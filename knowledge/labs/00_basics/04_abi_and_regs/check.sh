#!/bin/bash
# 00_基础 第 02 篇（ARM 寄存器与调用约定）、第 03 篇（ABI 与 sysroot）判据核对
#
# 用法：bash check.sh
# 注错见红：改坏任意一处（比如把 ext6 换成 use6），必须有判据变红。

cd "$(dirname "$0")" || exit 1

CC=arm-linux-gnueabihf-gcc
OD=arm-linux-gnueabihf-objdump
RE=arm-linux-gnueabihf-readelf

PASS=0; FAIL=0; SKIP=0
ok()   { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
no()   { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -n "$2" ] && printf '        %s\n' "$2"; }
skip() { SKIP=$((SKIP+1)); printf '  SKIP  %s\n' "$1"; }
eq()   { if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "期望 $3，实得 $2"; fi; }
has()  { if echo "$2" | grep -qE "$3"; then ok "$1"; else no "$1" "输出里找不到 $3"; fi; }
hasnt(){ if echo "$2" | grep -qE "$3"; then no "$1" "不该出现 $3"; else ok "$1"; fi; }

die() {
	FAIL=$((FAIL+1))
	printf '  FAIL  构建：%s\n\n  %d PASS / %d FAIL / %d SKIP（构建没过）\n' "$1" "$PASS" "$FAIL" "$SKIP"
	exit 1
}

echo "=== 构建 ==="
$CC -O1 -c args.c -o args.o || die "args.c 编译不过"
echo "  完成"
echo

fn() { $OD -d args.o | sed -n "/<$1>:/,/^\$/p"; }

echo "=== 02 篇 2.7  参数放在哪 ==="
U4=$(fn use4)
has   "use4 用 r0/r1/r2/r3 做加法" "$U4" 'add[[:space:]]+r0, r1'
hasnt "use4 里没有任何内存访问（没有 ldr/str）" "$U4" 'ldr|str'
has   "use4 以 bx lr 返回" "$U4" 'bx[[:space:]]+lr'

U6=$(fn use6)
has "use6 的第 5 个参数从 [sp, #0] 读" "$U6" 'ldr[[:space:]]+r[0-9]+, \[sp, #0\]'
has "use6 的第 6 个参数从 [sp, #4] 读" "$U6" 'ldr[[:space:]]+r[0-9]+, \[sp, #4\]'

CA=$(fn caller)
has "caller 把 5 写进 [sp, #0]" "$CA" 'movs[[:space:]]+r3, #5'
has "caller 把 6 写进 [sp, #4]" "$CA" 'movs[[:space:]]+r3, #6'
has "caller 用 movs 把 1 放进 r0" "$CA" 'movs[[:space:]]+r0, #1'
has "caller 里有 bl（真的发生了调用，没被优化掉）" "$CA" 'bl'

R64=$(fn ret64)
has "ret64 用 ldrd 一次取两个寄存器" "$R64" 'ldrd[[:space:]]+r0, r1'
has "64 位返回值的低半段 0x55667788 排在前面（对应 r0）" "$R64" '55667788'
echo

echo "=== 02 篇 3.5  谁负责保存寄存器 ==="
MANY=$(fn many)
has "many 进门就 stmdb 保存一批寄存器" "$MANY" 'stmdb[[:space:]]+sp!,'
has "many 出门 ldmia 恢复"             "$MANY" 'ldmia'
# 被保存的寄存器必须全在 r4-r11 之间（外加 lr/pc）
SAVED=$(echo "$MANY" | grep -oE 'stmdb[[:space:]]+sp!, \{[^}]*\}' | grep -oE 'r[0-9]+')
BAD=$(echo "$SAVED" | awk '{n=substr($0,2)+0; if (n<4 || n>11) print}')
if [ -z "$BAD" ]; then
	ok "被保存的寄存器全部落在 r4-r11（$(echo $SAVED | tr '\n' ' '))"
else
	no "被保存的寄存器越界了" "$(echo $BAD | tr '\n' ' ')"
fi
hasnt "use4 里没有 stmdb（它不调别人，不需要保住任何东西）" "$U4" 'stmdb'
echo

echo "=== 02 篇 5.5  三种浮点 ABI ==="
for abi in hard softfp soft; do
	eval "ASM_$abi=\$($CC -O1 -S -mfloat-abi=$abi -o - fadd.c 2>/dev/null | sed -n '/^fadd2:/,/\.size/p')"
done
has   "hard 版直接用 s0/s1 算"      "$ASM_hard"   'vadd\.f32[[:space:]]+s0, s0, s1'
has   "softfp 版要 vmov 搬运"       "$ASM_softfp" 'vmov'
has   "softfp 版参数在 r0/r1"       "$ASM_softfp" 'vmov[[:space:]]+s[0-9]+, r0'
has   "soft 版调库函数 __aeabi_fadd" "$ASM_soft"   '__aeabi_fadd'
hasnt "soft 版完全不碰 FPU"          "$ASM_soft"   'vadd'

DASM=$($CC -O1 -S -mfloat-abi=hard -o - fadd.c | sed -n '/^dadd2:/,/\.size/p')
has "double 版用 vadd.f64 和 d0/d1" "$DASM" 'vadd\.f64[[:space:]]+d0, d0, d1'

IASM=$($CC -O1 -S -mfloat-abi=soft -o - fadd.c | sed -n '/^iadd2:/,/\.size/p')
has "整数版不受浮点 ABI 影响，仍是 add r0, r0, r1" "$IASM" 'add[[:space:]]+r0, r0, r1'
echo

echo "=== 02 篇 6.5  ABI 不一致的下场 ==="
cat > .m.c <<'EOF'
#include <stdio.h>
float fadd2(float a, float b);
int main(void) { printf("%f\n", fadd2(1.5f, 2.5f)); return 0; }
EOF
$CC -c .m.c   -o .m_hard.o    -mfloat-abi=hard   2>/dev/null
$CC -c fadd.c -o .fadd_soft.o -mfloat-abi=soft   2>/dev/null
$CC -c fadd.c -o .fadd_sfp.o  -mfloat-abi=softfp 2>/dev/null
$CC -c fadd.c -o .fadd_hard.o -mfloat-abi=hard   2>/dev/null

ERR=$($CC .m_hard.o .fadd_soft.o -o .bad 2>&1); RC=$?
has "hard + soft 链接报 VFP register arguments" "$ERR" 'uses VFP register arguments'
eq  "而且退出码非 0" "$([ $RC -ne 0 ] && echo yes)" "yes"

ERR2=$($CC .m_hard.o .fadd_sfp.o -o .bad2 2>&1)
has "hard + softfp 同样链不上（决定性的是传参方式，不是用不用 FPU）" \
    "$ERR2" 'uses VFP register arguments'

$CC .m_hard.o .fadd_hard.o -o .good 2>/dev/null && ok "两个都用 hard 就链得上" || no "hard+hard 应能链接"

has   "hard 版 .o 带 Tag_FP_arch 标记" "$($RE -A .m_hard.o)"    'Tag_FP_arch'
hasnt "soft 版 .o 没有这个标记"        "$($RE -A .fadd_soft.o)" 'Tag_FP_arch'
has   "ABI 标记存在 .ARM.attributes 这个 section 里" \
      "$($RE -S args.o)" '\.ARM\.attributes'
echo

echo "=== 02 篇 7  Thumb-2 ==="
has "默认是 Thumb 模式" "$($CC -O1 -S -o - fadd.c)" '\.thumb'
echo

echo "=== 03 篇 2.5  类型大小两个平台不同 ==="
ask_arm() {   # 用编译期断言问 ARM 平台的常量
	printf '_Static_assert(%s, "no");\nint main(void){return 0;}\n' "$1" > .q.c
	$CC -c .q.c -o /dev/null 2>/dev/null
}
ask_arm 'sizeof(long)==4'  && ok "ARM: sizeof(long)==4 成立"  || no "ARM 上 long 应是 4 字节"
ask_arm 'sizeof(long)==8'  && no "ARM 上 long 不该是 8 字节"  || ok "ARM: sizeof(long)==8 不成立"
ask_arm 'sizeof(void*)==4' && ok "ARM: sizeof(void*)==4 成立" || no "ARM 上指针应是 4 字节"
ask_arm 'sizeof(struct{char a; int b;})==8' \
	&& ok "ARM: struct{char;int;} 是 8 字节（中间填了 3 字节）" \
	|| no "结构体对齐判据失败"

# 探针自检：同样的断言在本机 x86 上必须失败，否则说明探针根本没生效
printf '_Static_assert(sizeof(long)==4, "no");\nint main(void){return 0;}\n' > .q.c
if gcc -c .q.c -o /dev/null 2>/dev/null; then
	no "探针自检失败：本机 x86 上 sizeof(long)==4 竟然编过了" "前面的结论全部作废"
else
	ok "探针自检：同一断言在 x86 上编不过（long=8），说明断言真的在起作用"
fi
echo

echo "=== 03 篇 4.4  libc.so 其实是链接脚本 ==="
ARM_LIBC=$($CC -print-file-name=libc.so)
eq "libc.so 是文本不是 ELF" "$(file -Lb "$ARM_LIBC" | cut -d, -f1)" "ASCII text"
has "内容里有 OUTPUT_FORMAT(elf32-littlearm)" "$(cat "$ARM_LIBC")" 'OUTPUT_FORMAT\(elf32-littlearm\)'
has "内容里有 GROUP，指向真正的库"            "$(cat "$ARM_LIBC")" 'GROUP'
has "真正的 ELF 是 libc.so.6" \
    "$(file -Lb "$($CC -print-file-name=libc.so.6)")" 'ELF 32-bit.*ARM'
has "对照：x86 版也是链接脚本，只是 OUTPUT_FORMAT 不同" \
    "$(cat "$(gcc -print-file-name=libc.so)")" 'OUTPUT_FORMAT\(elf64-x86-64\)'
echo

echo "=== 03 篇 5.5  两个编译器的搜索路径 ==="
armpath() { echo 'int main(){}' | $CC  -E -v - 2>&1 | sed -n '/search starts/,/End of/p'; }
x86path() { echo 'int main(){}' | gcc  -E -v - 2>&1 | sed -n '/search starts/,/End of/p'; }
if diff <(armpath) <(x86path) >/dev/null; then
	no "两个编译器的搜索路径不该相同"
else
	ok "两个编译器的头文件搜索路径确实不同"
fi
has "ARM 那边有 arm-linux-gnueabihf" "$(armpath)" 'arm-linux-gnueabihf'
has "x86 那边有 x86_64-linux-gnu"    "$(x86path)" 'x86_64-linux-gnu'
if diff <(armpath) <(armpath) >/dev/null; then
	ok "对比方法自检：同一个编译器比自己，diff 为空"
else
	no "对比方法有问题：同一个编译器比自己竟然不同"
fi
echo

echo "=== 03 篇 6.5  故意用错头文件 ==="
cat > .t.c <<'EOF'
#include <stdio.h>
int main(void) { printf("x\n"); return 0; }
EOF
$CC -c .t.c -o /dev/null 2>/dev/null && ok "正常编译成功" || no "正常编译应当成功"
if $CC -I/usr/include/x86_64-linux-gnu -c .t.c -o /dev/null 2>/dev/null; then
	skip "塞入 x86 头文件后仍编过（这台机器没装 x86 的 32 位头，撞不出来）"
else
	ok "塞入 x86 头文件目录后编译失败"
fi
$CC -I/nonexistent -c .t.c -o /dev/null 2>/dev/null \
	&& ok "-I 指向不存在的目录时 gcc 一声不吭（所以编译成功不能证明 -I 写对了）" \
	|| no "不存在的 -I 不该导致失败"
echo

rm -f .m.c .q.c .t.c .m_hard.o .fadd_soft.o .fadd_sfp.o .fadd_hard.o .bad .bad2 .good
echo "======================================"
printf '  %d PASS / %d FAIL / %d SKIP\n' "$PASS" "$FAIL" "$SKIP"
echo "======================================"
[ "$FAIL" -eq 0 ]
