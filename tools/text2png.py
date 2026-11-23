#!/usr/bin/env python3
"""The ROM's text screen in an x16emu dump (-dump V or BV): check it, draw it.

usage: text2png.py <dump.bin> [<out.png>] [--want TEXT]...

Checks that VERA shows the X16's text screen (DECISIONS V67: a black
screen after BASIC on a real X16): layer 1 on and a 1 bpp tile map (not
a bitmap), layer 0 off, a video output selected, a scale, and each TEXT
(uppercase PETSCII as BASIC prints it) somewhere in the map's visible
rows, its cells in a colour that differs from their background. Draws
the screen as VERA composes it (640 x 480; a background of index 0 shows
palette entry 0) into out.png. Exit status 1 with the reasons printed.
"""
import sys

VDUMP = 132878
VRAM, COMPOSER, PALETTE = 131072, 256, 512


def rgb(v, i):
    p = v[VRAM + COMPOSER:]
    gb, r = p[2 * i], p[2 * i + 1]
    return ((r & 15) * 17, (gb >> 4) * 17, (gb & 15) * 17)


def screen_code(ch):
    o = ord(ch)
    if 'A' <= ch <= 'Z':
        return o - 64
    if ch == '@':
        return 0
    return o                    # space, digits, punctuation: as ASCII


def main():
    a = sys.argv[1:]
    want = []
    while '--want' in a:
        i = a.index('--want')
        want.append(a[i + 1])
        del a[i:i + 2]
    if not a:
        sys.exit(__doc__)
    d = open(a[0], 'rb').read()
    v = d[len(d) - VDUMP:]
    c = v[VRAM:VRAM + COMPOSER]
    l1 = v[VRAM + COMPOSER + PALETTE + 7:][:7]
    video, hs, vs = c[0], c[1], c[2]
    bad = []
    if not video & 0x20:
        bad.append('DC_VIDEO $%02X: layer 1 (the text) is off' % video)
    if video & 0x10:
        bad.append('DC_VIDEO $%02X: layer 0 is on' % video)
    if not video & 0x03:
        bad.append('DC_VIDEO $%02X: no video output' % video)
    if l1[0] & 0x07 or l1[0] & 0x08:
        bad.append('layer 1 CONFIG $%02X: want a 1 bpp, 16-colour tile map' % l1[0])
    if not hs or not vs:
        bad.append('scale $%02X/$%02X' % (hs, vs))
    mapw = 32 << ((l1[0] >> 4) & 3)
    maph = 32 << ((l1[0] >> 6) & 3)
    mbase = l1[1] << 9
    tbase = (l1[2] >> 2) << 11
    tw = 16 if l1[2] & 1 else 8
    th = 16 if l1[2] & 2 else 8
    cols = max(1, 640 * hs // 128 // tw)
    rows = max(1, 480 * vs // 128 // th)

    def cell(x, y):
        o = (mbase + 2 * (y * mapw + x)) & 0x1FFFF
        return v[o], v[o + 1]

    def colours(attr):
        fg, bg = attr & 15, attr >> 4
        return rgb(v, fg), rgb(v, bg)          # (bg 0: entry 0 behind it)

    for t in want:
        codes = [screen_code(ch) for ch in t]
        hit = None
        for y in range(min(rows, maph)):
            line = [cell(x, y) for x in range(min(cols, mapw))]
            chars = [ch for ch, _ in line]
            for x in range(len(chars) - len(codes) + 1):
                if chars[x:x + len(codes)] == codes:
                    hit = (x, y, line[x:x + len(codes)])
                    break
            if hit:
                break
        if not hit:
            bad.append('"%s" is not in the text map\'s visible %d x %d cells' % (t, cols, rows))
            continue
        x, y, cells = hit
        for ch, attr in cells:
            if ch != 32:
                fg, bg = colours(attr)
                if fg == bg:
                    bad.append('"%s" (row %d): ink %s on paper %s, unreadable' % (t, y, fg, bg))
                break
    if len(a) > 1:
        from PIL import Image
        img = Image.new('RGB', (640, 480))
        px = img.load()
        for y in range(480):
            ly = y * vs // 128
            ty, ry = divmod(ly, th)
            for x in range(640):
                lx = x * hs // 128
                tx, rx = divmod(lx, tw)
                ch, attr = cell(tx % mapw, ty % maph)
                row = v[(tbase + ch * th * tw // 8 + ry * tw // 8 + rx // 8) & 0x1FFFF]
                fg, bg = colours(attr)
                px[x, y] = fg if row & (0x80 >> (rx % 8)) else bg
        img.save(a[1])
    for b in bad:
        print('text2png:', b)
    if bad:
        sys.exit(1)
    print('text2png: the text screen: layer 1 $%02X map $%05X tiles $%05X, %d x %d, DC_VIDEO $%02X'
          % (l1[0], mbase, tbase, cols, rows, video))


if __name__ == '__main__':
    main()
