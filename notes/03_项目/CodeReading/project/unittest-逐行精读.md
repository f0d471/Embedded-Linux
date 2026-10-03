# unittest 逐行精读

对应代码：`project/unittest/disp_test.c`（42 行）、`font_test.c`（137 行）、
`input_test.c`（51 行）、`count.py`（30 行）、`count.sh`（73 行）、
`input_replay.txt`（29 行）、`input_replay_bad.txt`（1 行）。

## 1. 文件定位

单层测试与独立计数。三个 `_test.c` 各自带 `main`，由 `make test` 单独链接
（不进 `product_tool`，见 Makefile 篇）；两个计数脚本从显存转储独立算像素
分布，与被测的 `disp_manager.c` 不共享任何代码；两个回放文件是 input 层
状态机的确定性输入。判据脚本（check 篇）调用这里的全部产物。

前置知识：[从零开始读写 project 代码](../00-从零开始读写项目代码.md)第 9 节
（Makefile/Bash/Python/回放数据）。

```
disp_test ─画固定图案─> DISP_MEM_DUMP ─> count.sh / count.py(独立计数)
font_test ─三 provider─> 假显存转储 ─> count.sh
input_test <─input_replay.txt(五帧) / input_replay_bad.txt(畸形)
```

## 2. disp_test.c

### 第 1—15 行：图案说明与启动

```c
/*
 * display 层单测。画一张固定图案, 由外部读回显存独立计数:
 *   全屏黑; (1,1) 起红 4x3; (6,1) 起绿 4x3; (11,1) 起蓝 4x3;
 *   右下角一个白点; 右边缘一个黄色 4x2 矩形只有 2x2 落在屏内;
 *   (xres,0) 越界写一个白点, 必须被拒绝。
 *
 * 这张图一次验四件事: 三个分量的位段、行宽、右边界裁剪、越界拒绝。
 * 程序自己不统计任何东西, 只把坐标和返回值打出来。
 */

#include <stdio.h>

#include "common.h"
#include "display/disp_manager.h"

int main(void)
{
	const struct disp_buf *b;
	struct disp_region all, r;
	int ret;

	if (display_init() != ERR_OK)
		return 1;
	b = disp_get_buf();
	printf("mode %dx%dx%d line_length %d\n", b->xres, b->yres, b->bpp, b->line_length);
```

图案设计对着判据需求反推：三个不重叠的色块让三种位段各错各的（红错只有
红块分布变）；黄块 `xres-2` 起步 4 宽，只有 2 列在屏内，考右边界裁剪；
越界点考拒绝路径。程序自己不计数——统计是独立脚本的事，
"自己数自己画的东西，判据永远 PASS"。

### 第 17—42 行：画图与退出

```c
	all = (struct disp_region){ 0, 0, b->xres, b->yres };
	disp_fill_rect(&all, 0x000000);

	r = (struct disp_region){ 1, 1, 4, 3 };  disp_fill_rect(&r, 0xff0000);
	r = (struct disp_region){ 6, 1, 4, 3 };  disp_fill_rect(&r, 0x00ff00);
	r = (struct disp_region){ 11, 1, 4, 3 }; disp_fill_rect(&r, 0x0000ff);
	disp_put_pixel(b->xres - 1, b->yres - 1, 0xffffff);
	r = (struct disp_region){ b->xres - 2, 5, 4, 2 }; disp_fill_rect(&r, 0xffff00);

	ret = disp_put_pixel(b->xres, 0, 0xffffff);
	printf("out of range put_pixel ret %d\n", ret);

	disp_flush(&all);
	display_exit();
	return 0;
}
```

复合字面量 `(struct disp_region){1,1,4,3}` 就地给矩形赋值，每块用完即弃。
右下白点取 `(xres-1, yres-1)`——合法坐标的最右上角，配黄块把右/下两个
边界各考一次。越界写的返回值 `-1` 打印出来由判据比对。

## 3. font_test.c

### 第 1—23 行：可控探针位图

```c
/*
 * font 层单测：先用可控的 4x2 灰度 provider 验 alpha、负 pitch 和四边裁剪，
 * 再用真实 FreeType 验 UTF-8、missing、bbox 与 26.6 advance。
 */

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "common.h"
#include "display/disp_manager.h"
#include "font/font_internal.h"
#include "font/font_manager.h"

/*
 * pitch=-6：逻辑首行放在内存后半，manager 若把 width 当 pitch 或忽略负号，
 * 读到的覆盖率顺序都会改变。每行最后两字节是 padding。
 */
static const unsigned char g_probe_bitmap[12] = {
	255, 128, 64, 0, 0xaa, 0xaa,
	0, 64, 128, 255, 0xaa, 0xaa,
};
```

探针位图同时带三个坑：负 `pitch`、每行 2 字节填充、alpha 梯度对称
（255/128/64/0 与 0/64/128/255）。对称是刻意的——顺序读反后 8 个像素值
整体颠倒，判据的逐字节对比没有一处碰巧相等。

### 第 25—66 行：probe provider

```c
static int probe_open(const char *path, int face_index)
{
	(void)path;
	return face_index == 0 ? ERR_OK : ERR_PARAM;
}

static void probe_close(void)
{
}

static int probe_size(int px)
{
	return px > 0 ? ERR_OK : ERR_PARAM;
}

static int probe_has(uint32_t cp)
{
	(void)cp;
	return 1;
}

static int probe_render(uint32_t cp, struct font_bitmap *out)
{
	(void)cp;
	*out = (struct font_bitmap) {
		.width = 4, .rows = 2, .pitch = -6,
		.pixel_mode = FONT_PIXEL_GRAY, .num_grays = 256,
		.left = 0, .top = 1,
		.advance_x_26_6 = 5 * 64,
		.buffer = g_probe_bitmap,
	};
	return ERR_OK;
}

static struct font_provider g_probe = {
	.name = "probe",
	.open = probe_open,
	.close = probe_close,
	.set_pixel_size = probe_size,
	.has_codepoint = probe_has,
	.render = probe_render,
};
```

probe 对任何码点都返回同一张位图（`has` 恒 1）：它的职责是考 manager 的
排版与混色路径，不考字形选择。`top=1` 让字形探出基线上方 1 像素，
`advance=5*64` 与位图宽 4 不同——推进量由 provider 说了算，
布局预测不能拿位图宽度凑。注册发生在 `main` 里 `font_select("probe",...)`
之前，provider 链在 init 后仍可追加，这是 `font_register` 判空的原因。

### 第 68—117 行：四个绘制用例

```c
static int draw_probe(int x, int baseline, struct font_text_metrics *m)
{
	size_t bad;
	return font_draw_utf8("X", 1, x, baseline, 0xe0a020, m, &bad);
}

int main(void)
{
	const struct disp_buf *b;
	struct disp_region all;
	struct font_text_metrics m, left, right, top, bottom;
	const char invalid[] = { (char)0xc0, (char)0xaf, 'A' };
	const char *font_file = getenv("FONT_TEST_FILE");
	size_t bad;
	int ret;

	if (display_init() != ERR_OK || font_init() != ERR_OK)
		return 1;
	b = disp_get_buf();
	all = (struct disp_region){ 0, 0, b->xres, b->yres };

	ret = font_measure_utf8(invalid, sizeof(invalid), &m, &bad);
	printf("invalid ret=%d bad=%zu\n", ret, bad);
	ret = font_measure_utf8("A\xe4\xb8\xadg", 5, &m, &bad);
	if (ret != ERR_OK)
		return 2;
	printf("builtin cp=%zu missing=%zu advance=%d bbox=%d,%d,%d,%d\n",
	       m.codepoints, m.missing, m.advance_x_26_6,
	       m.ink_x, m.ink_y, m.ink_w, m.ink_h);

	font_register(&g_probe);
	if (font_select("probe", NULL, 0) != ERR_OK)
		return 3;
	disp_fill_rect(&all, 0x204060);
	if (draw_probe(1, 1, &m) != ERR_OK)
		return 4;
	printf("probe covered=%zu drawn=%zu clipped=%zu advance=%d bbox=%d,%d,%d,%d\n",
	       m.covered_pixels, m.drawn_pixels, m.clipped_pixels, m.advance_x_26_6,
	       m.ink_x, m.ink_y, m.ink_w, m.ink_h);

	if (draw_probe(-3, 1, &left) != ERR_OK ||
	    draw_probe(b->xres - 1, 1, &right) != ERR_OK ||
	    draw_probe(8, 0, &top) != ERR_OK ||
	    draw_probe(14, b->yres, &bottom) != ERR_OK)
		return 5;
	printf("clip left=%zu/%zu right=%zu/%zu top=%zu/%zu bottom=%zu/%zu\n",
	       left.drawn_pixels, left.clipped_pixels,
	       right.drawn_pixels, right.clipped_pixels,
	       top.drawn_pixels, top.clipped_pixels,
	       bottom.drawn_pixels, bottom.clipped_pixels);
```

`invalid` 字面量带显式 `(char)0xc0` 转换：`0xc0` 超出 `char` 范围，
不转换在某些平台是 `int` 截断警告，且负值 `char` 送进解码器会误判。
`sizeof(invalid)` 是 3——含 `'A'`，所以坏字节 0 号之后还有合法尾巴，
考的是"首坏即停"。`"A\xe4\xb8\xadg"` 长度 5：builtin 没有中文，第 2 码点
计 `missing` 并画问号，判据 [11] 对这一行的期望 `cp=3 missing=1
advance=1152 bbox=0,-14,18,14`（`-14` 是 builtin `top=14` 相对基线的负值）。

四个裁剪用例各打一条边：`-3` 考左（位图 4 宽，1 列在屏内），
`xres-1` 考右，`baseline=0` 且 `top=1` 考上，`baseline=yres` 考下。
每次都从零开始画 `draw_probe`，互不叠加（背景同一色，逐字节期望值固定）。

### 第 119—137 行：真字体分支与收尾

```c
	if (font_file != NULL) {
		if (font_select("freetype", font_file, 0) != ERR_OK ||
		    font_set_pixel_size(48) != ERR_OK)
			return 6;
		disp_fill_rect(&all, 0x000000);
		ret = font_draw_utf8("Ag\xe4\xb8\xad", 5, 4, 52, 0xffd040, &m, &bad);
		if (ret != ERR_OK)
			return 7;
		printf("freetype cp=%zu missing=%zu advance=%d bbox=%d,%d,%d,%d"
		       " covered=%zu drawn=%zu clipped=%zu\n",
		       m.codepoints, m.missing, m.advance_x_26_6,
		       m.ink_x, m.ink_y, m.ink_w, m.ink_h,
		       m.covered_pixels, m.drawn_pixels, m.clipped_pixels);
	}

	font_exit();
	display_exit();
	return 0;
}
```

真字体段由 `FONT_TEST_FILE` 开关：判据给 simsun.ttc，48 px、黑底、
基线 52（64 高假屏留出下伸部）。select 先关掉 probe（`font_select` 的
"先关旧再开新"路径在这里被真实验证）。同一程序换 `FONT_FILE` 即跑 msyh.ttc，
板上实验用的就是它。

## 4. input_test.c

### 第 1—51 行：三种用法

```c
/* input 层单测：同一程序既能读文本回放，也能在板上 probe/读取真实 evdev。 */

#include <stdio.h>
#include <string.h>

#include "common.h"
#include "display/disp_manager.h"
#include "input/input_manager.h"

int main(int argc, char **argv)
{
	const struct input_source_info *info;
	struct input_event_data event;
	int ret;
	int timeout = 0;

	if (display_init() != ERR_OK || input_init() != ERR_OK)
		return 1;
	info = input_get_source_info();
	printf("source name=%s path=%s rel=%d abs=%d keys=%d"
	       " xrange=%d..%d yrange=%d..%d\n",
	       info->name, info->path, info->has_relative, info->has_absolute,
	       info->has_keys, info->abs_x_min, info->abs_x_max,
	       info->abs_y_min, info->abs_y_max);

	if (argc > 1 && strcmp(argv[1], "--probe") == 0)
		goto out;
	if (argc > 1 && strcmp(argv[1], "--once") == 0)
		timeout = 5000;

	for (;;) {
		ret = input_get_event(&event, timeout);
		if (ret == ERR_NOTFOUND || ret == ERR_BUSY)
			break;
		if (ret != ERR_OK)
			return 2;
		if (event.kind == INPUT_KIND_POINTER) {
			printf("pointer x=%d y=%d dx=%d dy=%d buttons=%u\n",
			       event.x, event.y, event.dx, event.dy, event.buttons);
		} else {
			printf("key code=%u value=%d\n", event.code, event.value);
		}
		if (timeout > 0)
			break;
	}

out:
	input_exit();
	display_exit();
	return 0;
}
```

回放与真实设备共用这一个循环：判据拿它对账五行回放输出，板上拿它
`--probe`（打印来源后直接退出）与 `--once`（5 秒等一帧）。退出码约定：
正常（EOF/超时/probe）0，`input_get_event` 其它错误 2——判据 [14] 的
"畸形回放被拒绝 = 2" 与 "普通文件不会冒充 evdev = 1" 里的 1 是
`input_init` 失败（replay 打不开坏文件返回 ERR_IO → main 返回 1），
2 是事件循环里的错误，两者可区分。

## 5. count.py

### 第 1—30 行：独立计数

```python
#!/usr/bin/env python3
# 独立计数脚本: 把一块显存转储按 宽x高x位深x行宽 解开, 数每种像素值各几个、
# 行尾填充里还剩几个 0xAA、几个关键坐标上是什么值。
#
#   用法: python3 count.py 转储文件 宽 高 位深 行宽
#
# 它按自己的理解算地址, 和被测的 disp_manager.c 不共享任何代码 --
# 被测程序算错行宽时, 这里不会跟着错。
import sys, collections

path, w, h, bpp, ll = sys.argv[1], *map(int, sys.argv[2:6])
d = open(path, 'rb').read()
B = bpp // 8
cnt = collections.Counter()
pad = 0
for y in range(h):
    row = d[y*ll:(y+1)*ll]
    pad += sum(1 for c in row[w*B:] if c == 0xAA)
    for x in range(w):
        cnt['%0*x' % (B*2, int.from_bytes(row[x*B:x*B+B], 'little'))] += 1

print('size', len(d), 'pad_AA', pad, 'pad_total', (ll - w*B) * h)
print(' '.join('%s:%d' % kv for kv in sorted(cnt.items())))

def px(x, y):
    return '%0*x' % (B*2, int.from_bytes(d[y*ll+x*B:y*ll+x*B+B], 'little'))

print('at', ' '.join('(%d,%d)=%s' % (x, y, px(x, y)) for x, y in
                     [(1,1), (4,3), (5,1), (6,1), (11,1),
                      (w-1,h-1), (w-1,5), (w-2,6), (w-3,5), (0,0)]))
```

地址公式 `y*ll + x*B` 按自己的理解写，与 `disp_put_pixel` 是两份独立实现——
被测程序行宽算错时这里不会跟着错，判据 [7] 还有"两个计数实现互校"一条。
像素值输出成 `B*2` 位十六进制（16 位格式 4 位、32 位 8 位），小端由
`int.from_bytes(..., 'little')` 处理。抽查坐标与 `disp_test` 的图案一一对应，
含两个边界点（右下角、右边缘黄块）。

## 6. count.sh

### 第 1—17 行：板上版

```sh
#!/bin/sh
#
# 独立计数脚本, 和 count.py 做同一件事, 输出格式也一样, 区别是只用
# od + awk, 板子上没有 python 也能跑。
#
#   用法: sh count.sh 转储文件 宽 高 位深 行宽
#
# 它按自己的理解算地址, 和被测的 disp_manager.c 不共享任何代码。
# 流式处理, 不把整块显存读进数组, 所以一屏 2.4 MiB 在板上也跑得动。

set -u

f=$1; w=$2; h=$3; bpp=$4; ll=$5
B=$((bpp / 8))

# 要抽查的坐标, 和 count.py 里的一样
qs="1,1 4,3 5,1 6,1 11,1 $((w-1)),$((h-1)) $((w-1)),5 $((w-2)),6 $((w-3)),5 0,0"
```

### 第 19—59 行：od + awk 主循环

```sh
out=$(od -An -v -tu1 "$f" | awk -v w="$w" -v h="$h" -v B="$B" -v ll="$ll" -v qs="$qs" '
BEGIN {
	idx = 0; pad = 0; cur = 0; mul = 1;
	n = split(qs, q, " ");
	for (i = 1; i <= n; i++) {
		split(q[i], c, ",");
		want[c[1] "," c[2]] = 1;
	}
	fmt = "%0" (B * 2) "x";
}
{
	for (i = 1; i <= NF; i++) {
		y = int(idx / ll);
		off = idx % ll;
		if (y < h) {
			if (off < w * B) {
				k = off % B;
				if (k == 0) { cur = 0; mul = 1; }
				cur = cur + $i * mul;
				mul = mul * 256;
				if (k == B - 1) {
					x = int(off / B);
					key = sprintf(fmt, cur);
					cnt[key]++;
					if ((x "," y) in want)
						at[x "," y] = key;
				}
			} else if ($i == 170) {
				pad++;
			}
		}
		idx++;
	}
}
END {
	print "P", pad;
	for (k in cnt)
		print "C", k, cnt[k];
	for (k in at)
		print "A", k, at[k];
}')
```

`od -tu1` 把字节转成 0..255 的十进制流，awk 逐字节重建位置
（`idx / ll` 得行、`idx % ll` 得列偏移），小端拼装用 `cur + byte*mul` 逐位
乘 256 累加，与 count.py 的 `int.from_bytes` 是两条独立路径。
填充区只认 `170`（0xAA 的十进制）。流式处理是板上约束：串口传上来的
2.4 MiB 转储不能整个读进 awk 数组。

### 第 61—73 行：汇总输出

```sh
pad=$(printf '%s\n' "$out" | awk '$1 == "P" { print $2 }')
size=$(wc -c < "$f" | tr -d ' ')

printf 'size %s pad_AA %s pad_total %s\n' "$size" "$pad" "$(( (ll - w * B) * h ))"
printf '%s\n' "$out" | awk '$1 == "C" { print $2 ":" $3 }' | sort | tr '\n' ' ' | sed 's/ $//'
printf '\n'

printf 'at'
for q in $qs; do
	v=$(printf '%s\n' "$out" | awk -v k="$q" '$1 == "A" && $2 == k { print $3 }')
	printf ' (%s)=%s' "$q" "$v"
done
printf '\n'
```

三行输出与 count.py 完全同格式，判据才能用同一套 `sed -n Np` 取行比对。
`pad_total` 是理论值 `(ll - w*B) * h`，`pad_AA` 是实测剩余——两者相等
即没有越界写冲掉哨兵。

## 7. input_replay.txt

### 第 1—29 行：五帧加丢帧 fixture

```text
# sec usec type code value
# 鼠标右移 10、下移 5，同时按下左键；SYN_REPORT 封口后才产出一帧。
1 100 2 0 10
1 110 2 1 5
1 120 1 272 1
1 130 0 0 0
# 大幅负位移必须被钳到左上角。
2 100 2 0 -1000
2 110 2 1 -1000
2 120 0 0 0
# 普通键盘 A。
3 100 1 30 1
3 110 0 0 0
# 鼠标左键释放。
4 100 1 272 0
4 110 0 0 0
# 绝对坐标按 0..4095 缩放到假屏 64x32，并把 BTN_TOUCH 映射成左键。
5 100 3 0 4095
5 110 3 1 0
5 120 1 330 1
5 130 0 0 0
# SYN_DROPPED 前的位移、以及它到下个 SYN_REPORT 之间的记录都必须丢弃。
6 100 2 0 99
6 110 0 3 0
6 120 2 1 77
6 130 1 272 1
6 140 0 0 0
# EOF 前没有 SYN_REPORT，不能泄露半帧。
7 100 2 0 3
```

七段各考一件事，type 编码：0=EV_SYN、1=EV_KEY、2=EV_REL、3=EV_ABS；
272=BTN_LEFT、330=BTN_TOUCH、3=SYN_DROPPED。第 2 帧只有位移没有按钮记录，
考按钮跨帧保持；第 4 帧只有按钮释放，考"释放也是 pointer 事件"；
第 6 段 DROPPED 前后各放干扰记录（99、77、BTN_LEFT 按下），考完整丢弃区间。
最后一行故意没有 REPORT，考 EOF 半帧不泄露。

## 8. input_replay_bad.txt

```text
1 0 2 0 10 unexpected_field
```

一行五个合法字段加一个第六词。`replay_read_raw` 的 `%c` 探测把返回值顶成 6，
判 `ERR_IO`，`input_test` 退出码 2（判据 [14]）。

## 9. 容易读错的地方

- 三个 `_test.c` 各自有 `main`，`make test` 单独链接；`unittest/` 不进
  `SUBDIRS`，否则 `main` 撞车（Makefile 篇第 2 节）。
- count.sh/count.py 的抽查坐标写死在脚本里，改 `disp_test` 图案必须同步改
  两个脚本与判据期望值。
- 探针位图的对称 alpha 是给"注错反序"用的，改位图前先看 [11r1] 依赖什么。
- fixture 的 type/code 是内核数值不是符号：272=BTN_LEFT、330=BTN_TOUCH、
  3=SYN_DROPPED。
- `--once` 的超时是"每次调用最多 5 秒"，不是整个程序的生命周期。

## 10. 消费者清单

- `check_core.sh`：disp_test、count.sh、count.py（[7][9]）。
- `check_font_input.sh`：font_test（[11][12]）、input_test 与两个 fixture
  （[13][14]）。
- 板上实验：count.sh 在板上对真显存转储计数（TechReport 03/04 的板上数字
  都出自它）；input_test 在板上探测真实 evdev。
