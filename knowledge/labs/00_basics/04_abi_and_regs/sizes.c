/* 用编译期断言把两个平台的类型大小逼出来：编不过就说明大小不是这个数 */
#include <stdio.h>
#include <time.h>

int main(void)
{
	printf("char=%zu short=%zu int=%zu long=%zu longlong=%zu ptr=%zu time_t=%zu\n",
	       sizeof(char), sizeof(short), sizeof(int), sizeof(long),
	       sizeof(long long), sizeof(void *), sizeof(time_t));
	printf("struct{char a; int b;} = %zu\n", sizeof(struct { char a; int b; }));
	return 0;
}
