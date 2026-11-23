#!/usr/bin/env python3
"""gate net: the test servers on localhost (tools/gate_net.sh, DECISIONS V98).

usage: net_servers.py <folder>            run them; <folder>/ready holds
                                          "<echo port> <file port>" once up
       net_servers.py --file <out>        write the file the file server sends
       net_servers.py --echo <out>        write the bytes the echo test sends

- the echo server: every connection's bytes sent back as they come, and
  kept in <folder>/echo<n>.bin (n = 1, 2 ... in the order they connect);
- the file server: FILE_LEN bytes of file_bytes(), then it closes; how
  long the sending took in <folder>/file.json.

Both run until killed (the gate kills them when the emulator ends).
"""
import json
import os
import socket
import sys
import threading
import time

FILE_LEN = 65536
ECHO_LEN = 16384
TRAPS = b"+++ATH0\r\nNO CARRIER 1\r\n\x11\x13[ 1 254 0 ]\r\n+++"


def xorshift(x, n):
    """tests/net_app.c's generator: 16-bit xorshift (7, 9, 8), x ^ x >> 8"""
    out = bytearray()
    for _ in range(n):
        x ^= (x << 7) & 0xFFFF
        x ^= x >> 9
        x ^= (x << 8) & 0xFFFF
        out.append((x ^ (x >> 8)) & 0xFF)
    return bytes(out)


def file_bytes():
    """tests/net_app.c's file_byte: page p (256 bytes) counts from p * 77
    in steps of 2p + 1 (odd: every byte value once a page)"""
    out = bytearray()
    for p in range(FILE_LEN // 256):
        v = (p * 77) & 0xFF
        for _ in range(256):
            out.append(v)
            v = (v + 2 * p + 1) & 0xFF
    return bytes(out)


def echo_bytes():
    head = bytes(range(256)) + TRAPS
    return head + xorshift(0x1234, ECHO_LEN - len(head))


def listener():
    s = socket.socket()
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(("127.0.0.1", 0))
    s.listen(4)
    return s


def main():
    if sys.argv[1] == "--file":
        open(sys.argv[2], "wb").write(file_bytes())
        return
    if sys.argv[1] == "--echo":
        open(sys.argv[2], "wb").write(echo_bytes())
        return
    d = sys.argv[1]
    es, fs = listener(), listener()
    count = [0]

    def echo_conn(c, n):
        with open(os.path.join(d, "echo%d.bin" % n), "wb") as f:
            while True:
                b = c.recv(4096)
                if not b:
                    break
                f.write(b)
                f.flush()
                c.sendall(b)
        c.close()

    def echo_loop():
        while True:
            c, _ = es.accept()
            count[0] += 1
            threading.Thread(target=echo_conn, args=(c, count[0]), daemon=True).start()

    def file_loop():
        data = file_bytes()
        while True:
            c, _ = fs.accept()
            t = time.time()
            c.sendall(data)
            c.shutdown(socket.SHUT_WR)
            json.dump({"sent": len(data), "seconds": time.time() - t}, open(os.path.join(d, "file.json"), "w"))
            time.sleep(0.5)
            c.close()

    threading.Thread(target=echo_loop, daemon=True).start()
    threading.Thread(target=file_loop, daemon=True).start()
    with open(os.path.join(d, "ready.tmp"), "w") as f:
        f.write("%d %d\n" % (es.getsockname()[1], fs.getsockname()[1]))
    os.rename(os.path.join(d, "ready.tmp"), os.path.join(d, "ready"))
    while True:
        time.sleep(1)


if __name__ == "__main__":
    main()
