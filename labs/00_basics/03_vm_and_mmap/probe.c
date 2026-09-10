/* 探路：mmap 和稀疏文件在这个目录能不能正常做 */
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>

int main(int argc, char **argv)
{
	const char *dir = argc > 1 ? argv[1] : ".";
	char path[256];
	int fd;
	char *p;
	struct stat st;

	snprintf(path, sizeof path, "%s/probe.bin", dir);

	fd = open(path, O_RDWR | O_CREAT | O_TRUNC, 0644);
	if (fd < 0) { perror("open"); return 1; }
	ftruncate(fd, 8192);

	p = mmap(NULL, 8192, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
	if (p == MAP_FAILED) { printf("%-12s mmap 失败: %m\n", dir); close(fd); return 1; }
	p[0] = 'X';
	msync(p, 8192, MS_SYNC);
	munmap(p, 8192);

	lseek(fd, 0, SEEK_SET);
	char c = 0;
	read(fd, &c, 1);
	printf("%-12s MAP_SHARED 写回: %s\n", dir, c == 'X' ? "有效" : "无效");
	close(fd);

	/* 稀疏文件 */
	snprintf(path, sizeof path, "%s/sparse.bin", dir);
	fd = open(path, O_RDWR | O_CREAT | O_TRUNC, 0644);
	lseek(fd, 1024 * 1024, SEEK_SET);
	write(fd, "END", 3);
	fstat(fd, &st);
	printf("%-12s 稀疏文件: 逻辑 %ld 字节, 占盘 %ld 个 512 字节块 (%s)\n",
	       dir, (long)st.st_size, (long)st.st_blocks,
	       st.st_blocks * 512 < st.st_size / 2 ? "空洞有效" : "空洞被填实");
	close(fd);
	return 0;
}
