#!/usr/bin/env python3
# 伪终端回显器: 开一对 pty, 把从端路径交给 serial_loop 当串口设备,
# 自己当对端, 收到什么原样回什么 -- 等价于一根 TX-RX 短接的跳线。
# 用法: python3 serial_pty.py <serial_loop 程序> [count]

import os
import pty
import select
import subprocess
import sys


def main():
    program = sys.argv[1]
    count = sys.argv[2] if len(sys.argv) > 2 else "5"
    master, slave = pty.openpty()
    slave_name = os.ttyname(slave)
    proc = subprocess.Popen(
        [program, slave_name, "--count", count],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    while proc.poll() is None:
        ready, _, _ = select.select([master], [], [], 0.2)
        if master in ready:
            data = os.read(master, 256)
            if data:
                os.write(master, data)
    sys.stdout.write(proc.stdout.read())
    sys.exit(proc.returncode)


main()
