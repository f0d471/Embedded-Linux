/*
 * 12 篇（进程与信号）实验：屏蔽中的信号不产生任何效果，/proc 里看得见
 *
 * 用法：./sigmask
 * 装好 SIGTERM 处理函数 -> 屏蔽 SIGTERM -> raise(SIGTERM) ->
 * 处理函数不执行、sigpending 里挂着 -> 解蔽后立刻执行。
 * 每一步都把 /proc/self/status 里 SigPnd/SigBlk/SigIgn/SigCgt 四行
 * 打出来对照：屏蔽集合、挂起集合、忽略集合、已装处理函数集合，
 * 在内核眼里就是档案里的四张位图。
 *
 * 注错：-DNO_MASK 不屏蔽，raise 当场执行处理函数。
 */
#include <signal.h>
#include <stdio.h>
#include <string.h>

static volatile sig_atomic_t g_got;

static void on_term(int sig)
{
	(void)sig;
	g_got++;
}

static void show_sig(void)
{
	FILE *f = fopen("/proc/self/status", "r");
	char line[256];

	if (!f)
		return;
	while (fgets(line, sizeof line, f)) {
		if (!strncmp(line, "SigPnd:", 7) || !strncmp(line, "SigBlk:", 7) ||
		    !strncmp(line, "SigIgn:", 7) || !strncmp(line, "SigCgt:", 7))
			printf("    %s", line);
	}
	fclose(f);
}

int main(void)
{
	struct sigaction sa;
	sigset_t blk, pend;

	memset(&sa, 0, sizeof sa);
	sa.sa_handler = on_term;
	sigemptyset(&sa.sa_mask);
	sigaction(SIGTERM, &sa, NULL);
	printf("1) 装好 SIGTERM 处理函数之后:\n");
	show_sig();

	sigemptyset(&blk);
	sigaddset(&blk, SIGTERM);
#ifndef NO_MASK
	sigprocmask(SIG_BLOCK, &blk, NULL);
	printf("2) 屏蔽 SIGTERM 之后:\n");
	show_sig();
#endif

	raise(SIGTERM);
	printf("3) raise(SIGTERM) 返回了，处理函数执行次数: %d\n", g_got);
	if (sigpending(&pend) == 0)
		printf("   sigpending 里 SIGTERM: %s\n",
		       sigismember(&pend, SIGTERM) ? "挂着" : "空");
	show_sig();

#ifndef NO_MASK
	sigprocmask(SIG_UNBLOCK, &blk, NULL);
	printf("4) 解蔽之后，处理函数执行次数: %d\n", g_got);
	show_sig();
#endif
	return 0;
}
