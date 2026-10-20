/* 09 篇第 4 节：映射一个 8 MiB 文件，然后打印自己的 /proc/self/maps
 *
 * 用法: mapshow <要映射的文件路径>
 */
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mman.h>

#define SIZE (8 * 1024 * 1024)

int main(int argc, char **argv)
{
	const char *path = argc > 1 ? argv[1] : "map8.bin";
	int fd;
	char *p;
	FILE *f;
	char line[512];

	fd = open(path, O_RDWR | O_CREAT | O_TRUNC, 0644);
	if (fd < 0) { perror("open"); return 1; }
	if (ftruncate(fd, SIZE) < 0) { perror("ftruncate"); return 1; }

	p = mmap(NULL, SIZE, PROT_READ, MAP_SHARED, fd, 0);
	if (p == MAP_FAILED) { perror("mmap"); return 1; }

	printf("mmap 返回的地址: %p（在下面的 maps 里找包含它的那一行）\n\n", (void *)p);

	f = fopen("/proc/self/maps", "r");
	if (!f) { perror("fopen"); return 1; }
	while (fgets(line, sizeof line, f))
		fputs(line, stdout);
	fclose(f);

	munmap(p, SIZE);
	close(fd);
	unlink(path);
	return 0;
}
