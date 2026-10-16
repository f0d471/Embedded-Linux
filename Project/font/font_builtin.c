#include <stdint.h>
#include <string.h>

#include "common.h"
#include "font/font_internal.h"

struct builtin_glyph {
	char ch;
	unsigned char rows[7];
};

/* 5x7 点阵是无外部字体时的英文/数字兜底；小写字母复用大写字形。 */
static const struct builtin_glyph g_glyphs[] = {
	{ ' ', {0,0,0,0,0,0,0} }, { '!', {4,4,4,4,4,0,4} },
	{ '-', {0,0,0,31,0,0,0} }, { '.', {0,0,0,0,0,6,6} },
	{ '/', {1,2,4,8,16,0,0} }, { ':', {0,6,6,0,6,6,0} },
	{ '?', {14,17,1,2,4,0,4} },
	{ '0', {14,17,19,21,25,17,14} }, { '1', {4,12,4,4,4,4,14} },
	{ '2', {14,17,1,2,4,8,31} }, { '3', {30,1,1,14,1,1,30} },
	{ '4', {2,6,10,18,31,2,2} }, { '5', {31,16,16,30,1,1,30} },
	{ '6', {14,16,16,30,17,17,14} }, { '7', {31,1,2,4,8,8,8} },
	{ '8', {14,17,17,14,17,17,14} }, { '9', {14,17,17,15,1,1,14} },
	{ 'A', {14,17,17,31,17,17,17} }, { 'B', {30,17,17,30,17,17,30} },
	{ 'C', {14,17,16,16,16,17,14} }, { 'D', {30,17,17,17,17,17,30} },
	{ 'E', {31,16,16,30,16,16,31} }, { 'F', {31,16,16,30,16,16,16} },
	{ 'G', {14,17,16,23,17,17,15} }, { 'H', {17,17,17,31,17,17,17} },
	{ 'I', {14,4,4,4,4,4,14} }, { 'J', {7,2,2,2,18,18,12} },
	{ 'K', {17,18,20,24,20,18,17} }, { 'L', {16,16,16,16,16,16,31} },
	{ 'M', {17,27,21,21,17,17,17} }, { 'N', {17,25,21,19,17,17,17} },
	{ 'O', {14,17,17,17,17,17,14} }, { 'P', {30,17,17,30,16,16,16} },
	{ 'Q', {14,17,17,17,21,18,13} }, { 'R', {30,17,17,30,20,18,17} },
	{ 'S', {15,16,16,14,1,1,30} }, { 'T', {31,4,4,4,4,4,4} },
	{ 'U', {17,17,17,17,17,17,14} }, { 'V', {17,17,17,17,17,10,4} },
	{ 'W', {17,17,17,21,21,21,10} }, { 'X', {17,17,10,4,10,17,17} },
	{ 'Y', {17,17,10,4,4,4,4} }, { 'Z', {31,1,2,4,8,16,31} },
};

static unsigned char g_bitmap[6 * 14];

static const struct builtin_glyph *find_glyph(uint32_t cp)
{
	size_t i;
	char ch;

	if (cp >= 'a' && cp <= 'z')
		cp -= 'a' - 'A';
	if (cp > 0x7f)
		return NULL;
	ch = (char)cp;
	for (i = 0; i < ARRAY_SIZE(g_glyphs); i++)
		if (g_glyphs[i].ch == ch)
			return &g_glyphs[i];
	return NULL;
}

static int builtin_open(const char *path, int face_index)
{
	(void)path;
	return face_index == 0 ? ERR_OK : ERR_PARAM;
}

static void builtin_close(void)
{
}

static int builtin_set_pixel_size(int px)
{
	return px > 0 ? ERR_OK : ERR_PARAM;
}

static int builtin_has_codepoint(uint32_t cp)
{
	return find_glyph(cp) != NULL;
}

static int builtin_render(uint32_t cp, struct font_bitmap *out)
{
	const struct builtin_glyph *g = find_glyph(cp);
	int x, y;

	if (g == NULL || out == NULL)
		return ERR_NOTFOUND;
	memset(g_bitmap, 0, sizeof(g_bitmap));
	for (y = 0; y < 7; y++)
		for (x = 0; x < 5; x++)
			if (g->rows[y] & (1u << (4 - x))) {
				g_bitmap[(y * 2) * 6 + x] = 255;
				g_bitmap[(y * 2 + 1) * 6 + x] = 255;
			}

	*out = (struct font_bitmap) {
		.width = 6, .rows = 14, .pitch = 6,
		.pixel_mode = FONT_PIXEL_GRAY, .num_grays = 256,
		.left = 0, .top = 14,
		.advance_x_26_6 = 6 * 64, .advance_y_26_6 = 0,
		.buffer = g_bitmap,
	};
	return ERR_OK;
}

static struct font_provider g_builtin = {
	.name = "builtin",
	.open = builtin_open,
	.close = builtin_close,
	.set_pixel_size = builtin_set_pixel_size,
	.has_codepoint = builtin_has_codepoint,
	.render = builtin_render,
};

void font_builtin_register(void)
{
	font_register(&g_builtin);
}
