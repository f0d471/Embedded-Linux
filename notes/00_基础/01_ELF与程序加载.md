# 01 ELF 与程序加载

**前置：[00_从源码到运行](00_从源码到运行.md)。** 那一篇里"链接器""加载器""section"
三个词是怎么被逼出来的，本篇直接接着用，不再重复定义。

被 01 章 3、4 节用到。

实验目录：`labs/00_basics/01_link_and_load/`（沿用上一篇的 `app` / `app_x86`）
和 `labs/01_toolchain/`（big1 / big2）。
所有输出是 2026-09-08 本机实跑，工具链 `arm-linux-gnueabihf-gcc 15.2.0`。

判据自查：`bash labs/00_basics/01_link_and_load/check.sh`，本机基线 45 PASS / 0 FAIL。

---

## 没看懂也先记住

暂时分不清那些表也没关系。先记“谁读哪张表、文件大小不等于内存大小”，
下次看到工具输出时，用下面的对应关系认位置。

### 先带走这 5 条

1. **ELF 是一种文件格式，不是“可执行程序”的同义词。** Linux 下的 `.o`、常见可执行文件和 `.so` 动态库都可以是 ELF，能不能运行还要看文件类型和目标架构等信息。
2. **section（节）主要给链接和分析工具看，segment（段）描述运行时如何组织文件内容。** 负责加载的 `LOAD` 段告诉加载器把哪些内容映射到内存；两种划分不是一一对应。
3. **`.bss` 记大小，不在文件中存一整块零。** 对应内存里的变量初始为零；大零数组可以让文件很小，但仍需要相应的运行时地址空间，实际物理内存消耗还与访问情况有关。
4. **看 `LOAD` 行时，`FileSiz` 是文件中的字节数，`MemSiz` 是内存中的字节数。** 后者比前者多出的尾部需要补零；这个差值可能包含对齐，不能总当成 `.bss` 的精确大小。
5. **`main` 前面已经有启动过程。** 普通动态链接 C 程序先由内核建立映射、启动动态加载器，再到程序入口 `_start` 和 C 运行库，最后才调用 `main`。动态加载器负责找到并装入所需共享库。

### 看到什么，就先想到什么

| 看到的东西 | 第一反应 |
|---|---|
| `readelf -h` / `-S` / `-l` | 分别查 ELF 总体信息、section 表、program header 表（里面有 `LOAD` 等运行时描述） |
| 文件明明存在，执行却说找不到 | 除程序路径外，查 `readelf -l` 显示的解释器路径；这个动态加载器缺失也可能导致启动失败 |
| `Exec format error` | 先用 `file` 或 `readelf -h` 检查架构、文件类型和格式，不能只凭扩展名判断 |
| 大数组让内存需求增加，文件却没大多少 | 先看它是否进了 `.bss`，再区分文件大小、虚拟地址空间和实际驻留内存 |

### 反复看这 3 组问答

- **问：加载时主要按 section 还是 segment？答：按 program header 中的运行时描述，装入内容主要看 `LOAD` segment。**
- **问：`.bss` 不存那块零，变量就不占内存吗？答：不是，文件省空间不等于运行时免费。**
- **问：程序第一条指令就是 `main` 吗？答：不是，前面有加载和运行库启动过程。**

想补原理时：文件身份看第二节，两张表看第三节，`.bss` 看第四节，启动路径看第五节。

---

## 一、上一篇留下的问题

上一篇最后停在这里：

    链接器把 main 安排在地址 0x4d8，把 .text 整体安排在 0x3dc。
    加载器要照这个布局把文件搬进内存。
    那么问题是：这个布局，链接器是怎么"告诉"加载器的？

不可能靠约定俗成。加载器是内核里的一段代码，它拿到的只是一个文件，
必须能从文件本身读出"哪一段放哪、多大、什么权限"。

**所以可执行文件里必须有一份说明书。规定这份说明书怎么写的，就是 ELF 格式。**

> **ELF** = Executable and Linkable Format。
> 注意名字里有两个词：Executable（可执行，给加载器用）
> 和 Linkable（可链接，给链接器用）。
> **一个格式同时服务两个完全不同的读者** —— 这是本篇后面一切复杂性的来源。

Linux 下这三种文件全是 ELF，你已经都见过：

    .o      目标文件      上一篇的 main.o，给链接器读
    可执行  app           给加载器读
    .so     共享库        两个都要读（第 04 篇讲）

---

## 二、实验 1：确认它真的是一种"格式"

### 2.1 先自己想

要证明一个文件有格式，最直接的办法是**直接看它的字节**。

    提示：看二进制文件的字节，用 hexdump。
          -C 表示"左边十六进制、右边对应的可打印字符"，最常用的看法。
          只需要看开头，所以管道接 head。

### 2.2 动手

    hexdump -C app | head -2

本机实测（ARM 版）：

```
00000000  7f 45 4c 46 01 01 01 00  00 00 00 00 00 00 00 00  |.ELF............|
00000010  03 00 28 00 01 00 00 00  dd 03 00 00 34 00 00 00  |..4...|
```

同一个程序编成 x86 版：

```
00000000  7f 45 4c 46 02 01 01 00  00 00 00 00 00 00 00 00  |.ELF............|
00000010  03 00 3e 00 01 00 00 00  40 10 00 00 00 00 00 00  |..>.....@.......|
```

### 2.3 逐字节读，两行就够

**左边是偏移，中间是字节，右边是这些字节当 ASCII 字符看的样子。**

看右边那列：`.ELF` —— 第 2、3、4 个字节就是字母 E、L、F 的 ASCII 码
（0x45 0x4c 0x46）。第一个字节 0x7f 是个不可打印字符，所以显示成点。

> **magic number（魔数）**：文件开头几个固定字节，用来标明"我是哪种文件"。
> ELF 的魔数是 `7f 45 4c 46`。内核拿到一个文件，第一件事就是比对这 4 个字节，
> 不对就直接拒绝执行。

**再对比两行的差异，只有两处不同，而且都能解释：**

    偏移 0x04:   ARM 是 01,  x86 是 02
                 这一字节叫 EI_CLASS：01 = 32 位，02 = 64 位

    偏移 0x12:   ARM 是 28 00,  x86 是 3e 00
                 这两字节叫 e_machine，小端存放，所以真值是 0x0028 和 0x003e
                 0x28 = 40  = EM_ARM
                 0x3e = 62  = EM_X86_64

**偏移 0x12 处这两个字节，就是"为什么 ARM 程序在 x86 上跑不了"的全部原因。**
内核检查它，不匹配就返回 `ENOEXEC`（Exec format error）。
这个报错你在 01 章第 3 节见过，在上一篇剥裸 bin 时也见过。

（顺带：如果你手上有 ysyx 编出来的 RISC-V ELF，同一位置应该是 `f3 00`，
0xf3 = 243 = EM_RISCV。可以拿来验一下。）

### 2.4 用工具读同一份东西

手数字节只适合验证魔数，字段一多就该用工具了：

    arm-linux-gnueabihf-readelf -h app

    -h = ELF header（文件头）

本机实测：

```
ELF Header:
  Magic:   7f 45 4c 46 01 01 01 00 00 00 00 00 00 00 00 00
  Class:                             ELF32
  Data:                              2's complement, little endian
  Type:                              DYN (Position-Independent Executable file)
  Machine:                           ARM
  Entry point address:               0x3dd
  Start of program headers:          52 (bytes into file)
  Start of section headers:          68172 (bytes into file)
  Size of program headers:           32 (bytes)
  Number of program headers:         10
  Size of section headers:           40 (bytes)
  Number of section headers:         29
  Section header string table index: 28
```

**把它和 2.2 的字节对起来看：**

    Magic       就是那 16 个字节，一模一样
    Class       ELF32     <- 来自偏移 0x04 的 01
    Machine     ARM       <- 来自偏移 0x12 的 28 00

**现在注意这四行，它们是本篇的骨架：**

    Start of program headers:   52        program header table 在文件第 52 字节处
    Number of program headers:  10        共 10 条
    Start of section headers:   68172     section header table 在文件第 68172 字节处
    Number of section headers:  29        共 29 条

**一个文件里有两张表。** 一张 10 条，一张 29 条。
两张表描述的是**同一份内容**，只是切法不同。这就是下一节的主题。

还有一行要留意：

    Entry point address: 0x3dd

程序从这个地址开始执行。**它不是 main 的地址**（上一篇查过 main 在 0x4d8），
而是 `_start`。第五节回来讲。

### 2.5 判据

    [ ] hexdump 出的前 4 字节是 7f 45 4c 46
    [ ] ARM 版偏移 0x12 处是 28 00，x86 版是 3e 00
    [ ] readelf -h 报的 Class / Machine 与你手数的字节一致
    [ ] 能说出这个文件里有几条 program header、几条 section header（本机是 10 和 29）

    注错见红：把偏移 0x12 那两个字节改掉，让内核认不出它。

        cp app_x86 app_fake
        printf '\xf3\x00' | dd of=app_fake bs=1 seek=18 conv=notrunc status=none
        readelf -h app_fake | grep Machine        # 应该变成 RISC-V
        ./app_fake                                # 必须 Exec format error

    改 2 个字节，一个能跑的程序就废了。如果它还能跑，说明 dd 没写进去
    （检查有没有漏掉 conv=notrunc，漏了会把文件截断成 2 字节）。

---

## 三、section 和 segment：一份内容，两种切法

这是 ELF 最容易糊的地方，也是上一节那"两张表"的真面目。

### 3.1 为什么会有两张表

回到第一节那句话：**一个格式服务两个读者。** 两个读者的需求完全不同：

    链接器关心    这个文件由哪些块组成？哪块是代码、哪块是符号表、
                  哪块是重定位便条？我要按块合并
                  --> 它需要的是 section 表（29 条，切得细）

    加载器关心    这个文件的哪些部分要进内存？放到哪个地址？什么权限？
                  符号表这种运行时用不着的东西，我一眼都不想看
                  --> 它需要的是 segment 表（10 条，切得粗）

于是同一份内容被切了两次：

```
                  同一个文件的字节流
    +--------------------------------------------------------------+
    |  ELF header                                                  |
    +--------------------------------------------------------------+
    |                                                              |
    |             实际内容（代码、数据、符号表、字符串...）              |
    |                                                              |
    +--------------------------------------------------------------+

    section 视角（29 条，链接器看）：
    | .text | .rodata | .data | .bss | .symtab | .strtab | ...      |
      细分到"用途"这个粒度

    segment 视角（10 条，加载器看）：
    |     LOAD (R E)      |   LOAD (RW)   |  （符号表不在任何 segment 里）
      只按"进内存后的权限"归堆
```

> **segment（段）**：可执行文件里"要装进内存的一整块"，
> 每个 segment 就是加载器的一次 mmap。**它是加载器的操作单位**，
> 正如 section 是链接器的操作单位。

    section  链接期的单位   编译器生成、链接器合并
    segment  运行期的单位   链接器最后生成、加载器消费

**注意 section 和 segment 不是并列的两批东西，是同一批字节的两种分组方式。**
一个 segment 通常包含好几个 section。

### 3.2 动手：让 ELF 自己把对应关系说出来

上面那句"一个 segment 包含好几个 section"，不用信我，readelf 直接给出对照表：

    arm-linux-gnueabihf-readelf -l big1

    -l = program headers，也就是 segment 表
         （记法：-l 的全称是 --segments，但字母是 l，来自旧名 "program header layout"）

本机实测，先看上半部分：

```
Elf file type is DYN (Position-Independent Executable file)
Entry point 0x3dd
There are 10 program headers, starting at offset 52

Program Headers:
  Type           Offset   VirtAddr   PhysAddr   FileSiz MemSiz  Flg Align
  ARM_EXIDX      0x00061c 0x0000061c 0x0000061c 0x00008 0x00008 R   0x4
  PHDR           0x000034 0x00000034 0x00000034 0x00140 0x00140 R   0x4
  INTERP         0x000198 0x00000198 0x00000198 0x00019 0x00019 R   0x1
      [Requesting program interpreter: /lib/ld-linux-armhf.so.3]
  LOAD           0x000000 0x00000000 0x00000000 0x00648 0x00648 R E 0x10000
  LOAD           0x00fed0 0x0001fed0 0x0001fed0 0x00138 0x3d0a3c RW  0x10000
  DYNAMIC        0x00fed8 0x0001fed8 0x0001fed8 0x000f8 0x000f8 RW  0x4
  NOTE           0x000174 0x00000174 0x00000174 0x00024 0x00024 R   0x4
  NOTE           0x000628 0x00000628 0x00000628 0x00020 0x00020 R   0x4
  GNU_STACK      0x000000 0x00000000 0x00000000 0x00000 0x00000 RW  0x10
  GNU_RELRO      0x00fed0 0x0001fed0 0x0001fed0 0x00130 0x00130 R   0x1
```

**先只看两列：Type 和 Flg。**

    Type = LOAD    "把我装进内存"。只有这种需要真的搬运
                   10 条里只有 2 条是 LOAD
    Type = 其他    不是要装进内存的内容，是给加载器的额外指示：
                   INTERP     我需要一个解释器，路径写在下面那行
                   DYNAMIC    动态链接的信息在这里
                   GNU_STACK  栈要不要可执行（这里是 RW，不可执行，防攻击）
                   PHDR       表自己的位置

    Flg = R E      可读、可执行 -> 代码
    Flg = RW       可读、可写   -> 数据

**上一篇 `/proc/self/maps` 里看到的 r-xp 和 rw-p，源头就在这两行 LOAD 的 Flg 列。**

再看输出的下半部分，readelf 直接把两张表的对应关系列了出来：

```
 Section to Segment mapping:
  Segment Sections...
   00     .ARM.exidx
   01
   02     .interp
   03     .note.gnu.build-id .interp .gnu.hash .dynsym .dynstr .gnu.version
          .gnu.version_r .rel.dyn .rel.plt .init .plt .text .fini .rodata
          .ARM.exidx .eh_frame .note.ABI-tag
   04     .init_array .fini_array .dynamic .got .data .bss
   05     .dynamic
   06     .note.gnu.build-id
   07     .note.ABI-tag
   08
   09     .init_array .fini_array .dynamic .got
```

**这张表是本节的核心证据。逐行读：**

    编号 03 就是第一条 LOAD（R E）。它一个人装了 16 个 section，
    包括 .text（你的代码）和 .rodata（字符串常量）。
    共同点：运行时都只需要读和执行，不需要写。

    编号 04 就是第二条 LOAD（RW）。装了 .data、.bss、.got 等 6 个。
    共同点：运行时要写。

    **一个 section 可以出现在多个 segment 里**（.interp 在 02 和 03 都有，
    .dynamic 在 04、05、09 都有）。因为分组方式不同，同一批字节
    在不同视角下归属不同。这也再次说明它们不是两批东西。

**最关键的是：数一数上表里出现过的 section 名字，只有二十来个，
而 `readelf -h` 说这个文件有 29 个 section。剩下的去哪了？**

它们不属于任何 segment —— 也就是**运行时根本不进内存**。
`.symtab`、`.strtab`、`.comment`、`.shstrtab` 这些，
是上一篇里 `nm` 和 `readelf -r` 读的那些工具用元信息。
程序跑起来完全不需要它们。

这就引出下一个实验。

### 3.3 动手：把不进内存的东西删掉，看程序还跑不跑

这是本篇最值得亲手做的实验。**它一次性把 section 和 segment 的区别钉死。**

先自己想：如果 `.symtab` 真的不进内存，那把它从文件里删掉，
程序应该照常运行。怎么删？

    提示：binutils 里有个专门干这事的工具，名字就叫 strip（剥掉）。
          它的默认行为就是删符号表。

用 x86 版做，因为**要真的运行看结果**：

    cd labs/00_basics/01_link_and_load
    cp app_x86 app_strip
    ./app_x86;    echo "退出码=$?"      # 先记下正常时的行为
    strip app_strip
    ./app_strip;  echo "退出码=$?"

本机实测：

```
--- strip 前 ---
-rwxrwxrwx  15888  app_x86
section 数: 30
运行退出码 = 3

--- strip 后 ---
-rwxrwxrwx  14328  app_strip
section 数: 28
运行退出码 = 3
```

（退出码 3 是对的：程序是 `return add(g_init,2) + g_bss`，
即 `add(1,2) + 0 = 3`。**退出码本身就是"程序真的正确跑完了"的判据。**）

**现象：文件小了 1560 字节，section 少了 2 个，程序行为完全不变。**

少的是哪两个？

    diff <(readelf -S app_x86 | grep -oE '\.[a-z_.]+' | sort -u) \
         <(readelf -S app_strip | grep -oE '\.[a-z_.]+' | sort -u)

    < .strtab
    < .symtab

正是 3.2 里推断"不属于任何 segment"的那两个。**推断被实验证实了。**

再确认 segment 数没变：

    strip 前: 16 条 program header
    strip 后: 16 条

一条没少。**因为 strip 动的全是"加载器视野之外"的东西。**

### 3.4 动手：把整张 section 表都删掉

上一步只删了两个 section，还可以更极端 —— **把 29 条 section header 全删了**，
让这个文件在链接器眼里彻底不成立：

    cp app_x86 app_nosh
    strip --strip-section-headers app_nosh
    readelf -h app_nosh | grep 'Number of section headers'
    ./app_nosh; echo "退出码=$?"

本机实测：

```
Number of section headers:         0
Start of section headers:          0 (bytes into file)
文件大小: 15888 -> 12308
退出码 = 3
```

**section 表整个不存在了，文件小了 3580 字节，程序照跑，结果一模一样。**

这时候 `readelf -S app_nosh` 什么都读不出来，`nm` 也废了 —— 所有链接期工具全瞎。
但内核毫不在意，因为内核从头到尾就没看过那张表。

### 3.5 动手：反过来，动 segment 试试

现在做反向实验。**不删任何内容，只把 ELF 头里"segment 有几条"这个数字改成 0。**
一共改 2 个字节。

    cp app_x86 app_noph
    printf '\x00\x00' | dd of=app_noph bs=1 seek=56 conv=notrunc status=none
    ./app_noph; echo "退出码=$?"

    seek=56  x86-64 ELF 头里 e_phnum（program header 数量）在偏移 56 处
    conv=notrunc  只覆盖这 2 个字节，不要把文件截断（漏了这个文件就毁了）

本机实测：

```
cannot execute binary file: Exec format error
退出码 = 126
```

### 3.6 把两组实验并排放

**这张表就是整节的结论：**

    改动                             文件变化      能跑吗
    ------------------------------   -----------   -----------------------
    strip 掉 .symtab/.strtab         -1560 字节    能，退出码 3
    删掉整张 section header table    -3580 字节    能，退出码 3
    只改 2 个字节，让 segment 数 = 0  0 字节       不能，Exec format error

**删掉三千多字节照样跑，改两个字节直接死。**

    section  是给编译工具看的。运行时不需要，删了不影响执行
    segment  是给内核看的。少一条都装不起来

这也解释了嵌入式里为什么发布固件前要 strip：白省的空间，零代价。
而"strip 之后 gdb 就看不到函数名了"也是同一件事的另一面 ——
gdb 是链接期视角的工具，它读的正是被你删掉的那张表。

### 3.7 判据

    [ ] readelf -l 的 Section to Segment mapping 里，能指出 .text 属于哪条 LOAD，
        .data 属于哪条，并说出两条 LOAD 的 Flg 分别是什么
    [ ] 找出至少两个不属于任何 segment 的 section
    [ ] strip 后文件变小、section 变少、segment 数不变、退出码不变
    [ ] --strip-section-headers 后 section 数为 0，程序仍能跑出同样的退出码
    [ ] 把 e_phnum 改成 0 后，必须 Exec format error

    注错见红：3.5 那条命令里去掉 conv=notrunc 再跑一次。本机实测：

        截断后大小: 58 字节 (原 15888)
        $ readelf -h app_trunc
        readelf: Error: app_trunc: Failed to read file header
        $ ./app_trunc
        cannot execute binary file: Exec format error   (退出码同样是 126)

    **注意运行时的报错和 3.5 一模一样，但这是两种完全不同的失败。**
    dd 默认会把输出文件截断到写入位置，15888 字节的程序只剩 58 字节。
    分辨方法不是看运行报错，是看 `ls -l` 的大小和 readelf 能不能读。
    这条本身就是个教训：**同一个报错可以来自完全不同的原因，
    光看报错文字会误判。**
    （做完把 app_trunc 删掉，别拿它当 3.5 的结果。）

---

## 四、.bss：文件里不存，内存里要有

上一篇提过 `.bss` 是 NOBITS，说"下一篇讲"。现在讲。

### 4.1 先自己想

两个全局变量：

```c
int g_init = 1;     /* 有初值 */
int g_bss;          /* 无初值，C 标准规定它初值是 0 */
```

`g_init` 的那个 1 必须存在文件里，否则加载后不知道该填几。
那 `g_bss` 呢？它的初值是 0，而且 C 标准保证了这一点。

**问题：需要在文件里存 4 个字节的 0 吗？**

不需要。文件里只要记一句"我需要 4 字节，全 0"，加载时由内核清零就行。
省下的是**文件大小**。

那这个"省"到底有多大？拿一个大数组来放大它就看得见了。

### 4.2 动手

    cd labs/01_toolchain

`big1.c`：数组不给初值 -> 进 .bss

```c
int arr[1000000];
int main(void){ return arr[0]; }
```

`big2.c`：数组给了初值 -> 进 .data

```c
int arr[1000000] = {1};
int main(void){ return arr[0]; }
```

    arm-linux-gnueabihf-gcc -o big1 big1.c
    arm-linux-gnueabihf-gcc -o big2 big2.c
    ls -l big1 big2

本机实测：

```
-rwxrwxrwx 1 glorinz glorinz   69236 big1
-rwxrwxrwx 1 glorinz glorinz 4069236 big2
```

    4069236 - 69236 = 4000000
    = 1000000 个 int x 4 字节，一个字节不多不少

### 4.3 看 section：两个数组去了不同的箱子

    arm-linux-gnueabihf-readelf -S big1 | grep -E '\.data|\.bss'
    arm-linux-gnueabihf-readelf -S big2 | grep -E '\.data|\.bss'

本机实测：

```
big1:  [22] .data   PROGBITS  00020000 010000 000008 ...  WA
       [23] .bss    NOBITS    00020008 010008 3d0904 ...  WA

big2:  [22] .data   PROGBITS  00020000 010000 3d0908 ...  WA
       [23] .bss    NOBITS    003f0908 3e0908 000004 ...  WA
```

**逐列对照（Size 那一列是第 6 个数字）：**

              .data Size    .bss Size     Type
    big1      0x000008      0x3d0904      .bss 是 NOBITS
    big2      0x3d0908      0x000004      .data 是 PROGBITS

    0x3d0904 = 4,000,004 字节，就是那个数组（多出的 4 字节是别的变量）

**数组整个从 .bss 挪到了 .data。** 只因为你多写了 ` = {1}`。

    PROGBITS   "文件里真的有这些字节"    -> 占文件空间
    NOBITS     "文件里没有，只记大小"     -> 不占文件空间

### 4.4 看 segment：加载器怎么知道要清多少零

这才是关键的一步。回到 segment 表：

    arm-linux-gnueabihf-readelf -l big1 | grep -E '^  LOAD'
    arm-linux-gnueabihf-readelf -l big2 | grep -E '^  LOAD'

本机实测：

```
big1:  LOAD  0x000000 0x00000000 ... FileSiz 0x00648  MemSiz 0x00648   R E
       LOAD  0x00fed0 0x0001fed0 ... FileSiz 0x00138  MemSiz 0x3d0a3c  RW

big2:  LOAD  0x000000 0x00000000 ... FileSiz 0x00648  MemSiz 0x00648   R E
       LOAD  0x00fed0 0x0001fed0 ... FileSiz 0x3d0a38 MemSiz 0x3d0a3c  RW
```

**盯住 RW 那一行的两列：**

              FileSiz     MemSiz      差值
    big1      0x00138     0x3d0a3c    0x3d0904 = 4,000,004
    big2      0x3d0a38    0x3d0a3c    0x000004 = 4

> **FileSiz**：这个 segment 在**文件**里占多少字节
> **MemSiz** ：这个 segment 装进**内存**后要占多少字节

**两个数关键的对照，一定要看出来：**

1. **big1 和 big2 的 MemSiz 完全一样，都是 0x3d0a3c。**
   也就是说，把数组从 .bss 挪到 .data，**内存一个字节都没省**。
   省的只有磁盘上的文件大小。

2. big1 的 MemSiz 比 FileSiz 大了整整 4MB。

**加载器的规则就一条：**

    把文件里 FileSiz 那么多字节映射进内存，
    然后从 FileSiz 到 MemSiz 之间的那一段，全部填 0。

`.bss` 的全部魔法就在这个减法里。没有任何特殊机制，
就是 program header 里两个数字不相等而已。

上一篇 `maps.c` 里打印出 `g_bss = 0` 而你从没赋过值 —— 清零的就是这一步。

### 4.5 这条在嵌入式上意味着什么

    static char buf[4 * 1024 * 1024];              -> 进 .bss，固件不变大
    static char buf[4 * 1024 * 1024] = {1};        -> 进 .data，固件立刻涨 4MB

flash 空间紧张时这条能救命。但要同时记住 4.4 的第 1 条：
**它省的是 flash，不是 RAM。** RAM 该占多少还是多少。
把这两件事搞混，是嵌入式新手最常见的误判之一。

### 4.6 判据

    [ ] big2 - big1 的文件大小差 == 4,000,000，一个字节不差
    [ ] readelf -S 里 arr 在 big1 属于 NOBITS 的 .bss，在 big2 属于 PROGBITS 的 .data
        （查法：readelf -s bigN 找到 arr 那行，看它的第 7 列 section 下标，
          再对照 readelf -S 里那个下标是哪个 section）
    [ ] big1 的 RW LOAD 段 MemSiz - FileSiz == 0x3d0904 == 4,000,004
    [ ] big1 和 big2 的 MemSiz 完全相等（内存占用没变）
    [ ] 数得出 app 有几条 PT_LOAD、各自权限是什么（本机 big1 是 2 条：R E 和 RW）

    注错见红：把 big2.c 的 = {1} 改成 = {0}。
    编译器发现初值全 0，把它放回 .bss，文件又变回小的。
    本机实测这一版是 69,236 字节，和 big1 一模一样，一个字节不差。
    如果改成 = {0} 后文件还是 4MB，说明你编的不是你改的那个文件。

---

## 五、从 execve 到 main

前面都在看静态的文件。这一节看动态的过程：**从敲下 `./app` 到 main 执行，
中间这段路谁在跑。**

### 5.1 先自己想

第二节留了个疑问：`Entry point address` 是 `0x3dd`，而 main 在 `0x4d8`。
入口不是 main。那 0x3dd 是谁？

上一篇的 app.map 里已经出现过答案：

    .text  0x000003dc  0x34  Scrt1.o
           0x000003dc            _start

`_start` 在 0x3dc（入口 0x3dd 的末位 1 是 Thumb 指令集标记位，不是地址差异）。
**入口是 `_start`，来自 gcc 偷偷链进来的 Scrt1.o。**

### 5.2 动手：把整个过程录下来

要看一个程序执行期间发生了什么系统调用，用 `strace`：

    strace -e trace=execve,openat,mmap ./app_x86

    -e trace=...  只看这三种调用，否则输出淹死人
                  execve 执行程序、openat 打开文件、mmap 映射内存

本机实测：

```
execve("./app_x86", ["./app_x86"], 0x7ffc9230ec10 /* 24 vars */) = 0
mmap(NULL, 8192, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7649fff0c000
openat(AT_FDCWD, "/etc/ld.so.cache", O_RDONLY|O_CLOEXEC) = 3
mmap(NULL, 49255, PROT_READ, MAP_PRIVATE, 3, 0) = 0x7649ffeff000
openat(AT_FDCWD, "/usr/lib/x86_64-linux-gnu/libc.so.6", O_RDONLY|O_CLOEXEC) = 3
mmap(NULL, 2231696, PROT_READ, MAP_PRIVATE|MAP_DENYWRITE, 3, 0) = 0x7649ffc00000
mmap(0x7649ffc28000, 1671168, PROT_READ|PROT_EXEC, MAP_PRIVATE|MAP_FIXED, 3, 0x28000)
mmap(0x7649ffdc0000, 319488, PROT_READ, MAP_PRIVATE|MAP_FIXED, 3, 0x1c0000)
mmap(0x7649ffe0e000, 24576, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_FIXED, 3, 0x20d000)
+++ exited with 3 +++
```

### 5.3 逐行读这段录像

**第 1 行**：`execve` 是唯一一个"用新程序替换当前进程"的系统调用。
shell 就是靠它启动一切程序的。`= 0` 表示成功。

**注意从第 3 行开始的事：进程打开了 `libc.so.6`，还 mmap 了它四次。**
你的程序里根本没有 open 和 mmap 的代码，main 甚至还没开始跑。
**这几行是动态链接器（`ld.so`）干的，不是你的程序干的。**

它是从哪冒出来的？—— 第三节 `readelf -l` 里那条 INTERP：

    INTERP   0x000198 ... [Requesting program interpreter: /lib/ld-linux-armhf.so.3]

**内核看到 INTERP，就不会直接跳到你的 `_start`，而是先把这个"解释器"
加载起来，把控制权交给它。** 由它去加载 libc、填好函数地址，再转交给你。

**再看那四次 mmap 的权限，和第三节的 LOAD 表对上：**

    PROT_READ                    只读段
    PROT_READ|PROT_EXEC          代码段        <- 对应 Flg 的 R E
    PROT_READ|PROT_WRITE         数据段        <- 对应 Flg 的 RW

libc 也是 ELF，也有它自己的 LOAD segment，
**加载它用的是和加载你的程序完全相同的规则。**

**最后一行 `exited with 3`**，和 3.3 的退出码对上，程序确实正常跑完了。

### 5.4 完整的路径

把前面所有证据串成一条链：

```
    ./app          shell 调 execve("./app")
        |
        v
    [内核] load_elf_binary()                        <- 这就是"加载器"
        |
        +-- 检查 magic 是不是 7f 45 4c 46            <- 第二节 hexdump 看到的
        +-- 检查 e_machine 是不是本机架构             <- 不对就 ENOEXEC，2.5 注错见红
        +-- 遍历 program header：                     <- 第三节的 10 条
        |     PT_LOAD  每条 mmap 一次，按 Flg 设权限   <- 上一篇 maps 里的 r-xp/rw-p
        |     PT_LOAD  MemSiz 超出 FileSiz 的部分清零  <- 第四节的减法，.bss
        |     PT_INTERP 记下解释器路径
        |
        +-- 有 INTERP：控制权交给 ld.so
        |   没有（静态链接）：直接跳到 e_entry
        v
    [用户态] ld.so                                   <- 5.2 里那些 openat/mmap
        +-- 读 .dynamic，看到需要 libc.so.6
        +-- mmap libc 的每一条 LOAD segment
        +-- 重定位：把库函数的真实地址填进表里          <- 详见 04 篇
        v
    _start（来自 Scrt1.o，e_entry 指向它）
        +-- 整理 argc / argv / envp
        v
    __libc_start_main
        +-- 跑构造函数（.init_array）
        v
    main()                                           <- 你的代码终于开始跑
        |
        v
    return 3  ->  exit(3)  ->  strace 的 exited with 3
```

**"程序从 main 开始"是个方便的谎言。** main 之前至少还有内核的加载、
动态链接器的整个工作、以及 libc 的初始化。

### 5.5 判据

    [ ] readelf -h 的 Entry point，等于 app.map 里 _start 的地址（Thumb 位除外）
    [ ] strace 里能找到 execve 是第一条
    [ ] strace 里 libc.so.6 被 mmap 了不止一次，且至少有一次带 PROT_EXEC
    [ ] strace 最后一行的退出码，等于你 C 代码里 return 的值
    [ ] 能指出是哪条 program header 导致 ld.so 被加载进来

    注错见红：静态链接一次，PT_INTERP 就没了。

        gcc -static main.c add.c -o app_static
        readelf -l app_static | grep INTERP        # 应该什么都没有
        strace -e trace=openat ./app_static        # 不再打开 libc.so.6
        ls -l app_x86 app_static

    本机实测三个现象同时出现：

        INTERP 条数            0
        strace 里打开 libc     0 次
        文件大小               15,888 -> 816,896（大了 51 倍）
        退出码                 仍然是 3，程序行为不变

    大 51 倍是因为 libc 被整个塞进了你的程序里。
    三个现象要一起出现；如果 INTERP 没了但 strace 还在开 libc，
    说明你 strace 的是旧文件。

---

## 六、顺带一提：和裸机的对照

如果你在 ysyx 或龙芯 SoC 那边做过裸机程序，这里可以对一下。
**没做过也不影响，跳过这节即可，本篇不依赖它。**

裸机那边的流程是：

    编译链接出 ELF -> objcopy -O binary 剥成 .bin -> 烧进 flash -> pc 跳到固定地址

`objcopy -O binary` 那一步扔掉的，正是本篇讲的全部东西：
ELF 头、program header、section 表，只留下 LOAD segment 里的原始字节。

可以直接验证扔掉之后会怎样：

    objcopy -O binary app_x86 app.bin
    chmod +x app.bin
    ./app.bin

本机实测：

    cannot execute binary file: Exec format error

**裸 bin 在 Linux 下一定跑不起来**，因为内核第一步就查不到 magic。
反过来，裸机能用 .bin，是因为那边不需要这些信息：

    裸机                                Linux
    ---------------------------------   ------------------------------------
    只有一个程序，独占内存               多进程，各自要独立地址空间
    加载地址在链接脚本里写死             有虚拟内存和 ASLR，每次地址都可能不同
    没有库，所有代码都在这一个 bin 里     要在运行时找到并加载 libc
    没有权限概念，全部可读可写可执行      要按 segment 设 R/W/X

**这四条差异，正是 ELF 里 program header 存在的四个理由。**

---

## 七、这一篇解决了什么，还欠什么

    上一篇结束时的问题                         本篇的答案
    ----------------------------------------   -------------------------------
    布局怎么记在文件里                          program header table（第三节）
    加载器怎么知道 .bss 要清多少零              MemSiz 减 FileSiz（第四节）
    加载器按 section 映射吗                     不，按 segment（第三节实验证死）

    还欠着的，下面几篇接：
    ld.so 具体怎么"填地址"，PLT/GOT 是什么      -> 04_静态库动态库与符号
    execve 这类"系统调用"到底怎么进内核的        -> 05_系统调用与用户内核态
    mmap 到底做了什么，为什么是"映射"不是"拷贝"  -> 07_虚拟内存与mmap

---

## 八、被谁用到

    00_从源码到运行     本篇的前置，先读那篇
    01 章 3            内核在哪一步拒绝 ARM 程序（第二节的 e_machine）
    01 章 4            .interp 与动态链接（第五节）
    02 章              讲进程地址空间时回来看第三、四节
    第 2 阶段          .ko 也是 ELF（ET_REL），insmod 时内核自己做重定位
