#!/bin/bash
#
# project 框架判据。在 WSL 里跑: bash check.sh
#
# 两条原则:
#   1. 判据尽量做成计数型或序列型, 不做"某条输出里有某个词"型 -- 后者太容易假绿。
#   2. 每条正判据后面都跟一次注错见红: 故意把代码或 Makefile 改坏, 判据必须变红。
#      注错不红的判据等于没有判据。
#
# 所有破坏性操作都在临时副本里做, 不动工作区。

set -u

SRC=$(cd "$(dirname "$0")" && pwd)
CROSS_PREFIX=${CROSS_PREFIX:-arm-linux-gnueabihf-}

PASS=0; FAIL=0; SKIP=0

ck()   { if [ "$2" = "$3" ]; then echo "  PASS  $1 = $2"; PASS=$((PASS+1));
         else echo "  FAIL  $1: got [$2] want [$3]"; FAIL=$((FAIL+1)); fi; }
red()  { if [ "$2" != "$3" ]; then echo "  PASS  注错见红: $1 变成 [$2]"; PASS=$((PASS+1));
         else echo "  FAIL  注错没红: $1 仍是 [$3], 这条判据是假绿"; FAIL=$((FAIL+1)); fi; }
skip() { echo "  SKIP  $1 ($2)"; SKIP=$((SKIP+1)); }

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
cp -r "$SRC" "$W/project"
cd "$W/project" || exit 1
rm -rf build

NSRC=$(find . -name '*.c' -not -path './build/*' | wc -l)
INIT_SEQ="display input font ui page business "
EXIT_SEQ="business page ui font input display "

echo "[1] 构建 + 分层启停顺序    (源文件 $NSRC 个)"
make >/dev/null 2>&1
out=$(./build/x86/product_tool 2>&1); rc=$?
ck "退出码"        "$rc" "0"
ck "init OK 行数"  "$(echo "$out" | grep -c 'init OK')" "6"
ck "exit OK 行数"  "$(echo "$out" | grep -c 'exit OK')" "6"
ck "init 顺序"     "$(echo "$out" | grep 'init OK' | awk '{print $(NF-2)}' | tr '\n' ' ')" "$INIT_SEQ"
ck "exit 顺序反向" "$(echo "$out" | grep 'exit OK' | awk '{print $(NF-2)}' | tr '\n' ' ')" "$EXIT_SEQ"

echo "[1r] 注错: 从 main.c 的层表里删掉 business 那一行"
sed -i '/{ "business",/d' main.c
make >/dev/null 2>&1
out2=$(./build/x86/product_tool 2>&1)
red "init OK 行数" "$(echo "$out2" | grep -c 'init OK')" "6"
ck  "其余 5 层照常启停(层间无隐式耦合)" "$(echo "$out2" | grep -c 'exit OK')" "5"
cp "$SRC/main.c" main.c

echo "[2] 交叉编译 + 两个架构的产物并存"
if command -v ${CROSS_PREFIX}gcc >/dev/null 2>&1; then
	make >/dev/null 2>&1
	make CROSS=$CROSS_PREFIX >/dev/null 2>&1
	ck "ARM 产物 Machine"  "$(readelf -h build/arm/product_tool | sed -n 's/^ *Machine: *//p')" "ARM"
	ck "x86 产物 Machine"  "$(readelf -h build/x86/product_tool | sed -n 's/^ *Machine: *//p')" "Advanced Micro Devices X86-64"
	ck "两份产物同时存在"  "$(ls build/*/product_tool | wc -l)" "2"
	make clean >/dev/null 2>&1
	ck "make clean 只清当前架构" "$(ls build/*/product_tool 2>/dev/null | wc -l)" "1"
	make distclean >/dev/null 2>&1
	ck "make distclean 清干净"   "$(ls -d build 2>/dev/null | wc -l)" "0"
else
	skip "交叉编译判据" "没装 ${CROSS_PREFIX}gcc"
fi

echo "[3] 新增 .c 不用改 Makefile"
rm -rf build
cat > display/disp_dummy.c <<'X'
#include "common.h"
int disp_dummy_probe(void) { return ERR_NOTSUP; }
X
make >/dev/null 2>&1
ck "新增文件被编译" "$([ -f build/x86/display/disp_dummy.o ] && echo yes || echo no)" "yes"

echo "[3r] 注错: 把 SRCS 的 wildcard 换成写死的文件清单"
sed -i "s|^SRCS .*|SRCS := main.c common.c display/disp_manager.c input/input_manager.c font/font_manager.c ui/ui_manager.c page/page_manager.c business/business_manager.c|" Makefile
rm -rf build
make >/dev/null 2>&1
red "新增文件被编译" "$([ -f build/x86/display/disp_dummy.o ] && echo yes || echo no)" "yes"
cp "$SRC/Makefile" Makefile
rm -f display/disp_dummy.c

echo "[4] 头文件自动依赖: 改 include/common.h 必须全量重编"
rm -rf build
make >/dev/null 2>&1
touch include/common.h
ck "重编文件数" "$(make 2>&1 | grep -c '^  CC ')" "$NSRC"

echo "[4r] 注错: 去掉 -MMD -MP, .d 文件不再生成"
sed -i 's/ -MMD -MP//' Makefile
rm -rf build
make >/dev/null 2>&1
touch include/common.h
red "重编文件数" "$(make 2>&1 | grep -c '^  CC ')" "$NSRC"
cp "$SRC/Makefile" Makefile

echo "[5] 日志可整体关闭"
rm -rf build
make CFLAGS_EXTRA=-DLOG_LEVEL=0 >/dev/null 2>&1
ck "LOG_LEVEL=0 时输出行数" "$(./build/x86/product_tool 2>&1 | wc -l)" "0"
ck "LOG_LEVEL=0 时退出码"   "$(./build/x86/product_tool >/dev/null 2>&1; echo $?)" "0"

echo "[6] 日志落文件: LOG_FILE 存在时把 stderr 整条接到文件"
rm -rf build
make >/dev/null 2>&1
LOGF="$W/run.log"
rm -f "$LOGF"
ck "不设 LOG_FILE 时终端行数" "$(./build/x86/product_tool 2>&1 | wc -l)" "13"
ck "设了 LOG_FILE 时终端行数" "$(LOG_FILE=$LOGF ./build/x86/product_tool 2>&1 | wc -l)" "0"
ck "第一次跑完文件行数"       "$(wc -l < "$LOGF")" "13"
LOG_FILE=$LOGF ./build/x86/product_tool >/dev/null 2>&1
ck "第二次跑完文件行数(O_APPEND 接着写)" "$(wc -l < "$LOGF")" "26"
ck "日志文件打不开时退出码"   "$(LOG_FILE=/no/such/dir/x.log ./build/x86/product_tool >/dev/null 2>&1; echo $?)" "1"

# stderr 不带缓冲 => 13 条日志正好是 13 次 write。这条是 02 章第 4 节那个结论的守门人。
if command -v strace >/dev/null 2>&1; then
	rm -f "$LOGF"
	strace -f -e trace=write -o "$W/tw.txt" \
		env LOG_FILE=$LOGF ./build/x86/product_tool >/dev/null 2>&1
	ck "13 条日志对应 13 次 write(2,...)" \
	   "$(grep -cE '(^|[0-9]+ +)write\(2,' "$W/tw.txt")" "13"
else
	skip "stderr 无缓冲判据" "没装 strace"
fi

echo "[6r] 注错: O_APPEND 换成 O_TRUNC"
sed -i 's/O_WRONLY | O_CREAT | O_APPEND/O_WRONLY | O_CREAT | O_TRUNC/' common.c
rm -rf build
make >/dev/null 2>&1
rm -f "$LOGF"
LOG_FILE=$LOGF ./build/x86/product_tool >/dev/null 2>&1
LOG_FILE=$LOGF ./build/x86/product_tool >/dev/null 2>&1
red "第二次跑完文件行数" "$(wc -l < "$LOGF")" "26"

echo "[6r2] 注错: 去掉 dup2, 只开文件不换 2 号槽"
cp "$SRC/common.c" common.c
sed -i 's/if (dup2(fd, STDERR_FILENO) < 0)/if (0)/' common.c
rm -rf build
make >/dev/null 2>&1
rm -f "$LOGF"
LOG_FILE=$LOGF ./build/x86/product_tool >/dev/null 2>&1
red "第一次跑完文件行数" "$(wc -l < "$LOGF")" "13"
cp "$SRC/common.c" common.c

echo
echo "PASS=$PASS  FAIL=$FAIL  SKIP=$SKIP"
[ "$FAIL" -eq 0 ]
