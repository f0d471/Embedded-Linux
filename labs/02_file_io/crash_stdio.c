/* stdout/stderr 在异常退出时的差别。
 * 用法：./crash_stdio > stdout.txt 2> stderr.txt
 */
#include <stdio.h>
#include <stdlib.h>

int main(void)
{
	printf("to stdout\n");
	fprintf(stderr, "to stderr\n");
	abort();
}
