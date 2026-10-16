# 嵌入式 Linux 技术库（100ASK_IMX6ULL Pro）

从零开始学嵌入式 Linux，并把学到的知识落成一台可运行、可复测的设备。

本仓是**完全自足的教程库**：不需要看原视频，不需要翻原书——原书和视频的知识
已经提取进 Knowledge/ 的教程里；外部源项目作为技术参照，一层一层搭进自己的
Project/。原始资料本身放在 Sources/（不入 git），只作改写素材与最终兜底。

## 一、仓库四部分

    Sources/       原始资料库（不入 git）。原书 PDF、26 集视频字幕、外部源项目的
                   登记与章节对照，地图见 Sources/README.md。
    Knowledge/     知识库，本仓的重心。
      tutorials/     教程，按原书篇章与章号组织（第四篇应用编程 11 章、
                     第五篇驱动开发）。完整给出每条命令、每段代码，
                     手把手做实验，配判据。
      fundamentals/  基础知识与查阅手册：教程的前置知识（讲解篇，对照
                     RISC-V/ysyx 搭桥），以及原书罗列型知识点的手册
                     （手册篇：GCC 选项、Makefile 语法……）。
      labs/          课程实验与判据脚本，按教程章号组织，check.sh 自动核对。
    Project/       自己的工程：网络视频终端（路线图见 Engineering/Todo）。
      七层注册链表框架（display/input/font/ui/page/config/business）+ items
      测试项，check.sh 三套件 124 条判据。
    Engineering/   工程文档：TechReports（每个工作点一章，六节固定）/
                   Todo / Bugs。体例照搬 Loongarch_NPU_SoC 与 Efinix 两仓。

协作规则见 [AGENTS.md](AGENTS.md)；Knowledge 的体例唯一出处是
[Knowledge/README.md](Knowledge/README.md)；"提交即更新文档"的对照表在
[Engineering/README.md](Engineering/README.md)。

## 二、汲取路线

    第一来源  韦东山《嵌入式Linux应用开发完全手册》+ 配套视频 + 32 步量产工具项目
              （E:\Workspace\01_all_series_quickstart-master，只读）
              状态：应用编程前三章已按新体例重写为教程，其余逐章推进
              （排期见 Engineering/Todo/knowledge教程化路线.md）
    第二来源  边缘视觉质检终端产品级项目（付费课程，已申请软著：
              只汲取架构思想与工程方法，禁止复制其代码与文档进仓、禁止上传）
              落点：Engineering/Todo/质检业务嫁接-inspect层与产品化.md（Q 刀）

素材对照（原书 11 章框架、视频分集与字幕、各章源码目录）全部在 Sources/README.md。

## 三、开发板资源（决定哪些实验能做）

100ASK_IMX6ULL Pro，**2026-09 已到货**，上板实验从第 01 章开始就能做。

板载：

    2       用户 LED                    LED 驱动、GPIO、pinctrl 实验
    8 / 9   KEY1 / KEY2                 按键驱动、查询/中断/poll/异步通知实验
    14      板载 HDMI 口                framebuffer 显示，接普通显示器即可
    17      AP3216 光感传感器（I2C）    I2C 应用编程和驱动实验
    31      ICM-20608 六轴传感器        SPI/I2C 进阶
    7       2 路 USB HOST               插 USB 鼠标/键盘，作为 input 设备
    6       USB 转串口（CH9102）        调试串口，本仓上板唯一链路（左侧下面那个 micro-USB）
    5       USB OTG                     烧写；本仓不用 ADB（左侧上面那个 micro-USB）
    12 / 13 两个百兆网口                网络编程、NFS、网络输入
    33      RTL8723 WiFi/蓝牙
    26 / 27 512MB DDR3L + 4GB eMMC

    15      RGB TFT LCD 接口            没有屏，用 HDMI 替代
            触摸屏                       没有，用 USB 鼠标替代（同样是 /dev/input/eventX）

## 四、环境策略

日常开发在 WSL Ubuntu 里做，只有真正需要上板验证时才连板子。
环境与判据的完整规则在 [Project/doc/开发环境.md](Project/doc/开发环境.md)
与 [Project/doc/验证流程.md](Project/doc/验证流程.md)，先记三条：

    1. 第 1 阶段（应用编程）绝大部分实验在 WSL 里用 x86 gcc 跑通逻辑，
       交叉编译产物攒着，阶段末尾集中上板验一次；第 2 阶段（驱动开发）必须上板，
       要用板子 BSP 的工具链和内核源码。
    2. 故意没装 qemu-user-static：装了它 x86 上能直接跑 ARM 程序，
       01 篇"必须报 Exec format error"那条判据就失效了。
    3. 交叉工具链 glibc（2.41）比板上（2.30）新，动态产物上板会报
       GLIBC not found，上板程序一律 `-static`（教程各篇已按此写）。

## 五、进度

    [x] 仓库重构（2026-10-16）：四部分骨架、CodeReading 删除、教程化路线立项
        排期与逐章状态见 Engineering/Todo/knowledge教程化路线.md
    [ ] Knowledge 教程化
        [x] 01_HelloWorld背后没那么简单（字幕 4_1×2 + PDF 141-142；3978104）
        [x] 02_GCC编译器的使用（字幕 4_2×2 + PDF 143-153；e87e848）
        [x] 03_Makefile的使用（字幕 4_3×7 + PDF 154-165；daea10c）
        [x] 04_文件IO（e2b6214）/ 05_Framebuffer应用编程（5cdcb91）/ 06_文字显示（95b83f4）
            ——四章字幕 8+1+6 集与 PDF 166-215 全部融合,附 4_6-3 字幕补齐复核
        [ ] 07_输入系统 ～ 11_串口（待写；素材 = PDF + 源码 + TechReports 实测）
        [x] fundamentals 13 篇讲解篇（311 条判据）+ 2 篇手册篇
            （13_GCC常用选项手册 / 14_Makefile语法与函数手册，
             含原书勘误 2 条：gcc -M 落文件、-M 系真实行为）
        [ ] 02_驱动开发（未开工，前置 = BSP 工具链与内核源码）
    [ ] project（现行终点 = 网络视频终端，刀 0 起步）
        量产工具旧路线已走完并归档（TechReports 06-09，判据 73 → 124）
        判据基线：bash Project/check.sh → TOTAL 124 PASS / 0 FAIL / 0 SKIP

labs 判据基线（WSL，2026-10-16 复核）：Knowledge/labs/00_basics 十一套 +
06_text 合计 323 PASS / 0 FAIL / 5 SKIP（04 篇 1 条：本机缺 x86 32 位头；
08 篇 4 条：要 root）。

## 六、文档规则

**每一次 commit，都要在同一次 commit 里把它影响到的文档改完。**
完整的对照表在 [Engineering/README.md](Engineering/README.md)
的"项目规则：提交即更新文档"一节。两条硬约束先记在这里：

    1. 引用代码位置时行号必须准。重新 grep -n '' <文件> 对一遍，不靠记忆。
    2. 文档里出现的 PASS 数、体积、行数、耗时，一律以本机或板上实测为准。
       改完代码先跑 bash Project/check.sh，拿到的数字再写进文档。
