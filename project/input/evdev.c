#include <errno.h>
#include <fcntl.h>
#include <linux/input.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

#include "common.h"
#include "input/input_internal.h"

#define BITS_PER_LONG (sizeof(unsigned long) * 8)
#define NBITS(max) (((max) + BITS_PER_LONG) / BITS_PER_LONG)

static int g_fd = -1;

static int bit_is_set(const unsigned long *bits, int bit)
{
	return !!(bits[bit / BITS_PER_LONG] & (1ul << (bit % BITS_PER_LONG)));
}

static int read_abs_range(int fd, int primary, int fallback, int *min, int *max)
{
	struct input_absinfo abs;

	if (ioctl(fd, EVIOCGABS(primary), &abs) == 0) {
		*min = abs.minimum;
		*max = abs.maximum;
		return 1;
	}
	if (fallback >= 0 && ioctl(fd, EVIOCGABS(fallback), &abs) == 0) {
		*min = abs.minimum;
		*max = abs.maximum;
		return 1;
	}
	return 0;
}

static int probe_fd(int fd, const char *path, struct input_source_info *out)
{
	unsigned long ev[NBITS(EV_MAX)];
	unsigned long rel[NBITS(REL_MAX)];
	unsigned long abs[NBITS(ABS_MAX)];
	unsigned long key[NBITS(KEY_MAX)];
	char name[sizeof(out->name)] = "unknown";
	int code, key_count = 0, score = 0;

	memset(ev, 0, sizeof(ev));
	memset(rel, 0, sizeof(rel));
	memset(abs, 0, sizeof(abs));
	memset(key, 0, sizeof(key));
	if (ioctl(fd, EVIOCGBIT(0, sizeof(ev)), ev) < 0)
		return -1;
	(void)ioctl(fd, EVIOCGNAME(sizeof(name)), name);

	memset(out, 0, sizeof(*out));
	snprintf(out->name, sizeof(out->name), "%s", name);
	snprintf(out->path, sizeof(out->path), "%s", path);
	if (bit_is_set(ev, EV_REL) &&
	    ioctl(fd, EVIOCGBIT(EV_REL, sizeof(rel)), rel) >= 0 &&
	    bit_is_set(rel, REL_X) && bit_is_set(rel, REL_Y)) {
		out->has_relative = 1;
		score += 400;
	}
	if (bit_is_set(ev, EV_ABS) &&
	    ioctl(fd, EVIOCGBIT(EV_ABS, sizeof(abs)), abs) >= 0 &&
	    ((bit_is_set(abs, ABS_X) && bit_is_set(abs, ABS_Y)) ||
	     (bit_is_set(abs, ABS_MT_POSITION_X) && bit_is_set(abs, ABS_MT_POSITION_Y)))) {
		out->has_absolute = 1;
		read_abs_range(fd, ABS_X, ABS_MT_POSITION_X,
			       &out->abs_x_min, &out->abs_x_max);
		read_abs_range(fd, ABS_Y, ABS_MT_POSITION_Y,
			       &out->abs_y_min, &out->abs_y_max);
		score += 300;
	}
	if (bit_is_set(ev, EV_KEY) &&
	    ioctl(fd, EVIOCGBIT(EV_KEY, sizeof(key)), key) >= 0) {
		for (code = 0; code <= KEY_MAX; code++)
			if (bit_is_set(key, code))
				key_count++;
		out->has_keys = key_count > 0;
		if (key_count > 0)
			score += strstr(name, "power") != NULL ? 10 : 100;
	}
	return score;
}

static int evdev_open(struct input_source_info *out)
{
	struct input_source_info candidate, best;
	const char *forced = getenv("INPUT_DEV");
	char path[64], best_path[64] = "";
	int fd, i, score, best_score = -1;

	if (forced != NULL) {
		g_fd = open(forced, O_RDONLY | O_NONBLOCK);
		if (g_fd < 0)
			return ERR_IO;
		if (probe_fd(g_fd, forced, out) < 0) {
			close(g_fd);
			g_fd = -1;
			return ERR_NOTSUP;
		}
		return ERR_OK;
	}

	for (i = 0; i < 32; i++) {
		snprintf(path, sizeof(path), "/dev/input/event%d", i);
		fd = open(path, O_RDONLY | O_NONBLOCK);
		if (fd < 0)
			continue;
		score = probe_fd(fd, path, &candidate);
		close(fd);
		if (score > best_score) {
			best_score = score;
			best = candidate;
			snprintf(best_path, sizeof(best_path), "%s", path);
		}
	}
	if (best_score < 0)
		return ERR_NOTFOUND;
	g_fd = open(best_path, O_RDONLY | O_NONBLOCK);
	if (g_fd < 0)
		return ERR_IO;
	*out = best;
	return ERR_OK;
}

static void evdev_close(void)
{
	if (g_fd >= 0) {
		close(g_fd);
		g_fd = -1;
	}
}

static int evdev_get_fd(void)
{
	return g_fd;
}

static int evdev_read_raw(struct input_raw_event *out)
{
	struct input_event event;
	ssize_t got;

	if (out == NULL || g_fd < 0)
		return ERR_PARAM;
	do {
		got = read(g_fd, &event, sizeof(event));
	} while (got < 0 && errno == EINTR);
	if (got < 0 && (errno == EAGAIN || errno == EWOULDBLOCK))
		return ERR_BUSY;
	if (got == 0)
		return ERR_NOTFOUND;
	if (got != (ssize_t)sizeof(event))
		return ERR_IO;
	out->sec = event.input_event_sec;
	out->usec = event.input_event_usec;
	out->type = event.type;
	out->code = event.code;
	out->value = event.value;
	return ERR_OK;
}

static struct input_provider g_evdev = {
	.name = "evdev",
	.open = evdev_open,
	.close = evdev_close,
	.get_fd = evdev_get_fd,
	.read_raw = evdev_read_raw,
};

void evdev_register(void)
{
	input_register(&g_evdev);
}
