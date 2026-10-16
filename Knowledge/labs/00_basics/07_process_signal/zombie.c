/*
 * 08 篇（进程与信号）实验 4：子进程先结束、父进程迟迟不收
 *
 * 用法：./zombie &   然后在 1 秒和 4 秒时各看一次 ps
 * 子进程立刻退出；父进程先睡 3 秒才 waitpid，再睡 3 秒才退出。
 *
 * 注错：-DREAP_NOW 父进程不睡，马上 waitpid。
 */
#include <stdio.h>
#include <unistd.h>
#include <sys/wait.h>

int main(void)
{
	pid_t c = fork();

	if (c == 0)
		_exit(7);	/* 子进程：什么都不干，直接结束 */

	printf("父 %d  子 %d（子进程已经结束）\n", getpid(), c);
	fflush(stdout);
#ifndef REAP_NOW
	sleep(3);		/* 这 3 秒里子进程是僵尸 */
#endif
	waitpid(c, NULL, 0);
	printf("父进程 waitpid 完成\n");
	fflush(stdout);
	sleep(3);
	return 0;
}
