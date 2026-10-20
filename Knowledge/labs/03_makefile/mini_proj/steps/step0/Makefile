# 第 0 步:一条规则,一条命令编全部。
# 用法:在 mini_proj 目录里执行  make -f steps/step0/Makefile
# 毛病:改了任何一个文件,三个 .c 全部从头再编一遍,因为命令只有这一条。

app: main.c math_ops.c display.c math_ops.h display.h config.h
	gcc -o app main.c math_ops.c display.c

clean:
	rm -f app

.PHONY: clean
