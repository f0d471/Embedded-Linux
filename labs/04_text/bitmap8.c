#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct glyph {
	char name;
	unsigned char row[16];
};

/* 摘自 Linux 8x16 控制台字库，只留实验用的 A、F。 */
static const struct glyph glyphs[] = {
	{ 'A', { 0x00, 0x00, 0x10, 0x38, 0x6c, 0xc6, 0xc6, 0xfe,
	         0xc6, 0xc6, 0xc6, 0xc6, 0x00, 0x00, 0x00, 0x00 } },
	{ 'F', { 0x00, 0x00, 0xfe, 0x66, 0x62, 0x68, 0x78, 0x68,
	         0x60, 0x60, 0x60, 0xf0, 0x00, 0x00, 0x00, 0x00 } },
};

static int pixel(const struct glyph *g, int x, int y, int lsb_first)
{
	int bit = lsb_first ? x : 7 - x;
	return !!(g->row[y] & (1u << bit));
}

static const struct glyph *find_glyph(char name)
{
	for (size_t i = 0; i < sizeof glyphs / sizeof glyphs[0]; i++)
		if (glyphs[i].name == name)
			return &glyphs[i];
	return NULL;
}

static int write_pgm(const char *path, const struct glyph *g, int lsb_first)
{
	FILE *fp = fopen(path, "wb");
	if (!fp)
		return -1;
	fprintf(fp, "P5\n8 16\n255\n");
	for (int y = 0; y < 16; y++)
		for (int x = 0; x < 8; x++)
			fputc(pixel(g, x, y, lsb_first) ? 255 : 0, fp);
	return fclose(fp);
}

int main(int argc, char **argv)
{
	const struct glyph *g;
	const char *pgm = NULL;
	int lsb_first = 0, lit = 0, minx = 8, miny = 16, maxx = -1, maxy = -1;

	if (argc < 2) {
		fprintf(stderr, "usage: %s A|F [--lsb-first] [--pgm FILE]\n", argv[0]);
		return 2;
	}
	g = find_glyph(argv[1][0]);
	if (!g || argv[1][1] != '\0') {
		fprintf(stderr, "only A and F are available\n");
		return 2;
	}
	for (int i = 2; i < argc; i++) {
		if (strcmp(argv[i], "--lsb-first") == 0)
			lsb_first = 1;
		else if (strcmp(argv[i], "--pgm") == 0 && i + 1 < argc)
			pgm = argv[++i];
		else {
			fprintf(stderr, "bad option: %s\n", argv[i]);
			return 2;
		}
	}

	for (int y = 0; y < 16; y++) {
		for (int x = 0; x < 8; x++) {
			int on = pixel(g, x, y, lsb_first);
			putchar(on ? '#' : '.');
			if (on) {
				lit++;
				if (x < minx) minx = x;
				if (x > maxx) maxx = x;
				if (y < miny) miny = y;
				if (y > maxy) maxy = y;
			}
		}
		putchar('\n');
	}
	printf("glyph=%c order=%s lit=%d bbox=%d,%d..%d,%d\n",
	       g->name, lsb_first ? "LSB" : "MSB", lit, minx, miny, maxx, maxy);
	if (pgm && write_pgm(pgm, g, lsb_first) < 0) {
		perror(pgm);
		return 1;
	}
	return 0;
}
