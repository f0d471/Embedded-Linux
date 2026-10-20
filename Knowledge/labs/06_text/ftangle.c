/* 06 章：FT_Set_Transform 旋转对单个字形外框的影响。
 * 用法: ftangle FONT PIXELS UTF8_TEXT ANGLE_DEG [ANGLE_DEG ...]
 * 每个角度输出一行的总外框与第一个字形的位图尺寸。
 */
#include <limits.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#include <ft2build.h>
#include FT_FREETYPE_H

#define MAX_GLYPHS 64

static int is_cont(unsigned char c)
{
	return (c & 0xc0) == 0x80;
}

static int decode_one(const unsigned char *s, size_t left, uint32_t *cp)
{
	if (!left) return -1;
	if (s[0] <= 0x7f) { *cp = s[0]; return 1; }
	if (s[0] >= 0xc2 && s[0] <= 0xdf && left >= 2 && is_cont(s[1])) {
		*cp = ((uint32_t)(s[0] & 0x1f) << 6) | (s[1] & 0x3f); return 2;
	}
	if (s[0] >= 0xe0 && s[0] <= 0xef && left >= 3 && is_cont(s[1]) && is_cont(s[2]) &&
	    !(s[0] == 0xe0 && s[1] < 0xa0) && !(s[0] == 0xed && s[1] >= 0xa0)) {
		*cp = ((uint32_t)(s[0] & 0x0f) << 12) |
		      ((uint32_t)(s[1] & 0x3f) << 6) | (s[2] & 0x3f); return 3;
	}
	if (s[0] >= 0xf0 && s[0] <= 0xf4 && left >= 4 && is_cont(s[1]) &&
	    is_cont(s[2]) && is_cont(s[3]) && !(s[0] == 0xf0 && s[1] < 0x90) &&
	    !(s[0] == 0xf4 && s[1] >= 0x90)) {
		*cp = ((uint32_t)(s[0] & 7) << 18) | ((uint32_t)(s[1] & 0x3f) << 12) |
		      ((uint32_t)(s[2] & 0x3f) << 6) | (s[3] & 0x3f); return 4;
	}
	return -1;
}

static long floor64(long value)
{
	if (value >= 0) return value >> 6;
	return -(((-value) + 63) >> 6);
}

int main(int argc, char **argv)
{
	FT_Library library;
	FT_Face face;
	uint32_t cp[MAX_GLYPHS];
	size_t count = 0;
	const unsigned char *text;
	size_t length, offset = 0;
	char *end;
	long size;

	if (argc < 5) {
		fprintf(stderr, "usage: %s FONT PIXELS UTF8_TEXT ANGLE_DEG...\n", argv[0]);
		return 2;
	}
	size = strtol(argv[2], &end, 10);
	if (*argv[2] == '\0' || *end != '\0' || size < 1 || size > 1000) {
		fprintf(stderr, "bad pixel size\n");
		return 2;
	}
	text = (const unsigned char *)argv[3];
	length = strlen(argv[3]);
	while (offset < length) {
		int used;
		if (count == MAX_GLYPHS || (used = decode_one(text + offset, length - offset, &cp[count])) < 0) {
			fprintf(stderr, "bad UTF-8 text\n");
			return 2;
		}
		offset += (size_t)used;
		count++;
	}
	if (FT_Init_FreeType(&library) ||
	    FT_New_Face(library, argv[1], 0, &face) ||
	    FT_Select_Charmap(face, FT_ENCODING_UNICODE) ||
	    FT_Set_Pixel_Sizes(face, 0, (FT_UInt)size)) {
		fprintf(stderr, "FreeType setup failed\n");
		return 1;
	}

	for (int a = 4; a < argc; a++) {
		long angle = strtol(argv[a], &end, 10);
		double rad;
		FT_Matrix matrix;
		long pen_x = 0, pen_y = 0;
		int xmin = INT_MAX, ymin = INT_MAX, xmax = INT_MIN, ymax = INT_MIN;
		unsigned first_w = 0, first_h = 0;
		long first_adx = 0, first_ady = 0;

		if (*argv[a] == '\0' || *end != '\0' || angle < -360 || angle > 360) {
			fprintf(stderr, "bad angle: %s\n", argv[a]);
			return 2;
		}
		rad = (double)angle * 3.14159265358979323846 / 180.0;
		matrix.xx = (FT_Fixed)(cos(rad) * 65536.0);
		matrix.xy = (FT_Fixed)(-sin(rad) * 65536.0);
		matrix.yx = (FT_Fixed)(sin(rad) * 65536.0);
		matrix.yy = (FT_Fixed)(cos(rad) * 65536.0);
		FT_Set_Transform(face, &matrix, NULL);

		for (size_t i = 0; i < count; i++) {
			FT_GlyphSlot slot;
			int x0, y0, x1, y1;

			if (FT_Load_Char(face, cp[i], FT_LOAD_RENDER | FT_LOAD_TARGET_NORMAL)) {
				fprintf(stderr, "cannot render U+%04X\n", cp[i]);
				return 1;
			}
			slot = face->glyph;
			x0 = (int)floor64(pen_x) + slot->bitmap_left;
			y1 = (int)floor64(pen_y) + slot->bitmap_top;
			y0 = y1 - (int)slot->bitmap.rows;
			x1 = x0 + (int)slot->bitmap.width;
			if (slot->bitmap.width && slot->bitmap.rows) {
				if (x0 < xmin) xmin = x0;
				if (y0 < ymin) ymin = y0;
				if (x1 > xmax) xmax = x1;
				if (y1 > ymax) ymax = y1;
			}
			if (i == 0) {
				first_w = slot->bitmap.width;
				first_h = slot->bitmap.rows;
				first_adx = (long)slot->advance.x;
				first_ady = (long)slot->advance.y;
			}
			pen_x += slot->advance.x;
			pen_y += slot->advance.y;
		}
		if (xmin == INT_MAX)
			xmin = ymin = xmax = ymax = 0;
		printf("angle=%ld first_bitmap=%ux%u first_advance26_6=%ld,%ld bbox=%d,%d..%d,%d width=%d height=%d\n",
		       angle, first_w, first_h, first_adx, first_ady,
		       xmin, ymin, xmax, ymax, xmax - xmin, ymax - ymin);
	}
	FT_Done_Face(face);
	FT_Done_FreeType(library);
	return 0;
}
