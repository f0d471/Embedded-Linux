#ifndef __CONFIG_MANAGER_H
#define __CONFIG_MANAGER_H

/*
 * config 层对外接口。
 * 一份文本配置决定界面上有几个测试项、每个测试项点什么命令、
 * 字体用哪个文件。改配置不重编, 是这个产品"不改代码换一套测试项"的根基。
 *
 * 文件格式(缺字段一律走默认值, 文件不存在也一样):
 *
 *   # 整行注释
 *   [global]
 *   font_file = /usr/share/fonts/liberation/LiberationSans-Regular.ttf
 *   font_size = 24                # 也可以写在行尾
 *   page_timeout_ms = 0           # 0 = 等事件永不超时
 *   [item]
 *   name = mem
 *   command = head -3 /proc/meminfo
 *   [item]
 *   name = ap3216
 *   command = ap3216_read
 */

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

int  config_init(void);
void config_exit(void);

/* config_init 成功后返回当前生效的配置, 之前返回 NULL。 */
const struct config *config_get(void);

#endif /* __CONFIG_MANAGER_H */
