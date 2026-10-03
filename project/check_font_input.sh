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
