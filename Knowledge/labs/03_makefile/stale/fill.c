#include "point.h"

/* 按 point.h 当时的样子决定 x、y 在结构体里的偏移,编进 fill.o */
void fill(struct point *p)
{
    p->x = 1;
    p->y = 2;
}
