#!/bin/bash
# 00_基础 第 11 篇（数据表示）的判据自动核对

cd "$(dirname "$0")" || exit 1

PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
no() { FAIL=$((FAIL+1)); printf '  FAIL  %s\n        期望 [%s]，实得 [%s]\n' "$1" "$3" "$2"; }
eq() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "$2" "$3"; fi; }
red() { if [ "$2" != "$3" ]; then ok "注错见红：$1 变成 [$2]"; else no "注错没红：$1" "$2" "不等于 $3"; fi; }
die() { printf '  FAIL  构建：%s\n' "$1"; exit 1; }

gcc -Wall -Wextra -Werror -O2 -o repr repr.c || die "正确版编译失败"
gcc -Wall -Wextra -Werror -O2 -DBUG_ENDIAN -o .repr_endian repr.c || die "字节序注错版编译失败"
gcc -Wall -Wextra -Werror -O2 -DBUG_BIT_ORDER -o .repr_bits repr.c || die "位序注错版编译失败"
gcc -Wall -Wextra -Werror -O2 -DBUG_FIXED_100 -o .repr_fixed repr.c || die "定点数注错版编译失败"

OUT=$(./repr)
eq "本机 0x12345678 的四个内存字节（x86-64 小端）" "$(echo "$OUT" | sed -n 's/native bytes: //p')" "78 56 34 12"
eq "同样两个字节按小端解释" "$(echo "$OUT" | sed -n 's/.*as LE=\(0x[0-9a-f]*\).*/\1/p')" "0x4e2d"
eq "同样两个字节按大端解释" "$(echo "$OUT" | sed -n 's/.*as BE=\(0x[0-9a-f]*\).*/\1/p')" "0x2d4e"
eq "0x62 按高位在左展开" "$(echo "$OUT" | sed -n 's/0x62 MSB-first: //p')" ".##...#."
eq "0x62 按低位在左展开" "$(echo "$OUT" | sed -n 's/0x62 LSB-first: //p')" ".#...##."
eq "26.6 中 1 像素就是 64" "$(echo "$OUT" | grep -o 'one_pixel=[0-9]*' | cut -d= -f2)" "64"
eq "10.5 像素编码成 672" "$(echo "$OUT" | grep -o 'ten_and_half=[0-9]*' | cut -d= -f2)" "672"
eq "672 向下取整是 10 像素" "$(echo "$OUT" | grep -o 'raw_672_floor=[0-9-]*' | cut -d= -f2)" "10"
eq "672 四舍五入是 11 像素" "$(echo "$OUT" | grep -o 'raw_672_round=[0-9-]*' | cut -d= -f2)" "11"
eq "负的半像素向下取整是 -1，不是 0" "$(echo "$OUT" | grep -o 'raw_-33_floor=[0-9-]*' | cut -d= -f2)" "-1"

B=$(./.repr_endian)
red "把小端读取公式写反，U+4E2D" "$(echo "$B" | sed -n 's/.*as LE=\(0x[0-9a-f]*\).*/\1/p')" "0x4e2d"
B=$(./.repr_bits)
red "把字库约定的 MSB-first 写成 LSB-first" "$(echo "$B" | sed -n 's/0x62 MSB-first: //p')" ".##...#."
B=$(./.repr_fixed)
red "把 26.6 错当成百分制，672 四舍五入" "$(echo "$B" | grep -o 'raw_672_round=[0-9-]*' | cut -d= -f2)" "11"

rm -f repr .repr_endian .repr_bits .repr_fixed
echo "======================================"
printf '  %d PASS / %d FAIL / 0 SKIP\n' "$PASS" "$FAIL"
echo "======================================"
[ "$FAIL" -eq 0 ]
