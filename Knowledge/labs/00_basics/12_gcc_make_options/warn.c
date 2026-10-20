#include <stdio.h>

int add(int a, int b)
{
    return a + b;
}

int main(void)
{
    int i;
    unsigned int n = 3;

    printf("sum=%d\n", add(1, 2));
    if (n < -1)
        printf("never\n");
    return 0;
}
