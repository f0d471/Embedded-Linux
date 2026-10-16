#!/bin/bash
# 00_基础 第 06 篇（文件描述符与 VFS）的判据自动核对
#
# 用法：bash check.sh
# 注错见红：改坏任意一处（比如把 dup 改成 open），必须有判据变红。

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
for p in fdshow logredir forkfd append vfs; do
	gcc $p.c -o $p || die "$p.c 编译不过"
done
echo "  完成"
echo

echo "=== 06 篇 2.5  fd 是下标，中间还有一层 ==="
OUT=$(./fdshow)
eq "open 发的是最小空闲编号 3/4/5" \
   "$(echo "$OUT" | sed -n '1p' | grep -oE 'fd1=[0-9]+ fd2=[0-9]+ fd3=[0-9]+')" \
   "fd1=3 fd2=4 fd3=5"

# 读之后三个 pos：期望 1 / 0 / 1
POSES=$(echo "$OUT" | awk '/\[读之后\]/{f=1} f&&/^  fd /{gsub(/.*pos:[ \t]*/,""); gsub(/[ \t].*/,""); printf "%s ", $0}')
eq "读之后三个 pos 是 1 / 0 / 1（dup 的那个跟着动了）" "$POSES" "1 0 1 "

PRE=$(echo "$OUT" | awk '/\[读之前\]/{f=1} /\[读之后\]/{f=0} f&&/^  fd /{gsub(/.*pos:[ \t]*/,""); gsub(/[ \t].*/,""); printf "%s ", $0}')
eq "读之前三个 pos 全是 0" "$PRE" "0 0 0 "
echo

echo "=== 06 篇 4.6  让 stderr 从终端改写到文件 ==="
rm -f log.txt
TERM_OUT=$(./logredir 2>&1)
echo "$TERM_OUT" | grep -q '1. 重定向之前' && ok "第 1 行留在终端" || no "第 1 行应在终端"
echo "$TERM_OUT" | grep -q '3. 重定向之后' && no "第 3 行不该出现在终端" || ok "第 3 行没出现在终端"
grep -q '3. 重定向之后' log.txt && ok "第 3 行进了 log.txt" || no "log.txt 里应有第 3 行"
eq "log.txt 里有两行（含库函数那行）" "$(wc -l < log.txt)" "2"
grep -q 'worker' log.txt && ok "worker() 一个字没改，输出跟着换了地方" || no "log.txt 里应有 worker"
echo

echo "=== 06 篇 5.5  fork 共享 f_pos ==="
./forkfd > /dev/null
eq "父子不互相覆盖，文件是 15 字节" "$(stat -c %s shared.txt)" "15"
eq "内容是 AAAAAchildPAREN" "$(cat shared.txt)" "AAAAAchildPAREN"
echo

echo "=== 06 篇 6.5  O_APPEND 的原子性 ==="
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

echo "=== 06 篇 7.6  VFS：同一段代码，四种下场 ==="
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

rm -rf /tmp/red
echo "======================================"
printf '  %d PASS / %d FAIL / %d SKIP\n' "$PASS" "$FAIL" "$SKIP"
echo "======================================"
[ "$FAIL" -eq 0 ]
