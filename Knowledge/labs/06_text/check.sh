#!/bin/bash
# 第 04 章文字显示的 WSL 判据。真机 framebuffer 判据见本章笔记。

set -u
cd "$(dirname "$0")" || exit 1
Q=${Q:-/mnt/e/Workspace/01_all_series_quickstart-master}
HZK=${HZK16:-$Q/04_嵌入式Linux应用开发基础知识/source/09_show_chinese/HZK16}
FONT=${FONT_FILE:-$Q/04_嵌入式Linux应用开发基础知识/source/10_freetype/02_freetype_show_font/simsun.ttc}
PASS=0; FAIL=0; SKIP=0
ok() { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
no() { FAIL=$((FAIL+1)); printf '  FAIL  %s\n        期望 [%s]，实得 [%s]\n' "$1" "$3" "$2"; }
skip() { SKIP=$((SKIP+1)); printf '  SKIP  %s（%s）\n' "$1" "$2"; }
eq() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "$2" "$3"; fi; }
ne() { if [ "$2" != "$3" ]; then ok "$1"; else no "$1" "$2" "不等于 $3"; fi; }

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT

echo "=== 构建 ==="
gcc -Wall -Wextra -Werror -O2 -o "$W/utf8" utf8.c || exit 1
gcc -Wall -Wextra -Werror -O2 -o "$W/bitmap8" bitmap8.c || exit 1
gcc -Wall -Wextra -Werror -O2 -o "$W/hzk16" hzk16.c || exit 1
gcc -Wall -Wextra -Werror -O2 -o "$W/rawcheck" rawcheck.c || exit 1
if pkg-config --exists freetype2; then
	gcc -Wall -Wextra -Werror -O2 $(pkg-config --cflags freetype2) -o "$W/ftprobe" ftprobe.c $(pkg-config --libs freetype2) || exit 1
	gcc -Wall -Wextra -Werror -O2 $(pkg-config --cflags freetype2) -o "$W/fbtext" fbtext.c $(pkg-config --libs freetype2) || exit 1
	HAVE_FT=1
else
	HAVE_FT=0
fi
echo "  完成"
echo

echo "=== UTF-8：字节流先还原成码点 ==="
U=$("$W/utf8" 'A中🙂')
eq "A中🙂 共 8 个字节" "$(echo "$U" | sed -n 's/bytes=//p')" "8"
eq "8 字节解出 3 个码点、0 错误" "$(echo "$U" | sed -n 's/summary //p')" "codepoints=3 errors=0"
eq "三个码点依次是 U+0041/U+4E2D/U+1F642" "$(echo "$U" | sed -n 's/^\(U+[^ ]*\).*/\1/p' | tr '\n' ' ' )" "U+0041 U+4E2D U+1F642 "
U=$("$W/utf8" --hex c0 af 41 2>/dev/null || true)
eq "过长编码 C0 AF 被拒绝为两个坏字节" "$(echo "$U" | grep -c '^ERROR')" "2"
eq "坏字节之后的 A 仍能恢复" "$(echo "$U" | grep -c '^U+0041')" "1"
U=$("$W/utf8" --hex e4 ad 41 2>/dev/null || true)
eq "丢掉‘中’的中间字节，只伤两个字节" "$(echo "$U" | grep -c '^ERROR')" "2"
eq "丢字节后边界重新同步，A 仍解出" "$(echo "$U" | grep -c '^U+0041')" "1"
echo

echo "=== 8x16：编码值只负责选表项，位序负责选像素 ==="
A=$("$W/bitmap8" A --pgm "$W/A.pgm")
eq "A 有 39 个前景像素" "$(echo "$A" | sed -n 's/.*lit=\([0-9]*\).*/\1/p')" "39"
eq "A 的实际墨迹外框不是 8x16 整个格子" "$(echo "$A" | sed -n 's/.*bbox=//p')" "0,2..6,11"
eq "PGM 像素体正好 8x16=128 字节" "$(( $(wc -c < "$W/A.pgm") - 12 ))" "128"
F=$("$W/bitmap8" F)
R=$("$W/bitmap8" F --lsb-first)
eq "F 点阵前景像素数" "$(echo "$F" | sed -n 's/.*lit=\([0-9]*\).*/\1/p')" "34"
eq "反转位序不改变前景像素个数" "$(echo "$R" | sed -n 's/.*lit=\([0-9]*\).*/\1/p')" "34"
ne "注错见红：位序反了，F 的第一行从左对齐变成右对齐" "$(echo "$R" | sed -n '3p')" "$(echo "$F" | sed -n '3p')"
echo

echo "=== HZK16：GB2312 两字节算区位偏移 ==="
if [ -f "$HZK" ]; then
	C=$("$W/hzk16" "$HZK" d6 d0)
	W8=$("$W/hzk16" "$HZK" e4 b8)
	eq "GB2312 D6D0 的区位索引" "$(echo "$C" | sed -n 's/.*index=\([0-9]*\).*/\1/p')" "5029"
	eq "每字 32 字节，所以偏移是 5029x32" "$(echo "$C" | sed -n 's/.*offset=\([0-9]*\).*/\1/p')" "160928"
	eq "‘中’点阵前景像素数" "$(echo "$C" | sed -n 's/.*lit=\([0-9]*\).*/\1/p')" "52"
	eq "‘中’的墨迹外框" "$(echo "$C" | sed -n 's/.*bbox=\([^ ]*\).*/\1/p')" "1,0..14,15"
	ne "注错见红：把 UTF-8 的 E4 B8 当 GB2312，会查到另一个字形" "$(echo "$W8" | sed -n 's/.*fnv1a=//p')" "$(echo "$C" | sed -n 's/.*fnv1a=//p')"
else
	skip "HZK16 一组" "找不到 $HZK"
fi
echo

echo "=== FreeType：码点 -> glyph -> 灰度覆盖图 -> 行外框 ==="
if [ "$HAVE_FT" -eq 1 ] && [ -f "$FONT" ]; then
	T=$("$W/ftprobe" "$FONT" 48 'Ag中' "$W/line.pgm")
	eq "UTF-8 文本解出并渲染 3 个 glyph" "$(echo "$T" | sed -n 's/.*glyphs=\([0-9]*\).*/\1/p' | head -1)" "3"
	eq "宋体中 A/g/中 都有 glyph，不走 .notdef" "$(echo "$T" | sed -n 's/.*missing=\([0-9]*\).*/\1/p')" "0"
	eq "每个 glyph 的 pitch 都被实际打印" "$(echo "$T" | grep -c '^glyph .*pitch=')" "3"
	MID=$(echo "$T" | sed -n 's/.* mid=\([0-9]*\) full=.*/\1/p' | tail -1)
	if [ "$MID" -gt 0 ]; then ok "抗锯齿边缘有 $MID 个半覆盖像素"; else no "抗锯齿应产生半覆盖像素" "$MID" ">0"; fi
	BOTTOM=$(echo "$T" | sed -n 's/^glyph cp=U+0067 .* bottom=\([-0-9]*\).*/\1/p')
	if [ "$BOTTOM" -lt 0 ]; then ok "小写 g 的墨迹伸到基线下方（bottom=$BOTTOM）"; else no "g 应伸到基线下方" "$BOTTOM" "<0"; fi
	eq "生成的灰度图以 P5 开头" "$(head -c 2 "$W/line.pgm")" "P5"
else
	skip "FreeType 一组" "缺 pkg-config/freetype2 或字体 $FONT"
fi

echo "======================================"
printf '  %d PASS / %d FAIL / %d SKIP\n' "$PASS" "$FAIL" "$SKIP"
echo "======================================"
[ "$FAIL" -eq 0 ]
