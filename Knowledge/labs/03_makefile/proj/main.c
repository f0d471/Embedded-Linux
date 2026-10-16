/* 通用 Makefile 工程:main 调用三个子函数,分别在 sub.c 和 a/ 下 */
extern void sub_func(void);
extern void sub2_print(void);
extern void sub3_print(void);

int main(void)
{
    sub_func();
    sub2_print();
    sub3_print();
    return 0;
}
