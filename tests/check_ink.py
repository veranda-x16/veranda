#!/usr/bin/env python3
"""gate paint, the ink session (tests/ink_script.py; DECISIONS V33).

usage: check_ink.py <run dir: console.txt, dump.bin, SAVED.MAP, Inked.cvt,
                     Inked.bmp> <inkmenu dump> <inkdlg dump> <out dir>

- the menu and the dialog box over the colours: the cards under them are
  covered (Paint runs in tile mode since V147: their entries in palette
  row 15, the paper; their own row and a cover in the map row's shadow
  byte, V101; their tiles, the colours, kept), the composed display black
  on white there and in the picture's colours around it (the drawing
  area);
- the colours at the save (after the menu and the box were closed) are
  exactly the rectangles' (SAVED.MAP);
- Inked.cvt is version 3 with the ink colour 2 in record 0;
- at the end (Inked opened again after file/new) palette entry 1 is
  colour 2's red, the map is the one saved, and the composed display has
  the ink red; Inked.bmp is a 4 bpp BMP equal to the drawing area, its
  palette entry 1 that red.
PNGs: inkmenu.png, inkdlg.png, ink.png (the end), composed.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'tools'))
sys.path.insert(0, HERE)
import vram2png  # noqa: E402
import check_color  # noqa: E402
import check_paint  # noqa: E402

AREA = (60, 20, 630, 470)
RED = (200, 150, 450, 350)
MAP = 0x1AC00
WHITE, BLACK, X16RED = (255, 255, 255), (0x22, 0x22, 0x33), (0x8 * 17, 0, 0)   # (BLACK: Veranda's ink, slate since V74)
failures = 0


def check(cond, what):
    global failures
    print(('ok    ' if cond else 'FAIL  ') + what)
    if not cond:
        failures += 1


def expected():
    want = [[0] * 80 for _ in range(60)]
    for (l, t, r, b), c in ((AREA, 5), (RED, 2)):
        for y in range(t // 8, b // 8 + 1):
            for x in range(l // 8, r // 8 + 1):
                want[y][x] = c
    return want


def png(pic, path):
    from PIL import Image
    img = Image.new('RGB', (640, 480))
    p = img.load()
    for y in range(480):
        for x in range(640):
            p[x, y] = pic[y][x]
    img.save(path)


def covered(path, what, want, out):
    """the drawing area's cards under a menu or a dialog box (tile mode:
    tiles/check_tile.py's rules)"""
    v = vram2png.section(path)
    cov = set()
    bad = 0
    for y in range(2, 60):
        for x in range(6, 80):
            t, a = v[MAP + 2 * (y * 128 + x)], v[MAP + 2 * (y * 128 + x) + 1]
            sh = v[MAP + 256 * y + 160 + x]
            if a >> 4 == 15:
                cov.add((x, y))
                bad += t != want[y][x] or sh >> 4 != 0 or not sh & 15
            else:
                bad += a != 0 or t != want[y][x] or sh != 0
    n = sum(1 for x, y in cov if want[y][x])
    pic = vram2png.compose(v)
    bits = lambda x, y: v[y * 80 + x // 8] & (0x80 >> (x % 8))   # noqa: E731
    wrong = 0
    for y in range(16, 480):
        for x in range(48, 640):
            c = 0 if (x // 8, y // 8) in cov else want[y // 8][x // 8]
            exp = BLACK if bits(x, y) else (vram2png.rgb(v, c) if c else WHITE)
            wrong += pic[y][x] != exp
    check(bad == 0 and n > 20 and vram2png.rgb(v, 1) == BLACK,
          '%s open over the colours: %d cards of the drawing area under it covered (%d coloured, each colour kept '
          'in its tile), the rest as drawn (%d entries differ)' % (what, len(cov), n, bad))
    check(wrong == 0, '%s: the composed display the ink on white under it, the colours around it (%d pixels differ)'
          % (what, wrong))
    png(pic, out)


def main():
    run, mshot, dshot, out = sys.argv[1:5]
    con = open(os.path.join(run, 'console.txt'), 'rb').read().decode('latin-1')
    con = re.sub(r'\\X[0-9A-F]{2}', '', con).replace('\r', '')
    want = ['PAINT RUNNING', 'PAINT ABOUT', 'PAINT INK', 'PAINT SAVED', 'PAINT NEW', 'PAINT OPENED\nInked',
            'PAINT EXPORTED\nInked.bmp']
    p, ok = 0, True
    for m in want:
        p = con.find(m, p)
        if p < 0:
            ok = False
            break
    check(ok, 'the console in order: %s' % ', '.join(w.replace('\n', ' ') for w in want))
    exp = expected()
    covered(mshot, 'the options menu', exp, os.path.join(out, 'inkmenu.png'))
    covered(dshot, 'options/about\'s dialog box', exp, os.path.join(out, 'inkdlg.png'))
    saved = open(os.path.join(run, 'SAVED.MAP'), 'rb').read()
    area = bytes(exp[y][x] for y in range(2, 60) for x in range(6, 80))
    check(saved == area, 'the colours at the save, after the menu and the box: exactly the rectangles\' (%d cards '
          'differ)' % sum(1 for a, b in zip(saved, area) if a != b))
    cvt = open(os.path.join(run, 'Inked.cvt'), 'rb').read()
    recs = check_paint.records(cvt)
    check(recs[0] == b'VPNT\x03' + bytes([74, 16, 29, 2]) and len(recs) == 32,
          'Inked.cvt: version 3, the ink colour 2 in record 0 (%r), 32 records' % recs[0])
    v = vram2png.section(os.path.join(run, 'dump.bin'))
    check(vram2png.rgb(v, 1) == X16RED and vram2png.rgb(v, 0) == WHITE,
          'opened again after file/new: palette entry 1 red %r (colour 2\'s), the paper white' % (vram2png.rgb(v, 1),))
    now = bytes(check_paint.mapcol(v, x, y) for y in range(2, 60) for x in range(6, 80))
    check(now == area, 'and the colour map the one saved')
    pic = vram2png.compose(v)
    bits = lambda x, y: v[y * 80 + x // 8] & (0x80 >> (x % 8))   # noqa: E731
    red = sum(1 for y in range(16, 480) for x in range(48, 640) if bits(x, y))
    bad = sum(1 for y in range(16, 480) for x in range(48, 640)
              if pic[y][x] != (X16RED if bits(x, y) else vram2png.rgb(v, exp[y // 8][x // 8]) if exp[y // 8][x // 8]
                               else WHITE))
    check(red > 50000 and bad == 0, 'the composed display: %d ink pixels in red, the paper in its cards\' colours '
          '(%d pixels differ)' % (red, bad))
    png(pic, os.path.join(out, 'ink.png'))
    check_color.failures = 0
    check_color.bmp4(os.path.join(run, 'Inked.bmp'), v, exp, 48, 16, 639, 479)
    d = open(os.path.join(run, 'Inked.bmp'), 'rb').read()
    check(check_color.failures == 0 and tuple(d[58:62]) == (0, 0, X16RED[0], 0),
          'Inked.bmp: palette entry 1 the red ink (B, G, R: %r)' % (tuple(d[58:61]),))
    sys.exit(1 if failures else 0)


if __name__ == '__main__':
    main()
