CC      ?= gcc
PREFIX  ?= /usr
DESTDIR ?=
CFLAGS  ?= -O2

all: libanswer.so.1.0

answer.o: answer.c answer.h
	$(CC) $(CFLAGS) -fPIC -Wall -Wextra -Werror -c -o $@ answer.c

libanswer.so.1.0: answer.o
	$(CC) -shared -Wl,-soname,libanswer.so.1 -o $@ answer.o
	ln -sfn libanswer.so.1.0 libanswer.so.1
	ln -sfn libanswer.so.1 libanswer.so

install: all
	mkdir -p $(DESTDIR)$(PREFIX)/include $(DESTDIR)$(PREFIX)/lib
	cp answer.h $(DESTDIR)$(PREFIX)/include/
	cp -a libanswer.so libanswer.so.1 libanswer.so.1.0 $(DESTDIR)$(PREFIX)/lib/

clean:
	rm -f answer.o libanswer.so libanswer.so.1 libanswer.so.1.0

.PHONY: all install clean
