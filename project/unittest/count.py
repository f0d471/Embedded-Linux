#!/usr/bin/env python3
# 独立计数脚本: 把一块显存转储按 宽x高x位深x行宽 解开, 数每种像素值各几个、
# 行尾填充里还剩几个 0xAA、几个关键坐标上是什么值。
#
#   用法: python3 count.py 转储文件 宽 高 位深 行宽
#
# 它按自己的理解算地址, 和被测的 disp_manager.c 不共享任何代码 --
# 被测程序算错行宽时, 这里不会跟着错。
import sys, collections

path, w, h, bpp, ll = sys.argv[1], *map(int, sys.argv[2:6])
d = open(path, 'rb').read()
B = bpp // 8
cnt = collections.Counter()
pad = 0
for y in range(h):
    row = d[y*ll:(y+1)*ll]
    pad += sum(1 for c in row[w*B:] if c == 0xAA)
    for x in range(w):
        cnt['%0*x' % (B*2, int.from_bytes(row[x*B:x*B+B], 'little'))] += 1

print('size', len(d), 'pad_AA', pad, 'pad_total', (ll - w*B) * h)
print(' '.join('%s:%d' % kv for kv in sorted(cnt.items())))

def px(x, y):
    return '%0*x' % (B*2, int.from_bytes(d[y*ll+x*B:y*ll+x*B+B], 'little'))

print('at', ' '.join('(%d,%d)=%s' % (x, y, px(x, y)) for x, y in
                     [(1,1), (4,3), (5,1), (6,1), (11,1),
                      (w-1,h-1), (w-1,5), (w-2,6), (w-3,5), (0,0)]))
