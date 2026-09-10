/* printf 和 write，谁先到达内核 */
#include <stdio.h>
#include <unistd.h>

int main(void)
{
	printf("A_printf\n");            /* 先写的 */
	write(1, "B_write\n", 8);        /* 后写的 */
	return 0;
}
