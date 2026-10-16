/* VFS：同一段代码，只换路径，下场完全不同 */
#include <stdio.h>
#include <unistd.h>
#include <fcntl.h>
#include <string.h>
#include <errno.h>
#include <sys/ioctl.h>
#include <sys/stat.h>

static void try_path(const char *path)
{
	char buf[8];
	int fd, n;
	struct stat st;
	struct winsize ws;
	const char *kind;

	printf("--- %s ---\n", path);

	fd = open(path, O_RDWR);
	if (fd < 0) {
		printf("  open 失败: %s\n\n", strerror(errno));
		return;
	}

	fstat(fd, &st);
	if      (S_ISREG(st.st_mode))  kind = "普通文件";
	else if (S_ISCHR(st.st_mode))  kind = "字符设备";
	else if (S_ISBLK(st.st_mode))  kind = "块设备";
	else                           kind = "其他";
	printf("  类型      : %s\n", kind);

	n = write(fd, "hello", 5);
	printf("  write 5 字节 -> 返回 %d\n", n);

	/* 终端的 read 会一直等你敲键盘，这里跳过，只演示前后两项 */
	if (isatty(fd)) {
		printf("  read      -> 跳过（终端会一直等你敲键盘）\n");
	} else {
		lseek(fd, 0, SEEK_SET);
		memset(buf, '.', sizeof buf);
		n = read(fd, buf, 5);
		printf("  read  5 字节 -> 返回 %d, 内容 \"%.5s\"\n", n, buf);
	}

	/* 问一个只有终端才懂的问题：你的窗口多大 */
	if (ioctl(fd, TIOCGWINSZ, &ws) == 0)
		printf("  ioctl(TIOCGWINSZ) -> 成功，%d 行 %d 列\n", ws.ws_row, ws.ws_col);
	else
		printf("  ioctl(TIOCGWINSZ) -> 失败: %s\n", strerror(errno));

	close(fd);
	printf("\n");
}

int main(void)
{
	try_path("data.txt");
	try_path("/dev/null");
	try_path("/dev/zero");
	try_path("/dev/tty");
	return 0;
}
