# 第 2 步:变量与模式规则。命令里的碎片提成变量,三条编译规则塌缩成一条。
# 用法:在 mini_proj 目录里执行  make -f steps/step2/Makefile

CC     := gcc
CFLAGS := -O2 -Wall -Wextra
OBJS   := main.o math_ops.o display.o

app: $(OBJS)
	$(CC) $(OBJS) -o $@

%.o: %.c
	$(CC) $(CFLAGS) -c -o $@ $<

clean:
	rm -f app $(OBJS)

.PHONY: clean
