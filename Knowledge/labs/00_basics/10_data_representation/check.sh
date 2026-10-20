#!/bin/bash
# 00_basics 第 13 篇（数据表示：字节序、位序与定点数）的判据自动核对

set -u
cd "$(dirname "$0")" || exit 1
CROSS_PREFIX=${CROSS_PREFIX:-arm-linux-gnueabihf-}

PASS=0; FAIL=0; SKIP=0
ok() { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
no() { FAIL=$((FAIL+1)); printf '  FAIL  %s\n        期望 [%s]，实得 [%s]\n' "$1" "$3" "$2"; }
skip() { SKIP=$((SKIP+1)); printf '  SKIP  %s（%s）\n' "$1" "$2"; }
eq() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "$2" "$3"; fi; }
red() { if [ "$2" != "$3" ]; then ok "注错见红：$1 变成 [$2]"; else no "注错没红：$1" "$2" "不等于 $3"; fi; }
die() { printf '  FAIL  构建：%s\n' "$1"; exit 1; }

CFLAGS="-Wall -Wextra -Werror -O2"
gcc $CFLAGS -o repr repr.c || die "正确版编译失败"
gcc $CFLAGS -DBUG_ENDIAN -o .repr_endian repr.c || die "字节序注错版编译失败"
gcc $CFLAGS -DBUG_BIT_ORDER -o .repr_bits repr.c || die "位序注错版编译失败"
gcc $CFLAGS -DBUG_FIXED_100 -o .repr_fixed repr.c || die "定点尺度注错版编译失败"
gcc $CFLAGS -DBUG_TRUNC_DIV -o .repr_trunc repr.c || die "负数取整注错版编译失败"

OUT=$(./repr)

echo "=== 字节序：内存里只有字节 ==="
eq "0x12345678 的内存字节（x86-64 小端）" "$(echo "$OUT" | sed -n 's/native bytes: //p')" "78 56 34 12"
eq "xxd 实看 mem.bin 的四个字节" "$(xxd -p mem.bin)" "78563412"
eq "2d 4e 按小端解释" "$(echo "$OUT" | sed -n 's/.*as LE=\(0x[0-9a-f]*\).*/\1/p')" "0x4e2d"
eq "2d 4e 按大端解释" "$(echo "$OUT" | sed -n 's/.*as BE=\(0x[0-9a-f]*\).*/\1/p')" "0x2d4e"

echo "=== 编码文件里的字节序（iconv 实转） ==="
if command -v iconv >/dev/null 2>&1; then
	eq "UTF-16LE 的 A 中" "$(printf 'A中' | iconv -f UTF-8 -t UTF-16LE | xxd -p)" "41002d4e"
	eq "UTF-16BE 的 A 中" "$(printf 'A中' | iconv -f UTF-8 -t UTF-16BE | xxd -p)" "00414e2d"
	eq "UTF-16 文件开头带 BOM fffe" "$(printf 'A中' | iconv -f UTF-8 -t UTF-16 | xxd -p | cut -c1-4)" "fffe"
	eq "UTF-8 的中只有 e4b8ad 一种排法" "$(printf '中' | xxd -p)" "e4b8ad"
else
	skip "iconv 编码一组" "没有 iconv"
fi

echo "=== 两个编译器眼里的字节序与 char ==="
if command -v "${CROSS_PREFIX}gcc" >/dev/null 2>&1; then
	eq "ARM 也是小端（预定义宏）" "$("${CROSS_PREFIX}gcc" -dM -E - </dev/null | sed -n 's/#define __BYTE_ORDER__ //p')" "__ORDER_LITTLE_ENDIAN__"
	eq "ARM 上 char 默认无符号" "$("${CROSS_PREFIX}gcc" -dM -E - </dev/null | grep -c '__CHAR_UNSIGNED__')" "1"
	eq "x86-64 上 char 默认有符号" "$(gcc -dM -E - </dev/null | grep -c '__CHAR_UNSIGNED__')" "0"
else
	skip "ARM 宏对照一组" "没装 ${CROSS_PREFIX}gcc"
fi

echo "=== 位序：点阵字模的约定 ==="
eq "0x62 高位在左" "$(echo "$OUT" | sed -n 's/0x62 MSB-first: //p')" ".##...#."
eq "0x62 低位在左" "$(echo "$OUT" | sed -n 's/0x62 LSB-first: //p')" ".#...##."
eq "A 的第 5 行 0x6c 逐位展开" "$(echo "$OUT" | sed -n 's/^0x6c //p')" ".##.##.."

echo "=== 补码 ==="
eq "-1 的四个字节" "$(echo "$OUT" | sed -n 's/-1  bytes: //p')" "ff ff ff ff"
eq "-33 的四个字节" "$(echo "$OUT" | sed -n 's/-33 bytes: //p')" "df ff ff ff"
eq "同一字节 0xd6 按 int8 读是 -42" "$(echo "$OUT" | sed -n 's/(int8_t)0xd6=\([-0-9]*\) .*/\1/p')" "-42"
eq "负数右移是算术右移" "$(echo "$OUT" | grep -o -- '-33>>6=[-0-9]*' | cut -d= -f2)" "-1"
eq "uint8 的 255+1 绕回 0" "$(echo "$OUT" | grep -o 'u8:255+1=[0-9]*' | cut -d= -f2)" "0"

echo "=== 26.6 定点数 ==="
eq "1 像素存成 64" "$(echo "$OUT" | grep -o 'one_pixel=[0-9]*' | cut -d= -f2)" "64"
eq "10.5 像素存成 672" "$(echo "$OUT" | grep -o 'ten_and_half=[0-9]*' | cut -d= -f2)" "672"
eq "672 向下取整是 10" "$(echo "$OUT" | grep -o 'raw_672_floor=[0-9-]*' | cut -d= -f2)" "10"
eq "672 四舍五入是 11" "$(echo "$OUT" | grep -o 'raw_672_round=[0-9-]*' | cut -d= -f2)" "11"
eq "-33 向下取整是 -1，不是 0" "$(echo "$OUT" | grep -o 'raw_-33_floor=[0-9-]*' | cut -d= -f2)" "-1"
eq "真实 advance 1536 还原成 24 像素" "$(echo "$OUT" | grep -o '1536>>6=[0-9]*' | cut -d= -f2)" "24"
eq "整行 advance 6144 还原成 96 像素" "$(echo "$OUT" | grep -o '6144>>6=[0-9]*' | cut -d= -f2)" "96"

echo "=== 注错见红 ==="
B=$(./.repr_endian)
red "小端公式两项权重写反，U+4E2D" "$(echo "$B" | sed -n 's/.*as LE=\(0x[0-9a-f]*\).*/\1/p')" "0x4e2d"
B=$(./.repr_bits)
red "位序从 bit0 开始画，0x62" "$(echo "$B" | sed -n 's/0x62 MSB-first: //p')" ".##...#."
B=$(./.repr_fixed)
red "把 26.6 错当百分制，672 四舍五入" "$(echo "$B" | grep -o 'raw_672_round=[0-9-]*' | cut -d= -f2)" "11"
B=$(./.repr_trunc)
red "负数向下取整错写成 C 除法，-33" "$(echo "$B" | grep -o 'raw_-33_floor=[0-9-]*' | cut -d= -f2)" "-1"

rm -f repr .repr_endian .repr_bits .repr_fixed .repr_trunc mem.bin
echo "======================================"
printf '  %d PASS / %d FAIL / %d SKIP\n' "$PASS" "$FAIL" "$SKIP"
echo "======================================"
[ "$FAIL" -eq 0 ]
