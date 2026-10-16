#!/bin/bash
# 00_基础 第 05 篇（系统调用与用户内核态）的判据自动核对
#
# 用法：bash check.sh
# 注错见红：改坏一处（比如给 crash.c 加 fflush），必须有判据变红。

cd "$(dirname "$0")" || exit 1

CC=arm-linux-gnueabihf-gcc
OD=arm-linux-gnueabihf-objdump

PASS=0; FAIL=0; SKIP=0
ok()   { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
no()   { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -n "$2" ] && printf '        %s\n' "$2"; }
skip() { SKIP=$((SKIP+1)); printf '  SKIP  %s\n' "$1"; }
eq()   { if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "期望 $3，实得 $2"; fi; }
has()  { if echo "$2" | grep -qE "$3"; then ok "$1"; else no "$1" "输出里找不到 $3"; fi; }

die() {
	FAIL=$((FAIL+1))
	printf '  FAIL  构建：%s\n\n  %d PASS / %d FAIL / %d SKIP（构建没过）\n' "$1" "$PASS" "$FAIL" "$SKIP"
	exit 1
}

echo "=== 构建 ==="
for p in order crash rawsys; do
	gcc $p.c -o $p 2>/dev/null || die "$p.c 编译不过"
done
cat > .w.c <<'EOF'
#include <unistd.h>
int main(void) { write(1, "hi\n", 3); return 0; }
EOF
$CC -static -O1 .w.c -o .w_static 2>/dev/null || die "ARM 静态版编译不过"
$CC         -O1 .w.c -o .w_dyn    2>/dev/null || die "ARM 动态版编译不过"
echo "  完成"
echo

echo "=== 05 篇 3.5  找到那条 svc ==="
NS=$($OD -d .w_static | grep -c '\bsvc\b')
ND=$($OD -d .w_dyn    | grep -c '\bsvc\b')
if [ "$NS" -gt 0 ]; then ok "静态链接的 ARM 程序里有 $NS 条 svc"; else no "静态版应当有 svc"; fi
eq "动态链接的 ARM 程序里 0 条 svc（封装在 libc.so.6 里）" "$ND" "0"
has "找得到「装调用号 + svc」的模式" \
    "$($OD -d .w_static | grep -A1 'mov.*r7, #')" 'svc'
has "__getpid 用的调用号是 20" \
    "$($OD -d .w_static | sed -n '/<__getpid>:/,/svc/p')" 'r7, #20'
echo

echo "=== 05 篇 4.5  绕过 libc 自己敲门 ==="
if grep -q 'stdio.h' rawsys.c; then
	no "rawsys.c 不该 include stdio.h"
else
	ok "rawsys.c 没有 include stdio.h"
fi
eq "它照样打出了字符串" "$(./rawsys)" "hello from raw syscall"
if command -v strace >/dev/null 2>&1; then
	# 2>&1 >/dev/null：先把 stderr 指到当前 stdout，再把程序自己的 stdout 丢掉。
	# 不这么做的话，程序的输出会插进 strace 那一行中间，把它断成两行。
	has "strace 证明它发的是真正的 write 系统调用" \
	    "$(strace -e trace=write ./rawsys 2>&1 >/dev/null)" 'write\(1, .*\) = 23'
else
	skip "strace 未安装"
fi
echo

echo "=== 05 篇 5  printf 和 write 谁先到内核 ==="
PIPE=$(./order | cat)
eq "接管道时（全缓冲）B_write 先出" "$(echo "$PIPE" | head -1)" "B_write"
./order > .f.txt
eq "接文件时（全缓冲）B_write 先出" "$(head -1 .f.txt)" "B_write"
rm -f .f.txt

if command -v script >/dev/null 2>&1; then
	TTY=$(script -qc './order' /dev/null | tr -d '\r')
	eq "接终端时（行缓冲）A_printf 先出" "$(echo "$TTY" | head -1)" "A_printf"
	if [ "$(echo "$TTY" | head -1)" != "$(echo "$PIPE" | head -1)" ]; then
		ok "同一个程序，输出目标不同则顺序不同"
	else
		no "两种情况下顺序应当相反"
	fi
else
	skip "script 未安装，测不到「接终端」这一档 x2"
fi

if command -v strace >/dev/null 2>&1; then
	SORDER=$(strace -e trace=write ./order 2>&1 | grep -oE 'write\(1, "[AB]_[a-z]+' | head -2 | tr '\n' ' ')
	has "strace 里到达内核的顺序确实是 B 在前" "$SORDER" 'B_write.*A_printf'
else
	skip "strace 未安装"
fi
echo

echo "=== 05 篇 6.5  崩溃时 printf 的内容会丢 ==="
bash -c './crash > .out.txt' 2>/dev/null; RC=$?
eq "crash 是被信号打死的（退出码 139 = SIGSEGV）" "$RC" "139"
eq "重定向到文件时，printf 的内容全丢（0 字节）" "$(stat -c %s .out.txt)" "0"

# 加 fflush 就不丢
sed 's|\*(int \*)0 = 1;|fflush(stdout);\n\t*(int *)0 = 1;|' crash.c > .c2.c
gcc .c2.c -o .c2 2>/dev/null
bash -c './.c2 > .out2.txt' 2>/dev/null
eq "加一行 fflush 之后就不丢了（13 字节）" "$(stat -c %s .out2.txt)" "13"
eq "内容是 before crash" "$(cat .out2.txt)" "before crash"
rm -f .c2.c .c2 .out.txt .out2.txt
echo

rm -f .w.c .w_static .w_dyn
echo "======================================"
printf '  %d PASS / %d FAIL / %d SKIP\n' "$PASS" "$FAIL" "$SKIP"
echo "======================================"
[ "$FAIL" -eq 0 ]
