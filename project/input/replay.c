#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "common.h"
#include "input/input_internal.h"

static FILE *g_file;

static int replay_open(struct input_source_info *out)
{
	const char *path = getenv("INPUT_REPLAY");

	if (path == NULL || path[0] == '\0')
		return ERR_PARAM;
	g_file = fopen(path, "r");
	if (g_file == NULL)
		return ERR_IO;
	memset(out, 0, sizeof(*out));
	snprintf(out->name, sizeof(out->name), "text replay");
	snprintf(out->path, sizeof(out->path), "%s", path);
	out->has_relative = 1;
	out->has_absolute = 1;
	out->has_keys = 1;
	out->abs_x_min = 0;
	out->abs_x_max = 4095;
	out->abs_y_min = 0;
	out->abs_y_max = 4095;
	return ERR_OK;
}

static void replay_close(void)
{
	if (g_file != NULL) {
		fclose(g_file);
		g_file = NULL;
	}
}

static int replay_get_fd(void)
{
	return g_file == NULL ? -1 : fileno(g_file);
}

static int replay_read_raw(struct input_raw_event *out)
{
	char line[256], extra;
	long long sec, usec;
	unsigned int type, code;
	int value;

	if (g_file == NULL || out == NULL)
		return ERR_PARAM;
	while (fgets(line, sizeof(line), g_file) != NULL) {
		if (line[0] == '#' || line[0] == '\n')
			continue;
		if (sscanf(line, "%lld %lld %u %u %d %c",
			   &sec, &usec, &type, &code, &value, &extra) != 5)
			return ERR_IO;
		out->sec = sec;
		out->usec = usec;
		out->type = (uint16_t)type;
		out->code = (uint16_t)code;
		out->value = value;
		return ERR_OK;
	}
	return ferror(g_file) ? ERR_IO : ERR_NOTFOUND;
}

static struct input_provider g_replay = {
	.name = "replay",
	.open = replay_open,
	.close = replay_close,
	.get_fd = replay_get_fd,
	.read_raw = replay_read_raw,
};

void replay_register(void)
{
	input_register(&g_replay);
}
