# 01 ELF 与程序加载

被 01 章 3、4 节用到。

## 一句话

ELF 是 Linux 下可执行文件、目标文件（.o）、共享库（.so）共用的一种文件格式。
它规定了"代码放在文件的哪个位置、加载到内存的哪个地址、需要哪些外部依赖"。

## 一、先跟 ysyx 对上

    ysyx / NPC                          Linux
    ------------------------------      ---------------------------------
    make 出来的是 .bin 裸镜像           .elf 带完整元信息
    objcopy -O binary 把 ELF 剥成裸的
    加载 = 把整个文件塞进内存 0x80000000  加载 = 内核解析 ELF 头，
    然后 pc 跳到起始地址                  按 program header 分段 mmap，
                                          再跳到 e_entry

    为什么 ysyx 能用裸 bin：             为什么 Linux 必须用 ELF：
      只有一个程序                         多进程，每个程序要有独立地址空间
      物理地址写死                         有虚拟内存和 ASLR，加载地址不固定
      没有库                               要动态链接 libc
      没有权限概念                         代码段只读可执行，数据段可写不可执行

你在 ysyx 里做的 `objcopy -O binary` 那一步，扔掉的就是本篇讲的这些东西。

## 二、ELF 的三种类型

    类型         e_type      典型文件        谁来消费它
    ---------    --------    ------------    ------------------------
    可重定位     ET_REL      hello.o         链接器 ld
    可执行       ET_EXEC     传统可执行      内核加载器
    共享库       ET_DYN      libc.so.6       链接器 + 动态链接器
                             也包括 PIE 可执行文件（见 01 章 3.3）

## 三、section 和 segment：同一份内容的两种切法

这是 ELF 最容易搞混的地方，务必分清。

    ELF 文件
    +-------------------------------------------------------------+
    |  ELF header                                                 |
    +-------------------------------------------------------------+
    |  Program header table   ---> 加载器视角：这个文件怎么进内存     |
    +-------------------------------------------------------------+
    |                                                             |
    |  实际内容（代码、数据、字符串表、符号表...）                      |
    |                                                             |
    +-------------------------------------------------------------+
    |  Section header table   ---> 链接器视角：这个文件由哪些块组成    |
    +-------------------------------------------------------------+

    section（节）    链接期的单位。.text .data .bss .rodata .symtab ...
                     链接器把多个 .o 的同名 section 合并
                     可以被 strip 掉，程序照样跑

    segment（段）    运行期的单位。PT_LOAD PT_INTERP PT_DYNAMIC ...
                     内核只看这个，一个 segment 就是一次 mmap
                     strip 不掉，掉了就跑不起来

本机实测（29 个 section 被归成 11 个 segment，其中真正装进内存的只有 2 个 LOAD）：

    section 视角（readelf -S，摘要）        segment 视角（readelf -l）
    ----------------------------------      -----------------------------------
    .interp     ld.so 的路径          \
    .dynsym     动态符号表             |
    .dynstr     动态字符串表           |
    .rel.plt    重定位表               +--> LOAD #1   R E   只读 + 可执行
    .init                              |     0x00000000 起
    .plt        跳板                   |     FileSiz 0x694  MemSiz 0x694
    .text       你的代码               |
    .rodata     字符串常量 "hi %d\n"   /

    .init_array 构造函数表            \
    .fini_array                        |
    .dynamic    NEEDED libc.so.6       +--> LOAD #2   RW    可读写
    .got        全局偏移表             |     0x0001fecc 起
    .data       g_init = 1             |     FileSiz 0x140  MemSiz 0x148
    .bss        g_bss                  /                          ^^^^^
                                             这两个数不相等，差 8 字节

    .symtab     符号表        \
    .strtab     字符串表       +--> 不属于任何 segment，运行时根本不加载
    .comment                   |     strip 命令删的就是这些
    .shstrtab                  /

**FileSiz 和 MemSiz 不相等，差的就是 .bss**。这不是 bug，是设计：

    .data    有初值的全局变量，比如 int g_init = 1;
             那个 1 必须存在文件里 --> 占文件空间，也占内存

    .bss     没初值的全局变量，比如 int g_bss;
             C 标准规定它初值为 0，全是 0 存进文件纯属浪费
             --> 只在文件里记一个"我需要 8 字节"，加载时由内核清零
             section 类型是 NOBITS，字面意思就是"没有字节"

    所以：一个几 MB 的数组 static char buf[4*1024*1024];
          放进 .bss 时可执行文件不会变大；
          写成 = {1} 就掉进 .data，文件立刻涨 4MB。
          嵌入式上这条能救命。

## 四、ELF header 的关键字段

    偏移   大小   字段          含义
    ----   ----   -----------   ------------------------------------------
    0x00   4      e_ident[0-3]  magic：7f 45 4c 46，即 '\x7f' 'E' 'L' 'F'
    0x04   1      EI_CLASS      01 = 32 位，02 = 64 位
    0x05   1      EI_DATA       01 = 小端，02 = 大端
    0x10   2      e_type        1=REL 2=EXEC 3=DYN 4=CORE
    0x12   2      e_machine     40=EM_ARM  62=EM_X86_64  243=EM_RISCV
    0x18   4/8    e_entry       入口地址（不是 main，是 _start）
    0x1c   4/8    e_phoff       program header table 在文件里的偏移
    0x20   4/8    e_shoff       section header table 的偏移

    e_machine 就是 01 章第 3 节内核拿来拒绝你的那两个字节。
    RISC-V 是 243（0xF3），你可以拿 ysyx 编出的 elf 验一下。

## 五、从 execve 到 main 的完整路径

    execve("./hello")
        |
        v
    内核 load_elf_binary()
        |
        +-- 检查 magic 是不是 \x7fELF
        +-- 检查 e_machine 是不是本机架构        <== 不对就 -ENOEXEC，01 章 3.2
        +-- 遍历 program header：
        |     PT_LOAD    每个 mmap 一次，按 Flg 设权限（R E 或 RW）
        |     PT_LOAD    MemSiz 比 FileSiz 大的部分清零（这就是 .bss）
        |     PT_INTERP  读出 /lib/ld-linux-armhf.so.3，把它也加载进来
        |
        +-- 有 PT_INTERP：把控制权交给 ld.so，而不是 e_entry
        |   没有（静态链接）：直接跳到 e_entry
        v
    ld.so（用户态）
        +-- 读 .dynamic，看到 NEEDED libc.so.6
        +-- mmap libc.so.6
        +-- 重定位：填 .got 表     <== 详见 04_静态库动态库与符号
        v
    程序的 _start（在 crt1.o 里，libc 提供）
        +-- 整理 argc / argv / envp
        v
    __libc_start_main
        +-- 跑 .init_array 里的构造函数
        v
    main()

## 六、亲手验证

先自己想：

    问题 1  怎么看一个文件的 ELF 头？（提示：binutils 里有个专门读 elf 的工具）
    问题 2  怎么分别看 section 表和 segment 表？（提示：同一个工具的两个选项，
            一个的首字母是 section，一个是 program header 的另一种叫法 layout）
    问题 3  怎么证明 .bss 不占文件空间？
            （提示：写两个程序，一个 int arr[1000000];，一个 int arr[1000000]={1};
             比较文件大小）

答案：

    arm-linux-gnueabihf-readelf -h h        # -h = ELF header
    arm-linux-gnueabihf-readelf -S h        # -S = Section headers
    arm-linux-gnueabihf-readelf -l h        # -l = program headers（segment）
    arm-linux-gnueabihf-readelf -d h        # -d = .dynamic 段，看 NEEDED

    # 问题 3 自己动手，这个实验很直观：
    cat > big1.c <<'X'
    int arr[1000000];
    int main(void){ return arr[0]; }
    X
    cat > big2.c <<'X'
    int arr[1000000] = {1};
    int main(void){ return arr[0]; }
    X
    arm-linux-gnueabihf-gcc -o big1 big1.c
    arm-linux-gnueabihf-gcc -o big2 big2.c
    ls -l big1 big2

[判] 判据

    [ ] 本机实测：big1 = 69,236 字节，big2 = 4,069,236 字节。
        差值正好 4,000,000，就是 1000000 个 int 乘 4 字节，一个字节不多不少。
    [ ] arr 所在 section：big1 是 NOBITS（.bss），big2 是 PROGBITS（.data）
        查法：先 readelf -s 找到 arr 那行的第 7 列（section 下标），
              再 readelf -S 看那个下标是哪个 section
    [ ] readelf -l 里，big1 的 RW 那个 LOAD 段 MemSiz 远大于 FileSiz
    [ ] 数得出你的 hello 有几个 PT_LOAD segment，各自权限是什么

    注错见红：把 big2.c 的 = {1} 改成 = {0}。
    编译器发现全 0，把它放回 .bss，文件又变回小的。
    本机实测这一版是 69,236 字节，和 big1 一模一样，一个字节不差。
    如果你改成 = {0} 之后文件还是 4MB，说明编译的不是你改的那个文件。

## 七、被谁用到

    01 章 3      内核在哪一步拒绝 ARM 程序
    01 章 4      .interp 和动态链接
    02 章        文件 IO 之后讲进程地址空间时还会回来
    第 2 阶段    内核模块 .ko 也是 ELF（ET_REL），insmod 时内核自己做重定位
