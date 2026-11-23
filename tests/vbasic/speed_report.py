#!/usr/bin/env python3
"""gate vb_speed: the plan's section 3.3 table from the cycle counts the
programs of tests/vbasic/speed logged ("T name cycles count"), against
its targets; BM1-BM8 against the X16 ROM's BASIC in the same emulator.

usage: speed_report.py VB_CONSOLE ROM_CONSOLE

8 MHz cycles. "net" removes the loop around the statement (the same FOR
loop timed empty). Prints the table and the misses with their factor.
The targets met since V107 are checks (CHECKED): a miss of one of them
exits 1, as does a missing number; the others are reported only.
MIT licence (LICENSE).
"""
import re
import sys

HZ = 8_000_000
# the targets that are checks (docs/DECISIONS.md V107): the rest are the
# plan's still out of reach, reported with their factor
CHECKED = {'for_empty', 'float_mul', 'goto'} | {'BM%d' % i for i in range(1, 9)} | \
    {'BM%di' % i for i in range(1, 8)}


def times(path):
    t = {}
    for line in open(path, 'rb').read().decode('latin-1').split('\n'):
        m = re.search(r'T (\w+) *(-?\d+)(?: +(\d+))?', line)
        if m:
            t[m.group(1)] = (int(m.group(2)), int(m.group(3) or 1))
    return t


def main(argv):
    vb, rom = times(argv[0]), times(argv[1])
    need = ['for_empty', 'int_assign', 'float_mul', 'sub_call', 'for_two_lines', 'goto', 'string', 'for_2000',
            'clock'] + ['BM%d' % i for i in range(1, 9)] + ['BM%di' % i for i in range(1, 9)]
    missing = [n for n in need if n not in vb] + ['BM%d' % i for i in range(1, 9) if 'BM%d' % i not in rom]
    if missing:
        print('FAIL  no time for: ' + ', '.join(missing))
        return 1
    clock = vb['clock'][0]
    misses = []
    failed = []

    def rate(name, loop=None):
        c, n = vb[name]
        c -= clock
        raw = n * HZ / c
        net = None
        if loop:
            lc, ln = vb[loop]
            per = (c - (lc - clock) * n / ln) / n
            net = HZ / per if per > 0 else 0
        return raw, net

    rows = [
        ('FOR i% = 1 TO 10000 : NEXT', 'for_empty', None, 25000, 'iterations/s'),
        ('a% = a% + b% * 2', 'int_assign', 'for_2000', 15000, '/s'),
        ('x = x * 1.0001 (float)', 'float_mul', 'for_2000', 2000, '/s'),
        ('SUB call with 2 arguments and return', 'sub_call', 'for_2000', 5000, '/s'),
        ('GOTO to a line number (cached)', 'goto', 'for_two_lines', 30000, '/s'),
        ('s$ = LEFT$(t$, 5) + "x"', 'string', 'for_2000', 5000, '/s'),
    ]
    print('%-40s %10s %10s %10s  %s' % ('the plan\'s section 3.3', 'raw', 'net', 'target', ''))
    for text, name, loop, target, unit in rows:
        raw, net = rate(name, loop)
        v = net if net is not None else raw
        verdict = 'ok' if v >= target else 'MISS x%.2f' % (target / v)
        if name in CHECKED:
            verdict += ' (checked)'
        if v < target:
            misses.append(text)
            if name in CHECKED:
                failed.append(text)
        print('%-40s %10.0f %10s %10d  %s %s' % (text, raw, '%.0f' % net if net else '-', target, unit, verdict))
    print()
    print('%-8s %12s %12s %12s %8s  %s' % ('', 'ROM BASIC', 'VeraBASIC', 'VB integer', 'float', 'integer'))
    for i in range(1, 9):
        r = rom['BM%d' % i][0] - 0
        f = vb['BM%d' % i][0] - clock
        n = vb['BM%di' % i][0] - clock
        fv = 'ok' if f <= r else 'MISS x%.2f' % (f / r)
        nv = 'ok' if r / n >= 3 else 'MISS x%.2f' % (3 / (r / n))
        if f > r:
            misses.append('BM%d (float)' % i)
            if 'BM%d' % i in CHECKED:
                failed.append('BM%d (float)' % i)
        if r / n < 3:
            misses.append('BM%d (integer, 3x)' % i)
            if 'BM%di' % i in CHECKED:
                failed.append('BM%d (integer, 3x)' % i)
        print('BM%d      %9.0f ms %9.0f ms %9.0f ms  %s / %.2fx  %s' % (
            i, r * 1000 / HZ, f * 1000 / HZ, n * 1000 / HZ, fv, r / n, nv))
    print()
    print('targets missed: %d%s' % (len(misses), (' (' + '; '.join(misses) + ')') if misses else ''))
    if failed:
        print('FAIL  checked targets missed: ' + '; '.join(failed))
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
