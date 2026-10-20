/* 01 篇第 4 节：和 big1.c 只差一个初值 {1}，数组改进 .data。
 * .data 在文件里真存字节，文件立刻大约四百万字节。
 */
int arr[1000000] = {1};

int main(void)
{
	return arr[0];
}
