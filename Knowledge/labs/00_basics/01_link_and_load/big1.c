/* 01 篇第 4 节：一百万项的数组不给初值，进 .bss。
 * .bss 在文件里只记一个大小，不存那四百万个零字节。
 */
int arr[1000000];

int main(void)
{
	return arr[0];
}
