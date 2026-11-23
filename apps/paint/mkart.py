#!/usr/bin/env python3
"""Paint's Sunroom chrome (Veranda Look 3, DECISIONS V147): the tool and
palette column at the left of the screen (x 0-47, y 16-479), drawn here
as 4 bpp tiles for the kernel's tile mode (V101, V105: layer 0 under the
1 bpp bitmap), and written as

  art.s   overlay 3 of Paint: one record of VRAM chunks (vrpic.h's
          vr_vram_load: 3 bytes the address, 2 the length, the bytes; a
          length 0 ends): tiles 0-15 solid, the chrome's tiles from 16,
          palette rows 2-11 and 15, the column's map (6 x 58 cards)
  art.h   the tables Paint's chrome code (chrome.c, overlay 2) uses: each
          tool's, pattern's and colour's cards, plain and chosen

usage: mkart.py [--png out.png] [--check]
       (--png: a preview, 8x; --check: art.s and art.h are what it writes)

The column, by card rows (the screen's; 8 pixels each):
  2-19   the tools, 2 a row, 24 x 24 cells (3 x 3 cards); the chosen one
         on a sky plate (the same tiles in palette row S instead of T)
  20     a divider
  21-36  the patterns, 3 a row, 16 x 16 swatches (the pattern itself is
         drawn in the ink by Paint, inside the frame)
  37     a divider
  38-41  the current pattern on the current colour (the inside cards are
         the colour's solid tile: ColorRect; the pattern in the ink)
  42     a divider
  43-54  the colours, 3 a row, 16 x 16 swatches
  55     a divider
  56-59  the status: the pointer's position, a shape's size (text in the
         ink, drawn by Paint)
and a slate line at x 47 (the drawing area's edge) all the way down.

The icons are original, drawn as geometry in a 16-unit space and
rendered in Look 3's style A (tools/mkicons3.py's rules at 16 x 16: a
1-pixel highlight on top and left edges, a shade on bottom and right, a
1-pixel slate outline, a 1-pixel drop shadow; light from the top left).
None is traced from any other program's artwork.

Palette rows (Paint's pictures keep row 0: their colours are VERA's 16
first entries, DECISIONS V32; rows 2-15 are free for a program in tile
mode, V105):
  2 (T)  the chrome and the icons: mist, slate, white, greys, sky, blue,
         yellow, amber, brown, red, pink; entries 2 and 3 (the plate and
         its edge) mist
  3 (S)  the same with the plate sky ($ACE) and its edge darker: a
         chosen tool or pattern is its cards in row 3
  4-11   the colour swatches: mist, slate, the ring of a chosen one, and
         two of the picture's colours each (entries 4 and 5); Paint
         writes colour 1's (the ink) when the ink changes
  15     the paper (a covered card's: menus, dialog boxes)
"""
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
N = 16

# ------------------------------------------------------------------ palette
MIST, PLATE, EDGE, SLATE, WHITE, PALE, GREY, DARK, LSKY, BLUE, YELLOW, AMBER, BROWN, RED, PINK = range(1, 16)
ROW_T = [0xFFF, 0xEEF, 0xEEF, 0xFFF, 0x223, 0xFFF, 0xDDE, 0x99A, 0x556, 0x9DF, 0x48D, 0xFE5, 0xFA3, 0xA52, 0xE44,
         0xF9B]
ROW_S = list(ROW_T)
ROW_S[PLATE] = 0xACE
ROW_S[EDGE] = 0x68B
# the picture's colours (paint.c's rgb[]: VERA's first 16 entries, the
# paper white and the ink black)
PICTURE = [0xFFF, 0x000, 0x800, 0xAFE, 0xC4C, 0x0C5, 0x00A, 0xEE7, 0xD85, 0x640, 0xF77, 0x333, 0x777, 0xAF6, 0x08F,
           0xBBB]
# a swatch row: 1 mist, 2 slate, 3 the chosen ring, 4 and 5 two colours
C_MIST, C_SLATE, C_RING, C_A, C_B = 1, 2, 3, 4, 5
RING = 0x68B

ROWT, ROWS, ROWC = 2, 3, 4      # palette rows (ROWC .. ROWC + 7)
TILE0 = 16                      # the chrome's first tile


def crow(k):
    r = [0xFFF] * 16
    r[C_MIST], r[C_SLATE], r[C_RING] = 0xEEF, 0x223, RING
    r[C_A], r[C_B] = PICTURE[2 * k], PICTURE[2 * k + 1]
    return r


# ------------------------------------------------------------------ shapes
def R(x, y, w, h):
    return lambda u, v: x <= u < x + w and y <= v < y + h


def RR(x, y, w, h, r):
    def f(u, v):
        if not (x <= u < x + w and y <= v < y + h):
            return False
        cx = min(max(u, x + r), x + w - r)
        cy = min(max(v, y + r), y + h - r)
        return (u - cx) ** 2 + (v - cy) ** 2 <= r * r
    return f


def E(cx, cy, rx, ry):
    return lambda u, v: ((u - cx) / rx) ** 2 + ((v - cy) / ry) ** 2 <= 1.0


def P(*pts):
    def f(u, v):
        ins = False
        n = len(pts)
        for i in range(n):
            x0, y0 = pts[i]
            x1, y1 = pts[(i + 1) % n]
            if (y0 > v) != (y1 > v):
                if u < x0 + (v - y0) * (x1 - x0) / (y1 - y0):
                    ins = not ins
        return ins
    return f


def L(x0, y0, x1, y1, w):
    def f(u, v):
        dx, dy = x1 - x0, y1 - y0
        t = max(0, min(1, ((u - x0) * dx + (v - y0) * dy) / (dx * dx + dy * dy)))
        return (u - x0 - t * dx) ** 2 + (v - y0 - t * dy) ** 2 <= (w / 2) ** 2
    return f


def D(a, *bs):
    return lambda u, v: a(u, v) and not any(b(u, v) for b in bs)


def I(a, b):
    return lambda u, v: a(u, v) and b(u, v)


def rot(f, cx, cy, deg):
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    return lambda u, v: f(cx + (u - cx) * c + (v - cy) * s, cy - (u - cx) * s + (v - cy) * c)


def pix(rows, x0=0, y0=0):
    """a little pixel picture as a mask ('#' set) at unit x0, y0"""
    pts = set()
    for j, r in enumerate(rows):
        for i, ch in enumerate(r):
            if ch == '#':
                pts.add((x0 + i, y0 + j))
    return lambda u, v: (math.floor(u), math.floor(v)) in pts


MATS = {
    'white': (WHITE, WHITE, PALE),
    'pale': (WHITE, PALE, GREY),
    'metal': (PALE, GREY, DARK),
    'dark': (GREY, DARK, SLATE),
    'blue': (LSKY, BLUE, DARK),
    'sky': (WHITE, LSKY, BLUE),
    'yellow': (WHITE, YELLOW, AMBER),
    'amber': (YELLOW, AMBER, BROWN),
    'wood': (AMBER, BROWN, DARK),
    'red': (PINK, RED, BROWN),
    'pink': (WHITE, PINK, RED),
}


class Ic:
    def __init__(self, name):
        self.name = name
        self.shapes = []        # (mask, material, outline, shade)
        self.decals = []        # (mask, colour index)

    def s(self, mask, mat, outline=True, shade='soft'):
        self.shapes.append((mask, mat, outline, shade))
        return self

    def d(self, mask, colour):
        self.decals.append((mask, colour))
        return self


def raster(mask):
    return {(px, py) for py in range(N) for px in range(N) if mask(px + 0.5, py + 0.5)}


def render(ic):
    """16 rows of 16 entries of row T (0 none)"""
    grid = [[0] * N for _ in range(N)]
    owner = {}
    for k, (m, mat, ol, sh) in enumerate(ic.shapes):
        for p in raster(m):
            owner[p] = k
    union = set(owner)
    out = {}
    for (x, y), k in owner.items():
        m, mat, ol, sh = ic.shapes[k]
        hi, mid, lo = MATS[mat]
        same = lambda dx, dy: owner.get((x + dx, y + dy)) == k
        c = mid
        if sh != 'flat':
            if not same(0, -1) or not same(-1, 0):
                c = hi
            elif not same(0, 1) or not same(1, 0):
                c = lo
        out[(x, y)] = c
    for (x, y), k in owner.items():         # inner outlines: against a lower shape
        if not ic.shapes[k][2]:
            continue
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            q = owner.get((x + dx, y + dy))
            if q is not None and q < k and ic.shapes[q][2]:
                out[(x, y)] = SLATE
                break
    outline = set()
    for (x, y) in union:
        if not ic.shapes[owner[(x, y)]][2]:
            continue
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            q = (x + dx, y + dy)
            if q not in union and 0 <= q[0] < N and 0 <= q[1] < N:
                outline.add(q)
    for (x, y), c in out.items():
        grid[y][x] = c
    for (x, y) in outline:
        grid[y][x] = SLATE
    for m, col in ic.decals:
        for (x, y) in raster(m):
            grid[y][x] = col
    sil = {(x, y) for y in range(N) for x in range(N) if grid[y][x]}
    for (x, y) in list(sil):                # the drop shadow
        q = (x + 1, y + 1)
        if q not in sil and q[0] < N and q[1] < N:
            grid[q[1]][q[0]] = GREY
    return grid


# ------------------------------------------------------------------ the tools
def tools():
    t = []
    # the selection: a dashed frame and the pointer's arrow
    dash = set()
    for x in range(1, 13):
        if (x // 2) % 2 == 0:
            dash.add((x, 2))
            dash.add((x, 11))
    for y in range(2, 12):
        if (y // 2) % 2 == 1:
            dash.add((1, y))
            dash.add((12, y))
    arrow = Ic('select').s(P((8.2, 6.2), (8.2, 15.2), (10.4, 12.9), (12.0, 15.6), (13.3, 14.9), (11.8, 12.3),
                             (14.6, 12.0)), 'white')
    arrow.d(lambda u, v: (math.floor(u), math.floor(v)) in dash and not (u > 7 and v > 5), SLATE)
    t.append(arrow)
    # the fill: a pail tipped to the right, its paint running out
    t.append(Ic('fill')
             .s(rot(P((0.5, 4.0), (9.5, 4.0), (8.2, 12.5), (1.8, 12.5)), 5.0, 8.0, 45), 'metal')
             .s(rot(E(5.0, 4.0, 4.5, 1.6), 5.0, 8.0, 45), 'dark', shade='flat')
             .s(P((9.6, 5.4), (11.8, 6.0), (13.6, 9.0), (14.6, 12.4), (13.8, 14.6), (11.8, 14.4), (11.2, 11.0)),
                'blue'))
    # the pencil: from the point at the bottom left up to its eraser
    a = math.radians(45)
    t.append(Ic('pencil')
             .s(L(4.5, 11.5, 11.6, 4.4, 4.4), 'yellow')
             .s(L(11.8, 4.2, 13.4, 2.6, 4.4), 'pink')
             .s(P((1.4, 14.6), (2.2, 10.0), (6.0, 13.8)), 'amber')
             .d(pix(['##', '#.'], 1, 13), SLATE))
    # the brush: a wooden handle, the ferrule, the bristles with paint
    t.append(Ic('brush')
             .s(L(9.6, 6.4, 14.0, 2.0, 2.8), 'wood')
             .s(L(7.4, 8.6, 9.8, 6.2, 4.2), 'metal')
             .s(P((1.2, 14.8), (2.0, 10.6), (5.4, 8.0), (8.0, 10.6), (5.4, 14.0)), 'dark')
             .s(P((1.2, 14.8), (1.8, 12.0), (4.0, 14.2)), 'blue', outline=False))
    # the spray: a can with its cap, a mist of dots
    sp = Ic('spray').s(RR(7.0, 5.5, 7.0, 9.5, 1.5), 'red').s(R(8.5, 2.5, 4.0, 3.5), 'metal')
    sp.d(pix(['#.#', '...', '#.#', '.#.', '#..'], 1, 2), SLATE)
    sp.d(pix(['#'], 4, 4), SLATE)
    sp.d(pix(['#'], 5, 1), SLATE)
    t.append(sp)
    # the eraser: a block, the near end pale
    t.append(Ic('eraser')
             .s(P((1.5, 10.5), (8.5, 3.5), (14.5, 7.0), (7.5, 14.0)), 'pink')
             .s(P((1.5, 10.5), (4.8, 7.2), (10.6, 10.8), (7.5, 14.0)), 'white'))
    # the line: a diagonal stroke with its ends marked
    ln = Ic('line').s(L(3.0, 13.0, 13.0, 3.0, 1.6), 'dark', outline=False, shade='flat')
    ln.s(E(3.0, 13.0, 1.9, 1.9), 'sky').s(E(13.0, 3.0, 1.9, 1.9), 'sky')
    t.append(ln)
    # the text: a capital letter
    t.append(Ic('text')
             .s(D(P((1.5, 14.5), (6.0, 1.5), (10.0, 1.5), (14.5, 14.5), (10.8, 14.5), (9.9, 11.6), (6.1, 11.6),
                    (5.2, 14.5)), P((7.0, 9.0), (8.0, 5.0), (9.0, 9.0))), 'blue'))
    # the rectangle and the filled one; the oval and the filled one
    t.append(Ic('rect').s(D(R(1.0, 3.0, 14.0, 11.0), R(3.0, 5.0, 10.0, 7.0)), 'white'))
    t.append(Ic('box').s(R(1.0, 3.0, 14.0, 11.0), 'sky'))
    t.append(Ic('oval').s(D(E(8.0, 8.5, 7.4, 5.7), E(8.0, 8.5, 5.1, 3.4)), 'white'))
    t.append(Ic('disc').s(E(8.0, 8.5, 7.4, 5.7), 'sky'))
    return t


# tool numbers (paint.h's T_*) in the column's order: 2 a row
TOOL_NAMES = ['select', 'fill', 'pencil', 'brush', 'spray', 'eraser', 'line', 'text', 'rect', 'box', 'oval', 'disc']

# ------------------------------------------------------------------ the column
W, H = 48, 464                  # pixels (the screen's x 0-47, y 16-479)
TOOLY, PATY, CURY, COLY, STATY = 0, 152, 288, 328, 432     # column y of each part
DIVS = [144, 280, 320, 424]     # divider rows (card rows 20, 37, 42, 55)


def swatch(u, v):
    """a swatch's pixel in its 16 x 16 cell: a 13 x 13 box at 1, 1 (a
    3-pixel gap to the next, and to the slate line at x 47): the ring
    outside the frame, the frame, the ring inside it, the inside"""
    if u > 14 or v > 14:
        return None
    d = min(u, v, 14 - u, 14 - v)
    return ('ring0', 'frame', 'ring2')[d] if d < 3 else 'in'


def column():
    """the column's pixels as (palette row class, entry): class 'T' (rows
    T/S), or a colour swatch's row k; and the selectable parts' cards"""
    px = [[('T', MIST) for _ in range(W)] for _ in range(H)]
    parts = {}

    def put(x, y, cls, e):
        px[y][x] = (cls, e)

    # the tools: a plate (entries PLATE and EDGE: invisible in row T,
    # the sky plate in row S) and the icon on it
    icons = {ic.name: render(ic) for ic in tools()}
    plate = raster(RR(1, 1, 22, 22, 3.2)) if False else None
    for i, name in enumerate(TOOL_NAMES):
        cx, cy = (i & 1) * 24, TOOLY + (i >> 1) * 24
        pl = {(u, v) for v in range(24) for u in range(24)
              if RR(1, 1, 22, 22, 3.5)(u + 0.5, v + 0.5)}
        for (u, v) in pl:
            edge = any((u + du, v + dv) not in pl for du, dv in ((1, 0), (-1, 0), (0, 1), (0, -1)))
            put(cx + u, cy + v, 'T', EDGE if edge else PLATE)
        g = icons[name]
        for v in range(N):
            for u in range(N):
                if g[v][u]:
                    put(cx + 4 + u, cy + 4 + v, 'T', g[v][u])
        parts['tool%d' % i] = (cx // 8, (cy + 16) // 8, 3, 3, 'row')
    # dividers: an etched line
    for y in DIVS:
        for x in range(3, 45):
            put(x, y + 3, 'T', PALE)
            put(x, y + 4, 'T', WHITE)
    # the patterns: a slate frame, inside it the paper (Paint draws the
    # pattern); chosen: the ring outside the frame and one inside it
    for i in range(24):
        cx, cy = (i % 3) * 16, PATY + (i // 3) * 16
        for v in range(16):
            for u in range(16):
                k = swatch(u, v)
                if k:
                    put(cx + u, cy + v, 'T', {'ring0': PLATE, 'frame': SLATE, 'ring2': EDGE, 'in': 0}[k])
        parts['pat%d' % i] = (cx // 8, (cy + 16) // 8, 2, 2, 'row')
    # the current pattern on the current colour: a frame around 4 x 2
    # cards that are the colour's solid tile (Paint's)
    l, t, r, b = 8, CURY + 8, 39, CURY + 23     # the inside
    for y in range(t - 1, b + 2):
        put(l - 1, y, 'T', SLATE)
        put(r + 1, y, 'T', SLATE)
    for x in range(l - 1, r + 2):
        put(x, t - 1, 'T', SLATE)
        put(x, b + 1, 'T', SLATE)
    for y in range(t, b + 3):
        put(r + 2, y, 'T', GREY)
    for x in range(l, r + 3):
        put(x, b + 2, 'T', GREY)
    for y in range(t, b + 1):
        for x in range(l, r + 1):
            put(x, y, 'solid', 0)
    parts['current'] = (1, (t + 16) // 8, 4, 2, 'solid')
    # the colours: a slate frame around the colour; chosen: the ring
    # (entry C_RING) outside the frame and one inside it
    for i in range(18):
        cx, cy = (i % 3) * 16, COLY + (i // 3) * 16
        if i >= 16:
            continue
        k = i >> 1
        for v in range(16):
            for u in range(16):
                e = {None: C_MIST, 'ring0': ('ring', C_MIST), 'frame': C_SLATE, 'ring2': ('ring', C_A + (i & 1)),
                     'in': C_A + (i & 1)}[swatch(u, v)]
                px[cy + v][cx + u] = (k, e)
        parts['col%d' % i] = (cx // 8, (cy + 16) // 8, 2, 2, 'tiles')
    # the slate line at x 47
    for y in range(H):
        cls, e = px[y][47]
        px[y][47] = (cls, C_SLATE if isinstance(cls, int) else SLATE)
    return px, parts


def resolve(px, chosen=None):
    """the pixels with the rings of the part chosen (a colour) drawn"""
    out = [[None] * W for _ in range(H)]
    for y in range(H):
        for x in range(W):
            cls, e = px[y][x]
            if isinstance(e, tuple):
                e = C_RING if chosen and chosen(x, y) else e[1]
            out[y][x] = (cls, e)
    return out


def card(pix, cx, cy):
    rows = tuple(tuple(pix[cy * 8 + y][cx * 8 + x][1] for x in range(8)) for y in range(8))
    cls = {pix[cy * 8 + y][cx * 8 + x][0] for y in range(8) for x in range(8)}
    if len(cls) != 1:
        raise ValueError('card %d, %d: palette classes %r' % (cx, cy + 2, cls))
    return cls.pop(), rows


class Tiles:
    def __init__(self):
        self.tiles = []
        self.index = {}

    def get(self, rows):
        """(tile number, flips: bit 2 h, bit 3 v)"""
        if all(v == rows[0][0] for r in rows for v in r):
            return rows[0][0], 0        # tiles 0-15: solid (tile c every pixel c)
        h = tuple(r[::-1] for r in rows)
        v = rows[::-1]
        hv = tuple(r[::-1] for r in rows[::-1])
        for t, f in ((rows, 0), (h, 4), (v, 8), (hv, 12)):
            if t in self.index:
                return self.index[t], f
        n = TILE0 + len(self.tiles)
        self.tiles.append(rows)
        self.index[rows] = n
        return n, 0


def entry(tiles, cls, rows):
    t, f = tiles.get(rows)
    row = ROWT if cls == 'T' else ROWC + cls
    return (t & 255, row << 4 | f | t >> 8)


def build():
    px, parts = column()
    tiles = Tiles()
    base = resolve(px)
    cmap = {}
    for cy in range(H // 8):
        for cx in range(W // 8):
            cls, rows = card(base, cx, cy)
            if cls == 'solid':
                cmap[(cx, cy)] = (0, 0)
                continue
            cmap[(cx, cy)] = entry(tiles, cls, rows)
    tabs = {}
    for name, (x, y, w, h, kind) in parts.items():
        plain, chosen = [], []
        if kind == 'tiles':
            sx, sy = x * 8, (y - 2) * 8
            sel = resolve(px, lambda u, v: sx <= u < sx + w * 8 and sy <= v < sy + h * 8)
        for j in range(h):
            for i in range(w):
                e = cmap[(x + i, y - 2 + j)]
                plain.append(e)
                if kind == 'row':
                    chosen.append((e[0], (e[1] & 15) | ROWS << 4))
                elif kind == 'tiles':
                    cls, rows = card(sel, x + i, y - 2 + j)
                    chosen.append(entry(tiles, cls, rows))
                else:
                    chosen.append(e)
        tabs[name] = (x, y, w, h, plain, chosen)
    return px, tiles, cmap, tabs


def b12(v):
    return [(v >> 4 & 15) << 4 | (v & 15), v >> 8 & 15]


def palette_rows():
    rows = {ROWT: ROW_T, ROWS: ROW_S}
    for k in range(8):
        rows[ROWC + k] = crow(k)
    return rows


def tile_bytes(rows):
    out = []
    for r in rows:
        for x in range(0, 8, 2):
            out.append(r[x] << 4 | r[x + 1])
    return out


def write(tiles, cmap, tabs, out=HERE):
    pal = palette_rows()
    chunks = []
    solid = []
    for c in range(16):
        solid += [c << 4 | c] * 32
    chunks.append((0x13000, solid + [b for t in tiles.tiles for b in tile_bytes(t)]))
    prow = []
    for r in range(ROWT, ROWC + 8):
        for v in pal[r]:
            prow += b12(v)
    chunks.append((0x1FA00 + 32 * ROWT, prow))
    chunks.append((0x1FA00 + 32 * 15, b12(0xFFF) * 16))
    for cy in range(H // 8):
        row = []
        for cx in range(W // 8):
            row += list(cmap[(cx, cy)])
        chunks.append((0x1AC00 + 256 * (cy + 2), row))
    with open(os.path.join(out, 'art.s'), 'w') as o:
        o.write('; Paint\'s Sunroom chrome: overlay 3, VRAM chunks for vr_vram_load\n')
        o.write('; (written by apps/paint/mkart.py: do not edit; DECISIONS V147)\n')
        o.write('; %d chrome tiles from %d, palette rows %d-%d and 15, the column\'s map\n\n'
                % (len(tiles.tiles), TILE0, ROWT, ROWC + 7))
        o.write('.segment "OVERLAY3"\n\n')
        for addr, data in chunks:
            o.write('\t.byte $%02X, $%02X, $%02X, $%02X, $%02X\t; %d bytes at $%05X\n'
                    % (addr & 255, addr >> 8 & 255, addr >> 16, len(data) & 255, len(data) >> 8, len(data), addr))
            for i in range(0, len(data), 16):
                o.write('\t.byte ' + ', '.join('$%02X' % b for b in data[i:i + 16]) + '\n')
        o.write('\t.byte 0, 0, 0, 0, 0\n')
    with open(os.path.join(out, 'art.h'), 'w') as o:
        o.write('/* Paint\'s Sunroom chrome: the cards of each tool, pattern and colour,\n'
                '   plain and chosen (map entries: the tile\'s low byte; palette row << 4\n'
                '   | flips | the tile\'s bits 8-9). Written by apps/paint/mkart.py: do\n'
                '   not edit (DECISIONS V147). */\n')
        o.write('#define ART_TILES %d\n' % len(tiles.tiles))
        o.write('#define ART_ROWT %d\n#define ART_ROWS %d\n#define ART_ROWC %d\n' % (ROWT, ROWS, ROWC))
        for kind, n, w, h in (('tool', 12, 3, 3), ('pat', 24, 2, 2), ('col', 16, 2, 2)):
            o.write('static const unsigned char art_%s[%d][2][%d] = {\n' % (kind, n, 2 * w * h))
            for i in range(n):
                x, y, w_, h_, plain, chosen = tabs['%s%d' % (kind, i)]
                o.write('    { { %s },\n      { %s } },\n' % (
                    ', '.join('%d, %d' % e for e in plain), ', '.join('%d, %d' % e for e in chosen)))
            o.write('};\n')
    return len(tiles.tiles)


def png(path, px, tabs, chosen=('tool2', 'pat1', 'col2')):
    from PIL import Image
    pal = palette_rows()
    sel = set()
    for name in chosen:
        x, y, w, h, plain, ch = tabs[name]
        if name.startswith('col'):
            continue
        for j in range(h):
            for i in range(w):
                sel.add((x + i, y + j))
    cx0, cy0, cw, chh = tabs[chosen[2]][:4]
    grid = resolve(px, lambda u, v: cx0 * 8 <= u < (cx0 + cw) * 8 and (cy0 - 2) * 8 <= v < (cy0 - 2 + chh) * 8)
    img = Image.new('RGB', (W + 80, H + 16), (255, 255, 255))
    pats = [0x00, 0xFF, 0xAA55AA55, 0x88228822]
    for y in range(H):
        for x in range(W):
            cls, e = grid[y][x]
            if cls == 'solid':
                v = PICTURE[2]
            elif cls == 'T':
                row = ROWS if (x // 8, y // 8 + 2) in sel else ROWT
                v = pal[row][e] if e else 0xFFF
            else:
                v = pal[ROWC + cls][e] if e else 0xFFF
            img.putpixel((x, y + 16), ((v >> 8 & 15) * 17, (v >> 4 & 15) * 17, (v & 15) * 17))
    img = img.resize((img.width * 8, img.height * 8), Image.NEAREST)
    img.save(path)


def main():
    px, tiles, cmap, tabs = build()
    if '--check' in sys.argv:
        import tempfile
        with tempfile.TemporaryDirectory() as t:
            write(tiles, cmap, tabs, t)
            for f in ('art.s', 'art.h'):
                if open(os.path.join(t, f)).read() != open(os.path.join(HERE, f)).read():
                    sys.exit('mkart: apps/paint/%s is not what mkart.py writes' % f)
        print('mkart: art.s and art.h are what it writes (%d chrome tiles)' % len(tiles.tiles))
        return
    n = write(tiles, cmap, tabs)
    print('mkart: %d chrome tiles (%d bytes), tiles %d-%d' % (n, 32 * n, TILE0, TILE0 + n - 1))
    if '--png' in sys.argv:
        png(sys.argv[sys.argv.index('--png') + 1], px, tabs)


if __name__ == '__main__':
    main()
