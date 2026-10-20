/* fundamentals 05 第 1 节:各种写法在符号表里的样子
 * 编译: gcc -c syms.c -o syms.o && nm syms.o
 * 注意: 这个文件故意引用没有定义的 nobody, 只能 -c, 链接一定失败
 */
#include <stdio.h>

int         g_init = 1;            /* 有初值的全局变量 */
int         g_bss;                 /* 没有初值的全局变量 */
const char *g_str = "abc";         /* 指针本身可改, 指向的字符串只读 */
const int   g_ro = 42;             /* 只读全局常量 */
static int  s_local = 7;           /* static: 只在本文件内可见 */

int helper(int x) { return x + s_local; }
static int shelp(int x) { return x - 1; }

extern int nobody(void);           /* 只有声明, 哪里都没有定义 */

int main(void)
{
	printf("%d\n", helper(g_init) + shelp(g_ro) + nobody());
	return 0;
}
