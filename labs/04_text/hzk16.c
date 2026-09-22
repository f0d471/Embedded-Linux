#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

static int parse_byte(const char *text, unsigned char *out)
{
	char *end;
	unsigned long value;

	errno = 0;
	value = strtoul(text, &end, 16);
	if (errno || *text == '\0' || *end != '\0' || value > 0xff)
		return -1;
	*out = (unsigned char)value;
	return 0;
}

static uint32_t fnv1a(const unsigned char *data, size_t length)
{
	uint32_t hash = 2166136261u;
	for (size_t i = 0; i < length; i++) {
		hash ^= data[i];
		hash *= 16777619u;
	}
	return hash;
}

int main(int argc, char **argv)
{
	unsigned char first, second, dots[32];
	unsigned long index, offset;
	long size = -1;
	int lit = 0, minx = 16, miny = 16, maxx = -1, maxy = -1;
	FILE *fp;

	if (argc != 4) {
		fprintf(stderr, "usage: %s HZK16 FIRST SECOND  (bytes are hex)\n", argv[0]);
		return 2;
	}
	if (parse_byte(argv[2], &first) < 0 || parse_byte(argv[3], &second) < 0) {
		fprintf(stderr, "bad byte\n");
		return 2;
	}
	if (first < 0xa1 || first > 0xfe || second < 0xa1 || second > 0xfe) {
		fprintf(stderr, "bytes are outside the GB2312 94x94 area\n");
		return 2;
	}
	index = (unsigned long)(first - 0xa1) * 94 + (second - 0xa1);
	offset = index * sizeof dots;
	fp = fopen(argv[1], "rb");
	if (!fp) {
		perror(argv[1]);
		return 1;
	}
	if (fseek(fp, 0, SEEK_END) != 0 || (size = ftell(fp)) < 0 ||
	    offset + sizeof dots > (unsigned long)size || fseek(fp, (long)offset, SEEK_SET) != 0 ||
	    fread(dots, 1, sizeof dots, fp) != sizeof dots) {
		fprintf(stderr, "glyph offset %lu is outside file size %ld\n", offset, size);
		fclose(fp);
		return 1;
	}
	fclose(fp);

	for (int y = 0; y < 16; y++) {
		for (int x = 0; x < 16; x++) {
			unsigned char byte = dots[y * 2 + x / 8];
			int on = !!(byte & (1u << (7 - x % 8)));
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
	printf("bytes=%02X%02X index=%lu offset=%lu file_size=%ld lit=%d bbox=%d,%d..%d,%d fnv1a=%08x\n",
	       first, second, index, offset, size, lit, minx, miny, maxx, maxy,
	       fnv1a(dots, sizeof dots));
	return 0;
}
