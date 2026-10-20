# 第 4 步:头文件自动依赖。编译时让 gcc 顺带写出 .d,make 再读回来。
# 用法:在 mini_proj 目录里执行  make -f steps/step4/Makefile
# 验证:先完整 make 一次,再 touch config.h 后 make,必须恰好重编 display.o。

CC     := gcc
CFLAGS := -O2 -Wall -Wextra

SRCS := $(wildcard *.c)
OBJS := $(SRCS:.c=.o)
DEPS := $(OBJS:.o=.d)

app: $(OBJS)
	$(CC) $(OBJS) -o $@

%.o: %.c
	$(CC) $(CFLAGS) -MMD -c -o $@ $<

clean:
	rm -f app $(OBJS) $(DEPS)

.PHONY: clean

# 第一次 make 时 .d 还不存在,-include 对不存在的文件跳过不报错
-include $(DEPS)
