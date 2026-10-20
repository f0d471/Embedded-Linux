	.arch armv7-a
	.fpu vfpv3-d16
	.eabi_attribute 28, 1
	.eabi_attribute 20, 1
	.eabi_attribute 21, 1
	.eabi_attribute 23, 3
	.eabi_attribute 24, 1
	.eabi_attribute 25, 1
	.eabi_attribute 26, 2
	.eabi_attribute 30, 6
	.eabi_attribute 34, 1
	.eabi_attribute 18, 4
	.file	"main.c"
	.text
	.global	g_init
	.data
	.align	2
	.type	g_init, %object
	.size	g_init, 4
g_init:
	.word	1
	.global	g_bss
	.bss
	.align	2
	.type	g_bss, %object
	.size	g_bss, 4
g_bss:
	.space	4
	.text
	.align	1
	.global	main
	.syntax unified
	.thumb
	.thumb_func
	.type	main, %function
main:
	@ args = 0, pretend = 0, frame = 0
	@ frame_needed = 1, uses_anonymous_args = 0
	push	{r7, lr}
	add	r7, sp, #0
	ldr	r3, .L3
.LPIC0:
	add	r3, pc
	ldr	r3, [r3]
	movs	r1, #2
	mov	r0, r3
	bl	add(PLT)
	mov	r2, r0
	ldr	r3, .L3+4
.LPIC1:
	add	r3, pc
	ldr	r3, [r3]
	add	r3, r3, r2
	mov	r0, r3
	pop	{r7, pc}
.L4:
	.align	2
.L3:
	.word	g_init-(.LPIC0+4)
	.word	g_bss-(.LPIC1+4)
	.size	main, .-main
	.ident	"GCC: (Ubuntu 15.2.0-16ubuntu1) 15.2.0"
	.section	.note.GNU-stack,"",%progbits
