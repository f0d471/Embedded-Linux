#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "common.h"
#include "config/config.h"

/*
 * 解析规则: 一行一个 "key = value", [global]/[item] 切换小节,
 * # 或 ; 开头的整行和值后的 # 注释都忽略。识别不了的行跳过, 不当作错误
 * -- 配置是运维改的文件, 多敲一个字不应该让整台设备起不来。
 */

#define CONFIG_DEFAULT_PATH "/etc/test_gui/gui.conf"

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
