# 03 Makefile 的使用

    PDF     第 154-165 页（目录页 145-156），第四篇第 3 章
    视频    4_3-1 到 4_3-7 共 7 集，分集表见 sources/README.md
    源码    $Q\04_嵌入式Linux应用开发基础知识\source\03/04/05_Makefile、04_2018Makefile

> [占位] 本篇由旧《01_工具链与构建系统》按原书章节拆出，正文仍是旧导学体例，
> 正在按 knowledge/README.md 的新教程体例重写。节号与自检/坑编号沿用旧稿原样；
> 实验环境与上板配置暂见 01 篇 0.4 节。

## 0.2 过滤表（本篇对应集）

**第三段 Makefile（视频 4_3-1 到 4_3-7，PDF 154-165）**

| 集     | 看不看    | 内容                                                                               |
| ----- | ------ | -------------------------------------------------------------------------------- |
| 4_3-1 | 跳      | 用 Visual Studio 演示"点鼠标就能编译"。结论一句话：IDE 背后就是 Makefile                              |
| 4_3-2 | **重点** | 规则的形状；为什么要分开编译；make 靠比时间戳决定重编谁                                                   |
| 4_3-3 | **看**  | `%` 模式规则、`$@ $< $^`、假想目标（现场演示了 `clean` 同名文件的坑）、变量的四种赋值                           |
| 4_3-4 | **看**  | 四个函数：`foreach` / `filter` / `filter-out` / `wildcard` / `patsubst`。现场踩了延时变量自引用的坑 |
| 4_3-5 | **重点** | 全集最关键的一集：改了 `.h` 却不重编的现场，以及自动生成依赖                                                |
| 4_3-6 | **看**  | 通用 Makefile 怎么用：改三个地方就能管一个多目录工程                                                  |
| 4_3-7 | **看**  | 通用 Makefile 怎么实现：递归调用 + `built-in.o` 层层合并                                        |

---

## 4 第三段：Makefile

### 4.0 看哪里

    视频    4_3-1 到 4_3-7 共七集，过滤表见 0.2
    PDF     154-165 页
    源码    $Q\04_...\source\03_Makefile、04_2018Makefile、05_general_Makefile
            注意：视频 4_3-2 起用的是 04_2018Makefile 下的源码，
            视频里说的目录名和你看到的对不上，这是视频剪辑复用造成的

七集加起来一百分钟，但真正的内容只有三层，压缩在 4.1 到 4.6。
4.7 和 4.8 是两个从零写的实验。

### 4.1 第一性原理：make 只有一条公理

**make 不理解 C，不理解编译，它只会做一件事：比两个文件的时间戳。**

整个 Makefile 体系都是这一条推出来的。

    规则的形状：

        目标: 依赖1 依赖2 ...
        <TAB>命令

    执行条件只有两个：
        1. 目标文件不存在
        2. 任意一个依赖比目标新

    满足其一，就执行命令。

举例：

| `main.c`（依赖）mtime | `main.o`（目标）mtime | make 的决定 |
|---|---|---|
| 10:00:05 | 10:00:07 | 依赖比目标旧，不重编 |
| 10:00:09 | 10:00:07 | 依赖比目标新，重编 |

**比的是 mtime，不是内容哈希。** 直接后果：

    touch main.c        内容一个字没改，依赖它的全部重编
    改完又改回来        内容和原来一样，照样重编

（顺带一提，这也是 ccache 存在的理由：它在 gcc 前面加一层内容哈希缓存，
内容没变就直接吐出上次的 `.o`。你这台机器上已经装了 ccache。）

从这一条公理出发，剩下的一切都是在回答同一个问题：
**"依赖"这张表怎么才能写全、写对、又不用手写。**

| 层次 | 做法 | 解决什么 | 仍有什么问题 | 章节 |
|---|---|---|---|---|
| 一 | 手写每一条规则 | make 能按规则构建 | 一千个文件要写一千条 | 4.2 |
| 二 | 模式规则 `%.o : %.c` | 用一条规则覆盖同类文件 | 依赖表仍漏掉 `.h` | 4.3 |
| 三 | 让编译器生成依赖表 | 头文件变化也能触发正确重编 | 不做会留下隐蔽 bug | 4.6 |

### 4.2 层次一：规则

视频 4_3-2 从 `gcc -o test a.c b.c` 一路推到三条规则，推导过程见 3.3 节。
最终形态：

    test: a.o b.o
    	gcc -o test a.o b.o

    a.o: a.c
    	gcc -c -o a.o a.c

    b.o: b.c
    	gcc -c -o b.o b.c

`make` 不带参数时生成**第一条规则的目标**。它会递归地先满足依赖：
要 `test` 就先要 `a.o`，要 `a.o` 就先看 `a.c` 的时间戳。

**命令前面必须是 TAB，不能是空格。** 这是 Makefile 最著名的坑，
报错是 `missing separator`。编辑器默认可能把 TAB 转成空格，
给 Makefile 单独设一下。

`make xxx` 可以指定生成哪个目标，`make clean` 就是这么工作的。

### 4.3 层次二：模式规则、自动变量、四种赋值

**模式规则**（视频 4_3-3 的 1:19 处）：

    %.o : %.c
    	gcc -c -o $@ $<

    % 是通配符，两边的 % 匹配同一段文字。
    要生成 a.o 时，make 拿 a.o 去套这条规则，% 匹配到 a，依赖就是 a.c。

**三个自动变量**：

    $@   目标
    $<   第一个依赖
    $^   全部依赖，去重

    为什么编译用 $< 而链接用 $^：
        编译     一次只喂一个 .c 给 gcc，所以取第一个依赖
        链接     要把所有 .o 一起喂给 gcc，所以取全部

    这个区别在 4.6 打开自动依赖之后变成硬约束：那时 $^ 里会多出一串 .h，
    喂给 gcc 会出错。

**四种赋值**（视频 4_3-3 的 10:33 到 19:42）：

    :=    即时变量。定义的那一刻就求值，之后右边再变也不影响它
    =     延时变量。用到的时候才求值
    ?=    延时变量，但只在该变量还没被定义过时才生效
    +=    追加。是即时还是延时，取决于前面那个变量是怎么定义的

即时和延时的差别，视频里用这个例子演示的：

    A := $(C)        # 此刻 C 还是空的，所以 A 永远是空
    B  = $(C)        # 用到 B 的时候才去取 C
    C := abc

    all:
    	@echo "A = $(A)"     # A =
    	@echo "B = $(B)"     # B = abc

    注意 make 会先把整个 Makefile 读完再执行规则，所以 C 定义在后面
    对 B 没有影响，对 A 有影响。

自己敲一遍，把 `C := abc` 挪到最前面再跑一次，两次输出对比着看。

**延时变量不能自引用**：`X = $(X) foo` 会让 make 报
`Recursive variable 'X' references itself (eventually)`。
视频 4_3-4 的 8:19 和 4_3-5 的 13:18 各踩了一次。改成 `X := $(X) foo` 即可，
因为即时变量的右边在求值那一刻用的是旧值。

### 4.4 四个函数

视频 4_3-4 讲了四个，加上 4_3-5 用到的一个，本仓的 `project/Makefile` 里全用上了。

    $(wildcard *.c)
        去磁盘上列出匹配的文件。**注意是真的去磁盘找，找不到就不返回。**
        这一条被用在两个完全不同的用途上：
          用途 A  收集源文件      SRCS := $(wildcard *.c)
          用途 B  过滤出真实存在的文件   DEPS := $(wildcard $(DEPS))
                  用途 B 是给 include 用的，见 4.6

    $(patsubst %.c,%.o,$(SRCS))
        模式替换。不匹配的项原样保留。
        简写：$(SRCS:.c=.o)

    $(filter %/,$(LIST))         从列表里挑出符合模式的
    $(filter-out %/,$(LIST))     挑出不符合的
        通用 Makefile 用它区分"这一项是目录还是文件"，见 4.8

    $(foreach d,$(DIRS),$(wildcard $(d)/*.c))
        对列表里每一项做一次展开，结果拼起来。
        project/Makefile 用它收集六个子目录的源文件。

查函数用法就查 GNU make 手册的 Functions 那一章，
视频 4_3-4 全程在演示"忘了就去搜手册"这个动作，这本身也是要学的东西。

### 4.5 假想目标：clean 的那个坑

    clean:
    	rm -f *.o test

平时能用。但如果目录里正好有一个**名字叫 `clean` 的文件**：

    目标 clean 存在
    依赖 一个都没有，没法比时间戳
    -> make 认为目标是最新的
    -> make: 'clean' is up to date.  什么都不做

视频 4_3-3 的 8:03 处现场造了一个 `clean` 文件复现了这个现象。

修法是声明它是假想目标（也叫伪目标）：

    .PHONY: clean
    clean:
    	rm -f *.o test

`.PHONY` 告诉 make："`clean` 不是一个文件名，别去比时间戳，无条件执行。"

自己复现一遍，这一条比看视频印象深：

    touch clean
    make clean          # 预期：什么都不做
    # 加上 .PHONY 那一行再跑
    make clean          # 预期：正常执行

`all` 也要声明，理由相同。

### 4.6 层次三：自动头文件依赖

**这一层是分水岭。视频 4_3-5 整集讲的就是它，是七集里最该逐帧看的一集。**

问题在于：`main.o: main.c` 这条规则里没有 `config.h`。

| 关系来源 | make 当前知道的依赖 |
|---|---|
| Makefile 手写规则 | `main.o → main.c` |
| 源码真实 include 关系 | `main.o → main.c → config.h` |

缺少的是 `main.o` 对 `config.h` 的间接依赖；只看手写规则时，make 不知道改头文件也该重编 `main.o`。

你改了 `config.h` 里的一个宏，make 沿着它知道的那条边看：
`main.c` 没变，`main.o` 是最新的，不重编。

视频 4_3-5 的 2:27 处现场演示了这个：改了 `c.h` 里的宏，
`make` 说没事可做，程序输出还是旧值。

**结果是最难查的那类 bug：**

| 文件 | 修改前后/重编情况 | 对 `struct point` 的理解 |
|---|---|---|
| `config.h` | `{ int x, y; }` 改成 `{ int x, y, z; }` | 定义已变为 12 字节 |
| `main.o` | 没重编 | 仍按 8 字节计算 `sizeof` |
| `display.o` | 已重编 | 按 12 字节解释 |

两边对同一块内存的理解不同，坐标会读错；编译可以零警告，运行表现却很诡异。

手写依赖是不可能的：视频里说"对我们的内核它有几万个文件，
对于这几万个文件你都要打开确定它的头文件吗"。

**解法：让编译器自己吐出依赖关系。** 四个相关选项，逐级递进：

    gcc -M  c.c              打印完整依赖（含系统头），只打印不编译
    gcc -MM c.c              同上，但跳过系统头
    gcc -MF c.d ...          指定依赖写到哪个文件
    gcc -MD -c -o c.o c.c    边编译边生成 .d
    gcc -MMD -c -o c.o c.c   同上，跳过系统头

    生成的 c.d 内容就是一行普通的 make 规则：
        c.o: c.c common.h config.h

Makefile 用 `include` 读入全部 `.d` 后，依赖会成为 `main.o → main.c` 和 `main.o → config.h` 两条明确关系。

**两种写法，效果一样：**

| 项目 | 教材：`-MD` + wildcard 过滤 | 本仓 `project/`：`-MMD -MP` |
|---|---|---|
| 编译命令 | `gcc -Wp,-MD,.$@.d -c -o $@ $<` | `gcc -MMD -MP -c -o $@ $<` |
| 引入依赖 | 先 `wildcard` 过滤已经存在的 `.d`，再用 `include` | 直接 `-include $(DEPS)`；文件不存在也不报错 |
| 系统头 | `-MD` 会写入系统头 | `-MMD` 跳过基本不会变化的系统头 |
| 删除头文件 | 仍可能报缺目标 | `-MP` 给每个头补空规则，避免 `No rule to make target`，改为直接重编 |

教材那套的价值在于它把每一步都摊开了，值得照着写一遍再换成短的。

**顺便一个视频里踩到的坑**（4_3-5 的 3:54 处）：手工加

    c.o: c.c c.h
    <TAB>

那个 TAB 后面什么都不写，就成了一条**空命令规则**，它会覆盖掉模式规则，
结果是 `c.o` 永远不会被重新生成。删掉那个 TAB 就好了。
这说明 make 里"有命令"和"没有命令"是两回事，空命令也是命令。

**还有一个选项值得现在就加上**（4_3-5 的 14:37 处）：

    CFLAGS := -Werror -Wall

    -Wall     打开常用警告
    -Werror   把警告当错误，编不过去

    视频里的原话：我建议你们编译程序的时候都加上这个选项，
    很多警告都隐藏有错误。

本仓 `project/Makefile` 用的是 `-Wall -Wextra`，没加 `-Werror`。
理由是学习阶段警告太多会挡住进度，但**上板前的最后一次编译建议手工加一次**
`make CFLAGS_EXTRA=-Werror` 看看有没有藏着的问题。

### 4.7 [做 L3] 一个五文件工程，一份手写 Makefile

**这一节是本章第一个从零手写的部分。别看资料仓的源码，写完再去对照。**

先建工程（代码自己敲，逻辑随便写，重点在文件之间的依赖关系）：

    knowledge/labs/01_hello/mini_proj/
        main.c          调用 add() 和 print_banner()
        math_ops.c      实现 add()
        math_ops.h
        display.c       实现 print_banner()，内部 #include "config.h"
        display.h
        config.h        定义一个宏 BANNER_TEXT

    关键是 display.c 必须 include config.h。第 4 步的坑就埋在这条边上。

Makefile 分五步长出来，**每一步都能单独跑、单独验**。别一上来就照抄最终形态，
那样你只是抄了一份配置，感受不到每一层在解决什么问题。

    第 1 步  全部写死
             四条编译规则加一条链接规则，一个变量都不用，一条模式规则都不用。
             [验] make 能出可执行文件，能跑。
             [感受] 又臭又长，加一个文件要改两处。这就是后面几步要治的病。

    第 2 步  引入变量和模式规则
             CC、CFLAGS 提成变量；四条编译规则塌缩成一条 %.o : %.c。
             [验] make clean && make，产物和第 1 步的字节完全一样：
                  md5sum 两次的产物对比。变了说明你顺手改了别的东西。

    第 3 步  自动收集源文件
             $(wildcard *.c) 拿到源文件列表，$(patsubst) 或 $(SRCS:.c=.o) 转成 .o 列表。
             [验] 新建 extra.c 并在 main.c 里调它，不改 Makefile，make 必须成功。

    第 4 步  头文件自动依赖         <== 最关键的一步，也最容易糊弄过去
             编译时加 -MMD 生成 .d，用 -include 把它们读进来。
             [验] 改 config.h 里的 BANNER_TEXT，make 之后程序输出必须跟着变。
             [注错] 把 -include 那行注释掉，再改 config.h，
                    make 会说"nothing to be done"，程序输出不变。
                    **一定要亲眼看到这个现象**，这是 4.6 讲的那个隐蔽 bug 的原型。

    第 5 步  支持交叉编译
             CC := $(CROSS)gcc，CROSS 默认为空。
             [验] make clean && make CROSS=arm-linux-gnueabihf-，file 显示 ARM。

写的过程中用到的记号在 4.3、4.4、4.5，忘了翻回去。
不确定的查 GNU make 手册（`info make`）。

**[判] 这五条必须逐条注错见红**

    [ ] 判据 1  make 后能跑，输出正确

    [ ] 判据 2  改 config.h 里的 BANNER_TEXT，再 make，display.o 必须重编，
                程序输出跟着变。
                注错方式：把 include .d 那几行注释掉，再改 config.h，
                make 应该表现为什么都没做，程序输出不变。
                见到这个现象，才算真懂了第三层。

    [ ] 判据 3  新建 extra.c 并在 main.c 里调用它的函数，不改 Makefile，
                make 必须成功。
                注错方式：把 wildcard 换成写死的文件清单，extra.c 就编不进去，
                链接时报 undefined reference。

    [ ] 判据 4  make clean && make CROSS=arm-linux-gnueabihf- 后，
                file 显示产物是 ARM。
                注错方式：故意漏掉 CROSS 前缀（比如写成 CC := gcc 写死），
                产物会变回 x86。

    [ ] 判据 5  make clean 后目录里没有任何 .o .d 和可执行文件。
                用 ls -a 检查，.d 如果起名成 .main.d 是隐藏文件，容易漏。

### 4.8 [做 L3] 通用 Makefile：内核那套递归构建

视频 4_3-6 教怎么用，4_3-7 教怎么实现。**这一节要从零复现一遍它。**

**为什么要学它**：本仓的 `project/Makefile` 没有用这套（理由见第 5 节），
但 Linux 内核和 U-Boot 的构建就是这套。第 2 阶段读内核 Makefile 时躲不开。
视频 4_3-7 结尾那句话说得很准："以后我们来分析内核、分析 U-Boot 时，
才需要对 Makefile 有更加深刻的理解。"

**它的设计思想，三条：**

    1. 每个目录一份 Makefile，里面只声明一个变量 obj-y：
           obj-y += main.o
           obj-y += sub.o
           obj-y += a/          <-- 结尾带斜杠的是子目录
       靠结尾那个斜杠区分"这一项是文件还是目录"。

    2. 顶层有一份 Makefile.build，它是递归引擎。
       它被 make -f 反复调用，每次处理一个目录。

    3. 每个目录里的 .o 用 ld -r 合并成一个 built-in.o，
       子目录的 built-in.o 再并进上一层，最后顶层的 built-in.o 链接成程序。

合并关系如下：

| 合并阶段 | 输入 | 输出 |
|---|---|---|
| 子目录 `a/` | `a/sub2.o`、`a/sub3.o` | `a/built-in.o` |
| 顶层 | `main.o`、`sub.o`、`a/built-in.o` | 顶层 `built-in.o` |
| 最终链接 | 顶层 `built-in.o` | `app` |

**先自己想（这一节的先自己想比前面几节都重要）：**

    问题 1  make -C a -f ../Makefile.build 这条命令做了什么？
            两个选项分别是什么意思？
    问题 2  Makefile.build 怎么知道当前目录里有哪些 .o、哪些子目录？
            提示：它自己 include 当前目录的 Makefile。
    问题 3  为什么要 ld -r 合并成 built-in.o，直接把所有 .o 一起链接不行吗？
            提示：想想顶层的链接命令要写多长，以及它要怎么知道
            三层深的目录里有哪些 .o。
    问题 4  $(filter %/, $(obj-y)) 和 $(patsubst %/,%,...) 组合起来在干什么？

**任务**：自己写出 `Makefile` 和 `Makefile.build` 两个文件，
管理这样一个工程：

    proj/
        Makefile
        Makefile.build
        main.c
        sub.c
        include/sub2.h  include/sub3.h
        a/
            Makefile
            sub2.c
            sub3.c

要求做到视频 4_3-6 演示的四件事：

    1. make 能编出程序，make clean 能清干净
    2. 改 include/sub3.h，只有 sub3.c 重编
    3. 在 a/Makefile 里写 EXTRA_CFLAGS := -DDEBUG，
       只有 a 目录下的文件带这个宏
    4. 在 a/Makefile 里写 CFLAGS_sub3.o := -DDEBUG_SUB3，
       只有 sub3.c 带这个宏

第 3、4 条是这套东西相对 4.7 那份 Makefile 的真正优势：
**按目录、按单个文件设置编译选项。**

写不出来再去看资料仓的 `05_general_Makefile`，
但先自己想满二十分钟——第 3、4 条怎么做到，是这一节的全部价值。

**[判]**

    [ ] make 之后跑起来，输出正确
    [ ] touch include/sub3.h && make，只有 sub3.c 被重编（数编译命令的条数）
    [ ] a/ 下两个文件的编译命令里有 -DDEBUG，顶层两个文件的没有
        用 make V=1 或者去掉 @ 看完整命令
    [ ] sub3.c 的编译命令里有 -DDEBUG_SUB3，sub2.c 的没有
    [ ] find . -name built-in.o 能找到两个：顶层一个，a/ 一个

    注错见红：把 a/Makefile 里的 obj-y 那两行删掉一行，
    make 之后链接必须报 undefined reference。
    如果照样能链接成功，说明你的 built-in.o 是用别的方式收集的，回去查。

---

## 5 落进项目：本章交出的是构建系统

`project/` 是这个仓的终点整合项目，它会长十几章。
**这一节只讲它的构建系统，也就是本章第 4 节那些知识的落地。**

分层怎么定的、启停顺序为什么是那样、判据体系怎么设计的——
那些是整个项目的地基，不属于这一章的知识范围。
它们写在工程文档里，跟这一章的进度无关：

    Engineering/TechReports/project/01-先立骨架-分层启停与两棵产物树.md
        为什么是这个形状：分层、启停顺序、失败回滚、判据的两条原则

    Engineering/CodeReading/project/
        每个文件逐行讲解，含行号

    Engineering/Todo/项目路线图-对齐电子产品量产工具.md
        和课程配套项目的逐项对照，以及每一章该往里填什么

**这一节要做的只有一件事：把 `project/Makefile` 逐行读懂，
确认第 4 节学的每一个记号在真实工程里长什么样。**

### 5.1 四个记号，四个落点

    第 4 节学的                      project/Makefile 里的样子           行
    -----------------------------    ---------------------------------   ---
    4.3 变量的即时/延时赋值          CROSS ?= 与 CC := $(CROSS)gcc       12-13
    4.4 wildcard + foreach           SRCS := $(wildcard *.c) $(foreach   25
                                       d,$(SUBDIRS),$(wildcard $(d)/*.c))
    4.4 patsubst                     OBJS := $(patsubst %.c,             26
                                       $(BUILD)/%.o,$(SRCS))
    4.6 -MMD -MP 与 -include         第 54 行和第 57 行                  54,57

还有一个第 4 节没讲、但这里用到了的：

    ARCH := $(if $(CROSS),$(firstword $(subst -, ,$(CROSS))),x86)       16

`$(if a,b,c)`、`$(firstword ...)`、`$(subst 旧,新,串)` 三个函数套在一起，
作用是从工具链前缀里算出架构名：`arm-linux-gnueabihf-` 得到 `arm`，
前缀为空得到 `x86`。自己拆一遍，从最里面往外拆。

验证方法（这也是 `make show` 那个目标存在的理由）：

    cd /mnt/e/Workspace/embedded-linux/project
    make show
    make CROSS=arm-linux-gnueabihf- show

**本机实测：**

    $ make show | head -2
    ARCH  = x86
    CC    = gcc

    $ make CROSS=arm-linux-gnueabihf- show | head -2
    ARCH  = arm
    CC    = arm-linux-gnueabihf-gcc

### 5.2 [做 L4] 三个自问，两次注错

**这个骨架已经建好了，你不用重写它。**

它是脚手架不是知识点：分层结构、层表、多架构构建这些东西全项目只搭一次，
搭完后面十几章都往里填。你要从零写的是 4.7 的 `mini_proj` 和 4.8 的通用 Makefile，
那才是 Makefile 的知识点。

**但要做这三件事，不做等于这一节没学。**

**第一件，回答三个自问。** 答不上来就回 4.4 和 4.6：

    1. 第 25 行为什么用 $(foreach) 而不是直接 $(wildcard */*.c)？
       提示：想想 build/ 目录，以及以后会加的 unittest/ 目录里有什么。

    2. 第 26 行为什么要把 .o 放进 $(BUILD)/ 而不是源码旁边？
       提示：两个架构的产物要能同时存在。

    3. 第 54 行的 -MP 去掉会怎样？什么场景下才看得出差别？
       提示：删掉一个头文件，并且从 .c 里去掉那行 #include，再 make。

**第二件，亲手跑一遍：**

    cd /mnt/e/Workspace/embedded-linux/project
    make && ./build/x86/product_tool
    make CROSS=arm-linux-gnueabihf-
    file build/arm/product_tool
    ls build/*/product_tool          # 两份产物同时在
    bash check.sh

**本机实测** `bash check.sh` 的结果：

    PASS=18  FAIL=0  SKIP=0

**第三件，亲手做两次注错见红。** 这两条都直接对应第 4 节的知识点：

    注错 A（对应 4.4 的 wildcard）
        把 Makefile 第 25 行的 SRCS 换成写死的文件清单，
        然后在 display/ 下新建一个 .c，make。
        预期：那个新文件不会被编译，链接时如果有人调它就报 undefined reference。
        说明什么：wildcard 收集源文件这件事是有代价也有收益的，
                  收益是加文件不用改 Makefile，代价是删了 .c 忘了删引用时
                  报错发生在链接期。

    注错 B（对应 4.6 的自动依赖）
        把 Makefile 第 54 行的 -MMD -MP 删掉，make clean && make，
        然后 touch include/common.h 再 make。
        预期：一个文件都不重编。
        说明什么：4.6 那个坑在真实项目里长什么样。

        注意顺序：必须先完整 make 一次，再 touch，再 make。
        顺序错了量到的是"产物不存在所以全编"，跟依赖生效与否无关。

    做完记得改回去，或者 git checkout project/Makefile。

这两条注错在 `check.sh` 里各有一条自动化版本（`[3r]` 和 `[4r]`），
手工做一遍是为了亲眼看现象，自动化版本是为了以后每次改动都能重跑。

### 5.3 这个 Makefile 和视频那份通用 Makefile 的关系

本仓没有采用 4.8 那套递归构建。理由一句话：
**那套东西的三项能力（任意深的目录树、按目录设编译选项、按单文件设编译选项），
本仓当前一项都用不上，而它的代价是构建过程分散在七个文件里。**

完整的权衡、以及什么条件下会改回去，写在
`Engineering/Todo/项目路线图-对齐电子产品量产工具.md` 第 3.3 节。

**这不影响 4.8 那个实验的必要性。** 内核和 U-Boot 就是那套，
第 2 阶段躲不开。学它是为了读得懂别人的，不是为了用在自己的工程里。

---


---

## 6 自检问题

答不上来就回到对应小节重读。这些问题都能用命令验证，不要凭印象答。

    11. make 判断要不要重新执行一条规则，依据是什么？它看内容还是看时间戳？(4.1)

    12. Makefile 里 $@ $< $^ 分别是什么？为什么编译规则用 $< 而链接用 $^？
        打开自动依赖之后，用 $^ 会出什么问题？                             (4.3 4.6)

    13. := 和 = 有什么区别？下面这段输出是什么，为什么？                   (4.3)
            A := $(C)
            B  = $(C)
            C := abc

    14. 目录里有一个叫 clean 的文件，make clean 会怎样？怎么解决？          (4.5)

    15. 不做自动头文件依赖，会在什么情况下编出一个能编过但行为错误的程序？
        描述一个具体场景。                                                  (4.6)

    16. -MD 和 -MMD 差在哪？-MP 解决的是什么场景下的什么问题？             (4.6)

    17. 通用 Makefile 靠什么区分 obj-y 里的一项是文件还是目录？
        built-in.o 是怎么层层合并上去的？                                   (4.8)

    18. wildcard 收集源文件有什么风险？
        （提示：一个被废弃但没删的 .c；一个只在某平台才该编译的 .c；
        一个带 main() 的测试文件）                                        (4.4 5.2)

---

## 7 已知的坑


    坑 6  Makefile 的命令行必须用 TAB 缩进，不能用空格。编辑器默认可能把 TAB
          转成空格，报错是 missing separator。给 Makefile 单独设成 TAB。     (4.2)

    坑 7  一条规则后面跟一个只有 TAB 的空行，它是"空命令规则"，
          会覆盖掉模式规则，导致目标永远不重新生成。                        (4.6)

    坑 8  延时变量不能自引用（X = $(X) foo），会报 Recursive variable。
          改成即时变量 X := $(X) foo。                                      (4.3)

    坑 9  第一次 make 时 .d 文件不存在。用 include 必须先 wildcard 过滤，
          用 -include 则不用管。                                            (4.6)

    坑 10 验证"自动依赖生效了"时，必须先完整 make 一次再 touch 头文件。
          直接 clean 之后 touch 再 make，量到的是"产物不存在所以全编"。      (5.2)

    坑 11 在 /mnt/e/ 下（Windows 文件系统）编译，mtime 精度和 IO 性能都不如
          WSL 原生盘。如果遇到明明改了却不重编的现象，把工程挪到 ~ 下试试。
          project/check.sh 就是把整个工程复制到临时目录再跑的，原因之一就是这个。

    坑 12 wildcard 收集源文件时，如果误留了一个带 main() 的测试文件，
          链接会报 multiple definition of main，报错信息不直观。            (5.2)
    坑 14 视频 4_3-2 起讲的源码在 04_2018Makefile 目录，
          不是视频里口播的那个路径。这是视频剪辑复用旧素材造成的。          (4.0)
