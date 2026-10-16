#include <stdio.h>

int g_init = 1;
int g_bss;

int main(void)
{
	char line[256];
	FILE *f = fopen("/proc/self/maps", "r");

	while (fgets(line, sizeof line, f))
		if (line[0] != '7' || line[73 - 73] == 0)  /* 打全部 */
			fputs(line, stdout);
	fclose(f);
	printf("&main  =%p\n", (void *)main);
	printf("&g_init=%p\n", (void *)&g_init);
	printf("&g_bss =%p\n", (void *)&g_bss);
	printf("g_bss  =%d\n", g_bss);
	return 0;
}
