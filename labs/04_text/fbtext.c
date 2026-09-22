#include <errno.h>
#include <fcntl.h>
#include <linux/fb.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#include <ft2build.h>
#include FT_FREETYPE_H

struct screen {
	int fd;
	struct fb_var_screeninfo var;
	struct fb_fix_screeninfo fix;
	unsigned char *memory;
	size_t map_size;
	unsigned bytes_per_pixel;
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

static uint32_t mask_for(unsigned length)
{
	if (length == 0) return 0;
	if (length >= 32) return UINT32_MAX;
	return (1u << length) - 1u;
}

static unsigned field_to_8(uint32_t pixel, const struct fb_bitfield *field)
{
	uint32_t value, max;
	if (!field->length) return 0;
	max = mask_for(field->length);
	value = (pixel >> field->offset) & max;
	return (unsigned)((value * 255u + max / 2u) / max);
}

static uint32_t eight_to_field(unsigned value, const struct fb_bitfield *field)
{
	uint32_t max;
	if (!field->length) return 0;
	max = mask_for(field->length);
	return ((value * max + 127u) / 255u) << field->offset;
}

static uint32_t load_pixel(const unsigned char *p, unsigned bytes)
{
	uint32_t value = 0;
	for (unsigned i = 0; i < bytes; i++)
		value |= (uint32_t)p[i] << (8 * i);
	return value;
}

static void store_pixel(unsigned char *p, unsigned bytes, uint32_t value)
{
	for (unsigned i = 0; i < bytes; i++)
		p[i] = (unsigned char)(value >> (8 * i));
}

static unsigned blend(unsigned background, unsigned foreground, unsigned alpha)
{
	return (foreground * alpha + background * (255u - alpha) + 127u) / 255u;
}

static int put_coverage(struct screen *screen, int x, int y, uint32_t rgb, unsigned alpha)
{
	unsigned char *address;
	uint32_t old, pixel;
	unsigned r, g, b;
	size_t offset;

	if (x < 0 || y < 0 || (unsigned)x >= screen->var.xres || (unsigned)y >= screen->var.yres)
		return 0;
	offset = (size_t)(y + (int)screen->var.yoffset) * screen->fix.line_length +
	         (size_t)(x + (int)screen->var.xoffset) * screen->bytes_per_pixel;
	if (offset + screen->bytes_per_pixel > screen->map_size)
		return 0;
	address = screen->memory + offset;
	/* Deliberate fault-injection hook: collapse antialiasing to on/off pixels. */
#ifdef BUG_NO_ALPHA
	if (alpha)
		alpha = 255;
#endif
	old = load_pixel(address, screen->bytes_per_pixel);
	r = blend(field_to_8(old, &screen->var.red),   (rgb >> 16) & 0xff, alpha);
	g = blend(field_to_8(old, &screen->var.green), (rgb >> 8) & 0xff, alpha);
	b = blend(field_to_8(old, &screen->var.blue),   rgb & 0xff, alpha);
	pixel = eight_to_field(r, &screen->var.red) |
	        eight_to_field(g, &screen->var.green) |
	        eight_to_field(b, &screen->var.blue);
	if (screen->var.transp.length)
		pixel |= mask_for(screen->var.transp.length) << screen->var.transp.offset;
	store_pixel(address, screen->bytes_per_pixel, pixel);
	return 1;
}

static int open_screen(struct screen *screen, const char *path)
{
	memset(screen, 0, sizeof *screen);
	screen->fd = open(path, O_RDWR);
	if (screen->fd < 0 || ioctl(screen->fd, FBIOGET_VSCREENINFO, &screen->var) < 0 ||
	    ioctl(screen->fd, FBIOGET_FSCREENINFO, &screen->fix) < 0) {
		perror(path);
		if (screen->fd >= 0) close(screen->fd);
		return -1;
	}
	if (!screen->var.bits_per_pixel || screen->var.bits_per_pixel % 8 ||
	    screen->var.bits_per_pixel > 32) {
		fprintf(stderr, "unsupported bpp: %u\n", screen->var.bits_per_pixel);
		close(screen->fd);
		return -1;
	}
	screen->bytes_per_pixel = screen->var.bits_per_pixel / 8;
	screen->map_size = screen->fix.smem_len;
	screen->memory = mmap(NULL, screen->map_size, PROT_READ | PROT_WRITE,
	                      MAP_SHARED, screen->fd, 0);
	if (screen->memory == MAP_FAILED) {
		perror("mmap");
		close(screen->fd);
		return -1;
	}
	return 0;
}

static void close_screen(struct screen *screen)
{
	munmap(screen->memory, screen->map_size);
	close(screen->fd);
}

static void clear_visible(struct screen *screen)
{
	for (unsigned y = 0; y < screen->var.yres; y++) {
		size_t offset = (size_t)(y + screen->var.yoffset) * screen->fix.line_length +
		                (size_t)screen->var.xoffset * screen->bytes_per_pixel;
		memset(screen->memory + offset, 0,
		       (size_t)screen->var.xres * screen->bytes_per_pixel);
	}
}

static int parse_long(const char *text, long min, long max, long *value)
{
	char *end;
	errno = 0;
	*value = strtol(text, &end, 0);
	return errno || *text == '\0' || *end != '\0' || *value < min || *value > max ? -1 : 0;
}

int main(int argc, char **argv)
{
	struct screen screen;
	FT_Library library;
	FT_Face face;
	const unsigned char *text;
	size_t length, offset = 0;
	long x, baseline, size, color;
	long pen;
	unsigned glyphs = 0, covered = 0, middle = 0, written = 0, clipped = 0, missing = 0;
	int clear = 0;

	if (argc != 8 && argc != 9) {
		fprintf(stderr, "usage: %s FB FONT UTF8_TEXT X BASELINE_Y PIXELS 0xRRGGBB [--clear]\n", argv[0]);
		return 2;
	}
	if (parse_long(argv[4], -100000, 100000, &x) ||
	    parse_long(argv[5], -100000, 100000, &baseline) ||
	    parse_long(argv[6], 1, 1000, &size) || parse_long(argv[7], 0, 0xffffff, &color) ||
	    (argc == 9 && strcmp(argv[8], "--clear") != 0)) {
		fprintf(stderr, "bad numeric argument or option\n");
		return 2;
	}
	clear = argc == 9;
	if (open_screen(&screen, argv[1]) < 0)
		return 1;
	if (FT_Init_FreeType(&library) || FT_New_Face(library, argv[2], 0, &face) ||
	    FT_Select_Charmap(face, FT_ENCODING_UNICODE) ||
	    FT_Set_Pixel_Sizes(face, 0, (FT_UInt)size)) {
		fprintf(stderr, "FreeType setup failed\n");
		close_screen(&screen);
		return 1;
	}
	if (clear)
		clear_visible(&screen);
	text = (const unsigned char *)argv[3];
	length = strlen(argv[3]);
	pen = x << 6;
	while (offset < length) {
		uint32_t cp;
		int used = decode_one(text + offset, length - offset, &cp);
		FT_GlyphSlot slot;
		if (used < 0) {
			fprintf(stderr, "bad UTF-8 at byte %zu\n", offset);
			FT_Done_Face(face);
			FT_Done_FreeType(library);
			close_screen(&screen);
			return 1;
		}
		if (!FT_Get_Char_Index(face, cp))
			missing++;
		if (FT_Load_Char(face, cp, FT_LOAD_RENDER | FT_LOAD_TARGET_NORMAL)) {
			fprintf(stderr, "cannot render U+%04X\n", cp);
			FT_Done_Face(face);
			FT_Done_FreeType(library);
			close_screen(&screen);
			return 1;
		}
		slot = face->glyph;
		for (unsigned row = 0; row < slot->bitmap.rows; row++)
			for (unsigned col = 0; col < slot->bitmap.width; col++) {
				unsigned alpha = coverage(&slot->bitmap, col, row);
				int dx, dy;
				if (!alpha) continue;
				covered++;
				if (alpha < 255) middle++;
				dx = (int)(pen >> 6) + slot->bitmap_left + (int)col;
				dy = (int)baseline - slot->bitmap_top + (int)row;
				if (put_coverage(&screen, dx, dy, (uint32_t)color, alpha))
					written++;
				else
					clipped++;
			}
		pen += slot->advance.x;
		glyphs++;
		offset += (size_t)used;
	}
	msync(screen.memory, screen.map_size, MS_SYNC);
	printf("fb=%ux%u bpp=%u line_length=%u rgb=%u/%u,%u/%u,%u/%u\n",
	       screen.var.xres, screen.var.yres, screen.var.bits_per_pixel,
	       screen.fix.line_length, screen.var.red.offset, screen.var.red.length,
	       screen.var.green.offset, screen.var.green.length,
	       screen.var.blue.offset, screen.var.blue.length);
	printf("glyphs=%u missing=%u covered=%u mid=%u written=%u clipped=%u advance26_6=%ld advance_px=%.3f\n",
	       glyphs, missing, covered, middle, written, clipped,
	       pen - (x << 6), (pen - (x << 6)) / 64.0);
	FT_Done_Face(face);
	FT_Done_FreeType(library);
	close_screen(&screen);
	return 0;
}
