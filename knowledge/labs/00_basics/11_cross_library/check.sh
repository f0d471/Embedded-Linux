#!/bin/bash
# 00_基础 第 12 篇（第三方库交叉构建与部署）的判据自动核对

set -u
SRC=$(cd "$(dirname "$0")" && pwd)
CROSS_PREFIX=${CROSS_PREFIX:-arm-linux-gnueabihf-}
PASS=0; FAIL=0; SKIP=0
ok() { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
no() { FAIL=$((FAIL+1)); printf '  FAIL  %s\n        %s\n' "$1" "$2"; }
skip() { SKIP=$((SKIP+1)); printf '  SKIP  %s（%s）\n' "$1" "$2"; }
eq() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "期望 [$3]，实得 [$2]"; fi; }

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
cp -r "$SRC/upstream" "$W/native"
mkdir -p "$W/stage"

echo "=== 本机库：暂存安装，不污染 /usr ==="
make -C "$W/native" clean all >/dev/null || { no "构建本机库" "make 失败"; exit 1; }
make -C "$W/native" DESTDIR="$W/stage" PREFIX=/usr install >/dev/null || exit 1
eq "头文件装进 stage/usr/include" "$([ -f "$W/stage/usr/include/answer.h" ] && echo yes || echo no)" "yes"
eq "真实库文件装进 stage/usr/lib" "$([ -f "$W/stage/usr/lib/libanswer.so.1.0" ] && echo yes || echo no)" "yes"
eq "链接名 libanswer.so 仍是符号链接" "$([ -L "$W/stage/usr/lib/libanswer.so" ] && echo yes || echo no)" "yes"
eq "SONAME 链接 libanswer.so.1 仍是符号链接" "$([ -L "$W/stage/usr/lib/libanswer.so.1" ] && echo yes || echo no)" "yes"

echo "=== 三次找东西发生在三个时刻 ==="
BAD=$(gcc -Wall -Wextra -Werror -o "$W/app" "$SRC/app.c" 2>&1 || true)
eq "不加 -I，编译期先报 answer.h 找不到" "$(echo "$BAD" | grep -c 'answer.h.*No such file')" "1"
BAD=$(gcc -Wall -Wextra -Werror -I"$W/stage/usr/include" -o "$W/app" "$SRC/app.c" -lanswer 2>&1 || true)
eq "只有 -I 没有 -L，链接期报 -lanswer 找不到" "$(echo "$BAD" | grep -c 'cannot find -lanswer')" "1"
gcc -Wall -Wextra -Werror -I"$W/stage/usr/include" -L"$W/stage/usr/lib" -o "$W/app" "$SRC/app.c" -lanswer || exit 1
eq "ELF 记录的是 SONAME，不是构建机绝对路径" "$(readelf -d "$W/app" | sed -n 's/.*Shared library: \[\(libanswer[^]]*\)\].*/\1/p')" "libanswer.so.1"
BAD=$("$W/app" 2>&1 || true)
eq "运行时没指路，加载器报 libanswer.so.1 找不到" "$(echo "$BAD" | grep -c 'libanswer.so.1.*cannot open shared object file')" "1"
eq "LD_LIBRARY_PATH 只解决运行时找库" "$(LD_LIBRARY_PATH="$W/stage/usr/lib" "$W/app")" "answer=42"

echo "=== ARM 库：产物架构跟 CC 走 ==="
if command -v "${CROSS_PREFIX}gcc" >/dev/null 2>&1; then
	cp -r "$SRC/upstream" "$W/arm"
	mkdir -p "$W/arm-stage"
	make -C "$W/arm" clean all CC="${CROSS_PREFIX}gcc" >/dev/null || exit 1
	make -C "$W/arm" DESTDIR="$W/arm-stage" PREFIX=/usr install >/dev/null || exit 1
	eq "ARM 共享库的 ELF Machine" "$(readelf -h "$W/arm-stage/usr/lib/libanswer.so.1.0" | sed -n 's/^ *Machine: *//p')" "ARM"
	BAD=$(gcc -Wall -Wextra -Werror -I"$W/arm-stage/usr/include" -L"$W/arm-stage/usr/lib" -o "$W/wrong" "$SRC/app.c" -lanswer 2>&1 || true)
	N=$(echo "$BAD" | grep -Ec 'skipping incompatible|file in wrong format')
	if [ "$N" -gt 0 ]; then
		ok "注错见红：x86 链接器拒绝 ARM 库（$N 行架构不兼容证据）"
	else
		no "注错见红：x86 链接器应拒绝 ARM 库" "没有看到架构不兼容错误"
	fi
	"${CROSS_PREFIX}gcc" -Wall -Wextra -Werror -I"$W/arm-stage/usr/include" -L"$W/arm-stage/usr/lib" -o "$W/app-arm" "$SRC/app.c" -lanswer || exit 1
	eq "ARM 应用的 ELF Machine" "$(readelf -h "$W/app-arm" | sed -n 's/^ *Machine: *//p')" "ARM"
	eq "ARM 应用也只记 SONAME" "$(readelf -d "$W/app-arm" | sed -n 's/.*Shared library: \[\(libanswer[^]]*\)\].*/\1/p')" "libanswer.so.1"
else
	skip "ARM 交叉构建一组" "没装 ${CROSS_PREFIX}gcc"
fi

echo "======================================"
printf '  %d PASS / %d FAIL / %d SKIP\n' "$PASS" "$FAIL" "$SKIP"
echo "======================================"
[ "$FAIL" -eq 0 ]
