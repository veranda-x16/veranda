#!/usr/bin/env python3
"""gate term_tcp: test hosts for Veranda Term's TCP sessions (DECISIONS
V112), on localhost, Python's socket module only. One connection each.

usage: term_tcp_server.py telnet|raw <port> <out dir>

telnet  IAC DO NAWS, DO TERMINAL-TYPE, WILL ECHO, WILL SGA, WILL BINARY,
        DO BINARY; the replies checked (WILL NAWS and SB NAWS 0 80 0 55,
        WILL TERMINAL-TYPE, DO ECHO, DO SGA, DO and WILL BINARY), then SB
        TERMINAL-TYPE SEND and IS "ANSI"; WILL ECHO again (already on:
        it must not be answered); an ANSI page with 0xFF bytes in it (as
        IAC IAC); 256 bytes 0-255 read back (sent by Term with 0xFF
        doubled: the raw bytes are checked too); a block of 0-255 sent
        (IAC IAC for 0xFF); an XMODEM download (CRC, 1 KB blocks, every
        0xFF doubled) of 20,000 bytes with runs of 0xFF; then it closes
        (Term: "closed by the host")
raw     a line, an echo of 256 bytes as they come, then an XMODEM download
        of the same kind with nothing doubled; it waits for Term to hang up
<out>/tcp.json: what happened; <out>/CAP.REF: the bytes Term should have
delivered (its capture); <out>/PAGE.REF: the ANSI page (telnet);
<out>/DLT.REF: the file sent by XMODEM; <out>/recv.bin: all received.
"""
import json
import os
import random
import select
import socket
import sys
import time

IAC, DONT, DO, WONT, WILL, SB, SE = 255, 254, 253, 252, 251, 250, 240
O_BIN, O_ECHO, O_SGA, O_TTYPE, O_NAWS = 0, 1, 3, 24, 31
SOH, STX, EOT, ACK, NAK, CAN = 1, 2, 4, 6, 21, 24
NAMES = {WILL: 'WILL', WONT: 'WONT', DO: 'DO', DONT: 'DONT'}


class Conn:
    def __init__(self, c, telnet):
        self.c, self.telnet = c, telnet
        self.raw = bytearray()          # everything received
        self.data = bytearray()         # after Telnet's commands
        self.events = []
        self.st, self.sb = 0, b''
        self.closed = False

    def pump(self, timeout):
        r, _, _ = select.select([self.c], [], [], timeout)
        if not r:
            return
        b = self.c.recv(4096)
        if not b:
            self.closed = True
            return
        self.raw += b
        if not self.telnet:
            self.data += b
            return
        for x in b:
            if self.st == 0:
                if x == IAC:
                    self.st = 1
                else:
                    self.data.append(x)
            elif self.st == 1:
                if x == IAC:
                    self.data.append(x)
                    self.st = 0
                elif x in NAMES:
                    self.cmd, self.st = x, 2
                elif x == SB:
                    self.sb, self.st = b'', 3
                else:
                    self.st = 0
            elif self.st == 2:
                self.events.append((NAMES[self.cmd], x))
                self.st = 0
            elif self.st == 3:
                if x == IAC:
                    self.st = 4
                else:
                    self.sb += bytes([x])
            else:
                if x == SE:
                    self.events.append(('SB',) + tuple(self.sb))
                    self.st = 0
                else:
                    self.sb += bytes([x])
                    self.st = 3

    def wait(self, pred, secs):
        end = time.time() + secs
        while not pred() and time.time() < end and not self.closed:
            self.pump(0.1)
        return pred()

    def send(self, b):
        self.c.sendall(bytes(b).replace(b'\xff', b'\xff\xff') if self.telnet else bytes(b))

    def take(self, n, secs):
        """n data bytes (Telnet's taken out)"""
        self.wait(lambda: len(self.data) >= n, secs)
        b, self.data = self.data[:n], self.data[n:]
        return bytes(b)

    def byte_of(self, want, secs):
        end = time.time() + secs
        while time.time() < end and not self.closed:
            while self.data:
                x = self.data.pop(0)
                if x in want:
                    return x
            self.pump(0.1)
        return None


def crc16(b):
    c = 0
    for x in b:
        c ^= x << 8
        for _ in range(8):
            c = ((c << 1) ^ 0x1021) if c & 0x8000 else c << 1
            c &= 0xFFFF
    return c


def xmodem(k, data, res):
    if k.byte_of((ord('C'),), 60) is None:
        res['xmodem'] = 'no C'
        return
    blocks = [data[i:i + 1024] for i in range(0, len(data), 1024)]
    naks = 0
    for i, b in enumerate(blocks):
        b = b + b'\x1a' * (1024 - len(b))
        n = (i + 1) & 255
        c = crc16(b)
        frame = bytes([STX, n, 255 - n]) + b + bytes([c >> 8, c & 255])
        for _ in range(10):
            k.send(frame)
            got = k.byte_of((ACK, NAK, CAN), 20)
            if got == ACK:
                break
            if got != NAK:
                res['xmodem'] = 'block %d: %r' % (i + 1, got)
                return
            naks += 1
        else:
            res['xmodem'] = 'block %d: ten NAKs' % (i + 1)
            return
    for _ in range(5):
        k.send([EOT])
        if k.byte_of((ACK, NAK), 10) == ACK:
            break
    res['xmodem'] = {'blocks': len(blocks), 'naks': naks, 'size': len(data)}


def file_data():
    rnd = random.Random(112)
    d = bytearray(rnd.getrandbits(8) for _ in range(20000))
    for i in range(0, 20000, 997):      # runs of 0xFF, one across a block's end
        d[i:i + 40] = b'\xff' * 40
    d[1000:1060] = b'\xff' * 60
    return bytes(d[:20000 - 1]) + b'\x42'


PAGE = (b'\x1b[0m\x1b[2J\x1b[H\x1b[1;33;44m Veranda TCP \x1b[0m Telnet test host\r\n'
        b'\r\n\x1b[1mBold\x1b[0m, \x1b[7mreverse\x1b[0m, \x1b[30;42mgreen paper\x1b[0m\r\n'
        b'0xFF as a CP437 glyph: [\xff] and two: [\xff\xff]\r\n'
        b'\x1b[10;5H\x1b[31;40mred on black\x1b[0m\r\n> ')


def telnet(k, res, out):
    k.c.sendall(bytes([IAC, DO, O_NAWS, IAC, DO, O_TTYPE, IAC, WILL, O_ECHO, IAC, WILL, O_SGA,
                       IAC, WILL, O_BIN, IAC, DO, O_BIN]))
    want = [('WILL', O_NAWS), ('SB', O_NAWS, 0, 80, 0, 55), ('WILL', O_TTYPE), ('DO', O_ECHO), ('DO', O_SGA),
            ('DO', O_BIN), ('WILL', O_BIN)]
    k.wait(lambda: all(w in k.events for w in want), 30)
    k.c.sendall(bytes([IAC, SB, O_TTYPE, 1, IAC, SE]))
    k.wait(lambda: ('SB', O_TTYPE, 0) + tuple(b'ANSI') in k.events, 30)
    n = len(k.events)
    k.c.sendall(bytes([IAC, WILL, O_ECHO]))     # (on already: no answer)
    k.wait(lambda: False, 1.5)
    res['events'] = [list(e) for e in k.events]
    res['again_answered'] = k.events[n:]
    res['telnet_ok'] = all(w in k.events for w in want) and ('SB', O_TTYPE, 0) + tuple(b'ANSI') in k.events
    res['ttype'] = [bytes(e[3:]).decode('latin-1') for e in k.events if e[:3] == ('SB', O_TTYPE, 0)]
    res['naws'] = [list(e[2:]) for e in k.events if e[:2] == ('SB', O_NAWS)]
    k.data.clear()
    cap = bytearray(PAGE)
    open(os.path.join(out, 'PAGE.REF'), 'wb').write(PAGE)
    k.send(PAGE)
    got = k.take(256, 60)
    res['up'] = got == bytes(range(256))
    res['up_len'] = len(got)
    if not res['up']:
        res['up_got'] = got.hex()
    # (Term doubled the 0xFF it sent: in the raw bytes, after the
    # negotiation's, 0xFF 0xFF then nothing else)
    res['up_raw_ff'] = bytes(k.raw).count(b'\xfe\xff\xff') == 1
    block = b'\r\nBLOCK ' + bytes(range(256)) + b' END\r\n'
    cap += block
    k.send(block)
    open(os.path.join(out, 'CAP.REF'), 'wb').write(cap)
    data = file_data()
    open(os.path.join(out, 'DLT.REF'), 'wb').write(data)
    xmodem(k, data, res)
    time.sleep(0.5)
    res['closed_by'] = 'host'


def raw(k, res, out):
    hello = b'raw echo: 256 bytes, then XMODEM\r\n'
    k.send(hello)
    got = bytearray()
    end = time.time() + 60
    while len(got) < 256 and time.time() < end and not k.closed:
        k.pump(0.1)
        if k.data:
            b = bytes(k.data[:256 - len(got)])
            del k.data[:len(b)]
            got += b
            k.send(b)
    res['up'] = bytes(got) == bytes(range(256))
    res['up_len'] = len(got)
    open(os.path.join(out, 'CAP.REF'), 'wb').write(hello + bytes(got))
    data = file_data()
    open(os.path.join(out, 'DLT.REF'), 'wb').write(data)
    xmodem(k, data, res)
    k.wait(lambda: False, 60)           # until Term hangs up
    res['closed_by'] = 'term' if k.closed else 'nobody'


def main():
    mode, port, out = sys.argv[1], int(sys.argv[2]), sys.argv[3]
    os.makedirs(out, exist_ok=True)
    s = socket.socket()
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(('127.0.0.1', port))
    s.listen(1)
    open(os.path.join(out, 'ready'), 'w').close()
    s.settimeout(240)
    res = {'mode': mode}
    try:
        c, _ = s.accept()
    except socket.timeout:
        res['error'] = 'no connection'
    else:
        res['connected'] = True
        k = Conn(c, mode == 'telnet')
        try:
            (telnet if mode == 'telnet' else raw)(k, res, out)
        finally:
            c.close()
            open(os.path.join(out, 'recv.bin'), 'wb').write(bytes(k.raw))
    json.dump(res, open(os.path.join(out, 'tcp.json'), 'w'), indent=1)


if __name__ == '__main__':
    main()
