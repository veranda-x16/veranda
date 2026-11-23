#!/usr/bin/env python3
"""gate desk: writes tests/calc_script.h, the session the Calculator's
test build plays (tests/calc_play.c), from the accessory's start.

usage: calc_script.py [out.h]      (default tests/calc_script.h)

The window (apps/calc/calc.c) at 640x480: 200 x 224 at (216, 128); a
key is 40 x 32, 48 and 40 apart, from (224, 184); the close box at the
title band's right (the SDK's vr_win, V148): 398-408, 131-141. Clicks: 1 2 + 3 0 = (42), keys * 2 Return (84), then
the close box. "/* shot NAME FRAME */" lines name frames for a
screenshot (CALC_STOP).
"""
import os
import sys

X0, Y0 = 216, 128
KEYS = '789/456*123-C0=+'
L = []
shots = []


def P(f, x, y, b, c=None):
    L.append('P(%d, %d, %d, %d),%s' % (f, x, y, b, '  /* %s */' % c if c else ''))


def K(f, ch, c=None):
    code = {'\r': '13'}.get(ch, "'%s'" % ch)
    L.append('K(%d, %s),%s' % (f, code, '  /* %s */' % c if c else ''))


def key_at(k):
    i = KEYS.index(k)
    return X0 + 8 + (i & 3) * 48 + 20, Y0 + 56 + (i >> 2) * 40 + 16


def click(f, x, y, c=None):
    P(f, x, y, 0, c)
    P(f + 1, x, y, 1)
    P(f + 3, x, y, 0)
    return f + 12


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), 'calc_script.h')
    f = 30
    for k in '12+30=':
        f = click(f, *key_at(k), c='key %s' % k)
    for k in '*2\r':
        K(f, k, 'typed' if k == '*' else None)
        f += 6
    shots.append(('calc', f + 20))
    f = click(f + 30, X0 + 200 - 13, Y0 + 8, c='the close box: RstrAppl')
    L.append('END(60000)')
    with open(out, 'w') as o:
        o.write('/* gate desk: the Calculator\'s session, written by tests/calc_script.py */\n')
        for name, fr in shots:
            o.write('/* shot %s %d */\n' % (name, fr))
        o.write('\n'.join(L) + '\n')


if __name__ == '__main__':
    main()
