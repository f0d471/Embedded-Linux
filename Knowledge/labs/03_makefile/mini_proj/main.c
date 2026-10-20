/* 03 篇 mini_proj：调用 add 和 print_banner。
 * Makefile 五步演进的实验工程,中间形态在 steps/ 下。
 */
#include <stdio.h>
#include "math_ops.h"
#include "display.h"

int main(void)
{
    printf("1 + 2 = %d\n", add(1, 2));
    print_banner();
    return 0;
}
