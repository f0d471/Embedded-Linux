/* 把命令行参数原样数出来：argc 是个数，argv 是字符串数组。
 * 编译：gcc -Wall argv_dump.c -o argv_dump
 * 跑：  ./argv_dump            ./argv_dump a b            ./argv_dump "a b c"
 * 观察点：argc 的值、argv[0] 永远是程序名、带空格的参数用引号并成一个。
 */
#include <stdio.h>

int main(int argc, char **argv)
{
	int i;

	printf("argc = %d\n", argc);
	for (i = 0; i < argc; i++)
		printf("argv[%d] = %s\n", i, argv[i]);
	return 0;
}
