/* 预处理实验：宏替换、条件编译，以及"宏只做文本替换"的后果。
 * 只预处理：      gcc -E pp_demo.c -o pp_demo.i
 * 打开 DEBUG 块： gcc -E -DDEBUG pp_demo.c -o pp_demo_dbg.i
 */
#include <stdio.h>

#define MAX 20
#define MIN 10
#define BIT(n)   (1 << (n))
#define TWICE(x) x + x

int main(void)
{
    int range = MAX - MIN;
    int mask = BIT(3);
    int twice = TWICE(3) * 2;

#ifdef DEBUG
    range = range + BIT(BIT(2));
#endif
    printf("range=%d mask=%d twice=%d\n", range, mask, twice);
    return 0;
}
