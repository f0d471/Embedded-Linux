#include "mathx.h"

int mx_len(const char *s)
{
	int n = 0;
	while (*s++)
		n++;
	return n;
}
