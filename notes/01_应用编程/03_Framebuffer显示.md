# 03 Framebuffer 显示

    PDF     第 174-181 页（目录页 165-172），第四篇第 5 章
    视频    4_5-1 一集，14 分钟。字幕在 E:\Workspace\Temp\新建文件夹\
            （同一个文件夹里另外 5 集是第 04 章文字显示的），分集表见 refs/章节对照表.md
    源码    $Q\04_嵌入式Linux应用开发基础知识\source\07_framebuffer\show_pixel.c
    产出    project/ 的 display 层 —— 这一层由你自己写，本章第 6 节只给规格和验收判据

---

## 0 这份笔记怎么用

### 0.1 定位：PDF 8 页、视频 14 分钟，真正新的只有两件事

这一章的 8 页 PDF 里，有 3 页是 `open` / `ioctl` / `mmap` 的手册抄录，
上一章已经讲透。视频 14 分钟，其中 1 分钟在总结这三个函数。
剩下的内容压缩一下，只有两件事是新的：

    1. 显示 = 往一块内存里写。有一个硬件在不停地读这块内存，送到屏幕上
    2. 屏幕上的 (x, y) 对应这块内存的哪几个字节，这几个字节怎么拼出颜色

这两件事都不难，所以这一章的份量不在"讲清楚"，而在"验清楚"。
PDF 和视频都停在"屏幕上出现一条红线"，但板子上有几件事它们没说，
不知道的话，你写的程序会时灵时不灵：

- 出厂系统里有个 GUI 一直开着，它也在往同一块内存里写（第 5.1、5.2 节）
- 显存有 32 MiB，一屏只有 2.4 MiB，`cat /dev/fb0` 读出来的是前者（第 8 节坑 6）
- 从显存里**读**比往显存里**写**慢 10 倍（第 5.5 节）
- 插上 HDMI 显示器，驱动会按显示器的能力改分辨率，本板实测连 bpp 都从 32 变成了 16（第 5.6 节）
- PDF 说 `fb_fix_screeninfo`"很少用到"，但行宽和显存大小都在它里面（第 2.3、3.3 节）

还有一件事决定了这一章怎么做实验：**WSL 里没有 `/dev/fb0`**（第 2.2 节实测），
所以本章分两条腿走：

    电脑上   用一个普通文件冒充显存，练地址公式和颜色拼法（第 3、4 节）
    板子上   跑真的 /dev/fb0，用回读显存来验证（第 5 节）

回读是这一章最值钱的方法：**不看屏幕也能判对错**。
把显存读回来数红色像素有几个、在哪个位置，比盯着显示器看一条线准得多。

### 0.2 过滤表：1 集视频看什么、跳什么

| 集 | 时间段 | 看不看 | 内容 |
|---|---|---|---|
| 4_5-1 | 0:08-1:47 | **重点** | framebuffer 是一块内存，LCD 控制器"周而复始"地从头读到尾。本笔记第 2.1 节 |
| | 1:47-3:43 | **看** | 从 (x, y) 推出偏移：前面有 y 行，这一行前面有 x 个。本笔记第 3.1 节 |
| | 3:57-5:20 | **看** | 32/24/16 bpp 三种颜色格式，24bpp 实际也占 4 个字节。本笔记第 4.1 节 |
| | 5:20-6:31 | 快进 | 总结 open / ioctl / mmap。02 章讲过 |
| | 6:51-7:54 | **重点** | 可变参数和固定参数；`fb_bitfield` 的 offset/length。他说"我们没有去看 bitfield，用惯例" —— 本笔记第 4.3 节就是不用惯例的写法 |
| | 7:54-8:34 | **看** | `FBIOPUT_VSCREENINFO` 能改分辨率，"嵌入式里一般不这么做" —— 本板插 HDMI 时驱动自己会改，见第 5.6 节 |
| | 8:34-9:19 | **看** | mmap 的大小 = xres × yres × bpp / 8。本笔记第 3.4、5.4 节讲这个数和 `smem_len` 不是一回事 |
| | 9:19-11:16 | **看** | 描点函数的推导，`line_width` 和 `pixel_width` 两个量 |
| | 11:16-13:06 | **重点** | 888 转 565：红取高 5 位、绿取高 6 位、蓝取高 5 位。本笔记第 4.2 节 |
| | 13:06-14:01 | 看结果 | 上机：整屏清白 + 中间一条红线。他用 NFS 跑，本仓走串口（第 5 节） |
| | 14:01-14:15 | **重点** | "出厂一般有 GUI，可能要去掉" —— 只有一句话。本板实测见第 5.1-5.3 节 |

字幕是自动识别的，检索时要换词：

    flame buffer / flow buffer / fn buffer / film buff / flabuffer = framebuffer
    l7 d / l c d46                  = LCD / LCD 是 16          bp / b p p / bbp = bpp
    vr / var 可变的                  = var                       卫浴 / bf 卫浴  = bitfield
    l control / ile control         = ioctl                     a map  = mmap
    描点 / 瞄点                      = 描点                       五味   = 五位
    日光图                           = Ubuntu                    建设 linux = 嵌入式 Linux
    sy / s方向                       = xy / x 方向                纸     = 值

### 0.3 PDF 那一侧的过滤表

| PDF 小节 | 页 | 看不看 | 怎么用 |
|---|---|---|---|
| 5.1 LCD 操作原理 | 174-175 | **看** | 图 5.1 是全章骨架（显存、LCD 控制器、屏幕三块），图 5.2 是地址公式，图 5.3 是三种颜色格式 |
| 5.2.1 open 函数 | 175-176 | 跳 | 02 章讲过 |
| 5.2.2 ioctl 函数 | 176-177 | 看一次 | **返回值那句写错了**，见下 |
| 5.2.3 mmap 函数 | 177-178 | 跳 | 02 章第 5 节、[基础 07] 讲过。标题自己写着"待后续修正" |
| 5.3.1-5.3.2 打开设备、获取参数 | 178-179 | **看** | 图 5.7、5.8 是两个结构体。"fix 很少用到"这句不要信，见第 2.3 节 |
| 5.3.3 映射 Framebuffer | 179-180 | **重点** | 配第 3.3、3.4 节读 |
| 5.3.4 描点函数 | 180-181 | **重点** | 配第 3、4 节读 |
| 5.3.5、5.4 上机实验 | 181 | 看 | "以后会补充禁止 GUI 的方法" —— 没有补。本板做法见第 5.3 节 |

PDF 里查得到的两处错误：

**第一处，5.2.2 节 ioctl 的返回值。** PDF 写"打开成功返回文件描述符，失败将返回 -1"，
这一句是从 `open` 那一节原样复制过来的。**本机 `man 2 ioctl` 实测**：

```text
RETURN VALUE
       Usually, on success zero is returned.  A few ioctl() operations use the return value as an output parameter and
       return a nonnegative value on success.  On error, -1 is returned, and errno is set to indicate the error.
```

`FBIOGET_VSCREENINFO` 成功返回 0。所以源码写 `if (ioctl(...))` 判失败是对的，
你要是照 PDF 的说法写成 `if (ioctl(...) < 3)` 之类，就错了。

**第二处，5.3.5 节第 96 行。** PDF 贴的是 `memset(fbmem, 0xff, screen_size);`，
资料仓源码里是 `memset(fb_base, 0xff, screen_size);`。`fbmem` 这个变量不存在，
照 PDF 敲会编译失败。

资料仓 `07_framebuffer` 下只有一个文件 `show_pixel.c`，106 行，
第 3 节读完地址公式、第 4 节读完颜色之后再对着它看一遍，每一行都应该认得。

### 0.4 四种块

和 01 章一样，不重复解释，见 [01 章 0.3 节](01_工具链与构建系统.md)。

    正文    [基础]    [做 L1/L2/L3/L4]    [判]

**凡是标了"自己敲"的代码，别去资料仓里拷。** 抄一遍等于没学。

本章的测量探针（结构体大小、越界、读写计时、截屏转图片）放在
`labs/03_framebuffer/probe/`，它们不是本章要你学会写的东西，是量数据用的工具，
直接编直接用。要你自己写的是 `fbinfo`（第 2.3 节）、假显存上的描点（第 3.2 节）、
按位段拼色（第 4.3 节）和 project 的 display 层（第 6 节）。

### 0.5 环境

**本机**：Ubuntu 26.04 on WSL2，内核 6.6.114.1，gcc 15.2.0，
`arm-linux-gnueabihf-gcc` 15.2.0。

**上板**：100ASK_IMX6ULL Pro，经板载 USB 转串口（CH9102，Windows 上是 COM8）
用 `tools/serial-board.ps1` 执行，连接方法见 01 章 2.11。本章板上实测：

```text
Linux 100ask 4.9.88 #1 SMP PREEMPT Sun Jul 21 03:42:00 EDT 2024 armv7l GNU/Linux
```

板上 glibc 是 2.30，所以所有上板程序都加 `-static`（01 章 2.11.7）。

**第 5 节做完之后板子上的出厂 GUI 是停着的**，重启板子它会自己回来。

工作目录：

    cd /mnt/e/Workspace/embedded-linux/labs
    mkdir -p 03_framebuffer && cd 03_framebuffer

第 3 节的假显存实验会生成几个 2.4 MiB 的 `.raw` 文件，
在 `/mnt/e` 下做也可以（这一章不涉及稀疏文件），只是慢一点。

---

## 1 一张脉络图

```text
  用户态                                  内核                         硬件
  -------------------------------------  ---------------------------  ---------------------------------
  你的程序                                                              DDR 里一段 32 MiB 的内存
    fd = open("/dev/fb0")  ---------->   主设备号 29 -> fb 核心           物理地址 0x8c100000
                                          次设备号 0  -> mxsfb 驱动实例      ^                 |
    ioctl(fd, FBIOGET_VSCREENINFO) --->   把 var / fix 拷给你             |                 | LCDIF 控制器
                                          (分辨率/bpp/行宽/显存地址)       |                 | 每秒读 58.586 遍
    p = mmap(fd, ...)  -------------->   把那段物理内存映射进你的地址空间  |                 v
                                                                         |        RGB 并行信号
    p[offset] = 颜色  ============================= 直接写内存 =========+                 |
                      (这一步没有系统调用，内核完全不参与)                              SiI9022 (I2C 1-0039)
                                                                                           |
                                                                                         HDMI -> 显示器
```

图里最重要的是那条双线：**写像素这一步不经过内核**。
`open`、`ioctl`、`mmap` 各进一次内核，之后每秒画几百万个像素，一次系统调用都不发。
屏幕能跟上，是因为右边那个控制器自己在不停地读。

三条贯穿全章的线：

1. **显示就是写内存**，第 2 节。谁在读这块内存、它有多大、在哪，都能从驱动那里问出来。
2. **二维坐标拍扁成一维**，第 3 节。行起点要用驱动给的 `line_length`，不要自己算。
3. **颜色是几个位段拼起来的**，第 4 节。位段在哪、多宽，驱动也告诉你了。

第 5 节在真板子上把三条线跑一遍，顺带处理"这块内存不止你一个人在写"。
第 6 节是 project 的 display 层，你自己写。

---

## 2 第一段：显示就是写内存

### 2.0 看哪里

    PDF     174-175 页（5.1），图 5.1
    视频    4_5-1 的 0:08-1:47，以及 6:51-8:34（两类参数）
    源码    show_pixel.c 第 73-93 行
    基础    [基础 06] notes/00_基础/06_文件描述符与VFS.md 第七节（f_op 分发）
            [基础 07] notes/00_基础/07_虚拟内存与mmap.md（MAP_SHARED）
            [基础 03] notes/00_基础/03_ABI与sysroot.md（类型大小跟着平台走）

### 2.1 第一性原理：有一个硬件在不停地读这块内存

屏幕是一张像素网格。每个像素要亮成什么颜色，必须有人每秒告诉它几十遍 ——
液晶和 HDMI 线都不会"记住"上一帧。

干这件事的是 SoC 里的**显示控制器**（i.MX6ULL 上叫 LCDIF）。它的工作只有一句话：

> 按固定节拍，从内存里某个地址开始，一个像素一个像素往后读，读到一帧末尾就回到开头。

所以只要驱动把"从哪个地址开始读、读多宽多高、每个像素几位"告诉控制器，
应用程序想改屏幕，**改那块内存就行了**。这块内存就叫 framebuffer（帧缓冲）。

```text
    内存（framebuffer）                          显示控制器                    屏幕
    +------+------+------+-----+------+          +----------------+          +--------+
    | 像素0 | 像素1 | 像素2 | ... | 像素N |  <----  | 读指针从头走到尾 |  ---->   | 一帧   |
    +------+------+------+-----+------+          | 走完回到开头    |          +--------+
        ^                                         +----------------+
        |                                          节拍 = 像素时钟
    你的程序改这里                                  本板 50 MHz
```

这里藏着一个结论，第 5 节会反复用到：**控制器不管是谁写的**。
你写、GUI 写、内核控制台写，它都照读不误。谁最后写，屏幕上就是谁的。

节拍是多少，第 2.5 节会从驱动给的时序参数里算出来：本板每秒 58.586 帧。

### 2.2 [做 L1] /dev/fb0 是怎么找到驱动的

**先自己想：** 上一章说"一切皆文件"，`open` 的时候内核按你打开的东西往 `f_op`
里填不同的函数表（[基础 06] 第七节）。那 `/dev/fb0` 这个文件本身里存了什么，
能让内核知道该填显示驱动的表？WSL 里没有 `/dev/fb0`，你自己造一个同名文件行不行？

线索：`ls -l` 看设备文件时，大小那一列会变成两个数；`/proc/devices` 列出了
内核里登记过的设备号；造设备文件的命令是 `mknod`。

**先在板子上看。** Windows PowerShell 里：

```powershell
.\tools\serial-board.ps1 'ls -l /dev/fb*; grep -n fb /proc/devices; ls /sys/class/graphics/; ls -l /sys/class/graphics/fb0/device'
```

- `grep -n fb /proc/devices`：`/proc/devices` 是内核里"设备号 -> 名字"的登记表。
- `/sys/class/graphics/`：内核按"类"组织设备，显示类的设备都在这下面。
- `.../fb0/device`：一个符号链接，指向这个 fb 背后真正的硬件设备。

**本次上板实测：**

```text
crw-rw---- 1 root video 29, 0 Jan  1 00:00 /dev/fb0
crw-rw---- 1 root video 29, 1 Jan  1 00:00 /dev/fb1
11: 29 fb
fb0  fb1  fbcon
lrwxrwxrwx 1 root root 0 Jan  1 00:04 /sys/class/graphics/fb0/device -> ../../../21c8000.lcdif
```

逐列读：

- 权限前面那个 `c`：**字符设备**。普通文件是 `-`，目录是 `d`。
- 大小那一列变成了 `29, 0`：这不是大小，是**主设备号 29、次设备号 0**。
- `/proc/devices` 里 29 号登记的名字就是 `fb`。
- `fb0` 的 `device` 链接指向 `21c8000.lcdif`：物理地址 `0x021c8000` 上那个 LCDIF 控制器。
- 有两个 fb：`fb0` 和 `fb1`，次设备号 0 和 1。`fb1` 是什么，第 2.3 节问出来。
- 权限是 `rw-rw----`、属组 `video`：**普通用户不在 video 组就打不开**。
  本板串口登录的是 root，所以本章不受影响。

> **设备号**：设备文件里存的不是数据，是两个数。**主设备号**选"哪个驱动"，
> **次设备号**选"这个驱动管的第几个设备"。`open` 时内核拿主设备号找到那个驱动的
> `file_operations` 表，填进 `struct file` 的 `f_op`。

所以设备文件的名字叫 `fb0` 还是叫 `abc` 都无所谓，内核认的是那两个数。

**再到 WSL 里验证"只有号码没有驱动实例"会怎样。** 这一步要 root，
因为 `mknod` 造设备文件是特权操作。在 **Windows PowerShell** 里用 `wsl -u root` 进去
（WSL 里的 `sudo` 要密码，这是免密的写法）：

```bash
ls -l /dev/fb*
grep -n ' fb$' /proc/devices
ls /sys/class/graphics/
mknod fb_fake c 29 0          # c: 字符设备  29: 主设备号  0: 次设备号
ls -l fb_fake
```

然后用一个只做 `open` + `ioctl` 的小程序去开它（`labs/03_framebuffer/probe/fbopen.c`，
对每个路径打印 `open` 和 `ioctl` 的 errno）：

```bash
gcc -Wall -o fbopen probe/fbopen.c
./fbopen fb_fake
```

**本机实测：**

```text
ls: cannot access '/dev/fb*': No such file or directory
13: 29 fb
fbcon
crw-r--r-- 1 root root 29, 0 Sep 14 22:36 fb_fake
fb_fake                open  失败 errno=19 No such device
```

三件事对上账：

- `/proc/devices` 里有 `29 fb` —— WSL 的内核编进了 fb 核心，29 号登记上了。
- `/sys/class/graphics/` 下只有 `fbcon`，没有 `fb0` —— 没有任何一个 fb 实例。
- 所以设备文件造得出来，`open` 却报 `ENODEV`（19，No such device）：
  主设备号找到了 fb 核心，次设备号 0 对应的实例不存在。

次设备号换成 7 结果一样（实测 `errno=19`）。**这就是 WSL 里练不了真 framebuffer 的原因**，
和装不装什么软件无关，内核里压根没有显示控制器的驱动实例。

顺带看 `ioctl` 打错对象时的报错。对普通文件和 `/dev/null`：

```bash
printf 'ABCDEFGH' > data.txt
./fbopen data.txt /dev/null /dev/zero
```

```text
data.txt               ioctl 失败 errno=25 Inappropriate ioctl for device
/dev/null              ioctl 失败 errno=25 Inappropriate ioctl for device
/dev/zero              ioctl 失败 errno=25 Inappropriate ioctl for device
```

`open` 成功、`ioctl` 失败，errno 是 25 `ENOTTY`。`man 2 ioctl` 的 ERRORS 一节
（本机实测）写的就是"The specified operation does not apply to the kind of object
that the file descriptor fd references"。和 [基础 06] 第 7.4 节 `TIOCGWINSZ` 那组实验是同一回事：
**`FBIOGET_VSCREENINFO` 只有 fb 驱动的表里有人接。**

两个 errno 要分清：

    ENODEV (19)   open 就失败了：号码对应的设备不存在
    ENOTTY (25)   open 成功了：但这个文件背后的驱动不认这个请求码

### 2.3 [做 L2] 写 fbinfo：把驱动知道的全部问出来

**先自己想：** 描点需要知道哪些数？分辨率、每个像素几位、每行多少字节、
显存从哪开始多大、红绿蓝各占哪几位。这些数分别在哪个结构体里？
PDF 说"编写应用程序时主要关心可变参数，固定参数很少用到"，你写完之后回头判断这句话。

线索：

    头文件          <linux/fb.h>
    两个请求码      FBIOGET_VSCREENINFO    V = var，可变参数
                    FBIOGET_FSCREENINFO    F = fix，固定参数
    两个结构体      struct fb_var_screeninfo / struct fb_fix_screeninfo
    看定义          arm-linux-gnueabihf 工具链的头文件在
                    /usr/arm-linux-gnueabihf/include/linux/fb.h

自己敲 `fbinfo.c`，分四步，每步编一次、在 WSL 里对 `/dev/null` 跑一次确认报错分支：

    第 1 步  open 命令行给的路径（默认 /dev/fb0），失败打印 strerror(errno) 并返回 1
    第 2 步  两个 ioctl，失败同样打印并返回 1
    第 3 步  把 fix 的 id / smem_start / smem_len / line_length，
             var 的 xres / yres / xres_virtual / yres_virtual / bits_per_pixel /
             red/green/blue/transp 的 offset 和 length 全打出来
    第 4 步  打三笔对账（下面第 2.5 节要用）：
             行宽  xres*bpp/8 和 line_length 比
             大小  xres*yres*bpp/8 和 smem_len 比
             刷新  用时序参数算帧率

第 4 步里帧率的算法：

> **像素时钟**：控制器每读一个像素走一拍，`var.pixclock` 是一拍的长度，单位皮秒。
> 一行不只 `xres` 个像素，前后还有消隐（`left_margin`、`right_margin`）和同步脉冲
> （`hsync_len`），这些拍控制器也要走。纵向同理。

```text
    一行的总拍数   htotal = xres + left_margin + right_margin + hsync_len
    一帧的总行数   vtotal = yres + upper_margin + lower_margin + vsync_len
    帧率           = (1e12 / pixclock) / htotal / vtotal
```

核心三行，每个参数在管什么：

```c
struct fb_var_screeninfo var;           /* 可变: 分辨率、bpp、颜色位段、时序 */
struct fb_fix_screeninfo fix;           /* 固定: 显存物理地址、大小、行宽 */
ioctl(fd, FBIOGET_VSCREENINFO, &var);   /* fd:     open("/dev/fb0") 得到的
                                           第 2 个: 请求码, 告诉驱动"要可变参数"
                                           第 3 个: 结构体地址, 驱动往里填
                                           返回:   成功 0, 失败 -1 (不是 PDF 说的 fd) */
```

**在 WSL 编两个版本**：

```bash
gcc -Wall -Wextra -O2 -o fbinfo fbinfo.c
mkdir -p board
arm-linux-gnueabihf-gcc -static -O2 -Wall -Wextra -o board/fbinfo fbinfo.c
./fbinfo /dev/null ; echo "exit=$?"
./fbinfo /dev/nonexist ; echo "exit=$?"
```

- `-static`：板上 glibc 2.30 比工具链的旧，动态版跑不起来。
- `-Wextra`：比 `-Wall` 再多开一批警告，比如"有符号和无符号比较"，
  这一章满地都是 `__u32`，这类警告很有用。

**本机实测**（报错分支）：

```text
ioctl 失败: Inappropriate ioctl for device
exit=1
open /dev/nonexist 失败: No such file or directory
exit=1
```

**传上板运行**。回到 Windows PowerShell（文件多的时候先打 tar 包，一次传完，
理由见 02 章 7.2）：

```powershell
.\tools\serial-board.ps1 'rm -rf /tmp/ch03; mkdir -p /tmp/ch03'
.\tools\serial-board.ps1 -Upload .\labs\03_framebuffer\board\fbinfo -Destination /tmp/ch03/fbinfo
.\tools\serial-board.ps1 'chmod +x /tmp/ch03/fbinfo; /tmp/ch03/fbinfo /dev/fb0; /tmp/ch03/fbinfo /dev/fb1'
```

- 单个文件上传不带权限位，所以要 `chmod +x`。打 tar 包传就不用这一步。

**本次上板实测：**

```text
[fix] id=mxs-lcdif smem_start=0x8c100000 smem_len=33554432 line_length=4096 type=0 visual=2 ypanstep=1
[var] xres=1024 yres=600 xres_virtual=1024 yres_virtual=600 xoffset=0 yoffset=0 bpp=32
[var] red=16/8 green=8/8 blue=0/8 transp=0/0 (offset/length)
[var] pixclock=20000 ps  left=140 right=160 hsync=20  upper=20 lower=12 vsync=3  size=0x0 mm
对账1 行宽: xres*bpp/8=4096  line_length=4096  相等
对账2 大小: 可见区=2457600  虚拟区=2457600  smem_len=33554432  smem_len/可见区=13.65
对账3 刷新: 像素时钟=50.000 MHz  一行=1344 像素  一帧=635 行  行频=37.202 kHz  帧率=58.586 Hz
```

`/dev/fb1` 只有两处不同：

```text
[fix] id=FG smem_start=0x8e100000 smem_len=33554432 line_length=4096 type=0 visual=2 ypanstep=1
[var] red=16/8 green=8/8 blue=0/8 transp=24/8 (offset/length)
```

逐行读：

- **`id=mxs-lcdif`**：驱动名。`fb1` 叫 `FG`（foreground，前景层），
  它有自己的 32 MiB 显存，而且多了 `transp=24/8` —— 高 8 位是透明度。
  本章只用 `fb0`，`fb1` 知道它存在就行。
- **`smem_start=0x8c100000`**：显存的**物理地址**。你的程序拿不到物理地址，
  这个数第 5.1 节用来对账。
- **`smem_len=33554432`**：显存 32 MiB，是一屏（2457600 字节）的 13.65 倍。
  **驱动分的比一屏大得多。** 第 3.4 节和第 8 节坑 6 都要用到这个数。
- **`line_length=4096`**：一行 4096 字节，恰好等于 1024 × 4。
- **`bpp=32`，`red=16/8 green=8/8 blue=0/8 transp=0/0`**：32 位里，
  红在第 16 位起 8 位，绿第 8 位起 8 位，蓝第 0 位起 8 位，高 8 位不用。
  这就是 PDF 图 5.3 那个 RGB888 的布局，第 4.1 节画图。
- **`pixclock=20000`**：一拍 20000 皮秒 = 20 纳秒，也就是 50 MHz。

回头看 PDF 那句"固定参数很少用到"：行宽 `line_length`、显存大小 `smem_len`
都在固定参数里。**描点公式要行宽，截屏要知道只读多少，这两个数少一个都会出事**
（第 3.3 节、第 8 节坑 6）。那句话只在"行宽恰好等于 xres × bpp/8、
从来不截屏"时成立。

### 2.4 同一个结构体，x86 和 ARM 上不一样大

`fbinfo` 要分别编 x86 版和 ARM 版，还有一个理由：**这两个结构体在两个平台上的布局不一样。**

**先自己想：** `fb_fix_screeninfo` 里 `smem_start` 的类型是 `unsigned long`。
x86-64 和 32 位 ARM 上 `long` 各几个字节？这会让后面每个字段的偏移怎么变？

板子上跑不了"打印 sizeof 的程序"之外的招，而我们想在 WSL 里一次看两个平台。
[基础 03] 用过一个办法：**让编译器把大小变成数组长度，再用 `nm -S` 读符号大小**，
不用运行程序。`labs/03_framebuffer/probe/fbabi.c`：

```c
char var_size[sizeof(struct fb_var_screeninfo)];
char fix_size[sizeof(struct fb_fix_screeninfo)];
char fix_smem_len_off[offsetof(struct fb_fix_screeninfo, smem_len)];
char fix_line_length_off[offsetof(struct fb_fix_screeninfo, line_length)];
char var_bpp_off[offsetof(struct fb_var_screeninfo, bits_per_pixel)];
```

```bash
gcc -c probe/fbabi.c -o fbabi_x86.o && nm -S --defined-only fbabi_x86.o
arm-linux-gnueabihf-gcc -c probe/fbabi.c -o fbabi_arm.o && nm -S --defined-only fbabi_arm.o
```

- `-c`：只编译不链接，拿到 `.o` 就够了。
- `nm -S`：在地址后面多打一列**符号大小**，这一列就是数组长度。
- `--defined-only`：只列本文件定义的符号。

**本机实测**（前 5 行是 x86-64，后 6 行是 ARM；第二列是十六进制大小；
`nm` 默认按符号名排序）：

```text
0000000000000120 0000000000000030 B fix_line_length_off
00000000000000a0 0000000000000050 B fix_size
00000000000000f0 0000000000000018 B fix_smem_len_off
0000000000000150 0000000000000018 B var_bpp_off
0000000000000000 00000000000000a0 B var_size
00000000 b $d
000000f8 0000002c B fix_line_length_off
000000a0 00000044 B fix_size
000000e4 00000014 B fix_smem_len_off
00000124 00000018 B var_bpp_off
00000000 000000a0 B var_size
```

ARM 那边多出来的 `$d` 是 ARM ELF 的**映射符号**，标记"从这里开始是数据不是指令"，
给反汇编器用的，没有大小，不用管。

换成十进制：

| | x86-64 | ARM |
|---|---|---|
| `sizeof(fb_var_screeninfo)` | 160 | 160 |
| `sizeof(fb_fix_screeninfo)` | **80** | **68** |
| `smem_len` 的偏移 | 24 | 20 |
| `line_length` 的偏移 | 48 | 44 |
| `var.bits_per_pixel` 的偏移 | 24 | 24 |

`var` 全是 `__u32`，两边一样大；`fix` 里有两个 `unsigned long`（`smem_start` 和
`mmio_start`），x86-64 上 8 字节、ARM 上 4 字节，于是从 `smem_len` 往后每个字段都挪了位置。
`smem_len` 的偏移 24 = `id[16]` 的 16 + `smem_start` 的 8；ARM 上 20 = 16 + 4。

这件事的工程含义：**请求码里不带结构体大小**。`fb.h` 里
`#define FBIOGET_FSCREENINFO 0x4602`，就是一个裸数字。
所以结构体布局对不对，全靠你编译时用的头文件和目标平台一致。
交叉编译用 `arm-linux-gnueabihf-gcc` 就会自动用它自己 sysroot 里的头文件
（[基础 03]），不要手工 `-I` 到 x86 的 `/usr/include` 去。

### 2.5 [判] 第 2 节的判据

```text
    [ ] WSL: /proc/devices 有 29 fb，/sys/class/graphics 下没有 fb0
    [ ] WSL: mknod c 29 0 造出的节点 open 报 errno=19，对普通文件 ioctl 报 errno=25
    [ ] 板上 fbinfo 打出的 line_length 等于 sysfs 的 stride
        (cat /sys/class/graphics/fb0/stride，本板 4096)
    [ ] 板上 fbinfo 算出的帧率等于 fbset 报的 V: 频率（本板 58.586 Hz）
    [ ] 板上 fbinfo 的 smem_start 等于 fbset -i 的 Address（本板 0x8c100000）
    [ ] fbabi 的 nm -S 结果：fix 在 x86-64 上 80 字节、ARM 上 68 字节
```

后三条是**对账型**：同一个数从两条独立的路拿到，必须相等。
sysfs 和 `fbset` 走的是驱动的另一套接口，不经过你的代码。

板上对账那两条的命令：

```powershell
.\tools\serial-board.ps1 'cat /sys/class/graphics/fb0/stride; fbset -i -fb /dev/fb0'
```

**本次上板实测**：

```text
4096

mode "1024x600-59"
    # D: 50.000 MHz, H: 37.202 kHz, V: 58.586 Hz
    geometry 1024 600 1024 600 32
    timings 20000 140 160 20 12 20 3
    rgba 8/16,8/8,8/0,0/0
endmode

Frame buffer device information:
    Name        : mxs-lcdif
    Address     : 0x8c100000
    Size        : 33554432
    Type        : PACKED PIXELS
    Visual      : TRUECOLOR
    XPanStep    : 0
    YPanStep    : 1
    YWrapStep   : 1
    LineLength  : 4096
    Accelerator : No
```

`fbset` 的 `D: 50.000 MHz, H: 37.202 kHz, V: 58.586 Hz` 三个数和
`fbinfo` 的对账 3 逐个相等。`timings` 那一行七个数依次是
`pixclock left right upper lower hsync vsync`，和 `fbinfo` 打出的也逐个相等。

**注错见红：** 在 `fbinfo.c` 算完 `htotal`/`vtotal` 之后加两段 `#ifdef`：
`BUG_VTOTAL` 把 `vtotal` 改成 `var.yres`（忘了纵向消隐和同步），
`BUG_HVTOTAL` 把 `htotal`、`vtotal` 都改成分辨率。编两个注错版一起传上板：

```bash
arm-linux-gnueabihf-gcc -static -O2 -Wall -Wextra -DBUG_VTOTAL  -o board/fbinfo_bugv  fbinfo.c
arm-linux-gnueabihf-gcc -static -O2 -Wall -Wextra -DBUG_HVTOTAL -o board/fbinfo_bughv fbinfo.c
```

```powershell
.\tools\serial-board.ps1 'cd /tmp/ch03 && ./fbinfo /dev/fb0 | tail -1; ./fbinfo_bugv /dev/fb0 | tail -1; ./fbinfo_bughv /dev/fb0 | tail -1'
```

- `tail -1`：只留最后一行对账 3。这里不能写 `grep 对账3`，
  串口脚本拒绝命令里带中文（板上 readline 会把中文字节改写掉，见 01 章 2.11）。

**本次上板实测**（依次是正确版、`BUG_VTOTAL`、`BUG_HVTOTAL`）：

```text
对账3 刷新: 像素时钟=50.000 MHz  一行=1344 像素  一帧=635 行  行频=37.202 kHz  帧率=58.586 Hz
对账3 刷新: 像素时钟=50.000 MHz  一行=1344 像素  一帧=600 行  行频=37.202 kHz  帧率=62.004 Hz
对账3 刷新: 像素时钟=50.000 MHz  一行=1024 像素  一帧=600 行  行频=48.828 kHz  帧率=81.380 Hz
```

两个注错版和 `fbset` 的 `V: 58.586 Hz` 都对不上，判据红了。
**62 Hz 和 81 Hz 看起来都"像个正常的刷新率"**，单看数字判断不出错，只有和另一条路拿到的数对账才抓得住。
第一个注错版的行频 37.202 kHz 还是对的（横向没错），所以对账要比到帧率这一级。

---

## 3 第二段：像素在哪

### 3.0 看哪里

    PDF     175 页图 5.2 和那个公式，179-181 页（5.3.3、5.3.4）
    视频    4_5-1 的 1:47-3:43 和 9:19-11:16
    源码    show_pixel.c 第 28-30 行、85-88 行
    基础    [基础 07] 第 SIGSEGV 与 SIGBUS 那一节

### 3.1 第一性原理：二维坐标拍扁成一维

显存是一段连续的字节，屏幕是二维的。控制器读的顺序是从左到右、从上到下，
所以第 y 行第 x 个像素，前面已经有：

    整整 y 行          每行 line_length 个字节
    这一行里 x 个像素  每个 bpp/8 个字节

```text
    fb_base
    |
    v
    +------ 第 0 行: line_length 字节 -------------------------+
    +------ 第 1 行 ------------------------------------------+
    ...
    +------ 第 y 行 --------+---+------------------------------+
    |<--- x 个像素 -------->| * |
    |   x * (bpp/8) 字节     |
                           ^
            偏移 = y * line_length + x * (bpp/8)
```

```text
    偏移 = y * line_length + x * (bpp / 8)
    地址 = fb_base + 偏移
```

PDF 和源码写的是 `y * (xres * bpp / 8)`，也就是**假设每行恰好 xres 个像素、没有别的字节**。
本板这两个数相等（第 2.3 节对账 1），所以源码在本板上是对的。
第 3.3 节讲它们什么时候不相等。

### 3.2 [做 L2] 假显存：在电脑上练描点

WSL 没有 `/dev/fb0`，但描点这件事只需要"一块内存 + 几个参数"。
**普通文件 `mmap` 出来的也是一块内存**（[基础 07]）。
那就用一个文件冒充显存，参数从命令行给。

**先自己想：** 要让这个文件和板上的显存一模一样大，文件大小该怎么定？
文件刚创建时是 0 字节，`mmap` 一个 0 字节的文件然后往里写会怎样？（[基础 07] 讲过那个信号）
写完之后，怎么不看图片就判断"红点画对了"？

线索：

    造指定大小的文件          ftruncate
    改了要落回文件            MAP_SHARED（和 show_pixel.c 一样）
    按 4 字节一组看文件内容    od 的 -t 选项选"每组几个字节、按什么格式"

自己敲 `fakefb.c`，分三步：

    第 1 步  命令行：文件名 xres yres bpp line_length
             打开（没有就创建）-> ftruncate 到 line_length * yres -> mmap
    第 2 步  memset 成 0xff（清白），照 show_pixel.c 的描点公式写一个 put_pixel，
             在 (xres/2 + i, yres/2) 画 100 个 0xFF0000
    第 3 步  munmap、close，打印一行参数

**跑 1024×600×32、行宽 4096**，这正是板子的参数：

```bash
./fakefb fb.raw 1024 600 32 4096
ls -l fb.raw
od -An -v -tx4 -w4 fb.raw | grep -c '00ff0000'
od -An -v -tx4 -w4 fb.raw | grep -c 'ffffffff'
```

- `od`：把文件按指定格式逐组打印。
- `-An`：不打左边那列偏移（`A` 是 address，`n` 是 none），只留数据，方便 `grep`。
- `-v`：**不省略重复行**。不加它，连续相同的行会被折成一个 `*`，计数就错了。
- `-tx4`：`t` 选类型，`x4` 是"4 字节一组、十六进制"。
- `-w4`：每行 4 字节，也就是每行一个像素，`grep -c` 数的就是像素个数。

**本机实测：**

```text
xres=1024 yres=600 bpp=32 line_length=4096 实际用的行宽=4096 显存=2457600 字节
-rw-r--r-- 1 root root 2457600 Sep 14 22:36 fb.raw
100
614300
```

100 个红、614300 个白，合计 614400 = 1024 × 600。

**光数个数不够**，还要知道红点在不在该在的地方。取第一个红像素的行号换算回坐标：

```bash
n=$(od -An -v -tx4 -w4 fb.raw | grep -n -m1 '00ff0000' | cut -d: -f1)
off=$(( (n - 1) * 4 ))
echo "偏移=$off y=$((off / 4096)) x=$(( (off % 4096) / 4 ))  公式预期=$(( 300 * 4096 + 512 * 4 ))"
od -An -tx1 -j "$off" -N 4 fb.raw
```

- `grep -n -m1`：`-n` 带行号，`-m1` 找到第一个就停。行号从 1 开始，所以减 1。
- `od -tx1 -j 偏移 -N 4`：`-j` 跳过前面若干字节，`-N` 只读 4 个，`x1` 一个字节一组。

**本机实测：**

```text
偏移=1230848 y=300 x=512  公式预期=1230848
 00 00 ff 00
```

最后一行值得停下来看：`put_pixel` 写进去的是整数 `0x00FF0000`，
文件里按顺序存的却是 `00 00 ff 00`。x86 和 ARM 都是**小端**：整数的最低字节放在最前面。
所以一个 32bpp 像素在内存里的顺序是 **B G R x**。第 5.4 节转图片时要用到这一条。

### 3.3 行宽为什么要用 line_length

`struct fb_fix_screeninfo` 里单独有一个 `line_length` 字段，注释是
`length of a line in bytes`。**如果它永远等于 `xres * bpp / 8`，内核没必要单独给一个字段。**

本板驱动怎么算的，可以直接看源码。NXP 4.9.88 内核的 `drivers/video/fbdev/mxsfb.c`：

```c
fb_info->fix.line_length =
	fb_info->var.xres * (fb_info->var.bits_per_pixel >> 3);
```

所以**在本板上**两者一定相等。但一个应用程序不该依赖"这块板子的驱动恰好这么写"：
有的显示控制器要求每行字节数按 4 或 8 对齐，行尾会多出几个填充字节；
有的驱动让 `xres_virtual` 比 `xres` 大，行宽按虚拟宽度算。

用假显存把"行尾有填充"造出来：**行宽给 4104**，也就是每行比 1024 × 4 多 8 个字节。
这一次画一条从上到下的竖线，看它还竖不竖。

给 `fakefb` 加两个参数：行宽来源（`fix` 用 `line_length`，`xres` 用源码那种算法）
和图案（`hline` 横线、`vline` 竖线），然后：

```bash
./fakefb fbpad_fix.raw  1024 600 32 4104 fix  vline
./fakefb fbpad_xres.raw 1024 600 32 4104 xres vline
```

判据用 awk 把每个红像素换算回 (x, y)，数它们占了几个不同的 x
（`LL` 是真实行宽 4104，换算必须按真实行宽，因为控制器是按真实行宽读的）：

```bash
for f in fbpad_fix.raw fbpad_xres.raw; do
echo "-- $f"
od -An -v -tx4 -w4 $f | awk -v LL=4104 '
    $1 == "00ff0000" { off = (NR - 1) * 4; x = (off % LL) / 4; y = int(off / LL)
                       cnt++; seen[x] = 1; rows[y] = 1
                       if (y == 0 || y == 100 || y == 300 || y == 598) printf "   y=%-3d x=%d\n", y, x }
    END { nx = 0; for (k in seen) nx++; ny = 0; for (k in rows) ny++
          printf "   红像素=%d 占了 %d 个不同的 x, %d 个不同的行\n", cnt, nx, ny }'
done
```

- `$1 == "00ff0000"`：`od` 每行一个像素，第一列就是像素值。
- `NR`：awk 的当前行号，从 1 开始，所以 `(NR-1)*4` 就是这个像素的字节偏移。

**本机实测：**

前两行是两次 `./fakefb` 自己打印的，后面是 awk 的判据输出：

```text
xres=1024 yres=600 bpp=32 line_length=4104 实际用的行宽=4104 显存=2462400 字节
xres=1024 yres=600 bpp=32 line_length=4104 实际用的行宽=4096 显存=2462400 字节
-- fbpad_fix.raw
   y=0   x=512
   y=100 x=512
   y=300 x=512
   y=598 x=512
   红像素=600 占了 1 个不同的 x, 600 个不同的行
-- fbpad_xres.raw
   y=0   x=512
   y=100 x=312
   y=300 x=936
   y=598 x=340
   红像素=600 占了 513 个不同的 x, 599 个不同的行
```

用 `line_length` 的版本，600 个点全在 x=512 上。用 `xres*4` 的版本，
每往下一行，写入位置就比控制器认为的行起点早 8 个字节，也就是**往左偏 2 个像素**：
第 100 行偏了 200 个像素（512 → 312），偏到行首之后绕到上一行的行尾（第 300 行看到 936）。
屏幕上看到的是一条斜着拉满全屏的线，而不是竖线。

这就是 PDF 那个公式的适用条件：**只在 `line_length == xres * bpp / 8` 时成立。**
写代码时直接用 `line_length`，这个条件就不用记了。

### 3.4 [做 L1] 越界的点去哪了

`show_pixel.c` 的 `lcd_put_pixel` 不检查坐标。越界了会怎样？

**先自己想：** x 等于 `xres`（刚好出右边界一个像素）时，按公式算出的偏移落在哪？
y 等于 `yres` 时呢？板子上显存有 32 MiB，程序只映射了一屏 2.4 MiB，
写到映射区外面但还在 32 MiB 以内，会怎样？

`labs/03_framebuffer/probe/oob.c`：`wrapx` 在 (xres, 100) 画一个点，
然后把整块映射扫一遍，报告红点实际落在哪；`beyondy` 往 (0, yres) 写一个像素。
路径是设备就用 `ioctl` 取参数，是普通文件就按 1024×600×32 造一个。

```bash
gcc -Wall -O2 -o oob probe/oob.c
./oob oob.raw wrapx;   echo "exit=$?"
./oob oob.raw beyondy; echo "exit=$?"
```

**本机实测：**

```text
映射 2457600 字节, 地址 0x7b734fa00000..0x7b734fc58000
画在 (1024,100), 实际落在 (0,101)
exit=0
映射 2457600 字节, 地址 0x727425600000..0x727425858000
写 (0,600) -> 地址 0x727425858000
Segmentation fault
exit=139
```

**板上对真的 `/dev/fb0` 跑同一个程序**（ARM 静态版，第 5 节的包里带着）：

```text
映射 2457600 字节, 地址 0x76cff000..0x76f57000
画在 (1024,100), 实际落在 (0,101)
wrapx exit=0
映射 2457600 字节, 地址 0x76d18000..0x76f70000
写 (0,600) -> 地址 0x76f70000
Segmentation fault
beyondy exit=139
```

两个平台结果一致：

- **x 越界不报错，点跑到下一行开头。** 这比崩溃更糟：程序"正常"，屏幕左边缘多出一个点。
  画一个跨过右边界的矩形，右边露出去的部分会从左边冒出来。
- **y 越界：写的地址恰好是映射区的结尾**（`0x76f70000` 就是上一行打印的区间终点），
  收到 `SIGSEGV`，退出码 139 = 128 + 11。
- **板上显存明明有 32 MiB，照样段错误。** 能不能访问看的是**你映射了多少**，
  不是物理上有多少。映射区外面的虚拟地址在页表里没有登记（[基础 07]）。

所以描点函数要么在里面查边界，要么调用它的人保证不越界。
project 的 display 层选哪种，是第 6 节的设计问题之一。

### 3.5 [判] 第 3 节的判据

```text
    [ ] 1024x600x32 行宽 4096：红像素 100 个、白像素 614300 个
    [ ] 第一个红像素的偏移 == 300*4096 + 512*4 == 1230848
    [ ] 那个像素的 4 个字节按顺序是 00 00 ff 00
    [ ] 行宽 4104、用 line_length：竖线 600 个点只占 1 个 x
    [ ] 行宽 4104、用 xres*4：竖线占 513 个 x，第 100 行 x=312
    [ ] (xres, 100) 落到 (0, 101)；(0, yres) 退出码 139
```

**注错见红：把行起点写成 `y * xres`**（忘了乘每个像素的字节数）。
在你自己的 `put_pixel` 里用 `#ifdef BUG_ROW_NO_PW` 包住注错的那一行，
编译时用 `-D` 打开，再跑一遍第 3.2 节的计数和位置两条判据：

```bash
gcc -Wall -O2 -DBUG_ROW_NO_PW -o fakefb_bug fakefb.c
./fakefb_bug fb.raw 1024 600 32 4096
od -An -v -tx4 -w4 fb.raw | grep -c '00ff0000'
n=$(od -An -v -tx4 -w4 fb.raw | grep -n -m1 '00ff0000' | cut -d: -f1)
off=$(( (n - 1) * 4 ))
echo "偏移=$off y=$((off / 4096)) x=$(( (off % 4096) / 4 ))  公式预期=$(( 300 * 4096 + 512 * 4 ))"
```

- `-DBUG_ROW_NO_PW`：等于在源码最前面写一行 `#define BUG_ROW_NO_PW`。
  正确版和注错版是同一份源码，不用来回改文件，也不会忘了改回去。

**本机实测：**

```text
xres=1024 yres=600 bpp=32 line_length=4096 实际用的行宽=4096 显存=2457600 字节
100
偏移=309248 y=75 x=512  公式预期=1230848
```

**红像素还是 100 个，计数判据是绿的。** 点整整齐齐画在了第 75 行（300 / 4），
只有偏移那一条对账把它抓住了。

这就是为什么第一条判据不能单独用：**计数型判据只能证明"写了多少"，证明不了"写在哪"**。
一条横线整体平移，个数一个不少。每组判据至少要有一条和公式对账的位置判据。

---

## 4 第三段：颜色怎么拼

### 4.0 看哪里

    PDF     175 页图 5.3，180-181 页（5.3.4 第 39-66 行的解释）
    视频    4_5-1 的 3:57-5:20、6:51-7:54、11:16-13:06
    源码    show_pixel.c 第 39-66 行

### 4.1 第一性原理：一个像素就是几个位段拼起来

一个像素占 `bpp` 位。里面哪几位是红、哪几位是绿、哪几位是蓝，
**由驱动决定，驱动通过 `var.red` / `var.green` / `var.blue` 告诉你**，
每个都是 `offset`（从第几位开始）和 `length`（占几位）。

本板 `fb0` 没插显示器时（第 2.3 节实测 `red=16/8 green=8/8 blue=0/8 transp=0/0`；
插上显示器后变成 565，见第 5.6 节）：

```text
    位号     31      24 23      16 15       8 7        0
            +---------+----------+----------+----------+
    整数值   |  不用   |    R     |    G     |    B     |     0x00RRGGBB
            +---------+----------+----------+----------+

    内存里的顺序（小端，低字节在前）:
    fb_base + 偏移:   [ B ] [ G ] [ R ] [ x ]
                       +0    +1    +2    +3
```

所以 `show_pixel.c` 里 32bpp 那一支直接 `*pen_32 = color` 是对的：
它传进来的颜色格式约定为 `0x00RRGGBB`，恰好和本板的位段布局一样。
**这是一个巧合，不是一条规律。** 视频 7:35 那段自己也说了"我们没有去看 bitfield，用惯例"。
如果驱动给的是 `red=0/8 blue=16/8`（BGR 顺序），同样的代码画出来红蓝就对调了。

16bpp 常见的 RGB565 布局：

```text
    位号     15    11 10     5 4     0
            +-------+--------+-------+
            |  R 5  |  G 6   |  B 5  |       red=11/5 green=5/6 blue=0/5
            +-------+--------+-------+
```

绿色多一位，因为人眼对绿色最敏感。

### 4.2 [做 L1] 888 压成 565 丢了多少

从 8 位压到 5 位，就是只留高 5 位：`r >> 3`。源码第 52 行：

```c
color = ((red >> 3) << 11) | ((green >> 2) << 5) | (blue >> 3);
```

**先自己想：** 1600 多万种颜色压完剩几种？压完再读回来（比如截屏时），
`0xFF` 压成 5 位的 `0x1F`，读回来左移 3 位是 `0xF8` 不是 `0xFF`，纯白就变灰了。
有没有更好的放大方法？

`labs/03_framebuffer/probe/rgb565.c` 把 2^24 种颜色全部压一遍，
再用两种方法放大回 8 位：**只左移补 0**，和**把高位复制到空出来的低位**
（5 位 `abcde` 放大成 `abcdeabc`）。

```bash
gcc -Wall -O2 -o rgb565 probe/rgb565.c && ./rgb565
```

**本机实测：**

```text
888 共 16777216 种, 压成 565 后剩 65536 种, 原样读回来的 65536 种
RGB888     RGB565   补0读回   复制高位读回
0xFF0000   0xF800   0xF80000     0xFF0000
0x00FF00   0x07E0   0x00FC00     0x00FF00
0x0000FF   0x001F   0x0000F8     0x0000FF
0xFFFFFF   0xFFFF   0xF8FCF8     0xFFFFFF
0x808080   0x8410   0x808080     0x848284
0x123456   0x11AA   0x103450     0x103452
```

逐行读：

- **16777216 种压成 65536 种**，256 个颜色挤一个格子。
  "原样读回来"的恰好 65536 种，就是那些低位本来就是 0 的颜色。
- **纯白用补 0 读回来是 `0xF8FCF8`**，偏灰。复制高位读回来是 `0xFFFFFF`，纯白保住了。
- **但 `0x808080` 反过来**：补 0 读回来原样 `0x808080`，复制高位读回来成了 `0x848284`。
  两种放大方法各有对的时候，没有哪一种能把所有颜色还原 —— 丢掉的位就是丢了。

所以在 16bpp 屏上，"写进去再读出来比较"这种判据**必须按 565 比**，不能按 888 比。

### 4.3 [做 L2] 按位段拼色，不写死 switch

**先自己想：** 源码用 `switch (bpp)` 分三支，每支硬编码一种布局。
怎么写一个函数，驱动给什么 `offset/length` 就拼成什么，一行 `switch` 都不用？

线索：拼一个分量只要两步，**先砍到它的位数，再挪到它的位置**。

    砍位数    8 位的值右移 (8 - length)
    挪位置    左移 offset

自己敲 `pack(rgb888)`，参数全部取自 `var`。然后在假显存上验证三种布局：
32bpp xRGB（`16/8 8/8 0/8`）、32bpp BGR（`0/8 8/8 16/8`）、16bpp 565（`11/5 5/6 0/5`）。

答案的核心就三行，每个分量同一个形状：

```c
r = (r >> (8 - var.red.length))   << var.red.offset;    /* 砍到 length 位，挪到 offset */
g = (g >> (8 - var.green.length)) << var.green.offset;
b = (b >> (8 - var.blue.length))  << var.blue.offset;
```

第 5.6 节板上用的测试图 `probe/bars.c` 就是这么拼色的，可以做完再对着看。

**判据，以及一个会假绿的注错。** 用 16bpp 假显存，画一条横线，
数非白像素的值（`grep -v ffff` 排掉白色，`sort | uniq -c` 按值分组计数）：

```bash
od -An -v -tx2 -w2 fb16.raw | grep -v ffff | sort | uniq -c
```

注错：把红绿的位数写反，红取高 6 位、绿取高 5 位
（`(r >> 2) << 11` 和 `(g >> 3) << 5`），用 `-DBUG_565_SWAP` 编一个注错版。
给 `fakefb` 再加第 8 个参数"颜色"，正确版和注错版分别用纯红、纯绿、纯蓝画：

```bash
gcc -Wall -O2 -DBUG_565_SWAP -o fakefb_bug565 fakefb.c
for b in fakefb fakefb_bug565; do
	for c in FF0000 00FF00 0000FF; do
		echo "-- $b $c"
		./$b fb16.raw 1024 600 16 2048 fix hline $c > /dev/null
		od -An -v -tx2 -w2 fb16.raw | grep -v ffff | sort | uniq -c
	done
done
```

- `-tx2 -w2`：16bpp 一个像素 2 字节，所以按 2 字节一组、一行一组。
- `> /dev/null`：扔掉 `fakefb` 自己打印的参数行，只留判据输出。

**本机实测：**

```text
-- fakefb FF0000
    100  f800
-- fakefb 00FF00
    100  07e0
-- fakefb 0000FF
    100  001f
-- fakefb_bug565 FF0000
    100  f800
-- fakefb_bug565 00FF00
    100  03e0
-- fakefb_bug565 0000FF
    100  001f
```

注错版的纯红和正确版一模一样，都是 `f800`；只有纯绿那一组变成了 `03e0`。

**用纯红测，注错版和正确版逐字节相同。** 算一下：
`0xFF >> 2 = 63`，`63 << 11 = 0x1F800`，写进 16 位只剩低 16 位 `0xF800` ——
多出来那一位恰好溢出掉了。

资料仓的 `show_pixel.c` 只画了红色。**如果你的判据也只用红色，这个 bug 永远发现不了。**
规矩：颜色判据至少用三原色各测一次。

### 4.4 高 8 位：GUI 写的是 ff，show_pixel 写的是 00

`fb0` 的 `transp=0/0`，高 8 位驱动不看。第 5.4 节会把出厂 GUI 的一帧拉回电脑，
统计出现最多的 5 种像素值：

```text
  17792  ff00070f
  17551  ff000810
  17432  ffffffff
  14722  ff00070e
  14480  ff02b9db
```

整帧 614400 个像素，**高字节不是 `ff` 的一个都没有**（实测计数 0）。
而 `show_pixel.c` 写的红色是 `0x00FF0000`，高字节是 `00`。两者在屏上都正常显示，
因为这 8 位控制器不读。

这一条的实用意义在判据上：**回读比较时，高 8 位要么屏蔽掉，要么和写入方约定好。**
你用 `grep -c 00ff0000` 数 GUI 画出来的红色，一个也数不到，因为 GUI 写的是 `ffff0000`。

### 4.5 memset 为什么能清成白色

源码第 96 行用 `memset(fb_base, 0xff, screen_size)` 清屏，
这能用，是因为**所有位都是 1** 在任何 RGB 布局下都是白（外加高位也是 1）。
同理 `memset(..., 0, ...)` 在任何布局下都是黑。

想清成红色就不能用 `memset` 了：`memset` 是按**字节**填的，
红色 `00 00 ff 00` 是 4 个不同的字节。第 5.5 节会看到，清成非黑白的颜色，
最快的办法是先填好一行，再按行复制。

### 4.6 [判] 第 4 节的判据

```text
    [ ] rgb565: 16777216 种压成 65536 种
    [ ] 0xFFFFFF 压成 0xFFFF；补 0 读回 0xF8FCF8，复制高位读回 0xFFFFFF
    [ ] 自己的 pack() 在 32bpp xRGB 下，0xFF0000 写成 00ff0000
    [ ] 自己的 pack() 在 32bpp BGR 布局下，0xFF0000 写成 000000ff
    [ ] 自己的 pack() 在 565 布局下，三原色分别是 f800 / 07e0 / 001f
```

注错见红：红绿位数写反，**只有纯绿那一条红**（实测 `03e0`），纯红仍是 `f800`。

---

## 5 第四段：上板 —— 这块内存不止你一个人在写

### 5.0 看哪里

    PDF     181 页（5.4），就一句"可能需要把 GUI 程序禁止掉"
    视频    4_5-1 的 13:06-14:15
    源码    show_pixel.c 第 95-100 行

这一节把前面的东西搬到板子上，实验全部走串口，一次传一个包。

**5.1-5.5 的数据都是没插显示器时测的**（1024×600、32bpp、行宽 4096）。
插上显示器后模式会变，判据命令里的 `bs`、`count`、`-tx4` 都要跟着改，见第 5.6 节。

```text
 WSL                          Windows PowerShell                      开发板
 -----------------------      --------------------------------------  ---------------------------
 编 ARM 静态版                 serial-board.ps1 -Upload   == 串口 ==>  /tmp/ch03/
 打成 tar                      serial-board.ps1 '命令'    == 串口 ==>  跑程序，dd 回读 /dev/fb0
                        <==   serial-board.ps1 -Download <== 串口 ==  截屏的 .raw
 raw 转 png，看图
```

**先自己想：**

    问题 1  出厂系统开机就有个界面，它是哪个进程？你怎么证明它在用 /dev/fb0？
    问题 2  它在跑的时候你画一条线，线会立刻被擦掉吗？怎么用数字回答，而不是用眼睛？
    问题 3  不插显示器，怎么看到屏幕上现在是什么？
    问题 4  截屏要读多少字节？读 /dev/fb0 直到末尾行不行？

### 5.1 [做 L1] 找出占着屏幕的程序

**打包上传。** 在 WSL 里（`show_pixel.c` 是资料仓的原版，这一步只编不改；
`oob.c` 是第 3.4 节那个探针）：

```bash
cd /mnt/e/Workspace/embedded-linux/labs/03_framebuffer
Q=/mnt/e/Workspace/01_all_series_quickstart-master
CC=arm-linux-gnueabihf-gcc
mkdir -p board
$CC -static -O2 -Wall -o board/show_pixel "$Q/04_嵌入式Linux应用开发基础知识/source/07_framebuffer/show_pixel.c"
$CC -static -O2 -Wall -Wextra -o board/fbinfo fbinfo.c
$CC -static -O2 -Wall -o board/oob probe/oob.c
tar -cf board.tar -C board .
```

```powershell
.\tools\serial-board.ps1 'rm -rf /tmp/ch03; mkdir -p /tmp/ch03'
.\tools\serial-board.ps1 -Upload .\labs\03_framebuffer\board.tar -Destination /tmp/ch03/board.tar
.\tools\serial-board.ps1 'cd /tmp/ch03 && tar -xf board.tar && ls -l'
```

本次上传两个程序打的包（`fbinfo` + `show_pixel`）实测：

```text
警告: block 6/17 arrived damaged (attempt 1), sending it again
fbboard.tar -> /tmp/ch03/fbboard.tar: 983040 bytes, gzip 483330, 17 blocks, 1 resent, 70.8 s, sha256 OK
```

第 6 块传坏了一次，脚本自动重传，最后哈希对上。这就是 01 章 2.11.4 讲的串口丢字节，
每个 500 KB 左右的静态程序大约要传 35 秒。

**找进程。**

```powershell
.\tools\serial-board.ps1 'ps | grep -v grep | grep -E "mxapp|PID"; ls /etc/init.d/'
```

**本次上板实测**（`ps` 原始输出有 100 多行，这里只留表头和那一行）：

```text
PID   USER     COMMAND
  342 root     /usr/bin/mxapp2 --plugin tslib:/dev/input/event1
S01syslogd  S10udev	S44modem-manager    S50pulseaudio  S98swupdate	rcK
S02klogd    S20urandom	S45network-manager  S50sshd	   S99adbd	rcS
S02sysctl   S30dbus	S49ntp		    S50telnet	   S99myirhmi2
S09modload  S40network	S50mosquitto	    S80dnsmasq	   bluetooth
```

`mxapp2` 是出厂的 Qt 界面程序。`/etc/init.d/S99myirhmi2` 是启动它的脚本，
`S` 开头的脚本开机时按数字顺序执行，99 是最后一批。脚本里关键的几行：

```sh
export QT_QPA_PLATFORM=linuxfb
/usr/bin/mxapp2 --plugin tslib:$TSLIB_TSDEVICE &
...
stop() {
	killall mxapp2
}
```

`QT_QPA_PLATFORM=linuxfb`：Qt 的显示后端选"直接写 Linux framebuffer"。
到这里还只是推断。**证明它在用 `/dev/fb0`**，看它的 fd 表和内存映射表：

```powershell
.\tools\serial-board.ps1 'P=$(pidof mxapp2); ls -l /proc/$P/fd | grep fb; grep /dev/fb0 /proc/$P/maps'
```

- `pidof mxapp2`：按程序名查进程号。
- `grep /dev/fb0` 而不是 `grep fb0`：`mxapp2` 还映射了一堆 Qt 缓存文件，
  文件名是一长串十六进制，实测其中一个含有 `6fb04e`，只写 `fb0` 会把它也匹配进来。
- `/proc/<pid>/fd`：02 章讲过，它打开的每个 fd 指向什么。
- `/proc/<pid>/maps`：它的虚拟地址空间里每一段映射了什么（[基础 07]）。

**本次上板实测：**

```text
lrwx------ 1 root root 64 Jan  1 00:04 4 -> /dev/fb0
71153000-73153000 rw-s 8c100000 00:06 9788       /dev/fb0
```

逐列读 `maps` 那一行：

- `71153000-73153000`：虚拟地址区间，长度 `0x2000000` = 32 MiB。**GUI 把整个显存都映射了**，
  不只是一屏。
- `rw-s`：可读可写，`s` 是 shared —— 就是 `MAP_SHARED`。
- `8c100000`：这一列本来是"映射的文件偏移"，这里却正好是显存的物理地址
  `smem_start`（第 2.3 节）。原因在驱动的 `mmap` 实现里，NXP 4.9.88 `mxsfb.c`：

  ```c
  vma->vm_pgoff = (info->fix.smem_start + offset) >> PAGE_SHIFT;
  ```

  驱动把"偏移"改写成了物理页号，`maps` 把它原样打了出来。
  **三条独立的路拿到了同一个数**：`fbinfo` 的 `smem_start`、`fbset` 的 `Address`、
  GUI 进程 `maps` 的偏移列，都是 `0x8c100000`。

### 5.2 [做 L1] GUI 在跑的时候画一条线

**先自己想：** 问题 2。线画上去之后，你怎么用数字回答"被擦了没有、擦了多少"？

答案是回读计数。整屏读回来，数红像素和白像素：

```powershell
.\tools\serial-board.ps1 'cd /tmp/ch03; ./show_pixel; echo "show_pixel exit=$?"; R() { dd if=/dev/fb0 bs=4096 count=600 2>/dev/null | od -An -v -tx4 | tr -s " " "\n" | grep -c "$1"; }; echo "red now: $(R 00ff0000)  white now: $(R ffffffff)"; sleep 3; echo "red after 3s: $(R 00ff0000)  white after 3s: $(R ffffffff)"'
```

- `dd if=/dev/fb0 bs=4096 count=600`：每块 4096 字节（一行）、读 600 块（600 行），
  **恰好一屏**。为什么必须带 `count`，见第 8 节坑 6。
- `od -An -v -tx4`：板上 busybox 的 `od` 没有 `-w`，默认一行 4 个数，
  所以用 `tr -s " " "\n"` 把空格换成换行，变成一行一个像素，再 `grep -c`。
- `R() { ...; }`：定义一个 shell 函数，`$1` 是它的第一个参数，省得把长管道写两遍。

**本次上板实测：**

```text
show_pixel exit=0
red now: 100  white now: 613889
red after 3s: 100  white after 3s: 613887
```

红线还在（100 个），但白像素是 613889，**比应有的 614300 少了 411 个**，
3 秒后又少了 2 个。GUI 没有把整屏重画，只重画了一小块。是哪一块？

隔 3 秒抓两次显存，用 `cmp -l` 列出所有不同的字节，换算成坐标框：

```powershell
.\tools\serial-board.ps1 'cd /tmp/ch03; dd if=/dev/fb0 bs=4096 count=600 of=a.raw 2>/dev/null; sleep 3; dd if=/dev/fb0 bs=4096 count=600 of=b.raw 2>/dev/null; cmp -l a.raw b.raw | awk "{o=\$1-1; y=int(o/4096); x=int((o%4096)/4); n++; if(n==1){x0=x;x1=x;y0=y;y1=y} if(x<x0)x0=x; if(x>x1)x1=x; if(y<y0)y0=y; if(y>y1)y1=y} END{print \"changed bytes=\" n, \"box x=\" x0 \"..\" x1, \"y=\" y0 \"..\" y1}"'
```

- `cmp -l`：逐字节比较两个文件，每个不同的字节打一行，第一列是位置（从 1 开始）。
- `awk` 程序外面用双引号，所以里面的 `$1` 要写成 `\$1`，否则会被板上的 shell 先展开。

**本次上板实测：**

```text
changed bytes=92 box x=997..1002 y=8..16
```

3 秒里只有 92 个字节变了，全在右上角一个 6 × 9 像素的小框里。
第 5.4 节把 GUI 的画面拉回来一看，那个位置是**时钟的秒位**。

结论：**GUI 只重画它自己变了的地方。** 所以你画的东西会"大部分时候还在"，
被擦掉的只是恰好和 GUI 某个会动的控件重叠的部分。这比整屏被擦掉更难排查 ——
线段画在屏幕中间，一切正常；画到右上角，就会一闪一闪地少几个像素。

### 5.3 [做 L1] 停掉 GUI 再画

```powershell
.\tools\serial-board.ps1 '/etc/init.d/S99myirhmi2 stop; sleep 1; echo "GUI pid after stop: [$(pidof mxapp2)]"'
```

- `/etc/init.d/S99myirhmi2 stop`：调用脚本里的 `stop()`，也就是 `killall mxapp2`。
- `[$(pidof mxapp2)]`：方括号是为了让"查不到"显示成 `[]`，一眼看得出是空。

本章做实验时停过两次 GUI，**两次等 1 秒后的结果不一样**：

```text
第一次:  GUI pid after stop: []
第二次:  after stop: [5512]
```

第二次那个进程是刚用 `start` 拉起来 8 秒的，1 秒后还在。下一次串口会话再查：

```text
gui: []
gui after 3s: []
```

已经没了。**`killall` 只是发了个信号，进程什么时候真正退出不确定。**
所以停完一定要查 `pidof` 是空的，再做后面的实验。

确认是空的之后，再跑一遍：

```powershell
.\tools\serial-board.ps1 'cd /tmp/ch03; ./show_pixel; R() { dd if=/dev/fb0 bs=4096 count=600 2>/dev/null | od -An -v -tx4 | tr -s " " "\n" | grep -c "$1"; }; echo "red: $(R 00ff0000)  white: $(R ffffffff)"; dd if=/dev/fb0 bs=4096 count=600 2>/dev/null | md5sum; sleep 3; dd if=/dev/fb0 bs=4096 count=600 2>/dev/null | md5sum'
```

**本次上板实测：**

```text
red: 100  white: 614300
09032006539705f27fb2dfe37d94dc98  -
09032006539705f27fb2dfe37d94dc98  -
```

白像素正好 614300，隔 3 秒两次哈希相同 —— **屏幕上现在只有你一个写者。**

想恢复 GUI：`/etc/init.d/S99myirhmi2 start`，或者直接重启板子。
注意 `start` 会把 Qt 的日志打到当前终端上，经串口执行时这些日志会混进脚本的输出里。

### 5.4 [做 L1] 不插显示器也能截屏

**先自己想：** 问题 3。屏幕内容就是那块内存。内存能读回来，就能转成图片。
读回来的字节顺序是什么（第 3.2 节）？图片格式要的顺序是什么？

**第一步，板上存一屏。**

```powershell
.\tools\serial-board.ps1 'dd if=/dev/fb0 bs=4096 count=600 of=/tmp/ch03/line.raw 2>/dev/null'
```

**第二步，拉回电脑。**

```powershell
.\tools\serial-board.ps1 -Download /tmp/ch03/line.raw -To .\labs\03_framebuffer\line.raw
```

**第三步，转 PNG。** `labs/03_framebuffer/probe/raw2png.py` 用 Python 标准库写
PNG，不依赖第三方包。它做的核心一件事是把每个像素的 `B G R x` 重排成 `R G B`：

```bash
python3 probe/raw2png.py line.raw 1024 600 4096 line.png
```

- 参数依次是：输入、宽、高、**行宽字节数**（第 3.3 节，这里也要用 `line_length`）、输出。

**本次实测**：停掉 GUI、跑完 `show_pixel` 之后那一屏：

```text
/tmp/ch03/line.raw -> line.raw: 2457600 bytes, gzip 2440, 0.6 s, sha256 OK
line.png: 1024x600, 2705 字节
```

转出来是白底、正中间一条 100 像素长的红线。

再截一张 GUI 在跑时的画面：先 `start` 拉起 GUI、等 8 秒让它画完，存成 `gui.raw`，
再 `stop` 掉，下载：

```text
/tmp/ch03/gui.raw -> gui.raw: 2457600 bytes, gzip 659624, 79.0 s, sha256 OK
gui.png: 1024x600, 628519 字节
```

图上是出厂界面：顶部一行"Make Your Ideal Real!"、中间一排卡片、底部四个按钮，
右上角是时钟，显示 `00:10:07`。**第 5.2 节 `cmp` 算出的变化框 x=997..1002、y=8..16，
正好落在秒位上。**

注意两张图的传输时间：同样 2457600 字节，白底那张 gzip 后 2440 字节、0.6 秒；
GUI 那张 gzip 后 659624 字节、79 秒。**串口截屏的耗时取决于画面能压缩成多小**。

### 5.5 读显存比写显存慢 10 倍

第 3、4 节的描点都是往显存里写。project 的 display 层要做"区域刷新"、
"文字叠在背景上"时，会想从显存里读回背景。这件事先量一下。

`labs/03_framebuffer/probe/rwbench.c`：同样 2.4 MiB 一次 `memcpy`，三个方向各计时，
每项 5 轮取最短。

**本次上板实测**（跑了两遍）：

```text
写 内存->显存         4.9 ms   481.1 MiB/s
读 显存->内存        49.8 ms    47.1 MiB/s
对照 内存->内存      6.2 ms   377.9 MiB/s
读回来的内容和写进去的一致

写 内存->显存         4.9 ms   482.4 MiB/s
读 显存->内存        49.7 ms    47.1 MiB/s
对照 内存->内存      6.3 ms   372.3 MiB/s
```

**读比写慢 10 倍。** 写显存和普通内存拷贝差不多快，读显存掉到 47 MiB/s。

为什么，能查到的出处是这两处：

驱动 `mmap` 时给这段映射设的属性（NXP 4.9.88 `mxsfb.c`）：

```c
/* make buffers bufferable */
vma->vm_page_prot = pgprot_writecombine(vma->vm_page_prot);
```

`pgprot_writecombine` 在 ARM 上的定义（v4.9 `arch/arm/include/asm/pgtable.h`），
以及 ARMv7 内存类型表里 `BUFFERABLE` 这一行（v4.9 `arch/arm/mm/proc-v7-2level.S`）：

```text
#define pgprot_writecombine(prot) \
	__pgprot_modify(prot, L_PTE_MT_MASK, L_PTE_MT_BUFFERABLE)

 *			n	TR	IR	OR
 *   BUFFERABLE		001	10	00	00
 *   CACHED		011	10	10	10
```

显存映射用的内存类型叫 **writecombine**（写合并），名字就说明它是冲着"写"优化的；
表里它的缓存属性列（IR、OR）是 `00`，和普通内存 `CACHED` 那一行的 `10` 不一样。
读慢 10 倍是实测结论；CPU 在这种内存类型上具体怎么处理读访问，
本笔记没有做进一步的实验，不下结论。

**这个结论直接影响设计。** `labs/03_framebuffer/probe/fillbench.c` 把整屏涂成一种颜色，三种写法：

    A  逐点写显存        每个像素调一次 put_pixel
    B  逐行复制          先写好第 0 行，再把它 memcpy 到其余各行 —— 源数据取自显存本身
    C  离屏画完一次拷贝   在 malloc 的内存里逐点画完，最后一次 memcpy 进显存

**本次上板实测**，`-O2` 和 `-O2 -fno-inline` 各一组（程序用 `%-24s` 对齐，
中文按字节算宽度，所以列没对齐，原样保留）。

`-O2`，`put_pixel` 被内联：

```text
A 逐点写显存             2.5 ms
B 逐行 memcpy              50.5 ms
C 离屏画完一次拷贝      7.4 ms
```

`-O2 -fno-inline`，每个像素一次真正的函数调用：

```text
A 逐点写显存            17.2 ms
B 逐行 memcpy              50.4 ms
C 离屏画完一次拷贝     22.4 ms
```

程序结束时屏幕是蓝色，回读计数 `000000ff` 为 614400，确认三种写法真的写进去了。

逐行读：

- **B 最慢，两组都是 50 ms 左右**，和 `rwbench` 的"读显存 49.8 ms"几乎一样。
  "按行复制"本来是个好主意，但它的源数据是从显存里读的，慢就慢在这。
  如果第 0 行放在普通内存里再往显存复制，它就是最快的写法。
- **A 在内联时只要 2.5 ms。** 编译器把整个双重循环优化成了连续写同一个值，
  这时"逐点"已经不是逐点了。**关掉内联，每个像素一次函数调用，涨到 17.2 ms**，
  将近 7 倍。project 里描点要经过 display 层的函数（甚至函数指针），更接近下面那组。
- **C 比 A 多出来的约 5 ms**，是最后那次 2.4 MiB 的 `memcpy`，和 `rwbench` 的"写 4.9 ms"对得上。

**三条设计结论，第 6 节要用：**

1. **显存当只写的用。** 需要读回的内容（背景、已画的界面），自己在普通内存里留一份。
2. 画很多像素时，**函数调用的开销比写内存本身大得多**。区域填充、画一行文字这类操作，
   接口粒度应该是"一块"而不是"一个点"。
3. "先在离屏缓冲里画完、再一次拷贝进显存"只多花约 5 ms，
   换来的是**屏幕上永远不会出现画了一半的帧**。

量产工具的 `DispOpr` 里有 `GetBuffer` 和 `FlushRegion` 两个接口，就是为这件事留的口子。

另外用 `dd` 走 `read`/`write` 系统调用各测了三次整屏，作为对照（写的是全 0，屏幕会变黑）：

```powershell
.\tools\serial-board.ps1 'for i in 1 2 3; do time dd if=/dev/fb0 of=/dev/null bs=4096 count=600 2>/dev/null; done 2>&1 | grep real; for i in 1 2 3; do time dd if=/dev/zero of=/dev/fb0 bs=4096 count=600 2>/dev/null; done 2>&1 | grep real'
```

- `time`：bash 内建，命令结束后打三行耗时，只留 `real`（墙钟时间）。
- `done 2>&1`：`time` 的输出走标准错误，要并进管道才能被 `grep` 到。

前三行是读、后三行是写：

```text
real	0m0.035s
real	0m0.035s
real	0m0.028s
real	0m0.020s
real	0m0.018s
real	0m0.018s
```

这组数字包括进程启动时间，只能看出同样是"读比写慢"，不能和 `rwbench` 的毫秒数直接比。

### 5.6 HDMI：插上显示器之后

**到这里为止，本章所有板上数据都是在没插 HDMI 的状态下测的。**

板上的 HDMI 口不是 i.MX6ULL 原生的，SoC 只有 LCDIF 这一个显示控制器，
输出的是 RGB 并行信号。板上有一颗 **SiI9022** 把它转成 HDMI，挂在 I2C 总线上：

```powershell
.\tools\serial-board.ps1 'dmesg | grep -iE "sii|lcdif|mxsfb"; D=/sys/bus/i2c/devices/1-0039; ls $D; cat $D/name $D/cable_state $D/fb_name'
```

**本次上板实测**（未插显示器）：

```text
[    0.248996] OF: Duplicate name in lcdif@021c8000, renamed to "display#1"
[    0.922058] sii902x 1-0039: No reset pin found
[    0.926017] 21c8000.lcdif supply lcd not found, using dummy regulator
[    1.169617] 100ask, drivers/video/fbdev/mxsfb.c mxsfb_probe 2341
[    1.194327] mxsfb 21c8000.lcdif: Success seset LCDIF
[    1.194368] mxsfb 21c8000.lcdif: initialized
cable_state  edid     modalias	of_node  subsystem
driver	     fb_name  name	power	 uevent
sii902x
plugout
mxs-lcdif
```

- `1-0039`：I2C 第 1 号总线、地址 `0x39` 上的设备，驱动是 `sii902x`。
- `cable_state=plugout`：HDMI 线没插。
- `fb_name=mxs-lcdif`：它接的是 `fb0` 那个控制器。
- dmesg 那行 `100ask, drivers/video/fbdev/mxsfb.c` 说明这块板的显示驱动被 100ask 改过。

**插上显示器会发生什么，先看驱动源码怎么写**（NXP 4.9.88
`drivers/video/fbdev/mxc/mxsfb_sii902x.c`，100ask 在它基础上改过，以板上实测为准）：
检测到插线后读显示器的 **EDID**（显示器自报的"我支持哪些分辨率"），
从中找一个和当前模式最接近的，然后调用 `fb_set_var` **把 framebuffer 的分辨率改掉**。

> **EDID**：显示器里一小块只读数据，经 HDMI 线里的 DDC（本质是 I2C）读出来，
> 列出它支持的分辨率和时序。

这意味着：**插不插显示器，`xres`/`yres` 可能不一样。**
第 2.3 节量到的 1024×600 是"没插"时的值。这就是为什么所有程序都必须运行时 `ioctl` 问分辨率，
不能把 1024×600 写死 —— 视频 8:24 说"一个 LCD 定了就定了"，在 HDMI 上不成立。

#### 插上之后：实测

显示器插到板子的 HDMI 口上，出厂 GUI 保持停止状态，然后查一遍：

```powershell
.\tools\serial-board.ps1 'D=/sys/bus/i2c/devices/1-0039; echo "cable_state: $(cat $D/cable_state)"; echo "gui: [$(pidof mxapp2)]"; dmesg | grep -iE "sii|hdmi|edid|mxsfb|lcdif|fb0" | tail -20; echo ==modes; cat /sys/class/graphics/fb0/modes; echo ==vsize; cat /sys/class/graphics/fb0/virtual_size; echo ==fbinfo; /tmp/ch03/fbinfo /dev/fb0; echo ==fbset; fbset -i -fb /dev/fb0'
```

**本次上板实测：**

```text
cable_state: plugin
gui: []
[    0.248996] OF: Duplicate name in lcdif@021c8000, renamed to "display#1"
[    0.922058] sii902x 1-0039: No reset pin found
[    0.926017] 21c8000.lcdif supply lcd not found, using dummy regulator
[    1.169617] 100ask, drivers/video/fbdev/mxsfb.c mxsfb_probe 2341
[    1.194327] mxsfb 21c8000.lcdif: Success seset LCDIF
[    1.194368] mxsfb 21c8000.lcdif: initialized
==modes
D:1920x1080p-179
D:1920x1080p-165
D:1920x1080p-144
S:1920x1080p-30
S:1920x1080p-25
S:1920x1080p-24
S:1920x1080p-50
S:1280x720p-50
S:1280x720p-60
S:720x480p-60
S:720x480p-60
S:640x480p-60
S:1920x1080p-60
U:1920x1080p-60
V:1024x768p-60
V:800x600p-60
V:640x480p-60
D:1920x1080p-60
==vsize
1280,720
==fbinfo
[fix] id=mxs-lcdif smem_start=0x8c100000 smem_len=33554432 line_length=2560 type=0 visual=2 ypanstep=1
[var] xres=1280 yres=720 xres_virtual=1280 yres_virtual=720 xoffset=0 yoffset=0 bpp=16
[var] red=11/5 green=5/6 blue=0/5 transp=0/0 (offset/length)
[var] pixclock=13468 ps  left=220 right=110 hsync=40  upper=20 lower=5 vsync=5  size=0x0 mm
对账1 行宽: xres*bpp/8=2560  line_length=2560  相等
对账2 大小: 可见区=1843200  虚拟区=1843200  smem_len=33554432  smem_len/可见区=18.20
对账3 刷新: 像素时钟=74.250 MHz  一行=1650 像素  一帧=750 行  行频=45.000 kHz  帧率=60.000 Hz
==fbset

mode "1280x720-60"
    # D: 74.250 MHz, H: 45.000 kHz, V: 60.000 Hz
    geometry 1280 720 1280 720 16
    timings 13468 220 110 20 5 40 5
    hsync high
    vsync high
    rgba 5/11,6/5,5/0,0/0
endmode

Frame buffer device information:
    Name        : mxs-lcdif
    Address     : 0x8c100000
    Size        : 33554432
    Type        : PACKED PIXELS
    Visual      : TRUECOLOR
    XPanStep    : 0
    YPanStep    : 1
    YWrapStep   : 1
    LineLength  : 2560
    Accelerator : No
```

逐段读：

- **`cable_state: plugin`**，**`gui: []`**：线插上了，出厂 GUI 没在跑。
  所以下面的变化不是哪个应用程序改的，是驱动自己改的。
- **dmesg 一行都没多**：六行的时间戳都在开机后 1.2 秒以内，是开机时打的。
  **驱动插线后改了模式，却不留日志**，只能靠 sysfs 或 `ioctl` 去查。
- **`modes` 从 1 行变成 18 行**：没插线时只有 `U:1024x600p-58` 一行，
  现在列出的是显示器经 EDID 报上来的模式，每行一个，`p` 后面的数字是刷新率。
  这台显示器最高报到 `1920x1080p-179`。
- **分辨率变成 1280×720，bpp 从 32 变成 16**：`virtual_size`、`fbinfo`、`fbset` 三处一致。
  颜色位段变成 `red=11/5 green=5/6 blue=0/5`，就是第 4.1 节画的 RGB565。
  行宽跟着变成 2560 = 1280 × 2。
- **时序全换了**：像素时钟从 50 MHz 变成 74.250 MHz，一行 1650 拍、一帧 750 行，
  帧率正好 60.000 Hz。对账 3 和 `fbset` 的 `D: 74.250 MHz, H: 45.000 kHz, V: 60.000 Hz`
  逐个相等，**第 2.5 节那组判据在新模式下照样成立**。
- **`smem_start` 和 `smem_len` 没变**：还是 `0x8c100000` 开始的 32 MiB。
  **同一块内存，只是解读方式变了**：一屏现在是 1843200 字节，占显存的 1/18.2。

显示器报了 1920×1080，驱动为什么选的是 1280×720、为什么把 bpp 降到 16，
这取决于 100ask 改过的驱动怎么写，本笔记没有拿到那份源码，不做推测，只记实测结果。

**同一个 `show_pixel`，不重编，照样画。** 判据命令要按新模式改：
一行 2560 字节、720 行，按 2 字节一组数像素，红色在 565 里是 `f800`、白色是 `ffff`：

```powershell
.\tools\serial-board.ps1 'cd /tmp/ch03; ./show_pixel; echo "show_pixel exit=$?"; R() { dd if=/dev/fb0 bs=2560 count=720 2>/dev/null | od -An -v -tx2 | tr -s " " "\n" | grep -c "$1"; }; echo "f800: $(R f800)  ffff: $(R ffff)"'
```

**本次上板实测：**

```text
show_pixel exit=0
f800: 100  ffff: 921500
```

100 + 921500 = 921600 = 1280 × 720，对上了。`show_pixel` 是运行时 `ioctl` 读 bpp 的，
这次走进了 `case 16` 那一支，`line_width = 1280 * 16 / 8 = 2560` 恰好等于新的 `line_length`。
**如果当初把 1024、600、32 写死在代码里，插上显示器这一刻程序就画错了。**

**彩条：用计数判颜色和位置。** `probe/bars` 运行时读分辨率，
画 8 条等宽竖彩条（红 绿 蓝 白 黄 青 品红 黑），四周一圈 1 像素白边框，按 `var` 的位段拼色。
画完回读，按像素值分组计数：

```powershell
.\tools\serial-board.ps1 'cd /tmp/ch03; ./bars; echo "bars exit=$?"; dd if=/dev/fb0 bs=2560 count=720 2>/dev/null | od -An -v -tx2 | tr -s " " "\n" | grep -v "^$" | sort | uniq -c; dd if=/dev/fb0 bs=2560 count=720 of=/tmp/ch03/bars.raw 2>/dev/null; ls -l /tmp/ch03/bars.raw'
```

- `grep -v "^$"`：`tr` 把行首空格也变成了换行，会多出空行，排掉。
- `sort | uniq -c`：先排序让相同的值挨在一起，`uniq -c` 再数每种有几个。

**本次上板实测：**

```text
画完: 1280x720 16bpp line_length=2560
bars exit=0
 114162 0000
 114880 001f
 114880 07e0
 114880 07ff
 114162 f800
 114880 f81f
 114880 ffe0
 118876 ffff
-rw-r--r-- 1 root root 1843200 Jan  1 00:53 /tmp/ch03/bars.raw
```

先把 565 值翻译成颜色：`0000` 黑、`001f` 蓝、`07e0` 绿、`07ff` 青、`f800` 红、
`f81f` 品红、`ffe0` 黄、`ffff` 白。每个数都能事先算出来：

```text
    每条彩条宽 1280 / 8 = 160 像素，去掉上下边框，高 720 - 2 = 718 行
    红（最左）和黑（最右）各被左右边框吃掉一列:   159 × 718 = 114162
    绿 蓝 黄 青 品红:                            160 × 718 = 114880
    白边框: 上下两行 2 × 1280 + 左右两列 2 × 718 = 3996
    白 = 白条 114880 + 边框 3996                            = 118876
    合计 114162 × 2 + 114880 × 5 + 118876                   = 921600 = 1280 × 720
```

**八个数逐项相等。** 这比数红点强得多：颜色拼错（比如红蓝对调）会让 `f800` 和 `001f`
的计数互换；边框少画一圈，红、黑、白三个数都会变。

把这一屏拉回电脑转成图片（`raw2png.py` 第 6 个参数给 16，按 565 解）：

```powershell
.\tools\serial-board.ps1 -Download /tmp/ch03/bars.raw -To .\labs\03_framebuffer\bars.raw
```

```bash
python3 probe/raw2png.py bars.raw 1280 720 2560 bars.png 16
```

**本次实测：**

```text
/tmp/ch03/bars.raw -> bars.raw: 1843200 bytes, gzip 9258, 1.8 s, sha256 OK
bars.png: 1280x720, 10802 字节
```

转出来的图从左到右是红、绿、蓝、白、黄、青、品红、黑八条，四周一圈白边。

回读和截屏证明的是**显存里的内容对**。显示器上看到的是不是这个样子，
还隔着 LCDIF、SiI9022、HDMI 线和显示器的缩放，这一段只能用眼睛确认：

```text
    [x] 显示器上从左到右是 红 绿 蓝 白 黄 青 品红 黑
    [x] 四条白边都看得见（看不见说明显示器把画面边缘裁掉了）
    [ ] 拔掉显示器后，模式是否变回 1024x600x32（未测）
```

前两条 2026-09-14 在显示器上看过，都成立：1280×720 这个模式下显示器没有裁边，
颜色顺序和显存里的内容一致。第三条没测。

### 5.7 [判] 真机清单

```text
    [ ] fbinfo /dev/fb0 与 fbset -i：smem_start / line_length / 帧率 三笔对上
    [ ] mxapp2 的 /proc/<pid>/maps 里 /dev/fb0 那一行偏移列 == smem_start
    [ ] GUI 在跑时：show_pixel 之后白像素 < 614300；cmp 变化框在时钟位置
    [ ] GUI 停掉后：红 100、白 614300，隔 3 秒两次 md5 相同
    [ ] line.raw 下载 sha256 OK，转出的 PNG 是白底中间一条红线
    [ ] oob 在板上：(1024,100) 落到 (0,101)；(0,600) 退出码 139
    [ ] rwbench：读显存明显慢于写显存（本板约 10 倍）
    [ ] 插上显示器后 cable_state=plugin，fbinfo 算出的帧率仍等于 fbset 的 V: 频率
    [ ] 插上后按 fbinfo 给的 line_length / yres / bpp 回读：
        bars 八种颜色的计数与按分辨率推算的值逐项相等，合计等于 xres*yres
```

"GUI 在跑时白像素少于 614300"这一条，本身就是"停掉 GUI"那条判据的注错见红：
不停 GUI，判据必然红（实测 613889）。

---

## 6 落进项目：display 层（你自己做）

### 6.1 这一章要交出什么

`project/display/disp_manager.c` 现在是空壳，`display_init` 里留着一行
`TODO 第 03 章 Framebuffer`。工程文档里早就给这一步定了验收口径
（`notes/03_项目/TechReports/project/01-先立骨架-分层启停与两棵产物树.md` 的里程碑表）：

```text
    交付   DispBuffer、DispOps/注册选择接口、display/framebuffer.c；
          打开 /dev/fb0，读取真实分辨率和 bpp，mmap 显存；
          unittest/disp_test.c 和单测构建目标
    验收   HDMI 屏能依次显示几种纯色和指定矩形；
          退出后映射和 fd 都释放；上层不出现 /dev/fb0
```

路线图 `notes/03_项目/Todo/项目路线图-对齐电子产品量产工具.md` 记着：
注册链表（`RegisterDisplay` 那一套）就是在这一章引进，是一次接口大改。

**这一节不给实现。** 下面是对照对象的形状、本章实测对它的影响、以及你动手前该想清楚的问题。

### 6.2 对照：量产工具第 01-04 步长什么样

`$P` = `$Q\06_实战项目\01_电子产品量产工具\source\02_视频配套源码\`，
display 相关的是 `01_display_struct` 到 `04_disp_unittest` 四步。第 04 步的接口：

```c
typedef struct DispBuff {
	int iXres;
	int iYres;
	int iBpp;
	char *buff;
} DispBuff, *PDispBuff;

typedef struct Region {
	int iLeftUpX;
	int iLeftUpY;
	int iWidth;
	int iHeigh;
} Region, *PRegion;

typedef struct DispOpr {
	char *name;
	int (*DeviceInit)(void);
	int (*DeviceExit)(void);
	int (*GetBuffer)(PDispBuff ptDispBuff);
	int (*FlushRegion)(PRegion ptRegion, PDispBuff ptDispBuff);
	struct DispOpr *ptNext;
} DispOpr, *PDispOpr;

void RegisterDisplay(PDispOpr ptDispOpr);
void DisplayInit(void);
int SelectDefaultDisplay(char *name);
int InitDefaultDisplay(void);
int PutPixel(int x, int y, unsigned int dwColor);
int FlushDisplayRegion(PRegion ptRegion, PDispBuff ptDispBuff);
PDispBuff GetDisplayBuffer(void);
```

它的 `framebuffer.c` 里 `FbDeviceInit` 就是 `show_pixel.c` 的 `main` 前半段搬过去，
`FbGetBuffer` 直接返回 `fb_base`，`FbFlushRegion` 是空函数。`disp_test.c` 的 `main`
依次调 `DisplayInit` → `SelectDefaultDisplay("fb")` → `InitDefaultDisplay` → 画一个字母 →
`FlushDisplayRegion`。

**用本章的实测回头读它，有三处值得你自己决定要不要照搬：**

1. `line_width = var.xres * var.bits_per_pixel / 8`：没用 `line_length`（第 3.3 节）。
2. `FbDeviceInit` 里 `ioctl` 或 `mmap` 失败直接 `return -1`，**前面 `open` 得到的 fd 没有关**。
   对照源码第 28-31 行和第 38-41 行。
3. `GetBuffer` 返回的就是显存本身，所以 `FlushRegion` 是空的。
   第 5.5 节的数据说明：只要上层有一次"读回背景"，这个设计就要付 10 倍的读代价。

### 6.3 先自己想：动手前要回答的七个问题

每个问题后面括号里是本章给你证据的那一节。不要求和量产工具一样，但要能说出为什么。

    1. 分辨率、bpp、行宽存在哪一层？上层（font、ui）通过什么拿到？
       插拔 HDMI 分辨率和 bpp 都会变（本板实测 1024x600x32 变成
       1280x720x16），你的存法在变了之后会怎样？                （2.3、5.6）
    2. PutPixel 查不查边界？查的话越界返回什么？
       不查的话，谁来保证不越界？                              （3.4）
    3. 颜色参数用 0x00RRGGBB 传进来，还是让上层直接给像素值？
       拼色用 switch(bpp) 还是按 var 的位段？                   （4.1、4.3）
    4. GetBuffer 给上层的是显存，还是一块离屏缓冲？
       如果是离屏缓冲，FlushRegion 拷贝的时候行宽用哪个？      （5.5、3.3）
    5. display_exit 的释放顺序是什么？init 半路失败时，
       已经申请到的资源谁来还？                                  （6.2 第 2 条）
    6. project/check.sh 是在 WSL 里跑的，而 WSL 里 open /dev/fb0 必然失败。
       display_init 失败时整个程序怎么办？现有 29 条判据会不会全红？
       有没有办法在 WSL 里也验证 PutPixel 写对了位置？          （2.2、3.2）
    7. "上层不出现 /dev/fb0" 这一条验收，怎么写成一条能注错见红的判据？

第 6 个问题最值得花时间。提示一个方向：量产工具之所以要"注册一张操作表、按名字选后端"，
不只是为了以后能换显示设备 —— 你手里已经有一个现成的第二后端了，就是第 3.2 节的假显存。

### 6.4 [判] 验收判据（你写完之后要全部满足）

```text
    [ ] WSL: bash project/check.sh 原有判据不减少、全部 PASS
    [ ] WSL: 有一条判据能验证 PutPixel 的写入位置（不只是个数），并且注错见红过
    [ ] WSL: 三原色各有一条颜色判据（4.3 那个纯红假绿的坑）
    [ ] WSL: grep 判据：display/ 以外的目录不出现 "/dev/fb"
    [ ] 板上: 停掉 GUI 后跑单测，回读计数与预期一致
    [ ] 板上: 程序退出后 /proc/<pid> 已消失，再跑一次结果相同（资源确实还了）
    [ ] 板上 + 显示器: 依次显示几种纯色和一个指定矩形，肉眼确认
    [ ] CodeReading / TechReports 按 notes/03_项目/README.md 的规则同步
```

---

## 7 自检问题

答不上来就回对应小节。

1. 应用程序画一个像素要发几次系统调用？屏幕为什么能跟上？（1、2.1）
2. `/dev/fb0` 这个文件里存的是什么？改名叫 `abc` 还能用吗？（2.2）
3. WSL 里 `mknod c 29 0` 造出来的节点为什么 `open` 失败？errno 是几？和 `ENOTTY` 差在哪一步？（2.2）
4. `ioctl` 成功返回什么？PDF 5.2.2 那句为什么是错的？（0.3）
5. 描点要用到的数，哪些在 `var` 里、哪些在 `fix` 里？"fix 很少用到"在什么条件下成立？（2.3）
6. 由 `pixclock` 和六个消隐/同步参数怎么算出帧率？只用 `xres`/`yres` 算会得几？（2.3、2.5）
7. `fb_fix_screeninfo` 在 x86-64 和 ARM 上为什么不一样大？请求码能不能帮你发现结构体用错了？（2.4）
8. 像素偏移公式是什么？PDF 那个公式的适用条件是什么？（3.1、3.3）
9. 32bpp 的 `0x00FF0000` 在内存里的 4 个字节是什么顺序？为什么？（3.2、4.1）
10. 行尾有 8 字节填充、却用 `xres*4` 当行宽，一条竖线会变成什么样？（3.3）
11. x 越过右边界一个像素，点落在哪？y 越过映射区呢？显存有 32 MiB 为什么还会段错误？（3.4）
12. 只数红像素个数的判据，会放过哪种 bug？（3.5）
13. 888 压成 565 剩几种颜色？纯白读回来为什么可能变灰？（4.2）
14. 不写 `switch(bpp)`，按位段拼一个分量是哪两步？（4.3）
15. 565 红绿位数写反，为什么用纯红测不出来？（4.3）
16. GUI 画的像素高字节是多少？为什么 `grep -c 00ff0000` 数不到 GUI 画的红色？（4.4）
17. 为什么 `memset` 能清白清黑，不能清红？（4.5）
18. 怎么证明出厂 GUI 在用 `/dev/fb0`？`maps` 里那个 `8c100000` 是什么？（5.1）
19. GUI 在跑时你画的线会被擦掉吗？怎么用数字回答？（5.2）
20. `killall` 之后立刻查进程，为什么可能还在？（5.3）
21. 不插显示器怎么截屏？截屏的 `dd` 为什么必须带 `count`？（5.4、8）
22. 读显存和写显存哪个快？这对 display 层的接口设计意味着什么？（5.5）
23. 插上 HDMI 显示器，分辨率为什么可能变？谁改的？（5.6）
24. 本板插上显示器后 bpp 变成几？第 5.2 节那条 `grep -c 00ff0000` 的判据为什么会失效？
    同一个 `show_pixel` 为什么不用重编就能照常画？（5.6、8）

---

## 8 已知的坑

**坑 1：WSL 里没有 `/dev/fb0`，自己 `mknod` 也没用。**

实测 `open` 报 `ENODEV`（第 2.2 节）。内核里有 fb 核心，没有显示控制器的驱动实例。
这一章的真显存实验只能上板；电脑上练地址和颜色，用第 3.2 节的假显存。

**坑 2：出厂 GUI 不会整屏擦掉你的画，只擦它自己变化的那一块。**

实测 3 秒只变了 92 个字节，在时钟的秒位上（第 5.2 节）。
所以"画上去看着没问题"不能证明没有冲突。上板做显示实验前先停 GUI，并用 `pidof` 确认。

**坑 3：`killall` 之后进程不会立刻消失。**

`S99myirhmi2 stop` 之后等 1 秒，实测 `pidof mxapp2` 还查得到。脚本里要轮询或多等几秒。

**坑 4：只数个数的判据会放过"整体平移"。**

行起点少乘像素宽度，红点还是 100 个，整条线挪到了第 75 行（第 3.5 节）。
每组判据至少一条位置对账。

**坑 5：纯红测不出 565 的位数写反。**

`(0xFF >> 2) << 11` 溢出后恰好还是 `0xF800`（第 4.3 节）。三原色各测一次。

**坑 6：`cat /dev/fb0` 读出来的是 32 MiB，不是一屏。**

```powershell
.\tools\serial-board.ps1 'echo "cat bytes: $(cat /dev/fb0 | wc -c)"; dd if=/dev/fb0 of=/dev/null bs=65536 2>&1 | tail -2'
```

```text
cat bytes: 33554432
512+0 records out
33554432 bytes (34 MB, 32 MiB) copied, 0.240766 s, 139 MB/s
```

读到末尾是 `smem_len` 那么多（第 2.3 节的 32 MiB），是一屏的 13.65 倍。
内核通用的 `fb_read`（v4.9 `drivers/video/fbdev/core/fbmem.c`）里总长度的取法：

```c
total_size = info->screen_size;

if (total_size == 0)
	total_size = info->fix.smem_len;
```

截屏必须写 `bs=<line_length> count=<yres>`，否则 2.4 MiB 的截屏变成 32 MiB，
经串口要多传十几倍的数据，转图片时后面也全是垃圾。

**坑 7：GUI 写的像素高字节是 `ff`，数颜色时要带上它。**

第 4.4 节。`grep -c 00ff0000` 只数得到 `show_pixel` 这类写 `00` 的程序画的红。

**坑 8：`/dev/fb0` 的权限是 `crw-rw---- root video`。**

板上串口登录是 root 所以不受影响。以后用普通用户跑显示程序，要把用户加进 `video` 组，
否则 `open` 报 `Permission denied`。

**坑 9：串口截屏的时间取决于画面，而不是分辨率。**

同样一屏，白底 gzip 后 2440 字节传 0.6 秒，GUI 画面 659624 字节传 79 秒（第 5.4 节）。
要反复截屏对比时，尽量用纯色背景做实验。

**坑 10：`serial-board.ps1 -Download -To` 以前不认绝对路径。**

本章做实验时发现，`-To C:\...\line.raw` 会被拼成 `当前目录\C:\...`，写文件失败。
原因是脚本用 `Join-Path (Get-Location) $To`，它不管 `$To` 是不是绝对路径都硬拼。
已改成 `[IO.Path]::Combine`（遇到绝对路径直接用它），并用绝对路径实测下载一次、
哈希与旧文件一致。之前的章节都用相对路径，所以一直没暴露。

**坑 11：插上显示器，bpp 从 32 变成 16，第 5 节前半的判据命令全部失效。**

第 5.6 节实测：插线后模式变成 1280×720、16bpp、行宽 2560。这时：

- `dd bs=4096 count=600` 读到的不再是一屏（一屏是 `bs=2560 count=720`）。
- `od -tx4` 把两个 565 像素拼成一个 32 位数，`grep -c 00ff0000` 永远是 0。
- `probe/fillbench` 只写了 32bpp 版本，会直接报"这块屏是 16bpp"退出。

判据命令里的 `bs`、`count`、`-tx` 宽度和颜色值，都应该先跑一次 `fbinfo` 再定，
不能从笔记里抄一套数字用到底。

---

## 9 这一章交出了什么

    notes/01_应用编程/03_Framebuffer显示.md     本笔记
    labs/03_framebuffer/probe/                  8 个测量探针
        fbopen.c     open + ioctl 的 errno（2.2）
        fbabi.c      结构体大小与偏移，不运行只看 nm -S（2.4）
        oob.c        越界描点落在哪（3.4）
        rgb565.c     888 压成 565 的丢失量（4.2）
        rwbench.c    显存读/写/普通内存拷贝计时（5.5）
        fillbench.c  三种整屏填充写法计时（5.5）
        bars.c       插显示器用的彩条测试图，按位段拼色（5.6）
        raw2png.py   显存转储转 PNG，支持 32bpp 和 16bpp（5.4、5.6）
    tools/serial-board.ps1                      修复 -Download -To 绝对路径

**要你自己完成的**：`fbinfo`（2.3）、假显存描点（3.2、3.3）、按位段拼色（4.3）、
project 的 display 层（第 6 节）。

**还欠的**：拔掉显示器后模式会不会变回 1024×600×32（第 5.6 节）。

下一章 04 文字显示：在描点函数之上画字符。点阵字模本质上是一张"哪些像素要描"的位图，
FreeType 是把矢量字体现场算成这张位图。那一章会大量调用描点，
第 5.5 节"函数调用比写内存贵"那组数据在那里会直接变成性能问题。

---

## 顺带一提：和 NEMU 的 VGA、龙芯 SoC 的 DVI 帧缓冲对照

**没做过这两个项目也不影响，跳过即可，本章不依赖它们。**

如果你在 ysyx 里给 NEMU 实现过 VGA 设备：那边是一块 `vmem`，AM 往里写像素，
模拟器按时把它刷到 SDL 窗口里。和本章是同一个形状 —— 写内存、另一方按节拍去读。
区别是 NEMU 里"按节拍去读"的是模拟器的一段 C 代码，这里是 SoC 里的 LCDIF 硬件。

如果你在龙芯 SoC 上做过 DVI 输出：扫描器按像素时钟从一块 RAM 里逐个取像素、
生成行场同步，那就是本章图 2.1 右边那个"显示控制器"。本章第 2.3 节 `fbset` 那行
`timings 20000 140 160 20 12 20 3`，就是你当时在 RTL 里写死的那几个行场参数，
只不过这里由驱动写进 LCDIF 的寄存器，并通过 `ioctl` 报告给应用程序。
