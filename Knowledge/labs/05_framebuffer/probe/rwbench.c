/*
 * 显存的读和写分开计时：同样 2.4 MiB，一次 memcpy。
 *   写：malloc 的普通内存 -> 显存
 *   读：显存 -> malloc 的普通内存
 *   对照：普通内存 -> 普通内存
 * 每项 5 轮取最短。
 */
#include <fcntl.h>
#include <linux/fb.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

static double now_ms(void)
{
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return ts.tv_sec * 1e3 + ts.tv_nsec / 1e6;
}

int main(void)
{
	int fd = open("/dev/fb0", O_RDWR);
	struct fb_var_screeninfo var;
	struct fb_fix_screeninfo fix;
	if (fd < 0 || ioctl(fd, FBIOGET_VSCREENINFO, &var) || ioctl(fd, FBIOGET_FSCREENINFO, &fix)) {
		perror("fb0");
		return 1;
	}
	size_t size = (size_t)fix.line_length * var.yres;
	unsigned char *fb = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
	unsigned char *a = malloc(size), *b = malloc(size);
	if (fb == MAP_FAILED || !a || !b) {
		perror("mmap/malloc");
		return 1;
	}
	memset(a, 0x80, size);
	memset(b, 0x00, size);

	const char *name[3] = { "写 内存->显存", "读 显存->内存", "对照 内存->内存" };
	double best[3] = { 1e9, 1e9, 1e9 };
	for (int round = 0; round < 5; round++) {
		for (int m = 0; m < 3; m++) {
			double t0 = now_ms();
			if (m == 0)
				memcpy(fb, a, size);
			else if (m == 1)
				memcpy(b, fb, size);
			else
				memcpy(b, a, size);
			double t = now_ms() - t0;
			if (t < best[m])
				best[m] = t;
		}
	}
	for (int m = 0; m < 3; m++)
		printf("%-22s %7.1f ms  %6.1f MiB/s\n", name[m], best[m], size / 1048576.0 / (best[m] / 1e3));
	printf("读回来的内容和写进去的%s\n", memcmp(a, b, size) == 0 ? "一致" : "不一致");

	munmap(fb, size);
	free(a);
	free(b);
	close(fd);
	return 0;
}
