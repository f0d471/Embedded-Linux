#!/bin/sh
#
# 独立计数脚本, 和 count.py 做同一件事, 输出格式也一样, 区别是只用
# od + awk, 板子上没有 python 也能跑。
#
#   用法: sh count.sh 转储文件 宽 高 位深 行宽
#
# 它按自己的理解算地址, 和被测的 disp_manager.c 不共享任何代码。
# 流式处理, 不把整块显存读进数组, 所以一屏 2.4 MiB 在板上也跑得动。

set -u

f=$1; w=$2; h=$3; bpp=$4; ll=$5
B=$((bpp / 8))

# 要抽查的坐标, 和 count.py 里的一样
qs="1,1 4,3 5,1 6,1 11,1 $((w-1)),$((h-1)) $((w-1)),5 $((w-2)),6 $((w-3)),5 0,0"

out=$(od -An -v -tu1 "$f" | awk -v w="$w" -v h="$h" -v B="$B" -v ll="$ll" -v qs="$qs" '
BEGIN {
	idx = 0; pad = 0; cur = 0; mul = 1;
	n = split(qs, q, " ");
	for (i = 1; i <= n; i++) {
		split(q[i], c, ",");
		want[c[1] "," c[2]] = 1;
	}
	fmt = "%0" (B * 2) "x";
}
{
	for (i = 1; i <= NF; i++) {
		y = int(idx / ll);
		off = idx % ll;
		if (y < h) {
			if (off < w * B) {
				k = off % B;
				if (k == 0) { cur = 0; mul = 1; }
				cur = cur + $i * mul;
				mul = mul * 256;
				if (k == B - 1) {
					x = int(off / B);
					key = sprintf(fmt, cur);
					cnt[key]++;
					if ((x "," y) in want)
						at[x "," y] = key;
				}
			} else if ($i == 170) {
				pad++;
			}
		}
		idx++;
	}
}
END {
	print "P", pad;
	for (k in cnt)
		print "C", k, cnt[k];
	for (k in at)
		print "A", k, at[k];
}')

pad=$(printf '%s\n' "$out" | awk '$1 == "P" { print $2 }')
size=$(wc -c < "$f" | tr -d ' ')

printf 'size %s pad_AA %s pad_total %s\n' "$size" "$pad" "$(( (ll - w * B) * h ))"
printf '%s\n' "$out" | awk '$1 == "C" { print $2 ":" $3 }' | sort | tr '\n' ' ' | sed 's/ $//'
printf '\n'

printf 'at'
for q in $qs; do
	v=$(printf '%s\n' "$out" | awk -v k="$q" '$1 == "A" && $2 == k { print $3 }')
	printf ' (%s)=%s' "$q" "$v"
done
printf '\n'
