# 第 3 步:自动收集源文件。加一个 .c 不用改本文件。
# 用法:在 mini_proj 目录里执行  make -f steps/step3/Makefile
# 代价:wildcard 只认"现在存在"的文件;删掉一个 .c 之后,
#       它的 .o 会从 $(OBJS) 里消失,clean 再也扫不到它(孤儿产物)。

CC     := gcc
CFLAGS := -O2 -Wall -Wextra

SRCS := $(wildcard *.c)
OBJS := $(SRCS:.c=.o)

app: $(OBJS)
	$(CC) $(OBJS) -o $@

%.o: %.c
	$(CC) $(CFLAGS) -c -o $@ $<

clean:
	rm -f app $(OBJS)

.PHONY: clean
