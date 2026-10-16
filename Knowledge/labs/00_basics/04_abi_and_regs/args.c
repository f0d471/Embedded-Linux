/* 参数到底放在哪：让反汇编告诉你 */

/* 只声明不定义：编译器无法内联，也无法把结果算出来 */
int ext6(int a, int b, int c, int d, int e, int f);

int use4(int a, int b, int c, int d)
{
	return a + b + c + d;
}

int use6(int a, int b, int c, int d, int e, int f)
{
	return a + b + c + d + e + f;
}

long long ret64(void)
{
	return 0x1122334455667788LL;
}

int caller(void)
{
	return ext6(1, 2, 3, 4, 5, 6);
}

/* 用满 8 个"活很久"的值，逼编译器动用 callee-saved 寄存器 */
int many(int a, int b, int c, int d)
{
	int v1 = ext6(a, 0, 0, 0, 0, 0);
	int v2 = ext6(b, 0, 0, 0, 0, 0);
	int v3 = ext6(c, 0, 0, 0, 0, 0);
	int v4 = ext6(d, 0, 0, 0, 0, 0);
	return v1 + v2 + v3 + v4;
}
