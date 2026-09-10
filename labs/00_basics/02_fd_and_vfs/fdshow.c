/* fd 是下标不是指针：让程序自己把自己的三张表打出来 */
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <string.h>

/* 把 /proc/self/fdinfo/<fd> 的 pos 和 flags 打出来 */
static void show(int fd, const char *tag)
{
	char path[64], line[128];
	FILE *f;

	snprintf(path, sizeof path, "/proc/self/fdinfo/%d", fd);
	f = fopen(path, "r");
	if (!f) { printf("  fd %d (%s): 打不开 %s\n", fd, tag, path); return; }

	printf("  fd %-2d (%-10s)", fd, tag);
	while (fgets(line, sizeof line, f)) {
		line[strcspn(line, "\n")] = 0;
		if (!strncmp(line, "pos:", 4) || !strncmp(line, "flags:", 6))
			printf("  %s", line);
	}
	printf("\n");
	fclose(f);
}

int main(void)
{
	int fd1, fd2, fd3;
	char c;

	fd1 = open("data.txt", O_RDONLY);
	fd2 = open("data.txt", O_RDONLY);   /* 同一个文件，第二次 open */
	fd3 = dup(fd1);                     /* 复制 fd1 */

	printf("open 返回的编号: fd1=%d fd2=%d fd3=%d\n\n", fd1, fd2, fd3);

	printf("[读之前] 三个 fd 的位置：\n");
	show(fd1, "open 1"); show(fd2, "open 2"); show(fd3, "dup fd1");

	read(fd1, &c, 1);                   /* 只从 fd1 读一个字节 */
	printf("\n从 fd1 读了 1 个字节（读到 '%c'）\n\n", c);

	printf("[读之后] 三个 fd 的位置：\n");
	show(fd1, "open 1"); show(fd2, "open 2"); show(fd3, "dup fd1");

	return 0;
}
