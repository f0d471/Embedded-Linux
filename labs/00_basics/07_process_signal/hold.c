/*
 * 08 篇（进程与信号）实验 1：一个什么都不干、只等信号的程序
 *
 * 用法：./hold &
 * 打印自己的 PID 和父进程 PID，然后睡到有信号来为止。
 */
#include <stdio.h>
#include <unistd.h>

int main(void)
{
	printf("pid=%d ppid=%d\n", getpid(), getppid());
	fflush(stdout);		/* 输出重定向到文件时是全缓冲，不刷就看不到 */
	pause();		/* 睡到有信号来；默认动作会直接结束进程 */
	return 0;
}
