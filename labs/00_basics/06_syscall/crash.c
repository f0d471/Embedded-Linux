/* 崩溃时 printf 的内容还在不在 */
#include <stdio.h>

int main(void)
{
	printf("before crash\n");
	*(int *)0 = 1;                   /* 故意触发 SIGSEGV */
	return 0;
}
