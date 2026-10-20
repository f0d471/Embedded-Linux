/* 多文件与库的实验：main.c 只认识 sub_func 的声明（来自 sub.h），
 * 定义在 sub.c 里。编译 main.c 时用不到定义，找定义是链接那一步的事。
 */
#include "sub.h"

int main(void)
{
    sub_func();
    return 0;
}
