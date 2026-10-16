/*
 * 08 篇（进程与信号）实验 2：用三种方式结束自己
 *
 * 用法：./child exit N    调 exit(N) 正常退出
 *       ./child segv      往 0 地址写，CPU 报异常，内核发 SIGSEGV
 *       ./child term      自己给自己发 SIGTERM
 */
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv)
{
	if (argc < 2) {
		fprintf(stderr, "用法: %s exit N | segv | term\n", argv[0]);
		return 2;
	}
	if (!strcmp(argv[1], "exit"))
		exit(argc > 2 ? atoi(argv[2]) : 0);
	if (!strcmp(argv[1], "segv"))
		*(volatile int *)0 = 1;
	if (!strcmp(argv[1], "term"))
		raise(SIGTERM);
	fprintf(stderr, "不认识的方式: %s\n", argv[1]);
	return 2;
}
