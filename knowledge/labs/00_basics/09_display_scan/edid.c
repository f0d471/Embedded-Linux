/*
 * 10 篇（显示原理）实验：把显示器的 EDID 拆开，看它自报了哪些模式
 *
 * 用法：./edid edid.bin
 *
 * EDID 是显示器里一小块只读数据，前 128 字节是基本块，后面每 128 字节一个扩展块。
 * 本程序只解这一篇用得到的几段，解的先后顺序照 Linux 4.9 的 fbmon.c：
 *   基本块  字节 54-125 四个 18 字节描述符（详细时序在这里）
 *           字节 35-36  老式固定模式表（每一位代表一个模式）
 *           字节 38-53  标准模式（每 2 字节一个）
 *   扩展块  标签 0x02（CEA-861）：视频数据块里的 VIC 编号，以及后面的详细时序
 * 另外核对每块的校验和、打出厂商和产品号。序列号（字节 12-15 和类型 0xFF 的描述符）不打印。
 *
 * 最后的"模式清单"按板子上 /sys/class/graphics/fb0/modes 的写法和顺序打印：
 *   D: 详细时序  V: 老式固定模式表  U: 标准模式  S: CEA 编号
 * 内核每解出一个模式就插到链表最前面，所以清单是倒着的：最后解出来的排第一。
 */
#include <stdio.h>
#include <string.h>

static unsigned char e[512];
static int nmodes;
static char modes[64][32];

static void add_mode(char kind, int x, int y, int hz)
{
	if (nmodes < 64)
		snprintf(modes[nmodes++], sizeof modes[0], "%c:%dx%dp-%d", kind, x, y, hz);
}

/* 18 字节的详细时序描述符 */
static void dtd(const unsigned char *d)
{
	unsigned pclk_khz = (d[0] | d[1] << 8) * 10;
	unsigned hact = d[2] | (d[4] >> 4) << 8;
	unsigned hblank = d[3] | (d[4] & 0xf) << 8;
	unsigned vact = d[5] | (d[7] >> 4) << 8;
	unsigned vblank = d[6] | (d[7] & 0xf) << 8;
	unsigned hfp = d[8] | ((d[11] >> 6) & 3) << 8;		/* 画面之后、同步之前 */
	unsigned hsync = d[9] | ((d[11] >> 4) & 3) << 8;
	unsigned vfp = (d[10] >> 4) | ((d[11] >> 2) & 3) << 4;
	unsigned vsync = (d[10] & 0xf) | (d[11] & 3) << 4;
	unsigned htotal = hact + hblank, vtotal = vact + vblank;
	double hz = pclk_khz * 1000.0 / htotal / vtotal;

	printf("  详细时序 %ux%u%s  像素时钟 %.2f MHz  一行 %u 拍 一帧 %u 行  帧率 %.3f Hz\n",
	       hact, vact, d[17] & 0x80 ? "i" : "p", pclk_khz / 1000.0, htotal, vtotal, hz);
	printf("    按 fbset 的写法: timings %.0f %u %u %u %u %u %u\n",
	       1e9 / pclk_khz, hblank - hfp - hsync, hfp, vblank - vfp - vsync, vfp, hsync, vsync);
	add_mode('D', hact, vact, (int)hz);	/* 和内核一样直接截断小数，不四舍五入 */
}

static void descriptor(const unsigned char *d)
{
	char text[14];

	if (d[0] || d[1]) {
		dtd(d);
		return;
	}
	switch (d[3]) {
	case 0xfc:
		memcpy(text, d + 5, 13);
		text[13] = '\0';
		text[strcspn(text, "\n")] = '\0';
		printf("  显示器名字: %s\n", text);
		break;
	case 0xfd:
		printf("  范围限制: 场频 %u-%u Hz, 行频 %u-%u kHz, 最高像素时钟 %u MHz\n",
		       d[5], d[6], d[7], d[8], d[9] * 10);
		break;
	case 0xff:
		printf("  序列号: （不打印）\n");
		break;
	default:
		printf("  描述符类型 0x%02x（本程序不解）\n", d[3]);
	}
}

/* CEA-861 的 VIC 编号，只列这台显示器用到的 */
static void vic(int v, int native)
{
	static const struct { int vic, x, y, hz; } tab[] = {
		{1, 640, 480, 60}, {2, 720, 480, 60}, {3, 720, 480, 60}, {4, 1280, 720, 60},
		{16, 1920, 1080, 60}, {17, 720, 576, 50}, {18, 720, 576, 50}, {19, 1280, 720, 50},
		{31, 1920, 1080, 50}, {32, 1920, 1080, 24}, {33, 1920, 1080, 25}, {34, 1920, 1080, 30},
		{60, 1280, 720, 24}, {61, 1280, 720, 25}, {62, 1280, 720, 30},
		{63, 1920, 1080, 120}, {64, 1920, 1080, 100},
	};

	for (size_t i = 0; i < sizeof tab / sizeof tab[0]; i++) {
		if (tab[i].vic == v) {
			printf("  VIC %-3d %dx%dp@%d%s\n", v, tab[i].x, tab[i].y, tab[i].hz,
			       native ? "  (标了 native)" : "");
			add_mode('S', tab[i].x, tab[i].y, tab[i].hz);
			return;
		}
	}
	printf("  VIC %-3d（本程序的表里没有）\n", v);
}

static void cea(const unsigned char *b)
{
	unsigned dtd_off = b[2];

	printf("扩展块: 标签 0x%02x（CEA-861） 版本 %u，详细时序从块内偏移 %u 开始\n", b[0], b[1], dtd_off);
	for (unsigned i = 4; i < dtd_off;) {
		unsigned tag = b[i] >> 5, len = b[i] & 0x1f;

		if (tag == 2) {		/* 视频数据块：一串 VIC */
			printf(" 视频数据块，%u 个 VIC:\n", len);
			for (unsigned k = 1; k <= len; k++)
				vic(b[i + k] & 0x7f, b[i + k] & 0x80);
		}
		i += 1 + len;
	}
	printf(" 详细时序:\n");
	for (unsigned o = dtd_off; o + 18 <= 127 && (b[o] || b[o + 1]); o += 18)
		dtd(b + o);
}

int main(int argc, char **argv)
{
	static const unsigned char head[8] = {0x00, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x00};
	static const struct { int byte, bit, x, y, hz; } est[] = {
		{35, 7, 720, 400, 70}, {35, 6, 720, 400, 88}, {35, 5, 640, 480, 60}, {35, 4, 640, 480, 67},
		{35, 3, 640, 480, 72}, {35, 2, 640, 480, 75}, {35, 1, 800, 600, 56}, {35, 0, 800, 600, 60},
		{36, 7, 800, 600, 72}, {36, 6, 800, 600, 75}, {36, 5, 832, 624, 75}, {36, 3, 1024, 768, 60},
		{36, 2, 1024, 768, 70}, {36, 1, 1024, 768, 75}, {36, 0, 1280, 1024, 75},
	};
	FILE *f;
	size_t n;
	unsigned sum;

	if (argc < 2 || !(f = fopen(argv[1], "rb"))) {
		fprintf(stderr, "用法: %s edid.bin\n", argv[0]);
		return 2;
	}
	n = fread(e, 1, sizeof e, f);
	fclose(f);
	if (n < 128 || memcmp(e, head, 8)) {
		printf("不是 EDID：长度 %zu，或者前 8 个字节不是 00 ff ff ff ff ff ff 00\n", n);
		return 1;
	}

	for (size_t blk = 0; blk * 128 < n; blk++) {
		sum = 0;
		for (int i = 0; i < 128; i++)
			sum += e[blk * 128 + i];
		printf("块 %zu 校验和: 128 个字节加起来模 256 = %u %s\n", blk, sum & 0xff,
		       sum & 0xff ? "（坏了）" : "（正确）");
	}
	printf("厂商 %c%c%c  产品号 0x%04x  EDID 版本 %u.%u  扩展块 %u 个\n",
	       '@' + (e[8] >> 2 & 0x1f), '@' + ((e[8] & 3) << 3 | e[9] >> 5), '@' + (e[9] & 0x1f),
	       e[10] | e[11] << 8, e[18], e[19], e[126]);

	printf("四个描述符（字节 54-125）:\n");
	for (int i = 54; i < 126; i += 18)
		descriptor(e + i);

	printf("老式固定模式表（字节 35-36 的位）:\n");
	for (size_t i = 0; i < sizeof est / sizeof est[0]; i++) {
		if (e[est[i].byte] >> est[i].bit & 1) {
			printf("  %dx%d@%d\n", est[i].x, est[i].y, est[i].hz);
			add_mode('V', est[i].x, est[i].y, est[i].hz);
		}
	}

	printf("标准模式（字节 38-53）:\n");
	for (int i = 38; i < 54; i += 2) {
		static const int num[] = {10, 4, 5, 16}, den[] = {16, 3, 4, 9};
		int x, a, y, hz;

		if (e[i] == 0x01 && e[i + 1] == 0x01)
			continue;			/* 01 01 表示这一格没用 */
		x = (e[i] + 31) * 8;
		a = e[i + 1] >> 6;
		y = x * den[a] / num[a];
		hz = (e[i + 1] & 0x3f) + 60;
		printf("  %dx%d@%d\n", x, y, hz);
		add_mode('U', x, y, hz);
	}

	for (size_t blk = 1; blk * 128 < n; blk++)
		if (e[blk * 128] == 0x02)
			cea(e + blk * 128);

	printf("模式清单（%d 条，最后解出来的排第一）:\n", nmodes);
	for (int i = nmodes - 1; i >= 0; i--)
		printf("  %s\n", modes[i]);
	return 0;
}
