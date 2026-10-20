/* 映射区出界的五种情形，各挨什么信号
 *
 * 用法: oob <数据目录> <情形>
 *   eof    文件 3 字节、映射 8192 字节，读 p[5000]：映射在，文件不够长
 *   trunc  文件 8192 字节、映射 8192 字节，先读 p[5000]，再把文件截成 3 字节后重读
 *   unmap  映射 8192 字节，munmap 掉第二页，再读 p[5000]：那一页的登记没了
 *   prot   PROT_READ 映射，往 p[0] 写：登记在，权限不许
 *   close  映射之后 close(fd)，再读 p[0]：关 fd 不取消映射
 *
 * 信号处理函数只报告信号名、si_code 和出错地址相对映射起点的偏移，
 * 然后恢复默认动作并返回；出错的那条指令重新执行，进程按默认动作终止，
 * 退出码仍是 128 + 信号编号。
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <signal.h>
#include <sys/mman.h>

static char *base;

/* 处理函数里只能用 write 这类异步信号安全的函数，数字自己转 */
static void put(const char *s) { write(1, s, strlen(s)); }
static void putnum(long v)
{
	char b[24];
	int i = sizeof b;
	int neg = v < 0;

	if (neg) v = -v;
	do { b[--i] = '0' + v % 10; v /= 10; } while (v);
	if (neg) b[--i] = '-';
	write(1, b + i, sizeof b - i);
}

static void on_fault(int sig, siginfo_t *si, void *ctx)
{
	(void)ctx;
	put(sig == SIGBUS ? "收到 SIGBUS" : "收到 SIGSEGV");
	put("  si_code=");
	putnum(si->si_code);
	if (sig == SIGBUS && si->si_code == BUS_ADRERR) put("(BUS_ADRERR)");
	if (sig == SIGSEGV && si->si_code == SEGV_MAPERR) put("(SEGV_MAPERR)");
	if (sig == SIGSEGV && si->si_code == SEGV_ACCERR) put("(SEGV_ACCERR)");
	put("  出错地址 = 映射起点 + ");
	putnum((char *)si->si_addr - base);
	put("\n");
	signal(sig, SIG_DFL);
}

static int make_file(const char *path, long len)
{
	int fd = open(path, O_RDWR | O_CREAT | O_TRUNC, 0644);

	if (fd < 0) { perror("open"); exit(1); }
	if (write(fd, "abc", 3) != 3) { perror("write"); exit(1); }
	if (len > 3 && ftruncate(fd, len) < 0) { perror("ftruncate"); exit(1); }
	return fd;
}

int main(int argc, char **argv)
{
	const char *dir = argc > 1 ? argv[1] : ".";
	const char *mode = argc > 2 ? argv[2] : "eof";
	char path[256];
	struct sigaction sa;
	volatile char *p;
	int fd;

	memset(&sa, 0, sizeof sa);
	sa.sa_sigaction = on_fault;
	sa.sa_flags = SA_SIGINFO;
	sigaction(SIGBUS, &sa, NULL);
	sigaction(SIGSEGV, &sa, NULL);

	snprintf(path, sizeof path, "%s/oob.bin", dir);
	fd = make_file(path, strcmp(mode, "eof") == 0 ? 3 : 8192);

	base = mmap(NULL, 8192, strcmp(mode, "prot") == 0 ? PROT_READ : PROT_READ | PROT_WRITE,
	            MAP_SHARED, fd, 0);
	if (base == MAP_FAILED) { perror("mmap"); return 1; }
	p = base;
	unlink(path);   /* 映射还在，文件名删了也不影响访问 */
	setvbuf(stdout, NULL, _IONBF, 0);

	if (!strcmp(mode, "eof")) {
		printf("文件 3 字节，映射 8192 字节，读 p[5000] ...\n");
		printf("p[5000] = %d\n", p[5000]);
	} else if (!strcmp(mode, "trunc")) {
		printf("文件 8192 字节，读 p[5000] = %d\n", p[5000]);
		if (ftruncate(fd, 3) < 0) { perror("ftruncate"); return 1; }
		printf("把文件截成 3 字节，再读 p[5000] ...\n");
		printf("p[5000] = %d\n", p[5000]);
	} else if (!strcmp(mode, "unmap")) {
		printf("文件 8192 字节，读 p[5000] = %d\n", p[5000]);
		if (munmap(base + 4096, 4096) < 0) { perror("munmap"); return 1; }
		printf("munmap 掉第二页，再读 p[5000] ...\n");
		printf("p[5000] = %d\n", p[5000]);
	} else if (!strcmp(mode, "prot")) {
		printf("PROT_READ 映射，读 p[0] = '%c'\n", p[0]);
		printf("往 p[0] 写 'X' ...\n");
		p[0] = 'X';
		printf("写成功了\n");
	} else if (!strcmp(mode, "close")) {
		close(fd);
		printf("close(fd) 之后读 p[0] = '%c'\n", p[0]);
		p[1] = 'B';
		printf("close(fd) 之后写 p[1]，再读回 = '%c'\n", p[1]);
	} else {
		fprintf(stderr, "不认识的情形: %s\n", mode);
		return 2;
	}
	return 0;
}
