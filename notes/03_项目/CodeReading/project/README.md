# project 逐行精读

对应 `project/` 的全部交付源码、脚本与输入 fixture，共 12 篇。
**一个层（或一个构建/判据单元）一篇**：同一层的 manager、内部头与后端互相
咬合，拆成每文件一篇会把一条执行路径切成几段；篇内每个被覆盖文件仍有自己的
行号区间，代码增删时定位不受影响。

当前实现包括七层生命周期骨架（config/ui/page/business 已有实现）、display
真/假后端、font builtin/FreeType 后端、input evdev/replay/netinput 三后端
与两个 items 测试项程序。为什么采用这些形状，见
[`../../TechReports/project/`](../../TechReports/project/) 的 01—09 章。

## 推荐阅读顺序

```
common -> display -> font / input -> config / ui / page / business -> main
            |          |                  |                                |
            +-- unittest + fixture -------+   items 两个测试项 -------------+
Makefile 负责构建，三个 check 脚本从外部守住上述关系
```

## 篇目

| 对应文件 | CodeReading | 行数 | 定位 |
|---|---|---:|---|
| `include/common.h`、`common.c` | [common](common-逐行精读.md) | 101 | 错误码、日志宏、日志落文件 |
| `display/disp_manager.h/.c`、`memdisp.c`、`framebuffer.c` | [display 层](display层-逐行精读.md) | 451 | 画布、真假后端、位段拼色与 alpha 混色 |
| `font/font_manager.h/.c`、`font_internal.h`、`font_builtin.c`、`font_freetype.c` | [font 层](font层-逐行精读.md) | 583 | 严格 UTF-8、provider 链、排版与借用契约 |
| `input/input_manager.h/.c`、`input_internal.h`、`evdev.c`、`replay.c`、`netinput.c` | [input 层](input层-逐行精读.md) | 1035 | SYN 帧、坐标状态机、读取线程与环形队列、网络输入源 |
| `config/config.h/.c` | [config 层](config层-逐行精读.md) | 211 | 文本配置解析、四象限默认值 |
| `ui/ui_manager.h/.c` | [ui 层](ui层-逐行精读.md) | 254 | 按钮控件、两态命中、像素级判据对象 |
| `page/page_manager.h/.c` | [page 层](page层-逐行精读.md) | 120 | 注册/切换/分发，切页即 destroy+create |
| `business/` 五个文件、`items/ap3216_read.c`、`items/serial_loop.c` | [business 层与测试项](business层与测试项-逐行精读.md) | 695 | 具体页面、命令执行、布局公式、I2C/串口测试项 |
| `main.c` | [main](main-逐行精读.md) | 101 | 七层层表、顺序启停与失败回滚 |
| `unittest/` 全部（七个程序、count.py/sh、serial_pty.py、回放与配置 fixture） | [unittest](unittest-逐行精读.md) | 700 | 单层测试、协议对端与独立计数 |
| `Makefile` | [Makefile](Makefile-逐行精读.md) | 137 | x86/ARM 两棵产物树、items 目标、FreeType 隔离构建 |
| `check.sh`、`check_core.sh`、`check_font_input.sh`、`check_gui.sh` | [check 脚本](check脚本-逐行精读.md) | 941 | 124 条判据与注错见红 |

## 维护规则

1. 上表每个路径只能出现在一篇里；新增源文件归入所在层的那一篇，同时更新
   本表的行数列。
2. 每篇正文的行号区间从每个文件第 1 行连续覆盖到末行；空行也包含在相邻
   区间内。
3. `rg --files project` 出现新交付文件时，同一改动中把它的内容并入对应层
   篇目并订正行号。
4. build 产物不进精读；输入 fixture 决定状态机判据，随 unittest 篇覆盖。

## 当前状态

七层全部有实现：display/font/input 承接第 03-07 章（input 已线程化并挂上
netinput），config/ui/page/business 承接第 08 章（GUI 四层与端到端链），
items 两个测试项承接第 09 章。input 层有一项已登记未修的缺陷（同帧
pointer+key 丢键，见
[`../../Bugs/01-同帧指针与普通键丢事件.md`](../../Bugs/01-同帧指针与普通键丢事件.md)），
精读把该分支的现状如实写出，不做修好后的描述。display 两个后端的 flush
在单缓冲模型下为空。
