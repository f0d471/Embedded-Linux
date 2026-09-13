# 03 ABI 与 sysroot

## 这一篇到底在讲什么

> **API 是给人看的说明书，ABI 是给机器看的说明书。**
> API 说"这个函数叫什么、收几个参数"，你照着写代码；
> ABI 说"编译成二进制之后怎么对接"——参数放哪个寄存器、`int` 几个字节、
> 结构体的字段怎么排。源码那一层对得上，不代表二进制这一层拼得起来。
>
> **而 sysroot，是你在开发机上给板子建的一个替身根目录。**

### 你是从哪儿撞见它的

你想把一个程序编给板子，换上交叉编译器，敲下去：

    fatal error: stdio.h: No such file or directory

`stdio.h`？这个文件你电脑上明明有啊。于是很自然地想去 `/usr/include` 里
把它找出来，用 `-I` 指过去。**这个念头是本篇最想拦住你的那个。**

或者你注意到另一件事：一个交叉工具链解压出来动辄几百兆，
可编译器本身没那么大。剩下那几百兆是什么？

两个问题的答案是同一个。

### 交叉编译的全部麻烦，就一句话

交叉编译是**在 A 机器上，造 B 机器要用的东西**。
所有的坑都来自同一件事：**造的时候，你身边只有 A 的材料。**

你写 `#include <stdio.h>`，编译器得去找这个文件。你电脑上那份
`/usr/include/stdio.h` 确实存在，但**它是给 x86 用的**：
里头写着 `long` 是 8 字节、结构体按 x86 的规矩排、系统调用是 x86 的那套编号。

拿它编出来的 ARM 程序会怎样？最糟的情况不是编不过，
**是编得过、跑起来、然后悄悄算错**——数据读歪几个字节，结构体字段串位，
现象飘忽，查起来要人命。

所以结论只能是：**编给板子的程序，必须用板子那套头文件和库。**
可板子不在手边，就算插着 USB 线也没法让编译器跑去板子上读文件。

于是办法只剩一个：**把板子根目录下那些头文件和库，复制一份放到开发机上，
然后告诉编译器——你找头文件和库的时候，把这个目录当成 `/`。**

那个被当成 `/` 的目录，就叫 **sysroot**。工具链里那几百兆，大头就是它。

```
    开发机（x86）                                  板子（ARM）

    /usr/include/stdio.h   ← 给 x86 的，别碰

    交叉工具链/
      bin/arm-...-gcc      编译器本体，不大
      <sysroot>/           ─────── 复制自 ───────→  板子的 / 下面那些
        usr/include/stdio.h                          头文件和库
        lib/libc.so                                  （版本要对得上）
              ↑
        编译时它被当成 /
```

**sysroot 保证你用对了材料，ABI 保证材料之间拼得上**——一篇里讲两个词，
是因为它们是同一个问题的两面。

### ABI 到底管多少事

02 篇量到的"参数放 `r0`～`r3`"只是 ABI 的头几条。它还管：

    类型大小      x86-64 上 long 和指针 8 字节，32 位 ARM 上都是 4 字节
    对齐          一个字段从第几个字节开始放
    结构体布局    字段之间要不要填空洞，填几个
    字节序        多字节的数，低位在前还是高位在前
    系统调用      调用号是多少、放在哪个寄存器（这条 05 篇细讲）

第二节会实测第一条：**同一行 C 代码，在两个平台上 `sizeof` 出来的数不一样。**
`sizeof(long)` 从来不是 C 语言规定死的，是 ABI 规定的。
这也解释了一个常见的坑：**两台机器之间直接 `write` 一个结构体再 `read` 回来，
换平台就散架**——因为你依赖的是 ABI，而不是一个说清楚的数据格式。

## 结论先贴出来

下面每条都能直接背走，看不懂推导也不影响用。条数按本篇实际有几个独立结论来定，
不凑数：正文每一节至少对应下面一条，没对上就是漏了。

1. **API 管源码怎么写，ABI 管编译完的二进制怎么对接。** 函数名和声明长得一样，
   不代表两个编译好的文件能拼到一起。
2. **ABI 不止管寄存器**：类型大小、对齐、结构体布局、字节序、系统调用规则全在内。
   实测 x86-64 的 `long` 和指针是 8 字节，32 位 ARM 上是 4 字节——
   **`sizeof(long)` 是 ABI 说了算，不是 C 语言说了算。**
3. **交叉编译必须用目标平台的头文件和库。** 缺头文件时最不该做的补救，
   就是把宿主机的 `/usr/include` 用 `-I` 指进去：它能让你编过，然后在板子上错得很隐蔽。
4. **sysroot 就是"编译时被当成 `/` 的那个目录"。** 交叉工具链体积大，大头是它。
5. **`-print-sysroot` 输出 `/` 不代表配错了。** 工具链还可以靠架构专属目录选中 ARM
   材料。想确认到底用了哪一份，**问它**：`-print-file-name=libc.so`，别照目录名猜。
6. **交叉工具链里的 `libc.so` 可能根本不是 ELF，而是一行文本的链接脚本**，
   内容是告诉链接器接着去找哪几个文件。`file` 一下就看得出来（本仓实测，
   这条推翻过一版旧判据）。
7. **`-I` 找头文件目录，`-L` 找链接时的库目录，`-lfoo` 选名叫 foo 的库**
   （对应 `libfoo.so` 或 `libfoo.a`）。**`-L` 只管链接那一刻**，
   板子上运行时去哪找 `.so` 是另一件事，`-L` 一点忙都帮不上。

### 看到什么，就先想到什么

| 看到的东西 | 第一反应 |
|---|---|
| 交叉编译报找不到 `stdio.h` | 查 sysroot 配没配对，**不要**拿宿主机的 `/usr/include` 顶上 |
| 想知道到底用了哪份 `libc.so` | `arm-linux-gnueabihf-gcc -print-file-name=libc.so`，别凭目录名猜 |
| `file libc.so` 显示是文本 | 它是链接脚本，不是库本体；打开看它指向哪几个文件 |
| 换平台后结构体或二进制文件读写错位 | 查类型大小、对齐、字节序；跨平台的数据格式要自己写死，别赖 ABI |
| 开发机链接通过，上板报缺库或版本不对 | 构建时用的材料和板子上实际装的对不上；查板子的加载器和库版本 |

想补原理时：API/ABI 和类型大小看第一、二节，sysroot 看第三至六节，
三个参数看第七节。

---

**前置：[00 从源码到运行](00_从源码到运行.md)** 和
**[02 ARM 寄存器与调用约定](02_ARM寄存器与调用约定.md)。**
02 篇实测出来的"参数放哪、谁保存寄存器"，正是本篇要讲的 ABI 的头几条。

被 01 章第 2 节用到。

实验目录：`labs/00_basics/04_abi_and_regs/`（和 02 篇共用）
所有输出是 2026-09-08 本机实跑，`arm-linux-gnueabihf-gcc 15.2.0`。

---

## 一、两个只差一个字母的词

    API (Application Programming Interface)     源码层面的约定
    ABI (Application Binary Interface)          机器码层面的约定

**API 是你写代码时看的东西：**

```c
int open(const char *path, int flags);
```

这行声明告诉你：函数叫 `open`，收一个字符串和一个整数，返回整数。
**换编译器、换优化等级、换目标架构，这行都不用改。**

**ABI 是编译完之后、字节层面的约定：**

    path 放 r0，flags 放 r1，返回值在 r0        <- 02 篇 2.3 实测过
    r4-r11 调用前后必须保持原值                  <- 02 篇 3.3 实测过
    浮点参数走 s0/s1 还是 r0/r1                  <- 02 篇 5.3 实测过
    long 占 4 字节还是 8 字节
    struct { char a; int b; } 占几个字节
    栈往低地址长，调用前 sp 要 8 字节对齐        <- 02 篇 2.5 那个 sub sp,#12

**你写代码时看不见 ABI，但两个 `.o` 要链到一起，ABI 就必须逐条一致。**

02 篇第六节已经实测过不一致的下场：链接器直接拒绝，
报 `uses VFP register arguments`。**那就是 ABI 冲突的现场。**

> **ABI**：编译产物之间的二进制接口约定。
> ARM 上这份文档叫 **AAPCS**（Procedure Call Standard for the ARM Architecture）。

ABI 具体管这七件事：

    1. 参数怎么传          前 4 个整数走 r0-r3，多的压栈；浮点走哪要看 -mfloat-abi
    2. 返回值怎么给        32 位放 r0，64 位放 r0:r1，大结构体由调用方给一块内存
    3. 哪些寄存器要保存    r4-r11 是 callee-saved
    4. 基本类型的大小和对齐  long 是 4 还是 8，double 要不要 8 字节对齐
    5. 结构体怎么排布      成员之间怎么填充，位域怎么塞
    6. 栈帧长什么样        异常怎么展开（backtrace 靠这个）
    7. 名字修饰            C++ 的 name mangling

    第 1、2、3 条 02 篇已经全部实测过。第 4 条本篇第二节测。

---

## 二、实验 1：同一行 C 代码，两个平台的字节数不同

### 2.1 先自己想

上面第 4 条说"long 是 4 还是 8"。**怎么验证？**

本机 x86-64 好办，写个 `printf("%zu", sizeof(long))` 跑一下就行。
**但 ARM 程序在 x86 上跑不了**（01 篇 2.3 节：`e_machine` 对不上）。

板子还没接、也不想为了问一个数字就烧一次板。**有没有办法在编译期问出来？**

有。C 有个编译期断言：

    _Static_assert(条件, "消息");

条件为真就什么都不发生，为假就**编译报错**。
**把它当探针用：编得过说明条件成立，编不过说明不成立。**

### 2.2 动手

先量本机的：

```c
#include <stdio.h>
#include <time.h>

int main(void)
{
	printf("char=%zu short=%zu int=%zu long=%zu longlong=%zu ptr=%zu time_t=%zu\n",
	       sizeof(char), sizeof(short), sizeof(int), sizeof(long),
	       sizeof(long long), sizeof(void *), sizeof(time_t));
	printf("struct{char a; int b;} = %zu\n", sizeof(struct { char a; int b; }));
	return 0;
}
```

    gcc sizes.c -o sizes_x86 && ./sizes_x86

再用断言问 ARM 的：

```bash
for t in "sizeof(long)==8" "sizeof(long)==4" "sizeof(void*)==4" "sizeof(void*)==8"; do
    printf '_Static_assert(%s, "no");\nint main(void){return 0;}\n' "$t" > q.c
    if arm-linux-gnueabihf-gcc -c q.c -o /dev/null 2>/dev/null; then
        echo "  ARM: $t   成立"
    else
        echo "  ARM: $t   不成立"
    fi
done
```

    printf '...' > q.c     现场生成一个只有两行的 C 文件
    -c ... -o /dev/null    只要知道编不编得过，产物直接扔掉
    2>/dev/null            报错信息不用看，看退出码就够了
    if 命令; then          shell 里直接拿命令的退出码当条件：0 为真

### 2.3 本机实测

```
=== 本机 x86-64 实跑 ===
char=1 short=2 int=4 long=8 longlong=8 ptr=8 time_t=8
struct{char a; int b;} = 8

=== ARM 32 位：跑不了，用编译期断言问它 ===
  ARM: sizeof(long)==8    不成立
  ARM: sizeof(long)==4    成立
  ARM: sizeof(void*)==4   成立
  ARM: sizeof(void*)==8   不成立
```

### 2.4 逐条读

**同一个 `long`，x86-64 上 8 字节，ARM 32 位上 4 字节。**

    类型        x86-64      ARM 32 位
    --------    --------    ---------
    long        8           4
    void *      8           4
    int         4           4
    long long   8           8

**这意味着什么？** 假设一个结构体里有个 `long`：

```c
struct config { int id; long offset; };
```

    在 x86 上编：id 占 0-3，offset 占 8-15（要 8 字节对齐），总共 16 字节
    在 ARM 上编：id 占 0-3，offset 占 4-7，              总共 8 字节

**两边对同一个结构体的理解差了一倍。** 如果一边写、一边读（比如通过共享内存、
或者一个配置文件），读出来的全是错位的垃圾。**而编译期不会有任何警告。**

**顺便注意 `struct{char a; int b;} = 8` 这个数**：一个 char（1 字节）
加一个 int（4 字节）明明是 5 字节，实际占 8。中间填了 3 字节，
好让 `int b` 落在 4 字节对齐的位置上。**这是 ABI 第 5 条在起作用。**

**`_Static_assert` 这个技巧值得单独记住**：
目标平台的程序跑不了时，用它在编译期问出任何"编译器知道的常量"。
第 2 阶段编内核模块时会反复用到。

### 2.5 判据

    [ ] x86-64 上 long=8、ptr=8
    [ ] ARM 上 sizeof(long)==4 成立、==8 不成立
    [ ] struct{char;int;} 是 8 字节而不是 5 字节，能说出多出来的 3 字节是什么
    [ ] 能说出 _Static_assert 为什么可以问出"跑不了的平台"上的数值

    注错见红：把断言写成 sizeof(long)==4 却用本机 gcc 编：

        printf '_Static_assert(sizeof(long)==4,"no");\nint main(void){return 0;}\n' > q.c
        gcc -c q.c -o /dev/null

    必须报错。**如果它编过了，说明你的探针根本没生效**（比如写成了
    static_assert 但没 include，或者被宏吃掉了）——
    那么前面所有"成立"的结论全部作废，因为它们可能只是"没报错"而不是"真成立"。

---

## 三、sysroot：材料库在哪

### 3.1 编译需要哪些材料

00 篇讲过，编译一个程序不只是翻译你写的代码。至少还要三类外来材料：

    头文件      stdio.h 里 FILE 结构体的布局
    库文件      libc.so / libc.a，链接时要用
    启动文件    crt1.o crti.o crtn.o —— 00 篇 4.2 节在 app.map 里见过它们，
                _start 就在里面

**这三类东西必须是目标平台的。** 为什么？看第二节的结论：

```
    你 Ubuntu 上的 /usr/include/stdio.h 里，FILE 结构体是按 x86-64 排的
        （里面有一堆 long 和指针，每个 8 字节）
              |
              | 如果拿它给 ARM 编译
              v
    编出的 ARM 代码按 x86-64 的字段偏移去访问 FILE
              |
              | 拷到板子上，板子的 libc 按 ARM 的偏移排（每个 4 字节）
              v
    fread 读出来的全是错位的垃圾，而编译期零警告
```

> **sysroot**：目标系统的根目录。编译器去找头文件和库时，
> 会自动在路径前面拼上它。换一个 sysroot，整套材料库就换了。

    <sysroot>/
        usr/include/     目标平台的头文件
        usr/lib/         目标平台的库
        lib/             动态链接器 ld-linux-armhf.so.3（01 篇 5.3 见过）

### 3.2 动手：问编译器材料在哪

编译器有一批 `-print-` 选项，专门回答这类问题：

    arm-linux-gnueabihf-gcc -print-file-name=libc.so    # 某个文件的完整路径
    arm-linux-gnueabihf-gcc -print-file-name=crt1.o
    arm-linux-gnueabihf-gcc -print-sysroot              # sysroot 在哪
    gcc -print-file-name=libc.so                        # 对照：本机编译器

### 3.3 本机实测

```
ARM libc.so : /usr/lib/gcc-cross/arm-linux-gnueabihf/15/../../../../arm-linux-gnueabihf/lib/libc.so
ARM crt1.o  : /usr/lib/gcc-cross/arm-linux-gnueabihf/15/../../../../arm-linux-gnueabihf/lib/crt1.o
ARM sysroot : /
x86 libc.so : /usr/lib/gcc/x86_64-linux-gnu/15/../../../x86_64-linux-gnu/libc.so
```

那串 `../../../..` 看着头晕，用 `readlink -f` 化简（它会把路径里的
`..` 和符号链接全部解开）：

```
$ readlink -f "$(arm-linux-gnueabihf-gcc -print-file-name=libc.so)"
/usr/arm-linux-gnueabihf/lib/libc.so

$ readlink -f "$(gcc -print-file-name=libc.so)"
/usr/lib/x86_64-linux-gnu/libc.so
```

**两个编译器各去各的目录，谁也不碰谁。**

**注意 `-print-sysroot` 返回的是 `/`。** 这台机器上 sysroot 就是根目录 ——
因为 Debian/Ubuntu 用的是 multiarch 布局，把多个架构的库并排装在同一棵树里，
靠目录名区分。第 2 阶段换成板子 BSP 的工具链时，这里会返回一个很长的真实路径。

    Debian/Ubuntu multiarch                    buildroot / BSP 独立 sysroot
    -----------------------------------        ------------------------------
    /usr/arm-linux-gnueabihf/lib/    ARM        <sysroot>/usr/lib/
    /usr/lib/x86_64-linux-gnu/       x86        <sysroot>/usr/include/
    -print-sysroot 返回 /                       返回一个很长的真实路径
    apt install 就能装                          跟着 BSP 一起发布
    本阶段用这个                                第 2 阶段编内核模块必须用这个

---

## 四、实验 2：libc.so 竟然不是一个库

### 4.1 先自己想

上一节查到 `libc.so` 在 `/usr/arm-linux-gnueabihf/lib/libc.so`。
**验证一下它是不是 ARM 的库** —— 用 `file` 看文件类型，
应该报 "ELF 32-bit ... ARM"。

    file -L "$(arm-linux-gnueabihf-gcc -print-file-name=libc.so)"

    -L  跟随符号链接看真身（这个文件很可能是个链接）

### 4.2 本机实测

```
类型: ASCII text
```

**不是 ELF，是一个文本文件。**

（这条推翻了本篇上一版写的判据"file 一下是 ELF 32-bit ARM"。
那条判据是照常理写的，从没跑过。）

既然是文本，直接看内容：

```
$ cat /usr/arm-linux-gnueabihf/lib/libc.so
/* GNU ld script
   Use the shared library, but some functions are only in
   the static library, so try that secondarily.  */
OUTPUT_FORMAT(elf32-littlearm)
GROUP ( /usr/arm-linux-gnueabihf/lib/libc.so.6
        /usr/arm-linux-gnueabihf/lib/libc_nonshared.a
        AS_NEEDED ( /usr/arm-linux-gnueabihf/lib/ld-linux-armhf.so.3 ) )
```

### 4.3 逐行读

**它是一个给链接器看的脚本。** 三行各有用处：

    OUTPUT_FORMAT(elf32-littlearm)
        产物必须是 32 位小端 ARM 的 ELF。
        架构信息直接写在这里 —— 01 篇 2.3 节 e_machine 那两个字节的来源之一

    GROUP ( libc.so.6  libc_nonshared.a  ... )
        链接 -lc 时，实际上要同时用这几个：
          libc.so.6          真正的共享库（绝大部分函数在这）
          libc_nonshared.a   少数函数只有静态版（注释里那句
                             "some functions are only in the static library"）

    AS_NEEDED ( ld-linux-armhf.so.3 )
        动态链接器。01 篇 3.2 节 readelf -l 里 INTERP 那行指的就是它

**所以 `-lc` 不是"链接一个文件"，而是"按这张单子链接三样东西"。**

真正的 ELF 是 `libc.so.6`：

```
$ readlink -f "$(arm-linux-gnueabihf-gcc -print-file-name=libc.so.6)"
/usr/arm-linux-gnueabihf/lib/libc.so.6
    ELF 32-bit LSB shared object, ARM, EABI5 version 1 (GNU/Linux), dynamically linked

$ arm-linux-gnueabihf-gcc -print-file-name=libc.a
/usr/arm-linux-gnueabihf/lib/libc.a
    current ar archive          <- .a 是打包格式，见 04 篇
```

**这条的教训**：`.so` 后缀不保证是 ELF。
遇事先 `file` 一下，别按后缀想当然 —— 我按常理写的判据就错在这。

### 4.4 判据

    [ ] file 报 libc.so 是 ASCII text，不是 ELF
    [ ] 它的内容里有 OUTPUT_FORMAT(elf32-littlearm) 和 GROUP
    [ ] libc.so.6 才是 ELF 32-bit ARM
    [ ] 能说出 GROUP 里那三个文件各是干什么的

    注错见红：对本机的 x86 版做同样的事：

        file -L "$(gcc -print-file-name=libc.so)"

    本机实测同样是 ASCII text，内容里是 OUTPUT_FORMAT(elf64-x86-64)。
    **两边都是链接脚本，只是 OUTPUT_FORMAT 那一行不同** ——
    正好证明这一行就是架构标记。

---

## 五、实验 3：两个编译器的搜索路径有没有交集

### 5.1 先自己想

第三节说"两个编译器各去各的目录"。**这句话能不能验证得更彻底一点 ——
它们的头文件搜索路径列表，有没有哪怕一条是重合的？**

怎么让 gcc 把搜索路径列出来？

    线索：预处理阶段（-E）负责找头文件，加上 -v（verbose）它会把
          内部动作全打出来（00 篇 2.2 用过同一招）。
          但 -E 需要一个输入文件 —— 能不能不建文件？
          提示：Unix 工具里 - 表示"从标准输入读"。

### 5.2 动手

```bash
echo 'int main(){}' | arm-linux-gnueabihf-gcc -E -v - 2>&1 \
    | sed -n '/search starts here/,/End of search/p'
```

    echo ... |      造一个最小的 C 程序从管道喂进去，不用建文件
    -E              只预处理
    -v              打印内部动作
    -               从标准输入读
    2>&1            这些信息走的是 stderr，要合并到 stdout 才能进管道
    sed -n '/起/,/止/p'   只留这两行之间的内容

两个编译器直接对比：

```bash
diff <(echo 'int main(){}' | arm-linux-gnueabihf-gcc -E -v - 2>&1 | sed -n '/search starts/,/End of/p') \
     <(echo 'int main(){}' | gcc                     -E -v - 2>&1 | sed -n '/search starts/,/End of/p')
```

    <(命令)   进程替换：把命令的输出当成一个临时文件名交给 diff

### 5.3 本机实测

```
3,4c3,5
<  /usr/lib/gcc-cross/arm-linux-gnueabihf/15/include
<  /usr/lib/gcc-cross/arm-linux-gnueabihf/15/../../../../arm-linux-gnueabihf/include
---
>  /usr/lib/gcc/x86_64-linux-gnu/15/include
>  /usr/local/include
>  /usr/include/x86_64-linux-gnu

（diff 退出码 1，非 0 表示两边确实不同）
```

### 5.4 逐条读

**`3,4c3,5` 是 diff 的记法**：左边文件的第 3-4 行，
对应右边文件的第 3-5 行，内容不同（c = change）。
`<` 开头是左边（ARM）独有，`>` 开头是右边（x86）独有。

    ARM 编译器去：  .../gcc-cross/arm-linux-gnueabihf/15/include
                    .../arm-linux-gnueabihf/include

    x86 编译器去：  .../gcc/x86_64-linux-gnu/15/include
                    /usr/local/include
                    /usr/include/x86_64-linux-gnu

**关键在没被 diff 列出来的那些行 —— 那是两边相同的。**
其中有 `/usr/include`：**这一条是两边共用的。**

这不矛盾：`/usr/include` 下放的是架构无关的头（比如 `stdio.h` 的骨架），
架构相关的部分被拆到了 `bits/` 子目录里，
由各自的 `arm-linux-gnueabihf/include` 或 `x86_64-linux-gnu` 提供。
**这正是 multiarch 布局的设计：共用的共用，不共用的分开。**

### 5.5 判据

    [ ] ARM 那边出现 gcc-cross 和 arm-linux-gnueabihf
    [ ] x86 那边出现 x86_64-linux-gnu
    [ ] diff 退出码非 0（两边确实不同）
    [ ] 找出至少一条两边共有的路径，并说出为什么它可以共用

    注错见红：把 diff 的两条命令都改成 ARM 编译器。
    diff 应当输出为空、退出码 0。**判据本身要能区分"真的不同"和
    "我的对比方法有问题"。**

---

## 六、实验 4：故意用错头文件

### 6.1 先自己想

第三节论证过"用 x86 的头文件给 ARM 编译会出错位的垃圾"。
**那实际做一次会怎样？会静默出错，还是会报错？**

用 `-I` 把 x86 的头文件目录塞到搜索列表最前面就能试。

### 6.2 动手

```bash
cat > t.c <<'EOF'
#include <stdio.h>
int main(void) { printf("hello\n"); return 0; }
EOF

arm-linux-gnueabihf-gcc -c t.c -o t.o                              # 正常
arm-linux-gnueabihf-gcc -I/usr/include/x86_64-linux-gnu -c t.c     # 塞入 x86 头
```

### 6.3 本机实测

```
=== 正常编译 ===
成功

=== 强行把 x86 的头文件目录塞到最前面 ===
In file included from /usr/arm-linux-gnueabihf/include/features.h:563,
                 from /usr/include/x86_64-linux-gnu/bits/libc-header-start.h:33,
                 from /usr/arm-linux-gnueabihf/include/stdio.h:28,
                 from t.c:1:
/usr/include/x86_64-linux-gnu/gnu/stubs.h:7:11: fatal error: gnu/stubs-32.h: No such file or directory
    7 | # include <gnu/stubs-32.h>
      |           ^~~~~~~~~~~~~~~~
compilation terminated.
退出码=1
```

### 6.4 逐条读

**这次运气好，它报错了。** 顺着报错里的 "In file included from" 链看，
能看出混搭是怎么发生的：

    t.c 第 1 行
      -> ARM 的 stdio.h            （对的）
        -> x86 的 libc-header-start.h   （错的！被 -I 抢先找到了）
          -> ARM 的 features.h      （又回到对的）
            -> x86 的 gnu/stubs.h   （又错）
              -> gnu/stubs-32.h     找不到，编译中止

**ARM 的头和 x86 的头交替 include，最后卡在一个不存在的文件上。**

**但要注意：这次报错是运气。** 报错的原因是"文件找不到"，
不是"我发现你混用了架构"。**编译器没有任何机制检测这件事。**

如果两边的头文件恰好都存在、只是内容不同（比如结构体字段偏移不同），
**它会安安静静编过，编出一个运行时行为错乱的程序** ——
这正是 3.1 节那张图描述的情形，而且是最难查的一类问题。

**所以交叉编译时的规矩是：**

    永远不要手动指定 -I/usr/include 或 -L/usr/lib
    工具链自己知道去哪找，别帮倒忙

第 6 章交叉编译 freetype 时会真踩到这条：
`configure` 脚本很容易把宿主机的路径混进去。

### 6.5 判据

    [ ] 不加 -I 时编译成功
    [ ] 加了 x86 的 -I 之后编译失败
    [ ] 报错里的 include 链能看出 ARM 的头和 x86 的头在交替出现
    [ ] 能说出"这次报错是运气"的理由

    注错见红：把 -I 换成一个不存在的目录：

        arm-linux-gnueabihf-gcc -I/nonexistent -c t.c -o t.o

    本机实测编译成功 —— gcc 对不存在的 -I 目录一声不吭地跳过。
    **所以"编译成功"不能证明你的 -I 写对了。**

---

## 七、-I / -L / -l 分别在管什么

前面各节反复用到这三个选项，集中说明一次：

    选项        管什么              在哪个阶段起作用
    --------    ----------------    ----------------------------
    -I<dir>     加一个头文件目录    预处理阶段，找 #include
    -L<dir>     加一个库目录        链接阶段，找 .so / .a
    -l<name>    链接 lib<name>      链接阶段

一条完整的命令：

    gcc -I./include -L./lib -o app main.c -lfreetype -lm
        ^^^^^^^^^^^ 去哪找 .h
                    ^^^^^^^^^ 去哪找库文件
                                            ^^^^^^^^^^^^^^^^ 链接哪些库

**三个坑：**

1. **`-l` 要放在源文件后面。** 链接器从左往右扫描，`-lm` 放在前面时
   它还不知道谁需要 `m` 里的符号，扫过去就丢掉了。
   现象是 `undefined reference to 'sqrt'` —— 00 篇 3.5 那个报错。

2. **`-lfreetype` 找的是 `libfreetype.so`。** 前缀 `lib` 和后缀 `.so`
   是链接器自己加的，中间那截才是名字。

3. **交叉编译时 `-L` 千万别指到 `/usr/lib`**，那是 x86 的库。
   第六节讲过为什么。

**头文件搜索顺序：**

    1. -I 指定的目录，按命令行出现的顺序
    2. 工具链自带的目录（gcc 内建 + sysroot）
    3. /usr/include（multiarch 布局才有这一条）

    #include "xxx.h"  引号：先找当前源文件所在目录，再走上面三步
    #include <xxx.h>  尖括号：跳过第一步

---

## 八、顺带一提：和 ysyx 的对照

**没做过 ysyx 也不影响，跳过即可。**

    ysyx / abstract-machine              Linux 交叉编译
    ---------------------------------    ------------------------------
    没有 sysroot 这个概念                必须有
    因为 libc 是 am 自己写的 klib        因为 libc 是别人（glibc）编好的
    头文件就在项目目录里                  头文件在工具链自带的一棵目录树里
    编译时 -I$(AM_HOME)/klib/include     工具链自动带上 sysroot 路径

**ABI 你其实已经踩过一次**：RISC-V 的 `ilp32` / `ilp32f` / `ilp32d`，
和 ARM 的 `soft` / `softfp` / `hard` 是同一件事的两套命名
（02 篇第八节有对照表）。改了这个整个 am 要重编，
原因和 02 篇 6.4 节讲的完全一样。

---

## 九、被谁用到

    01 章 2         交叉编译的三件事
    01 章 4.2       GLIBC 版本不匹配
    [02 ARM 寄存器与调用约定](02_ARM寄存器与调用约定.md)  ABI 的第 1-3 条在那里实测
    [04 静态库动态库与符号](04_静态库动态库与符号.md)      .a 和 .so 的区别
    06 章           交叉编译 freetype，第一次真正自己指定 -I 和 -L
    第 2 阶段       换成 BSP 工具链，sysroot 变成一棵真实的板子根文件系统
