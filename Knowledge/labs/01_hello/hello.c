#include <stdio.h>


/* 执行命令: ./hello learner
 * argc = 2
 * argv[0] = ./hello
 * argv[1] = learner
 */

int main(int argc, char **argv)
{
	if (argc >= 2)
		printf("Hello, %s!\n", argv[1]);
	else
		printf("Hello, world!\n");
	return 0;
}


