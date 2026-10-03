# check 脚本逐行精读

对应代码（`grep -n ''` 于 2026-10-04 核对）：`project/check.sh`（41 行，
总入口）、`check_core.sh`（约 310 行，框架/display）、
`check_font_input.sh`（约 300 行，font/input/netinput/多线程）、
`check_gui.sh`（约 290 行，config/ui/page/business/items）。

## 1. 文件定位

判据体系的三层结构：总入口设好确定性环境后调三个 suite，各自累计
PASS/FAIL/SKIP，入口汇总出 TOTAL 并要求三个 suite 的退出码全为 0。
两条原则写在 core 脚本头部：判据尽量做成计数型或序列型，"输出里有
某个词"型判据太容易假绿；每条正判据后面跟一次注错见红，注错不红
等于没有判据。所有破坏性操作（注错 sed、临时文件）都在 /tmp 副本里
做，不动工作区。

第 06-09 章的增量：[15]/[16]/[17] 三组（netinput、压力对账、tsan）
进 font_input 套件，新增 check_gui.sh 四组（[18]-[23]），core 套件
的框架数字随层表从 6 层变 7 层更新。

## 2. check.sh：总入口

```bash
# project/check.sh  [10-13] 确定性环境(节选)
export DISP_DEV=mem
export FONT_DEV=builtin
export INPUT_BACKEND=replay
export INPUT_REPLAY=/dev/null

# check_core.sh 会把 project/ 复制进 /tmp；依赖包不能再用相对仓库路径。
export FT_TARBALL=${FT_TARBALL:-/mnt/e/Workspace/01_all_series_quickstart-master/04_嵌入式Linux应用开发基础知识/source/10_freetype/freetype-2.10.2.tar.xz}
```

```bash
# project/check.sh  [28-41] 三套件汇总(节选)
run_suite check_core.sh "$W/core.out"; CORE_RC=$?
run_suite check_font_input.sh "$W/font_input.out"; EXTRA_RC=$?
run_suite check_gui.sh "$W/gui.out"; GUI_RC=$?
...
read -r P1 F1 S1 <<<"$(read_result "$W/core.out")"
read -r P2 F2 S2 <<<"$(read_result "$W/font_input.out")"
read -r P3 F3 S3 <<<"$(read_result "$W/gui.out")"

echo
echo "TOTAL PASS=$((P1 + P2 + P3))  FAIL=$((F1 + F2 + F3))  SKIP=$((S1 + S2 + S3))"
{ [ "$CORE_RC" -eq 0 ] && [ "$EXTRA_RC" -eq 0 ] && [ "$GUI_RC" -eq 0 ]; } && \
	[ "$((F1 + F2 + F3))" -eq 0 ]
```

四个环境变量把"没有真实硬件"的 WSL 钉进确定性分支：假显存、内置
点阵、回放输入、空回放。`run_suite` 用 `tee` 留一份输出再用
`PIPESTATUS[0]` 取脚本真实退出码——read_result 只对数字，suite 内部
的 FAIL 会先体现在退出码上。TOTAL 的三项全 0 才算绿，仓根 README
的 PASS 数就是这一行。

## 3. check_core.sh：框架与 display

[1]-[10] 组的完整讲解见旧篇（TechReports 03 的判据叙事），本篇记
第 08 章的改动：

```bash
# project/check_core.sh  [35-44] 配置与层表(节选)
# business 主循环取事件的超时走配置; 判据里给它一个短超时, 否则默认配置
# (page_timeout_ms = 0 永久等待)会让 product_tool 在无输入时挂死。
printf '[global]\npage_timeout_ms = 300\n' > etc_check.conf
export CONFIG_FILE=etc_check.conf

# unittest/ 与 items/ 由 make test 单独编, make 不碰它们, 不算进"应该重编的文件数"
NSRC=$(find . -name '*.c' -not -path './build/*' -not -path './unittest/*' -not -path './items/*' | wc -l)
INIT_SEQ="display input font ui page config business "
EXIT_SEQ="business config page ui font input display "
```

三处联动：`CONFIG_FILE` 给出短超时（默认值 0 = 永久等待，product_tool
会在 [1] 挂死——这是 business 主循环带进判据的第一个"环境必须喂"）；
`NSRC` 的 find 排除 items（与 unittest 同理，`make` 不编它们）；
两个序列变成七层。`init OK` 计数 6→7、`exit OK` 同、[1r] 注错删
business 行后"其余 6 层照常启停"、[6] 的日志行数 13→20（七层加
config 详情、business 几何、页面 created/destroyed、loop end），
每个数字都由 `awk '{print $(NF-2)}'` 的提取规则牵动——层名紧邻
`init OK` 的约定在 TechReports 08 的 4.3 节。

## 4. check_font_input.sh：font/input/netinput/多线程

[11]-[14] 见旧篇。[15] 起：

```bash
# project/check_font_input.sh  [161-185] [15] 组(节选)
echo "[15] netinput: 网络输入源挂同一条注册链表"
make test >/dev/null 2>&1
PORT=$((21000 + RANDOM % 20000))

INPUT_BACKEND=netinput NETINPUT_PORT=$PORT \
	./build/x86/unittest/input_test --wait 3000 --count 5 \
	>"$W/net.out" 2>&1 &
NI_SRV=$!
sleep 1
./build/x86/unittest/netinput_send 127.0.0.1 $PORT \
	unittest/input_replay.txt >"$W/net-send.out" 2>&1
wait $NI_SRV; NI_RC=$?
ck "发送端发满 21 条原始记录" "$(cat "$W/net-send.out")" "sent 21 records"
ck "网络路径产出 5 个应用事件" "$(grep -Ec '^(pointer|key) ' "$W/net.out")" "5"
ck "网络路径与 replay 路径逐行相同" \
   "$(grep -E '^(pointer|key) ' "$W/net.out")" "$EXPECTED_INPUT"
```

判据的立意：同一份 fixture（21 条原始记录、5 帧）走回放与走 TCP 必须
产出逐行相同的应用事件——`EXPECTED_INPUT` 复用 [13] 的变量，两条
路径共毫秒级差异地收敛到同一串输出。端口每次随机，套件重复跑不撞
TIME_WAIT。无客户端判据用 `date +%s` 量窗口：退出码 0 之外还要
"等满 4 秒以上"，证明是真超时不是立即返回。

```bash
# project/check_font_input.sh  [222-247] [16]/[17] 组(节选)
echo "[16] 多线程: 读取线程 + 环形队列, 丢帧有账"
awk 'BEGIN { for (i = 0; i < 400; i++) { print 1, 0, 2, 0, 1; print 1, 0, 0, 0, 0 } }' \
	> "$W/stress_replay.txt"
INPUT_BACKEND=replay INPUT_REPLAY="$W/stress_replay.txt" \
	./build/x86/unittest/input_test --wait 1000 --slow 5000 \
	>"$W/stress.out" 2>&1
...
ck "三本账闭合 received=delivered+dropped" "$((S_RECV - S_DELIV - S_DROP))" "0"
ck "慢消费者确实挤掉了旧帧" "$([ "$S_DROP" -gt 0 ] && echo yes || echo no)" "yes"

echo "[17] tsan: 线程与队列无数据竞争"
make distclean >/dev/null 2>&1
if make test CFLAGS_EXTRA=-fsanitize=thread LDFLAGS_EXTRA=-fsanitize=thread >/dev/null 2>&1; then
	...
	ck "tsan 无竞争报告" "$(grep -c 'WARNING: ThreadSanitizer' "$W/tsan.out")" "0"

	echo "[17r] 注错: 拆掉队列的互斥锁"
	sed -i 's/pthread_mutex_lock(&g_lock);/(void)0;/' input/input_manager.c
	...
	red "tsan 无竞争报告" "$(grep -c 'WARNING: ThreadSanitizer' "$W/tsan-bad.out")" "0"
else
	skip "tsan 判据" "线程净化器在本机编译失败"
fi
```

[16] 的四条判据全部锚在 stats 行：400 帧采集、送达数与 pointer 行数
相等（统计不虚报）、三本账闭合、dropped>0（策略真的在丢）。[17]
先证明 tsan 构建可行再跑绿判据，注错把 `pthread_mutex_lock(&g_lock)`
整体换成 `(void)0;`——实测报 7 处竞争。tsan 依赖本机内核地址布局，
编译失败走 skip 而非 FAIL（[17r] 的红判据同时是 tsan 活性的证据，
假绿会被它抓走）。

## 5. check_gui.sh：四层与 items

```bash
# project/check_gui.sh  [24-48] [18] 组(节选)
echo "[18] config 层: 四份配置的解析与默认值"
make test >/dev/null 2>&1
./build/x86/unittest/config_test "$F/full.conf" "$F/partial.conf" \
	"$F/empty.conf" /no/such/file >"$W/cfg.out" 2>&1
ck "全字段逐项读回" \
   "$(sed -n 's/^cfg full \(.*\)$/  \1/p' "$W/cfg.out" | head -1 | sed 's/^  //')" \
   "font=/usr/share/fonts/liberation/LiberationSans-Regular.ttf size=32 timeout=1500 items=3"
ck "行尾注释与带空格的命令原样保留" "$(grep '^cfg full item0' "$W/cfg.out")" \
   "cfg full item0 name=mem cmd=head -3 /proc/meminfo"
...
echo "[18r] 注错: key=value 的切分失效, 所有键都读不进来"
sed -i "s/\*eq = '\\\\0';/\*eq = *eq;/" config/config.c
make test >/dev/null 2>&1
./build/x86/unittest/config_test "$F/full.conf" "$F/partial.conf" \
	"$F/empty.conf" /no/such/file >"$W/cfg-bad.out" 2>&1
red "全字段逐项读回" \
    "$(sed -n 's/^cfg full \(.*\)$/  \1/p' "$W/cfg-bad.out" | head -1 | sed 's/^  //')" \
    "font=/usr/share/fonts/liberation/LiberationSans-Regular.ttf size=32 timeout=1500 items=3"
cp "$SRC/config/config.c" config/config.c
```

四象限读回值逐项对账；[18r] 把 `*eq = '\0'` 改成自赋值——`=` 右侧
原样保留，键名带着 `= value` 去匹配，全部键落空，full fixture 读回
默认值，正判据立刻红。[19] 组跑 ui_test 两次（正常 + `--hold`），
显存转储喂 count.sh，期望分布是实测值：

```bash
# project/check_gui.sh  [97-99] [19] 组的两个分布(节选)
UI_DISTRIB_NORMAL="00000000:6592 00303030:1242 00909090:232 00ffffff:126"
UI_DISTRIB_HOLD="00000000:6592 00303030:618 00707070:624 00909090:232 00ffffff:126"
```

静态背景 6592、两颗按钮静止底色 1242、边框 232、白字 126；hold 态
静止底色少 624、按下底色 624——按下态改的是整块内芯。[19r] 注错
把 `UI_BG_PRESSED` 写成静止色，hold 分布立刻对不上。[20] 组两页
互切 50 轮（`page_test 50` 的六个数字）加"不销毁旧页"的计数注错与
ASan 双跑（`free(btn)` 注错，见 TechReports 08 的 4.5 节）。

```bash
# project/check_gui.sh  [188-208] [21]/[22] 组(节选)
e2e_run() {
	awk 'BEGIN {
		print "0 0 2 0 -78"; print "0 0 2 1 -92"; print "0 0 0 0 0";
		print "0 0 1 272 1"; print "0 0 0 0 0";
		print "0 0 1 272 0"; print "0 0 0 0 0";
		print "0 0 2 0 156"; print "0 0 2 1 48"; print "0 0 0 0 0";
		print "0 0 1 272 1"; print "0 0 0 0 0";
		print "0 0 1 272 0"; print "0 0 0 0 0";
		print "0 0 1 272 1"; print "0 0 0 0 0";
		print "0 0 1 272 0"; print "0 0 0 0 0";
		print "0 0 1 16 1"; print "0 0 0 0 0";
	}' > "$W/e2e.replay"
	DISP_MEM=320x240x32x1280 CONFIG_FILE="$F/e2e.conf" \
		INPUT_BACKEND=replay INPUT_REPLAY="$W/e2e.replay" \
		./build/x86/product_tool >"$W/e2e.out" 2>&1
}

echo "[21] business: 输入 -> 页面 -> 控件 -> 命令 整条链"
...
ck "点 mem 测试项执行了 head 命令" "$(grep -c 'item mem rc=0' "$W/e2e.out")" "1"
ck "两次回到主页" "$(grep -c 'page main created' "$W/e2e.out")" "2"
ck "q 键结束主循环" \
   "$(grep 'business loop end' "$W/e2e.out" | sed 's/^\[[^]]*\] [^ ]* //')" \
   "business loop end events=9"
```

端到端组把四层串成一条链：awk 生成 20 行回放（320x240 布局的点击
坐标按 `business_internal.h` 公式手算：测试项中心 (82,28)、设置
(238,76)），product_tool 跑完，四条 grep 分别钉住命令执行（rc=0）、
页面切换、事件计数。坐标与布局的耦合写在 [21] 组头注释里——布局
改，坐标改，这是刻意的。`loop end` 行先剥掉日志前缀（`[I] 路径:行号 `）
再对账，行号随代码漂移不能进判据。

[22] 组 items：`ap3216_read --bus 99` 无总线退出码 1；serial 用
`serial_pty.py` 开伪终端回显，`serial ok=5/5` 加退出码 0；[22r]
把校验和起点错开一个字节，回显核对变红。[23] 组分层边界四条
grep（`/dev/i2c` 只在 items、termios 只在 items、pthread_create 只在
input、fork 只在 business）加一条注错。

## 6. 执行顺序与消费者清单

| 阶段 | 发生了什么 | 耗时占比 |
|---|---|---|
| core [1]-[6] | 多轮 rm -rf build + make，构建判据为主 | 约 1/3 |
| core [7]-[10] / font [11]-[14] | 假显存转储 + count.sh，纯本机 | 轻 |
| font [15]-[17] | netinput 等待窗口 + 400 帧压力 + tsan 两轮构建 | 约 1/3 |
| gui [18]-[23] | 四层单测 + ASan 两轮构建 + 端到端 | 约 1/3 |

| 消费者 | 用到的输出 |
|---|---|
| 仓根 README.md | TOTAL PASS 数（124） |
| TechReports 各章第五节 | 各组实测数字与注错输出 |
| CodeReading 各层篇 | 每条判据引用的行为定义 |
