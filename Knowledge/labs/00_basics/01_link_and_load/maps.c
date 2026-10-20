/* 00 篇第 7 节：打印自己进程的内存布局，再报告几个符号的运行时地址。
 * /proc/self/maps 是内核提供的伪文件，读它就是在问内核：
 * “我这个进程的内存现在摆成了什么样？”
 */
#include <stdio.h>

int g_init = 1;   /* 有初值的全局变量，进 .data */
int g_bss;        /* 无初值的全局变量，进 .bss */

int main(void)
{
	char line[256];
	FILE *f = fopen("/proc/self/maps", "r");

	while (fgets(line, sizeof line, f))
		fputs(line, stdout);
	fclose(f);

	printf("&main  =%p\n", (void *)main);
	printf("&g_init=%p\n", (void *)&g_init);
	printf("&g_bss =%p\n", (void *)&g_bss);
	printf("g_bss  =%d\n", g_bss);
	return 0;
}
