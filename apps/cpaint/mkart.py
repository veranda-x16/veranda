#!/usr/bin/env python3
"""Colour Paint's Sunroom chrome (Veranda Look 3, DECISIONS V170): the
tool column (x 0-39) and the title band (x 40-319, y 14-27) of the 320 x
240 screen, as bytes of the picture's palette (the canvas shows them
under the 1 bpp screen like the picture), written as

  art.s   overlays 2 and 3: the column's rows 14-126 and 127-239, 40
          bytes each (overlay 2 also the title band's row pattern)
  art.h   the layout and the chrome's palette entries for cpaint.c

usage: mkart.py [--png out.png] [--check]
       (--png: a preview at 4x, the first tool chosen; --check: art.s and
       art.h are what it writes)

The icons are Paint's own (apps/paint/mkart.py: original geometry
rendered in Look 3's style A, V147), the eyedropper new here, all mapped
to the nearest entries of Colour Paint's default palette (defpal.h): the
chrome's greys are the fixed entries where they are close (17-20, the
pointer's, and 0 and 1), its accents entries a palette editor may change
(the chrome then shows the new colours: V170).

The column, by screen rows:
  16-141  the tools, two a row, 20 x 18 cells: a plate (rounded), the
          16 x 16 icon on it; the chosen tool's plate sky (cpaint.c
          swaps the plate's two entries)
  143     a divider
  147-162 the wells A and B (16 x 16 frames; cpaint.c fills the inside)
  166     a divider
  169-200 the recent colours, 4 x 4 of 9 x 8 (a frame, the colour inside)
  204     a divider
  207-239 the status (text: cpaint.c, in the 1 bpp screen)
and a slate line at x 39 down the column's edge.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'paint'))
import mkart as pm  # noqa: E402  (Paint's icon renderer)

W = 40
Y0, Y1 = 14, 239                # the column's screen rows
H = Y1 - Y0 + 1
TOOLY, CELLW, CELLH = 16, 20, 18
TOOL_NAMES = ['select', 'fill', 'pencil', 'brush', 'spray', 'eraser', 'line', 'text', 'rect', 'box', 'oval', 'disc',
              'pick']
WELLY, WAX, WBX = 147, 3, 21
RECY, RECX, RW, RH = 169, 2, 9, 8
STATY = 207
DIVS = [143, 166, 204]
TITLEH = 14                     # the title band: y 14-27 over the view

# the default palette (defpal.h)
DEFPAL = []
for ln in open(os.path.join(HERE, 'defpal.h')):
    DEFPAL += [int(t, 16) for t in ln.replace(',', ' ').split() if t.startswith('0x')]
assert len(DEFPAL) == 256


def rgb(c):
    return ((c >> 8) & 15, (c >> 4) & 15, c & 15)


def nearest(c, fixed_first=True):
    """the default palette's entry nearest $0RGB c (the fixed entries 0,
    1 and 17-20 when one is as near as 1 step)"""
    r, g, b = rgb(c)

    def d(i):
        r2, g2, b2 = rgb(DEFPAL[i])
        return (r - r2) ** 2 + (g - g2) ** 2 + (b - b2) ** 2
    best = min(range(2, 256), key=d)
    if fixed_first:
        for i in (0, 1, 17, 18, 19, 20):
            if d(i) <= d(best) + 1:
                return i
    return best


# the chrome's colours: Look 3's row T (Paint's mkart) to entries
LOOK = {k: nearest(c) for k, c in enumerate(pm.ROW_T) if k}
LOOK[pm.SLATE] = 17             # (the pointer's dark: fixed)
BG = 20                         # the column: the pointer's light grey (fixed)
PLATE = 18                      # a tool's plate: white (fixed), its edge
EDGE = nearest(0xDDE, False)
SKY = nearest(0xACE, False)     # the chosen tool's
SKYEDGE = nearest(0x68B, False)
SLATE = LOOK[pm.SLATE]
PALE = LOOK[pm.PALE]
WHITE = LOOK[pm.WHITE]
GREY = LOOK[pm.GREY]
BAND = 20                       # the title band (the column's grey)
BANDLINE = SLATE


def pick_icon():
    """the eyedropper (new): a glass tube with its bulb, a drop below"""
    import math
    ic = pm.Ic('pick')
    ic.s(pm.L(4.0, 12.0, 10.5, 5.5, 3.2), 'sky')
    ic.s(pm.RR(10.0, 1.5, 5.0, 5.0, 2.0), 'dark')
    ic.s(pm.L(9.0, 7.0, 11.0, 5.0, 4.2), 'metal')
    ic.d(lambda u, v: (math.floor(u), math.floor(v)) in {(2, 14), (3, 14), (2, 13)}, pm.BLUE)
    return ic


def icons():
    got = {ic.name: pm.render(ic) for ic in pm.tools()}
    got['pick'] = pm.render(pick_icon())
    return got


def rr(x, y, w, h, r):
    return {(u, v) for v in range(y, y + h) for u in range(x, x + w) if pm.RR(x, y, w, h, r)(u + 0.5, v + 0.5)}


def column():
    """the column's rows Y0..Y1, 40 entries each"""
    px = [[BG] * W for _ in range(H)]

    def put(x, y, e):
        px[y - Y0][x] = e
    ics = icons()
    for i, name in enumerate(TOOL_NAMES):
        cx, cy = (i & 1) * CELLW, TOOLY + (i >> 1) * CELLH
        pl = rr(cx + 1, cy, CELLW - 2, CELLH, 3.5)
        for (u, v) in pl:
            edge = any((u + du, v + dv) not in pl for du, dv in ((1, 0), (-1, 0), (0, 1), (0, -1)))
            put(u, v, EDGE if edge else PLATE)
        g = ics[name]
        for v in range(16):
            for u in range(16):
                if g[v][u]:
                    put(cx + 2 + u, cy + 1 + v, LOOK[g[v][u]])
    for y in DIVS:                  # an etched line
        for x in range(3, 37):
            put(x, y, PALE)
            put(x, y + 1, WHITE)
    for wx in (WAX, WBX):           # the wells: a slate frame and a shadow
        for k in range(16):
            for (x, y) in ((wx + k, WELLY), (wx + k, WELLY + 15), (wx, WELLY + k), (wx + 15, WELLY + k)):
                put(x, y, SLATE)
            put(wx + 16, WELLY + 1 + k, GREY) if k < 15 else None
            put(wx + 1 + k, WELLY + 16, GREY) if k < 15 else None
    for i in range(16):             # the recent colours' frames
        x0, y0 = RECX + (i & 3) * RW, RECY + (i >> 2) * RH
        for x in range(x0, x0 + RW - 1):
            put(x, y0, SLATE)
            put(x, y0 + RH - 2, SLATE)
        for y in range(y0, y0 + RH - 1):
            put(x0, y, SLATE)
            put(x0 + RW - 2, y, SLATE)
    for y in range(Y0, Y1 + 1):     # the slate line at the edge
        put(W - 1, y, SLATE)
    return px


def band():
    """the title band's rows (the same each column): its colour, a slate
    line at the bottom"""
    return [BAND] * (TITLEH - 1) + [BANDLINE]


def write(px, art_s, art_h):
    rows = [bytes(r) for r in px]
    half = 113
    out = ['; Colour Paint\'s chrome: written by apps/cpaint/mkart.py (DECISIONS V170)',
           '.segment "OVERLAY2"', '.export _art_col0', '_art_col0:   ; the column\'s rows %d-%d' % (Y0, Y0 + half - 1)]
    for r in rows[:half]:
        out.append('\t.byte ' + ', '.join('$%02X' % b for b in r))
    out += ['.segment "OVERLAY3"', '.export _art_col1', '_art_col1:   ; rows %d-%d' % (Y0 + half, Y1)]
    for r in rows[half:]:
        out.append('\t.byte ' + ', '.join('$%02X' % b for b in r))
    s = '\n'.join(out) + '\n'
    h = ['/* Colour Paint\'s chrome: written by apps/cpaint/mkart.py (DECISIONS V170) */',
         '#define ART_HALF  %d          /* the column\'s rows %d-%d in overlay 2, the rest in 3 */' % (half, Y0, Y0 + half - 1),
         '#define C_BG      %d' % BG, '#define C_PLATE   %d' % PLATE, '#define C_EDGE    %d' % EDGE,
         '#define C_SKY     %d' % SKY, '#define C_SKYEDGE %d' % SKYEDGE, '#define C_SLATE   %d' % SLATE,
         '#define C_BAND    %d' % BAND, '#define TITLEH    %d' % TITLEH,
         '#define TOOLY     %d' % TOOLY, '#define CELLW     %d' % CELLW, '#define CELLH     %d' % CELLH,
         '#define WELLY     %d' % WELLY, '#define WAX       %d' % WAX, '#define WBX       %d' % WBX,
         '#define RECY      %d' % RECY, '#define RECX      %d' % RECX, '#define RW        %d' % RW,
         '#define RH        %d' % RH, '#define STATY     %d' % STATY,
         'extern const unsigned char art_col0[], art_col1[];']
    hs = '\n'.join(h) + '\n'
    return s, hs


def main():
    a = sys.argv[1:]
    px = column()
    s, hs = write(px, None, None)
    ps, ph = os.path.join(HERE, 'art.s'), os.path.join(HERE, 'art.h')
    if '--check' in a:
        ok = os.path.exists(ps) and open(ps).read() == s and os.path.exists(ph) and open(ph).read() == hs
        if not ok:
            sys.exit('mkart.py: art.s or art.h is not what it writes')
        return
    open(ps, 'w').write(s)
    open(ph, 'w').write(hs)
    if '--png' in a:
        from PIL import Image
        img = Image.new('RGB', (W, H))
        for y in range(H):
            for x in range(W):
                r, g, b = rgb(DEFPAL[px[y][x]])
                img.putpixel((x, y), (r * 17, g * 17, b * 17))
        img.resize((W * 4, H * 4), Image.NEAREST).save(a[a.index('--png') + 1])
    print('mkart.py: colours: bg %d plate %d edge %d sky %d slate %d band %d' % (BG, PLATE, EDGE, SKY, SLATE, BAND))


if __name__ == '__main__':
    main()
