/* 00 篇第 7 节注错见红：往 main 的代码里写一个字。
 * main 落在只读可执行（r-xp）的映射里，写它被硬件拒绝，
 * 进程收到 SIGSEGV，退出码 139。
 */
int main(void)
{
	*(volatile int *)main = 0;
	return 0;
}
