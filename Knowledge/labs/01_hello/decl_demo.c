/* 01 章 1.3 节：声明与定义的分工。
 * 编译：gcc -Wall decl_demo.c        （故意少传参数，看声明怎么抓错）
 */
#include <stdio.h>

int add(int a, int b);            /* 声明:只说形状 */

int main(void)
{
    printf("1+2=%d\n", add(1));   /* 故意只传一个参数 */
    return 0;
}

int add(int a, int b)             /* 定义:给实现 */
{
    return a + b;
}
