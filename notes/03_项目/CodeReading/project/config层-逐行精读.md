# config 层逐行精读

代码路径与总行数（`grep -n ''` 于 2026-10-04 核对）：
`config/config.c`（163 行）+ `config/config.h`（48 行）。

前置知识：`notes/01_应用编程/02_文件IO.md` 的标准 IO 与行读取。
文件定位：层表第六层（page 之后、business 之前）。上游是文本配置文件
（`CONFIG_FILE` 环境变量指定的路径），下游是 business（读条目与字体路径）。
消费者：business 层两处页面、`unittest/config_test`。

## config.h：对外接口

```c
// config/config.h  [15-33] 常量与结构体(节选正文)
#define CONFIG_NAME_MAX  64
#define CONFIG_CMD_MAX   128
#define CONFIG_PATH_MAX  256
#define CONFIG_ITEMS_MAX 16

struct config_item {
	char name[CONFIG_NAME_MAX];
	char command[CONFIG_CMD_MAX];
};

struct config {
	char font_file[CONFIG_PATH_MAX];   /* 空串 = 用内置点阵字体 */
	int  font_size;                    /* 像素; 0 = 走 font 层默认 */
	int  page_timeout_ms;              /* 业务主循环取事件的超时 */
	struct config_item items[CONFIG_ITEMS_MAX];
	int  item_count;
};
```

全部定长数组、无动态分配——配置在启动时读一次，生命周期与进程等长，
静态内存换掉一类释放错误。文件格式（头注释里有全文）是 INI 的极简
子集：`[section]`、`key = value`、`#`/`;` 注释。

## config.c

### [16-45] 状态、trim 与默认值

```c
static struct config g_cfg;
static int g_inited;

/* 去掉首尾空白, 原地改写并返回串首 */
static char *trim(char *s)
{
	char *end;

	while (*s == ' ' || *s == '\t')
		s++;
	end = s + strlen(s);
	while (end > s && (end[-1] == ' ' || end[-1] == '\t' ||
			   end[-1] == '\r' || end[-1] == '\n'))
		end--;
	*end = '\0';
	return s;
}

static void config_defaults(struct config *cfg)
{
	memset(cfg, 0, sizeof(*cfg));
	cfg->font_size = 0;            /* font 层自己定默认字号 */
	cfg->page_timeout_ms = 0;      /* 产品默认: 等事件永不超时 */
	/* 一个能开机就跑的演示测试项, 保证没有配置文件时界面不是空的 */
	cfg->item_count = 1;
	snprintf(cfg->items[0].name, sizeof(cfg->items[0].name), "mem");
	snprintf(cfg->items[0].command, sizeof(cfg->items[0].command),
		 "head -3 /proc/meminfo");
}
```

`trim` 收尾两侧都清，`\r` 在列是因为 Windows 编辑过的配置文件会带
CRLF——配置是运维改的文件，这一点要假设会发生。默认值里那一条演示
条目是"出厂第一次上电"的定义：没有 `/etc/test_gui/gui.conf` 也能点
出一个真的命令。

### [47-84] 注释剥离与键值应用

```c
/* 值后面的 "# ..." 是行尾注释; 值本身不含 #, 直接截断 */
static void strip_comment(char *value)
{
	char *hash = strchr(value, '#');

	if (hash != NULL)
		*hash = '\0';
}

static void apply_kv(struct config *cfg, const char *section,
		     const char *key, char *value, int item_index)
{
	char *v = value;

	strip_comment(v);
	v = trim(v);

	if (strcmp(section, "global") == 0) {
		if (strcmp(key, "font_file") == 0) {
			snprintf(cfg->font_file, sizeof(cfg->font_file),
				 "%s", v);
		} else if (strcmp(key, "font_size") == 0) {
			cfg->font_size = atoi(v);
		} else if (strcmp(key, "page_timeout_ms") == 0) {
			cfg->page_timeout_ms = atoi(v);
		}
		return;
	}
	if (strcmp(section, "item") != 0 || item_index < 0 ||
	    item_index >= CONFIG_ITEMS_MAX)
		return;
	if (strcmp(key, "name") == 0) {
		snprintf(cfg->items[item_index].name,
			 sizeof(cfg->items[item_index].name), "%s", v);
	} else if (strcmp(key, "command") == 0) {
		snprintf(cfg->items[item_index].command,
			 sizeof(cfg->items[item_index].command), "%s", v);
	}
}
```

先 `strip_comment` 再 `trim`：行尾注释切掉之后才轮到空白清理，顺序反了
会留下 `  \r` 这类尾巴。未识别的 key 与 section 直接落地为空操作——
宽容解析是刻意的，配置写坏一个字不该让设备起不来（TechReports 08 的
4.1 节记录了这套宽容曾经漏掉的一种残留）。

### [86-149] config_init：读文件主流程

```c
int config_init(void)
{
	const char *path = getenv("CONFIG_FILE");
	char line[512];
	char section[32] = "";
	int item_index = -1;
	FILE *file;

	if (g_inited)
		return ERR_OK;
	if (path == NULL || path[0] == '\0')
		path = CONFIG_DEFAULT_PATH;

	config_defaults(&g_cfg);
	file = fopen(path, "r");
	if (file == NULL) {
		/* 没有配置文件是正常形态: 出厂设备第一次上电就靠默认值跑起来 */
		LOG_INFO("config %s not found, using defaults", path);
		g_inited = 1;
		LOG_INFO("config init OK");
		return ERR_OK;
	}

	/* 文件在: 默认值整体让位, 一切以文件为准。
	 * 只重置 item_count 会让 items[0] 残留上一份默认项的字段。 */
	memset(&g_cfg, 0, sizeof(g_cfg));
	while (fgets(line, sizeof(line), file) != NULL) {
		char *s = trim(line);
		char *eq;

		if (*s == '\0' || *s == '#' || *s == ';')
			continue;
		if (*s == '[') {
			char *close = strchr(s, ']');

			if (close == NULL)
				continue;
			*close = '\0';
			snprintf(section, sizeof(section), "%s", trim(s + 1));
			if (strcmp(section, "item") == 0) {
				/* 每个新 [item] 都开一个新条目 */
				item_index = g_cfg.item_count < CONFIG_ITEMS_MAX
					   ? g_cfg.item_count : -1;
				if (item_index >= 0)
					g_cfg.item_count++;
			}
			continue;
		}
		eq = strchr(s, '=');
		if (eq == NULL)
			continue;
		*eq = '\0';
		apply_kv(&g_cfg, section, trim(s), eq + 1, item_index);
	}
	fclose(file);

	g_inited = 1;
	LOG_INFO("config %s: font=%s size=%d timeout=%d items=%d",
		 path,
		 g_cfg.font_file[0] != '\0' ? g_cfg.font_file : "(builtin)",
		 g_cfg.font_size, g_cfg.page_timeout_ms, g_cfg.item_count);
	LOG_INFO("config init OK");
	return ERR_OK;
}
```

分支图：文件不在 → 全默认；文件在 → memset 后逐行解析。`item_index`
在遇到每个新 `[item]` 时指向下一个空槽，`item_count` 同步前进；第 17
个 `[item]` 之后 `item_index` 变 -1，多出来的条目整体忽略。`init OK`
独占一行（层名紧邻行尾）是框架判据 [1] 对所有层日志的硬约定，
详情拆在它前面一行。

### [151-163] 退出与查询

```c
void config_exit(void)
{
	if (!g_inited)
		return;
	config_defaults(&g_cfg);
	g_inited = 0;
	LOG_INFO("config exit OK");
}

const struct config *config_get(void)
{
	return g_inited ? &g_cfg : NULL;
}
```

exit 恢复成默认值而不是清零：下次 init 前 `config_get` 返回 NULL，
不会有人读到半旧状态。business 层在层表里排在 config 之后，
`config_get()` 在 `business_init` 时必非 NULL。

## 执行顺序

| 步 | 成功路径 | 失败路径（文件不在） |
|---|---|---|
| 1 | 定路径（env → 默认路径） | 同左 |
| 2 | fopen 成功，memset 清默认 | fopen 失败，直接带默认值收场 |
| 3 | 逐行 trim/分节/apply_kv | 无 |
| 4 | fclose，LOG 两行 | LOG 两行（not found + init OK） |

## 容易读错的地方

1. **默认条目不是"至少一条"**：文件存在但没写 `[item]` 时 `item_count`
   是 0，主页只有"设置"一颗按钮——这是 parse 判据 [18] 明文锁定的行为。
2. **`strip_comment` 无视引号**：command 里写 `grep '#' xxx` 会被截断，
   当前测试项用不到 `#`，写进配置前先记住这条。
3. **行长度上限 512**：更长的行被 fgets 截成两半，两半都解析失败——
   表现是"这一项少几个字段"，判据 [18] 的全字段 fixture 顶格测试过。

## 消费者清单

| 消费者 | 用到的接口 |
|---|---|
| business/business_manager.c | `config_get()`（字体路径、超时、条目） |
| business/business_main_page.c | `config_get()`、`CONFIG_ITEMS_MAX` |
| unittest/config_test.c | 全部四个接口 |
| check_gui.sh [18] | 四份 fixture 的读回值逐项对账 |
