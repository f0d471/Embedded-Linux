/* 04 篇 3.2 节：用 dup2 把 printf 骗进文件，以及 _exit 的那个坑。
 * 编译：gcc -Wall dup2_printf.c -o dup2_printf
 * 跑：  ./dup2_printf out.txt && cat out.txt && wc -c < out.txt
 * 注错：删掉 fflush 一行，并把 return 0 改成 _exit(0) 再跑，文件变 0 字节（缓冲没冲）。
 */
#include <stdio.h>
#include <fcntl.h>
#include <unistd.h>

int main(int argc, char **argv)
{
    int fd, save;

    if (argc != 2) {
        printf("Usage: %s <file>\n", argv[0]);
        return 1;
    }
    save = dup(1);                 /* 先存一份原 stdout，事后好恢复 */
    fd = open(argv[1], O_RDWR | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) {
        perror("open");
        return 1;
    }
    dup2(fd, 1);                   /* 1 号槽改指这个文件(旧的先被关掉) */
    printf("hello, world\n");      /* printf 认的是数字 1, 不是"终端" */
    fflush(stdout);                /* 不冲这一下, _exit 版本会丢 */
    dup2(save, 1);                 /* 恢复原 stdout */
    close(fd);
    return 0;
}
