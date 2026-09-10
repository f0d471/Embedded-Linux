# 业界对接路线：从内核驱动到推理 runtime

这份文件回答一个问题：**照现在这条路线学下去，能不能拿到嵌入式方向的实习，
以及如果不能，要补什么。**

它和同目录的 [`项目路线图-对齐电子产品量产工具.md`](项目路线图-对齐电子产品量产工具.md)
分工不同：那一份回答"`project/` 这棵树往哪长"，是仓内的施工图；
这一份回答"这棵树长成了之后，对外值多少钱"，是仓外的对接图。
两份文件的第一期有交集，交集处在第四节写明。

结论先写在这里，后面是依据：

> **量产工具这个项目不适合当求职主项目，Loongarch_NPU_SoC 才是。
> 嵌入式 Linux 不是目标，是给那个 SoC 补一条通往 Linux 的软件路的工具。
> 目标岗位不是"嵌入式软件开发"，是端侧芯片公司的 NPU 驱动 / runtime / 工具链。**

## 一、诊断：量产工具离真实岗位有多远

2026-09-08 检索了猎聘、智联、牛客、LINUX DO 上的在招 JD（来源见第七节），
把高频硬指标和 `06_实战项目/01_电子产品量产工具` 成品版
（`32_improve_touch`，真实代码约 1750 行）逐条对照：

| JD 高频硬指标                                         | 量产工具覆盖情况                   |
| ------------------------------------------------ | -------------------------- |
| Kernel / Bootloader / RootFS / Device Tree 定制    | 没有。纯用户态程序，一行不进内核           |
| 写或移植 Linux 驱动（i2c / spi / camera / GPIO）         | 没有。板载 AP3216、ICM20608 一个没碰 |
| Yocto / Buildroot 构建发行版，BitBake / Layer / Recipe | 没有。只有一个递归 Makefile         |
| 交叉编译、ARM 平台、Git                                  | 覆盖                         |
| 多线程、socket、串口 / TCP / UDP                        | 覆盖，但只到 `recvfrom` 那一层      |
| 模型量化 INT8/FP16，ONNX / TVM / NCNN / RKNN 部署       | 没有                         |

也就是说：**BSP 驱动岗要的它一条不沾，应用岗要的它沾了但浅。**

另外它作为"量产工具"名不副实：没有 OTA、没有看门狗、没有崩溃恢复、
没有测试结果上报和留档。真产线工具这些才是主体。
它的配置解析器还有一个已实证的缺陷，记录在第六节。

## 二、赛道选择：为什么不走通用嵌入式 Linux

走这条赛道，竞争者是从大二就开始写 STM32 加 FreeRTOS 加 Linux 驱动的人。
本仓当前进度是第 02 章文件 IO。**在这条赛道上是落后的，而且是拿短板比长板。**

手上真正稀缺的牌在另一个仓：

    Loongarch_NPU_SoC
      自研 SoC + 五个计算原语引擎（GEMM / matvec / LaCC / LRE / VSE）
      自定义标量 FP 指令扩展，geometry 端到端 -89.3%
      3DGS 边缘渲染，整帧 55.7s -> 11.3s
      实测出瓶颈在总线不在计算（MI 占 87%，阵列忙 2.6%）

这张牌在家电、工控、路由器的嵌入式岗一分不值，那边只关心会不会调 i2c。
它唯一能打满的地方是端侧芯片公司的软件栈岗位，JD 原文形态是：

> 基于自研 AI 工具链（编译器、量化器、Runtime、Profiler）完成客户模型的
> 端到端部署；定位功能、性能及精度问题。要求 C++/Python、Linux、模型量化、
> 算子部署到 NPU / DSP / GPU / FPGA。

这类岗位面试必问"NPU 里面怎么算的、为什么这个算子在板上比理论慢 3 倍"。
多数候选人只能答"我调了 RKNN 的 API"。能画阵列结构、能讲 FP32 尾数乘为什么
吃 DSP、能拿出实测 roofline 的人，差异是碾压性的，且无法靠背八股速成。

**所以缺口只有一个：硬件侧满配，Linux 软件侧是空的。这份 Todo 就是补这一半。**

## 三、总切分

三期，一期在本仓做，二三期回 SoC 仓做。

    一期  IMX6ULL 上写真正的内核驱动 + Buildroot 根文件系统
          目的：拿门票。把第一节表里三个"没有"消掉
          周期：约 3 周   落点：本仓 labs/ 与 project/

    二期  自研 SoC 跑起 Linux，GEMM 加速器做成设备树节点 + 驱动
          目的：差异化。这是别人没有的项目
          周期：数周，不确定   落点：Loongarch_NPU_SoC 仓

    三期  runtime 层：ONNX 模型 -> 算子映射到自研加速器 -> 不支持的回落 CPU
          目的：把 JD 里"编译器、量化器、Runtime"那套做出最小实现
          周期：待定   落点：Loongarch_NPU_SoC 仓

**一期做完就可以投递，不要把二期当成投递的前置条件。**
简历上写 SoC 当主项目、写一期当 Linux 能力证明，足够拿到面试。
二期是拿来在面试里讲的，做到哪讲到哪，哪怕只跑通 U-Boot 和内核起来那一步。

## 四、一期 spec

### 4.1 要解决什么

在 100ASK_IMX6ULL Pro 上，从设备树到应用打通一条完整的纵向通路，
被驱动对象选板载 AP3216 光感（i2c1 上，本仓 README 第三节已确认存在）。

选 AP3216 而不选 LED 的理由：它同时用到 i2c 子系统、中断、
以及"数据不是随时有"这个特性，能把 `poll` 那条路径逼出来。
LED 只能验到 GPIO 和字符设备，练不到阻塞读。

### 4.2 切分

    刀 1  设备树
          在 arch/arm/boot/dts 下给 &i2c1 加一个节点
          配 compatible / reg / pinctrl / interrupt-parent / interrupts
          判据见 4.3

    刀 2  最小 platform_driver
          of_match_table 匹配上面那个 compatible
          probe 里只打一行 printk，先确认匹配链路通了

    刀 3  字符设备
          alloc_chrdev_region + cdev_add + class_create + device_create
          open / release / read，read 里同步读一次 i2c 寄存器

    刀 4  中断与阻塞读
          request_irq 上半部只唤醒等待队列
          workqueue 下半部读 i2c（i2c 传输会睡眠，不能在中断上下文里做）
          read 改成阻塞：没有新数据就 wait_event_interruptible
          实现 poll，让用户态可以 select

    刀 5  mmap
          分配一块 DMA 一致性内存，mmap 给用户态
          这一刀在一期没有实际用处，是给二期铺路：
          二期的加速器要靠 mmap 零拷贝传权重，形状先在这里练出来

    刀 6  Buildroot
          用 Buildroot 构建根文件系统，把上面的驱动做成一个 package
          不用 Yocto：Buildroot 一两天能上手，Yocto 太重，
          而 JD 里两者是并列出现的，先拿下便宜的那个

    刀 7  接进 project/
          量产工具那一格 ap3216c 按钮，真的去读这个驱动
          依赖：project/ 的 display 与 input 层要先落地（第 03、05 章）
          所以这一刀排在最后，且可能跨到十月

### 4.3 判据

按本仓规矩，每条判据都要能注错见红。**写完判据先故意改坏一处，
看它红一次，再改回来。** 没红过的判据不算数。

| # | 判据 | 注错方式 |
|---|---|---|
| 1 | `ls /sys/bus/i2c/devices/` 下出现新节点 | 把 dts 里 reg 地址改错，节点应消失 |
| 2 | `dmesg` 里有 probe 的那行 printk | 把 compatible 字符串改掉一个字符 |
| 3 | `/dev/ap3216c` 存在，主设备号与 `/proc/devices` 一致 | 注释掉 device_create |
| 4 | 读一次返回的字节数等于结构体大小，不是 -1 | 让 read 返回 0，判据必须失败 |
| 5 | 遮住传感器再读，数值有可观测变化 | 这条是 L1 性质，只建立事实基础 |
| 6 | 阻塞读：无新数据时进程停在 D/S 态，`ps` 可见 | 把 wait_event 去掉，进程会空转 |
| 7 | `poll` 超时返回 0，有数据返回 1 | 不实现 poll，应退化成永远返回 POLLIN |
| 8 | rmmod 后 `/dev/` 下节点消失且 `lsmod` 无残留 | 漏掉一个 cdev_del，rmmod 应报错或 oops |
| 9 | Buildroot 出的 rootfs 里驱动自动加载 | 从 package 里去掉 modules 安装步骤 |

判据 1 到 8 用一个脚本自动跑，形状照 `project/check.sh`：
每组正判据配一次注错见红，输出 PASS/FAIL 计数。
脚本落点 `labs/08_i2c_driver/check.sh`（章号待定，见 4.4）。

**数字都要实跑。** 上表里没有写任何具体数值，因为一条都还没跑过。
做完之后回来把实测值补进来，别照抄任何博客。

### 4.4 与本仓既有路线的关系

一期不是插队，它落在既有路线图第四节那张表的第 08 行：

> 08 I2C / 09 串口 | 无新层 | 无对应 | 板载 AP3216 光感和调试串口，可作为 business 的测试项

差别在于：**原计划是用户态 i2c（`/dev/i2c-1` 加 ioctl），现在改成自己写内核驱动。**
这是有意的偏离，理由是第一节那张对照表 —— 用户态 i2c 在 JD 里不值钱，
内核驱动是硬指标。

代价是它把第 02 章驱动开发的内容提前了。可以接受：
应用编程后面几章（06 网络、07 多线程）在 ysyx 和 SoC 仓已有等价经验，
不是瓶颈，可以边做驱动边补。

`labs/` 目录编号按主线章号走，这一期先占 `labs/08_i2c_driver/`。

## 五、两条顺手做的快路

**其一，不用 RKNN 自己写 INT8 算子。**
所有人简历都写"用 RKNN 部署 YOLOv5"，这是负分项。
写"自己实现 conv/gemm 的 NEON 内核并做 INT8 量化，对比 RKNN 慢 X 倍，
瓶颈定位在 Y"是正分项。roofline 分析这活在 SoC 仓已经做熟。
硬件可以用 IMX6ULL（Cortex-A7 带 NEON），不必买新板。

**其二，投递方向别撒网。**

    目标公司   地平线、寒武纪、瑞芯微、爱芯元智、黑芝麻、算能，
               以及做端侧芯片的初创
    搜索关键词 NPU 驱动 / AI 编译器 / runtime / 异构计算 / SoC 软件
    不要搜     嵌入式软件开发

## 六、顺带记录：量产工具的一个已实证缺陷

读 `06_实战项目` 源码时发现，`config/config.c` 的 `ParseConfigFile()`
遇到空行会凭空生成一个空名字的配置项：空行既不是 `#` 注释，
`sscanf` 又匹配 0 项，但 `g_iItemCfgCount++` 照样执行。

2026-09-08 把 `config.c` 抠出来在 WSL 上单独编译实测（`gcc 15.2.0`），
配置文件写三行、中间一个空行，输出：

    count = 3
      [0] name="led" touch=1
      [1] name="" touch=0          <- 凭空多出来的
      [2] name="wifi" touch=0

同一个函数还有第二个坑：`ITEMCFG_MAX_NUM` 是 30，
但解析循环里没有任何边界检查，配置文件写到第 31 行就是数组越界写。

另有一条并发缺陷：`input/input_manager.c` 的 `GetInputEvent()` 在
`pthread_cond_wait` 之后用 `if` 而不是 `while` 重查缓冲，
虚假唤醒时返回 -1。POSIX 明确允许 spurious wakeup，标准写法是 while 循环。
它靠上层 `MainPageRun` 一句 `if (error) continue;` 兜住了，所以看不出毛病。

**这三条是本仓 L2 改造实验的现成素材。**
第 07 章多线程做 input 层时，把 while 那条作为判据写死；
项目整合做 config 层时，把"配置文件插一个空行，按钮数必须不变"写成判据。
照抄 `$P` 的代码会把这三个缺陷一起抄进来。

## 七、来源

2026-09-08 检索，均为公开在招信息与社区讨论：

- 猎聘 嵌入式 LINUX 驱动软件开发工程师 <https://www.liepin.com/zpqrslinuxqdrjkfgcsyaew7vl/>
- 猎聘 嵌入式开发实习生 <https://www.liepin.com/zpqrskfsxs6n3h/>
- 猎聘 资深 Linux 嵌入式研发工程师（Yocto / BSP / 设备树）<https://www.liepin.com/job/1983957181.shtml>
- 智联 芯片平台系统 / 驱动开发（Linux / BSP）<https://www.zhaopin.com/jobdetail/CCL1307987640J40845294903.htm>
- CSDN AI 嵌入式方向求职要求拾例 <https://blog.csdn.net/weixin_40314713/article/details/146986733>
- LINUX DO 国产端侧芯片初创招 AI Infra / 编译器 / runtime / 嵌入式实习 <https://linux.do/t/topic/2502009>
- 爱测社区 寒武纪实习生岗位内推 <https://ceshiren.com/t/topic/35845>
- 牛客 26 届嵌入式软件暑期实习简历讨论 <https://www.nowcoder.com/feed/main/detail/5bf621be5f2e403288aeb858eb66d52a>

## 八、这份文件什么时候删

按 [`../README.md`](../README.md) 的流转规则，`Todo/` 里的文件完成后删除。

这一份的删除条件是**一期七刀全部完成且判据全绿**。
届时把第四节搬进 `TechReports/project/` 作为一章，
第二节的赛道判断和第五节的投递方向搬进 `refs/`（它们不是工程内容），
然后删掉这个文件。二三期属于 SoC 仓，不在这里跟踪。

进度：

    [ ] 刀 1 设备树
    [ ] 刀 2 最小 platform_driver
    [ ] 刀 3 字符设备
    [ ] 刀 4 中断与阻塞读
    [ ] 刀 5 mmap
    [ ] 刀 6 Buildroot
    [ ] 刀 7 接进 project/
