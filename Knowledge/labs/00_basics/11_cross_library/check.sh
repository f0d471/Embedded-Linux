#!/bin/bash
# 00_basics 第 14 篇（第三方库的交叉构建与部署）的判据自动核对

set -u
SRC=$(cd "$(dirname "$0")" && pwd)
CROSS_PREFIX=${CROSS_PREFIX:-arm-linux-gnueabihf-}
DEPS=${DEPS:-$HOME/deps}
FT_TARBALL=${FT_TARBALL:-$DEPS/freetype-2.10.2.tar.xz}
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

echo "=== 运行时的另一条路：RUNPATH 烙进 ELF ==="
gcc -Wall -Wextra -Werror -I"$W/stage/usr/include" -L"$W/stage/usr/lib" \
	-Wl,-rpath,"$W/stage/usr/lib" -o "$W/app-rpath" "$SRC/app.c" -lanswer || exit 1
eq "RUNPATH 被写进 ELF 的动态段" "$(readelf -d "$W/app-rpath" | grep -cE 'Library (runpath|rpath): \[.*stage/usr/lib\]')" "1"
eq "不设 LD_LIBRARY_PATH 也能运行" "$("$W/app-rpath")" "answer=42"

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

echo "=== 交叉构建 FreeType 2.10.2：真库全流程 ==="
if [ -f "$FT_TARBALL" ] && command -v "${CROSS_PREFIX}gcc" >/dev/null 2>&1; then
	mkdir -p "$W/ft/src" "$W/ft/build" "$W/ft/stage"
	tar -xJf "$FT_TARBALL" -C "$W/ft/src" || exit 1
	(
		cd "$W/ft/build" || exit 1
		"$W/ft/src/freetype-2.10.2/configure" \
			--build=x86_64-pc-linux-gnu --host=arm-linux-gnueabihf --prefix=/usr \
			--without-zlib --without-bzip2 --without-png \
			--without-harfbuzz --without-brotli > configure.log 2>&1 || exit 1
		make -j2 > make.log 2>&1 || exit 1
		make DESTDIR="$W/ft/stage" install > install.log 2>&1 || exit 1
	) || { no "FreeType 构建安装" "见 $W/ft/build 日志"; exit 1; }
	eq "configure 确认在交叉编译" "$(grep -c 'checking whether we are cross compiling... yes' "$W/ft/build/configure.log")" "1"
	eq "GCC 15 编 2.10.2 只有两条 dangling-pointer 警告" "$(grep -c 'Wdangling-pointer' "$W/ft/build/make.log")" "2"
	eq "libfreetype.so.6.17.2 是 ARM 共享库" "$(readelf -h "$W/ft/stage/usr/lib/libfreetype.so.6.17.2" | sed -n 's/^ *Machine: *//p')" "ARM"
	eq "头文件 ft2build.h 装进 staging" "$([ -f "$W/ft/stage/usr/include/freetype2/ft2build.h" ] && echo yes || echo no)" "yes"
	eq ".pc 的 prefix 是目标路径 /usr" "$(sed -n 's/^prefix=//p' "$W/ft/stage/usr/lib/pkgconfig/freetype2.pc")" "/usr"
	eq "pkg-config 把路指向 staging" "$(PKG_CONFIG_LIBDIR="$W/ft/stage/usr/lib/pkgconfig" PKG_CONFIG_SYSROOT_DIR="$W/ft/stage" pkg-config --cflags freetype2)" "-I$W/ft/stage/usr/include/freetype2"
	"${CROSS_PREFIX}gcc" -Wall -Wextra -Werror -O2 -I"$W/ft/stage/usr/include/freetype2" \
		-o "$W/ft-dyn" "$SRC/ftmini.c" -L"$W/ft/stage/usr/lib" -lfreetype || exit 1
	eq "动态探针 NEEDED 记的是 SONAME" "$(readelf -d "$W/ft-dyn" | sed -n 's/.*Shared library: \[\(libfreetype[^]]*\)\].*/\1/p')" "libfreetype.so.6"
	"${CROSS_PREFIX}gcc" -static -Wall -Wextra -Werror -O2 -I"$W/ft/stage/usr/include/freetype2" \
		-o "$W/ft-sta" "$SRC/ftmini.c" "$W/ft/stage/usr/lib/libfreetype.a" -lm || exit 1
	eq "静态探针没有动态段" "$(readelf -d "$W/ft-sta" 2>&1 | grep -c 'no dynamic section')" "1"
	eq "静态探针仍是 ARM" "$(readelf -h "$W/ft-sta" | sed -n 's/^ *Machine: *//p')" "ARM"
	(
		mkdir -p "$W/ft/nohost" && cd "$W/ft/nohost" || exit 1
		"$W/ft/src/freetype-2.10.2/configure" --prefix=/usr \
			--without-zlib --without-bzip2 --without-png \
			--without-harfbuzz --without-brotli > configure.log 2>&1 || exit 1
	) || exit 1
	eq "注错见红：不带 --host 退回本机编译" "$(grep -c 'checking whether we are cross compiling... no' "$W/ft/nohost/configure.log")" "1"
	(
		mkdir -p "$W/ft/badpfx" && cd "$W/ft/badpfx" || exit 1
		"$W/ft/src/freetype-2.10.2/configure" --host=arm-linux-gnueabihf \
			--prefix="$W/badp/usr" \
			--without-zlib --without-bzip2 --without-png \
			--without-harfbuzz --without-brotli > configure.log 2>&1 || exit 1
		make -j2 > make.log 2>&1 || exit 1
	) || exit 1
	eq "注错见红：prefix 写临时路径会被烙进 .pc" "$(grep -c "^prefix=$W/badp/usr" "$W/ft/badpfx/freetype2.pc")" "1"
else
	skip "FreeType 交叉构建一组" "缺 $FT_TARBALL 或 ${CROSS_PREFIX}gcc"
fi

echo "======================================"
printf '  %d PASS / %d FAIL / %d SKIP\n' "$PASS" "$FAIL" "$SKIP"
echo "======================================"
[ "$FAIL" -eq 0 ]
