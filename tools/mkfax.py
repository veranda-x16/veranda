#!/usr/bin/env python3
"""The CCITT run-length codes (ITU-T T.4, tables 2 and 3), for the PDF
writer's Group 4 encoder (kernel/p/fax.s; docs/DECISIONS.md V38).

usage: mkfax.py out.inc      the tables for ca65
       mkfax.py --test       encode random pages here (the same algorithm
                             as kernel/p/fax.s) and decode them with
                             libtiff (Pillow): every run length 0-2560

The include: for each colour (W white, B black) three tables of 104
entries, index n = a terminating code for a run of n (0-63), or n = 63 + k
the make-up code for 64 * k (k = 1-40, up to 2560): FaxWHi / FaxWLo, the
code left-aligned in 16 bits, and FaxWLen, its length in bits.
"""
import sys

WT = '''00110101 000111 0111 1000 1011 1100 1110 1111 10011 10100 00111 01000
001000 000011 110100 110101 101010 101011 0100111 0001100 0001000 0010111
0000011 0000100 0101000 0101011 0010011 0100100 0011000 00000010 00000011
00011010 00011011 00010010 00010011 00010100 00010101 00010110 00010111
00101000 00101001 00101010 00101011 00101100 00101101 00000100 00000101
00001010 00001011 01010010 01010011 01010100 01010101 00100100 00100101
01011000 01011001 01011010 01011011 01001010 01001011 00110010 00110011
00110100'''.split()
WM = '''11011 10010 010111 0110111 00110110 00110111 01100100 01100101 01101000
01100111 011001100 011001101 011010010 011010011 011010100 011010101
011010110 011010111 011011000 011011001 011011010 011011011 010011000
010011001 010011010 011000 010011011'''.split()
BT = '''0000110111 010 11 10 011 0011 0010 00011 000101 000100 0000100 0000101
0000111 00000100 00000111 000011000 0000010111 0000011000 0000001000
00001100111 00001101000 00001101100 00000110111 00000101000 00000010111
00000011000 000011001010 000011001011 000011001100 000011001101
000001101000 000001101001 000001101010 000001101011 000011010010
000011010011 000011010100 000011010101 000011010110 000011010111
000001101100 000001101101 000011011010 000011011011 000001010100
000001010101 000001010110 000001010111 000001100100 000001100101
000001010010 000001010011 000000100100 000000110111 000000111000
000000100111 000000101000 000001011000 000001011001 000000101011
000000101100 000001011010 000001100110 000001100111'''.split()
BM = '''0000001111 000011001000 000011001001 000001011011 000000110011
000000110100 000000110101 0000001101100 0000001101101 0000001001010
0000001001011 0000001001100 0000001001101 0000001110010 0000001110011
0000001110100 0000001110101 0000001110110 0000001110111 0000001010010
0000001010011 0000001010100 0000001010101 0000001011010 0000001011011
0000001100100 0000001100101'''.split()
XM = '''00000001000 00000001100 00000001101 000000010010 000000010011
000000010100 000000010101 000000010110 000000010111 000000011100
000000011101 000000011110 000000011111'''.split()       # 1792-2560, both

assert len(WT) == len(BT) == 64 and len(WM) == len(BM) == 27 and len(XM) == 13
WHITE = WT + WM + XM            # index: 0-63, 63 + k for 64 * k
BLACK = BT + BM + XM
MODES = {'P': '0001', 'H': '001', 0: '1', -1: '011', -2: '000011', -3: '0000011',
         1: '010', 2: '000010', 3: '0000010'}   # vertical: b1 - a1
EOFB = '000000000001' * 2


def span(n, black):
    """the codes of a run of n (n < 2624)"""
    t = BLACK if black else WHITE
    s = ''
    if n >= 64:
        s += t[63 + (n >> 6)]
        n &= 63
    return s + t[n]


def finddiff(row, x, w, colour):
    """the first position >= x whose pixel is not colour (w at most)"""
    while x < w and row[x] == colour:
        x += 1
    return x


def g4(rows, w):
    """T.6 coding of rows (lists of 0/1, 1 = black), as kernel/p/fax.s does
    it (libtiff's Fax3Encode2DRow); bytes, EOFB at the end"""
    bits = []
    ref = [0] * w
    for cur in rows:
        px = lambda r, x: r[x] if x < w else 0     # noqa: E731
        a0 = 0
        a1 = finddiff(cur, 0, w, 0)
        b1 = finddiff(ref, 0, w, 0)
        while True:
            b2 = finddiff(ref, b1, w, px(ref, b1)) if b1 < w else w
            if b2 >= a1:
                d = b1 - a1
                if -3 <= d <= 3:
                    bits.append(MODES[d])
                    a0 = a1
                else:
                    a2 = finddiff(cur, a1, w, px(cur, a1)) if a1 < w else w
                    bits.append(MODES['H'])
                    if a0 + a1 == 0 or px(cur, a0) == 0:
                        bits.append(span(a1 - a0, 0) + span(a2 - a1, 1))
                    else:
                        bits.append(span(a1 - a0, 1) + span(a2 - a1, 0))
                    a0 = a2
            else:
                bits.append(MODES['P'])
                a0 = b2
            if a0 >= w:
                break
            c = px(cur, a0)
            a1 = finddiff(cur, a0, w, c)
            b1 = finddiff(ref, a0, w, 1 - c)
            b1 = finddiff(ref, b1, w, c)
        ref = cur
    s = ''.join(bits) + EOFB
    s += '0' * (-len(s) % 8)
    return bytes(int(s[i:i + 8], 2) for i in range(0, len(s), 8))


def decode(data, w, h):
    """libtiff (Pillow): the rows, 1 = black"""
    import io
    import struct
    from PIL import Image
    tags = [(256, 4, w), (257, 4, h), (258, 3, 1), (259, 3, 4), (262, 3, 0), (273, 4, 0),
            (277, 3, 1), (278, 4, h), (279, 4, len(data))]
    off = 8 + 2 + 12 * len(tags) + 4             # the strip after the directory
    ifd = struct.pack('<H', len(tags))
    for t, typ, v in tags:
        v = off if t == 273 else v
        ifd += struct.pack('<HHI', t, typ, 1) + (struct.pack('<HH', v, 0) if typ == 3 else struct.pack('<I', v))
    tif = b'II*\0' + struct.pack('<I', 8) + ifd + b'\0\0\0\0' + data
    im = Image.open(io.BytesIO(tif))
    im.load()
    px = im.convert('L').tobytes()        # (WhiteIsZero: black is 0 here)
    return [[1 if px[y * w + x] == 0 else 0 for x in range(w)] for y in range(h)]


def test():
    import random
    random.seed(7)
    for w, h in ((2550, 40), (1240, 60), (77, 50), (8, 9)):
        rows = []
        for y in range(h):
            r, c, x = [], random.randint(0, 1), 0
            kind = y % 5
            while len(r) < w:
                n = random.choice([random.randint(0, 3), random.randint(0, 70), random.randint(60, 2600)]) \
                    if kind else random.randint(1, 4)
                r += [c] * n
                c ^= 1
            rows.append(r[:w] if y % 7 else (rows[-1] if rows else r[:w]))
        rows[h // 2] = [0] * w
        rows[h // 2 + 1] = [1] * w
        got = decode(g4(rows, w), w, h)
        if got != rows:
            bad = [y for y in range(h) if got[y] != rows[y]][0]
            raise SystemExit('mkfax: %d x %d: row %d differs' % (w, h, bad))
        print('mkfax: %d x %d decoded equal' % (w, h))
    # every code: runs 1-63 of both colours, then 64 k + k of each colour
    # (horizontal mode: a white row before each)
    w, rows = 2550, []
    for first in (0, 1):
        r = [first] * 0
        c = first
        for n in range(1, 64):
            r += [c] * n
            c ^= 1
        rows += [[0] * w, (r + [c] * w)[:w]]
    for k in range(1, 40):
        n = 64 * k + k % 64
        rows += [[0] * w, ([0] * n + [1] * w)[:w], [0] * w, ([1] * n + [0] * w)[:w]]
    if decode(g4(rows, w), w, len(rows)) != rows:
        raise SystemExit('mkfax: the run lengths 1-63 and 64 k + k differ')
    print('mkfax: every terminating and make-up code (to 2496) decoded equal')


def inc():
    out = ['; generated by tools/mkfax.py: the CCITT run-length codes (T.4), for kernel/p/fax.s',
           '; index n: a run of n (0-63); 63 + k: the make-up code for 64 * k (k 1-40)']
    for name, t in (('W', WHITE), ('B', BLACK)):
        codes = [int(c, 2) << (16 - len(c)) for c in t]
        out.append('Fax%sHi:' % name)
        out += ['\t.byte ' + ', '.join('$%02X' % (c >> 8) for c in codes[i:i + 16]) for i in range(0, 104, 16)]
        out.append('Fax%sLo:' % name)
        out += ['\t.byte ' + ', '.join('$%02X' % (c & 255) for c in codes[i:i + 16]) for i in range(0, 104, 16)]
        out.append('Fax%sLen:' % name)
        out += ['\t.byte ' + ', '.join('%d' % len(c) for c in t[i:i + 16]) for i in range(0, 104, 16)]
    return '\n'.join(out) + '\n'


if __name__ == '__main__':
    if sys.argv[1:] == ['--test']:
        test()
    elif len(sys.argv) == 2:
        open(sys.argv[1], 'w').write(inc())
    else:
        sys.exit(__doc__)
