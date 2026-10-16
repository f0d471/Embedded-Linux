#include <stdio.h>
#include "sub3.h"

void sub3_print(void)
{
    printf("sub3 magic=%d\n", SUB3_MAGIC);
#ifdef DEBUG
    printf("sub3 debug\n");
#endif
#ifdef DEBUG_SUB3
    printf("sub3 debug only\n");
#endif
}
