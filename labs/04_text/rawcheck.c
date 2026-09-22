#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static unsigned number(const char *text, const char *name)
{
	char *end;
	unsigned long value;

	errno = 0;
	value = strtoul(text, &end, 0);
	if (errno || *text == '\0' || *end != '\0' || value > UINT32_MAX) {
		fprintf(stderr, "bad %s: %s\n", name, text);
		exit(2);
	}
	return (unsigned)value;
}

static uint32_t load_pixel(const unsigned char *p, unsigned bytes)
{
	uint32_t value = 0;

	for (unsigned i = 0; i < bytes; i++)
		value |= (uint32_t)p[i] << (8 * i);
	return value;
}

static unsigned field_to_8(uint32_t pixel, unsigned offset, unsigned length)
{
	uint32_t mask, value;

	if (!length)
		return 0;
	mask = length == 32 ? UINT32_MAX : ((UINT32_C(1) << length) - 1);
	value = (pixel >> offset) & mask;
	return (unsigned)(((uint64_t)value * 255 + mask / 2) / mask);
}

static int compare_u32(const void *left, const void *right)
{
	uint32_t a = *(const uint32_t *)left;
	uint32_t b = *(const uint32_t *)right;

	return (a > b) - (a < b);
}

int main(int argc, char **argv)
{
	FILE *file;
	unsigned width, height, stride, bpp, bytes;
	unsigned ro, rl, go, gl, bo, bl;
	size_t expected, pixels, got, nonblack = 0, unique = 0;
	unsigned min_x, min_y, max_x = 0, max_y = 0;
	unsigned char *raw;
	uint32_t *colors;

	if (argc != 12) {
		fprintf(stderr, "usage: %s RAW W H STRIDE BPP RO RL GO GL BO BL\n", argv[0]);
		return 2;
	}
	width = number(argv[2], "width");
	height = number(argv[3], "height");
	stride = number(argv[4], "stride");
	bpp = number(argv[5], "bpp");
	ro = number(argv[6], "red offset");
	rl = number(argv[7], "red length");
	go = number(argv[8], "green offset");
	gl = number(argv[9], "green length");
	bo = number(argv[10], "blue offset");
	bl = number(argv[11], "blue length");
	if (!width || !height || (bpp != 16 && bpp != 32) ||
	    ro + rl > bpp || go + gl > bpp || bo + bl > bpp) {
		fprintf(stderr, "unsupported geometry or bitfield\n");
		return 2;
	}
	bytes = bpp / 8;
	if (stride < width * bytes) {
		fprintf(stderr, "stride %u is smaller than one visible row %u\n",
		        stride, width * bytes);
		return 2;
	}
	expected = (size_t)stride * height;
	pixels = (size_t)width * height;
	raw = malloc(expected);
	colors = malloc(pixels * sizeof *colors);
	if (!raw || !colors) {
		fprintf(stderr, "out of memory\n");
		return 2;
	}
	file = fopen(argv[1], "rb");
	if (!file) {
		fprintf(stderr, "%s: %s\n", argv[1], strerror(errno));
		return 2;
	}
	got = fread(raw, 1, expected, file);
	if (got != expected || fgetc(file) != EOF) {
		fprintf(stderr, "size mismatch: got at least %zu, expected exactly %zu\n",
		        got, expected);
		return 2;
	}
	fclose(file);

	min_x = width;
	min_y = height;
	for (unsigned y = 0; y < height; y++) {
		for (unsigned x = 0; x < width; x++) {
			uint32_t p = load_pixel(raw + (size_t)y * stride + (size_t)x * bytes, bytes);
			uint32_t rgb = field_to_8(p, ro, rl) << 16 |
			               field_to_8(p, go, gl) << 8 |
			               field_to_8(p, bo, bl);

			colors[(size_t)y * width + x] = rgb;
			if (!rgb)
				continue;
			nonblack++;
			if (x < min_x) min_x = x;
			if (x > max_x) max_x = x;
			if (y < min_y) min_y = y;
			if (y > max_y) max_y = y;
		}
	}
	qsort(colors, pixels, sizeof *colors, compare_u32);
	for (size_t i = 0; i < pixels; i++)
		if (i == 0 || colors[i] != colors[i - 1])
			unique++;

	printf("bytes=%zu expected=%zu visible=%ux%u bpp=%u stride=%u\n",
	       expected, expected, width, height, bpp, stride);
	if (nonblack)
		printf("nonblack=%zu bbox=%u,%u..%u,%u colors=%zu\n",
		       nonblack, min_x, min_y, max_x, max_y, unique);
	else
		printf("nonblack=0 bbox=empty colors=%zu\n", unique);
	free(colors);
	free(raw);
	return 0;
}
