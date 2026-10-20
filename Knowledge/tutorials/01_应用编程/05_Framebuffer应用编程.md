# 05 Framebuffer 应用编程

    实验    Knowledge/labs/05_framebuffer/（fbinfo、show_pixel、fakefb 三个主实验；
            probe/ 下 8 个探针；check.sh 自动核对电脑侧全部判据）
    电脑    WSL Ubuntu 26.04，gcc 15.2.0，arm-linux-gnueabihf-gcc 15.2.0
            （本篇"本机实测"均为 2026-10-20 实跑）
    板子    100ASK_IMX6ULL Pro，Linux 4.9.88，glibc 2.30
            （板上输出均为 2026-09-14/22 实测归档，板子不在线时不重跑、不改数）

---

**读前须知**：看懂本篇需要下面的底子，缺哪条先补哪条：

- 前一章 [04 文件 IO](./04_文件IO.md)：open/mmap 是本篇的手脚，第 1.4 节起全程
  在用；ioctl 只在 04 篇露过面，本篇第 1.3 节就地讲透
- [01 HelloWorld 背后没那么简单](./01_HelloWorld背后没那么简单.md) 第 4 节：
  交叉编译静态程序、串口分块校验上传的上板流程，本篇第 4 节走同一条路
- 用到再读 [10 驱动与设备文件](../../fundamentals/10_驱动与设备文件.md)：
  设备文件里只存类型和主、次设备号，第 1.2 节一开场就在用
- 用到再读 [09 虚拟内存与 mmap](../../fundamentals/09_虚拟内存与mmap.md)：
  第 1.4 节的映射、第 2.4 节"显存 32 MiB 为什么还段错误"都指过去
- 用到再读 [11 显示原理](../../fundamentals/11_显示原理.md)：第 1.3 节的行场
  时序与帧率、第 5 节的 EDID 指过去
- 用到再读 [12 进程与信号](../../fundamentals/12_进程与信号.md)：第 4.4 节给
  出厂 GUI 发 SIGTERM 请它退出时指过去

**这一章在整机里的位置**：上接 04 篇（open/mmap/ioctl）与 01 篇的上板流程，下接
06 篇（文字显示）与 Project 的 display 层。它补的零件是"显示就是写内存"：问驱动
要参数、把二维坐标拍扁成一维偏移、按位段拼颜色、直接写显存。

**不学它会怎样**：画面写不上去；行宽写死成 `xres*bpp/8`，遇到行尾带填充的显存会
错行（本板两种模式的行宽恰好都等于 `xres*bpp/8`，这个错在板上永远看不出来）；
16/32bpp 位段拼错，颜色全反；GUI 占着屏幕时画了也看不见；mmap 越界不返回错误码，
直接 SIGSEGV。

## 0 起点

### 0.1 先看结果：红 100，白 614300

在板上停掉出厂 GUI，让一个程序把整屏清成白色、在正中间画 100 个红色像素，然后把
显存里的内容原样读回来，按像素数数：

```text
red=100 white=614300          合计 614400 = 1024 × 600
```

（2026-09-14 板上实测归档；怎么画、怎么数，第 4 节一步步做。）

三个数都不神奇，但每一个都能问出一串问题：程序往哪里写，屏幕就知道变了？"正中间"
这个二维位置，怎么变成内存里的一个偏移？"红色"这个颜色，怎么变成内存里的四个字节？
数出来的 614400 为什么恰好是 1024 × 600？本章把这四个问题逐个拆开。

### 0.2 这一章为什么存在

一句话：**屏幕自己记不住画面，有一个硬件在不停地读一块内存；你想改屏幕，改那块
内存就行了。**

这块内存叫 framebuffer（帧缓冲，本章也叫显存）：里面按固定格式存着一整帧每个像素
的颜色。那个不停读它的硬件叫显示控制器。从应用写一个像素到屏幕上看到它，只有两条
路径，全章其余内容都是这两条路径的注脚：

![图 5　framebuffer 的两条路径：建立映射（一次）与写像素（零系统调用）](fig/05-fb两条路径.svg)

图里最关键的是那条粗的蓝线：**写像素这一步不经过内核。** open、ioctl、mmap 各进
一次内核，把映射建立起来；之后每秒写几百万个像素，一次系统调用都不发。屏幕能跟
得上，是图右边那个控制器按自己的节拍在读，与应用写不写、谁在写无关。

贯穿全章的三条线：

1. **显示就是写内存**（第 1 节）：这块内存在哪、多大、什么格式，都能从驱动问出来。
2. **二维坐标拍扁成一维**（第 2 节）：行起点要用驱动给的 `line_length`。
3. **颜色是几个位段拼起来的**（第 3 节）：位段在哪、多宽，驱动也会告诉你。

WSL 里没有可用的 framebuffer（第 1.2 节会亲手碰到这个限制），所以电脑上用普通
文件冒充显存来练第 2、3 条（假显存），板子上验第 1 条和第 4 节的"这块内存不止
你一个人在写"。第 5 节插显示器，第 6 节对账 Project 的 display 层。

### 0.3 怎么读这一章

    只想先看见结果   0.1 → 1.3（fbinfo 把驱动问出来）→ 2.1（坐标拍扁）
    完整学一遍       1 → 4；5 插显示器时再看，6 对账 Project
    选读，第二轮再看 4.6（读显存慢 10 倍与三条设计结论）、10（延伸 A~D）

---

## 1 显示就是写内存

### 1.1 LCDIF：按固定节拍读内存的硬件

先想清楚一件事：LCD 屏上每个像素要亮成什么颜色，必须有人一遍一遍地告诉它。液晶
本身没有记忆一帧画面的能力，停止送数据，画面就没了。

干这件事的是 SoC 里的**显示控制器**。i.MX6ULL 里的这个模块叫 LCDIF（LCD
Interface，寄存器基地址 0x021C8000，i.MX6ULL Reference Manual 的 LCDIF 一章）。
它的工作只有一句话：

> 按固定节拍，从内存里某个地址开始，一个像素一个像素往后读，读到一帧末尾就回到
> 开头，周而复始。

```
显存(一块普通内存)              LCDIF 显示控制器              屏
+------------------+      每个像素时钟读出一个像素      +--------+
| 第0行 1024 像素   |  --->  从左到右,从上到下,     ---> | 像素发亮 |
| 第1行 1024 像素   |        读完一帧回到开头            |        |
| ...              |                                   +--------+
| 第599行 1024 像素 |
+------------------+
     ^
     | 驱动开工时把"起始地址、每行多少字节、每帧多少行、
        每个像素占几位、节拍多快"写进 LCDIF 的寄存器
```

"节拍"由一组时序参数决定：每行扫多少个像素时钟、每帧扫多少行、时钟多快。这组参数
第 1.3 节会从驱动里读出来，并亲手算出本板每秒刷 58.586 帧。行、场、消隐的完整
含义见[11 显示原理](../../fundamentals/11_显示原理.md)第 2 节。

于是分工清楚了：**驱动负责在开工时配好控制器和显存，应用负责改显存的内容。**
这里藏着一个第 4 节要反复用的结论：控制器不管显存是谁写的。你写、出厂 GUI 写、
内核控制台写，它照读不误，谁最后写，屏幕上就是谁的。

**这一节搭好的积木**：屏幕上每一帧都来自一个硬件对一块内存的循环扫描。接下来的
问题：这块内存在哪、归谁管，应用怎么找到它。

### 1.2 [做 L1] /dev/fb0 是怎么找到驱动的

应用在用户态，显存和控制器在内核和硬件那边，中间的门是设备文件 `/dev/fb0`。
按[10 驱动与设备文件](../../fundamentals/10_驱动与设备文件.md)第 1 节的结论：设备文件本身不存数据，只存"字符/块、主设备号、
次设备号"三样；打开它时，内核用主设备号找到驱动，驱动再用次设备号找到具体实例。

把这件事放到 fb0 上看一遍。板上（2026-09-14 归档）：

```powershell
.\Tools\serial-board.ps1 'ls -l /dev/fb*; grep -n fb /proc/devices; ls -l /sys/class/graphics/fb0/device'
```

```text
crw-rw---- 1 root video 29, 0 Jan  1 00:00 /dev/fb0
11: 29 fb
lrwxrwxrwx ... /sys/class/graphics/fb0/device -> ../../../21c8000.lcdif
```

逐行读：

- 第一行：`c` 开头是字符设备；主设备号 29，次设备号 0；属主 root、属组 video，
  权限 `rw-rw----`，所以**不在 video 组的普通用户打不开它**（本板串口登录的是
  root，不受影响）。
- 第二行：`/proc/devices` 里登记的字符设备主设备号，29 号归 `fb`。这个 `fb` 是
  内核里的 framebuffer 核心层（源码 `drivers/video/fbdev/core/fbmem.c`，它启动时
  执行 `register_chrdev(FB_MAJOR, "fb", &fb_fops)`，FB_MAJOR 就是 29）。打开
  `/dev/fb0` 时，先进 fb 核心，核心再按次设备号 0 找到第一个登记进来的显示驱动
  实例。
- 第三行：sysfs 里 fb0 挂在一个链接下面，链接指向物理地址 0x021c8000 的那个设备，
  正是 1.1 节说的 LCDIF。管它的驱动叫 `mxsfb`（NXP 内核源码
  `drivers/video/fbdev/mxsfb.c`）。

现在回答"为什么 WSL 里练不了真 framebuffer"。电脑上没有显示控制器接这块屏，但
这件事不能靠推理，要亲手碰一下。在 WSL 里造一个和板上一模一样的节点（要 root：
`wsl -u root` 进 WSL；节点必须建在 WSL 自己的根文件系统上，原因最后说）：

```bash
mkdir -p ~/fblab && cd ~/fblab
mknod fb_fake c 29 0            # c=字符设备 29=主设备号 0=次设备号
echo hello > data.txt
gcc -Wall -o fbopen /mnt/e/Workspace/Embeded/Embedded-linux/Knowledge/labs/05_framebuffer/probe/fbopen.c
./fbopen fb_fake data.txt /dev/null
```

- `mknod fb_fake c 29 0`：手工造一个设备文件。它只在文件里登记那三样信息，不会
  变出任何硬件。
- `probe/fbopen.c`：对命令行给的每个路径做两步，`open` 然后
  `ioctl(FBIOGET_VSCREENINFO)`，把失败的 errno 打出来。

本机实测（2026-10-20，`wsl -u root`）：

```text
crw-r--r-- 1 root root 29, 0 Oct 20 19:04 fb_fake
fb_fake                open  失败 errno=19 No such device
data.txt               ioctl 失败 errno=25 Inappropriate ioctl for device
/dev/null              ioctl 失败 errno=25 Inappropriate ioctl for device
```

三件事对账，解释这两行失败：

```text
$ grep -n 'fb' /proc/devices
13: 29 fb
$ ls /sys/class/graphics/
fbcon
$ ls -l /dev/fb*
ls: cannot access '/dev/fb*': No such file or directory
```

WSL 的内核编进了 fb 核心（29 号登记在册），但没有任何显示驱动实例登记进来
（`/sys/class/graphics/` 下只有 fbcon 这个控制台层，`/dev/fb0` 不存在）。所以：

    ENODEV (19)   open 就失败:主设备号 29 有主,但次设备号 0 没有对应实例
    ENOTTY (25)   open 成功了:但这个驱动不认这个请求码(普通文件、/dev/null 都是)

两个 errno 卡的是两道不同的门，这就是 1.3 节调试 ioctl 时的路标。mknod 本身的
两个边界也记一下：在 `/mnt/e`（Windows 盘的 DrvFs）上 mknod 报
`Operation not supported (os error 95)`；`/tmp` 是带 `nodev` 挂载标志的 tmpfs，
节点造得出来也用不了（2026-10-20 实测，`mount | grep ' /tmp '` 能看到 nodev）。

**这一节搭好的积木**：`/dev/fb0` 只是"字符设备 29:0"一条登记；open 经过 fb 核心
找到驱动实例，实例不存在报 ENODEV。接下来的问题：打开之后，怎么把分辨率、行宽、
颜色格式这些参数从驱动里问出来。

### 1.3 [做 L2] fbinfo：把驱动知道的全部问出来

#### ioctl 是什么

04 篇的 read/write 只能搬数据流。"把屏幕参数填进我给的结构体"这种请求没有对应
的读写语义，Unix 留了一个兜底口子：**ioctl**（`man 2 ioctl`）：

```c
int ioctl(int fd, unsigned long request, ...);
```

- `fd`：已打开的设备。
- `request`：请求码，一个整数，驱动按它分辨"你要干什么"。framebuffer 的这一组
  定义在 `<linux/fb.h>` 里。
- 第三个参数按请求码定，这两个请求码都要"一个结构体的地址"：内核把参数填进这个
  结构体。fb 核心收到请求码后做的事很直白（fbmem.c 的 `do_fb_ioctl`）：
  `FBIOGET_VSCREENINFO` 就把驱动登记的 `info->var` 原样 `copy_to_user` 给你，
  `FBIOGET_FSCREENINFO` 就给你 `info->fix`。
- 返回值：成功 0，失败 -1 并置 errno（比如 1.2 节见到的 ENOTTY）。

framebuffer 给应用两类参数，名字就写在请求码里：

| 请求码 | 值（本机实测） | 填的结构体 | 装什么 |
|---|---|---|---|
| `FBIOGET_VSCREENINFO` | 0x4600 | `struct fb_var_screeninfo` | 可变参数：分辨率、bpp、颜色位段、时序 |
| `FBIOGET_FSCREENINFO` | 0x4602 | `struct fb_fix_screeninfo` | 固定参数：显存物理地址、大小、行宽 |

（"值"一列用本机实测小程序打印，见延伸 A；0x4600/0x4602 是不带结构体大小的裸
数字，它的后果也在延伸 A。）

#### 程序：两个 ioctl 问出全部参数

实验 `Knowledge/labs/05_framebuffer/fbinfo.c`，完整代码：

```c
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <linux/fb.h>

int main(int argc, char **argv)
{
    const char *dev = argc > 1 ? argv[1] : "/dev/fb0";
    struct fb_var_screeninfo var;
    struct fb_fix_screeninfo fix;
    int fd = open(dev, O_RDWR);

    if (fd < 0) {
        printf("open %s 失败: %s\n", dev, strerror(errno));
        return 1;
    }
    if (ioctl(fd, FBIOGET_FSCREENINFO, &fix) < 0) {
        printf("ioctl 失败: %s\n", strerror(errno));
        return 1;
    }
    if (ioctl(fd, FBIOGET_VSCREENINFO, &var) < 0) {
        printf("ioctl 失败: %s\n", strerror(errno));
        return 1;
    }
    /* ... 打印所有字段,再做三笔对账,见 labs 源码 ... */
}
```

逐块读：

- `const char *dev = argc > 1 ? argv[1] : "/dev/fb0";`：命令行给了路径就用给的，
  没给就用 `/dev/fb0`。这样电脑上可以拿 `/dev/null` 试报错分支。
- 两个结构体都在栈上声明，把地址交给 ioctl 去填。`var` 是"可变"（可以
  FBIOPUT_VSCREENINFO 改），`fix` 是"固定"（由驱动和硬件定）。
- 每次系统调用回来都查返回值：`< 0` 就打印 errno 的文字（`strerror`）并退出。

先在 WSL 里把报错分支跑出来（电脑上 open 成功、ioctl 撞到 1.2 节的第二道门）：

```bash
cd /mnt/e/Workspace/Embeded/Embedded-linux/Knowledge/labs/05_framebuffer
gcc -Wall -Wextra -O2 fbinfo.c -o /tmp/fbinfo
/tmp/fbinfo /dev/null; echo exit=$?
```

本机实测（2026-10-20）：

```text
ioctl 失败: Inappropriate ioctl for device
exit=1
```

再交叉编译静态版上板（为什么必须 `-static`，01 篇第 5.3 节用 `GLIBC_2.34 not
found` 讲透了）：

```bash
arm-linux-gnueabihf-gcc -static -O2 -Wall -Wextra fbinfo.c -o fbinfo_arm
```

**两个平台的程序必须分开编**：`fb_fix_screeninfo` 在 x86-64 上占 80 字节、在 ARM
上占 68 字节，而这两个请求码里不带结构体大小，内核按自己编译时的布局往回拷。
用错平台编出来的程序读到的全是错位数据。结构体怎么错位的，延伸 A 有实测。

板上实测（2026-09-14 归档，未插显示器；只保留与本章有关的列）：

```text
[fix] id=mxs-lcdif smem_start=0x8c100000 smem_len=33554432 line_length=4096
[var] xres=1024 yres=600 bpp=32
[var] red=16/8 green=8/8 blue=0/8 transp=0/0 (offset/length)
[var] pixclock=20000 ps  left=140 right=160 hsync=20  upper=20 lower=12 vsync=3
对账1 行宽: xres*bpp/8=4096  line_length=4096  相等
对账2 大小: 可见区=2457600  smem_len=33554432  smem_len/可见区=13.65
对账3 刷新: 像素时钟=50.000 MHz  一行=1344 像素  一帧=635 行  帧率=58.586 Hz
```

把两个结构体的字段逐个读一遍：

`fb_fix_screeninfo`（"这块显存是什么"）：

- `id=mxs-lcdif`：驱动自己的名字。NXP 的 mxsfb.c 里就是
  `sprintf(fb_info->fix.id, "mxs-lcdif")`。
- `smem_start=0x8c100000`：显存的**物理地址**。应用在用户态拿不到物理地址，这个
  字段的价值是对账：1.4 节 mmap 之后、4.2 节看别的进程的映射表，都会再见到它。
- `smem_len=33554432`：显存总大小，32 MiB。一屏只要 2457600 字节（2.3 MiB 多
  一点），驱动分了 13.65 屏。这个数第 4.5 节截屏时是关键。
- `line_length=4096`：**一行在显存里占多少字节**。第 2 节的主角。

`fb_var_screeninfo`（"现在按什么方式解释这块显存"）：

- `xres=1024 yres=600`：可见分辨率。
- `bpp=32`：每个像素占 32 位。
- `red=16/8 green=8/8 blue=0/8 transp=0/0`：红绿蓝三个分量各自从整数的第几位
  开始、占几位（offset/length）。第 3 节的主角。`transp`（透明度）长度 0，表示
  这 32 位的高 8 位没有用。这个布局叫 xRGB8888。
- `pixclock=20000 ps`：一个像素时钟 20000 皮秒，即 20 ns。
- `left=140 right=160 hsync=20 upper=20 lower=12 vsync=3`：行场时序里的空白与
  同步宽度。一行实际扫 1344 拍，只有 1024 拍是画面；一帧实际扫 635 行，只有
  600 行是画面。完整解释见[11 显示原理](../../fundamentals/11_显示原理.md)第 2 节。

程序末尾的"三笔对账"是本章的判据手法：每个关键数都从两条独立的路拿到，对上才
算数。

**对账 1（行宽）**：`xres*bpp/8 = 1024*32/8 = 4096`，和驱动给的 `line_length`
相等。为什么"恰好相等"不等于"永远相等"，2.3 节专门做一个不相等的实验。

**对账 2（大小）**：可见区 = 1024×600×4 = 2457600 字节；`smem_len` 是它的
13.65 倍。

**对账 3（刷新率）**：从时序参数亲手算出帧率：

    像素时钟 = 10^12 ps / 20000 ps = 50 000 000 Hz = 50.000 MHz
    一行     = 1024 + 140 + 160 + 20 = 1344 拍
    一帧     = 600 + 20 + 12 + 3 = 635 行
    行频     = 50 000 000 / 1344 ≈ 37202 Hz = 37.202 kHz
    帧率     = 37202 / 635 ≈ 58.586 Hz          ← 1.1 节"每秒读 58.586 遍"的出处

另一组独立的数从板上的现成工具拿（2026-09-14 归档）：

```powershell
.\Tools\serial-board.ps1 'cat /sys/class/graphics/fb0/stride; fbset -i -fb /dev/fb0'
```

```text
4096
mode "1024x600-59"
    # D: 50.000 MHz, H: 37.202 kHz, V: 58.586 Hz
    geometry 1024 600 1024 600 32
    timings 20000 140 160 20 12 20 3
    rgba 8/16,8/8,8/0,0/0
    Address: 0x8c100000
```

逐项对上：sysfs 的 `stride`（行宽）= 4096 = 对账 1；fbset 的 D/H/V 三个频率 =
对账 3 逐个相等；`geometry` 里 1024 600 出现两次，前两个是可见分辨率，后两个是
虚拟分辨率（驱动把两者设成一样，mxsfb.c 的 `mxsfb_check_var` 里就是
`var->xres_virtual = var->xres; var->yres_virtual = var->yres;`）；`timings` 的
七个数和 var 的七个时序字段逐个相等；`rgba` 是 length/offset 顺序（和 fbinfo 打印
的 offset/length 相反），8/16 就是 red 从第 16 位起占 8 位；`Address` =
`smem_start`。

**注错见红**：帧率公式如果忘了加空白和同步，结果错得不多、看起来还很正常。编译
两个注错版上板（2026-09-14 归档）：`-DBUG_VTOTAL` 一帧只按 600 行算，
`-DBUG_HVTOTAL` 一行只按 1024 拍、一帧只按 600 行算：

```text
正确版:        一行=1344  一帧=635  帧率=58.586 Hz   ← 与 fbset 的 V 一致
BUG_VTOTAL:    一行=1344  一帧=600  帧率=62.004 Hz
BUG_HVTOTAL:   一行=1024  一帧=600  帧率=81.380 Hz
```

62 Hz 和 81 Hz 都"像个正常的刷新率"，单看自己的输出判断不出错。只有和 fbset 这
另一条路对到帧率这一级才抓得住；第一个注错版的行频还是对的，只对行宽、行频就会
漏掉它。

顺带纠正一个容易有的印象："描点只需要 var 里的分辨率和 bpp，fix 那些固定参数
用不上。"1.3 的对账已经用掉了 fix 的 `line_length` 和 `smem_len`：描点公式要
行宽（2.1 节），截屏要知道只读多少（4.5 节坑 6），少一个都出事。

**这一节搭好的积木**：ioctl 两个请求码把驱动知道的全问出来了，而且每个数都有
第二条路对账。还差最后一步：应用在用户态，怎么摸得到物理地址 0x8c100000 那块
内存。

### 1.4 mmap：把显存搬进进程的地址空间

`open` 给了一个 fd，`ioctl` 告诉了参数，但写到 `/dev/fb0` 的每个字节若都走
`write`，每个像素都要进一次内核。04 篇 mmap 一节（04 篇第 7.1 节）
处理过同构的问题：让指针直接指到那块内存，写内存就是写设备。

```c
unsigned long size = (unsigned long)fix.line_length * var.yres;
unsigned char *fb_base = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
```

- 映射长度：`line_length × yres`，一屏实际占用的字节数。**不要映射
  `smem_len`**：板上 smem 有 32 MiB 而一屏只有 2.4 MiB，多映射的部分会把越界写
  从"当场 SIGSEGV"变成"悄悄写坏别人的内存"（2.4 节会看到越界的下场）。
- `PROT_READ | PROT_WRITE`：这段映射可读可写。
- `MAP_SHARED`：写进这段内存的内容对其他映射同一设备的人可见，也会被显示控制器
  读到。对设备内存这是唯一合理的选择。
- 第四个参数 `fd`、第五个 `0`：从显存的开头映射。

对普通文件的 mmap 背后有页缓存；对 `/dev/fb0`，走的是驱动自己的 `mmap` 函数。
NXP mxsfb.c 里的 `mxsfb_mmap` 做两件事：把要映射的物理页（从 `smem_start` 起）
用 `remap_pfn_range` 登记进进程的页表；用 `pgprot_writecombine` 给这段映射设置
"写合并"的内存属性（4.6 节会量出它的代价）。页表、映射大小与越界的关系，见
[09 虚拟内存与 mmap](../../fundamentals/09_虚拟内存与mmap.md)第 9 节。

`mmap` 返回之后，应用手里就是一个普通指针 `fb_base`。回到 0.2 节那张图：
**open、ioctl、mmap 各进一次内核，之后 `fb_base[...] = 颜色` 就是一条普通的内存
写指令**，显示控制器下一帧扫描时自然读到新值。从应用到出光的完整路径就是图里
那条粗蓝线加右边硬件的虚线。

**这一节搭好的积木**：显存已经映射进进程，可以当数组写。接下来的问题：屏幕上
的 (x, y) 对应数组里的第几个字节。

---

## 2 像素在哪：二维坐标拍扁成一维

### 2.1 第一性原理：把行优先地数下去

显存是一维的字节串，屏幕是二维的，控制器按 1.1 节的顺序读：第 0 行从左到右，
然后第 1 行，直到最后一行。所以"第 (x, y) 个像素"在显存里的位置就是数出来的：
它前面有完整的 y 行，每行 `line_length` 字节；本行内它前面还有 x 个像素，每个
`bpp/8` 字节：

```text
offset = y * line_length + x * (bpp / 8)
地址   = fb_base + offset
```

把本板未插屏的参数（1024×600、bpp=32、line_length=4096）代进去，画出 0.1 节
那 100 个红点的第一个 (512, 300)：

```
显存按字节编址,每个像素 4 字节,一行 4096 字节:

偏移    0       4096      8192             1228800        2457600
        |        |         |                  |               |
        v        v         v                  v               v
        +--------+---------+-- ... ----------+---- ... ----+
        | 第0行   | 第1行   |               | 第300行       | ... 共 600 行
        +--------+---------+-- ... ----------+---- ... ----+
                                              ^
                              (512,300) 在 1228800 + 512*4 = 1230848

逐步代入:
  y * line_length = 300 * 4096 = 1228800    (前面 300 整行)
  x * (bpp/8)     = 512 * 4    = 2048       (本行前面 512 个像素)
  offset          = 1230848
```

图从下往上读：先算前面 300 整行的字节数，再加本行内 512 个像素的字节数，得到
偏移 1230848。2.2 节会在电脑上把这个数实测出来。

### 2.2 [做 L2] 假显存：在电脑上练描点

WSL 里没有真显存（1.2 节），用一个普通文件冒充：`open` 一个文件，`ftruncate`
撑到显存大小，`mmap(MAP_SHARED)` 映射进来，写内存，关掉后改动落回文件，再用
`od` 把文件里的字节数出来核对。文件就是我们的"显存照片"，每一字节都赖不掉。

实验 `Knowledge/labs/05_framebuffer/fakefb.c` 的结构（完整代码在 labs）：

```c
/* 用法: ./fakefb <文件> <xres> <yres> <bpp> <line_length> [fix|xres] [hline|vline] [RRGGBB] */
unsigned long size = (unsigned long)g_ll * yres;
int fd = open(path, O_RDWR | O_CREAT | O_TRUNC, 0644);
ftruncate(fd, size);                     /* 先撑到显存大小,0 字节文件 mmap 后写会 SIGBUS */
unsigned char *fb = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
memset(fb, 0xff, size);                  /* 全 1 = 白,任何布局都成立 */
/* 默认图案:屏幕正中 100 个红点 */
for (unsigned i = 0; i < 100; i++)
    put_pixel(fb, xres / 2 + i, yres / 2, 0xFF0000);
munmap(fb, size);
close(fd);                               /* MAP_SHARED,改动落回文件 */
```

参数全部从命令行来，这样板上任何一种模式都能在电脑上复现。`put_pixel` 就是
2.1 节的公式加 3.3 节的拼色，讲完第 3 节再回头看它。先跑板子同参数：

```bash
gcc -Wall -Wextra -O2 fakefb.c -o /tmp/fakefb
cd /tmp
./fakefb fb.raw 1024 600 32 4096
echo "red=$(od -An -v -tx4 -w4 fb.raw | grep -c 00ff0000) white=$(od -An -v -tx4 -w4 fb.raw | grep -c ffffffff)"
n=$(od -An -v -tx4 -w4 fb.raw | grep -n -m1 00ff0000 | cut -d: -f1)
off=$(( (n - 1) * 4 ))
echo "偏移=$off y=$((off / 4096)) x=$(( (off % 4096) / 4 ))  公式预期=$(( 300 * 4096 + 512 * 4 ))"
od -An -tx1 -j "$off" -N 4 fb.raw
```

`od` 的参数逐个说：

- `-An`：不打印每行开头的偏移列（偏移我们自己算）。
- `-v`：重复的行不折叠。少了它，od 把连续相同的行折成一个 `*`，像素就数少了。
- `-tx4 -w4`：按 4 字节一组、每行 4 字节打印，于是一行就是一个像素的值；
  `grep -c 00ff0000` 数的就是"值等于 0x00FF0000（红）的像素个数"。
- 第二条命令链：`grep -n -m1` 找第一个红像素在第几行（从 1 数），减 1 乘 4 得到
  字节偏移，再按公式反解出 y 和 x。
- 最后 `od -An -tx1 -j $off -N 4`：跳到那个偏移，逐字节看这 4 个字节。

本机实测（2026-10-20）：

```text
xres=1024 yres=600 bpp=32 line_length=4096 实际用的行宽=4096 显存=2457600 字节
red=100 white=614300
偏移=1230848 y=300 x=512  公式预期=1230848
 00 00 ff 00
```

逐行读：

- 第一行是 fakefb 自己报告的参数。
- 第二行就是 0.1 节板上数过的那两个数：红 100，白 614300，合计 614400 =
  1024 × 600。电脑上的假显存和板上的真显存数出同一组数，说明描点这件事与硬件
  无关，只与公式有关。
- 第三行：第一个红像素在偏移 1230848，反解出 y=300、x=512，和 2.1 节手工算的
  公式预期逐项相等。
- 第四行值得停下来看：程序写进去的整数是 `0x00FF0000`，文件里按字节顺序却是
  `00 00 ff 00`。这是小端：整数的最低字节放在地址最小处（x86 和本板的 ARM 都是
  小端）。所以 32bpp 像素在内存里的字节序是 **B G R X**，和整数写法
  `0x00RRGGBB` 正好倒过来。4.5 节把显存拉回电脑转图片时全靠这一条。

**这一节搭好的积木**：坐标公式在电脑上验证过了，还顺手看到小端把颜色字节的
顺序倒了过来。接下来的问题：公式里的 `line_length` 能不能用 `xres*bpp/8` 代替。

### 2.3 line_length 与 xres×bpp/8：为什么分开给

`fb_fix_screeninfo` 里单独有一个 `line_length` 字段。如果它永远等于
`xres*bpp/8`，内核没有必要多给这个数。它可能不等的两个原因：

- 有的显示控制器要求每行按 4/8/64 字节对齐，行尾要补填充字节；
- 有的驱动让虚拟行宽（`xres_virtual`）大于可见行宽，方便做双缓冲和滚屏。

本板的驱动恰好是"总是相等"的那一类：mxsfb.c 里
`line_size = fb_info->var.xres * (fb_info->var.bits_per_pixel >> 3);`，然后
`fb_info->fix.line_length = line_size;`。"恰好"两个字是关键：源码这么写，
不等于所有驱动都这么写。

用假显存把"行尾有填充"造出来，看用错公式会怎样。行宽给 4104（每行多 8 字节
填充），画一条竖线（x 固定 512，y 从 0 到 599），分两种定位方式：

```bash
./fakefb fbpad_fix.raw  1024 600 32 4104 fix  vline     # 按 line_length 定位
./fakefb fbpad_xres.raw 1024 600 32 4104 xres vline     # 按 xres*bpp/8 定位
```

然后用 awk 把每个红像素的偏移按**真实行宽 4104** 换算回坐标（控制器读显存时认
的是真实行宽）：

```bash
od -An -v -tx4 -w4 fbpad_xres.raw | awk '
  /00ff0000/ { off=(NR-1)*4; y=int(off/4104); x=int((off%4104)/4);
               if (y==0||y==100||y==300||y==598) printf "y=%d x=%d\n", y, x }'
```

本机实测（2026-10-20），两种定位并排：

```text
-- fbpad_fix.raw（按 line_length）   -- fbpad_xres.raw（按 xres*4）
   y=0    x=512                         y=0    x=512
   y=100  x=512                         y=100  x=312
   y=300  x=512                         y=300  x=936
   y=598  x=512                         y=598  x=340
   红像素=600 占了 1 个 x               红像素=600 占了 513 个 x
```

按 `line_length`：600 个点全在 x=512，一条竖线。按 `xres*4`：每往下一行，写入
位置比控制器认为的行起点早 8 字节，也就是左偏 2 个像素；第 100 行已经偏了
200 个像素（x=312）；偏过行首还会绕回上一行行尾（第 300 行出现在 x=936）。
屏幕上看到的会是一条斜拉满屏的线。

内存里发生的事情：

```
line_length = 4104 时,一行长这样:

偏移    0                    4096  4104
        |                       |     |
        v                       v     v
        +-----------------------+-----+-----------------------+--
        | 第0行 1024 个像素      |填充8B| 第1行 1024 个像素      |
        +-----------------------+-----+-----------------------+--

按 4096 算行起点:第 y 行起点写成 y*4096,比真实的 y*4104 每次早 8 字节
```

**描点公式只用 `line_length`，"它什么时候等于 `xres*bpp/8`"这个条件就不用记了。**

### 2.4 [做 L1] 越界的点去哪了

描点函数 `put_pixel` 不检查坐标。越界分两种，下场完全不同。实验
`probe/oob.c` 各做一个：`wrapx` 在 (1024, 100) 画一个点（x 越右界一个像素），
然后全图扫描找到它实际落在哪；`beyondy` 在 (0, 600) 画一个点（y 已经越出整个
映射区）。本机实测（2026-10-20）：

```text
$ ./oob oob.raw wrapx
映射 2457600 字节, 地址 0x7d4a955a8000..0x7d4a95800000
画在 (1024,100), 实际落在 (0,101)

$ ./oob oob.raw beyondy; echo exit=$?
映射 2457600 字节, 地址 0x7bfecf9a8000..0x7bfecfc00000
写 (0,600) -> 地址 0x7bfecfc00000
Segmentation fault (core dumped)
exit=139
```

- **x 越界不报错**：公式 `y*line_length + x*4` 照算，(1024,100) 算出来的偏移恰好
  是 (0,101)，点出现在下一行行首。这比崩溃更难查：程序正常结束，屏幕左缘多了
  一个不知哪来的点。
- **y 越出映射区**：地址 0x7bfecfc00000 正好是映射区终点（
  0x7bfecf9a8000 + 2457600），页表里没有这一页，CPU 访存异常，内核发 SIGSEGV，
  退出码 139 = 128 + 11（SIGSEGV 的编号，01 篇第 1.3 节的退出码规则）。

板上对真 `/dev/fb0` 做过同构实验（2026-09-14 归档）：(1024,100) 同样落在
(0,101)，(0,600) 同样退出 139。**板上显存明明有 32 MiB，照样段错误**：能不能
访问一块内存，看你 mmap 了多少，不看驱动分了多少（页表只登记了映射的那一屏，
[09 虚拟内存与 mmap](../../fundamentals/09_虚拟内存与mmap.md)第 9 节）。这也是 1.4 节"只映射一屏"的理由：映射一屏时越界
写当场崩溃，映射 32 MiB 时同样的 bug 会悄悄写进显存里没人看的角落。

所以描点函数要么自己查边界，要么在接口上约定"调用者不越界"。Project 的 display
层选了前者（第 6 节）。

### 2.5 [判] 第 2 节

    [ ] 1024x600x32、行宽 4096:红 100 白 614300;第一个红像素偏移=1230848
    [ ] 那个像素的 4 个字节按序是 00 00 ff 00(小端,内存里是 B G R x)
    [ ] 行宽 4104:按 line_length 画竖线只占 1 个 x;按 xres*4 占 513 个 x,
        第 100 行偏到 x=312
    [ ] (xres,100) 落到 (0,101);(0,yres) 退出码 139

    注错见红:用 -DBUG_ROW_NO_PW 编译 fakefb(行起点写成 y*xres,忘了乘每像素
    字节数):红像素还是 100 个,计数判据全绿,但点整整齐齐画到了第 75 行
    (300/4),第一个红像素偏移=309248。位置对账才抓得住(2026-10-20 实测)。
    **计数型判据只能证明"写了多少",证明不了"写在哪";每组判据至少带一条
    位置对账。**

---

## 3 颜色怎么拼：位段

### 3.1 一个像素就是几个位段拼起来

定位解决了"写到哪里"，还剩"写什么"。一个像素占 bpp 位，哪几位是红、哪几位是
绿蓝，由驱动决定，通过 `var.red/green/blue` 的 offset/length 告诉应用。这样
"一个整数里连续的若干位"叫**位段**；offset 从整数的最低位（第 0 位）数起。

本板见过的两种布局（1.3 节和第 5 节各遇到一种）：

```
32bpp,xRGB8888(red=16/8 green=8/8 blue=0/8 transp=0/0):

 位号     31        24 23        16 15         8 7          0
           +----------+-----------+-----------+-----------+
 整数:     | X 未用    | R 8 位    | G 8 位    | B 8 位    |
           +----------+-----------+-----------+-----------+
 内存字节:  第3字节     第2字节     第1字节     第0字节(低地址)
           (小端:整数的低字节放低地址,所以文件里看到 B G R X)

16bpp,RGB565(red=11/5 green=5/6 blue=0/5):

 位号     15      11 10       5 4        0
           +---------+----------+----------+
 整数:     | R 5 位  | G 6 位   | B 5 位   |
           +---------+----------+----------+
           绿多 1 位:16 位分给三色,多出的一位给绿(人眼对绿最敏感)
```

两张图对照着看：位号从右往左数，`red=16/8` 就是"从第 16 位起占 8 位"。整图版：

![图 6　RGB 位段与 565 压色](fig/05-rgb格式与565压色.svg)

这里要澄清一个常见写法。很多描点例程在 32bpp 分支里直接 `*pen_32 = color`，
前提是"调用方传来的颜色恰好就是 0x00RRGGBB，而驱动的位段恰好也是
red=16/8 green=8/8 blue=0/8"。两个"恰好"在本板未插屏时都成立，代码就是对的；
换一块位段是 BGR（red=0/8 blue=16/8）的屏，同样的代码红蓝对调。**直接写成立与
否取决于驱动报的位段，不取决于 bpp。** 本章 labs 里的程序一律按 var 里的位段拼
（3.3 节），就不依赖这个巧合。

### 3.2 [做 L1] 888 压成 565 丢了多少

16bpp 要把 8 位的分量压成 5/6 位，丢掉的位真的丢了。实验 `probe/rgb565.c` 把
2^24 种 RGB888 颜色全部压一遍、再读回来对照：

```bash
gcc -Wall -O2 probe/rgb565.c -o /tmp/rgb565
/tmp/rgb565
```

本机实测（2026-10-20）：

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

读法：

- 16777216 种颜色压完只剩 65536 种，平均 256 种 888 颜色共用一个 565 值。
- "读回"是把 5/6 位放大回 8 位，有两种做法：**补 0**（只左移）和**复制高位到
  低位**。纯白补 0 读回是 `0xF8FCF8`，偏灰；复制高位保住了纯白。中灰
  `0x808080` 恰好反过来：补 0 读回原值，复制高位变成 `0x848284`。**两种放大各有
  对的时候，丢掉的位就是丢了。**
- 工程含义：16bpp 屏上"写进去再读出来比较"的判据，必须按 565 的值比，不能按
  888 的原值比（第 5 节判据里红色就是数 `f800`）。

### 3.3 [做 L2] 按位段拼色，不写死 switch

拼一个分量只要两步：**砍到位数（右移 8-length），挪到位置（左移 offset）**：

```c
r = (r >> (8 - var.red.length))   << var.red.offset;
g = (g >> (8 - var.green.length)) << var.green.offset;
b = (b >> (8 - var.blue.length))  << var.blue.offset;
```

fakefb 的 `put_pixel` 就是这么拼的，然后按 bpp 选 2 字节还是 4 字节写。把 888
压进 565 的取位过程画出来：

```
R888:  R7 R6 R5 R4 R3 R2 R1 R0
        |  |  |  |  |                    右移 3 位,丢掉低 3 位
        v  v  v  v  v
R565:  R7 R6 R5 R4 R3  << 11             再左移到第 11 位

G888:  8 位 -- 右移 2 位 --> G7..G2 << 5  (6 位)
B888:  8 位 -- 右移 3 位 --> B7..B3       (5 位,offset=0 不用再移)
```

用 16bpp 假显存验证三原色（画一整行横线，1024 个像素同色）：

```bash
./fakefb f16.raw 1024 600 16 2048 fix hline FF0000
od -An -v -tx2 -w2 f16.raw | awk '{c[$1]++} END{for(k in c) if(k!="ffff") print k, c[k]}'
```

本机实测（2026-10-20）：

```text
FF0000 -> f800 x1024      (0xff>>3=31, 31<<11=0xF800)
00FF00 -> 07e0 x1024      (0xff>>2=63, 63<<5 =0x07E0)
0000FF -> 001f x1024      (0xff>>3=31, 31<<0 =0x001F)
```

**注错见红，而且是一个会假绿的错**：用 `-DBUG_565_SWAP` 编译 fakefb，把红绿的
位数写反（红取 6 位、绿取 5 位）：

```text
BUG_565_SWAP:  FF0000 -> f800 x1024      ← 和正确版一模一样!
BUG_565_SWAP:  00FF00 -> 03e0 x1024      ← 错的,正确值是 07e0
BUG_565_SWAP:  0000FF -> 001f x1024
```

纯红那条为什么假绿：0xff>>2=63，63<<11=0x1F800，写进 16 位的 `unsigned short`
时超出的位被丢掉，恰好剩 0xF800，和正确值相同。**判据只测红色，这个 bug 永远
发现不了；颜色判据三原色各测一次。**

### 3.4 memset 为什么能清成白色

`memset(fb_base, 0xff, screen_size)` 能把整屏清成白色，因为**所有位都是 1** 在
任何 RGB 位段布局下三个分量都是满值，都是白；同理填 0 是黑。想清成红色就不行：
memset 按字节填，32bpp 的红色在内存里是 `00 00 ff 00` 四个不同的字节，没有
单一字节能填出来。整屏填一种非黑白的颜色，快办法是先填好第一行、再按行
`memcpy`；但注意 4.6 节的实测，源行要放在普通内存里，不能从显存读。

### 3.5 [判] 第 3 节

    [ ] rgb565:16777216 种压成 65536 种;纯白补 0 读回是 0xF8FCF8
    [ ] 位段拼色:565 三原色分别是 f800 / 07e0 / 001f,说得出每个数怎么移出来的
    [ ] 注错 BUG_565_SWAP:纯红假绿(f800),纯绿变成 03e0;说得出为什么红色隐身

---

## 4 上板：这块内存不止你一个人在写

本节板测全部是**未插显示器**状态（1024×600×32、行宽 4096），输出为 2026-09-14
归档。流程与 01 篇第 4 节相同：WSL 交叉编译静态程序打 tar，串口分块校验上传，
板上 `dd` 回读 `/dev/fb0`，再下载回电脑转 PNG。当时的上传实录（一次真实的损坏
重传，01 篇第 4.7 节的机制在工作）：

```text
警告: block 6/17 arrived damaged (attempt 1), sending it again
fbboard.tar -> /tmp/ch03/fbboard.tar: 983040 bytes, 17 blocks, 1 resent, 70.8 s, sha256 OK
```

### 4.1 [做 L1] show_pixel：完整程序逐行讲

实验 `Knowledge/labs/05_framebuffer/show_pixel.c`，把第 1~3 节合成一个程序：清屏
成白，正中间画 100 个红点。完整源码：

```c
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <linux/fb.h>

static int fd_fb;
static struct fb_var_screeninfo var;   /* 可变参数:分辨率、bpp、位段 */
static struct fb_fix_screeninfo fix;   /* 固定参数:行宽、显存地址与大小 */
static unsigned char *fb_base;
static unsigned long screen_size;
static unsigned pixel_width;

/* 在 (x, y) 处描一个点。颜色传进来一律是 0x00RRGGBB */
static void lcd_put_pixel(unsigned x, unsigned y, unsigned color)
{
    unsigned char  *pen_8  = fb_base + y * fix.line_length + x * pixel_width;
    unsigned short *pen_16 = (unsigned short *)pen_8;
    unsigned int   *pen_32 = (unsigned int *)pen_8;
    unsigned r, g, b, v;

    switch (var.bits_per_pixel) {
    case 8:
        *pen_8 = color;                  /* 8bpp 是调色板编号,本章不展开 */
        break;
    case 16:                             /* 本板插显示器后是 RGB565 */
    case 32:                             /* 本板未插屏时是 xRGB8888 */
        r = (color >> 16) & 0xff;
        g = (color >> 8)  & 0xff;
        b =  color        & 0xff;
        v = ((r >> (8 - var.red.length))   << var.red.offset)
          | ((g >> (8 - var.green.length)) << var.green.offset)
          | ((b >> (8 - var.blue.length))  << var.blue.offset);
        if (var.bits_per_pixel == 16)
            *pen_16 = v;
        else
            *pen_32 = v;
        break;
    default:
        printf("can't support %ubpp\n", var.bits_per_pixel);
        break;
    }
}

int main(int argc, char **argv)
{
    const char *dev = argc > 1 ? argv[1] : "/dev/fb0";
    int i;

    fd_fb = open(dev, O_RDWR);
    if (fd_fb < 0) {
        printf("open %s 失败: %s\n", dev, strerror(errno));
        return 1;
    }
    if (ioctl(fd_fb, FBIOGET_VSCREENINFO, &var) < 0) {
        printf("can't get var: %s\n", strerror(errno));
        return 1;
    }
    if (ioctl(fd_fb, FBIOGET_FSCREENINFO, &fix) < 0) {
        printf("can't get fix: %s\n", strerror(errno));
        return 1;
    }

    pixel_width = var.bits_per_pixel / 8;
    screen_size = (unsigned long)fix.line_length * var.yres;

    fb_base = mmap(NULL, screen_size, PROT_READ | PROT_WRITE, MAP_SHARED, fd_fb, 0);
    if (fb_base == MAP_FAILED) {
        printf("can't mmap: %s\n", strerror(errno));
        return 1;
    }

    memset(fb_base, 0xff, screen_size);       /* 清屏:全 1 在任何布局下都是白 */

    for (i = 0; i < 100; i++)                 /* 屏幕正中横着画 100 个红点 */
        lcd_put_pixel(var.xres / 2 + i, var.yres / 2, 0xFF0000);

    munmap(fb_base, screen_size);
    close(fd_fb);
    return 0;
}
```

逐块读，每一块都对应前面某节的积木：

- 全局变量那几行：`var`/`fix` 是 1.3 节 ioctl 要填的两个结构体；`fb_base` 是
  1.4 节 mmap 返回的显存指针；`pixel_width` 是每个像素的字节数。
- `lcd_put_pixel` 第一行：`fb_base + y * fix.line_length + x * pixel_width` 就是
  2.1 节的公式，`fix.line_length` 是 2.3 节的教训（不用 `xres*bpp/8` 代替）。
  算出来的是字节地址 `pen_8`；`pen_16`、`pen_32` 是同一个地址的两种看法，按
  bpp 选一种写。
- 16/32bpp 两个分支共用 3.3 节的两步拼色：先 `>>` 砍到位数，再 `<<` 挪到
  `var.red.offset` 等位段位置。位段全部来自运行时读到的 `var`，不写死 565 或
  8888，第 5 节插上显示器 bpp 变成 16 时这个程序不用改。
- `main` 前半段：open → 两个 ioctl（顺序无所谓）→ 由 `line_length × yres` 算出
  一屏大小 → mmap（1.4 节，只映射一屏）。
- `memset(fb_base, 0xff, screen_size)` 清成白（3.4 节）；`for` 循环 100 次描点，
  位置 (512..611, 300)，即 0.1 节那 100 个红点。
- `munmap` + `close` 收摊。MAP_SHARED 的写在赋值那一刻就已经进了显存，munmap
  只是拆掉自己这边的映射。

编译两个平台。本机跑出错分支（2026-10-20 实测）：

```bash
gcc -Wall -Wextra -O2 show_pixel.c -o /tmp/show_pixel
/tmp/show_pixel /dev/null; echo exit=$?
```

```text
can't get var: Inappropriate ioctl for device
exit=1
```

上板版本：

```bash
arm-linux-gnueabihf-gcc -static -O2 -Wall -Wextra show_pixel.c -o show_pixel_arm
```

先不急着运行：板上还有别人在写这块显存。

### 4.2 找出占着屏幕的程序

板子出厂带一个 GUI（`mxapp2`，Qt 程序，由开机脚本 `/etc/init.d/S99myirhmi2`
拉起，环境变量 `QT_QPA_PLATFORM=linuxfb`，Qt 的 linuxfb 后端就是直接写
framebuffer）。证明它此刻正在用 fb0，看它的文件描述符表和映射表
（2026-09-14 归档）：

```text
ls -l /proc/<pid>/fd | grep fb     →  4 -> /dev/fb0
grep /dev/fb0 /proc/<pid>/maps     →  71153000-73153000 rw-s 8c100000 00:06 9788  /dev/fb0
```

maps 那一行逐列读：

- `71153000-73153000`：映射在 GUI 进程里的虚拟地址范围，长度 0x2000000 =
  **32 MiB，GUI 把整块显存都映射了**。
- `rw-s`：可读可写，`s` 是 shared，即 MAP_SHARED。
- `8c100000`：这一列是映射在设备文件里的偏移。它等于 `smem_start`，因为 mxsfb
  的 mmap 把偏移改写成了物理页号（延伸 C）。到这里，同一块显存的起始地址
  0x8c100000 已经从三条独立的路拿到了：fbinfo 的 ioctl、fbset 的 Address、
  GUI 的 maps。

### 4.3 GUI 在跑时画一条线：回读计数

1.1 节说过控制器不管是谁写的。那么 GUI 在跑时强行画线，会发生什么？用数字回答
而不用眼睛：画完立刻把显存读回来数，隔 3 秒再数一次（2026-09-14 归档）：

```text
red now: 100  white now: 613889      ← 白像素比应有的 614300 少了 411
red after 3s: 100  white after 3s: 613887
```

再用 `cmp -l` 比较两次截屏的全部差异字节，换算回坐标框：

```text
changed bytes=92 box x=997..1002 y=8..16
```

3 秒里全屏 2457600 字节只有 92 个变了，全在右上角一个 6×9 像素的小框里；把那块
拉回图片一看，是**时钟的秒位**。结论：**GUI 不整屏重画，只重画它变化的那一小块。**
你画的东西大部分时候还在，被擦掉的只是恰好重叠的部分。这比"整屏被擦掉"难排查
得多：看起来一切正常，只有数字对不上。

### 4.4 停掉 GUI 再画

```bash
/etc/init.d/S99myirhmi2 stop          # 等效于 killall mxapp2
pidof mxapp2                          # 必须等它输出为空
```

归档里记过一次实测：连着两次 stop 后等 1 秒查 `pidof`，一次为空、一次还有 pid。
原因：killall 发的是 SIGTERM，**信号递到就返回**，进程收到后要走完自己的清理才
真正退出（[12 进程与信号](../../fundamentals/12_进程与信号.md)第 5 节里量过：装了处理函数的程序收到 SIGTERM 后又活了
2 秒）。所以可靠的停法是停完轮询 `pidof` 到空，再动手画。

GUI 停干净后再跑 show_pixel，回读计数（2026-09-14 归档）：

```text
red: 100  white: 614300               ← 与 2.2 节假显存逐项相等
两次隔 3 秒的 dd 回读,md5 相同         ← 屏幕上只剩你一个写者
```

0.1 节预告的三个数在这里兑现：电脑上假显存算出来的、板上真显存读回来的，逐项
相等。恢复 GUI：`/etc/init.d/S99myirhmi2 start`（会把 Qt 的日志混进串口输出），
或者重启板子。

### 4.5 不插显示器也能截屏

显存是普通内存，`dd` 能把整屏原样读出来，拉回电脑转成图片看：

```powershell
.\Tools\serial-board.ps1 'dd if=/dev/fb0 bs=4096 count=600 of=/tmp/ch03/line.raw 2>/dev/null'
.\Tools\serial-board.ps1 -Download /tmp/ch03/line.raw -To .\Knowledge\labs\05_framebuffer\line.raw
python3 Knowledge/labs/05_framebuffer/probe/raw2png.py line.raw 1024 600 4096 line.png
```

- `bs=4096 count=600`：一块正好是 `line_length`，600 块正好一屏。**必须带
  count**：不带的话 dd 会一直读到设备报告"没有更多数据"，而驱动报告的总长是
  `smem_len` = 32 MiB（内核 fbmem.c 的 `fb_read` 按 `screen_size` 报总长，NXP
  驱动把 `screen_size` 设成了整个 `smem_len`），2.4 MiB 的一屏会变成 32 MiB，
  串口传 13 倍的数据。这就是坑 6。
- `probe/raw2png.py` 只用 Python 标准库写 PNG，核心一件事：把每个像素的
  `B G R x`（2.2 节的小端字节序）重排成 RGB。16bpp 模式按 RGB565 解，5/6 位
  分量用"复制高位"放大（3.2 节）。

本机实测（2026-10-20，用 2.2 节的假显存 fb.raw 走同一转换）：

```text
$ python3 probe/raw2png.py fb.raw 1024 600 4096 fb.png
fb.png: 1024x600, 2705 字节
```

归档里记过串口传两张截屏的耗时：白底加红线那张 gzip 后 2440 字节，0.6 秒；
GUI 画面那张 659624 字节，79 秒。**串口截屏的耗时取决于画面能压多小**，反复
截屏时把背景弄成纯色。

GUI 截屏还有一个发现：整帧 614400 个像素里，**高 8 位不是 0xff 的一个都没有**
（GUI 写的像素高字节是 0xff，show_pixel 写的是 0x00；fb0 的 `transp=0/0`，控制器
不读这 8 位，两种写法显示都正常）。所以回读比颜色时，高 8 位要么屏蔽掉，要么
和写入方约定好，否则 `grep -c 00ff0000` 只数得到自己写的点（坑 7）。

### 4.6 读显存比写显存慢 10 倍

`probe/rwbench.c`：同样 2.4 MiB 一次 memcpy，三个方向各跑 5 轮取最短
（2026-09-14 板上归档，跑过两遍取稳定值）：

```text
写 内存->显存     4.9 ms    481 MiB/s
读 显存->内存    49.8 ms     47 MiB/s      ← 慢 10 倍
对照 内存->内存    6.2 ms    378 MiB/s
```

原因的方向在驱动源码里：mxsfb 的 mmap 给这段映射设了 `pgprot_writecombine`
（写合并）内存属性（延伸 B），名字就说明它冲着写优化。读慢 10 倍是实测；CPU 在
这种内存类型上怎么处理读，没做进一步实验，不下结论。

`probe/fillbench.c` 再量"整屏涂色"的三种写法（-O2 与 -fno-inline 各一组）：

```text
                    -O2(内联)   -fno-inline
A 逐点写显存         2.5 ms      17.2 ms     ← 关掉内联涨 7 倍:函数调用比写内存贵
B 逐行 memcpy       50.5 ms      50.4 ms     ← 源数据从显存读,慢在读(≈rwbench 的 49.8)
C 离屏画完一次拷贝    7.4 ms      22.4 ms     ← 比 A 多出的 ≈5 ms 是最后那次 memcpy
```

三条设计结论（Project display 层的依据）：

1. **显存当只写的用**：要读回的内容（背景、界面），自己在普通内存留一份。
2. 画大量像素时，**接口粒度应该是一块而不是一个点**：A 组关掉内联后涨 7 倍，
   函数调用的开销比写内存本身还大。
3. **离屏画完一次拷贝**只多约 5 ms，换来屏幕上永远不会出现画了一半的帧。

### 4.7 [判] 上板清单（归档判据，板子在线时照此复跑）

    [ ] GUI 的 maps 里 /dev/fb0 那行的偏移列 == smem_start(0x8c100000)
    [ ] GUI 在跑:画线后白像素 < 614300;cmp 的变化框落在时钟秒位
    [ ] GUI 停掉:pidof 为空;红 100 白 614300;隔 3 秒两次 dd 的 md5 相同
    [ ] line.raw 下载 sha256 OK,转 PNG 是白底红线;gui.raw 高字节非 ff 的像素为 0
    [ ] oob:(1024,100) 落到 (0,101);(0,600) 退出码 139
    [ ] rwbench 读显存比写慢约 10 倍;fillbench 三条结论说得出

---

## 5 插上 HDMI 显示器以后

i.MX6ULL 只有 LCDIF 一个显示控制器，输出的是并行 RGB；板上的 HDMI 口是另一颗
芯片 SiI9022（挂在 I2C 总线上，地址 1-0039）转换出来的，驱动经 I2C 配置它。
未插屏时读 `/sys/bus/i2c/devices/1-0039/cable_state` 是 `plugout`。

插线会发生什么，由驱动决定：sii902x 检测到插线后读显示器的 EDID（显示器自己
存的"我支持哪些模式"清单，[11 显示原理](../../fundamentals/11_显示原理.md)第 7 节），从中选一个模式，然后**把 framebuffer
的分辨率改掉**。板上实测（2026-09-14 归档，GUI 保持停止）：

```text
cable_state: plugin
dmesg 一行都没多(全是开机 1.2 秒内打的)      ← 驱动改了模式却不留日志
modes: 从 1 行变成 18 行(显示器 EDID 报上来的模式清单)
fbinfo: xres=1280 yres=720 bpp=16 line_length=2560
        red=11/5 green=5/6 blue=0/5 (RGB565)
        对账3: 74.250 MHz / 1650 像素 / 750 行 / 60.000 Hz   ← 与 fbset 逐个相等
smem_start / smem_len 没变                    ← 同一块内存,解释方式变了
```

两个数字变了要留意：bpp 从 32 降到 16，颜色格式从 xRGB8888 变成 RGB565；
line_length 从 4096 变成 2560（1280×2）。显示器其实报了 1920×1080，驱动为什么
选 720p、为什么 bpp 降到 16，取决于这版驱动自己的策略，拿不到那份源码的完整
逻辑就不做推测，只记实测。

这件事推翻一个容易有的印象："分辨率在驱动加载时就定死了，应用不用管。"在 HDMI
上不成立。**这就是所有程序必须运行时 ioctl 问参数、不能把 1024×600×32 写死的
原因。**

验证的方式很漂亮：同一个 show_pixel，不重编译，插着显示器照样画（判据按新
模式换数字：`dd bs=2560 count=720`，od 用 `-tx2`，红是 `f800`，白是 `ffff`）：

```text
f800: 100  ffff: 921500        合计 921600 = 1280 × 720
```

它运行时 ioctl 读到 bpp=16，自动走进 16bpp 分支，按新的位段拼色。当初把
1024、600、32 写死的话，插上显示器这一刻程序就画错了。

**彩条对账**：`probe/bars.c` 运行时读分辨率，画 8 条等宽竖彩条（红绿蓝白黄青
品红黑），四周一圈 1 像素白边，颜色全部按 var 位段拼。回读后按像素值分组计数
（2026-09-14 归档）：

```text
 114162 0000(黑)  114880 001f(蓝)  114880 07e0(绿)  114880 07ff(青)
 114162 f800(红)  114880 f81f(品)  114880 ffe0(黄)  118876 ffff(白)
合计 = 921600 = 1280 × 720;八个数逐项等于按分辨率推算的值
```

每个数都能事先算出来：1280 列分 8 条，每条 160 列；左右两条竖白边各吃掉红条和
黑条一列（159×718=114162），中间六条各 160×718=114880；白色 = 白条 114880 +
上下两行横边 2560 + 左右两列竖边 1436 = 118876。**八个数逐项相等**：颜色拼错会
让 f800 和 001f 互换位置，边框少画一圈会让红黑白三个数全变，比只数红点强得多。
截屏拉回电脑转 PNG 后肉眼确认过：颜色顺序一致，四边白框完整（2026-09-14）。

**还欠一笔**：拔掉显示器后模式是否变回 1024×600×32，未测。

---

## 6 落进 Project：display 层已在

本章的知识在 `Project/display/` 里已经落地：`disp_manager.c` 管一张后端注册表
（manager 只认函数指针表，加后端不改 manager），`framebuffer.c` 是真 fb 后端
（全项目只有它认识 `<linux/fb.h>`），`memdisp.c` 是假显存后端。整个决策过程在
[Engineering/TechReports/project/03-display层-两个后端与一张能数的图.md](../../../Engineering/TechReports/project/03-display层-两个后端与一张能数的图.md)；
本节只留三件由本章实测直接决定的事：

1. **行宽用 `fix.line_length`**（2.3 节），而且假显存后端的行宽故意带填充。
   板上两种模式的行宽都恰好等于 `xres*bpp/8`（4096 和 2560），这个错在板上永远
   看不出来，只有带填充的假显存能让它现形。
2. **接口粒度是一块而不是一个点**（4.6 节结论 2）：display 层有画点，也有区域
   刷新。
3. **越界拒绝**（2.4 节）：`put_pixel` 查边界，越界返回错误码；映射也只映射
   一屏，把越界写挡在 SIGSEGV 之前。

判据跑法（WSL 无 fb0，用 mem 后端）：

```bash
cd /mnt/e/Workspace/Embeded/Embedded-linux/Project
export DISP_DEV=mem FONT_DEV=builtin INPUT_BACKEND=replay INPUT_REPLAY=/dev/null
./build/x86/product_tool        # 日志里看 display init OK / exit OK
bash check.sh                   # display 相关的判据在 [1]~[10] 组
```

上板验收（2026-09-22 归档，不插显示器组）：停 GUI 后 disp_test 报告
`mode 1024x600x32 line_length 4096`，与 fbset 一致；dd 读回一屏交板上 count.sh
计数，与电脑假显存预演逐项相等（614359/12/12/12/4/1）；两次 dd 的 sha256 相同。
display 层的施工过程（先规格后实现的七个步骤）连同判据数字在 git 历史的上一版；
现在代码已定稿，用"读代码 + 跑判据 + 注错"代替重走。

---

## 7 回看：整章的问题链

| 问题 | 答案 | 证据在哪 |
|---|---|---|
| 屏幕上的画面谁在维持 | LCDIF 按节拍循环读显存 | 1.1 |
| 应用怎么找到这块内存 | /dev/fb0，主 29 选 fb 核心、次 0 选实例 | 1.2 |
| 分辨率、行宽、颜色格式从哪来 | ioctl 两个请求码填 var/fix 两个结构体 | 1.3 |
| 帧率 58.586 怎么算 | pixclock 与空白同步参数，行频/帧率两级 | 1.3 |
| 应用怎么摸到物理内存 | mmap，驱动把物理页登记进进程页表 | 1.4 |
| (x,y) 是第几个字节 | y*line_length + x*(bpp/8)，实测偏移 1230848 | 2.1、2.2 |
| 行宽能不能用 xres*bpp/8 | 本板恰好相等；有填充时竖线变斜线 | 2.3 |
| 越界写到哪去 | x 越界绕到下一行行首；y 越映射区 SIGSEGV | 2.4 |
| 颜色怎么变成整数 | 位段：砍到位数、挪到位置 | 3.1、3.3 |
| 888 压 565 丢多少 | 16777216 剩 65536，丢的位两种读回都救不全 | 3.2 |
| 板上的画面为什么对不上 | GUI 也在写，只重画它变化的那块 | 4.2、4.3 |
| 怎么独占屏幕 | stop 后轮询 pidof 到空再画 | 4.4 |
| 不插屏怎么看画面 | dd 回读 bs=line_length count=yres，转 PNG | 4.5 |
| 插 HDMI 后为什么要改判据 | 驱动按 EDID 改模式，bpp 32 变 16 | 5 |

---

## 8 自检

答不上来就回对应小节。每一题都能用命令或 labs 里的程序验证。

    1. 应用画一个像素发几次系统调用?屏幕为什么能跟上?              (0.2 1.1 1.4)
    2. WSL 里 mknod c 29 0 造的节点 open 报什么?和 ENOTTY 差在哪一道门?
       节点为什么不能建在 /mnt/e 下?                                 (1.2)
    3. 描点需要的数,哪些在 var、哪些在 fix?"fix 用不上"什么时候才成立? (1.3)
    4. 用 pixclock 和六个空白同步参数算出本板帧率;只用分辨率算会得几?  (1.3)
    5. fb_fix_screeninfo 在两个平台为什么不一样大?请求码能帮你发现吗?  (1.3 延伸A)
    6. 像素偏移公式是什么?"行宽等于 xres*bpp/8"的适用条件?           (2.1 2.3)
    7. 行尾有 8 字节填充却按 xres*4 定位,竖线变成什么样?第 100 行偏多少?(2.3)
    8. x 越右界一个像素落在哪?y 越出映射区呢?显存 32 MiB 为什么还段错误?(2.4)
    9. 只数红像素个数的判据会放过哪种 bug?                           (2.5)
   10. 888 压 565 剩几种颜色?纯白补 0 读回为什么偏灰?                (3.2)
   11. 按位段拼一个分量是哪两步?                                     (3.3)
   12. 565 红绿位数写反,为什么纯红测不出来?                          (3.3)
   13. memset 为什么能清成白、清不成红?                              (3.4)
   14. 怎么证明 GUI 在用 /dev/fb0?maps 偏移列的 8c100000 是什么?    (4.2 延伸C)
   15. GUI 在跑时你画的线会被整屏擦掉吗?怎么用数字回答?              (4.3)
   16. killall 之后立刻 pidof 为什么可能还有?可靠的停法怎么写?       (4.4)
   17. 不插显示器怎么截屏?dd 为什么必须带 count?                     (4.5)
   18. 读显存和写显存哪个快?对 display 层接口设计意味着什么?         (4.6)
   19. 插上 HDMI 分辨率为什么可能变?谁改的?模式清单从哪来?           (5)
   20. 本板插屏后 bpp 变成几?4.3 节 grep -c 00ff0000 为什么失效?     (5 坑10)

---

## 9 已知的坑

    坑 1  WSL 没有 /dev/fb0,mknod 造节点也没用(ENODEV)。要 root,节点要建在
          WSL 根文件系统上:/mnt/e 上 mknod 报 Operation not supported(95),
          /tmp 是带 nodev 的 tmpfs,user namespace 里 mknod 报 EPERM。  (1.2)

    坑 2  出厂 GUI 不整屏擦你的画,只擦它变化的那块(实测 3 秒 92 字节,
          时钟秒位)。"看着没问题"不证明没冲突。上板前停 GUI 并 pidof 确认。(4.3)

    坑 3  killall 之后进程不会立刻消失(SIGTERM 递到就返回)。停完轮询
          pidof 到空,或写等待型 stop。                                (4.4)

    坑 4  只数个数的判据会放过整体平移:行起点少乘像素宽度,红点还是 100 个,
          挪到了第 75 行。每组判据至少带一条位置对账。                  (2.5)

    坑 5  纯红测不出 565 位数写反(溢出截断后恰好还是 f800)。三原色各测一次。(3.3)

    坑 6  cat /dev/fb0 读出来是 32 MiB 而不是一屏(实测 33554432;fb_read 按
          screen_size 报总长,这个驱动把 screen_size 设成了 smem_len,延伸 D)。
          截屏必须 bs=<line_length> count=<yres>,否则 2.4 MiB 变 32 MiB。(4.5)

    坑 7  GUI 写的像素高字节是 ff。grep -c 00ff0000 只数得到写 00 的程序。(4.5)

    坑 8  /dev/fb0 权限 crw-rw---- root video。普通用户要用,先加进 video 组。(1.2)

    坑 9  串口截屏耗时取决于画面可压缩度:白底 0.6 秒,GUI 画面 79 秒。
          反复截屏用纯色背景。                                          (4.5)

    坑 10 插上显示器 bpp 32 变 16:dd 的 bs/count、od 的 -tx 宽度、颜色值
          全部要按新模式改。先跑一次 fbinfo 再定判据,不抄一套数字用到底。  (5)

---

## 10 延伸（选读，不影响主线）

**延伸 A：同一个结构体，两个平台不一样大。** `fb_fix_screeninfo` 里的
`smem_start`、`mmio_start` 是 `unsigned long`：x86-64 上 8 字节、ARM 上 4 字节，
从 `smem_len` 起每个字段的偏移都挪位。实验 `probe/fbabi.c` 不运行程序，让编译器
把结构体大小和字段偏移变成数组长度，再 `nm -S` 读出来（本机 2026-10-20 实测）：

```text
                x86-64   ARM
sizeof(var)     0xa0     0xa0      (160;var 里全是 32 位类型,两平台相同)
sizeof(fix)     0x50     0x44      (80 vs 68)
smem_len 偏移    0x18     0x14      (24 vs 20)
line_length 偏移 0x30     0x2c      (48 vs 44)
bpp 偏移        0x18     0x18      (24)
```

工程含义：`FBIOGET_VSCREENINFO=0x4600`、`FBIOGET_FSCREENINFO=0x4602`（本机实测
打印）是不带结构体大小的裸数字，内核 `do_fb_ioctl` 按**自己编译时**的布局往回拷
`sizeof(var)`/`sizeof(fix)` 字节。编译用的头文件与目标平台不一致时，读到的每个
字段都是错位的，而程序不会报任何错。所以 fbinfo、show_pixel 这类程序必须按目标
平台各编一份。

**延伸 B：读显存为什么慢。** mxsfb 的 mmap 里有一行
`vma->vm_page_prot = pgprot_writecombine(vma->vm_page_prot);`，给映射设了"写合并"
内存属性：CPU 把对小片显存的连续写先合并成大批突发再发出去，写很快；读享受不到
这个优化。读慢 10 倍（4.6 节）是实测，更细的机理未做实验，不下结论。

**延伸 C：maps 偏移列为什么是物理地址。** 通用文件的 mmap 里，maps 的偏移列是
文件内的偏移。mxsfb 的 mmap 把这一列改写了：
`vma->vm_pgoff = (info->fix.smem_start + offset) >> PAGE_SHIFT;`，把"显存内偏移"
换成了"物理页号"再 `remap_pfn_range`。所以 4.2 节 GUI 的 maps 里偏移列直接显示
0x8c100000，和 `smem_start` 对得上。

**延伸 D：cat /dev/fb0 为什么读出 32 MiB。** 内核 fbmem.c 的 `fb_read` 里：

```c
total_size = info->screen_size;
if (total_size == 0)
    total_size = info->fix.smem_len;
```

应用能 read 到的总长是 `screen_size`，为 0 才退回 `smem_len`。而这个驱动
（NXP mxsfb.c）把 `screen_size` 直接设成了 `smem_len` = 32 MiB，所以从头读到尾
是 32 MiB，截屏必须自己按 `line_length × yres` 截断（坑 6）。

**顺带一提（跳过不影响）**：这个"写内存、硬件按节拍扫"的形状到处都在。ysyx 的
NEMU 里 VGA 是同一形状：程序写 vmem，模拟器按节拍刷到 SDL 窗口；龙芯 SoC 课上
写的 DVI 扫描器就是本章"显示控制器"的 RTL 版，fbset 那行 timings 就是当年写进
寄存器的行场参数。[11 显示原理](../../fundamentals/11_显示原理.md)第 2 节有完整对照。

---

## 11 这一章交出了什么

现在能独立做到：

- 用 ioctl 把驱动知道的全部问出来：分辨率、bpp、行宽、显存地址与大小、时序，
  并用 fbset/sysfs 走第二条路对账
- 用 `line_length` 把二维坐标拍扁成一维，说得出为什么会有行尾填充
- 按位段拼 32bpp 与 16bpp 的颜色，说得出 888 压成 565 丢了什么
- 在假显存上预演、在板上回读计数，两边逐项相等才算画对
- 停掉占着屏幕的 GUI，并确认它真的停了
- 说得出"读显存比写慢 10 倍"和"接口粒度是一块而不是一个点"这两条设计结论

还不能做：

- 在屏幕上画字（06 篇：点阵、矢量字体，每个字最终都要写进这块显存）
- 双缓冲与翻页（本仓未做）
- 显示驱动的内部实现（第 2 阶段）

下一章：[06 文字显示](06_文字显示.md)。
