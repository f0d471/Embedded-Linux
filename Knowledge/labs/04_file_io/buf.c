/* 04 章 4.2 节：数一数标准 IO 那 4096 字节的缓冲层。
 * 编译：gcc -Wall buf.c -o buf
 * 跑：  strace -f -e trace=write -o t.txt ./buf > out.txt
 *       grep -cE '(^|[0-9]+ +)write\(' t.txt      ← 数 write 次数
 * 对照：./buf | cat > /dev/null（管道，全缓冲）
 *       script -q -c "strace -f -e trace=write -o t2.txt ./buf" /dev/null（终端，行缓冲）
 */
#include <stdio.h>

int main(void)
{
    int i;

    for (i = 0; i < 1000; i++)
        printf("line %d\n", i);
    return 0;
}
