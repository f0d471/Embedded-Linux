/*
 * 插上显示器后用的测试图：运行时读分辨率，画 8 条竖彩条，四周一圈 1 像素白边框。
 * 彩条从左到右：红 绿 蓝 白 黄 青 品红 黑。
 * 按 var.red/green/blue 的 offset 拼颜色，不假设 xRGB。
 */
#include <fcntl.h>
#include <linux/fb.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <unistd.h>

static struct fb_var_screeninfo var;
static struct fb_fix_screeninfo fix;
static unsigned char *fb;

static unsigned pack(unsigned rgb888)
{
	unsigned r = (rgb888 >> 16) & 0xff, g = (rgb888 >> 8) & 0xff, b = rgb888 & 0xff;
	r >>= 8 - var.red.length;
	g >>= 8 - var.green.length;
	b >>= 8 - var.blue.length;
	return (r << var.red.offset) | (g << var.green.offset) | (b << var.blue.offset);
}

static void put(unsigned x, unsigned y, unsigned rgb888)
{
	unsigned char *p = fb + y * fix.line_length + x * (var.bits_per_pixel / 8);
	unsigned v = pack(rgb888);
	if (var.bits_per_pixel == 16)
		*(unsigned short *)p = v;
	else
		*(unsigned int *)p = v;
}

int main(void)
{
	int fd = open("/dev/fb0", O_RDWR);
	if (fd < 0 || ioctl(fd, FBIOGET_VSCREENINFO, &var) || ioctl(fd, FBIOGET_FSCREENINFO, &fix)) {
		perror("fb0");
		return 1;
	}
	if (var.bits_per_pixel != 16 && var.bits_per_pixel != 32) {
		printf("不支持 %ubpp\n", var.bits_per_pixel);
		return 1;
	}
	size_t size = (size_t)fix.line_length * var.yres;
	fb = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
	if (fb == MAP_FAILED) {
		perror("mmap");
		return 1;
	}
	const unsigned bar[8] = { 0xFF0000, 0x00FF00, 0x0000FF, 0xFFFFFF, 0xFFFF00, 0x00FFFF, 0xFF00FF, 0x000000 };
	for (unsigned y = 0; y < var.yres; y++)
		for (unsigned x = 0; x < var.xres; x++) {
			int edge = x == 0 || y == 0 || x == var.xres - 1 || y == var.yres - 1;
			put(x, y, edge ? 0xFFFFFF : bar[x * 8 / var.xres]);
		}
	printf("画完: %ux%u %ubpp line_length=%u\n", var.xres, var.yres, var.bits_per_pixel, fix.line_length);
	munmap(fb, size);
	close(fd);
	return 0;
}
