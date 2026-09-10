#!/bin/bash
# 00_基础 第 00、01 篇的判据自动核对
#
# 用法：bash check.sh
# 它会从源码重新构建一遍，然后逐条核对两篇笔记里的判据。
#
# 每条判据的编号对应笔记里的小节号，失败时先回去看那一节。
# 注错见红：随便改坏一处（比如把 add.c 的函数名改掉），必须有判据变红。

cd "$(dirname "$0")" || exit 1

CC=arm-linux-gnueabihf-gcc
NM=arm-linux-gnueabihf-nm
OBJDUMP=arm-linux-gnueabihf-objdump
READELF=arm-linux-gnueabihf-readelf
BIG=../../01_toolchain          # big1 / big2 在 01 章的实验目录

PASS=0
FAIL=0
SKIP=0

ok()   { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
no()   { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -n "$2" ] && printf '        %s\n' "$2"; }
skip() { SKIP=$((SKIP+1)); printf '  SKIP  %s\n' "$1"; }

# 判断两个值是否相等
eq() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "期望 $3，实得 $2"; fi; }
# 判断两个值是否不等
ne() { if [ "$2" != "$3" ]; then ok "$1"; else no "$1" "两值不该相等，都是 $2"; fi; }

echo "=== 构建 ==="
rm -f main.o add.o app app.map app_x86 main.i main.s maps app_strip app_nosh

# 构建失败不静默退出：先说清楚是哪一步、对应笔记哪一节，再收工。
die() {
	FAIL=$((FAIL+1))
	printf '  FAIL  构建：%s\n' "$1"
	printf '        %s\n' "$2"
	printf '\n  %d PASS / %d FAIL / %d SKIP（构建没过，判据一条都没跑）\n' \
	       "$PASS" "$FAIL" "$SKIP"
	exit 1
}

$CC -c main.c -o main.o || die "main.c 编译不过" "语法错误，看编译器报的行号"
$CC -c add.c  -o add.o  || die "add.c 编译不过"  "语法错误，看编译器报的行号"
$CC main.o add.o -o app -Wl,-Map=app.map \
	|| die "链接不过（undefined reference）" \
	       "正是 00 篇 3.5 讲的现象：某个符号谁都没定义。看上面报的符号名"
$CC -E main.c -o main.i
$CC -S main.c -o main.s
gcc main.c add.c -o app_x86 || die "x86 版编译不过" "本机 gcc 有问题，或源码被改坏"
gcc maps.c -o maps          || die "maps.c 编译不过" "看 00 篇 5.2 的源码"
echo "  完成"
echo

echo "=== 00 篇 2.6  四个程序 ==="
V=$($CC -c main.c -o /tmp/_chk.o -v 2>&1)
echo "$V" | grep -q 'cc1'  && ok "gcc -v 里出现 cc1（真正的编译器）" || no "gcc -v 里出现 cc1"
echo "$V" | grep -q '/as ' && ok "gcc -v 里出现 as（汇编器）"        || no "gcc -v 里出现 as"
LC=$(wc -l < main.c); LI=$(wc -l < main.i); LS=$(wc -l < main.s)
if [ "$LC" -lt "$LI" ] && [ "$LI" -lt "$LS" ]; then
	ok "行数满足 main.c($LC) < main.i($LI) < main.s($LS)"
else
	no "行数递增" "c=$LC i=$LI s=$LS"
fi
grep -q 'bl.*add' main.s && ok "main.s 里 bl 后面还是函数名（文本）" || no "main.s 里有 bl add"
echo

echo "=== 00 篇 3.7  链接器在干什么 ==="
$NM main.o | grep -qE '^ +U add' && ok "nm main.o 里 add 是 U（未定义）" || no "add 应该是 U"
ZERO=$($NM main.o | grep -cE '^00000000 [TDB]')
eq "main/g_init/g_bss 在 .o 里地址都是 0（共 3 个）" "$ZERO" "3"

# 便条上的偏移，与 bl 指令的偏移必须一致
RELOFF=$($READELF -r main.o | awk '$5=="add"{print strtonum("0x"$1)}')
BLOFF=$($OBJDUMP -d main.o | awk '/\tbl\t/{sub(":","",$1); print strtonum("0x"$1); exit}')
eq "重定位便条的 Offset == bl 指令的偏移" "$RELOFF" "$BLOFF"

ERR=$($CC main.o -o /tmp/_chk_bad 2>&1)
echo "$ERR" | grep -q 'undefined reference to' \
	&& ok "只链 main.o 时报 undefined reference（链接器发的话）" \
	|| no "应报 undefined reference"

# 链接后四个符号地址必须互不相同
CNT=$($NM app | grep -E ' (main|add|g_init|g_bss)$' | awk '{print $1}' | sort -u | wc -l)
eq "链接后四个符号地址互不相同" "$CNT" "4"

# bl 的机器码必须已经不是占位模式
$OBJDUMP -d main.o | grep -q 'f7ff fffe' && ok "链接前 bl 机器码是占位 f7ff fffe" || no "链接前应是 f7ff fffe"
$OBJDUMP -d app | grep -A 20 '<main>:' | grep -q 'f7ff fffe' \
	&& no "链接后 bl 机器码仍是占位，说明没被填" \
	|| ok "链接后 bl 机器码已被改写"

# 手算：bl 地址 + 4 + 偏移 == add 地址
ADDADDR=$($NM app | awk '$3=="add"{print $1}')
# 只看 main 函数体内的那条 bl；文件里还有 crt 启动代码的 bl，别抓错
TGT=$($OBJDUMP -d app | awk '/<main>:/{f=1} f&&/\tbl\t/{print $(NF-1); exit}')
eq "bl 的目标地址 == nm 查到的 add 地址" "$(printf '%08x' $((0x$TGT)))" "$ADDADDR"
echo

echo "=== 00 篇 4.3  section 是链接器搬运的箱子 ==="
# readelf -S 每行前面有 [ N] 编号，先剥掉再取字段（编号有无空格取决于位数）
TSIZE=$($READELF -S main.o | sed 's/^ *\[ *[0-9]*\] *//' | awk '$1==".text"{print $5}')
MSIZE=$(awk '/^ \.text .*main\.o$/{print $3}' app.map | sed 's/^0x//')
eq "readelf 里 .text 大小 == app.map 里 main.o 那块的长度" \
   "$((0x$TSIZE))" "$((0x$MSIZE))"

MSTART=$(awk '/^ \.text .*main\.o$/{print $2}' app.map)
ASTART=$(awk '/^ \.text .*add\.o$/{print $2}' app.map)
eq "main.o 起始 + 长度 == add.o 起始（首尾相接）" \
   "$(($MSTART + 0x$MSIZE))" "$((ASTART))"

eq "app.map 里 main.o 的地址 == nm 查到的 main 地址" \
   "$(printf '%08x' $((MSTART)))" "$($NM app | awk '$3=="main"{print $1}')"

awk '/^ \.text /' app.map | grep -qE 'crt|Scrt' \
	&& ok "app.map 里有你没写过的 .o（C 运行时启动代码）" \
	|| no "应能找到 Scrt1.o / crti.o 之类"
echo

echo "=== 00 篇 5.5  加载器摆出来的样子 ==="
OUT=$(./maps)
XLINE=$(echo "$OUT" | grep -E 'r-xp.*maps$' | head -1)
WLINE=$(echo "$OUT" | grep -E 'rw-p.*maps$' | head -1)
[ -n "$XLINE" ] && ok "maps 里有且能找到带 x 权限的那行" || no "找不到 r-xp 行"
[ -n "$WLINE" ] && ok "maps 里有带 w 不带 x 的那行"      || no "找不到 rw-p 行"

in_range() {   # $1=地址 $2=形如 aaaa-bbbb 的区间
	local a=$((0x$1)) lo=$((0x${2%%-*})) hi=$((0x${2##*-}))
	[ "$a" -ge "$lo" ] && [ "$a" -lt "$hi" ]
}
MAINA=$(echo "$OUT" | awk -F'=0x' '/&main/{print $2}')
INITA=$(echo "$OUT" | awk -F'=0x' '/&g_init/{print $2}')
in_range "$MAINA" "$(echo "$XLINE" | awk '{print $1}')" \
	&& ok "&main 落在带 x 权限的区间内" || no "&main 不在 r-xp 区间"
in_range "$INITA" "$(echo "$WLINE" | awk '{print $1}')" \
	&& ok "&g_init 落在带 w 权限的区间内" || no "&g_init 不在 rw-p 区间"

A1=$(./maps | awk -F'=0x' '/&main/{print $2}')
A2=$(./maps | awk -F'=0x' '/&main/{print $2}')
ne "两次运行 &main 不同（ASLR 生效）" "$A1" "$A2"
eq "但末三位十六进制相同（块内偏移是定死的）" "${A1: -3}" "${A2: -3}"
eq "g_bss 未赋值却是 0（加载器清的零）" "$(./maps | awk -F= '/^g_bss/{print $2}')" "0"
echo

echo "=== 01 篇 2.5  ELF 头 ==="
eq "前 4 字节是 ELF 魔数" \
   "$(hexdump -n4 -e '4/1 "%02x"' app)" "7f454c46"
eq "ARM 版 e_machine（偏移 0x12）是 28 00" \
   "$(hexdump -s 18 -n2 -e '2/1 "%02x"' app)" "2800"
eq "x86 版 e_machine 是 3e 00" \
   "$(hexdump -s 18 -n2 -e '2/1 "%02x"' app_x86)" "3e00"

# 入口点不是 main
ENTRY=$($READELF -h app | awk '/Entry point/{print $NF}')
MAINADDR=0x$($NM app | awk '$3=="main"{print $1}')
ne "Entry point 不等于 main 的地址（入口是 _start）" "$((ENTRY))" "$((MAINADDR))"
echo

echo "=== 01 篇 3.7  section 删得、segment 删不得 ==="
SZ0=$(stat -c %s app_x86)
SEC0=$(readelf -S app_x86 | grep -cE '^  \[')
SEG0=$(readelf -l app_x86 | grep -c '^  [A-Z]')
./app_x86; RC0=$?

cp app_x86 app_strip && strip app_strip
SZ1=$(stat -c %s app_strip)
SEC1=$(readelf -S app_strip | grep -cE '^  \[')
SEG1=$(readelf -l app_strip | grep -c '^  [A-Z]')
./app_strip; RC1=$?

[ "$SZ1" -lt "$SZ0" ] && ok "strip 后文件变小（$SZ0 -> $SZ1）" || no "strip 后应变小"
[ "$SEC1" -lt "$SEC0" ] && ok "strip 后 section 变少（$SEC0 -> $SEC1）" || no "section 应变少"
eq "strip 后 segment 数不变" "$SEG1" "$SEG0"
eq "strip 后退出码不变（程序照跑）" "$RC1" "$RC0"

cp app_x86 app_nosh
if strip --strip-section-headers app_nosh 2>/dev/null; then
	./app_nosh; RC2=$?
	eq "整张 section 表删光后，section 数为 0" \
	   "$(readelf -h app_nosh | awk '/Number of section headers/{print $NF}')" "0"
	eq "整张 section 表删光后，程序仍跑出同样退出码" "$RC2" "$RC0"
else
	skip "--strip-section-headers（binutils 版本不支持）"
	skip "--strip-section-headers 后仍能运行"
fi

cp app_x86 app_noph
printf '\x00\x00' | dd of=app_noph bs=1 seek=56 conv=notrunc status=none
./app_noph 2>/dev/null; RC3=$?
eq "把 segment 数改成 0 后无法执行（退出码 126）" "$RC3" "126"
eq "而它的文件大小没变（只改了 2 个字节）" "$(stat -c %s app_noph)" "$SZ0"
rm -f app_noph
echo

echo "=== 01 篇 4.6  .bss 的减法 ==="
if [ -f "$BIG/big1" ] && [ -f "$BIG/big2" ]; then
	B1=$(stat -c %s $BIG/big1); B2=$(stat -c %s $BIG/big2)
	eq "big2 - big1 == 4,000,000" "$((B2-B1))" "4000000"

	$READELF -S $BIG/big1 | grep -qE '\.bss +NOBITS' && ok "big1 的 .bss 是 NOBITS" || no "big1 .bss 应是 NOBITS"
	B1BSS=$($READELF -S $BIG/big1 | sed 's/^ *\[ *[0-9]*\] *//' | awk '$1==".bss"{print $5}')
	B2DATA=$($READELF -S $BIG/big2 | sed 's/^ *\[ *[0-9]*\] *//' | awk '$1==".data"{print $5}')
	[ $((0x$B1BSS)) -gt 4000000 ] && ok "big1 的数组在 .bss 里（大小 $((0x$B1BSS))）" || no "big1 .bss 应超过 4MB"
	[ $((0x$B2DATA)) -gt 4000000 ] && ok "big2 的数组在 .data 里（大小 $((0x$B2DATA))）" || no "big2 .data 应超过 4MB"

	read -r F1 M1 <<< "$($READELF -l $BIG/big1 | awk '/^  LOAD/&&$7=="RW"{print $5, $6}')"
	read -r F2 M2 <<< "$($READELF -l $BIG/big2 | awk '/^  LOAD/&&$7=="RW"{print $5, $6}')"
	eq "big1 的 RW 段 MemSiz - FileSiz == 4,000,004" "$((0x${M1#0x} - 0x${F1#0x}))" "4000004"
	eq "big1 与 big2 的 MemSiz 完全相等（内存一分没省）" "$((0x${M1#0x}))" "$((0x${M2#0x}))"
	LOADS=$($READELF -l $BIG/big1 | grep -c '^  LOAD')
	eq "big1 有 2 条 PT_LOAD" "$LOADS" "2"
else
	skip "big1/big2 不存在（先做 01 篇第四节的实验）×6"
fi
echo

echo "=== 01 篇 5.5  静态链接就没有解释器 ==="
if gcc -static main.c add.c -o /tmp/_chk_static 2>/dev/null; then
	eq "静态链接后没有 INTERP" \
	   "$(readelf -l /tmp/_chk_static | grep -c INTERP)" "0"
	[ "$(stat -c %s /tmp/_chk_static)" -gt "$SZ0" ] \
		&& ok "静态版比动态版大（libc 被整个塞了进去）" || no "静态版应更大"
	/tmp/_chk_static; eq "静态版行为不变" "$?" "$RC0"
	rm -f /tmp/_chk_static
else
	skip "gcc -static 不可用（未装 glibc 静态库）×3"
fi
echo

rm -f /tmp/_chk.o /tmp/_chk_bad
echo "======================================"
printf '  %d PASS / %d FAIL / %d SKIP\n' "$PASS" "$FAIL" "$SKIP"
echo "======================================"
[ "$FAIL" -eq 0 ]
