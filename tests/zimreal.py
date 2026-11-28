#!/usr/bin/env python3
"""A Zimodem 4.0.x in command mode as the firmware itself behaves, with a
Wi-Fi's latency (DECISIONS V213): the X16's UART reaches it through the
emulator's TCP back-end (-uart 9FE0 tcp:127.0.0.1:<port>), so a gate can
run a program against it in place of the emulator's own modem (which
answers at once and differs from the firmware where V211 broke on the
user's card).

    zimreal.py <folder>  (writes <folder>/zim.port; its log <folder>/zim.log)
        [--loop MS] [--write MS] [--connect MS] [--net MS] [--jitter MS]
        [--stallp P --stall MS [--stallall]] [--rxcap N] [--seed N]
        [--mlog FILE]   (the emulated modem's log= lines, for the checkers)

Modelled on Zimodem's source (zcommand.ino 4.0.x: readSerialStream,
doTransmitCommand, sendNextPacket, doHangupCommand; serout.ino), not on
its manual:
- the serial line is read by the firmware's loop: an XON (ATF3) sets
  packetXOn and calls sendNextPacket at once; a CR or an LF ends a
  command line (an XON inside it is taken out, not part of it);
- sendNextPacket: nothing when the 4 KB serial buffer has less room than
  a packet (packetXOn stays set: the next pass of the loop answers it);
  the connections in turn from the one after the last; a packet, or a
  connection gone (NO CARRIER <id>), which leaves packetXOn SET: the loop
  calls sendNextPacket again on its next pass, so another answer (a
  packet, or "[ id 0 0 ]") follows without an XON; nothing: an empty
  header with the first connection's id;
- ATT<n>: with no current connection, or one that is gone, ERROR at once
  and its n bytes are NOT read (they are taken as command lines); else
  readBytes(n) (1 s), the write to the connection (--write ms: a TLS
  record over Wi-Fi), then OK. While a command runs, nothing else is
  read (an XON waits);
- ATC"host:port", ATCS"host:port": the connection made (--connect ms; a
  plain TCP one), "CONNECT <id>", current; ATC<id> selects; ATH<id>
  deletes (current becomes the first connection if it was that one),
  ATH0 the current one, ATH all; a client's node stays after its NO
  CARRIER until ATH;
- the line paced at the rate (ATB), so the serial buffer fills as the
  firmware's does; the 4 KB buffer (TBUF) goes to the UART's 128 bytes
  only from the loop (serialOutDeque): while the loop is held (a command
  running, a stall) at most those 128 bytes go on, then the line stops,
  in the middle of a packet if one is there;
- (latency) the loop runs every --loop ms (the ESP32's Wi-Fi and TLS
  work between passes); what a server sends is there --net ms later
  (+ up to --jitter), in the pieces it came in; its close after its data;
- (--stallp, --stall) the loop held for --stall ms when a packet is read
  from a connection, that often (WiFiClientSecure waiting for a whole TLS
  record; --stallall: plain connections too, the Wi-Fi's own pauses):
  with an XON ahead (vrahead.c) the packet before it is in TBUF and stops
  half way on the line; (--rxcap) the serial receive buffer's size: more
  while the loop is held is lost.

MIT licence (see LICENSE)."""
import argparse
import os
import random
import socket
import sys
import time

XON, XOFF, CR, LF = 0x11, 0x13, 13, 10
TBUF = 4096


def crc8(data):
    crc = 0
    for b in data[:255] if len(data) < 256 else b'':
        for _ in range(8):
            s = (crc ^ b) & 1
            crc >>= 1
            if s:
                crc ^= 0x8C
            b >>= 1
    return crc


class Node:
    def __init__(self, cid, sock, host):
        self.id = cid
        self.sock = sock
        self.host = host
        self.rx = bytearray()           # available()
        self.tx = bytearray()           # written, not sent yet
        self.later = []                 # (when, bytes or None: the close)
        self.connected = True           # isConnected()
        self.was = True                 # wasConnected
        self.eof_read = False


class Zim:
    def __init__(self, ser, a, log, mlog):
        self.mlog = mlog
        self.ser = ser
        self.a = a
        self.log = log
        self.rnd = random.Random(a.seed)
        self.t0 = time.monotonic()
        self.sin = bytearray()          # from the X16, not read yet
        self.out = bytearray()          # TBUF: to the X16
        self.hw = bytearray()           # the UART's own 128 bytes: what goes on while the loop is held
        self.out_t = time.monotonic()
        self.baud = 115200
        self.echo = True
        self.verbose = True
        self.longr = True
        self.quiet = False
        self.flow = 0
        self.psize = 127
        self.conns = []
        self.current = None
        self.nextc = None
        self.xon = False
        self.next_id = 1
        self.nbuf = bytearray()
        self.busy_until = 0.0
        self.then = None                # what a command does when its time is up
        self.want = 0                   # ATT: bytes still to read
        self.want_t = 0.0
        self.tx = bytearray()
        self.next_loop = 0.0
        self.stats = {}

    def M(self, s):
        # (the emulated modem's log= lines, which the gates' checkers read)
        if self.mlog:
            self.mlog.write(s + '\n')
            self.mlog.flush()

    def L(self, s):
        if self.log:
            self.log.write('%9.3f %s\n' % (time.monotonic() - self.t0, s))
            self.log.flush()

    def count(self, k):
        self.stats[k] = self.stats.get(k, 0) + 1

    # ---- the serial line -------------------------------------------------
    def put(self, b):
        self.out += b

    def prints(self, s):
        self.put(s.encode('latin-1'))

    def room(self):
        return TBUF - 1 - len(self.out)

    def pace(self):
        now = time.monotonic()
        n = int((now - self.out_t) * self.baud / 10)
        if n <= 0:
            return
        self.out_t = now if n >= len(self.hw) else self.out_t + n * 10 / self.baud
        if self.hw:
            k = min(n, len(self.hw))
            try:
                self.ser.sendall(bytes(self.hw[:k]))
            except OSError:
                sys.exit(0)
            del self.hw[:k]

    def deque(self):
        # (serialOutDeque: TBUF to the UART, from the loop only)
        k = min(len(self.out), 128 - len(self.hw))
        if k > 0:
            self.hw += self.out[:k]
            del self.out[:k]

    def response(self, word, cid=0):
        if self.quiet:
            return
        if cid and self.longr:
            self.prints('\r\n%s %d\r\n' % (word, cid))
        else:
            self.prints('\r\n%s\r\n' % word)

    # ---- the connections -------------------------------------------------
    def service(self):
        now = time.monotonic()
        for c in self.conns:
            if c.sock is not None and not c.eof_read:
                while True:
                    try:
                        d = c.sock.recv(4096)
                    except BlockingIOError:
                        break
                    except OSError:
                        d = b''
                    lat = (self.a.net + self.rnd.random() * self.a.jitter) / 1000.0
                    last = c.later[-1][0] if c.later else 0
                    c.later.append((max(now + lat, last), d if d else None))
                    if not d:
                        c.eof_read = True
                        break
            while c.later and c.later[0][0] <= now:
                d = c.later.pop(0)[1]
                if d is None:
                    c.connected = False
                    self.L('closed %d (by the other side)' % c.id)
                    self.M('CLOSED %d (by the other side)' % c.id)
                else:
                    c.rx += d
            if c.tx and c.sock is not None:
                try:
                    n = c.sock.send(c.tx)
                    del c.tx[:n]
                except BlockingIOError:
                    pass
                except OSError:
                    c.tx.clear()
                    c.connected = False

    def delete(self, c):
        if c.sock is not None:
            try:
                c.sock.close()
            except OSError:
                pass
        self.conns.remove(c)

    def nxt(self, c):
        i = self.conns.index(c)
        return self.conns[i + 1] if i + 1 < len(self.conns) else None

    # ---- sendNextPacket (zcommand.ino) ----------------------------------
    def send_next(self):
        if self.room() < self.psize:
            if self.xon:
                self.count('deferred')
            return
        first = self.nextc
        if self.nextc not in self.conns:
            self.nextc = None
        if self.nextc is None or self.nxt(self.nextc) is None:
            first = None
            self.nextc = self.conns[0] if self.conns else None
        else:
            self.nextc = self.nxt(self.nextc)
        while self.nextc is not None and self.xon:
            c = self.nextc
            if c.rx:
                n = min(len(c.rx), self.psize)
                d = bytes(c.rx[:n])
                del c.rx[:n]
                self.xon = False
                self.count('packets')

                def emit():
                    self.prints('[ %d %d %d ]\r\n' % (c.id, n, crc8(d)))
                    self.put(d)
                    self.L('packet %d %d' % (c.id, n))
                if (c.secure or self.a.stallall) and self.rnd.random() < self.a.stallp:
                    # (WiFiClientSecure's read waiting for a whole TLS record:
                    # the loop held, TBUF not drained: a packet before this
                    # one stops half way on the line)
                    self.L('TLS read stall %g ms' % self.a.stall)
                    self.count('stalls')
                    self.wait(self.a.stall, emit)
                else:
                    emit()
                return
            elif not c.connected:
                if c.was:
                    c.was = False
                    self.response('NO CARRIER', c.id)
                    self.L('NO CARRIER %d (packetXOn left set)' % c.id)
                    self.M('NO CARRIER %d' % c.id)
                    return                      # (packetXOn still set)
            self.nextc = self.nxt(c)
            if self.nextc is first:
                break
        if self.xon:
            self.xon = False
            self.prints('[ %d 0 0 ]\r\n' % (self.conns[0].id if self.conns else 0))
            self.count('empties')

    # ---- commands ---------------------------------------------------------
    def wait(self, ms, then):
        self.busy_until = time.monotonic() + ms / 1000.0
        self.then = then

    def command(self, s):
        self.L('@ %s' % s)
        self.M('@%d %s' % (self.baud, s[s.upper().find('AT'):] if 'AT' in s.upper() else s))
        i = s.upper().find('AT')
        if i < 0:
            self.L('not a command')
            self.response('ERROR')
            return
        s = s[i + 2:]
        u = s.upper()
        i = 0

        def num():
            nonlocal i
            j = i
            while i < len(s) and s[i].isdigit():
                i += 1
            return int(s[j:i]) if i > j else None
        while i < len(s):
            c = u[i]
            i += 1
            if c == ' ':
                continue
            if c in 'EVXQF':
                v = num() or 0
                if c == 'E':
                    self.echo = v != 0
                elif c == 'V':
                    self.verbose = v != 0
                elif c == 'X':
                    self.longr = v != 0
                elif c == 'Q':
                    self.quiet = v != 0
                else:
                    self.flow = v
            elif c == '&':
                i += 1
                if i < len(s) and s[i] == '"':
                    j = s.find('"', i + 1)
                    i = len(s) if j < 0 else j + 1
                else:
                    num()
            elif c == 'S':
                r = num()
                if r is None or i >= len(s) or s[i] != '=':
                    self.response('ERROR')
                    return
                i += 1
                v = num()
                if r == 40 and v:
                    self.psize = v
            elif c == 'B':
                v = num()
                self.response('OK')
                self.pace_flush()
                self.baud = v or self.baud
                return
            elif c == 'I':
                num()
                self.prints('\r\nZIMODEM ESP32 FIRMWARE V4.0.2 (zimreal)\r\n')
            elif c == 'Z':
                pass
            elif c == 'C':
                sec = False
                while i < len(s) and s[i].isalpha():
                    sec = sec or s[i] in 'Ss'
                    i += 1
                if i < len(s) and s[i] == '"':
                    j = s.find('"', i + 1)
                    t = s[i + 1:j if j > 0 else len(s)]
                    self.sec = sec
                    if sec:
                        self.M('SECURE %s (plain TCP here: no TLS)' % t)
                    self.connect(t)
                    return
                v = num()
                k = [n for n in self.conns if n.id == v]
                if not k:
                    self.response('ERROR')
                    return
                self.current = k[0]
            elif c == 'T':
                v = num()
                if self.current is None or self.current not in self.conns or not self.current.connected:
                    self.L('ATT%s: no connection: ERROR, its bytes not read' % v)
                    self.count('att_error')
                    self.response('ERROR')
                    return
                if v:
                    self.want = v
                    self.want_t = time.monotonic() + 1.0
                    self.tx = bytearray()
                    return
            elif c == 'H':
                v = num()
                if v is None:
                    for n in list(self.conns):
                        self.delete(n)
                    self.current = self.nextc = None
                elif v == 0:
                    if self.current is None:
                        self.response('ERROR')
                        return
                    self.delete(self.current)
                    self.current = self.conns[0] if self.conns else None
                    self.nextc = self.current
                else:
                    k = [n for n in self.conns if n.id == v]
                    if not k:
                        self.response('ERROR')
                        return
                    n = k[0]
                    if self.current is n:
                        self.current = self.conns[0] if self.conns[0] is not n else (self.conns[1] if len(self.conns) > 1 else None)
                    if self.nextc is n:
                        self.nextc = self.conns[0] if self.conns[0] is not n else None
                    self.delete(n)
                    self.L('hung up %d' % v)
                    self.M('HANGUP %d' % v)
            else:
                self.L('unknown %s' % c)
                self.response('ERROR')
                return
        self.response('OK')

    def pace_flush(self):
        while self.out or self.hw:
            self.deque()
            self.pace()
            time.sleep(0.001)

    def connect(self, t):
        host, _, port = t.rpartition(':')
        try:
            so = socket.create_connection((host, int(port)), timeout=5)
            so.setblocking(False)
            so.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        except (OSError, ValueError) as e:
            self.L('connect %s: %s' % (t, e))
            self.M('ERROR connect %s: %s' % (t, e))
            self.wait(self.a.connect, lambda: self.prints('\r\nNO ANSWER\r\n'))
            return
        c = Node(self.next_id, so, t)
        c.secure = self.sec
        self.next_id += 1

        def done():
            self.conns.append(c)
            self.current = c
            self.L('CONNECT %d %s' % (c.id, t))
            self.M('CONNECT %d %s' % (c.id, t))
            self.response('CONNECT', c.id)
        self.wait(self.a.connect, done)

    def payload_done(self):
        c = self.current
        d = bytes(self.tx)
        self.want = 0
        self.L('ATT payload %d to %d: %r' % (len(d), c.id, d[:80]))

        def ok():
            if c in self.conns and c.connected:
                c.tx += d
                self.response('OK')
            else:
                self.response('ERROR')
        self.wait(self.a.write, ok)

    # ---- readSerialStream + serialIncoming + loop ------------------------
    def loop(self):
        now = time.monotonic()
        self.service()
        if self.then is not None:
            if now < self.busy_until:
                return
            f, self.then = self.then, None
            f()
        self.deque()
        if self.want:
            k = min(self.want, len(self.sin))
            self.tx += self.sin[:k]
            del self.sin[:k]
            self.want -= k
            if not self.want:
                self.payload_done()
                return
            if now > self.want_t:
                self.L('ATT: readBytes timed out')
                self.want = 0
                self.response('ERROR')
            return
        cr = False
        while self.sin and not cr:
            b = self.sin.pop(0)
            if b in (CR, LF):
                cr = True
                break
            if b == XON and self.flow in (2, 3):
                self.xon = True
                self.count('xons')
                if self.flow == 3:
                    self.send_next()
            elif b == XOFF:
                self.xon = False
            else:
                if self.echo:
                    self.put(bytes([b]))
                if b in (8, 127):
                    if self.nbuf:
                        self.nbuf.pop()
                else:
                    self.nbuf.append(b)
        if cr and self.nbuf:
            s = self.nbuf.decode('latin-1').strip()
            self.nbuf = bytearray()
            if s:
                self.command(s)
            return
        self.send_next()                # (loop: if(serial.isSerialOut()) sendNextPacket())


def main():
    p = argparse.ArgumentParser()
    p.add_argument('folder')
    p.add_argument('--loop', type=float, default=2.0)
    p.add_argument('--write', type=float, default=40.0)
    p.add_argument('--connect', type=float, default=400.0)
    p.add_argument('--net', type=float, default=60.0)
    p.add_argument('--jitter', type=float, default=80.0)
    p.add_argument('--stall', type=float, default=300.0)
    p.add_argument('--stallp', type=float, default=0.0, help='a TLS read held this often (0..1)')
    p.add_argument('--stallall', action='store_true', help='stalls on plain connections too (the loop held by the Wi-Fi)')
    p.add_argument('--seed', type=int, default=213)
    p.add_argument('--rxcap', type=int, default=0, help='the serial receive buffer (0: no limit)')
    p.add_argument('--mlog', help='the emulated modem\'s log= lines here')
    a = p.parse_args()
    ls = socket.socket()
    ls.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    ls.bind(('127.0.0.1', 0))
    ls.listen(1)
    log = open(os.path.join(a.folder, 'zim.log'), 'w')
    with open(os.path.join(a.folder, 'zim.port.tmp'), 'w') as f:
        f.write('%d\n' % ls.getsockname()[1])
    os.rename(os.path.join(a.folder, 'zim.port.tmp'), os.path.join(a.folder, 'zim.port'))
    ser, _ = ls.accept()
    ser.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    ser.setblocking(False)
    z = Zim(ser, a, log, open(a.mlog, 'w') if a.mlog else None)
    z.L('START loop %g write %g connect %g net %g+%g ms' % (a.loop, a.write, a.connect, a.net, a.jitter))
    try:
        while True:
            try:
                d = ser.recv(4096)
                if not d:
                    break
                if a.rxcap and len(z.sin) + len(d) > a.rxcap:
                    # (the ESP32's serial receive buffer full while the loop is held: lost)
                    k = max(0, a.rxcap - len(z.sin))
                    z.L('RX LOST %d bytes' % (len(d) - k))
                    z.count('rxlost')
                    d = d[:k]
                z.sin += d
            except BlockingIOError:
                pass
            z.pace()
            now = time.monotonic()
            if now >= z.next_loop:
                z.next_loop = now + a.loop * (0.5 + z.rnd.random()) / 1000.0
                z.loop()
            time.sleep(0.0005)
    except (ConnectionResetError, BrokenPipeError):
        pass
    z.L('END %r' % z.stats)


if __name__ == '__main__':
    main()
