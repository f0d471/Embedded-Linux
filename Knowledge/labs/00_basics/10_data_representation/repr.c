/* fundamentals 13（数据表示：字节序、位序与定点数）的配套实验。
 * 一个程序把四层"同一串比特、不同规格"各打印一遍：
 *   1. 字节序  同一个 uint32 在内存里的四个字节；同两个字节的两种读法
 *   2. 位序    点阵字模一个字节的 8 个 bit 对应哪 8 个像素
 *   3. 补码    负数的字节长相；同一字节按有/无符号两种读法
 *   4. 定点数  26.6 的存法与还原；负数取整
 * 编译: gcc -Wall -Wextra -Werror -O2 -o repr repr.c
 * 注错版: -DBUG_ENDIAN / -DBUG_BIT_ORDER / -DBUG_FIXED_100 / -DBUG_TRUNC_DIV
 */
#include <stdint.h>
#include <stdio.h>
#include <string.h>

static uint16_t read_le16(const unsigned char p[2])
{
#ifdef BUG_ENDIAN
	return ((uint16_t)p[0] << 8) | p[1]; /* 两项权重写反 */
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
	int x;

#ifdef BUG_BIT_ORDER
	(void)msb_first; /* 注错版无视字库约定 */
#endif
	for (x = 0; x < 8; x++) {
#ifdef BUG_BIT_ORDER
		int bit = x; /* 恒从 bit 0 开始 */
#else
		int bit = msb_first ? 7 - x : x;
#endif
		putchar((byte & (1u << bit)) ? '#' : '.');
	}
}

/* Linux 内核 8x16 控制台字库里 'A' 的前 12 行，出自 lib/fonts/font_8x16.c */
static const unsigned char glyph_a[12] = {
	0x00, 0x00, 0x10, 0x38, 0x6c, 0xc6,
	0xc6, 0xfe, 0xc6, 0xc6, 0xc6, 0xc6
};

static long floor_26_6(long value)
{
#ifdef BUG_TRUNC_DIV
	return value / 64; /* C 除法向 0 截断，不是几何意义上的向下取整 */
#else
	if (value >= 0)
		return value >> 6;
	return -(((-value) + 63) >> 6);
#endif
}

static long round_26_6(long value)
{
#ifdef BUG_FIXED_100
	return (value + 50) / 100; /* 错当成百分制 */
#else
	return floor_26_6(value + 32);
#endif
}

int main(void)
{
	uint32_t value = 0x12345678u;
	unsigned char memory[sizeof value];
	const unsigned char two[] = { 0x2d, 0x4e };
	int32_t neg1 = -1, neg33 = -33;
	unsigned char nb[4];
	FILE *fp;
	int i;

	/* 1 字节序 */
	memcpy(memory, &value, sizeof memory);
	printf("native bytes: %02x %02x %02x %02x\n",
	       memory[0], memory[1], memory[2], memory[3]);
	fp = fopen("mem.bin", "wb"); /* 落盘一份，正文用 xxd 实看 */
	if (fp) {
		fwrite(memory, 1, sizeof memory, fp);
		fclose(fp);
	}
	printf("2d 4e as LE=0x%04x as BE=0x%04x\n",
	       read_le16(two), read_be16(two));

	/* 2 位序 */
	printf("0x62 MSB-first: ");
	print_bits(0x62, 1);
	printf("\n0x62 LSB-first: ");
	print_bits(0x62, 0);
	putchar('\n');
	printf("glyph A (MSB-first), ruler=bit number:\n");
	printf("bit: 76543210\n");
	for (i = 0; i < 12; i++) {
		printf("0x%02x ", glyph_a[i]);
		print_bits(glyph_a[i], 1);
		putchar('\n');
	}

	/* 3 补码 */
	memcpy(nb, &neg1, 4);
	printf("-1  bytes: %02x %02x %02x %02x\n", nb[0], nb[1], nb[2], nb[3]);
	memcpy(nb, &neg33, 4);
	printf("-33 bytes: %02x %02x %02x %02x\n", nb[0], nb[1], nb[2], nb[3]);
	printf("(int8_t)0xd6=%d (uint8_t)0xd6=%d\n",
	       (int)(int8_t)0xd6, (int)(uint8_t)0xd6);
	printf("-33>>6=%d  u8:255+1=%d\n", neg33 >> 6, (int)(uint8_t)(255u + 1u));

	/* 4 定点数 26.6 */
	printf("26.6: one_pixel=%d ten_and_half=%d raw_672_floor=%ld raw_672_round=%ld\n",
	       1 << 6, (10 << 6) + 32, floor_26_6(672), round_26_6(672));
	printf("26.6 negative: raw_-33_floor=%ld raw_-33_round=%ld\n",
	       floor_26_6(-33), round_26_6(-33));
	printf("26.6 advance: 1536>>6=%ld 6144>>6=%ld\n",
	       floor_26_6(1536), floor_26_6(6144));
	return 0;
}
