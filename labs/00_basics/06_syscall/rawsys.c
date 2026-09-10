/* 绕过 libc，自己发一条系统调用 */
#include <unistd.h>

/* x86-64: 调用号放 rax，参数放 rdi/rsi/rdx，syscall 指令进内核 */
static long raw_write(int fd, const void *buf, unsigned long n)
{
	long ret;
	__asm__ volatile (
		"syscall"
		: "=a"(ret)                          /* 返回值从 rax 出来 */
		: "a"(1),      /* rax = 1 = __NR_write */
		  "D"(fd),     /* rdi = 第 1 个参数 */
		  "S"(buf),    /* rsi = 第 2 个参数 */
		  "d"(n)       /* rdx = 第 3 个参数 */
		: "rcx", "r11", "memory"             /* syscall 会破坏这两个寄存器 */
	);
	return ret;
}

int main(void)
{
	const char msg[] = "hello from raw syscall\n";
	raw_write(1, msg, sizeof msg - 1);
	return 0;
}
