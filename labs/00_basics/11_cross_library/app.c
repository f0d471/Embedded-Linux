#include <stdio.h>
#include <answer.h>

int main(void)
{
	printf("answer=%d\n", answer_value());
	return answer_value() == 42 ? 0 : 1;
}
