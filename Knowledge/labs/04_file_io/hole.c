/* 04 章 3.3 节：lseek 造空洞——文件大小和占盘大小是两个数。
 * 编译：gcc -Wall hole.c -o hole
 * 跑：  ./hole sparse.bin && ls -l sparse.bin && du -h sparse.bin && stat -c '%s %b' sparse.bin
 * ⚠ 必须在 WSL 原生目录(~)里跑，不要在 /mnt/e 下（NTFS 不支持稀疏，结论会反）。
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
    fd = open(argv[1], O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) {
        perror("open");
        return 1;
    }
    write(fd, "HEAD", 4);              /* 开头 4 字节 */
    lseek(fd, 1048576, SEEK_SET);    /* 跳到 1 MiB 处——中间不写 */
    write(fd, "TAIL", 4);            /* 末尾 4 字节 */
    close(fd);
    return 0;
}
