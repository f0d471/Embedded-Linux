/* 04 章 3.5 节：mode 是"请求"不是"落地"，且对已存在的文件根本不看。
 * 编译：gcc -Wall mode.c -o mode
 * 跑：  rm -f a.txt && ./mode a.txt 0777 && stat -c '%a %n' a.txt
 *       ./mode a.txt 0600 && stat -c '%a %n' a.txt   ← 已存在，权限不变
 *       ./mode a.txt 0777 && stat -c '%a %n' a.txt   ← 仍不变
 */
#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>

int main(int argc, char **argv)
{
    int fd;

    if (argc != 3) {
        printf("Usage: %s <file> <mode octal>\n", argv[0]);
        return 1;
    }
    fd = open(argv[1], O_WRONLY | O_CREAT | O_TRUNC, (int)strtol(argv[2], NULL, 8));
    if (fd < 0) {
        perror("open");
        return 1;
    }
    close(fd);
    return 0;
}
