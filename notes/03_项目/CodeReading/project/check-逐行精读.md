# check.sh 逐行精读

对应代码：`project/check.sh`，148 行。

前置：`Makefile` 各开关的行为，见 [Makefile 逐行精读](Makefile-逐行精读.md)。

---

## 1. 文件定位

`project/` 的判据。在 WSL 里 `bash check.sh` 跑一次，输出 26 条 PASS/FAIL，
末尾给计数，退出码为 0 表示全绿。

它量的不是功能——这棵树现在没有功能。它量的是
[TechReports 第 01 章](../../TechReports/project/01-先立骨架-分层启停与两棵产物树.md)
里定下的那几条约定还成立没有：六层按顺序起停、加 `.c` 不用改 `Makefile`、
改头文件会全量重编、两个架构的产物并存、日志能整体关掉。
第 02 章之后又多了一条：日志能整条接到文件上，并且是 stderr 那种一行一次 write 的接法
（见 [TechReports 第 02 章](../../TechReports/project/02-日志落文件-用dup2换掉2号槽.md)）。

文件头写着两条原则（第 5 到 8 行）：

```
#   1. 判据尽量做成计数型或序列型, 不做"某条输出里有某个词"型 -- 后者太容易假绿。
#   2. 每条正判据后面都跟一次注错见红: 故意把代码或 Makefile 改坏, 判据必须变红。
#      注错不红的判据等于没有判据。
```

第二条决定了这个文件的结构：判据成对出现，`[N]` 是正判据，`[Nr]` 是它的注错。

---

## 2. 准备（第 12 到 17 行）

```bash
set -u

SRC=$(cd "$(dirname "$0")" && pwd)
CROSS_PREFIX=${CROSS_PREFIX:-arm-linux-gnueabihf-}

PASS=0; FAIL=0; SKIP=0
```

`set -u` 让引用未定义变量成为错误。**没有 `set -e`**，这是有意的：
`set -e` 会在任何一条命令返回非零时立刻退出，
而这个脚本里有大量"预期会失败"的命令（注错之后的 `make`、
故意跑一个不存在的产物）。开了 `set -e` 会在第一次注错时整个脚本退出，
后面的判据一条都跑不到。

`SRC=$(cd "$(dirname "$0")" && pwd)` 取脚本所在目录的**绝对路径**。
`$0` 是脚本自身的路径，`dirname` 取它的目录部分，`cd` 进去再 `pwd` 得到绝对路径。
必须转绝对，因为下面第 28 行会 `cd` 到别处去，相对路径就失效了。

`${CROSS_PREFIX:-arm-linux-gnueabihf-}` 是"环境变量没给就用默认值"。
留这个口子是为了第 2 阶段换成 BSP 工具链时不用改脚本：

```
    CROSS_PREFIX=arm-buildroot-linux-gnueabihf- bash check.sh
```

---

## 3. 三个断言函数（第 19 到 23 行）

```bash
ck()   { if [ "$2" = "$3" ]; then echo "  PASS  $1 = $2"; PASS=$((PASS+1));
         else echo "  FAIL  $1: got [$2] want [$3]"; FAIL=$((FAIL+1)); fi; }
red()  { if [ "$2" != "$3" ]; then echo "  PASS  注错见红: $1 变成 [$2]"; PASS=$((PASS+1));
         else echo "  FAIL  注错没红: $1 仍是 [$3], 这条判据是假绿"; FAIL=$((FAIL+1)); fi; }
skip() { echo "  SKIP  $1 ($2)"; SKIP=$((SKIP+1)); }
```

`ck` 与 `red` 是**同一个比较的两个方向**：`ck` 要求相等，`red` 要求不等。
`red` 的第三个参数传的是"注错之前的正确值"，语义是"这个值现在必须不再是它了"。

`red` 的 FAIL 分支那句话值得单独看：

```
    FAIL  注错没红: xxx 仍是 [yyy], 这条判据是假绿
```

它说的不是代码坏了，是**判据坏了**。这两种失败要分开报，
因为处理方式完全不同：前者去改代码，后者去改判据。

`[ "$2" = "$3" ]` 里两个变量都加了引号。不加的话，
空字符串会让 `[ = xxx ]` 语法错误，而空字符串恰恰是判据失败时最常见的取值
（命令跑挂了，`$(...)` 返回空）。

三个函数都直接改全局的 `PASS` / `FAIL` / `SKIP`。这依赖一件事：
**它们必须在当前 shell 里执行，不能在子 shell 里。**
把 `ck ... | tee log` 这样写，`ck` 会跑在管道的子进程里，
计数加在子进程的变量上，父进程这边永远是 0。
这个文件里所有的 `ck`/`red` 调用都在顶层，没有放进管道。

---

## 4. 临时工作区（第 25 到 33 行）

```bash
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
cp -r "$SRC" "$W/project"
cd "$W/project" || exit 1
rm -rf build

NSRC=$(find . -name '*.c' -not -path './build/*' | wc -l)
INIT_SEQ="display input font ui page business "
EXIT_SEQ="business page ui font input display "
```

**所有破坏性操作都在副本里做。** `mktemp -d` 建一个临时目录，
`cp -r` 把整个工程复制进去，`cd` 过去。工作区一个字节不动，
所以判据中途失败退出也不会留下损坏的源码，
也不会和未提交的改动打架。

`trap 'rm -rf "$W"' EXIT` 把清理挂在脚本退出上，
不管是正常结束、出错退出还是被 Ctrl-C，临时目录都会被删掉。
`$W` 在单引号里，所以它是在 trap **触发时**展开的，不是注册时——
这里两者相同，但写成双引号会在 `W` 还没定值时就展开成空，
`rm -rf ""` 虽然无害，但清理就失效了。

`rm -rf build` 是因为 `cp -r` 会把工作区里已有的 `build/` 一起复制过来，
那里面的 `.o` 时间戳比刚复制过去的 `.c` 新，第一条判据会量到"什么都没重编"。

`NSRC` 是**自己数出来的源文件个数**，不是写死的 8。
第 88 行的"全量重编"判据用它做期望值，所以以后加文件时这条判据不用改。
`-not -path './build/*'` 排除产物目录里可能存在的 `.c`（当前没有，
但复制过来的目录如果没删干净会有）。

`INIT_SEQ` / `EXIT_SEQ` 是六个层名，**写死在这里**，
和 `main.c` 的层表各写各的。这是有意的重复：
判据的期望值必须独立于被测对象，如果它从 `main.c` 里读，
那么改坏 `main.c` 时期望值会跟着变，判据永远绿。

末尾那个空格不是笔误。取字段那一步用 `tr '\n' ' '` 把六行并成一行，
每个词后面都跟一个空格，包括最后一个。期望值必须带上它才能相等。

---

## 5. 第 1 组：构建与启停顺序（第 35 到 42 行）

```bash
echo "[1] 构建 + 分层启停顺序    (源文件 $NSRC 个)"
make >/dev/null 2>&1
out=$(./build/x86/product_tool 2>&1); rc=$?
ck "退出码"        "$rc" "0"
ck "init OK 行数"  "$(echo "$out" | grep -c 'init OK')" "6"
ck "exit OK 行数"  "$(echo "$out" | grep -c 'exit OK')" "6"
ck "init 顺序"     "$(echo "$out" | grep 'init OK' | awk '{print $(NF-2)}' | tr '\n' ' ')" "$INIT_SEQ"
ck "exit 顺序反向" "$(echo "$out" | grep 'exit OK' | awk '{print $(NF-2)}' | tr '\n' ' ')" "$EXIT_SEQ"
```

`out=$(./build/x86/product_tool 2>&1)` 里的 `2>&1` 不能省：
日志走的是 `stderr`（见 [common 精读](common-逐行精读.md)第 5 节），
不重定向的话 `out` 是空的，四条判据一起红。

`rc=$?` 必须紧跟在上一行。`$?` 是上一条命令的退出码，
中间插任何一条命令（哪怕是 `echo`）都会把它冲掉。

`awk '{print $(NF-2)}'` 取倒数第三个字段。日志行的形状是：

```
    [I] display/disp_manager.c:14 display init OK
     ^                             ^      ^   ^
     $1                          NF-2   NF-1  NF
```

取行首的 `$1` 会得到六个 `[I]`，那是一条恒定输出的判据。
锚行尾的好处是日志前缀以后再变也不用改判据。
两种取法的实测对照见
[TechReports 第 01 章第 4.1 节](../../TechReports/project/01-先立骨架-分层启停与两棵产物树.md)。

**四条判据分工不重叠**：行数判据管"有没有少一层"，
顺序判据管"顺序对不对"。只留顺序判据是不够的：
如果程序一行都不输出，顺序判据的实际值是空串，
期望值非空，它会红——这一点上两者确实重叠，
但行数判据的报错信息更直接（`got [5] want [6]`），
定位时省一步。

---

## 6. 第 1r 组：注错，删掉一层（第 44 到 50 行）

```bash
echo "[1r] 注错: 从 main.c 的层表里删掉 business 那一行"
sed -i '/{ "business",/d' main.c
make >/dev/null 2>&1
out2=$(./build/x86/product_tool 2>&1)
red "init OK 行数" "$(echo "$out2" | grep -c 'init OK')" "6"
ck  "其余 5 层照常启停(层间无隐式耦合)" "$(echo "$out2" | grep -c 'exit OK')" "5"
cp "$SRC/main.c" main.c
```

`sed -i '/{ "business",/d'` 删掉匹配这个形状的整行，也就是层表第 38 行。
匹配的是字面量 `{ "business",`，**层表的写法一变这条注错就静默失效**：
它会删不掉任何东西，然后 `red` 那一条会报"注错没红"——
这个失效是看得见的，因为 `red` 会红。这是把注错做成判据的好处。

这一组有两条判据，第二条不是注错而是正判据：删掉一层之后，
**其余五层必须照常启停**。它量的是层与层之间没有隐式耦合——
如果 `page` 层的代码里偷偷用了 `business` 的什么东西，
删掉 `business` 之后 `page` 会跟着坏，这条会红。

现在六层都是空壳，这条判据必然绿。它的价值在以后：
等各层有了真实实现，这条会成为"分层是不是真的分开了"的唯一自动检查。

`cp "$SRC/main.c" main.c` 从**原目录**复制一份回来还原。
不用 `git checkout`，因为这里是临时副本，不是 git 工作区。

---

## 7. 第 2 组：交叉编译（第 52 到 65 行）

```bash
if command -v ${CROSS_PREFIX}gcc >/dev/null 2>&1; then
	make >/dev/null 2>&1
	make CROSS=$CROSS_PREFIX >/dev/null 2>&1
	ck "ARM 产物 Machine"  "$(readelf -h build/arm/product_tool | sed -n 's/^ *Machine: *//p')" "ARM"
	ck "x86 产物 Machine"  "$(readelf -h build/x86/product_tool | sed -n 's/^ *Machine: *//p')" "Advanced Micro Devices X86-64"
	ck "两份产物同时存在"  "$(ls build/*/product_tool | wc -l)" "2"
	make clean >/dev/null 2>&1
	ck "make clean 只清当前架构" "$(ls build/*/product_tool 2>/dev/null | wc -l)" "1"
	make distclean >/dev/null 2>&1
	ck "make distclean 清干净"   "$(ls -d build 2>/dev/null | wc -l)" "0"
else
	skip "交叉编译判据" "没装 ${CROSS_PREFIX}gcc"
fi
```

`command -v xxx` 是查"这个命令存在吗"的可移植写法（`which` 在某些系统上不是内建命令，
且退出码行为不一致）。没装交叉工具链时整组 SKIP 而不是 FAIL，
因为那不是代码的问题。

**`make` 和 `make CROSS=...` 的顺序不能反。**
先编 x86 再编 ARM，之后 `make clean`（无 `CROSS`）清掉的是 `build/x86`，
剩下 `build/arm`，所以第四条判据期望 1。
反过来的话 `make clean` 清掉的还是 `build/x86`（因为 `clean` 那次没带 `CROSS`），
结果相同——但这是巧合，不是设计。这里依赖的是
"`make clean` 只看这一次命令行的 `CROSS`"，
和上一次编了什么无关。

`sed -n 's/^ *Machine: *//p'` 从 `readelf -h` 的输出里抠出 Machine 字段的值：
`-n` 不打印，`s///p` 只打印替换成功的行，替换的内容是行首空格加 `Machine:` 加空格，
剩下的就是值。

期望值 `"Advanced Micro Devices X86-64"` 是 readelf 的原文，不是简写。
这个字符串跟着 binutils 版本走，换一个大版本可能会变，
那时这条判据会红，红的原因是判据过时而不是代码坏了。这是一处已知的脆弱点。

后两条 `2>/dev/null` 是因为目录不存在时 `ls` 会往 `stderr` 写一行报错，
不重定向的话它会混进判据输出里。`ls` 找不到东西时 `wc -l` 数到 0，正是期望值。

---

## 8. 第 3 组：加文件不改 Makefile（第 67 到 82 行）

```bash
rm -rf build
cat > display/disp_dummy.c <<'X'
#include "common.h"
int disp_dummy_probe(void) { return ERR_NOTSUP; }
X
make >/dev/null 2>&1
ck "新增文件被编译" "$([ -f build/x86/display/disp_dummy.o ] && echo yes || echo no)" "yes"
```

现场造一个新的 `.c` 扔进 `display/`，不改 `Makefile`，看它有没有被编。

`<<'X'` 是 heredoc，定界符加了单引号，所以里面的内容**不做变量展开**。
不加引号的话 `$` 开头的东西会被 shell 替换掉。这里内容里虽然没有 `$`，
加引号是习惯：heredoc 里写代码时一律加。

造出来的文件必须能编过：它包含 `common.h` 并且用了 `ERR_NOTSUP`，
所以同时也顺带验证了 `-Iinclude` 是通的。它定义的函数没有任何人调用，
链接时不会报错，因为它是全局符号，链接器不会因为"没人用"而报错。

`$([ -f xxx ] && echo yes || echo no)` 把"文件存在吗"转成字符串给 `ck` 比。
直接用退出码也行，但那样 `ck` 的报错信息会是 `got [1] want [0]`，
不如 `got [no] want [yes]` 直白。

```bash
echo "[3r] 注错: 把 SRCS 的 wildcard 换成写死的文件清单"
sed -i "s|^SRCS .*|SRCS := main.c common.c display/disp_manager.c ...|" Makefile
rm -rf build
make >/dev/null 2>&1
red "新增文件被编译" "$([ -f build/x86/display/disp_dummy.o ] && echo yes || echo no)" "yes"
cp "$SRC/Makefile" Makefile
rm -f display/disp_dummy.c
```

`sed` 的分隔符用 `|` 而不是 `/`，因为替换内容里有一堆 `/`（路径）。
sed 的 `s` 命令分隔符可以是任意字符，选一个内容里没有的即可。

匹配 `^SRCS .*`，也就是行首的 `SRCS` 加一个空格。
`Makefile` 里那一行是 `SRCS    := ...`，`SRCS` 后面是多个空格，
第一个空格被模式吃掉，剩下的落进 `.*`。把变量改名或者写成 `SRCS:=`
（等号前无空格）都会让这条注错失效，失效时 `red` 会报红，看得见。

两条清理：还原 `Makefile`，删掉造出来的 `.c`。后者必须删，
否则下一组判据数出来的重编文件数会多一个，而 `NSRC` 是在第 31 行就算好的。

---

## 9. 第 4 组：头文件自动依赖（第 84 到 96 行）

```bash
rm -rf build
make >/dev/null 2>&1
touch include/common.h
ck "重编文件数" "$(make 2>&1 | grep -c '^  CC ')" "$NSRC"
```

三步的顺序是这组判据的全部内容：**先完整构建一次，再动头文件，再构建**。

顺序错了量不到东西。如果 `rm -rf build` 之后直接 `touch` 再 `make`，
全量重编是因为产物不存在，和依赖生效与否无关。
必须先让产物存在且都是最新的，`touch` 才是唯一的变量。

`grep -c '^  CC '` 数的是 `Makefile` 第 53 行打的那行提示。
行首两个空格加 `CC` 加一个空格，格式与 `Makefile` 里的 `@echo "  CC    $<"` 对应。
**这两处格式必须一致，改一处要改另一处。**

`touch` 只改时间戳不改内容，这正好验证了 make 比的是 mtime 而不是内容哈希。

```bash
echo "[4r] 注错: 去掉 -MMD -MP, .d 文件不再生成"
sed -i 's/ -MMD -MP//' Makefile
rm -rf build
make >/dev/null 2>&1
touch include/common.h
red "重编文件数" "$(make 2>&1 | grep -c '^  CC ')" "$NSRC"
cp "$SRC/Makefile" Makefile
```

去掉自动依赖之后，`touch include/common.h` 一个文件都不会重编，
实测值从 8 变成 0。

`sed 's/ -MMD -MP//'` 连前面那个空格一起删，避免留下两个连续空格。
它也会命中第 50 行注释里的 `-MMD -MP` 字样——那一行是注释，改了无害。

---

## 10. 第 5 组：日志整体关闭（第 98 到 102 行）

```bash
rm -rf build
make CFLAGS_EXTRA=-DLOG_LEVEL=0 >/dev/null 2>&1
ck "LOG_LEVEL=0 时输出行数" "$(./build/x86/product_tool 2>&1 | wc -l)" "0"
ck "LOG_LEVEL=0 时退出码"   "$(./build/x86/product_tool >/dev/null 2>&1; echo $?)" "0"
```

两条一起才有意义。只量输出行数的话，一个启动就崩的程序也是 0 行；
配上退出码为 0，才说明它是正常跑完而不是没跑起来。

这一组**没有配注错**。它的注错是隐含的：第 1 组在默认 `LOG_LEVEL` 下量到 13 行输出，
这一组在 `LOG_LEVEL=0` 下量到 0 行，两组互为对照。

`2>&1 | wc -l` 收的是 `stderr`，理由同第 5 节。
第二条里 `>/dev/null 2>&1; echo $?` 把输出全丢掉只取退出码。

---

## 11. 第 6 组：日志落文件（第 104 到 144 行）

这一组是 02 章的产出，八条判据分三段。

### 11.1 正判据（第 104 到 114 行）

```bash
LOGF="$W/run.log"
rm -f "$LOGF"
ck "不设 LOG_FILE 时终端行数" "$(./build/x86/product_tool 2>&1 | wc -l)" "13"
ck "设了 LOG_FILE 时终端行数" "$(LOG_FILE=$LOGF ./build/x86/product_tool 2>&1 | wc -l)" "0"
ck "第一次跑完文件行数"       "$(wc -l < "$LOGF")" "13"
LOG_FILE=$LOGF ./build/x86/product_tool >/dev/null 2>&1
ck "第二次跑完文件行数(O_APPEND 接着写)" "$(wc -l < "$LOGF")" "26"
ck "日志文件打不开时退出码"   "$(LOG_FILE=/no/such/dir/x.log ./build/x86/product_tool >/dev/null 2>&1; echo $?)" "1"
```

四条判据量的是四件不同的事，缺一条就漏掉一种失效方式：

| 判据 | 它单独能排除什么 | 它单独排除不了什么 |
|---|---|---|
| 终端 13 行 | 程序根本没跑起来 | 重定向有没有生效 |
| 终端 0 行 | `dup2` 没换掉 2 号槽 | 文件里有没有东西 |
| 文件 13 行 | 换了槽但写丢了 | 是不是每次都清空 |
| 文件 26 行 | `O_APPEND` 被换成 `O_TRUNC` | — |
| 退出码 1 | 打不开时静默降级继续跑 | — |

**13 和 26 这两个数是算出来的**，不是抄运行结果：
六层各一行 `init OK`、各一行 `exit OK`，加 `main_loop` 那行 `framework is up`，
一次运行 13 行；跑两次 26 行。以后加一层，这两个数要跟着变成 15 和 30。
`main.c` 精读第 7 节那张时间轴表是这两个数的来源。

日志路径用 `$W/run.log` 而不是 `/tmp/run.log`：`$W` 是本脚本的临时工作区，
`trap` 会连它一起删掉。写死 `/tmp` 会在跑完之后留垃圾，
更糟的是两个人同时跑这个脚本会互相踩。

### 11.2 stderr 无缓冲那条（第 116 到 125 行）

```bash
if command -v strace >/dev/null 2>&1; then
	strace -f -e trace=write -o "$W/tw.txt" \
		env LOG_FILE=$LOGF ./build/x86/product_tool >/dev/null 2>&1
	ck "13 条日志对应 13 次 write(2,...)" \
	   "$(grep -cE '(^|[0-9]+ +)write\(2,' "$W/tw.txt")" "13"
else
	skip "stderr 无缓冲判据" "没装 strace"
fi
```

这条是**唯一一条量"怎么写"而不是"写没写成"的判据**。上面四条在
`stdout` 全缓冲的实现下也能全绿：数据最后照样进了文件，只是时机不同。
只有数系统调用次数才分得出 13 次一行一次，还是攒成一次。

而"日志走 stderr"正是这套设计的地基（`common.h` 第 27 到 35 行那段注释），
所以它必须有自己的守门人。

三个写法上的点：

- `env LOG_FILE=... ./prog`：**不能**写成 `LOG_FILE=... strace ...`，
  那样变量给的是 strace，被跟踪的程序看不见。
- 正则是 `(^|[0-9]+ +)write\(2,` 而不是 `^write\(2,`：
  加了 `-f` 且真有多个进程时，strace 会在每行前面加 pid 和空格。
  写成 `^write(` 会数出 0，然后判据以"注错没红"的形式失败 —— 
  这个坑在写这一组时踩过一次。
- 用 `if command -v` 包起来，没装 strace 时走 `skip` 而不是 `FAIL`。
  这是本脚本第二处 SKIP 分支，第一处是第 2 组的交叉工具链。

### 11.3 两次注错（第 127 到 144 行）

```bash
sed -i 's/O_WRONLY | O_CREAT | O_APPEND/O_WRONLY | O_CREAT | O_TRUNC/' common.c
...
red "第二次跑完文件行数" "$(wc -l < "$LOGF")" "26"

cp "$SRC/common.c" common.c
sed -i 's/if (dup2(fd, STDERR_FILENO) < 0)/if (0)/' common.c
...
red "第一次跑完文件行数" "$(wc -l < "$LOGF")" "13"
```

第一次注错把 `O_APPEND` 换成 `O_TRUNC`，第二次跑完只剩 13 行。
第二次注错把 `dup2` 那个 `if` 的条件换成 `if (0)` —— 文件照开、
错误照判、`fd` 照关，唯独 2 号槽没换，日志文件因此是 0 行。

**`if (0)` 这个改法是特意挑的**，因为它编得过：直接删掉整个 `if` 块
会留下 `fd` 未被使用的路径变化，`-Wall -Wextra` 下未必干净；
把条件写成恒假，编译器只是把那一支优化掉，其余代码原样。
注错本身必须能编译通过，否则量到的是"编译失败"而不是"判据变红"。

第二次注错前先 `cp "$SRC/common.c"` 还原，否则两次注错叠在一起，
第二条红了也说不清是哪一处造成的。**一次只坏一个地方**，
这是本脚本里每一组注错都遵守的规矩。

---

## 12. 结尾（第 146 到 148 行）

```bash
echo
echo "PASS=$PASS  FAIL=$FAIL  SKIP=$SKIP"
[ "$FAIL" -eq 0 ]
```

最后一行是脚本的退出码：`FAIL` 为 0 时 `[` 返回 0，脚本退出码 0。
它是脚本的最后一条命令，所以它的退出码就是脚本的退出码，不用写 `exit`。

这一行的作用是让这个脚本能被别的东西调用（以后接 CI 时）：
调用方只看退出码就知道全绿没有，不用去解析输出。

---

## 13. 执行顺序

| 步 | 行 | 动作 | 副作用 |
|---|---|---|---|
| 1 | 25-29 | 建临时目录、复制工程、`cd` 过去、删 `build/` | 之后所有操作都在副本里 |
| 2 | 31 | 数源文件个数 | `NSRC=8` |
| 3 | 35-42 | 第 1 组，5 条 | 工程被完整编译一次 |
| 4 | 44-50 | 第 1r 组，2 条 | `main.c` 被改坏又还原 |
| 5 | 52-65 | 第 2 组，5 条或 1 条 SKIP | `build/` 被清空 |
| 6 | 67-82 | 第 3 组，2 条 | 造出又删掉一个 `.c`，`Makefile` 被改坏又还原 |
| 7 | 84-96 | 第 4 组，2 条 | `Makefile` 被改坏又还原 |
| 8 | 98-102 | 第 5 组，2 条 | 用不同的 `CFLAGS` 重编一次 |
| 9 | 104-125 | 第 6 组，6 条或 5 条加 1 条 SKIP | 在 `$W/run.log` 里攒下 26 行日志 |
| 10 | 127-144 | 第 6r / 6r2 两组，各 1 条 | `common.c` 被改坏两次，各自还原 |
| 11 | 146-148 | 打计数，定退出码 | trap 触发，删掉临时目录 |

第 4、6、7、10 步各有一次"改坏又还原"。还原用的是从 `$SRC` 复制，
所以**即使脚本在还原之前挂掉，也只是临时副本损坏**，工作区无恙。

---

## 14. 容易读错的地方

**没有 `set -e` 是有意的。** 见第 2 节。

**`ck` / `red` 不能放进管道。** 计数会加在子 shell 里，父进程看不到。

**`INIT_SEQ` 末尾那个空格不是笔误。** `tr '\n' ' '` 会在最后一个词后面也留一个。

**第 2 组里 `make` 和 `make CROSS=...` 的先后有讲究。** 见第 7 节。

**第 4 组三步的顺序是判据本身。** 换个顺序它量到的就不是依赖生效与否了。

**`grep -c '^  CC '` 的空格数与 `Makefile` 里的 `echo` 绑死。** 改一处要改另一处。

**判据总数 26 是"跑得到的条数"，不是"写了几条"。**
第 2 组在没装交叉工具链的机器上是 1 条 SKIP 而不是 5 条 PASS，
那种情况下末尾会是 `PASS=22 FAIL=0 SKIP=1`；没装 strace 再少一条。

---

## 15. 消费者

| 谁 | 关系 |
|---|---|
| 人 | `bash check.sh`，看 `PASS=26 FAIL=0 SKIP=0` |
| `notes/03_项目/README.md` 的提交规则 | 判据条数变化时要同步根 `README.md` 的进度栏 |
| 以后的 CI | 只看退出码 |

被它依赖的东西（改这些要回来跑一次 `check.sh`）：

| 位置 | 依赖内容 |
|---|---|
| `Makefile` 第 25 行 | 变量名 `SRCS` 与行首形状 |
| `Makefile` 第 53 行 | `"  CC    $<"` 的空格数 |
| `Makefile` 第 54 行 | `-MMD -MP` 这个字面串 |
| `Makefile` 的 `clean` / `distclean` | 两者的差别 |
| `main.c` 第 40 行 | `{ "business",` 这个字面形状 |
| `main.c` 第 89 行 | 环境变量名 `LOG_FILE` |
| `common.c` 第 36 行 | `O_WRONLY`、`O_CREAT`、`O_APPEND` 三个 flag 拼写与空格 |
| `common.c` 第 47 行 | `if (dup2(fd, STDERR_FILENO) < 0)` 这个字面形状 |
| 六层的 `*_init()` / `*_exit()` | 日志文本以 `<层名> init OK` 结尾 |
| `include/common.h` | `LOG_LEVEL` 这个编译期开关 |
