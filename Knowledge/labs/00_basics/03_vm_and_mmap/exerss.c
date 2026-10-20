/* 程序自己的那几段映射，有多少真的进了物理内存
 *
 * 用法: exerss
 * 读 /proc/self/smaps，把路径等于本程序文件的那几段的 Size 与 Rss 加起来，
 * 和程序文件本身的字节数对照。静态链接编出来更明显：gcc -static exerss.c -o exerss_static
 */
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>

int main(void)
{
	char exe[512], line[1024], cur[512] = "";
	long size_kb = 0, rss_kb = 0, v;
	ssize_t n = readlink("/proc/self/exe", exe, sizeof exe - 1);
	struct stat st;
	FILE *f;

	if (n < 0) { perror("readlink"); return 1; }
	exe[n] = 0;
	if (stat(exe, &st) < 0) { perror("stat"); return 1; }

	f = fopen("/proc/self/smaps", "r");
	if (!f) { perror("fopen"); return 1; }
	while (fgets(line, sizeof line, f)) {
		char path[512] = "";
		/* 段头那一行形如 "起-止 权限 偏移 设备 inode 路径" */
		if (sscanf(line, "%*s %*s %*s %*s %*s %511s", path) == 1 && strchr(line, '-') == line + strcspn(line, "-") && path[0] == '/') {
			strcpy(cur, path);
			continue;
		}
		if (!strncmp(line, "Size:", 5) && !strcmp(cur, exe) && sscanf(line + 5, "%ld", &v) == 1) size_kb += v;
		if (!strncmp(line, "Rss:", 4) && !strcmp(cur, exe) && sscanf(line + 4, "%ld", &v) == 1) rss_kb += v;
		if (!strncmp(line, "VmFlags:", 8)) cur[0] = 0;
	}
	fclose(f);

	printf("程序文件 %ld 字节（%ld KB）\n", (long)st.st_size, (long)(st.st_size + 1023) / 1024);
	printf("它的几段映射合计 Size %ld KB，Rss %ld KB\n", size_kb, rss_kb);
	return 0;
}
