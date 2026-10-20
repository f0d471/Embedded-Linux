/* 04 篇 7.2 节：read/write 循环拷与 mmap 拷，数系统调用，也数时间。
 * 编译：gcc -O2 -Wall cp_rw.c -o cp_rw
 *       gcc -O2 -Wall -DUSE_MMAP cp_rw.c -o cp_mmap   （同一份源码,-DUSE_MMAP 走 mmap 支路）
 * 跑：  head -c 8388608 /dev/urandom > big.bin
 *       strace -f -e trace=read,write -o t1.txt ./cp_rw big.bin c1.bin
 *       strace -f -e trace=read,write -o t2.txt ./cp_mmap big.bin c2.bin
 *       cmp big.bin c1.bin && cmp big.bin c2.bin && echo SAME
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/mman.h>
#include <sys/stat.h>

int main(int argc, char **argv)
{
    int in, out;
    ssize_t n;
    struct stat st;

    if (argc != 3) {
        fprintf(stderr, "Usage: %s <src> <dst>\n", argv[0]);
        return 1;
    }
    in = open(argv[1], O_RDONLY);
    if (in < 0) { perror("open src"); return 1; }
    fstat(in, &st);

#ifdef USE_MMAP
    /* mmap 版:整个文件映射进来,一次 write 发出去 */
    if (st.st_size == 0) {                    /* 空文件不能映射 */
        fprintf(stderr, "mmap: empty file\n");
        return 1;
    }
    char *p = mmap(NULL, st.st_size, PROT_READ, MAP_SHARED, in, 0);
    if (p == MAP_FAILED) { perror("mmap"); return 1; }
    out = open(argv[2], O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (out < 0) { perror("open dst"); return 1; }
    n = write(out, p, st.st_size);
    if (n != st.st_size) { perror("write"); return 1; }
#else
    /* read/write 版:4096 字节缓冲循环 */
    char buf[4096];
    out = open(argv[2], O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (out < 0) { perror("open dst"); return 1; }
    while ((n = read(in, buf, sizeof(buf))) > 0) {
        if (write(out, buf, n) != n) { perror("write"); return 1; }
    }
    if (n < 0) { perror("read"); return 1; }
#endif
    close(in);
    close(out);
    return 0;
}
