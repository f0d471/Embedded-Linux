/* 板上文件系统探针：稀疏文件、char 默认符号和同步写代价。
 *
 * 用法：./board_fs_probe DIR
 * DIR 必须是允许创建临时文件的目录。程序结束前会删除自己创建的文件。
 */
#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

enum {
	BLOCK_SIZE = 4096,
	WRITE_COUNT = 64,
	ROUNDS = 5,
};

static long long elapsed_us(const struct timespec *start,
			    const struct timespec *end)
{
	return (end->tv_sec - start->tv_sec) * 1000000LL +
	       (end->tv_nsec - start->tv_nsec) / 1000;
}

static int write_all(int fd, const void *buf, size_t len)
{
	const char *p = buf;

	while (len > 0) {
		ssize_t n = write(fd, p, len);

		if (n < 0) {
			if (errno == EINTR)
				continue;
			return -1;
		}
		p += n;
		len -= (size_t)n;
	}
	return 0;
}

static int make_path(char *out, size_t size, const char *dir,
		     const char *name)
{
	int n = snprintf(out, size, "%s/%s-%ld", dir, name, (long)getpid());

	if (n < 0 || (size_t)n >= size) {
		errno = ENAMETOOLONG;
		return -1;
	}
	return 0;
}

static int probe_sparse(const char *dir)
{
	char path[512] = {0};
	struct stat st;
	int fd = -1;
	int rc = -1;

	if (make_path(path, sizeof(path), dir, "codex-hole") < 0)
		goto out;
	fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
	if (fd < 0)
		goto out;
	if (lseek(fd, 1024 * 1024, SEEK_SET) < 0)
		goto out;
	if (write_all(fd, "END\n", 4) < 0)
		goto out;
	if (fsync(fd) < 0)
		goto out;
	if (fstat(fd, &st) < 0)
		goto out;

	printf("hole_size=%lld hole_blocks_512=%lld allocated_bytes=%lld\n",
	       (long long)st.st_size, (long long)st.st_blocks,
	       (long long)st.st_blocks * 512);
	rc = 0;
out:
	if (rc < 0)
		perror("sparse probe");
	if (fd >= 0)
		close(fd);
	if (path[0] != '\0')
		unlink(path);
	return rc;
}

static int cmp_ll(const void *a, const void *b)
{
	const long long aa = *(const long long *)a;
	const long long bb = *(const long long *)b;

	return (aa > bb) - (aa < bb);
}

static int char_equals(char value, int expected)
{
	return value == expected;
}

static int probe_sync_mode(const char *dir, const char *label, int flags,
			   int fsync_each)
{
	char path[512];
	char buf[BLOCK_SIZE];
	long long samples[ROUNDS];
	int round;

	memset(buf, 0x5a, sizeof(buf));
	if (make_path(path, sizeof(path), dir, label) < 0)
		return -1;

	for (round = 0; round < ROUNDS; round++) {
		struct timespec start, end;
		int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC | flags, 0644);
		int i;

		if (fd < 0)
			goto fail;
		if (clock_gettime(CLOCK_MONOTONIC, &start) < 0) {
			close(fd);
			goto fail;
		}
		for (i = 0; i < WRITE_COUNT; i++) {
			if (write_all(fd, buf, sizeof(buf)) < 0 ||
			    (fsync_each && fsync(fd) < 0)) {
				close(fd);
				goto fail;
			}
		}
		if (!fsync_each && !(flags & O_SYNC) && fsync(fd) < 0) {
			close(fd);
			goto fail;
		}
		if (close(fd) < 0)
			goto fail;
		if (clock_gettime(CLOCK_MONOTONIC, &end) < 0)
			goto fail;
		samples[round] = elapsed_us(&start, &end);
	}

	qsort(samples, ROUNDS, sizeof(samples[0]), cmp_ll);
	printf("%-22s median_us=%lld (%d x %d-byte writes, %d rounds)\n",
	       label, samples[ROUNDS / 2], WRITE_COUNT, BLOCK_SIZE, ROUNDS);
	unlink(path);
	return 0;

fail:
	perror(label);
	unlink(path);
	return -1;
}

int main(int argc, char **argv)
{
	const char *dir;
	char c = (char)0xef;

	if (argc != 2) {
		fprintf(stderr, "usage: %s DIR\n", argv[0]);
		return 2;
	}
	dir = argv[1];

	printf("directory=%s\n", dir);
	printf("char_default=%s char_0xef_as_int=%d direct_eq=%d unsigned_eq=%d\n",
	       (char)-1 < 0 ? "signed" : "unsigned", (int)c,
	       char_equals(c, 0xef), (unsigned char)c == 0xef);
	if (probe_sparse(dir) < 0 ||
	    probe_sync_mode(dir, "buffered+one-fsync", 0, 0) < 0 ||
	    probe_sync_mode(dir, "fsync-after-each-write", 0, 1) < 0 ||
	    probe_sync_mode(dir, "O_SYNC", O_SYNC, 0) < 0)
		return 1;
	return 0;
}
