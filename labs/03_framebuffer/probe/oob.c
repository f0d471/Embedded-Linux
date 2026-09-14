/*
 * 描点函数不查边界时，越界的点落到哪里。
 *   ./oob 设备或文件 wrapx     在 (xres, 100) 画一个红点，然后找它实际落在哪
 *   ./oob 设备或文件 beyondy   在 (0, yres) 画一个红点（映射区外面）
 * 文件不存在时按 1024x600x32 造一个假显存。
 */
#include <fcntl.h>
#include <linux/fb.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <unistd.h>

int main(int argc, char **argv)
{
	if (argc != 3)
		return 2;
	unsigned xres = 1024, yres = 600, bpp = 32;
	int fd = open(argv[1], O_RDWR | O_CREAT, 0644);
	if (fd < 0) {
		perror("open");
		return 1;
	}
	struct fb_var_screeninfo var;
	if (ioctl(fd, FBIOGET_VSCREENINFO, &var) == 0) {
		xres = var.xres, yres = var.yres, bpp = var.bits_per_pixel;
	} else if (ftruncate(fd, (off_t)xres * yres * 4) < 0) {
		perror("ftruncate");
		return 1;
	}
	unsigned pw = bpp / 8, lw = xres * pw, size = xres * yres * pw;
	unsigned char *base = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
	if (base == MAP_FAILED) {
		perror("mmap");
		return 1;
	}
	printf("映射 %u 字节, 地址 %p..%p\n", size, (void *)base, (void *)(base + size));
	fflush(stdout);

	if (strcmp(argv[2], "wrapx") == 0) {
		memset(base, 0, size);
		unsigned x = xres, y = 100;
		*(unsigned int *)(base + y * lw + x * pw) = 0x00FF0000;
		for (unsigned off = 0; off < size; off += pw)
			if (*(unsigned int *)(base + off) == 0x00FF0000)
				printf("画在 (%u,%u), 实际落在 (%u,%u)\n", x, y, off % lw / pw, off / lw);
	} else {
		unsigned x = 0, y = yres;
		printf("写 (%u,%u) -> 地址 %p\n", x, y, (void *)(base + y * lw + x * pw));
		fflush(stdout);
		*(unsigned int *)(base + y * lw + x * pw) = 0x00FF0000;
		printf("写完了, 没有崩\n");
	}
	munmap(base, size);
	close(fd);
	return 0;
}
