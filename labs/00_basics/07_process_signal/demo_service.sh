#!/bin/sh
# 08 篇（进程与信号）实验 5：一个 init.d 风格的启停脚本
#
# 用法：sh demo_service.sh start
#       sh demo_service.sh stop-naive     照出厂脚本那样 killall 一下就返回
#       sh demo_service.sh stop           发 SIGTERM 后等进程真的消失，超时再 SIGKILL
#
# 被管理的程序是同目录的 slowstop（收到 SIGTERM 要 2 秒才退出）。

DIR=$(cd "$(dirname "$0")" && pwd)
PIDFILE=${PIDFILE:-$DIR/.slowstop.pid}

start() {
	"$DIR/slowstop" > "$DIR/.slowstop.log" 2>&1 &	# & 放到后台，脚本自己马上结束
	echo $! > "$PIDFILE"				# $! 是刚放到后台的那个进程的 PID
	echo "start: pid=$(cat "$PIDFILE")"
}

stop_naive() {
	killall slowstop				# 只是发了 SIGTERM
	echo "stop-naive 返回时: pidof=[$(pidof slowstop)]"
}

stop() {
	pid=$(cat "$PIDFILE" 2>/dev/null) || { echo "stop: 没有 pid 文件"; return 1; }
	kill "$pid" 2>/dev/null
	n=0
	while [ -d /proc/"$pid" ] && [ "$n" -lt 50 ]; do	# 最多等 50 x 0.1 秒
		sleep 0.1
		n=$((n + 1))
	done
	if [ -d /proc/"$pid" ]; then
		kill -9 "$pid"
		echo "stop: 5 秒没退出，发了 SIGKILL"
	fi
	rm -f "$PIDFILE"
	echo "stop 返回时: 等了约 $((n * 100)) ms, pidof=[$(pidof slowstop)]"
}

case "$1" in
start)		start ;;
stop-naive)	stop_naive ;;
stop)		stop ;;
*)		echo "用法: $0 start|stop-naive|stop"; exit 2 ;;
esac
