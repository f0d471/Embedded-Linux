/*
 * 12 篇（进程与信号）实验：挂起的信号是一位，不是一个数
 *
 * 用法：./sigcount
 * 屏蔽 SIGUSR1 后连续 raise 5 次，处理函数一次都不执行；
 * 解蔽的一瞬间执行，且只执行 1 次：5 个信号压成了挂起位图里的同一位。
 *
 * 注错：-DNO_BLOCK 不屏蔽，5 次 raise 各执行一次。
 */
#include <signal.h>
#include <stdio.h>
#include <string.h>

static volatile sig_atomic_t g_n;

static void on_usr1(int sig)
{
	(void)sig;
	g_n++;
}

int main(void)
{
	struct sigaction sa;
	sigset_t blk, pend;
	int i;

	memset(&sa, 0, sizeof sa);
	sa.sa_handler = on_usr1;
	sigemptyset(&sa.sa_mask);
	if (sigaction(SIGUSR1, &sa, NULL) < 0) {
		perror("sigaction");
		return 1;
	}

	sigemptyset(&blk);
	sigaddset(&blk, SIGUSR1);
#ifndef NO_BLOCK
	if (sigprocmask(SIG_BLOCK, &blk, NULL) < 0) {
		perror("sigprocmask");
		return 1;
	}
#endif

	for (i = 0; i < 5; i++)
		raise(SIGUSR1);
	printf("连续发了 5 个 SIGUSR1，处理函数已执行 %d 次\n", g_n);

	if (sigpending(&pend) == 0)
		printf("sigpending 里 SIGUSR1: %s\n",
		       sigismember(&pend, SIGUSR1) ? "挂着" : "空");

#ifndef NO_BLOCK
	sigprocmask(SIG_UNBLOCK, &blk, NULL);
	printf("解蔽之后，处理函数共执行 %d 次\n", g_n);
#endif
	return 0;
}
