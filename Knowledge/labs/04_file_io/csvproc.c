/* 04 篇第 4 节 L3 综合实验：处理 CSV 表格（参考答案）。
 * 任务规格见教程: ./csvproc <输入.csv> <输出.csv>
 *   逐行读/逐行处理/逐行写;表头原样;数据行补总分与评价;
 *   输出行尾统一 CRLF;保留文件开头的 UTF-8 BOM。
 * 三个坑都在代码里标了位置:行尾字节、BOM、%[^,]。
 * 判据:score.csv→110 字节 4 行;crlf.csv 4 行;nonl.csv 2 行(见教程)。
 * 编译：gcc -Wall csvproc.c -o csvproc
 */
#include <stdio.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>

/* 读一行。返回值三态(教程 4.5"返回值怎么设计"):
 *   >0  这行的字节数
 *    0  空行(连着的换行),不是错误,调用方要 continue
 *   -1  文件读完(且手里没有半行)或出错
 */
static int read_line(int fd, char *buf, int size)
{
    int i = 0, err = 0;
    char b;
    ssize_t c;

    while ((c = read(fd, &b, 1)) == 1) {
        if (b == '\n' || b == '\r')      /* 坑 1:两个行尾字节都要认 */
            break;
        if (i < size - 1)
            buf[i++] = b;
    }
    if (c <= 0)
        err = 1;                         /* 读到 EOF(或出错) */
    buf[i] = '\0';
    if (err && i == 0)
        return -1;                       /* EOF 且手里没有半行 */
    return i;                            /* 手里有半行就先交出去 */
}

/* 处理一行。表头(BOM 打头或逗号打头)原样过;数据行补总分与评价。 */
static void process_line(const char *line, char *result)
{
    char name[100];
    int s0, s1, s2, sum;
    const char *level;

    if ((unsigned char)line[0] == 0xEF   /* 坑 2:UTF-8 BOM,必须转 unsigned char */
        || line[0] == ',') {             /* 表头行 */
        strcpy(result, line);
        return;
    }
    /* 坑 3:%s 遇到逗号不停,会把整行吞掉;要用 %[^,] */
    if (sscanf(line, "%99[^,],%d,%d,%d,", name, &s0, &s1, &s2) != 4) {
        strcpy(result, line);            /* 解析不动就原样过,不猜 */
        return;
    }
    sum = s0 + s1 + s2;
    level = sum >= 270 ? "A+" : (sum >= 240 ? "A" : "B");
    sprintf(result, "%s,%d,%d,%d,%d,%s", name, s0, s1, s2, sum, level);
}

int main(int argc, char **argv)
{
    int fd_in, fd_out, len;
    char line[1000], result[1200];

    if (argc != 3) {
        printf("Usage: %s <data csv> <result csv>\n", argv[0]);
        return 1;
    }
    fd_in = open(argv[1], O_RDONLY);
    if (fd_in < 0) {
        perror("open data");
        return 1;
    }
    fd_out = open(argv[2], O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd_out < 0) {
        perror("create result");
        close(fd_in);
        return 1;
    }
    while (1) {
        len = read_line(fd_in, line, sizeof(line));
        if (len < 0)                     /* 只能 <0 停;==0 是空行要继续 */
            break;
        if (len == 0)
            continue;
        process_line(line, result);
        write(fd_out, result, strlen(result));
        write(fd_out, "\r\n", 2);        /* 输出行尾统一 CRLF */
    }
    close(fd_in);
    close(fd_out);
    return 0;
}
