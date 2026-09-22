#include <stdint.h>
#include <stdio.h>
#include <string.h>

static uint16_t read_le16(const unsigned char p[2])
{
#ifdef BUG_ENDIAN
	return ((uint16_t)p[0] << 8) | p[1];
#else
	return (uint16_t)p[0] | ((uint16_t)p[1] << 8);
#endif
}

static uint16_t read_be16(const unsigned char p[2])
{
	return ((uint16_t)p[0] << 8) | p[1];
}

static void print_bits(unsigned char byte, int msb_first)
{
#ifdef BUG_BIT_ORDER
	(void)msb_first;
#endif
	for (int x = 0; x < 8; x++) {
#ifdef BUG_BIT_ORDER
		int bit = x;
#else
		int bit = msb_first ? 7 - x : x;
#endif
		putchar((byte & (1u << bit)) ? '#' : '.');
	}
}

static long floor_26_6(long value)
{
	if (value >= 0)
		return value >> 6;
	return -(((-value) + 63) >> 6);
}

static long round_26_6(long value)
{
#ifdef BUG_FIXED_100
	return (value + 50) / 100;
#else
	return floor_26_6(value + 32);
#endif
}

int main(void)
{
	uint32_t value = 0x12345678u;
	unsigned char memory[sizeof value];
	const unsigned char two[] = { 0x2d, 0x4e };

	memcpy(memory, &value, sizeof memory);
	printf("native bytes: %02x %02x %02x %02x\n",
	       memory[0], memory[1], memory[2], memory[3]);
	printf("2d 4e as LE=0x%04x as BE=0x%04x\n",
	       read_le16(two), read_be16(two));

	printf("0x62 MSB-first: ");
	print_bits(0x62, 1);
	printf("\n0x62 LSB-first: ");
	print_bits(0x62, 0);
	putchar('\n');

	printf("26.6: one_pixel=%d ten_and_half=%d raw_672_floor=%ld raw_672_round=%ld\n",
	       1 << 6, (10 << 6) + 32, floor_26_6(672), round_26_6(672));
	printf("26.6 negative: raw_-33_floor=%ld raw_-33_round=%ld\n",
	       floor_26_6(-33), round_26_6(-33));
	return 0;
}
