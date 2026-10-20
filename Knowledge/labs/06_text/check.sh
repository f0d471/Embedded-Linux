#!/bin/bash
# 教程 06 篇（文字显示）的判据自动核对。假显存判据在本机跑；真机 framebuffer 判据见教程第 7 节。

set -u
cd "$(dirname "$0")" || exit 1
DEPS=${DEPS:-$HOME/deps}
HZK=${HZK16:-$DEPS/HZK16}
FONT=${FONT_FILE:-$DEPS/simsun.ttc}
FT_TARBALL=${FT_TARBALL:-$DEPS/freetype-2.10.2.tar.xz}
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
	gcc -Wall -Wextra -Werror -O2 $(pkg-config --cflags freetype2) -o "$W/ftangle" ftangle.c $(pkg-config --libs freetype2) -lm || exit 1
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
U=$("$W/utf8" --hex ed a0 80 41 2>/dev/null || true)
eq "UTF-16 surrogate 区 ED A0 80 三个字节全被拒" "$(echo "$U" | grep -c '^ERROR')" "3"
U=$("$W/utf8" --hex f4 90 80 80 41 2>/dev/null || true)
eq "超过 U+10FFFF 的 F4 90 80 80 四个字节全被拒" "$(echo "$U" | grep -c '^ERROR')" "4"
echo

echo "=== 8x16：编码值只负责选表项，位序负责选像素 ==="
A=$("$W/bitmap8" A --pgm "$W/A.pgm")
eq "A 有 39 个前景像素" "$(echo "$A" | sed -n 's/.*lit=\([0-9]*\).*/\1/p')" "39"
eq "A 的实际墨迹外框不是 8x16 整个格子" "$(echo "$A" | sed -n 's/.*bbox=//p')" "0,2..6,11"
eq "PGM 像素体正好 8x16=128 字节" "$(( $(wc -c < "$W/A.pgm") - 12 ))" "128"
eq "PGM 文件总长=12 字节头+128 字节体" "$(wc -c < "$W/A.pgm")" "140"
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
	eq "这份 HZK16 实际 267616 字节，不是理论的 94x94x32" "$(echo "$C" | sed -n 's/.*file_size=\([0-9]*\).*/\1/p')" "267616"
	eq "‘中’的 32 字节原样摘要" "$(echo "$C" | sed -n 's/.*fnv1a=//p')" "0b4ee7e7"
	ne "注错见红：把 UTF-8 的 E4 B8 当 GB2312，会查到另一个字形" "$(echo "$W8" | sed -n 's/.*fnv1a=//p')" "$(echo "$C" | sed -n 's/.*fnv1a=//p')"
	BAD=$("$W/hzk16" "$HZK" fe fe 2>&1 || true)
	eq "注错见红：偏移超出真实文件大小的区位被拒绝" "$(echo "$BAD" | grep -c 'outside file size')" "1"
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
	eq "整行总步进 96px" "$(echo "$T" | sed -n 's/^line .*advance_px=\([0-9.]*\).*/\1/p')" "96.000"
	eq "整行墨迹宽 91px，与总步进 96px 是两回事" "$(echo "$T" | sed -n 's/^line .* width=\([0-9]*\).*/\1/p')" "91"
	eq "生成的灰度图以 P5 开头" "$(head -c 2 "$W/line.pgm")" "P5"
	G=$("$W/ftangle" "$FONT" 48 '中' 0 90 180)
	eq "不旋转时‘中’的位图是 37x45" "$(echo "$G" | sed -n 's/^angle=0 first_bitmap=\([0-9x]*\).*/\1/p')" "37x45"
	eq "旋转 90 度后宽高互换" "$(echo "$G" | sed -n 's/^angle=90 first_bitmap=\([0-9x]*\).*/\1/p')" "45x37"
	eq "旋转 90 度后步进转到 y 方向" "$(echo "$G" | sed -n 's/^angle=90 .*first_advance26_6=\([^ ]*\).*/\1/p')" "0,3072"
	eq "旋转 180 度外框移到原点左下方" "$(echo "$G" | sed -n 's/^angle=180 .*bbox=\([^ ]*\).*/\1/p')" "-43,-40..-6,5"
	eq "旋转 90 度时第二个字沿 y 方向排开，Ag 整行高 47" "$(echo "$("$W/ftangle" "$FONT" 48 'Ag' 90)" | sed -n 's/.* height=\([0-9]*\)$/\1/p')" "47"
	# 假显存：fbtext 的 mem: 模式走和板上同一条混色与打包路径，rawcheck 独立解析导出的字节
	gcc -Wall -Wextra -Werror -O2 $(pkg-config --cflags freetype2) -DBUG_NO_ALPHA -o "$W/fbtext_noalpha" fbtext.c $(pkg-config --libs freetype2) || exit 1
	gcc -Wall -Wextra -Werror -O2 $(pkg-config --cflags freetype2) -DBUG_FIXED_565 -o "$W/fbtext_565" fbtext.c $(pkg-config --libs freetype2) || exit 1
	R32="1024 600 4096 32 16 8 8 8 0 8"; R16="1024 600 2048 16 11 5 5 6 0 5"
	D=$("$W/fbtext" "mem:1024x600x32:$W/fb32.raw" "$FONT" 'Ag' 40 120 72 0xffffff --clear)
	COV=$(echo "$D" | sed -n 's/.* covered=\([0-9]*\).*/\1/p')
	eq "假显存 32bpp：Ag 两个 glyph、0 缺字" "$(echo "$D" | sed -n 's/^glyphs=\([0-9]*\) missing=\([0-9]*\).*/\1,\2/p')" "2,0"
	eq "假显存 32bpp：被覆盖的像素全部写入，0 裁剪" "$(echo "$D" | sed -n 's/.* written=\([0-9]*\) clipped=\([0-9]*\).*/\1,\2/p')" "$COV,0"
	eq "假显存 32bpp：总步进 72px（24+48）" "$(echo "$D" | sed -n 's/.*advance_px=//p')" "72.000"
	K=$("$W/rawcheck" "$W/fb32.raw" $R32)
	eq "导出的显存正好 4096x600=2457600 字节" "$(echo "$K" | sed -n 's/^bytes=\([0-9]*\).*/\1/p')" "2457600"
	eq "rawcheck 独立数出的非黑像素 = fbtext 写入数" "$(echo "$K" | sed -n 's/^nonblack=\([0-9]*\).*/\1/p')" "$COV"
	C32=$(echo "$K" | sed -n 's/.* colors=\([0-9]*\).*/\1/p')
	if [ "$C32" -gt 2 ]; then ok "抗锯齿：显存里有 $C32 种颜色，不止黑白两种"; else no "抗锯齿边缘应产生多级灰" "$C32" ">2"; fi
	eq "白字最亮的像素是 ffffff" "$(echo "$K" | sed -n 's/^brightest=//p')" "ffffff"
	KB=$("$W/fbtext_noalpha" "mem:1024x600x32:$W/bad.raw" "$FONT" 'Ag' 40 120 72 0xffffff --clear >/dev/null && "$W/rawcheck" "$W/bad.raw" $R32)
	eq "注错见红：BUG_NO_ALPHA 时非黑像素数照样对得上" "$(echo "$KB" | sed -n 's/^nonblack=\([0-9]*\).*/\1/p')" "$COV"
	eq "注错见红：BUG_NO_ALPHA 只剩 2 种颜色，颜色种类判据抓住它" "$(echo "$KB" | sed -n 's/.* colors=\([0-9]*\).*/\1/p')" "2"
	KB=$("$W/fbtext_565" "mem:1024x600x32:$W/bad.raw" "$FONT" 'Ag' 40 120 72 0xffffff --clear >/dev/null && "$W/rawcheck" "$W/bad.raw" $R32)
	eq "注错见红：32bpp 下写死 565 打包，白字变成 00ffff" "$(echo "$KB" | sed -n 's/^brightest=//p')" "00ffff"
	"$W/fbtext" "mem:1024x600x16:$W/fb16.raw" "$FONT" 'Ag' 40 120 72 0xffffff --clear >/dev/null
	K16=$("$W/rawcheck" "$W/fb16.raw" $R16)
	eq "同一程序不重编画 16bpp，最亮的像素仍是 ffffff" "$(echo "$K16" | sed -n 's/^brightest=//p')" "ffffff"
	N16=$(echo "$K16" | sed -n 's/^nonblack=\([0-9]*\).*/\1/p')
	if [ "$N16" -lt "$COV" ]; then ok "565 量化：16bpp 非黑像素 $N16 < $COV，极低覆盖率被量化成 0"; else no "16bpp 应有极低覆盖率被量化为 0" "$N16" "<$COV"; fi
	C16=$(echo "$K16" | sed -n 's/.* colors=\([0-9]*\).*/\1/p')
	if [ "$C16" -lt "$C32" ]; then ok "565 量化：16bpp 颜色种类 $C16 < 32bpp 的 $C32"; else no "16bpp 颜色种类应少于 32bpp" "$C16" "<$C32"; fi
	D=$("$W/fbtext" "mem:1024x600x32:$W/clip.raw" "$FONT" 'Ag' 1000 120 72 0xffffff --clear)
	CL=$(echo "$D" | sed -n 's/.* covered=\([0-9]*\) mid=[0-9]* written=\([0-9]*\) clipped=\([0-9]*\).*/\1 \2 \3/p')
	set -- $CL
	if [ "$3" -gt 0 ] && [ $(( $2 + $3 )) -eq "$1" ]; then ok "x=1000 时右边被裁掉 $3 个，写入+裁剪=覆盖"; else no "越界像素应被裁剪且计数守恒" "$CL" "written+clipped=covered 且 clipped>0"; fi
	"$W/fbtext" "mem:1024x600x32:$W/clip.raw" "$FONT" $'A\xe4\xadB' 40 120 72 0xffffff >/dev/null 2>&1
	eq "坏 UTF-8 不画、退出码 1" "$?" "1"
else
	skip "FreeType 一组" "缺 pkg-config/freetype2 或字体 $FONT"
fi
echo

echo "=== 交叉构建 FreeType：configure 认出 ARM，产物进 staging ==="
if [ -f "$FT_TARBALL" ] && command -v arm-linux-gnueabihf-gcc >/dev/null 2>&1; then
	FB=$W/ftarm
	mkdir -p "$FB/src" "$FB/build" "$FB/stage"
	tar -xJf "$FT_TARBALL" -C "$FB/src" || exit 1
	( cd "$FB/build" && ../src/freetype-2.10.2/configure \
		--build=x86_64-pc-linux-gnu --host=arm-linux-gnueabihf --prefix=/usr \
		--without-zlib --without-bzip2 --without-png \
		--without-harfbuzz --without-brotli > conf.log 2>&1 ) || exit 1
	eq "configure 认出 host 是 ARM" "$(grep -c 'checking host system type... arm-unknown-linux-gnueabihf' "$FB/build/conf.log")" "1"
	eq "configure 确认这是交叉编译" "$(grep -c 'checking whether we are cross compiling... yes' "$FB/build/conf.log")" "1"
	eq "configure 找到的是交叉编译器" "$(grep -c 'checking for arm-linux-gnueabihf-gcc... arm-linux-gnueabihf-gcc' "$FB/build/conf.log")" "1"
	( cd "$FB/build" && make -j2 > make.log 2>&1 && make DESTDIR="$FB/stage" install > install.log 2>&1 ) || exit 1
	eq "静态库 libfreetype.a 已生成" "$([ -f "$FB/build/.libs/libfreetype.a" ] && echo yes || echo no)" "yes"
	eq "共享库 libfreetype.so.6.17.2 是 ARM 机器码" "$(readelf -h "$FB/stage/usr/lib/libfreetype.so.6.17.2" | sed -n 's/^ *Machine: *//p')" "ARM"
	eq "头文件装进 staging 而不是本机 /usr" "$([ -f "$FB/stage/usr/include/freetype2/ft2build.h" ] && echo yes || echo no)" "yes"
	arm-linux-gnueabihf-gcc -static -Wall -Wextra -Werror -O2 \
		-I"$FB/stage/usr/include/freetype2" -o "$W/fbtext-arm" fbtext.c \
		"$FB/build/.libs/libfreetype.a" -lm || exit 1
	eq "fbtext-arm 是 ARM 静态链接程序" "$(file "$W/fbtext-arm" | grep -c 'ARM.*statically linked')" "1"
	eq "fbtext-arm 没有动态段，板上不需要再找 libfreetype.so.6" "$(readelf -d "$W/fbtext-arm" 2>&1 | grep -c 'no dynamic section')" "1"
else
	skip "FreeType 交叉构建一组" "缺 $FT_TARBALL 或 arm-linux-gnueabihf-gcc"
fi

echo "======================================"
printf '  %d PASS / %d FAIL / %d SKIP\n' "$PASS" "$FAIL" "$SKIP"
echo "======================================"
[ "$FAIL" -eq 0 ]
