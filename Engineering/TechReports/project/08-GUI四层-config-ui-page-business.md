# 08 GUI 四层：config/ui/page/business 与一个能点的主页

## 一、动机

`Project/` 的层表里，ui、page、business 三行从第 01 章起就是打印一行日志的
空壳，config 目录根本不存在。第 03 至 05 章落地的 display/font/input 三层
各自能测，但没有人消费它们：程序起得来、退得出，屏幕上什么都没有。路线图
（对齐电子产品量产工具）把这批工作整体划给"项目整合"，对应 $P 的第 18 到
32 步：ui（按钮）、page（页面管理）、business（业务调度）、config（配置
文件），量产工具"不改代码换一套测试项"的能力全在 config 这一层。

第 08/09 章的 L4 产出是"AP3216 光感与调试串口做成 business 的测试项"，
测试项要有处可挂——按钮、页面、命令执行三件事先于传感器到位。本章交付
四层与一条端到端链：回放一段点击脚本，命令真的被执行，页面真的被切换。

## 二、为什么是这几步

```
C1  config 层: 文本配置解析, 缺什么走什么默认值
C2  ui 层: 按钮控件(矩形+标签+两态+命中)
C3  page 层: 注册/切换/分发, 切页必经 destroy
C4  business 层: 具体页面、命令执行、主循环
C5  main 接线: 层表加 config, main_loop 交 business
C6  判据: config/ui/page/端到端四组, 每组注错见红
```

C1 最先：page 要按配置项建按钮，business 要按配置项执行命令，配置是它们
共同的输入。C2 在 C3 之前：页面管理器切换页面时必须能整体销毁旧页的控件，
按钮的生命周期接口（create/destroy）先立住，页面的 create/destroy 才有
东西可管。C3 在 C4 之前：具体页面是 page 框架的第一个消费者，框架先于
使用者一拍，发现接口不顺时改的还是框架。C4 把三件事放进同一层：$P 的
结构正是"具体页面住在 business 层"，页面要调的命令执行、命令要读的配置
都在同一个编译单元附近。C5 是层表的一行与 main_loop 的一行，层表顺序
（config 在 page 之后 business 之前）由依赖方向决定。C6 的端到端组
把 input→page→ui→business 四层串成一条回放链，任何一环断掉都会红。

工作量由依赖关系推出，倒过来排任何一个都会返工。

## 三、每一步做了什么

### 3.1 config：解析规则与默认值

```
# 注释
[global]
font_file = /usr/share/fonts/liberation/LiberationSans-Regular.ttf
font_size = 32                # 也可写在行尾
page_timeout_ms = 0           # 0 = 等事件永不超时
[item]
name = mem
command = head -3 /proc/meminfo
```

每行一个 `key = value`，`[section]` 切小节，`#`/`;` 整行注释、行尾 `#`
注释都忽略；识别不了的行跳过。默认值策略：文件不存在、字段缺失、行写坏
三种情况都落到默认值上，产品的第一次上电（还没有 `/etc/test_gui/gui.conf`）
靠一条内置演示条目跑出非空界面；文件存在时整体清零重来，默认条目让位。
`CONFIG_FILE` 环境变量覆盖路径，判据靠它喂四份 fixture。

### 3.2 ui：按钮就是一块矩形加一个标签

```
struct ui_button
  label[64]      标签文本
  rect           外框(x,y,w,h), 与显示像素同单位
  pressed        按下态
  on_click/ctx   抬起且仍在框内才触发
  next           链表指针
```

出图依赖 display（填矩形、flush），出字依赖 font（测墨迹外框、画 UTF-8），
标签按墨迹外框居中：baseline 抬到 `(盒高-墨高)/2` 再抵掉墨迹顶。两个底色
常量 `0x303030`（静止）与 `0x707070`（按下）是判据数像素的对象；1 像素
边框 `0x909090` 把按钮从黑底上圈出来。命中测试左闭右开，与 `disp_region`
一致。`ui_button_press/release` 管按下态与回调，按下后挪出区域再抬起算
放弃：不触发回调，只回弹。

### 3.3 page：切换即"旧页 destroy、新页 create"

页面是三份函数指针：`create`（建控件画整页）/`destroy`（释放全部资源）/
`on_event`（收当前页该处理的事件）。`page_switch()` 先 destroy 当前页
再 create 新页，没有第三种状态；具体页面（住 business 层）调
`page_register()` 挂进链表，与 display/font/input 的注册形状同型。
页面上有几个按钮、点了干什么，page 层一概不知道。

### 3.4 business：页面、命令与主循环

```
主页 create: 清屏 -> 按配置项建网格按钮 -> 右下角"设置" -> draw_all
设置页 create: 清屏 -> 一行配置摘要文本 -> 右下角"返回"
命令执行: fork + execl("/bin/sh","sh","-c",command), waitpid 收退出码
主循环: input_get_event(配置超时) -> KEY_Q 按下退出 -> page_dispatch
```

布局公式写死在 `business_internal.h`：测试项按钮两列一排，"设置"/"返回"
永远在最后一行最后一格。判据脚本里的点击坐标按同一套公式手算
（320x240 单测试项时为 (82,28) 与 (238,76)），布局一改判据必须跟着改，
这个耦合是刻意的——布局是判据的一部分。页面上每个测试项按钮的 ctx 带着自己在
配置里的下标，回调里按配置执行命令，退出码进日志（`item mem rc=0`）。

### 3.5 端到端判据

`check_gui.sh` 四组。[18] 四份配置 fixture（全字段/缺字段/仅注释/不存在）
逐项对读回值。[19] 按钮的按下/回弹/点击/销毁，显存转储交给 `count.sh`
数两种底色的像素。[20] 两页互切 100 次的建毁对账加 ASan。端到端组
[21] 用 awk 生成 20 行回放：移到测试项、按下抬起、移到设置、按下抬起、
按下抬起、q，九个应用事件走完 input 线程、环形队列、page 切换、按钮
回调、命令执行整条链。

## 四、遇到的问题

### 4.1 只清条目数不清内容，默认条目漏进用户配置

**第一现场**（config_test 首跑，2026-10-04 实跑）：

```
cfg partial item0 name= only_name cmd=head -3 /proc/meminfo
```

**解读** `partial.conf` 的条目只写了 name，command 却读出了默认条目的
`head -3 /proc/meminfo`。当时的实现是"文件在就 `item_count = 0`"，
结构体里默认条目的字段还在，文件里写了 name 就盖住 name，没写的 command
沿用默认值。默认值语义是"缺什么补什么"的兜底，前提是兜底发生在解析之前
而不是解析的间隙。

**定位** 对比 `nofile`（文件不在，整份默认）与 `partial`（文件在，字段级
缺失）两条输出，残留只发生在后者，指向"部分清零"。

**根因与修法** 文件成功打开后 `memset` 整个配置结构体再解析；解析时
"识别不了的行跳过"的宽容策略保持不变。原判据为什么没覆盖到：初版判据
没有"字段级缺失"这份 fixture，是写 fixture 时把问题抓住了。

### 4.2 页面切换后上一页的像素留在屏幕上

**第一现场**（切页烟测，肉眼可见设置页右上角残留主页按钮的一角；无计数）。

**解读** 每页只画自己的东西：主页按钮、设置页文本。切页清掉的控件从
屏幕上消失，像素却留在显存里，新页没覆盖到的位置就是上一页的残影。
page 层管控件生命周期，管不了显存；显存归 display，残影归页面的
create——它是唯一知道"整页长什么样"的位置。

**根因与修法** 两个具体页面的 `create` 第一步先 `disp_fill_rect` 整屏
黑再画自己的内容。原判据为什么没覆盖到：像素级判据盯的是"画了什么"，
残影是"没画什么"，现有转储对账抓不到缺省区域，这条以肉眼烟测记录。

### 4.3 日志行的词序是判据的一部分

**第一现场**（[1] 判据首跑）：

```
FAIL  init 顺序: got [display config business ] want [display input font ui page config business ]
```

**解读** 顺序判据用 `awk '{print $(NF-2)}'` 从每行里抠层名，前提是行尾
三个词恰好是"层名 init OK"。config 首版日志把加载详情接在
`config init OK:` 后面，business 把几何与条目数接在 `business init OK:`
后面，awk 抠出来的分别是 `items=0` 和 `320x240,`。这些行在 grep
`init OK` 时照样命中，只在抠词时露馅。

**定位** 层名必须紧邻 `init OK` 是框架判据的既有约定，两个新层把它打破
了。详情是有价值的日志，去留是约定问题。

**根因与修法** 详情拆成独立一行、`init OK` 独占行尾：`config <路径>: ...`
一行、`config init OK` 一行；business 同样拆成两行。七层的 `init OK`
行重新全部满足"倒数第二个词是层名"。原判据为什么没覆盖到：旧判据只锁
旧六层，新层首跑时才第一次被这条约定约束。

### 4.4 LOG_LEVEL=0 时日志参数变成未使用变量

**第一现场**（[5] 判据，`make CFLAGS_EXTRA=-DLOG_LEVEL=0`）：

```
business/business_manager.c:70:32: error: variable 'fb' set but not used
    [-Werror=unused-but-set-variable]
business/business_manager.c:46:39: error: unused parameter 'name'
    [-Werror=unused-parameter]
```

**解读** 日志宏在 `LOG_LEVEL=0` 时整体展开成 `do {} while (0)`，宏参数
不求值：只在日志参数里出现的 `fb`、`name` 此刻成了未使用变量，`-Werror`
把编译打断。第 02 章引入这套宏时本仓还没有"只进日志的局部变量"。

**定位** 两处都在 business 层新代码里。修法要同时满足两个编译配置：
正常级别下变量被日志使用，零级别下被 `(void)` 使用。

**根因与修法** 日志专用的变量与参数后跟 `(void)` 压制，注释写明缘由。
`LOG_LEVEL=0` 判据从此从"日志关得掉"升级为"关掉日志也必须编译干净"。
原判据为什么没覆盖到：它当时只检查运行行为，管不到这个配置下的编译。

### 4.5 ASan 注错第一版选错了坏点

**第一现场**（[20r2] 首跑）：注错把切页的 `g_cur->destroy()` 换成
`(void)0;`，ASan 泄漏报告数仍是 0，注错没红。

**解读** 切页不销毁，旧页按钮留在 ui 层链表上，引用一直在——ui_exit
的总清理循环会把它们一个一个 free 掉。ASan 看到的"泄漏"是失去所有引用
的分配，留在链表上的按钮恰好不满足这个定义。判据真正要红，得让 free
本身失效。

**定位** page 层的 `destroy` 缺失由 [20r] 的计数判据（切几轮后按钮数
不归一）抓着；ASan 组要盯的是 ui 层的释放路径。

**根因与修法** 注错目标改成 `ui_button_destroy` 里的 `free(btn);`——
摘链不释放，分配才真正失去引用，LeakSanitizer 如期报数。原判据为什么
没覆盖到：首版注错把"资源未释放"与"引用未清除"混为一谈，ASan 只认前者。

## 五、结果

测量方法：`wsl bash Project/check.sh`。

| 测量项 | 改动前 | 本轮后 |
|---|---|---|
| `Project/check.sh` 总判据 | 90 PASS（07 章后） | 124 PASS / 0 FAIL（四层占 34 条） |
| 层表 | 6 层（三个空壳） | 7 层（config/ui/page/business 有实现） |
| 交付源码 | — | 四层 13 文件 1280 行（含 items 两程序） |
| 端到端链 | 无 | 回放 9 个事件：点击执行命令、两页切换、q 退出 |

端到端（2026-10-04 实跑，320x240 假屏，回放脚本）：`item mem rc=0`
出现 1 次（`head -3 /proc/meminfo` 经 `/bin/sh` 执行、退出码 0）；
`page settings created` 1 次、`page main created` 2 次（初始一次、
返回一次）；`business loop end events=9`；退出码 0。ASan 下同一脚本
无泄漏报告；tsan 下无竞争报告。

配置默认值四象限（[18] 实跑输出）：全字段 fixture 逐项读回
（`size=32 timeout=1500 items=3`）；缺字段条目命令为空
（`name=only_name cmd=`）；仅注释文件全默认且无条目；文件不存在走
内置演示条目（`items=1`）。

已知误差与不确定：4.2 的残影以肉眼烟测记录，没有像素级判据；设置页
当前只读展示配置，没有可调项——设置项的业务（分辨率、报警阈值）属于
网络视频终端路线，本章不预做。

## 六、还欠什么

一笔：主页测试项网格在配置超过 8 条（`CONFIG_ITEMS_MAX` 16 的一半）时
会排到屏幕外，当前配置最大 3 条碰不到。等真实测试项数量接近上限时再
加翻页或滚动，提前做没有数据支撑。
