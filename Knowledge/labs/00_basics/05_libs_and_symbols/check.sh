#!/bin/bash
# fundamentals 05(静态库、动态库与符号)的判据自动核对
#
# 用法: bash check.sh
# 注错见红: 改坏一处(比如把 syms.c 里的 static 去掉、把 -lmathx 挪到源文件前面),
#           对应判据必须变红。

cd "$(dirname "$0")" || exit 1

ARMCC=arm-linux-gnueabihf-gcc
ARMOD=arm-linux-gnueabihf-objdump
ARMNM=arm-linux-gnueabihf-nm
ARMRE=arm-linux-gnueabihf-readelf
ARMLIBC=/usr/arm-linux-gnueabihf/lib/libc.so.6

PASS=0; FAIL=0; SKIP=0
ok()   { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
no()   { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -n "$2" ] && printf '        %s\n' "$2"; }
skip() { SKIP=$((SKIP+1)); printf '  SKIP  %s\n' "$1"; }
eq()   { if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "期望 $3，实得 $2"; fi; }
has()  { if echo "$2" | grep -qE -- "$3"; then ok "$1"; else no "$1" "输出里找不到 $3"; fi; }

die() {
	FAIL=$((FAIL+1))
	printf '  FAIL  构建：%s\n\n  %d PASS / %d FAIL / %d SKIP（构建没过）\n' "$1" "$PASS" "$FAIL" "$SKIP"
	exit 1
}

echo "=== 构建 ==="
rm -rf .good .bad .soname .plain .onlyso .empty .pref
rm -f mathx.o strx.o syms.o syms_arm.o syms_more.o syms_more_c.o cnt_nop.o cnt_nop_arm.o \
      libcnt.so libcnt_arm.so app_static.map app_force_a .um .um2 .um.c .strong.c .gdb_lazy \
      libmathx.a libmathx.so libplain.so libnoidx.a libboth.a libbothfs.a both.o both_fs.o \
      app_static app_dyn app_lazy app_pick app_pick_st app_soname app_plain app_nopath \
      app_origin app_runpath app_rpath app_both app_bothfs app_noidx \
      h_arm hi_arm sq_lm .app_full
gcc -c syms.c -o syms.o                          || die "syms.c 编译不过"
gcc -c mathx.c strx.c                            || die "库源码编译不过"
ar rcs libmathx.a mathx.o strx.o                 || die "ar 打包失败"
gcc app.c -o app_static libmathx.a               || die "静态链接失败"
gcc -shared -fPIC -o libmathx.so mathx.c strx.c  || die "共享库编译不过"
gcc app.c -o app_dyn -L. -lmathx -Wl,-rpath,'$ORIGIN'        || die "动态链接失败"
gcc app.c -o app_lazy -L. -lmathx -Wl,-rpath,'$ORIGIN' -Wl,-z,lazy || die "lazy 版链接失败"
$ARMCC -O1 h.c mathx.c strx.c -o h_arm           || die "ARM 版编译不过"
$ARMCC -c syms.c -o syms_arm.o                   || die "ARM 版 syms.o 编译不过"
gcc -c syms_more.c -o syms_more.o                || die "syms_more.c 编译不过"
gcc -fcommon -c syms_more.c -o syms_more_c.o     || die "syms_more.c（-fcommon）编译不过"
cat > .hi.c <<'X'
#include <stdio.h>
int main(int argc, char **argv)
{
	if (argc > 1)
		printf("hi %s\n", argv[1]);
	else
		printf("hi\n");
	return 0;
}
X
$ARMCC -O2 .hi.c -o hi_arm                       || die "ARM 版 hi 编译不过"
echo "  完成"
echo

echo "=== 05 篇 1 节  符号类型 ==="
S=$(nm syms.o)
has "helper 是 T（全局函数）"           "$S" '^[0-9a-f]+ T helper$'
has "shelp 是 t（static 函数，小写）"   "$S" '^[0-9a-f]+ t shelp$'
has "g_init 是 D（有初值）"             "$S" '^[0-9a-f]+ D g_init$'
has "g_bss 是 B（无初值，进 .bss）"     "$S" '^[0-9a-f]+ B g_bss$'
has "g_ro 是 R（只读）"                 "$S" '^[0-9a-f]+ R g_ro$'
has "g_str 是 D（指针变量本身可写）"    "$S" '^[0-9a-f]+ D g_str$'
has "s_local 是 d（static 变量，小写）" "$S" '^[0-9a-f]+ d s_local$'
has "nobody 是 U 且没有地址"            "$S" '^ +U nobody$'
has "printf 也是 U（编译期一视同仁）"   "$S" '^ +U printf$'
RS=$(readelf -s syms.o)
has "readelf -s：helper 是 GLOBAL"  "$(echo "$RS" | grep -w helper)" 'GLOBAL'
has "readelf -s：shelp 是 LOCAL"    "$(echo "$RS" | grep -w shelp)"  'LOCAL'
has ".bss 是 NOBITS（不占文件空间）" "$(readelf -S syms.o)" '\.bss +NOBITS'
has "完整链接只报 nobody 未定义" "$(gcc syms.c -o /dev/null 2>&1)" "undefined reference to .nobody."
has "arm-nm 看 ARM .o：helper 是 T" "$($ARMNM syms_arm.o)" '^[0-9a-f]+ T helper$'
has "x86 objdump 拒绝反汇编 ARM .o" "$(objdump -d syms_arm.o 2>&1)" "can't disassemble"
M=$(nm syms_more.o)
has "弱定义 weak_def 是 W"              "$M" '^[0-9a-f]+ W weak_def$'
has "弱引用 weak_ref 是 w 且没有地址"   "$M" '^ +w weak_ref$'
has "static const s_ro 是 r（小写）"    "$M" '^[0-9a-f]+ r s_ro$'
has "static 无初值 s_zero 是 b（小写）" "$M" '^[0-9a-f]+ b s_zero$'
has "无初值全局 g_tent 默认是 B"        "$M" '^[0-9a-f]+ B g_tent$'
has "-fcommon 时 g_tent 变成 C"         "$(nm syms_more_c.o)" '^[0-9a-f]+ C g_tent$'
printf 'int use(void);\nint main(void) { return use(); }\n' > .um.c
printf 'int weak_def(void) { return 40; }\n' > .strong.c
gcc .um.c syms_more.c -o .um && gcc .um.c syms_more.c .strong.c -o .um2 || die "弱符号实验链接失败"
./.um;  R1=$?
./.um2; R2=$?
eq  "弱引用没人定义也能链接，弱定义生效：退出码 6" "$R1" "6"
eq  "别处有强定义时弱定义让位：退出码 45"         "$R2" "45"
echo

echo "=== 05 篇 2 节  静态库 ==="
has ".a 的前 8 个字节是 !<arch>" "$(xxd -l 8 libmathx.a)" '!<arch>'
has "ar t 列出打包进去的两个 .o" "$(ar t libmathx.a)" 'mathx\.o'
has "ar t 里有 strx.o"           "$(ar t libmathx.a)" 'strx\.o'
has "符号索引：mx_add in mathx.o" "$(nm --print-armap libmathx.a)" 'mx_add in mathx\.o'
has "app_static 里有 T mx_add"     "$(nm app_static)" ' T mx_add$'
eq  "app_static 里没有 mx_len（没用到就不抄）" "$(nm app_static | grep -c 'mx_len')" "0"
eq  "静态版跑出 7" "$(./app_static)" "mx_add(3,4) = 7"
gcc app.c -o /dev/null libmathx.a -Wl,-Map,app_static.map || die "生成 map 文件失败"
has "map 文件记着 mathx.o 是为 mx_add 拉进来的" \
    "$(sed -n '1,6p' app_static.map)" 'libmathx\.a\(mathx\.o\)'
eq  "map 文件里 strx.o 没有被拉进来" "$(sed -n '1,6p' app_static.map | grep -c 'strx\.o')" "0"
has "把 -l 放在源文件前面会 undefined reference" \
    "$(gcc -L. -lmathx app.c -o /dev/null 2>&1)" "undefined reference"
ar rcS libnoidx.a mathx.o strx.o
has "没有索引的 .a 链接器拒收" \
    "$(gcc app.c -L. -lnoidx -o /dev/null 2>&1)" "archive has no index"
{ echo '#include "mathx.h"'; grep -h -v '#include' mathx.c strx.c; } > .both.c
gcc -c .both.c -o both.o && ar rcs libboth.a both.o || die "libboth.a 构建失败"
gcc app.c -o app_both libboth.a                      || die "app_both 链接失败"
has "两个函数挤进同一个 .o：mx_add 进来了" "$(nm app_both)" ' T mx_add$'
has "同一个 .o 里的 mx_len 被一起抄进来"   "$(nm app_both)" ' T mx_len$'
gcc -c -ffunction-sections .both.c -o both_fs.o && ar rcs libbothfs.a both_fs.o || die "libbothfs.a 构建失败"
gcc app.c -o app_bothfs libbothfs.a -Wl,--gc-sections || die "app_bothfs 链接失败"
eq "开 gc-sections 后 mx_len 不进程序" "$(nm app_bothfs | grep -c mx_len)" "0"
has "sqrt 不带 -lm 报 undefined reference" \
    "$(gcc -O0 sq.c -o /dev/null 2>&1)" "undefined reference to .sqrt."
gcc -O0 sq.c -o sq_lm -lm || die "sq.c 带 -lm 链接失败"
has "带 -lm 后 NEEDED 里有 libm.so.6" "$(readelf -d sq_lm)" 'NEEDED.*libm\.so\.6'
eq  "带 -lm 后能跑出结果" "$(./sq_lm)" "1.414214"
has "sqrt 在 libm.so.6 里" \
    "$(nm -D /usr/lib/x86_64-linux-gnu/libm.so.6)" 'W sqrt@@GLIBC_2\.2\.5'
eq  "sqrt 不在 libc.so.6 里" \
    "$(nm -D /usr/lib/x86_64-linux-gnu/libc.so.6 | grep -cw sqrt)" "0"
has "默认链接名单里有 -lc" "$(gcc -### app.c libmathx.a -o /dev/null 2>&1)" ' -lc '
echo

echo "=== 05 篇 3 节  动态库 ==="
has "nm app_dyn 里 mx_add 仍然是 U"      "$(nm app_dyn)" '^ +U mx_add'
has "readelf -d 里有 NEEDED libmathx.so" "$(readelf -d app_dyn)" 'NEEDED.*libmathx\.so'
has "NEEDED 里同时有 libc.so.6"          "$(readelf -d app_dyn)" 'NEEDED.*libc\.so\.6'
has "本机默认开启 BIND_NOW"              "$(readelf -d app_dyn)" 'FLAGS\).*BIND_NOW'
eq  "动态版跑出 7" "$(./app_dyn)" "mx_add(3,4) = 7"
mv libmathx.so .libmathx.so.hidden
ERR=$(./app_dyn 2>&1); RC=$?
mv .libmathx.so.hidden libmathx.so
eq  "库藏起来后运行失败（退出码 127）" "$RC" "127"
has "报错是 cannot open shared object file" "$ERR" 'cannot open shared object file'
mkdir .pref && cp libmathx.a libmathx.so .pref/
gcc app.c -o app_pick -L.pref -lmathx -Wl,-rpath,'$ORIGIN/.pref'
has ".a 和 .so 同时在场时 -l 选 .so" "$(readelf -d app_pick)" 'NEEDED.*libmathx\.so'
gcc -static app.c -o app_pick_st -L.pref -lmathx
has "加上 -static 后选 .a" "$(nm app_pick_st)" ' T mx_add$'
gcc app.c -o app_force_a -L.pref -l:libmathx.a
has "-l:libmathx.a 点名要 .a，mx_add 被抄进来" "$(nm app_force_a)" ' T mx_add$'
eq  "-l:libmathx.a 的产物不再 NEEDED libmathx.so" "$(readelf -d app_force_a | grep -c 'libmathx')" "0"
mkdir .onlyso && cp libmathx.so .onlyso/
has "-static 却只有 .so 时的报错" \
    "$(gcc -static app.c -o /dev/null -L.onlyso -lmathx 2>&1)" 'have you installed the static version'
$ARMCC -O2 -fno-pic -c cnt.c -o cnt_nop_arm.o
has "ARM 上关掉 PIC 编 .so 被拒（recompile with -fPIC）" \
    "$($ARMCC -shared cnt_nop_arm.o -o libcnt_arm.so 2>&1)" 'recompile with -fPIC'
gcc -O2 -fno-pic -c cnt.c -o cnt_nop.o
if gcc -shared cnt_nop.o -o libcnt.so 2>/dev/null; then
	ok "x86 上同一个 cnt.c 关掉 PIC 也能编成 .so（static 变量走 PC 相对寻址）"
else
	no "x86 上 cnt.c 关掉 PIC 应该仍能编成 .so"
fi
mkdir .soname
gcc -shared -fPIC -o .soname/libmathx.so.1.2 mathx.c strx.c -Wl,-soname,libmathx.so.1
ln -sf libmathx.so.1.2 .soname/libmathx.so.1
ln -sf libmathx.so.1   .soname/libmathx.so
has "库的 SONAME 是 libmathx.so.1" "$(readelf -d .soname/libmathx.so.1.2)" 'SONAME.*libmathx\.so\.1'
gcc app.c -o app_soname -L.soname -lmathx
has "程序 NEEDED 记的是 soname 而不是文件名" \
    "$(readelf -d app_soname)" 'NEEDED.*libmathx\.so\.1'
mv .soname/libmathx.so.1.2 .soname/libmathx.so.1.2.bak
ERR=$(LD_LIBRARY_PATH=.soname ./app_soname 2>&1); RC=$?
mv .soname/libmathx.so.1.2.bak .soname/libmathx.so.1.2
eq  "真身缺失时退出码 127" "$RC" "127"
has "报错里写的是 soname libmathx.so.1" "$ERR" 'libmathx\.so\.1: cannot open'
mkdir .plain
gcc -shared -fPIC -o .plain/libplain.so mathx.c strx.c
gcc app.c -o app_plain .plain/libplain.so
has "没有 soname 时 NEEDED 记下链接时给的路径" \
    "$(readelf -d app_plain)" 'NEEDED.*\.plain/libplain\.so'
echo

echo "=== 05 篇 3.6 节  改库不重编程序 ==="
MD5D0=$(md5sum app_dyn | cut -d' ' -f1)
MD5S0=$(md5sum app_static | cut -d' ' -f1)
cp mathx.c .mathx.c.bak
sed -i 's|return a + b;|return a * b;|' mathx.c
gcc -shared -fPIC -o libmathx.so mathx.c strx.c
gcc -c mathx.c strx.c && ar rcs libmathx.a mathx.o strx.o
eq "app_dyn 的 md5 没变（一个字节都没重编）" "$(md5sum app_dyn    | cut -d' ' -f1)" "$MD5D0"
eq "app_static 的 md5 没变"                  "$(md5sum app_static | cut -d' ' -f1)" "$MD5S0"
eq "动态版跟着库变了：3*4=12" "$(./app_dyn)"    "mx_add(3,4) = 12"
eq "静态版纹丝不动：还是 7"   "$(./app_static)" "mx_add(3,4) = 7"
mv .mathx.c.bak mathx.c
gcc -shared -fPIC -o libmathx.so mathx.c strx.c
gcc -c mathx.c strx.c && ar rcs libmathx.a mathx.o strx.o
eq "复原后动态版回到 7" "$(./app_dyn)" "mx_add(3,4) = 7"
gcc -static app.c libmathx.a -o .app_full 2>/dev/null
if [ -f .app_full ]; then
	SZ_D=$(stat -c %s app_dyn); SZ_S=$(stat -c %s .app_full)
	if [ $((SZ_S / SZ_D)) -ge 10 ]; then
		ok "全静态版体积是动态版的 $((SZ_S / SZ_D)) 倍（$SZ_D -> $SZ_S）"
	else
		no "全静态版应该大一个数量级以上" "$SZ_D -> $SZ_S"
	fi
	rm -f .app_full
else
	skip "全静态链接不可用（未装 glibc 静态库）"
fi
echo

echo "=== 05 篇 4 节  动态链接器的搜索顺序 ==="
mkdir .good .bad .empty
gcc -shared -fPIC -o .good/libmathx.so mathx.c strx.c
sed 's|return a + b;|return a * b;|' mathx.c > .mul.c
gcc -shared -fPIC -o .bad/libmathx.so .mul.c strx.c
gcc app.c -o app_runpath -L.good -lmathx -Wl,-rpath,"$PWD/.good"
gcc app.c -o app_rpath   -L.good -lmathx -Wl,--disable-new-dtags,-rpath,"$PWD/.good"
has "默认 -rpath 生成的是 RUNPATH"        "$(readelf -d app_runpath)" 'RUNPATH'
has "--disable-new-dtags 生成的是 RPATH"  "$(readelf -d app_rpath)"   'RPATH'
eq  "RUNPATH 版：不带环境变量跑的是好库（7）" "$(./app_runpath)" "mx_add(3,4) = 7"
eq  "RUNPATH 排在 LD_LIBRARY_PATH 后面（坏库生效，12）" \
    "$(LD_LIBRARY_PATH=$PWD/.bad ./app_runpath)" "mx_add(3,4) = 12"
eq  "RPATH 排在 LD_LIBRARY_PATH 前面（坏库被压住，7）" \
    "$(LD_LIBRARY_PATH=$PWD/.bad ./app_rpath)" "mx_add(3,4) = 7"
gcc app.c -o app_origin -L.good -lmathx -Wl,-rpath,'$ORIGIN/.good'
has "\$ORIGIN 原样记进 RUNPATH" "$(readelf -d app_origin)" 'RUNPATH.*\$ORIGIN/\.good'
eq  "\$ORIGIN 版能跑出 7" "$(./app_origin)" "mx_add(3,4) = 7"
gcc app.c -o app_nopath -L. -lmathx
ERR=$(cd .empty && LD_LIBRARY_PATH= ../app_nopath 2>&1); RC=$?
eq  "没有任何指路信息时退出码 127" "$RC" "127"
has "报错 cannot open shared object file" "$ERR" 'cannot open shared object file'
has "LD_DEBUG=libs 能看到 (LD_LIBRARY_PATH) 这一段搜索" \
    "$(LD_DEBUG=libs LD_LIBRARY_PATH=.onlyso ./app_dyn 2>&1)" 'search path=.*\(LD_LIBRARY_PATH\)'
has "找不到时能看到 system search path 逐目录尝试" \
    "$(cd .empty && LD_DEBUG=libs LD_LIBRARY_PATH= ../app_nopath 2>&1)" 'system search path'
has "ldd 能列出 libmathx.so 的实际路径" "$(ldd ./app_dyn)" 'libmathx\.so => '
has "ldd 看不了 ARM 程序" "$(ldd ./hi_arm 2>&1)" 'not a dynamic executable'
echo

echo "=== 05 篇 5 节  符号版本 ==="
has "hi_arm 要求 GLIBC_2.34 版的 __libc_start_main" \
    "$($ARMOD -T hi_arm)" '\(GLIBC_2\.34\) __libc_start_main'
has ".gnu.version_r 里记着 File: libc.so.6 需要 GLIBC_2.34" \
    "$($ARMRE -V hi_arm)" 'File: libc\.so\.6'
has ".gnu.version_r 里有 GLIBC_2.34 这一项" \
    "$($ARMRE -V hi_arm)" 'Name: GLIBC_2\.34'
has "交叉 libc 里 __libc_start_main 有 GLIBC_2.34 默认版本" \
    "$($ARMOD -T $ARMLIBC | grep -w __libc_start_main)" ' GLIBC_2\.34 +__libc_start_main'
has "同一个名字还留着 (GLIBC_2.4) 兼容版本" \
    "$($ARMOD -T $ARMLIBC | grep -w __libc_start_main)" '\(GLIBC_2\.4\) +__libc_start_main'
has ".rel.plt 里函数名带着版本 @GLIBC_2.34" \
    "$($ARMRE -r h_arm)" 'JUMP_SLOT +0+ +__libc_start_main@GLIBC_2\.34'
echo

echo "=== 05 篇 6 节  PLT 与 GOT ==="
MAIN=$($ARMOD -d h_arm | sed -n '/<main>:/,/^$/p')
has "调同文件的函数是 bl <mx_add>（直接跳）"   "$MAIN" 'bl[[:space:]]+[0-9a-f]+ <mx_add>'
has "调库函数是 blx <...@plt>（跳跳板）"        "$MAIN" 'blx[[:space:]]+[0-9a-f]+ <[a-z_]+@plt>'
has "ARM 的 PLT 跳板最后一条是 ldr pc, [...]"  "$($ARMOD -d -j .plt h_arm)" 'ldr[[:space:]]+pc, \['
# ARM 状态下读 pc 得到"本条地址 + 8"，跳板三条指令算出的地址必须正好是 .rel.plt 里那一格
PLT=$($ARMOD -d -j .plt h_arm | sed -n '/<__printf_chk@plt>:/,/^$/p')
PA=$(echo "$PLT" | awk 'NR==2{sub(":","",$1); print $1}')
PI=$(echo "$PLT" | grep -oE 'add[[:space:]]+ip, ip, #[0-9]+' | grep -oE '[0-9]+$')
PL=$(echo "$PLT" | grep -oE 'ldr[[:space:]]+pc, \[ip, #[0-9]+' | grep -oE '[0-9]+$')
SLOTA=$(printf '%08x' $(( 0x$PA + 8 + PI + PL )))
eq  "__printf_chk@plt 算出的 GOT 地址就是 .rel.plt 里它那一格" \
    "$($ARMRE -r h_arm | awk '/__printf_chk/{print $1}')" "$SLOTA"
PLT0=$($ARMRE -SW h_arm | awk '$2==".plt"{print $4}' | sed 's/^0*//')
GOTW=$($ARMOD -s -j .got h_arm | awk 'NR>4{for(i=2;i<=5;i++) print $i}' | grep -c "^$(printf '%08x' $((0x$PLT0)) | sed 's/\(..\)\(..\)\(..\)\(..\)/\4\3\2\1/')$")
eq  "文件里 5 个 JUMP_SLOT 格子的初值都指向 .plt 开头（0x$PLT0）" "$GOTW" "5"
has ".plt 在只读可执行的 AX 段，.got 在可写的 WA 段" \
    "$($ARMRE -SW h_arm | grep -E ' \.plt |\.got ' | awk '{print $2, $8}' | tr '\n' ' ')" '^\.plt AX \.got WA $'
has "x86 的 .plt.sec 跳板是 jmp *GOT(rip)" \
    "$(objdump -d -j .plt.sec app_lazy)" 'jmp +\*0x[0-9a-f]+\(%rip\)'
REL=$(readelf -r app_dyn)
has ".rela.plt 里有 mx_add 的 JUMP_SLOT"     "$REL" 'JUMP_SLO.*mx_add'
has "JUMP_SLOT 的 Sym. Value 是 0（还没填）" "$REL" 'JUMP_SLO +0+ +mx_add'
AREL=$($ARMRE -r h_arm)
NJS=$(echo "$AREL" | grep -c 'R_ARM_JUMP_SLOT')
NZJ=$(echo "$AREL" | grep 'R_ARM_JUMP_SLOT' | grep -c ' 00000000 ')
eq "ARM 的 .rel.plt 每条 Sym.Value 都是 0" "$NJS-$NZJ" "$NJS-$NJS"
BIND=$(LD_DEBUG=bindings ./app_lazy 2>&1)
has "LD_DEBUG 能看到 mx_add 在运行时被绑定" "$BIND" 'binding file .*app_lazy.* to .*libmathx\.so.*mx_add'
LI=$(echo "$BIND" | grep -n 'calling init: .*libmathx\.so' | head -1 | cut -d: -f1)
LB=$(echo "$BIND" | grep -n 'normal symbol `mx_add' | head -1 | cut -d: -f1)
if [ -n "$LI" ] && [ -n "$LB" ] && [ "$LB" -gt "$LI" ]; then
	ok "lazy 版：mx_add 的绑定（第 $LB 行）发生在库初始化（第 $LI 行）之后"
else
	no "lazy 版：绑定应该推迟到初始化之后" "LI=$LI LB=$LB"
fi
if command -v gdb >/dev/null 2>&1; then
	SL=$(readelf -r app_lazy | awk '/JUMP_SLO.*mx_add/{print $1}')
	cat > .gdb_lazy <<X
set pagination off
break main
run
info symbol *(long*)(0x555555554000 + 0x$SL)
next
info symbol *(long*)(0x555555554000 + 0x$SL)
kill
X
	G=$(gdb -q -batch -x .gdb_lazy ./app_lazy 2>&1)
	has "lazy 版：进 main 时 mx_add 的 GOT 格子还没指向库" "$G" 'No symbol matches'
	has "lazy 版：调用一次之后格子指向 libmathx.so 的 mx_add" "$G" 'mx_add in section \.text of .*libmathx\.so'
else
	skip "gdb 不在：看不了 GOT 格子前后的值"
	skip "gdb 不在：看不了 GOT 格子前后的值"
fi
has "app_dyn 有 GNU_RELRO 段（填完后整段改只读）" "$(readelf -lW app_dyn)" 'GNU_RELRO'
BIND2=$(LD_DEBUG=bindings ./app_dyn 2>&1)
LI2=$(echo "$BIND2" | grep -n 'calling init: .*libmathx\.so' | head -1 | cut -d: -f1)
LB2=$(echo "$BIND2" | grep -n 'normal symbol `mx_add' | head -1 | cut -d: -f1)
if [ -n "$LI2" ] && [ -n "$LB2" ] && [ "$LB2" -lt "$LI2" ]; then
	ok "BIND_NOW 版：mx_add 的绑定（第 $LB2 行）抢在库初始化（第 $LI2 行）之前"
else
	no "BIND_NOW 版：绑定应该在初始化之前完成" "LI2=$LI2 LB2=$LB2"
fi
cat > .only_printf.c <<'X'
#include <stdio.h>
int main(void) { printf("hi\n"); return 0; }
X
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

echo "=== 05 篇速查清单  动态符号表 ==="
has "nm -D 能看到 .so 导出的 mx_add" "$(nm -D libmathx.so)" ' T mx_add'
has "nm -D 能看到 .so 导出的 mx_len" "$(nm -D libmathx.so)" ' T mx_len'
cp libmathx.so .stripped.so && strip .stripped.so
has "strip 之后 nm 报 no symbols（.symtab 没了）" "$(nm .stripped.so 2>&1)" 'no symbols'
has "strip 之后 nm -D 还在（.dynsym 不能删）"    "$(nm -D .stripped.so)" ' T mx_add'
eq  "nm -u 只列出 U 的两行" "$(nm -u syms.o | wc -l)" "2"
has "nm -A 每行带上 库:成员 前缀" "$(nm -A libmathx.a)" '^libmathx\.a:strx\.o:[0-9a-f]+ T mx_len$'
rm -f .stripped.so
echo

rm -rf .good .bad .soname .plain .onlyso .empty .pref
rm -f .hi.c .both.c .mul.c .mathx.c.bak .um .um2 .um.c .strong.c .gdb_lazy
echo "======================================"
printf '  %d PASS / %d FAIL / %d SKIP\n' "$PASS" "$FAIL" "$SKIP"
echo "======================================"
[ "$FAIL" -eq 0 ]
