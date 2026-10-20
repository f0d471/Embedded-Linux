/* fundamentals 05 第 3.3 节:-fPIC 什么时候是硬约束
 * 这个文件访问了全局变量, 关掉位置无关代码后再编共享库, 链接器会拒绝:
 *   arm-linux-gnueabihf-gcc -O2 -fno-pic -c cnt.c -o cnt_nop.o
 *   arm-linux-gnueabihf-gcc -shared cnt_nop.o -o libcnt_arm.so
 *     -> relocation R_ARM_THM_MOVW_ABS_NC ... recompile with -fPIC
 */
static int counter = 100;

int bump(void)
{
	return ++counter;
}
