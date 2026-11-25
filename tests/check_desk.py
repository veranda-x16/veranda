#!/usr/bin/env python3
"""gate desk: Paint, a desk accessory, Paint again (tests/desk_script.py,
tests/calc_script.py).

usage: check_desk.py <run dir: console.txt, PRE.RAW, POST.RAW, dump.bin>
       check_desk.py --calc [--dark] <dump.bin>   (the Calculator open; dark mode)

PRE.RAW and POST.RAW: both screens (foreground, then back screen; 480
rows of 80 bytes each) when Paint opened the accessory and when GetFile
returned to it.
"""
import os
import re
import sys

VDUMP = 132878
failures = 0


def check(cond, what):
    global failures
    print(('ok    ' if cond else 'FAIL  ') + what)
    if not cond:
        failures += 1


LIGHT = [0xFFF, 0x223, 0xDDE, 0xEEF, 0x9CF, 0xACE, 0xFD5, 0xF87, 0x8D9, 0xB9F, 0xFA5, 0x6CE, 0x36A, 0x8BE,
         0x7A8, 0xDAC]          # (sdk/lib/theme.c: Veranda's palette, light)
DARK = [0x334, 0xEEF, 0x223, 0x223, 0x357, 0x346, 0xA82, 0xA44, 0x385, 0x649, 0xA62, 0x278, 0x124, 0x247,
        0x343, 0x535]           # (and dark)


def calc(path, dark=False):
    """the Calculator open over Paint (Look 3 "Sunroom", V148; V186): its
    window in Veranda's colours (Paint's put aside with the rest, V33):
    the colour map shown (layer 0 the map, layer 1 the bitmap), palette
    entries 0-15 Veranda's, light or dark; in the window (296 x 304 at
    168, 88: card 21, card row 11) the title band's cards the theme's
    accent (3: Sunroom's mist), the display's the sidebar's tint (3), a
    digit's key the paper, an operator's the chrome (2), a function's the
    tint (3), C's orange (10), ='s the selection colour (5)"""
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'tools'))
    import vram2png
    v = vram2png.section(path)
    lay0 = v[131072 + 256 + 512:][:7]
    mbase = lay0[1] << 9
    check(v[131072] & 0x30 == 0x30 and not lay0[0] & 4, 'the Calculator open: the colour map shown (layer 0 the '
          'map, layer 1 the bitmap)')
    pal = [vram2png.rgb(v, i) for i in range(16)]
    want = [((c >> 8) * 17, (c >> 4 & 15) * 17, (c & 15) * 17) for c in (DARK if dark else LIGHT)]
    check(pal == want, 'palette entries 0-15 Veranda\'s, %s (%d differ)' % ('dark' if dark else 'light',
                                                                           sum(1 for a, b in zip(pal, want) if a != b)))

    def paper(cx, cy):
        return v[mbase + 2 * (cy * 128 + cx) + 1] >> 4
    got = [paper(25, 11), paper(23, 14), paper(34, 33), paper(52, 25), paper(22, 25), paper(40, 25), paper(52, 41),
           paper(52, 44)]
    check(got == [3, 3, 0, 2, 3, 10, 5, 5], 'its cards: the title band 3, the display 3, the key 7 0, / 2, sin 3, '
          'C 10, = 5 (both its rows) (%s)' % ' '.join(map(str, got)))
    sys.exit(1 if failures else 0)


def main():
    if sys.argv[1] == '--calc':
        calc(sys.argv[-1], '--dark' in sys.argv)
    d = sys.argv[1]
    con = open(os.path.join(d, 'console.txt'), 'rb').read().decode('latin-1')
    con = re.sub(r'\\X[0-9A-F]{2}', '', con).replace('\r', '')
    want = ['PAINT RUNNING', 'CALC RUNNING', 'CALC = 42', 'CALC = 84', 'CALC CLOSED', 'PAINT DESK BACK']
    p, ok = 0, True
    for m in want:
        p = con.find(m, p)
        if p < 0:
            ok = False
            break
    check(ok, 'the console in order: %s' % ', '.join(want))
    t = dict((k, int(c, 16) / 8000) for k, c in re.findall(r'TIME (open|back) ([0-9A-F]{8})', con))
    if len(t) == 2:
        print('      GetFile to the accessory\'s main (Paint put aside, the accessory loaded): %.0f ms; RstrAppl '
              'to GetFile\'s return in Paint: %.0f ms' % (t['open'], t['back']))
    pre = open(os.path.join(d, 'PRE.RAW'), 'rb').read()
    post = open(os.path.join(d, 'POST.RAW'), 'rb').read()
    n = sum(1 for a, b in zip(pre, post) if a != b)
    check(len(pre) == len(post) == 76800 and n == 0,
          'the screens when GetFile returned equal those when the accessory was opened (both, 76,800 bytes; '
          '%d differ)' % n)
    pm = open(os.path.join(d, 'PRE.MAP'), 'rb').read()
    qm = open(os.path.join(d, 'POST.MAP'), 'rb').read()
    check(pm == qm and pm.count(2) > 20, 'the colour map when GetFile returned equals the one before (%d cards in '
          'colour 2; %d differ)' % (pm.count(2), sum(1 for a, b in zip(pm, qm) if a != b)))
    raw = open(os.path.join(d, 'dump.bin'), 'rb').read()
    v = raw[len(raw) - VDUMP:]
    ink = sum(bin(x).count('1') for x in pre[:38400])
    check(ink > 3000, 'the picture before: %d ink pixels' % ink)
    # after: the second rectangle (420,300)-(560,420) in pattern 7 ($AA);
    # everything else as before (both screens)
    l, t, r, b = 420, 300, 560, 420
    bad_in = bad_out = 0
    for s in range(2):
        base = s * 0x9600
        for y in range(480):
            for x in range(640):
                now = v[base + y * 80 + x // 8] >> (7 - x % 8) & 1
                if l <= x <= r and t <= y <= b:
                    bad_in += now != (0xAA >> (7 - x % 8) & 1)
                elif x < 48 and y >= 448:       # (Paint's status: the pointer's place, V147)
                    continue
                else:
                    bad_out += now != (pre[s * 38400 + y * 80 + x // 8] >> (7 - x % 8) & 1)
    check(bad_in == 0, 'drawing after the accessory: the filled rectangle with the tool and pattern 7 chosen before '
          '(%d pixels differ)' % bad_in)
    check(bad_out == 0, 'the rest of both screens (but Paint\'s status) as before the accessory (%d pixels differ)' % bad_out)
    # the colour map at the end: as before, the second rectangle's cards in colour 2
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import check_paint
    now = bytes(check_paint.mapcol(v, x, y) for y in range(2, 60) for x in range(6, 80))
    exp = bytearray(pm)
    for cy in range(t // 8, b // 8 + 1):
        for cx in range(l // 8, r // 8 + 1):
            exp[(cy - 2) * 74 + cx - 6] = 2
    # the column's colour swatches (V147: tiles of their own in palette rows 4-11) back
    sw = check_paint.tilemode(v) and all(v[0x1AC00 + 2 * ((43 + 2 * (i // 3)) * 128 + 2 * (i % 3)) + 1] >> 4
                                         == 4 + i // 2 for i in range(16))
    check(v[131072 + 256 + 2:131072 + 256 + 4] == bytes([0x00, 0x08]),
          'the ink after the accessory: Paint\'s red again (palette entry 1; the accessory ran in black)')
    check(now == bytes(exp) and sw, 'the colour map at the end: as before, the new rectangle\'s cards in colour 2, '
          'the column\'s colour swatches (%d cards differ)' % sum(1 for a, c in zip(now, exp) if a != c))
    sys.exit(1 if failures else 0)


if __name__ == '__main__':
    main()
