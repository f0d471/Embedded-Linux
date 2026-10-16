/*
 * 同样是把整屏涂成一种颜色，三种写法各要多久。
 *   A 逐点：每个像素调一次 put_pixel（官方描点函数的形状）
 *   B 逐行：先填好第 0 行，再把它 memcpy 到其余各行
 *   C 离屏：在 malloc 的缓冲里用逐点画完，最后一次 memcpy 到显存
 * 每种跑 5 轮取最短。结束时屏幕是蓝色，用回读计数验证真的写进去了。
 */
#include <fcntl.h>
#include <linux/fb.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

static unsigned xres, yres, lw, pw, size;

static double now_ms(void)
{
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return ts.tv_sec * 1e3 + ts.tv_nsec / 1e6;
}

static void put_pixel(unsigned char *base, unsigned x, unsigned y, unsigned color)
{
	*(unsigned int *)(base + y * lw + x * pw) = color;
}

static void fill_pixel(unsigned char *base, unsigned color)
{
	for (unsigned y = 0; y < yres; y++)
		for (unsigned x = 0; x < xres; x++)
			put_pixel(base, x, y, color);
}

static void fill_row(unsigned char *base, unsigned color)
{
	for (unsigned x = 0; x < xres; x++)
		put_pixel(base, x, 0, color);
	for (unsigned y = 1; y < yres; y++)
		memcpy(base + y * lw, base, lw);
}

int main(void)
{
	int fd = open("/dev/fb0", O_RDWR);
	struct fb_var_screeninfo var;
	struct fb_fix_screeninfo fix;
	if (fd < 0 || ioctl(fd, FBIOGET_VSCREENINFO, &var) || ioctl(fd, FBIOGET_FSCREENINFO, &fix)) {
		perror("fb0");
		return 1;
	}
	if (var.bits_per_pixel != 32) {
		printf("只写了 32bpp 的版本, 这块屏是 %ubpp\n", var.bits_per_pixel);
		return 1;
	}
	xres = var.xres, yres = var.yres, pw = 4, lw = fix.line_length, size = lw * yres;
	unsigned char *fb = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
	unsigned char *off = malloc(size);
	if (fb == MAP_FAILED || !off) {
		perror("mmap/malloc");
		return 1;
	}

	const char *name[3] = { "A 逐点写显存", "B 逐行 memcpy", "C 离屏画完一次拷贝" };
	double best[3] = { 1e9, 1e9, 1e9 };
	unsigned colors[2] = { 0x00FF0000, 0x000000FF };
	for (int round = 0; round < 5; round++) {
		for (int m = 0; m < 3; m++) {
			unsigned c = colors[round % 2 == 0 ? 1 : 0];
			if (round == 4)
				c = 0x000000FF;
			double t0 = now_ms();
			if (m == 0) {
				fill_pixel(fb, c);
			} else if (m == 1) {
				fill_row(fb, c);
			} else {
				fill_pixel(off, c);
				memcpy(fb, off, size);
			}
			double t = now_ms() - t0;
			if (t < best[m])
				best[m] = t;
		}
	}
	for (int m = 0; m < 3; m++)
		printf("%-24s %8.1f ms\n", name[m], best[m]);

	munmap(fb, size);
	free(off);
	close(fd);
	return 0;
}
