#!/bin/bash
# 00_basics/04_abi_and_regs：fundamentals 02 篇（ARM 寄存器与调用约定）、
# 03 篇（ABI 与 sysroot）的判据核对。
#
# 用法：bash check.sh
# 注错见红：改坏任意一处（比如 caller 里把 ext6 换成 use6，或者把某条
# 期望值改掉），对应判据必须变红。

cd "$(dirname "$0")" || exit 1

CC=arm-linux-gnueabihf-gcc
OD=arm-linux-gnueabihf-objdump
RE=arm-linux-gnueabihf-readelf
LD=arm-linux-gnueabihf-ld

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
$CC -O1 -c args.c  -o args.o      || die "args.c 编译不过"
$CC -O1 -c wrap1.c -o wrap1.o     || die "wrap1.c 编译不过"
$CC -O1 -marm -c args.c -o args_arm.o || die "args.c 的 -marm 版编译不过"
echo "  完成"
echo

fn() { $OD -d "$2" | sed -n "/<$1>:/,/^\$/p"; }

echo "=== 02 篇 2.7  参数放在哪 ==="
U4=$(fn use4 args.o)
has   "use4 用 r0/r1/r2/r3 做加法" "$U4" 'add[[:space:]]+r0, r1'
hasnt "use4 里没有任何内存访问（没有 ldr/str）" "$U4" 'ldr|str'
has   "use4 以 bx lr 返回" "$U4" 'bx[[:space:]]+lr'

U6=$(fn use6 args.o)
has "use6 的第 5 个参数从 [sp, #0] 读" "$U6" 'ldr[[:space:]]+r[0-9]+, \[sp, #0\]'
has "use6 的第 6 个参数从 [sp, #4] 读" "$U6" 'ldr[[:space:]]+r[0-9]+, \[sp, #4\]'

CA=$(fn caller args.o)
has "caller 把 5 写进 [sp, #0]" "$CA" 'movs[[:space:]]+r3, #5'
has "caller 把 6 写进 [sp, #4]" "$CA" 'movs[[:space:]]+r3, #6'
has "caller 用 movs 把 1 放进 r0" "$CA" 'movs[[:space:]]+r0, #1'
has "caller 里有 bl（真的发生了调用，没被优化掉）" "$CA" 'bl'

R64=$(fn ret64 args.o)
has "ret64 用 ldrd 一次取两个寄存器" "$R64" 'ldrd[[:space:]]+r0, r1'
has "64 位返回值的低半段 0x55667788 排在前面（对应 r0）" "$R64" '55667788'
echo

echo "=== 02 篇 3.5  谁负责保存寄存器 ==="
MANY=$(fn many args.o)
has "many 进门就 stmdb 保存一批寄存器" "$MANY" 'stmdb[[:space:]]+sp!,'
has "many 出门 ldmia 恢复"             "$MANY" 'ldmia'
SAVED=$(echo "$MANY" | grep -oE 'stmdb[[:space:]]+sp!, \{[^}]*\}' | grep -oE 'r[0-9]+')
BAD=$(echo "$SAVED" | awk '{n=substr($0,2)+0; if (n<4 || n>11) print}')
if [ -z "$BAD" ]; then
	ok "被保存的寄存器全部落在 r4-r11（$(echo $SAVED | tr '\n' ' ')）"
else
	no "被保存的寄存器越界了" "$(echo $BAD | tr '\n' ' ')"
fi
hasnt "use4 里没有 stmdb（它不调别人，不需要保住任何东西）" "$U4" 'stmdb'

W1=$(fn wrap1 wrap1.o)
has   "wrap1 进门 push {r3, lr}：它还要调 ext1，先把 lr 存起来" "$W1" 'push[[:space:]]+\{r3, lr\}'
has   "wrap1 出门 pop {r3, pc}：恢复与返回合成一条"             "$W1" 'pop[[:space:]]+\{r3, pc\}'
LEAF=$(fn leaf wrap1.o)
hasnt "leaf 没有任何压栈（它不调别人，lr 不会被改写）" "$LEAF" 'push|stmdb'
has   "leaf 直接 bx lr 返回"                           "$LEAF" 'bx[[:space:]]+lr'
echo

echo "=== 02 篇 4.4  三种浮点 ABI ==="
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

echo "=== 02 篇 5.4  ABI 不一致的下场 ==="
cat > .m.c <<'X'
#include <stdio.h>
float fadd2(float a, float b);
int main(void) { printf("%f\n", fadd2(1.5f, 2.5f)); return 0; }
X
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

has   "hard 版 .o 带 Tag_ABI_VFP_args: VFP registers（真正区分 hard 的标记）" \
      "$($RE -A .m_hard.o)"    'Tag_ABI_VFP_args: VFP registers'
hasnt "softfp 版没有 Tag_ABI_VFP_args" "$($RE -A .fadd_sfp.o)" 'Tag_ABI_VFP_args'
has   "softfp 版却带 Tag_FP_arch（它用 FPU 算，只是不走 VFP 传参）" \
      "$($RE -A .fadd_sfp.o)"  'Tag_FP_arch'
hasnt "soft 版连 Tag_FP_arch 也没有"   "$($RE -A .fadd_soft.o)" 'Tag_FP_arch'
has   "ABI 标记存在 .ARM.attributes 这个 section 里" \
      "$($RE -S args.o)" '\.ARM\.attributes'

cat > .a1.c <<'X'
float af1(float a, float b){ return a + b; }
X
cat > .a2.c <<'X'
float af2(float a, float b){ return a - b; }
X
$CC -c .a1.c -o .a1_soft.o -mfloat-abi=soft   2>/dev/null
$CC -c .a2.c -o .a2_sfp.o  -mfloat-abi=softfp 2>/dev/null
if $LD -r .a1_soft.o .a2_sfp.o -o .a12.o 2>/dev/null; then
	hasnt "soft 与 softfp 可以互链，合并产物仍无 VFP_args 标记" \
	      "$($RE -A .a12.o)" 'Tag_ABI_VFP_args'
else
	no "soft 与 softfp 传参方式相同，ld -r 应能合并"
fi
echo

echo "=== 02 篇 6.4  Thumb-2 与符号表 ==="
has "默认是 Thumb 模式" "$($CC -O1 -S -o - fadd.c)" '\.thumb'
eq "Thumb 版符号表里 use4 的 Value 末位是 1（Thumb 标记位）" \
   "$($RE -s args.o | awk '$NF=="use4"{print $2}')" "00000001"
eq "-marm 版同一个 use4 的 Value 末位是 0" \
   "$($RE -s args_arm.o | awk '$NF=="use4"{print $2}')" "00000000"
has "符号表里有 \$t/\$d 映射符号（给反汇编器和链接器留的路标）" \
    "$($RE -s args.o)" '\$t'
echo

echo "=== 03 篇 2.5  类型大小两个平台不同 ==="
ask_arm() {   # 用编译期断言问 ARM 平台的常量；$2 非空时先加一行 include
	{ [ -n "$2" ] && printf '#include <%s>\n' "$2";
	  printf '_Static_assert(%s, "no");\nint main(void){return 0;}\n' "$1"; } > .q.c
	$CC -c .q.c -o /dev/null 2>/dev/null
}
ask_arm 'sizeof(long)==4'  && ok "ARM: sizeof(long)==4 成立"  || no "ARM 上 long 应是 4 字节"
ask_arm 'sizeof(long)==8'  && no "ARM 上 long 不该是 8 字节"  || ok "ARM: sizeof(long)==8 不成立"
ask_arm 'sizeof(void*)==4' && ok "ARM: sizeof(void*)==4 成立" || no "ARM 上指针应是 4 字节"
ask_arm 'sizeof(struct{char a; int b;})==8' \
	&& ok "ARM: struct{char;int;} 是 8 字节（中间填了 3 字节）" \
	|| no "结构体对齐判据失败"
ask_arm 'sizeof(time_t)==8' time.h \
	&& ok "ARM: sizeof(time_t)==8 成立（本工具链默认 -D_TIME_BITS=64）" \
	|| no "本工具链 armhf 的 time_t 应是 8 字节"
ask_arm '(char)-1 > 0' \
	&& ok "ARM: char 是无符号的（(char)-1 > 0 成立）" \
	|| no "ARM 上 char 应是无符号"
ask_arm 'sizeof(struct{int id; long offset;})==8' \
	&& ok "ARM: struct{int;long;} 是 8 字节" \
	|| no "ARM 上 struct{int;long;} 应是 8 字节"

printf '_Static_assert(sizeof(long)==4, "no");\nint main(void){return 0;}\n' > .q.c
if gcc -c .q.c -o /dev/null 2>/dev/null; then
	no "探针自检失败：本机 x86 上 sizeof(long)==4 竟然编过了" "前面的结论全部作废"
else
	ok "探针自检：同一断言在 x86 上编不过（long=8），说明断言真的在起作用"
fi
printf '_Static_assert(sizeof(struct{int id; long offset;})==16, "no");\nint main(void){return 0;}\n' > .q.c
gcc -c .q.c -o /dev/null 2>/dev/null \
	&& ok "对照：x86 上 struct{int;long;} 是 16 字节" \
	|| no "x86 上 struct{int;long;} 应是 16 字节"
echo

echo "=== 03 篇 3.5  sysroot 与材料位置 ==="
eq "交叉编译器的 -print-sysroot 输出 /（multiarch 布局）" \
   "$($CC -print-sysroot)" "/"
eq "readlink 化简后 libc.so 在 /usr/arm-linux-gnueabihf/lib/" \
   "$(readlink -f "$($CC -print-file-name=libc.so)")" \
   "/usr/arm-linux-gnueabihf/lib/libc.so"
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

echo "=== 03 篇 5.4  两个编译器的搜索路径 ==="
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

echo "=== 03 篇 6.5  故意混用头文件 ==="
cat > .t.c <<'X'
#include <stdio.h>
int main(void) { printf("x\n"); return 0; }
X
$CC -c .t.c -o /dev/null 2>/dev/null && ok "正常编译成功" || no "正常编译应当成功"
if [ -f /usr/include/x86_64-linux-gnu/gnu/stubs-32.h ]; then
	$CC -I/usr/include/x86_64-linux-gnu -c .t.c -o /dev/null 2>/dev/null \
		&& ok "塞入 x86 头文件目录后静默编过（没有任何报错，这才是危险所在）" \
		|| no "本机装有 x86 32 位头，混入后应能编过（旧环境撞 stubs-32.h 是运气）"
	cat > .probe.c <<'X'
#include <setjmp.h>
int s_jmp = sizeof(jmp_buf);
X
	A=$($CC -S -o - .probe.c | grep -A1 '^s_jmp:' | grep -oE '[0-9]+')
	B=$($CC -I/usr/include/x86_64-linux-gnu -S -o - .probe.c | grep -A1 '^s_jmp:' | grep -oE '[0-9]+')
	if [ -n "$A" ] && [ -n "$B" ] && [ "$A" != "$B" ]; then
		ok "同一行 sizeof(jmp_buf)：正常 $A，混入 x86 头后 $B，静默出错坐实"
	else
		no "混用头文件后 sizeof(jmp_buf) 应当变化" "正常 $A，混入后 $B"
	fi
else
	skip "本机没装 x86 32 位头（无 gnu/stubs-32.h），混用会撞编译错误，跳过静默编过判据"
	skip "同上，跳过 sizeof(jmp_buf) 对比"
fi
$CC -I/nonexistent -c .t.c -o /dev/null 2>/dev/null \
	&& ok "-I 指向不存在的目录时 gcc 一声不吭（所以编译成功不能证明 -I 写对了）" \
	|| no "不存在的 -I 不该导致失败"
echo

rm -f .m.c .q.c .t.c .probe.c .a1.c .a2.c \
      .m_hard.o .fadd_soft.o .fadd_sfp.o .fadd_hard.o .a1_soft.o .a2_sfp.o .a12.o \
      .bad .bad2 .good
echo "======================================"
printf '  %d PASS / %d FAIL / %d SKIP\n' "$PASS" "$FAIL" "$SKIP"
echo "======================================"
[ "$FAIL" -eq 0 ]
