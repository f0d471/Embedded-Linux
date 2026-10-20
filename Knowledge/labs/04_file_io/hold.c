/* 04 篇 1.1 节：打开一个文件后挂住，好让你去 /proc 里看它的 fd 表。
 * 编译：gcc -Wall hold.c -o hold
 * 跑：  ./hold data.txt &       然后  ls -l /proc/<pid>/fd
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
    fd = open(argv[1], O_RDONLY);
    if (fd < 0) {
        perror("open");
        return 1;
    }
    printf("pid=%d fd=%d\n", getpid(), fd);
    fflush(stdout);          /* printf 的先进 C 库缓冲，不冲这一下终端看不到（本篇第 5 节） */
    pause();                 /* 挂住，等信号 */
    return 0;
}
