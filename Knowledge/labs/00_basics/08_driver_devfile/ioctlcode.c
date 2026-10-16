/*
 * 09 篇（驱动与设备文件）实验：ioctl 请求码里装了什么
 *
 * 用法：./ioctlcode [/dev/rtc0]
 * 先把几个请求码拆成 方向/类型/序号/大小 四段；
 * 给了路径就再真发两次 ioctl：一次发它认识的，一次发它不认识的。
 */
#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <linux/fb.h>
#include <linux/rtc.h>
#include <sys/ioctl.h>

static void show(const char *name, unsigned long req, size_t real)
{
	unsigned long type = _IOC_TYPE(req);

	printf("%-20s 0x%08lx  方向=%lu  类型=0x%02lx'%c'  序号=%-3lu  大小=%-3lu  sizeof=%zu\n",
	       name, req, _IOC_DIR(req), type, isprint((int)type) ? (int)type : '.',
	       _IOC_NR(req), _IOC_SIZE(req), real);
}

int main(int argc, char **argv)
{
	show("RTC_RD_TIME", RTC_RD_TIME, sizeof(struct rtc_time));
	show("TIOCGWINSZ", TIOCGWINSZ, sizeof(struct winsize));
	show("FBIOGET_VSCREENINFO", FBIOGET_VSCREENINFO, sizeof(struct fb_var_screeninfo));
	show("FBIOGET_FSCREENINFO", FBIOGET_FSCREENINFO, sizeof(struct fb_fix_screeninfo));

	if (argc > 1) {
		struct rtc_time t;
		struct fb_var_screeninfo var;
		int fd = open(argv[1], O_RDONLY);

		if (fd < 0) {
			printf("open %s 失败: %s\n", argv[1], strerror(errno));
			return 1;
		}
		if (ioctl(fd, RTC_RD_TIME, &t) == 0)
			printf("ioctl(RTC_RD_TIME)         成功: %04d-%02d-%02d %02d:%02d:%02d (UTC)\n",
			       t.tm_year + 1900, t.tm_mon + 1, t.tm_mday, t.tm_hour, t.tm_min, t.tm_sec);
		else
			printf("ioctl(RTC_RD_TIME)         失败: %s\n", strerror(errno));
		if (ioctl(fd, FBIOGET_VSCREENINFO, &var) == 0)
			printf("ioctl(FBIOGET_VSCREENINFO) 成功\n");
		else
			printf("ioctl(FBIOGET_VSCREENINFO) 失败: %s\n", strerror(errno));
		close(fd);
	}
	return 0;
}
