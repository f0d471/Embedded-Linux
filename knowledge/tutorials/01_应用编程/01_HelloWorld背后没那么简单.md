# 01 HelloWorld 背后没那么简单

    PDF     第 141-142 页（目录页 132-133），第四篇第 1 章
    视频    4_1-1、4_1-2 共 2 集，分集表见 sources/README.md
    源码    $Q\04_嵌入式Linux应用开发基础知识\source\01_hello\

> [占位] 本篇由旧《01_工具链与构建系统》按原书章节拆出，正文仍是旧导学体例
> （"过滤器"定位、"先自己想"式实验块），正在按 knowledge/README.md 的新教程
> 体例重写。节号与自检/坑编号沿用旧稿原样，第 1 节的脉络图是原三章总图，
> 过滤表已按集拆到各篇。

## 0.2 过滤表（本篇对应集）

**第一段 交叉编译（视频 4_1-1、4_1-2，PDF 141-142）**

| 集 | 时间段 | 看不看 | 内容 |
|---|---|---|---|
| 4_1-1 | 0:00-3:40 | 跳 | `argc` / `argv` 是什么。学过 C 就不用看 |
| 4_1-1 | 3:40-6:00 | 快进 | 用 FileZilla 上传、MobaXterm 登录服务器。本仓在 WSL 里做，不需要 |
| 4_1-1 | 6:01-6:20 | **看** | `file hello` 看出它是 x86 的 |
| 4_1-1 | 6:20-8:00 | **看** | 串口连接：波特率 115200，流控必须关掉 |
| 4_1-1 | 8:00-13:00 | **看** | NFS 挂载，以及第一次挂载卡死的现场（少了 `nolock`） |
| 4_1-1 | 12:25-13:10 | **重点** | 板子上跑 x86 程序，报 Exec format error |
| 4_1-1 | 12:48-15:25 | **看** | 换交叉工具链重编，拷过去能跑 |
| 4_1-2 | 全 7 分钟 | **看** | `.h` 声明与 `.c` 定义的分工；头文件和库"去哪找"；app / 库 / 内核三层 |

### 0.3 四种块

    正文        讲原理；关系复杂时用 Markdown 表格或单列步骤，不靠中文宽度排 ASCII 图。
    [基础]      一个跳转。碰到不认识的通用名词，跳到 knowledge/fundamentals/ 对应那篇，
                看完再回来。那些篇章都从 RISC-V / ysyx 那边搭桥讲起。
    [做 Lx]     动手。x 是强度：
                  L1 复现   跑通并观察现象
                  L2 改造   改现有代码，改出预期的可观测变化
                  L3 从零   不看资料仓源码，自己写完整程序
                  L4 入项目 把这一层能力落进 project/
    [判]        判据。没有判据的实验等于没做。
                每条判据都要能注错见红：故意改坏，判据必须失败。

**每个 [做] 块开头都有一段"先自己想"**，给的是目标和线索，不是现成命令。
先自己拼一版，拼不出来再看答案。答案里每个参数都注了它在管什么——
光会敲命令没用，换个场景就拼不出来了。

凡是标了"自己敲"的代码，别去资料仓里拷。抄一遍等于没学。

### 0.4 环境

已装（Ubuntu 26.04 on WSL2，gcc 15.2.0）：

    gcc / make / ccache             本机 x86-64
    arm-linux-gnueabihf-gcc         交叉，15.2.0
    binutils-arm-linux-gnueabihf    readelf / nm / objdump 的 ARM 版
    strace                          看一个程序发了哪些系统调用
    file / bc

**故意没装 qemu-user-static。** 装了它 x86 上能直接跑 ARM 程序，
第 2.5 节那条"必须报 Exec format error"的判据就失效了。理由见 2.9 节。

工作目录：

    cd /mnt/e/Workspace/embedded-linux/knowledge/labs
    mkdir -p 01_hello && cd 01_hello

下面所有标了"本机实测"的输出都是在这套环境上真跑出来的，不是照抄书。
你的数字可能有小差异（gcc 版本不同），但结构必须一样。
**跑出来和笔记不一致时先信自己的机器**，查清楚原因，再回来改笔记。

**上板实测环境：**

    开发板      100ASK_IMX6ULL Pro，armv7l
    内核        Linux 4.9.88
    rootfs      Buildroot 2020.02，glibc 2.30
    连接        板子左侧下面那个 micro-USB（6 号，USB 转串口 CH9102）-> Windows COM8
    串口参数    115200 8N1，无流控；命令和文件都经 tools/serial-board.ps1 收发

本章凡是写“上板实测”的输出，都来自这块板，不是从 PDF 或旧日志推出来的。

---

## 1 一张脉络图

整章讲的是下面这条顺序链：

| 顺序 | 在哪里 | 发生什么 | 对应章节 |
|---|---|---|---|
| 1 | x86-64 Ubuntu 开发机 | 从 `hello.c` 出发，经历预处理、编译、汇编、链接，生成 ARM ELF | 第 2、3 节 |
| 2 | 开发机 → 开发板 | 把 ELF 编成 base64 文本，经串口传到板子 | 第 2.11 节 |
| 3 | ARM Cortex-A7 开发板 | shell 执行 `./hello`，经历 `fork + execve` | 第 2.5～2.7 节 |
| 4 | 开发板内核 | `load_elf_binary()` 检查 `e_machine` 并映射 ELF | 第 2.5～2.7 节 |
| 5 | 开发板用户态 | `ld.so` 完成重定位，随后进入 `main()` | 第 3.6 节 |

第 4 节解决第 1 步如何自动化：文件很多时，判断谁该重编、谁不该重编。第 5 节再把构建成果落进 `project/`。

这一章不是入门礼节。第 2 阶段编内核模块时工具链选错直接编不过；
项目做到几万行时 Makefile 写错了，改一个头文件要么全量重编（慢），
要么根本不重编（更糟，会编出一个能跑但行为错误的程序）。

---

## 2 第一段：交叉编译

### 2.0 看哪里

    视频    4_1-1（15 分）、4_1-2（7 分），过滤表见 0.2
    PDF     141-142 页
    源码    $Q\04_...\source\01_hello\

### 2.1 第一性原理：编译器只是在选"给谁生成机器码"

一句话：**编译器不是一个通用的翻译机，它是一台专门给某一个平台生产机器码的机器。**

这句话推出这一节的全部内容。既然产物是给某个平台的，
那么"某个平台"这件事就必须在编译时说清楚，而它至少包含三件独立的事：

    1. 指令集    生成 ARM 机器码还是 x86-64 机器码
    2. 调用约定  参数放哪个寄存器、结构体怎么对齐、栈帧怎么排
    3. 配套的头文件和库在哪   编译时 include 的 stdio.h、链接时用的 libc.so

这三件事互相独立：指令集相同、调用约定不同的两个产物不能互相调用；
前两者都相同、配套库版本不同的产物拷过去会启动失败。

它们被塞进了一个名字里：

以 `arm-linux-gnueabihf-gcc` 为例：

| 名称片段 | 表示什么 | 影响 |
|---|---|---|
| `arm` | 目标架构 ISA | 生成 ARMv7-A，而不是 x86-64 机器码 |
| `linux` | 目标 OS | 选择 Linux 系统调用约定及配套 C 库 |
| `gnu` + `eabi` | ABI 与 C 库体系 | `gnu` 表示 glibc；`eabi` 规定参数、结构体、栈帧等二进制约定 |
| `hf` | hard-float ABI | 浮点参数走 `s0/s1/d0` 等 VFP 寄存器；soft/softfp 则走 `r0-r3` |
| `gcc` | 工具名 | 编译驱动程序 |

板子 BSP 中的 `arm-buildroot-linux-gnueabihf-gcc` 多了 `buildroot`，它是厂商/构建者标识；apt 安装的工具链省略了这一段。

这个名字叫 target triplet，实际常常是四段。

三件事分别落在 ELF 文件的不同位置：

| ELF 中的位置 | 示例内容 | 由什么决定 |
|---|---|---|
| ELF header | `e_machine = EM_ARM` | 目标 ISA |
| `.text` | ARM 机器码 | 目标 ISA |
| 调用指令及约定 | 参数放 `r0-r3` 或 `s0-s7` | ABI |
| `.interp` | `/lib/ld-linux-armhf.so.3` | sysroot 中配套的动态链接器 |
| `.dynamic` | `NEEDED libc.so.6` | sysroot 中链接到的库 |

[基础] 这一节会用到三个通用概念，不熟就先跳过去：

    ABI 和 sysroot 到底是什么   ->  [fundamentals/03_ABI与sysroot](../../fundamentals/03_ABI与sysroot.md)
    r0 / s0 这些寄存器名        ->  [fundamentals/02_ARM寄存器与调用约定](../../fundamentals/02_ARM寄存器与调用约定.md)

### 2.2 hf 这一位是硬约束，不是性能选项

同一个函数 `float f(float a, float b)`，两种 ABI 的调用现场完全不同：

| 项目 | hard-float | soft / softfp |
|---|---|---|
| 参数 `a` | `s0` | `r0`，保留 float 的 32 位原样 |
| 参数 `b` | `s1` | `r1` |
| 返回值 | `s0` | `r0` |
| 计算 | 直接发 `vadd.f32` | 调 `__aeabi_fadd`，或先搬进 VFP |

如果调用方按 hard-float 把参数放进 `s0/s1`，被调方却按 soft-float 去 `r0/r1` 取，得到的就是无关内容。

所以链接器不让这两种 `.o` 链到一起，直接报错：

    xxx.o uses VFP register arguments, yyy.o does not

（s0、r0 是什么，以及三种浮点 ABI 编出来的汇编长什么样，
见 [fundamentals/02](../../fundamentals/02_ARM寄存器与调用约定.md) 第三、四节，那边有实测的汇编对照。）

IMX6ULL 的 Cortex-A7 带 VFPv4 和 NEON，所以用 hf。

### 2.3 两种 sysroot 布局

sysroot 是"目标系统的根目录"：编译时用的 `stdio.h`、链接时用的 `libc.so`，
必须是给 ARM 的那一份，不能是你 Ubuntu x86 上那一份。

| 项目 | Debian/Ubuntu multiarch | Buildroot / BSP 独立 sysroot |
|---|---|---|
| 头文件 | `/usr/include/`、`/usr/arm-linux-gnueabihf/include/`、`/usr/include/x86_64-linux-gnu/` | `<sysroot>/usr/include/` |
| ARM 库 | `/usr/arm-linux-gnueabihf/lib/` | `<sysroot>/usr/lib/` |
| `-print-sysroot` | 返回 `/` | 返回独立 sysroot 目录 |
| 优点 | apt 可直接安装；多个架构能并存 | 与板子 rootfs 一一对应，版本可控 |
| 注意 | `/usr/include` 也可能进入 ARM 编译器搜索路径 | 第 2 阶段编内核模块必须使用 BSP 配套工具链 |

第 2 阶段编驱动时会换成板子 BSP 里的 `arm-buildroot-linux-gnueabihf-gcc`，
那时 `-print-sysroot` 会返回一个很长的真实路径。

### 2.4 [做 L1] 让工具链自报家门

**先自己想，别急着往下看：**

    问题 1  怎么让编译器自报家门，说出它给哪个平台编、默认什么浮点 ABI？
            线索：几乎所有编译器都有一个"啰嗦模式"开关，一个字母。
    问题 2  怎么知道它去哪些目录找头文件？
            线索：头文件是预处理阶段的事，gcc 里让它只做预处理的选项是 -E。
                  再配上问题 1 那个开关，它会把内部动作全打出来。
                  可是 -E 要一个输入文件，能不能不建文件？
                  提示：很多 Unix 工具用 - 表示"从标准输入读"。
    问题 3  怎么问它某个具体的库文件在哪？
            线索：man gcc 里搜 print-file-name。gcc 有一批 -print-xxx 选项。

自己拼过之后再对答案：

    # 1) 它给谁编？ISA 和默认 ABI
    arm-linux-gnueabihf-gcc -v 2>&1 | grep -E 'Target:|--with-(arch|fpu|float)'
    #                       ^^  ^^^^   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
    #                       |   |      -E 用扩展正则，| 是"或"，(a|b) 是分组
    #                       |   这些信息走 stderr，2>&1 把它并到 stdout 才能进管道
    #                       -v verbose。单独跑 -v 会刷屏，所以拿 grep 挑重点

    # 2) 头文件去哪找？
    echo 'int main(){}' | arm-linux-gnueabihf-gcc -E -v - 2>&1 \
        | sed -n '/search starts here/,/End of search/p'
    #     ^^^^^^^^^^^^^^^^^^ 造一个最小的合法 C 程序，从管道喂进去，不落文件
    #                                                 -E 只做预处理就停
    #                                                    -v 打印内部动作
    #                                                       -  从标准输入读源码
    #          sed -n '/起/,/止/p'   -n 默认不打印，只打印 p 指定的
    #                                /a/,/b/ 是行范围：从匹配 a 的行到匹配 b 的行

    # 3) 和本机 gcc 对比，看两套路径有没有一条重合
    echo 'int main(){}' | gcc -E -v - 2>&1 \
        | sed -n '/search starts here/,/End of search/p'

    # 4) sysroot 和实际的库在哪？
    arm-linux-gnueabihf-gcc -print-sysroot
    arm-linux-gnueabihf-gcc -print-file-name=libc.so
    #                       ^^^^^^^^^^^^^^^^ 问它"如果我要链接这个库，你会用哪个文件"
    ls /usr/arm-linux-gnueabihf/
    file -L /usr/arm-linux-gnueabihf/lib/libc.so.6
    #    ^^ 跟随符号链接看真身，不加 -L 只会告诉你"这是个 symbolic link"

第 2 条那个技巧视频 4_2-2 的 21:02 处演示过，视频里的说法是
"难道我们想去确定这些路径时，都要去编写 `.c` 文件吗？不需要的"。

**本机实测**，第 1 条从一长串 configure 参数里挑出来的关键几项：

    Target: arm-linux-gnueabihf
    --with-arch=armv7-a+fp          ISA：ARMv7-A 带浮点单元
    --with-float=hard               ABI：hf，对应 2.2 那张寄存器图
    --with-mode=thumb               默认生成 Thumb-2 指令，16/32 位混合，代码更小
    --with-sysroot=/                对应 2.3 讲的 multiarch 布局
    --enable-default-pie            对应 2.8 讲的 e_type 为什么是 DYN
    --includedir=/usr/arm-linux-gnueabihf/include

一条 `-v` 就把本章后面要讲的四件事全预告了。

**本机实测**，第 2 条的输出：

    #include <...> search starts here:
     /usr/lib/gcc-cross/arm-linux-gnueabihf/15/include
     /usr/lib/gcc-cross/arm-linux-gnueabihf/15/../../../../arm-linux-gnueabihf/include
     /usr/include
    End of search list.

第 4 条的 `-print-sysroot` 输出是一个光秃秃的 `/`。这跟"sysroot 是目标系统的
根目录"的说法看起来矛盾，其实就是 2.3 那两种布局的区别。

**[判]** 逐条对着输出回答，答不上来就是没看懂：

    [ ] Target: 那一行完整是什么，四段各管什么
    [ ] --with-float= 的值是 hard 还是 soft，为什么这台机器上是这个值
    [ ] ARM 编译器的头文件搜索路径里，哪几条是它专属的
        （特征：路径里带 arm-linux-gnueabihf 或 gcc-cross）
    [ ] 本机 gcc 的搜索路径里有 x86_64-linux-gnu，ARM 的没有
    [ ] /usr/arm-linux-gnueabihf/lib/libc.so.6 存在，并且 file 一下它是 ARM 的

    注错见红：把第 2 条命令里的 arm-linux-gnueabihf-gcc 换成 gcc 再跑，
    两次输出必须不同。如果一样，说明命令敲错了或者装了个假的。

### 2.5 内核在哪一步拒绝了 ARM 程序

**[做 L1] 同一份源码，两个目标平台**

先自己想：

    问题 1  同一个 .c，怎么分别编出 x86 版和 ARM 版？
    问题 2  编出来之后，怎么一眼看出哪个是哪个？
            线索：有个命令专门用来"猜这个文件是什么"，名字就三个字母。
    问题 3  在 x86 机器上运行 ARM 版会怎样？先预测，再跑，看你猜没猜中。

`hello.c` 自己敲一份，别去资料仓拷：

    #include <stdio.h>
    int main(int argc, char **argv)
    {
        printf("hello, %s\n", argc > 1 ? argv[1] : "world");
        return 0;
    }

    /* 收 argv 是为了后面能传参数进来看效果，
       argc > 1 ? argv[1] : "world" 是三目运算符：有参数就用参数，没有就用 world */

然后：

    gcc                     -o hello_x86 hello.c
    arm-linux-gnueabihf-gcc -o hello_arm hello.c
    #                       ^^ 指定输出文件名。不加 -o 的话产物一律叫 a.out，
    #                          两次编译会互相覆盖

    file hello_x86 hello_arm
    #    file 读文件开头的特征字节来判断类型，不看扩展名。
    #    它认识几千种格式，ELF 只是其中一种。

    ./hello_x86 weidongshan
    ./hello_arm weidongshan          # 这一句会失败，失败方式才是重点
    echo $?                          # $? 是上一条命令的退出码，记住这个数

**本机实测：**

    hello_x86: ELF 64-bit LSB pie executable, x86-64, ... dynamically linked,
               interpreter /lib64/ld-linux-x86-64.so.2
    hello_arm: ELF 32-bit LSB pie executable, ARM, EABI5 ... dynamically linked,
               interpreter /lib/ld-linux-armhf.so.3

    bash: ./hello_arm: cannot execute binary file: Exec format error

视频 4_1-1 的 12:25 处在**板子上**做了这件事的镜像版本：
把 x86 编的 hello 拷到 ARM 板上跑，报的是同一句话。
两个方向报同一个错，说明拦下它的东西两边都有。它是什么，下面两节回答。

[基础] 下面要拆 ELF 文件头。ELF 是什么、section 和 segment 有什么区别、
`.bss` 为什么不占文件空间，见
[fundamentals/01_ELF与程序加载](../../fundamentals/01_ELF与程序加载.md)。
跟 ysyx 的对照：你 `objcopy -O binary` 扔掉的就是这些东西。

### 2.6 那两个被检查的字节

内核检查的是 ELF header 里的 `e_machine` 字段，它在文件开头第 18、19 字节。

    xxd -l 20 hello_arm
    xxd -l 20 hello_x86

**本机实测**（最左边是文件偏移）：

    hello_arm
    00000000: 7f45 4c46 0101 0100 0000 0000 0000 0000  .ELF............
    00000010: 0300 2800                                ..(.

    hello_x86
    00000000: 7f45 4c46 0201 0100 0000 0000 0000 0000  .ELF............
    00000010: 0300 3e00                                ..>.

拆开读：

    偏移   字节          含义
    ----   -----------   ----------------------------------------------------
    0x00   7f 45 4c 46   magic，也就是 '\x7f' 'E' 'L' 'F'。全世界的 ELF 都一样
    0x04   01 / 02       EI_CLASS   01 = 32 位，02 = 64 位
                         hello_arm 是 01，hello_x86 是 02
    0x05   01            EI_DATA    01 = 小端
    0x06   01            EI_VERSION
    0x10   03 00         e_type     0x0003 = ET_DYN，为什么不是 EXEC 见 2.8
    0x12   28 00         e_machine  小端 0x0028 = 40 = EM_ARM      <== 就是它
           3e 00                    小端 0x003e = 62 = EM_X86_64

    对一下 readelf 说的和字节是否一致：
        readelf -h hello_arm | grep -E 'Class|Machine|Type:'

### 2.7 完整的拒绝路径

`./hello_arm` 的拒绝路径按顺序是：

1. bash 在用户态执行 `fork()`，随后调用 `execve("./hello_arm", argv, envp)`。
2. 内核进入 `do_execveat_common()`；`bprm_execve()` 把文件头 256 字节读入 `bprm->buf`。
3. `search_binary_handler()` 依次询问已注册的格式处理器：

   | 处理器 | 检查 | 本例结果 |
   |---|---|---|
   | `binfmt_script` | 头两字节是否为 `#!` | 不是，拒绝 |
   | `binfmt_elf` | 头四字节是否为 `\x7fELF` | 是，进入 `load_elf_binary()` |
   | `elf_check_arch` | `e_machine` 是否匹配本机 | 文件为 `EM_ARM (40)`，本机为 `EM_X86_64 (62)`，返回 `-ENOEXEC` |
   | `binfmt_misc` | 是否有已注册规则能接管 ARM 文件 | 没有，返回 `-ENOEXEC` |

4. 所有处理器都拒绝后，`execve` 返回 `-ENOEXEC`。
5. bash 把它翻译为 `cannot execute binary file: Exec format error`。

**拦下它的不是 CPU，是内核里一段普通的 if 判断。** CPU 根本没机会看到那些
ARM 指令。这句话是 2.5 那两个方向报同一个错的原因：两边都是 Linux，
两边都跑同一段 `elf_check_arch`。

### 2.8 顺便：为什么 e_type 是 DYN 不是 EXEC

书上常说"可执行文件是 ET_EXEC，共享库是 ET_DYN"，但上面实测出来的可执行文件
是 ET_DYN。因为现代 gcc 默认开 PIE（position independent executable）：
程序编成位置无关的，内核每次加载时随机选一个基址，这叫 ASLR，防溢出攻击用的。
2.4 里 `-v` 打出来的 `--enable-default-pie` 就是它。

| 项目 | 传统 `ET_EXEC` | PIE / `ET_DYN` |
|---|---|---|
| 加载地址 | 链接时定死 | 运行时决定，每次可能不同 |
| `file` 输出 | `executable` | `pie executable` |

    想看传统形态：
        gcc -no-pie -o hello_nopie hello.c
        readelf -h hello_nopie | grep Type:        -> EXEC

嵌入式上这一位有实际影响：PIE 需要动态链接器参与重定位，
纯静态且 `-no-pie` 的程序才是真正的"拷过去就能跑"。3.7 会看到 `-static` 的产物类型。

### 2.9 binfmt_misc：为什么 WSL 里能直接敲 notepad.exe

2.7 流程图里 `binfmt_misc` 那一支不是摆设。它允许往内核注册一条规则：

    看到文件头是这几个字节 -> 别自己加载，交给我指定的解释器去跑

你这台机器上就有活的例子：

    ls /proc/sys/fs/binfmt_misc/
    cat /proc/sys/fs/binfmt_misc/WSLInterop

**本机实测：**

    $ ls /proc/sys/fs/binfmt_misc/
    WSLInterop  python3.14  register  status

    $ cat /proc/sys/fs/binfmt_misc/WSLInterop
    enabled
    interpreter /init
    flags: P
    offset 0
    magic 4d5a           <-- 'M' 'Z'，Windows PE 文件的头两个字节

`notepad.exe` 的接管过程是：

1. 你在 WSL 中执行 `notepad.exe`。
2. 内核读取文件头两个字节，发现是 `4d 5a`（`MZ`）。
3. 该 magic 匹配已注册的 `WSLInterop` 规则。
4. 内核把文件交给规则指定的 `/init`，再转到 Windows 侧执行。

同一个机制，把 magic 换成 ELF 头里 `e_machine` 等于 `EM_ARM` 的那几个字节，
解释器换成 `qemu-arm-static`，ARM 程序就能在 x86 上直接跑起来。
Docker 在 x86 机器上拉 arm64 镜像跑，靠的就是这个。

本仓故意没装 `qemu-user-static`，因为装了之后 `./hello_arm` 会真的打印
`hello, weidongshan`，2.10 那条"必须报 Exec format error"的判据就失效了。
等你把这一节吃透，可以自己装上再跑一遍看现象反转，那本身就是最好的验证。

### 2.10 [判] 第 2 节的判据

    [ ] file 的两行输出里，架构字段不同（x86-64 与 ARM），位宽也不同（64 与 32）
    [ ] xxd 看到偏移 0x12 处两个字节，一个是 28 00，一个是 3e 00
    [ ] readelf -h 的 Machine 字段和上面两个字节对得上
    [ ] 运行 hello_arm 报的是 Exec format error，不是 Permission denied
        （后者说明是权限问题，chmod +x 就好，跟架构无关）
    [ ] 说得出 e_type 为什么是 DYN，以及 -no-pie 编出来会变成什么
    [ ] /proc/sys/fs/binfmt_misc/WSLInterop 的 magic 是 4d5a，说得出它是什么

**注错见红。这条务必动手，而且要做两次，对照着看。**

第一次，改动态版：

    cp hello_arm hello_fake
    printf '>' | dd of=hello_fake bs=1 seek=18 conv=notrunc
    #        ^  '>' 的 ASCII 码是 0x3e，正好是 EM_X86_64 的低字节
    #                  bs=1 一次一字节  seek=18 跳到第 18 字节
    #                  conv=notrunc 只覆盖这一字节，不把后面截掉
    xxd -s 16 -l 4 hello_fake            # 确认变成了 0300 3e00
    ./hello_fake; echo "exit=$?"

你把 `e_machine` 从 40 改成了 62，内核那道 if 就骗过去了。**本机实测**的结果
不是段错误，而是：

    bash: ./hello_fake: cannot execute: required file not found
    exit=127

找不到文件？文件明明就在眼前。找不到的是 `.interp` 里写的那个
`/lib/ld-linux-armhf.so.3`，你的 x86 机器上根本没有 ARM 的动态链接器。
也就是说你确实骗过了 arch 检查，内核往下走了一步，卡在了下一关。

第二次，改静态版。它没有 `.interp`，没有下一关：

    arm-linux-gnueabihf-gcc -static -o hello_sta hello.c
    cp hello_sta hello_sta_fake
    printf '>' | dd of=hello_sta_fake bs=1 seek=18 conv=notrunc
    ./hello_sta_fake; echo "exit=$?"

**本机实测：**

    Segmentation fault
    exit=139                            139 = 128 + 11，11 号信号是 SIGSEGV

这一次 CPU 真的开始执行那段 ARM 机器码了。x86 的解码器拿 ARM 字节当 x86
指令啃，几条之内必然踩坏内存。

两次对照，把 2.7 的流程图和 3.6 的加载时序一起验活了：

    e_machine     动态版                        静态版
    -----------   ---------------------------   ---------------------------
    原样 (40)     Exec format error   exit=126  Exec format error   exit=126
                  内核 elf_check_arch 拦下      同左
    改成 62       required file not found       Segmentation fault  exit=139
                  exit=127                      没有 .interp 这一关，内核
                  过了 arch 检查，卡在找 ld.so  直接跳到 ARM 代码入口

    126 是内核不认这个格式；127 是内核认了，但配套的解释器找不到；
    139 是内核放行之后 CPU 自己崩的。三个退出码正好对应流程图上三个位置。

### 2.11 [做 L1] 上板实测：用串口跑三种 hello

视频 4_1-1 用的是"串口登录 + NFS 挂载"。本仓只用串口：一根 USB 线同时负责
登录、敲命令、看输出、传文件。NFS 放到本节末尾当拓展。

| 顺序 | 所在系统 | 动作 |
|---|---|---|
| 1 | WSL Ubuntu（x86-64） | 用 `gcc` / `arm-linux-gnueabihf-gcc` 从 `hello.c` 生成 `knowledge/labs/01_hello/hello_*` |
| 2 | WSL ↔ Windows | `/mnt/e` 和 `E:\` 是同一块盘，PowerShell 脚本可直接读取产物 |
| 3 | Windows PowerShell | `tools/serial-board.ps1` 用 gzip 压缩，再编码成 base64 文本 |
| 4 | Windows → 开发板 | 经 CH9102 的 COM8 和 USB 线，以 UART `115200 8N1` 送到 `ttymxc0` |
| 5 | ARMv7 Buildroot 开发板 | tty 行规程交给 bash；`base64 -d \| gzip -dc` 还原到 `/tmp/ch01-board-repro/`，再执行 `./hello_*` |
| 6 | 开发板 → Windows | 同一根串口线把命令输出送回脚本 |

图里有两条边界：

- **WSL 看不见 COM 口。** 编译在 WSL 里敲，串口相关的命令在 Windows PowerShell
  里敲，两边通过同一块 E 盘交换文件。
- **板上的 `/tmp` 在板子的内存里**（tmpfs，02 章 7.1 节实测），不在电脑上，断电就没。

**先自己想：**

    问题 1  Windows 里多出一个 USB 设备，是否已经证明能跟板上 Linux 说话？
    问题 2  串口线那头连着的是 tty，它会把某些字节当成按键（Ctrl+C、回车）。
            一个二进制 ELF 怎样才能一个字节不差地过去？
    问题 3  传完之后，怎样证明板上的文件和电脑上的完全一样？

#### 2.11.1 先找对口：板子左侧有两个长得一样的 micro-USB

PDF 第 93 页图 3.1 的 5 号和 6 号，上下挨着：

    5 号（上）  USB OTG      插上后 Windows 只多出一个叫 100ASK_IMX6ULL 的 USB 设备，
                             没有 COM 口。本仓不用这个口。
    6 号（下）  USB 转串口   板载 CH9102 芯片，插上后 Windows 多出一个 COM 口。

**本仓实测踩过：** 线插在 5 号口，电脑照样响起 USB 接入提示音，COM 口一个没多。
提示音只能证明"有 USB 设备接进来"，证明不了接的是哪个口。

先自己想：怎样在 PowerShell 里只列出"现在插着的端口类设备"？
线索：`Get-PnpDevice` 列即插即用设备，它有一个参数排除已拔掉的历史设备，
还有一个参数按设备类别过滤。

~~~powershell
Get-PnpDevice -PresentOnly -Class Ports
~~~

- `-PresentOnly`：只列现在插着的。不加它，很久以前拔掉的 CH340、CH9102 记录
  也会列出来，看起来"在"，其实不在。
- `-Class Ports`：只看设备管理器里"端口（COM 和 LPT）"这一类。

本次实测（`InstanceId` 列截短了）：

~~~text
Status Class FriendlyName                      InstanceId
------ ----- ------------                      ----------
OK     Ports 蓝牙链接上的标准串行 (COM3)       BTHENUM\{00001101-0000-1000-8000-00805F9B34FB}...
OK     Ports USB-Enhanced-SERIAL CH9102 (COM8) USB\VID_1A86&PID_55D4\5B8E648930
OK     Ports 蓝牙链接上的标准串行 (COM4)       BTHENUM\{00001101-0000-1000-8000-00805F9B34FB}...
~~~

COM3、COM4 是笔记本的蓝牙串口，和板子无关。认准 `CH9102`，`VID_1A86` 是它的
厂商号。COM 编号是 Windows 分配的，换个 USB 插孔可能会变；下文脚本默认 COM8，
不一样就在每条命令后面加 `-Port COM实际编号`。

#### 2.11.2 串口参数：两端必须逐项一致

串口没有"协商"这一步。两端各自按自己的设置去切比特，有一项不同就收不到对的东西。

    参数      本板取值   填错的现象
    -------   --------   ------------------------------------------------
    波特率    115200     乱码（每一位的宽度对不上，比特切错了位置）
    数据位    8          乱码
    校验      无（N）    乱码或丢字
    停止位    1          偶发错字
    流控      无         一个字不显示、敲什么都没反应（第 7 节坑 1）

合起来常写成 `115200 8N1`。板子那一端的设置不用猜，下一小节让它自己念出来。

**交互式终端。** 视频用 MobaXterm，也可以用 PuTTY：新建一个 Serial 会话，
按上表填，连上后按一次回车，看到 `100ask login:` 输入 `root`，密码为空。
这适合手动探索。本仓里所有写进笔记的上板命令都改用下面这个脚本发，
因为它的输出能原样复现、能写进判据：

    tools/serial-board.ps1   打开 COM8，按 115200 8N1 无流控收发；
                             板子停在 login: 时自动用 root 登录

**同一个 COM 口同一时刻只能被一个程序打开。** MobaXterm 开着会话时跑脚本，
脚本会报端口被占用；先断开终端的连接（不用在板上 `exit`）。

#### 2.11.3 先证明线那头真是板上 Linux 的 shell

先自己想：光看到 COM8 出现，只证明 CH9102 芯片通了电。怎样证明线那头有一个
能执行命令的 ARM Linux？线索：让它报告 CPU 架构，再把"它自己认为的串口参数"
念出来——内核启动参数里有一项专门管控制台放在哪个串口、用什么波特率。

在 **Windows PowerShell** 里：

~~~powershell
Set-Location E:\Workspace\embedded-linux
.\tools\serial-board.ps1 'uname -a; cat /etc/os-release; cat /proc/cmdline; ls /dev/ttymxc*'
~~~

- 单引号里的整串是**板上** shell 的命令。PowerShell 的单引号不做任何替换，
  `;`、`*`、`$?` 都原样发过去，由板上的 bash 解释。
- 脚本只打印这串命令自己的输出，并把**最后一条**命令的退出码作为自己的退出码，
  PowerShell 里用 `$LASTEXITCODE` 查看。

本次上板实测：

~~~text
Linux 100ask 4.9.88 #1 SMP PREEMPT Sun Jul 21 03:42:00 EDT 2024 armv7l GNU/Linux
NAME=Buildroot
VERSION=2020.02-g65177d4
ID=buildroot
VERSION_ID=2020.02
PRETTY_NAME="Buildroot 2020.02"
console=ttymxc0,115200 root=/dev/mmcblk1p2 rootwait rw
/dev/ttymxc0  /dev/ttymxc2  /dev/ttymxc5
~~~

`console=ttymxc0,115200` 就是板子那一端的参数：内核把控制台放在 0 号 UART
（i.MX 的串口驱动叫 `mxc`，设备节点叫 `ttymxc*`），波特率 115200。
电脑这端填的必须和它一样。

再看 tty 这一层怎么对待收到的字节：

~~~powershell
.\tools\serial-board.ps1 'stty -a'
~~~

本次上板实测：

~~~text
speed 115200 baud; rows 0; columns 0; line = 0;
intr = ^C; quit = ^\; erase = ^?; kill = ^U; eof = ^D; eol = ^J; eol2 = <undef>;
swtch = <undef>; start = ^Q; stop = ^S; susp = ^Z; rprnt = ^R; werase = ^W;
lnext = ^V; discard = ^O; min = 1; time = 0;
-parenb -parodd -cmspar cs8 hupcl -cstopb cread clocal -crtscts
-ignbrk -brkint -ignpar -parmrk -inpck -istrip -inlcr -igncr icrnl ixon ixoff
-iuclc -ixany -imaxbel -iutf8
opost -olcuc -ocrnl onlcr -onocr -onlret -ofill -ofdel nl0 cr0 tab0 bs0 vt0 ff0
isig icanon -iexten -echo echoe echok -echonl -noflsh -xcase -tostop -echoprt
echoctl echoke -flusho -extproc
~~~

对着 2.11.2 的表读：`speed 115200`；`-parenb` 无校验；`cs8` 8 个数据位；
`-cstopb` 1 个停止位；`-crtscts` 没有硬件流控。`-echo` 是脚本为了输出干净
临时关掉的回显，脚本退出前会恢复。

剩下 `intr = ^C`、`eof = ^D`、`icrnl`、`ixon ixoff` 这几项，是下一小节的伏笔。

#### 2.11.4 为什么不能把 ELF 直接灌进串口

先自己想：上面 `stty -a` 列出的那几项，遇到一个二进制文件里恰好出现的
`0x03`、`0x04`、`0x13` 会做什么？

串口收到的字节不是直接交给程序的。中间隔着 **tty 行规程**（line discipline），
它的本职工作是把"人在键盘上按的键"翻译成程序看到的输入：

UART 收到的字节要先经过 tty 行规程，再经过 bash 的 readline，最后才成为程序输入：

| 层 | 特殊字节 | 处理 |
|---|---|---|
| tty 行规程 | `0x03`（`^C`） | 不交给程序，改为向前台进程发送 `SIGINT`；`intr = ^C` |
| tty 行规程 | `0x04`（`^D`） | 当作输入结束；`eof = ^D` |
| tty 行规程 | `0x0d`（CR） | 改写成 `0x0a`；`icrnl` |
| tty 行规程 | `0x13 / 0x11` | 暂停/恢复发送并吞掉；`ixon` |
| tty 行规程 | `0x7f`（DEL） | 当退格，删除前一字节；`erase = ^?` |
| bash readline | `0x00` 等控制字符 | 当作编辑快捷键 |
| bash readline | `>= 0x80` | 当作 Meta 组合键（第 7 节坑 15） |

在 WSL 里数一数，静态版 hello 里有多少个这样的字节。先自己想用什么工具把文件
逐字节打成十进制（线索：`od` 的 `-t` 选项）。

~~~bash
cd /mnt/e/Workspace/embedded-linux/knowledge/labs/01_hello
od -An -tu1 -v hello_arm_static | tr -s ' ' '\n' | awk 'NF { c[$1]++; n++ } END {
    printf "0x03=%d 0x04=%d 0x0d=%d 0x11=%d 0x13=%d 0x7f=%d\n", c[3], c[4], c[13], c[17], c[19], c[127]
    for (k in c) if (k+0 >= 128 || k+0 < 32 || k+0 == 127) bad += c[k]
    printf "%d of %d bytes (%.1f%%)\n", bad, n, 100 * bad / n }'
~~~

- `od -An`：不打左边的地址列；`-tu1`：每个字节按 1 字节无符号十进制打；
  `-v`：连续相同的行也照打（默认会折叠成一个 `*`，计数就少了）。
- `tr -s ' ' '\n'`：把空格换成换行，一个数一行；`-s` 把连续空格压成一个。
- `awk`：`c[$1]++` 按值计数；`k+0` 把数组下标转成数字再比大小，
  不加 `+0` 就是按字符串比，`"99" >= "128"` 会成立。

本机实测：

~~~text
0x03=5600 0x04=5926 0x0d=870 0x11=1155 0x13=1415 0x7f=903
345819 of 487028 bytes (71.0%)
~~~

七成的字节会被 tty 或 readline 截走、改写、当成命令（其中光 `0x00` 就占了
169742 个）。所以电脑这端先把文件转成**只含 `A-Z a-z 0-9 + / =`** 的
base64 文本，板上再解回来。

**光转成文本还不够：串口会丢字节，而且丢的时候没有任何报错。**
本仓第一版脚本把整个文件一口气发完，只在最后比一次哈希。用它传 02 章那个
4.4 MB 的测试包，5 分多钟传完，哈希对不上（下面是第一版脚本的原样输出）：

~~~text
board.tar -> /tmp/ch02-board-repro/board.tar: 4433920 bytes, gzip 2246265, base64 2995020 chars, 324.6 s, sha256 MISMATCH
  local 315310eff3bf450f8c6437f043e3f5eaa02179aff9844d652f9eddd4120a9991
  board cd251c1fabeafe4e4170dd7bba610307ece169f80ca32fde7352a85b25fcaa6a
~~~

丢在哪一层，内核记着账。先自己想：串口驱动如果来不及收，最可能在哪里留下计数？
线索：`/proc/tty/driver/` 下面每个串口驱动一个文件。

~~~powershell
.\tools\serial-board.ps1 'cat /sys/class/tty/ttymxc0/xmit_fifo_size; grep "^0:" /proc/tty/driver/IMX-uart'
~~~

- `/sys/class/tty/ttymxc0/xmit_fifo_size`：驱动登记的这个 UART 的硬件 FIFO 深度。
- `/proc/tty/driver/IMX-uart`：i.MX 串口驱动的统计，`^0:` 只留 0 号串口那一行。

那次事故之后的上板实测：

~~~text
32
0: uart:IMX mmio:0x02020000 irq:20 tx:25656 rx:3652181 oe:2 RTS|DTR|DSR|CD
~~~

`rx` 是开机以来 0 号串口收到的字节数，`oe`（overrun error）是**接收溢出**的次数。
溢出是这样发生的：

数据接收顺序是“电脑连续发送 → 32 字节 UART FIFO → CPU 中断搬入 tty 缓冲 → tty 行规程 → bash”。

在 115200 波特、8N1 下，有效速率约为每秒 11520 字节，因此：

```text
32 字节 / 11520 字节每秒 ≈ 2.8 ms
```

CPU 只要有一次超过 2.8 ms 没来搬数据，FIFO 就会装满；后续字节直接丢失，`oe` 加 1。

发送端放慢节奏挡不住这个：一行字符在线上是紧挨着到达的，这期间 CPU 卡一下照样丢。
**只能检测，然后重传。** 脚本现在这样传：

传输协议按顺序工作：

1. 电脑把 487028 字节的 `hello_arm_static` 用 gzip 压到 239471 字节。
2. 压缩数据按每块 30000 字节切成 8 块。
3. 每块转成 base64，每 3072 个字符一行；发送一行后，必须等板子返回 `> ` 才继续。
4. 板子用 `base64 -d` 生成 `.part`，计算该块 SHA-256；只有与电脑端一致时才追加到 `hello_arm_static.gz`。
5. 某块哈希不同或迟迟等不到 `> ` 时，电脑发送 Ctrl+C，让 bash 放弃本块，然后整块重传。
6. 全部块到齐后，板子用 `gzip -dc` 还原 `hello_arm_static`。
7. 最后比较整个文件的 SHA-256 与电脑端 `Get-FileHash`，输出 `sha256 OK` 或 `sha256 MISMATCH`。

- base64 是**编码不是压缩**，它让体积变大三分之一；前面的 gzip 才是压缩。
- `<<'EOF_...'` 是 here-document：从下一行起，到单独一行结束标记为止，都当作
  `base64 -d` 的标准输入。结束标记加了引号，里面的 `$` 不会被 bash 展开。
- `> ` 是 bash 读完 here-document 的一行之后打出来的续行提示符。等到它再发下一行，
  保证板子读走了上一行，tty 缓冲不会被越灌越满。
- **等不到 `> ` 本身也是损坏信号。** 丢的正好是行尾的回车，两行会粘成一行；
  丢在结束标记里，here-document 永远结束不了。两种情况 bash 都不会回预期的提示符，
  脚本等 3 秒就发 Ctrl+C 让 bash 放弃，然后整块重发。
- 每块单独校验，丢一个字节只重传这 30000 字节，不用从头再来。最后仍对整个文件
  再比一次：万一每块都对、拼起来却不对，也逃不掉。

#### 2.11.5 在 WSL 编出三个控制变量

下面切到 **WSL Ubuntu**。三条命令读同一个 `hello.c`，只改变目标架构和链接方式：

~~~bash
cd /mnt/e/Workspace/embedded-linux/knowledge/labs/01_hello
gcc -O2 -Wall -Wextra hello.c -o hello_x86
arm-linux-gnueabihf-gcc -O2 -Wall -Wextra hello.c -o hello_arm_dynamic
arm-linux-gnueabihf-gcc -static -O2 -Wall -Wextra hello.c -o hello_arm_static
ls -l hello_x86 hello_arm_dynamic hello_arm_static
sha256sum hello_x86 hello_arm_dynamic hello_arm_static
~~~

- 第一条使用 x86-64 本机编译器，故意生成板子不能执行的反例。
- 第二条生成 ARM 指令，但运行时仍要使用板上的动态加载器和 glibc。
- 第三条的 `-static` 把所需 libc 链进程序，避开两边 glibc 版本差异。
- 这三个产物在 `.gitignore` 里，不入库。

本机实测：

~~~text
-rwxrwxrwx 1 glorinz glorinz  69284 Sep 14 19:19 hello_arm_dynamic
-rwxrwxrwx 1 glorinz glorinz 487028 Sep 14 19:19 hello_arm_static
-rwxrwxrwx 1 glorinz glorinz  16000 Sep 14 19:19 hello_x86
74f67f513b7a15c03180c73f2b4e09da6b2a1d8d75822473a537915ae4f1cde8  hello_x86
7a3937e69328b911e509a4dae81a64cc1add10edd4690fc9b057befc77222d5c  hello_arm_dynamic
427c94684093c06dc9e99e0f00a87b0403781870c5bae7d6eba85028de93e96a  hello_arm_static
~~~

编译器版本或选项变化会让哈希变化。你不需要得到这三个固定值，只需要自己
上传前后的值逐项一致。

#### 2.11.6 传到板上，先验文件再运行

回到 **Windows PowerShell**：

~~~powershell
Set-Location E:\Workspace\embedded-linux
.\tools\serial-board.ps1 'rm -rf /tmp/ch01-board-repro'
foreach ($n in 'hello_x86', 'hello_arm_dynamic', 'hello_arm_static') {
    .\tools\serial-board.ps1 -Upload ".\labs\01_toolchain\$n" -Destination "/tmp/ch01-board-repro/$n"
}
~~~

- 第一条只清本实验专用的这个精确路径，保证板上不残留上一次的旧文件。
- `-Upload`：电脑上的源文件；`-Destination`：板上的目标路径。
  脚本只允许写 `/tmp/` 底下，免得手滑覆盖板上的系统文件；父目录不存在会自动建。
- `foreach`：PowerShell 的循环，`$n` 依次取三个文件名。脚本一次只传一个文件。
  这里用双引号，因为要让 PowerShell 把 `$n` 替换掉。

本次上板实测：

~~~text
hello_x86 -> /tmp/ch01-board-repro/hello_x86: 16000 bytes, gzip 2312, 1 blocks, 0 resent, 0.7 s, sha256 OK
hello_arm_dynamic -> /tmp/ch01-board-repro/hello_arm_dynamic: 69284 bytes, gzip 2713, 1 blocks, 0 resent, 0.7 s, sha256 OK
hello_arm_static -> /tmp/ch01-board-repro/hello_arm_static: 487028 bytes, gzip 239471, 8 blocks, 0 resent, 32.9 s, sha256 OK
~~~

`resent` 是重传的块数，这次三个文件都是一次到齐。

**算一下串口到底多快。** 静态版 gzip 后 239471 字节，转成 base64 是 319296 个字符，
用了 32.9 秒，约每秒 9700 个字符。115200 波特、8N1 每个字符占 10 位
（1 起始位 + 8 数据位 + 1 停止位），理论上限是每秒 11520 个字符，脚本跑到了约 84%，
剩下的花在逐行等 `> ` 和逐块校验上。
**串口传文件只适合几百 KB 级别。** 几 MB 的产物要换网线（scp 或 NFS）。

再从板子的视角看收到的文件：

~~~powershell
.\tools\serial-board.ps1 'cd /tmp/ch01-board-repro; chmod +x hello_*; ls -l; file hello_*; sha256sum hello_*'
~~~

- `chmod +x` 添加执行位。文件是 `gzip -dc >` 重定向新建出来的，没有执行位；
  不加它，运行时得到的是 `Permission denied`，不是格式错误。
- 板上的 `sha256sum` 必须与上一步 WSL 的三项一一相同。

本次上板实测：

~~~text
total 560
-rwxr-xr-x 1 root root  69284 Jan  1 00:25 hello_arm_dynamic
-rwxr-xr-x 1 root root 487028 Jan  1 00:26 hello_arm_static
-rwxr-xr-x 1 root root  16000 Jan  1 00:25 hello_x86
hello_arm_dynamic: ELF 32-bit LSB shared object, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-linux-armhf.so.3, BuildID[sha1]=c9f0885d0c48a3eb2bae7ceb92104b5758490a5d, for GNU/Linux 3.2.0, not stripped
hello_arm_static:  ELF 32-bit LSB executable, ARM, EABI5 version 1 (GNU/Linux), statically linked, BuildID[sha1]=45f7d312386b21b4537b93e72a5c8a9fd7262cf3, for GNU/Linux 3.2.0, not stripped
hello_x86:         ELF 64-bit LSB shared object, x86-64, version 1 (SYSV), dynamically linked, interpreter /lib64/ld-linux-x86-64.so.2, BuildID[sha1]=afbbf256b8381462e6074495ae99e7c317c24f6d, for GNU/Linux 3.2.0, not stripped
7a3937e69328b911e509a4dae81a64cc1add10edd4690fc9b057befc77222d5c  hello_arm_dynamic
427c94684093c06dc9e99e0f00a87b0403781870c5bae7d6eba85028de93e96a  hello_arm_static
74f67f513b7a15c03180c73f2b4e09da6b2a1d8d75822473a537915ae4f1cde8  hello_x86
~~~

时间戳显示 `Jan  1`，是因为板子没有对过时，系统时间从 1970 年 1 月 1 日起算
（02 章 7.1 节用 `date` 实测过）。它不影响本节任何判据。

板上 `file` 把两个 PIE 文件称为 `shared object`（原因见 2.8），但关键字段没有歧义：
`hello_x86` 是 `x86-64`，另外两个都是 `ARM, EABI5`，静态版明确写着
`statically linked`。

#### 2.11.7 连续运行三个版本，并保存退出码

~~~powershell
.\tools\serial-board.ps1 'cd /tmp/ch01-board-repro; ./hello_x86 learner; echo x86_exit=$?; ./hello_arm_dynamic learner; echo dynamic_exit=$?; ./hello_arm_static learner; echo static_exit=$?'
~~~

- `$?` 是**紧挨着的上一条**命令的退出码，所以每个程序后面立刻跟一条 `echo`。
  不能把 `echo $?` 放到下一次脚本调用里：两次调用之间脚本自己还发过别的命令，
  那时的 `$?` 已经不是你的程序的了。
- 外层必须是单引号。换成双引号，PowerShell 会先把 `$?` 换成它自己的状态值
  （`True`），板上收到的就是 `echo x86_exit=True`。

本次上板实测原样输出：

~~~text
-bash: ./hello_x86: cannot execute binary file: Exec format error
x86_exit=126
./hello_arm_dynamic: /lib/libc.so.6: version `GLIBC_2.34' not found (required by ./hello_arm_dynamic)
dynamic_exit=1
Hello, learner!
static_exit=0
~~~

这三行失败在三层不同的位置：

~~~text
x86 ELF       内核检查 e_machine 时拒绝                         exit 126
ARM 动态 ELF  架构通过，动态加载时发现板上 glibc 2.30 太旧        exit 1
ARM 静态 ELF  架构通过，又不依赖板上 glibc，进入 main              exit 0
~~~

板上 glibc 的版本号可以直接从库文件名看出来：

~~~powershell
.\tools\serial-board.ps1 'ls -l /lib/libc.so.6 /lib/libc-2*.so'
~~~

~~~text
-rwxr-xr-x 1 root root 1241860 Jul 21  2024 /lib/libc-2.30.so
lrwxrwxrwx 1 root root      12 Jul 21  2024 /lib/libc.so.6 -> libc-2.30.so
~~~

#### 2.11.8 [判] 上板判据

    [ ] Get-PnpDevice -PresentOnly -Class Ports 里有状态为 OK 的 CH9102
    [ ] 板上 uname -a 含 armv7l；/proc/cmdline 含 console=ttymxc0,115200
    [ ] 三次上传都打印 sha256 OK；板上 sha256sum 与 WSL 的三项一一相同
    [ ] hello_x86 报 Exec format error，退出码 126
    [ ] hello_arm_dynamic 报 GLIBC_2.34 not found，退出码 1
    [ ] hello_arm_static 打印 Hello, learner!，退出码 0

**注错见红一：传输校验必须真能抓住损坏。** 趁板上文件还在，复制一份静态版，
只改其中一个字节，看哈希变不变。先自己想用哪个命令"只覆盖文件中间的一个字节、
不截断后面"（线索：2.10 节改 `e_machine` 时用过）。

~~~powershell
.\tools\serial-board.ps1 'cd /tmp/ch01-board-repro; cp hello_arm_static bad; printf X | dd of=bad bs=1 seek=1000 conv=notrunc 2>/dev/null; sha256sum hello_arm_static bad; cmp -l hello_arm_static bad'
~~~

- `seek=1000`：跳过前 1000 个字节，写第 1001 个；`conv=notrunc`：不截断文件。
- `2>/dev/null`：丢掉 `dd` 打的统计信息，只看哈希。
- `cmp -l`：逐字节比较，列出每个不同字节的位置（从 1 数）和两边的值（八进制）。

本次上板实测：

~~~text
427c94684093c06dc9e99e0f00a87b0403781870c5bae7d6eba85028de93e96a  hello_arm_static
0d833cb2cd7fe307af7d73167cdf4a6049a4988d74431ee0e49df22b5970b5c9  bad
1001 143 130
~~~

只差第 1001 个字节（八进制 `143` 是 `c`，`130` 是 `X`），哈希整串都变了。
脚本的退出码是 1，那是最后一条 `cmp` 发现不同时的退出码。

**注错见红二：ELF 层。** ARM 动态版和静态版只差链接方式：动态版因为
sysroot/glibc 不匹配而失败，静态版通过。以后换成 BSP 配套工具链后，
动态版应当变成成功；届时这条判据也要随实测结果更新。

**注错见红三：重传这条路必须真的走过。** 串口平时很少丢字节，重传代码可能
几十次上传都走不到一次，没走到过的代码不算验过。脚本留了一个测试开关
`-CorruptBlock`：指定的那一块第一次发送时，故意把第一个字符换掉。

~~~powershell
.\tools\serial-board.ps1 -Upload .\labs\01_toolchain\hello_arm_static -Destination /tmp/ch01-board-repro/hello_arm_static -CorruptBlock 2
~~~

- `-CorruptBlock 2`：块从 0 开始数，2 是第 3 块。换掉的是一个合法的 base64 字符，
  所以 `base64 -d` 不报错，解出来的字节却是错的，只有哈希能发现。

本次上板实测（第一行是脚本用 `Write-Warning` 打的警告，在 PowerShell 窗口里
前面还会带一个 `警告:`）：

~~~text
block 3/8 arrived damaged (attempt 1), sending it again
hello_arm_static -> /tmp/ch01-board-repro/hello_arm_static: 487028 bytes, gzip 239471, 8 blocks, 1 resent, 37.3 s, sha256 OK
~~~

比正常上传多出的约 4 秒，就是第 3 块重发一遍的时间。

    [ ] 加 -CorruptBlock 2 时报 block 3/8 arrived damaged，统计里是 1 resent，
        最终仍然 sha256 OK

最后清理板上的临时产物：

~~~powershell
.\tools\serial-board.ps1 'rm -rf /tmp/ch01-board-repro'
~~~

#### 2.11.9 NFS：保留知识，暂不接通

视频 4_1-1 的 8:00-13:00 用 NFS 把电脑上的目录挂到板子上，改完代码不用再传文件。
挂载时要带 `-o nolock`（视频里第一次漏了，当场卡死）。

本仓当前没有接通 NFS。先看板子有没有网络地址：

~~~powershell
.\tools\serial-board.ps1 'ip -4 addr | grep -E "^[0-9]+:|inet "'
~~~

- `ip -4 addr`：列出网卡和它们的 IPv4 地址。
- `grep -E`：只留网卡名那一行（行首是编号加冒号）和 `inet` 地址行。

本次上板实测：

~~~text
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1
    inet 127.0.0.1/8 scope host lo
~~~

只有回环口 `lo` 有 IPv4 地址，两个网口和 WiFi 都没有。电脑这边还有一道坎：
WSL2 默认是 NAT 网络，据调研板子从外面连不进 WSL 里的 NFS 服务（还没实测）。

所以串口是本仓目前唯一的上板链路。等以后产物变大、串口传不动了，再把网线和
NFS 配通，并把实际 IP、导出目录和测速结果写回这里；在那之前不要照抄一个假 IP
去执行 `mount`。

---


---

## 6 自检问题

答不上来就回到对应小节重读。这些问题都能用命令验证，不要凭印象答。

    1. arm-linux-gnueabihf 里的 hf 换成 soft 会怎样？两种 ABI 编出的 .o
       能链接到一起吗？为什么这是硬约束而不是性能选项？                    (2.2)

    2. 内核在哪个函数里、检查哪个字段，判定一个 ELF 不能在本机执行？
       把那两个字节改成本机的值之后，报错为什么从 Exec format error
       变成了 Segmentation fault？                                        (2.6 2.7 2.10)

    3. 串口连不上，屏幕一个字都不显示。哪三个参数最可能填错？
       其中哪一个会导致"一个字不显示"而不是"显示乱码"？                    (2.11)

    19. 为什么不能把 ELF 原样灌进串口？tty 行规程会怎样对待 0x03、0x04、0x13？
        转成 base64 之后为什么还要逐块校验？丢字节在内核哪里留下计数？      (2.11.4)

---

## 7 已知的坑

    坑 1  串口流控没关掉，屏幕一个字都不显示，而且敲什么都没反应。
          和"波特率填错导致乱码"是两个不同的现象，别混。                    (2.11)

    坑 2  视频里的 NFS 挂载漏掉 -o nolock 会卡死；本机尚未接通 NFS，
          当前上板只走串口。                                              (2.11)

    坑 13 装了 qemu-user-static 之后，x86 上直接跑 ARM 程序会成功而不是报错。
          本仓故意没装，为的是保住第 2.10 节那条判据。哪天你发现 ./hello_arm
          居然跑起来了，先去看 /proc/sys/fs/binfmt_misc/ 下多了什么。       (2.9)

    坑 15 串口里敲的命令不能带中文。板上 bash 没有 UTF-8 locale，readline 把
          >= 0x80 的字节当成 Meta 组合键（M-d 是删掉一个词），整行被悄悄改写。
          实测发一行带中文的 printf，报的是 printf: --: invalid option。
          程序输出的中文能正常显示；命令里要用中文就写 printf 的八进制转义。  (2.11.4)

    坑 16 板子左侧两个 micro-USB 长得一样。插在上面的 5 号（OTG）电脑照样响
          USB 提示音，但不会多出 COM 口；串口是下面的 6 号。                (2.11.1)

    坑 17 串口会丢字节，而且不报错。实测一次性传 4.4 MB 哈希对不上，事后
          /proc/tty/driver/IMX-uart 里 oe（接收溢出）计数是 2。传文件必须带校验、
          丢了能重传；怀疑丢字节时先看 oe 有没有涨。                        (2.11.4)
