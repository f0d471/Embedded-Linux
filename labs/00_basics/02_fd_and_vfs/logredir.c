/* 不改原有日志语句，统一让 stderr 从终端改写到文件 */
#include <stdio.h>
#include <unistd.h>
#include <fcntl.h>

static void worker(void)          /* 假装这是别人写的库，只认 stderr */
{
	fprintf(stderr, "worker: 干活中\n");
}

int main(void)
{
	int fd;

	fprintf(stderr, "1. 重定向之前，这行去终端\n");
	worker();

	fd = open("log.txt", O_WRONLY | O_CREAT | O_TRUNC, 0644);
	printf("2. 日志文件拿到的 fd = %d\n", fd);

	dup2(fd, STDERR_FILENO);      /* 让 stderr 以后写进 log.txt */
	close(fd);                    /* fd 已经多余；关掉它不影响 stderr */

	fprintf(stderr, "3. 重定向之后，这行去文件\n");
	worker();                     /* 同一个函数，一个字没改 */

	return 0;
}
