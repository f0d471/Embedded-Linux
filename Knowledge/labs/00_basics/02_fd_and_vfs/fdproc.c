/* 每个进程一张 fd 表: 打开一个文件, 列出 /proc/self/fd 里每一格指向哪 */
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>

int main(int argc, char **argv)
{
	const char *path = argc > 1 ? argv[1] : "data.txt";
	char from[64], to[256];
	int fd, i;
	ssize_t n;

	fd = open(path, O_RDONLY);
	if (fd < 0) { perror("open"); return 1; }
	printf("pid=%d open(\"%s\") 得到 fd=%d\n", getpid(), path, fd);

	for (i = 0; i <= fd; i++) {
		snprintf(from, sizeof from, "/proc/self/fd/%d", i);
		n = readlink(from, to, sizeof to - 1);
		if (n < 0) { printf("  fd %d -> (读不出)\n", i); continue; }
		to[n] = 0;
		printf("  fd %d -> %s\n", i, to);
	}

	if (argc > 2) sleep(atoi(argv[2]));   /* 给个窗口, 好让两个进程同时活着 */
	return 0;
}
