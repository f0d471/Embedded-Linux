#include <errno.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <ft2build.h>
#include FT_FREETYPE_H

#define MAX_GLYPHS 256

struct line {
	uint32_t cp[MAX_GLYPHS];
	size_t count;
	long advance_26_6;
	int xmin, ymin, xmax, ymax;
	unsigned missing, nonzero, middle, full;
};

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

static int parse_text(const char *text, struct line *line)
{
	const unsigned char *s = (const unsigned char *)text;
	size_t length = strlen(text), offset = 0;

	while (offset < length) {
		uint32_t cp;
		int used;
		if (line->count == MAX_GLYPHS)
			return -1;
		used = decode_one(s + offset, length - offset, &cp);
		if (used < 0)
			return -1;
		line->cp[line->count++] = cp;
		offset += (size_t)used;
	}
	return 0;
}

static const unsigned char *bitmap_row(const FT_Bitmap *bitmap, unsigned y)
{
	if (bitmap->pitch >= 0)
		return bitmap->buffer + y * (unsigned)bitmap->pitch;
	return bitmap->buffer + (bitmap->rows - 1 - y) * (unsigned)(-bitmap->pitch);
}

static unsigned coverage(const FT_Bitmap *bitmap, unsigned x, unsigned y)
{
	const unsigned char *row = bitmap_row(bitmap, y);
	if (bitmap->pixel_mode == FT_PIXEL_MODE_GRAY)
		return row[x];
	if (bitmap->pixel_mode == FT_PIXEL_MODE_MONO)
		return (row[x / 8] & (0x80u >> (x % 8))) ? 255 : 0;
	return 0;
}

static long floor64(long value)
{
	if (value >= 0) return value >> 6;
	return -(((-value) + 63) >> 6);
}

static int inspect_line(FT_Face face, struct line *line)
{
	long pen = 0;
	line->xmin = line->ymin = INT_MAX;
	line->xmax = line->ymax = INT_MIN;

	for (size_t i = 0; i < line->count; i++) {
		FT_UInt glyph_index = FT_Get_Char_Index(face, line->cp[i]);
		FT_GlyphSlot slot;
		int x0, y0, x1, y1;
		unsigned nz = 0, mid = 0, full = 0;

		if (!glyph_index) line->missing++;
		if (FT_Load_Char(face, line->cp[i], FT_LOAD_RENDER | FT_LOAD_TARGET_NORMAL))
			return -1;
		slot = face->glyph;
		x0 = (int)floor64(pen) + slot->bitmap_left;
		y0 = slot->bitmap_top - (int)slot->bitmap.rows;
		x1 = x0 + (int)slot->bitmap.width;
		y1 = slot->bitmap_top;
		if (slot->bitmap.width && slot->bitmap.rows) {
			if (x0 < line->xmin) line->xmin = x0;
			if (y0 < line->ymin) line->ymin = y0;
			if (x1 > line->xmax) line->xmax = x1;
			if (y1 > line->ymax) line->ymax = y1;
		}
		for (unsigned y = 0; y < slot->bitmap.rows; y++)
			for (unsigned x = 0; x < slot->bitmap.width; x++) {
				unsigned a = coverage(&slot->bitmap, x, y);
				if (a) nz++;
				if (a && a < 255) mid++;
				if (a == 255) full++;
			}
		line->nonzero += nz;
		line->middle += mid;
		line->full += full;
		printf("glyph cp=U+%04X gid=%u bitmap=%ux%u pitch=%d mode=%u left=%d top=%d bottom=%d advance26_6=%ld advance_px=%.3f nonzero=%u mid=%u full=%u\n",
		       line->cp[i], glyph_index, slot->bitmap.width, slot->bitmap.rows,
		       slot->bitmap.pitch, slot->bitmap.pixel_mode, slot->bitmap_left,
		       slot->bitmap_top, y0, (long)slot->advance.x,
		       slot->advance.x / 64.0, nz, mid, full);
		pen += slot->advance.x;
	}
	line->advance_26_6 = pen;
	if (line->xmin == INT_MAX)
		line->xmin = line->ymin = line->xmax = line->ymax = 0;
	return 0;
}

static int write_pgm(const char *path, FT_Face face, const struct line *line)
{
	const int margin = 2;
	int width = line->xmax - line->xmin + 2 * margin;
	int height = line->ymax - line->ymin + 2 * margin;
	unsigned char *image;
	long pen = 0;
	FILE *fp;

	if (width <= 0 || height <= 0)
		return -1;
	image = calloc((size_t)width * (size_t)height, 1);
	if (!image)
		return -1;
	for (size_t i = 0; i < line->count; i++) {
		FT_GlyphSlot slot;
		int left, top;
		if (FT_Load_Char(face, line->cp[i], FT_LOAD_RENDER | FT_LOAD_TARGET_NORMAL)) {
			free(image);
			return -1;
		}
		slot = face->glyph;
		left = margin + (int)floor64(pen) + slot->bitmap_left - line->xmin;
		top = margin + line->ymax - slot->bitmap_top;
		for (unsigned y = 0; y < slot->bitmap.rows; y++)
			for (unsigned x = 0; x < slot->bitmap.width; x++) {
				int dx = left + (int)x, dy = top + (int)y;
				unsigned a = coverage(&slot->bitmap, x, y);
				if (dx >= 0 && dx < width && dy >= 0 && dy < height &&
				    a > image[dy * width + dx])
					image[dy * width + dx] = (unsigned char)a;
			}
		pen += slot->advance.x;
	}
	fp = fopen(path, "wb");
	if (!fp) {
		free(image);
		return -1;
	}
	fprintf(fp, "P5\n%d %d\n255\n", width, height);
	fwrite(image, 1, (size_t)width * (size_t)height, fp);
	fclose(fp);
	free(image);
	printf("pgm=%s size=%dx%d baseline_row=%d\n", path, width, height,
	       margin + line->ymax);
	return 0;
}

int main(int argc, char **argv)
{
	FT_Library library;
	FT_Face face;
	FT_Int major, minor, patch;
	struct line line = { 0 };
	char *end;
	long size;

	if (argc != 4 && argc != 5) {
		fprintf(stderr, "usage: %s FONT PIXELS UTF8_TEXT [OUT.pgm]\n", argv[0]);
		return 2;
	}
	errno = 0;
	size = strtol(argv[2], &end, 10);
	if (errno || *argv[2] == '\0' || *end != '\0' || size < 1 || size > 1000 ||
	    parse_text(argv[3], &line) < 0) {
		fprintf(stderr, "bad size or UTF-8 text\n");
		return 2;
	}
	if (FT_Init_FreeType(&library)) {
		fprintf(stderr, "FT_Init_FreeType failed\n");
		return 1;
	}
	FT_Library_Version(library, &major, &minor, &patch);
	if (FT_New_Face(library, argv[1], 0, &face)) {
		fprintf(stderr, "FT_New_Face failed: %s\n", argv[1]);
		FT_Done_FreeType(library);
		return 1;
	}
	if (FT_Select_Charmap(face, FT_ENCODING_UNICODE) || FT_Set_Pixel_Sizes(face, 0, (FT_UInt)size)) {
		fprintf(stderr, "Unicode charmap or pixel size unavailable\n");
		FT_Done_Face(face);
		FT_Done_FreeType(library);
		return 1;
	}
	printf("freetype=%d.%d.%d family=%s style=%s glyphs=%zu pixel_size=%ld\n",
	       major, minor, patch, face->family_name ? face->family_name : "?",
	       face->style_name ? face->style_name : "?", line.count, size);
	if (inspect_line(face, &line) < 0) {
		fprintf(stderr, "glyph render failed\n");
		FT_Done_Face(face);
		FT_Done_FreeType(library);
		return 1;
	}
	printf("line bbox=%d,%d..%d,%d width=%d height=%d advance26_6=%ld advance_px=%.3f missing=%u nonzero=%u mid=%u full=%u\n",
	       line.xmin, line.ymin, line.xmax, line.ymax,
	       line.xmax - line.xmin, line.ymax - line.ymin,
	       line.advance_26_6, line.advance_26_6 / 64.0,
	       line.missing, line.nonzero, line.middle, line.full);
	if (argc == 5 && write_pgm(argv[4], face, &line) < 0) {
		fprintf(stderr, "write pgm failed: %s\n", argv[4]);
		FT_Done_Face(face);
		FT_Done_FreeType(library);
		return 1;
	}
	FT_Done_Face(face);
	FT_Done_FreeType(library);
	return 0;
}
