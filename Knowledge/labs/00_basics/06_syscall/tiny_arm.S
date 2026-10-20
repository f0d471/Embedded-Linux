/* 不链接 C 库的最小程序（32 位 ARM EABI）：write(1, msg, len)，再 exit(7)。
 * 编译：arm-linux-gnueabihf-gcc -nostdlib -static tiny_arm.S -o tiny_arm
 */
	.syntax	unified
	.arm

	.section .rodata
msg:	.ascii	"hi from svc\n"
	len = . - msg

	.text
	.globl	_start
_start:
	mov	r0, #1			@ 参数 1：fd = 1
	ldr	r1, =msg		@ 参数 2：buf = msg 的地址
	mov	r2, #len		@ 参数 3：count = 12
	mov	r7, #4			@ 调用号 4 = write
	svc	#0
	mov	r0, #7			@ 参数 1：退出码 7
	mov	r7, #1			@ 调用号 1 = exit
	svc	#0
