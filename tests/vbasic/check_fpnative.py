#!/usr/bin/env python3
"""gate vb_core: what VeraBASIC Run does with floats itself, not through the
ROM's maths library (apps/vbasic/vbio.s toflt, toint, fcmp; negation is a
sign bit), is exactly what the library gives: integer to float (givayf +
movmf), float to integer (ayint), comparison (fcomp), on every integer and
20,000 floats, through tools/vbrom.py (the ROM image, run).

usage: check_fpnative.py ROM.bin                MIT licence (LICENSE)."""
import os
import random
import sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'tools'))
import vbrom  # noqa

m = vbrom.Maths(sys.argv[1])


def itof(n):
    if n == 0:
        return bytes(5)
    s = 0x80 if n < 0 else 0
    v = -n if n < 0 else n
    e = 0x90
    while not v & 0x8000:
        v <<= 1
        e -= 1
    return bytes([e, ((v >> 8) & 0x7F) | s, v & 0xFF, 0, 0])


def ftoi(b):
    e = b[0]
    if e == 0:
        return 0
    neg = b[1] & 0x80
    mant = ((b[1] | 0x80) << 24) | (b[2] << 16) | (b[3] << 8) | b[4]
    if e < 0x81:
        return -1 if neg else 0
    if e >= 0x90:
        if neg and e == 0x90 and mant == 0x80000000:
            return -32768
        raise ValueError('illq')
    sh = 32 - (e - 0x80)
    ip = mant >> sh
    frac = mant & ((1 << sh) - 1)
    if neg:
        return -ip - (1 if frac else 0)
    return ip


r = random.Random(1)
bad = 0
for n in range(-32768, 32768):
    if itof(n) != m.from_int(n):
        bad += 1
        print('itof', n, itof(n).hex(), m.from_int(n).hex())
        break
vals = []
for i in range(20000):
    e = r.choice([0, r.randint(0x70, 0x95), r.randint(0x7E, 0x92)])
    b = bytes([e, r.randrange(256), r.randrange(256), r.randrange(256), r.randrange(256)])
    if e == 0:
        b = bytes(5)
    vals.append(b)
vals += [bytes([0x90, 0x80, 0, 0, 0]), bytes([0x90, 0, 0, 0, 0]), bytes([0x90, 0x80, 0, 0, 1]),
         bytes([0x81, 0x80, 0, 0, 0]), bytes([0x80, 0x80, 0, 0, 0])]
for b in vals:
    try:
        want = m.to_int(b)
    except vbrom.MathError:
        want = 'err'
    try:
        got = ftoi(b)
    except ValueError:
        got = 'err'
    if want != got:
        bad += 1
        if bad < 10:
            print('ftoi', b.hex(), want, got)
bad_conv = bad


def fcmp(a, b):
    az, bz = a[0] == 0, b[0] == 0
    if az and bz:
        return 0
    an, bn = bool(a[1] & 0x80), bool(b[1] & 0x80)
    if az:
        return 1 if bn else -1
    if bz:
        return -1 if an else 1
    if an != bn:
        return -1 if an else 1
    ka = (a[0], a[1] & 0x7F, a[2], a[3], a[4])
    kb = (b[0], b[1] & 0x7F, b[2], b[3], b[4])
    c = (ka > kb) - (ka < kb)
    return -c if an else c


bad = 0
vals2 = vals[:3000] + [bytes([0, 0x80, 1, 2, 3]), bytes([0, 0, 0, 0, 5])]
for i in range(6000):
    a = r.choice(vals2)
    b = r.choice(vals2) if r.random() < 0.7 else bytes([a[0], a[1] ^ r.choice([0, 0x80]), a[2], a[3], a[4] ^ r.choice([0, 1])])
    if m.cmp(a, b) != fcmp(a, b):
        bad += 1
        if bad < 5:
            print('cmp', a.hex(), b.hex(), m.cmp(a, b), fcmp(a, b))
if bad or bad_conv:
    print('FAIL  the native conversions or comparison differ from the ROM: %d, %d' % (bad_conv, bad))
    sys.exit(1)
print('ok    integer to float on all 65,536 integers, float to integer and comparison on %d floats: as the ROM' % len(vals))
