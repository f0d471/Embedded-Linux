#!/bin/bash
# fundamentals 09 篇（虚拟内存与 mmap）的判据自动核对
#
# 用法：bash check.sh
# 数据文件写在 $LAB（默认 ~/vmlab），必须是 ext4 —— 第 10 节讲了为什么。

cd "$(dirname "$0")" || exit 1
LAB=${LAB:-$HOME/vmlab}
mkdir -p "$LAB" || exit 1

PASS=0; FAIL=0; SKIP=0
ok()   { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
no()   { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -n "$2" ] && printf '        %s\n' "$2"; }
skip() { SKIP=$((SKIP+1)); printf '  SKIP  %s\n' "$1"; }
eq()   { if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "期望 $3，实得 $2"; fi; }
lt()   { if awk "BEGIN{exit !($2 < $3)}"; then ok "$1"; else no "$1" "$2 应当小于 $3"; fi; }
between() { if awk "BEGIN{exit !($2 >= $3 && $2 <= $4)}"; then ok "$1"; else no "$1" "$2 应在 [$3, $4] 内"; fi; }

die() {
	FAIL=$((FAIL+1))
	printf '  FAIL  构建：%s\n\n  %d PASS / %d FAIL / %d SKIP（构建没过）\n' "$1" "$PASS" "$FAIL" "$SKIP"
	exit 1
}

echo "=== 构建 ==="
for p in twoaddr lazymap faults mapshow anon mallocsz shared_private sigbus probe; do
	gcc -Wall -Wextra $p.c -o $p || die "$p.c 编译不过"
done
sed 's|MAP_SHARED, fd, 0)|MAP_SHARED \| MAP_POPULATE, fd, 0)|' lazymap.c > .pop.c
gcc .pop.c -o .pop || die "MAP_POPULATE 版编译不过"
echo "  完成（数据目录 $LAB）"
echo

echo "=== 09 篇 0  先确认数据目录是 ext4 ==="
FSTYPE=$(stat -f -c %T "$LAB")
if [ "$FSTYPE" = "ext2/ext3" ] || [ "$FSTYPE" = "ext4" ]; then
	ok "数据目录是 $FSTYPE，稀疏文件判据有效"
else
	no "数据目录是 $FSTYPE，不是 ext4" "第 10 节的判据会失败；用 LAB=/some/ext4/dir bash check.sh"
fi
echo

echo "=== 09 篇 1.7  同一个地址，两份数据 ==="
OUT=$(./twoaddr)
NADDR=$(echo "$OUT" | grep -oE '&g=0x[0-9a-f]+' | sort -u | wc -l)
eq "三行打印的 &g 是同一个地址" "$NADDR" "1"
if echo "$OUT" | grep -q '子进程.*g=222' && echo "$OUT" | grep -q '父进程.*g=111'; then
	ok "同一个地址，子进程读到 222、父进程读到 111"
else
	no "子进程应读到 222、父进程 111" "$OUT"
fi
echo

echo "=== 09 篇 2.6  懒分配 ==="
OUT=$(./lazymap "$LAB/big.bin")
MMAP_MS=$(echo "$OUT" | grep -oE 'mmap 本身耗时 [0-9.]+' | grep -oE '[0-9.]+')
D2=$(echo "$OUT" | sed -n '/\[2\]/,+1p' | tail -1)
D3=$(echo "$OUT" | sed -n '/\[3\]/,+1p' | tail -1)
MI1=$(echo "$D2" | grep -oE '多了 [0-9]+ 次次缺页' | grep -oE '[0-9]+')
R1=$(echo "$D2" | grep -oE '，[0-9]+ KB' | grep -oE '[0-9]+')
MI2=$(echo "$D3" | grep -oE '多了 [0-9]+ 次次缺页' | grep -oE '[0-9]+')
MA2=$(echo "$D3" | grep -oE '[0-9]+ 次主缺页' | grep -oE '[0-9]+')
R2=$(echo "$D3" | grep -oE '，[0-9]+ KB' | grep -oE '[0-9]+')
NPAGES=$(echo "$OUT" | grep -oE '共 [0-9]+ 页' | grep -oE '[0-9]+')

lt "mmap 64 MiB 耗时不到 1 毫秒（$MMAP_MS ms）" "$MMAP_MS" "1"
lt "mmap 之后物理内存增量不到 1 MB（$R1 KB）" "$R1" "1024"
eq "摸完每页后物理内存精确涨 65536 KB" "$R2" "65536"
between "主缺页约等于 页数/32（$MA2 ≈ $((NPAGES/32))，磁盘预读窗口 32 页）" "$MA2" "500" "520"
lt "总缺页远小于页数（$((MI2+MA2)) << $NPAGES）" "$((MI2+MA2))" "$((NPAGES / 4))"
echo

echo "=== 09 篇 2.6  fault-around 与预读（faults.c 对照） ==="
WOUT=$(./faults "$LAB/f.bin" 1 16384)
WMI=$(echo "$WOUT" | grep -oE '次缺页 [0-9]+' | grep -oE '[0-9]+')
WMA=$(echo "$WOUT" | grep -oE '主缺页 [0-9]+' | grep -oE '[0-9]+')
eq "页全在缓存时：次缺页 = 页数/16（fault-around 一次 16 页）" "$WMI" "1024"
eq "页全在缓存时：主缺页为 0（一页磁盘都不用读）" "$WMA" "0"
COUT=$(./faults "$LAB/f.bin" 0 16384)
CMA=$(echo "$COUT" | grep -oE '主缺页 [0-9]+' | grep -oE '[0-9]+')
between "冷文件：主缺页 ≈ 页数/32（$CMA）" "$CMA" "500" "520"
POUT=$(./faults "$LAB/f.bin" 2 256)
echo "$POUT" | grep -q '顺手建好了 16 页的表项' \
	&& ok "摸第 0 页后，0..15 共 16 页已在内存（pagemap 实测）" \
	|| no "fault-around 窗口应是 16 页" "$POUT"
echo

echo "=== 09 篇 3.4  把懒关掉：MAP_POPULATE ==="
POUT=$(./.pop "$LAB/big2.bin")
PMS=$(echo "$POUT" | grep -oE 'mmap 本身耗时 [0-9.]+' | grep -oE '[0-9.]+')
PD2=$(echo "$POUT" | sed -n '/\[2\]/,+1p' | tail -1)
PD3=$(echo "$POUT" | sed -n '/\[3\]/,+1p' | tail -1)
PR1=$(echo "$PD2" | grep -oE '，[0-9]+ KB' | grep -oE '[0-9]+')
PMI2=$(echo "$PD3" | grep -oE '多了 [0-9]+ 次次缺页' | grep -oE '[0-9]+')
PMA2=$(echo "$PD3" | grep -oE '[0-9]+ 次主缺页' | grep -oE '[0-9]+')

lt "POPULATE 版 mmap 慢得多（$MMAP_MS -> $PMS ms）" "$MMAP_MS" "$PMS"
if awk "BEGIN{exit !($PR1 > 60000)}"; then
	ok "POPULATE 版 mmap 之后物理内存就已涨满（$PR1 KB）"
else
	no "POPULATE 版 mmap 后应已涨满 64 MiB" "实得 $PR1 KB"
fi
if [ "$PMI2" = "0" ] && [ "$PMA2" = "0" ]; then
	ok "POPULATE 版摸页时缺页增量为 0（次 $PMI2 主 $PMA2）"
else
	no "POPULATE 版摸页时缺页应为 0" "次 $PMI2 主 $PMA2"
fi
echo

echo "=== 09 篇 4.4  /proc/self/maps 逐列读 ==="
MOUT=$(./mapshow "$LAB/map8.bin")
MLINE=$(echo "$MOUT" | grep 'map8\.bin')
if [ -n "$MLINE" ]; then
	ok "maps 里找得到 map8.bin 那一行"
else
	no "maps 里应有 map8.bin 那一行"
fi
PERM=$(echo "$MLINE" | awk '{print $2}')
eq "映射行的权限是 r--s（PROT_READ + MAP_SHARED）" "$PERM" "r--s"
RNG=$(echo "$MLINE" | awk '{print $1}')
LO=${RNG%-*}; HI=${RNG#*-}
eq "映射长度精确等于 8 MiB（$LO-$HI）" "$((16#$HI - 16#$LO))" "8388608"
echo

echo "=== 09 篇 6.6  MAP_SHARED vs MAP_PRIVATE ==="
SOUT=$(./shared_private "$LAB")
S_OTHER=$(echo "$SOUT" | awk '/MAP_SHARED .*另一个进程/{print $NF}')
S_FILE=$(echo  "$SOUT" | awk '/MAP_SHARED .*文件里/{print $NF}')
P_OTHER=$(echo "$SOUT" | awk '/MAP_PRIVATE .*另一个进程/{print $NF}')
P_FILE=$(echo  "$SOUT" | awk '/MAP_PRIVATE .*文件里/{print $NF}')
eq "MAP_SHARED：另一个进程看到 BBBBBAAAAA" "$S_OTHER" "BBBBBAAAAA"
eq "MAP_SHARED：文件里也是 BBBBBAAAAA"     "$S_FILE"  "BBBBBAAAAA"
eq "MAP_PRIVATE：另一个进程看到 AAAAAAAAAA" "$P_OTHER" "AAAAAAAAAA"
eq "MAP_PRIVATE：文件里还是 AAAAAAAAAA（写丢了，且没报错）" "$P_FILE" "AAAAAAAAAA"
echo

echo "=== 09 篇 7.4  匿名映射 ==="
AOUT=$(./anon)
AD2=$(echo "$AOUT" | sed -n '/\[2 mmap/,+1p' | tail -1)
AD3=$(echo "$AOUT" | sed -n '/\[3 /,+1p' | tail -1)
AD4=$(echo "$AOUT" | sed -n '/\[4 /,+1p' | tail -1)
AR1=$(echo "$AD2" | grep -oE '，[0-9]+ KB' | grep -oE '[0-9]+')
AMI_RD=$(echo "$AD3" | grep -oE '多了 [0-9]+ 次次缺页' | grep -oE '[0-9]+')
AR_RD=$(echo "$AD3" | grep -oE '，[0-9]+ KB' | grep -oE '[0-9]+')
AMI_WR=$(echo "$AD4" | grep -oE '多了 [0-9]+ 次次缺页' | grep -oE '[0-9]+')
AR_WR=$(echo "$AD4" | grep -oE '，[0-9]+ KB' | grep -oE '[0-9]+')

lt "匿名 mmap 1 GiB 之后物理内存增量不到 1 MB（$AR1 KB）" "$AR1" "1024"
eq "读匿名内存：每页都缺页（262144 次，没有 fault-around）" "$AMI_RD" "262144"
lt "读匿名内存：物理内存不涨（零页是共享的）" "$AR_RD" "4096"
eq "写匿名内存：物理内存精确涨 1 GiB（1048576 KB）" "$AR_WR" "1048576"
eq "写匿名内存：又是逐页一次缺页（262144 次）" "$AMI_WR" "262144"

if command -v strace >/dev/null 2>&1; then
	TOUT=$(strace -e trace=mmap,brk ./mallocsz 2>&1)
	if echo "$TOUT" | grep -qE 'mmap\(NULL, 2[0-9]{6}, PROT_READ\|PROT_WRITE, MAP_PRIVATE\|MAP_ANONYMOUS, -1'; then
		ok "malloc 2 MiB 走 mmap(MAP_ANONYMOUS)（strace 可见）"
	else
		no "2 MiB 的 malloc 应走匿名 mmap" "$TOUT"
	fi
else
	skip "strace 不在，malloc 阈值那条没法看"
fi
echo

echo "=== 09 篇 8.4  映射设备内存（/dev/fb0，只能在板上做） ==="
skip "板上判据：maps 里 /dev/fb0 行是 rw-s、偏移列是 smem_start（2026-09-14 归档，板子不在线）"
echo

echo "=== 09 篇 9.5  映射的边界 ==="
BOUT=$(./sigbus "$LAB/tiny.bin" 0)
echo "$BOUT" | grep -q "p\[0\]    = 'a'" && ok "p[0] 是文件里真有的 'a'" || no "p[0] 应是 'a'"
echo "$BOUT" | grep -qE "p\[100\]  = 0"   && ok "p[100]（第一页内、文件外）读到 0，不报错" || no "p[100] 应是 0"
echo "$BOUT" | grep -qE "p\[4095\] = 0"   && ok "p[4095]（第一页最后一字节）仍然安全" || no "p[4095] 应是 0"

# 用子 shell 跑，免得父 shell 打出 "Bus error" 那行提示
bash -c "./sigbus \"$LAB/tiny.bin\" 1" >/dev/null 2>&1; RC=$?
eq "读 p[5000] 挨 SIGBUS（退出码 135 = 128+7）" "$RC" "135"

cat > .segv.c <<'EOF'
int main(void){ *(int*)0 = 1; return 0; }
EOF
gcc .segv.c -o .segv 2>/dev/null
bash -c "./.segv" >/dev/null 2>&1; RC=$?
eq "空指针解引用是 SIGSEGV（退出码 139 = 128+11）" "$RC" "139"

# 空文件不能映射
cat > .empty.c <<'EOF'
#include <stddef.h>
#include <fcntl.h>
#include <sys/mman.h>
int main(int c, char **v)
{
	int fd = open(v[1], O_RDWR | O_CREAT | O_TRUNC, 0644);
	return mmap(NULL, 0, PROT_READ, MAP_SHARED, fd, 0) == MAP_FAILED;
}
EOF
if gcc .empty.c -o .empty 2>/dev/null; then
	./.empty "$LAB/empty.bin"; eq "空文件（length=0）映射失败，返回 MAP_FAILED" "$?" "1"
else
	no "空文件判据的辅助程序编译不过"
fi
echo

echo "=== 09 篇 10.4  稀疏文件 ==="
rm -f "$LAB/sp.bin"
dd if=/dev/zero of="$LAB/sp.bin" bs=1 count=4 seek=1048576 status=none
eq "逻辑大小 1048580 字节" "$(stat -c %s "$LAB/sp.bin")" "1048580"
BLOCKS=$(stat -c %b "$LAB/sp.bin")
if [ "$BLOCKS" -le 16 ]; then
	ok "实际只占 $BLOCKS 个 512 字节块（空洞不占盘）"
else
	no "空洞应当不占盘" "占了 $BLOCKS 块；这个目录的文件系统不支持稀疏文件"
fi
eq "空洞里读出来是 0" \
   "$(dd if="$LAB/sp.bin" bs=1 skip=500000 count=4 status=none | od -An -tu1 | tr -s ' ' | sed 's/^ //;s/ $//')" \
   "0 0 0 0"

PROBE_OUT=$(./probe "$LAB")
echo "$PROBE_OUT" | grep -q 'MAP_SHARED 写回: 有效' \
	&& ok "probe：这个目录上 MAP_SHARED 写回有效" \
	|| no "probe：MAP_SHARED 写回无效" "$PROBE_OUT"
echo "$PROBE_OUT" | grep -q '空洞有效' \
	&& ok "probe：这个目录上稀疏文件空洞有效" \
	|| no "probe：空洞被填实" "$PROBE_OUT"
rm -f "$LAB/probe.bin" "$LAB/sparse.bin"

# 对照：仓库所在目录（Windows 盘）不支持稀疏文件
HERE_FS=$(stat -f -c %T .)
if [ "$HERE_FS" = "v9fs" ] || [ "$HERE_FS" = "9p" ]; then
	rm -f .sp.bin
	dd if=/dev/zero of=.sp.bin bs=1 count=4 seek=1048576 status=none
	HB=$(stat -c %b .sp.bin)
	rm -f .sp.bin
	if [ "$HB" -gt 1000 ]; then
		ok "对照：同一条命令在 $HERE_FS 上占了 $HB 块（空洞被填实）"
	else
		no "对照：$HERE_FS 上本应把空洞填实" "只占了 $HB 块"
	fi
else
	skip "对照实验（当前目录是 $HERE_FS，不是 Windows 盘）"
fi
echo

rm -f .pop.c .pop .segv.c .segv .empty.c .empty
rm -f "$LAB"/big.bin "$LAB"/big2.bin "$LAB"/f.bin "$LAB"/map8.bin "$LAB"/tiny.bin "$LAB"/empty.bin "$LAB"/sp.bin
echo "======================================"
printf '  %d PASS / %d FAIL / %d SKIP\n' "$PASS" "$FAIL" "$SKIP"
echo "======================================"
[ "$FAIL" -eq 0 ]
