#!/bin/bash
# 00_基础 第 04 篇（静态库、动态库与符号）的判据自动核对
#
# 用法：bash check.sh
# 注错见红：改坏一处（比如把 -lmathx 挪到源文件前面），必须有判据变红。

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
rm -f *.o *.a *.so app_static app_dyn app_st2 h_arm
gcc -c mathx.c strx.c                      || die "库源码编译不过"
ar rcs libmathx.a mathx.o strx.o           || die "ar 打包失败"
gcc app.c -o app_static -L. -lmathx        || die "静态链接失败"
gcc -shared -fPIC -o libmathx.so mathx.c strx.c || die "共享库编译不过"
gcc app.c -o app_dyn -L. -lmathx -Wl,-rpath,'$ORIGIN' || die "动态链接失败"
$CC -O1 h.c mathx.c strx.c -o h_arm        || die "ARM 版编译不过"
echo "  完成"
echo

echo "=== 04 篇 2.6  符号类型 ==="
cat > .sym.c <<'EOF'
#include <stdio.h>
int         g_init = 1;
int         g_bss;
const int   g_ro = 42;
static int  s_local = 7;
int helper(int x) { return x + s_local; }
static int shelp(int x) { return x - 1; }
extern int nobody(void);
int main(void) { printf("%d\n", helper(g_init) + shelp(g_ro) + nobody()); return 0; }
EOF
gcc -c .sym.c -o .sym.o || die ".sym.c 编译不过"
S=$(nm .sym.o)
has "helper 是 T（全局函数）"          "$S" '^[0-9a-f]+ T helper$'
has "shelp 是 t（static 函数，小写）"  "$S" '^[0-9a-f]+ t shelp$'
has "g_init 是 D（有初值）"            "$S" '^[0-9a-f]+ D g_init$'
has "g_bss 是 B（无初值，进 .bss）"    "$S" '^[0-9a-f]+ B g_bss$'
has "g_ro 是 R（只读）"                "$S" '^[0-9a-f]+ R g_ro$'
has "s_local 是 d（static 变量，小写）" "$S" '^[0-9a-f]+ d s_local$'
has "nobody 是 U 且没有地址"           "$S" '^ +U nobody$'
has "printf 也是 U（编译期一视同仁）"   "$S" '^ +U printf$'
has "完整链接只报 nobody 未定义" "$(gcc .sym.c -o /dev/null 2>&1)" "undefined reference to .nobody."
echo

echo "=== 04 篇 3.5  静态库只抄用得到的 .o ==="
has "ar t 列出打包进去的两个 .o" "$(ar t libmathx.a)" 'mathx\.o'
eq "app_static 里有 mx_add"   "$(nm app_static | grep -c ' T mx_add')" "1"
eq "app_static 里没有 mx_len（没用到就不抄）" "$(nm app_static | grep -c ' T mx_len')" "0"
eq "静态版跑出 7" "$(./app_static)" "mx_add(3,4) = 7"
has "把 -l 放在源文件前面会 undefined reference" \
    "$(gcc -L. -lmathx app.c -o /dev/null 2>&1)" "undefined reference"
echo

echo "=== 04 篇 4.6  动态库链接完仍是 U ==="
has "nm app_dyn 里 mx_add 仍然是 U" "$(nm app_dyn)" '^ +U mx_add'
has "readelf -d 里有 NEEDED libmathx.so" "$(readelf -d app_dyn)" 'NEEDED.*libmathx\.so'
eq "动态版跑出 7" "$(./app_dyn)" "mx_add(3,4) = 7"
mv libmathx.so .libmathx.so.hidden
./app_dyn >/dev/null 2>&1; RC=$?
eq "库藏起来后运行失败（退出码 127）" "$RC" "127"
mv .libmathx.so.hidden libmathx.so
echo

echo "=== 04 篇 5.5  改库不重编程序 ==="
MD5D0=$(md5sum app_dyn | cut -d' ' -f1)
MD5S0=$(md5sum app_static | cut -d' ' -f1)
cp mathx.c .mathx.c.bak
sed -i 's|return a + b;|return a * b;|' mathx.c
gcc -shared -fPIC -o libmathx.so mathx.c strx.c
gcc -c mathx.c strx.c && ar rcs libmathx.a mathx.o strx.o
eq "app_dyn 的 md5 没变（一个字节都没重编）"    "$(md5sum app_dyn    | cut -d' ' -f1)" "$MD5D0"
eq "app_static 的 md5 没变"                     "$(md5sum app_static | cut -d' ' -f1)" "$MD5S0"
eq "动态版跟着库变了：3*4=12" "$(./app_dyn)"    "mx_add(3,4) = 12"
eq "静态版纹丝不动：还是 7"   "$(./app_static)" "mx_add(3,4) = 7"
mv .mathx.c.bak mathx.c
gcc -shared -fPIC -o libmathx.so mathx.c strx.c
gcc -c mathx.c strx.c && ar rcs libmathx.a mathx.o strx.o
eq "复原后动态版回到 7" "$(./app_dyn)" "mx_add(3,4) = 7"

gcc app.c -o .app_st2 -L. -lmathx -static 2>/dev/null
if [ -f .app_st2 ]; then
	SZ_D=$(stat -c %s app_dyn); SZ_S=$(stat -c %s .app_st2)
	if [ $((SZ_S / SZ_D)) -ge 10 ]; then
		ok "全静态版体积是动态版的 $((SZ_S / SZ_D)) 倍（$SZ_D -> $SZ_S）"
	else
		no "全静态版应该大一个数量级以上" "$SZ_D -> $SZ_S"
	fi
	rm -f .app_st2
else
	skip "全静态链接不可用（未装 glibc 静态库）"
fi
echo

echo "=== 04 篇 6.6  PLT 与 GOT ==="
MAIN=$($OD -d h_arm | sed -n '/<main>:/,/^$/p')
has "调自己的函数是 bl <mx_add>（直接跳）"     "$MAIN" 'bl[[:space:]]+[0-9a-f]+ <mx_add>'
has "调库函数是 blx <...@plt>（跳跳板）"       "$MAIN" 'blx[[:space:]]+[0-9a-f]+ <[a-z_]+@plt>'
has "PLT 跳板最后一条是 ldr pc, [...]"         "$($OD -d -j .plt h_arm)" 'ldr[[:space:]]+pc, \['
REL=$(readelf -r app_dyn)
has ".rela.plt 里有 mx_add 的 JUMP_SLOT"       "$REL" 'JUMP_SLO.*mx_add'
has "JUMP_SLOT 的 Sym. Value 是 0（还没填）"   "$REL" 'JUMP_SLO +0+ +mx_add'
BIND=$(LD_DEBUG=bindings ./app_dyn 2>&1)
has "LD_DEBUG 能看到 mx_add 在运行时被绑定"    "$BIND" "binding file .*app_dyn.* to .*libmathx\.so.*mx_add"

# 待办清单的长度 == 用了几个外部函数
cat > .only_printf.c <<'EOF'
#include <stdio.h>
int main(void) { printf("hi\n"); return 0; }
EOF
gcc .only_printf.c -o .only_printf
N2=$(readelf -r app_dyn      | grep -c JUMP_SLO)
N1=$(readelf -r .only_printf | grep -c JUMP_SLO)
if [ "$N2" -gt "$N1" ]; then
	ok "用两个外部函数的比只用一个的多一条待办（$N2 > $N1）"
else
	no "待办清单长度应随外部函数数量变化" "$N2 vs $N1"
fi
rm -f .only_printf.c .only_printf
echo

echo "=== 04 篇 7  动态符号表 ==="
has "nm -D 能看到 .so 导出的 mx_add" "$(nm -D libmathx.so)" ' T mx_add'
has "nm -D 能看到 .so 导出的 mx_len" "$(nm -D libmathx.so)" ' T mx_len'
cp libmathx.so .stripped.so && strip .stripped.so
has "strip 之后动态符号表还在（不然动态链接就废了）" \
    "$(nm -D .stripped.so)" ' T mx_add'
rm -f .stripped.so
echo

rm -f .sym.c .sym.o
echo "======================================"
printf '  %d PASS / %d FAIL / %d SKIP\n' "$PASS" "$FAIL" "$SKIP"
echo "======================================"
[ "$FAIL" -eq 0 ]
