/*
 * 09 篇（驱动与设备文件）实验：同一套 open/read/write，对各种文件各试一遍
 *
 * 用法：./devopen 路径...
 * 每个路径打一行：它是什么类型、设备号是多少、open/read/write 各得到什么。
 */
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/sysmacros.h>

/* 把 errno 数字翻译成宏名，方便和手册对照 */
static const char *ename(int e)
{
	switch (e) {
	case ENOENT:	return "ENOENT";
	case EACCES:	return "EACCES";
	case ENXIO:	return "ENXIO";
	case ENODEV:	return "ENODEV";
	case ENOSPC:	return "ENOSPC";
	case ENOTTY:	return "ENOTTY";
	case EINVAL:	return "EINVAL";
	case EPERM:	return "EPERM";
	default:	return "?";
	}
}

int main(int argc, char **argv)
{
	for (int i = 1; i < argc; i++) {
		const char *p = argv[i];
		struct stat st;
		char buf[8];
		int fd, n;

		printf("%-10s ", p);
		if (stat(p, &st) < 0) {
			printf("stat 失败 %s\n", ename(errno));
			continue;
		}
		if (S_ISCHR(st.st_mode))	/* 设备号藏在 st_rdev 里，大小那一栏没有意义 */
			printf("字符设备 %3u,%-3u  ", major(st.st_rdev), minor(st.st_rdev));
		else if (S_ISREG(st.st_mode))
			printf("普通文件 %4lld字节  ", (long long)st.st_size);
		else
			printf("其他类型           ");

		fd = open(p, O_RDWR);
		if (fd < 0) {
			printf("open 失败 %s (%s)\n", ename(errno), strerror(errno));
			continue;
		}

		n = read(fd, buf, sizeof buf);
		if (n < 0) {
			printf("read 失败 %s  ", ename(errno));
		} else {
			printf("read=%d [", n);
			for (int k = 0; k < n; k++)
				printf("%02x", (unsigned char)buf[k]);
			printf("]  ");
		}

		n = write(fd, "A", 1);
		if (n < 0)
			printf("write 失败 %s\n", ename(errno));
		else
			printf("write=%d\n", n);
		close(fd);
	}
	return 0;
}
