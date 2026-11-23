#!/usr/bin/env python3
"""gate edit: tests/edit_buftest.c's edits replayed on a Python string;
the program's files and log lines must agree.

usage: check_edit_buf.py <run folder>
"""
import os
import sys


class R:
    def __init__(self):
        self.x = 0x1D35

    def rnd(self):
        x = self.x
        x ^= (x << 7) & 0xFFFF
        x ^= x >> 9
        x ^= (x << 8) & 0xFFFF
        self.x = x
        return x

    def rnd32(self):
        h = self.rnd()
        return (h << 16) | self.rnd()


def main():
    run = sys.argv[1]
    r = R()
    t = bytearray()
    gs = 0
    for i in range(700):
        op = r.rnd() & 15
        ln = len(t)
        if op <= 6:
            k = r.rnd() % 3000 + 1 if op == 6 else r.rnd() % 200 + 1
            pos = r.rnd32() % (ln + 1)
            b = bytes(10 if (r.rnd() & 31) == 0 else ord('a') + (i + j) % 26 for j in range(k))
            t[pos:pos] = b
            gs = pos + k
        elif op <= 9:
            pos = r.rnd32() % (ln + 1)
            k = r.rnd() % 300
            k = min(k, ln - pos)
            del t[pos:pos + k]
            gs = pos
        elif op <= 11:
            gs = r.rnd32() % (ln + 1)
        else:
            t[gs:gs] = bytes([ord('A') + (op & 7)])
            gs += 1
    t = bytes(t)
    log = {}
    for line in open(os.path.join(run, 'console.txt'), errors='replace'):
        line = line.rstrip('\n')
        i = line.find('BUF ')
        if i < 0:
            continue
        line = line[i:]
        if line.startswith('BUF ROW0 '):
            log['ROW0'] = line[9:]
            continue
        p = line.split()
        if len(p) == 3:
            log[p[1]] = int(p[2], 16)
        else:
            log[p[1]] = None
    bad = []

    def want(k, v):
        if log.get(k) != v:
            bad.append('%s: %r, want %r' % (k, log.get(k), v))
    if 'DONE' not in log:
        bad.append('the program did not finish')
    for k in ('FULL', 'NO'):
        if k in log:
            bad.append('BUF %s' % k)
    want('LEN', len(t))
    want('GS', gs)
    want('LFS', t.count(b'\n'))
    p = 0
    for _ in range(10):
        q = t.find(b'\n', p)
        if q < 0:
            p = len(t)
            break
        p = q + 1
    want('LINE10', p)
    mid = len(t) // 2
    ms = t.rfind(b'\n', 0, mid) + 1
    want('MIDSTART', ms)
    want('MIDCOL', mid - ms)
    e = t.find(b'\n', ms)
    e = len(t) if e < 0 else e
    want('ATCOL5', min(ms + 5, e))
    f = t.find(b'xyz')
    want('FINDXYZ', f if f >= 0 else 0xFFFFFFFF)
    f = t.find(b'AB', 100)
    want('FINDAB', f if f >= 0 else 0xFFFFFFFF)
    e = t.find(b'\n')
    first = t[:e if e >= 0 else len(t)]
    want('ROW0', (first[:79].decode('latin-1') + ' ' * 79)[:79])
    want('ROW0NEXT', e + 1 if e >= 0 else len(t))
    want('ROW0MK0', 3 if len(first) >= 3 else 0xFFFF)
    want('LOADLF', t.count(b'\n'))
    files = {'BUF.OUT': t, 'BUF.CRLF': t.replace(b'\n', b'\r\n'), 'BUF.CR': t.replace(b'\n', b'\r'),
             'BUF.RT1': t, 'BUF.RT2': t}
    for n, v in files.items():
        p = os.path.join(run, n)
        d = open(p, 'rb').read() if os.path.exists(p) else None
        if d != v:
            bad.append('%s: %s' % (n, 'missing' if d is None else '%d bytes, want %d' % (len(d), len(v))))
    for b in bad:
        print('check_edit_buf:', b)
    if bad:
        sys.exit(1)
    print('ok    the gap buffer: %d bytes after 700 random edits (%d banks); the three line-end forms '
          'written and read back; lines, columns, find' % (len(t), log.get('BANKS', 0)))


if __name__ == '__main__':
    main()
