/* 09 篇第 7 节：匿名映射，不挂文件的 mmap
 *
 * 映射 1 GiB 匿名内存，量四个时刻：
 *   1. mmap 之前
 *   2. mmap 之后（还没碰过）
 *   3. 每页读一个字节之后
 *   4. 每页写一个字节之后
 * 读和写分开量，因为两者兑现的东西不一样（见正文）。
 */
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/resource.h>

#define MB   1024
#define SIZE ((size_t)MB * 1024 * 1024)

static void faults(long *minor, long *major)
{
	struct rusage ru;
	getrusage(RUSAGE_SELF, &ru);
	*minor = ru.ru_minflt;
	*major = ru.ru_majflt;
}

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

static void show(const char *tag, long mi, long ma, long r,
                 long mi0, long ma0, long r0)
{
	printf("[%s] 次缺页 %-8ld 主缺页 %-6ld 物理内存 %ld KB\n", tag, mi, ma, r);
	printf("    -> 多了 %ld 次次缺页、%ld 次主缺页，%ld KB 物理内存\n",
	       mi - mi0, ma - ma0, r - r0);
}

int main(void)
{
	char *p;
	long mi0, mi1, mi2, mi3, ma0, ma1, ma2, ma3, r0, r1, r2, r3;
	long pagesz = sysconf(_SC_PAGESIZE);
	long npages = SIZE / pagesz;
	long i;
	volatile char sink = 0;

	printf("匿名映射 %d MiB，页大小 %ld 字节，共 %ld 页\n\n", MB, pagesz, npages);

	faults(&mi0, &ma0); r0 = rss_kb();
	show("1 mmap 之前    ", mi0, ma0, r0, mi0, ma0, r0);

	/* MAP_ANONYMOUS：不挂文件，fd 传 -1，offset 传 0 */
	p = mmap(NULL, SIZE, PROT_READ | PROT_WRITE,
	         MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
	if (p == MAP_FAILED) { perror("mmap"); return 1; }

	faults(&mi1, &ma1); r1 = rss_kb();
	show("2 mmap 之后    ", mi1, ma1, r1, mi0, ma0, r0);

	/* 只读：每页读一个字节 */
	for (i = 0; i < npages; i++)
		sink += p[i * pagesz];

	faults(&mi2, &ma2); r2 = rss_kb();
	show("3 每页读一下后 ", mi2, ma2, r2, mi1, ma1, r1);

	/* 再写：每页写一个字节 */
	for (i = 0; i < npages; i++)
		p[i * pagesz] = (char)i;

	faults(&mi3, &ma3); r3 = rss_kb();
	show("4 每页写一下后 ", mi3, ma3, r3, mi2, ma2, r2);

	munmap(p, SIZE);
	(void)sink;
	return 0;
}
