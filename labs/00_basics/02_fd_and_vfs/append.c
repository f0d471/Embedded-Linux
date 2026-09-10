/* O_APPEND 的原子性：两个进程同时往一个文件追加
 *   用法: ./append append   -> 用 O_APPEND
 *         ./append lseek    -> 自己 lseek 到末尾再写
 */
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <string.h>
#include <sys/wait.h>

#define N     2000            /* 每个进程写多少条 */
#define LINE  "0123456789abcdef\n"   /* 每条 17 字节 */

static void writer(int use_append, int tag)
{
	int fd, i;
	int flags = O_WRONLY | (use_append ? O_APPEND : 0);

	fd = open("out.txt", flags);
	for (i = 0; i < N; i++) {
		if (!use_append)
			lseek(fd, 0, SEEK_END);   /* 自己找末尾：这是第 1 次系统调用 */
		write(fd, LINE, strlen(LINE));    /* 写：这是第 2 次 */
	}
	close(fd);
	(void)tag;
}

int main(int argc, char **argv)
{
	int use_append = (argc > 1 && !strcmp(argv[1], "append"));
	int fd;
	pid_t pid;

	fd = open("out.txt", O_WRONLY | O_CREAT | O_TRUNC, 0644);
	close(fd);

	pid = fork();
	if (pid == 0) { writer(use_append, 1); exit(0); }
	writer(use_append, 0);
	wait(NULL);

	printf("%-8s 模式：期望 %d 字节，实际 %ld 字节\n",
	       use_append ? "append" : "lseek",
	       2 * N * (int)strlen(LINE),
	       (long)lseek(open("out.txt", O_RDONLY), 0, SEEK_END));
	return 0;
}
