/* 打印 N 行、每行 10 字节，数 C 库一共发了几次 write。
 * 用法：./lines N [full|line|none|err]
 *       不给第二个参数：stdout 用 C 库按目标自动选的缓冲方式
 *       full/line/none：先用 setvbuf 把 stdout 改成全缓冲/行缓冲/无缓冲
 *       err：改往 stderr 打印，缓冲方式用 stderr 的默认值
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv)
{
	int n = argc > 1 ? atoi(argv[1]) : 1000;
	const char *mode = argc > 2 ? argv[2] : "";
	FILE *out = stdout;
	int i;

	if (strcmp(mode, "full") == 0)
		setvbuf(stdout, NULL, _IOFBF, 0);
	else if (strcmp(mode, "line") == 0)
		setvbuf(stdout, NULL, _IOLBF, 0);
	else if (strcmp(mode, "none") == 0)
		setvbuf(stdout, NULL, _IONBF, 0);
	else if (strcmp(mode, "err") == 0)
		out = stderr;

	for (i = 0; i < n; i++)
		fprintf(out, "line %04d\n", i);
	return 0;
}
