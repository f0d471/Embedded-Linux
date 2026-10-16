/*
 * 08 篇（进程与信号）实验 3：收到 SIGTERM 之后，先花 2 秒收拾再退出
 *
 * 用法：./slowstop &   然后 kill <pid>
 * 模拟一个 GUI 程序：被要求退出时要保存状态、释放显存，不会马上消失。
 *
 * 注错：-DNO_HANDLER 不装 SIGTERM 处理函数，走内核的默认动作。
 */
#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

static volatile sig_atomic_t g_stop;

static void on_term(int sig)
{
	(void)sig;
	g_stop = 1;		/* 处理函数里只记一笔，真正的活回到主循环再干 */
}

int main(void)
{
	struct sigaction sa;

	memset(&sa, 0, sizeof sa);
	sa.sa_handler = on_term;

	/* SIGKILL 不许装处理函数，内核会直接拒绝 */
	if (sigaction(SIGKILL, &sa, NULL) < 0)
		printf("给 SIGKILL 装处理函数: 失败 (%s)\n", strerror(errno));
#ifndef NO_HANDLER
	sigaction(SIGTERM, &sa, NULL);
#endif

	printf("pid=%d 开始干活\n", getpid());
	fflush(stdout);

	while (!g_stop)
		sleep(1);	/* 信号一来 sleep 会提前返回，回到循环检查标志 */

	printf("收到 SIGTERM，开始收拾（2 秒）\n");
	fflush(stdout);
	sleep(2);
	printf("收拾完，退出\n");
	return 0;
}
