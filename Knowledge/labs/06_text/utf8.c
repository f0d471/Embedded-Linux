#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int is_cont(unsigned char c)
{
	return (c & 0xc0) == 0x80;
}

/* 成功返回消耗的字节数；失败返回 -1。调用者失败时只跳过 1 字节，重新找边界。 */
static int decode_one(const unsigned char *s, size_t left, uint32_t *codepoint)
{
	uint32_t cp;

	if (left == 0)
		return -1;
	if (s[0] <= 0x7f) {
		*codepoint = s[0];
		return 1;
	}
	if (s[0] >= 0xc2 && s[0] <= 0xdf) {
		if (left < 2 || !is_cont(s[1]))
			return -1;
		cp = ((uint32_t)(s[0] & 0x1f) << 6) | (s[1] & 0x3f);
		*codepoint = cp;
		return 2;
	}
	if (s[0] >= 0xe0 && s[0] <= 0xef) {
		if (left < 3 || !is_cont(s[1]) || !is_cont(s[2]))
			return -1;
		if ((s[0] == 0xe0 && s[1] < 0xa0) ||
		    (s[0] == 0xed && s[1] >= 0xa0))
			return -1; /* 过长编码，或 UTF-16 surrogate 区 */
		cp = ((uint32_t)(s[0] & 0x0f) << 12) |
		     ((uint32_t)(s[1] & 0x3f) << 6) | (s[2] & 0x3f);
		*codepoint = cp;
		return 3;
	}
	if (s[0] >= 0xf0 && s[0] <= 0xf4) {
		if (left < 4 || !is_cont(s[1]) || !is_cont(s[2]) || !is_cont(s[3]))
			return -1;
		if ((s[0] == 0xf0 && s[1] < 0x90) ||
		    (s[0] == 0xf4 && s[1] >= 0x90))
			return -1; /* 过长编码，或超过 U+10FFFF */
		cp = ((uint32_t)(s[0] & 0x07) << 18) |
		     ((uint32_t)(s[1] & 0x3f) << 12) |
		     ((uint32_t)(s[2] & 0x3f) << 6) | (s[3] & 0x3f);
		*codepoint = cp;
		return 4;
	}
	return -1;
}

static int hex_byte(const char *text, unsigned char *out)
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

int main(int argc, char **argv)
{
	unsigned char *owned = NULL;
	const unsigned char *bytes;
	size_t length, offset = 0;
	unsigned codepoints = 0, errors = 0;

	if (argc >= 3 && strcmp(argv[1], "--hex") == 0) {
		length = (size_t)argc - 2;
		owned = malloc(length ? length : 1);
		if (!owned)
			return 2;
		for (int i = 2; i < argc; i++) {
			if (hex_byte(argv[i], &owned[i - 2]) < 0) {
				fprintf(stderr, "bad hex byte: %s\n", argv[i]);
				free(owned);
				return 2;
			}
		}
		bytes = owned;
	} else if (argc == 2) {
		bytes = (const unsigned char *)argv[1];
		length = strlen(argv[1]);
	} else {
		fprintf(stderr, "usage: %s TEXT | %s --hex BYTE...\n", argv[0], argv[0]);
		return 2;
	}

	printf("bytes=%zu\n", length);
	while (offset < length) {
		uint32_t cp;
		int used = decode_one(bytes + offset, length - offset, &cp);
		if (used < 0) {
			printf("ERROR at=%zu byte=%02X\n", offset, bytes[offset]);
			errors++;
			offset++;
			continue;
		}
		printf("U+%04X at=%zu len=%d\n", cp, offset, used);
		codepoints++;
		offset += (size_t)used;
	}
	printf("summary codepoints=%u errors=%u\n", codepoints, errors);
	free(owned);
	return errors ? 1 : 0;
}
