/* malloc 一块比物理内存还大的空间，会不会成功
 *
 * 用法: bigmalloc <GiB> [<GiB> ...]
 * 先打印 MemTotal、SwapTotal 和 overcommit 模式，再按参数逐个 malloc。
 * 申请到的块一个都不写、也不释放，所以「累计」是这个进程同时持有的虚拟内存。
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static long field_kb(const char *file, const char *key)
{
	FILE *f = fopen(file, "r");
	char line[256];
	long kb = -1;
	size_t n = strlen(key);

	if (!f) return -1;
	while (fgets(line, sizeof line, f))
		if (!strncmp(line, key, n)) { sscanf(line + n, "%ld", &kb); break; }
	fclose(f);
	return kb;
}

int main(int argc, char **argv)
{
	FILE *f = fopen("/proc/sys/vm/overcommit_memory", "r");
	int mode = -1, i;
	size_t held = 0;

	if (f) { if (fscanf(f, "%d", &mode) != 1) mode = -1; fclose(f); }
	printf("MemTotal %ld KB，SwapTotal %ld KB，overcommit_memory = %d\n",
	       field_kb("/proc/meminfo", "MemTotal:"),
	       field_kb("/proc/meminfo", "SwapTotal:"), mode);

	for (i = 1; i < argc; i++) {
		size_t gib = strtoul(argv[i], NULL, 10);
		void *p = malloc(gib << 30);

		if (p) held += gib;
		printf("malloc(%zu GiB) = %-10s 累计持有 %zu GiB   VmRSS %ld KB\n", gib,
		       p ? "成功" : "失败(NULL)", held,
		       field_kb("/proc/self/status", "VmRSS:"));
	}
	return 0;
}
