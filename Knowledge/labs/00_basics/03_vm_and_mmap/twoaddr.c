/* 09 篇第 1 节：两个进程打出同一个地址，内容却不同
 *
 * fork 之后，父子进程各自打印全局变量 g 和堆块 h 的地址与内容：
 * 地址数字一模一样，内容各是各的。
 * 这个地址是虚拟地址，每个进程一张自己的翻译表。
 */
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/wait.h>

int g = 111;            /* 全局变量，已初始化，落在数据段 */

int main(void)
{
	int *h = malloc(sizeof(int));   /* 堆上再要一块 */
	pid_t pid;

	*h = 333;
	printf("fork 之前   &g=%p  g=%d   h=%p  *h=%d\n",
	       (void *)&g, g, (void *)h, *h);
	fflush(stdout);   /* fork 前刷干净，不然缓冲区的内容会被子进程再打一遍 */

	pid = fork();
	if (pid == 0) {
		/* 子进程：把两份都改掉，再看地址和内容 */
		g = 222;
		*h = 444;
		printf("子进程      &g=%p  g=%d   h=%p  *h=%d\n",
		       (void *)&g, g, (void *)h, *h);
		exit(0);   /* 不用 _exit：要它把 stdio 缓冲区刷出去 */
	}
	wait(NULL);
	printf("父进程      &g=%p  g=%d   h=%p  *h=%d\n",
	       (void *)&g, g, (void *)h, *h);
	free(h);
	return 0;
}
