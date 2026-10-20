#!/bin/bash
# 03 篇 Makefile 的全部判据。在临时目录里复制一份工程再跑,不污染仓库。
# 用法: bash check.sh
set -u
cd "$(dirname "$0")" || exit 1
SRC=$PWD
PASS=0; FAIL=0; SKIP=0
ok()   { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
no()   { FAIL=$((FAIL+1)); printf '  FAIL  %s\n        期望 [%s]，实得 [%s]\n' "$1" "$3" "$2"; }
skip() { SKIP=$((SKIP+1)); printf '  SKIP  %s（%s）\n' "$1" "$2"; }
eq()   { if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "$2" "$3"; fi; }
has()  { if echo "$2" | grep -qF -- "$3"; then ok "$1"; else no "$1" "$2" "包含 $3"; fi; }
notin(){ if echo "$2" | grep -qF -- "$3"; then no "$1" "$2" "不含 $3"; else ok "$1"; fi; }

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
cp -r "$SRC"/mini_proj "$SRC"/proj "$SRC"/vars "$SRC"/funcs "$SRC"/phony "$SRC"/stale "$W"/

HAVE_CROSS=0
command -v arm-linux-gnueabihf-gcc >/dev/null && HAVE_CROSS=1

echo "=== mini_proj 第 0 步: 一条规则编全部 ==="
cd "$W/mini_proj"
OUT=$(make -f steps/step0/Makefile 2>&1)
eq "首次构建只有 1 条命令" "$OUT" "gcc -o app main.c math_ops.c display.c"
eq "立刻再 make: up to date" "$(make -f steps/step0/Makefile 2>&1)" "make: 'app' is up to date."
touch display.c
OUT=$(make -f steps/step0/Makefile 2>&1)
eq "touch 一个文件,三个 .c 全部重编" "$OUT" "gcc -o app main.c math_ops.c display.c"
make -f steps/step0/Makefile clean >/dev/null 2>&1
echo

echo "=== mini_proj 第 1 步: 四条写死的规则 ==="
OUT=$(make -f steps/step1/Makefile 2>&1)
eq "首次构建 4 条命令" "$(echo "$OUT" | grep -c '^gcc')" "4"
eq "运行输出第 1 行" "$(./app | sed -n '1p')" "1 + 2 = 3"
eq "运行输出第 2 行" "$(./app | sed -n '2p')" "hello, makefile"
OUT=$(make -f steps/step1/Makefile 2>&1)
eq "立刻再 make: up to date" "$OUT" "make: 'app' is up to date."
touch display.c
OUT=$(make -f steps/step1/Makefile 2>&1)
eq "touch display.c 后只重编 display.o" "$(echo "$OUT" | grep -c '^gcc -c')" "1"
has "重编的是 display.c" "$OUT" "gcc -c -o display.o display.c"
touch -d '2000-01-01' main.c
OUT=$(make -f steps/step1/Makefile 2>&1)
eq "mtime 改旧就不重编(比的是时间戳)" "$OUT" "make: 'app' is up to date."
OUT=$(make -f steps/step1/Makefile clean 2>&1)
eq "clean 后无残留" "$(ls app *.o 2>/dev/null | wc -l)" "0"
echo

echo "=== TAB 与默认值 ==="
mkdir "$W/tab" && cd "$W/tab"
printf 'all:\n    echo hi\n' > Makefile
OUT=$(make 2>&1)
has "空格缩进报 missing separator" "$OUT" "missing separator"
cd "$W/mini_proj"
OUT=$(make -f steps/step1/Makefile math_ops.o 2>&1)
eq "指定目标只编 math_ops.o" "$(ls *.o 2>/dev/null)" "math_ops.o"
make -f steps/step1/Makefile clean >/dev/null 2>&1
echo

echo "=== 假想目标 .PHONY ==="
cd "$W/phony"
eq "有 .PHONY 时 make clean 执行" "$(make clean 2>&1)" "cleaning"
grep -v 'PHONY' Makefile > "$W/nophony.mk"
touch clean
OUT=$(make -f "$W/nophony.mk" clean 2>&1)
eq "目录里有 clean 文件且没声明 .PHONY: 不执行" "$OUT" "make: 'clean' is up to date."
( grep -v 'PHONY' Makefile; echo '.PHONY: all clean' ) > "$W/phony3.mk"
eq "补回 .PHONY 后照常执行" "$(make -f "$W/phony3.mk" clean 2>&1)" "cleaning"
rm -f clean
echo

echo "=== 变量: 两种时机 ==="
cd "$W/vars"
OUT=$(make 2>&1)
eq "A := \$(C) 定义时 C 还是空" "$(echo "$OUT" | sed -n 's/^A=\[\(.*\)\]/\1/p')" ""
eq "B = \$(C) 用到时才展开"     "$(echo "$OUT" | sed -n 's/^B=\[\(.*\)\]/\1/p')" "abc"
eq "?= 挡不住已定义"           "$(echo "$OUT" | sed -n 's/^D=\[\(.*\)\]/\1/p')" "first"
eq "?= 对未定义的生效"         "$(echo "$OUT" | sed -n 's/^E=\[\(.*\)\]/\1/p')" "first"
eq "+= 追加"                   "$(echo "$OUT" | sed -n 's/^X=\[\(.*\)\]/\1/p')" "abc def"
OUT=$(make D=cmdline 2>&1)
eq "命令行变量覆盖文件内赋值" "$(echo "$OUT" | sed -n 's/^D=\[\(.*\)\]/\1/p')" "cmdline"
eq "延时变量在命令里展开能拿到 \$@" "$(make show 2>&1)" "VAL=[show]"
OUT=$(make prereq 2>&1)
has "规则的依赖在读取时展开(one 不存在)" "$OUT" "No rule to make target 'one'"
touch one
eq "依赖读取时展开,命令里再展开" "$(make prereq 2>&1)" "prereq 展开成了 one, 而 LIST 现在是 two"
rm -f one
OUT=$(make -C selfref 2>&1)
has "延时变量自引用报错" "$OUT" "Recursive variable 'Y' references itself"
echo

echo "=== 函数 ==="
cd "$W/funcs"
OUT=$(make 2>&1)
g() { echo "$OUT" | sed -n "s/^$1 *= *//p"; }
eq "wildcard 只收存在的 *.c"      "$(g files)" "a.c b.c"
eq "wildcard 丢掉不存在的 ghost.c" "$(g ask)"   "a.c b.c"
eq "替换引用 .c->.o"              "$(g objs)"  "a.o b.o"
eq "patsubst 不匹配的原样保留"     "$(g objs2)" "a.o b.o read.me"
eq "filter %/ 留下目录"           "$(g dirs)"  "src/ include/"
eq "filter-out %/ 扔掉目录"       "$(g plain)" "main.o"
eq "foreach 给每项加前后缀"        "$(g deps)"  ".a.o.d .b.o.d"
eq "if+subst+firstword 默认 x86"  "$(g arch)"  "x86"
eq "shell pwd 取当前目录"          "$(g top)"   "$W/funcs"
OUT=$(make CROSS=arm-linux-gnueabihf- 2>&1)
eq "CROSS 给了前缀 arch 变 arm" "$(echo "$OUT" | sed -n 's/^arch *= *//p')" "arm"
echo

echo "=== 内建隐式规则 ==="
mkdir "$W/bi" && cd "$W/bi"
cp "$W/mini_proj"/{main.c,math_ops.c,math_ops.h,display.c,display.h,config.h} .
printf 'app: main.o math_ops.o display.o\n\tgcc -o $@ $^\n' > Makefile
OUT=$(make 2>&1)
has "没写模式规则也编得出 .o(内建规则)" "$OUT" "cc    -c -o main.o main.c"
echo

echo "=== 没有头文件依赖时(第 3 步) ==="
cd "$W/mini_proj"
make -f steps/step3/Makefile >/dev/null 2>&1
touch config.h
eq "第 3 步 touch config.h: make 认为一切最新" "$(make -f steps/step3/Makefile 2>&1)" "make: 'app' is up to date."
make -f steps/step3/Makefile clean >/dev/null 2>&1
cd "$W/stale"
make >/dev/null 2>&1
eq "stale: 首次构建输出" "$(./app)" "x=1 y=2 sizeof=8"
sed -i 's/    int x, y;/    int tag;\n    int x, y;/' point.h
touch main.c
OUT=$(make 2>&1)
eq "stale: 只重编了 main.o" "$(echo "$OUT" | grep -c ' -c ')" "1"
eq "stale: 新旧 .o 拼起来,x、y 错位" "$(./app)" "x=2 y=0 sizeof=12"
make clean >/dev/null 2>&1; make >/dev/null 2>&1
eq "stale: 全量重编后恢复正确" "$(./app)" "x=1 y=2 sizeof=12"
cp "$SRC/stale/point.h" point.h; make clean >/dev/null 2>&1
echo

echo "=== 头文件自动依赖(第 4 步) ==="
cd "$W/mini_proj"
make -f steps/step4/Makefile >/dev/null 2>&1
eq ".d 文件内容是一条规则" "$(cat display.d)" "display.o: display.c config.h display.h"
touch config.h
OUT=$(make -f steps/step4/Makefile 2>&1)
eq "touch config.h 后恰好重编 1 个文件" "$(echo "$OUT" | grep -c '^gcc .*-c')" "1"
has "重编的是 display.c" "$OUT" "-c -o display.o display.c"
sed -i 's/hello, makefile/hello, auto-dep/' config.h
make -f steps/step4/Makefile >/dev/null 2>&1
eq "改了宏输出跟着变" "$(./app | sed -n '2p')" "hello, auto-dep"
touch math_ops.h
OUT=$(make -f steps/step4/Makefile 2>&1)
eq "touch math_ops.h 重编 include 它的 2 个文件" "$(echo "$OUT" | grep -c '^gcc .*-c')" "2"
sed -i 's/hello, auto-dep/hello, makefile/' config.h
OUT=$(make -f steps/step4/Makefile clean 2>&1)
eq "clean 后 .o .d app 全清" "$(ls app *.o *.d 2>/dev/null | wc -l)" "0"
echo "--- 注错对照: 去掉 -include 再 touch config.h ---"
sed 's/^-include/#-include/' steps/step4/Makefile > "$W/noinc.mk"
make -f "$W/noinc.mk" >/dev/null 2>&1
touch config.h
OUT=$(make -f "$W/noinc.mk" 2>&1)
eq "没有 .d 支撑时头文件改动被漏掉" "$OUT" "make: 'app' is up to date."
eq "漏编导致输出还是旧值" "$(./app | sed -n '2p')" "hello, makefile"
make -f "$W/noinc.mk" clean >/dev/null 2>&1
echo "--- include 与 -include ---"
sed 's/^-include/include/' steps/step4/Makefile > "$W/badinc.mk"
OUT=$(make -f "$W/badinc.mk" 2>&1)
has "首次 make 用 include 直接报错" "$OUT" "No rule to make target"
echo "--- -MP 与删头文件 ---"
sed 's/-MMD/-MMD -MP/' steps/step4/Makefile > "$W/mp.mk"
make -f "$W/mp.mk" >/dev/null 2>&1
sed -i '2,3d' display.c
sed -i 's/BANNER_TEXT/"bye"/' display.c
rm config.h
OUT=$(make -f "$W/mp.mk" 2>&1) && R1=ok || R1=fail
eq "带 -MP: 删了头文件还能继续编" "$R1" "ok"
eq "删头后的程序输出" "$(./app | sed -n '2p')" "bye"
cp "$SRC/mini_proj/display.c" "$SRC/mini_proj/config.h" .
make -f steps/step4/Makefile clean >/dev/null 2>&1
echo "--- 编译命令误用 \$^ ---"
sed 's/-c -o \$@ \$</-c -o $@ $^/' steps/step4/Makefile > "$W/caret.mk"
make -f "$W/caret.mk" >/dev/null 2>&1
touch config.h
OUT=$(make -f "$W/caret.mk" 2>&1)
has "\$^ 把 .h 也塞给 gcc,报 multiple files" "$OUT" "with multiple files"
make -f steps/step4/Makefile clean >/dev/null 2>&1
echo "--- 空命令规则覆盖模式规则 ---"
mkdir "$W/er" && cd "$W/er"
cp "$SRC/mini_proj"/{main.c,math_ops.c,math_ops.h,display.c,display.h,config.h} .
{ printf 'CC := gcc\n'
  printf 'app: main.o math_ops.o display.o\n\t$(CC) -o $@ $^\n'
  printf '%%.o: %%.c\n\t$(CC) -c -o $@ $<\n'; } > Makefile.good
{ cat Makefile.good; printf 'display.o: display.c config.h\n\t\n'; } > Makefile.bad
make -f Makefile.good >/dev/null 2>&1
touch config.h
OUT=$(make -f Makefile.bad 2>&1)
eq "带空命令的规则: 头文件改了也毫无动作" "$OUT" "make: 'app' is up to date."
grep -v '^	$' Makefile.bad > Makefile.fixed
touch config.h
OUT=$(make -f Makefile.fixed 2>&1)
has "删掉那个 TAB 空行后正常重编" "$OUT" "gcc -c -o display.o display.c"
rm -f *.o app
OUT=$(make -f Makefile.bad 2>&1)
has "带空命令的规则: 从零构建时 display.o 根本不会生成" "$OUT" "cannot find display.o"
echo "--- 手工补一条没有命令的依赖 ---"
rm -f *.o app
{ cat Makefile.good; printf 'display.o: config.h\n'; } > Makefile.hand
make -f Makefile.hand >/dev/null 2>&1
touch config.h
OUT=$(make -f Makefile.hand 2>&1)
has "手工依赖 display.o: config.h 生效" "$OUT" "gcc -c -o display.o display.c"
eq "手工依赖只重编 display.o" "$(echo "$OUT" | grep -c ' -c ')" "1"
echo

echo "=== mini_proj 中间形态 step2/step3 ==="
cd "$W/mini_proj"
make -f steps/step2/Makefile >/dev/null 2>&1 && eq "step2 构建并运行" "$(./app | head -1)" "1 + 2 = 3"
make -f steps/step2/Makefile clean >/dev/null 2>&1
make -f steps/step3/Makefile >/dev/null 2>&1
printf 'int mul(int a, int b) { return a * b; }\n' > extra.c
sed -i 's/#include "display.h"/#include "display.h"\nint mul(int, int);/' main.c
sed -i 's/print_banner();/print_banner(); printf("3 * 4 = %d\\n", mul(3, 4));/' main.c
OUT=$(make -f steps/step3/Makefile 2>&1)
has "step3: 新文件不改 Makefile 自动编进去" "$OUT" "-c -o extra.o extra.c"
eq "step3: 程序用到新文件" "$(./app | sed -n '3p')" "3 * 4 = 12"
rm extra.c
cp "$SRC/mini_proj/main.c" .
make -f steps/step3/Makefile clean >/dev/null 2>&1
eq "wildcard 的代价: 孤儿 extra.o 扫不掉" "$([ -f extra.o ] && echo yes)" "yes"
rm -f extra.o
printf '#include <stdio.h>\nint main(void) { puts("test"); return 0; }\n' > t_add.c
OUT=$(make -f steps/step3/Makefile 2>&1)
has "wildcard 的代价: 收进带 main 的测试文件" "$OUT" "multiple definition of \`main'"
rm -f t_add.c t_add.o
make -f steps/step3/Makefile clean >/dev/null 2>&1
echo

echo "=== mini_proj 最终形态(第 5 步) ==="
cd "$W/mini_proj"
make >/dev/null 2>&1
eq "默认 gcc 本机构建可运行" "$(./app | head -1)" "1 + 2 = 3"
make clean >/dev/null 2>&1
if [ "$HAVE_CROSS" -eq 1 ]; then
  make CROSS=arm-linux-gnueabihf- >/dev/null 2>&1
  has "make CROSS=... 产物是 ARM" "$(file app)" "ARM"
  make clean >/dev/null 2>&1
  make >/dev/null 2>&1
  eq "不 clean 直接换架构: make 回答 up to date" "$(make CROSS=arm-linux-gnueabihf- 2>&1)" "make: 'app' is up to date."
  touch main.c
  has "不 clean 直接换架构: 新旧架构 .o 混链报错" "$(make CROSS=arm-linux-gnueabihf- 2>&1)" "file format not recognized"
  make clean >/dev/null 2>&1
else
  skip "交叉编译判据" "没装 arm-linux-gnueabihf-gcc"
fi
echo

echo "=== proj 递归构建 ==="
cd "$W/proj"
OUT=$(make 2>&1)
has "引擎被 -f 调起" "$OUT" "make -f Makefile.build"
has "递归进子目录"   "$OUT" "make -C a -f"
eq  "app 输出 6 行" "$(./app | wc -l)" "6"
eq  "app 输出内容"  "$(./app | tr '\n' '|')" "sub|sub2|sub2 debug|sub3 magic=3|sub3 debug|sub3 debug only|"
S3=$(echo "$OUT" | grep 'sub3.c'); S2=$(echo "$OUT" | grep 'sub2.c')
has "sub3 带单文件选项 -DDEBUG_SUB3" "$S3" "-DDEBUG_SUB3"
notin "sub2 不带 -DDEBUG_SUB3" "$S2" "-DDEBUG_SUB3"
has "本目录合并不进 DEBUG(a/ 的 EXTRA_CFLAGS 不外溢到顶层)" "$(echo "$OUT" | grep 'main.c')" "Wp,-MMD,.main.o.d"
notin "顶层 main.c 不带 -DDEBUG" "$(echo "$OUT" | grep 'main.c')" "-DDEBUG"
OUT2=$(make 2>&1)
eq "第二次 make 不重编不重链接" "$(echo "$OUT2" | grep -c '^gcc\|^ld ')" "0"
touch include/sub3.h
OUT=$(make 2>&1)
eq "touch sub3.h 恰好重编 1 个 .c" "$(echo "$OUT" | grep -c ' -c -o ')" "1"
eq "两层 built-in.o 重新合并" "$(echo "$OUT" | grep -c '^ld -r')" "2"
eq "重新链接 app" "$(echo "$OUT" | grep -c '^gcc -o app')" "1"
eq "built-in.o 恰好两个" "$(find . -name built-in.o | wc -l)" "2"
has "隐藏 .d 记录到头文件" "$(cat a/.sub3.o.d)" "sub3.h"
if [ "$HAVE_CROSS" -eq 1 ]; then
  make clean >/dev/null 2>&1
  make CROSS_COMPILE=arm-linux-gnueabihf- >/dev/null 2>&1
  has "proj 交叉编译产物是 ARM" "$(file app)" "ARM"
  make clean >/dev/null 2>&1
else
  skip "proj 交叉编译判据" "没装 arm-linux-gnueabihf-gcc"
fi
echo "--- make -j2 ---"
make clean >/dev/null 2>&1
make -j2 >/dev/null 2>&1 && R=ok || R=fail
eq "make -j2 从零构建成功" "$R" "ok"
touch include/sub3.h
OUT=$(make -j2 2>&1)
eq "make -j2 下 touch sub3.h 后仍重新链接 app" "$(echo "$OUT" | grep -c '^gcc -o app')" "1"
echo "--- 注错: 不 export TOPDIR ---"
make clean >/dev/null 2>&1
sed -i 's/^export AS CC LD TOPDIR/export AS CC LD/' Makefile
OUT=$(make 2>&1)
has "子目录里 TOPDIR 为空,-I 变成 /include" "$OUT" "-I/include "
has "子目录找不到头文件" "$OUT" "sub2.h: No such file or directory"
cp "$SRC/proj/Makefile" Makefile
make clean >/dev/null 2>&1
echo "--- 注错: 从 obj-y 里去掉 sub2.o ---"
sed -i 's/^obj-y += sub2.o//' a/Makefile
OUT=$(make 2>&1)
has "链接必须报 undefined reference" "$OUT" "undefined reference to \`sub2_print'"
cp "$SRC/proj/a/Makefile" a/Makefile
make clean >/dev/null 2>&1
echo "--- 坑一: 删掉 .DEFAULT_GOAL ---"
sed -i '/DEFAULT_GOAL/d' Makefile.build
OUT=$( ( ulimit -u 256; timeout 20 make ) 2>&1 )
if echo "$OUT" | grep -q 'Resource temporarily unavailable' || [ "$(echo "$OUT" | grep -c 'Entering directory')" -gt 50 ]; then
  ok "默认目标被抢导致无限递归"
else
  no "默认目标被抢应无限递归" "$(echo "$OUT" | tail -2)" "递归到资源耗尽"
fi
cp "$SRC/proj/Makefile.build" Makefile.build
echo "--- 坑二: __build 规则写到过滤之前 ---"
grep -v -e '^__build:' -e '^	@:$' Makefile.build > "$W/mb.tmp"
awk '{print} /^include Makefile$/{print "__build: $(subdir-y) built-in.o"; print "\t@:"}' "$W/mb.tmp" > Makefile.build
OUT=$(make 2>&1)
has "子目录永远不被递归" "$OUT" "No rule to make target 'a/built-in.o'"
cp "$SRC/proj/Makefile.build" Makefile.build

echo "======================================"
printf '  %d PASS / %d FAIL / %d SKIP\n' "$PASS" "$FAIL" "$SKIP"
echo "======================================"
[ "$FAIL" -eq 0 ]
