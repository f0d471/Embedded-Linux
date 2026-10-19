# project：视觉终端（在建）

在 100ASK_IMX6ULL Pro 上逐层长出的一台设备。目标是**视觉终端**：监看与质检
两个业务共用一条流水线，路线图在
[../Engineering/Todo/学习与项目路线.md](../Engineering/Todo/学习与项目路线.md)。

当前状态：七层注册链表框架 + items 测试项全部有实现并上板验证过，判据基线
**124 PASS / 0 FAIL / 0 SKIP**（`bash check.sh`）。目标十一条层，还差
video / net / inspect / record 四层；视频链路从刀 0 起步，尚未开工。

为什么用"结构体 + 函数指针 + 链表注册"这个骨架：它是 Linux 子系统的通用形状
（`file_operations`、`platform_driver` 同形），UVC 与 CSI 两个摄像头后端将来挂
同一条链表，切后端时上层代码 diff 为空——注册链表在这里第一次有真实理由。

## 构建速查

    make                                x86 版，产物 build/x86/product_tool
    make CROSS=arm-linux-gnueabihf-     ARM 版；首次自动隔离构建静态 FreeType 2.10.2
    make CROSS=arm-linux-gnueabihf- LDFLAGS=-static
                                        上板产物必须静态（见 doc/开发环境.md 第 3 节）
    make test                           编 unittest 与 items 全部可执行
    make clean / make distclean         清当前架构 / 清整个 build/
    bash check.sh                       判据三套件总入口（见 doc/验证流程.md）

构建细节（wildcard 收源、unittest 与 items 为何不进 SUBDIRS、FreeType staging）
都写在 Makefile 注释里，本 README 不重复。

## 目录

| 目录 | 内容 | 可改性 |
|---|---|---|
| [display/](display/) | 显示管理：注册链表 + framebuffer/memdisp 真假两后端，画点填矩形 | 可改 |
| [input/](input/) | 输入管理：replay/evdev/netinput 三 provider + 专职读取线程与 32 槽环形队列 | 可改 |
| [font/](font/) | 文字：builtin 点阵 + FreeType 两后端，严格 UTF-8 | 可改 |
| [ui/](ui/) [page/](page/) [config/](config/) [business/](business/) | GUI 四层：按钮两态、页面切换（destroy+create）、INI 配置、业务页面与命令执行 | 可改 |
| [items/](items/) | 独立小工具（ap3216_read / serial_loop），只链 common.o，上板单发 | 可改 |
| [unittest/](unittest/) | 各层单测、回放 fixture、板测辅助（count.sh / serial_pty.py 等），独立链 main | 可改 |
| [include/](include/) | common.h：LOG/ERR、`log_redirect` 声明 | 可改 |
| build/ | 产物树 `build/<arch>/…`，生成物 | 不手改，make 维护 |
| [doc/](doc/) | 规范约束文档（开发环境 / 验证流程） | 规则类，改动即全仓约束变化，慎改 |
| check*.sh | 判据三套件：check.sh 汇总 check_core / check_font_input / check_gui | 判据增删必须同步 PASS 数 |

**加一个新层只改两处**：Makefile 的 `SUBDIRS` 行、main.c 的 `g_layers` 表。
新增 `.c` 到任何已列出的子目录不需要改 Makefile（wildcard 收源）。

## 硬性规则

1. **上板产物必须静态链接**：WSL 交叉工具链 glibc 2.41，板上 buildroot glibc 2.30，
   动态产物上板一行代码没跑就报 `version 'GLIBC_2.xx' not found`。
2. **unittest 与 items 的 main 不进 SUBDIRS**，否则和 main.c 的 main 撞车。
3. **business 日志 `init OK` 必须独占行尾**——判据 [1] 的 awk 提取硬约定，改日志
   格式必须连判据一起改。
4. **provider 致命错误走 `g_error` 穿透队列**：把"读坏"和"读完"合并会丢退出码
   判据（畸形回放必须退出码 2）。
5. 本 README 只写当前状态；"这段代码为什么长这样"在 Engineering/TechReports
   对应章。
