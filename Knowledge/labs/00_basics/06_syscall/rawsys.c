/* 不经过 C 库的 write：没有 include 任何 C 库头文件，照样把一行字送到 fd 1。
 * 电脑：gcc -O2 rawsys.c -o rawsys
 * ARM： arm-linux-gnueabihf-gcc -O2 -static rawsys.c -o rawsys_arm
 */
#include "raw.h"

int main(void)
{
	static const char msg[] = "hello from raw syscall\n";

	raw_syscall3(NR_write, 1, (long)msg, sizeof msg - 1);
	return 0;
}
