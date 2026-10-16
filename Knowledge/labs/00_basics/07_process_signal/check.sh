#!/bin/bash
# 00_基础 第 08 篇（进程与信号）的判据自动核对
#
# 用法：bash check.sh
# 普通用户即可。大约 20 秒：有几条判据要等进程自己退出。

cd "$(dirname "$0")" || exit 1

PASS=0; FAIL=0; SKIP=0
ok()   { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
no()   { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -n "$2" ] && printf '        %s\n' "$2"; }
skip() { SKIP=$((SKIP+1)); printf '  SKIP  %s\n' "$1"; }
eq()   { if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "期望 [$3]，实得 [$2]"; fi; }
lt()   { if awk "BEGIN{exit !($2 < $3)}"; then ok "$1"; else no "$1" "$2 应当小于 $3"; fi; }
ge()   { if awk "BEGIN{exit !($2 >= $3)}"; then ok "$1"; else no "$1" "$2 应当不小于 $3"; fi; }

die() {
	FAIL=$((FAIL+1))
	printf '  FAIL  构建：%s\n\n  %d PASS / %d FAIL / %d SKIP（构建没过）\n' "$1" "$PASS" "$FAIL" "$SKIP"
	exit 1
}

cleanup() {
	pkill -x hold 2>/dev/null; pkill -x slowstop 2>/dev/null
	rm -f a_very_long_program_name .waiter_bug .slowstop_nh .zombie_reap
	rm -f .h1.log .h2.log .z.log .o.log .slowstop.log ..slowstop_nh.log .slowstop.pid
	rm -f .sig.c .sig.o
}
trap cleanup EXIT

echo "=== 构建 ==="
gcc -Wall -o hold hold.c          || die "hold.c 编译不过"
gcc -Wall -o child child.c        || die "child.c 编译不过"
gcc -Wall -o waiter waiter.c      || die "waiter.c 编译不过"
gcc -Wall -o slowstop slowstop.c  || die "slowstop.c 编译不过"
gcc -Wall -o zombie zombie.c      || die "zombie.c 编译不过"
gcc -Wall -o orphan orphan.c      || die "orphan.c 编译不过"
gcc -Wall -DBUG_ONLY_EXITSTATUS -o .waiter_bug waiter.c || die "waiter.c 注错版编译不过"
gcc -Wall -DNO_HANDLER -o .slowstop_nh slowstop.c       || die "slowstop.c 注错版编译不过"
gcc -Wall -DREAP_NOW -o .zombie_reap zombie.c           || die "zombie.c 注错版编译不过"
echo "  完成"
echo

echo "=== 08 篇 二  进程是内核里的一份档案 ==="
./hold > .h1.log & P1=$!
./hold > .h2.log & P2=$!
sleep 0.2
if [ "$P1" != "$P2" ]; then ok "同一个程序跑两次，得到两个不同的 PID（$P1 / $P2）"; else no "两个 PID 应当不同"; fi
eq "两个进程的 /proc/<pid>/exe 指向同一个文件" "$(readlink /proc/$P1/exe)" "$(readlink /proc/$P2/exe)"
eq "status 里的 PPid 就是启动它的这个 shell" "$(awk '/^PPid:/{print $2}' /proc/$P1/status)" "$$"
eq "程序自己打印的 pid 和 \$! 一致" "$(grep -oE '^pid=[0-9]+' .h1.log)" "pid=$P1"
eq "pidof hold 找到 2 个" "$(pidof hold | wc -w)" "2"
kill $P1; wait $P1 2>/dev/null
eq "注错见红：杀掉一个之后 pidof hold 只剩 1 个" "$(pidof hold | wc -w)" "1"
kill $P2; wait $P2 2>/dev/null
echo

echo "=== 08 篇 二  名字不是身份证 ==="
cp hold a_very_long_program_name
./a_very_long_program_name > /dev/null & P=$!
sleep 0.2
eq "/proc/<pid>/comm 被截成 15 个字符" "$(cat /proc/$P/comm)" "a_very_long_pro"
eq "pidof 用全名能找到" "$(pidof a_very_long_program_name)" "$P"
eq "pidof 用截断后的名字找不到" "$(pidof a_very_long_pro)" ""
eq "pgrep 用截断后的名字能找到" "$(pgrep a_very_long_pro)" "$P"
eq "pgrep 用全名找不到" "$(pgrep a_very_long_program_name 2>/dev/null)" ""
eq "pgrep -f 按完整命令行能找到" "$(pgrep -f a_very_long_program_name)" "$P"
eq "放进 sh -c 里跑 pgrep -f，那个 sh 自己也被算进去" "$(sh -c 'pgrep -f a_very_long_program_name' | wc -l)" "2"
kill $P; wait $P 2>/dev/null
echo

echo "=== 08 篇 三  退出码与信号 ==="
./child exit 3;                        eq "exit(3) 之后 \$? 是 3" "$?" "3"
./child exit 139;                      RC_EXIT=$?; eq "exit(139) 之后 \$? 是 139" "$RC_EXIT" "139"
# 多套一层 bash 并在末尾补 exit：崩溃提示由里层 bash 打到它自己的 stderr（已丢掉），外层只拿退出码
bash -c './child segv; exit $?' >/dev/null 2>&1; RC_SEGV=$?; eq "段错误之后 \$? 是 139（128+11）" "$RC_SEGV" "139"
bash -c './child term; exit $?' >/dev/null 2>&1; eq "被 SIGTERM 杀掉之后 \$? 是 143（128+15）" "$?" "143"
eq "只看 \$?，分不出 exit(139) 和段错误" "$RC_EXIT" "$RC_SEGV"

W1=$(./waiter ./child exit 139)
W2=$(./waiter ./child segv)
W3=$(./waiter ./child term)
eq "waitpid 拿到的状态字：exit(139) 是 0x8b00" "$(echo "$W1" | grep -oE '0x[0-9a-f]{4}')" "0x8b00"
eq "waitpid 拿到的状态字：段错误是 0x000b"     "$(echo "$W2" | grep -oE '0x[0-9a-f]{4}')" "0x000b"
echo "$W1" | grep -q "正常退出，退出码 139" && ok "waiter 把 exit(139) 认成正常退出" || no "waiter 应认出 exit(139) 是正常退出" "$W1"
echo "$W2" | grep -q "被信号 11"           && ok "waiter 把段错误认成被信号 11 杀死" || no "waiter 应认出信号 11" "$W2"
echo "$W3" | grep -q "被信号 15"           && ok "waiter 把 SIGTERM 认成被信号 15 杀死" || no "waiter 应认出信号 15" "$W3"
eq "注错见红：只取退出码，段错误被报成退出码 0" "$(./.waiter_bug ./child segv | grep -oE '退出码 [0-9]+')" "退出码 0"

# 板子是 ARM：用交叉编译器把信号编号变成数组长度，nm -S 读出来和 x86 比（[基础 03] 的办法）
sigsizes() {
	"$1" -c .sig.c -o .sig.o && nm -S --defined-only .sig.o |
		while read -r _ size _ name; do
			case "$name" in s_*) echo "$name $((16#$size))" ;; esac
		done | sort
}
if command -v arm-linux-gnueabihf-gcc >/dev/null 2>&1; then
	printf '#include <signal.h>\nchar s_int[SIGINT], s_bus[SIGBUS], s_kill[SIGKILL], s_segv[SIGSEGV],\n     s_term[SIGTERM], s_chld[SIGCHLD], s_stop[SIGSTOP];\n' > .sig.c
	SX=$(sigsizes gcc)
	SA=$(sigsizes arm-linux-gnueabihf-gcc)
	eq "SIGTERM 是 15、SIGSEGV 是 11" "$(echo "$SX" | awk '$1 == "s_term" || $1 == "s_segv" {printf "%s ", $2}')" "11 15 "
	eq "7 个常用信号的编号，x86 和 ARM 头文件里一样" "$SA" "$SX"
else
	skip "没有 arm-linux-gnueabihf-gcc，比不了 ARM 的信号编号"
fi
echo

echo "=== 08 篇 四  kill 只是递了一张通知 ==="
measure() {
	./$1 > .$1.log 2>&1 & MP=$!
	sleep 0.5
	local t0 t1 n=0
	t0=$(date +%s%N)
	kill -"$2" $MP
	while [ -e /proc/$MP ] && [ $n -lt 1000 ]; do sleep 0.01; n=$((n + 1)); done
	t1=$(date +%s%N)
	wait $MP 2>/dev/null; RC=$?
	MS=$(( (t1 - t0) / 1000000 ))
}
measure slowstop TERM
ge "装了处理函数：SIGTERM 之后又活了 1800 ms 以上（$MS ms）" "$MS" "1800"
eq "收拾完自己退出，退出码 0" "$RC" "0"
grep -q "收拾完，退出" .slowstop.log && ok "日志里有“收拾完，退出”" || no "日志里应有“收拾完，退出”"
grep -q "给 SIGKILL 装处理函数: 失败 (Invalid argument)" .slowstop.log \
	&& ok "给 SIGKILL 装处理函数被内核拒绝（EINVAL）" || no "给 SIGKILL 装处理函数应当失败"
measure slowstop KILL 2>/dev/null
lt "SIGKILL：200 ms 内消失（$MS ms）" "$MS" "200"
eq "SIGKILL 的退出码 137（128+9）" "$RC" "137"
measure .slowstop_nh TERM
lt "注错见红：不装处理函数，SIGTERM 之后 200 ms 内消失（$MS ms）" "$MS" "200"
eq "注错见红：不装处理函数，退出码是 143" "$RC" "143"
echo

echo "=== 08 篇 五  僵尸与孤儿 ==="
./zombie > .z.log & P=$!
sleep 1
ST=$(ps -o stat= --ppid $P | tr -d ' ')
case "$ST" in
Z*) ok "子进程已结束、父进程还没 waitpid：状态是 Z（$ST）" ;;
*)  no "子进程此时应当是僵尸" "ps 看到的状态是 [$ST]" ;;
esac
eq "pidof zombie 不算僵尸，只找到父进程" "$(pidof zombie)" "$P"
sleep 3
eq "父进程 waitpid 之后，僵尸消失" "$(ps -o pid= --ppid $P | wc -l)" "0"
wait $P
./.zombie_reap > /dev/null & P=$!
sleep 1
eq "注错见红：父进程马上 waitpid，1 秒时没有僵尸" "$(ps -o pid= --ppid $P | wc -l)" "0"
kill $P; wait $P 2>/dev/null

./orphan > .o.log
sleep 1.5
PARENT=$(grep -oE '^父 [0-9]+' .o.log | grep -oE '[0-9]+')
BEFORE=$(grep '父进程退出前' .o.log | grep -oE '父进程 [0-9]+' | grep -oE '[0-9]+')
AFTER=$(grep '父进程退出后' .o.log | grep -oE '父进程 [0-9]+' | grep -oE '[0-9]+')
eq "父进程退出前，子进程的 ppid 就是 orphan" "$BEFORE" "$PARENT"
if [ -n "$AFTER" ] && [ "$AFTER" != "$PARENT" ]; then
	ok "父进程退出后，子进程换了一个父进程（$AFTER）"
else
	no "父进程退出后 ppid 应当变掉" "$(cat .o.log)"
fi
if grep -q '父进程退出后.*(Relay' .o.log; then
	ok "WSL 里接手的是 Relay，不是 1 号进程"
elif [ "$AFTER" = "1" ]; then
	ok "接手的是 1 号进程"
else
	skip "接手的既不是 Relay 也不是 1 号（$(grep '父进程退出后' .o.log)）"
fi
echo

echo "=== 08 篇 六  启停脚本：stop 要等到进程真的消失 ==="
sh demo_service.sh start > /dev/null
sleep 0.5
OUT=$(sh demo_service.sh stop-naive)
echo "$OUT" | grep -qE 'pidof=\[[0-9]+\]' && ok "只 killall 就返回：返回那一刻进程还在" || no "stop-naive 返回时进程应当还在" "$OUT"
sleep 3
eq "3 秒后进程才真的没了" "$(pidof slowstop)" ""
sh demo_service.sh start > /dev/null
sleep 0.5
OUT=$(sh demo_service.sh stop)
echo "$OUT" | grep -q 'pidof=\[\]' && ok "等待型 stop：返回时 pidof 已经是空的" || no "stop 返回时进程应当已经消失" "$OUT"
WAITED=$(echo "$OUT" | grep -oE '等了约 [0-9]+' | grep -oE '[0-9]+')
ge "等待型 stop 确实等了（约 $WAITED ms）" "${WAITED:-0}" "1800"
echo

echo "======================================"
printf '  %d PASS / %d FAIL / %d SKIP\n' "$PASS" "$FAIL" "$SKIP"
echo "======================================"
[ "$FAIL" -eq 0 ]
