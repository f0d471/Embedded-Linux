#include <stdio.h>
#include "mathx.h"

int helper(int x)
{
	return x + 1;
}

int main(void)
{
	printf("%d\n", helper(mx_add(3, 4)));
	return 0;
}
