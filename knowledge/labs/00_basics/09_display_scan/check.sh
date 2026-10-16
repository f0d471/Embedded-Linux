#!/bin/bash
# 00_基础 第 10 篇（显示原理）的判据自动核对
#
# 用法：bash check.sh
# 普通用户即可，大约 10 秒。
#
# EDID 那一组要显示器的 EDID 原始数据。WSL 里拿不到显示器，但 Windows 把它存在注册表里，
# 脚本通过 powershell.exe 去取。默认找型号 SAC2563（SANC N50PRO V+，也就是插在板子上的
# 那台），换了显示器用 EDID_MODEL=<型号> bash check.sh；取不到就 SKIP 这一组。

cd "$(dirname "$0")" || exit 1
LAB=${LAB:-$HOME/displab}
MODEL=${EDID_MODEL:-SAC2563}

PASS=0; FAIL=0; SKIP=0
ok()   { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
no()   { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -n "$2" ] && printf '        %s\n' "$2"; }
skip() { SKIP=$((SKIP+1)); printf '  SKIP  %s\n' "$1"; }
eq()   { if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "期望 [$3]，实得 [$2]"; fi; }

die() {
	FAIL=$((FAIL+1))
	printf '  FAIL  构建：%s\n\n  %d PASS / %d FAIL / %d SKIP（构建没过）\n' "$1" "$PASS" "$FAIL" "$SKIP"
	exit 1
}

echo "=== 构建 ==="
gcc -Wall -Wextra -O2 -o scan scan.c                     || die "scan.c 编译不过"
gcc -Wall -Wextra -O2 -DBUG_NO_BLANK -o .scan_bug scan.c || die "scan.c 注错版编译不过"
gcc -Wall -Wextra -O2 -o edid edid.c                     || die "edid.c 编译不过"
mkdir -p "$LAB" || die "建不了 $LAB"
echo "  完成"
echo

hz()       { echo "$1" | grep -oE '帧率 [0-9.]+ Hz' | grep -oE '[0-9.]+'; }
khz()      { echo "$1" | grep -oE '行频 [0-9.]+ kHz' | grep -oE '[0-9.]+'; }
perframe() { echo "$1" | grep -oE '每帧 [0-9]+ 次' | grep -oE '[0-9]+'; }
shape()    { echo "$1" | grep -oE '一行 [0-9]+ 拍，一帧 [0-9]+ 行'; }

echo "=== 10 篇 二  一帧里不只有画面 ==="
G=$(./scan draw 8 4 0 2 1 1 1 2 1 | grep -E '^[#.HV]+$')
eq "一帧 7 行：4 行画面 + 1 行空白 + 1 行场同步 + 1 行空白" "$(echo "$G" | wc -l)" "7"
eq "每行 13 格：8 格画面 + 1 格空白 + 2 格行同步 + 2 格空白" "$(echo "$G" | awk '{print length($0)}' | sort -u)" "13"
eq "读显存的 # 一共 32 个 = 8 x 4" "$(echo "$G" | tr -cd '#' | wc -c)" "32"
eq "场同步只有 1 行，而且整行都是 V" "$(echo "$G" | grep -c '^V*$')" "1"
eq "其余 6 行每行都有 2 格行同步 H" "$(echo "$G" | grep -v '^V*$' | awk '{print gsub(/H/, "H")}' | sort -u)" "2"
echo

echo "=== 10 篇 三  帧率由像素时钟和总格数算出来 ==="
B=$(./scan count 1024 600 20000 140 160 20 12 20 3 10)
eq "板子没插显示器时的时序：帧率等于 fbset 报的 V: 58.586 Hz" "$(hz "$B")" "58.586"
eq "板子没插显示器时的时序：行频等于 fbset 报的 H: 37.202 kHz" "$(khz "$B")" "37.202"
eq "每个整帧读显存 614400 次 = 1024 x 600" "$(perframe "$B")" "614400"
H=$(./scan count 1280 720 13468 220 110 20 5 40 5 10)
eq "插上显示器后的时序：帧率等于 fbset 报的 V: 60.000 Hz" "$(hz "$H")" "60.000"
eq "插上显示器后的时序：行频等于 fbset 报的 H: 45.000 kHz" "$(khz "$H")" "45.000"
eq "一行 1650 拍、一帧 750 行，和内核 drm_edid.c 里 CEA 第 4 号模式一致" "$(shape "$H")" "一行 1650 拍，一帧 750 行"
F=$(./scan count 1280 720 13468 220 440 20 5 40 5 10)
eq "像素时钟不变、行尾空白 110 改成 440：50.000 Hz（CEA 第 19 号模式）" "$(hz "$F")" "50.000"
eq "50Hz 那一版一行 1980 拍，和 drm_edid.c 一致" "$(shape "$F")" "一行 1980 拍，一帧 750 行"
X=$(./.scan_bug count 1024 600 20000 140 160 20 12 20 3 10)
if [ "$(hz "$X")" != "58.586" ]; then
	ok "注错见红：控制器不走空白和同步，帧率算成 $(hz "$X") Hz，和 fbset 的 58.586 对不上"
else
	no "不走空白和同步，帧率不应还是 58.586"
fi
eq "注错见红：不走同步，行同步脉冲一个都没有" "$(echo "$X" | grep -oE '行同步脉冲 [0-9]+' | grep -oE '[0-9]+')" "0"
echo

echo "=== 10 篇 五  EDID：显示器自报的模式表 ==="
EDID="$LAB/edid.bin"
rm -f "$EDID"
if command -v powershell.exe >/dev/null 2>&1 && command -v iconv >/dev/null 2>&1; then
	PS='$k = Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Enum\DISPLAY\'"$MODEL"'" -ErrorAction SilentlyContinue | Select-Object -First 1; if ($k) { $e = (Get-ItemProperty -LiteralPath ($k.PSPath + "\Device Parameters") -Name EDID).EDID; [Convert]::ToBase64String($e) }'
	ENC=$(printf '%s' "$PS" | iconv -f utf-8 -t utf-16le | base64 -w0)
	powershell.exe -NoProfile -NonInteractive -EncodedCommand "$ENC" 2>/dev/null | tr -d '\r' | base64 -d > "$EDID" 2>/dev/null
fi
if [ ! -s "$EDID" ]; then
	skip "EDID 一组（没从注册表取到型号 $MODEL 的 EDID）"
else
	E=$(./edid "$EDID")
	eq "两个块的校验和都正确" "$(echo "$E" | grep -c '校验和.*（正确）')" "2"
	eq "厂商 SAC、产品号 0x2563" "$(echo "$E" | grep -oE '厂商 [A-Z]{3}  产品号 0x[0-9a-f]{4}')" "厂商 SAC  产品号 0x2563"
	eq "显示器名字 N50PRO V+" "$(echo "$E" | grep -oE '显示器名字: .*' | sed 's/显示器名字: //')" "N50PRO V+"
	eq "180Hz 那条详细时序算出来是 179.998 Hz" "$(echo "$E" | grep -oE '415.58 MHz.*帧率 [0-9.]+' | grep -oE '[0-9.]+$')" "179.998"

	# 2026-09-14 板上实测：插着这台显示器时 cat /sys/class/graphics/fb0/modes 的原始输出
	BOARD='D:1920x1080p-179
D:1920x1080p-165
D:1920x1080p-144
S:1920x1080p-30
S:1920x1080p-25
S:1920x1080p-24
S:1920x1080p-50
S:1280x720p-50
S:1280x720p-60
S:720x480p-60
S:720x480p-60
S:640x480p-60
S:1920x1080p-60
U:1920x1080p-60
V:1024x768p-60
V:800x600p-60
V:640x480p-60
D:1920x1080p-60'
	ALL=$(echo "$E" | sed -n '/^模式清单/,$p' | grep -oE '[A-Z]:[0-9]+x[0-9]+p-[0-9]+')
	eq "解出来 22 条模式" "$(echo "$ALL" | wc -l)" "22"
	MINE=$(echo "$ALL" | grep -vxE 'S:1280x720p-(24|25|30)|S:1920x1080p-120')
	eq "去掉板子内核表里没有的 VIC 60-63，剩下 18 条和板上 modes 逐行相同，顺序也相同" "$MINE" "$BOARD"
	eq "注错见红：不去掉 VIC 60-63，就和板上对不上（行数差 4）" "$(( $(echo "$ALL" | wc -l) - $(echo "$BOARD" | wc -l) ))" "4"

	cp "$EDID" "$LAB/edid_bad.bin"
	printf '\x81' | dd of="$LAB/edid_bad.bin" bs=1 seek=20 conv=notrunc status=none
	eq "注错见红：改掉基本块里 1 个字节，块 0 校验和报坏" "$(./edid "$LAB/edid_bad.bin" | grep -c '块 0 校验和.*（坏了）')" "1"
	rm -f "$LAB/edid_bad.bin"
fi
echo

rm -f .scan_bug
echo "======================================"
printf '  %d PASS / %d FAIL / %d SKIP\n' "$PASS" "$FAIL" "$SKIP"
echo "======================================"
[ "$FAIL" -eq 0 ]
