#!/usr/bin/env python3
"""gate term: a fake Wi-Fi modem with BBSes behind it (tools/gate_term.sh).

usage: term_bbs.py <port> <out dir>      serve one connection, then exit
       term_bbs.py --page <file>         write the ANSI test page (the
                                         script back-end's TERM.IN)

The emulator's UART (-uart <addr> tcp:localhost:<port>) connects at
start. This side behaves like a Zimodem: AT commands answered (no echo,
verbal results), "ATDT<host:port>" connects to one of these, by name:

  bbs.test     Telnet: WILL ECHO, WILL SGA, DO TTYPE, DO NAWS, the
               TERMINAL-TYPE asked; then the ANSI test page (page()),
               the prompt, and what is typed echoed; a line ends with
               "You typed: ..."
  speed.test   9600 bytes of numbered lines, then NO CARRIER
  files.test   Telnet BINARY both ways; XMODEM: file 1 (70,000 bytes,
               CRC, 1 KB blocks, block 3 sent once with a bad CRC), file
               2 (5,000 bytes, checksum, 128-byte blocks: the 'C's are
               ignored until a NAK comes); 0xFF doubled (IAC)
  time.test    a daytime line (NIST's format, RFC 867), then NO CARRIER

Everything sent is kept in <out>/sent.bin (Telnet commands left out: what
the terminal shows), everything received in <out>/recv.bin, and what
happened in <out>/bbs.json (the Telnet replies, the typed line, the XMODEM
results, the files in DL1.REF and DL2.REF).
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

TIME_LINE = b"\r\n63748 31-05-17 13:45:00 50 0 0 816.4 UTC(NIST) * \r\n"


def page():
    """the ANSI test page: 100 numbered lines (some coloured) scroll past
    the bottom, then sections drawn over the top rows"""
    E = '\033['
    out = [E + '0m' + E + '2J']
    for i in range(1, 101):
        if i % 4 == 0:
            c = i // 4 % 7 + 1
            out.append(E + '0mScroll %03d ' % i + E + '4%dm coloured background %d ' % (c, c) + E + '0m'
                       + E + '1;3%dm bright text ' % c + E + '0m end\r\n' % ())
        else:
            out.append(E + '0mScroll %03d the quick brown fox jumps over the lazy dog\r\n' % i)
    t = []
    t.append(E + '1;1H' + E + '1;37;44m' + E + '2K' + '   Veranda Term ANSI test page')
    t.append(E + '0m' + E + '2;1H' + E + '2K')
    t.append(E + '3;1H' + E + '0;40m' + E + '2K')
    for c in range(8):
        t.append(E + '3%dm colour %d ' % (c, c))
    t.append(E + '4;1H' + E + '2K')
    for c in range(8):
        t.append(E + '1;3%dm bright %d ' % (c, c))
    t.append(E + '0m' + E + '5;1H' + E + '2K')
    for c in range(1, 8):
        t.append(E + '0;4%dm back %d ' % (c, c))
    t.append(E + '0m' + E + '6;1H' + E + '2K' + 'plain ' + E + '1mbold' + E + '0m ' + E + '7mreverse' + E + '0m '
             + E + '1;7mboth' + E + '0m ' + E + '44;7mreverse on blue' + E + '0m')
    t.append(E + '7;1H' + E + '2K')
    # a DEC line drawing box (rows 8-12, columns 2-21) and a CP437 one
    t.append(E + '8;1H' + E + '2K' + ' \033(0lqqqqqqqqqqqqqqqqqqk\033(B')
    for r in (9, 10, 11):
        t.append(E + '%d;1H' % r + E + '2K' + ' \033(0x\033(B' + ' ' * 18 + '\033(0x\033(B')
    t.append(E + '12;1H' + E + '2K' + ' \033(0mqqqqqqqqvqqqqqqqqqj\033(B')
    t.append(E + '10;4HDEC graphics')
    t.append(E + '8;40H' + '\xc9' + '\xcd' * 18 + '\xbb')
    for r in (9, 10, 11):
        t.append(E + '%d;40H\xba' % r + E + '18C\xba')
    t.append(E + '12;40H\xc8' + '\xcd' * 18 + '\xbc')
    t.append(E + '10;42H' + E + '1;33;40mCP437 \xb0\xb1\xb2\xdb' + E + '0m')
    # cursor moves
    t.append(E + '13;1H' + E + '2K' + E + '14;1H' + E + '2K' + E + '15;1H' + E + '2K' + E + '16;1H' + E + '2K')
    t.append(E + '15;10HA' + E + '2AB' + E + '5CC' + E + '3DD' + E + 's' + E + '16;1HE' + E + 'uF'
             + E + '14;30H' + '\0337' + E + '16;60HG' + '\0338' + 'H')
    # erase in line, insert and delete lines
    t.append(E + '17;1H' + E + '2K' + 'erase test xxxxxxxxxxxx' + E + '17;12H' + E + 'K')
    t.append(E + '18;1H' + E + '2K' + 'line to delete' + E + '19;1H' + E + '2K' + 'line that stays'
             + E + '18;1H' + E + 'M')
    t.append(E + '20;1H' + E + '2K' + E + '21;1H' + E + '2K' + 'tab\tstop\tend' + E + '0m')
    t.append(E + '22;1H' + E + '2K' + 'Type something: ')
    return (''.join(out) + ''.join(t)).encode('latin-1')


class Line:
    def __init__(self, conn, out):
        self.c = conn
        self.sent = open(os.path.join(out, 'sent.bin'), 'wb')
        self.recv = open(os.path.join(out, 'recv.bin'), 'wb')
        self.buf = b''

    def send(self, data, show=True):
        self.c.sendall(data)
        if show:
            self.sent.write(data)
            self.sent.flush()

    def read(self, timeout):
        """bytes, or b'' after timeout seconds; None when closed"""
        if self.buf:
            b, self.buf = self.buf, b''
            return b
        r, _, _ = select.select([self.c], [], [], timeout)
        if not r:
            return b''
        b = self.c.recv(4096)
        if not b:
            return None
        self.recv.write(b)
        self.recv.flush()
        return b

    def unread(self, b):
        self.buf = b + self.buf


class Telnet:
    """the receiving side of Telnet: commands taken out, the data kept"""

    def __init__(self, line):
        self.l = line
        self.events = []
        self.state = 0
        self.sb = b''

    def data(self, raw):
        out = bytearray()
        for b in raw:
            if self.state == 0:
                if b == IAC:
                    self.state = 1
                else:
                    out.append(b)
            elif self.state == 1:
                if b == IAC:
                    out.append(b)
                    self.state = 0
                elif b in (WILL, WONT, DO, DONT):
                    self.cmd = b
                    self.state = 2
                elif b == SB:
                    self.sb = b''
                    self.state = 3
                else:
                    self.state = 0
            elif self.state == 2:
                self.events.append(({WILL: 'WILL', WONT: 'WONT', DO: 'DO', DONT: 'DONT'}[self.cmd], b))
                self.state = 0
            elif self.state == 3:
                if b == IAC:
                    self.state = 4
                else:
                    self.sb += bytes([b])
            elif self.state == 4:
                if b == SE:
                    self.events.append(('SB', list(self.sb)))
                    self.state = 0
                else:
                    self.sb += bytes([b])
                    self.state = 3
        return bytes(out)

    def wait(self, pred, timeout):
        end = time.time() + timeout
        while not pred(self.events) and time.time() < end:
            b = self.l.read(0.2)
            if b is None:
                return False
            if b:
                d = self.data(b)
                if d:
                    self.l.unread(d)
        return pred(self.events)


def has(ev, *want):
    return all(w in ev for w in want)


def bbs(l, res):
    tn = Telnet(l)
    l.send(bytes([IAC, WILL, O_ECHO, IAC, WILL, O_SGA, IAC, DO, O_TTYPE, IAC, DO, O_NAWS]), False)
    ok = tn.wait(lambda e: has(e, ('DO', O_ECHO), ('DO', O_SGA), ('WILL', O_TTYPE), ('WILL', O_NAWS))
                 and any(x[0] == 'SB' and x[1][:1] == [O_NAWS] for x in e), 30)
    l.send(bytes([IAC, SB, O_TTYPE, 1, IAC, SE]), False)
    ok = tn.wait(lambda e: any(x[0] == 'SB' and x[1][:1] == [O_TTYPE] for x in e), 30) and ok
    res['telnet'] = [list(e) if e[0] != 'SB' else ['SB', e[1]] for e in tn.events]
    res['telnet_ok'] = ok
    l.send(page())
    typed = b''
    end = time.time() + 120
    while time.time() < end:
        b = l.read(0.5)
        if b is None:
            break
        if not b:
            continue
        for c in tn.data(b):
            if c == 13:
                res['typed'] = typed.decode('latin-1')
                l.send(b'\r\nYou typed: ' + typed + b'\r\n> ')
                return 'stay'
            if c in (0, 10):
                continue
            typed += bytes([c])
            l.send(bytes([c]))
    return 'stay'


def speed(l, res):
    data = bytearray()
    n = 0
    while len(data) < 9600:
        s = ('%05d 0123456789 the quick brown fox jumps over the lazy dog ABCDEFGHIJKLMNOPQRSTUVWX\r\n' % n)
        data += s.encode()
        n += 1
    data = data[:9598] + b'\r\n'
    res['speed_bytes'] = len(data)
    l.send(bytes(data))
    return 'drop'


def xm_send(l, tn, data, big, crc, corrupt, res, key):
    """send data with XMODEM; the receiver started it ('C' or NAK)"""
    size = 1024 if big else 128
    blocks = [data[i:i + size] for i in range(0, len(data), size)]
    nak = 0
    for i, b in enumerate(blocks):
        b = b + b'\x1a' * (size - len(b))
        n = (i + 1) & 255
        if crc:
            c = 0
            for x in b:
                c ^= x << 8
                for _ in range(8):
                    c = ((c << 1) ^ 0x1021) if c & 0x8000 else c << 1
                    c &= 0xFFFF
            tail = bytes([c >> 8, c & 255])
        else:
            tail = bytes([sum(b) & 255])
        frame = bytes([STX if big else SOH, n, 255 - n]) + b + tail
        for attempt in range(10):
            f = frame
            if corrupt and i == 2 and attempt == 0:
                f = frame[:-1] + bytes([frame[-1] ^ 0x55])
            l.send(f.replace(b'\xff', b'\xff\xff'), False)
            got = wait_byte(l, tn, (ACK, NAK, CAN), 20)
            if got == ACK:
                break
            if got == NAK:
                nak += 1
                continue
            res[key] = 'no answer at block %d' % (i + 1)
            return False
        else:
            return False
    for attempt in range(5):
        l.send(bytes([EOT]), False)
        if wait_byte(l, tn, (ACK, NAK), 10) == ACK:
            break
    res[key] = {'blocks': len(blocks), 'naks': nak, 'size': len(data), 'crc': crc, 'big': big}
    return True


def wait_byte(l, tn, want, timeout):
    end = time.time() + timeout
    while time.time() < end:
        b = l.read(0.2)
        if b is None:
            return None
        if not b:
            continue
        d = tn.data(b)
        for i, c in enumerate(d):
            if c in want:
                rest = d[i + 1:]
                if rest:
                    l.unread(rest)
                return c
    return None


def files(l, res, out):
    tn = Telnet(l)
    l.send(bytes([IAC, WILL, O_BIN, IAC, DO, O_BIN, IAC, WILL, O_SGA]), False)
    tn.wait(lambda e: has(e, ('DO', O_BIN), ('WILL', O_BIN)), 30)
    res['files_telnet'] = [list(e) for e in tn.events]
    l.send(b'Files: ready to send.\r\n')
    rnd = random.Random(16)
    f1 = bytes(rnd.getrandbits(8) for _ in range(70000))
    f1 = f1[:-1] + b'\x42'
    f2 = bytes(rnd.getrandbits(8) for _ in range(5000))
    f2 = f2[:-1] + b'\x17'
    open(os.path.join(out, 'DL1.REF'), 'wb').write(f1)
    open(os.path.join(out, 'DL2.REF'), 'wb').write(f2)
    c = wait_byte(l, tn, (ord('C'), NAK), 60)
    if c is None:
        res['xm1'] = 'no start'
        return 'drop'
    xm_send(l, tn, f1, True, c == ord('C'), True, res, 'xm1')
    # file 2: the checksum (the 'C's ignored until a NAK)
    if wait_byte(l, tn, (NAK,), 60) != NAK:
        res['xm2'] = 'no NAK'
        return 'drop'
    xm_send(l, tn, f2, False, False, False, res, 'xm2')
    time.sleep(0.5)
    return 'drop'


def daytime(l, res):
    l.send(TIME_LINE)
    res['time'] = TIME_LINE.decode().strip()
    return 'drop'


def serve(conn, out):
    l = Line(conn, out)
    res = {'commands': []}
    cmd = b''
    try:
        while True:
            b = l.read(1.0)
            if b is None:
                break
            for c in b:
                if c in (10, 0):
                    continue
                if c != 13:
                    cmd += bytes([c])
                    continue
                line, cmd = cmd.decode('latin-1').strip(), b''
                if not line:
                    continue
                res['commands'].append(line)
                u = line.upper()
                if u.startswith('ATDT') or u.startswith('ATD'):
                    target = line[4:] if u.startswith('ATDT') else line[3:]
                    name = target.split(':')[0].strip('"').lower()
                    sess = {'bbs.test': lambda: bbs(l, res), 'speed.test': lambda: speed(l, res),
                            'files.test': lambda: files(l, res, out),
                            'time.test': lambda: daytime(l, res)}.get(name)
                    if target.endswith(':13'):          # any daytime service (time.nist.gov:13)
                        sess = lambda: daytime(l, res)
                    if not sess:
                        l.send(b'\r\nNO ANSWER\r\n')
                        continue
                    l.send(b'\r\nCONNECT 9600\r\n')
                    r = sess()
                    if r == 'drop':
                        l.send(b'\r\nNO CARRIER\r\n')
                    else:       # online until +++ and ATH
                        online(l)
                elif u == 'ATI':
                    l.send(b'\r\nZimodem (gate fake) 4.0.0\r\nOK\r\n')
                elif u == 'ATI2':
                    l.send(b'\r\n192.168.1.64\r\nOK\r\n')
                elif u.startswith('AT'):
                    l.send(b'\r\nOK\r\n')
                else:
                    l.send(b'\r\nERROR\r\n')
                save(res, out)
    finally:
        save(res, out)


def save(res, out):
    t = os.path.join(out, 'bbs.json.tmp')
    json.dump(res, open(t, 'w'), indent=1)
    os.replace(t, os.path.join(out, 'bbs.json'))


def online(l):
    """after a session: the line stays up until +++ (then ATH: back in
    command mode)"""
    while True:
        b = l.read(1.0)
        if b is None:
            return
        if b'+++' in b:
            l.send(b'\r\nOK\r\n')
            return


def main():
    if len(sys.argv) == 3 and sys.argv[1] == '--page':
        open(sys.argv[2], 'wb').write(b'\r\nOK\r\n\r\nCONNECT 9600\r\n' + page())
        return
    port, out = int(sys.argv[1]), sys.argv[2]
    os.makedirs(out, exist_ok=True)
    s = socket.socket()
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(('127.0.0.1', port))
    s.listen(1)
    s.settimeout(60)
    open(os.path.join(out, 'ready'), 'w').close()
    conn, _ = s.accept()
    conn.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    serve(conn, out)


if __name__ == '__main__':
    main()
