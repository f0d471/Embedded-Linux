/* 源码里写 open 和 write，看静态链接的 ARM 程序里实际装进 r7 的是几号。
 * 编译：arm-linux-gnueabihf-gcc -static -O1 w.c -o w_static
 *       arm-linux-gnueabihf-gcc         -O1 w.c -o w_dyn
 */
#include <fcntl.h>
#include <unistd.h>

int main(void)
{
	int fd = open("/etc/hostname", O_RDONLY);

	write(1, "hi\n", 3);
	if (fd >= 0)
		close(fd);
	return 0;
}
