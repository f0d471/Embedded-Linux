/* clock_gettime 进不进内核：经 C 库调用（走 vDSO）与强制发系统调用各计一次时。
 * 用法：./vdso N [libc|sys]     循环 N 次，打印每次平均耗时
 *       ./vdso dump FILE        把本进程里的 vDSO 原样存成文件
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <sys/auxv.h>
#include <sys/syscall.h>

static int dump(const char *path)
{
	FILE *maps = fopen("/proc/self/maps", "r");
	char line[256];
	unsigned long lo = 0, hi = 0;
	FILE *f;

	while (maps && fgets(line, sizeof line, maps))
		if (strstr(line, "[vdso]"))
			sscanf(line, "%lx-%lx", &lo, &hi);
	if (maps)
		fclose(maps);
	printf("maps: [vdso] %#lx-%#lx (%lu bytes)\n", lo, hi, hi - lo);
	printf("auxv: AT_SYSINFO_EHDR = %#lx\n", getauxval(AT_SYSINFO_EHDR));
	if (lo == 0 || (f = fopen(path, "wb")) == NULL)
		return 1;
	fwrite((void *)lo, 1, hi - lo, f);
	fclose(f);
	return 0;
}

int main(int argc, char **argv)
{
	long n, i;
	int sys;
	struct timespec t0, t1, ts;
	double ns;

	if (argc > 2 && strcmp(argv[1], "dump") == 0)
		return dump(argv[2]);

	n = argc > 1 ? atol(argv[1]) : 1000000;
	sys = argc > 2 && strcmp(argv[2], "sys") == 0;
	clock_gettime(CLOCK_MONOTONIC, &t0);
	for (i = 0; i < n; i++) {
		if (sys)
			syscall(SYS_clock_gettime, CLOCK_MONOTONIC, &ts);
		else
			clock_gettime(CLOCK_MONOTONIC, &ts);
	}
	clock_gettime(CLOCK_MONOTONIC, &t1);
	ns = ((t1.tv_sec - t0.tv_sec) * 1e9 + (t1.tv_nsec - t0.tv_nsec)) / n;
	printf("%s: %ld calls, %.1f ns/call\n", sys ? "sys" : "libc", n, ns);
	return 0;
}
