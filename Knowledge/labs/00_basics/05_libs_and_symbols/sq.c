/* fundamentals 05 第 2.5 节:sqrt 在 libm 里, 不在默认链接名单上
 * 编译: gcc -O0 sq.c        报 undefined reference to `sqrt'
 *       gcc -O0 sq.c -lm    正常
 * x 用 volatile 修饰, 是为了挡住编译期常量折叠, 逼它真的去调 sqrt;
 * 直接写 sqrt(2.0) 的话, 编译器在编译期就把结果算出来了, 不带 -lm 也能编过
 */
#include <math.h>
#include <stdio.h>

int main(void)
{
	volatile double x = 2.0;

	printf("%f\n", sqrt(x));
	return 0;
}
