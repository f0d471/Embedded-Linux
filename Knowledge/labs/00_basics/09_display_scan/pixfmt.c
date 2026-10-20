/*
 * 11 篇（显示原理）实验：一个像素在显存里、在并行线上分别长什么样
 *
 * 用法：./pixfmt 32 0xFF0000 [xres]
 *       ./pixfmt 16 0xFF0000 [xres]
 *
 * 位段用本板两种模式的实测值（板上 fbset 的 rgba 行）：
 *   32bpp  red=16/8 green=8/8 blue=0/8   （XRGB8888，最高 8 位不读）
 *   16bpp  red=11/5 green=5/6 blue=0/5   （RGB565）
 * 字节序：本机与板子都是小端，多字节的值低位字节放低地址。
 *
 * 控制器一次从内存读 32 位。一个 32 位字里装几个像素，由驱动按 bpp 设置
 * （内核 mxsfb 驱动：32bpp 时 32 位字长、打包掩码 0x7，一个字的低 3 字节
 * 有效，一个 32 位字装 1 个像素；16bpp 时 16 位字长、打包掩码 0xF，
 * 4 个字节全有效，一个 32 位字装 2 个像素）。
 *
 * 注错：-DBUG_BE 按大端排字节（本板是小端，这个假设是错的，颜色会整个错位）。
 */
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv)
{
	unsigned rgb, r8, g8, b8, v, xres = 1024;
	int bpp, n, off[3], len[3];
	unsigned char b[4];

	if (argc < 3) {
		fprintf(stderr, "用法: %s 16|32 0xRRGGBB [xres]\n", argv[0]);
		return 2;
	}
	bpp = atoi(argv[1]);
	rgb = strtoul(argv[2], NULL, 0);
	if (argc > 3)
		xres = atoi(argv[3]);

	if (bpp == 32) {
		off[0] = 16; len[0] = 8;  off[1] = 8; len[1] = 8;  off[2] = 0; len[2] = 8;
	} else if (bpp == 16) {
		off[0] = 11; len[0] = 5;  off[1] = 5; len[1] = 6;  off[2] = 0; len[2] = 5;
	} else {
		fprintf(stderr, "本实验只讲本板用过的 16 和 32\n");
		return 2;
	}

	r8 = rgb >> 16 & 0xff;
	g8 = rgb >> 8 & 0xff;
	b8 = rgb & 0xff;
	/* 每个分量两步：右移砍到位数，左移挪到位段位置 */
	v = (r8 >> (8 - len[0]) << off[0]) |
	    (g8 >> (8 - len[1]) << off[1]) |
	    (b8 >> (8 - len[2]) << off[2]);

	printf("像素 0x%06X，%dbpp 位段 red=%d/%d green=%d/%d blue=%d/%d（偏移/长度）\n",
	       rgb, bpp, off[0], len[0], off[1], len[1], off[2], len[2]);
	printf("拼成 %d 位的值 0x%0*X\n", bpp, bpp / 4, v);

	n = bpp / 8;
	for (int i = 0; i < n; i++)
#ifdef BUG_BE
		b[i] = v >> (8 * (n - 1 - i)) & 0xff;	/* 大端：高位字节放低地址 */
#else
		b[i] = v >> (8 * i) & 0xff;		/* 小端：低位字节放低地址 */
#endif
	printf("显存字节（地址从低到高）:");
	for (int i = 0; i < n; i++)
		printf(" %02X", b[i]);
	printf("\n");

	if (bpp == 32)
		printf("控制器一个 32 位字装 1 个像素（打包掩码 0x7，一个字的低 3 字节有效）\n");
	else
		printf("控制器一个 32 位字装 2 个像素（打包掩码 0xF，一个字的 4 个字节全有效）\n");
	printf("一行 %u 像素：显存 %u 字节 = %u 个 32 位字\n", xres, xres * bpp / 8, xres * bpp / 32);
	return 0;
}
