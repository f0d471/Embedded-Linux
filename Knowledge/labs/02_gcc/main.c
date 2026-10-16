/* 02 章 2.3 节：多文件与库的实验。
 * main.c 只需要 sub_func 的"声明"，定义在 sub.c 里——
 * "在哪"是链接器的事，编译 main.c 时编译器不需要知道。
 */
void sub_func(void);          /* 声明:01 章 1.3 讲过的分工 */

int main(void)
{
    sub_func();
    return 0;
}
