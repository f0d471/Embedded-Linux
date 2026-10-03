/*
 * font 层单测：先用可控的 4x2 灰度 provider 验 alpha、负 pitch 和四边裁剪，
 * 再用真实 FreeType 验 UTF-8、missing、bbox 与 26.6 advance。
 */

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "common.h"
#include "display/disp_manager.h"
#include "font/font_internal.h"
#include "font/font_manager.h"

/*
 * pitch=-6：逻辑首行放在内存后半，manager 若把 width 当 pitch 或忽略负号，
 * 读到的覆盖率顺序都会改变。每行最后两字节是 padding。
 */
static const unsigned char g_probe_bitmap[12] = {
	255, 128, 64, 0, 0xaa, 0xaa,
	0, 64, 128, 255, 0xaa, 0xaa,
};

static int probe_open(const char *path, int face_index)
{
	(void)path;
	return face_index == 0 ? ERR_OK : ERR_PARAM;
}

static void probe_close(void)
{
}

static int probe_size(int px)
{
	return px > 0 ? ERR_OK : ERR_PARAM;
}

static int probe_has(uint32_t cp)
{
	(void)cp;
	return 1;
}

static int probe_render(uint32_t cp, struct font_bitmap *out)
{
	(void)cp;
	*out = (struct font_bitmap) {
		.width = 4, .rows = 2, .pitch = -6,
		.pixel_mode = FONT_PIXEL_GRAY, .num_grays = 256,
		.left = 0, .top = 1,
		.advance_x_26_6 = 5 * 64,
		.buffer = g_probe_bitmap,
	};
	return ERR_OK;
}

static struct font_provider g_probe = {
	.name = "probe",
	.open = probe_open,
	.close = probe_close,
	.set_pixel_size = probe_size,
	.has_codepoint = probe_has,
	.render = probe_render,
};

static int draw_probe(int x, int baseline, struct font_text_metrics *m)
{
	size_t bad;
	return font_draw_utf8("X", 1, x, baseline, 0xe0a020, m, &bad);
}

int main(void)
{
	const struct disp_buf *b;
	struct disp_region all;
	struct font_text_metrics m, left, right, top, bottom;
	const char invalid[] = { (char)0xc0, (char)0xaf, 'A' };
	const char *font_file = getenv("FONT_TEST_FILE");
	size_t bad;
	int ret;

	if (display_init() != ERR_OK || font_init() != ERR_OK)
		return 1;
	b = disp_get_buf();
	all = (struct disp_region){ 0, 0, b->xres, b->yres };

	ret = font_measure_utf8(invalid, sizeof(invalid), &m, &bad);
	printf("invalid ret=%d bad=%zu\n", ret, bad);
	ret = font_measure_utf8("A\xe4\xb8\xadg", 5, &m, &bad);
	if (ret != ERR_OK)
		return 2;
	printf("builtin cp=%zu missing=%zu advance=%d bbox=%d,%d,%d,%d\n",
	       m.codepoints, m.missing, m.advance_x_26_6,
	       m.ink_x, m.ink_y, m.ink_w, m.ink_h);

	font_register(&g_probe);
	if (font_select("probe", NULL, 0) != ERR_OK)
		return 3;
	disp_fill_rect(&all, 0x204060);
	if (draw_probe(1, 1, &m) != ERR_OK)
		return 4;
	printf("probe covered=%zu drawn=%zu clipped=%zu advance=%d bbox=%d,%d,%d,%d\n",
	       m.covered_pixels, m.drawn_pixels, m.clipped_pixels, m.advance_x_26_6,
	       m.ink_x, m.ink_y, m.ink_w, m.ink_h);

	if (draw_probe(-3, 1, &left) != ERR_OK ||
	    draw_probe(b->xres - 1, 1, &right) != ERR_OK ||
	    draw_probe(8, 0, &top) != ERR_OK ||
	    draw_probe(14, b->yres, &bottom) != ERR_OK)
		return 5;
	printf("clip left=%zu/%zu right=%zu/%zu top=%zu/%zu bottom=%zu/%zu\n",
	       left.drawn_pixels, left.clipped_pixels,
	       right.drawn_pixels, right.clipped_pixels,
	       top.drawn_pixels, top.clipped_pixels,
	       bottom.drawn_pixels, bottom.clipped_pixels);

	if (font_file != NULL) {
		if (font_select("freetype", font_file, 0) != ERR_OK ||
		    font_set_pixel_size(48) != ERR_OK)
			return 6;
		disp_fill_rect(&all, 0x000000);
		ret = font_draw_utf8("Ag\xe4\xb8\xad", 5, 4, 52, 0xffd040, &m, &bad);
		if (ret != ERR_OK)
			return 7;
		printf("freetype cp=%zu missing=%zu advance=%d bbox=%d,%d,%d,%d"
		       " covered=%zu drawn=%zu clipped=%zu\n",
		       m.codepoints, m.missing, m.advance_x_26_6,
		       m.ink_x, m.ink_y, m.ink_w, m.ink_h,
		       m.covered_pixels, m.drawn_pixels, m.clipped_pixels);
	}

	font_exit();
	display_exit();
	return 0;
}
