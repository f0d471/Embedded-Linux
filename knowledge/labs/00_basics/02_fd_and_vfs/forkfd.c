/* fork 之后，父子共享的是哪一层 */
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/wait.h>

int main(void)
{
	int fd = open("shared.txt", O_WRONLY | O_CREAT | O_TRUNC, 0644);
	pid_t pid;

	write(fd, "AAAAA", 5);        /* fork 前先写 5 字节，f_pos = 5 */

	pid = fork();
	if (pid == 0) {
		write(fd, "child", 5);    /* 子进程写 */
		exit(0);
	}
	wait(NULL);                   /* 等子进程写完 */
	write(fd, "PAREN", 5);        /* 父进程再写 */
	close(fd);

	printf("文件内容: ");
	fflush(stdout);
	execlp("cat", "cat", "shared.txt", NULL);
	return 0;
}
