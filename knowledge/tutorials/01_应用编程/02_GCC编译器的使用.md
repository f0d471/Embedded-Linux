# 02 GCC 编译器的使用

    PDF     第 143-153 页（目录页 134-144），第四篇第 2 章
    视频    4_2-1、4_2-2 共 2 集，分集表见 sources/README.md
    源码    $Q\04_嵌入式Linux应用开发基础知识\source\02_options\

> [占位] 本篇由旧《01_工具链与构建系统》按原书章节拆出，正文仍是旧导学体例，
> 正在按 knowledge/README.md 的新教程体例重写。节号与自检/坑编号沿用旧稿原样；
> 实验环境与上板配置暂见 01 篇 0.4 节。

## 0.2 过滤表（本篇对应集）

**第二段 GCC（视频 4_2-1、4_2-2，PDF 143-153）**

| 集 | 时间段 | 看不看 | 内容 |
|---|---|---|---|
| 4_2-1 | 0:00-1:00 | 跳 | 铺垫 |
| 4_2-1 | 1:00-5:20 | **重点** | 四个步骤是怎么被逼出来的：电工接线 → 纸带打孔 → 汇编助记符 → 高级语言。这段是全集最有价值的五分钟 |
| 4_2-1 | 5:20-11:30 | **看** | `gcc -v` 里看见 `cc1`、`as`、`collect2` 三个内部程序 |
| 4_2-1 | 11:30-16:00 | **看** | 手工走四步：`-E` / `-S` / `-c` / 不加参数 |
| 4_2-1 | 16:01-16:44 | **看** | "编译"这个词在中文里指三个不同的范围 |
| 4_2-1 | 16:44-17:35 | **看** | 语法错误是在哪一步被发现的（现场演示） |
| 4_2-2 | 0:00-6:20 | **看** | 一条命令编多个文件 vs 分开编再链接，以及为什么必须分开 |
| 4_2-2 | 6:20-10:30 | **看** | `-I`：头文件去哪找 |
| 4_2-2 | 10:30-16:30 | **重点** | 现场做一个静态库和一个动态库，`-L` / `-l` |
| 4_2-2 | 17:10-18:33 | **重点** | 动态库运行时找不到，`LD_LIBRARY_PATH`。链接时和运行时是两回事 |
| 4_2-2 | 18:33-20:25 | **看** | 小结：头文件 / 链接时的库 / 运行时的库，三处都是“有默认路径也可以自己指定” |
| 4_2-2 | 21:02-21:20 | **看** | 不写 `.c` 也能问出默认搜索路径的技巧 |
| 4_2-2 | 21:20-23:04 | 快进 | `-M` 系列选项，第三段会详细讲 |

PDF 这一章 145-153 页有一大段是从书里截来的选项清单，
视频里明说了"这些内容是从以前我写的书里面截取出来的，有需要的人可以去看"。
不用逐条读，当手册用，要查的时候再翻。

---

## 3 第二段：GCC 的四个步骤与"去哪找"

### 3.0 看哪里

    视频    4_2-1（17 分）、4_2-2（23 分），过滤表见 0.2
    PDF     143-153 页。145 页往后那一大段选项清单是从书里截的，当手册用
    源码    $Q\04_...\source\02_options\

### 3.1 第一性原理：四个步骤是被历史逼出来的

视频 4_2-1 的 1:00 到 5:20 那五分钟是这一集最有价值的部分，
它没有从"预处理、编译、汇编、链接"讲起，而是反过来推：

| 演进阶段 | 解决了什么 | 又留下什么问题 | 对应术语 |
|---|---|---|---|
| 开关和电线 | 直接控制机器 | 操作太累 | — |
| 纸带机器码 | 把操作记录下来 | 仍要记住每条机器码的每一位 | — |
| 英文助记符 | 用人能读的名字表示机器码 | 汇编指令仍太多、太琐碎 | 助记符 → 机器码叫“汇编” |
| C / C++ | 用更高层表达描述程序 | 需要翻译成汇编 | 高级语言 → 汇编叫“编译” |
| 多文件组装 | 把各文件生成的机器码合成程序 | 需要处理跨文件地址和符号 | 多个 `.o` → 一个 app 叫“链接” |
| 预先处理源码 | 展开 `#include`、替换 `#define` | 交给后续编译 | `.c + .h` → `.i` 叫“预处理” |

**所以四个步骤不是设计出来的，是每一层抽象各自留下的一道翻译。**
记住这条推导链，比记住四个名词有用得多：
以后看到任何一个新工具链（Rust、Go、Verilog 综合器），
第一个问题都是"它把哪几层抽象各自翻译到哪里"。

反过来的那一步也有名字：机器码变回汇编叫**反汇编**，调试时会用到。

| 步骤 | 工具 | 输入 → 输出 | 关键变化 |
|---|---|---|---|
| 预处理 | `cpp` | `hello.c` → `hello.i` | 展开 `#include`、替换 `#define`、按 `#ifdef` 裁剪；结果仍是 C |
| 编译 | `cc1` | `hello.i` → `hello.s` | C 变为汇编助记符 |
| 汇编 | `as` | `hello.s` → `hello.o` | 变为机器码；地址未定，外部符号仍为空 |
| 链接 | `ld` | 多个 `.o` + 库 + 启动代码 → `hello` | 生成完整可执行文件 |

### 3.2 [做 L1] 亲手拆开四步，并看见 gcc 内部的三个程序

**先自己想：**

    问题 1  gcc 一条命令就编完了，怎么让它停在中间某一步？
            线索：三个选项，各对应一个停点。想想产物的扩展名是什么。
    问题 2  怎么看见 gcc 内部到底调了哪几个程序？
            线索：还是 2.4 那个"啰嗦模式"开关。
    问题 3  语法错误是在哪一步被发现的？先猜，再验。
            线索：预处理只做文本替换，它需要理解 C 语法吗？

答案：

    gcc -E hello.c -o hello.i    # 只预处理。-E 的 E 是 Expand/prEprocess
    gcc -S hello.i -o hello.s    # 只编译到汇编。大写 S
    gcc -c hello.s -o hello.o    # 只汇编。小写 c
    gcc    hello.o -o hello      # 不加参数就是链接

    gcc -v -o hello hello.c 2>&1 | grep -E 'cc1|/as |collect2'
    #   ^^ 把内部调用的每一条命令都打出来

**本机实测**，`-v` 里出现的内部程序（路径已简化）：

    /usr/libexec/gcc/x86_64-linux-gnu/15/cc1          预处理 + 编译，一个程序干两件事
    as                                                 汇编
    /usr/libexec/gcc/x86_64-linux-gnu/15/collect2      链接的外壳，它再去调 ld

ARM 那边同样三个，路径不同：

    /usr/libexec/gcc-cross/arm-linux-gnueabihf/15/cc1
    /usr/lib/gcc-cross/arm-linux-gnueabihf/15/../../../../arm-linux-gnueabihf/bin/as
    /usr/libexec/gcc-cross/arm-linux-gnueabihf/15/collect2

**注意 `cc1` 一个程序干了预处理和编译两件事。** 视频 4_2-1 的 7:21 处就是
在这里卡了一下："显然这一步又做了预处理和编译这两个工作"。
四个逻辑步骤，三个实际程序。

**本机实测**，四步产物的规模（`hello.c` 就是 2.5 那个，加上 `#include <stdio.h>`）：

    hello.c      2 行
    hello.i    840 行        <-- stdio.h 整个被展开进来了
    hello.s     45 行        <-- 变回很短，因为 840 行里绝大部分是声明，不产生代码
    hello.o   1480 字节
    hello    15952 字节

**2 行变 840 行再变 45 行**，这三个数把预处理在干什么讲清楚了：
它把头文件的全部内容原样贴进来，而头文件里绝大部分是函数声明和类型定义，
不产生任何机器码。

`hello.i` 里值得看两处：

    head -20 hello.i        # 开头是一堆 # 1 "xxx.h" 的行标记，
                            # 告诉编译器"下面这些行来自哪个文件的第几行"，
                            # 报错时的文件名行号就是从这来的
    grep -n 'int main' hello.i    # main 在最后面，前面全是展开进来的声明

问题 3 的答案：**预处理不检查语法。** 视频 4_2-1 的 16:54 处现场验了这个：
往 `.c` 里故意插一个语法错误，`gcc -E` 一声不吭，`gcc -S` 才报错。
道理是预处理只做文本替换，它不需要理解 C 语法。

自己验一遍：

    cp hello.c hello_bad.c
    echo 'this is not c' >> hello_bad.c
    gcc -E hello_bad.c -o /dev/null; echo "预处理 exit=$?"
    gcc -S hello_bad.c -o /dev/null; echo "编译   exit=$?"

**顺便一个中文的坑。** "编译"这个词在中文里指三个不同的范围，
视频 4_2-1 的 16:17 处专门提了这件事：

    窄义   .i -> .s 那一步
    中义   预处理 + 编译 + 汇编（也就是 gcc -c 干的事）
    宽义   四步全部（也就是 gcc 一条命令干的事）

读文档时要看上下文。本笔记里凡是需要精确区分的地方都写全称。

### 3.3 一次编多个文件，和分开编再链接

视频 4_2-2 的 0:00 到 6:20 讲的是这件事，它是第 4 节 Makefile 存在的全部理由。

一条命令编两个文件：

    gcc -o test main.c sub.c

它内部做的是：

| 源文件 | 预处理、编译、汇编的临时产物 | 最后一步 |
|---|---|---|
| `main.c` | `/tmp/xxxx.o` | 与下一行的 `.o` 一起链接成 `test` |
| `sub.c` | `/tmp/yyyy.o` | 与上一行的 `.o` 一起链接成 `test` |

中间那两个 `.o` 在 `/tmp` 下，用完就删。**代价是每次都要全部重做一遍。**
视频里把它推到极端：一千个文件，改一个，另外 999 个也要重新处理。

分开编：

    gcc -c -o main.o main.c        # -c 编译不链接，产物留下来
    gcc -c -o sub.o  sub.c
    gcc -o test main.o sub.o       # 只链接

改了 `main.c` 之后只需要重跑第一条和第三条。

**问题是：谁来判断"只需要重跑第一条和第三条"？**
手工判断，文件一多就判断不过来。这就是 make 存在的理由，第 4 节接着讲。

### 3.4 四个"去哪找"

视频 4_1-2 和 4_2-2 反复讲的是同一件事的四个实例。
把它们放在一张表里，这一段就压缩完了：

    找什么                 谁去找        默认去哪找                 怎么加自己的
    ---------------------  ------------  -------------------------  ------------------
    头文件 <stdio.h>       预处理器      工具链的 include 目录      -I<目录>
    头文件 "myhead.h"      预处理器      先当前目录，再同上         -I<目录>
    库文件 libsub.so       链接器        工具链的 lib 目录          -L<目录> 加 -l<名>
    动态库（运行时再找）   ld.so         /lib、/usr/lib 等          LD_LIBRARY_PATH

**最后一行是最容易漏的一条：链接时找得到，不代表运行时找得到。**
这两件事由两个不同的程序、在两个不同的时刻、按两套不同的规则去找。

`-l` 的名字规则：`-lsub` 找的是 `libsub.so` 或者 `libsub.a`，
前面的 `lib` 和后面的后缀都省略掉。

两个最常见的报错，各对应表里的一行：

    fatal error: xxx.h: No such file or directory      头文件没找到  -> 加 -I
    undefined reference to `xxx'                        符号没找到    -> 加 .o 或 -l
    error while loading shared libraries: libxxx.so     运行时没找到  -> LD_LIBRARY_PATH

视频 4_1-2 的 4:32 处把前两个称为"你会经常发现的两个问题"。

### 3.5 [做 L2] 现场做一个静态库和一个动态库

**先自己想：**

    问题 1  静态库和动态库，哪个在链接的时候被复制进可执行文件，
            哪个在运行的时候才加载？
    问题 2  一个只有两个文件的小程序，做成静态库和动态库，
            最终可执行文件的体积会差多少？先猜一个数量级，再跑。
    问题 3  动态库版本编好之后直接跑，会成功还是失败？为什么？

自己敲两个文件：

    /* sub.c */
    #include <stdio.h>
    void sub_func(void) { printf("sub\n"); }

    /* main.c */
    void sub_func(void);
    int main(void) { sub_func(); return 0; }

    注意 main.c 里用的是"声明"而不是 #include。这是 4_1-2 讲的
    .h 声明 / .c 定义分工的最小演示：编译 main.c 时编译器只需要知道
    sub_func 长什么样，不需要知道它在哪。"在哪"是链接器的事。

然后：

    # 先各自编成 .o
    gcc -c -o main.o main.c
    gcc -c -o sub.o  sub.c

    # 静态库：本质就是一堆 .o 打包成一个文件
    ar rcs libsub.a sub.o
    #  ^^ archive。r 插入或替换，c 不存在就创建且不警告，s 建符号索引
    gcc -o test_static main.o libsub.a

    # 动态库：需要位置无关代码
    gcc -shared -fPIC -o libsub.so sub.c
    #   ^^^^^^^ 产物是共享库不是可执行文件
    #           ^^^^^ position independent code，
    #                 因为动态库被加载到什么地址运行时才知道
    gcc -o test_shared main.o -L. -lsub
    #                          ^^^ 去当前目录找库
    #                              ^^^^^ 找 libsub.so 或 libsub.a

**本机实测：**

    1352  main.o
    1480  sub.o
    1626  libsub.a          静态库 = sub.o 加上一点索引开销
    15536 libsub.so         动态库大得多，它自带一套完整的 ELF 结构

    16016 test_static       静态链接
    15944 test_shared       动态链接

    两个可执行文件只差 72 字节。

第 2 问的答案多半和你猜的不一样。**这个例子里静态和动态几乎一样大**，
因为 `sub.c` 本身只有一行代码，复制进去也没多少。
视频 4_2-2 的 13:58 处也说了同一件事："小了若干个字节而已，这很正常"。

体积差异要在库很大的时候才显现。3.7 节 `-static` 那个实验里，
把整个 libc 静态链进来，差的就是 7 倍了。

第 3 问，**本机实测：**

    $ ./test_shared
    ./test_shared: error while loading shared libraries: libsub.so:
    cannot open shared object file: No such file or directory

    $ LD_LIBRARY_PATH=. ./test_shared
    sub

链接的时候你用 `-L.` 告诉了链接器库在当前目录，
但那个信息**没有被写进可执行文件**。运行的时候 `ld.so` 按自己的规则去找，
当前目录不在它的搜索列表里。这就是 3.4 表格最后一行说的那件事。

顺便看一眼"符号没找到"长什么样：

    $ gcc -o t main.c
    /usr/bin/ld: /tmp/ccXXXXXX.o: in function `main':
    main.c:(.text+0x9): undefined reference to `sub_func'
    collect2: error: ld returned 1 exit status

    注意报错的是 ld，不是 cc1。编译 main.c 完全没问题——
    它只需要那句声明。是链接这一步找不到实现。

**[判] 第 3.5 节的判据**

    [ ] ar 出来的 libsub.a，用 ar -t libsub.a 能列出里面有 sub.o
    [ ] nm test_static | grep sub_func 显示 T（有实现）
        nm test_shared | grep sub_func 显示 U（未定义，运行时才填）
    [ ] ./test_shared 直接跑失败，加 LD_LIBRARY_PATH=. 之后成功
    [ ] readelf -d test_shared | grep NEEDED 能看到 libsub.so

    注错见红：把 libsub.so 删掉，test_static 照样能跑，test_shared 跑不了。
    这一条最直观地说明了"静态链接把库搬进了自己的文件里"。

### 3.6 printf 到底是谁在干活

`gcc -o hello hello.c` 编出来的 hello 里，没有 printf 的代码。

[基础] 这一节全程在讲符号和链接。符号表的 U/T/W 各是什么、PLT 和 GOT 为什么
存在，见 [00_基础/04_静态库动态库与符号](../00_基础/04_静态库动态库与符号.md)。
那边有本机实测的 PLT 反汇编，三条指令就把跳板讲完了。

**[做 L1] 把 printf 的去向查出来**

先自己想：

    问题 1  怎么看一个可执行文件里都有哪些符号，哪些是"我需要但我没有"的？
            线索：binutils 里有个两字母的工具，name 的缩写。
    问题 2  .interp 段里存的是一个字符串。怎么把某个 section 的内容当字符串打出来？
            线索：readelf 有个 -p 选项，p 是 printable 的意思。
    问题 3  怎么知道这个程序依赖哪些动态库？
            线索：两条路，一条是读 .dynamic 段，一条是有个三字母命令直接列。

答案：

    nm hello_arm | grep -i printf
    #  ^^ 列符号表。输出三列：地址、类型字母、符号名
    #                 类型字母大小写敏感：大写=全局，小写=文件内可见
    #                 U 表示 undefined，这一列会是空白（还没有地址）

    readelf -p .interp hello_arm
    readelf -p .interp hello_x86

    readelf -d hello_arm | grep NEEDED
    #       ^^ -d 读 .dynamic 段，动态链接的所有信息都在这儿

    ldd hello_x86
    #   ^^^ 递归列出所有依赖库及其加载地址
    #   注意：ldd 对 ARM 文件用不了，它是靠真的跑一遍来列的。
    #         交叉编译的产物只能用 readelf -d 看。

**本机实测：**

    $ nm hello_arm | grep -i printf
             U printf@GLIBC_2.4         <-- U 是 Undefined，这个文件里没有它

    $ readelf -p .interp hello_arm
      [     0]  /lib/ld-linux-armhf.so.3

    $ readelf -p .interp hello_x86
      [     0]  /lib64/ld-linux-x86-64.so.2

**从 execve 到 main，中间还插了一个程序：**

| 顺序 | 执行者 | 动作 |
|---|---|---|
| 1 | 内核 `load_elf_binary()` | 发现 `PT_INTERP`，读出 `/lib/ld-linux-armhf.so.3`，把 `ld.so` 映射进来 |
| 2 | 内核 | 跳到 `ld.so` 的 `_start` |
| 3 | 用户态 `ld.so` | 读取 `hello` 的 `.dynamic`，发现 `NEEDED libc.so.6`，把 libc 映射进地址空间 |
| 4 | 用户态 `ld.so` | 重定位：把 GOT 中的 `printf` 表项填成 libc 里的真实地址 |
| 5 | 用户态 `ld.so` | 跳到 `hello` 的 `_start` |
| 6 | 用户态 `hello` | `_start → __libc_start_main → main()` |

所以 `.interp` 段里那个路径不是注释，是内核真的会去读、去加载的一个文件。
**它指定的程序（动态链接器）先于你的 main 运行。**

重定位这一步具体在改什么：

一次 `printf` 外部调用按 `你的代码 → printf@plt 跳板 → .got.plt 中的函数指针 → libc 的 printf 真代码` 前进；`.got.plt` 中的指针由 `ld.so` 在启动时填好。

    编译时 gcc 不知道 printf 在哪，就先跳到自家的跳板；
    跳板去查一张表；表在程序启动时由 ld.so 填好。

**这对嵌入式意味着一条硬约束：** 你交叉编译时链接的 libc，
必须和板子 rootfs 里那份 libc 兼容。

| 位置 | 工具/库 | 结果 |
|---|---|---|
| Ubuntu 开发机 | apt 的 `gcc-arm-linux-gnueabihf` 配较新的 Ubuntu glibc | 生成的 `hello` 可能记录 `printf@GLIBC_2.4`，其他符号可能要求 `GLIBC_2.34` |
| 板子 rootfs | Buildroot glibc 2.30 | `ld.so` 无法满足 `GLIBC_2.34`，程序启动失败 |

    ./hello: /lib/libc.so.6: version GLIBC_2.34 not found

第 2.11 节已经在板上得到这条原样报错和退出码 1。这不是你代码的问题，
是 sysroot 不匹配。两个解法：

    解法 A（本阶段用这个）  加 -static，把 libc 静态链进去，不依赖板子的库
    解法 B（正式用这个）    用板子 BSP 里的 arm-buildroot-linux-gnueabihf-gcc，
                            它配的就是板子上那份 glibc。第 2 阶段必须换成它

### 3.7 [做 L2] -static 的代价

**先自己想：**

    问题 1  怎么让 gcc 把 libc 整个链进来，不依赖外部 .so？
    问题 2  静态之后，四个观察点（体积、.interp、printf 的符号类型、e_type）
            各会变成什么？先写下预测，再跑。预测错了才有收获。

答案：

    arm-linux-gnueabihf-gcc -static -o hello_arm_static hello.c
    #                       ^^^^^^^ 注意位置：放在 -o 前面。
    #                       放到 -o 后面会被当成输出文件名，这是常见错误

    ls -l hello_arm hello_arm_static
    readelf -p .interp hello_arm_static
    nm hello_arm_static | grep -w printf
    #                          ^^ 全词匹配，不然 fprintf、sprintf 都会被捞出来
    readelf -h hello_arm_static | grep Type:

**本机实测：**

| 项目 | 动态 `hello_arm` | 静态 `hello_arm_static` |
|---|---|---|
| 本机体积 | 69,248 字节 | 486,920 字节 |
| ELF 类型 | `ET_DYN` | `ET_EXEC` |
| `.interp` | 有：`/lib/ld-linux-armhf.so.3` | 没有 |
| `.text` | `main`、`printf@plt` 跳板 | `main`、`printf`、`vfprintf`、`malloc`、`strlen` 等完整实现 |
| `.dynamic` | `NEEDED libc.so.6` | 没有这项运行时依赖 |
| 上板运行 | 运行时查找 `/lib/libc.so.6`；版本不符会报 `GLIBC_x.xx not found` | 自包含，不依赖板上 libc |

    $ nm hello_arm_static | grep -w printf
    00010cd5 T printf          <-- 从 U 变成 T，有实际地址了

    $ readelf -p .interp hello_arm_static
    readelf: Warning: Section '.interp' was not dumped because it does not exist

    $ readelf -h hello_arm_static | grep Type:
      Type:  EXEC (Executable file)      <-- 不再是 PIE，没有 ld.so 来做重定位了

代价那一栏别只记"变大了"，记这个量级：**一个 hello world，
为了自带 libc，从 6 万多字节涨到 48 万字节，7.0 倍。**
板子上放几十个这样的程序，rootfs 就撑爆了。
这就是嵌入式上宁可折腾 sysroot 也要用动态链接的原因。

对照 3.5 那个只差 72 字节的实验：静态链接的代价取决于库有多大，
`libsub.a` 只有一行代码，`libc.a` 有整个 C 标准库。

**[判]**

    [ ] 动态版 nm 里 printf 是 U，静态版是 T（或 W）
    [ ] 动态版有 .interp 段，静态版没有
    [ ] 静态版体积是动态版的 5 倍以上
        （本机 486920 / 69248 = 7.0 倍。别背绝对数字，gcc 版本一变就不同）
    [ ] 静态版的 e_type 从 DYN 变成 EXEC，说得出为什么
    [ ] readelf -d hello_arm 能看到 NEEDED libc.so.6，静态版根本没有 .dynamic 段

    注错见红：

        readelf -p .interp hello_arm        2>&1 | grep -c 'ld-linux'
        readelf -p .interp hello_arm_static 2>&1 | grep -c 'does not exist'

    两条都必须是 1。如果第二条是 0，说明 -static 没生效（常见原因：写成了
    -Static，或者放在 -o 后面被当成了输出文件名）。

### 3.8 [做 L2] 绕过 libc，直接跟内核说话

[基础] 用户态怎么请内核干活、`svc` 指令做了什么、缓冲为什么会吃掉你的调试打印，
见 [00_基础/05_系统调用与用户内核态](../00_基础/05_系统调用与用户内核态.md)。
跟 ysyx 的对照：ARM 的 `svc` 就是你实现过的 riscv `ecall`。

视频 4_1-2 的 5:57 处画了三层图：你的 app、库、内核。
下面把那张图的中间一段展开。

`printf` 不是系统调用，`write` 才是：

| 顺序 | 所在层 | 动作 |
|---|---|---|
| 1 | 用户态 libc | `printf` 调 `vfprintf`，解析 `%s` 并拼出 `hello, world\n` |
| 2 | 用户态 libc | 字符串进入 `stdout` 缓冲区；终端常为行缓冲，文件常为全缓冲，`stderr` 无缓冲 |
| 3 | 用户态 libc | 冲刷时调用 `write(1, "hello, world\n", 13)` |
| 4 | 用户态 → 内核态 | ARM 执行 `svc #0`；`r7=4`、`r0=1`、`r1=buf`、`r2=13` |
| 5 | 内核态 | `sys_write()` → tty 驱动 → 串口 → MobaXterm 中的一行字符 |

这张图解释了一个嵌入式调试里天天遇到的现象：**程序跑飞了，printf 的内容一个字
都没出来，好像那行代码没执行。** 其实执行了，字符串还躺在缓冲区里，
程序崩了缓冲区就跟着没了。所以调试打印要么加 `\n`，要么 `fflush(stdout)`，
要么直接用 `write`。上板调试时这一条会救你好几次。

**先自己想：**

    问题 1  write 的三个参数分别是什么？去哪查？
            线索：man 2 write。2 是手册第 2 章，专讲系统调用；
                  man 3 是库函数（printf 在这一章）；man 1 是命令。
                  man 2 write 和 man 3 printf 一对比，
                  谁是系统调用谁是库函数一目了然。
    问题 2  第一个参数填 1 是什么意思？2 又是什么？
    问题 3  长度怎么算？直接写死数字和用 strlen 有什么区别？

自己写 `hello_write.c`：不用 printf，用 write 把同样一句话打到屏幕上。
需要 `#include <unistd.h>`。

写完验证：

    arm-linux-gnueabihf-gcc -o hello_write hello_write.c
    arm-linux-gnueabihf-nm hello_write | grep ' U '
    #                                         ^^^^^ 前后各一个空格，
    #                                         精确匹配类型列是 U 的行
    arm-linux-gnueabihf-objdump -d hello_arm_static | grep -B4 'svc' | head -20
    #                           ^^ 反汇编可执行的 section
    #                                              -B4 匹配行的前 4 行也打出来，
    #                                              好看到 svc 之前往 r7 里装了几号

    # x86 版可以用 strace 直接看系统调用
    gcc -o hello_write_x86 hello_write.c
    strace -e trace=write ./hello_write_x86
    #      ^^^^^^^^^^^^^^ 只跟踪 write，不然满屏都是加载动态库的调用

**[判]**

    [ ] 未定义符号列表里没有 printf 了，但仍然有 write
        （write 也在 libc 里，它是对 syscall 的一层薄封装，不是 syscall 本身）
    [ ] 说得清 printf 和 write 的分工：printf 在用户态做格式化和缓冲，
        最终也是调 write
    [ ] 反汇编里找得到 svc 指令。找法：
            arm-linux-gnueabihf-objdump -d hello_arm        | grep -c 'svc'
            arm-linux-gnueabihf-objdump -d hello_arm_static | grep -c 'svc'
        本机实测：动态版 0 条，静态版 15 条。
        动态版是 0 不是 bug，syscall 封装都在 libc.so.6 里，没链进你的文件；
        静态版把 libc 搬进来了，那 15 条就是 write / exit / brk 这些封装的真身。

    注错见红：把 write(1, ...) 的 fd 从 1 改成 2，输出跑到 stderr。
    验证方式 ./hello_write > /dev/null，改之前屏幕上什么都没有，
    改之后字符串照样出现在屏幕上。这条同时也验证了你确实在用 write 而不是 printf。

---


---

## 6 自检问题

答不上来就回到对应小节重读。这些问题都能用命令验证，不要凭印象答。

    4. gcc 的四个步骤，分别由哪几个内部程序执行？为什么四个步骤只有三个程序？(3.2)

    5. 一个 .c 文件里有语法错误，gcc -E 会报错吗？为什么？                 (3.2)

    6. 头文件找不到、符号未定义、运行时找不到动态库，
       这三个报错各对应哪个阶段？各用什么选项解决？                        (3.4)

    7. 链接时用 -L. -lsub 成功了，运行时却报找不到 libsub.so。
       为什么？两个"找"有什么区别？                                       (3.5)

    8. 一个动态链接的 hello，从 execve 到 main 的第一条指令之间，
       内核和用户态各做了什么？动态链接器是谁加载的？                      (3.6)

    9. 为什么 -static 编出的程序没有 .interp 段，而且 e_type 从 DYN 变回 EXEC？(3.7)

    10. printf 和 write 的分界线在哪？为什么程序崩溃时 printf 的内容
        可能一个字都看不到？                                               (3.8)

---

## 7 已知的坑


    坑 3  apt 工具链和本板 glibc 2.30 已实测不匹配：动态 hello 明确报
          GLIBC_2.34 not found、退出 1。本阶段加 -static 规避，
          第 2 阶段换 BSP 工具链。                                          (3.6)

    坑 4  -static 要放在 -o 前面。放到 -o 后面会被当成输出文件名。           (3.7)

    坑 5  链接时找得到库，不代表运行时找得到。运行时是 ld.so 按另一套规则找。 (3.5)
