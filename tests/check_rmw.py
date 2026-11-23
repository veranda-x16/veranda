#!/usr/bin/env python3
"""gate disk, part 3 (tests/rmw.s): every Mxx.BIN written into the middle
of a file is the base with the pattern at its offset.

usage: check_rmw.py <dir> [--report]   (dir: the files, console.txt)
--report: list every case and go on after a failure (for finding which
patterns break)."""
import os
import re
import sys

KINDS = ['K_M', 'K_CH', 'K_M1', 'K_OPENW', 'K_MNEW', 'K_WSEEK', 'K_M2']


def cases():
    src = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'rmw.s')
    out = []
    for line in open(src):
        m = re.match(r'\s*CASE\s+(\w+),\s*(\d+),\s*(\d+),\s*(\d+)', line)
        if m:
            out.append((m.group(1), int(m.group(2)), int(m.group(3)), int(m.group(4))))
    return out


def base(n):
    return bytes(((i & 255) ^ (i >> 8) ^ 0x5A) & 255 for i in range(n))


def pattern(n):
    return bytes((j * 5 + 0x33) & 255 for j in range(n))


def expect(kind, b, off, ln):
    d = bytearray(base(b))
    if len(d) < off + ln:
        d += bytes(off + ln - len(d))
    d[off:off + ln] = pattern(ln)
    return bytes(d)


def find(folder, name):
    for f in os.listdir(folder):
        if f.upper() == name:
            return os.path.join(folder, f)
    return None


def main():
    a = sys.argv[1:]
    report = '--report' in a
    a = [x for x in a if x != '--report']
    folder = a[0]
    con = open(os.path.join(folder, 'console.txt'), errors='replace').read()
    if 'RMW DONE' not in con:
        print('FAIL  rmw: the test did not finish')
        return 1
    errs = re.findall(r'^E(.)([0-9A-F]{2})$', con, re.M)
    bad = 0
    for i, (kind, b, off, ln) in enumerate(cases()):
        name = 'M%02X.BIN' % i
        what = '%s %-7s base %4d, %3d bytes at %4d' % (name, kind, b, ln, off)
        p = find(folder, name)
        if p is None:
            print('FAIL  %s: not there' % what)
            bad += 1
            continue
        got = open(p, 'rb').read()
        want = expect(kind, b, off, ln)
        if got == want:
            if report:
                print('ok    %s' % what)
            continue
        bad += 1
        diff = [k for k in range(max(len(got), len(want)))
                if k >= len(got) or k >= len(want) or got[k] != want[k]]
        print('FAIL  %s: size %d (want %d); %d bytes differ, %d-%d' % (
            what, len(got), len(want), len(diff), diff[0], diff[-1]))
        if report:
            k = diff[0]
            print('      got  %s' % got[k:k + 16].hex(' '))
            print('      want %s' % want[k:k + 16].hex(' '))
    # the time of the largest overwrite: the T line after its C line
    t, c = {}, None
    for line in con.splitlines():
        if re.fullmatch(r'C[0-9A-F]{2}', line):
            c = int(line[1:], 16)
        elif re.fullmatch(r'T[0-9A-F]{8}', line) and c is not None:
            t[c] = int(line[1:], 16)
    big = max((ln, i) for i, (kind, b, off, ln) in enumerate(cases()) if i in t)
    print('      overwrite %d bytes in an \'m\' stream (open, seek, write, close): %.0f ms'
          % (big[0], t[big[1]] / 8000))
    if errs:
        print('      errors logged: %s' % ' '.join(s + e for s, e in errs))
    if bad:
        return 1
    print('ok    rmw: %d files written into their middle are right' % len(cases()))
    return 0


if __name__ == '__main__':
    sys.exit(main())
