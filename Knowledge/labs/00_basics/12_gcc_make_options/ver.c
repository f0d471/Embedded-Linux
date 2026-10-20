#include <stdio.h>

int main(void)
{
#ifdef VERSION
    printf("version=%d\n", VERSION);
#else
    printf("no version\n");
#endif
    return 0;
}
