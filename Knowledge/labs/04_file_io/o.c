/* 04 章 3.6 节：让 open 失败，看清 errno。
 * 编译：gcc -Wall o.c -o o && ./o
 */
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>

static void try_open(const char *tag, const char *path, int flags, unsigned mode)
{
    int fd = open(path, flags, mode);

    printf("%-30s fd=%3d errno=%2d %s\n", tag, fd, errno, strerror(errno));
    if (fd >= 0)
        close(fd);
}

int main(void)
{
    try_open("打开不存在的文件", "/tmp/no_such_file", O_RDWR, 0);
    try_open("用 O_RDWR 打开一个目录", "/tmp", O_RDWR, 0);
    try_open("用 O_RDONLY 打开一个目录", "/tmp", O_RDONLY, 0);
    try_open("O_CREAT|O_EXCL 打已存在文件", "/etc/hostname", O_WRONLY | O_CREAT | O_EXCL, 0644);
    try_open("用 O_WRONLY 打开 444 的文件", "/etc/hostname", O_WRONLY, 0);
    return 0;
}
