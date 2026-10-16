/* 888 -> 565 丢了多少：把 2^24 种颜色全部压一遍，数压完剩几种 */
#include <stdio.h>
#include <stdlib.h>

static unsigned to565(unsigned c)
{
	unsigned r = (c >> 16) & 0xff, g = (c >> 8) & 0xff, b = c & 0xff;
	return ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3);
}

/* 读回来时的两种放大：只左移补 0，或者把高位复制到低位 */
static unsigned back_shift(unsigned p)
{
	return (((p >> 11) & 0x1f) << 19) | (((p >> 5) & 0x3f) << 10) | ((p & 0x1f) << 3);
}

static unsigned back_repl(unsigned p)
{
	unsigned r = (p >> 11) & 0x1f, g = (p >> 5) & 0x3f, b = p & 0x1f;
	r = (r << 3) | (r >> 2);
	g = (g << 2) | (g >> 4);
	b = (b << 3) | (b >> 2);
	return (r << 16) | (g << 8) | b;
}

int main(void)
{
	static unsigned char seen[1 << 16];
	unsigned distinct = 0, survive = 0;

	for (unsigned c = 0; c < (1u << 24); c++) {
		unsigned p = to565(c);
		if (!seen[p]) {
			seen[p] = 1;
			distinct++;
		}
		if (back_shift(p) == c)
			survive++;
	}
	printf("888 共 %u 种, 压成 565 后剩 %u 种, 原样读回来的 %u 种\n", 1u << 24, distinct, survive);

	unsigned samples[] = { 0xFF0000, 0x00FF00, 0x0000FF, 0xFFFFFF, 0x808080, 0x123456 };
	printf("%-10s %-8s %-12s %-12s\n", "RGB888", "RGB565", "补0读回", "复制高位读回");
	for (unsigned i = 0; i < sizeof samples / sizeof samples[0]; i++) {
		unsigned p = to565(samples[i]);
		printf("0x%06X   0x%04X   0x%06X     0x%06X\n", samples[i], p, back_shift(p), back_repl(p));
	}
	return 0;
}
