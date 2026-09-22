/*
 * 08 篇（进程与信号）实验 2：父进程怎么知道子进程是怎么结束的
 *
 * 用法：./waiter ./child segv
 * fork 出子进程去跑命令行给的程序，然后 waitpid 拿回内核给的状态字并解码。
 *
 * 注错：-DBUG_ONLY_EXITSTATUS 只取退出码、不看是不是被信号杀的。
 */
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <sys/wait.h>

int main(int argc, char **argv)
{
	pid_t pid;
	int st;

	if (argc < 2) {
		fprintf(stderr, "用法: %s 程序 [参数...]\n", argv[0]);
		return 2;
	}

	pid = fork();
	if (pid == 0) {
		execv(argv[1], argv + 1);	/* 子进程换成要跑的程序 */
		perror("execv");
		_exit(127);
	}

	waitpid(pid, &st, 0);			/* 等它结束，内核把状态字填进 st */
	printf("状态字=0x%04x  ", st);
#ifdef BUG_ONLY_EXITSTATUS
	printf("退出码 %d\n", WEXITSTATUS(st));
#else
	if (WIFEXITED(st))
		printf("正常退出，退出码 %d\n", WEXITSTATUS(st));
	else if (WIFSIGNALED(st))
		printf("被信号 %d (%s) 杀死\n", WTERMSIG(st), strsignal(WTERMSIG(st)));
#endif
	return 0;
}
