/* 04 章 3.3 节：lseek 到中间再 write，是覆盖不是插入。
 * 编译：gcc -Wall wp.c -o wp
 * 跑：  printf 'abcdefghijklmnopqrst\n' > w.txt && ./wp w.txt && cat w.txt && wc -c < w.txt
 */
#include <stdio.h>
#include <fcntl.h>
#include <unistd.h>

int main(int argc, char **argv)
{
    int fd;

    if (argc != 2) {
        printf("Usage: %s <file>\n", argv[0]);
        return 1;
    }
    fd = open(argv[1], O_RDWR);
    if (fd < 0) {
        perror("open");
        return 1;
    }
    lseek(fd, 3, SEEK_SET);       /* 位置移到第 3 字节(0 起) */
    if (write(fd, "123", 3) != 3)
        perror("write");
    close(fd);
    return 0;
}
