/*
 * 10 篇（显示原理）实验：用软件模拟显示控制器的扫描
 *
 * 电脑上没有显示控制器，所以用一个循环扮演它：每循环一次就是像素时钟走一拍，
 * 两个计数器 x、y 记着"现在扫到哪一格"。
 *
 * 用法：./scan draw  xres yres pixclock left right upper lower hsync vsync
 *       ./scan count xres yres pixclock left right upper lower hsync vsync 秒数
 *
 * 参数顺序和 fbset 一样：先 geometry 里的 xres yres，再 timings 那一行的 7 个数，
 * 所以板子上 fbset 打出来的数可以原样抄进来。
 *
 * 一行里依次是：可见区 xres 拍 -> right_margin 拍空白 -> hsync_len 拍同步 -> left_margin 拍空白
 * 一帧里依次是：可见区 yres 行 -> lower_margin 行空白 -> vsync_len 行同步 -> upper_margin 行空白
 * （内核头文件的注释：left_margin 是 "time from sync to picture"，
 *   right_margin 是 "time from picture to sync"）
 *
 * 注错：-DBUG_NO_BLANK 控制器不走空白和同步，一行只有 xres 拍、一帧只有 yres 行。
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct timing {
	unsigned xres, yres, pixclock;		/* pixclock：一拍多少皮秒 */
	unsigned left, right, upper, lower, hsync, vsync;
	unsigned htotal, vtotal;
};

static void usage(const char *me)
{
	fprintf(stderr, "用法: %s draw|count xres yres pixclock left right upper lower hsync vsync [秒数]\n", me);
	exit(2);
}

/* 这一格是什么：'#' 可见区（读显存）、'H' 行同步、'V' 场同步、'.' 空白 */
static char cell(const struct timing *t, unsigned x, unsigned y)
{
	int in_v = y >= t->yres + t->lower && y < t->yres + t->lower + t->vsync;
	int in_h = x >= t->xres + t->right && x < t->xres + t->right + t->hsync;

	if (x < t->xres && y < t->yres)
		return '#';
	if (in_v)
		return 'V';
	if (in_h)
		return 'H';
	return '.';
}

static void draw(const struct timing *t)
{
	unsigned active = 0;

	for (unsigned y = 0; y < t->vtotal; y++) {
		for (unsigned x = 0; x < t->htotal; x++) {
			char c = cell(t, x, y);
			putchar(c);
			active += c == '#';
		}
		putchar('\n');
	}
	printf("一行 %u 拍，一帧 %u 行，一帧 %u 格；读显存的格子 %u 个（xres*yres=%u），空白和同步占 %.1f%%\n",
	       t->htotal, t->vtotal, t->htotal * t->vtotal, active, t->xres * t->yres,
	       100.0 * (t->htotal * t->vtotal - active) / (t->htotal * t->vtotal));
}

static void count(const struct timing *t, double secs)
{
	unsigned long long ticks = (unsigned long long)(secs * 1e12 / t->pixclock + 0.5);
	unsigned long long hpulse = 0, vpulse = 0, frames = 0, active = 0, active_done = 0;
	unsigned x = 0, y = 0;
	int h_prev = 0, v_prev = 0;

	for (unsigned long long k = 0; k < ticks; k++) {
		char c = cell(t, x, y);
		int in_h = c == 'H' || (x >= t->xres + t->right && x < t->xres + t->right + t->hsync);
		int in_v = c == 'V' || (y >= t->yres + t->lower && y < t->yres + t->lower + t->vsync);

		active += c == '#';
		hpulse += in_h && !h_prev;	/* 只数上升沿：进入同步的那一拍 */
		vpulse += in_v && !v_prev;
		h_prev = in_h;
		v_prev = in_v;

		if (++x == t->htotal) {		/* 一行扫完，回到行首，行号加一 */
			x = 0;
			if (++y == t->vtotal) {	/* 一帧扫完，回到左上角 */
				y = 0;
				frames++;
				active_done = active;	/* 只统计扫完的整帧 */
			}
		}
	}

	double done = frames + (double)(y * t->htotal + x) / ((double)t->htotal * t->vtotal);
	double hz = 1e12 / t->pixclock / t->htotal / t->vtotal;

	printf("像素时钟 %.3f MHz，模拟 %g 秒 = %llu 拍\n", 1e6 / t->pixclock, secs, ticks);
	printf("一行 %u 拍，一帧 %u 行\n", t->htotal, t->vtotal);
	printf("行同步脉冲 %llu 个 -> 行频 %.3f kHz\n", hpulse, hpulse / secs / 1e3);
	printf("场同步脉冲 %llu 个，扫完 %.3f 帧 -> 帧率 %.3f Hz\n", vpulse, done, done / secs);
	printf("扫完的 %llu 个整帧里读显存 %llu 次，每帧 %llu 次（xres*yres=%u）\n",
	       frames, active_done, frames ? active_done / frames : 0, t->xres * t->yres);
	printf("公式 1e12/pixclock/htotal/vtotal = %.3f Hz\n", hz);
}

int main(int argc, char **argv)
{
	struct timing t;

	if (argc < 11)
		usage(argv[0]);
	memset(&t, 0, sizeof t);
	t.xres = atoi(argv[2]);   t.yres = atoi(argv[3]);   t.pixclock = atoi(argv[4]);
	t.left = atoi(argv[5]);   t.right = atoi(argv[6]);
	t.upper = atoi(argv[7]);  t.lower = atoi(argv[8]);
	t.hsync = atoi(argv[9]);  t.vsync = atoi(argv[10]);
#ifdef BUG_NO_BLANK
	t.left = t.right = t.upper = t.lower = t.hsync = t.vsync = 0;
#endif
	t.htotal = t.xres + t.right + t.hsync + t.left;
	t.vtotal = t.yres + t.lower + t.vsync + t.upper;

	if (!strcmp(argv[1], "draw"))
		draw(&t);
	else if (!strcmp(argv[1], "count") && argc > 11 && t.pixclock)
		count(&t, atof(argv[11]));
	else
		usage(argv[0]);
	return 0;
}
