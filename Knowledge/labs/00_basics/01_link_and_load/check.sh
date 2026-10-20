#!/bin/bash
# fundamentals 00 篇、01 篇的判据自动核对
#
# 用法：bash check.sh
# 从源码重建一切，再逐条核对两篇正文里的判据。
# 每组的标题对应正文小节号，失败时先回去看那一节。
# 注错见红：随便改坏一处源码（比如把 add.c 的函数名改掉），必须有判据变红。

cd "$(dirname "$0")" || exit 1

CC=arm-linux-gnueabihf-gcc
NM=arm-linux-gnueabihf-nm
OBJDUMP=arm-linux-gnueabihf-objdump
READELF=arm-linux-gnueabihf-readelf
OBJCOPY=arm-linux-gnueabihf-objcopy

PASS=0
FAIL=0
SKIP=0

ok()   { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
no()   { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -n "$2" ] && printf '        %s\n' "$2"; }
skip() { SKIP=$((SKIP+1)); printf '  SKIP  %s\n' "$1"; }

# 判断两个值是否相等 / 不等
eq() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "期望 $3，实得 $2"; fi; }
ne() { if [ "$2" != "$3" ]; then ok "$1"; else no "$1" "两值不该相等，都是 $2"; fi; }

echo "=== 构建 ==="
rm -f main.o add.o app app.map app_x86 app_static main.i main.s maps wtext \
      big1 big2 app_strip app_nosh app_noph app_rv app.bin

# 构建失败不静默退出：先说清楚是哪一步，再收工。
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
	       "正是 00 篇第 5 节讲的现象：某个符号谁都没定义。看上面报的符号名"
$CC -E main.c -o main.i
$CC -S main.c -o main.s
$CC -o big1 big1.c || die "big1.c 编译不过" "看 01 篇第 4 节"
$CC -o big2 big2.c || die "big2.c 编译不过" "看 01 篇第 4 节"
gcc main.c add.c -o app_x86 || die "x86 版编译不过" "本机 gcc 有问题，或源码被改坏"
if gcc -static main.c add.c -o app_static 2>/dev/null; then
	STATIC_OK=1
else
	STATIC_OK=0
fi
gcc maps.c  -o maps  || die "maps.c 编译不过"  "看 00 篇第 7 节的源码"
gcc wtext.c -o wtext || die "wtext.c 编译不过" "看 00 篇第 7 节的源码"
echo "  完成"
echo

echo "=== 00 篇第 1 节  gcc 是调度员 ==="
V=$(gcc -v main.c add.c -o /tmp/_chk_x86 2>&1)
echo "$V" | grep -q 'cc1'      && ok "gcc -v 里出现 cc1（真正的编译器）"   || no "gcc -v 里应出现 cc1"
echo "$V" | grep -qE '[/-]as ' && ok "gcc -v 里出现 as（汇编器）"          || no "gcc -v 里应出现 as"
echo "$V" | grep -q 'collect2' && ok "gcc -v 里出现 collect2（链接的封装）" || no "gcc -v 里应出现 collect2"
ST=$(strace -f -qq -e trace=execve -e signal=none gcc main.c add.c -o /tmp/_chk_x86b 2>&1)
echo "$ST" | grep -q 'execve("/usr/libexec/gcc/x86_64-linux-gnu/15/cc1"' \
	&& ok "strace 抓到 gcc 启动 cc1" || no "strace 应抓到 cc1"
echo "$ST" | grep -q 'execve("/usr/bin/x86_64-linux-gnu-as"' \
	&& ok "strace 抓到 gcc 启动 as"  || no "strace 应抓到 as"
echo "$ST" | grep -q 'execve("/usr/libexec/gcc/x86_64-linux-gnu/15/collect2"' \
	&& ok "strace 抓到 gcc 启动 collect2" || no "strace 应抓到 collect2"
echo "$ST" | grep -q 'execve("/usr/bin/ld"' \
	&& ok "strace 抓到 collect2 启动 ld（第四层）" || no "strace 应抓到 ld"
EV=$($CC -E -v main.c -o /tmp/_chk.i 2>&1)
echo "$EV" | grep -qE 'cc1 .*-E' \
	&& ok "gcc -E 干活的是 cc1 -E（预处理器已并进编译器）" \
	|| no "gcc -E 应看到 cc1 带 -E"
rm -f /tmp/_chk_x86 /tmp/_chk_x86b /tmp/_chk.i
echo

echo "=== 00 篇第 2、3 节  中间产物都是文本 ==="
file main.i | grep -q 'C source'         && ok "main.i 仍是 C 文本"        || no "main.i 应是 C 文本"
file main.s | grep -q 'assembler source' && ok "main.s 是汇编文本"         || no "main.s 应是汇编文本"
file main.o | grep -qE 'ELF 32-bit.*relocatable.*ARM' \
	&& ok "main.o 是 ARM 的 ELF 目标文件" || no "main.o 应是 ELF relocatable ARM"
LC=$(wc -l < main.c); LI=$(wc -l < main.i); LS=$(wc -l < main.s)
if [ "$LC" -lt "$LI" ] && [ "$LI" -lt "$LS" ]; then
	ok "行数满足 main.c($LC) < main.i($LI) < main.s($LS)"
else
	no "行数递增" "c=$LC i=$LI s=$LS"
fi
grep -q 'return add(g_init, 2) + g_bss;' main.i \
	&& ok "main.i 里 main 的函数体原样还在（预处理不改写代码）" \
	|| no "main.i 里应能找到 main 的函数体"
printf '#include <stdio.h>\n' > /tmp/_chk_t.c && cat main.c >> /tmp/_chk_t.c
$CC -E /tmp/_chk_t.c -o /tmp/_chk_t.i
TL=$(wc -l < /tmp/_chk_t.i)
[ "$TL" -gt 800 ] && ok "加一行 stdio.h 后预处理结果 $TL 行（>800）" \
	|| no "stdio.h 展开应超过 800 行" "实得 $TL"
grep -q 'bl	add' main.s && ok "main.s 里 bl 后面还是函数名（文本）" \
	|| no "main.s 里应有 bl add"
rm -f /tmp/_chk_t.c /tmp/_chk_t.i
echo

echo "=== 00 篇第 4 节  .o 里的空条子与便条 ==="
$NM main.o | grep -qE '^ +U add' && ok "nm main.o 里 add 是 U（未定义）" || no "add 应该是 U"
ZERO=$($NM main.o | grep -cE '^00000000 [TDB]')
eq "main/g_init/g_bss 在 .o 里地址都是 0（共 3 个）" "$ZERO" "3"
$OBJDUMP -d main.o | grep -q 'f7ff fffe' \
	&& ok "main.o 里 bl 的机器码是占位 f7ff fffe" || no "链接前应是 f7ff fffe"
RELOFF=$($READELF -r main.o | awk '$5=="add"{print strtonum("0x"$1)}')
BLOFF=$($OBJDUMP -d main.o | awk '/\tbl\t/{sub(":","",$1); print strtonum("0x"$1); exit}')
eq "重定位便条的 Offset == bl 指令的偏移" "$RELOFF" "$BLOFF"
$OBJDUMP -dr main.o | grep -q 'R_ARM_THM_CALL	add' \
	&& ok "objdump -dr 把便条贴在 bl 指令旁边" || no "应看到 R_ARM_THM_CALL add"
$OBJCOPY -R .rel.text main.o /tmp/_chk_norel.o
$OBJDUMP -d /tmp/_chk_norel.o | grep -qE '	bl	e <main\+0xe>' \
	&& ok "删掉便条后，同一份机器码被显示成跳向自己（便条是另一份数据）" \
	|| no "删便条后 bl 应显示为跳向自己"
rm -f /tmp/_chk_norel.o
echo

echo "=== 00 篇第 5 节  链接器干什么 ==="
ERR=$($CC main.o -o /tmp/_chk_bad 2>&1)
echo "$ERR" | grep -q 'undefined reference to' \
	&& ok "只链 main.o 时报 undefined reference（链接器发的话）" \
	|| no "应报 undefined reference"
echo "$ERR" | grep -qF '(.text+0xe)' \
	&& ok "报错里的偏移 (.text+0xe) 与便条上的 Offset 一致" \
	|| no "报错应含 (.text+0xe)"
CNT=$($NM app | grep -E ' (main|add|g_init|g_bss)$' | awk '{print $1}' | sort -u | wc -l)
eq "链接后四个符号地址互不相同" "$CNT" "4"
$OBJDUMP -d app | grep -A 20 '<main>:' | grep -q 'f7ff fffe' \
	&& no "链接后 bl 机器码已被改写" "链接后仍是占位 f7ff fffe" \
	|| ok "链接后 bl 机器码已被改写"
ADDADDR=$($NM app | awk '$3=="add"{print $1}')
# 只看 main 函数体内的那条 bl；文件里还有 crt 启动代码的 bl，别抓错
TGT=$($OBJDUMP -d app | awk '/<main>:/{f=1} f&&/\tbl\t/{print $(NF-1); exit}')
eq "bl 的目标地址 == nm 查到的 add 地址" "$(printf '%08x' $((0x$TGT)))" "$ADDADDR"
rm -f /tmp/_chk_bad
echo

echo "=== 00 篇第 6 节  section 是链接器搬运的箱子 ==="
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
DSIZE=$($READELF -S main.o | sed 's/^ *\[ *[0-9]*\] *//' | awk '$1==".data"{print $5}')
BSIZE=$($READELF -S main.o | sed 's/^ *\[ *[0-9]*\] *//' | awk '$1==".bss"{print $5}')
eq "main.o 的 .data 正好 4 字节（g_init 一个 int）" "$((0x$DSIZE))" "4"
eq "main.o 的 .bss  正好 4 字节（g_bss 一个 int）"  "$((0x$BSIZE))" "4"
echo

echo "=== 00 篇第 7 节  加载器摆出来的样子 ==="
OUT=$(./maps)
XLINE=$(echo "$OUT" | grep -E 'r-xp.*maps$' | head -1)
WLINE=$(echo "$OUT" | grep -E 'rw-p.*maps$' | head -1)
[ -n "$XLINE" ] && ok "maps 里能找到带 x 权限的那行" || no "找不到 r-xp 行"
[ -n "$WLINE" ] && ok "maps 里有带 w 不带 x 的那行"   || no "找不到 rw-p 行"
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
if setarch -R true 2>/dev/null; then
	B1=$(setarch -R ./maps | awk -F'=0x' '/&main/{print $2}')
	B2=$(setarch -R ./maps | awk -F'=0x' '/&main/{print $2}')
	eq "setarch -R 关掉 ASLR 后，两次运行地址完全相同" "$B1" "$B2"
else
	skip "setarch -R 不可用（内核不允许关掉 ASLR）"
fi
eq "g_bss 未赋值却是 0（加载器清的零）" "$(./maps | awk -F= '/^g_bss/{print $2}')" "0"
./wtext 2>/dev/null; eq "往 main 的代码里写，段错误，退出码 139" "$?" "139"
echo

echo "=== 01 篇第 2 节  ELF 文件头 ==="
eq "前 4 字节是 ELF 魔数" \
   "$(hexdump -n4 -e '4/1 "%02x"' app)" "7f454c46"
eq "ARM 版 e_machine（偏移 0x12）是 28 00" \
   "$(hexdump -s 18 -n2 -e '2/1 "%02x"' app)" "2800"
eq "x86 版 e_machine 是 3e 00" \
   "$(hexdump -s 18 -n2 -e '2/1 "%02x"' app_x86)" "3e00"
$READELF -h app | grep -q 'Class:.*ELF32' && readelf -h app_x86 | grep -q 'Class:.*ELF64' \
	&& ok "readelf 的 Class 与手数的第 4 字节一致（ELF32 / ELF64）" \
	|| no "Class 应与第 4 字节一致"
ENTRY=$($READELF -h app | awk '/Entry point/{print $NF}')
MAINADDR=0x$($NM app | awk '$3=="main"{print $1}')
ne "Entry point 不等于 main 的地址（入口是 _start）" "$((ENTRY))" "$((MAINADDR))"
STARTADDR=0x$($NM app | awk '$3=="_start"{print $1}')
eq "Entry point == _start 的地址 + 1（末位是 Thumb 标记）" \
   "$((ENTRY))" "$((STARTADDR + 1))"
echo

echo "=== 01 篇第 3 节  两张表 ==="
MAP=$($READELF -lW app)
SEGNO=$(echo "$MAP" | awk '/Section to Segment/{f=1;next} f&&/\.text/{print $1; exit}')
SEGLINE=$(echo "$MAP" | awk -v n="$SEGNO" '/^  [A-Z_]+  +0x/{if(c==n){print;exit} c++}')
echo "$SEGLINE" | grep -q 'LOAD' && echo "$SEGLINE" | grep -qE 'R E' \
	&& ok ".text 所在的段（第 $SEGNO 条）是 R E 的 LOAD" \
	|| no ".text 应在 R E 的 LOAD 里" "第 $SEGNO 条: $SEGLINE"
SEGNO2=$(echo "$MAP" | awk '/Section to Segment/{f=1;next} f&&/\.data/{print $1; exit}')
SEGLINE2=$(echo "$MAP" | awk -v n="$SEGNO2" '/^  [A-Z_]+  +0x/{if(c==n){print;exit} c++}')
echo "$SEGLINE2" | grep -q 'LOAD' && echo "$SEGLINE2" | grep -qE 'RW' \
	&& ok ".data 所在的段（第 $SEGNO2 条）是 RW 的 LOAD" \
	|| no ".data 应在 RW 的 LOAD 里" "第 $SEGNO2 条: $SEGLINE2"
$READELF -SW app | grep -qF '.symtab' \
	&& ! echo "$MAP" | awk '/Section to Segment/{f=1} f' | grep -qF '.symtab' \
	&& ok ".symtab 在文件里有，但不属于任何 segment（运行时不进内存）" \
	|| no ".symtab 应在文件里且不属于任何 segment"
read -r OFF1 VA1 AL1 <<< "$(echo "$MAP" | awk '/^  LOAD/{print $2, $3, $8; exit}')"
read -r OFF2 VA2 AL2 <<< "$(echo "$MAP" | awk '/^  LOAD/{print $2, $3, $8}' | sed -n 2p)"
if [ $(( (0x${VA1#0x} - 0x${OFF1#0x}) % 0x${AL1#0x} )) -eq 0 ] && \
   [ $(( (0x${VA2#0x} - 0x${OFF2#0x}) % 0x${AL2#0x} )) -eq 0 ]; then
	ok "两条 LOAD 的 VirtAddr 与 Offset 对 Align 同余（mmap 的页对齐约束）"
else
	no "LOAD 的 VirtAddr 与 Offset 应对 Align 同余"
fi

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
eq "把 program header 条数改成 0 后无法执行（退出码 126）" "$RC3" "126"
eq "而它的文件大小没变（只改了 2 个字节）" "$(stat -c %s app_noph)" "$SZ0"

cp app_x86 app_rv
printf '\xf3\x00' | dd of=app_rv bs=1 seek=18 conv=notrunc status=none
readelf -h app_rv | grep -q 'Machine:.*RISC-V' \
	&& ok "改 e_machine 后 readelf 认成 RISC-V" || no "readelf 应报 RISC-V"
./app_rv 2>/dev/null
eq "没有任何处理器认领 RISC-V，退出码 126" "$?" "126"

objcopy -O binary app_x86 app.bin && chmod +x app.bin
./app.bin 2>/dev/null
eq "剥成裸 bin 后内核认不出格式，退出码 126" "$?" "126"
[ "$(stat -c %s app.bin)" -lt "$SZ0" ] \
	&& ok "裸 bin 比 ELF 小（扔掉的是全部表和说明）" || no "裸 bin 应更小"
rm -f app_noph app_rv
echo

echo "=== 01 篇第 4 节  .bss 的减法 ==="
B1=$(stat -c %s big1); B2=$(stat -c %s big2)
eq "big2 - big1 == 4,000,000，一个字节不差" "$((B2-B1))" "4000000"
$READELF -SW big1 | grep -qE '\.bss +NOBITS' && ok "big1 的 .bss 是 NOBITS" || no "big1 .bss 应是 NOBITS"
B1BSS=$($READELF -SW big1 | sed 's/^ *\[ *[0-9]*\] *//' | awk '$1==".bss"{print $5}')
B2DATA=$($READELF -SW big2 | sed 's/^ *\[ *[0-9]*\] *//' | awk '$1==".data"{print $5}')
[ $((0x$B1BSS)) -gt 4000000 ] && ok "big1 的数组在 .bss 里（大小 $((0x$B1BSS))）" || no "big1 .bss 应超过 4MB"
[ $((0x$B2DATA)) -gt 4000000 ] && ok "big2 的数组在 .data 里（大小 $((0x$B2DATA))）" || no "big2 .data 应超过 4MB"
read -r F1 M1 <<< "$($READELF -lW big1 | awk '/^  LOAD/&&$7=="RW"{print $5, $6}')"
read -r F2 M2 <<< "$($READELF -lW big2 | awk '/^  LOAD/&&$7=="RW"{print $5, $6}')"
eq "big1 的 RW 段 MemSiz - FileSiz == 4,000,004" "$((0x${M1#0x} - 0x${F1#0x}))" "4000004"
eq "big1 与 big2 的 MemSiz 完全相等（内存一分没省）" "$((0x${M1#0x}))" "$((0x${M2#0x}))"
LOADS=$($READELF -lW big1 | grep -c '^  LOAD')
eq "big1 有 2 条 PT_LOAD（R E 和 RW）" "$LOADS" "2"
# 同名重编：.symtab 里记着源文件名，名字长度不同会让文件差几个字节
mkdir -p /tmp/_chk_big0
sed 's/{1}/{0}/' big2.c > /tmp/_chk_big0/big2.c
$CC -o /tmp/_chk_big0/big2 /tmp/_chk_big0/big2.c
eq "初值改成 {0} 后文件又变回和 big1 一样大（编译器放回 .bss）" \
   "$(stat -c %s /tmp/_chk_big0/big2)" "$B1"
rm -rf /tmp/_chk_big0
echo

echo "=== 01 篇第 5 节  从 execve 到 main ==="
TR=$(strace -e trace=execve,openat,mmap ./app_x86 2>&1)
echo "$TR" | head -1 | grep -q '^execve("./app_x86"' \
	&& ok "strace 第一行是 execve（一切从这里开始）" || no "第一行应是 execve"
echo "$TR" | grep -q 'openat(.*libc.so.6' \
	&& ok "main 还没跑，libc.so.6 已被打开（动态链接器干的）" || no "应看到打开 libc.so.6"
echo "$TR" | grep -q 'PROT_READ|PROT_EXEC' \
	&& ok "libc 的代码按 PROT_READ|PROT_EXEC 映射（对应 LOAD 的 R E）" \
	|| no "应看到 PROT_EXEC 的 mmap"
echo "$TR" | tail -1 | grep -q 'exited with 3' \
	&& ok "退出码 3 正是 main 里 return 的值" || no "应 exited with 3"
if [ "$STATIC_OK" = 1 ]; then
	eq "静态链接后没有 INTERP" \
	   "$(readelf -lW app_static | grep -c INTERP)" "0"
	TRS=$(strace -e trace=openat ./app_static 2>&1)
	echo "$TRS" | grep -q 'libc.so.6' \
		&& no "静态版运行时不再打开 libc.so.6" "strace 里出现了 libc.so.6" \
		|| ok "静态版运行时不再打开 libc.so.6"
	[ "$(stat -c %s app_static)" -gt "$SZ0" ] \
		&& ok "静态版比动态版大（libc 被整个塞了进去）" || no "静态版应更大"
	./app_static; eq "静态版行为不变（退出码一样）" "$?" "$RC0"
else
	skip "gcc -static 不可用（未装 glibc 静态库）x4"
fi
echo

echo "======================================"
printf '  %d PASS / %d FAIL / %d SKIP\n' "$PASS" "$FAIL" "$SKIP"
echo "======================================"
[ "$FAIL" -eq 0 ]
