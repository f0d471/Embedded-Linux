/* 懒分配：mmap 到底有没有把文件读进内存
 *
 * 三个时刻各量一次「缺页次数」和「实际占用的物理内存」：
 *   1. mmap 之前
 *   2. mmap 之后（还没碰过那块地址）
 *   3. 每页摸一个字节之后
 */
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/resource.h>
#include <sys/time.h>

#define MB   64
#define SIZE ((size_t)MB * 1024 * 1024)

/* 次缺页次数：内核建了一个页表项，但没去读磁盘 */
static long minflt(void)
{
	struct rusage ru;
	getrusage(RUSAGE_SELF, &ru);
	return ru.ru_minflt;
}

/* 本进程真正占用的物理内存，单位 KB */
static long rss_kb(void)
{
	FILE *f = fopen("/proc/self/status", "r");
	char line[128];
	long kb = -1;

	while (fgets(line, sizeof line, f))
		if (!strncmp(line, "VmRSS:", 6)) { sscanf(line + 6, "%ld", &kb); break; }
	fclose(f);
	return kb;
}

static double now_ms(void)
{
	struct timeval tv;
	gettimeofday(&tv, NULL);
	return tv.tv_sec * 1000.0 + tv.tv_usec / 1000.0;
}

int main(int argc, char **argv)
{
	const char *path = argc > 1 ? argv[1] : "big.bin";
	int fd, i;
	char *p;
	long f0, f1, f2, r0, r1, r2;
	double t0, t1;
	long pagesz = sysconf(_SC_PAGESIZE);
	long npages = SIZE / pagesz;
	volatile char sink = 0;

	/* 造一个 64 MiB 的文件 */
	fd = open(path, O_RDWR | O_CREAT | O_TRUNC, 0644);
	if (fd < 0) { perror("open"); return 1; }
	if (ftruncate(fd, SIZE) < 0) { perror("ftruncate"); return 1; }

	printf("文件 %d MiB，页大小 %ld 字节，共 %ld 页\n\n", MB, pagesz, npages);

	f0 = minflt(); r0 = rss_kb();
	printf("[1] mmap 之前     缺页 %-8ld 物理内存 %ld KB\n", f0, r0);

	t0 = now_ms();
	p = mmap(NULL, SIZE, PROT_READ, MAP_SHARED, fd, 0);
	t1 = now_ms();
	if (p == MAP_FAILED) { perror("mmap"); return 1; }

	f1 = minflt(); r1 = rss_kb();
	printf("[2] mmap 之后     缺页 %-8ld 物理内存 %ld KB   （mmap 本身耗时 %.3f ms）\n",
	       f1, r1, t1 - t0);
	printf("    -> 比上一步多了 %ld 次缺页，%ld KB 物理内存\n\n", f1 - f0, r1 - r0);

	/* 每页摸一个字节 */
	t0 = now_ms();
	for (i = 0; i < npages; i++)
		sink += p[(size_t)i * pagesz];
	t1 = now_ms();

	f2 = minflt(); r2 = rss_kb();
	printf("[3] 每页摸一下后  缺页 %-8ld 物理内存 %ld KB   （摸完耗时 %.3f ms）\n",
	       f2, r2, t1 - t0);
	printf("    -> 比上一步多了 %ld 次缺页，%ld KB 物理内存\n", f2 - f1, r2 - r1);
	printf("    -> 摸了 %ld 页，缺页涨了 %ld 次\n", npages, f2 - f1);

	munmap(p, SIZE);
	close(fd);
	unlink(path);
	(void)sink;
	return 0;
}
