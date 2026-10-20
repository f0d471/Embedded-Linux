#!/bin/bash
# 00_basics 第 08 篇(文件描述符与 VFS)的判据自动核对
#
# 用法: bash check.sh
# 注错见红: 改坏任意一处(比如把 dup 改成 open), 必须有判据变红。

cd "$(dirname "$0")" || exit 1

PASS=0; FAIL=0; SKIP=0
ok()   { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
no()   { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -n "$2" ] && printf '        %s\n' "$2"; }
skip() { SKIP=$((SKIP+1)); printf '  SKIP  %s\n' "$1"; }
eq()   { if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "期望 $3，实得 $2"; fi; }

die() {
	FAIL=$((FAIL+1))
	printf '  FAIL  构建：%s\n\n  %d PASS / %d FAIL / %d SKIP（构建没过）\n' "$1" "$PASS" "$FAIL" "$SKIP"
	exit 1
}

echo "=== 构建 ==="
printf 'abcdefghij' > data.txt
printf 'aaaaaaaaaa' > one.txt
printf 'BBBBBBBBBB' > two.txt
for p in fdshow fdproc logredir forkfd append flagshare cloexec vfs; do
	gcc $p.c -o $p || die "$p.c 编译不过"
done
echo "  完成"
echo

echo "=== 08 篇 1.3  每个进程一张 fd 表 ==="
O1=$(./fdproc one.txt)
O2=$(./fdproc two.txt)
F1=$(echo "$O1" | sed -n '1p' | grep -oE 'fd=[0-9]+')
F2=$(echo "$O2" | sed -n '1p' | grep -oE 'fd=[0-9]+')
eq "两个进程 open 得到的都是 fd=3" "$F1 $F2" "fd=3 fd=3"
P1=$(echo "$O1" | sed -n '1p' | grep -oE 'pid=[0-9]+')
P2=$(echo "$O2" | sed -n '1p' | grep -oE 'pid=[0-9]+')
if [ "$P1" != "$P2" ]; then ok "两个进程 pid 不同（$P1 / $P2）"; else no "两个进程 pid 应不同"; fi
T1=$(echo "$O1" | grep -oE 'fd 3 -> .*' )
T2=$(echo "$O2" | grep -oE 'fd 3 -> .*' )
if [ "$T1" != "$T2" ] && echo "$T1" | grep -q 'one.txt' && echo "$T2" | grep -q 'two.txt'; then
	ok "同一个编号 3, 各指各的文件"
else
	no "同一个编号 3, 各指各的文件" "$T1 | $T2"
fi
eq "fdproc 列出 0/1/2/3 共 4 格" "$(echo "$O1" | grep -cE '^  fd [0-9]+ -> ')" "4"
echo

echo "=== 08 篇 2.4  strace: 发出去的是 openat 不是 open ==="
if command -v strace >/dev/null 2>&1; then
	strace -f -e trace=open,openat -o /tmp/f08-st.txt ./fdproc data.txt >/dev/null
	NO=$(grep -c 'openat(' /tmp/f08-st.txt)
	NN=$(grep -c 'open(' /tmp/f08-st.txt)
	if [ "$NO" -ge 1 ]; then ok "strace 抓到 openat（$NO 次）"; else no "应抓到 openat"; fi
	eq "没有裸 open( 调用" "$NN" "0"
	rm -f /tmp/f08-st.txt
else
	skip "strace 不在，跳过 openat 核对"
	skip "strace 不在，跳过 openat 核对"
fi
echo

echo "=== 08 篇 0/2.1  fd 是下标，中间还有一层 ==="
OUT=$(./fdshow)
eq "open 发的是最小空闲编号 3/4/5" \
   "$(echo "$OUT" | sed -n '1p' | grep -oE 'fd1=[0-9]+ fd2=[0-9]+ fd3=[0-9]+')" \
   "fd1=3 fd2=4 fd3=5"

# 读之后三个 pos：期望 1 / 0 / 1
POSES=$(echo "$OUT" | awk '/\[读之后\]/{f=1} f&&/^  fd /{gsub(/.*pos:[ \t]*/,""); gsub(/[ \t].*/,""); printf "%s ", $0}')
eq "读之后三个 pos 是 1 / 0 / 1（dup 的那个跟着动了）" "$POSES" "1 0 1 "

PRE=$(echo "$OUT" | awk '/\[读之前\]/{f=1} /\[读之后\]/{f=0} f&&/^  fd /{gsub(/.*pos:[ \t]*/,""); gsub(/[ \t].*/,""); printf "%s ", $0}')
eq "读之前三个 pos 全是 0" "$PRE" "0 0 0 "
eq "fdinfo 的 flags 列是八进制 0100000（O_LARGEFILE）" \
   "$(echo "$OUT" | grep -c 'flags:.0100000')" "6"
echo

echo "=== 08 篇 4  让 stderr 从终端改写到文件 ==="
rm -f log.txt
TERM_OUT=$(./logredir 2>&1)
echo "$TERM_OUT" | grep -q '1. 重定向之前' && ok "第 1 行留在终端" || no "第 1 行应在终端"
echo "$TERM_OUT" | grep -q '3. 重定向之后' && no "第 3 行不该出现在终端" || ok "第 3 行没出现在终端"
grep -q '3. 重定向之后' log.txt && ok "第 3 行进了 log.txt" || no "log.txt 里应有第 3 行"
eq "log.txt 里有两行（含库函数那行）" "$(wc -l < log.txt)" "2"
grep -q 'worker' log.txt && ok "worker() 一个字没改，输出跟着换了地方" || no "log.txt 里应有 worker"
echo

echo "=== 08 篇 3.2  fork 共享 f_pos ==="
./forkfd > /dev/null
eq "父子不互相覆盖，文件是 15 字节" "$(stat -c %s shared.txt)" "15"
eq "内容是 AAAAAchildPAREN" "$(cat shared.txt)" "AAAAAchildPAREN"
echo

echo "=== 08 篇 5.2  O_APPEND 的原子性 ==="
AOK=1
for i in 1 2 3; do
	N=$(./append append | grep -oE '实际 [0-9]+' | grep -oE '[0-9]+')
	[ "$N" = "68000" ] || AOK=0
done
[ "$AOK" = 1 ] && ok "append 模式三轮都精确 68000 字节" || no "append 模式应每轮都是 68000"

L1=$(./append lseek | grep -oE '实际 [0-9]+' | grep -oE '[0-9]+')
L2=$(./append lseek | grep -oE '实际 [0-9]+' | grep -oE '[0-9]+')
L3=$(./append lseek | grep -oE '实际 [0-9]+' | grep -oE '[0-9]+')
if [ "$L1" -lt 68000 ] && [ "$L2" -lt 68000 ] && [ "$L3" -lt 68000 ]; then
	ok "lseek 模式三轮都丢了数据（$L1 / $L2 / $L3）"
else
	no "lseek 模式应该丢数据" "$L1 / $L2 / $L3"
fi
if [ "$L1" != "$L2" ] || [ "$L2" != "$L3" ]; then
	ok "lseek 模式每轮结果都不同（竞态的典型特征）"
else
	no "三轮结果相同，竞态没触发；试试把 N 调大"
fi
echo

echo "=== 08 篇 5.3  O_APPEND 记在 struct file 上 ==="
FS=$(./flagshare)
BEF=$(echo "$FS" | awk '/F_SETFL 之前/{f=1;next} /之后/{f=0} f' | grep -c 'flags:.0100001')
eq "F_SETFL 之前两格 flags 都是 0100001" "$BEF" "2"
AFT=$(echo "$FS" | awk '/F_SETFL O_APPEND 之后/{f=1;next} /拨回/{f=0} f' | grep -c 'flags:.0102001')
eq "只对 fd1 设 O_APPEND, fd2 的 flags 也变成 0102001" "$AFT" "2"
ENDP=$(echo "$FS" | awk '/拨回 0 后写/{f=1} f' | grep -c 'pos:.6 ')
eq "fd2 拨回 0 写完后, 两格 pos 都是 6（定位与写合一）" "$ENDP" "2"
eq "flag.txt 内容是 AAAAAZ（没有盖掉开头）" "$(cat flag.txt)" "AAAAAZ"
echo

echo "=== 08 篇 5.4  O_CLOEXEC 记在 fd 格子上 ==="
CE=$(./cloexec)
eq "F_GETFD: fd1=1 fd2=0" \
   "$(echo "$CE" | grep -oE 'F_GETFD: fd1=[0-9]+ fd2=[0-9]+')" \
   "F_GETFD: fd1=1 fd2=0"
eq "fdinfo 的 flags 列也分开了: fd1=02100000 fd2=0100000" \
   "$(echo "$CE" | grep -oE 'fdinfo: fd [34] 的 flags:.*' | tr '\t' ' ' | tr '\n' ' ')" \
   "fdinfo: fd 3 的 flags: 02100000 fdinfo: fd 4 的 flags: 0100000 "
eq "exec 之后: fd 3 已关闭, fd 4 还在" \
   "$(echo "$CE" | grep -oE 'exec 之后: .*')" \
   "exec 之后: fd 3 已关闭, fd 4 还在"
echo

echo "=== 08 篇 6.2  VFS：同一段代码，四种下场 ==="
V=$(./vfs < /dev/null)
sec() { echo "$V" | awk -v p="--- $1 ---" '$0==p{f=1;next} /^--- /{f=0} f'; }

eq "普通文件 write 返回 5"        "$(sec data.txt   | grep -oE 'write.*返回 [0-9-]+' | grep -oE '[0-9-]+$')" "5"
eq "普通文件 read 读回 hello"     "$(sec data.txt   | grep -oE '内容 "[^"]*"')" '内容 "hello"'
eq "/dev/null 的 read 返回 0（永远 EOF）" \
   "$(sec /dev/null | grep -oE 'read.*返回 [0-9-]+' | grep -oE '[0-9-]+$')" "0"
eq "/dev/null 没动过 buf（还是那些点）" \
   "$(sec /dev/null | grep -oE '内容 "[^"]*"')" '内容 "....."'
eq "/dev/zero 的 read 返回 5（读到 5 个 \\0）" \
   "$(sec /dev/zero | grep -oE 'read.*返回 [0-9-]+' | grep -oE '[0-9-]+$')" "5"

TTYOK=$(sec /dev/tty | grep -c 'ioctl.*成功')
NULLOK=$(sec /dev/null | grep -c 'ioctl.*失败')
if [ -n "$(sec /dev/tty)" ]; then
	eq "只有 /dev/tty 的 ioctl(TIOCGWINSZ) 成功" "$TTYOK" "1"
else
	skip "/dev/tty 打不开（没有控制终端时会这样）"
fi
eq "/dev/null 的 ioctl 报 ENOTTY" "$NULLOK" "1"
echo

echo "======================================"
printf '  %d PASS / %d FAIL / %d SKIP\n' "$PASS" "$FAIL" "$SKIP"
echo "======================================"
[ "$FAIL" -eq 0 ]
