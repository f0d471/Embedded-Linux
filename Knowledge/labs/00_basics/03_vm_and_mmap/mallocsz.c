/* 09 篇第 7.3 节：malloc 什么时候去要一块匿名映射
 *
 * 用法: strace -e trace=mmap,brk ./mallocsz
 * 看输出：64 KiB 的申请走 brk，2 MiB 的申请走 mmap(MAP_ANONYMOUS)。
 */
#include <stdio.h>
#include <stdlib.h>

int main(void)
{
	void *a = malloc(64 * 1024);         /* 小于阈值，从堆里切 */
	void *b = malloc(2 * 1024 * 1024);   /* 大于阈值，单独 mmap 一块 */

	printf("a = %p（64 KiB）\n", a);
	printf("b = %p（2 MiB）\n", b);
	((char *)a)[0] = 1;
	((char *)b)[0] = 1;
	free(a);
	free(b);
	return 0;
}
