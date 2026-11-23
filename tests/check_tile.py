#!/usr/bin/env python3
"""Gate tile (DECISIONS V101): the shell's full-colour desktop picture in
an x16emu dump's VRAM (-dump V).

usage: check_tile.py desk <dump> <wallpaper.cvt> <variant> [--skip x0,y0,x1,y1 ...]
                     [--covered x0,y0,x1,y1 ...] [--any x0,y0,x1,y1 ...]
       check_tile.py exact <dump> <picture.png> [--skip ...]
       check_tile.py shot <dump> <SHOT.BMP>
       check_tile.py app <console.txt> <dump> <wallpaper.cvt> [aside]
       check_tile.py times <console.txt> [limits]
       check_tile.py plain <dump>
       check_tile.py box <dump> <wallpaper.cvt> <variant>
       check_tile.py chrome <dump> <wallpaper.cvt> <variant> [--win x0,y0,x1,y1 [--back]] [--desk]
                     [--dock x0,y0,x1,y1] [--accent n] [--square q,...]

desk: tile mode on (layer 0 4 bpp 8 x 8 tiles, its tile base $13000, the
map at $1AC00 128 wide); VRAM $13000 holds the file's tiles; palette rows
2-13 the variant's (0 light, 1 dark), row 15 the paper (entry 0); every
desktop card (rows 2-59, cards 0-68: left of the desktop's icons) not in
a --skip rectangle (cards, inclusive) shows the file's map entry, its
bitmap 0 on both screens, its shadow byte 0 (not covered); a --covered
card keeps its tile and flips, shows palette row 15 or 14 and its shadow
byte holds its own row and a cover; --any cards are not looked at; the
count of covers (VRAM $1EB00) is the number of --covered rectangles' levels
seen (0 without).
exact: the screen as VERA shows it (tools/vram2png.py) equals the picture
pixel for pixel on those cards (a picture drawn as tiles: V162's).
shot: ExportRect's 8 bpp BMP (the shell's SHOT.BMP) equals the screen as
VERA shows it, pixel for pixel, and its palette VERA's 256 entries.
app: tests/tile_app.s's lines: at its start tile mode off and the rows
2-15 not the picture's; after SET a 1 bpp colour map ($60, tile base
$F4) and its own entries; [aside] back from the switcher with the same
rows and its map; the dump (the shell again) in tile mode, VRAM_TILEPAL
($12C00) the program's rows as it left them.
chrome (DECISIONS V102: a wallpaper of version 3): palette row 13 the
icons' colours (shell/gui.inc) and its entries 11-15 the shades, the same
in rows 2-12, 12 the accent (entry n, 5), 14 chrome; the pool (VRAM
$17C00: tile 608) shell/guiart.s's tiles and every colour's four rounded
corners; --desk: the desktop's card, printer and trash as colour icons
(row 13) at cards 72, rows 4, 11, 18, their corners composed (the
picture's tile in its row where the mask is 0, the art where 1); --win: a
window's title band (in front, not --back: the gradient's two tiles) and
its four corners composed and round in the ink on both screens (the
--square ones not on the picture: the plain colour, square), a colour
icon of a folder in it; --dock: the dock's plate's corners composed, its
first item's corners a colour's rounded ones.
box (V102): the shell's message box over the picture (cards 28-51, rows
24-35, covered): its title band (rows 24-26: the gradient's two tiles and
shade 13 in row 13, still covered), its line, its corners composed on the
picture and round in the ink (the bottom right on the shadow), the
shadow's two end cards the picture.
times: the shell's logs (SHELL MOVED, REPAINT, ALL, DESKTOP FILL and
COLOURS IN <cycles>) printed; limits "WHAT=cycles,...": exit 1 above.
"""
import os
import re
import struct
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'tools'))
import mkwall  # noqa: E402
import vram2png  # noqa: E402

VDUMP = 132878
VRAM, COMPOSER, PALETTE = 131072, 256, 512
MAP = 0x1AC00
BACK = 0x09600
TILES = 0x13000
TILECOV = 0x1EB00
TILEPAL = 0x12C00
SHADOW = 160


def fail(m):
    print('FAIL ', m)
    sys.exit(1)


def section(path):
    d = open(path, 'rb').read()
    return d[len(d) - VDUMP:]


def pal(v, i):
    p = v[VRAM + COMPOSER:]
    return p[2 * i] | p[2 * i + 1] << 8


def layers(v):
    return [v[VRAM + COMPOSER + PALETTE + 7 * i:][:7] for i in range(2)]


def rects(a, name):
    out = []
    while name in a:
        i = a.index(name)
        out.append(tuple(int(x) for x in a[i + 1].split(',')))
        del a[i:i + 2]
    return out


def inside(cx, cy, rs):
    return any(x0 <= cx <= x1 and y0 <= cy <= y1 for x0, y0, x1, y1 in rs)


def desk(v, path, variant, skip, covered, anyr):
    data = mkwall.read(path)
    if data[4] not in (2, 3):
        fail('%s: not a version 2 or 3 wallpaper' % path)
    ncol = 10 if data[4] == 3 else 15
    p256, mp, tiles = mkwall.parts2(data, variant)
    l0 = layers(v)[0]
    if l0[0] != 0x62 or l0[2] != 0x98 or l0[1] != MAP >> 9:
        fail('layer 0 is not in tile mode: config $%02X, map base $%02X, tile base $%02X' % (l0[0], l0[1], l0[2]))
    if not v[VRAM] & 0x30 == 0x30:
        fail('DC_VIDEO $%02X: not both layers' % v[VRAM])
    if bytes(v[TILES:TILES + len(tiles)]) != bytes(tiles):
        bad = next(i for i in range(len(tiles)) if v[TILES + i] != tiles[i])
        fail('VRAM $%05X: not the file\'s tiles (tile %d)' % (TILES + bad, bad // 32))
    r0, nr = data[10], data[11]
    for e in range(r0 * 16, (r0 + nr) * 16):
        if 0 < e % 16 <= ncol and pal(v, e) != p256[e]:
            fail('palette entry %d is $%03X, not the picture\'s $%03X' % (e, pal(v, e), p256[e]))
    for e in range(240, 256):
        if pal(v, e) != pal(v, 0):
            fail('palette entry %d (row 15, a covered card\'s) is $%03X, not the paper $%03X' % (e, pal(v, e), pal(v, 0)))
    n = c = 0
    for cy in range(2, 60):
        for cx in range(69):
            if inside(cx, cy, skip) or inside(cx, cy, anyr):
                continue
            a = MAP + cy * 256 + 2 * cx
            s = v[MAP + cy * 256 + SHADOW + cx]
            want = mp[2 * (cy * 80 + cx)], mp[2 * (cy * 80 + cx) + 1]
            if inside(cx, cy, covered):
                if v[a] != want[0] or v[a + 1] & 15 != want[1] & 15 or v[a + 1] >> 4 not in (14, 15):
                    fail('card %d, %d: covered, %02X %02X, not the tile %02X %X shown in row 14 or 15' % (
                        cx, cy, v[a], v[a + 1], want[0], want[1] & 15))
                if s >> 4 != want[1] >> 4 or not s & 15:
                    fail('card %d, %d: its shadow byte $%02X, not its row %d and a cover' % (cx, cy, s, want[1] >> 4))
                c += 1
                continue
            if (v[a], v[a + 1]) != want:
                fail('card %d, %d: map entry %02X %02X, not the picture\'s %02X %02X' % (cx, cy, v[a], v[a + 1], *want))
            if s:
                fail('card %d, %d: its shadow byte is $%02X (not covered: 0)' % (cx, cy, s))
            for j in range(8):
                r = cy * 8 + j
                if v[r * 80 + cx] or v[BACK + r * 80 + cx]:
                    fail('card %d, %d, row %d: ink on the picture (foreground $%02X, back screen $%02X)' % (
                        cx, cy, j, v[r * 80 + cx], v[BACK + r * 80 + cx]))
            n += 1
    if not covered and v[TILECOV]:
        fail('VRAM_TILECOV is %d with nothing covered' % v[TILECOV])
    if covered and not v[TILECOV]:
        fail('VRAM_TILECOV is 0 with cards covered')
    print('ok    tile mode ($62, tiles at $13000, %d of them the file\'s), palette rows %d-%d the %s variant\'s, row 15 '
          'the paper; %d desktop cards the picture (map entries, no ink on either screen, not covered)%s' % (
              len(tiles) // 32, r0, r0 + nr - 1, 'dark' if variant else 'light', n,
              '; %d covered (row 14 or 15, tile kept, own row and a cover in the shadow byte; %d covers in place)' % (
                  c, v[TILECOV]) if covered else ''))


def exact(v, png, skip):
    from PIL import Image
    img = Image.open(png).convert('RGB')
    b = img.tobytes()
    rows = vram2png.compose(v)
    n = 0
    for cy in range(2, 60):
        for cx in range(69):
            if inside(cx, cy, skip):
                continue
            for j in range(8):
                y = cy * 8 + j
                for i in range(8):
                    x = cx * 8 + i
                    want = tuple(b[3 * (y * 640 + x):3 * (y * 640 + x) + 3])
                    if tuple(rows[y][x]) != want:
                        fail('pixel %d, %d: %s on the screen, %s in %s' % (x, y, rows[y][x], want, png))
            n += 1
    print('ok    %d desktop cards (%d pixels) on the screen equal %s exactly' % (n, n * 64, os.path.basename(png)))


def shot(v, bmp):
    d = open(bmp, 'rb').read()
    if d[:2] != b'BM':
        fail('%s: not a BMP' % bmp)
    off, = struct.unpack('<I', d[10:14])
    w, h, planes, bpp = struct.unpack('<iiHH', d[18:30])
    ncol, = struct.unpack('<I', d[46:50])
    if (w, h, bpp) != (640, 480, 8) or off != 54 + 1024 or ncol not in (0, 256):
        fail('%s: %d x %d, %d bpp, rows at %d, %d colours: not 640 x 480 x 8 with 256' % (bmp, w, h, bpp, off, ncol))
    if len(d) != off + 640 * 480:
        fail('%s: %d bytes, not %d' % (bmp, len(d), off + 640 * 480))
    bpal = [(d[54 + 4 * i + 2], d[54 + 4 * i + 1], d[54 + 4 * i]) for i in range(256)]
    for i in range(256):
        if bpal[i] != vram2png.rgb(v, i):
            fail('%s: palette entry %d %s, VERA\'s %s' % (bmp, i, bpal[i], vram2png.rgb(v, i)))
    rows = vram2png.compose(v)
    for y in range(480):
        r = d[off + (479 - y) * 640:off + (480 - y) * 640]
        for x in range(640):
            if bpal[r[x]] != tuple(rows[y][x]):
                fail('%s: pixel %d, %d is entry %d %s, the screen %s' % (bmp, x, y, r[x], bpal[r[x]], rows[y][x]))
    print('ok    %s: 640 x 480, 8 bpp, VERA\'s 256 palette entries; every pixel as VERA shows the screen' % bmp)


def psum(b):
    return sum(b) & 0xFFFF


def app(console, v, path, aside):
    t = open(console, 'rb').read().decode('latin-1').replace('\r', '')
    got = {}
    for m in re.finditer(r'TILEAPP (START|SET|BACK) L0 ([0-9A-F]{2}) TB ([0-9A-F]{2}) PAL ([0-9A-F]{4})', t):
        got[m.group(1)] = (int(m.group(2), 16), int(m.group(3), 16), int(m.group(4), 16))
    for k in ('START', 'SET') + (('BACK',) if aside else ()):
        if k not in got:
            fail('no "TILEAPP %s" line on the console' % k)
    if 'TILEAPP QUIT' not in t:
        fail('TileApp did not quit')
    data = mkwall.read(path)
    p256, _, _ = mkwall.parts2(data, 0)
    pic = psum(b''.join(c.to_bytes(2, 'little') for c in p256[32:]))
    l0, tb, ps = got['START']
    if tb == 0x98 or l0 & 0x07 == 2:
        fail('at its start layer 0 is still the tile desktop (config $%02X, tile base $%02X)' % (l0, tb))
    if ps == pic:
        fail('at its start the palette rows 2-15 are the picture\'s')
    l0, tb, ps = got['SET']
    if (l0, tb) != (0x60, 0xF4):
        fail('its colour map: layer 0 config $%02X, tile base $%02X, not the 1 bpp map ($60, $F4)' % (l0, tb))
    kept = psum(v[TILEPAL:TILEPAL + 448])
    if kept != ps:
        fail('the shell kept rows summing to %04X at its start after it, not the program\'s %04X' % (kept, ps))
    msg = ('TileApp started from the tile desktop: tile mode off (layer 0 $%02X), the rows 2-15 its own (sum %04X, '
           'not the picture\'s %04X); its 1 bpp map ($60, $F4) on' % (got['START'][0], got['START'][2], pic))
    if aside:
        if got['BACK'] != got['SET']:
            fail('back from the switcher: %s, not as it left (%s)' % (got['BACK'], got['SET']))
        msg += '; put aside (the switcher), the shell in tile mode, brought back from the dock: its map and rows as it left them'
    print('ok    ' + msg + '; the shell again: VRAM_TILEPAL holds its rows (%04X)' % kept)


def times(console, limits):
    t = open(console, 'rb').read().decode('latin-1').replace('\r', '')
    lim = {}
    if limits:
        for x in limits.split(','):
            k, c = x.split('=')
            lim[k] = int(c)
    bad = []
    for m in re.finditer(r'SHELL (MOVED|REPAINT|ALL|DESKTOP FILL|DESKTOP COLOURS) IN ([0-9]+)', t):
        what, c = m.group(1), int(m.group(2))
        print('%-16s %9d  %6.1f ms' % (what, c, c / 8000))
        k = what.replace(' ', '_')
        if k in lim and c > lim[k]:
            bad.append('%s %d > %d' % (what, c, lim[k]))
    if bad:
        fail('slower than the limits: ' + ', '.join(bad))


# ---------------------------------------------------------------- the colour chrome (V102)
POOL = 0x260                    # tile 608: VRAM $17C00
GROW = 13
SHELLDIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'shell')
KINDS = ['folder', 'up', 'document', 'card', 'printer', 'trash']


def gui_tables():
    """shell/gui.inc and shell/guiart.s (tools/mkgui.py) -> dict"""
    inc = open(os.path.join(SHELLDIR, 'gui.inc')).read().split('\n')
    t = {'icon': [], 'mask': [], 'cols': []}
    cur = None
    for line in inc:
        m = re.match(r'(GUI_\w+) = (\d+)', line)
        if m:
            t[m.group(1)] = int(m.group(2))
        elif line.startswith('guiIcon:'):
            cur = 'icon'
        elif line.startswith('guiMask:'):
            cur = 'mask'
        elif line.startswith('guiCols:'):
            cur = 'cols'
        elif cur and '.byte' in line:
            t[cur].append([int(x.strip()[1:], 16) for x in line.split(';')[0].split('.byte')[1].split(',')])
        elif cur == 'cols' and '.word' in line:
            t['cols'] = [int(x.strip()[1:], 16) for x in line.split('.word')[1].split(',')]
    art = b''
    for line in open(os.path.join(SHELLDIR, 'guiart.s')):
        if line.startswith('\t.byte'):
            art += bytes(int(x.strip()[1:], 16) for x in line.split('.byte')[1].split(','))
    t['art'] = art
    t['CORN'] = POOL + t['GUI_NART']
    t['DYN'] = t['CORN'] + 64
    return t


def tpix(data, x, y):
    b = data[y * 4 + x // 2]
    return b & 15 if x & 1 else b >> 4


def vtile(v, t):
    return bytes(v[TILES + 32 * t:TILES + 32 * t + 32])


def entry(v, cx, cy):
    a = MAP + cy * 256 + 2 * cx
    return v[a], v[a + 1]


ICONS3 = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'shell', 'icons3.txt')
NAMES3 = {'folder': 'Folder', 'up': 'Up', 'document': 'Document', 'card': 'SD card', 'printer': 'Printer',
          'trash': 'Trash'}


def ic3(v, cx, cy, kind=None):
    """(V153) a Look 3 colour icon (look3.c's cache) at cards cx, cy: its 16
    cards tiles in palette row 12 (the icons') or the paper (tile 0, row
    0); kind: its ink is the library's icon's (shell/icons3.txt)"""
    for j in range(4):
        for i in range(4):
            lo, hi = entry(v, cx + i, cy + j)
            if not (hi >> 4 == 12 and (lo | (hi & 3) << 8) >= 17) and (lo, hi) != (0, 0):
                return False
    if kind is None:
        return True
    import mkicons3
    g = [ic[2] for ic in mkicons3.read(ICONS3) if ic[0] == NAMES3[kind]][0]
    frame = [0x1FFFFFF8, 0x60000006, 0x40000002] + [0x80000001] * 26 + [0x40000002, 0x60000006, 0x1FFFFFF8]
    ok = [True, True]                   # (bare; on a picture its plate's frame, radius 4)
    for r in range(32):
        row = sum(1 << (31 - x) for x in range(32) if g[r][x] == 'K')
        a = (cy * 8 + r) * 80 + cx
        got = int.from_bytes(v[a:a + 4], 'big')
        ok = [ok[0] and got == row, ok[1] and got == row | frame[r]]
    return ok[0] or ok[1]


def composed(v, g, cx, cy, slot, art, mask, mp, ftiles, what):
    """card cx, cy: pool tile slot in the picture's row, its pixels the
    picture's where mask is 0, art's where 1"""
    lo, hi = entry(v, cx, cy)
    plo, phi = mp[2 * (cy * 80 + cx)], mp[2 * (cy * 80 + cx) + 1]
    if lo | (hi & 3) << 8 != slot or hi & 12 or hi >> 4 != phi >> 4:
        fail('%s: card %d, %d: map entry %02X %02X, not pool tile %d (no flips) in the picture\'s row %d' % (
            what, cx, cy, lo, hi, slot, phi >> 4))
    t = vtile(v, slot)
    pt = plo | (phi & 3) << 8
    for y in range(8):
        for x in range(8):
            if mask[y] & (0x80 >> x):
                want = tpix(art, x, y)
            else:
                want = mkwall.tile_pixel(ftiles, pt, x, y, phi)
            if tpix(t, x, y) != want:
                fail('%s: card %d, %d, pixel %d, %d: %d, not %d (the %s\'s)' % (
                    what, cx, cy, x, y, tpix(t, x, y), want, 'art' if mask[y] & (0x80 >> x) else 'picture'))


INK = [[(0xF0, 0x00), (0xE0, 0x10), (0xC0, 0x20), (0x80, 0x40)],
       [(0x00, 0xF0), (0x70, 0x80), (0x60, 0x80), (0x40, 0x80)]]


def ink_corner(v, cx, cy, q, square, what):
    """rows 0-3 of a window's corner card in the bitmap, both screens"""
    for j in range(4):
        clr, st = INK[square][j]
        if q & 1:
            clr, st = int('{:08b}'.format(clr)[::-1], 2), int('{:08b}'.format(st)[::-1], 2)
        y = cy * 8 + (7 - j if q & 2 else j)
        for base, scr in ((0, 'foreground'), (BACK, 'back screen')):
            b = v[base + y * 80 + cx]
            if b & clr or (b & st) != st:
                fail('%s: corner %d, row %d (%s): $%02X, not the %s corner\'s pixels (clear $%02X, set $%02X)' % (
                    what, q, j, scr, b, 'square' if square else 'round', clr, st))


def chrome(v, path, variant, win, front, desk, dock, accent, square=()):
    g = gui_tables()
    data = mkwall.read(path)
    if data[4] != 3:
        fail('%s: not a version 3 wallpaper (the chrome needs one)' % path)
    _, mp, ftiles = mkwall.parts2(data, variant)
    # the palette: row 13's icons, the shades in rows 2-13
    for i, c in enumerate(g['cols']):
        c = (c >> 1) & 0x777 if variant else c        # (dark mode: half as bright)
        if pal(v, GROW * 16 + 1 + i) != c:
            fail('palette entry %d: $%03X, not the icons\' $%03X' % (GROW * 16 + 1 + i, pal(v, GROW * 16 + 1 + i), c))
    sh = [pal(v, GROW * 16 + 11 + i) for i in range(5)]
    for r in range(data[10], data[10] + data[11]):     # (V153: the picture's rows; 11-12 the icons' on 2-10)
        for i in range(5):
            if pal(v, r * 16 + 11 + i) != sh[i]:
                fail('palette entry %d: $%03X, not the shade $%03X (row 13\'s)' % (r * 16 + 11 + i, pal(v, r * 16 + 11 + i), sh[i]))
    if sh[1] != pal(v, accent) or sh[3] != pal(v, 2):
        fail('the shades %s: 12 not the accent (entry %d, $%03X) or 14 not chrome ($%03X)' % (
            ' '.join('$%03X' % c for c in sh), accent, pal(v, accent), pal(v, 2)))
    # the pool
    if vtile(v, POOL)[:0] != b'' or bytes(v[TILES + 32 * POOL:TILES + 32 * POOL + len(g['art'])]) != g['art']:
        fail('VRAM $17C00: not the chrome\'s %d tiles (guiart.s)' % (len(g['art']) // 32))
    for c in range(16):
        for q in range(4):
            t = vtile(v, g['CORN'] + 4 * c + q)
            m = g['mask'][q]
            for y in range(8):
                for x in range(8):
                    want = c if m[y] & (0x80 >> x) else 0
                    if tpix(t, x, y) != want:
                        fail('pool tile %d (colour %d\'s corner %d): pixel %d, %d is %d, not %d' % (
                            g['CORN'] + 4 * c + q, c, q, x, y, tpix(t, x, y), want))
    out = ['the pool (%d tiles at $17C00, every colour\'s 4 corners), palette row 13 and the shades in rows %d-%d'
           % (len(g['art']) // 32, data[10], data[10] + data[11] - 1)]
    # the colour icons anywhere on the screen (4 x 4 blocks of their entries)
    found = {}
    for k, kind in enumerate(KINDS):
        want = []
        for b in g['icon'][k]:
            want.append((b & 15, GROW << 4) if b & 0x80 else ((POOL + b) & 255, GROW << 4 | (POOL + b) >> 8))
        for cy in range(2, 57):
            for cx in range(0, 77):
                ok = all(entry(v, cx + i, cy + j) == want[j * 4 + i] for j in range(4) for i in range(4)
                         if not (i in (0, 3) and j in (0, 3) and kind in ('card', 'printer', 'trash')))
                if ok:
                    found.setdefault(kind, []).append((cx, cy))
    # the desktop's icons: card, printer, trash at cards 72-75, rows 4, 11, 18
    looks3 = []
    if desk:
        for i, (kind, row) in enumerate((('card', 4), ('printer', 11), ('trash', 18))):
            if (72, row) not in found.get(kind, []):
                if ic3(v, 72, row, kind):          # (V153: Look 3's on a picture of rows 2-10)
                    looks3.append(kind)
                    continue
                if kind == 'card' and not ic3(v, 72, row) and entry(v, 73, row + 1)[1] >> 4 == 0:
                    continue                    # (the host folder's: Look 2's tile)
                fail('the desktop\'s %s: not its colour icon at cards 72, %d' % (kind, row))
            k = KINDS.index(kind)
            for q in range(4):
                i_, j_ = (q & 1) * 3, (q >> 1) * 3
                art = g['art'][32 * g['icon'][k][j_ * 4 + i_]:][:32]
                composed(v, g, 72 + i_, row + j_, g['DYN'] + 8 + 4 * i + q, art, g['mask'][q], mp, ftiles,
                         'the desktop\'s %s' % kind)
        out.append('the desktop\'s card, printer and trash colour icons%s' % (
            ' (Look 3\'s: %s, on a plate)' % ', '.join(looks3) if looks3 else ', their corners composed on the picture'))
    # a window: its title band, its corners
    if win:
        x0, y0, x1, y1 = win
        grad = g['GUI_GRAD']
        for j in range(2):
            t = POOL + grad + j
            for cx in range(x0 + 1, x1):
                if front and entry(v, cx, y0 + j) != (t & 255, GROW << 4 | t >> 8):
                    fail('the title band, card %d, %d: %02X %02X, not the gradient\'s tile %d' % (
                        (cx, y0 + j) + entry(v, cx, y0 + j) + (t,)))
        for q in range(4):
            cx, cy = (x1 if q & 1 else x0), (y1 if q & 2 else y0)
            if front and q < 2:
                art = g['art'][32 * grad:32 * grad + 32]
            else:
                art = bytes([0xEE]) * 32
            if q in square:             # (not on the picture: as before)
                t = POOL + grad
                want = (t & 255, GROW << 4 | t >> 8) if front and q < 2 else (2, 0)
                if entry(v, cx, cy) != want:
                    fail('window 0\'s corner %d (square): %02X %02X, not %02X %02X' % ((q,) + entry(v, cx, cy) + want))
            else:
                composed(v, g, cx, cy, g['DYN'] + q, art, g['mask'][4 + q], mp, ftiles, 'window 0\'s corner %d' % q)
            ink_corner(v, cx, cy, q, q in square, 'window 0')
        out.append('window 0 (cards %d-%d, rows %d-%d): the title band\'s gradient, its corners %s composed on '
                   'the picture and round in the ink on both screens%s' % (
                       x0, x1, y0, y1, ', '.join(str(q) for q in range(4) if q not in square),
                       ', %s square (not on the picture)' % ', '.join(str(q) for q in square) if square else ''))
        if 'folder' not in found and 'up' not in found:
            f3 = [(cx, cy) for cy in range(y0 + 2, y1 - 3) for cx in range(x0 + 1, x1 - 3)
                  if ic3(v, cx, cy, 'folder') or ic3(v, cx, cy, 'up')]
            if not f3:
                fail('no colour icon of a folder in window 0')
            found['folder'] = f3
        out.append('its icons: %s' % ', '.join('%s at %s' % (k, found[k]) for k in found if k in ('up', 'folder', 'document')))
    if dock:
        x0, y0, x1, y1 = dock
        for q in range(4):
            cx, cy = (x1 if q & 1 else x0), (y1 if q & 2 else y0)
            composed(v, g, cx, cy, g['DYN'] + 20 + q, bytes(32), g['mask'][4 + q], mp, ftiles, 'the dock\'s corner %d' % q)
        # its item (V152: 2 cards in): a tile with rounded corners of its
        # colour (row 0), or a colour icon; the trash's colour icon last
        lo, hi = entry(v, x0 + 2, y0 + 1)
        t = lo | (hi & 3) << 8
        if ic3(v, x0 + 2, y0 + 1):
            what = 'a colour icon'
        elif not g['CORN'] <= t < g['CORN'] + 64 or (t - g['CORN']) % 4 or hi >> 4:
            fail('the dock\'s item: card %d, %d is %02X %02X, not a colour\'s top left corner' % (x0 + 2, y0 + 1, lo, hi))
        else:
            what = 'its corners rounded (colour %d)' % ((t - g['CORN']) // 4)
        if not ic3(v, x1 - 5, y0 + 1, 'trash'):
            fail('the dock\'s trash: not its colour icon at cards %d, %d' % (x1 - 5, y0 + 1))
        out.append('the dock (cards %d-%d, rows %d-%d): its corners composed on the picture; its item %s; '
                   'the trash\'s colour icon' % (x0, x1, y0, y1, what))
    print('ok    the colour chrome: ' + '; '.join(out))


def box(v, path, variant):
    """the shell's message box (V102, gui_box) at the kernel's default place
    over the picture: cards 28-51, rows 24-35, covered with its shadow"""
    g = gui_tables()
    data = mkwall.read(path)
    _, mp, ftiles = mkwall.parts2(data, variant)
    x0, y0, x1, y1 = 28, 24, 51, 35
    grad = g['GUI_GRAD']
    dbox = g['DYN'] + 24
    for j in range(3):
        for cx in range(x0, x1 + 1):
            if j == 0 and cx in (x0, x1):
                continue
            t = POOL + grad + j if j < 2 else 13
            want = (t & 255, GROW << 4 | t >> 8) if j < 2 else (13, GROW << 4)
            if entry(v, cx, y0 + j) != want:
                fail('the box\'s title band, card %d, %d: %02X %02X, not %02X %02X' % (
                    (cx, y0 + j) + entry(v, cx, y0 + j) + want))
            s = v[MAP + (y0 + j) * 256 + SHADOW + cx]
            if not s & 15:
                fail('the box\'s title band, card %d, %d: not covered (shadow byte $%02X)' % (cx, y0 + j, s))
    for q in range(3):
        cx, cy = (x1 if q & 1 else x0), (y1 if q & 2 else y0)
        art = g['art'][32 * grad:32 * grad + 32] if q < 2 else bytes(32)
        composed(v, g, cx, cy, dbox + q, art, g['mask'][4 + q], mp, ftiles, 'the box\'s corner %d' % q)
        # (ink: the foreground only, the kernel's box)
        for j in range(4):
            clr, st = INK[0][j]
            if q & 1:
                clr, st = int('{:08b}'.format(clr)[::-1], 2), int('{:08b}'.format(st)[::-1], 2)
            y = cy * 8 + (7 - j if q & 2 else j)
            b = v[y * 80 + cx]
            if b & clr or (b & st) != st:
                fail('the box\'s corner %d, row %d: $%02X, not round (clear $%02X, set $%02X)' % (q, j, b, clr, st))
    # the bottom right on the shadow: its outside ink
    for j, st in enumerate((0x0F, 0x0F, 0x07, 0x03)):
        b = v[(y1 * 8 + 7 - j) * 80 + x1]
        if b & st != st:
            fail('the box\'s bottom right corner, row %d: $%02X, not the shadow round it ($%02X)' % (j, b, st))
    # the band's line
    for x in range(x0 * 8 + 1, x1 * 8 + 7):
        if not v[((y0 + 3) * 8 - 1) * 80 + x // 8] & (0x80 >> (x & 7)):
            fail('the title band\'s line: pixel %d, %d not ink' % (x, (y0 + 3) * 8 - 1))
    # the shadow's ends: what is under them (the picture), still covered
    for cx, cy in ((52, 24), (28, 36)):
        lo, hi = entry(v, cx, cy)
        plo, phi = mp[2 * (cy * 80 + cx)], mp[2 * (cy * 80 + cx) + 1]
        s = v[MAP + cy * 256 + SHADOW + cx]
        if (lo, hi) != (plo, phi) or not s & 15:
            fail('the shadow\'s end %d, %d: %02X %02X (shadow $%02X), not the picture\'s %02X %02X covered' % (
                cx, cy, lo, hi, s, plo, phi))
    print('ok    the message box: its title band (3 card rows, the gradient, its line), its corners composed on the '
          'picture and round (the bottom right on its shadow), its shadow\'s ends the picture')


def plain(v):
    """no card shows a tile of the chrome's pool (608 on): the look of before"""
    for cy in range(60):
        for cx in range(80):
            lo, hi = entry(v, cx, cy)
            if lo | (hi & 3) << 8 >= POOL:
                fail('card %d, %d: map entry %02X %02X, a tile of the chrome\'s pool' % (cx, cy, lo, hi))
    print('ok    no card shows a tile of the chrome\'s pool (the look of before)')


def main():
    a = sys.argv[1:]
    if not a:
        sys.exit(__doc__)
    skip, covered, anyr = rects(a, '--skip'), rects(a, '--covered'), rects(a, '--any')
    win, dock = rects(a, '--win'), rects(a, '--dock')
    flags = {f: f in a for f in ('--back', '--desk')}
    a = [x for x in a if x not in flags]
    accent = 5
    square = ()
    if '--square' in a:
        i = a.index('--square')
        square = tuple(int(x) for x in a[i + 1].split(','))
        del a[i:i + 2]
    if '--accent' in a:
        i = a.index('--accent')
        accent = int(a[i + 1])
        del a[i:i + 2]
    what = a[0]
    if what == 'desk' and len(a) == 4:
        desk(section(a[1]), a[2], int(a[3]), skip, covered, anyr)
    elif what == 'exact' and len(a) == 3:
        exact(section(a[1]), a[2], skip)
    elif what == 'shot' and len(a) == 3:
        shot(section(a[1]), a[2])
    elif what == 'app' and len(a) in (4, 5):
        app(a[1], section(a[2]), a[3], len(a) == 5)
    elif what == 'chrome' and len(a) == 4:
        chrome(section(a[1]), a[2], int(a[3]), win[0] if win else None, not flags['--back'], flags['--desk'],
               dock[0] if dock else None, accent, square)
    elif what == 'box' and len(a) == 4:
        box(section(a[1]), a[2], int(a[3]))
    elif what == 'plain' and len(a) == 2:
        plain(section(a[1]))
    elif what == 'times' and len(a) in (2, 3):
        times(a[1], a[2] if len(a) == 3 else '')
    else:
        sys.exit(__doc__)


if __name__ == '__main__':
    main()
