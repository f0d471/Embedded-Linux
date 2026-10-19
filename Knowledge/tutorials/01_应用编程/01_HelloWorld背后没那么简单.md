# 01 HelloWorld 背后没那么简单

    实验    Knowledge/labs/01_hello/
    电脑    WSL Ubuntu 26.04，gcc 15.2.0，arm-linux-gnueabihf-gcc 15.2.0
            （本篇"本机实测"均为 2026-10-20 实跑）
    板子    100ASK_IMX6ULL Pro，Linux 4.9.88，glibc 2.30
            （板上输出均为 2026-09-14 实测归档）

---

**读前须知**：会在终端里敲命令、见过一点 C 语言就够了。下面几样东西本篇都会
从头讲，不需要提前会：

- 退出码、`echo $?`：第 1.3 节当场讲
- 机器码、指令集：第 2.2 节当场讲
- ELF 文件、系统调用：第 3 节用到时讲到够用为止；想彻底弄懂再看
  [fundamentals/00 从源码到运行](../../fundamentals/00_从源码到运行.md) 和
  [fundamentals/01 ELF与程序加载](../../fundamentals/01_ELF与程序加载.md)
- 读过 [00 这台机器与我们要造的东西](./00_这台机器与我们要造的东西.md) 更好：
  那里讲了电脑和板子是"两个世界"，本篇是第一次真正在两个世界之间搬东西

**这一章在整机里的位置**：上接 00 篇，下接 02 篇（GCC 的编译过程）。它补的零件
是"电脑上写的程序怎么变成板子上能跑的程序"这条通道。后面每一章的实验、Project
的每一层，上板时都走这条通道。

**不学它会怎样**：在电脑上编好的程序传到板子上，会先报 `Exec format error`；
换了编译器又报 `GLIBC_2.34 not found`；就算两关都过了，串口传上去的文件也可能
在没有任何提示的情况下少了几个字节。三件事各有原因，本章逐个讲清。

## 0 起点

我们手里有一份最短的 C 程序 `hello.c`，在电脑上一编一跑就能打印出一行字。
我们要做的事情只有一件：**让它在板子上也打印出这行字。**

这听起来只是"拷过去再运行"。实际走一遍会碰到三道坎，每道坎都会逼我们多弄懂
一样东西：

    第 1 节  这个程序由哪些部分组成，各部分在电脑上分别是谁负责的
    第 2 节  电脑和板子的 CPU 不一样，同一份源码要编成两种机器码
    第 3 节  编错了机器码的程序，是谁、在哪一步、凭什么把它拦下的
    第 4 节  怎么把文件送进板子，路上会出什么问题
    第 5 节  在板子上运行，三种编法分别是什么下场，为什么

每一节都从上一节留下的问题出发。读完之后，你应该能自己解释板子上打印出的
每一行字，包括失败的那几行。

---

## 1 一个程序最少由什么组成

### 1.1 先让它在电脑上跑起来

先看源码。完整文件在 `Knowledge/labs/01_hello/hello.c`：

```c
#include <stdio.h>

/* 执行命令: ./hello learner
 * argc = 2
 * argv[0] = ./hello
 * argv[1] = learner
 */
int main(int argc, char **argv)
{
    if (argc >= 2)
        printf("Hello, %s!\n", argv[1]);
    else
        printf("Hello, world!\n");
    return 0;
}
```

先不急着读懂每一行，把它编出来、跑起来。在仓库根目录下进入实验目录：

```bash
cd Knowledge/labs/01_hello
gcc -O2 -Wall -Wextra hello.c -o hello_x86
./hello_x86
./hello_x86 learner
```

这四条命令逐个说清：

- `cd Knowledge/labs/01_hello`：进入实验目录。后面所有命令都在这个目录里执行。
- `gcc ... hello.c -o hello_x86`：调用编译器 gcc，读入源码 `hello.c`，产出一个
  能运行的文件。
  - `-o hello_x86`：`-o` 后面跟输出文件的名字。不写 `-o` 时 gcc 会把产物叫
    `a.out`。起名叫 `hello_x86` 是为了和后面编给板子的版本区分开，"x86" 是
    电脑 CPU 的种类，第 2 节会讲。
  - `-O2`：让编译器做常规的优化。它不改变程序的行为，只让生成的代码更紧凑。
  - `-Wall -Wextra`：打开警告。编译器发现"语法上没错、但很可能是你写错了"的
    地方时会说出来。它们不改变产物。
- `./hello_x86`：运行刚编出来的文件。前面的 `./` 表示"当前目录下的这个文件"。
  不写 `./` 时，shell 只会去系统登记的几个程序目录（`PATH` 变量里列的那些）里找，
  当前目录不在其中，就会报找不到命令。
- `./hello_x86 learner`：运行时在后面多跟一个词。

本机实测：

```text
$ ./hello_x86
Hello, world!
$ ./hello_x86 learner
Hello, learner!
```

同一个程序，后面多跟一个词，打印的内容就变了。程序是怎么知道你在后面跟了
什么的？这就是 `main` 那两个参数的事。

**这一节搭好的积木**：一份 `.c` 源码经过 gcc 变成一个能运行的文件，用
`./文件名` 运行它。接下来的问题：运行时跟在后面的词，是怎么交到程序手里的。

### 1.2 main 的两个参数从哪里来

`main` 是程序开始执行的地方。它的完整写法有两个参数：

```c
int main(int argc, char **argv)
```

这一行从左往右读：

- `int`：`main` 执行完会交回一个整数。交给谁，下一节讲。
- `main`：函数名。C 程序规定从名叫 `main` 的函数开始执行。
- `int argc`：第一个参数，一个整数，名字是 argument count 的缩写，意思是
  "启动时一共收到了几个参数"。
- `char **argv`：第二个参数，名字是 argument vector 的缩写，装的是那些参数的
  内容。`char **` 的写法以后会细讲；现在只要知道它可以当一个字符串数组来用：
  `argv[0]`、`argv[1]`、`argv[2]`……每一项是一个字符串。

这两个参数不是程序自己算出来的，是**启动它的那个程序**交给它的。你在终端里
敲命令时，负责接收命令的是 shell（这里是 bash）。bash 拿到你敲的一整行字，
先按空格把它切成一个一个的词，再启动程序，把切好的词交过去。

为了亲眼看到交过去的是什么，用一个专门把参数原样打印出来的小程序
`Knowledge/labs/01_hello/argv_dump.c`：

```c
#include <stdio.h>

int main(int argc, char **argv)
{
    int i;

    printf("argc = %d\n", argc);
    for (i = 0; i < argc; i++)
        printf("argv[%d] = %s\n", i, argv[i]);
    return 0;
}
```

逐行读：

- `int i;`：声明一个整数变量 `i`，下面的循环拿它当计数器。
- `printf("argc = %d\n", argc);`：打印一行。`printf` 的第一个参数是格式串，
  里面的 `%d` 是一个占位符，表示"这里填一个十进制整数"，填进去的就是后面的
  `argc`。`\n` 是换行。
- `for (i = 0; i < argc; i++)`：循环。括号里用分号隔成三段：
  `i = 0` 是开始前做一次的事（计数器从 0 开始）；`i < argc` 是每一轮开始前的
  检查（不满足就结束循环）；`i++` 是每一轮结束后做的事（计数器加 1）。
  合起来：`i` 依次取 0、1、2……直到 `argc - 1`。
- `printf("argv[%d] = %s\n", i, argv[i]);`：每一轮打印一项。`%s` 也是占位符，
  表示"这里填一个字符串"，填进去的是 `argv[i]`。

编译并用四种方式运行：

```bash
gcc -Wall argv_dump.c -o argv_dump
./argv_dump
./argv_dump learner
./argv_dump "hello board"
./argv_dump hello board
```

本机实测：

```text
$ ./argv_dump
argc = 1
argv[0] = ./argv_dump

$ ./argv_dump learner
argc = 2
argv[0] = ./argv_dump
argv[1] = learner

$ ./argv_dump "hello board"
argc = 2
argv[0] = ./argv_dump
argv[1] = hello board

$ ./argv_dump hello board
argc = 3
argv[0] = ./argv_dump
argv[1] = hello
argv[2] = board
```

一组一组对着看：

1. 什么都不跟，`argc` 也是 1，不是 0。因为 `argv[0]` 永远是命令本身
   `./argv_dump`。所以"你跟了几个词"等于 `argc - 1`。
2. 跟一个词 `learner`，`argc` 变成 2，`argv[1]` 就是那个词。
3. `"hello board"` 带引号，中间虽然有空格，bash 还是把它当成**一个**词，
   `argc` 是 2。
4. 同样两个单词去掉引号，bash 按空格切成两个，`argc` 变成 3。

第 3、4 组对比说明：**切词是 bash 做的，程序拿到的是切完之后的结果。**
程序自己看不到你敲的原始那一行，也不知道你用没用引号。

现在回头读 `hello.c` 的判断就很自然了：

```c
    if (argc >= 2)
        printf("Hello, %s!\n", argv[1]);
    else
        printf("Hello, world!\n");
```

`argc >= 2` 的意思是"除了命令本身，至少还跟了一个词"。有，就用第一个跟着的词
`argv[1]` 填进 `%s`；没有，就打印 `Hello, world!`。1.1 节的两次运行正好走了
两个分支。

**这一节搭好的积木**：bash 把命令行切成词，交给程序的 `argc` 和 `argv`；
`argv[0]` 是命令本身。接下来的问题：`main` 最后那句 `return 0` 交回的 0，
又是交给了谁。

### 1.3 return 0 交给了谁：退出码

程序运行结束时，会交回一个整数给启动它的程序。这个整数叫**退出码**。
`main` 里 `return 0;` 的那个 0，就是 `hello_x86` 的退出码，交给了 bash。

bash 会把"刚才那条命令的退出码"存在一个特殊变量 `$?` 里，用 `echo $?`
就能看到。拿三条现成的命令试一下：

```bash
true;  echo "true:$?"
false; echo "false:$?"
ls /nonexist >/dev/null 2>&1; echo "ls:$?"
```

- `true` 和 `false` 是两个什么都不干的小程序，一个专门返回 0，一个专门返回 1。
- `;` 把两条命令写在一行，依次执行。
- `ls /nonexist` 去列一个不存在的目录，一定失败。后面的 `>/dev/null 2>&1`
  把它的输出和报错都扔掉，免得干扰；这里只关心退出码。
- `echo "true:$?"`：打印 `true:` 后面接上 `$?` 的值。`$?` 只保存**紧挨着的
  上一条**命令的退出码，所以每条命令后面要立刻 echo。

本机实测：

```text
true:0
false:1
ls:2
```

惯例是：**0 表示成功，非 0 表示失败**，不同的非 0 值由各个程序自己规定含义
（`ls` 用 2 表示"参数指的东西不存在"这类严重问题）。

`hello_x86` 的退出码：

```bash
./hello_x86 learner; echo "exit=$?"
```

```text
Hello, learner!
exit=0
```

退出码会是本章最重要的线索之一。第 3 节和第 5 节里，程序没跑起来时看不到
任何打印，但退出码会告诉我们它死在了哪一步：126、127、139、1，每个数字对应
一个不同的位置。

**这一节搭好的积木**：程序结束时交回一个整数（退出码），bash 存在 `$?` 里；
0 是成功。接下来回到源码第一行：`#include <stdio.h>` 是干什么的。

### 1.4 第一行的 #include：声明

`hello.c` 用到了 `printf`，但整个文件里并没有写 `printf` 是怎么实现的。
编译器在编译 `hello.c` 时，怎么知道 `printf` 该怎么调用？

答案在第一行：`#include <stdio.h>`。它的作用是把一个叫 `stdio.h` 的文件的
内容，原样插到这一行的位置。`stdio.h` 是一个**头文件**，里面写着 `printf`
等一批函数的**声明**。

要分清两个词：

- **声明**：只说明一个函数"长什么样"：叫什么名字、要几个参数、每个参数什么
  类型、返回什么类型。没有函数体。
- **定义**：给出函数体，也就是这个函数到底怎么做。

编译器编译一个 `.c` 文件时，只看这个文件本身（加上它 include 进来的内容）。
它遇到一次函数调用，需要知道"这个函数要几个什么参数"，才能检查你传得对不对、
才能决定参数怎么交过去。声明就是提供这个信息的。

用一个故意写错的程序看声明怎么起作用。`Knowledge/labs/01_hello/decl_demo.c`：

```c
/* 01 章 1.4 节：声明与定义的分工。
 * 编译：gcc -Wall decl_demo.c        （故意少传参数，看声明怎么抓错）
 */
#include <stdio.h>

int add(int a, int b);            /* 声明:只说形状 */

int main(void)
{
    printf("1+2=%d\n", add(1));   /* 故意只传一个参数 */
    return 0;
}

int add(int a, int b)             /* 定义:给实现 */
{
    return a + b;
}
```

逐行读：

- 第 6 行 `int add(int a, int b);`：声明。末尾是分号，没有函数体。它告诉
  编译器：有一个函数叫 `add`，要两个 `int` 参数，返回 `int`。
- 第 8 行 `int main(void)`：这次 `main` 不收参数，`void` 就是"没有参数"的写法。
- 第 10 行：调用 `add(1)`，只传了一个参数。这是故意的错。
- 第 14～17 行：`add` 的定义，函数体里把两个参数相加后返回。

编译：

```bash
gcc -Wall decl_demo.c
```

本机实测：

```text
decl_demo.c: In function 'main':
decl_demo.c:10:24: error: too few arguments to function 'add'; expected 2, have 1
   10 |     printf("1+2=%d\n", add(1));   /* 故意只传一个参数 */
      |                        ^~~
decl_demo.c:6:5: note: declared here
    6 | int add(int a, int b);            /* 声明:只说形状 */
      |     ^~~
```

读这段报错：

- `decl_demo.c:10:24: error:`：第 10 行第 24 列有一个错误。`error` 表示编译
  失败，不会产出文件。
- `too few arguments to function 'add'; expected 2, have 1`：参数太少，
  应该 2 个，给了 1 个。
- `note: declared here`：编译器还指出了它依据的是哪一行：第 6 行的声明。

也就是说，编译器是**拿声明去核对调用**的。那么把第 6 行的声明删掉会怎样？
编译器读到第 10 行时还没见过 `add`，手里没有任何依据。用 `grep -v` 生成一份
去掉声明的副本再编：

```bash
grep -v '^int add(int a, int b);' decl_demo.c > /tmp/decl_nodecl.c
gcc -Wall /tmp/decl_nodecl.c -o /tmp/decl2
```

- `grep -v '模式'`：输出所有**不**匹配模式的行，也就是把声明那一行去掉、其余原样
  输出。`^` 表示行首，保证只去掉以这串文字开头的那一行。
- `> /tmp/decl_nodecl.c`：把输出写进一个新文件。放在 `/tmp` 下，不弄乱实验目录。

本机实测：

```text
/tmp/decl_nodecl.c: In function 'main':
/tmp/decl_nodecl.c:9:24: error: implicit declaration of function 'add' [-Wimplicit-function-declaration]
```

（删掉一行之后，调用所在的行号从 10 变成了 9。）gcc 15 默认按 2023 年的 C 标准
编译，这个标准要求函数必须先声明再调用，所以直接报错。

C 语言早年的规则不是这样的：没声明的函数，编译器会自己猜一个形状继续编下去。
用 `-std=gnu89` 让 gcc 按 1989 年的老规则编，就能看到猜错的后果：

```bash
gcc -std=gnu89 -Wall /tmp/decl_nodecl.c -o /tmp/decl3
/tmp/decl3
/tmp/decl3
```

```text
/tmp/decl_nodecl.c:9:24: warning: implicit declaration of function 'add' [-Wimplicit-function-declaration]
1+2=431033113
1+2=187278313
```

只剩一个警告，文件编出来了，运行结果却是毫无意义的数，而且每次运行都不一样。原因是调用方
只放了一个参数，`add` 却按两个参数去取，第二个参数取到的是一块没人写过的
位置里残留的内容，那里每次运行时恰好是什么就是什么。编译器没有声明可依据，就没法发现这个错误。

这就是"调用别人的函数之前，先 include 它的头文件"的全部理由：**头文件里的声明
让编译器能检查每一次调用。**

**这一节搭好的积木**：`.h` 里放声明（函数的形状），`.c` 里放定义（函数的实现）；
`#include` 把头文件内容插进来，编译器据此核对调用。接下来的问题：`stdio.h` 只有
`printf` 的声明，`printf` 的定义在哪里？

### 1.5 printf 的实现在哪里：库

`printf` 的定义不在 `hello.c` 里，也不在 `stdio.h` 里。它在一个**库**里。

库是一个文件，里面装着已经编译好的函数实现，供很多程序共用。C 语言最基础的
那批函数（`printf`、`strlen`、`malloc`、`open`……）都装在**C 库**里。Linux 上
最常用的 C 库叫 **glibc**（GNU C Library）。

于是 `hello_x86` 这个程序在运行时由三部分配合：

- 你写的那部分：`main` 函数，在 `hello_x86` 文件里。
- C 库：`printf` 的实现。
- 内核：`printf` 把字排好之后，真正把字送到屏幕上的动作，C 库自己做不了，
  要请操作系统内核来做。

最后这一点需要多说两句。程序不能直接操作硬件（屏幕、磁盘、串口），这是 CPU
在硬件上强制的：普通程序运行在"用户态"，只有内核运行在"内核态"，只有内核态
才能碰硬件。程序想做这类事，要通过一种特殊的调用请内核代劳，这种调用叫
**系统调用**。`printf` 自己只负责把 `"Hello, %s!\n"` 和 `learner` 拼成一串字，
拼好之后调用 `write` 这个系统调用，由内核把这串字送出去。

![图 1　app、库、内核三层，以及用户/内核边界](fig/01-app-库-内核三层.svg)

图里的红线就是用户态和内核态的边界。`printf` 在线的上方；它最终调用的
`write` 穿过红线进入内核。

头文件和库都是真实存在的文件，可以直接找到。先问 gcc 它去哪些目录找头文件。
这里有个办法，不用写 `.c` 文件也能问：

```bash
echo 'int main(){}' | gcc -E -v - 2>&1 | sed -n '/search starts here/,/End of search/p'
```

这条命令由三段用 `|`（管道）连起来，前一段的输出成为后一段的输入：

- `echo 'int main(){}'`：输出一个最小的 C 程序。
- `gcc -E -v -`：`-` 表示"源码从输入里读，不从文件读"；`-E` 表示只做预处理
  （就是展开 `#include` 这一类工作），不往下编；`-v` 让 gcc 把它内部的动作和
  搜索路径都打印出来。这些信息打印在"标准错误"上，`2>&1` 把它并到普通输出里，
  才能交给下一段。
- `sed -n '/起/,/止/p'`：只打印从匹配"起"的那一行到匹配"止"的那一行之间的内容。

本机实测：

```text
#include "..." search starts here:
#include <...> search starts here:
 /usr/lib/gcc/x86_64-linux-gnu/15/include
 /usr/local/include
 /usr/include/x86_64-linux-gnu
 /usr/include
End of search list.
```

`#include <stdio.h>` 用尖括号，就在这几个目录里依次找。用引号写成
`#include "xxx.h"` 时，先在源文件所在的目录找，找不到再按这个列表找。都不在
时，可以在编译时用 `-I 目录` 自己加一个目录（02 篇细讲）。

库也可以问。gcc 有一个选项专门回答"如果要链接某个库，你会用哪个文件"：

```bash
gcc -print-file-name=libc.so
```

库的细节留到 02 篇。这里只要记住：**编译一个程序，要用到头文件（声明）和库
（实现）这两样东西，它们都是编译器所在系统里的真实文件。** 这句话在第 2 节
会变得很要紧。

**这一节搭好的积木**：程序运行时由三层配合：自己的代码、C 库、内核；C 库通过
系统调用请内核做事。编译时用到的头文件和库，都是电脑上的真实文件。

到这里，`hello.c` 的每一行都讲完了，它在电脑上也跑通了。下一步把它放到板子上。

---

## 2 程序换一台机器还能跑吗

### 2.1 两台机器的 CPU 不一样

最直接的想法：`hello_x86` 已经编好了，把这个文件拷到板子上运行就行。

在拷之前，先看两台机器各自是什么 CPU。`uname -m` 打印当前机器的硬件架构名：

```bash
uname -m
```

电脑上（本机实测）：

```text
x86_64
```

板子上（2026-09-14 实测，第 4.4 节会讲怎么在板子上执行命令）：

```text
armv7l
```

两个名字不一样：

- `x86_64`：Intel 和 AMD 的 64 位 CPU 架构，绝大多数电脑用的都是它。
- `armv7l`：ARM 公司的第 7 代架构，`l` 表示小端（下文 3.3 节解释）。板子上的
  i.MX6ULL 芯片里是一颗 ARM Cortex-A7 核心，属于这一代。

架构名不同，意味着什么？要回答这个问题，得先弄清楚 CPU 真正执行的是什么。

### 2.2 机器码：CPU 真正执行的东西

CPU 不认识 C 语言。CPU 只会做一件事：从内存里一条一条取出**指令**来执行。
每条指令是一串固定格式的字节，表示一个很小的动作：比较两个数、把一个数搬到
另一个位置、跳到另一处继续执行。这样一串串的字节叫**机器码**。

哪串字节表示哪个动作，是 CPU 的设计者规定的，这套规定叫**指令集**。x86_64 有
一套指令集，ARM 有另一套，两套之间没有任何关系：同样是"比较两个数"，在两边是
完全不同的字节；x86 CPU 拿到一串 ARM 的字节，会按 x86 的规定去理解，得到的是
毫无意义（甚至危险）的动作。

所以 2.1 节的问题有了答案的方向：**`hello_x86` 文件里装的是 x86 机器码，板子上
那颗 ARM CPU 读不懂。**编译器干的事，就是把 C 源码翻译成某一套指令集的机器码。
电脑上那个 `gcc` 翻译成的是哪一套？问它自己：

```bash
gcc -v 2>&1 | grep '^Target:'
```

- `gcc -v`：打印 gcc 的配置信息。
- `grep '^Target:'`：只留下以 `Target:` 开头的那一行。`^` 表示"行首"。

```text
Target: x86_64-linux-gnu
```

`Target` 就是"产物给谁用"。电脑上的 gcc 只为 x86_64 生成机器码。要给板子
生成机器码，需要另一个编译器。

**这一节搭好的积木**：CPU 执行的是机器码，不同架构的机器码互不相通；一个编译器
只为一种目标架构生成机器码。接下来的问题：给 ARM 生成机器码的编译器在哪里。

### 2.3 给 ARM 生成机器码：交叉编译器

编译器自己是一个程序，它运行在某台机器上；它生成的机器码给另一台机器用。这两台
可以是同一种架构，也可以不是：

- 电脑上的 `gcc`：自己跑在 x86_64 上，产物也给 x86_64。这叫本地编译。
- 我们要的：自己跑在 x86_64 上（因为我们在电脑上写代码），产物给 ARM。
  这叫**交叉编译**，这种编译器叫**交叉编译器**。

为什么不直接在板子上编译？可以，但板子的 CPU 慢、内存小（512 MB），编大一点的
程序要等很久，而且板子上也没装编译器。在快的机器上为慢的机器编译，是嵌入式开发
的常规做法。

本仓的电脑上已经装好了交叉编译器，名字叫 `arm-linux-gnueabihf-gcc`。它和 `gcc`
用法完全一样，只是名字前面多了一段。问它的 `Target`：

```bash
arm-linux-gnueabihf-gcc -v 2>&1 | grep '^Target:'
```

```text
Target: arm-linux-gnueabihf
```

再从它的配置里挑出几项和"自己在哪跑、给谁编"有关的：

```bash
arm-linux-gnueabihf-gcc -v 2>&1 | tr ' ' '\n' | grep -E -- '--(build|host|target)='
```

- `tr ' ' '\n'`：把空格换成换行，让一长串配置项每项占一行。
- `grep -E -- '--(build|host|target)='`：`-E` 允许用 `(a|b)` 这种"或"的写法；
  `--` 告诉 grep 后面的东西不是它自己的选项（因为要找的内容本身以 `--` 开头）。

本机实测：

```text
--build=x86_64-linux-gnu
--host=x86_64-linux-gnu
--target=arm-linux-gnueabihf
```

`host` 是编译器自己运行的机器，`target` 是产物要去的机器。host 是 x86_64，
target 是 ARM，两者不同，这就是"交叉"两个字的准确含义。（`build` 是当初编译
这个编译器本身的机器，这里不用管。）

用它编译同一份 `hello.c`：

```bash
arm-linux-gnueabihf-gcc -O2 -Wall -Wextra hello.c -o hello_arm_dynamic
```

命令和 1.1 节一模一样，只把 `gcc` 换成了 `arm-linux-gnueabihf-gcc`。产物叫
`hello_arm_dynamic`，名字里的 dynamic（动态）第 3.5 节解释。

### 2.4 两份机器码摆在一起看

现在有两个产物，`file` 命令可以识别一个文件是什么：

```bash
file hello_x86 hello_arm_dynamic
```

本机实测（每行较长，截去了与本节无关的末尾部分）：

```text
hello_x86:         ELF 64-bit LSB pie executable, x86-64, version 1 (SYSV), dynamically linked, interpreter /lib64/ld-linux-x86-64.so.2, ...
hello_arm_dynamic: ELF 32-bit LSB pie executable, ARM, EABI5 version 1 (SYSV), dynamically linked, interpreter /lib/ld-linux-armhf.so.3, ...
```

逐段对照：

| 字段 | hello_x86 | hello_arm_dynamic | 含义 |
|---|---|---|---|
| `ELF` | 是 | 是 | 文件格式，Linux 上可执行文件的统一格式，第 3.3 节讲 |
| 位宽 | 64-bit | 32-bit | x86_64 是 64 位架构；Cortex-A7 是 32 位 |
| `LSB` | 是 | 是 | 小端字节序，第 3.3 节讲 |
| 架构 | x86-64 | ARM | 里面装的是哪套指令集的机器码 |
| `interpreter` | `/lib64/ld-linux-x86-64.so.2` | `/lib/ld-linux-armhf.so.3` | 第 3.5 节讲 |

两个文件都是 ELF 格式，但架构一栏不同。再直接看机器码本身。`objdump -d` 能把
机器码翻译回人能读的指令（这叫反汇编），`--disassemble=main` 只看 `main` 函数：

```bash
objdump -d --disassemble=main hello_x86
arm-linux-gnueabihf-objdump -d --disassemble=main hello_arm_dynamic
```

ARM 的文件要用 ARM 版的 `objdump` 来看，道理和编译器一样：电脑上的 `objdump`
只认识 x86 指令。

本机实测，x86 版的 `main`：

```text
0000000000001080 <main>:
    1080:	f3 0f 1e fa          	endbr64
    1084:	48 83 ec 08          	sub    $0x8,%rsp
    1088:	83 ff 01             	cmp    $0x1,%edi
    108b:	7e 1e                	jle    10ab <main+0x2b>
    108d:	48 8b 56 08          	mov    0x8(%rsi),%rdx
    1091:	bf 02 00 00 00       	mov    $0x2,%edi
    1096:	31 c0                	xor    %eax,%eax
    1098:	48 8d 35 65 0f 00 00 	lea    0xf65(%rip),%rsi
    109f:	e8 cc ff ff ff       	call   1070 <__printf_chk@plt>
    10a4:	31 c0                	xor    %eax,%eax
    10a6:	48 83 c4 08          	add    $0x8,%rsp
    10aa:	c3                   	ret
    10ab:	48 8d 3d 5e 0f 00 00 	lea    0xf5e(%rip),%rdi
    10b2:	e8 a9 ff ff ff       	call   1060 <puts@plt>
    10b7:	eb eb                	jmp    10a4 <main+0x24>
```

ARM 版的 `main`：

```text
00000438 <main>:
 438:	2801      	cmp	r0, #1
 43a:	b508      	push	{r3, lr}
 43c:	dd07      	ble.n	44e <main+0x16>
 43e:	684a      	ldr	r2, [r1, #4]
 440:	2002      	movs	r0, #2
 442:	4905      	ldr	r1, [pc, #20]
 444:	4479      	add	r1, pc
 446:	f7ff efec 	blx	420 <__printf_chk@plt>
 44a:	2000      	movs	r0, #0
 44c:	bd08      	pop	{r3, pc}
 44e:	4803      	ldr	r0, [pc, #12]
 450:	4478      	add	r0, pc
 452:	f7ff efda 	blx	408 <puts@plt>
 456:	e7f8      	b.n	44a <main+0x12>
```

每一行从左到右是三列：这条指令在文件里的位置、指令的机器码字节、反汇编出来的
指令文字。不需要读懂每条指令，只看三件事：

1. **做的是同一件事。** 两边都有一条"比较"（x86 的 `cmp $0x1,%edi`，ARM 的
   `cmp r0, #1`），都是在拿 `argc` 和 1 比，对应源码里的 `if (argc >= 2)`；
   比完都有一条"小于等于就跳走"（`jle` / `ble.n`）；后面都有两处调用（`call` /
   `blx`），分别调 `__printf_chk` 和 `puts`，对应两个 `printf`。
2. **字节完全不同。** 同样是那条比较，x86 是 `83 ff 01` 三个字节，ARM 是
   `28 01` 两个字节。没有任何对应关系。
3. **连"参数放在哪"都不同。** x86 版从 `%edi` 里拿 `argc`，ARM 版从 `r0` 里拿。
   `%edi`、`r0` 都是 CPU 内部的寄存器（CPU 里几个最快的存储格子）。"第一个参数放
   在哪个寄存器"是各个架构自己的约定，这一点 2.6 节还会用到。

（编译器把 `printf("Hello, world!\n")` 换成了等价的 `puts`，把另一个换成了带检查
的 `__printf_chk`，这是 `-O2` 优化的结果，不影响行为。）

**这一节搭好的积木**：同一份 C 源码，两个编译器产出两份 ELF 文件；文件格式相同，
里面的机器码完全不同，参数存放的位置也不同。接下来的问题：交叉编译器那个长名字
里的每一段，分别规定了什么。

### 2.5 编译器名字里的四段

`arm-linux-gnueabihf-gcc` 这个名字前面那串 `arm-linux-gnueabihf`
叫**目标三元组**（target triplet，历史上是三段，现在常见四段），完整描述了
"产物给谁用"。拆开：

| 片段 | 表示什么 | 规定了产物的哪一方面 |
|---|---|---|
| `arm` | 目标 CPU 架构 | 生成 ARM 指令集的机器码 |
| `linux` | 目标操作系统 | 产物运行在 Linux 上，用 Linux 的系统调用 |
| `gnueabi` | C 库与二进制约定 | `gnu` 表示配套的 C 库是 glibc；`eabi` 是 ARM 规定的一套二进制约定，管参数怎么放、结构体怎么排 |
| `hf` | hard-float，浮点参数的放法 | 下一节专门讲 |
| `gcc` | 工具名 | 这是编译器；同一套里还有 `arm-linux-gnueabihf-objdump`、`-ld` 等 |

为什么"给谁用"要说这么多项？因为一个程序能在目标机器上跑起来，至少要同时满足
三件事：

1. **指令集对**：CPU 能执行里面的机器码（2.2 节）。
2. **二进制约定对**：自己的代码和库里的代码互相调用时，对"参数放哪、返回值放哪"
   的理解一致（2.4 节第 3 点看到过，不同架构约定不同；同一架构也可能有不止一种
   约定，比如下一节的 hf）。
3. **配套的库对**：用到的 C 库在目标机器上存在，而且版本合得上（第 5.2 节会在
   这里摔一跤）。

三元组的每一段，就是在给这三件事定答案。

### 2.6 hf：浮点参数放在哪里

`hf` 这一段单独说，因为它最容易被当成"可有可无的性能选项"，实际上是硬约束。

先看问题：函数调用时，参数要放到双方都知道的位置，被调用的函数才能取到。整数
参数在 ARM 上放在 `r0`、`r1`、`r2`、`r3` 这几个通用寄存器里（2.4 节看到 `argc`
就在 `r0`）。浮点数（带小数点的数，C 里的 `float`、`double`）呢？Cortex-A7 里
有一组专门做浮点运算的寄存器（VFP 寄存器，名叫 `s0`、`s1`……），于是出现了两种
做法：

| 函数 `float f(float a, float b)` | hard-float（hf） | soft-float |
|---|---|---|
| 参数 `a` 放在 | `s0`（浮点寄存器） | `r0`（通用寄存器） |
| 参数 `b` 放在 | `s1` | `r1` |
| 返回值放在 | `s0` | `r0` |

两种做法各自都能工作。问题出在混用：调用方按 hard-float 把参数放进 `s0`、`s1`，
被调用方按 soft-float 去 `r0`、`r1` 取，取到的是不相干的内容。结果不是"慢一点"，
而是"算错"。所以链接器（把多个编译结果拼成一个程序的工具，02 篇讲）发现两种
约定的代码要拼在一起时，会直接拒绝：

```text
xxx.o uses VFP register arguments, yyy.o does not
```

一块板子上，系统自带的库是按哪种约定编的，你的程序就必须按哪种约定编。
板子的系统库是 hard-float 的，所以用 `gnueabihf` 这一套。三种浮点约定编出来的
汇编对照，见 [fundamentals/02 ARM寄存器与调用约定](../../fundamentals/02_ARM寄存器与调用约定.md)。

### 2.7 头文件和库也得是 ARM 的：sysroot

回到 1.5 节结尾那句话：编译时要用到头文件和库，它们是编译器所在系统里的真实
文件。电脑上的那些库，是给 x86 程序用的，里面是 x86 机器码。交叉编译 ARM 程序
时，把这样的 x86 C 库拼进 ARM 程序，得到的是两种机器码混在一起、哪种 CPU 都跑不了
的东西，所以不能用它们。

所以交叉编译器必须另带一套**给 ARM 用的头文件和库**，并且编译时只去那里找。
这一套文件所在的位置，叫 **sysroot**：可以理解为"目标机器的根目录在电脑上的
一份替身"，编译器把它当作目标机器的 `/` 来查找 `/usr/include`、`/usr/lib`。

验证一下。问交叉编译器去哪里找头文件，和 1.5 节对照：

```bash
echo 'int main(){}' | arm-linux-gnueabihf-gcc -E -v - 2>&1 | sed -n '/search starts here/,/End of search/p'
```

```text
#include "..." search starts here:
#include <...> search starts here:
 /usr/lib/gcc-cross/arm-linux-gnueabihf/15/include
 /usr/lib/gcc-cross/arm-linux-gnueabihf/15/../../../../arm-linux-gnueabihf/include
 /usr/include
End of search list.
```

前两条带着 `gcc-cross` 和 `arm-linux-gnueabihf`，是 ARM 专属的目录；第二条
`../../../..` 往上回退四层后，实际指向 `/usr/arm-linux-gnueabihf/include`。
对比 1.5 节本地 gcc 的列表，那里是 `x86_64-linux-gnu` 的目录。

找一下 `stdio.h`：

```bash
find /usr/arm-linux-gnueabihf -name stdio.h
```

```text
/usr/arm-linux-gnueabihf/include/stdio.h
/usr/arm-linux-gnueabihf/include/bits/stdio.h
```

再看 ARM 的 C 库，用 `file` 确认它里面真的是 ARM 机器码：

```bash
file -L /usr/arm-linux-gnueabihf/lib/libc.so.6
```

- `-L`：如果这个名字是一个链接（指向另一个文件的快捷方式），就去看它指向的真身。

```text
/usr/arm-linux-gnueabihf/lib/libc.so.6: ELF 32-bit LSB shared object, ARM, EABI5 version 1 (GNU/Linux), dynamically linked, ...
```

`ARM`、`32-bit`，和 `hello_arm_dynamic` 一样。**给板子用的 C 库，在电脑上就有
一份。**

问它的 sysroot 在哪：

```bash
arm-linux-gnueabihf-gcc -print-sysroot
```

```text
/
```

回答是 `/`，看起来和"替身根目录"对不上。原因是这套交叉编译器是用 Ubuntu 的
软件包装的，Ubuntu 的做法是不另立一个根目录，而是把 ARM 的文件放进系统里带
`arm-linux-gnueabihf` 前缀的目录（`/usr/arm-linux-gnueabihf/include`、
`/usr/arm-linux-gnueabihf/lib`），靠目录名区分架构。另一种常见做法是芯片或板卡
厂商提供的工具链，那种会有一个真正独立的 sysroot 目录，`-print-sysroot` 会打印
出一个实际路径。第 2 阶段写驱动时会用到那种。

**第 2 节搭好的积木**：板子的 CPU 是 ARM，要用交叉编译器生成 ARM 机器码；
交叉编译器的名字（三元组）说清了指令集、二进制约定和 C 库；它自带一套 ARM 的
头文件和库。现在手里有了一个 ARM 版的 `hello_arm_dynamic`。

### 2.8 [做 L1] 让工具链自报家门

把第 2 节的观察集中做一遍：

```bash
# 1) 两个编译器各自给谁编
gcc -v 2>&1 | grep '^Target:'
arm-linux-gnueabihf-gcc -v 2>&1 | grep '^Target:'

# 2) 交叉编译器的 host 和 target
arm-linux-gnueabihf-gcc -v 2>&1 | tr ' ' '\n' | grep -E -- '--(build|host|target)='

# 3) 浮点约定与默认架构
arm-linux-gnueabihf-gcc -v 2>&1 | tr ' ' '\n' | grep -E -- '--with-(arch|float)='

# 4) 两个产物的架构
file hello_x86 hello_arm_dynamic

# 5) ARM 的 C 库在电脑上
file -L /usr/arm-linux-gnueabihf/lib/libc.so.6
```

第 3 条的本机实测：

```text
--with-arch=armv7-a+fp
--with-float=hard
```

`armv7-a` 是 Cortex-A7 所属的架构版本，`+fp` 表示带浮点单元；`--with-float=hard`
就是 2.6 节的 hard-float，和名字里的 `hf` 对得上。

**[判]**

    [ ] 第 1 条两行 Target 不同:一个 x86_64-linux-gnu,一个 arm-linux-gnueabihf
    [ ] 第 2 条 host 与 target 不同,说得出这就是"交叉"
    [ ] 第 3 条 --with-float=hard,说得出它和名字里哪一段对应
    [ ] 第 4 条 file 的架构一栏分别是 x86-64 和 ARM,位宽 64 和 32
    [ ] 第 5 条 libc.so.6 是 ARM 的

    注错见红:把第 2、3 条里的 arm-linux-gnueabihf-gcc 换成 gcc 再跑,
    target 必须变成 x86_64-linux-gnu,--with-float 那一行必须消失。

---

## 3 ARM 程序在电脑上运行，被谁拦下了

### 3.1 现象：Exec format error，退出码 126

2.3 节编出了 `hello_arm_dynamic`。在把它送上板子之前，先做一件看似多余的事：
在电脑上运行它。

```bash
./hello_arm_dynamic learner; echo "exit=$?"
```

本机实测：

```text
bash: ./hello_arm_dynamic: cannot execute binary file: Exec format error
exit=126
```

预料之中，电脑的 x86 CPU 跑不了 ARM 机器码。但这个报错的措辞值得细看：它没有说
"指令错误"或"程序崩溃"，说的是 **cannot execute binary file: Exec format error**，
"不能执行这个二进制文件：执行格式错误"。退出码 126 是 bash 的约定，意思是
"找到了这个文件，但它不能被执行"。

这说明程序根本没有开始运行，CPU 一条 ARM 指令都没碰到，在那之前就被拒绝了。
是谁拒绝的？

### 3.2 拒绝发生在内核里：用 strace 看 execve

先弄清楚"运行一个程序"这件事到底是谁在做。

bash 自己不会把一个文件变成一个运行中的程序。把一个文件装进内存、准备好 CPU、
让它从第一条指令开始执行，这些都要动用硬件，按 1.5 节的道理，只有内核能做。
所以 bash 是通过系统调用请内核来做的，这个系统调用叫 **execve**：
"execute"（执行）加上两个字母后缀，`v` 表示参数以数组（vector）形式给出，`e` 表示
同时给出环境变量（environment）。bash 把文件名、`argv`、环境变量
交给 `execve`，由内核把这个文件变成运行中的程序。

`strace` 是一个能把程序发出的系统调用逐个打印出来的工具。让它盯着这次运行，
只看 `execve`：

```bash
strace -e trace=execve ./hello_arm_dynamic learner
```

- `strace 命令...`：运行后面的命令，同时打印它发出的系统调用。
- `-e trace=execve`：只打印 `execve` 这一种，其他的不看。

本机实测：

```text
execve("./hello_arm_dynamic", ["./hello_arm_dynamic", "learner"], 0x7ffd7e1cbd08 /* 22 vars */) = -1 ENOEXEC (Exec format error)
strace: exec: Exec format error
+++ exited with 1 +++
```

读第一行：

- `execve("./hello_arm_dynamic", ...)`：请求内核执行这个文件。
- `["./hello_arm_dynamic", "learner"]`：交过去的 `argv`，就是 1.2 节那两项。
- `/* 22 vars */`：交过去的 22 个环境变量，这里不展开。
- `= -1 ENOEXEC (Exec format error)`：内核的回答。`-1` 表示失败；`ENOEXEC` 是
  失败原因的代号（"no exec"，不是可执行格式），括号里是它的文字说明。

bash 那句 `Exec format error`，就是把内核返回的 `ENOEXEC` 翻译成了文字。
**拒绝是内核在 execve 里做出的。**（strace 自己也是用 execve 启动目标程序的，
被拒绝后它以退出码 1 结束，所以最后一行是 `exited with 1`，这是 strace 的退出码，
不是 bash 的 126。）

下一个问题：内核还没执行任何指令，凭什么知道这个文件"格式不对"？

### 3.3 内核看的是文件开头的几个字节

2.4 节 `file` 说两个产物都是 **ELF** 文件。ELF（Executable and Linkable Format）
是 Linux 上可执行文件的统一格式。它规定文件的最开头必须是一个固定结构的**文件头**，
里面用几个字节写明这个文件的基本属性。内核要执行一个文件，首先读的就是这个头。

`xxd` 能把文件内容按字节以十六进制显示出来。看两个产物的前 20 个字节：

```bash
xxd -l 20 hello_arm_dynamic
xxd -l 20 hello_x86
```

- `-l 20`：只显示前 20 个字节。

本机实测：

```text
00000000: 7f45 4c46 0101 0100 0000 0000 0000 0000  .ELF............
00000010: 0300 2800                                ..(.
```

```text
00000000: 7f45 4c46 0201 0100 0000 0000 0000 0000  .ELF............
00000010: 0300 3e00                                ..>.
```

怎么读这种输出：每行最左边是这一行第一个字节在文件里的位置（十六进制，
`00000010` 就是第 16 个字节，从 0 数）；中间是字节内容，每两个十六进制数字是
一个字节，四个数字一组只是为了好看；最右边是把这些字节当作字符显示，不能显示的
用 `.` 代替。

对照 ELF 的规定逐个拆开（位置从 0 数）：

    位置   ARM 版   x86 版   含义
    ----   ------   ------   -------------------------------------------------
    0~3    7f 45 4c 46       魔数。0x7f 后接 'E' 'L' 'F' 三个字母。
                             所有 ELF 文件都以这 4 个字节开头,内核靠它认出
                             "这是一个 ELF 文件"
    4      01       02       位宽。01 = 32 位,02 = 64 位
    5      01       01       字节序。01 = 小端
    16~17  03 00    03 00    文件类型(e_type)。3.7 节讲
    18~19  28 00    3e 00    目标架构(e_machine)。  <== 关键在这里

第 4 个字节和 2.4 节 `file` 说的 32-bit / 64-bit 对上了。最关键的是第 18、19 两个
字节，叫 **e_machine**，写的是"这个文件里的机器码是给哪种 CPU 的"。

这里要先讲清楚"小端"，否则 `28 00` 读不对。一个数如果要用两个字节存，就有一个
先后问题：数值 0x0028 拆成高位字节 `00` 和低位字节 `28`，存的时候先放哪个？
**小端**的规定是低位字节放在前面（位置小的地方），所以文件里看到的是 `28 00`，
它表示的数是 0x0028，也就是十进制 40。x86 和这块板子上的 ARM 都用小端。

于是：

- ARM 版：`28 00` 表示 0x0028 = 40。ELF 规定 40 号代表 ARM（名叫 `EM_ARM`）。
- x86 版：`3e 00` 表示 0x003e = 62。62 号代表 x86-64（名叫 `EM_X86_64`）。

这些编号人工去对很麻烦，`readelf -h` 会把文件头翻译成文字：

```bash
readelf -h hello_arm_dynamic | grep -E 'Class|Data|Machine|Type:'
readelf -h hello_x86 | grep -E 'Class|Machine|Type:'
```

- `readelf -h`：显示 ELF 文件头（header）。

```text
  Class:                             ELF32
  Data:                              2's complement, little endian
  Type:                              DYN (Position-Independent Executable file)
  Machine:                           ARM
```

```text
  Class:                             ELF64
  Type:                              DYN (Position-Independent Executable file)
  Machine:                           Advanced Micro Devices X86-64
```

`Class` 对应第 4 个字节，`Data` 对应第 5 个字节，`Machine` 对应第 18、19 个字节。
`xxd` 看到的原始字节、`readelf` 翻译的文字、2.4 节 `file` 的判断，三方一致。

现在可以回答 3.2 节结尾的问题了：**内核读文件头，看到 e_machine 是 40（ARM），
而这台电脑是 62（x86-64），两者不符，于是拒绝。**

### 3.4 内核的检查顺序

上一节说"内核读文件头，发现 e_machine 不符就拒绝"。这件事在内核里是按一个固定
顺序做的。了解这个顺序，3.5 节的实验才看得懂。

Linux 能执行的文件不止 ELF 一种，比如以 `#!/bin/bash` 开头的脚本也能直接运行。
内核的做法是：维护一张"格式处理器"的列表，每种格式一个处理器；执行一个文件时，
先把文件开头的一小段读进来（较新的内核读 256 字节，板子上的 4.9 内核读 128 字节，
文件头都在里面），然后**按列表顺序依次问每个处理器"这个文件归你管吗"**，谁认领了
就交给谁，都不认领就返回 `ENOEXEC`。

列表的顺序由各处理器向内核登记的方式决定：自定义规则处理器 binfmt_misc 登记时
插在列表最前面，脚本处理器和 ELF 处理器按登记先后排在后面。对 `hello_arm_dynamic`
来说，依次是：

| 顺序 | 处理器 | 它检查什么 | 对本文件的结论 |
|---|---|---|---|
| 1 | 自定义规则处理器（binfmt_misc） | 文件开头是否匹配某条登记过的规则 | 没有匹配的规则，不认领 |
| 2 | 脚本处理器（binfmt_script） | 开头两个字节是不是 `#!` | 不是，不认领 |
| 3 | ELF 处理器（binfmt_elf） | 开头四个字节是不是 `7f 45 4c 46` | 是，进入 ELF 的加载流程 |
| 3a | ELF 处理器内部的架构检查 | e_machine 是不是本机的架构 | 40 不等于 62，放弃，返回"不归我管" |
| 结果 | | | 没有任何处理器认领，execve 返回 `ENOEXEC` |

表里的名字是这些处理器在 Linux 内核源码里的真实名字（`fs/binfmt_misc.c`、
`fs/binfmt_script.c`、`fs/binfmt_elf.c`）；binfmt_misc 插到最前面，是因为它在
`fs/binfmt_misc.c` 里用 `insert_binfmt` 登记，其余两个用 `register_binfmt` 追加
在末尾。第 3a 步的检查在 ELF 处理器的加载函数里，是一个叫 `elf_check_arch` 的判断。

**拦下它的是内核里一段普通的判断代码，不是 CPU。** CPU 一条 ARM 指令都没有见到。

反过来想，同样的事情在板子上也会发生：板子上也是 Linux，也有同样一段判断，只不过
在那里"本机架构"是 ARM。把 x86 的 `hello_x86` 拿到板子上运行，会被同一段代码以
同样的理由拒绝，报同一句 `Exec format error`。第 5.1 节会亲眼看到。

### 3.5 骗过第一关会怎样：注错两连

如果上一节的说法是对的，那么把 ARM 文件的 e_machine 字节改成 62，假装它是 x86
的，内核就会放它过架构检查，往下走。往下走到哪里？这能验证 3.4 节的流程。

**这个实验要做两次：一次用 `hello_arm_dynamic`，一次用"静态"版本。**两个版本的
差别正好决定了"往下走"之后会发生什么，所以先把这个差别讲清楚。

**动态链接和静态链接。** 1.5 节说 `printf` 的实现在 C 库里。程序要用到库里的函数，
有两种办法：

- **动态链接**：程序文件里不放 `printf` 的实现，只记一笔"我需要 libc.so.6 这个库"。
  等程序运行时，再由一个专门的程序把 C 库装进内存、把 `printf` 的位置填好。
  这个专门的程序叫**动态链接器**（也叫动态加载器）。2.3 节默认编出来的就是这种，
  所以叫 `hello_arm_dynamic`。
- **静态链接**：编译时就把用到的库函数实现整个拷进程序文件里。运行时不需要任何
  外部的库，也不需要动态链接器。加 `-static` 选项编出来的就是这种。

动态链接的程序要在 ELF 里写明"运行时请找哪个动态链接器"。这一项叫 `.interp`
（interpreter 的缩写，意思是"解释器"），就是 2.4 节 `file` 输出里
`interpreter /lib/ld-linux-armhf.so.3` 那一段。`readelf -l` 可以看到它：

```bash
readelf -l hello_arm_dynamic | grep -A1 INTERP
```

- `readelf -l`：显示 ELF 的"程序头"，也就是内核加载时要看的那几项。
- `grep -A1 INTERP`：找到含 `INTERP` 的行，连同它后面 1 行一起显示。

```text
  INTERP         0x000198 0x00000198 0x00000198 0x00019 0x00019 R   0x1
      [Requesting program interpreter: /lib/ld-linux-armhf.so.3]
```

ELF 处理器通过架构检查之后的下一步，就是读这一项、去打开这个动态链接器。

现在编出静态版：

```bash
arm-linux-gnueabihf-gcc -static -O2 -Wall -Wextra hello.c -o hello_arm_static
readelf -l hello_arm_static | grep -c INTERP
```

- `-static`：静态链接。
- `grep -c`：只输出匹配的行数。

```text
0
```

静态版里没有 `INTERP` 这一项。

有了这个准备，开始注错。改一个字节用 `dd`：

```bash
# 第一次:动态版
cp hello_arm_dynamic hello_fake
printf '>' | dd of=hello_fake bs=1 seek=18 conv=notrunc 2>/dev/null
xxd -s 16 -l 4 hello_fake
./hello_fake; echo "exit=$?"

# 第二次:静态版
cp hello_arm_static hello_sta_fake
printf '>' | dd of=hello_sta_fake bs=1 seek=18 conv=notrunc 2>/dev/null
./hello_sta_fake; echo "exit=$?"
```

改字节那一行逐段说清：

- `printf '>'`：输出一个字符 `>`。它在 ASCII 编码里是 0x3e，正好是 62 的低位字节。
- `dd of=hello_fake`：`dd` 是按字节读写的工具，`of=` 是要写入的文件。它从前面
  管道读入那一个字节。
- `bs=1`：每次读写 1 个字节。
- `seek=18`：写之前在输出文件里先跳过 18 个字节，于是写在位置 18（从 0 数），
  也就是 e_machine 的低位字节。
- `conv=notrunc`：只覆盖这一个字节，不要把文件后面的内容截掉。不加这个，dd 写完
  会把文件截断在写入的位置。
- `2>/dev/null`：扔掉 dd 打印的统计信息。
- `xxd -s 16 -l 4`：从位置 16 开始看 4 个字节，确认改对了。

本机实测：

```text
00000010: 0300 3e00                                ..>.
bash: ./hello_fake: cannot execute: required file not found
exit=127
```

```text
Segmentation fault
exit=139
```

先看动态版。`28 00` 已经变成 `3e 00`，内核这次放它过了架构检查。报错变了：
`required file not found`，"需要的文件找不到"，退出码 127。文件 `hello_fake`
明明就在眼前，找不到的是哪个文件？是 `.interp` 里写的
`/lib/ld-linux-armhf.so.3`。电脑上没有 ARM 的动态链接器放在那个位置，内核去
打开它，失败了。这正是 ELF 处理器通过架构检查（3.4 节表里第 3a 步）之后的下一步。

再看静态版。它没有 `.interp`，内核过了架构检查之后没有别的东西要找，直接把文件
装进内存，让 CPU 从程序的入口开始执行。CPU 是 x86 的，读到的是 ARM 机器码，按
x86 的规定去理解这些字节，执行了几条毫无意义的指令之后，访问了一个不允许访问的
内存地址，内核发出一个信号把它终止，这就是 `Segmentation fault`（段错误）。
退出码 139 的来历：程序被信号终止时，bash 用 128 加上信号编号作为退出码；
段错误的信号叫 `SIGSEGV`，编号 11，128 + 11 = 139。

把三个退出码排在一起，它们正好对应流程上三个不同的位置：

| 退出码 | 现象 | 死在哪一步 |
|---|---|---|
| 126 | Exec format error | 架构检查不通过，内核拒绝执行 |
| 127 | required file not found | 过了架构检查，找不到 `.interp` 指定的动态链接器 |
| 139 | Segmentation fault | 没有动态链接器要找，CPU 真的开始执行，执行到错误的指令后被终止 |

这个实验说明两件事：3.4 节描述的流程是真实存在的；退出码能精确告诉我们一个程序
死在了哪一步。第 5 节在板子上还会用到这张表。

### 3.6 binfmt_misc：可以让内核把文件转交给别人

3.4 节的表里排在最前面的是自定义规则处理器 binfmt_misc。它允许往内核里登记
规则：

    文件开头是某几个字节时,不要自己加载,交给我指定的程序去运行

这台电脑上就有一条活的规则。WSL 能在 Linux 里直接运行 Windows 的 `.exe` 程序，
靠的就是它：

```bash
ls /proc/sys/fs/binfmt_misc/
cat /proc/sys/fs/binfmt_misc/WSLInterop
```

`/proc` 下面不是磁盘上的文件，是内核把自己的状态以文件的形式展示出来，读它就是
在问内核。本机实测：

```text
WSLInterop  python3.14  register  status
```

```text
enabled
interpreter /init
flags: P
offset 0
magic 4d5a
```

`magic 4d5a` 是规则要匹配的字节：0x4d 是 'M'，0x5a 是 'Z'，Windows 的 `.exe`
文件都以 `MZ` 两个字母开头。`interpreter /init` 是匹配上之后交给谁。所以在 WSL
里敲 `notepad.exe`，内核读到文件开头 `MZ`，最先问到的 binfmt_misc 发现匹配这条
规则，就交给 `/init`，再由它转到 Windows 那边去运行。

同样的机制，把规则换成"文件头的 e_machine 是 40 的 ELF"，把交给的程序换成一个
ARM 指令模拟器（`qemu-arm-static`），ARM 程序就能在 x86 电脑上直接运行。因为
binfmt_misc 排在 ELF 处理器前面，这条规则会在架构检查之前生效，ARM 程序根本走不到
`elf_check_arch` 那一步。

**本仓故意不装 `qemu-user-static`**。装了它，系统会自动登记这样的规则，
3.1 节的 `./hello_arm_dynamic` 就不再报错而是正常打印，本章依赖的
"必须报 Exec format error"这条判据就失效了。

### 3.7 顺带：Type 为什么是 DYN

3.3 节的 `readelf -h` 里有一行 `Type: DYN (Position-Independent Executable file)`。
按 ELF 最初的设计，能直接运行的程序类型应该是 `EXEC`，`DYN` 原本用于共享库。
这里两个程序都是 `DYN`，原因是现代 gcc 默认生成 **PIE**（位置无关可执行文件）：
程序的机器码不依赖自己被装在内存的哪个地址，于是内核每次运行它时可以随机挑一个
加载地址，让攻击者难以预测代码的位置。这种程序在 ELF 里就标成 `DYN`。

用 `-no-pie` 关掉它，类型就变回 `EXEC`：

```bash
gcc -no-pie -o hello_nopie hello.c
readelf -h hello_nopie | grep 'Type:'
```

```text
  Type:                              EXEC (Executable file)
```

`file` 的措辞也会从 `pie executable` 变成 `executable`。这一点和本章主线无关，
只是为了不让 `DYN` 这个词在你心里留个疑问。

### 3.8 [判] 第 2、3 节

    [ ] file 两行输出的架构一栏是 x86-64 和 ARM,位宽是 64 和 32
    [ ] xxd 看到位置 18、19 的两个字节,一个是 28 00,一个是 3e 00,
        并能说出它们为什么分别是 40 和 62
    [ ] readelf -h 的 Machine 与上面的字节对得上
    [ ] 运行 hello_arm_dynamic 报 Exec format error,退出码 126;
        不是 Permission denied(那是文件没有执行权限,和架构无关)
    [ ] strace 看到 execve 返回 -1 ENOEXEC
    [ ] 注错两连得到 127 和 139,能说出各自死在哪一步
    [ ] readelf -l 动态版有 INTERP,静态版没有
    [ ] /proc/sys/fs/binfmt_misc/WSLInterop 的 magic 是 4d5a,说得出是什么

    注错见红:不改 e_machine,直接运行 hello_arm_static,
    必须得到 126 而不是 139(本机实测确实是 126)。
    如果得到的是正常的 Hello,说明 binfmt_misc 里多了一条 ARM 规则。

**第 3 节搭好的积木**：运行程序是内核在 execve 里做的；内核先读 ELF 文件头，
检查 e_machine，不符就拒绝；动态链接的程序还要找 `.interp` 写的动态链接器，
静态链接的程序不需要；退出码 126 / 127 / 139 分别对应这三个位置。

现在 ARM 版的程序准备好了，也知道电脑上为什么跑不了。下一步是把它送进板子。

---
## 4 把文件送进板子：串口

### 4.1 串口是什么

电脑和板子之间，本仓只用一根线连接：串口。串口（UART）是一种最简单的通信方式：
两根数据线，一根发、一根收，每次在线上送 1 个比特（0 或 1），一个字节分成 8 个
比特依次送过去。

板子上的系统启动后，会在串口上运行一个登录界面和 shell（就像电脑上打开的终端）。
于是这一根线可以同时干四件事：登录板子、发命令、看输出、传文件。本仓所有上板操作
都走这一根线，由仓库里的脚本 `Tools/serial-board.ps1` 统一完成。

电脑这一侧要注意一个边界：串口设备在 Windows 那边，WSL 里看不到。所以**编译在
WSL 里做，串口命令在 Windows 的 PowerShell 里敲。**两边通过同一块磁盘交换文件：
WSL 里的 `/mnt/e/Workspace/...` 就是 Windows 的 `E:\Workspace\...`，WSL 编出来的
文件，PowerShell 能直接读到。

### 4.2 找对口

板子左侧有两个上下挨着的 micro-USB 口：

    上面那个  USB OTG 口    插上后电脑只多出一个名叫 100ASK_IMX6ULL 的 USB 设备,
                            没有串口。本仓不用这个口。
    下面那个  USB 转串口口  板上有一颗 CH9102 芯片,把 USB 转成串口,
                            插上后电脑多出一个 COM 口。

两个口插上去，Windows 都会响一声"设备接入"的提示音。提示音只说明"有设备接进来"，
说明不了接的是哪个口。判断要看系统里多出来的是不是 COM 口。在 PowerShell 里列出
当前插着的端口类设备：

~~~powershell
Get-PnpDevice -PresentOnly -Class Ports
~~~

- `-PresentOnly`：只列现在插着的。不加会把很久以前插过、早已拔掉的设备也列出来。
- `-Class Ports`：只看"端口"这一类设备。

2026-09-14 实测（最后一列截短）：

~~~text
Status Class FriendlyName                      InstanceId
------ ----- ------------                      ----------
OK     Ports 蓝牙链接上的标准串行 (COM3)       BTHENUM\{00001101-...}...
OK     Ports USB-Enhanced-SERIAL CH9102 (COM8) USB\VID_1A86&PID_55D4\5B8E648930
OK     Ports 蓝牙链接上的标准串行 (COM4)       BTHENUM\{00001101-...}...
~~~

COM3、COM4 是电脑自带的蓝牙串口，和板子无关。认准名字里带 `CH9102` 的那一个，
这里是 COM8。COM 号是 Windows 分配的，换一个 USB 插孔可能会变；变了就在脚本命令
后面加 `-Port COM实际编号`。

### 4.3 两端参数必须一致：115200 8N1

串口线上只有一串高低电平，没有任何"现在开始一个字节"的额外信号。接收方要从这串
电平里切出一个个比特、一个个字节，全靠双方事先约定好几个参数。串口没有协商过程，
两端各按自己的设置去切，任何一项不同就对不上：

| 参数 | 本板取值 | 它规定了什么 | 填错的现象 |
|---|---|---|---|
| 波特率 | 115200 | 每秒送多少个比特，也就决定了每个比特在线上持续多长时间 | 乱码：每一位的宽度对不上，切错了位置 |
| 数据位 | 8 | 一个字节用几个比特送 | 乱码 |
| 校验位 | 无（N） | 每个字节后面要不要多送一个用来检查错误的比特 | 乱码或丢字 |
| 停止位 | 1 | 每个字节结束后，线上保持空闲电平多久（几个比特的时间） | 偶尔错字 |
| 流控 | 无 | 收方能不能用额外的线通知发方"先停一下" | 一个字都不显示，敲什么都没反应 |

前四项合起来写作 `115200 8N1`。

顺着这几个参数可以算出串口有多快。送一个字节，线上实际要送：1 个起始位（告诉
对方"一个字节开始了"）+ 8 个数据位 + 0 个校验位 + 1 个停止位 = 10 个比特。
波特率 115200 表示每秒 115200 个比特，那么每秒最多送 115200 ÷ 10 = **11520 个
字节**，也就是大约 11 KB/s。这个数在 4.6 节和 4.8 节都要用。

板子那一端的设置不用猜，让它自己报出来。下一节先学怎么在板子上执行命令。

### 4.4 在板子上执行命令

`Tools/serial-board.ps1` 的基本用法：把要在板子上执行的命令用单引号括起来作为参数，
脚本负责登录、发命令、把输出取回来，并把板上最后一条命令的退出码作为自己的退出码。

~~~powershell
Set-Location E:\Workspace\Embedded-linux
.\Tools\serial-board.ps1 'uname -a; cat /proc/cmdline; ls /dev/ttymxc*'
~~~

- `Set-Location`：PowerShell 里的 `cd`，进入仓库根目录。
- 单引号里的整串，原样发给板子上的 bash 去执行。PowerShell 的单引号里不做任何
  替换，`;`、`*`、`$?` 都原样发过去，由板子上的 bash 来解释。
- `uname -a`：打印内核和机器的完整信息。
- `cat /proc/cmdline`：打印内核启动时收到的参数。
- `ls /dev/ttymxc*`：列出板子上的串口设备文件。

2026-09-14 实测：

~~~text
Linux 100ask 4.9.88 #1 SMP PREEMPT Sun Jul 21 03:42:00 EDT 2024 armv7l GNU/Linux
console=ttymxc0,115200 root=/dev/mmcblk1p2 rootwait rw
/dev/ttymxc0  /dev/ttymxc2  /dev/ttymxc5
~~~

第一行末尾的 `armv7l`，就是 2.1 节引用的板子架构。第二行 `console=ttymxc0,115200`
是板子那一端的设置：内核把控制台（登录界面所在的地方）放在 0 号串口 `ttymxc0`
上（i.MX 芯片的串口驱动叫 mxc，所以设备名叫 `ttymxc`），波特率 115200。电脑这一端
必须设成一样，脚本里已经设好。

再看串口这一层更细的设置：

~~~powershell
.\Tools\serial-board.ps1 'stty -a'
~~~

`stty -a` 打印当前终端的全部设置。2026-09-14 实测（节选）：

~~~text
speed 115200 baud; rows 0; columns 0; line = 0;
intr = ^C; quit = ^\; erase = ^?; kill = ^U; eof = ^D; ...
-parenb -parodd -cmspar cs8 hupcl -cstopb cread clocal -crtscts
... icrnl ixon ixoff ...
~~~

对着 4.3 节的表读第一行和第三行：`speed 115200` 是波特率；`cs8` 是 8 个数据位；
`-parenb` 前面的减号表示"关闭"，即不用校验位；`-cstopb` 表示不用两个停止位，也就是
1 个；`-crtscts` 表示关闭硬件流控。和 `115200 8N1`、无流控完全一致。

第二行和第四行（`intr = ^C`、`eof = ^D`、`icrnl`、`ixon`）是下一节的伏笔。

### 4.5 为什么不能把 ELF 原样灌进串口

最直接的传文件办法：把 `hello_arm_static` 的字节原样从串口送过去，板子那边存成
文件。这行不通，原因在于串口收到的字节不是直接交给程序的。

板子上，串口收到的每个字节要先经过内核里一层叫**行规程**（line discipline）的处理，
再交给 bash。这一层的本来用途是处理人在键盘上敲的字：人按下 Ctrl+C，终端送来的是
字节 0x03，行规程看到它就不交给程序，而是通知前台程序中断。上一节 `stty -a` 输出的
那几项，就是行规程的规则：

| 字节 | 行规程怎么处理 | 来自 `stty -a` 的哪一项 |
|---|---|---|
| `0x03`（Ctrl+C） | 不交给程序，向前台程序发中断信号 | `intr = ^C` |
| `0x04`（Ctrl+D） | 当作"输入结束" | `eof = ^D` |
| `0x0d`（回车） | 改写成 `0x0a`（换行） | `icrnl` |
| `0x13`、`0x11` | 当作"暂停发送""恢复发送"，吞掉不交 | `ixon` |
| `0x7f` | 当作退格，删掉前一个字节 | `erase = ^?` |

行规程之后还有一层：bash 自己的行编辑功能会把 `0x80` 以上的字节当成组合键处理。

一个 ELF 文件里，这类特殊字节有多少？在 WSL 里数一数 `hello_arm_static`：

```bash
od -An -tu1 -v hello_arm_static | tr -s ' ' '\n' | awk 'NF { c[$1]++; n++ } END {
    printf "0x03=%d 0x04=%d 0x0d=%d 0x11=%d 0x13=%d 0x7f=%d\n", c[3], c[4], c[13], c[17], c[19], c[127]
    for (k in c) if (k+0 >= 128 || k+0 < 32 || k+0 == 127) bad += c[k]
    printf "%d of %d bytes (%.1f%%)\n", bad, n, 100 * bad / n }'
```

这条命令分三段：

- `od -An -tu1 -v hello_arm_static`：`od` 把文件按字节打印出来。`-tu1` 表示每个字节
  按无符号十进制数打印（0～255）；`-An` 表示不打印每行开头的位置；`-v` 表示连续
  相同的行也照样打印（默认会把重复行折叠成一个 `*`，那样就数少了）。
- `tr -s ' ' '\n'`：把空格换成换行，每个数占一行。`-s` 把连续的多个空格当作一个。
- `awk '...'`：`awk` 是一个按行处理文本的小语言。`NF { c[$1]++; n++ }` 对每个非空行，
  把这个数出现的次数加 1，总数也加 1；`END { ... }` 在全部读完后打印统计：几个特殊
  字节各出现多少次，以及所有"控制字符"（小于 32、等于 127、大于等于 128）合计占
  多少。

本机实测：

```text
0x03=5600 0x04=5926 0x0d=870 0x11=1155 0x13=1415 0x7f=903
345819 of 487028 bytes (71.0%)
```

文件里有七成的字节会被行规程或 bash 截走、改写，或者当成控制命令。原样灌进去，
板子上收到的会是一团完全不同的东西。

解决办法是先把文件转成只含普通字符的文本再送。**base64** 编码就是干这个的：它把
任意字节转成只由 `A-Z`、`a-z`、`0-9`、`+`、`/`、`=` 这 65 个字符组成的文本，这些
字符行规程都不会碰。板子上用 `base64 -d` 解回原来的字节。代价是体积变大：base64 每
3 个字节变成 4 个字符，多出三分之一。所以脚本在 base64 之前先用 gzip 压缩一次，
把这部分损失补回来。

### 4.6 串口会悄悄丢字节

转成文本后，还有第二个问题。本仓第一版脚本的做法是：整个文件 base64 之后一口气
发完，最后比一次校验值。用它传一个 4.4 MB 的测试包（2026-09-14 实测）：

~~~text
board.tar -> /tmp/ch02-board-repro/board.tar: 4433920 bytes, gzip 2246265, base64 2995020 chars, 324.6 s, sha256 MISMATCH
  local 315310eff3bf450f8c6437f043e3f5eaa02179aff9844d652f9eddd4120a9991
  board cd251c1fabeafe4e4170dd7bba610307ece169f80ca32fde7352a85b25fcaa6a
~~~

这里的 sha256 是一种校验值：对文件的全部内容算出一串 64 位的十六进制数，内容差
一个比特，结果就面目全非。电脑上算的（local）和板子上算的（board）不一样，说明
文件在路上坏了。而整个过程没有任何报错。

丢在了哪里？板子的内核对串口的错误有记账：

~~~powershell
.\Tools\serial-board.ps1 'cat /sys/class/tty/ttymxc0/xmit_fifo_size; grep "^0:" /proc/tty/driver/IMX-uart'
~~~

- `/sys/class/tty/ttymxc0/xmit_fifo_size`：0 号串口硬件缓冲区的大小。
- `/proc/tty/driver/IMX-uart`：i.MX 串口驱动的统计信息，`grep "^0:"` 只看 0 号口。

2026-09-14 实测：

~~~text
32
0: uart:IMX mmio:0x02020000 irq:20 tx:25656 rx:3652181 oe:2 RTS|DTR|DSR|CD
~~~

`tx`、`rx` 是发送和接收的字节数。`oe` 是 overrun error（接收溢出）的次数，这次
事故之后是 2。

接收溢出是这样发生的。串口芯片收到的字节，先放进芯片内部一个很小的硬件缓冲区
（这里是 32 字节），等 CPU 来取走；CPU 取走之后，再交给行规程、交给 bash。按 4.3
节算出的速度，每秒到达 11520 个字节，32 字节的缓冲区大约 32 ÷ 11520 ≈ 0.0028 秒，
即 **2.8 毫秒**就会装满。只要 CPU 有一次超过 2.8 毫秒没来取（比如正忙着处理别的
事），后面到达的字节就没有地方放，直接丢掉，`oe` 加 1。

丢的时候没有任何通知，发送方也不知道。放慢发送节奏也不能根治：串口一旦开始发一行
字，这一行的字节是紧挨着到达的。**能做的只有两件事：检测出损坏，然后重发。**

### 4.7 分块校验重传

现行脚本按下面的流程传文件：

1. 先用 gzip 压缩文件。
2. 把压缩结果切成每块 30000 字节，每块单独转成 base64。
3. 一块一块地发。每发一行，等板子回一个 `> ` 提示符再发下一行（板子上 bash 在等待
   多行输入时会显示这个提示符），这样两边步调一致。
4. 每块发完，板子上把这一块解码，算 sha256，和电脑上算好的值比。对上了才把这一块
   追加到目标文件；对不上，或者迟迟等不到 `> `，电脑就发 Ctrl+C 放弃这一块，整块重发。
5. 全部发完后，对整个文件再比一次 sha256，打印 `sha256 OK` 或 `MISMATCH`。

几处设计的理由：

- 为什么"等不到 `> `"也算损坏：如果丢掉的正好是行尾的回车，两行会粘成一行，板子
  不会回提示符；如果丢在结束标记里，板子会一直等下去。两种情况都表现为"等不到"。
- 为什么分块：丢一个字节只需要重发这 30000 字节，不用整个文件从头再来。
- 为什么最后还要整体比一次：防止每一块都对、但拼接时出了错。

### 4.8 [做 L1] 上传三个产物

**第一步，在 WSL 里确认三个产物。** 第 2、3 节已经编好了 `hello_x86`、
`hello_arm_dynamic`、`hello_arm_static`：

```bash
ls -l hello_x86 hello_arm_dynamic hello_arm_static
```

本机实测：

```text
-rwxrwxrwx 1 glorinz glorinz  69284 Oct 20 01:44 hello_arm_dynamic
-rwxrwxrwx 1 glorinz glorinz 487028 Oct 20 01:44 hello_arm_static
-rwxrwxrwx 1 glorinz glorinz  16000 Oct 20 01:44 hello_x86
```

第 5 列是文件大小（字节）。静态版 487028 字节，是动态版 69284 字节的 7.0 倍：
3.5 节说过，静态版把用到的 C 库函数全部拷了进来。

**第二步，在 PowerShell 里传三个文件。**

~~~powershell
Set-Location E:\Workspace\Embedded-linux
.\Tools\serial-board.ps1 'rm -rf /tmp/ch01-board-repro'
foreach ($n in 'hello_x86', 'hello_arm_dynamic', 'hello_arm_static') {
    .\Tools\serial-board.ps1 -Upload ".\Knowledge\labs\01_hello\$n" -Destination "/tmp/ch01-board-repro/$n"
}
~~~

- 第一条：先清掉板子上的旧目录，保证这次是从空目录开始。
- `foreach ($n in ...) { ... }`：PowerShell 的循环，`$n` 依次取三个文件名。
- `-Upload`：电脑上的源文件。这里用双引号，是要让 PowerShell 把 `$n` 替换成文件名。
- `-Destination`：板子上的目标路径。脚本只允许写到 `/tmp/` 下面。板子上的 `/tmp`
  在内存里，断电就没了，适合放实验产物。

2026-09-14 实测：

~~~text
hello_x86 -> /tmp/ch01-board-repro/hello_x86: 16000 bytes, gzip 2312, 1 blocks, 0 resent, 0.7 s, sha256 OK
hello_arm_dynamic -> /tmp/ch01-board-repro/hello_arm_dynamic: 69284 bytes, gzip 2713, 1 blocks, 0 resent, 0.7 s, sha256 OK
hello_arm_static -> /tmp/ch01-board-repro/hello_arm_static: 487028 bytes, gzip 239471, 8 blocks, 0 resent, 32.9 s, sha256 OK
~~~

每行依次是：原始大小、gzip 后的大小、分成几块、重发了几块、用时、最终校验结果。

用静态版算一下实际速度。gzip 后 239471 字节，base64 之后变成 4/3 倍，约 319296 个
字符；用了 32.9 秒，每秒约 9700 个字符。4.3 节算出的上限是每秒 11520 个，实际达到
约 84%，其余时间花在逐行等提示符和逐块校验上。**串口传文件适合几百 KB 的
产物**；几 MB 的东西要几分钟，那时就该换网线了（5.5 节）。

**第三步，在板子上确认文件。**

~~~powershell
.\Tools\serial-board.ps1 'cd /tmp/ch01-board-repro; chmod +x hello_*; ls -l; file hello_*'
~~~

- `chmod +x hello_*`：给文件加上"可执行"权限。脚本在板子上是新建文件再写入内容的，
  新建的文件默认没有执行权限，不加这一步，运行时会报 `Permission denied`。

2026-09-14 实测（节选）：

~~~text
-rwxr-xr-x 1 root root  69284 hello_arm_dynamic
-rwxr-xr-x 1 root root 487028 hello_arm_static
-rwxr-xr-x 1 root root  16000 hello_x86
hello_arm_dynamic: ELF 32-bit LSB shared object, ARM, EABI5 ..., dynamically linked, interpreter /lib/ld-linux-armhf.so.3
hello_arm_static:  ELF 32-bit LSB executable, ARM, EABI5 ..., statically linked
hello_x86:         ELF 64-bit LSB shared object, x86-64, ...
~~~

大小和电脑上一致，`file` 的判断也和 2.4 节一致（板子上的 `file` 版本较旧，把 PIE
程序称作 shared object，这是措辞差异）。

**第 4 节搭好的积木**：串口一根线负责登录、命令和传文件；参数必须两端一致；
文件要先转成 base64 才能经过行规程；串口会悄悄丢字节，只能靠分块校验重传。
三个产物已经完好地躺在板子的 `/tmp/ch01-board-repro/` 里了。

---

## 5 在板子上运行三个产物

一次运行三个，每个后面立刻接住退出码：

~~~powershell
.\Tools\serial-board.ps1 'cd /tmp/ch01-board-repro; ./hello_x86 learner; echo x86_exit=$?; ./hello_arm_dynamic learner; echo dynamic_exit=$?; ./hello_arm_static learner; echo static_exit=$?'
~~~

外层必须用单引号。换成双引号，PowerShell 会先把 `$?` 替换成它自己的值 `True`，
板子收到的就是 `echo x86_exit=True`，看不到真正的退出码。

2026-09-14 板上原样输出：

~~~text
-bash: ./hello_x86: cannot execute binary file: Exec format error
x86_exit=126
./hello_arm_dynamic: /lib/libc.so.6: version `GLIBC_2.34' not found (required by ./hello_arm_dynamic)
dynamic_exit=1
Hello, learner!
static_exit=0
~~~

三个产物，三种下场。前面四节攒下的积木，足够把每一行都解释清楚。

### 5.1 x86 版：和电脑上同一个拒绝

`Exec format error`，退出码 126。这和 3.1 节在电脑上运行 ARM 版的结果是同一个，
方向反过来而已：板子上的内核读到 `hello_x86` 的 e_machine 是 62（x86-64），而本机
是 40（ARM），架构检查不通过，拒绝执行。3.4 节说过，板子和电脑跑的是同一段 Linux
内核检查代码，所以报的是同一句话。

### 5.2 ARM 动态版：GLIBC_2.34 not found

这一行是新面孔。架构是对的（ARM），说明它过了架构检查；它也没有报 127，说明
`.interp` 指定的动态链接器 `/lib/ld-linux-armhf.so.3` 在板子上找到了。死在了更后面
的一步。

报错逐段读：

- `./hello_arm_dynamic:`：出错的程序。
- `/lib/libc.so.6:`：出问题的是板子上的 C 库。
- ``version `GLIBC_2.34' not found``：程序要求的 `GLIBC_2.34` 这个版本，在这个 C 库里
  没有。
- `(required by ./hello_arm_dynamic)`：提出这个要求的是我们的程序。
- 退出码 1：这一次不是内核拒绝，而是动态链接器自己检查失败后，以 1 退出。

要看懂它，需要知道 glibc 怎么处理版本。glibc 会不断推出新版本，新版本有时会修改
某个函数的行为。为了让老程序不受影响，glibc 给每个函数打上"版本标签"：程序编译时
链接的是哪个版本的函数，就在程序里记下这个标签；运行时，动态链接器要在板子的 C 库
里找到**带同样标签**的函数，找不到就拒绝运行。

看一看我们的程序记下了哪些标签（在 WSL 里）：

```bash
arm-linux-gnueabihf-objdump -T hello_arm_dynamic | grep GLIBC
```

- `objdump -T`：显示程序的动态符号表，也就是"运行时需要从库里找的函数"。

本机实测：

```text
00000000      DF *UND*	00000000 (GLIBC_2.34) __libc_start_main
00000000  w   DF *UND*	00000000 (GLIBC_2.4)  __cxa_finalize
00000000      DF *UND*	00000000 (GLIBC_2.4)  puts
00000000      DF *UND*	00000000 (GLIBC_2.4)  __printf_chk
00000000      DF *UND*	00000000 (GLIBC_2.4)  abort
```

`*UND*` 表示"这个函数不在本文件里，要到库里找"。`puts`、`__printf_chk`（2.4 节反汇编
里见过的两个调用）要求的是 `GLIBC_2.4`，这是很老的标签，板子上肯定有。问题出在第一行：
`__libc_start_main` 要求 `GLIBC_2.34`。这个函数是 C 库里负责做好准备工作、然后调用
`main` 的那一段，每个程序都要用到。它在 glibc 2.34 版本里改过一次，电脑上的交叉编译器
带的 C 库比 2.34 新，编出来的程序就记下了 2.34 这个标签。

板子上的 C 库是哪个版本？版本号直接写在文件名里：

~~~powershell
.\Tools\serial-board.ps1 'ls -l /lib/libc.so.6 /lib/libc-2*.so'
~~~

2026-09-14 实测：

~~~text
-rwxr-xr-x 1 root root 1241860 Jul 21  2024 /lib/libc-2.30.so
lrwxrwxrwx 1 root root      12 Jul 21  2024 /lib/libc.so.6 -> libc-2.30.so
~~~

`libc.so.6` 是一个链接，指向 `libc-2.30.so`：板子上是 glibc **2.30**，比 2.34 老，
当然没有 2.34 的标签。

这就是 2.5 节那三件事里的第三件：**配套的库对不上**。指令集对了、二进制约定对了，
程序还是跑不起来。

### 5.3 ARM 静态版：进入 main

`Hello, learner!`，退出码 0。它为什么能过？回到 3.5 节对静态链接的描述：编译时就把
用到的库函数整个拷进了程序文件。所以：

- 它的 e_machine 是 40，过了板子的架构检查。
- 它没有 `.interp`，内核不去找动态链接器，直接把它装进内存运行。
- 运行时它不去板子的 C 库里找任何函数，`__libc_start_main`、`puts` 都在它自己身上，
  也就不存在版本对不上的问题。

可以在 WSL 里确认这几个函数确实在静态版自己身上：

```bash
arm-linux-gnueabihf-nm hello_arm_static | grep -E ' (puts|__printf_chk|__libc_start_main)$'
```

- `nm`：列出文件里的符号（函数名、变量名）。

```text
00010464 T __libc_start_main
0001c648 T __printf_chk
00010cc4 W puts
```

`T` 表示"这个函数的代码就在本文件里"（`W` 是它的一个变体）。对比 5.2 节动态版里
同样三个函数标的是 `*UND*`（不在本文件里）。

于是有了本仓的规矩：**现阶段上板的程序一律用 `-static` 编译**（记录在
`Project/doc/开发环境.md` 第 3 节）。代价是文件大了 7 倍，换来的是不依赖板子上
C 库的版本。以后换用和板子系统同一批构建出来的工具链，C 库版本一致了，动态链接的
程序也能直接跑，那时这条规矩可以放宽。

把板上三行和前面的表放在一起：

| 产物 | 板上结果 | 退出码 | 死在哪一步（或走到哪里） |
|---|---|---|---|
| hello_x86 | Exec format error | 126 | 架构检查（3.4 节） |
| hello_arm_dynamic | GLIBC_2.34 not found | 1 | 架构过了，动态链接器也找到了，库的版本标签对不上 |
| hello_arm_static | Hello, learner! | 0 | 一路通过，进入 main |

### 5.4 [做 L2] 上板判据与注错

    [ ] Get-PnpDevice -PresentOnly -Class Ports 里有状态 OK 的 CH9102
    [ ] 板上 uname -a 含 armv7l;/proc/cmdline 含 console=ttymxc0,115200
    [ ] 三次上传都打印 sha256 OK
    [ ] hello_x86 报 Exec format error,退出码 126
    [ ] hello_arm_dynamic 报 GLIBC_2.34 not found,退出码 1
    [ ] hello_arm_static 打印 Hello, learner!,退出码 0
    [ ] objdump -T 能指出是哪个函数要求 GLIBC_2.34

判据里最依赖"不出错"的是传输校验，所以要专门验证它真的能发现错误。

**注错一：校验必须能抓住一个字节的损坏。** 趁板子上文件还在，复制一份、改坏一个
字节，比较校验值：

~~~powershell
.\Tools\serial-board.ps1 'cd /tmp/ch01-board-repro; cp hello_arm_static bad; printf X | dd of=bad bs=1 seek=1000 conv=notrunc 2>/dev/null; sha256sum hello_arm_static bad; cmp -l hello_arm_static bad'
~~~

- `printf X | dd ... seek=1000`：和 3.5 节同一个手法，把位置 1000 的字节改成 `X`。
- `sha256sum`：算两个文件的校验值。
- `cmp -l`：逐字节比较两个文件，列出所有不同的位置和两边的值。

2026-09-14 实测：

~~~text
427c9468...da6b2a1d8d75822473a537915ae4f1cde8  hello_arm_static
0d833cb2...ee0e49df22b5970b5c9  bad
1001 143 130
~~~

两个文件只差一个字节（`cmp` 说是第 1001 个，它从 1 开始数，就是位置 1000；
原值八进制 143 即字母 `c`，现值八进制 130 即字母 `X`），校验值却从头到尾完全不同。

**注错二：重发这条路必须真的走过一次。** 串口平时很少丢字节，上传几十次也未必触发
一次重发，从没被执行过的代码不能算验证过。脚本留了一个开关，故意把指定的一块改坏：

~~~powershell
.\Tools\serial-board.ps1 -Upload .\Knowledge\labs\01_hello\hello_arm_static -Destination /tmp/ch01-board-repro/hello_arm_static -CorruptBlock 2
~~~

- `-CorruptBlock 2`：把第 2 块（从 0 数，也就是第 3 块）的一个 base64 字符换成另一个
  合法字符。这样板子上 `base64 -d` 不会报错，解出来的字节却是错的，只有校验值能发现。

2026-09-14 实测：

~~~text
block 3/8 arrived damaged (attempt 1), sending it again
hello_arm_static -> /tmp/ch01-board-repro/hello_arm_static: 487028 bytes, gzip 239471, 8 blocks, 1 resent, 37.3 s, sha256 OK
~~~

第 3 块被发现损坏并重发，最终校验通过。比正常上传多出的约 4 秒，就是重发这一块的
时间。最后清理板子上的实验目录：

~~~powershell
.\Tools\serial-board.ps1 'rm -rf /tmp/ch01-board-repro'
~~~

### 5.5 另一条上板通道：NFS（暂不接通）

串口每秒十来 KB，几 MB 的程序要传几分钟。嵌入式开发里更常用的做法是用网线：
在电脑上开一个 NFS（网络文件系统）服务，把电脑上的一个目录"挂"到板子上，板子
访问那个目录就像访问自己的磁盘一样，电脑上编完，板子上立刻就能运行，不用再传。

板子上挂载 NFS 的命令形如：

```bash
mount -t nfs -o nolock,vers=3 电脑的IP:/导出的目录 /mnt
```

- `mount -t 类型 -o 选项 来源 挂载点`：这是 mount 的通用形式。来源可以是 U 盘、
  SD 卡，也可以像这里一样是"另一台机器上的目录"。
- `-t nfs`：类型是网络文件系统。
- `-o nolock,vers=3`：`vers=3` 指定 NFS 协议的第 3 版；`nolock` 表示不使用文件锁服务。
  板子上的精简系统通常没有运行锁服务，不加这一项时挂载会一直等锁服务的响应而卡住。
- `/mnt`：挂到板子上的哪个目录。

**这条命令现在不要执行。**本仓目前没有接通 NFS，原因有两个（2026-09-14 板上实测）：
板子上只有回环接口 `lo` 有 IP 地址，网口和 WiFi 都没有配置；电脑这一侧，WSL2 默认
用的是 NAT 网络，板子从外面连不进 WSL 里的服务。以后产物大到串口传不动时，再把网络
配好，把实际的 IP、目录和测速结果写回这一节。

---

## 6 回看：整章的问题链

整章从"让 hello 在板子上打印一行字"出发，每一步都是被上一步逼出来的：

| 问题 | 答案 | 证据在哪 |
|---|---|---|
| 程序怎么拿到命令行上的词 | bash 切词后交给 `argc`、`argv` | 1.2 |
| 程序怎么告诉别人成功与否 | 退出码，bash 存在 `$?` | 1.3 |
| 编译器怎么检查函数调用 | 依据头文件里的声明 | 1.4 |
| `printf` 的实现在哪 | C 库；C 库通过系统调用请内核做事 | 1.5 |
| 电脑编的程序板子能跑吗 | 不能，CPU 架构不同，机器码不通 | 2.1、2.2、2.4 |
| 怎么给 ARM 生成机器码 | 交叉编译器 `arm-linux-gnueabihf-gcc` | 2.3 |
| 编译器名字说明了什么 | 指令集、二进制约定、C 库 | 2.5、2.6 |
| ARM 的头文件和库从哪来 | 交叉编译器自带的 sysroot | 2.7 |
| ARM 程序在电脑上为什么跑不了 | 内核在 execve 里检查 e_machine，拒绝 | 3.1～3.4 |
| 骗过架构检查会怎样 | 动态版找不到动态链接器（127），静态版执行错指令（139） | 3.5 |
| 怎么把文件送上板子 | 串口，base64 加分块校验重传 | 4.3～4.8 |
| 板上三个产物为什么三种下场 | 架构不符（126）、库版本不符（1）、全部通过（0） | 5.1～5.3 |

整条链路画在一张图里：

![图 2　本章链路：同一份源码，两条机器线，三种下场](fig/01-本章链路.svg)

实线是会发生的流程；绿框是跑通的结果，红框是被拦下的结果；虚线是失败与对照路径。
图里标的"第 N 节"就是本章的节号。

---

## 7 自检

答不上来就回到对应小节。每一题都能用命令验证，不要凭印象回答。

    1. ./argv_dump a "b c" 时 argc 是多少?argv[1]、argv[2] 各是什么?
       去掉引号再数一遍。                                            (1.2)

    2. 声明和定义各是什么?把 decl_demo.c 的声明删掉,用默认标准编译和用
       -std=gnu89 编译,结果分别是什么?为什么后者打印出一个奇怪的数? (1.4)

    3. printf 的实现在哪里?它把字送到屏幕上,自己做不到的那一步是谁做的? (1.5)

    4. 电脑上的 gcc 和 arm-linux-gnueabihf-gcc,Target 各是什么?
       交叉编译的 host 和 target 分别指什么?                       (2.2 2.3)

    5. arm-linux-gnueabihf 各段规定了什么?为什么 hf 是硬约束而不是性能选项? (2.5 2.6)

    6. 交叉编译时用的 stdio.h 和 libc.so.6 在电脑上的哪里?怎么确认 libc.so.6
       是 ARM 的?                                                    (2.7)

    7. 内核在哪个系统调用里、检查文件的哪两个字节,决定拒绝一个 ARM 程序?
       用什么命令能看到这次拒绝?                                     (3.2 3.3)

    8. 改坏 e_machine 后,动态版报 required file not found 而静态版段错误,
       为什么?126、127、139、1 四个退出码各对应哪一步?          (3.5 5.2)

    9. 为什么不能把 ELF 原样灌进串口?串口丢字节时,内核在哪里留下记录?
       115200 8N1 每秒最多传多少字节,怎么算的?               (4.3 4.5 4.6)

   10. 板上动态版报 GLIBC_2.34 not found,是程序里哪个函数要求的?板子上的
       glibc 是哪个版本?静态版为什么没有这个问题?             (5.2 5.3)

---

## 8 已知的坑

    坑 1  串口流控没关,屏幕一个字都不显示,敲什么都没反应。
          和"波特率填错导致乱码"是两种不同的现象。                    (4.3)

    坑 2  线插在上面那个 OTG 口,提示音照样响,但不会出现 COM 口。
          判断靠 Get-PnpDevice 看有没有 CH9102,不靠提示音。          (4.2)

    坑 3  串口里发的命令不能带中文。板子上的 bash 没有配置 UTF-8,
          会把 0x80 以上的字节当成组合键,整行命令被悄悄改写
          (实测发一行带中文的 printf,报 printf: --: invalid option)。
          程序输出的中文能正常显示;命令里确实要用中文,就写成
          printf 的八进制转义。                                       (4.5)

    坑 4  装了 qemu-user-static 之后,电脑上直接运行 ARM 程序会成功。
          哪天发现 ./hello_arm_dynamic 居然打印出了 Hello,先去看
          /proc/sys/fs/binfmt_misc/ 下面多了什么。                    (3.6)

    坑 5  串口传文件必须带校验和重传。怀疑丢了字节,先看
          /proc/tty/driver/IMX-uart 里的 oe 有没有增加。              (4.6)

    坑 6  传上去的文件没有执行权限,运行报 Permission denied。
          先 chmod +x。这和 Exec format error 是两回事。              (4.8)

    坑 7  PowerShell 里给脚本传板上命令时用了双引号,$? 被 PowerShell
          提前替换成 True,看不到真正的退出码。一律用单引号。          (5)

---

## 9 交出了什么

现在能独立做到：

- 解释一个程序从 `main` 的参数、退出码，到 C 库、系统调用的分工
- 说清楚"给谁编"为什么必须在编译时决定，交叉编译器的名字各段规定了什么
- 用 `file`、`xxd`、`readelf`、`strace` 查出一个程序为什么不能运行，以及死在哪一步
- 用交叉编译器编出静态链接的 ARM 程序，通过串口分块校验传上板，运行并解释结果

还做不到：

- 编译的内部过程：预处理、编译、汇编、链接四步各产出什么，库是怎么被拼进来的
  （02 篇）
- 用一条命令编译几十个文件的构建系统（03 篇）
- 编写内核模块、修改设备树（第 2 阶段）

下一章：[02 GCC 编译器的使用](02_GCC编译器的使用.md)。这一章里我们一直把
"`gcc hello.c -o hello`"当成一步，下一章把它拆开。
