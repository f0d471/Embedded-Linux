/* close-on-exec 记在 fd 这一格上, 不在 struct file 上 */
#include <stdio.h>
#include <unistd.h>
#include <fcntl.h>
#include <string.h>

static void showflags(int fd)
{
	char path[64], line[128];
	FILE *f;

	snprintf(path, sizeof path, "/proc/self/fdinfo/%d", fd);
	f = fopen(path, "r");
	if (!f) return;
	while (fgets(line, sizeof line, f)) {
		if (!strncmp(line, "flags:", 6)) {
			line[strcspn(line, "\n")] = 0;
			printf("fdinfo: fd %d 的 %s\n", fd, line);
		}
	}
	fclose(f);
}

int main(int argc, char **argv)
{
	int fd1, fd2;

	if (argc > 1) {                    /* exec 之后的新程序: 报告 3/4 还在不在 */
		printf("exec 之后: fd 3 %s, fd 4 %s\n",
		       fcntl(3, F_GETFD) >= 0 ? "还在" : "已关闭",
		       fcntl(4, F_GETFD) >= 0 ? "还在" : "已关闭");
		return 0;
	}

	fd1 = open("data.txt", O_RDONLY);
	fd2 = dup(fd1);
	printf("fd1=%d fd2=%d, 两个 fd 指向同一个 struct file\n", fd1, fd2);

	fcntl(fd1, F_SETFD, FD_CLOEXEC);   /* 只给 fd1 这一格打 close-on-exec 标记 */
	printf("fcntl F_GETFD: fd1=%d fd2=%d (1 = 打了标记)\n",
	       fcntl(fd1, F_GETFD), fcntl(fd2, F_GETFD));
	showflags(fd1);
	showflags(fd2);

	fflush(stdout);           /* 缓冲是用户态的, exec 不替我们交出去 */
	execl("/proc/self/exe", argv[0], "dump", NULL);
	perror("execl");
	return 1;
}
