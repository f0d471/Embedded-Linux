/* MAP_SHARED 与 MAP_PRIVATE：写进去的东西去了哪 */
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/wait.h>

static void try_flag(const char *path, int flag, const char *name)
{
	int fd = open(path, O_RDWR | O_CREAT | O_TRUNC, 0644);
	char *p;
	char buf[16] = {0};

	write(fd, "AAAAAAAAAA", 10);          /* 文件初始内容 10 个 A */

	p = mmap(NULL, 10, PROT_READ | PROT_WRITE, flag, fd, 0);
	if (p == MAP_FAILED) { perror("mmap"); return; }

	memcpy(p, "BBBBB", 5);                /* 往映射区写 5 个 B */

	fflush(stdout);   /* fork 前必须刷干净，否则缓冲区会被子进程连同复制、再打一遍 */
	if (fork() == 0) {                    /* 子进程也映射同一个文件，看得见吗 */
		char *q = mmap(NULL, 10, PROT_READ, MAP_SHARED, fd, 0);
		printf("  %-12s 另一个进程映射同一文件看到: %.10s\n", name, q);
		exit(0);
	}
	wait(NULL);

	msync(p, 10, MS_SYNC);
	munmap(p, 10);

	lseek(fd, 0, SEEK_SET);
	read(fd, buf, 10);
	printf("  %-12s 文件里最终存的是          : %.10s\n\n", name, buf);
	close(fd);
}

int main(int argc, char **argv)
{
	const char *dir = argc > 1 ? argv[1] : ".";
	char p1[256], p2[256];

	snprintf(p1, sizeof p1, "%s/sh.bin", dir);
	snprintf(p2, sizeof p2, "%s/pv.bin", dir);

	printf("往映射区写 5 个 B（文件原本是 10 个 A）：\n\n");
	try_flag(p1, MAP_SHARED,  "MAP_SHARED");
	try_flag(p2, MAP_PRIVATE, "MAP_PRIVATE");
	unlink(p1); unlink(p2);
	return 0;
}
