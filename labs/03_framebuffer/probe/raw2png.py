"""把显存转储转成 PNG：python3 raw2png.py in.raw 宽 高 行宽字节 out.png [bpp]

bpp 默认 32，按 xRGB 小端解（内存里是 B G R x）；
bpp 为 16 时按 RGB565 小端解，5/6 位的分量用"高位复制到低位"放大回 8 位。
"""
import struct
import sys
import zlib

src, w, h, stride, dst = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4]), sys.argv[5]
bpp = int(sys.argv[6]) if len(sys.argv) > 6 else 32
data = open(src, "rb").read()
rows = bytearray()
for y in range(h):
    rows.append(0)  # PNG 每行前面一个过滤类型字节，0 表示不过滤
    line = data[y * stride : y * stride + w * (bpp // 8)]
    for x in range(w):
        if bpp == 16:
            (p,) = struct.unpack_from("<H", line, x * 2)
            r, g, b = (p >> 11) & 0x1F, (p >> 5) & 0x3F, p & 0x1F
            rows += bytes(((r << 3) | (r >> 2), (g << 2) | (g >> 4), (b << 3) | (b >> 2)))
        else:
            b, g, r, _ = line[x * 4 : x * 4 + 4]
            rows += bytes((r, g, b))


def chunk(tag, body):
    return struct.pack(">I", len(body)) + tag + body + struct.pack(">I", zlib.crc32(tag + body))


png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
png += chunk(b"IDAT", zlib.compress(bytes(rows), 9)) + chunk(b"IEND", b"")
open(dst, "wb").write(png)
print(f"{dst}: {w}x{h}, {len(png)} 字节")
