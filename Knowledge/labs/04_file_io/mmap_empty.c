/* 04 篇 7.3 节：长度为 0 的 mmap 直接失败，返回 MAP_FAILED 而不是 NULL。
 * 编译：gcc -Wall mmap_empty.c -o mmap_empty
 * 跑：  : > e0.bin && ./mmap_empty e0.bin
 */
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <sys/mman.h>

int main(int argc, char **argv)
{
    int fd;
    void *p;

    if (argc != 2) {
        printf("Usage: %s <empty file>\n", argv[0]);
        return 1;
    }
    fd = open(argv[1], O_RDONLY);
    if (fd < 0) {
        perror("open");
        return 1;
    }
    p = mmap(NULL, 0, PROT_READ, MAP_SHARED, fd, 0);
    printf("p=%p MAP_FAILED=%d errno=%d %s\n",
           p, p == MAP_FAILED, errno, strerror(errno));
    return 0;
}
