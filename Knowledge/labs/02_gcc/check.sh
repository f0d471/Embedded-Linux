#!/bin/bash
# 02 章（GCC 编译器的使用）的判据自动核对
#
# 用法：bash check.sh
# 从源码重建一切（四步停点、多文件、静态库、动态库、write 实验），逐条核对。
# 注错见红：改坏一处（比如把 pp_demo.c 的 TWICE 定义加上括号），必须有判据变红。

cd "$(dirname "$0")" || exit 1

HELLO=../01_hello/hello.c
CC_ARM=arm-linux-gnueabihf-gcc
OD_ARM=arm-linux-gnueabihf-objdump
HAVE_ARM=1
command -v $CC_ARM >/dev/null 2>&1 || HAVE_ARM=0

PASS=0; FAIL=0; SKIP=0
ok()   { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
no()   { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -n "$2" ] && printf '        %s\n' "$2"; }
skip() { SKIP=$((SKIP+1)); printf '  SKIP  %s\n' "$1"; }
eq()   { if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "期望 $3，实得 $2"; fi; }
has()  { if echo "$2" | grep -qE -e "$3"; then ok "$1"; else no "$1" "输出里找不到 $3"; fi; }

die() {
	FAIL=$((FAIL+1))
	printf '  FAIL  构建：%s\n\n  %d PASS / %d FAIL / %d SKIP（构建没过）\n' "$1" "$PASS" "$FAIL" "$SKIP"
	exit 1
}

echo "=== 构建 ==="
rm -f hello.i hello.s hello.o hello main.o sub.o test libsub.a libsub.so \
      test_static test_shared pp_demo pp_demo_dbg pp_demo.i pp_demo_dbg.i \
      hello_write warn.o pic_nopie.o pic_pic.o
gcc -E "$HELLO" -o hello.i          || die "预处理失败"
gcc -S hello.i -o hello.s           || die "编译到汇编失败"
gcc -c hello.s -o hello.o           || die "汇编失败"
gcc hello.o -o hello                || die "链接失败"
gcc -c -o main.o main.c             || die "main.c 编译失败"
gcc -c -o sub.o  sub.c              || die "sub.c 编译失败"
ar rcs libsub.a sub.o               || die "ar 打包失败"
gcc -shared -fPIC -o libsub.so sub.o || die "动态库构建失败"
gcc -o test_static main.o libsub.a  || die "静态链接失败"
gcc -o test_shared main.o -L. -lsub || die "动态链接失败"
gcc -Wall pp_demo.c -o pp_demo               || die "pp_demo 编译失败"
gcc -Wall -DDEBUG pp_demo.c -o pp_demo_dbg   || die "pp_demo -DDEBUG 编译失败"
gcc -E pp_demo.c -o pp_demo.i                || die "pp_demo 预处理失败"
gcc -E -DDEBUG pp_demo.c -o pp_demo_dbg.i    || die "pp_demo -DDEBUG 预处理失败"
gcc -Wall hello_write.c -o hello_write       || die "hello_write 编译失败"
echo "  完成"
echo

echo "=== 2 预处理 ==="
N_I=$(wc -l < hello.i)
if [ "$N_I" -ge 800 ]; then ok "hello.i 有 $N_I 行（19 行源码展开而来）"; else no "hello.i 行数" "只有 $N_I 行"; fi
has "hello.i 里有 printf 的声明" "$(grep 'extern int printf' hello.i)" 'extern int printf \(const char'
N_MAIN=$(grep -n 'int main' hello.i | head -1 | cut -d: -f1)
if [ "$N_MAIN" -ge 800 ]; then ok "main 被挤到第 $N_MAIN 行"; else no "main 的行号" "在第 $N_MAIN 行"; fi
N_MARK=$(grep -c '^# ' hello.i)
if [ "$N_MARK" -ge 100 ]; then ok "行标记有 $N_MARK 条"; else no "行标记数量" "只有 $N_MARK 条"; fi
cp "$HELLO" .bad.c && echo 'this is not c' >> .bad.c
gcc -E .bad.c -o /dev/null 2>/dev/null; RC_E=$?
gcc -S .bad.c -o /dev/null 2>/dev/null; RC_S=$?
rm -f .bad.c
eq "语法错误：-E 不报错（exit 0）" "$RC_E" "0"
if [ "$RC_S" -ne 0 ]; then ok "语法错误：-S 报错（exit $RC_S）"; else no "语法错误：-S 应报错" "exit 0"; fi
has "宏只做文本替换：twice 展开成 3 + 3 * 2" "$(grep 'int twice' pp_demo.i)" 'int twice = 3 \+ 3 \* 2;'
has "-DDEBUG 放出了条件编译块" "$(grep 'range = range' pp_demo_dbg.i)" 'range = range \+ \(1 << \(\(1 << \(2\)\)\)\);'
eq "TWICE(3)*2 算出来是 9 不是 12" "$(./pp_demo)" 'range=10 mask=8 twice=9'
eq "-DDEBUG 版 range=26" "$(./pp_demo_dbg)" 'range=26 mask=8 twice=9'
has "-dM 能看到自己的宏" "$(gcc -E -dM pp_demo.c)" '#define MAX 20'
N_MACRO=$(gcc -E -dM pp_demo.c | wc -l)
if [ "$N_MACRO" -ge 600 ]; then ok "-dM 一共列出 $N_MACRO 个宏（绝大多数来自系统头文件）"; else no "-dM 宏总数" "只有 $N_MACRO"; fi
echo

echo "=== 3 编译（.i -> .s） ==="
has "hello.s 里有字符串 .rodata" "$(cat hello.s)" '\.string\s+"Hello, world!"'
has "hello.s 里调用 printf@PLT" "$(cat hello.s)" 'call\s+printf@PLT'
has "无格式符的 printf 已被换成 puts" "$(cat hello.s)" 'call\s+puts@PLT'
gcc -c warn.c -o warn.o 2>.w0.err; RC0=$?; B0=$(wc -c < .w0.err)
gcc -Wall -c warn.c -o warn.o 2>.w1.err; RC1=$?
eq "不加 -Wall：编译成功且一个字都不说" "$RC0/$B0" "0/0"
eq "加 -Wall：警告不挡编译（exit 0）" "$RC1" "0"
has "-Wall 报未使用的变量" "$(cat .w1.err)" 'Wunused-variable'
has "-Wall 报未初始化就用" "$(cat .w1.err)" 'Wuninitialized'
rm -f .w0.err .w1.err
echo

echo "=== 4 汇编（.s -> .o） ==="
has "hello.o 的 Type 是 REL（可重定位）" "$(readelf -h hello.o)" 'Type:\s+REL'
S=$(readelf -S hello.o)
has "有 .text"  "$S" '\.text\s+PROGBITS'
has "有 .rodata" "$S" '\.rodata\s+PROGBITS'
has "有 .symtab" "$S" '\.symtab\s+SYMTAB'
has "有 .rela.text" "$S" '\.rela\.text\s+RELA'
SYM=$(readelf -s hello.o)
has "main 是 FUNC GLOBAL 且在 1 号 section" "$SYM" 'FUNC\s+GLOBAL\s+DEFAULT\s+1 main'
has "printf 是 UND（本文件没有）" "$SYM" 'UND printf'
has "puts 也是 UND" "$SYM" 'UND puts'
REL=$(readelf -r hello.o)
has "重定位表里有 printf 的 PLT32" "$REL" 'R_X86_64_PLT32.*printf'
has "重定位表里有 puts 的 PLT32" "$REL" 'R_X86_64_PLT32.*puts'
has "call 指令里填的是 00 00 00 00（等人来填）" "$(objdump -d hello.o)" 'call\s+3b <main\+0x3b>'
echo

echo "=== 5 链接（.o -> hello） ==="
D=$(objdump -d --disassemble=main hello)
has "链接后 call 指向 printf@plt" "$D" 'call\s+[0-9a-f]+ <printf@plt>'
has "链接后 call 指向 puts@plt" "$D" 'call\s+[0-9a-f]+ <puts@plt>'
if echo "$D" | grep -qE 'e8 00 00 00 00'; then no "链接后不应再有全零的 call" "还有 e8 00 00 00 00"; else ok "链接后没有全零的 call 了"; fi
has "字符串有了真实地址（# 2xxx 注释）" "$D" 'lea.*# 2[0-9a-f]{3} <_IO_stdin_used'
V=$(gcc -### -o /dev/null "$HELLO" 2>&1)
has "gcc 内部调用了 cc1"      "$V" 'cc1'
has "gcc 内部调用了 as"       "$V" '-as '
has "gcc 内部调用了 collect2" "$V" 'collect2'
gcc -nostartfiles -o .t_nsf main.o sub.o 2>.nsf.err
has "-nostartfiles 链接时警告找不到 _start" "$(cat .nsf.err)" 'cannot find entry symbol _start'
./.t_nsf >/dev/null 2>&1; RC=$?
eq "-nostartfiles 的产物一跑就段错误（139）" "$RC" "139"
rm -f .t_nsf .nsf.err
gcc -nostdlib -o .t_nsl main.o sub.o 2>.nsl.err; RC=$?
if [ "$RC" -ne 0 ]; then ok "-nostdlib 链接失败（exit $RC）"; else no "-nostdlib 应链接失败" "exit 0"; fi
has "-nostdlib 报 puts 未定义" "$(cat .nsl.err)" "undefined reference to \`puts'"
rm -f .t_nsl .nsl.err
gcc -M main.c abc.dep >/dev/null 2>.m.err; RC=$?
if [ "$RC" -ne 0 ]; then ok "-M 的清单只走 stdout，跟个文件名会报错（exit $RC）"; else no "-M 带文件名应报错" "exit 0"; fi
rm -f .m.err abc.dep
gcc -MD -c -o main.o main.c
has "-MD 生成 main.d，内容含 sub.h" "$(cat main.d)" 'main\.o: main\.c .*sub\.h'
has "-M 会列出系统头文件" "$(gcc -M main.c)" 'stdc-predef\.h'
if gcc -MM main.c | grep -q 'stdc-predef'; then no "-MM 不应列系统头文件" "列了"; else ok "-MM 不列系统头文件"; fi
echo

echo "=== 6 静态库与动态库 ==="
eq "ar t 列出打包进去的成员" "$(ar t libsub.a)" "sub.o"
has "test_static 里 sub_func 是 T（已抄进来）" "$(nm test_static)" ' T sub_func'
has "test_shared 里 sub_func 是 U（运行时再借）" "$(nm test_shared)" ' U sub_func'
has "test_shared 记下 NEEDED libsub.so" "$(readelf -d test_shared)" 'NEEDED.*libsub\.so'
eq "test_static 直接能跑" "$(./test_static)" "sub"
mv libsub.so .libsub.so.hidden
./test_shared >/dev/null 2>&1; RC=$?
eq "库藏起来后 test_shared 起不来（127）" "$RC" "127"
eq "同一个时刻 test_static 照样能跑" "$(./test_static)" "sub"
mv .libsub.so.hidden libsub.so
eq "LD_LIBRARY_PATH=. 之后 test_shared 能跑" "$(LD_LIBRARY_PATH=. ./test_shared)" "sub"
gcc -o .t_bad main.o -L. -lsub.so 2>.l.err; RC=$?
if [ "$RC" -ne 0 ]; then ok "-lsub.so 找不到（-l 只认去掉 lib 和后缀的名字）"; else no "-lsub.so 应失败" "链接成功"; fi
rm -f .t_bad .l.err
SZ_A=$(stat -c %s libsub.a); SZ_SO=$(stat -c %s libsub.so)
if [ "$SZ_SO" -ge $((SZ_A * 5)) ]; then ok "libsub.so($SZ_SO) 比 libsub.a($SZ_A) 大得多"; else no "libsub.so 应大得多" "$SZ_A vs $SZ_SO"; fi
SZ_TS=$(stat -c %s test_static); SZ_TD=$(stat -c %s test_shared)
DIFF=$((SZ_TS - SZ_TD)); [ $DIFF -lt 0 ] && DIFF=$((-DIFF))
if [ "$DIFF" -lt 500 ]; then ok "库只有一行代码时，静态/动态产物几乎一样大（差 $DIFF 字节）"; else no "两种产物应几乎一样大" "差 $DIFF 字节"; fi
echo

echo "=== 6.4 -fPIC（需要交叉编译器） ==="
if [ "$HAVE_ARM" -eq 1 ]; then
	$CC_ARM -O2 -fno-PIC -c pic_demo.c -o pic_nopie.o
	$CC_ARM -shared -o /dev/null pic_nopie.o 2>.pic.err; RC=$?
	if [ "$RC" -ne 0 ]; then ok "ARM 动态库不加 -fPIC：链接拒绝（exit $RC）"; else no "不加 -fPIC 应被拒绝" "链接成功"; fi
	has "拒绝信息让重编时加 -fPIC" "$(cat .pic.err)" 'recompile with -fPIC'
	$CC_ARM -O2 -fPIC -c pic_demo.c -o pic_pic.o
	$CC_ARM -shared -o .libpic.so pic_pic.o 2>/dev/null; RC=$?
	eq "加了 -fPIC 就能链成动态库" "$RC" "0"
	rm -f pic_nopie.o pic_pic.o .libpic.so .pic.err
else
	skip "无交叉编译器，-fPIC 三条未测"
	skip "无交叉编译器"
	skip "无交叉编译器"
fi
echo

echo "=== 6.5 -static（需要交叉编译器） ==="
if [ "$HAVE_ARM" -eq 1 ]; then
	$CC_ARM -static -O2 "$HELLO" -o .st_good
	$CC_ARM -O2 "$HELLO" -o .st_dyn
	has "-static 版 Type 是 EXEC" "$(readelf -h .st_good)" 'Type:\s+EXEC'
	has "动态版 Type 是 DYN"      "$(readelf -h .st_dyn)"  'Type:\s+DYN'
	eq "-static 版没有 .interp" "$(readelf -l .st_good 2>/dev/null | grep -c INTERP)" "0"
	SZ_S=$(stat -c %s .st_good); SZ_D=$(stat -c %s .st_dyn)
	if [ "$SZ_S" -ge $((SZ_D * 5)) ]; then ok "-static 版体积是动态版的 $((SZ_S / SZ_D)) 倍（$SZ_D -> $SZ_S）"; else no "-static 应大 5 倍以上" "$SZ_D -> $SZ_S"; fi
	mkdir -p .stbad && ( cd .stbad && $CC_ARM -O2 "../../01_hello/hello.c" -o -static )
	has "把 -static 放到 -o 后面：产物名叫 -static，而且是动态版" \
	    "$(readelf -h ./.stbad/-static 2>/dev/null)" 'Type:\s+DYN'
	rm -rf .stbad .st_good .st_dyn
else
	skip "无交叉编译器，-static 五条未测"; skip ""; skip ""; skip ""; skip ""
fi
echo

echo "=== 7 write 才是系统调用 ==="
eq "hello_write 打印同一句话" "$(./hello_write)" "hello, world"
has "hello_write 里 write 是 U（也在 libc 里）" "$(nm -D hello_write)" ' U write'
if command -v strace >/dev/null 2>&1; then
	strace -e trace=write -o .st.out ./hello_write >/dev/null
	eq "strace 只看到一条 write" "$(grep -c '^write(' .st.out)" "1"
	has "那条 write 写的是 13 字节、返回 13" "$(cat .st.out)" 'write\(1, "hello, world\\n", 13\)\s+= 13'
	rm -f .st.out
else
	skip "无 strace"; skip "无 strace"
fi
if [ "$HAVE_ARM" -eq 1 ]; then
	$CC_ARM -static -O2 "$HELLO" -o .hw_st
	$CC_ARM -O2 "$HELLO" -o .hw_dy
	N_ST=$($OD_ARM -d .hw_st | grep -c 'svc')
	N_DY=$($OD_ARM -d .hw_dy | grep -c 'svc')
	if [ "$N_ST" -ge 10 ]; then ok "静态版里有 $N_ST 条 svc（libc 的系统调用封装被抄了进来）"; else no "静态版应有多条 svc" "只有 $N_ST"; fi
	eq "动态版里一条 svc 都没有（封装在 libc.so 里）" "$N_DY" "0"
	rm -f .hw_st .hw_dy
else
	skip "无交叉编译器，svc 两条未测"; skip ""
fi
echo

rm -f warn.o main.d
echo "======================================"
printf '  %d PASS / %d FAIL / %d SKIP\n' "$PASS" "$FAIL" "$SKIP"
echo "======================================"
[ "$FAIL" -eq 0 ]
