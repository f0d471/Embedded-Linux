/*
 * 08 篇（进程与信号）实验 4：父进程先结束，子进程归谁
 *
 * 用法：./orphan; sleep 1.5
 * 子进程在父进程退出前后各查一次自己的父进程是谁（PID 和名字）。
 */
#include <stdio.h>
#include <string.h>
#include <unistd.h>

static void show_parent(const char *when)
{
	char path[64], name[64] = "?";
	pid_t pp = getppid();
	FILE *f;

	snprintf(path, sizeof path, "/proc/%d/comm", pp);	/* 进程名在这个文件里 */
	f = fopen(path, "r");
	if (f) {
		if (fgets(name, sizeof name, f))
			name[strcspn(name, "\n")] = '\0';
		fclose(f);
	}
	printf("子 %d %s: 父进程 %d (%s)\n", getpid(), when, pp, name);
	fflush(stdout);
}

int main(void)
{
	pid_t c = fork();

	if (c == 0) {
		show_parent("父进程退出前");
		sleep(1);
		show_parent("父进程退出后");
		_exit(0);
	}
	usleep(200000);		/* 让子进程先打出第一行 */
	printf("父 %d 退出\n", getpid());
	return 0;
}
