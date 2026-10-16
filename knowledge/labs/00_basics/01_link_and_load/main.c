int add(int a, int b);

int g_init = 1;
int g_bss;

int main(void)
{
	return add(g_init, 2) + g_bss;
}
