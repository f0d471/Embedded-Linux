#!/bin/bash
# 00_基础 第 09 篇（驱动与设备文件）的判据自动核对
#
# 用法：bash check.sh
#       普通用户能跑一半，建设备节点、读 /dev/rtc0、写 /dev/kmsg 这几组会 SKIP。
#       跑全套要 root。WSL 里的 sudo 要密码，从 Windows PowerShell 用免密的写法：
#           wsl -u root bash labs/00_basics/08_driver_devfile/check.sh
# 设备节点建在 $LAB（默认 ~/devlab），必须在 ext4 上，第四节讲了为什么。

cd "$(dirname "$0")" || exit 1
HERE=$(pwd)
LAB=${LAB:-$HOME/devlab}

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

ROOT=0; [ "$(id -u)" = 0 ] && ROOT=1

echo "=== 构建 ==="
gcc -Wall -O2 -o devopen devopen.c     || die "devopen.c 编译不过"
gcc -Wall -O2 -o ioctlcode ioctlcode.c || die "ioctlcode.c 编译不过"
mkdir -p "$LAB" || die "建不了 $LAB"
rm -f "$LAB"/mynull "$LAB"/myzero "$LAB"/myfull "$LAB"/nobody "$LAB"/fbfake
printf 'ABCDEFGH' > "$LAB/data.txt"
if [ $ROOT = 1 ]; then echo "  完成（root，全套）"; else echo "  完成（普通用户，需要 root 的判据会 SKIP）"; fi
echo

# 取 devopen 输出里某个路径那一行
row() { "$HERE/devopen" "$@" | tail -1; }

echo "=== 09 篇 二  设备文件里存的是两个数 ==="
eq "/dev/null 是字符设备" "$(stat -c %F /dev/null)" "character special file"
eq "/dev/null 的“大小”是 0" "$(stat -c %s /dev/null)" "0"
eq "/dev/null 的设备号是 1,3" "$(stat -c '%t,%T' /dev/null)" "1,3"
eq "/proc/devices 字符设备段里 1 号叫 mem" \
   "$(sed -n '/^Character/,/^$/p' /proc/devices | awk '$1 == 1 {print $2}')" "mem"
echo

echo "=== 09 篇 三  名字无所谓，号码说了算 ==="
if [ $ROOT = 1 ]; then
	cd "$LAB" || exit 1
	mknod mynull c 1 3 && mknod myzero c 1 5 && mknod myfull c 1 7
	echo "$(row mynull)" | grep -q 'read=0 \[\]  write=1' && ok "自己建的 mynull(1,3)：读返回 0、写吞掉 1 字节，和 /dev/null 一样" \
		|| no "mynull 应当表现得和 /dev/null 一样" "$(row mynull)"
	echo "$(row myzero)" | grep -q 'read=8 \[0000000000000000\]' && ok "自己建的 myzero(1,5)：读出 8 个 0" \
		|| no "myzero 应当读出 8 个 0" "$(row myzero)"
	echo "$(row myfull)" | grep -q 'write 失败 ENOSPC' && ok "自己建的 myfull(1,7)：写报 ENOSPC" \
		|| no "myfull 写应当报 ENOSPC" "$(row myfull)"
	rm mynull; mknod mynull c 1 5
	echo "$(row mynull)" | grep -q 'read=8 \[0000000000000000\]' && ok "注错见红：名字不变、号码换成 1,5，mynull 就变成了 zero" \
		|| no "号码换成 1,5 后 mynull 应当读出 8 个 0" "$(row mynull)"
	cd "$HERE" || exit 1
else
	skip "自建 mynull / myzero / myfull 三条 + 注错一条（要 root 才能 mknod）"
fi
echo

echo "=== 09 篇 四  号码没人认领，以及节点建在哪 ==="
eq "200 号在 /proc/devices 里没有登记" "$(sed -n '/^Character/,/^$/p' /proc/devices | grep -cE '^ *200 ')" "0"
eq "29 号登记的名字是 fb" "$(sed -n '/^Character/,/^$/p' /proc/devices | awk '$1 == 29 {print $2}')" "fb"
if [ -e /sys/class/graphics/fb0 ]; then
	skip "这台机器有 fb0，“登记了但没有实例”那条对照做不了"
else
	ok "/sys/class/graphics 下没有 fb0（只登记了号码，没有设备实例）"
fi
if [ $ROOT = 1 ]; then
	cd "$LAB" || exit 1
	mknod nobody c 200 0 && mknod fbfake c 29 0
	echo "$(row nobody)" | grep -q 'open 失败 ENXIO' && ok "200,0 没人登记：open 报 ENXIO" || no "200,0 应当报 ENXIO" "$(row nobody)"
	if [ ! -e /sys/class/graphics/fb0 ]; then
		echo "$(row fbfake)" | grep -q 'open 失败 ENODEV' && ok "29,0 登记了但没实例：open 报 ENODEV" || no "29,0 应当报 ENODEV" "$(row fbfake)"
	fi
	cd "$HERE" || exit 1
	if findmnt -no OPTIONS /tmp 2>/dev/null | grep -qw nodev; then
		rm -f /tmp/.devcheck_null; mknod /tmp/.devcheck_null c 1 3
		echo "$(row /tmp/.devcheck_null)" | grep -q 'open 失败 EACCES' && ok "同一个 1,3 建在带 nodev 的 /tmp：连 root 都 open 报 EACCES" \
			|| no "nodev 挂载点上的设备节点应当打不开" "$(row /tmp/.devcheck_null)"
		rm -f /tmp/.devcheck_null
	else
		skip "/tmp 没有 nodev 选项"
	fi
	if [ "$(stat -f -c %T "$HERE")" = "v9fs" ] || [ "$(findmnt -no FSTYPE -T "$HERE")" = "9p" ]; then
		if mknod "$HERE/.devtest" c 1 3 2>/dev/null; then
			rm -f "$HERE/.devtest"; no "仓库所在的 Windows 盘上 mknod 应当失败"
		else
			ok "仓库所在的 Windows 盘（9p）上 mknod 直接失败"
		fi
	else
		skip "仓库不在 Windows 盘上，这条对照做不了"
	fi
else
	skip "ENXIO / ENODEV / nodev / Windows 盘 四条（要 root 才能 mknod）"
fi
echo

echo "=== 09 篇 五  sysfs：内核公开出来的设备档案 ==="
N=0; BAD=0
for d in /sys/class/mem/*; do
	n=${d##*/}
	[ -e "/dev/$n" ] || continue
	t=$(stat -c '%t %T' "/dev/$n")
	[ "$(cat "$d/dev")" = "$((16#${t% *})):$((16#${t#* }))" ] || BAD=$((BAD + 1))
	N=$((N + 1))
done
if [ $N -ge 5 ] && [ $BAD -eq 0 ]; then
	ok "/sys/class/mem 下 $N 个设备，dev 文件里的号码和 /dev 节点逐个相等"
else
	no "sysfs 的号码应当和 /dev 节点一致" "比了 $N 个，不相等 $BAD 个"
fi
t=$(stat -c '%t %T' /dev/null)
if [ "$(cat /sys/class/mem/zero/dev)" != "$((16#${t% *})):$((16#${t#* }))" ]; then
	ok "注错见红：拿 zero 的 dev 文件去比 /dev/null，对不上"
else
	no "zero 的号码不应等于 /dev/null 的号码"
fi
eq "uevent 里的 DEVMODE 就是 /dev/null 的权限位" \
   "$(awk -F= '/^DEVMODE=/{print $2}' /sys/class/mem/null/uevent | sed 's/^0*//')" "$(stat -c %a /dev/null)"
if [ -e /sys/class/mem/null/device ]; then no "mem/null 背后不应有硬件（不应有 device 链接）"; else ok "mem/null 没有 device 链接：背后没有硬件"; fi
eq "/dev 挂的是 devtmpfs" "$(findmnt -no FSTYPE /dev)" "devtmpfs"
FOUND=0
for c in /sys/class/net/* /sys/class/rtc/*; do
	[ -e "$c/device/driver" ] || continue
	devname=$(basename "$(readlink -f "$c/device")")
	drvdir=$(readlink -f "$c/device/driver")
	if [ -e "$drvdir/$devname" ]; then
		ok "${c#/sys/class/}：驱动目录 $(basename "$drvdir")/ 里有指回这个设备（$devname）的链接"
	else
		no "${c#/sys/class/}：驱动目录里应当有 $devname"
	fi
	FOUND=$((FOUND + 1))
done
[ $FOUND = 0 ] && skip "没找到带 driver 链接的 net / rtc 设备"
echo

echo "=== 09 篇 六  ioctl：文件接口装不下的操作 ==="
C=$(./ioctlcode)
field() { echo "$C" | awk -v n="$1" -v k="$2" '$1 == n { for (i = 1; i <= NF; i++) if ($i ~ "^" k "=") { sub("^" k "=", "", $i); print $i } }'; }
eq "RTC_RD_TIME 请求码是 0x80247009" "$(echo "$C" | awk '$1 == "RTC_RD_TIME" {print $2}')" "0x80247009"
eq "RTC_RD_TIME 请求码里带的大小 == sizeof(struct rtc_time)" "$(field RTC_RD_TIME 大小)" "$(field RTC_RD_TIME sizeof)"
eq "FBIOGET_VSCREENINFO 请求码里的大小是 0（老式请求码不带大小）" "$(field FBIOGET_VSCREENINFO 大小)" "0"
eq "TIOCGWINSZ 请求码是 0x00005413" "$(echo "$C" | awk '$1 == "TIOCGWINSZ" {print $2}')" "0x00005413"
F=$(./ioctlcode "$LAB/data.txt" | tail -2)
eq "对普通文件发 RTC_RD_TIME 和 FBIOGET_VSCREENINFO，两个都报 ENOTTY" \
   "$(echo "$F" | grep -c 'Inappropriate ioctl for device')" "2"
if [ $ROOT = 1 ] && [ -e /dev/rtc0 ]; then
	R=$(./ioctlcode /dev/rtc0 | tail -2)
	eq "对 /dev/rtc0 发 RTC_RD_TIME 成功，日期和系统时间（UTC）同一天" \
	   "$(echo "$R" | grep -oE '成功: [0-9-]+' | grep -oE '[0-9-]+$')" "$(date -u +%F)"
	echo "$R" | grep -q 'FBIOGET_VSCREENINFO) 失败: Inappropriate ioctl' \
		&& ok "注错见红：对 /dev/rtc0 发 fb 的请求码，报 ENOTTY" || no "rtc 驱动不应认 fb 的请求码" "$R"
else
	skip "/dev/rtc0 两条（要 root，或者没有 rtc0）"
fi
echo

echo "=== 09 篇 七  dmesg：驱动写的日志 ==="
if [ "$(dmesg 2>/dev/null | wc -l)" -gt 0 ]; then ok "dmesg 读得到内核日志（$(dmesg | wc -l) 行）"; else skip "当前用户读不了 dmesg"; fi
if [ $ROOT = 1 ]; then
	M="devcheck-marker-$$"
	echo "$M" > /dev/kmsg
	LINE=$(dmesg | grep "$M")
	if [ -n "$LINE" ]; then ok "往 /dev/kmsg 写一行，dmesg 里能读到"; else no "dmesg 里应当有刚写的那一行"; fi
	TS=$(echo "$LINE" | grep -oE '^\[ *[0-9.]+' | tr -d '[ ')
	UP=$(cut -d' ' -f1 /proc/uptime)
	# /proc/uptime 只有两位小数，会比时间戳"早"几毫秒，所以下限放到 -0.01
	if awk "BEGIN{d = $UP - $TS; exit !(d >= -0.01 && d < 2)}"; then
		ok "dmesg 行首的时间戳就是开机后的秒数（$TS，uptime $UP）"
	else
		no "时间戳应当约等于 /proc/uptime" "时间戳 $TS，uptime $UP"
	fi
else
	skip "往 /dev/kmsg 写 + 时间戳对账 两条（要 root）"
	if echo x 2>/dev/null > /dev/kmsg; then no "普通用户不应能写 /dev/kmsg"; else ok "普通用户写 /dev/kmsg 被拒绝"; fi
fi
echo

rm -f "$LAB"/mynull "$LAB"/myzero "$LAB"/myfull "$LAB"/nobody "$LAB"/fbfake "$LAB"/data.txt
echo "======================================"
printf '  %d PASS / %d FAIL / %d SKIP\n' "$PASS" "$FAIL" "$SKIP"
echo "======================================"
[ "$FAIL" -eq 0 ]
