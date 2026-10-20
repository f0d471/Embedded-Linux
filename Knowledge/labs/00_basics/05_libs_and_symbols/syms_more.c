/* fundamentals 05 第 1.6 节:syms.c 没占到的几种符号类型
 * 编译: gcc -c syms_more.c -o syms_more.o && nm syms_more.o
 *       gcc -fcommon -c syms_more.c -o syms_more_c.o && nm syms_more_c.o
 */
int weak_ref(void) __attribute__((weak));       /* 弱引用: 没人定义也能链接 */

int __attribute__((weak)) weak_def(void)        /* 弱定义: 别处有同名强定义时让位 */
{
	return 1;
}

static const int s_ro = 5;                      /* static 只读: 小写 r */
static int       s_zero;                        /* static 无初值: 小写 b */
int              g_tent;                        /* 无初值全局: 默认 B, -fcommon 时 C */

int use(void)
{
	return s_ro + s_zero + g_tent + weak_def() + (weak_ref ? weak_ref() : 0);
}
