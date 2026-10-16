/* netinput 发送端: 把 input_replay.txt 同格式的文本事件行变成
 * 20 字节二进制记录经 TCP 发给 input 层的 netinput provider。
 *
 *   netinput_send <host> <port> <file> [--bad]
 *
 * --bad 把第一条记录的 magic 改坏后再发, 用来验证服务端丢弃坏客户端、
 * 服务本身不受影响的判据。文本格式与 replay 后端一致:
 *
 *   sec usec type code value        (# 开头与空行跳过)
 */

#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

#include "common.h"

#define NETINPUT_MAGIC 0x6e49

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

int main(int argc, char **argv)
{
	struct sockaddr_in addr;
	struct netinput_record rec;
	FILE *file;
	char line[256], extra;
	long long sec, usec;
	unsigned int type, code;
	int value, sent = 0, bad = 0, partial = 0, sock;
	size_t put_len;

	if (argc < 4) {
		fprintf(stderr, "usage: %s <host> <port> <file> [--bad|--partial]\n",
			argv[0]);
		return 2;
	}
	if (argc > 4 && strcmp(argv[4], "--bad") == 0)
		bad = 1;
	if (argc > 4 && strcmp(argv[4], "--partial") == 0)
		partial = 1;

	file = fopen(argv[3], "r");
	if (file == NULL) {
		fprintf(stderr, "cannot open %s\n", argv[3]);
		return 2;
	}

	sock = socket(AF_INET, SOCK_STREAM, 0);
	if (sock < 0) {
		fprintf(stderr, "socket: %s\n", strerror(errno));
		fclose(file);
		return 2;
	}
	memset(&addr, 0, sizeof(addr));
	addr.sin_family = AF_INET;
	addr.sin_port = htons((uint16_t)strtoul(argv[2], NULL, 10));
	if (inet_pton(AF_INET, argv[1], &addr.sin_addr) != 1) {
		fprintf(stderr, "bad host %s\n", argv[1]);
		return 2;
	}
	if (connect(sock, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
		fprintf(stderr, "connect: %s\n", strerror(errno));
		return 2;
	}

	while (fgets(line, sizeof(line), file) != NULL) {
		size_t off;
		ssize_t put;

		if (line[0] == '#' || line[0] == '\n')
			continue;
		if (sscanf(line, "%lld %lld %u %u %d %c",
			   &sec, &usec, &type, &code, &value, &extra) != 5) {
			fprintf(stderr, "malformed line: %s", line);
			return 2;
		}
		memset(&rec, 0, sizeof(rec));
		rec.magic = NETINPUT_MAGIC;
		if (bad && sent == 0)
			rec.magic = NETINPUT_MAGIC + 1;
		rec.type = (uint16_t)type;
		rec.code = (uint16_t)code;
		rec.value = value;
		rec.sec = (int32_t)sec;
		rec.usec = (int32_t)usec;
		put_len = sizeof(rec);
		if (partial && sent == 0)
			put_len = sizeof(rec) / 2;   /* 只发半条就断开 */
		for (off = 0; off < put_len; off += (size_t)put) {
			put = write(sock, (char *)&rec + off, put_len - off);
			if (put <= 0) {
				fprintf(stderr, "write: %s\n", strerror(errno));
				return 2;
			}
		}
		if (partial)
			break;
		sent++;
	}

	fclose(file);
	shutdown(sock, SHUT_WR);
	close(sock);
	printf("sent %d record%s\n", sent, sent == 1 ? "" : "s");
	return 0;
}
