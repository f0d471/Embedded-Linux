# 模式规则：一条 %.o: %.c 编所有 .c
app: main.o a.o b.o
	gcc -o $@ $^

%.o: %.c
	gcc -c -o $@ $<

clean:
	rm -f *.o app

.PHONY: clean
