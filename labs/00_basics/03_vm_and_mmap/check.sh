#!/bin/bash
# 00_基础 第 07 篇（虚拟内存与 mmap）的判据自动核对
#
# 用法：bash check.sh
# 数据文件写在 $LAB（默认 ~/vmlab），必须是 ext4 —— 第八节讲了为什么。

cd "$(dirname "$0")" || exit 1
LAB=${LAB:-$HOME/vmlab}
mkdir -p "$LAB" || exit 1

PASS=0; FAIL=0; SKIP=0
ok()   { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
no()   { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -n "$2" ] && printf '        %s\n' "$2"; }
skip() { SKIP=$((SKIP+1)); printf '  SKIP  %s\n' "$1"; }
eq()   { if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "期望 $3，实得 $2"; fi; }
lt()   { if awk "BEGIN{exit !($2 < $3)}"; then ok "$1"; else no "$1" "$2 应当小于 $3"; fi; }

die() {
	FAIL=$((FAIL+1))
	printf '  FAIL  构建：%s\n\n  %d PASS / %d FAIL / %d SKIP（构建没过）\n' "$1" "$PASS" "$FAIL" "$SKIP"
	exit 1
}

echo "=== 构建 ==="
for p in lazymap shared_private sigbus probe; do
	gcc $p.c -o $p || die "$p.c 编译不过"
done
sed 's|MAP_SHARED, fd, 0)|MAP_SHARED \| MAP_POPULATE, fd, 0)|' lazymap.c > .pop.c
gcc .pop.c -o .pop || die "MAP_POPULATE 版编译不过"
echo "  完成（数据目录 $LAB）"
echo

echo "=== 07 篇 0  先确认数据目录是 ext4 ==="
FSTYPE=$(stat -f -c %T "$LAB")
if [ "$FSTYPE" = "ext2/ext3" ] || [ "$FSTYPE" = "ext4" ]; then
	ok "数据目录是 $FSTYPE，稀疏文件判据有效"
else
	no "数据目录是 $FSTYPE，不是 ext4" "第八节的判据会失败；用 LAB=/some/ext4/dir bash check.sh"
fi
echo

echo "=== 07 篇 2.6  懒分配 ==="
OUT=$(./lazymap "$LAB/big.bin")
MMAP_MS=$(echo "$OUT" | grep -oE 'mmap 本身耗时 [0-9.]+' | grep -oE '[0-9.]+')
F1=$(echo "$OUT" | sed -n '/\[2\]/,+1p' | grep -oE '多了 [0-9]+ 次缺页' | grep -oE '[0-9]+')
R1=$(echo "$OUT" | sed -n '/\[2\]/,+1p' | grep -oE '次缺页，[0-9]+ KB' | grep -oE '[0-9]+ KB' | grep -oE '[0-9]+')
F2=$(echo "$OUT" | sed -n '/\[3\]/,+2p' | grep -oE '多了 [0-9]+ 次缺页' | grep -oE '[0-9]+')
R2=$(echo "$OUT" | sed -n '/\[3\]/,+2p' | grep -oE '次缺页，[0-9]+ KB' | grep -oE '[0-9]+ KB' | grep -oE '[0-9]+')
NPAGES=$(echo "$OUT" | grep -oE '共 [0-9]+ 页' | grep -oE '[0-9]+')

lt "mmap 64 MiB 耗时不到 1 毫秒（$MMAP_MS ms）" "$MMAP_MS" "1"
lt "mmap 之后物理内存增量不到 1 MB（$R1 KB）" "$R1" "1024"
eq "摸完每页后物理内存精确涨 65536 KB" "$R2" "65536"
lt "缺页增量远小于页数（$F2 << $NPAGES）" "$F2" "$((NPAGES / 4))"
eq "缺页增量 x 32 == 页数（fault-around 一次填 32 页）" "$((F2 * 32))" "$NPAGES"
echo

echo "=== 07 篇 3.5  把懒关掉：MAP_POPULATE ==="
POUT=$(./.pop "$LAB/big2.bin")
PMS=$(echo "$POUT" | grep -oE 'mmap 本身耗时 [0-9.]+' | grep -oE '[0-9.]+')
PR1=$(echo "$POUT" | sed -n '/\[2\]/,+1p' | grep -oE '次缺页，[0-9]+ KB' | grep -oE '[0-9]+ KB' | grep -oE '[0-9]+')
PF2=$(echo "$POUT" | sed -n '/\[3\]/,+2p' | grep -oE '多了 [0-9]+ 次缺页' | grep -oE '[0-9]+')

lt "POPULATE 版 mmap 慢得多（$MMAP_MS -> $PMS ms）" "$MMAP_MS" "$PMS"
if awk "BEGIN{exit !($PR1 > 60000)}"; then
	ok "POPULATE 版 mmap 之后物理内存就已涨满（$PR1 KB）"
else
	no "POPULATE 版 mmap 后应已涨满 64 MiB" "实得 $PR1 KB"
fi
eq "POPULATE 版摸页时缺页增量为 0" "$PF2" "0"
echo

echo "=== 07 篇 6.6  MAP_SHARED vs MAP_PRIVATE ==="
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

echo "=== 07 篇 7.5  映射的边界 ==="
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

echo "=== 07 篇 8.5  稀疏文件 ==="
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
rm -f "$LAB"/big.bin "$LAB"/big2.bin "$LAB"/tiny.bin "$LAB"/empty.bin "$LAB"/sp.bin
echo "======================================"
printf '  %d PASS / %d FAIL / %d SKIP\n' "$PASS" "$FAIL" "$SKIP"
echo "======================================"
[ "$FAIL" -eq 0 ]
