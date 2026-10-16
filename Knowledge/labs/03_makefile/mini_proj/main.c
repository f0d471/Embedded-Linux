/* 03 章 3.5 节 mini_proj：调用 add 和 print_banner。
 * 五步演进的最终形态（第 5 步，支持交叉编译）。
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
