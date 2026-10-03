/* config 层单测: 同一进程里依次装四份配置, 每装一份打印一行,
 * 判据在 check 脚本里 grep。 */

#include <stdio.h>
#include <stdlib.h>

#include "common.h"
#include "config/config.h"

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

int main(int argc, char **argv)
{
	if (argc < 5) {
		fprintf(stderr,
			"usage: %s <full.conf> <partial.conf> <empty.conf> <no/such/file>\n",
			argv[0]);
		return 2;
	}

	load_one("full", argv[1]);
	load_one("partial", argv[2]);
	load_one("empty", argv[3]);
	load_one("nofile", argv[4]);

	config_exit();
	return 0;
}
