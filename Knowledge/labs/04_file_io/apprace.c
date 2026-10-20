/* 04 篇 2.7 节：O_APPEND 和 lseek+write 在并发下的差别。
 * 用法：./apprace append|lseek [N]     N 默认 2000，竞态不明显就加大
 * 两个进程同时往 out.txt 各写 N 行，每行 17 字节，期望值 2*N*17。
 * 编译：gcc -Wall apprace.c -o apprace
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/wait.h>

#define LINE "0123456789abcdef\n"   /* 17 字节 */

static void writer(int use_append, int n)
{
    int fd = open("out.txt", O_WRONLY | (use_append ? O_APPEND : 0));
    int i;

    if (fd < 0) {
        perror("open");
        exit(1);
    }
    for (i = 0; i < n; i++) {
        if (!use_append)
            lseek(fd, 0, SEEK_END);      /* 先自己找末尾：第 1 次系统调用 */
        write(fd, LINE, strlen(LINE));   /* 再写：第 2 次；两次之间另一个进程可能插进来 */
    }
    close(fd);
}

int main(int argc, char **argv)
{
    int use_append = (argc > 1 && strcmp(argv[1], "append") == 0);
    int n = argc > 2 ? atoi(argv[2]) : 2000;
    int fd;
    pid_t pid;

    fd = open("out.txt", O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) {
        perror("create");
        return 1;
    }
    close(fd);

    pid = fork();
    if (pid == 0) {
        writer(use_append, n);
        _exit(0);
    }
    writer(use_append, n);
    wait(NULL);

    fd = open("out.txt", O_RDONLY);
    printf("%-7s 模式：期望 %d 字节，实际 %ld 字节\n",
           use_append ? "append" : "lseek",
           2 * n * (int)strlen(LINE), (long)lseek(fd, 0, SEEK_END));
    close(fd);
    return 0;
}
