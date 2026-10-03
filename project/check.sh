#!/bin/bash
# 总入口：原有框架/display 判据与 font/input 判据分文件维护，这里汇总数字。

set -u
SRC=$(cd "$(dirname "$0")" && pwd)
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT

# WSL 没有真实 framebuffer/evdev；核心框架判据选两个确定性的内存后端。
export DISP_DEV=mem
export FONT_DEV=builtin
export INPUT_BACKEND=replay
export INPUT_REPLAY=/dev/null

# check_core.sh 会把 project/ 复制进 /tmp；依赖包不能再用相对仓库路径。
export FT_TARBALL=${FT_TARBALL:-/mnt/e/Workspace/01_all_series_quickstart-master/04_嵌入式Linux应用开发基础知识/source/10_freetype/freetype-2.10.2.tar.xz}

run_suite() {
	local script=$1 output=$2
	bash "$SRC/$script" 2>&1 | tee "$output"
	return "${PIPESTATUS[0]}"
}

run_suite check_core.sh "$W/core.out"; CORE_RC=$?
run_suite check_font_input.sh "$W/font_input.out"; EXTRA_RC=$?

read_result() {
	sed -n 's/^PASS=\([0-9][0-9]*\)  FAIL=\([0-9][0-9]*\)  SKIP=\([0-9][0-9]*\)$/\1 \2 \3/p' "$1" | tail -1
}

read -r P1 F1 S1 <<<"$(read_result "$W/core.out")"
read -r P2 F2 S2 <<<"$(read_result "$W/font_input.out")"

echo
echo "TOTAL PASS=$((P1 + P2))  FAIL=$((F1 + F2))  SKIP=$((S1 + S2))"
[ "$CORE_RC" -eq 0 ] && [ "$EXTRA_RC" -eq 0 ] && [ "$((F1 + F2))" -eq 0 ]
