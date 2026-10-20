#!/bin/bash
# 第 05 章 framebuffer 的 WSL 判据。从源码重建一切再逐条核对。
# 板上判据（fbinfo 三笔对账、画线回读计数、rwbench/fillbench、HDMI 换模式）
# 见教程第 4、5 节；板子不在线时沿用 2026-09-14 归档，不在此脚本内。
# 设备节点实验需要 root：wsl -u root bash check.sh；普通用户那一条记 SKIP。

set -u
cd "$(dirname "$0")" || exit 1
PASS=0; FAIL=0; SKIP=0
ok()   { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
no()   { FAIL=$((FAIL+1)); printf '  FAIL  %s\n        期望 [%s]，实得 [%s]\n' "$1" "$3" "$2"; }
skip() { SKIP=$((SKIP+1)); printf '  SKIP  %s（%s）\n' "$1" "$2"; }
eq()   { if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "$2" "$3"; fi; }

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
XC=arm-linux-gnueabihf-gcc

echo "=== 构建（全部从源码重建） ==="
gcc -Wall -Wextra -Werror -O2 -o "$W/fakefb"        fakefb.c         || exit 1
gcc -Wall -Wextra -Werror -O2 -DBUG_ROW_NO_PW -o "$W/fakefb_brow" fakefb.c || exit 1
gcc -Wall -Wextra -Werror -O2 -DBUG_565_SWAP  -o "$W/fakefb_bswap" fakefb.c || exit 1
gcc -Wall -Wextra -Werror -O2 -o "$W/fbinfo"        fbinfo.c         || exit 1
gcc -Wall -Wextra -Werror -O2 -o "$W/show_pixel"    show_pixel.c     || exit 1
gcc -Wall -Wextra -Werror -O2 -o "$W/fbopen"        probe/fbopen.c   || exit 1
gcc -Wall -Wextra -Werror -O2 -o "$W/oob"           probe/oob.c      || exit 1
gcc -Wall -Wextra -Werror -O2 -o "$W/rgb565"        probe/rgb565.c   || exit 1
gcc -Wall -Werror -c -o "$W/fbabi_x86.o" probe/fbabi.c               || exit 1
$XC -static -O2 -Wall -Wextra -Werror -o "$W/fbinfo_arm"        fbinfo.c       || exit 1
$XC -static -O2 -Wall -Wextra -Werror -o "$W/show_pixel_arm"    show_pixel.c   || exit 1
$XC -static -O2 -Wall -Wextra -Werror -o "$W/oob_arm"           probe/oob.c    || exit 1
$XC -static -O2 -Wall -Wextra -Werror -o "$W/bars_arm"          probe/bars.c   || exit 1
$XC -static -O2 -Wall -Wextra -Werror -o "$W/rwbench_arm"       probe/rwbench.c  || exit 1
$XC -static -O2 -Wall -Wextra -Werror -o "$W/fillbench_arm"     probe/fillbench.c || exit 1
$XC -static -c -o "$W/fbabi_arm.o" probe/fbabi.c                           || exit 1
ok "本机与 ARM(-static) 全部产物从零构建成功"

echo "=== 1.2 设备节点与 errno ==="
echo hello > "$W/data.txt"
if [ "$(id -u)" = 0 ]; then
	ND="$HOME/fblab-check"; mkdir -p "$ND"   # /tmp 是 nodev 的 tmpfs,节点要建在根文件系统上
	rm -f "$ND/fb_fake"
	mknod "$ND/fb_fake" c 29 0
	R=$("$W/fbopen" "$ND/fb_fake")
	eq "mknod c 29 0 的节点 open 报 ENODEV(19)" \
	   "$(echo "$R" | grep -o 'errno=19 No such device')" "errno=19 No such device"
	rm -f "$ND/fb_fake"; rmdir "$ND" 2>/dev/null
else
	skip "mknod 造节点 open 报 ENODEV" "要 root：wsl -u root bash check.sh"
fi
R=$("$W/fbopen" "$W/data.txt")
eq "对普通文件 ioctl 报 ENOTTY(25)" \
   "$(echo "$R" | grep -o 'errno=25 Inappropriate ioctl for device')" \
   "errno=25 Inappropriate ioctl for device"
set +e
R=$("$W/fbinfo" /dev/null 2>&1); C=$?
set -e
eq "fbinfo 对 /dev/null ioctl 失败并以 1 退出" "$C" "1"
eq "fbinfo 报错文字是 ENOTTY" "$(echo "$R" | grep -c 'Inappropriate ioctl')" "1"
set +e
R=$("$W/show_pixel" /dev/null 2>&1); C=$?
set -e
eq "show_pixel 对 /dev/null 以 1 退出" "$C" "1"
eq "show_pixel 报 can't get var" "$(echo "$R" | grep -c "can't get var")" "1"

echo "=== 2.2 假显存：坐标拍扁与字节序 ==="
"$W/fakefb" "$W/fb.raw" 1024 600 32 4096 > "$W/fakefb.log"
eq "假显存大小 = 1024x600x4 = 2457600 字节" "$(wc -c < "$W/fb.raw")" "2457600"
eq "红 100 白 614300" \
   "$(od -An -v -tx4 -w4 "$W/fb.raw" | grep -c 00ff0000)/$(od -An -v -tx4 -w4 "$W/fb.raw" | grep -c ffffffff)" \
   "100/614300"
N=$(od -An -v -tx4 -w4 "$W/fb.raw" | grep -n -m1 00ff0000 | cut -d: -f1)
OFF=$(( (N - 1) * 4 ))
eq "第一个红像素偏移 = 300*4096+512*4 = 1230848" "$OFF" "1230848"
eq "该偏移换算回坐标是 (512,300)" "$((OFF / 4096))/$(( (OFF % 4096) / 4 ))" "300/512"
eq "该像素 4 字节按序是 00 00 ff 00（小端 B G R x）" \
   "$(od -An -tx1 -j "$OFF" -N 4 "$W/fb.raw" | tr -s ' ' | sed 's/^ //;s/ $//')" "00 00 ff 00"

"$W/fakefb_brow" "$W/fbb.raw" 1024 600 32 4096 > /dev/null
N=$(od -An -v -tx4 -w4 "$W/fbb.raw" | grep -n -m1 00ff0000 | cut -d: -f1)
OFFB=$(( (N - 1) * 4 ))
eq "注错见红：行起点忘乘像素宽度，红点仍是 100 个" \
   "$(od -An -v -tx4 -w4 "$W/fbb.raw" | grep -c 00ff0000)" "100"
eq "注错见红：但位置错了，偏移 309248 落在第 75 行" "$OFFB/$((OFFB / 4096))" "309248/75"

echo "=== 2.3 行尾有填充时 line_length 与 xres*bpp/8 分叉 ==="
"$W/fakefb" "$W/pad_fix.raw"  1024 600 32 4104 fix  vline > /dev/null
"$W/fakefb" "$W/pad_xres.raw" 1024 600 32 4104 xres vline > /dev/null
ana() { od -An -v -tx4 -w4 "$1" | awk '
	/00ff0000/ { n++; off=(NR-1)*4; y=int(off/4104); x=int((off%4104)/4); xs[x]=1;
	             if (y==100) x100=x }
	END { printf "%d %d %d", n, length(xs), x100 }'; }
set -- $(ana "$W/pad_fix.raw")
eq "按 line_length 定位：600 个红点全在同一列" "$1/$2" "600/1"
set -- $(ana "$W/pad_xres.raw")
eq "按 xres*4 定位：600 个红点散到 513 列" "$1/$2" "600/513"
eq "按 xres*4 定位：第 100 行偏到 x=312" "$3" "312"

echo "=== 2.4 越界 ==="
R=$("$W/oob" "$W/oob.raw" wrapx)
eq "x 越右界一点，落在下一行行首 (0,101)" \
   "$(echo "$R" | grep -o '实际落在 (0,101)')" "实际落在 (0,101)"
set +e
bash -c '"$0" "$1" beyondy' "$W/oob" "$W/oob.raw" > /dev/null 2>&1
C=$?
set -e
eq "y 越出映射区：SIGSEGV，退出码 139" "$C" "139"

echo "=== 3 颜色：位段与压色 ==="
R=$("$W/rgb565")
eq "888 共 16777216 色，压成 565 剩 65536 色" \
   "$(echo "$R" | sed -n 's/.*压成 565 后剩 \([0-9]*\) 种.*/\1/p')" "65536"
eq "纯白补 0 读回是 0xF8FCF8（偏灰）" \
   "$(echo "$R" | awk '/0xFFFFFF/{print $3}')" "0xF8FCF8"
for pair in "FF0000 f800" "00FF00 07e0" "0000FF 001f"; do
	set -- $pair
	"$W/fakefb" "$W/f16_$1.raw" 1024 600 16 2048 fix hline "$1" > /dev/null
	GOT=$(od -An -v -tx2 -w2 "$W/f16_$1.raw" | awk '{c[$1]++} END{for(k in c) if(k!="ffff") printf "%s/%d", k, c[k]}')
	eq "16bpp 按位段拼 $1" "$GOT" "$2/1024"
done
"$W/fakefb_bswap" "$W/f16s.raw" 1024 600 16 2048 fix hline 00FF00 > /dev/null
GOT=$(od -An -v -tx2 -w2 "$W/f16s.raw" | awk '{c[$1]++} END{for(k in c) if(k!="ffff") printf "%s", k}')
eq "注错见红：红绿位数写反，纯绿变成 03e0" "$GOT" "03e0"
"$W/fakefb_bswap" "$W/f16s2.raw" 1024 600 16 2048 fix hline FF0000 > /dev/null
GOT=$(od -An -v -tx2 -w2 "$W/f16s2.raw" | awk '{c[$1]++} END{for(k in c) if(k!="ffff") printf "%s", k}')
eq "同一注错对纯红恰好隐身（仍是 f800）" "$GOT" "f800"

echo "=== 1.3 延伸 A：两个平台的结构体布局 ==="
sym() { nm -S "$1" | awk -v s="$2" '$4==s {print $2}' | sed 's/^0*//'; }
eq "x86-64: sizeof(var)=0xa0 sizeof(fix)=0x50" \
   "$(sym "$W/fbabi_x86.o" var_size)/$(sym "$W/fbabi_x86.o" fix_size)" "a0/50"
eq "x86-64: smem_len 偏移 0x18，line_length 偏移 0x30" \
   "$(sym "$W/fbabi_x86.o" fix_smem_len_off)/$(sym "$W/fbabi_x86.o" fix_line_length_off)" "18/30"
eq "ARM: sizeof(var)=0xa0 sizeof(fix)=0x44" \
   "$(sym "$W/fbabi_arm.o" var_size)/$(sym "$W/fbabi_arm.o" fix_size)" "a0/44"
eq "ARM: smem_len 偏移 0x14，line_length 偏移 0x2c" \
   "$(sym "$W/fbabi_arm.o" fix_smem_len_off)/$(sym "$W/fbabi_arm.o" fix_line_length_off)" "14/2c"
eq "两平台 bpp 偏移都是 0x18（var 里全是 __u32）" \
   "$(sym "$W/fbabi_x86.o" var_bpp_off)/$(sym "$W/fbabi_arm.o" var_bpp_off)" "18/18"

echo "=== 4.5 截屏链路：raw 转 PNG ==="
python3 probe/raw2png.py "$W/fb.raw" 1024 600 4096 "$W/fb.png" > "$W/png.log"
eq "32bpp raw 转 PNG 成功" "$(grep -c '1024x600' "$W/png.log")" "1"
eq "产物是 PNG（魔数 89 50 4e 47）" \
   "$(head -c 4 "$W/fb.png" | od -An -tx1 | tr -s ' ' | sed 's/^ //;s/ $//')" "89 50 4e 47"
python3 probe/raw2png.py "$W/f16_FF0000.raw" 1024 600 2048 "$W/f16.png" 16 > /dev/null
eq "16bpp raw 转 PNG 成功" \
   "$(head -c 4 "$W/f16.png" | od -An -tx1 | tr -s ' ' | sed 's/^ //;s/ $//')" "89 50 4e 47"

echo "=== 上板产物（电脑上只验身份，运行见教程第 4、5 节） ==="
F=$(file "$W/show_pixel_arm")
eq "show_pixel_arm 是 ARM 静态链接" \
   "$(echo "$F" | grep -c 'ARM.*statically linked')" "1"
F=$(file "$W/fbinfo_arm")
eq "fbinfo_arm 是 ARM 静态链接" \
   "$(echo "$F" | grep -c 'ARM.*statically linked')" "1"

echo "======================================"
printf '  %d PASS / %d FAIL / %d SKIP\n' "$PASS" "$FAIL" "$SKIP"
echo "======================================"
[ "$FAIL" -eq 0 ]
