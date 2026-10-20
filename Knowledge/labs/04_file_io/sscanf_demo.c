/* 04 篇 4.4 节：sscanf 的 %s 停在空白，不停在逗号；%[^,] 才停在逗号。
 * 编译：gcc -Wall sscanf_demo.c -o sscanf_demo && ./sscanf_demo
 */
#include <stdio.h>

int main(void)
{
    const char *line = "张三,90,91,92,,";
    char name[100];
    int a, b, c, r;

    a = b = c = -1;
    r = sscanf(line, "%s,%d,%d,%d,", name, &a, &b, &c);
    printf("%%s     : ret=%d name='%s' a=%d\n", r, name, a);

    a = b = c = -1;
    r = sscanf(line, "%99[^,],%d,%d,%d,", name, &a, &b, &c);
    printf("%%99[^,]: ret=%d name='%s' a=%d b=%d c=%d\n", r, name, a, b, c);
    return 0;
}
