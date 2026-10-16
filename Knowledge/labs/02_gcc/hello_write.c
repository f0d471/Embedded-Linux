/* 02 章 2.7 节：不用 printf，用 write 把同一句话打到屏幕上。
 * printf 在用户态做格式化和缓冲，最终也是调 write(2)；
 * write 才是真正穿过用户/内核边界的那一层。
 * 编译：gcc -Wall hello_write.c -o hello_write
 * 看系统调用（x86 版）：strace -e trace=write ./hello_write
 */
#include <unistd.h>

int main(void)
{
    write(1, "hello, world\n", 13);
    /*   ^  1 是标准输出 stdout,2 是标准错误 stderr
     *                    ^^^ 字节数,必须数对 */
    return 0;
}
