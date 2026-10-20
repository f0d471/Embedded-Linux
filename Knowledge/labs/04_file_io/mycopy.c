/* 04 篇 2.6 节 L3：自己写一个 copy（参考答案）。
 * 判据:见教程 2.6 节,cmp 逐字节一致、空文件也能拷。
 * 编译：gcc -Wall mycopy.c -o mycopy
 */
#include <stdio.h>
#include <fcntl.h>
#include <unistd.h>

int main(int argc, char **argv)
{
    int in, out;
    char buf[4096];
    ssize_t n, w;

    if (argc != 3) {
        fprintf(stderr, "Usage: %s <src> <dst>\n", argv[0]);
        return 1;
    }
    in = open(argv[1], O_RDONLY);
    if (in < 0) {
        perror("open src");          /* 别只打 "error",要把原因带出来 */
        return 1;
    }
    out = open(argv[2], O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (out < 0) {
        perror("open dst");
        close(in);
        return 1;
    }
    while ((n = read(in, buf, sizeof(buf))) > 0) {
        w = write(out, buf, n);      /* 用返回值 n, 不是 sizeof(buf);
                                        注错:换成 sizeof(buf) 再 cmp,见红 */
        if (w != n) {
            perror("write");
            close(in);
            close(out);
            return 1;
        }
    }
    if (n < 0)
        perror("read");
    close(in);
    close(out);
    return n < 0 ? 1 : 0;
}
