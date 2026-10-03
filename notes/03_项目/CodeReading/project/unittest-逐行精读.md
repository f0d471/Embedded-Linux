# unittest 逐行精读

对应代码（`grep -n ''` 于 2026-10-04 核对）：
`project/unittest/disp_test.c`（42 行）、`font_test.c`（137 行）、
`input_test.c`（100 行）、`netinput_send.c`（131 行）、`config_test.c`
（47 行）、`ui_test.c`（88 行）、`page_test.c`（121 行）、`count.py`
（30 行）、`count.sh`（73 行）、`serial_pty.py`（38 行）、
`input_replay.txt`（29 行）、`input_replay_bad.txt`（1 行）、
`conf_fixtures/`（4 份 .conf）。

## 1. 文件定位

单层功能测（check.sh 管的是框架约定）。每个 `unittest/*.c` 自带 main，
由 Makefile 的 test 目标单独链成同名可执行；判定不靠肉眼——画图类
程序把显存转储交给独立的 `count.sh`/`count.py` 数，网络类程序的
输出由 check 脚本逐行对账。display/font 两篇的旧内容仍有效，本篇
补第 06-09 章的四个新成员与两个接口变化。

## 2. input_test.c：三种取事件姿势

```c
// unittest/input_test.c  [23-45] 参数与主循环(节选)
	int wait_ms = 0;   /* 每次取事件的最长等待; 0 = 只看现有数据 */
	int limit = 0;     /* 取满多少个事件后退出; 0 = 不限 */
	int slow_us = 0;   /* 每取一个事件睡多久, 模拟慢消费者 */
	int done = 0;
	int i;
	...
	for (i = 1; i < argc; i++) {
		if (strcmp(argv[i], "--probe") == 0) {
			goto out;
		} else if (strcmp(argv[i], "--once") == 0) {
			wait_ms = 5000;
			limit = 1;
		} else if (strcmp(argv[i], "--wait") == 0 && i + 1 < argc) {
			wait_ms = atoi(argv[++i]);
		} else if (strcmp(argv[i], "--count") == 0 && i + 1 < argc) {
			limit = atoi(argv[++i]);
		} else if (strcmp(argv[i], "--slow") == 0 && i + 1 < argc) {
			slow_us = atoi(argv[++i]);
		}
	}

	for (;;) {
		ret = input_get_event(&event, wait_ms);
		if (ret == ERR_NOTFOUND || ret == ERR_BUSY)
			break;
		if (ret != ERR_OK)
			return 2;
		...
		done++;
		if (slow_us > 0)
			usleep((useconds_t)slow_us);
		if (limit > 0 && done >= limit)
			break;
	}

	{
		struct input_stats stats;

		if (input_get_stats(&stats) == ERR_OK)
			printf("stats received=%d delivered=%d dropped=%d\n",
			       stats.received, stats.delivered, stats.dropped);
	}
```

第 05 章的 `--probe`/`--once` 之外新增三个参数：`--wait MS`（每次
取事件的期限，线程化后"timeout=0 就能拿到回放数据"的同步假设不再
成立，判据 [13] 全部用它）、`--count N`（网络判据要"收满 5 个就退"，
不等整个超时窗口）、`--slow US`（压力判据 [16] 把消费者拖慢到
5ms/帧，让 32 槽队列溢出）。`stats` 行是三本账的出口，[16] 的对账
就是 grep 这一行。

## 3. netinput_send.c：协议对端

```c
// unittest/netinput_send.c  [23-33] 线上格式声明
struct netinput_record {
	uint16_t magic;
	uint16_t type;
	uint16_t code;
	uint16_t pad;
	int32_t  value;
	int32_t  sec;
	int32_t  usec;
} __attribute__((packed));

/* 与 input/netinput.c 的线上格式保持逐字节一致; 真正的契约在
 * TechReports 的格式表里。 */
_Static_assert(sizeof(struct netinput_record) == 20, "wire record is 20 bytes");
```

吃 `input_replay.txt` 同格式的文本行（`%lld %lld %u %u %d %c` 探测
写法与 replay 后端一致，第 6 个字段抓多余词），逐行变成 20 字节记录
write 到 socket。两个注错开关：`--bad` 首条记录 magic 加一（服务端
校验判据），`--partial` 只发 10 字节就断开（"半条记录不杀伤服务"
判据）。它链接全部层 .o（unittest 链接规则的统一行为），只是不用——
判据 [15] 的端口由脚本随机选，服务端与发送端各自独立进程。

## 4. config_test.c：一程序四配置

```c
// unittest/config_test.c  [13-30] 装载与打印
static void load_one(const char *tag, const char *path)
{
	const struct config *cfg;
	int i;

	setenv("CONFIG_FILE", path, 1);
	config_exit();
	if (config_init() != ERR_OK) {
		printf("cfg %s init failed\n", tag);
		return;
	}
	cfg = config_get();
	printf("cfg %s font=%s size=%d timeout=%d items=%d\n", tag,
	       cfg->font_file[0] != '\0' ? cfg->font_file : "(builtin)",
	       cfg->font_size, cfg->page_timeout_ms, cfg->item_count);
	for (i = 0; i < cfg->item_count; i++)
		printf("cfg %s item%d name=%s cmd=%s\n", tag, i,
		       cfg->items[i].name, cfg->items[i].command);
}
```

同一进程里 `config_exit` + `setenv` + `config_init` 循环四次，
把全字段/缺字段/仅注释/文件不存在四个象限各打一行。打印格式
（`cfg <tag> ...`）是判据 [18] 的 grep 锚；`name=mem` 后面的
`cmd=` 带空格的命令原样出现，验证的是行尾注释与空格保留。

## 5. ui_test.c：像素交给 count.sh

```c
// unittest/ui_test.c  [46-58] 两颗按钮与 --hold 出口
	ok = ui_button_create("OK", 8, 8, 40, 20, on_ok, NULL);
	no = ui_button_create("NO", 56, 8, 40, 20, on_no, NULL);
	if (ok == NULL || no == NULL)
		return 1;
	ui_button_draw_all();
	printf("ui count=%d\n", ui_button_count());

	if (argc > 1 && strcmp(argv[1], "--hold") == 0) {
		/* 带着按下态退出, count.sh 数按下底色的像素 */
		ui_button_press(28, 18);
		printf("hold pressed=%d\n", ui_button_is_pressed(ok));
		ui_exit();
		font_exit();
		display_exit();
		return 0;
	}
```

正常路径走"命中点击 / 挪出回弹 / 空地按下"三个分支，打印返回值；
`--hold` 让程序带着按下态退出，memdisp 后端把显存转储交给
`count.sh` 数：静止态分布里 0x707070 必须是 0 个，hold 分布里必须
是 624 个——按下态"屏幕可见"由像素数证明，判据 [19]/[19r] 的
全部数字来自这两份转储。

## 6. page_test.c：建毁对账

```c
// unittest/page_test.c  [98-114] 互切与总结行
	page_register(&g_page_a);
	page_register(&g_page_b);
	if (page_switch("A") != ERR_OK)
		return 1;

	for (i = 0; i < rounds; i++) {
		click(15, 15);    /* A 的按钮: A -> B */
		click(15, 45);    /* B1 的按钮: B -> A */
	}

	printf("page_test creates=%d/%d destroys=%d/%d switches=%d"
	       " final=%s count=%d\n",
	       g_a_creates, g_b_creates, g_a_destroys, g_b_destroys,
	       g_switches, page_current_name(), ui_button_count());
```

两颗最小页面互切：A 一颗按钮、B 两颗，`click()` 是"按下+抬起"两条
事件直接喂 `page_dispatch`。总结行的六个数字（50 轮后
`creates=51/50 destroys=50/50 switches=100 final=A count=1`）由
判据 [20] 逐项锁定；ASan 下跑 20 轮（[20r2]）看泄漏。假页面的
destroy 必须真销毁按钮——页面的建毁平衡就是它要测的东西。

## 7. serial_pty.py：伪终端当对端

```python
# unittest/serial_pty.py  [11-31] 正文
def main():
    program = sys.argv[1]
    count = sys.argv[2] if len(sys.argv) > 2 else "5"
    master, slave = pty.openpty()
    slave_name = os.ttyname(slave)
    proc = subprocess.Popen(
        [program, slave_name, "--count", count],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    while proc.poll() is None:
        ready, _, _ = select.select([master], [], [], 0.2)
        if master in ready:
            data = os.read(master, 256)
            if data:
                os.write(master, data)
    sys.stdout.write(proc.stdout.read())
    sys.exit(proc.returncode)
```

`pty.openpty()` 开一对伪终端，从端路径给 `serial_loop` 当串口设备，
主端收到什么回什么——TX-RX 短接跳线的纯软件替身。程序发出的每帧
原样回来，校验核对判据（[22]）由此在本机成立；程序退出码原样透传，
check 脚本直接判。

## 8. count.sh / count.py 与 fixtures

两个独立实现的计数器（shell+od/awk 与 python）互相校验，判据 [7]
锁定"两实现同结果"；第 08 章的 ui 判据复用它们，几何参数换成
128x64x32x520（行尾 8 字节填充，哨兵仍在岗）。`conf_fixtures/`
四份配置与 `input_replay*.txt` 同属"判据的输入也是代码"——改格式
必须连判据一起改。

## 9. 执行顺序与消费者清单

| 程序 | 判据组 | 退出码含义 |
|---|---|---|
| disp_test / font_test | [7]/[11]/[12] | 0 = 跑完（判定在转储） |
| input_test | [13]-[17] | 2 = 输入层错误，1 = init 失败 |
| netinput_send | [15]/[15r] | 0 = 发完；2 = 连接/格式问题 |
| config_test | [18]/[18r] | 0 = 四象限打完 |
| ui_test | [19]/[19r] | 0 = 正常（含 --hold 出口） |
| page_test | [20]-[20r2] | 0 = 互切完成 |
| serial_pty.py | [22]/[22r] | 透传 serial_loop 退出码 |
