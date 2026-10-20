#include <stdio.h>
#include "point.h"

int main(void)
{
    struct point p = {0};

    fill(&p);
    printf("x=%d y=%d sizeof=%zu\n", p.x, p.y, sizeof p);
    return 0;
}
