# 03 ABI 与 sysroot

被 01 章第 2 节用到。

## 一句话

ABI 规定"机器码层面的接口长什么样"；sysroot 是"目标系统的头文件和库放在哪"。
一个管编译出来的字节，一个管编译时去哪找材料。

## 一、先跟 ysyx 对上

    ysyx / abstract-machine                Linux 交叉编译
    ----------------------------------     ---------------------------------
    没有 sysroot 这个概念                  必须有
    因为 libc 是 am 自己写的 klib          因为 libc 是别人（glibc）编好的
    头文件就在项目目录里                    头文件在工具链自带的一棵目录树里
    编译时 -I$(AM_HOME)/klib/include        编译时工具链自动带上 sysroot 路径

    ABI 你其实已经踩过：                    这里遇到的是同一件事
    riscv32 的 ilp32 / ilp32f / ilp32d      arm 的 soft / softfp / hard
    改了这个整个 am 要重编                  改了这个所有 .o 要重编

## 二、ABI 到底包含什么

先分清 API 和 ABI，这两个词只差一个字母，层次完全不同：

    API (Application Programming Interface)     源码层面的约定
        int open(const char *path, int flags);
        你写代码时看的是这个。换编译器、换优化等级，API 不变。

    ABI (Application Binary Interface)          机器码层面的约定
        path 放 r0，flags 放 r1，返回值在 r0
        栈往低地址长，调用前 sp 要 8 字节对齐
        struct { char a; int b; } 占 8 字节而不是 5 字节
        你写代码时看不见它，但两个 .o 要链到一起就必须一致。

ABI 具体规定这些（ARM 上这份文档叫 AAPCS）：

    +--------------------------------------------------------------+
    |  1. 参数怎么传                                               |
    |     前 4 个整数参数走 r0-r3，多的压栈                        |
    |     浮点参数走 s0-s15 还是 r0-r3   <== 这就是 hf 和 soft 之别 |
    +--------------------------------------------------------------+
    |  2. 返回值怎么给                                             |
    |     32 位放 r0，64 位放 r0:r1，大结构体由调用方给一块内存    |
    +--------------------------------------------------------------+
    |  3. 哪些寄存器调用后必须保持原值                             |
    |     r4-r11 是 callee-saved，r0-r3 随便糟蹋                    |
    +--------------------------------------------------------------+
    |  4. 基本类型的大小和对齐                                     |
    |     long 是 4 还是 8 字节，double 要不要 8 字节对齐          |
    +--------------------------------------------------------------+
    |  5. 结构体怎么排布，位域怎么填                               |
    +--------------------------------------------------------------+
    |  6. 栈帧长什么样，异常怎么展开                               |
    +--------------------------------------------------------------+
    |  7. 名字修饰（C++ 的 name mangling）                         |
    +--------------------------------------------------------------+

其中第 1 条的浮点部分就是 `hf` 那一位，实测对比见
[02_ARM寄存器与调用约定](02_ARM寄存器与调用约定.md) 第四节。

**为什么 ABI 不一致是硬错误而不是性能问题**：链接器只做一件事，把符号名和地址
对上。它不会、也不可能在中间插一段转换代码。所以两边对"参数放哪"的理解必须
字面一致，差一点就是读到垃圾。

## 三、sysroot：目标系统的根目录

编译一个程序需要三类材料，它们都必须是**目标平台的**：

    头文件      stdio.h 里的 struct FILE 布局，必须和目标 libc 一致
    库文件      libc.so / libc.a，链接时要用
    启动文件    crt1.o crti.o crtn.o，提供 _start，负责调 main 前的准备

sysroot 就是这三类东西所在的那棵目录树的根：

    <sysroot>/
        usr/include/        目标平台的头文件
        usr/lib/            目标平台的库
        lib/                动态链接器 ld-linux-armhf.so.3 也在这类地方

    编译时 gcc 会自动在这些路径前面拼上 sysroot。
    换句话说，sysroot 一换，整个"材料库"就换了一套。

**为什么必须是目标平台的**：

    你 Ubuntu 上的 /usr/include/stdio.h 里 FILE 结构体是按 x86-64 排的
              |
              | 如果拿它给 ARM 编译
              v
    编出的代码按 x86-64 的偏移去访问 FILE 的字段
              |
              | 拷到板子上，板子的 libc 按 ARM 的偏移排
              v
    fread 读出来的东西全错，而且编译期零警告

## 四、两种 sysroot 布局，本机上就有对照

    Debian / Ubuntu 的 multiarch 布局        buildroot / BSP 的独立 sysroot
    ---------------------------------        --------------------------------
    /usr/include/            架构无关         <sysroot>/usr/include/
    /usr/arm-linux-gnueabihf/include/  ARM    <sysroot>/usr/lib/
    /usr/arm-linux-gnueabihf/lib/      ARM    <sysroot>/lib/
    /usr/include/x86_64-linux-gnu/     x86

    -print-sysroot 返回 /                    返回一个很长的真实路径
    一台机器上并存多个架构的库                整棵树和板子 rootfs 一一对应
    apt install 就能装                        跟着 BSP 一起发布

    本阶段用这个                              第 2 阶段编内核模块必须用这个

本机实测，问它 libc.so 到底用哪一个：

    $ arm-linux-gnueabihf-gcc -print-file-name=libc.so
    /usr/lib/gcc-cross/arm-linux-gnueabihf/15/../../../../arm-linux-gnueabihf/lib/libc.so

    那串 ../../../.. 化简之后就是：
    /usr/arm-linux-gnueabihf/lib/libc.so

    $ gcc -print-file-name=libc.so
    /usr/lib/gcc/x86_64-linux-gnu/15/../../../x86_64-linux-gnu/libc.so
    化简后：/usr/lib/x86_64-linux-gnu/libc.so

    两个编译器各自去自己那一半，谁也不碰谁。这就是 multiarch。

## 五、-I / -L / -l 分别在管什么

    选项        管什么              什么时候起作用
    --------    ----------------    --------------------------
    -I<dir>     加一个头文件目录    预处理阶段，找 #include
    -L<dir>     加一个库目录        链接阶段，找 .so / .a
    -l<name>    链接 lib<name>      链接阶段
                                    -lm 找 libm.so，找不到再找 libm.a

    完整的一条命令：
        gcc -I./include -L./lib -o app main.c -lfreetype -lm
            ^^^^^^^^^^^ 去哪找 .h    ^^^^^^^^^^^^^^^^^^^^ 链接哪些库
                        ^^^^^^^^^^ 去哪找库文件

    三个坑：
      1. -l 要放在源文件后面。链接器从左往右扫，把 -lm 放前面时它还不知道
         谁需要 m 里的符号，扫过去就丢掉了。
      2. -lfreetype 找的是 libfreetype.so，中间那截才是名字，
         前缀 lib 和后缀 .so 是链接器自己加的。
      3. 交叉编译时 -L 千万别指到 /usr/lib，那是 x86 的库。
         第 6 章交叉编译 freetype 时会真踩到。

搜索顺序（头文件）：

    1. -I 指定的目录，按命令行出现顺序
    2. 工具链自带的目录（gcc 内建 + sysroot）
    3. /usr/include （multiarch 布局才有这一条）

    "" 引号 include 会多一步：先找当前源文件所在目录。
    <> 尖括号 include 跳过这一步。

## 六、亲手验证

先自己想：

    问题 1  怎么让 gcc 告诉你它去哪些目录找头文件？
            线索：预处理阶段（-E）加上 verbose（-v），它会把搜索列表打出来。
                  可是 -E 需要一个输入文件……能不能不建文件？
                  提示：很多工具用 - 表示"从标准输入读"。
    问题 2  怎么问它某个库的实际路径？
            线索：gcc 有一批 -print-xxx 选项，man gcc 里搜 print-file-name。
    问题 3  怎么证明 ARM 编译器和本机 gcc 用的是两套完全不同的目录？

答案：

    # 问题 1
    echo 'int main(){}' | arm-linux-gnueabihf-gcc -E -v - 2>&1 \
        | sed -n '/search starts here/,/End of search/p'
    #   ^^^^^^^^^^^^^^^ 造一个最小的 C 程序从管道喂进去
    #                                            -E 只预处理
    #                                               -v 打印内部动作
    #                                                  -  从标准输入读
    #                                     2>&1 这些信息走的是 stderr，要合并过来
    #     sed -n '/起/,/止/p'  只留这两行之间的内容

    # 问题 2
    arm-linux-gnueabihf-gcc -print-file-name=libc.so
    arm-linux-gnueabihf-gcc -print-file-name=crt1.o
    arm-linux-gnueabihf-gcc -print-sysroot

    # 问题 3
    diff <(echo 'int main(){}' | arm-linux-gnueabihf-gcc -E -v - 2>&1 | sed -n '/search starts/,/End of/p') \
         <(echo 'int main(){}' | gcc                     -E -v - 2>&1 | sed -n '/search starts/,/End of/p')
    #    ^^^^^^^^^^ 进程替换：把命令的输出当成一个临时文件名交给 diff

[判] 判据

    [ ] ARM 编译器的头文件搜索路径里有 gcc-cross 和 arm-linux-gnueabihf，
        本机 gcc 的路径里有 x86_64-linux-gnu，两边没有一条重合（除了 /usr/include）
    [ ] -print-file-name=libc.so 给出的路径化简后落在 /usr/arm-linux-gnueabihf/lib/
    [ ] file 一下那个 libc.so 指向的实体，是 ELF 32-bit ARM
    [ ] 说得出 -I、-L、-l 各自在哪个阶段起作用

    注错见红：编译时故意加一条错误的头文件路径，让它先找到 x86 的头：
        echo '#include <stdio.h>' > t.c
        echo 'int main(){return 0;}' >> t.c
        arm-linux-gnueabihf-gcc -I/usr/include/x86_64-linux-gnu -c t.c
    多半会报一堆 bits/ 相关的错。看到报错才说明"头文件必须配套"不是空话。

## 七、被谁用到

    01 章 2      交叉编译的三件事
    01 章 4.2    GLIBC 版本不匹配
    06 章        交叉编译 freetype，第一次真正自己指定 -I 和 -L
    第 2 阶段    换成 BSP 工具链，sysroot 变成一棵真实的板子根文件系统
