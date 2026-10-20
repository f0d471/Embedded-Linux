# 没有头文件依赖的 Makefile:两个 .o 都只依赖各自的 .c。
# 实验:make 一次;改 point.h 加字段;只 touch main.c;再 make,
#       只有 main.o 按新结构体重编,fill.o 还是旧的,两边对同一块内存理解不同。

app: main.o fill.o
	gcc -o $@ $^

%.o: %.c
	gcc -Wall -Wextra -c -o $@ $<

clean:
	rm -f app *.o *.d

.PHONY: clean
