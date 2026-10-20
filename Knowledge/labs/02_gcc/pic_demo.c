/* 做动态库时为什么要 -fPIC：这个函数读写一个全局变量。 */
int counter;

int bump(void)
{
    counter = counter + 1;
    return counter;
}
