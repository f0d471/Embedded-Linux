#include <stdio.h>
#include "mathx.h"

int main(void)
{
	printf("mx_add(3,4) = %d\n", mx_add(3, 4));
	return 0;                  /* 故意不调用 mx_len */
}
