# project 逐行精读

对应 `project/` 的全部交付源码、脚本与输入 fixture，共 8 篇。
**一个层（或一个构建/判据单元）一篇**：同一层的 manager、内部头与后端互相
咬合，拆成每文件一篇会把一条执行路径切成几段；篇内每个被覆盖文件仍有自己的
行号区间，代码增删时定位不受影响。

当前实现包括六层生命周期骨架、display 真/假后端、font builtin/FreeType 后端
和 input evdev/replay 后端。为什么采用这些形状，见
[`../../TechReports/project/`](../../TechReports/project/) 的 01—05 章。

## 推荐阅读顺序

```
common -> display -> font / input -> 空壳三层与 main
            |          |                  |
            +-- unittest + fixture ------+
Makefile 负责构建，三个 check 脚本从外部守住上述关系
```

## 篇目

| 对应文件 | CodeReading | 行数 | 定位 |
|---|---|---:|---|
| `include/common.h`、`common.c` | [common](common-逐行精读.md) | 101 | 错误码、日志宏、日志落文件 |
| `display/disp_manager.h/.c`、`memdisp.c`、`framebuffer.c` | [display 层](display层-逐行精读.md) | 451 | 画布、真假后端、位段拼色与 alpha 混色 |
| `font/font_manager.h/.c`、`font_internal.h`、`font_builtin.c`、`font_freetype.c` | [font 层](font层-逐行精读.md) | 583 | 严格 UTF-8、provider 链、排版与借用契约 |
| `input/input_manager.h/.c`、`input_internal.h`、`evdev.c`、`replay.c` | [input 层](input层-逐行精读.md) | 631 | SYN 帧、坐标状态机、能力打分与回放 |
| `main.c`、`ui/`、`page/`、`business/` 各 h/c | [空壳三层与 main](空壳三层与main-逐行精读.md) | 220 | 层表顺序启停与失败回滚 |
| `unittest/` 全部（三个 _test.c、count.py/sh、两个回放 fixture） | [unittest](unittest-逐行精读.md) | 363 | 单层测试与独立计数 |
| `Makefile` | [Makefile](Makefile-逐行精读.md) | 123 | x86/ARM 两棵产物树、FreeType 隔离构建 |
| `check.sh`、`check_core.sh`、`check_font_input.sh` | [check 脚本](check脚本-逐行精读.md) | 500 | 73 条判据与注错见红 |

## 维护规则

1. 上表每个路径只能出现在一篇里；新增源文件归入所在层的那一篇，同时更新
   本表的行数列。
2. 每篇正文的行号区间从每个文件第 1 行连续覆盖到末行；空行也包含在相邻
   区间内。
3. `rg --files project` 出现新交付文件时，同一改动中把它的内容并入对应层
   篇目并订正行号。
4. build 产物不进精读；输入 fixture 决定状态机判据，随 unittest 篇覆盖。

## 当前状态

ui、page、business 仍只有生命周期骨架；display 两个后端的 flush 在单缓冲
模型下为空。font 与 input 已不是空壳：前者具备严格 UTF-8、builtin/FreeType
与 alpha 绘制，后者具备 replay/evdev、SYN 帧聚合与相对/绝对坐标。
input 层有一项已登记未修的缺陷（同帧 pointer+key 丢键，见
[`../../Bugs/01-同帧指针与普通键丢事件.md`](../../Bugs/01-同帧指针与普通键丢事件.md)），
精读把该分支的现状如实写出，不做修好后的描述。
