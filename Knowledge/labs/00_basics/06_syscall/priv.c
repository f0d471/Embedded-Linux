/* 用户态直接碰硬件会怎样。
 * 用法：./priv none   什么都不碰，对照组
 *       ./priv insn   执行一条特权指令（x86-64: cli；ARM: 读 CP15 的 SCTLR）
 *       ./priv mmio   往 i.MX6ULL UART1 发送寄存器的物理地址写一个字节
 */
#include <stdio.h>
#include <string.h>

int main(int argc, char **argv)
{
	const char *what = argc > 1 ? argv[1] : "none";

	fprintf(stderr, "try %s\n", what);
	if (strcmp(what, "insn") == 0) {
#if defined(__x86_64__)
		__asm__ volatile ("cli");                       /* 关中断 */
#elif defined(__arm__)
		unsigned long sctlr;
		__asm__ volatile ("mrc p15, 0, %0, c1, c0, 0" : "=r"(sctlr));
#endif
	} else if (strcmp(what, "mmio") == 0) {
		*(volatile unsigned char *)0x02020040 = 'a';    /* UART1 基址 0x02020000 + UTXD 0x40 */
	}
	fprintf(stderr, "survived %s\n", what);
	return 0;
}
