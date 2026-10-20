/* fcntl(F_SETFL, O_APPEND) 改的是 struct file: dup 出来的 fd 跟着一起变 */
#include <stdio.h>
#include <unistd.h>
#include <fcntl.h>
#include <string.h>

static void showflags(int fd, const char *tag)
{
	char path[64], line[128];
	FILE *f;

	snprintf(path, sizeof path, "/proc/self/fdinfo/%d", fd);
	f = fopen(path, "r");
	if (!f) { printf("  fd %d (%s): 打不开\n", fd, tag); return; }
	printf("  fd %d (%-4s):", fd, tag);
	while (fgets(line, sizeof line, f)) {
		if (!strncmp(line, "pos:", 4) || !strncmp(line, "flags:", 6)) {
			line[strcspn(line, "\n")] = 0;
			printf("  %s", line);
		}
	}
	printf("\n");
	fclose(f);
}

int main(void)
{
	int fd1, fd2;

	fd1 = open("flag.txt", O_WRONLY | O_CREAT | O_TRUNC, 0644);
	fd2 = dup(fd1);
	write(fd1, "AAAAA", 5);          /* 先写 5 字节, f_pos = 5 */

	printf("[F_SETFL 之前]\n");
	showflags(fd1, "open"); showflags(fd2, "dup");

	fcntl(fd1, F_SETFL, O_APPEND);     /* 只对 fd1 说这一句话 */
	printf("\n[只对 fd1 做 F_SETFL O_APPEND 之后]\n");
	showflags(fd1, "open"); showflags(fd2, "dup");

	lseek(fd2, 0, SEEK_SET);           /* 用 fd2 把位置拨回 0 */
	write(fd2, "Z", 1);                /* 再经 fd2 写 1 字节 */
	printf("\n[fd2 拨回 0 后写 'Z' 之后]\n");
	showflags(fd1, "open"); showflags(fd2, "dup");

	return 0;
}
