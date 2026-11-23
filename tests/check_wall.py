#!/usr/bin/env python3
"""Gate wall (DECISIONS V78; the picture in tiles since V101): the
desktop's picture in an x16emu dump's VRAM (-dump V or RV).

usage: check_wall.py picture <dump> <wallpaper.cvt> <variant> [--skip x0,y0,x1,y1 ...]
       check_wall.py plain <dump> <colour> [--skip ...]
       check_wall.py notile <dump>
       check_wall.py diff <wallpaper.cvt> <picture.png>

picture: the shell's tile mode with the file's tiles, palette rows (0
light, 1 dark) and map on every card of the desktop (card rows 2 and
down, the cards left of the desktop's icons, x < 69) not in a --skip
rectangle (cards, inclusive), no ink on either screen (tests/check_tile.py
desk).
plain: those cards are the colour given (the 1 bpp colour map, not tile
mode), their bitmap 0 (pattern 0).
notile: tile mode off (layer 0 not 4 bpp tiles at $13000) and palette
entries 32-255 as the shell found them (VRAM_TILEPAL, $12C00: the kernel
put them back when tile mode ended).
diff: the wallpaper's light variant as VERA shows it against the picture
it was made from (both 640 x 480; card rows 2-59: 0-1 are under the menu
bar): the mean error of 8 x 8 card averages (a channel, 0-255) under 24;
the dark rows different from the light ones.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'tools'))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mkwall  # noqa: E402
import check_tile  # noqa: E402

MAP = 0x1AC00


def fail(m):
    print('FAIL ', m)
    sys.exit(1)


def cards(skip, rows=60):
    for cy in range(2, rows):
        for cx in range(69):
            if any(x0 <= cx <= x1 and y0 <= cy <= y1 for x0, y0, x1, y1 in skip):
                continue
            yield cx, cy


def plain(v, colour, skip):
    l0 = check_tile.layers(v)[0]
    tm = l0[2] == 0x98      # (V133: the plain desktop in tile mode: tile 16, entry 1 of row 2 the colour)
    if tm and check_tile.pal(v, 33) != check_tile.pal(v, colour):
        fail('the plain desktop\'s tile: palette entry 33 $%03X, not entry %d\'s $%03X' % (
            check_tile.pal(v, 33), colour, check_tile.pal(v, colour)))
    n = 0
    for cx, cy in cards(skip):
        a = MAP + 2 * (cy * 128 + cx)
        if tm and (v[a], v[a + 1]) != (16, 0x20):
            fail('card %d, %d: entry $%02X $%02X, not the plain tile (16, row 2)' % (cx, cy, v[a], v[a + 1]))
        if not tm and (v[a + 1] >> 4 != colour or v[a]):
            fail('card %d, %d: colour %d (tile %d), not %d' % (cx, cy, v[a + 1] >> 4, v[a], colour))
        for j in range(8):
            if v[(cy * 8 + j) * 80 + cx]:
                fail('card %d, %d: ink in a plain desktop' % (cx, cy))
        n += 1
    print('ok    %d cards of the desktop in colour %d%s, no ink' % (n, colour, ' (tile mode: the plain tile, V133)' if tm else ''))


def notile(v):
    l0 = check_tile.layers(v)[0]
    if l0[2] == 0x98 or l0[0] & 7 == 2:
        fail('layer 0 is in tile mode (config $%02X, tile base $%02X)' % (l0[0], l0[2]))
    for e in range(32, 256):
        k = check_tile.TILEPAL + 2 * (e - 32)
        if check_tile.pal(v, e) != v[k] | v[k + 1] << 8:
            fail('palette entry %d is $%03X, not $%03X as the shell found it' % (
                e, check_tile.pal(v, e), v[k] | v[k + 1] << 8))
    print('ok    tile mode off (layer 0 $%02X), palette entries 32-255 as the shell found them' % l0[0])


def diff(path, png):
    from PIL import Image
    data = mkwall.read(path)
    src = Image.open(png).convert('RGB')
    if src.size != (640, 480):
        src = src.resize((640, 480))
    b = src.tobytes()
    sp = [tuple(b[i:i + 3]) for i in range(0, len(b), 3)]
    rows = mkwall.render(data, 0)
    err, n = 0.0, 0
    for cy in range(2, 60):
        for cx in range(80):
            a = [0, 0, 0]
            b = [0, 0, 0]
            for j in range(8):
                for i in range(8):
                    x, y = cx * 8 + i, cy * 8 + j
                    for k in range(3):
                        a[k] += rows[y][x][k]
                        b[k] += sp[y * 640 + x][k]
            err += sum(abs(a[k] - b[k]) / 64 for k in range(3)) / 3
            n += 1
    err /= n
    if err >= 24:
        fail('the wallpaper is %.1f a channel from the picture (card averages)' % err)
    if mkwall.parts2(data, 0)[0] == mkwall.parts2(data, 1)[0]:
        fail('the dark rows are the light ones')
    print('ok    the light variant is %.1f a channel from the picture (8 x 8 averages); the dark rows differ' % err)


def main():
    a = sys.argv[1:]
    skip = check_tile.rects(a, '--skip')
    if len(a) == 4 and a[0] == 'picture':
        check_tile.desk(check_tile.section(a[1]), a[2], int(a[3]), skip, [], [])
    elif len(a) == 3 and a[0] == 'plain':
        plain(check_tile.section(a[1]), int(a[2]), skip)
    elif len(a) == 2 and a[0] == 'notile':
        notile(check_tile.section(a[1]))
    elif len(a) == 3 and a[0] == 'diff':
        diff(a[1], a[2])
    else:
        sys.exit(__doc__)


if __name__ == '__main__':
    main()
