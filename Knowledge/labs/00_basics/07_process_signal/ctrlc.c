/*
 * 12 篇（进程与信号）实验：Ctrl+C 到达程序的不是字符，是 SIGINT
 *
 * 用法一（默认）：./ctrlc
 *   装好 SIGINT 处理函数，收满 2 次自己退出。在终端里按两次 Ctrl+C；
 *   不靠终端、用伪终端喂字节 0x03 的等效做法：
 *     { sleep 0.5; printf '\003'; sleep 0.4; printf '\003'; sleep 0.8; } |
 *         script -qec ./ctrlc /dev/null
 *   script 给程序开一个伪终端，0x03 经行规程变成 SIGINT 发给前台进程组。
 *
 * 用法二：./ctrlc raw
 *   不装处理函数，逐字节读 stdin 打十六进制。先 stty -isig 关掉行规程的
 *   信号功能再喂 0x03，它就退回成一个普通字节：
 *     { sleep 0.5; printf '\003\n'; sleep 0.8; } |
 *         script -qec 'stty -isig; ./ctrlc raw' /dev/null
 */
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

static volatile sig_atomic_t g_n;

static void on_int(int sig)
{
	(void)sig;
	g_n++;
}

static int mode_default(void)
{
	struct sigaction sa;
	int seen = 0;

	memset(&sa, 0, sizeof sa);
	sa.sa_handler = on_int;
	sigemptyset(&sa.sa_mask);
	sigaction(SIGINT, &sa, NULL);
	printf("ctrlc: 装好了 SIGINT 处理函数，等 2 次\n");
	fflush(stdout);
	while (g_n < 2) {
		pause();
		for (; seen < g_n; seen++)
			printf("ctrlc: 收到第 %d 次 SIGINT\n", seen + 1);
		fflush(stdout);
	}
	printf("ctrlc: 两次都收到，正常退出\n");
	return 0;
}

static int mode_raw(void)
{
	unsigned char buf[64];
	ssize_t n;
	int i;

	printf("ctrlc raw: 不装处理函数，stdin 来什么读什么\n");
	fflush(stdout);
	n = read(0, buf, sizeof buf);
	if (n <= 0) {
		printf("ctrlc raw: 什么都没读到\n");
		return 1;
	}
	printf("ctrlc raw: 读到 %zd 个字节:", n);
	for (i = 0; i < n; i++)
		printf(" %02x", buf[i]);
	printf("\n");
	return 0;
}

int main(int argc, char **argv)
{
	if (argc > 1 && !strcmp(argv[1], "raw"))
		return mode_raw();
	return mode_default();
}
