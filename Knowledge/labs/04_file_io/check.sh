#!/bin/bash
# 04 篇（文件 IO）的判据自动核对。
#
# 用法：bash check.sh
# 全部工作在 $HOME 下的临时目录里做：/mnt/e 是 NTFS，空洞等判据会失真（教程 2.5 节）。
# 注错见红：教程各 [判] 块与 4.6 节的注错表列了注法；改坏一处，对应判据必须变红。
# 第 6、7 组还用到 labs/00_basics 下的 fdshow、forkfd、sigbus、shared_private。

cd "$(dirname "$0")" || exit 1
SRC=$PWD
B=$SRC/../00_basics

W=$(mktemp -d "$HOME/fio04-check.XXXXXX") || exit 1
trap 'rm -rf "$W"' EXIT
cd "$W" || exit 1
umask 022

PASS=0; FAIL=0; SKIP=0
ok()   { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
no()   { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; }
skip() { SKIP=$((SKIP+1)); printf '  SKIP  %s\n' "$1"; }
eq()   { if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "期望 $3，实得 $2"; fi; }
die()  { printf '  FAIL  构建：%s\n\n  %d PASS / %d FAIL / %d SKIP（构建没过）\n' "$1" "$PASS" "$((FAIL+1))" "$SKIP"; exit 1; }
field_int() { grep -oE '[0-9]+' | tail -1; }
field_int_all() { while read -r l; do echo "$l" | field_int; done | tr '\n' ' ' | sed 's/ $//'; }

echo "=== 构建 ==="
for f in hold o wp hole mode mycopy pipe_rw buf dup2_printf crash_stdio csvproc apprace sscanf_demo mmap_empty; do
	gcc -Wall "$SRC/$f.c" -o "$f" 2> "build_$f.log" || die "$f.c（$(head -1 build_$f.log)）"
done
gcc -O2 -Wall "$SRC/cp_rw.c" -o cp_rw || die "cp_rw.c"
gcc -O2 -Wall -DUSE_MMAP "$SRC/cp_rw.c" -o cp_mmap || die "cp_rw.c -DUSE_MMAP"
for f in 02_fd_and_vfs/fdshow 02_fd_and_vfs/forkfd 03_vm_and_mmap/sigbus 03_vm_and_mmap/shared_private; do
	gcc -w "$B/$f.c" -o "${f##*/}" || die "00_basics/$f.c"
done
echo "  完成"
echo

HAVE_STRACE=1
command -v strace >/dev/null 2>&1 || HAVE_STRACE=0

echo "=== 1 节  open 与 fd ==="
printf 'x' > f1.txt; printf 'y' > f2.txt
./hold f1.txt > h1.out & P1=$!
./hold f2.txt > h2.out & P2=$!
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
	[ -s h1.out ] && [ -s h2.out ] && break; sleep 0.1
done
eq "第一个 open 拿到 fd 3" "$(sed "s/pid=$P1//" h1.out)" " fd=3"
eq "另一个进程也拿到 fd 3" "$(sed "s/pid=$P2//" h2.out)" " fd=3"
L1=$(readlink "/proc/$P1/fd/3"); L2=$(readlink "/proc/$P2/fd/3")
if [ "$L1" = "$W/f1.txt" ] && [ "$L2" = "$W/f2.txt" ]; then
	ok "两个进程各自的 fd 3 指向各自的文件"
else
	no "/proc/<pid>/fd/3 指向" "$L1 / $L2"
fi
kill "$P1" "$P2" 2>/dev/null; wait 2>/dev/null

rm -f a.txt
./mode a.txt 0777
eq "新建要 0777，落地 755（umask 022）" "$(stat -c %a a.txt)" "755"
./mode a.txt 0600
eq "文件已存在时 mode=0600 不生效" "$(stat -c %a a.txt)" "755"
./mode a.txt 0777
eq "文件已存在时 mode=0777 仍不生效" "$(stat -c %a a.txt)" "755"

O=$(./o)
eq "打开不存在：errno 2"   "$(echo "$O" | sed -n 1p | grep -oE 'errno= *[0-9]+' | field_int)" "2"
eq "O_RDWR 开目录：errno 21" "$(echo "$O" | sed -n 2p | grep -oE 'errno= *[0-9]+' | field_int)" "21"
L3=$(echo "$O" | sed -n 3p)
if echo "$L3" | grep -q 'fd=  3' && echo "$L3" | grep -q 'errno=21'; then
	ok "O_RDONLY 开目录成功（fd=3），errno 是上一次失败的残值 21"
else
	no "open 成功时 errno 残值" "$L3"
fi
eq "O_CREAT|O_EXCL 打已存在：errno 17" "$(echo "$O" | sed -n 4p | grep -oE 'errno= *[0-9]+' | field_int)" "17"
eq "对无写权限文件 O_WRONLY：errno 13" "$(echo "$O" | sed -n 5p | grep -oE 'errno= *[0-9]+' | field_int)" "13"
echo

echo "=== 2 节  read/write 与文件位置 ==="
P=$(./pipe_rw)
eq "管道容量 65536 字节" "$(echo "$P" | sed -n 1p | field_int)" "65536"
eq "read 要 100 实际返回 5" "$(echo "$P" | sed -n 2p | field_int)" "5"
eq "write 要 1 MiB 实际返回 65536" "$(echo "$P" | sed -n 3p | field_int)" "65536"
eq "写满后再写返回 -1，errno 11（EAGAIN）" \
   "$(echo "$P" | sed -n 4p | grep -oE 'errno=[0-9]+' | field_int)" "11"

printf 'abcdefghijklmnopqrst\n' > w.txt
./wp w.txt
eq "lseek 到中间再 write 是覆盖" "$(cat w.txt)" "abc123ghijklmnopqrst"
eq "覆盖后长度仍是 21 字节" "$(wc -c < w.txt)" "21"

./hole sparse.bin
eq "空洞文件逻辑大小 1048580" "$(stat -c %s sparse.bin)" "1048580"
B512=$(stat -c %b sparse.bin)
if [ "$B512" -le 16 ]; then
	ok "实际只分配 $B512 个 512 字节块（空洞不占盘）"
else
	no "空洞应几乎不占盘" "分配了 $B512 个块"
fi
eq "空洞里读出来全是 0" "$(od -An -tx1 -j 512 -N 8 sparse.bin | tr -d ' \n')" "0000000000000000"

head -c 1048577 /dev/urandom > big.bin   # 不是 4096 的整数倍,最后一读不满一缓冲
if ./mycopy big.bin copy.bin && cmp -s big.bin copy.bin; then
	ok "mycopy 与源逐字节一致（cmp）"
else
	no "mycopy 拷贝不一致"
fi
: > empty.bin
./mycopy empty.bin e2.bin
eq "mycopy 拷空文件得到 0 字节" "$(stat -c %s e2.bin)" "0"

AOK=1
for _ in 1 2 3; do
	N=$(./apprace append | field_int)
	[ "$N" = "68000" ] || AOK=0
done
[ "$AOK" = 1 ] && ok "O_APPEND 并发追加 3 轮都精确 68000" || no "O_APPEND 应每轮 68000"
LOST=0
for _ in 1 2 3; do
	N=$(./apprace lseek 20000 | field_int)
	[ "$N" -lt 680000 ] && LOST=$((LOST+1))
done
if [ "$LOST" -ge 1 ]; then
	ok "lseek+write 并发 3 轮至少 1 轮丢数据（$LOST 轮）"
else
	no "lseek+write 并发应丢数据"
fi
echo

echo "=== 3 节  dup2 与重定向 ==="
./dup2_printf o3.txt
eq "dup2(fd,1) 后 printf 落进文件" "$(cat o3.txt)" "hello, world"
eq "文件正好 13 字节" "$(wc -c < o3.txt)" "13"
echo

echo "=== 4 节  CSV 综合实验 ==="
{ printf '\xEF\xBB\xBF'; printf ',语文,数学,英语,总分,评价\n张三,90,91,92,,\n李四,80,81,82,,\n王五,70,71,72,,\n'; } > score.csv
./csvproc score.csv out.csv
eq "score.csv 输出 110 字节" "$(wc -c < out.csv)" "110"
eq "输出 4 行且都以 CRLF 结尾" "$(grep -c "$(printf '\r')$" out.csv)" "4"
eq "BOM 三个字节原样保留" "$(head -c 3 out.csv | od -An -tx1 | tr -d ' \n')" "efbbbf"
grep -q '张三,90,91,92,273,A+' out.csv && ok "张三 总分 273 评价 A+" || no "张三 行"
grep -q '李四,80,81,82,243,A'  out.csv && ok "李四 总分 243 评价 A"  || no "李四 行"
grep -q '王五,70,71,72,213,B'  out.csv && ok "王五 总分 213 评价 B"  || no "王五 行"
if command -v perl >/dev/null 2>&1; then
	perl -pe 's/\n/\r\n/' score.csv > crlf.csv
	./csvproc crlf.csv o1.csv
	eq "CRLF 输入也处理 4 行" "$(wc -l < o1.csv)" "4"
	cmp -s out.csv o1.csv && ok "CRLF 输入的输出与 LF 输入逐字节一致" || no "CRLF 输入的输出应与 LF 输入一致" "$(wc -c < o1.csv) 字节"
else
	skip "crlf.csv 判据（没装 perl）"
fi
printf '\xEF\xBB\xBF,a,b,c,d,e\n\xE7\x94\xB2,1,2,3,,' > nonl.csv
./csvproc nonl.csv o2.csv
eq "末行无换行也收进来：2 行" "$(wc -l < o2.csv)" "2"
grep -q '甲,1,2,3,6,B' o2.csv && ok "末行的半行数据被处理" || no "末行半行"
SD=$(./sscanf_demo)
eq "sscanf %s 吞掉整行：返回 1" "$(echo "$SD" | sed -n 1p | grep -oE 'ret=[0-9]+' | field_int)" "1"
eq "sscanf %99[^,] 拆出 4 个字段" "$(echo "$SD" | sed -n 2p | grep -oE 'ret=[0-9]+' | field_int)" "4"
echo

echo "=== 5 节  标准 IO 的缓冲 ==="
if [ "$HAVE_STRACE" = 1 ]; then
	strace -f -e trace=write -o tf.txt ./buf > bufout.txt
	eq "printf 1000 行到文件：write 3 次" "$(grep -cE '(^|[0-9]+ +)write\(' tf.txt)" "3"
	eq "三次 write 共 8890 字节（4096+4096+698）" \
	   "$(grep -oE '= [0-9]+$' tf.txt | awk '{s+=$NF} END{print s}')" "8890"
	strace -f -e trace=write -o tp.txt ./buf | cat > /dev/null
	eq "输出到管道：write 3 次" "$(grep -cE '(^|[0-9]+ +)write\(' tp.txt)" "3"
	if command -v script >/dev/null 2>&1; then
		script -q -c "strace -f -e trace=write -o tt.txt ./buf" /dev/null > /dev/null
		eq "输出到终端：write 1000 次（行缓冲）" "$(grep -cE '(^|[0-9]+ +)write\(' tt.txt)" "1000"
	else
		skip "终端行缓冲判据（没有 script 命令）"
	fi
else
	skip "缓冲计数 4 条判据（没装 strace）"
fi
./crash_stdio > co.txt 2> ce.txt; RC=$?
eq "abort 退出码 134（128+6）" "$RC" "134"
eq "崩溃后 stdout 0 字节（缓冲里的丢了）" "$(wc -c < co.txt)" "0"
grep -q 'to stderr' ce.txt && ok "stderr 那 10 字节在" || no "stderr 应有内容"
echo

echo "=== 6 节  内部路径 ==="
printf 'ABCDEFGH' > data.txt
eq "fdshow 读后位置 1/0/1（dup 共享，第二次 open 独立）" \
   "$(./fdshow | sed -n '/读之后/,$p' | grep -oE 'pos:[[:space:]]+[0-9]+' | field_int_all)" "1 0 1"
./forkfd > forkfd.out
eq "fork 后父子共享 f_pos：AAAAAchildPAREN" "$(cat shared.txt)" "AAAAAchildPAREN"
if [ "$HAVE_STRACE" = 1 ]; then
	strace -f -e trace=open,openat -o to.txt ./dup2_printf z.txt
	eq "源码写 open，strace 里 open( 出现 0 次" "$(grep -c 'open(' to.txt)" "0"
	OT=$(grep -c 'openat(' to.txt)
	[ "$OT" -ge 1 ] && ok "实际发的是 openat（$OT 次）" || no "应有 openat"
else
	skip "openat 判据 2 条（没装 strace）"
fi
echo

echo "=== 7 节  mmap ==="
: > e0.bin
eq "长度 0 的 mmap 返回 MAP_FAILED，errno 22" "$(./mmap_empty e0.bin | sed 's/^p=[^ ]* //')" "MAP_FAILED=1 errno=22 Invalid argument"
eq "映射第一页内、文件外读到 0" "$(./sigbus tiny.bin 0 | sed -n 2p | grep -oE '= *-?[0-9]+' | field_int)" "0"
./sigbus tiny.bin 1 > /dev/null 2>&1; RC=$?
eq "越过文件末尾所在页：SIGBUS，退出码 135" "$RC" "135"
SP=$(./shared_private .)
eq "MAP_SHARED 写进了文件" "$(echo "$SP" | grep 'MAP_SHARED.*最终' | grep -oE '[AB]{10}')" "BBBBBAAAAA"
eq "MAP_PRIVATE 没写进文件" "$(echo "$SP" | grep 'MAP_PRIVATE.*最终' | grep -oE '[AB]{10}')" "AAAAAAAAAA"
head -c 8388608 /dev/urandom > big8.bin
./cp_rw big8.bin c1.bin
./cp_mmap big8.bin c2.bin
if cmp -s big8.bin c1.bin && cmp -s big8.bin c2.bin; then
	ok "read/write 版与 mmap 版拷贝都逐字节一致"
else
	no "两种拷贝应都一致"
fi
if [ "$HAVE_STRACE" = 1 ]; then
	strace -f -e trace=read,write -o t1.txt ./cp_rw big8.bin c1.bin
	strace -f -e trace=read,write -o t2.txt ./cp_mmap big8.bin c2.bin
	eq "cp_rw 发 2048 次 write" "$(grep -cE '(^|[0-9]+ +)write\(' t1.txt)" "2048"
	R1=$(grep -cE '(^|[0-9]+ +)read\(' t1.txt)
	if [ "$R1" -ge 2049 ] && [ "$R1" -le 2060 ]; then
		ok "cp_rw 发约 2049 次 read（实得 $R1，含加载器）"
	else
		no "cp_rw read 次数应在 2049 附近" "$R1"
	fi
	eq "cp_mmap 只发 1 次 write" "$(grep -cE '(^|[0-9]+ +)write\(' t2.txt)" "1"
else
	skip "mmap 系统调用计数 3 条（没装 strace）"
fi
echo

echo "======================================"
printf '  %d PASS / %d FAIL / %d SKIP\n' "$PASS" "$FAIL" "$SKIP"
echo "======================================"
[ "$FAIL" -eq 0 ]
