/* 不链接 C 库的最小程序（x86-64）：write(1, msg, len)，再 exit(7)。
 * 编译：gcc -nostdlib -static tiny_x86.S -o tiny_x86
 */
	.section .rodata
msg:	.ascii	"hi from syscall\n"
	len = . - msg

	.text
	.globl	_start
_start:
	mov	$1, %eax		/* 调用号 1 = write */
	mov	$1, %edi		/* 参数 1：fd = 1 */
	lea	msg(%rip), %rsi		/* 参数 2：buf = msg 的地址 */
	mov	$len, %edx		/* 参数 3：count = 16 */
	syscall
	mov	$60, %eax		/* 调用号 60 = exit */
	mov	$7, %edi		/* 参数 1：退出码 7 */
	syscall
