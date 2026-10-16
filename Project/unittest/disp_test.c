/*
 * display 层单测。画一张固定图案, 由外部读回显存独立计数:
 *   全屏黑; (1,1) 起红 4x3; (6,1) 起绿 4x3; (11,1) 起蓝 4x3;
 *   右下角一个白点; 右边缘一个黄色 4x2 矩形只有 2x2 落在屏内;
 *   (xres,0) 越界写一个白点, 必须被拒绝。
 *
 * 这张图一次验四件事: 三个分量的位段、行宽、右边界裁剪、越界拒绝。
 * 程序自己不统计任何东西, 只把坐标和返回值打出来。
 */

#include <stdio.h>

#include "common.h"
#include "display/disp_manager.h"

int main(void)
{
	const struct disp_buf *b;
	struct disp_region all, r;
	int ret;

	if (display_init() != ERR_OK)
		return 1;
	b = disp_get_buf();
	printf("mode %dx%dx%d line_length %d\n", b->xres, b->yres, b->bpp, b->line_length);

	all = (struct disp_region){ 0, 0, b->xres, b->yres };
	disp_fill_rect(&all, 0x000000);

	r = (struct disp_region){ 1, 1, 4, 3 };  disp_fill_rect(&r, 0xff0000);
	r = (struct disp_region){ 6, 1, 4, 3 };  disp_fill_rect(&r, 0x00ff00);
	r = (struct disp_region){ 11, 1, 4, 3 }; disp_fill_rect(&r, 0x0000ff);
	disp_put_pixel(b->xres - 1, b->yres - 1, 0xffffff);
	r = (struct disp_region){ b->xres - 2, 5, 4, 2 }; disp_fill_rect(&r, 0xffff00);

	ret = disp_put_pixel(b->xres, 0, 0xffffff);
	printf("out of range put_pixel ret %d\n", ret);

	disp_flush(&all);
	display_exit();
	return 0;
}
