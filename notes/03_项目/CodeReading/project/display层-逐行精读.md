# display 层 逐行精读

对应代码：

```
    project/display/disp_manager.h     45 行   公共类型与对外接口
    project/display/disp_manager.c    151 行   注册链表、选后端、画点、填矩形
    project/display/memdisp.c         112 行   假显存后端（malloc 出来的一块内存）
    project/display/framebuffer.c      98 行   真显存后端（mmap /dev/fb0）
    project/unittest/disp_test.c       42 行   单测：画一张固定图案
    project/unittest/count.sh          73 行   独立计数脚本（od + awk，板上也能跑）
    project/unittest/count.py          30 行   同上，python 版
```

前置：[common](common-逐行精读.md)（错误码与日志宏）、
[层管理器空壳](层管理器空壳-逐行精读.md)（这一层被填之前的样子）。
这一层的知识背景在 [`../../../01_应用编程/03_Framebuffer显示.md`](../../../01_应用编程/03_Framebuffer显示.md)，
本篇只讲代码。

---

## 1. 这一层解决什么

上层要说的是"把 (11,1) 这个点画成蓝色"。到内存里要变成两件互不相干的事：

```
    写到哪个地址   = base + y * line_length + x * (bpp / 8)      只跟坐标和几何有关
    写进去什么值   = 红 << 红offset | 绿 << 绿offset | 蓝 << 蓝offset   只跟颜色和位段有关
```

两件事都需要一组参数：`base`、`line_length`、`bpp`、三个分量的位置。
这组参数由**后端**提供，manager 只管用。后端有两个：

| 后端 | 那块内存是什么 | 用在哪 |
|---|---|---|
| `mem` | `malloc` 出来的一块 | 电脑上跑判据。WSL 没有 `/dev/fb0`，整条链路靠它才验得了 |
| `fb` | `mmap` 出来的真显存 | 板子上跑，写进去屏幕直接变 |

`mem` 不只是"没有硬件时的替身"。它的行宽**故意**大于一行像素占的字节数，
行尾填 `0xAA` 当哨兵，所以它能查出真板子上查不出来的错——
板上 `line_length` 是 4096，而 1024 x 4 也是 4096，行尾没有填充，
把行宽算成 `xres * bpp / 8` 在板上画出来的图是**对的**。判据 `[7r2]` 记录了这件事。

---

## 2. 头文件（`disp_manager.h` 全文 45 行）

### 2.1 位段描述（第 4 到 8 行）

```c
struct disp_field {
	int offset;
	int length;
};
```

一个颜色分量在像素里的位置：从第 `offset` 位起，占 `length` 位。

**没有直接用 `struct fb_bitfield`**，虽然它的前两个成员一模一样。
理由是这个头文件不能包含 `linux/fb.h`：包含了的话，
`unittest/disp_test.c`、以后的 font 层、ui 层都会跟着看见帧缓冲的全部 API，
"只有 display 认识硬件"这条分层就守不住了。判据 `[10]` 守的就是这一条。

### 2.2 一块能画的内存（第 10 到 18 行）

```c
struct disp_buf {
	int  xres;
	int  yres;
	int  bpp;
	int  line_length;          /* 一行的字节数, 不一定等于 xres * bpp / 8 */
	struct disp_field red, green, blue;
	unsigned char *base;
};
```

第 1 节那两个公式需要的量，一个不多一个不少。

`line_length` 那行注释是整个头文件里最重要的一句。它不是提醒，是**判据的依据**：
如果这两个值永远相等，`mem` 后端就没有存在的必要了。

`base` 是 `unsigned char *` 而不是 `void *`：地址计算要按字节走，
`void *` 上做指针加法是 GNU 扩展，标准 C 里没有定义。

### 2.3 区域与后端表（第 20 到 32 行）

```c
struct disp_region {
	int x, y, w, h;
};

struct disp_ops {
	const char *name;
	int  (*open)(struct disp_buf *out);
	void (*close)(void);
	int  (*flush)(const struct disp_region *r);
	struct disp_ops *next;
};
```

`disp_region` 是左闭右开的：覆盖 `x <= X < x + w`。和 `for` 循环的写法天然配合，
也避免了"宽度 0 的矩形"这种要特判的边界。

`disp_ops` 是这一层的核心形状，课程配套项目里叫 `DispOpr`。
三个函数指针加一个链表指针，一个后端填一份。
`next` 让 manager 能把任意多个后端串起来，运行时按 `name` 选一个——
这正是[路线图](../../Todo/项目路线图-对齐电子产品量产工具.md) 3.1 条要补的"注册链表"。

`open` 收一个出参 `struct disp_buf *out`：后端把自己那块内存的参数**填进去**，
而不是 manager 去问后端要。两种写法的差别在于，出参这种写法下
后端不需要导出任何 getter，内部状态一个都不用暴露。

### 2.4 对外接口（第 34 到 43 行）

```c
void disp_register(struct disp_ops *ops);

int  display_init(void);
void display_exit(void);

/* 上层接口。颜色一律是 0x00RRGGBB, 拼成什么像素值由本层决定 */
const struct disp_buf *disp_get_buf(void);
int  disp_put_pixel(int x, int y, unsigned int rgb);
int  disp_fill_rect(const struct disp_region *r, unsigned int rgb);
int  disp_flush(const struct disp_region *r);
```

`display_init` / `display_exit` 的签名**一个字都没改**。
这是填这一层时的硬约束：`main.c` 的层表不动，判据 `[1]` 不动。

"颜色一律是 `0x00RRGGBB`"这句注释是跨层约定，04 章的 font 层按它写的规格。
16 位色的板子上，上层照样传 8 位分量，缩位是这一层的事。

`disp_get_buf` 返回 `const` 指针：上层能读画布尺寸（单测就靠它算右下角坐标），
但改不了。

---

## 3. manager（`disp_manager.c` 全文 151 行）

### 3.1 三个文件级状态（第 14 到 19 行）

```c
extern void fb_register(void);
extern void memdisp_register(void);

static struct disp_ops *g_list;   /* 所有注册过的后端 */
static struct disp_ops *g_cur;    /* 当前选中的后端, NULL 表示未启动 */
static struct disp_buf  g_buf;    /* 当前后端交出来的画布 */
```

两个 `extern` 声明写在 `.c` 里而不是头文件里。这是有意的：
`fb_register` 和 `memdisp_register` 只有 manager 一个调用者，
放进头文件等于告诉所有人"你也可以注册"。

`g_cur` 身兼两职：既是"当前用哪个后端"，也是"这一层启动了没有"。
空壳版里那个 `g_inited` 标志因此不需要了，状态少一个就少一处可能不一致的地方。

### 3.2 注册与查找（第 21 到 35 行）

```c
void disp_register(struct disp_ops *ops)
{
	ops->next = g_list;
	g_list = ops;
}

static struct disp_ops *disp_find(const char *name)
{
	struct disp_ops *p;

	for (p = g_list; p != NULL; p = p->next)
		if (strcmp(p->name, name) == 0)
			return p;
	return NULL;
}
```

头插：新来的挂在最前面。两行的顺序不能反——
先 `g_list = ops` 再 `ops->next = g_list`，节点的 `next` 就指向自己了。

`disp_register` 收的是**指针**，不复制结构体。所以每个后端那张 `disp_ops` 表
必须活得比链表久：两个后端都把它定义成文件作用域的 `static` 变量
（`memdisp.c` 第 102 行、`framebuffer.c` 第 88 行）。
写成函数内的局部变量，函数一返回链表上就是野指针。

### 3.3 启动（第 37 到 68 行）

```c
int display_init(void)
{
	const char *name;
	int ret;

	if (g_cur != NULL)
		return ERR_OK;

	/* 每轮重建链表。少了这一行, 第二轮注册会让节点的 next 指向自己, disp_find 死循环 */
	g_list = NULL;
	fb_register();
	memdisp_register();

	name = getenv("DISP_DEV");
	if (name == NULL)
		name = "fb";

	g_cur = disp_find(name);
	if (g_cur == NULL) {
		LOG_ERR("no display backend named %s", name);
		return ERR_NOTFOUND;
	}

	ret = g_cur->open(&g_buf);
	if (ret != ERR_OK) {
		g_cur = NULL;
		return ret;
	}

	LOG_INFO("display init OK");
	return ERR_OK;
}
```

**第 46 行那句 `g_list = NULL;` 是本篇最值得看的一行。** 少了它，
`init` -> `exit` -> `init` 这个序列会把链表做成自环：
第二轮 `disp_register` 执行 `ops->next = g_list`，而此时 `g_list` 就是 `ops` 自己。

它的现场是无限循环，不是崩溃，所以很难查。实测（在单测里连跑两轮 init/exit）：

| 版本 | `DISP_DEV=mem` | `DISP_DEV=nosuch` |
|---|---|---|
| 有这一行 | `init1 0 / init2 0 / done`，退出码 0 | 正常报 not found |
| 删掉这一行 | 一样是 0，看不出问题（`mem` 正好是链表头，第一次比较就命中） | 卡死，`timeout 5` 杀掉，退出码 124 |

`main.c` 现在只 init 一次，所以这个 bug 在当前代码里不会发作。
它属于"以后加一个切换显示设备的功能时立刻发作"的那一类。

**缺省后端是 `fb` 而不是 `mem`。** 并且不做"fb 打不开就退回 mem"的回退：
回退看起来贴心，实际后果是板上显示出问题时程序默默画进一块没人看的内存，
现象是"屏幕没反应但程序说一切正常"。宁可启动失败。
代价是本机跑判据要显式设 `DISP_DEV=mem`，`check.sh` 第 19 行统一设了。

失败时 `g_cur = NULL`（第 62 行）不能省：`open` 失败但 `g_cur` 还指着那个后端的话，
后面 `disp_put_pixel` 的 `g_cur == NULL` 检查就挡不住了，会拿着没填过的 `g_buf` 算地址。

### 3.4 关闭与取画布（第 70 到 87 行）

```c
void display_exit(void)
{
	if (g_cur == NULL)
		return;

	g_cur->close();
	memset(&g_buf, 0, sizeof(g_buf));
	g_cur = NULL;

	LOG_INFO("display exit OK");
}
```

`memset` 把画布清零，其中包括 `base`。不清的话，`close` 之后 `g_buf.base`
还指着一块已经 `free` 或 `munmap` 掉的内存。虽然 `g_cur = NULL` 已经能挡住所有入口，
但留着一个悬垂指针没有任何好处。

`sizeof(g_buf)` 而不是写死字节数：以后 `disp_buf` 加字段，这行不用改。

### 3.5 拼色（第 89 到 93 行）

```c
/* 把一个 8 位分量缩到 length 位再挪到 offset 位。length 为 8 时 c8 原样返回 */
static unsigned int pack_field(unsigned int c8, const struct disp_field *f)
{
	return (c8 >> (8 - f->length)) << f->offset;
}
```

上层给的是 8 位分量，硬件要的是 `length` 位。**丢低位不丢高位**：
高位决定"大致多红"，低位只是细微差别。丢高位会让深红变成亮红。

`length` 为 8 时 `c8 >> 0` 就是原值，所以 32 位色和 16 位色用的是同一个公式，
没有 `switch (bpp)`。硬件换格式时这一层不用改——板上插 HDMI 后驱动会自己
把模式从 1024x600x32 改成 1280x720x16，同一个二进制不重编就能画对。

参数用 `unsigned int`：移位运算在有符号数上的行为部分由实现定义，位运算一律用无符号。

判据 `[7r5]` 注错时把这行改成 `(c8) << f->offset`，16 位色下
**红色仍然正确**（`f800`），绿变 `1fe0`、蓝变 `00ff`。只验红色的判据会假绿，
所以 `[7]` 组数的是整行像素值分布，三个原色一起验。

### 3.6 画点（第 95 到 122 行）

```c
int disp_put_pixel(int x, int y, unsigned int rgb)
{
	unsigned char *p;
	unsigned int v;

	if (g_cur == NULL)
		return ERR_PARAM;
	if (x < 0 || y < 0 || x >= g_buf.xres || y >= g_buf.yres)
		return ERR_PARAM;

	v = pack_field((rgb >> 16) & 0xff, &g_buf.red)
	  | pack_field((rgb >> 8) & 0xff, &g_buf.green)
	  | pack_field(rgb & 0xff, &g_buf.blue);

	/* 行宽用 line_length, 不是 xres * bpp / 8: 两者只在行尾有填充时才不同 */
	p = g_buf.base + y * g_buf.line_length + x * (g_buf.bpp / 8);
	switch (g_buf.bpp) {
	case 16:
		*(unsigned short *)p = v;
		break;
	case 32:
		*(unsigned int *)p = v;
		break;
	default:
		return ERR_NOTSUP;
	}
	return ERR_OK;
}
```

边界检查四条边都要，`>=` 不是 `>`：宽 64 的画布合法 x 是 0 到 63。
判据 `[7r3]` 删掉 `x >= g_buf.xres` 之后，越界那个点写进了上一行的行尾填充区，
哨兵从 2048 个变成 2044 个——**少的正好是一个 32 位像素占的 4 个字节**。

三个 `pack_field` 用 `|` 拼起来，因为三个分量占的位互不重叠。

`*(unsigned short *)p = v` 这种写法，把按字节走的指针临时当成宽指针用，
决定了"一次写几个字节"。这件事写在类型里，没法用变量表达，
所以拼色能查表而这里必须 `switch`。

`default` 分支现在到不了（两个后端都只给 16 或 32），留着是为了以后
有人加了 24 位色的后端却忘了改这里时当场报错，而不是写坏内存。

### 3.7 填矩形与刷新（第 124 到 151 行）

```c
/*
 * 裁剪后逐点画。put_pixel 自己也挡越界, 所以裁剪在功能上是冗余的,
 * 留着是为了不白跑屏外的点, 也为了将来 fill_rect 直接写内存时仍有一道边界。
 */
int disp_fill_rect(const struct disp_region *r, unsigned int rgb)
{
	int x0, y0, x1, y1, x, y;

	if (g_cur == NULL || r == NULL)
		return ERR_PARAM;

	x0 = r->x < 0 ? 0 : r->x;
	y0 = r->y < 0 ? 0 : r->y;
	x1 = r->x + r->w > g_buf.xres ? g_buf.xres : r->x + r->w;
	y1 = r->y + r->h > g_buf.yres ? g_buf.yres : r->y + r->h;

	for (y = y0; y < y1; y++)
		for (x = x0; x < x1; x++)
			disp_put_pixel(x, y, rgb);
	return ERR_OK;
}
```

外层循环走行、内层走列：同一行的像素在内存里连着，这个顺序对 cache 友好。

**这四行裁剪注错不红**，判据 `[7r6]` 把这件事记了下来并让它 PASS。
注错不红只有两种可能：判据没覆盖，或者被注错的代码本来就多余。
这里是后者——边界已经由 `put_pixel` 兜住了。留着的理由写在函数上方的注释里：
一是不白跑屏外的点，二是以后为了速度让 `fill_rect` 绕开 `put_pixel` 直接
`memset` 整行时，这四行就是唯一的越界防线，那时这条判据才开始起作用。

`disp_flush` 只做一件事：转发给当前后端的 `flush`。两个后端的 `flush` 现在都是空的，
它存在是为了以后接双缓冲时上层不用改。

---

## 4. 假显存后端（`memdisp.c` 全文 112 行）

### 4.1 两个文件级状态（第 20 到 21 行）

```c
static unsigned char *g_mem;   /* 假显存首地址, NULL 表示未打开 */
static size_t g_size;          /* 假显存总字节数 */
```

`g_mem` 兼作"开了没有"的标志，这是 `mem_close` 能被安全重复调用的基础。

### 4.2 打开（第 23 到 69 行）

参数从环境变量来，缺省 `64x32x32x320`：

```c
	const char *spec = getenv("DISP_MEM");
	int w = 64, h = 32, bpp = 32, ll = 320;

	if (spec != NULL && sscanf(spec, "%dx%dx%dx%d", &w, &h, &bpp, &ll) != 4) {
		LOG_ERR("bad DISP_MEM: %s", spec);
		return ERR_PARAM;
	}

	if (w <= 0 || h <= 0 || (bpp != 16 && bpp != 32) || ll < w * bpp / 8) {
		LOG_ERR("bad geometry %dx%dx%d ll %d", w, h, bpp, ll);
		return ERR_PARAM;
	}
```

两道检查分工不同：`sscanf` 只保证**格式**对（读到了四个整数），
第二道保证**值**合理。缺了第二道，`DISP_MEM=0x0x7x3` 也能一路走到 `malloc`。

缺省值里行宽 320 比一行像素的 256 字节多 64 字节，这 64 字节就是查错用的填充区。

```c
	g_size = (size_t)ll * h;
	g_mem = malloc(g_size);
	if (g_mem == NULL)
		return ERR_NOMEM;

	/* 像素区刷黑, 行尾填充区填 0xAA 当哨兵: 谁写出界, 谁就会把它冲掉 */
	for (y = 0; y < h; y++) {
		memset(g_mem + y * ll, 0x00, w * bpp / 8);
		memset(g_mem + y * ll + w * bpp / 8, 0xAA, ll - w * bpp / 8);
	}
```

`(size_t)ll * h` 先把一个操作数转成 `size_t` 再乘：两个 `int` 相乘的结果还是 `int`，
一块 4K 屏的显存就是 3300 万字节，离 21 亿虽然还远，但这种转换是无成本的保险。

`0xAA` 选得刻意：二进制 `10101010`，既不是 0 也不是 0xFF，不会和黑、白或任何一个
正常的颜色分量撞上。

位段按 bpp 分两套填（第 55 到 65 行），32 位是 xRGB8888，16 位是 RGB565。
这是后端的职责：manager 那边不认识任何一种具体格式。

### 4.3 关闭时把内存交出去（第 71 到 94 行）

```c
	/* 只倒原始字节, 统计交给外部脚本: 自己数自己画的东西, 判据永远 PASS */
	dump = getenv("DISP_MEM_DUMP");
	if (dump != NULL) {
		fp = fopen(dump, "wb");
		if (fp != NULL) {
			fwrite(g_mem, 1, g_size, fp);
			fclose(fp);
		} else {
			LOG_ERR("cannot open dump file %s", dump);
		}
	}

	free(g_mem);
	g_mem = NULL;
	g_size = 0;
```

注释里那句话是这一层判据体系的地基。如果让这个文件自己统计
"我画了 12 个红点"再打印出来，那么它数错和画错会一起错，判据永远绿。
**倒出原始字节，交给 `count.sh` 去数**，两边不共享任何代码。

`fopen` 失败要报出来，不能默默跳过：跳过的话外部脚本会读到上一次的旧文件，判据假绿。

`free` 之后置 `NULL` 和 `0`，维持 4.1 节那个约定。判据 `[9r]` 删掉 `free` 之后
ASan 报 `Direct leak of 10240 byte(s) in 1 object(s)`，10240 正好是 320 x 32。

---

## 5. 真显存后端（`framebuffer.c` 全文 98 行）

### 5.1 状态的初值（第 22 到 24 行）

```c
static int g_fd = -1;                       /* -1 表示未打开, 0 是合法 fd */
static unsigned char *g_base = MAP_FAILED;  /* mmap 失败返回的是 MAP_FAILED 不是 NULL */
static size_t g_size;
```

两个初值都不是 0，两行注释各写了一个理由。这两个坑都会让 `fb_close` 干错事：
`g_fd` 初值 0 会关掉标准输入；拿 `NULL` 判 `mmap` 的结果则永远判不出失败。

### 5.2 幂等的 close（第 26 到 37 行）

```c
/* 幂等: 每种资源自己判断在不在, 所以 open 的任何一个失败分支都能直接调它 */
static void fb_close(void)
{
	if (g_base != MAP_FAILED) {
		munmap(g_base, g_size);
		g_base = MAP_FAILED;
	}
	if (g_fd >= 0) {
		close(g_fd);
		g_fd = -1;
	}
}
```

这是这一层最值得抄走的结构。`fb_open` 有三处可能失败，每处已经拿到的资源都不同：

| 失败点 | 此时手上有什么 | 要还什么 |
|---|---|---|
| `open` 失败 | 什么都没有 | 什么都不用还 |
| `ioctl` 失败 | fd | `close(fd)` |
| `mmap` 失败 | fd | `close(fd)` |

每个分支各写一遍清理代码，就会有一处写漏。
**让 close 自己判断每种资源在不在，三个分支都调它**，就不会漏、也不会重复。
课程配套项目那边的失败路径就是漏了 `close(fd)`。

先 `munmap` 后 `close` 是"后申请的先释放"，和空壳篇里那句
"顺序与申请时相反"是同一条规矩。

### 5.3 打开（第 39 到 79 行）

```c
	g_fd = open(path, O_RDWR);
	if (g_fd < 0) {
		LOG_ERR("open %s failed", path);
		return ERR_IO;
	}
	if (ioctl(g_fd, FBIOGET_VSCREENINFO, &var) < 0 ||
	    ioctl(g_fd, FBIOGET_FSCREENINFO, &fix) < 0) {
		LOG_ERR("FBIOGET_*SCREENINFO failed");
		fb_close();
		return ERR_IO;
	}
```

`O_RDWR` 不能换成 `O_WRONLY`：后面 `mmap` 带了 `PROT_READ`，
映射的权限不能超过打开文件的权限。

两个 `ioctl` 用 `||` 串起来，短路求值保证第一个失败时不白跑第二个。

设备路径可以用 `DISP_FB` 覆盖（第 44 行）。这不是多余的灵活性：
`DISP_FB=/dev/null` 能 `open` 成功但 `ioctl` 必定 `ENOTTY`，
正好停在"fd 已开、ioctl 失败"那一步，让判据 `[8]` 能在没有帧缓冲的电脑上验失败路径。

```c
	/* 只映射一屏, 不映射 fix.smem_len: 板上 smem 是 32 MiB 而一屏只要 2.4 MiB,
	   多映射出来的部分会把越界写变成静默写坏, 而不是当场 SIGSEGV */
	g_size = (size_t)fix.line_length * var.yres;
	g_base = mmap(NULL, g_size, PROT_READ | PROT_WRITE, MAP_SHARED, g_fd, 0);
```

`MAP_SHARED` 不能换成 `MAP_PRIVATE`：私有映射的写入进的是一份写时复制的副本，
程序自己读得到，屏幕上什么都不会变——这种 bug 没有任何报错。

```c
	out->red   = (struct disp_field){ var.red.offset,   var.red.length   };
	out->green = (struct disp_field){ var.green.offset, var.green.length };
	out->blue  = (struct disp_field){ var.blue.offset,  var.blue.length  };
```

位段从 `var` 里抄，一位都不写死。板上插 HDMI 的一瞬间驱动会读 EDID 并改模式
（1024x600x32 变成 1280x720x16），dmesg 里一行日志都不留。
写死 565 的程序不插屏时全错，写死 8888 的程序插屏后全错，照抄的程序两种都对。

内核那边叫 `bits_per_pixel`，这里叫 `bpp`。换名字抄一遍正是这一层的价值：
上层不必认识内核的命名。

---

## 6. 单测（`unittest/disp_test.c` 全文 42 行）

它有自己的 `main`，链接时带上除 `main.o` 外的全部 `.o`（见 Makefile 精读）。
画的图案每一笔都有针对性：

| 画什么 | 验什么 |
|---|---|
| 全屏填黑 | `fill_rect` 走完整块画布不崩；给计数一个干净底 |
| (1,1) 红 4x3、(6,1) 绿 4x3、(11,1) 蓝 4x3 | 三个分量的位段都对；坐标不从 0 开始，行宽算错会整体偏 |
| (xres-1, yres-1) 一个白点 | 最后一行最后一列，行宽算错必定跑到别处 |
| (xres-2, 5) 起黄色 4x2 | 只有 2x2 在屏内，验右边界裁剪 |
| (xres, 0) 写一个白点 | 越界必须被拒，返回值打出来给外部验 |

程序自己不统计任何东西，只打印两行：`mode` 行和越界返回值。
`mode` 行本身也是一条判据——上板后它必须和 `fbset` 报的一致。

结尾必须调 `display_exit()`：转储文件是在 `mem_close` 里写的，不调就没有文件。

---

## 7. 计数脚本（`unittest/count.sh` 73 行、`count.py` 30 行）

两个脚本做同一件事，输出格式完全一样：

```
size 10240 pad_AA 2048 pad_total 2048
00000000:2007 000000ff:12 0000ff00:12 00ff0000:12 00ffff00:4 00ffffff:1
at (1,1)=00ff0000 (4,3)=00ff0000 ...
```

`count.sh` 只用 `od` 和 `awk`，板子上没有 python 也能跑，而且是流式处理，
不把整块显存读进数组——板上一屏 2.4 MiB，读进 awk 数组会很慢。
`count.py` 留着是因为它短，看得清算法。

判据 `[7]` 里有一条专门比对两者的输出是否逐字节相同：
**两个独立实现互校**，一个写错了另一个不会跟着错。

三行输出里最该看的是第一行的 `pad_AA` 和第二行的合计：

```
    2007 + 12 x 3 + 4 + 1 = 2048 = 64 x 32      一个像素不多不少
    pad_AA 2048 = (320 - 256) x 32              一个哨兵都没被冲掉
```

单看"红色 12 个"证明不了什么，这两个等式把整块画布封死了。

---

## 8. 执行顺序

以 `DISP_DEV=mem ./build/x86/unittest/disp_test` 为例：

| 步 | 谁在跑 | 可观测结果 |
|---|---|---|
| 1 | `display_init()` | `g_list` 清空，两个后端挂上去（链表顺序 mem -> fb） |
| 2 | `disp_find("mem")` | 第一个就命中 |
| 3 | `mem_open(&g_buf)` | `malloc` 10240 字节，刷黑加哨兵，填满 `g_buf` |
| 4 | `printf("mode ...")` | `mode 64x32x32 line_length 320` |
| 5 | 六次 `disp_fill_rect` + 一次 `disp_put_pixel` | 画图案，全部落在 `g_mem` 里 |
| 6 | 越界的 `disp_put_pixel` | 返回 `ERR_PARAM`，打印 `out of range put_pixel ret -1` |
| 7 | `disp_flush` -> `mem_flush` | 空操作，返回 `ERR_OK` |
| 8 | `display_exit()` -> `mem_close()` | 整块内存写进 `DISP_MEM_DUMP` 指的文件，`free` |
| 9 | 外部 `count.sh` | 独立解开转储文件，数出三行 |

换成 `DISP_DEV=fb` 时只有第 3 步和第 8 步不同：`mem_open` 换成 `fb_open`
（`open` + 两次 `ioctl` + `mmap`），`mem_close` 换成 `fb_close`（`munmap` + `close`）。
中间画图那几步走的是同一份代码。

---

## 9. 消费者

| 文件 | 用到的部分 |
|---|---|
| `main.c` 第 6 行、第 21 行 | 只用 `display_init` / `display_exit`，层表里那一行没变过 |
| `unittest/disp_test.c` | `disp_get_buf` / `disp_put_pixel` / `disp_fill_rect` / `disp_flush` 全套 |
| `check.sh` 第 19 行 | `export DISP_DEV=mem`，让前六组判据能在没有帧缓冲的电脑上跑 |
| `check.sh` 第 189 到 300 行 | `[7]` 到 `[10]` 四组，共 23 条 |
| 以后的 font 层（04 章） | 按 `0x00RRGGBB` 的约定调 `disp_put_pixel` 画字模 |

`main.c` 一个字都没改，是这一层交付的一部分：
从空壳换成真实现，层表、判据 `[1]`、启停顺序全都没受影响。
