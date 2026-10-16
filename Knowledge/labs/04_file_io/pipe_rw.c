/* 04 章 3.1 节：read/write 是"最多"不是"正好"——用管道把两件事当场做出来。
 * 编译：gcc -Wall pipe_rw.c -o pipe_rw
 * 跑：  ./pipe_rw
 */
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>

int main(void)
{
    int fds[2];
    char buf[100];
    ssize_t n;

    if (pipe(fds) != 0) {
        perror("pipe");
        return 1;
    }
    write(fds[1], "12345", 5);              /* 管道里只放 5 个字节 */

    n = read(fds[0], buf, 100);            /* 你要 100 个 */
    printf("read(要 100) 实际返回 %zd\n", n);

    fcntl(fds[1], F_SETFL, O_NONBLOCK);    /* 写端设成非阻塞 */
    n = write(fds[1], buf, 1048576);       /* 你要写 1 MiB */
    printf("write(要 1048576) 实际返回 %zd\n", n);
    n = write(fds[1], "x", 1);             /* 管道已满时再写 */
    printf("管道满时 write(1) 返回 %zd, errno=%d (%s)\n",
           n, errno, strerror(errno));
    return 0;
}
