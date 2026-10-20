/* 不经过 C 库，用一条指令直接发系统调用。x86-64 与 32 位 ARM（EABI）各一套。 */
#ifndef RAW_H
#define RAW_H

#if defined(__x86_64__)

#define NR_write 1
#define NR_exit  60

static inline long raw_syscall3(long nr, long a1, long a2, long a3)
{
	long ret;

	__asm__ volatile ("syscall"
		: "=a"(ret)                     /* 返回值从 rax 出来 */
		: "a"(nr),                      /* rax = 调用号 */
		  "D"(a1), "S"(a2), "d"(a3)     /* rdi、rsi、rdx = 参数 1～3 */
		: "rcx", "r11", "memory");      /* syscall 指令会改写 rcx 和 r11 */
	return ret;
}

#elif defined(__arm__)

#define NR_write 4
#define NR_exit  1

static inline long raw_syscall3(long nr, long a1, long a2, long a3)
{
	register long r7 __asm__("r7") = nr;    /* r7 = 调用号 */
	register long r0 __asm__("r0") = a1;    /* r0～r2 = 参数 1～3 */
	register long r1 __asm__("r1") = a2;
	register long r2 __asm__("r2") = a3;

	__asm__ volatile ("svc #0"
		: "+r"(r0)                      /* 返回值写回 r0 */
		: "r"(r7), "r"(r1), "r"(r2)
		: "memory");
	return r0;
}

#else
#error "raw.h 只写了 x86-64 和 32 位 ARM 两套"
#endif

#endif
