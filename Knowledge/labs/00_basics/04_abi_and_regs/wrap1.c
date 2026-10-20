/* 谁负责保存 lr：一个还要调用别人的函数，和一个不调用别人的函数
 *
 * wrap1 里有一句 ext1(a)，bl 会把返回地址写进 lr，
 * 所以 wrap1 进门必须先把 lr 存到栈上，出门再取回来。
 * leaf 不调用任何人，lr 不会被改写，bx lr 直接返回。
 */
int ext1(int a);

int wrap1(int a)
{
	return ext1(a) + 1;
}

int leaf(int a)
{
	return a * 3;
}
