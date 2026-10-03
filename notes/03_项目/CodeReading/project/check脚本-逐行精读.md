# check 脚本逐行精读

对应代码：`project/check.sh`（36 行，总入口）、`check_core.sh`（305 行，
框架/display 的 52 条判据）、`check_font_input.sh`（159 行，font/input 的 21 条判据）。

## 1. 文件定位

判据体系的三层结构：总入口设好确定性环境后调两个 suite，汇总数字并要求
两边退出码都为 0。两条原则写在 `check_core.sh` 头部：判据做成计数型或序列型，
不做"输出里有某个词"型；每条正判据后面跟一次注错见红，注错不红的判据等于
没有判据。所有破坏性操作（sed 注错、删文件）都发生在 `/tmp` 临时副本里，
不动工作区。

前置知识：[从零开始读写 project 代码](../00-从零开始读写项目代码.md)第 9.2 节；
判据数字的出处是 TechReports/project 各章第五节。

```
check.sh(36 行)
  ├─ export 确定性环境(DISP_DEV=mem FONT_DEV=builtin INPUT_BACKEND=replay)
  ├─ bash check_core.sh        → PASS=52 行
  ├─ bash check_font_input.sh  → PASS=21 行
  └─ 汇总 TOTAL PASS=73 FAIL=0 SKIP=0; 两个 rc 都 0 且 FAIL=0 才退 0
```

## 2. check.sh

### 第 1—16 行：环境固定

```bash
#!/bin/bash
# 总入口：原有框架/display 判据与 font/input 判据分文件维护，这里汇总数字。

set -u
SRC=$(cd "$(dirname "$0")" && pwd)
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT

# WSL 没有真实 framebuffer/evdev；核心框架判据选两个确定性的内存后端。
export DISP_DEV=mem
export FONT_DEV=builtin
export INPUT_BACKEND=replay
export INPUT_REPLAY=/dev/null

# check_core.sh 会把 project/ 复制进 /tmp；依赖包不能再用相对仓库路径。
export FT_TARBALL=${FT_TARBALL:-/mnt/e/Workspace/01_all_series_quickstart-master/04_嵌入式Linux应用开发基础知识/source/10_freetype/freetype-2.10.2.tar.xz}
```

`set -u` 抓未定义变量。四个 export 把"WSL 没有 fb/evdev"这个事实固定成
确定性输入：假显存 + builtin 字体 + `/dev/null` 回放（读到 EOF 即退出，
不产生事件）。`FT_TARBALL` 用 `:-` 缺省展开成绝对路径，外部可覆盖；
TechReport 04 第 4.3 节记录了它为什么必须是绝对路径。

### 第 18—36 行：调度与汇总

```bash
run_suite() {
	local script=$1 output=$2
	bash "$SRC/$script" 2>&1 | tee "$output"
	return "${PIPESTATUS[0]}"
}

run_suite check_core.sh "$W/core.out"; CORE_RC=$?
run_suite check_font_input.sh "$W/font_input.out"; EXTRA_RC=$?

read_result() {
	sed -n 's/^PASS=\([0-9][0-9]*\)  FAIL=\([0-9][0-9]*\)  SKIP=\([0-9][0-9]*\)$/\1 \2 \3/p' "$1" | tail -1
}

read -r P1 F1 S1 <<<"$(read_result "$W/core.out")"
read -r P2 F2 S2 <<<"$(read_result "$W/font_input.out")"

echo
echo "TOTAL PASS=$((P1 + P2))  FAIL=$((F1 + F2))  SKIP=$((S1 + S2))"
[ "$CORE_RC" -eq 0 ] && [ "$EXTRA_RC" -eq 0 ] && [ "$((F1 + F2))" -eq 0 ]
```

`PIPESTATUS[0]` 取管道第一个命令的退出码——`tee` 恒成功，`$?` 会把失败
洗成成功，这是判据脚本最常见的假绿来源。退出条件是三份独立证据：
两个 suite 的 rc 与汇总的 FAIL 数，任一非零整体非零。
`read_result` 只认行尾的 `PASS=n  FAIL=n  SKIP=n` 格式，suite 自己的汇总行
是唯一事实来源，入口不重复计数。

## 3. check_core.sh

### 第 1—33 行：头部与工具函数

```bash
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

# 本机上没有 /dev/fb0, display 层缺省选 fb 会 init 失败, 整个框架起不来。
# 这里统一选假显存后端, [7] 组里再单独验 fb 后端的失败路径。
export DISP_DEV=mem

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
```

`ck`/`red`/`skip` 三个原语贯穿两个 suite：`ck` 断言相等，`red` 断言**不等**
（注错之后期望值必须变化），`skip` 记录环境缺失。工作副本整体复制进
`/tmp` 再 `rm -rf build`，保证每次判据都是全量重建——增量产物会让
"改了头文件必重编"这类判据失真。

### 第 35—55 行：[1] 启停顺序

```bash
# unittest/ 由 make test 单独编, make 不碰它, 所以不算进"应该重编的文件数"
NSRC=$(find . -name '*.c' -not -path './build/*' -not -path './unittest/*' | wc -l)
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
```

启停顺序是序列型判据：`awk '{print $(NF-2)}'` 从 `display init OK` 里取层名
拼成序列再整体比对，任何一处乱序都红。注错删一行层表后，期望从"6 变成 6"
的反面是 5——`red` 同时验证了"其余层不受影响"（`ck` 5 层照常），
一条注错回答两个问题。注错后 `cp "$SRC/..."` 逐文件还原。

### 第 57—70 行：[2] 交叉编译

```bash
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
```

验证的是 Makefile 的架构隔离设计：产物树按 ARCH 分、clean 分档。
`readelf` 读 Machine 字段是产物级证据，不信任 make 的回显。
`SKIP` 分支让没装交叉工具链的机器只损失这一组（2026-09 中旬 arm gcc
被卸载时这一组曾长期 SKIP，重装后恢复）。

### 第 72—101 行：[3][4] 构建系统两条性质

```bash
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
```

两条性质各配一条注错。[3] 的探针文件落在 display/ 目录，wildcard 必须
收编它；[4] 的 `touch` 只改时间戳不改内容——重编由 `.d` 依赖驱动，
数 `^  CC ` 行数与 `NSRC`（排除 build/unittest 的源文件数）对账。
NSRC 的两个 `-not -path` 是踩过的坑：unittest 由 `make test` 单独编，
算进总数会让 [4] 永远差 3。

### 第 103—167 行：[5][6] 日志

```bash
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
bad_out=$(LC_ALL=C LOG_FILE=/no/such/dir/x.log ./build/x86/product_tool 2>&1); bad_rc=$?
ck "日志文件打不开时退出码" "$bad_rc" "1"
ck "日志文件打不开时系统错误" \
   "$(printf '%s\n' "$bad_out" | sed -n 's|^.*cannot redirect log to /no/such/dir/x.log: ||p')" \
   "device io failed (No such file or directory)"
empty_out=$(LC_ALL=C LOG_FILE= ./build/x86/product_tool 2>&1)
ck "LOG_FILE 为空时只有参数错误" \
   "$(printf '%s\n' "$empty_out" | sed -n 's|^.*cannot redirect log to : ||p')" \
   "invalid parameter"

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
```

13 行是六个层 init/exit 加框架日志的精确计数——计数型判据对行数敏感，
多一条日志就红，逼着改日志的人顺手改判据。`LC_ALL=C` 固定错误文本的
语言。strace 组把"stderr 无缓冲"从课本结论变成可数的系统调用事实。

### 第 140—167 行：[6r*] 三条注错

```bash
echo "[6r] 注错: O_APPEND 换成 O_TRUNC"
sed -i 's/O_WRONLY | O_CREAT | O_APPEND/O_WRONLY | O_CREAT | O_TRUNC/' common.c
rm -rf build
make >/dev/null 2>&1
rm -f "$LOGF"
LOG_FILE=$LOGF ./build/x86/product_tool >/dev/null 2>&1
LOG_FILE=$LOGF ./build/x86/product_tool >/dev/null 2>&1
red "第二次跑完文件行数" "$(wc -l < "$LOGF")" "26"

echo "[6r2] 注错: 去掉 dup2, 日志去向没有从终端改成文件"
cp "$SRC/common.c" common.c
sed -i 's/if (dup2(fd, STDERR_FILENO) < 0)/if (0)/' common.c
rm -rf build
make >/dev/null 2>&1
rm -f "$LOGF"
LOG_FILE=$LOGF ./build/x86/product_tool >/dev/null 2>&1
red "第一次跑完文件行数" "$(wc -l < "$LOGF")" "13"
cp "$SRC/common.c" common.c

echo "[6r3] 注错: open 失败时不带出 errno"
sed -i 's/\*os_errno = errno;/\*os_errno = 0;/' common.c
rm -rf build
make >/dev/null 2>&1
bad_out=$(LC_ALL=C LOG_FILE=/no/such/dir/x.log ./build/x86/product_tool 2>&1)
red "日志文件打不开时系统错误" \
    "$(printf '%s\n' "$bad_out" | sed -n 's|^.*cannot redirect log to /no/such/dir/x.log: ||p')" \
    "device io failed (No such file or directory)"
cp "$SRC/common.c" common.c
```

三条注错各打一个特征：O_TRUNC 让第二次运行把文件清成 13 行（26 见红）；
dup2 失效让文件保持 0 行；errno 失效让报错丢掉括号里的系统原因。
每条注错针对的代码位置互不重叠，恢复用 `cp "$SRC/common.c"`。

### 第 169—250 行：[7] display 像素对账与六条注错

```bash
# ---------------------------------------------------------------------------
# display 层。计数全部由 unittest/count.sh 独立算出来, 被测程序自己不统计。
# 所有像素判据都跑在行尾有填充的假显存上: 没有填充时算错行宽也看不出来,
# 见 [7r2]。
# ---------------------------------------------------------------------------

D32="00000000:2007 000000ff:12 0000ff00:12 00ff0000:12 00ffff00:4 00ffffff:1"
D16="0000:2007 001f:12 07e0:12 f800:12 ffe0:4 ffff:1"
PAD32="size 10240 pad_AA 2048 pad_total 2048"
AT32="at (1,1)=00ff0000 (4,3)=00ff0000 (5,1)=00000000 (6,1)=0000ff00 (11,1)=000000ff (63,31)=00ffffff (63,5)=00ffff00 (62,6)=00ffff00 (61,5)=00000000 (0,0)=00000000"

# 跑一遍单测, 把转储交给 count.sh, 输出三行: size/pad, 像素值分布, 抽查坐标
disp_run() {
	m=$1
	cw=${m%%x*}; t=${m#*x}; chh=${t%%x*}; t=${t#*x}; cb=${t%%x*}; cl=${t##*x}
	DISP_MEM="$m" DISP_MEM_DUMP="$W/d.raw" \
		./build/x86/unittest/disp_test >"$W/d.out" 2>&1
	sh unittest/count.sh "$W/d.raw" "$cw" "$chh" "$cb" "$cl"
}

echo "[7] display 层: 位置 + 位段 + 边界"
rm -rf build
make >/dev/null 2>&1
make test >/dev/null 2>&1
ck "make test 产出单测" "$([ -x build/x86/unittest/disp_test ] && echo yes || echo no)" "yes"
ck "32bpp 像素值分布" "$(disp_run 64x32x32x320 | sed -n 2p)" "$D32"
ck "32bpp 转储大小与哨兵" "$(disp_run 64x32x32x320 | sed -n 1p)" "$PAD32"
ck "32bpp 抽查坐标" "$(disp_run 64x32x32x320 | sed -n 3p)" "$AT32"
ck "越界 put_pixel 被拒" \
   "$(disp_run 64x32x32x320 >/dev/null; grep '^out of range' "$W/d.out")" \
   "out of range put_pixel ret -1"
ck "16bpp 像素值分布(565 三个分量都要对)" "$(disp_run 64x32x16x192 | sed -n 2p)" "$D16"

if command -v python3 >/dev/null 2>&1; then
	disp_run 64x32x32x320 >"$W/by_sh.txt"
	ck "count.sh 与 count.py 两个独立实现结果一致" \
	   "$(python3 unittest/count.py "$W/d.raw" 64 32 32 320 | diff -q - "$W/by_sh.txt" >/dev/null && echo same || echo differ)" \
	   "same"
else
	skip "两个计数实现互校" "没装 python3"
fi
```

`disp_run` 是本组的万能驱动：从 `64x32x32x320` 拆出四个数喂给 count.sh，
期望值 `D32/D16/PAD32/AT32` 全部是假显存几何下可独立手算的数（12 个像素的
红块、4 个重叠的黄块、右下角白点）。D16 的五个非零值把 RGB565 三个位段
一起锁死。两个计数实现互校防的是计数脚本自身的错。

```bash
echo "[7r1] 注错: put_pixel 的行宽换成 xres * bpp / 8"
sed -i 's@y \* g_buf.line_length@y * (g_buf.xres * g_buf.bpp / 8)@' display/disp_manager.c
make >/dev/null 2>&1; make test >/dev/null 2>&1
red "32bpp 像素值分布" "$(disp_run 64x32x32x320 | sed -n 2p)" "$D32"
red "32bpp 转储大小与哨兵" "$(disp_run 64x32x32x320 | sed -n 1p)" "$PAD32"

echo "[7r2] 同一个错, 换成行尾没有填充的 64x32x32x256"
ck "行宽算错在无填充的显存上看不出来(所以上面几条必须跑有填充的)" \
   "$(disp_run 64x32x32x256 | sed -n 2p)" "$D32"
cp "$SRC/display/disp_manager.c" display/disp_manager.c

echo "[7r3] 注错: put_pixel 去掉 x >= xres 检查"
sed -i 's@x >= g_buf.xres || @@' display/disp_manager.c
make >/dev/null 2>&1; make test >/dev/null 2>&1
red "越界 put_pixel 被拒" \
    "$(disp_run 64x32x32x320 >/dev/null; grep '^out of range' "$W/d.out")" \
    "out of range put_pixel ret -1"
red "32bpp 转储大小与哨兵" "$(disp_run 64x32x32x320 | sed -n 1p)" "$PAD32"
cp "$SRC/display/disp_manager.c" display/disp_manager.c

echo "[7r4] 注错: 红和蓝的位段对调"
sed -i -e 's@&g_buf.red)@\&g_buf.XCHG)@' -e 's@&g_buf.blue)@\&g_buf.red)@' \
       -e 's@&g_buf.XCHG)@\&g_buf.blue)@' display/disp_manager.c
make >/dev/null 2>&1; make test >/dev/null 2>&1
red "32bpp 抽查坐标" "$(disp_run 64x32x32x320 | sed -n 3p)" "$AT32"
cp "$SRC/display/disp_manager.c" display/disp_manager.c

echo "[7r5] 注错: 拼色不缩位, 8 位分量直接挪到 offset"
sed -i 's@(c8 >> (8 - f->length))@(c8)@' display/disp_manager.c
make >/dev/null 2>&1; make test >/dev/null 2>&1
red "16bpp 像素值分布(565 三个分量都要对)" "$(disp_run 64x32x16x192 | sed -n 2p)" "$D16"
cp "$SRC/display/disp_manager.c" display/disp_manager.c

echo "[7r6] 注错: fill_rect 去掉右边界裁剪"
sed -i 's@x1 = r->x + r->w > g_buf.xres ? g_buf.xres : r->x + r->w;@x1 = r->x + r->w;@' \
	display/disp_manager.c
make >/dev/null 2>&1; make test >/dev/null 2>&1
ck "fill_rect 的裁剪是冗余的(边界由 put_pixel 兜住), 它防的是以后绕开 put_pixel 的写法" \
   "$(disp_run 64x32x32x320 | sed -n 2p)" "$D32"
cp "$SRC/display/disp_manager.c" display/disp_manager.c
```

六条注错里 [7r2] 最特别：它期望**不红**（`ck` 而非 `red`）。同一个行宽错误
在无填充显存上无症状——这条判据钉住的是"为什么判据必须跑在 320 行宽上"，
删掉它，未来有人"优化"掉填充几何时不会有人发现判据失去了效力。
[7r6] 同理：期望不红，钉住冗余裁剪的存在理由。

### 第 252—305 行：[8][9][10]

```bash
echo "[8] fb 后端: 打不开设备时把 fd 还回去"
# /dev/null 能 open, 但不是帧缓冲, FBIOGET_VSCREENINFO 必定 ENOTTY,
# 正好停在"fd 已开、ioctl 失败"这一步。
fb_seq() {
	DISP_DEV=fb DISP_FB=/dev/null strace -e trace=openat,ioctl,close \
		-o "$W/s.txt" ./build/x86/product_tool >/dev/null 2>&1
	sed -n '/"\/dev\/null"/,$p' "$W/s.txt" | head -3 | sed 's/(.*//' | tr '\n' ' '
}
if command -v strace >/dev/null 2>&1; then
	make >/dev/null 2>&1
	ck "open 成功、ioctl 失败时的系统调用序列" "$(fb_seq)" "openat ioctl close "
	ck "fb 后端失败时整个程序的退出码" \
	   "$(DISP_DEV=fb DISP_FB=/dev/null ./build/x86/product_tool >/dev/null 2>&1; echo $?)" "1"

	echo "[8r] 注错: ioctl 失败分支里不调 fb_close"
	sed -i 's@^\t\tfb_close();\n@@' display/framebuffer.c
	sed -i '/FBIOGET_\*SCREENINFO failed/{n;/fb_close();/d}' display/framebuffer.c
	make >/dev/null 2>&1
	red "open 成功、ioctl 失败时的系统调用序列" "$(fb_seq)" "openat ioctl close "
	cp "$SRC/display/framebuffer.c" display/framebuffer.c
else
	skip "fb 后端失败路径判据" "没装 strace"
fi

echo "[9] 假显存后端不漏内存"
make distclean >/dev/null 2>&1
make test CFLAGS_EXTRA=-fsanitize=address LDLIBS=-fsanitize=address >/dev/null 2>&1
./build/x86/unittest/disp_test >/dev/null 2>"$W/asan.txt"
ck "ASan 报告的泄漏条数" "$(grep -c 'ERROR: LeakSanitizer' "$W/asan.txt")" "0"

echo "[9r] 注错: mem_close 里不 free"
sed -i '/^\tfree(g_mem);$/d' display/memdisp.c
make distclean >/dev/null 2>&1
make test CFLAGS_EXTRA=-fsanitize=address LDLIBS=-fsanitize=address >/dev/null 2>&1
./build/x86/unittest/disp_test >/dev/null 2>"$W/asan2.txt"
red "ASan 报告的泄漏条数" "$(grep -c 'ERROR: LeakSanitizer' "$W/asan2.txt")" "0"
ck  "漏掉的正好是一整块假显存(320 x 32)" \
    "$(sed -n 's/^Direct leak of \([0-9]*\) byte(s) in \([0-9]*\) object(s).*/\1 \2/p' "$W/asan2.txt")" \
    "10240 1"
cp "$SRC/display/memdisp.c" display/memdisp.c

echo "[10] 分层边界: 帧缓冲设备只出现在 display 层"
ck "display/ 以外提到 /dev/fb 的文件数" \
   "$(grep -rl '/dev/fb' --include='*.c' --include='*.h' . | grep -cv '^\./display/')" "0"

echo "[10r] 注错: 往 page 层塞一行含 /dev/fb0 的注释"
sed -i '1i /* 这一行故意越界引用 /dev/fb0 */' page/page_manager.c
red "display/ 以外提到 /dev/fb 的文件数" \
    "$(grep -rl '/dev/fb' --include='*.c' --include='*.h' . | grep -cv '^\./display/')" "0"
cp "$SRC/page/page_manager.c" page/page_manager.c

echo
echo "PASS=$PASS  FAIL=$FAIL  SKIP=$SKIP"
[ "$FAIL" -eq 0 ]
```

[8] 用 `/dev/null` 构造"open 成功、ioctl 必败"的中间态，strace 序列
`openat ioctl close` 证明 fb_close 在失败分支被调（[8r] 删掉后序列缺 close）。
[9] 的 ASan 判据把泄漏量化到字节数——10240 = 320×32，泄漏对象与假显存
几何对得上才算数。[10] 是文本型判据里唯一放行的一条：它数的是
**分层违规的模式**（`/dev/fb` 出现在 display/ 之外），grep 计数为 0，
配合 [10r] 注错证明判据本身活着。

## 4. check_font_input.sh

### 第 1—26 行：头部

```bash
#!/bin/bash
# 第 04/05 章的 font/input 判据。所有注错都发生在临时副本。

set -u
SRC=$(cd "$(dirname "$0")" && pwd)
PASS=0; FAIL=0; SKIP=0

ck()   { if [ "$2" = "$3" ]; then echo "  PASS  $1 = $2"; PASS=$((PASS+1));
         else echo "  FAIL  $1: got [$2] want [$3]"; FAIL=$((FAIL+1)); fi; }
red()  { if [ "$2" != "$3" ]; then echo "  PASS  注错见红: $1 变成 [$2]"; PASS=$((PASS+1));
         else echo "  FAIL  注错没红: $1 仍是 [$3]"; FAIL=$((FAIL+1)); fi; }
ok()   { echo "  PASS  $1"; PASS=$((PASS+1)); }
no()   { echo "  FAIL  $1: $2"; FAIL=$((FAIL+1)); }
skip() { echo "  SKIP  $1 ($2)"; SKIP=$((SKIP+1)); }

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
cp -r "$SRC" "$W/project"
cd "$W/project" || exit 1
rm -rf build

Q=${Q:-/mnt/e/Workspace/01_all_series_quickstart-master}
FONT=${FONT_TEST_FILE:-$Q/04_嵌入式Linux应用开发基础知识/source/10_freetype/02_freetype_show_font/simsun.ttc}
export DISP_DEV=mem
export FONT_DEV=builtin
```

工具函数比 core 多 `ok/no` 一对：处理"期望值需要计算"（advance 是否为
正的 26.6 倍数、颜色数是否超阈值）这类不成对比较。`FONT` 缺文件时 [12]
整组走 `skip`，font 的其余判据不依赖字体文件。

### 第 27—72 行：[11] font 探针组与两条注错

```bash
echo "[11] font 层: UTF-8 + provider + alpha + pitch + 四边裁剪"
make test >/dev/null 2>&1
ck "三套单层测试程序" "$(find build/x86/unittest -maxdepth 1 -type f -executable | wc -l)" "3"

probe_run() {
	DISP_MEM=64x32x32x320 DISP_MEM_DUMP="$W/probe.raw" \
		./build/x86/unittest/font_test >"$W/font.out" 2>&1
}

probe_pixels() {
	for off in 4 8 12 16 324 328 332 336; do
		od -An -j "$off" -N4 -tx4 "$W/probe.raw" | tr -d ' \n'
		printf ' '
	done
}

probe_run
ck "非法 UTF-8 报首个坏字节" "$(grep '^invalid ' "$W/font.out")" "invalid ret=-1 bad=0"
ck "builtin 缺中文时计数并画问号" \
   "$(grep '^builtin ' "$W/font.out")" \
   "builtin cp=3 missing=1 advance=1152 bbox=0,-14,18,14"
ck "负 pitch 探针的覆盖/推进/外框" \
   "$(grep '^probe ' "$W/font.out")" \
   "probe covered=6 drawn=6 clipped=0 advance=320 bbox=0,-1,4,2"
ck "左/右/上/下裁剪分别命中" \
   "$(grep '^clip ' "$W/font.out")" \
   "clip left=1/5 right=1/5 top=3/3 bottom=3/3"
ALPHA_PIXELS="00204060 00505850 00807040 00e0a020 00e0a020 00807040 00505850 00204060 "
ck "alpha=0/64/128/255 与背景逐通道混色" "$(probe_pixels)" "$ALPHA_PIXELS"
ck "文字越界没有冲掉行尾 0xAA 哨兵" \
   "$(sh unittest/count.sh "$W/probe.raw" 64 32 32 320 | sed -n 1p)" \
   "size 10240 pad_AA 2048 pad_total 2048"

echo "[11r1] 注错: 负 pitch 仍按正方向逐行"
sed -i 's/(b->rows - 1 - y) \* stride/y * stride/' font/font_manager.c
make test >/dev/null 2>&1
probe_run
red "8 个 alpha 探针的顺序" "$(probe_pixels)" "$ALPHA_PIXELS"
cp "$SRC/font/font_manager.c" font/font_manager.c

echo "[11r2] 注错: 红色通道无视 alpha"
sed -i 's/fr \* alpha + br \* (255 - alpha)/fr * 255 + br * 0/' display/disp_manager.c
make test >/dev/null 2>&1
probe_run
red "alpha 混色像素" "$(probe_pixels)" "$ALPHA_PIXELS"
cp "$SRC/display/disp_manager.c" display/disp_manager.c
```

`probe_pixels` 直接从转储偏移 4/8/12/16（第一行 4 个像素）与
324/328/332/336（`320 + 第二行 4 个像素`）取 32 位值——探针画在 (1,1)，
越过第一行的填充区正好落在这些偏移。期望序列 `00204060 00505850
00807040 00e0a020` 及其对称回程是 alpha=0/64/128/255 混色的逐字节手算值
（TechReport 04 第 3.4 节给了 alpha=64 的算式）。两条注错分别打
font_manager 的负 pitch 分支与 disp_manager 的红通道，恢复各自 cp 回源文件。

### 第 74—105 行：[12] FreeType 组

```bash
echo "[12] FreeType: UTF-8 中文 + bbox/advance + 抗锯齿"
if [ -f "$FONT" ]; then
	make test >/dev/null 2>&1
	DISP_MEM=128x64x32x576 DISP_MEM_DUMP="$W/freetype.raw" \
		FONT_TEST_FILE="$FONT" ./build/x86/unittest/font_test >"$W/freetype.out" 2>&1
	FT_LINE=$(grep '^freetype ' "$W/freetype.out")
	ck "FreeType 三码点无缺字且不裁剪" \
	   "$(printf '%s\n' "$FT_LINE" | sed -n 's/^freetype cp=\([0-9]*\) missing=\([0-9]*\).* clipped=\([0-9]*\)$/\1 \2 \3/p')" \
	   "3 0 0"
	ADV=$(printf '%s\n' "$FT_LINE" | sed -n 's/.* advance=\([0-9]*\) .*/\1/p')
	if [ "$ADV" -gt 0 ] && [ $((ADV % 64)) -eq 0 ]; then
		ok "FreeType advance 保留 26.6 单位 (advance=$ADV)"
	else
		no "FreeType advance 应是正的 26.6 值" "$ADV"
	fi
	COLORS=$(sh unittest/count.sh "$W/freetype.raw" 128 64 32 576 | sed -n 2p | wc -w)
	if [ "$COLORS" -gt 32 ]; then
		ok "抗锯齿产生 $COLORS 种像素值"
	else
		no "抗锯齿颜色种类应大于 32" "$COLORS"
	fi

	echo "[12r] 注错: 每个 glyph 的 advance 写死成 1 像素"
	sed -i 's/(int)slot->advance.x/64/' font/font_freetype.c
	make test >/dev/null 2>&1
	FONT_TEST_FILE="$FONT" ./build/x86/unittest/font_test >"$W/freetype-bad.out" 2>&1
	BAD_ADV=$(sed -n 's/^freetype .* advance=\([0-9]*\) .*/\1/p' "$W/freetype-bad.out")
	red "整行 advance" "$BAD_ADV" "$ADV"
	cp "$SRC/font/font_freetype.c" font/font_freetype.c
else
	skip "FreeType 真字体判据" "找不到 $FONT"
fi
```

advance 只断言性质（正数、64 的倍数）不断言具体值：换字体文件或字号时
判据仍成立。颜色数断言下界：抗锯齿若塌成黑白两色，`> 32` 必败。
这是"性质型判据"与计数型的混用——对会随输入变化的量验性质，
对固定几何的量验精确值。

### 第 107—159 行：[13][14] input 组

```bash
echo "[13] input 层: SYN 帧边界 + 相对/绝对坐标 + 按键"
make test >/dev/null 2>&1
INPUT_BACKEND=replay INPUT_REPLAY=unittest/input_replay.txt \
	./build/x86/unittest/input_test >"$W/input.out" 2>&1
ck "replay provider 能被 manager 选择" \
   "$(sed -n 's/^source name=\([^ ]* [^ ]*\).*/\1/p' "$W/input.out")" "text replay"
EXPECTED_INPUT="pointer x=42 y=21 dx=10 dy=5 buttons=1
pointer x=0 y=0 dx=-1000 dy=-1000 buttons=1
key code=30 value=1
pointer x=0 y=0 dx=0 dy=0 buttons=0
pointer x=63 y=0 dx=0 dy=0 buttons=1"
ck "五个 SYN_REPORT 帧逐项输出" \
   "$(grep -E '^(pointer|key) ' "$W/input.out")" "$EXPECTED_INPUT"
ck "SYN_DROPPED 与 EOF 半帧都不泄露" \
   "$(grep -Ec '^(pointer|key) ' "$W/input.out")" "5"

echo "[13r1] 注错: 去掉负坐标钳制"
sed -i '0,/if (value < 0)/s//if (value < -9999)/' input/input_manager.c
make test >/dev/null 2>&1
INPUT_BACKEND=replay INPUT_REPLAY=unittest/input_replay.txt \
	./build/x86/unittest/input_test >"$W/input-bad.out" 2>&1
red "大幅负位移后的坐标" \
    "$(grep 'dx=-1000' "$W/input-bad.out")" \
    "pointer x=0 y=0 dx=-1000 dy=-1000 buttons=1"
cp "$SRC/input/input_manager.c" input/input_manager.c

echo "[13r2] 注错: 不再等 SYN_REPORT 就提交事件"
sed -i 's/raw->type != EV_SYN || raw->code != SYN_REPORT/raw->type == EV_SYN \&\& raw->code == SYN_REPORT/' input/input_manager.c
make test >/dev/null 2>&1
INPUT_BACKEND=replay INPUT_REPLAY=unittest/input_replay.txt \
	./build/x86/unittest/input_test >"$W/input-nosync.out" 2>&1
red "应用事件个数" "$(grep -Ec '^(pointer|key) ' "$W/input-nosync.out")" "5"
cp "$SRC/input/input_manager.c" input/input_manager.c

echo "[13r3] 注错: SYN_DROPPED 后仍解析失真记录"
sed -i 's/if (g_dropping) {/if (g_dropping \&\& 0) {/' input/input_manager.c
make test >/dev/null 2>&1
INPUT_BACKEND=replay INPUT_REPLAY=unittest/input_replay.txt \
	./build/x86/unittest/input_test >"$W/input-dropped.out" 2>&1
red "应用事件个数" "$(grep -Ec '^(pointer|key) ' "$W/input-dropped.out")" "5"
cp "$SRC/input/input_manager.c" input/input_manager.c

echo "[14] input 失败路径"
INPUT_BACKEND=replay INPUT_REPLAY=unittest/input_replay_bad.txt \
	./build/x86/unittest/input_test >"$W/input-malformed.out" 2>&1
ck "畸形回放被拒绝" "$?" "2"
INPUT_BACKEND=evdev INPUT_DEV=/dev/null \
	./build/x86/unittest/input_test --probe >"$W/input-not-evdev.out" 2>&1
ck "普通文件不会冒充 evdev" "$?" "1"

echo
echo "PASS=$PASS  FAIL=$FAIL  SKIP=$SKIP"
[ "$FAIL" -eq 0 ]
```

五行期望是整段判据的心脏：每行都对应 fixture 的一帧与状态机的一个决定
（第 2 帧按钮保持、第 4 帧释放也是事件、第 5 帧 4095 缩到 63）。三条注错
分别打钳制、封帧条件、丢弃区，实测分别变出 `x=-958`、12 条事件、6 条
事件（TechReport 05 第 4.3/4.4 节）。`sed '0,/if (value < 0)/s//...'`
只替换第一处——`clamp_value` 与 `scale_abs` 里各有一个同样的条件，
注错只要打相对路径那一处。[14] 的两个退出码：2 是 `input_test` 事件
循环的 `ERR_IO`，1 是 `input_init` 失败（`/dev/null` 打开成功但 probe
判 `ERR_NOTSUP`），两个失败层级可区分。

## 5. 执行顺序

```
总入口: 固定环境 → core(52) → font_input(21) → 汇总 73/0/0
core 内部: 每组先 make 全量重建 → 跑 → ck; 注错 → 重建 → red → cp 还原
font_input 内部: make test → probe/回放跑 → ck; 三条 font 注错 + 三条 input 注错
任何一条 FAIL: 对应 suite 末行 rc=1 → 总入口 rc=1
```

## 6. 容易读错的地方

- `$?` 在管道后取的是管道最后一个命令；判据里取 rc 一律用
  `PIPESTATUS[0]` 或独立执行。
- `red` 期望"变红"：注错后期望值与实测值**必须不同**，相等说明判据假绿。
- `ck` 在 [7r2]/[7r6] 处故意接在注错后面且期望**不红**：那两条钉住的是
  冗余防御的存在理由，性质与 `red` 相反。
- 注错的 sed 都是对临时副本的 `font/...`、`display/...` 相对路径，
  工作区永不改动；还原用 `cp "$SRC/<file>"` 逐文件进行。
- `NSRC` 排除 `unittest/`，因为单测由 `make test` 单独编，不算进
  `make` 的重编数。

## 7. 消费者清单

- 根 README 的 PASS 数字（当前 73）与本篇及各 TechReport 的"结果"节，
  数字变化时三处同 commit 更新。
- `notes/03_项目/README.md` 的对照表：`check.sh` 判据条数变化指向本篇。
- TechReports/project 各章的"遇到的问题"以这里的注错输出为第一现场。
