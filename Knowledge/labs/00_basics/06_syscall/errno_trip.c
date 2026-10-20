/* 失败原因怎么从内核回到 errno：同一个坏 fd，直接发和经 C 库发各一次。 */
#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include "raw.h"

int main(void)
{
	long r;
	ssize_t w;
	int e;

	r = raw_syscall3(NR_write, 99, (long)"x", 1);   /* fd 99 没有打开 */
	printf("raw  write(99) = %ld\n", r);

	errno = 0;
	w = write(99, "x", 1);
	e = errno;                                      /* 先存下，printf 可能改它 */
	printf("libc write(99) = %zd, errno = %d (%s)\n", w, e, strerror(e));
	return 0;
}
