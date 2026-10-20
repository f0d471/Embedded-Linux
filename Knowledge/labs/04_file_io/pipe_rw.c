/* 04 篇 2.1 节：read/write 的返回值是"实际搬了几个字节"，用管道把两件事当场做出来。
 * 编译：gcc -Wall pipe_rw.c -o pipe_rw
 * 跑：  ./pipe_rw
 */
#define _GNU_SOURCE             /* F_GETPIPE_SZ 需要 */
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>

int main(void)
{
    int fds[2];
    char buf[100];
    static char big[1048576];   /* 1 MiB，供那次大 write 用 */
    ssize_t n;
    long total;

    if (pipe(fds) != 0) {
        perror("pipe");
        return 1;
    }
    printf("管道容量: %d 字节\n", fcntl(fds[1], F_GETPIPE_SZ));

    write(fds[1], "12345", 5);            /* 管道里只放 5 个字节 */
    n = read(fds[0], buf, 100);           /* 你要 100 个 */
    printf("read(要 100) 实际返回 %zd\n", n);

    fcntl(fds[1], F_SETFL, O_NONBLOCK);   /* 写端设成非阻塞：写不下就立刻返回，不等着 */
    n = write(fds[1], big, sizeof(big));  /* 你要写 1 MiB */
    printf("write(要 1048576) 实际返回 %zd\n", n);

    total = n > 0 ? n : 0;
    while ((n = write(fds[1], buf, sizeof(buf))) > 0)
        total += n;                       /* 接着写，直到写不进去 */
    printf("管道一共收下 %ld 字节；写满后再 write(100) 返回 %zd, errno=%d (%s)\n",
           total, n, errno, strerror(errno));
    return 0;
}
