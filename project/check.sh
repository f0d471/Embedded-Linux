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
