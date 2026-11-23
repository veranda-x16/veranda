#!/usr/bin/env python3
"""gate color: the colour map in a VRAM dump (tests/color.s).

usage: check_color.py <dir: dump.bin, console.txt> <out.png> [on|off|mode|menu|dlg]

on: layer 1 shows the bitmap, layer 0 the map at $1AC00 (128 x 64
entries, tile 0 at $1E800, eight 0 bytes); every card's attribute is the
colour tests/color.s's areas give it (clipped), every tile index 0; the
picture VERA composes (tools/vram2png.py's compose) has each card's paper
in its colour and the ink in palette entry 1 where the bitmap has ink.
on also: a menu and a dialog box were opened and closed over the colours
(timed): the map above is the areas' exactly, every tile 0.
off, mode: the display is the plain bitmap again (tools/check_vera.py's
first form), and the composed picture is slate ink on white (V74).
menu, dlg: the test ended with a menu (cards 12-25, rows 6-11) or the
default dialog box (cards 28-52, rows 24-36: the box and its shadow) open:
those cards are 0 (the normal paper), each tile holding the card's colour
and one cover (DECISIONS V33), the rest as the areas; the composed picture
is paper and ink only there, and in the areas' colours elsewhere.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'tools'))
import vram2png  # noqa: E402

COVER = {'menu': (12, 14, 6, 6), 'dlg': (28, 25, 24, 13)}
AREAS = [(2, 20, 3, 10, 2), (10, 30, 8, 20, 5), (70, 20, 50, 20, 6), (40, 1, 0, 60, 14),
         (90, 5, 5, 5, 7), (0, 80, 59, 1, 0), (44, 30, 30, 15, 7), (50, 6, 34, 4, 0)]
MAP, TILE0 = 0x1AC00, 0x1E800
failures = 0


def check(cond, what):
    global failures
    print(('ok    ' if cond else 'FAIL  ') + what)
    if not cond:
        failures += 1


def bmp4(path, v, want, l, t, r, b):
    """a 4 bpp BMP of the area: VERA's palette 0-15; ink 1, paper its card's colour"""
    import struct
    if not os.path.exists(path):
        check(False, '%s written' % path)
        return
    d = open(path, 'rb').read()
    w, h = r - l + 1, b - t + 1
    p = ((w + 1) // 2 + 3) & ~3
    size, _, off = struct.unpack_from('<IIi', d, 2)
    hs, bw, bh, planes, bpp, comp, isz = struct.unpack_from('<IiiHHII', d, 14)
    bad = []
    if (size, off, hs, bw, bh, bpp, comp, isz) != (len(d), 118, 40, w, h, 4, 0, p * h) or len(d) != 118 + p * h:
        bad.append('header: size %d of %d, offset %d, %dx%d, %d bpp' % (size, len(d), off, bw, bh, bpp))
    for i in range(16):
        rr, g, bb = vram2png.rgb(v, i)
        if tuple(d[54 + 4 * i:58 + 4 * i]) != (bb, g, rr, 0):
            bad.append('palette entry %d' % i)
    diff = 0
    if not bad:
        for row in range(h):
            y = b - row
            o = 118 + row * p
            for x in range(w):
                px = l + x
                nib = d[o + x // 2] >> (4 if x % 2 == 0 else 0) & 15
                ink = v[y * 80 + px // 8] & (0x80 >> (px % 8))
                diff += nib != (1 if ink else want[y // 8][px // 8])
        if diff:
            bad.append('%d pixels differ' % diff)
    try:
        from PIL import Image
        im = Image.open(path)
        im.load()
        if im.size != (w, h):
            bad.append('Pillow reads %dx%d' % im.size)
    except ImportError:
        pass
    check(not bad, 'COLOR.BMP: a 4 bpp BMP of %dx%d at %d,%d: %s' % (w, h, l, t, '; '.join(bad) or
          'every pixel its colour (ink 1, paper its card\'s), VERA\'s 16 palette entries'))


def main():
    d, png = sys.argv[1], sys.argv[2]
    kind = sys.argv[3] if len(sys.argv) > 3 else 'on'
    v = vram2png.section(os.path.join(d, 'dump.bin'))
    log = open(os.path.join(d, 'console.txt'), 'rb').read().decode('latin-1')
    check('COLOR DONE' in log, 'the test ran to its end')
    want = [[0] * 80 for _ in range(60)]
    for x, w, y, h, c in AREAS:
        for yy in range(y, min(y + h, 60)):
            for xx in range(x, min(x + w, 80)):
                want[yy][xx] = c
    pic = vram2png.compose(v)
    paper, ink = vram2png.rgb(v, 0), vram2png.rgb(v, 1)
    bits = lambda x, y: v[y * 80 + x // 8] & (0x80 >> (x % 8))   # noqa: E731
    if kind == 'on':
        lay = [v[131072 + 256 + 512 + 7 * i:][:7] for i in range(2)]
        check(v[131072] & 0x70 == 0x70 and lay[1][0] & 7 == 4 and lay[1][2] == 1 and lay[0][:3] == bytes([0x60, 0xD6, 0xF4]),
              'the layers: layer 1 the bitmap (1 bpp, $00000, 640 wide), layer 0 the map (1 bpp tiles, 128 x 64, '
              'map $1AC00, tile 0 at $1E800), both and the sprites on')
        got = [[v[MAP + 2 * (y * 128 + x) + 1] >> 4 for x in range(80)] for y in range(60)]
        bad = sum(1 for y in range(60) for x in range(80) if got[y][x] != want[y][x])
        idx = sum(1 for i in range(128 * 64) if v[MAP + 2 * i])
        low = sum(1 for y in range(60) for x in range(80) if v[MAP + 2 * (y * 128 + x) + 1] & 15)
        check(bad == 0 and idx == 0 and low == 0 and not any(v[TILE0:TILE0 + 8]),
              'the map: %d cards in %d colours as the areas give them (%d differ), every tile 0, tile 0 empty'
              % (sum(1 for r in want for c in r if c), len({c for r in want for c in r if c}), bad))
        bad = 0
        for y in range(480):
            for x in range(640):
                c = want[y // 8][x // 8]
                exp = ink if bits(x, y) else (vram2png.rgb(v, c) if c else paper)
                bad += pic[y][x] != exp
        check(bad == 0, 'the composed picture: every paper pixel in its card\'s colour, the ink in entry 1 (%d pixels '
              'differ)' % bad)
        m = re.search(r'EXPORT ([0-9A-F]{2})([0-9A-F]{2})', log)
        check(m and m.group(2) == '07', 'GetCardColor: card 45, 31 reads colour 7 (%s)' % (m and m.group(2)))
        check(m and m.group(1) == '00', 'ExportRect with the colours: no error')
        bmp4(os.path.join(d, 'COLOR.BMP'), v, want, 13, 7, 600, 470)
        t = dict((k, int(c, 16) / 8000) for k, c in re.findall(r'TIME (colouron|colour) ([0-9A-F]{8})', log))
        if len(t) == 2:
            print('      ColorRect, the whole screen (80 x 60 cards): %.2f ms; the first call, which shows the map '
                  '(16 KB cleared first): %.2f ms' % (t['colour'], t['colouron']))
        t = dict((k, int(c, 16) / 8000) for k, c in re.findall(r'TIME (menu|menuoff|dlg) ([0-9A-F]{8})', log))
        if len(t) == 3:
            print('      over the colours: RecoverAllMenus (a menu of 14 x 6 cards) %.2f ms; DoDlgBox to '
                  'RstrFrmDialogue\'s return (25 x 13 cards) %.2f ms (DoMenu: not timed here, see DECISIONS V33)'
                  % (t['menuoff'], t['dlg']))
    elif kind in COVER:
        cx, cw, cy, ch = COVER[kind]
        inside = lambda x, y: cx <= x < cx + cw and cy <= y < cy + ch   # noqa: E731
        bad = 0
        for y in range(60):
            for x in range(80):
                t, a = v[MAP + 2 * (y * 128 + x)], v[MAP + 2 * (y * 128 + x) + 1]
                exp = ((want[y][x] << 4) | 1, 0) if inside(x, y) else (0, want[y][x] << 4)
                bad += (t, a) != exp
        n = sum(1 for y in range(cy, cy + ch) for x in range(cx, cx + cw) if want[y][x])
        check(bad == 0 and n > 50, 'the %s open: its %d cards 0 (%d of them coloured, each colour kept in its tile, '
              'one cover), the rest as the areas (%d entries differ)' % (
                  ('menu', 'dialog box')[kind == 'dlg'], cw * ch, n, bad))
        bad = 0
        for y in range(480):
            for x in range(640):
                c = 0 if inside(x // 8, y // 8) else want[y // 8][x // 8]
                exp = ink if bits(x, y) else (vram2png.rgb(v, c) if c else paper)
                bad += pic[y][x] != exp
        check(bad == 0 and ink == (0x22, 0x22, 0x33) and paper == (255, 255, 255),
              'the composed picture: slate ink ($223, V74) on white inside it, the colours around it (%d pixels differ)' % bad)
    else:
        lay0 = v[131072 + 256 + 512:][:7]
        check(v[131072] & 0x70 == 0x50 and lay0[0] & 7 == 4 and lay0[2] == 1,
              'the map hidden (%s): layer 0 the bitmap again, layer 1 off' % (
                  'ColorRect $FF' if kind == 'off' else 'SetVideoMode'))
        bw = all(px in (paper, ink) for row in pic for px in row)
        check(bw, 'the composed picture: paper and ink only')
    from PIL import Image
    img = Image.new('RGB', (640, 480))
    p = img.load()
    for y in range(480):
        for x in range(640):
            p[x, y] = pic[y][x]
    img.save(png)
    sys.exit(1 if failures else 0)


if __name__ == '__main__':
    main()
