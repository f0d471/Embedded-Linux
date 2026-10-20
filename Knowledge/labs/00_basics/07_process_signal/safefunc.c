/*
 * 12 篇（进程与信号）实验：处理函数是一条随时插进来的执行流
 *
 * 用法：./safefunc    （约 3 秒自己结束）
 * main 每轮先 alarm(1) 再 sleep(3)：闹钟一响，sleep 提前返回，
 * 处理函数在 main 的两行打印之间插进来。处理函数里只用 write()
 * （man 7 signal-safety 名单上的函数），不用 printf。
 *
 * 变体：-DSA_RESTART_DEMO 给处理函数加 SA_RESTART。实测行为不变：
 * sleep(3) 底层是 nanosleep，不在 SA_RESTART 的自动重启名单里。
 * 注错：-DNO_HANDLER 不装处理函数，第一个 SIGALRM 按默认动作杀死进程。
 */
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

static volatile sig_atomic_t g_n;

static void on_alrm(int sig)
{
	char msg[] = "  [handler] 闹钟响了第 ? 次，从 main 手里抢过 CPU\n";
	char *q = msg;

	(void)sig;
	g_n++;
	while (*q != '?')
		q++;
	*q = (char)('0' + g_n);
	write(1, msg, sizeof msg - 1);	/* write 在 async-signal-safe 名单上 */
}

int main(void)
{
	struct sigaction sa;
	unsigned long left;
	int i;

	memset(&sa, 0, sizeof sa);
	sa.sa_handler = on_alrm;
	sigemptyset(&sa.sa_mask);
#ifdef SA_RESTART_DEMO
	sa.sa_flags = SA_RESTART;
#endif
#ifdef NO_HANDLER
	(void)sa;	/* 不装，走默认动作：终止进程 */
#else
	sigaction(SIGALRM, &sa, NULL);
#endif

	for (i = 1; i <= 3; i++) {
		printf("main: 第 %d 轮，调用 sleep(3)\n", i);
		fflush(stdout);
		alarm(1);
		left = sleep(3);
		printf("main: sleep(3) 返回，还剩 %lu 秒没睡\n", left);
	}
	printf("main: 结束，处理函数共执行 %d 次\n", g_n);
	return 0;
}
