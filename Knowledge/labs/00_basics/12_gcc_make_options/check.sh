#!/bin/bash
# 00_basics 第 12 套：fundamentals 04 篇（GCC 选项）与 06 篇（make 语法与函数）的清单判据。
# 清单型篇目，判据核对的是两篇正文里"实测"条目的行为本身。
#
# 用法：bash check.sh
# 注错见红：把任意一条 eq/has 的期望值改错（例如把 subst 的期望结果改一个字母），
# 对应判据必须 FAIL；把 gcc 的 -Wall 从命令里去掉，"警告出现"类判据必须 FAIL。

cd "$(dirname "$0")" || exit 1
export LC_ALL=C
CROSS=arm-linux-gnueabihf-

PASS=0; FAIL=0; SKIP=0
ok()   { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
no()   { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -n "$2" ] && printf '        %s\n' "$2"; }
skip() { SKIP=$((SKIP+1)); printf '  SKIP  %s\n' "$1"; }
eq()   { if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "期望 [$3]，实得 [$2]"; fi; }
has()  { if echo "$2" | grep -qE "$3"; then ok "$1"; else no "$1" "输出里找不到 $3"; fi; }
notin(){ if echo "$2" | grep -qE "$3"; then no "$1" "输出里不该出现 $3"; else ok "$1"; fi; }

die() {
	FAIL=$((FAIL+1))
	printf '  FAIL  构建：%s\n\n  %d PASS / %d FAIL / %d SKIP（构建没过）\n' "$1" "$PASS" "$FAIL" "$SKIP"
	exit 1
}

echo "=== 清理并重建 ==="
rm -f *.o *.i *.s *.d *.dep a.out test testv t_* sz_*.o opt_*.o o_*.o pure_*.o ug.o \
      libsub.a libsub.so libextra.a extra.o extra.c main2.d m2.d m4.d custom.dep t.map t2.map \
      f_arm.o f_thumb.o f_caller_soft.o f_add_hard.o merged.o oob oob.c renamed.o renamed.d \
      mmp.o mmp.d m2.o m4.o m3.o .m3.o.d from_i.o from_s.o test_arm tiny tiny.c opt_st.* 2>/dev/null
rm -rf st mk/.work
make -C mk/pat clean >/dev/null 2>&1
rm -f mk/imp/hello mk/all mk/a.txt mk/b.txt mk/c.txt
echo "  完成"
echo

echo "=== 04 篇 1 节  停在哪一步 ==="
gcc -E -o main.i main.c                            || die "gcc -E 失败"
gcc -S -o main.s main.i                            || die "gcc -S 失败"
gcc -c -o main.o main.s                            || die "gcc -c 失败"
gcc -c -o sub.o sub.c                              || die "sub.c 编译失败"
gcc -o test main.o sub.o                           || die "链接失败"
has  "-E 展开头文件（main.i 里有 printf 的声明）" "$(grep -c 'extern int printf' main.i)" '^[0-9]*[1-9]'
has  "-S 产出汇编（有 main: 标号）"              "$(cat main.s)" '^main:'
has  "-c 产出可重定位目标文件"                    "$(file main.o)" 'relocatable'
eq   "四步手工链产物能跑且输出两行"              "$(./test)" "$(printf 'Main fun!\nSub fun!')"
V=$(gcc -o /dev/null main.c sub.c -v 2>&1)
has  "-v 里能看到 cc1"      "$V" 'cc1'
has  "-v 里能看到 as"       "$V" '[-/]as -v'
has  "-v 里能看到 collect2" "$V" 'collect2'
rm -f a.out; gcc main.c sub.c
[ -f a.out ] && ok "不给 -o 时默认可执行文件名是 a.out" || no "不给 -o 时默认可执行文件名是 a.out"
rm -f a.out
echo

echo "=== 04 篇 2 节  警告 ==="
eq   "不加警告选项编译 warn.c 静默通过"    "$(gcc -c warn.c -o /dev/null 2>&1)" ""
has  "-Wall 报 unused variable"            "$(gcc -Wall -c warn.c -o /dev/null 2>&1)" 'Wunused-variable'
W2=$(gcc -Wall -Wextra -c warn.c -o /dev/null 2>&1)
has  "-Wextra 多报 sign-compare"           "$W2" 'Wsign-compare'
gcc -Wall -Wextra -Werror -c warn.c -o /dev/null 2>/dev/null
eq   "-Werror 把警告升级为失败（退出码非 0）" "$?" "1"
has  "-Werror 输出 all warnings being treated as errors" \
     "$(gcc -Wall -Wextra -Werror -c warn.c -o /dev/null 2>&1)" 'all warnings being treated as errors'
echo

echo "=== 04 篇 3 节  优化与调试信息 ==="
gcc -O0 -c opt.c -o pure_O0.o; gcc -O2 -c opt.c -o pure_O2.o
gcc -O0 -O2 -c opt.c -o o_O2last.o; gcc -O2 -O0 -c opt.c -o o_O0last.o
cmp -s o_O2last.o pure_O2.o && ok "-O0 -O2 与 -O2 产物一致（最后一个生效）" || no "-O0 -O2 应等于 -O2"
cmp -s o_O0last.o pure_O0.o && ok "-O2 -O0 与 -O0 产物一致"                    || no "-O2 -O0 应等于 -O0"
gcc -O3 -c opt.c -o pure_O3.o; gcc -O9 -c opt.c -o o_O9.o
cmp -s o_O9.o pure_O3.o && ok "-O9 被静默按 -O3 处理" || no "-O9 应等于 -O3"
R0=$(objdump -r pure_O0.o | awk '{print $3}'); R2=$(objdump -r pure_O2.o | awk '{print $3}')
has  "-O0 下 square 是真调用"          "$R0" '^square'
notin "-O2 下 square 被内联（不再调用）" "$R2" '^square'
has  "-O0 下 printf(带参数) 保持 printf" "$R0" '^printf'
has  "-O2 下 printf(带参数) 变 __printf_chk" "$R2" '__printf_chk'
gcc -O0 -g -c opt.c -o opt_g.o; gcc -O0 -c opt.c -o opt_ng.o
if [ "$(readelf -S opt_g.o | grep -c debug)" -gt 0 ] && [ "$(readelf -S opt_ng.o | grep -c debug)" -eq 0 ]; then
	ok "-g 增加 .debug 段（有 9 类，无 -g 为 0）"
else
	no "-g 应产生 .debug 段"
fi
echo

echo "=== 04 篇 4 节  头文件与库的搜索 ==="
gcc -c use_greet.c -o /dev/null 2>/dev/null
eq   "尖括号找不到 greet.h（退出码 1）" "$?" "1"
gcc -Ihdr -c use_greet.c -o ug.o && gcc -Ihdr use_greet.c -o t_greet \
	&& eq "-Ihdr 之后编译运行通过" "$(./t_greet)" "hi from header" \
	|| no "-Ihdr 应让 <greet.h> 可找到"
has  "-I- 已被标记废弃" "$(gcc -I- -c use_greet.c -o /dev/null 2>&1)" "obsolete option '-I-'"
has  "默认头文件路径含 /usr/include" \
     "$(echo 'int main(void){}' | gcc -E -v - 2>&1 | sed -n '/search starts here/,/End of search/p')" '/usr/include'
has  "交叉头文件路径含 arm-linux-gnueabihf" \
     "$(echo 'int main(void){}' | ${CROSS}gcc -E -v - 2>&1 | sed -n '/search starts here/,/End of search/p')" 'arm-linux-gnueabihf/include'
eq   "-print-sysroot 本机为空"            "$(gcc -print-sysroot)" ""
eq   "-print-sysroot 交叉为 /（Ubuntu 布局）" "$(${CROSS}gcc -print-sysroot)" "/"
eq   "-dumpmachine 交叉三元组"            "$(${CROSS}gcc -dumpmachine)" "arm-linux-gnueabihf"
LF=$(gcc -print-file-name=libc.so)
[ -f "$LF" ] && ok "-print-file-name=libc.so 给出真实存在的文件" || no "-print-file-name 结果不存在" "$LF"
has  "-nostdinc 后连 stdio.h 都找不到" "$(gcc -nostdinc -c main.c -o /dev/null 2>&1)" 'no include path'
echo

echo "=== 04 篇 5 节  目标架构与 ABI ==="
${CROSS}gcc -O2 -marm   -c f_add.c -o f_arm.o   || die "-marm 编译失败"
${CROSS}gcc -O2 -mthumb -c f_add.c -o f_thumb.o || die "-mthumb 编译失败"
has  "-marm 的返回指令是 4 字节（e12fff1e）" "$(${CROSS}objdump -d f_arm.o)"   'e12fff1e'
has  "-mthumb 的返回指令是 2 字节（4770）"   "$(${CROSS}objdump -d f_thumb.o)" '4770'
cat > .fcaller.c <<'EOF'
float f_add(float a, float b);
float result;
void compute(void) { result = f_add(1.5f, 2.25f); }
EOF
${CROSS}gcc -O2 -mfloat-abi=softfp -c .fcaller.c -o f_caller_soft.o || die "softfp 编译失败"
${CROSS}gcc -O2 -mfloat-abi=hard   -c f_add.c    -o f_add_hard.o    || die "hard 编译失败"
eq   "softfp 的 .o 不带 VFP_args 标记"  "$(readelf -A f_caller_soft.o | grep -c VFP_args)" "0"
has  "hard 的 .o 标记 VFP registers"    "$(readelf -A f_add_hard.o)" 'Tag_ABI_VFP_args: VFP registers'
has  "两种 ABI 的 .o 链接器拒收" \
     "$(${CROSS}ld -r f_caller_soft.o f_add_hard.o -o merged.o 2>&1)" 'uses VFP register arguments'
${CROSS}gcc -static -O2 -Wall -Wextra main.c sub.c -o test_arm || die "交叉编译失败"
has  "交叉编译同一套选项产出 ARM ELF" "$(file test_arm)" 'ELF 32-bit LSB executable, ARM'
rm -f .fcaller.c
echo

echo "=== 04 篇 6 节  链接 ==="
ar rcs libsub.a sub.o || die "ar 打包失败"
gcc -o t_ok main.o -L. -lsub || die "正常链接失败"
eq   "-l 放在使用者之后：链接成功运行正常" "$(./t_ok)" "$(printf 'Main fun!\nSub fun!')"
has  "-l 放在使用者之前：undefined reference" \
     "$(gcc -o /dev/null -L. -lsub main.o 2>&1)" "undefined reference to .sub_fun."
gcc -shared -fPIC -o libsub.so sub.c || die "共享库构建失败"
gcc -o t_dyn main.o -L. -lsub        || die "动态链接失败"
has  "动态版 ldd 找不到本地 libsub.so" "$(ldd t_dyn)" 'libsub\.so => not found'
./t_dyn >/dev/null 2>&1
eq   "运行时找不到库退出码 127" "$?" "127"
eq   "LD_LIBRARY_PATH=. 之后能跑" "$(LD_LIBRARY_PATH=. ./t_dyn)" "$(printf 'Main fun!\nSub fun!')"
gcc -o t_dyn2 main.o sub.o; gcc -static -o t_static main.o sub.o
has  "-static 产物 ldd 说 not a dynamic executable" "$(ldd t_static 2>&1)" 'not a dynamic executable'
SZ_D=$(stat -c %s t_dyn2); SZ_S=$(stat -c %s t_static)
if [ $((SZ_S / SZ_D)) -ge 5 ]; then ok "-static 体积是动态版的 $((SZ_S / SZ_D)) 倍（$SZ_D -> $SZ_S）"
else no "-static 体积应大得多" "$SZ_D -> $SZ_S"; fi
gcc main.o -L. -lsub -static -o t_pos_after && file t_pos_after | grep -q 'statically linked' \
	&& ok "-static 写在 -l 之后产物仍是全静态（gcc 把它提到 collect2 最前面）" \
	|| no "-static 写后面产物仍应全静态"
W=$(gcc -nostartfiles -o t_ns main.o sub.o 2>&1)
has  "-nostartfiles 链出文件但告找不到 _start" "$W" 'cannot find entry symbol _start'
./t_ns >/dev/null 2>&1
eq   "缺启动文件的程序一跑就段错误（139）" "$?" "139"
has  "-nostdlib 报一大串 undefined reference" "$(gcc -nostdlib -o /dev/null main.o sub.o 2>&1)" "undefined reference to .puts."
gcc -Wl,-Map,t.map -o t_map main.o sub.o || die "-Wl,-Map 失败"
[ -s t.map ] && ok "-Wl,-Map 生成 map 文件" || no "map 文件应为非空"
cat > extra.c <<'EOF'
int extra_fun(void) { return 99; }
EOF
gcc -c extra.c -o extra.o && ar rcs libextra.a extra.o
gcc -o t_u0 main.o sub.o -L. -lextra
eq   "没被引用的库成员不进产物"      "$(nm t_u0 | grep -c ' T extra_fun')" "0"
gcc -o t_u1 main.o sub.o -L. -u extra_fun -lextra
eq   "-u 强制把库成员拉进来"          "$(nm t_u1 | grep -c ' T extra_fun')" "1"
echo

echo "=== 04 篇 7 节  预处理与依赖 ==="
eq   "ver.c 默认打印 no version"        "$(gcc ver.c -o t_v0 && ./t_v0)" "no version"
eq   "-DVERSION=7 打开宏"               "$(gcc -DVERSION=7 ver.c -o t_v7 && ./t_v7)" "version=7"
eq   "-D 之后 -U 同一名称抵消"          "$(gcc -DVERSION=7 -UVERSION ver.c -o t_vu && ./t_vu)" "no version"
has  "-dM 打出预定义宏与命令行宏" \
     "$(gcc -E -dM -DVERSION=3 ver.c | grep -E '^#define (VERSION 3|__linux__ 1)$' | wc -l)" '^2$'
has  "-M 输出含系统头文件"   "$(gcc -M main.c)"  'stdio\.h'
eq   "-MM 只列自己的头文件"  "$(gcc -MM main.c)" "main.o: main.c sub.h"
M_ERR=$(gcc -M main.c abc.dep 2>&1); M_RC=$?
eq   "-M 后面多写一个文件名：退出码 1" "$M_RC" "1"
has  "-M 的清单只打在 stdout（勘误）" "$M_ERR" 'linker input file not found'
gcc -MMD -c -o m2.o main.c && eq "-MMD 顺带产出 m2.d" "$(cat m2.d)" "m2.o: main.c sub.h"
gcc -MMD -MP -c -o mmp.o main.c
has  "-MP 为头文件补空规则" "$(cat mmp.d)" '^sub\.h:$'
gcc -MD -MF custom.dep -c -o m4.o main.c
has  "-MF 改依赖文件名（-MD 含系统头）" "$(head -1 custom.dep)" '^m4\.o: main\.c'
gcc -Wp,-MD,.m3.o.d -c -o m3.o main.c
has  "-Wp,-MD, 目标名按源文件推导（main.o，不理会 -o m3.o）" "$(head -1 .m3.o.d)" '^main\.o: main\.c'
eq   "-include 强制先包含" \
     "$(printf 'const char *s = GREETING;\n' | gcc -Ihdr -include greet.h -E -x c - | tail -1)" \
     'const char *s = "hi from header";'
mkdir -p st && (cd st && gcc -save-temps -c ../opt.c -o opt_st.o)
[ -f st/opt_st.i ] && [ -f st/opt_st.s ] && ok "-save-temps 按 -o 的名字留下 .i 和 .s" || no "-save-temps 应留下中间文件"
has  "-fsanitize=address 运行时抓越界" \
     "$(printf 'int a[4];\nint main(void){a[10]=1;return a[10];}\n' > .oob.c && gcc -fsanitize=address -g .oob.c -o .oob && ./.oob 2>&1 | head -2; rm -f .oob .oob.c)" \
     'AddressSanitizer'
echo

echo "=== 06 篇 1 节  规则与目标 ==="
rm -rf mk/.work && cp -r mk/pat mk/.work
OUT1=$(make -C mk/.work 2>&1)
has  "pat 首次 make 编译全部三个 .c" "$(echo "$OUT1" | grep -c '^gcc -c')" '^3$'
eq   "pat 产物运行正确" "$(mk/.work/app)" "1 2"
has  "第二次 make 无事可做" "$(make -C mk/.work 2>&1)" "up to date"
touch mk/.work/a.c
OUT3=$(make -C mk/.work 2>&1)
has  "touch a.c 只重编 a.o"        "$OUT3" 'gcc -c -o a\.o a\.c'
notin "touch a.c 不重编 main.o"    "$OUT3" 'gcc -c -o main\.o'
touch mk/.work/b.c
has  "make -n 只打印不执行" "$(make -C mk/.work -n 2>&1)" 'gcc -c -o b\.o b\.c'
[ -f mk/.work/b.o ] && rm -f mk/.work/b.o
OUT4=$(make -C mk/.work 2>&1)
has  "-n 之后真的没执行（b.o 需要重建）" "$OUT4" 'gcc -c -o b\.o b\.c'
printf 'all:\n    echo hi\n' > mk/.work/badtab.mk
has  "命令行用空格缩进报 missing separator" "$(make -C mk/.work -f badtab.mk 2>&1)" 'missing separator'
mkdir -p mk/.work/ph && cd mk/.work/ph
printf 'clean:\n\trm -f *.o\n' > Makefile && touch clean
has  "目录里有同名文件时 make clean 被挡" "$(make clean 2>&1)" "up to date"
printf '.PHONY: clean\nclean:\n\trm -f *.o\n\t@echo cleaned\n' > Makefile
has  ".PHONY 之后 clean 无条件执行" "$(make clean 2>&1)" 'cleaned'
cd ../../..
echo

echo "=== 06 篇 2 节  变量 ==="
V0=$(make -C mk -f 01_vars.mk show 2>&1)
has  "延时变量 A 看到后面才定义的 C"   "$V0" 'A\(=\)        = \[later\]'
has  "立即变量 B 在定义时定死为空"     "$V0" 'B\(:=\)       = \[\]'
has  "延时变量 += 保持延时（用到时才取 C）" "$V0" 'G\(= 后 \+=\)  = \[a later\]'
has  "立即变量 += 立即展开（此刻 C 为空）"  "$V0" 'H\(:= 后 \+=\) = \[a\]'
has  "?= 不覆盖已定义的值"             "$V0" 'D\(\?=\)       = \[file_value\]'
has  "E 未定义过，?= 生效"             "$V0" 'E\(\?=\)       = \[first_seen\]'
has  "命令行变量压过文件内赋值" "$(make -C mk -f 01_vars.mk show D=from_cmd 2>&1)" 'D\(\?=\)       = \[from_cmd\]'
has  "环境变量算已定义，?= 不覆盖" "$(E=from_env make -C mk -f 01_vars.mk show 2>&1)" 'E\(\?=\)       = \[from_env\]'
SR=$(make -C mk -f 02_selfref.mk show 2>&1); SR_RC=$?
eq   "延时变量自引用退出码 2" "$SR_RC" "2"
has  "自引用报 Recursive variable"  "$SR" "Recursive variable 'Y' references itself"
EX=$(make -C mk -f 08_export.mk recurse 2>&1)
has  "export 的 TOPDIR 子 make 可见"   "$EX" 'TOPDIR=\[/'
has  "没 export 的 CC 子 make 只见内置默认值 cc" "$EX" 'CC=\[cc\]'
sed 's/^export TOPDIR/export TOPDIR CC/' mk/08_export.mk > mk/.work_export.mk
has  "export CC 后子 make 看到 gcc" "$(make -C mk -f .work_export.mk recurse 2>&1)" 'CC=\[gcc\]'
rm -f mk/.work_export.mk
echo

echo "=== 06 篇 3 节  自动变量 ==="
cd mk && rm -f all a.txt b.txt c.txt && touch a.txt b.txt c.txt
AV=$(make -f 03_autovar.mk 2>&1)
has  '$@ 是目标'        "$AV" '^#? ?\$@ = all$' 2>/dev/null || has '$@ 是目标' "$AV" '\$@ = all'
has  '$< 是第一个依赖'  "$AV" '\$< = a\.txt'
has  '$^ 是全部依赖'    "$AV" '\$\^ = a\.txt b\.txt c\.txt'
has  '$? 首次全部算新'  "$AV" '\$\? = a\.txt b\.txt c\.txt'
touch b.txt
has  '$? 第二次只剩 b.txt' "$(make -f 03_autovar.mk 2>&1)" '\$\? = b\.txt'
rm -f all a.txt b.txt c.txt
cd ..
echo

echo "=== 06 篇 4 节  模式规则与隐含规则 ==="
has  "pat 的 %.o:%.c 规则吃到 a.c" "$(cd mk/.work && rm -f a.o && make a.o 2>&1)" 'gcc -c -o a\.o a\.c'
rm -f mk/imp/hello
IM=$(cd mk/imp && make hello 2>&1)
has  "没有 Makefile 也能用内置规则" "$IM" 'cc +.*hello\.c.*-o hello'
eq   "内置规则的产物能跑" "$(mk/imp/hello)" "implicit rule built me"
rm -f mk/imp/hello
has  "make -p 能看到内置的 %.o: %.c" "$(make -p -f /dev/null 2>/dev/null)" '^%\.o: %\.c$'
echo

echo "=== 06 篇 5 节  条件 ==="
has  "默认 x86 分支"      "$(make -C mk -f 05_cond.mk show 2>&1)" 'ARCH=x86 MSG=native'
has  "CROSS= 走 arm 分支" "$(make -C mk -f 05_cond.mk show CROSS=arm-linux-gnueabihf- 2>&1)" 'ARCH=arm MSG=cross build for arm'
has  "V=1 走 ifdef 分支"  "$(make -C mk -f 05_cond.mk show V=1 2>&1)" 'verbose mode'
echo

echo "=== 06 篇 6 节  函数 ==="
F=$(make -C mk -f 04_funcs.mk show 2>&1)
has  "subst"      "$F" 'subst     : fEEt on the strEEt'
has  "patsubst"   "$F" 'patsubst  : x\.c\.o bar\.o'
has  "strip"      "$F" 'strip     : \[a b c\]'
has  "findstring" "$F" 'findstring: \[a\] \[\]'
has  "filter"     "$F" 'filter    : foo\.c bar\.c baz\.s'
has  "filter-out" "$F" 'filter-out: ugh\.h'
has  "sort"       "$F" 'sort      : bar foo lose'
has  "dir"        "$F" 'dir       : src/ \./'
has  "notdir"     "$F" 'notdir    : foo\.c hacks'
has  "suffix"     "$F" 'suffix    : \.c'
has  "basename"   "$F" 'basename  : src/foo hacks'
has  "addsuffix"  "$F" 'addsuffix : foo\.c bar\.c'
has  "addprefix"  "$F" 'addprefix : src/foo src/bar'
WL="$(cd mk && make -f 04_funcs.mk show 2>/dev/null | grep '^wildcard')"
EXP_WL="wildcard  : $(cd mk && ls ../*.c 2>/dev/null | sort | tr '\n' ' ' | sed 's| | |g' | sed 's/ $//')"
if [ "$WL" = "$(echo "$EXP_WL" | sed 's|\.\./|../|g')" ] || echo "$WL" | grep -q 'main\.c'; then
	ok "wildcard 真去磁盘找文件（找到 main.c）"
else
	no "wildcard 应列出 ../ 下真实存在的 .c" "$WL"
fi
has  "foreach"    "$F" 'foreach   : \.main\.c\.d \.sub\.c\.d \.app\.c\.d'
has  "if 真分支"  "$F" 'if\(true\)  : non-empty'
has  "if 假分支"  "$F" 'if\(false\) : \[empty\]'
has  "firstword+subst 从三元组取架构" "$F" 'subst\+fw  : arm'
has  "shell 取命令结果" "$F" 'shell     : 42'
has  "origin 文件内定义" "$F" 'origin src: file'
has  "origin 内置默认"   "$F" 'origin CC : default'
has  "origin 未定义"     "$F" 'origin ZZ : undefined'
has  "命令行变量的 origin" "$(make -C mk -f 04_funcs.mk show CC=clang 2>&1)" 'origin CC : command line'
echo

echo "=== 06 篇 7 节  默认目标、include、命令行 ==="
has  ".DEFAULT_GOAL 钉住 all"   "$(make -C mk -f 06_default_goal.mk 2>&1)" 'real default goal runs'
sed 's/^\.DEFAULT_GOAL.*//' mk/06_default_goal.mk > mk/.work_nodg.mk
has  "不设 .DEFAULT_GOAL 被 include 方抢走" "$(make -C mk -f .work_nodg.mk 2>&1)" 'steal the default goal'
rm -f mk/.work_nodg.mk
has  "-include 容忍不存在的文件" "$(make -C mk -f 07_include.mk show 2>&1)" 'included nothing'
has  "make -C 切目录执行"        "$(make -C mk/sub show 2>&1)" 'Entering directory'
rm -rf mk/.work
echo

echo "======================================"
printf '  %d PASS / %d FAIL / %d SKIP\n' "$PASS" "$FAIL" "$SKIP"
echo "======================================"
[ "$FAIL" -eq 0 ]
