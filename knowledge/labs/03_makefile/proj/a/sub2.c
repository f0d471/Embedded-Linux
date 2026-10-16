#include <stdio.h>
#include "sub2.h"

void sub2_print(void)
{
    printf("sub2\n");
#ifdef DEBUG
    printf("sub2 debug\n");
#endif
}
