#!/bin/bash
# 12 篇（进程与信号）的判据自动核对
#
# 用法：bash check.sh
# 普通用户即可。大约 25 秒：有几条判据要等进程自己退出。

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
	rm -f .sigmask_nm .sigcount_nb .safefunc_rst .safefunc_nh
	rm -f .h1.log .h2.log .z.log .o.log .slowstop.log .slowstop.pid
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
gcc -Wall -o sigmask sigmask.c    || die "sigmask.c 编译不过"
gcc -Wall -o sigcount sigcount.c  || die "sigcount.c 编译不过"
gcc -Wall -o safefunc safefunc.c  || die "safefunc.c 编译不过"
gcc -Wall -o ctrlc ctrlc.c        || die "ctrlc.c 编译不过"
gcc -Wall -DBUG_ONLY_EXITSTATUS -o .waiter_bug waiter.c   || die "waiter.c 注错版编译不过"
gcc -Wall -DNO_HANDLER -o .slowstop_nh slowstop.c         || die "slowstop.c 注错版编译不过"
gcc -Wall -DREAP_NOW -o .zombie_reap zombie.c             || die "zombie.c 注错版编译不过"
gcc -Wall -DNO_MASK -o .sigmask_nm sigmask.c              || die "sigmask.c 注错版编译不过"
gcc -Wall -DNO_BLOCK -o .sigcount_nb sigcount.c           || die "sigcount.c 注错版编译不过"
gcc -Wall -DNO_HANDLER -o .safefunc_nh safefunc.c         || die "safefunc.c 注错版编译不过"
gcc -Wall -DSA_RESTART_DEMO -o .safefunc_rst safefunc.c   || die "safefunc.c 变体编译不过"
echo "  完成"
echo

echo "=== 12 篇 1  同一个程序跑两次，是两份档案 ==="
./hold > .h1.log & P1=$!
./hold > .h2.log & P2=$!
sleep 0.2
if [ "$P1" != "$P2" ]; then ok "同一个程序跑两次，得到两个不同的 PID（$P1 / $P2）"; else no "两个 PID 应当不同"; fi
eq "两个进程的 /proc/<pid>/exe 指向同一个文件" "$(readlink /proc/$P1/exe)" "$(readlink /proc/$P2/exe)"
eq "status 里的 PPid 就是启动它的这个 shell" "$(awk '/^PPid:/{print $2}' /proc/$P1/status)" "$$"
eq "程序自己打印的 pid 和 \$! 一致" "$(grep -oE '^pid=[0-9]+' .h1.log)" "pid=$P1"
eq "status 里的 State 是 S（睡在 pause 里）" "$(awk '/^State:/{print $2}' /proc/$P1/status)" "S"
case "$(cat /proc/$P1/wchan)" in
*pause*) ok "wchan 显示它睡在 pause（$(cat /proc/$P1/wchan)）" ;;
*)       no "wchan 应当含 pause" "$(cat /proc/$P1/wchan)" ;;
esac
eq "后台启动：SIGINT/SIGQUIT 的忽略位随 execve 保留下来（SigIgn=0x6）" \
   "$(awk '/^SigIgn:/{print $2}' /proc/$P1/status | sed 's/^0*//')" "6"
eq "pidof hold 找到 2 个" "$(pidof hold | wc -w)" "2"
kill $P1; wait $P1 2>/dev/null
eq "注错见红：杀掉一个之后 pidof hold 只剩 1 个" "$(pidof hold | wc -w)" "1"
kill $P2; wait $P2 2>/dev/null
if [ ! -e /proc/$P2 ]; then ok "进程结束、父进程收走结果之后，/proc/<pid> 整个消失"; else no "/proc/$P2 应当消失"; fi
echo

echo "=== 12 篇 1  名字不是身份证 ==="
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

echo "=== 12 篇 2  fork/execve/waitpid 的链条 ==="
if command -v strace >/dev/null 2>&1; then
	ST=$(strace -f -e trace=clone,execve,wait4 ./waiter ./child exit 42 2>&1)
	echo "$ST" | grep -q 'clone(' && ok "strace 看到 fork 的真身 clone" || no "应看到 clone" "$ST"
	echo "$ST" | grep -q 'execve("./child"' && ok "strace 看到子进程 execve 换成 child" || no "应看到 execve ./child" "$ST"
	echo "$ST" | grep -q 'WEXITSTATUS(s) == 42' && ok "wait4 返回的状态字被解成退出码 42" || no "wait4 应带回 42" "$ST"
	echo "$ST" | grep -q 'SIGCHLD.*si_status=42' && ok "子进程一死，内核给父进程发 SIGCHLD" || no "应看到 SIGCHLD" "$ST"
else
	skip "没有 strace，看不了 fork/execve/wait4 链条"
	skip "没有 strace，看不了 fork/execve/wait4 链条"
	skip "没有 strace，看不了 fork/execve/wait4 链条"
	skip "没有 strace，看不了 fork/execve/wait4 链条"
fi
echo

echo "=== 12 篇 3  退出码与状态字 ==="
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
echo

echo "=== 12 篇 4  信号从哪来 ==="
eq "kill -l：11 号是 SIGSEGV" "$(kill -l 11)" "SEGV"
eq "kill -l：15 号是 SIGTERM" "$(kill -l 15)" "TERM"

# 板子是 ARM：用交叉编译器把信号编号变成数组长度，nm -S 读出来和 x86 比（和 fundamentals 03 篇同一个办法）
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
	skip "没有 arm-linux-gnueabihf-gcc，比不了 ARM 的信号编号"
fi

if [ "$(id -u)" -eq 0 ]; then
	skip "当前是 root，向 1 号进程发信号真的会递到，不测权限拒绝"
else
	OUT=$(kill -TERM 1 2>&1); RC=$?
	if [ $RC -ne 0 ] && echo "$OUT" | grep -q "Operation not permitted"; then
		ok "给 1 号进程发 SIGTERM 被拒绝（EPERM），kill 返回非 0"
	else
		no "普通用户给 1 号发信号应当被 EPERM 拒绝" "rc=$RC $OUT"
	fi
fi

if command -v script >/dev/null 2>&1; then
	OUT=$( { sleep 0.5; printf '\003'; sleep 0.4; printf '\003'; sleep 0.8; } | timeout 10 script -qec ./ctrlc /dev/null )
	echo "$OUT" | grep -q "收到第 1 次 SIGINT" && echo "$OUT" | grep -q "收到第 2 次 SIGINT" \
		&& ok "伪终端里喂 0x03，行规程把它变成 SIGINT（没走 kill）" \
		|| no "0x03 应当变成两次 SIGINT" "$OUT"
	echo "$OUT" | grep -q "两次都收到，正常退出" && ok "两次 SIGINT 后进程自己正常退出" || no "应正常退出" "$OUT"
	OUT=$( { sleep 0.5; printf '\003\n'; sleep 0.8; } | timeout 10 script -qec 'stty -isig; ./ctrlc raw' /dev/null )
	echo "$OUT" | grep -q "读到 2 个字节: 03 0a" && ok "stty -isig 之后，0x03 退回成普通字节（03 0a）" || no "应读到 03 0a" "$OUT"
else
	skip "没有 script，开不了伪终端，测不了 Ctrl+C"
	skip "没有 script，开不了伪终端，测不了 Ctrl+C"
	skip "没有 script，开不了伪终端，测不了 Ctrl+C"
fi
echo

echo "=== 12 篇 5  kill 只是递了一张通知 ==="
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

echo "=== 12 篇 5  挂起是位图，屏蔽是另一张位图 ==="
OUT=$(./sigcount)
echo "$OUT" | grep -q "已执行 0 次" && ok "屏蔽中连发 5 个 SIGUSR1，处理函数一次都没执行" || no "屏蔽中不应执行" "$OUT"
echo "$OUT" | grep -q "挂着" && ok "sigpending 里看得到挂着的 SIGUSR1" || no "sigpending 应显示挂着" "$OUT"
echo "$OUT" | grep -q "共执行 1 次" && ok "解蔽后只执行 1 次：5 个信号压成位图里的同一位" || no "解蔽后应只执行 1 次" "$OUT"
eq "注错见红：不屏蔽（-DNO_BLOCK），5 个信号执行 5 次" \
   "$(./.sigcount_nb | grep -oE '已执行 [0-9]+ 次')" "已执行 5 次"

OUT=$(./sigmask)
echo "$OUT" | sed -n '/^2)/,/^3)/p' | grep -q 'SigBlk:.*4000$' \
	&& ok "屏蔽之后 SigBlk 里 SIGTERM 位（0x4000）置 1" || no "SigBlk 应含 4000" "$OUT"
echo "$OUT" | grep -q "执行次数: 0" && ok "屏蔽中 raise(SIGTERM)，处理函数不执行" || no "屏蔽中不应执行" "$OUT"
echo "$OUT" | sed -n '/^3)/,/^4)/p' | grep -q 'SigPnd:.*4000$' \
	&& ok "信号在 SigPnd 里挂着（0x4000）" || no "SigPnd 应含 4000" "$OUT"
echo "$OUT" | grep -q "4) 解蔽之后，处理函数执行次数: 1" && ok "解蔽的瞬间处理函数执行" || no "解蔽后应执行 1 次" "$OUT"
eq "注错见红：不屏蔽（-DNO_MASK），raise 当场执行处理函数" \
   "$(./.sigmask_nm | grep -oE '执行次数: [0-9]+' | head -1)" "执行次数: 1"
echo

echo "=== 12 篇 6  处理函数是插进来的执行流 ==="
OUT=$(./safefunc)
eq "闹钟响了 3 次，处理函数执行 3 次" "$(echo "$OUT" | grep -c 'handler.*闹钟响了')" "3"
eq "每次 sleep(3) 都被信号提前打断" "$(echo "$OUT" | grep -c 'sleep(3) 返回，还剩')" "3"
echo "$OUT" | grep -q "处理函数共执行 3 次" && ok "main 正常走完，收尾打印执行次数" || no "应有收尾行" "$OUT"
bash -c './.safefunc_nh; exit $?' >/dev/null 2>&1; RC=$?
eq "注错见红：不装处理函数，第一个 SIGALRM 就杀死进程（142=128+14）" "$RC" "142"
OUT=$(./.safefunc_nh)
echo "$OUT" | grep -q "处理函数共执行" && no "注错见红：不装处理函数，main 走不到收尾" || ok "注错见红：不装处理函数，main 走不到收尾"
OUT=$(./.safefunc_rst)
echo "$OUT" | grep -q 'sleep(3) 返回，还剩' \
	&& ok "加了 SA_RESTART，sleep(3) 照样提前返回（nanosleep 不在重启名单里）" \
	|| no "SA_RESTART 对 sleep 不应生效" "$OUT"
echo

echo "=== 12 篇 7  僵尸与孤儿 ==="
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

echo "=== 12 篇 8  启停脚本：stop 要等到进程真的消失 ==="
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
