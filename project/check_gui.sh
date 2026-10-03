#!/bin/bash
# 第 08/09 章(config/ui/page/business 四层 + 两个测试项)的判据。
# 所有注错都发生在临时副本。

set -u
SRC=$(cd "$(dirname "$0")" && pwd)
PASS=0; FAIL=0; SKIP=0

ck()   { if [ "$2" = "$3" ]; then echo "  PASS  $1 = $2"; PASS=$((PASS+1));
         else echo "  FAIL  $1: got [$2] want [$3]"; FAIL=$((FAIL+1)); fi; }
red()  { if [ "$2" != "$3" ]; then echo "  PASS  注错见红: $1 变成 [$2]"; PASS=$((PASS+1));
         else echo "  FAIL  注错没红: $1 仍是 [$3]"; FAIL=$((FAIL+1)); fi; }
skip() { echo "  SKIP  $1 ($2)"; SKIP=$((SKIP+1)); }

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
cp -r "$SRC" "$W/project"
cd "$W/project" || exit 1
rm -rf build

export DISP_DEV=mem
export FONT_DEV=builtin
F=unittest/conf_fixtures

echo "[18] config 层: 四份配置的解析与默认值"
make test >/dev/null 2>&1
./build/x86/unittest/config_test "$F/full.conf" "$F/partial.conf" \
	"$F/empty.conf" /no/such/file >"$W/cfg.out" 2>&1
ck "全字段逐项读回" \
   "$(sed -n 's/^cfg full \(.*\)$/  \1/p' "$W/cfg.out" | head -1 | sed 's/^  //')" \
   "font=/usr/share/fonts/liberation/LiberationSans-Regular.ttf size=32 timeout=1500 items=3"
ck "行尾注释与带空格的命令原样保留" \
   "$(grep '^cfg full item0' "$W/cfg.out")" \
   "cfg full item0 name=mem cmd=head -3 /proc/meminfo"
ck "三个条目全部就位" "$(grep -c '^cfg full item' "$W/cfg.out")" "3"
ck "缺字段的条目命令为空而不是残留默认" "$(grep 'partial item0' "$W/cfg.out")" \
   "cfg partial item0 name=only_name cmd="
ck "只有注释的文件等于全默认" "$(grep '^cfg empty' "$W/cfg.out")" \
   "cfg empty font=(builtin) size=0 timeout=0 items=0"
ck "文件不存在走默认并带出演示条目" "$(grep '^cfg nofile font' "$W/cfg.out")" \
   "cfg nofile font=(builtin) size=0 timeout=0 items=1"

echo "[18r] 注错: key=value 的切分失效, 所有键都读不进来"
sed -i "s/\*eq = '\\\\0';/\*eq = *eq;/" config/config.c
make test >/dev/null 2>&1
./build/x86/unittest/config_test "$F/full.conf" "$F/partial.conf" \
	"$F/empty.conf" /no/such/file >"$W/cfg-bad.out" 2>&1
red "全字段逐项读回" \
    "$(sed -n 's/^cfg full \(.*\)$/  \1/p' "$W/cfg-bad.out" | head -1 | sed 's/^  //')" \
    "font=/usr/share/fonts/liberation/LiberationSans-Regular.ttf size=32 timeout=1500 items=3"
cp "$SRC/config/config.c" config/config.c

# ---------------------------------------------------------------------------
# ui 层。像素由 count.sh 从显存转储里数, 被测程序自己不统计。
# 转储几何 128x64x32x520: 行尾有 8 字节填充, 行宽算错会撞歪哨兵。
# ---------------------------------------------------------------------------

UI_DISTRIB_NORMAL="00000000:6592 00303030:1242 00909090:232 00ffffff:126"
UI_DISTRIB_HOLD="00000000:6592 00303030:618 00707070:624 00909090:232 00ffffff:126"

ui_run() {
	DISP_MEM=128x64x32x520 DISP_MEM_DUMP="$W/ui.raw" \
		./build/x86/unittest/ui_test "$@" >"$W/ui.out" 2>&1
}

echo "[19] ui 层: 按钮 + 命中 + 按下态"
make test >/dev/null 2>&1
ui_run
ck "建两颗销一颗" "$(grep 'after_destroy' "$W/ui.out")" "ui after_destroy=1 clicks=1/1"
ck "命中路径" "$(grep -E '^press=|^release_inside' "$W/ui.out" | tr '\n' ' ')" "press=1 release_inside=1 "
ck "挪出回弹与空地按下" \
   "$(grep -E '^release_outside|^release_no|^press_void' "$W/ui.out" | tr '\n' ' ')" \
   "release_outside=0 release_no=1 press_void=0 "
ck "静止态像素分布" "$(sh unittest/count.sh "$W/ui.raw" 128 64 32 520 | sed -n 2p)" \
   "$UI_DISTRIB_NORMAL"
ui_run --hold
ck "按下态退出(供转储数色)" "$(grep 'hold pressed' "$W/ui.out")" "hold pressed=1"
ck "按下态像素分布(按下底色出现)" \
   "$(sh unittest/count.sh "$W/ui.raw" 128 64 32 520 | sed -n 2p)" "$UI_DISTRIB_HOLD"
ck "行尾哨兵没被写字冲掉" \
   "$(sh unittest/count.sh "$W/ui.raw" 128 64 32 520 | sed -n 1p)" \
   "size 33280 pad_AA 512 pad_total 512"

echo "[19r] 注错: 按下底色写成静止底色, 按下态在屏幕上不可见"
sed -i 's/UI_BG_PRESSED  0x707070u/UI_BG_PRESSED  0x303030u/' ui/ui_manager.c
make test >/dev/null 2>&1
ui_run --hold
red "按下态像素分布(按下底色出现)" \
    "$(sh unittest/count.sh "$W/ui.raw" 128 64 32 520 | sed -n 2p)" "$UI_DISTRIB_HOLD"
cp "$SRC/ui/ui_manager.c" ui/ui_manager.c

echo "[20] page 层: 注册/切换/建毁平衡"
make test >/dev/null 2>&1
./build/x86/unittest/page_test 50 >"$W/page.out" 2>&1
ck "切换 100 次后回到 A, 控件数回到 1" \
   "$(grep '^page_test' "$W/page.out")" \
   "page_test creates=51/50 destroys=50/50 switches=100 final=A count=1"

echo "[20r] 注错: 切页时不销毁旧页, 旧页按钮留在链表上"
sed -i 's/g_cur->destroy();/(void)0;/' page/page_manager.c
make test >/dev/null 2>&1
./build/x86/unittest/page_test 5 >"$W/page-bad.out" 2>&1
red "切换后控件数回到 1" \
    "$(grep '^page_test' "$W/page-bad.out" | sed 's/.*switches/switches/')" \
    "switches=10 final=A count=1"
cp "$SRC/page/page_manager.c" page/page_manager.c

echo "[20r2] 同一处坏法的 ASan 对照: ui 层总清理失效 = 泄漏"
make distclean >/dev/null 2>&1
make test CFLAGS_EXTRA=-fsanitize=address LDLIBS=-fsanitize=address >/dev/null 2>&1
./build/x86/unittest/page_test 20 >/dev/null 2>"$W/page-asan.txt"
ck "正常路径无泄漏" "$(grep -c 'ERROR: LeakSanitizer' "$W/page-asan.txt")" "0"
sed -i 's/free(btn);/(void)0;/' ui/ui_manager.c
make test CFLAGS_EXTRA=-fsanitize=address LDLIBS=-fsanitize=address >/dev/null 2>&1
./build/x86/unittest/page_test 20 >/dev/null 2>"$W/page-asan-bad.txt"
red "ui 总清理失效时的泄漏报告" \
    "$(grep -c 'ERROR: LeakSanitizer' "$W/page-asan-bad.txt")" "0"
cp "$SRC/ui/ui_manager.c" ui/ui_manager.c
make distclean >/dev/null 2>&1

# ---------------------------------------------------------------------------
# business 端到端: 回放一段"点测试项 -> 点设置 -> 点返回 -> q"的脚本。
# 320x240 布局按 business_internal.h 的公式: 测试项按钮 (8,8,148,40),
# 中心 (82,28); 设置/返回按钮 (164,56,148,40), 中心 (238,76)。
# 指针从屏中心 (160,120) 出发。
# ---------------------------------------------------------------------------

E2E_DISTRIB=""
e2e_run() {
	awk 'BEGIN {
		print "0 0 2 0 -78"; print "0 0 2 1 -92"; print "0 0 0 0 0";
		print "0 0 1 272 1"; print "0 0 0 0 0";
		print "0 0 1 272 0"; print "0 0 0 0 0";
		print "0 0 2 0 156"; print "0 0 2 1 48"; print "0 0 0 0 0";
		print "0 0 1 272 1"; print "0 0 0 0 0";
		print "0 0 1 272 0"; print "0 0 0 0 0";
		print "0 0 1 272 1"; print "0 0 0 0 0";
		print "0 0 1 272 0"; print "0 0 0 0 0";
		print "0 0 1 16 1"; print "0 0 0 0 0";
	}' > "$W/e2e.replay"
	DISP_MEM=320x240x32x1280 CONFIG_FILE="$F/e2e.conf" \
		INPUT_BACKEND=replay INPUT_REPLAY="$W/e2e.replay" \
		./build/x86/product_tool >"$W/e2e.out" 2>&1
}

echo "[21] business: 输入 -> 页面 -> 控件 -> 命令 整条链"
make >/dev/null 2>&1
e2e_run
ck "端到端退出码" "$?" "0"
ck "点 mem 测试项执行了 head 命令" "$(grep -c 'item mem rc=0' "$W/e2e.out")" "1"
ck "切到设置页" "$(grep -c 'page settings created' "$W/e2e.out")" "1"
ck "两次回到主页" "$(grep -c 'page main created' "$W/e2e.out")" "2"
ck "q 键结束主循环" \
   "$(grep 'business loop end' "$W/e2e.out" | sed 's/^\[[^]]*\] [^ ]* //')" \
   "business loop end events=9"

echo "[21r] 注错: 设置按钮的回调不再切页"
sed -i 's/page_switch("settings");/(void)0;/' business/business_main_page.c
make >/dev/null 2>&1
e2e_run
red "切到设置页" "$(grep -c 'page settings created' "$W/e2e.out")" "1"
cp "$SRC/business/business_main_page.c" business/business_main_page.c

echo "[22] items: ap3216 错误路径 + serial 伪终端回显"
make test >/dev/null 2>&1
./build/x86/items/ap3216_read --bus 99 >/dev/null 2>&1
ck "没有 I2C 总线时干净报错退出" "$?" "1"
if command -v python3 >/dev/null 2>&1; then
	python3 unittest/serial_pty.py build/x86/items/serial_loop 5 \
		>"$W/serial.out" 2>&1
	ck "伪终端回显 5 帧全对" "$(tail -1 "$W/serial.out")" "serial ok=5/5"
	ck "回显程序的退出码" "$?" "0"
else
	skip "serial 回显判据" "没装 python3"
fi

echo "[22r] 注错: 帧校验和漏掉首字节, 回显核对必须变红"
sed -i 's/for (i = 0; i < n; i++)\n\t\tsum/XX/' items/serial_loop.c
sed -i '0,/for (i = 0; i < n; i++)/s//for (i = 1; i < n; i++)/' items/serial_loop.c
make test >/dev/null 2>&1
python3 unittest/serial_pty.py build/x86/items/serial_loop 5 \
	>"$W/serial-bad.out" 2>&1
red "伪终端回显 5 帧全对" "$(tail -1 "$W/serial-bad.out")" "serial ok=5/5"
cp "$SRC/items/serial_loop.c" items/serial_loop.c

echo "[23] 分层边界: 总线与线程只出现在该在的层"
ck "直接碰 /dev/i2c 的文件只在 items/" \
   "$(grep -rl '/dev/i2c' --include='*.c' --include='*.h' . | grep -cv '^\./items/')" "0"
ck "碰 termios 的文件只在 items/" \
   "$(grep -rl 'termios' --include='*.c' --include='*.h' . | grep -cv '^\./items/')" "0"
ck "起线程的文件只在 input 层" \
   "$(grep -rl 'pthread_create' --include='*.c' . | grep -cv '^\./input/')" "0"
ck "fork 进程的文件只在 business 层" \
   "$(grep -rl 'fork()' --include='*.c' . | grep -cv '^\./business/')" "0"

echo "[23r] 注错: 往 ui 层塞一行含 /dev/i2c 的注释"
sed -i '1i /* 这一行故意越界引用 /dev/i2c-1 */' ui/ui_manager.c
red "直接碰 /dev/i2c 的文件只在 items/" \
    "$(grep -rl '/dev/i2c' --include='*.c' --include='*.h' . | grep -cv '^\./items/')" "0"
cp "$SRC/ui/ui_manager.c" ui/ui_manager.c

echo
echo "PASS=$PASS  FAIL=$FAIL  SKIP=$SKIP"
[ "$FAIL" -eq 0 ]
