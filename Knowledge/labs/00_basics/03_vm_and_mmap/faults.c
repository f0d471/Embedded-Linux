/* 09 篇第 2.5 节：把「一次缺页顺手干多少活」拆开量
 *
 * 用法: faults <path> <mode> <npages>
 *   mode 0  新建稀疏文件（数据不在页缓存），mmap 后逐页摸
 *   mode 1  先把每一页都写过（数据已在页缓存），再 mmap 逐页摸
 *   mode 2  同 mode 1，但摸完第 0 页先打印此刻已在内存的页，
 *           看一次缺页顺手把多少页的表项建好了
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <unistd.h>
#include <fcntl.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/resource.h>

static void flt(long *mi, long *ma)
{
	struct rusage ru;
	getrusage(RUSAGE_SELF, &ru);
	*mi = ru.ru_minflt;
	*ma = ru.ru_majflt;
}

/* /proc/self/pagemap 每 8 字节对应一页，最高位是「在不在物理内存里」 */
static int present(int pm, char *base, long i)
{
	uint64_t e = 0;
	pread(pm, &e, 8, (off_t)((uintptr_t)(base + i * 4096) / 4096) * 8);
	return (int)((e >> 63) & 1);
}

int main(int argc, char **argv)
{
	const char *path = argv[1];
	(void)argc;
	int mode = atoi(argv[2]);
	long npages = atol(argv[3]);
	int fd, pm = -1;
	char *p;
	long i, a, b, c, d, tmi = 0, tma = 0;
	int shown = 0;
	volatile char sink = 0;

	fd = open(path, O_RDWR | O_CREAT | O_TRUNC, 0644);
	if (fd < 0) { perror("open"); return 1; }
	if (ftruncate(fd, npages * 4096L) < 0) { perror("ftruncate"); return 1; }

	if (mode >= 1) {	/* 把每一页都写过，数据就进了页缓存 */
		char buf[4096];
		memset(buf, 'x', sizeof buf);
		for (i = 0; i < npages; i++)
			if (pwrite(fd, buf, 4096, i * 4096L) != 4096) { perror("pwrite"); return 1; }
	}

	p = mmap(NULL, npages * 4096L, PROT_READ, MAP_SHARED, fd, 0);
	if (p == MAP_FAILED) { perror("mmap"); return 1; }
	if (mode == 2)
		pm = open("/proc/self/pagemap", O_RDONLY);

	/* 摸第 0 页 */
	flt(&a, &b);
	sink += p[0];
	flt(&c, &d);
	printf("摸第 0 页：%s缺页\n", d > b ? "主" : (c > a ? "次" : "无"));
	tmi += c - a; tma += d - b;

	if (mode == 2) {
		long last = -1, j;
		printf("摸过第 0 页后，已在内存的页: ");
		for (j = 0; j < npages; j++)
			if (present(pm, p, j)) last = j; else break;
		for (j = 0; j <= last; j++)
			printf("%ld ", j);
		printf("\n（一次缺页顺手建好了 %ld 页的表项）\n", last + 1);
	}

	printf("之后缺页发生在页: ");
	for (i = 1; i < npages; i++) {
		flt(&a, &b);
		sink += p[i * 4096];
		flt(&c, &d);
		if (c != a || d != b) {
			if (shown < 12) { printf("%ld(%s) ", i, d > b ? "M" : "m"); shown++; }
			tmi += c - a; tma += d - b;
		}
	}
	if (tmi + tma - 1 > 12) printf("...");
	printf("\n共 %ld 页：次缺页 %ld，主缺页 %ld\n", npages, tmi, tma);

	munmap(p, npages * 4096L);
	close(fd);
	unlink(path);
	(void)sink;
	return 0;
}
