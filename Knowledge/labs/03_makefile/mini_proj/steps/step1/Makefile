# 第 1 步:全部写死。四条规则,一个变量都没有。
# 用法:在 mini_proj 目录里执行  make -f steps/step1/Makefile
# 感受:加一个源文件要改两处(app 的依赖清单和链接命令),还要再写一条编译规则。

app: main.o math_ops.o display.o
	gcc -o app main.o math_ops.o display.o

main.o: main.c
	gcc -c -o main.o main.c

math_ops.o: math_ops.c
	gcc -c -o math_ops.o math_ops.c

display.o: display.c
	gcc -c -o display.o display.c

clean:
	rm -f app main.o math_ops.o display.o

.PHONY: clean
