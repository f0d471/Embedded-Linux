/* 映射长度超过文件末尾所在的页 -> SIGBUS，不是 SIGSEGV */
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mman.h>

int main(int argc, char **argv)
{
	const char *path = argc > 1 ? argv[1] : "tiny.bin";
	int which = argc > 2 ? atoi(argv[2]) : 0;
	int fd = open(path, O_RDWR | O_CREAT | O_TRUNC, 0644);
	char *p;

	write(fd, "abc", 3);                        /* 文件只有 3 字节 */
	p = mmap(NULL, 8192, PROT_READ, MAP_SHARED, fd, 0);   /* 却映射两页 */
	if (p == MAP_FAILED) { perror("mmap"); return 1; }

	switch (which) {
	case 0:
		printf("p[0]    = '%c'   （文件里真有这个字节）\n", p[0]);
		printf("p[100]  = %d     （第一页里、文件外：读到 0，不报错）\n", p[100]);
		printf("p[4095] = %d     （第一页最后一个字节，仍然安全）\n", p[4095]);
		break;
	case 1:
		printf("正要读 p[5000]（第二页，完全在文件之外）...\n");
		fflush(stdout);
		printf("p[5000] = %d\n", p[5000]);      /* 这里会挨 SIGBUS */
		printf("（没崩？那这台机器行为和笔记不一致）\n");
		break;
	}
	return 0;
}
