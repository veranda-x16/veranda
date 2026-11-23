#!/usr/bin/env python3
"""The shell's colour chrome on the tile desktop (DECISIONS V102): its
tile art, baked once from shell/tiles.txt -> shell/gui.inc, shell/guiart.s.

usage: mkgui.py <tiles.txt> <gui.inc> <guiart.s> [--png <out.png>]

On the full-colour desktop (the kernel's tile mode, V101) the colour map
is VERA's layer 0 in 4 bpp tiles: a card can show any 8 x 8 picture in
one palette row, under the bitmap's ink. The shell keeps a pool of tiles
of its own at VRAM $17C00-$1ABFF (tiles 608-991, sprite slots 2-7, which
nothing uses while the shell runs) and puts there:
  - the colour icons of its own six tiles (folder, up, document, card,
    printer, trash): each 32 x 32 tile's ink glyph (drawn as before, in
    its rounded frame) with its regions filled, 4 x 4 cards in palette
    row 13; a card of one colour is solid tile c in row 13, the others
    are this file's tiles (equal ones once);
  - the title band's gradient: two tiles (the band's two card rows), 4 x 4
    Bayer dithered between the accent's three shades;
  - (made by the shell itself) each colour's four rounded corners of a
    tile, and the corners it composes over the picture.
Palette row 13 is the shell's (a wallpaper of version 3 uses rows 2-12,
indices 1-10): 1-10 the icons' colours (ROW13 below), 11-15 the chrome's
shades, which the shell also puts into indices 11-15 of every picture row,
so a card that shows the picture and a corner of the chrome at once
(a window's rounded corner over the picture) is one tile in the
picture's row: 11 the accent made lighter, 12 the accent, 13 darker, 14
chrome (the status bar, a window behind), 15 white. So the corner cards
of a tile that sits on the picture (the desktop's icons: card, printer,
trash) use only 0 and 11-15 (checked here).

gui.inc (for shell/gui.s, overlay 11) has
  GUI_NART            the tiles (they go to the pool's start, 608)
  GUI_GRAD            the first gradient tile (+1 the second)
  GUI_KIND0           the first of the six in tiles.h (T_FOLDER)
  GuiTables, a macro of
  guiIcon             the six tiles' cards (6 x 16, rows of 4): $80 + c a
                      solid colour c, else a pool tile
  guiMask             the rounded corners' insides (8 x 8 bytes, bit 7 the
                      left pixel): radius 4 (a tile's frame) top left, top
                      right, bottom left, bottom right; then radius 6 (a
                      window's, the dock's: shell_rframe's)
  guiCols             palette row 13's entries 1-10 ($0RGB words)
guiart.s has the tiles themselves (VERA's 4 bpp, high nibble the left
pixel), in two halves that live in the spare room of overlays 9 and 5
(nothing in the shell needs them but VRAM: no bank of their own), with
gui_artA and gui_artB, which put them into the pool.

MIT licence (see LICENSE).
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import vpack  # noqa: E402

SHELLS = ['folder', 'up', 'document', 'card', 'printer', 'trash']
# palette row 13, entries 1-10: the icons' colours
ROW13 = [0x0FD5, 0x0DA3, 0x047C, 0x08AD, 0x0E55, 0x0BBC, 0x0DDE, 0x059D, 0x0FFF, 0x05A6]
YELLOW, OCHRE, BLUE, LBLUE, RED, GREY, LGREY, MBLUE, WHITE10, GREEN = range(1, 11)
LIGHT, ACCENT, DARKER, CHROME, WHITE = range(11, 16)
# the shades' look in a preview (the Veranda theme's accent, light mode)
SHADES = [0x0CDE, 0x0ACE, 0x089B, 0x0DDE, 0x0FFF]
# a kind: (the plate's colour, [(x, y, colour)]: the enclosed region at x, y,
# the other enclosed regions' colour)
SPEC = {
    'folder': (YELLOW, [(6, 10, LBLUE), (10, 20, BLUE)], YELLOW),
    'up': (YELLOW, [(6, 10, LBLUE), (6, 20, BLUE)], YELLOW),
    'document': (LGREY, [(10, 12, WHITE), (20, 8, GREY)], WHITE),
    'card': (LIGHT, [(10, 9, MBLUE), (4, 7, WHITE), (5, 22, WHITE)], WHITE),
    'printer': (LIGHT, [(12, 7, RED), (6, 14, LGREY), (12, 20, RED), (11, 24, WHITE)], WHITE),
    'trash': (LIGHT, [(11, 13, GREY)], GREY),
}
DESK = ('card', 'printer', 'trash')     # on the picture: corners in 0, 11-15
PLATE = (2, 16)                          # a pixel of the plate (inside the frame)
# vr_tile's frame (radius 4) and shell_rframe's insets (radius 6)
FRAME4 = [0x1FFFFFF8, 0x60000006, 0x40000002, 0x80000001]
IN6 = [4, 3, 2, 1]
BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]


def frame_ink(x, y):
    f = FRAME4[y if y < 4 else 31 - y if y > 27 else 3]
    return f >> (31 - x) & 1


def regions(ink):
    """4-connected regions of the 32 x 32 pixels without ink: a map pixel ->
    region number"""
    reg = {}
    n = 0
    for sy in range(32):
        for sx in range(32):
            if ink[sy][sx] or (sx, sy) in reg:
                continue
            st = [(sx, sy)]
            reg[(sx, sy)] = n
            while st:
                x, y = st.pop()
                for a, b in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                    if 0 <= a < 32 and 0 <= b < 32 and not ink[b][a] and (a, b) not in reg:
                        reg[(a, b)] = n
                        st.append((a, b))
            n += 1
    return reg


def colour(name, rows):
    plate, seeds, rest = SPEC[name]
    ink = [[1 if rows[y][x] == '#' or frame_ink(x, y) else 0 for x in range(32)] for y in range(32)]
    reg = regions(ink)
    want = {reg[(0, 0)]: 0, reg[(31, 0)]: 0, reg[(0, 31)]: 0, reg[(31, 31)]: 0, reg[PLATE]: plate}
    for x, y, c in seeds:
        if (x, y) not in reg:
            raise ValueError('%s: the seed %d, %d is ink' % (name, x, y))
        r = reg[(x, y)]
        if r in want:
            raise ValueError('%s: the seed %d, %d is in a region already coloured' % (name, x, y))
        want[r] = c
    out = [[0] * 32 for _ in range(32)]
    for (x, y), r in reg.items():
        out[y][x] = want.get(r, rest)
    # under the ink: the colour of a neighbour (the tile shows none of it,
    # but equal cards merge better)
    return out, ink


def pack(px):
    return bytes(px[2 * k] << 4 | px[2 * k + 1] for k in range(32))


def gradient():
    """the title band's two card rows: the shades 11 -> 12 -> 13 over 16
    lines, a 4 x 4 Bayer dither (the same every 4 pixels: one tile a row)"""
    t = []
    for cy in range(2):
        px = []
        for y in range(8):
            yy = cy * 8 + y
            f = 2.0 * yy / 15
            for x in range(8):
                k = int(f) + (1 if f - int(f) > (BAYER[yy & 3][x & 3] + 0.5) / 16 else 0)
                px.append(LIGHT + min(2, k))
        t.append(pack(px))
    return t


def masks():
    out = []
    # radius 4: inside = not the frame's outside pixels
    outside4 = {(x, y) for y in range(4) for x in range(4) if not any(frame_ink(i, y) for i in range(0, x + 1))}
    for ins in (outside4, {(x, y) for y in range(4) for x in range(IN6[y])}):
        for k in range(4):          # top left, top right, bottom left, bottom right
            m = []
            for y in range(8):
                v = 0
                for x in range(8):
                    xx = x if k in (0, 2) else 7 - x
                    yy = y if k in (0, 1) else 7 - y
                    if (xx, yy) not in ins:
                        v |= 0x80 >> x
                m.append(v)
            out.append(bytes(m))
    return out


def build(src):
    tiles = {}
    nclass = 0
    for name, kv, rows in vpack.read_tiles(src):
        if kv['kind'] == 'tile' and kv.get('for') in SHELLS:
            tiles[kv['for']] = rows
        elif kv['kind'] == 'tile' and kv.get('for', '').startswith('class '):
            nclass += 1
    art, index = [], {}
    icons = []
    pics = {}
    for k in SHELLS:
        px, ink = colour(k, tiles[k])
        pics[k] = (px, ink)
        cards = []
        for cy in range(4):
            for cx in range(4):
                c = [px[cy * 8 + y][cx * 8 + x] for y in range(8) for x in range(8)]
                corner = cx in (0, 3) and cy in (0, 3)
                if k in DESK and corner and set(c) - {0, 11, 12, 13, 14, 15}:
                    raise ValueError('%s: corner card %d, %d uses %s (on the picture: 0, 11-15 only)' % (
                        k, cx, cy, sorted(set(c) - {0, 11, 12, 13, 14, 15})))
                if len(set(c)) == 1 and not (k in DESK and corner):
                    cards.append(0x80 | c[0])
                    continue
                d = pack(c)
                if d not in index:
                    index[d] = len(art)
                    art.append(d)
                cards.append(index[d])
        icons.append(cards)
    grad = len(art)
    art += gradient()
    return art, icons, grad, masks(), pics, nclass


def rows(b, per=16):
    return ['\t.byte ' + ', '.join('$%02X' % x for x in b[i:i + per]) for i in range(0, len(b), per)]


def inc(art, icons, grad, mk, nclass):
    o = ['; generated by tools/mkgui.py from shell/tiles.txt: the shell\'s colour',
         '; chrome on the tile desktop (DECISIONS V102); for shell/gui.s',
         'GUI_NART = %d' % len(art), 'GUI_GRAD = %d' % grad, 'GUI_KIND0 = %d' % nclass,
         '.macro GuiTables', 'guiIcon:']
    for k, c in zip(SHELLS, icons):
        o += rows(bytes(c))
        o[-1] += '\t; ' + k
    o.append('guiMask:')
    for m in mk:
        o += rows(m)
    o.append('guiCols:')
    o.append('\t.word ' + ', '.join('$%03X' % c for c in ROW13))
    o.append('.endmacro')
    return '\n'.join(o) + '\n'


SPLIT = (9, 5)          # the overlays that hold the tiles' two halves


def art_s(art):
    h = (len(art) + 1) // 2
    o = ['; generated by tools/mkgui.py from shell/tiles.txt: the shell\'s colour',
         '; chrome\'s tiles (DECISIONS V102), in two halves in the spare room of',
         '; overlays %d and %d; gui_artA and gui_artB put them into the pool' % SPLIT,
         '; (VRAM $17C00: tile 608 on)',
         '.include "veranda.inc"', '.include "x16hw.inc"', '.export _gui_artA, _gui_artB', '.importzp ptr1', '']
    for n, (ov, part, first) in enumerate(((SPLIT[0], art[:h], 0), (SPLIT[1], art[h:], h))):
        at = 0x17C00 + 32 * first
        size = 32 * len(part)
        lab = 'A' if n == 0 else 'B'
        o += ['.segment "OVERLAY%d"' % ov, '_gui_art%s:' % lab,
              '\tstz VERA_CTRL', '\tlda #$%02X' % (at & 255), '\tsta VERA_ADDR_L', '\tlda #$%02X' % (at >> 8 & 255),
              '\tsta VERA_ADDR_M', '\tlda #$%02X | VERA_INC1' % (at >> 16), '\tsta VERA_ADDR_H',
              '\tlda #<art%s' % lab, '\tsta ptr1', '\tlda #>art%s' % lab, '\tsta ptr1+1',
              '\tldy #0', '\tldx #%d' % (size >> 8), '@p:\tlda (ptr1),y', '\tsta VERA_DATA0', '\tiny', '\tbne @p',
              '\tinc ptr1+1', '\tdex', '\tbne @p', '@t:\tcpy #%d' % (size & 255), '\tbeq @r',
              '\tlda (ptr1),y', '\tsta VERA_DATA0', '\tiny', '\tbra @t', '@r:\trts']
        o += ['.segment "OVL%dRO"' % ov, 'art%s:' % lab]
        for t in part:
            o += rows(t)
        o.append('')
    return '\n'.join(x for x in o if x != '') + '\n'


def png(pics, art, grad, out):
    from PIL import Image
    pal = [0x0FFF] + ROW13 + SHADES

    def rgb(c):
        return ((c >> 8 & 15) * 17, (c >> 4 & 15) * 17, (c & 15) * 17)
    im = Image.new('RGB', (len(pics) * 40 + 40, 40), (90, 120, 170))
    for i, k in enumerate(SHELLS):
        px, ink = pics[k]
        for y in range(32):
            for x in range(32):
                im.putpixel((i * 40 + 4 + x, 4 + y), (34, 34, 51) if ink[y][x] else rgb(pal[px[y][x]]))
    for cy in range(2):
        t = art[grad + cy]
        for y in range(8):
            for x in range(32):
                b = t[y * 4 + (x & 7) // 2]
                im.putpixel((len(pics) * 40 + 4 + x, 4 + cy * 8 + y), rgb(pal[b & 15 if x & 1 else b >> 4]))
    im.resize((im.width * 3, im.height * 3), Image.NEAREST).save(out)


def main():
    a = sys.argv[1:]
    if len(a) not in (3, 5) or (len(a) == 5 and a[3] != '--png'):
        sys.exit(__doc__)
    try:
        art, icons, grad, mk, pics, nclass = build(a[0])
    except (vpack.PackError, OSError, ValueError, KeyError) as e:
        sys.exit('mkgui: %s' % e)
    if len(art) // 2 * 32 < 256:
        sys.exit('mkgui: %d tiles: gui_artA and gui_artB take 8 each at least' % len(art))
    open(a[1], 'w').write(inc(art, icons, grad, mk, nclass))
    open(a[2], 'w').write(art_s(art))
    if len(a) == 5:
        png(pics, art, grad, a[4])
    print('mkgui: %d tiles (%d bytes), 6 icons, 8 corner masks' % (len(art), 32 * len(art)))


if __name__ == '__main__':
    main()
