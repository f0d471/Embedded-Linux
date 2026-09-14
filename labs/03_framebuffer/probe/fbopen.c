/* 对每个路径做两步：open，再 ioctl(FBIOGET_VSCREENINFO)，把失败的 errno 打出来 */
#include <errno.h>
#include <fcntl.h>
#include <linux/fb.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

int main(int argc, char **argv)
{
	for (int i = 1; i < argc; i++) {
		const char *path = argv[i];
		int fd = open(path, O_RDWR);
		if (fd < 0) {
			printf("%-22s open  失败 errno=%-2d %s\n", path, errno, strerror(errno));
			continue;
		}
		struct fb_var_screeninfo var;
		if (ioctl(fd, FBIOGET_VSCREENINFO, &var) < 0)
			printf("%-22s ioctl 失败 errno=%-2d %s\n", path, errno, strerror(errno));
		else
			printf("%-22s ioctl 成功 %ux%u %ubpp\n", path, var.xres, var.yres, var.bits_per_pixel);
		close(fd);
	}
	return 0;
}
