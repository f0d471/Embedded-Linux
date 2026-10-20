#!/bin/bash
# 00_basics 第 06 套（fundamentals 07 篇：系统调用与用户态/内核态）的判据自动核对
#
# 用法：bash check.sh
# 环境：x86-64 Linux（WSL）、gcc、arm-linux-gnueabihf-gcc。
# 可选：strace（11 条判据依赖）、script（1 条）、qemu-arm（4 条，可用
#       QEMU_ARM=/路径/qemu-arm 指定；不装包、不登记 binfmt 也可，
#       例如 apt-get download qemu-user 后 dpkg-deb -x 解开使用）。
# 注错见红：给 crash.c 的 printf 后加一行 fflush(stdout);，第 4 节判据必须变红；
#           把 order.c 里 printf 和 write 两行对调，第 4 节顺序判据必须变红。

cd "$(dirname "$0")" || exit 1

# 输出文件放本机临时目录：C 库的全缓冲大小取自目标文件所在文件系统的
# st_blksize，/mnt/*（DrvFs）上是 512 而不是 4096，write 次数会不一样。
TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT

CC=arm-linux-gnueabihf-gcc
OD=arm-linux-gnueabihf-objdump
QEMU="${QEMU_ARM:-$(command -v qemu-arm 2>/dev/null)}"

PASS=0; FAIL=0; SKIP=0
ok()   { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
no()   { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -n "$2" ] && printf '        %s\n' "$2"; }
skip() { SKIP=$((SKIP+1)); printf '  SKIP  %s\n' "$1"; }
eq()   { if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "期望 [$3]，实得 [$2]"; fi; }
has()  { if echo "$2" | grep -qE "$3"; then ok "$1"; else no "$1" "输出里找不到 $3"; fi; }

die() {
	FAIL=$((FAIL+1))
	printf '  FAIL  构建：%s\n\n  %d PASS / %d FAIL / %d SKIP（构建没过）\n' "$1" "$PASS" "$FAIL" "$SKIP"
	exit 1
}

echo "=== 构建 ==="
for p in order crash errno_trip priv lines vdso; do
	gcc -O2 -Wall $p.c -o $p 2>/dev/null || die "$p.c 编译不过"
done
gcc -O2 -Wall rawsys.c -o rawsys 2>/dev/null || die "rawsys.c 编译不过"
gcc -nostdlib -static tiny_x86.S -o tiny_x86 2>/dev/null || die "tiny_x86.S 汇编/链接不过"
$CC -static -O1 w.c -o w_static 2>/dev/null || die "w.c ARM 静态版编译不过"
$CC         -O1 w.c -o w_dyn    2>/dev/null || die "w.c ARM 动态版编译不过"
gcc -O1 -Wall w.c -o w_x86 2>/dev/null || die "w.c x86 版编译不过"
$CC -O2 -static -Wall rawsys.c -o rawsys_arm 2>/dev/null || die "rawsys.c ARM 版编译不过"
$CC -O2 -Wall -static priv.c -o priv_arm 2>/dev/null || die "priv.c ARM 版编译不过"
$CC -nostdlib -static tiny_arm.S -o tiny_arm 2>/dev/null || die "tiny_arm.S 汇编/链接不过"
echo "  完成"
echo

echo "=== 07 篇 1.4  用户态凭什么碰不了硬件 ==="
OUT=$(./priv none 2>&1); RC=$?
eq "不碰硬件时程序正常走完（退出码 0）" "$RC" "0"
has "它打到了 survived 那一行" "$OUT" 'survived none'
bash -c './priv insn >/dev/null 2>&1' 2>/dev/null; RC=$?
eq "x86-64 用户态执行特权指令 cli：被 SIGSEGV 杀（139）" "$RC" "139"
bash -c './priv mmio >/dev/null 2>&1' 2>/dev/null; RC=$?
eq "x86-64 用户态写 UART1 物理地址：被 SIGSEGV 杀（139）" "$RC" "139"
if [ -n "$QEMU" ]; then
	bash -c '"$0" ./priv_arm insn >/dev/null 2>&1' "$QEMU" 2>/dev/null; RC=$?
	eq "ARM 用户态读 CP15 寄存器：被 SIGILL 杀（132）" "$RC" "132"
	bash -c '"$0" ./priv_arm mmio >/dev/null 2>&1' "$QEMU" 2>/dev/null; RC=$?
	eq "ARM 用户态写 UART1 物理地址：被 SIGSEGV 杀（139）" "$RC" "139"
else
	skip "qemu-arm 不在，ARM 版特权指令实验跳过 x2"
fi
echo

echo "=== 07 篇 2.6  找到那条 svc ==="
NS=$($OD -d w_static | grep -c '\bsvc\b')
ND=$($OD -d w_dyn    | grep -c '\bsvc\b')
if [ "$NS" -gt 0 ]; then ok "静态链接的 ARM 程序里有 $NS 条 svc"; else no "静态版应当有 svc"; fi
eq "动态链接的 ARM 程序里 0 条 svc（封装在 libc.so.6 里）" "$ND" "0"
has "__getpid 就三条指令：装 20 号、svc、返回" \
    "$($OD -d w_static | sed -n '/<__getpid>:/,/bx/p')" 'mov.*r7, #20'
has "通用封装 __libc_do_syscall：号从 ip 进 r7 再 svc" \
    "$($OD -d w_static | sed -n '/<__libc_do_syscall>:/,/pop/p')" 'mov.*r7, ip'
has "ARM 上 open 的封装 __open_nocancel：322 号经 ip 进 r7 再 svc" \
    "$($OD -d w_static | sed -n '/<__open_nocancel>:/,/bx/p')" '#322'
if command -v strace >/dev/null 2>&1; then
	STO=$(strace -e trace=open,openat ./w_x86 2>&1 >/dev/null)
	has "源码写 open，x86 上实际发的也是 openat" "$STO" 'openat\(AT_FDCWD, "/etc/hostname"'
	if echo "$STO" | grep -qE '^open\('; then
		no "strace 里不应出现 open( 这个调用本身"
	else
		ok "strace 里看不到 open(，glibc 已经把它换成了 openat"
	fi
else
	skip "strace 未安装，open→openat 判据跳过 x2"
fi
echo

echo "=== 07 篇 3.6  不经过 C 库发系统调用 ==="
if grep -q 'stdio\.h' rawsys.c raw.h; then
	no "rawsys.c / raw.h 不该 include stdio.h"
else
	ok "rawsys.c 和 raw.h 都没有 include stdio.h"
fi
eq "不经过 C 库照样打出字符串" "$(./rawsys)" "hello from raw syscall"
if command -v strace >/dev/null 2>&1; then
	has "strace 证明那是一次真正的 write 系统调用" \
	    "$(strace -e trace=write ./rawsys 2>&1 >/dev/null)" 'write\(1, "hello from raw syscall\\n", 23\) += 23'
else
	skip "strace 未安装"
fi
if $OD -d rawsys_arm | grep -q '\bsvc\b'; then ok "同一份源码交叉编译后，ARM 版里是 svc 指令"; else no "ARM 版应当有 svc"; fi
if [ -n "$QEMU" ]; then
	eq "qemu-arm 跑 ARM 版，输出与 x86 版逐字节相同" "$("$QEMU" ./rawsys_arm)" "hello from raw syscall"
else
	skip "qemu-arm 不在，ARM 版 rawsys 跳过"
fi
ET=$(./errno_trip)
eq "直接发：内核把 -9（-EBADF）原样放在返回值里" "$(echo "$ET" | sed -n 1p)" "raw  write(99) = -9"
has "经 C 库：返回 -1，错误号被搬进 errno" \
    "$(echo "$ET" | sed -n 2p)" 'libc write\(99\) = -1, errno = 9 \(Bad file descriptor\)'
echo

echo "=== 07 篇 3.7  连 C 库都不链接的最小程序 ==="
eq "tiny_x86 打出了那行字" "$(./tiny_x86)" "hi from syscall"
./tiny_x86 >/dev/null 2>&1; RC=$?
eq "tiny_x86 用 exit 系统调用交回 7" "$RC" "7"
NTA=$($OD -d tiny_arm | grep -c '\bsvc\b')
eq "tiny_arm 一共就两条 svc（write 和 exit）" "$NTA" "2"
has "tiny_arm：4 号（write）和 1 号（exit）都装进 r7" \
    "$($OD -d tiny_arm | grep -E 'r7, #(4|1)$' | wc -l)" '^2$'
if [ -n "$QEMU" ]; then
	OUT=$("$QEMU" ./tiny_arm); RC=$?
	eq "qemu-arm 跑 tiny_arm，打出 hi from svc" "$OUT" "hi from svc"
	eq "qemu-arm 跑 tiny_arm，退出码同样是 7" "$RC" "7"
else
	skip "qemu-arm 不在，tiny_arm 上机验证跳过 x2"
fi
echo

echo "=== 07 篇 4.6  C 库缓冲与内核缓冲 ==="
PIPE=$(./order | cat)
eq "order 接管道（全缓冲）：B_write 先出" "$(echo "$PIPE" | head -1)" "B_write"
./order > .f.txt
eq "order 接文件（全缓冲）：B_write 先出" "$(head -1 .f.txt)" "B_write"
if command -v script >/dev/null 2>&1; then
	TTY=$(script -qc './order' /dev/null | tr -d '\r')
	eq "order 接终端（行缓冲）：A_printf 先出" "$(echo "$TTY" | head -1)" "A_printf"
else
	skip "script 未安装，测不到「接终端」这一档"
fi
if command -v strace >/dev/null 2>&1; then
	strace -e trace=write -o .st.txt ./order >/dev/null 2>&1
	SORDER=$(grep -oE 'write\(1, "[AB]_[a-z]+' .st.txt | head -2 | tr '\n' ' ')
	has "strace 看到内核收到的顺序确实是 B 在前" "$SORDER" 'B_write.*A_printf'

	strace -e trace=write -o "$TMPD/l.txt" ./lines 1000 > "$TMPD/lines.txt" 2>/dev/null
	NL=$(grep -c '^write(' "$TMPD/l.txt")
	eq "printf 1000 行（接文件，全缓冲）只发了 3 次 write" "$NL" "3"
	LENS=$(grep '^write(' "$TMPD/l.txt" | sed 's/.* = //' | tr '\n' ' ' | sed 's/ $//')
	eq "三次 write 的长度是 4096 + 4096 + 1808" "$LENS" "4096 4096 1808"
	strace -e trace=write -o "$TMPD/l2.txt" ./lines 1000 line > "$TMPD/x" 2>/dev/null
	eq "改成行缓冲后，1000 行发了 1000 次 write" "$(grep -c '^write(' "$TMPD/l2.txt")" "1000"
	strace -e trace=write -o "$TMPD/l3.txt" ./lines 1000 2>/dev/null | cat >/dev/null
	eq "接管道同样是全缓冲：3 次 write" "$(grep -c '^write(' "$TMPD/l3.txt")" "3"
	strace -e trace=write -o "$TMPD/l4.txt" ./lines 1000 err >/dev/null 2>&1
	eq "stderr 永远无缓冲：1000 次 write" "$(grep -c '^write(' "$TMPD/l4.txt")" "1000"
	rm -f .st.txt
else
	skip "strace 未安装，write 次数系列跳过 x6"
fi
./lines 1000 > .lines.txt 2>/dev/null
eq "1000 行共 10000 字节，与 write 长度对账一致" "$(stat -c %s .lines.txt)" "10000"
rm -f .lines.txt .f.txt
echo

echo "=== 07 篇 4.7  崩溃时 printf 的内容会丢 ==="
bash -c './crash > .out.txt' 2>/dev/null; RC=$?
eq "crash 是被信号打死的（退出码 139 = 128 + SIGSEGV）" "$RC" "139"
eq "重定向到文件时，printf 的内容全丢（0 字节）" "$(stat -c %s .out.txt)" "0"
sed 's|\*(int \*)0 = 1;|fflush(stdout);\n\t*(int *)0 = 1;|' crash.c > .c2.c
gcc .c2.c -o .c2 2>/dev/null
bash -c './.c2 > .out2.txt' 2>/dev/null
eq "加一行 fflush 之后就不丢了（13 字节）" "$(stat -c %s .out2.txt)" "13"
eq "内容是 before crash" "$(cat .out2.txt)" "before crash"
rm -f .c2.c .c2 .out.txt .out2.txt
echo

echo "=== 07 篇 5.4  vDSO：不进内核的系统调用 ==="
T_LIBC=$(./vdso 200000 libc | awk '{print $4}' | tr -d ',')
T_SYS=$(./vdso 200000 sys  | awk '{print $4}' | tr -d ',')
if awk -v a="$T_LIBC" -v b="$T_SYS" 'BEGIN{exit !(a+0 > 0 && b+0 > 0)}'; then
	ok "两种取时间的方式都跑通（libc $T_LIBC ns/次，sys $T_SYS ns/次）"
else
	no "vdso 计时输出异常" "libc=$T_LIBC sys=$T_SYS"
fi
if awk -v a="$T_LIBC" -v b="$T_SYS" 'BEGIN{exit !(a < b/2)}'; then
	ok "经 vDSO（libc）比真发系统调用（sys）快一倍以上"
else
	no "vDSO 应当明显更快" "libc=$T_LIBC sys=$T_SYS"
fi
DOUT=$(./vdso dump .vdso.so)
has "内核把 vDSO 映射在进程地址空间里（[vdso] 段存在）" "$DOUT" 'maps: \[vdso\] 0x[0-9a-f]+-0x[0-9a-f]+'
LO1=$(echo "$DOUT" | sed -n 's/maps: \[vdso\] \(0x[0-9a-f]*\)-.*/\1/p')
LO2=$(echo "$DOUT" | sed -n 's/auxv: AT_SYSINFO_EHDR = \(0x[0-9a-f]*\)/\1/p')
eq "AT_SYSINFO_EHDR 指向的就是 [vdso] 段开头" "$LO2" "$LO1"
has "dump 出来的 vDSO 是一个 ELF 共享库" "$(file .vdso.so)" 'ELF 64-bit LSB shared object'
has "里面导出 __vdso_clock_gettime 等函数" "$(nm -D .vdso.so 2>/dev/null)" '__vdso_clock_gettime'
if command -v strace >/dev/null 2>&1; then
	strace -c -e trace=clock_gettime ./vdso 50000 >/dev/null 2>"$TMPD/v1.txt"
	eq "libc 版 50000 次取时间，strace 一次 clock_gettime 都看不到" \
	    "$(grep -c 'clock_gettime' "$TMPD/v1.txt")" "0"
	strace -c -e trace=clock_gettime ./vdso 50000 sys >/dev/null 2>"$TMPD/v2.txt"
	eq "sys 版 50000 次，strace 看到 50000 次 clock_gettime" \
	    "$(awk '$NF=="clock_gettime"{print $4}' "$TMPD/v2.txt")" "50000"
else
	skip "strace 未安装，vDSO 计数判据跳过 x2"
fi
rm -f .vdso.so
echo

echo "======================================"
printf '  %d PASS / %d FAIL / %d SKIP\n' "$PASS" "$FAIL" "$SKIP"
echo "======================================"
[ "$FAIL" -eq 0 ]
