#!/usr/bin/env python3
"""Veranda Look 3's colour icons (DECISIONS V133): 32 x 32 shaded icons in
style A ("Sunroom": light from the top left, a 1-pixel highlight on top
and left edges and a shade on bottom and right, a 1-pixel outline in the
ink, a 1-pixel drop shadow), drawn here as geometry and written as icon
sources, packed for the CVT files (tools/vpack.py) and the shell.

usage:
  mkicons3.py write             every icon source: apps/*/icon.txt (the
                                applications of this repository),
                                shell/icons3.txt (the shell's library:
                                its own, the ports', the programs of
                                other repositories, by class) and
                                shell/icons3s.txt (the small ones, V151)
  mkicons3.py check [files...]  the rules (below) and the tiles of each
  mkicons3.py lib <icons3.txt> <out> [<out2> ...]
                                the shell's library as overlay records
                                (12 icons a record; a source of small
                                icons: one record, SM_AT, SM_LEN)
  mkicons3.py sheet <out.png> [files...]   a picture of them, 1x and 3x,
                                on the paper and on the sage

The icons were designed for Look 3 (veranda-dist plans/look3, icons.py:
the 19 of the proposal) and the same way for the rest; none is traced
from any other system's artwork.

An icon source (icon.txt):
  # comments
  icon <name>
  for class <GEOS class>     (the library: what it is for; or "for
                             <the shell's>": folder, up, document,
                             card, printer, trash)
  32 rows of 32 characters: '.' none (the paper or the desktop shows),
  'K' the ink (layer 1: the outline and the details), 'a'..'o' entries
  1-15 of the icons' palette row (Look 3's PAL below: palette row 12 on
  the shell's tile desktop)

The rules (check): every pixel '.', 'K' or a-o; 16 tiles at most (an
8 x 8 card of only '.' and 'K' needs no tile; equal cards, flipped or
not, one tile).

The small icons (DECISIONS V151): 16 x 16, for the list, the small
icons' view and the sidebar, each drawn again for 16 pixels with its own
simpler geometry (small_subjects: not a 2:1 reduction of the 32 x 32),
by the class of its large one ('app': any other program); 4 tiles at
most. Their record: the count and the keys (12 bytes each) at 0, icon i
at SM_AT + SM_LEN i: the tiles n, the map (4 bytes, as below), the ink
(16 rows of 2 bytes), 4 tiles of 32 bytes.

The packed icon (ICON_LEN = 658 bytes; docs/APPFORMAT.md "The colour
icon"):
  0        the tiles n (0-16)
  1        3 (the version)
  2-17     the map: card k (row by row, 4 x 4): bits 0-3 its tile, bit 4
           h flip, bit 5 v flip, bit 7 none (only '.' and 'K')
  18-145   the ink: 32 rows of 4 bytes, bit 7 the left pixel
  146-657  the tiles, 32 bytes each (4 bpp, the high nibble the left
           pixel; 0 transparent), unused ones 0

MIT licence (see LICENSE).
"""
import math
import os
import sys

N = 32
ICON_LEN = 658
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')

# the icons' palette row (Look 3, style A; light; dark mode halves it)
NAMES = ['white', 'pale', 'grey', 'dark', 'sky', 'blue', 'navy', 'yellow', 'amber', 'brown', 'red',
         'lgreen', 'green', 'lilac', 'purple']
PAL = [0xFFF, 0xDDE, 0x99A, 0x556, 0x9DF, 0x48D, 0x237, 0xFE5, 0xFA3, 0xA52, 0xE44, 0x9E6, 0x3A5, 0xC9F, 0x73C]
LETTERS = 'abcdefghijklmno'


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


def U(*fs):
    return lambda u, v: any(f(u, v) for f in fs)


def D(a, *bs):
    return lambda u, v: a(u, v) and not any(b(u, v) for b in bs)


def I(a, b):
    return lambda u, v: a(u, v) and b(u, v)


def rot(f, cx, cy, deg):
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    return lambda u, v: f(cx + (u - cx) * c + (v - cy) * s, cy - (u - cx) * s + (v - cy) * c)


def pix(rows, x0, y0):
    """a little pixel picture as a mask ('#' set) at unit x0, y0"""
    pts = set()
    for j, r in enumerate(rows):
        for i, ch in enumerate(r):
            if ch == '#':
                pts.add((x0 + i, y0 + j))
    return lambda u, v: (math.floor(u), math.floor(v)) in pts


def ARC(cx, cy, r0, r1, a0, a1):
    """(v2) a ring's part from angle a0 to a1 (degrees, counter-clockwise
    from 3 o'clock, y up as on paper)"""
    def f(u, v):
        d2 = (u - cx) ** 2 + (v - cy) ** 2
        if not (r0 * r0 <= d2 <= r1 * r1):
            return False
        a = math.degrees(math.atan2(cy - v, u - cx)) % 360
        return (a - a0) % 360 <= (a1 - a0) % 360
    return f


DIGIT = {'0': ['###', '#.#', '#.#', '#.#', '###'], '1': ['.#.', '##.', '.#.', '.#.', '###'],
         '2': ['###', '..#', '###', '#..', '###'], '3': ['###', '..#', '.##', '..#', '###']}


def num(s, x0, y0):
    """(v2) digits of 3 x 5 pixels, a column apart"""
    return U(*(pix(DIGIT[c], x0 + 4 * i, y0) for i, c in enumerate(s)))


HEART = ['.#.#.', '#####', '#####', '.###.', '..#..']
SPADE = ['..#..', '.###.', '#####', '#####', '..#..', '.###.']


class Ic:
    def __init__(self, name, cls=None, out=None):
        self.name, self.cls, self.out = name, cls, out
        self.shapes = []     # (mask, material, outline, shade)
        self.decals = []     # (mask, colour)

    def s(self, mask, mat, outline=True, shade='soft'):
        self.shapes.append((mask, mat, outline, shade))
        return self

    def d(self, mask, colour):
        self.decals.append((mask, colour))
        return self


# ------------------------------------------------------------------ the set
# out: 'app:<dir>' (apps/<dir>/icon.txt) or 'lib' (shell/icons3.txt, by
# its class; '*name' the shell's own)
def subjects():
    out = []

    def new(name, cls, where):
        ic = Ic(name, cls, where)
        out.append(ic)
        return ic

    # ---- the proposal's 19 (plans/look3/src/icons.py, style A)
    ic = new('Paint', 'Paint', 'app:paint')
    board = D(U(E(15, 18, 13, 10), E(20, 13, 8, 7)), E(9.5, 22, 2.6, 2.2))
    ic.s(board, 'wood')
    for (x, y, m) in ((9, 14, 'red'), (14.5, 11, 'blue'), (20.5, 11.5, 'green'), (23, 17.5, 'purple'), (16, 23.5, 'yellow')):
        ic.s(E(x, y, 2.6, 2.3), m)
    ic.s(L(29, 2.5, 19.5, 15, 3.2), 'red')
    ic.s(L(19.5, 15, 16.5, 19, 3.4), 'metal')
    ic.s(P((15, 17.2), (18.4, 20.2), (12.2, 25.5)), 'dark')

    # (V173) Colour Paint: a colour wheel of six, a brush across it
    ic = new('Colour Paint', 'ColourPaint', 'app:cpaint')
    for k, m in enumerate(('red', 'orange', 'yellow', 'green', 'blue', 'purple')):
        ic.s(ARC(14, 17, 0, 12.5, 60 + 60 * k, 120 + 60 * k), m, outline=False, shade='flat')
    ic.d(D(E(14, 17, 13.2, 13.2), E(14, 17, 12.4, 12.4)), 'K')
    ic.s(E(14, 17, 3.5, 3.5), 'paper')
    ic.s(L(30, 2, 21, 12, 3.2), 'wood')
    ic.s(L(21, 12, 18.5, 14.8, 3.4), 'metal')
    ic.s(P((17, 13.2), (20.2, 16.4), (14.5, 19.5)), 'dark')

    ic = new('Veranda Write', 'CmdrWrite', 'lib')
    ic.s(RR(5, 3, 19, 26, 1.2), 'paper')
    ic.d(R(8, 7, 11, 2), 'navy')
    for y, w in ((11, 13), (14, 12), (17, 13), (20, 9), (23, 11)):
        ic.d(R(8, y, w, 1), 'grey')
    ic.s(L(29.5, 3, 20, 17, 4.2), 'blue')
    ic.s(P((22.6, 15.6), (17.6, 18.8), (14, 26.5)), 'yellow')
    ic.d(L(18.6, 19.2, 15.4, 24.4, 0.9), 'K')

    ic = new('Veranda Calc', 'VCalc', 'lib')
    ic.s(RR(3, 4, 24, 23, 1), 'paper')
    ic.s(R(3, 4, 24, 4), 'green', outline=False, shade='flat')
    for x in (9, 15, 21):
        ic.d(R(x, 8, 1, 19), 'pale')
    for y in (12, 16, 20, 24):
        ic.d(R(4, y, 22, 1), 'pale')
    ic.s(R(17, 17, 4, 12), 'orange')
    ic.s(R(22, 11, 4, 18), 'blue')
    ic.s(R(27, 20, 4, 9), 'red')

    ic = new('Calendar', 'Calendar', 'app:calendar')
    ic.s(RR(4, 6, 24, 23, 2), 'paper')
    ic.s(R(4, 6, 24, 7), 'red', outline=False, shade='flat')
    ic.d(R(4, 13, 24, 1), 'K')
    ic.s(RR(9, 3, 3, 6, 1), 'metal')
    ic.s(RR(20, 3, 3, 6, 1), 'metal')
    ic.d(pix(['####.', '....#', '....#', '.###.', '#....', '#....', '#####'], 9, 16), 'K')
    ic.d(pix(['..#.', '.##.', '#.#.', '..#.', '..#.', '..#.', '####'], 17, 16), 'K')

    ic = new('Veranda Edit', 'VerandaEdit', 'app:edit')
    ic.s(RR(2, 5, 28, 22, 2), 'paper')
    ic.s(R(2, 5, 28, 5), 'purple', outline=False, shade='flat')
    ic.d(R(2, 10, 28, 1), 'K')
    ic.s(R(3, 11, 5, 15), 'pale', outline=False, shade='flat')
    for i, (x, w, c) in enumerate(((10, 9, 'purple'), (12, 12, 'blue'), (12, 7, 'green'), (10, 5, 'purple'), (12, 10, 'blue'))):
        ic.d(R(x, 13 + 3 * i, w, 1), c)
        ic.d(R(5, 13 + 3 * i, 2, 1), 'grey')
    ic.d(R(23, 18, 1, 5), 'red')
    for x in (5, 8, 11):
        ic.d(R(x, 7, 2, 1), 'white')

    ic = new('Veranda Gemini', 'VerandaGemi', 'app:gemini')   # (v2) a rocket with two portholes (Gemini: the twins)
    ic.s(P((10, 20), (4, 28), (5, 30), (11, 27)), 'red')
    ic.s(P((22, 20), (28, 28), (27, 30), (21, 27)), 'red')
    ic.s(P((12.5, 27), (19.5, 27), (16, 31.5)), 'orange', shade='flat')
    body = U(E(16, 13, 6, 11), R(10, 13, 12, 15))
    ic.s(body, 'paper', shade='round')
    ic.s(I(body, R(0, 0, 32, 7)), 'red', shade='round')
    ic.s(E(16, 12.5, 2.6, 2.6), 'sky')
    ic.s(E(16, 19.5, 2.6, 2.6), 'sky')
    ic.s(R(15, 29, 2, 2), 'yellow', outline=False, shade='flat')

    ic = new('Veranda Claude', 'VerandaClau', 'app:claude')   # (v2) a friendly robot's head
    ic.s(R(15, 4, 2, 6), 'metal')
    ic.s(E(16, 3.5, 2.5, 2.5), 'red', shade='round')
    ic.s(RR(1, 13, 5, 9, 1.5), 'metal')
    ic.s(RR(26, 13, 5, 9, 1.5), 'metal')
    ic.s(RR(4, 8, 24, 19, 5), 'orange', shade='round')
    ic.s(RR(7, 11, 18, 12, 3), 'paper')
    ic.d(E(12, 16, 2.1, 2.6), 'navy')
    ic.d(E(20, 16, 2.1, 2.6), 'navy')
    ic.d(R(11, 14, 1, 1), 'white')
    ic.d(R(19, 14, 1, 1), 'white')
    ic.d(pix(['#......#', '.######.'], 12, 19), 'K')

    ic = new('Veranda Ask', 'VerandaAsk', 'app:ask')     # (v2) a light bulb with a question in it
    ic.s(U(E(16, 11.5, 8.5, 8.5), P((11, 17), (21, 17), (19.5, 23.5), (12.5, 23.5))), 'yellow', shade='round')
    ic.d(pix(['.###.', '##.##', '...##', '..##.', '..##.', '.....', '..##.'], 14, 6), 'blue')
    ic.d(R(10, 7, 1, 3), 'white')
    ic.s(RR(12, 23, 8, 5, 1), 'metal')
    ic.d(R(12, 25, 8, 1), 'dark')
    ic.s(RR(14, 27.5, 4, 2.5, 1), 'dark')

    ic = new('Preferences', 'Preferences', 'app:prefs')
    ic.s(RR(3, 3, 26, 26, 3), 'metal')
    for x in (10, 16, 22):
        ic.d(R(x - 0.5, 7, 1, 19), 'K')
    ic.s(RR(6.5, 16, 7, 6, 1.5), 'red')
    ic.s(RR(12.5, 8, 7, 6, 1.5), 'yellow')
    ic.s(RR(18.5, 19, 7, 6, 1.5), 'blue')

    ic = new('Solitaire', 'Solitaire', 'lib')
    c1 = rot(RR(4, 6, 15, 21, 2), 11.5, 16.5, 12)
    c2 = rot(RR(13, 5, 15, 21, 2), 20.5, 15.5, -8)
    ic.s(c1, 'paper')
    ic.d(I(c1, pix(HEART, 7, 11)), 'red')
    ic.s(c2, 'paper')
    ic.d(pix(SPADE, 18, 12), 'K')
    ic.d(pix(['#', '#'], 16, 8), 'K')
    ic.d(pix(['#', '#'], 25, 21), 'K')

    ic = new('MOD Player', 'VModPlay', 'lib')          # (v2) two notes over a keyboard
    ic.s(RR(2, 20, 28, 10, 1), 'paper')
    for x in (6, 10, 14, 18, 22, 26):
        ic.d(R(x, 21, 1, 9), 'grey')
    for x in (5, 9, 17, 21, 25):
        ic.d(R(x, 20, 2, 5), 'dark')
    ic.s(U(E(12, 15, 3.6, 2.7), E(23, 12.5, 3.6, 2.7), R(13.6, 3, 2, 12), R(24.6, 1, 2, 11.5),
           P((13.6, 3), (26.6, 0.5), (26.6, 4), (13.6, 6.5))), 'lilac', shade='round')

    ic = new('Disk Tools', 'VerandaDisk', 'app:disktools')   # (v2) a card and a spanner
    ic.s(P((3, 3), (15, 3), (20, 8), (20, 29), (3, 29)), 'blue', shade='round')
    for x in (5, 8, 11):
        ic.d(R(x, 4, 2, 4), 'yellow')
    ic.s(R(5, 12, 12, 13), 'paper', shade='flat')
    for y, w in ((15, 8), (18, 6), (21, 7)):
        ic.d(R(7, y, w, 1), 'grey')
    ic.s(U(L(27.5, 12.5, 14.5, 28.5, 4), D(E(26.5, 10, 4.8, 4.8), E(29, 7.5, 2.8, 2.8))), 'metal', shade='round')

    ic = new('Veranda Update', 'VerandaUpd', 'app:update')   # (v2) two arrows going round, a download in the middle
    def head(a0, a1):           # an arrowhead from the ring's angle a0 to its tip at a1
        p = lambda a, r: (16 + r * math.cos(math.radians(a)), 16 - r * math.sin(math.radians(a)))
        return P(p(a0, 4.3), p(a0, 15), p(a1, 9.65))
    ic.s(U(ARC(16, 16, 7.5, 11.8, 35, 172), head(35, 2)), 'green', shade='round')
    ic.s(U(ARC(16, 16, 7.5, 11.8, 215, 352), head(215, 182)), 'green', shade='round')
    ic.s(P((14, 10), (18, 10), (18, 15), (21, 15), (16, 21), (11, 15), (14, 15)), 'blue', shade='round')

    ic = new('About this X16', 'VerandaAbout', 'app:about')
    ic.s(RR(3, 3, 26, 19, 2), 'metal')
    ic.s(R(6, 6, 20, 13), 'screen', outline=True, shade='flat')
    ic.d(pix(['#...#', '#...#', '.#.#.', '.#.#.', '..#..'], 14, 9), 'white')
    ic.s(P((5, 24), (27, 24), (30, 29), (2, 29)), 'metal')
    for x in range(7, 26, 3):
        ic.d(R(x, 26, 2, 1), 'grey')

    ic = new('Document', '*Document', 'lib')
    ic.s(P((6, 2), (19, 2), (26, 9), (26, 30), (6, 30)), 'paper')
    ic.s(P((19, 2), (19, 9), (26, 9)), 'metal')
    ic.d(R(9, 6, 7, 2), 'dark')
    for y, w in ((13, 15), (16, 13), (19, 15), (22, 11), (25, 14)):
        ic.d(R(9, y, w, 1), 'grey')

    ic = new('Folder', '*Folder', 'lib')
    ic.s(U(RR(2, 7, 28, 21, 2), RR(2, 4, 12, 6, 1.5)), 'amber')
    ic.s(RR(2, 11.5, 28, 16.5, 1.5), 'yellow')

    ic = new('SD card', '*SD card', 'lib')
    card = P((7, 2), (21, 2), (26, 7), (26, 30), (7, 30))
    ic.s(card, 'navy')
    for x in (9, 12, 15, 18):
        ic.d(R(x, 3, 2, 5), 'yellow')
    ic.s(R(9, 12, 15, 15), 'paper', outline=False, shade='flat')
    ic.d(pix(['.##..###.', '#....#..#', '.#...#..#', '..#..#..#', '##...###.'], 12, 17), 'blue')

    ic = new('Printer', '*Printer', 'lib')
    ic.s(R(9, 3, 14, 11), 'paper')
    for y in (6, 8, 10):
        ic.d(R(11, y, 10, 1), 'grey')
    ic.s(RR(3, 12, 26, 11, 2), 'metal')
    ic.d(R(7, 16, 18, 1), 'dark')
    ic.d(R(24, 19, 2, 1), 'green')
    ic.s(P((6, 22), (26, 22), (28.5, 29), (3.5, 29)), 'paper')
    ic.d(R(9, 25, 12, 1), 'grey')

    ic = new('Trash', '*Trash', 'lib')
    ic.s(D(RR(12, 2, 8, 4, 1), R(14, 4, 4, 3)), 'metal')
    ic.s(P((7, 9), (25, 9), (23, 30), (9, 30)), 'metal')
    ic.s(RR(5, 6, 22, 4, 1), 'metal')
    for x in (12, 16, 20):
        ic.d(L(x, 13, x - (x - 16) * 0.12, 27, 1.1), 'dark')

    # ---- the rest, drawn the same way (V133)
    ic = new('Up', '*Up', 'lib')          # "..": a folder with an arrow up
    ic.s(U(RR(2, 7, 28, 21, 2), RR(2, 4, 12, 6, 1.5)), 'amber')
    ic.s(RR(2, 11.5, 28, 16.5, 1.5), 'yellow')
    ic.s(U(P((16, 12), (23, 19), (19, 19), (19, 25), (13, 25), (13, 19), (9, 19))), 'blue')

    ic = new('Archive', 'Archive', 'app:archive')     # a parcel, tied
    ic.s(R(4, 12, 24, 17), 'wood')
    ic.s(P((2, 12), (30, 12), (27, 6), (5, 6)), 'orange')
    ic.d(R(14, 6, 4, 23), 'paper')
    ic.d(R(4, 19, 24, 2), 'paper')
    ic.s(E(16, 6, 4, 2.4), 'paper')

    ic = new('Calculator', 'Calculator', 'app:calc')
    ic.s(RR(6, 2, 20, 28, 2), 'metal')
    ic.s(R(9, 5, 14, 6), 'lgreen', outline=True, shade='flat')
    ic.d(pix(['.##.###', '#.#...#', '..#..#.', '..#..#.', '.###.#.'], 14, 6), 'dark')
    for j in range(3):
        for i in range(3):
            ic.s(R(9 + 5 * i, 14 + 5 * j, 4, 3), 'paper')
    ic.s(R(9, 29 - 4 - 1, 9, 3), 'paper')
    ic.s(R(19, 24, 4, 3), 'orange')

    ic = new('Dex', 'Dex', 'app:dex')                 # a card index
    ic.s(P((3, 16), (29, 16), (27, 29), (5, 29)), 'blue')
    ic.s(R(6, 6, 20, 14), 'paper')
    ic.s(R(9, 3, 8, 4), 'yellow')
    for y in (10, 13, 16):
        ic.d(R(9, y, 14, 1), 'grey')
    ic.s(R(5, 18, 22, 3), 'pale', outline=False, shade='flat')
    ic.d(R(14, 22, 4, 4), 'navy')

    ic = new('Font Editor', 'Font Editor', 'app:fonted')   # a big A on a grid sheet
    ic.s(RR(3, 3, 26, 26, 1), 'paper')
    big = U(P((14, 6), (18, 6), (26, 26), (21, 26), (16, 12), (11, 26), (6, 26)), R(11, 18, 10, 3))
    for k in range(8, 28, 6):
        ic.d(D(R(k, 4, 1, 24), big), 'pale')
        ic.d(D(R(4, k, 24, 1), big), 'pale')
    ic.s(big, 'navy')
    ic.s(L(28, 10, 22, 22, 2.6), 'red')

    ic = new('Note Pad', 'Note Pad', 'app:notepad')
    ic.s(R(6, 6, 20, 24), 'yellow')
    ic.s(R(6, 3, 20, 4), 'red')
    for y in (12, 16, 20, 24):
        ic.d(R(9, y, 14, 1), 'amber')
    ic.s(L(27, 8, 17, 26, 2.6), 'blue')
    ic.s(P((16, 24.5), (18.7, 26.2), (15.2, 29)), 'paper')

    ic = new('Term', 'VerandaTerm', 'app:term')        # (v2) a terminal and its prompt
    ic.s(RR(2, 4, 28, 22, 2), 'metal')
    ic.s(R(5, 7, 22, 15), 'navy', shade='flat')
    ic.d(U(L(8.5, 9.5, 11.5, 12, 1.5), L(11.5, 12, 8.5, 14.5, 1.5)), 'lgreen')
    ic.d(R(14, 13, 5, 2), 'lgreen')
    ic.s(R(10, 26, 12, 4), 'metal')

    ic = new('View', 'View', 'app:view')               # a framed picture
    ic.s(R(2, 5, 28, 22), 'wood')
    ic.s(R(5, 8, 22, 16), 'sky', outline=True, shade='flat')
    ic.d(I(R(5, 8, 22, 16), U(E(11, 26, 9, 7), E(23, 27, 8, 6))), 'green')
    ic.d(E(21, 12, 2.5, 2.5), 'yellow')

    ic = new('Veranda FTP', 'VerandaFTP', 'app:ftp')   # (v2) a folder, an arrow up and an arrow down
    ic.s(U(RR(1, 8, 21, 19, 2), RR(1, 5, 10, 5, 1.5)), 'amber')
    ic.s(RR(1, 12, 21, 15, 1.5), 'yellow')
    ic.s(P((19, 9), (23.5, 15), (21, 15), (21, 29), (17, 29), (17, 15), (14.5, 15)), 'green', shade='round')
    ic.s(P((27, 30), (31.5, 24), (29, 24), (29, 10), (25, 10), (25, 24), (22.5, 24)), 'blue', shade='round')

    ic = new('Veranda Gopher', 'VerandaGoph', 'app:gopher')   # (v2) a gopher looking out of its burrow
    ic.s(E(16, 26.5, 15, 4.5), 'wood')
    ic.s(E(8.5, 9.5, 2.2, 2.4), 'orange')
    ic.s(E(23.5, 9.5, 2.2, 2.4), 'orange')
    ic.s(U(E(16, 12, 7.5, 9), R(8.5, 12, 15, 13)), 'orange', shade='round')
    ic.s(E(16, 17.5, 5, 3.4), 'yellow', outline=False, shade='flat')
    ic.d(R(12, 9, 2, 3), 'K')
    ic.d(R(18, 9, 2, 3), 'K')
    ic.d(R(12, 9, 1, 1), 'white')
    ic.d(R(18, 9, 1, 1), 'white')
    ic.d(R(15, 14.5, 2, 2), 'K')
    ic.d(R(14, 18, 4, 3), 'white')
    ic.d(R(14, 17, 4, 1), 'K')

    ic.s(D(E(16, 28, 14, 3.5), R(0, 0, 32, 24.5)), 'wood')
    ic.s(RR(9, 22, 5, 3, 1), 'yellow')
    ic.s(RR(18, 22, 5, 3, 1), 'yellow')

    ic = new('Veranda Chat', 'VerandaChat', 'app:irc')  # two speech bubbles
    ic.s(U(RR(2, 3, 19, 13, 4), P((6, 14), (4, 20), (12, 15))), 'lgreen', shade='round')
    ic.s(U(RR(10, 12, 20, 13, 4), P((24, 23), (28, 30), (18, 24))), 'sky', shade='round')
    ic.d(pix(['.#.#.', '#####', '.#.#.', '#####', '.#.#.'], 8, 6), 'green')
    ic.d(R(14, 16, 12, 1), 'navy')
    ic.d(R(14, 19, 8, 1), 'navy')

    # (v2) VeraBASIC, the editor (class VBEdit, apps/vbasic/ide: no icon of
    # its own, so the library's): a listing on a navy panel and a big B;
    # VeraBASIC Run (class VBRun, apps/vbasic) the same panel and a play
    # button, its file's own icon and the library's (before v2 the Run
    # file carried the editor's B badge)
    ic = new('VeraBASIC', 'VBEdit', 'lib')
    ic.s(RR(1, 2, 21, 20, 2), 'navy')
    for i, (n, w) in enumerate((('10', 8), ('20', 6), ('30', 3))):
        ic.d(num(n, 3, 4 + 6 * i), 'yellow')
        ic.d(R(11, 6 + 6 * i, w, 1), 'sky')
    ic.s(pix(['#########...',
              '##########..',
              '###....####.',
              '###.....###.',
              '###....####.',
              '#########...',
              '##########..',
              '###.....####',
              '###......###',
              '###......###',
              '###.....####',
              '###########.',
              '##########..'], 17, 16), 'red', shade='flat')

    ic = new('VeraBASIC Run', 'VBRun', 'lib')
    ic.s(RR(1, 2, 21, 20, 2), 'navy')
    for i, (n, w) in enumerate((('10', 8), ('20', 6), ('30', 3))):
        ic.d(num(n, 3, 4 + 6 * i), 'yellow')
        ic.d(R(11, 6 + 6 * i, w, 1), 'sky')
    ic.s(E(23, 23, 7, 7), 'green', shade='round')
    ic.d(P((20.5, 19), (28, 23), (20.5, 27)), 'white')
    ic2 = new('VeraBASIC Run', 'VBRun', 'app:vbasic')   # its file's own: the same
    ic2.shapes, ic2.decals = ic.shapes, ic.decals

    ic = new('Veranda Setup', 'VSetup', 'app:setup')    # (v2) a card and an arrow going in
    ic.s(P((8, 11), (19, 11), (24, 16), (24, 30), (8, 30)), 'navy', shade='round')
    for x in (10, 13, 16):
        ic.d(R(x, 12, 2, 4), 'yellow')
    ic.s(R(10, 18, 12, 10), 'paper', shade='flat')
    ic.d(pix(['#...#', '#...#', '.#.#.', '.#.#.', '..#..'], 14, 20), 'blue')
    ic.s(P((13, 1), (19, 1), (19, 6), (23, 6), (16, 13), (9, 6), (13, 6)), 'green', shade='round')

    ic = new('Photo Manager', 'PhotoManager', 'lib')   # (v2) a photo album, a photo in front
    ic.s(RR(3, 3, 19, 24, 1), 'blue', shade='round')
    ic.s(R(3, 3, 4, 24), 'navy', outline=False)
    for y in (7, 14, 21):
        ic.d(R(4, y, 2, 2), 'yellow')
    ph = rot(R(10, 11, 19, 15), 20, 19, -10)
    ic.s(ph, 'paper')
    pic = rot(R(12, 13, 15, 11), 20, 19, -10)
    ic.s(pic, 'sky', shade='flat')
    ic.d(I(pic, E(17, 28, 11, 6.5)), 'green')
    ic.d(I(pic, E(23.5, 16, 1.8, 1.8)), 'yellow')

    ic = new('Text Manager', 'Text Manager', 'lib')   # (v2) a scrapbook of texts, a page in front
    ic.s(RR(3, 3, 19, 24, 1), 'green', shade='round')
    ic.s(R(3, 3, 4, 24), 'navy', outline=False)
    for y in (7, 14, 21):
        ic.d(R(4, y, 2, 2), 'yellow')
    ic.s(R(12, 9, 17, 21), 'paper')
    ic.d(pix(['.#.', '#.#', '###', '#.#', '#.#'], 15, 12), 'red')
    ic.d(R(20, 14, 6, 1), 'grey')
    for y, w in ((18, 12), (21, 10), (24, 12), (27, 8)):
        ic.d(R(15, y, w, 1), 'grey')

    ic = new('Wikipedia', 'GeminiStart', 'lib')        # (v2) encyclopaedia volumes on a shelf (Veranda Gemini's launcher document)
    for x, y, w, m in ((3, 10, 6, 'red'), (9, 5, 7, 'blue'), (16, 8, 6, 'green')):
        ic.s(R(x, y, w, 27 - y), m, shade='round')
        ic.d(R(x, y + 2, w, 1), 'yellow')
        ic.d(R(x, 24, w, 1), 'yellow')
        ic.d(R(x + 1, y + 5, w - 2, 3), 'paper')
    lean = rot(R(22, 10, 6, 18), 22, 27, -14)
    ic.s(lean, 'orange', shade='round')
    ic.d(I(lean, rot(R(22, 12, 6, 1), 22, 27, -14)), 'brown')
    ic.s(R(1, 27, 30, 3), 'wood')

    ic = new('Bird Watch', 'BirdWatch', 'lib')
    ic.s(L(2, 27, 30, 23, 2.6), 'wood')
    ic.s(U(E(14, 16, 9, 7), E(21, 10, 5, 5), P((6, 15), (1, 21), (8, 19))), 'blue')
    ic.s(P((25, 9), (31, 11), (25, 12)), 'yellow')
    ic.d(E(21.5, 9, 1, 1), 'K')
    ic.s(E(12, 17, 5, 3), 'sky', outline=False, shade='flat')
    ic.d(R(15, 22, 1, 4), 'dark')
    ic.d(R(18, 22, 1, 3), 'dark')

    ic = new('Lighthouse Pinball', 'Lighthouse', 'lib')
    tower = P((12, 9), (20, 9), (23, 29), (9, 29))
    ic.s(tower, 'paper')
    ic.d(I(tower, U(R(0, 13, 32, 4), R(0, 21, 32, 4))), 'red')
    ic.s(R(11, 4, 10, 6), 'yellow')
    ic.s(P((10, 4), (16, 0), (22, 4)), 'red')
    ic.s(E(26, 23, 4, 4), 'metal')
    ic.d(E(25, 22, 1.2, 1.2), 'white')

    ic = new('Harbour Walls', 'HarbourWalls', 'lib')   # (v2) a sandstone harbour wall over the sea
    ic.s(R(2, 4, 28, 17), 'orange')
    for j, y in enumerate((8, 12, 16)):
        ic.d(R(2, y, 28, 1), 'brown')
        for x in range(4 + (j & 1) * 4, 30, 8):
            ic.d(R(x, y - 3, 1, 3), 'brown')
    ic.d(R(2, 19, 28, 1), 'brown')
    ic.s(R(1, 21, 30, 9), 'blue', outline=True, shade='flat')
    ic.d(pix(['.##.....##.....##.', '#..#...#..#...#..#'], 3, 24), 'white')

    ic = new('geoWrite', 'geoWrite', 'lib')            # a page and a pencil
    ic.s(P((5, 3), (19, 3), (25, 9), (25, 29), (5, 29)), 'paper')
    for y, w in ((10, 15), (13, 12), (16, 15), (19, 10), (22, 13)):
        ic.d(R(8, y, w, 1), 'grey')
    ic.s(L(29, 12, 17, 28, 3.6), 'yellow')
    ic.s(L(29, 12, 27, 14.7, 3.6), 'red')
    ic.s(P((17.6, 25.8), (19.9, 27.6), (15.5, 30.5)), 'orange')

    # (V156) a Veranda Write document (geoWrite's documents' class: Veranda
    # Write opens them, V135; the shell also gives it to its .cwr files): the
    # document's page with Veranda Write's navy heading and its blue pen
    ic = new('Veranda Write document', 'Write Image', 'lib')
    ic.s(P((5, 2), (18, 2), (25, 9), (25, 30), (5, 30)), 'paper')
    ic.s(P((18, 2), (18, 9), (25, 9)), 'pale')
    ic.d(R(8, 6, 8, 2), 'navy')
    for y, w in ((12, 14), (15, 12), (18, 14), (21, 8)):
        ic.d(R(8, y, w, 1), 'grey')
    ic.s(L(30, 14, 22.5, 25, 3.6), 'blue')
    ic.s(P((24.4, 23.4), (20.6, 26.2), (18.5, 30.5)), 'yellow')

    # (V173) a Colour Paint picture (class PaintColour): the page with a
    # picture on it, a sky, the sun and a green hill
    ic = new('Colour Paint picture', 'PaintColour', 'lib')
    ic.s(P((5, 2), (18, 2), (25, 9), (25, 30), (5, 30)), 'paper')
    ic.s(P((18, 2), (18, 9), (25, 9)), 'pale')
    ic.s(R(8, 11, 14, 15), 'sky', outline=True, shade='flat')
    ic.d(E(18, 15, 2.2, 2.2), 'yellow')
    ic.d(I(R(8.5, 11, 13, 15), E(11, 27, 9, 6)), 'green')
    ic.d(I(R(8.5, 11, 13, 15), E(21, 28, 6, 5)), 'lgreen')

    # (V197) an X16 program (a plain .PRG, which BASIC runs): BASIC's
    # screen, its lines and cursor, and a play mark; TopDesk's gave it its
    # room (24 at most; TopDesk is not in the package: V173's small one)
    ic = new('X16 program', '*Prg', 'lib')
    ic.s(RR(2, 3, 28, 22, 2), 'metal')
    ic.s(R(4, 5, 24, 17), 'navy', outline=True, shade='flat')
    ic.d(R(6, 8, 13, 1), 'sky')
    ic.d(R(6, 11, 9, 1), 'sky')
    ic.d(R(6, 14, 2, 3), 'white')
    ic.s(P((18, 16), (30, 23), (18, 30)), 'yellow')

    ic = new('geoChess', 'GeoChess', 'lib')            # two pawns
    for (cx, mat) in ((11, 'paper'), (21, 'dark')):
        ic.s(U(E(cx, 10, 3.6, 3.6), P((cx - 2.5, 13), (cx + 2.5, 13), (cx + 4.5, 25), (cx - 4.5, 25)),
               RR(cx - 7, 25, 14, 4, 1)), mat)

    ic = new('SID Player', 'VSidPlay', 'lib')          # (v2) a chip, its pins, a bright note
    ic.s(RR(3, 8, 25, 20, 1), 'dark', shade='round')
    for x in (5, 10, 15, 20, 25):
        ic.d(R(x, 8, 2, 2), 'pale')
        ic.d(R(x, 26, 2, 2), 'pale')
    ic.d(E(7, 13, 1.3, 1.3), 'grey')
    ic.d(R(6, 21, 9, 1), 'grey')
    ic.s(U(E(18.5, 22.5, 4.2, 3.2), R(20.8, 9, 2.2, 13.5), P((20.8, 9), (28.5, 12), (28.5, 16.5), (20.8, 13.5))), 'yellow', shade='round')
    return out


# ------------------------------------------------------------------ the small set
# (DECISIONS V151) 16 x 16 icons for the list, the small icons' view and the
# sidebar: each drawn again for 16 pixels (its own simpler geometry in a
# 16-unit space, the same style and palette; not a 2:1 reduction of the 32),
# by the class of its 32 x 32 one; '*App' any other program.
NS = 16


def small_subjects():
    out = []

    def new(name, cls):
        ic = Ic(name, cls, 'small')
        out.append(ic)
        return ic

    def folder(ic):
        ic.s(U(RR(1, 1.5, 6, 3, 0.6), RR(1, 3, 14, 11, 1)), 'amber')
        ic.s(RR(1, 6, 14, 8, 0.6), 'yellow')

    def card(ic):
        ic.s(P((3, 1), (10, 1), (13, 4), (13, 15), (3, 15)), 'navy')
        for x in (5, 7, 9):
            ic.d(R(x, 2, 1, 2), 'yellow')
        ic.s(R(5, 7, 6, 6), 'paper', outline=False, shade='flat')

    def page(ic, lines=((5, 5), (5, 7), (5, 9), (5, 11)), w=6):
        ic.s(P((3, 1), (10, 1), (13, 4), (13, 15), (3, 15)), 'paper')
        ic.s(P((10, 1), (10, 4), (13, 4)), 'pale')
        for x, y in lines:
            ic.d(R(x, y, w, 1), 'grey')

    def screen(ic, mat='screen'):
        ic.s(RR(1, 1, 14, 10, 1), 'metal')
        ic.s(R(3, 3, 10, 6), mat, outline=True, shade='flat')
        ic.s(P((3, 12), (13, 12), (14.5, 15), (1.5, 15)), 'metal')

    # the shell's own
    ic = new('Folder', '*Folder')
    folder(ic)
    ic = new('Up', '*Up')
    folder(ic)
    ic.s(P((8, 6.5), (11.5, 10), (9.5, 10), (9.5, 13), (6.5, 13), (6.5, 10), (4.5, 10)), 'blue', outline=False, shade='flat')
    ic = new('Document', '*Document')
    page(ic)
    ic = new('SD card', '*SD card')
    card(ic)
    ic.d(pix(['.#.##.', '#..#.#', '.#.#.#', '#..##.'], 5, 8), 'blue')
    ic = new('Printer', '*Printer')
    ic.s(R(4, 1, 8, 5), 'paper')
    ic.d(R(5, 3, 6, 1), 'grey')
    ic.s(RR(1, 5, 14, 6, 1), 'metal')
    ic.d(R(11, 7, 2, 1), 'green')
    ic.s(P((3, 11), (13, 11), (14.5, 15), (1.5, 15)), 'paper')
    ic = new('Trash', '*Trash')
    ic.s(D(RR(6, 0.5, 4, 2.5, 0.5), R(7, 2, 2, 2)), 'metal')
    ic.s(P((3, 4.5), (13, 4.5), (12, 15), (4, 15)), 'metal')
    ic.s(R(2, 3, 12, 2), 'metal')
    for x in (6, 8, 10):
        ic.d(R(x, 7, 1, 6), 'dark')
    ic = new('Program', '*App')
    ic.s(RR(1, 2, 14, 12, 1), 'paper')
    ic.s(R(1, 2, 14, 3), 'blue', outline=False, shade='flat')
    ic.d(R(1, 5, 14, 1), 'K')
    ic.d(R(3, 3, 1, 1), 'white')
    ic.d(R(3, 8, 5, 1), 'grey')
    ic.d(R(3, 10, 8, 1), 'grey')

    # the programs
    ic = new('Paint', 'Paint')
    ic.s(D(U(E(7.5, 9, 6.5, 5), E(10, 6.5, 4, 3.5)), E(4.5, 11, 1.3, 1.1)), 'wood')
    for (x, y, m) in ((4, 7, 'red'), (7, 5, 'blue'), (10, 6, 'green'), (11, 9, 'purple'), (7, 11, 'yellow')):
        ic.d(R(x, y, 2, 2), m)
    ic.s(L(15, 1, 9.5, 7.5, 1.8), 'red')
    ic = new('Colour Paint', 'ColourPaint')        # (V173)
    for k, m in enumerate(('red', 'orange', 'yellow', 'green', 'blue', 'purple')):
        ic.s(ARC(7.5, 8.5, 0, 6.5, 60 + 60 * k, 120 + 60 * k), m, outline=False, shade='flat')
    ic.d(D(E(7.5, 8.5, 7.2, 7.2), E(7.5, 8.5, 6.4, 6.4)), 'K')
    ic.s(L(15.5, 0.5, 9, 7, 1.8), 'wood')
    ic = new('Veranda Write', 'CmdrWrite')
    ic.s(R(2, 1, 9, 14), 'paper')
    ic.d(R(4, 3, 5, 1), 'navy')
    for y in (6, 8, 10, 12):
        ic.d(R(4, y, 5, 1), 'grey')
    ic.s(L(14.5, 1.5, 9.5, 9.5, 2.4), 'blue')
    ic.s(P((10.6, 9.6), (8.4, 8.2), (7.5, 12.5)), 'yellow', outline=False, shade='flat')
    ic = new('Veranda Calc', 'VCalc')
    ic.s(R(1, 2, 11, 11), 'paper')
    ic.s(R(1, 2, 11, 2), 'green', outline=False, shade='flat')
    for x in (4, 7):
        ic.d(R(x, 4, 1, 9), 'pale')
    for y in (6, 9):
        ic.d(R(1, y, 11, 1), 'pale')
    ic.s(R(9, 8, 2, 7), 'orange')
    ic.s(R(12, 5, 2, 10), 'blue')
    ic = new('Calendar', 'Calendar')
    ic.s(RR(1, 3, 14, 12, 1), 'paper')
    ic.s(R(1, 3, 14, 3), 'red', outline=False, shade='flat')
    ic.d(R(1, 6, 14, 1), 'K')
    ic.s(R(4, 1, 1, 3), 'metal', outline=False, shade='flat')
    ic.s(R(11, 1, 1, 3), 'metal', outline=False, shade='flat')
    ic.d(pix(['###..#.', '..#.##.', '###..#.', '#....#.', '###.###'], 4, 8), 'K')
    ic = new('Veranda Edit', 'VerandaEdit')
    ic.s(RR(1, 2, 14, 12, 1), 'paper')
    ic.s(R(1, 2, 14, 3), 'purple', outline=False, shade='flat')
    ic.d(R(1, 5, 14, 1), 'K')
    for i, (x, w, c) in enumerate(((3, 5, 'purple'), (4, 7, 'blue'), (4, 4, 'green'), (3, 6, 'purple'))):
        ic.d(R(x, 7 + 2 * i, w, 1), c)
    ic = new('Veranda Gemini', 'VerandaGemi')
    ic.s(P((5, 9), (2, 13.5), (5.5, 12.5)), 'red', shade='flat')
    ic.s(P((11, 9), (14, 13.5), (10.5, 12.5)), 'red', shade='flat')
    ic.s(P((6, 13), (10, 13), (8, 16)), 'orange', outline=False, shade='flat')
    body = U(E(8, 5.5, 3, 5), R(5, 6, 6, 7))
    ic.s(body, 'paper', shade='round')
    ic.s(I(body, R(0, 0, 16, 3)), 'red', shade='flat')
    ic.d(R(7, 5, 2, 2), 'blue')
    ic.d(R(7, 8, 2, 2), 'blue')
    ic = new('Veranda Claude', 'VerandaClau')
    ic.s(R(7, 2, 2, 3), 'metal', outline=False, shade='flat')
    ic.s(R(7, 0.5, 2, 2), 'red', shade='flat')
    ic.s(R(0.5, 7, 2, 4), 'metal')
    ic.s(R(13.5, 7, 2, 4), 'metal')
    ic.s(RR(2, 4, 12, 10, 2.5), 'orange', shade='round')
    ic.s(R(4, 6, 8, 6), 'paper', shade='flat')
    ic.d(R(5, 7, 2, 2), 'navy')
    ic.d(R(9, 7, 2, 2), 'navy')
    ic.d(R(6, 10, 4, 1), 'K')
    ic = new('Veranda Ask', 'VerandaAsk')
    ic.s(U(E(8, 6, 4.8, 4.8), P((5.5, 9), (10.5, 9), (9.8, 12), (6.2, 12))), 'yellow', shade='round')
    ic.d(pix(['##.', '..#', '.#.', '...', '.#.'], 7, 3), 'blue')
    ic.s(R(6, 12, 4, 3), 'metal')
    ic = new('Preferences', 'Preferences')
    ic.s(RR(1, 1, 14, 14, 1.5), 'metal')
    for x in (4, 8, 12):
        ic.d(R(x, 3, 1, 10), 'K')
    ic.d(R(3, 8, 3, 2), 'red')
    ic.d(R(7, 4, 3, 2), 'yellow')
    ic.d(R(11, 10, 3, 2), 'blue')
    ic = new('Solitaire', 'Solitaire')
    ic.s(RR(1, 2, 8, 11, 1), 'paper')
    ic.d(pix(['#.#', '###', '.#.'], 3, 4), 'red')
    ic.s(RR(6, 4, 8, 11, 1), 'paper')
    ic.d(pix(['.#.', '###', '###', '.#.'], 9, 8), 'K')
    ic = new('MOD Player', 'VModPlay')
    ic.s(R(1, 10, 14, 5), 'paper')
    for x in (3, 6, 10, 13):
        ic.d(R(x, 10, 1, 3), 'dark')
    ic.s(U(E(5, 7.5, 2, 1.5), E(11, 6.5, 2, 1.5), R(6.2, 1.5, 1.2, 6), R(12.2, 0.5, 1.2, 6),
           P((6.2, 1.5), (13.4, 0.5), (13.4, 2.5), (6.2, 3.5))), 'lilac', shade='flat')
    ic = new('Disk Tools', 'VerandaDisk')
    ic.s(P((2, 1), (8, 1), (11, 4), (11, 15), (2, 15)), 'blue')
    for x in (3, 5, 7):
        ic.d(R(x, 2, 1, 2), 'yellow')
    ic.s(R(4, 7, 5, 5), 'paper', outline=False, shade='flat')
    ic.s(U(L(14.5, 7, 9, 14, 2), D(E(13.5, 6, 2.4, 2.4), E(15, 4.5, 1.3, 1.3))), 'metal')
    ic = new('Veranda Update', 'VerandaUpd')
    def head(a0, a1):
        p = lambda a, r: (8 + r * math.cos(math.radians(a)), 8 - r * math.sin(math.radians(a)))
        return P(p(a0, 2.5), p(a0, 9.5), p(a1, 6))
    ic.s(U(ARC(8, 8, 4, 7.5, 50, 170), head(50, 12)), 'green', shade='flat')
    ic.s(U(ARC(8, 8, 4, 7.5, 230, 350), head(230, 192)), 'green', shade='flat')
    ic.s(P((7, 4.5), (9, 4.5), (9, 8), (10.5, 8), (8, 11), (5.5, 8), (7, 8)), 'blue', outline=False, shade='flat')
    ic = new('About this X16', 'VerandaAbout')
    screen(ic)
    ic.d(pix(['#...#', '.#.#.', '..#..'], 6, 4), 'white')
    ic = new('Archive', 'Archive')
    ic.s(R(2, 6, 12, 9), 'wood')
    ic.s(R(1, 3, 14, 4), 'orange')
    ic.d(R(7, 3, 2, 12), 'paper')
    ic.d(pix(['#..#', '.##.'], 6, 1), 'K')
    ic = new('Calculator', 'Calculator')
    ic.s(RR(3, 1, 10, 14, 1), 'dark')
    ic.s(R(5, 3, 6, 3), 'lgreen', outline=False, shade='flat')
    for y in (8, 10, 12):
        for x in (5, 7, 9):
            ic.d(R(x, y, 1, 1), 'pale')
    ic.d(R(10, 10, 1, 3), 'amber')
    ic = new('Dex', 'Dex')
    ic.s(R(2, 2, 12, 6), 'paper')
    ic.d(R(4, 4, 6, 1), 'grey')
    ic.s(P((1, 7), (15, 7), (14, 15), (2, 15)), 'blue')
    ic.d(R(6, 10, 4, 2), 'navy')
    ic = new('Font Editor', 'Font Editor')
    ic.s(R(1, 1, 14, 14), 'paper')
    for k in (4, 8, 12):
        ic.d(R(k, 1, 1, 14), 'pale')
        ic.d(R(1, k, 14, 1), 'pale')
    ic.s(P((3, 14), (7, 2.5), (9, 2.5), (13, 14), (10.5, 14), (9.5, 11), (6.5, 11), (5.5, 14)), 'navy',
         outline=False, shade='flat')
    ic.d(R(7, 8, 2, 1), 'paper')
    ic = new('Note Pad', 'Note Pad')
    ic.s(R(2, 2, 11, 13), 'yellow')
    ic.s(R(2, 1, 11, 2), 'red', outline=False, shade='flat')
    for y in (6, 9, 12):
        ic.d(R(3, y, 9, 1), 'amber')
    ic.s(L(14.5, 4, 9, 13, 1.8), 'blue')
    ic = new('Term', 'VerandaTerm')
    screen(ic, 'navy')
    ic.d(pix(['#..', '.#.', '#..'], 4, 4), 'lgreen')
    ic.d(R(8, 6, 3, 1), 'lgreen')
    ic = new('View', 'View')
    ic.s(R(1, 2, 14, 12), 'wood')
    ic.s(R(3, 4, 10, 8), 'sky', outline=True, shade='flat')
    ic.d(I(R(3, 4, 10, 8), U(E(6, 12, 4, 2.5), E(11, 12.5, 3, 2))), 'green')
    ic.d(R(10, 5, 2, 2), 'yellow')
    ic = new('Veranda FTP', 'VerandaFTP')
    ic.s(U(RR(1, 4.5, 5, 3, 0.6), RR(1, 5.5, 10, 9.5, 1)), 'amber')
    ic.s(RR(1, 8, 10, 7, 0.6), 'yellow')
    ic.s(P((13, 0.5), (15.5, 3.5), (14, 3.5), (14, 7), (12, 7), (12, 3.5), (10.5, 3.5)), 'green', outline=False, shade='flat')
    ic.s(P((13, 15.5), (15.5, 12.5), (14, 12.5), (14, 9), (12, 9), (12, 12.5), (10.5, 12.5)), 'blue', outline=False, shade='flat')
    ic = new('Veranda Gopher', 'VerandaGoph')
    ic.s(E(8, 13.5, 7.5, 2.2), 'wood')
    ic.s(U(E(8, 7.5, 5, 5), E(4, 3.5, 1.6, 1.6), E(12, 3.5, 1.6, 1.6)), 'amber', shade='flat')
    ic.d(R(5, 6, 1, 2), 'K')
    ic.d(R(10, 6, 1, 2), 'K')
    ic.d(R(7, 8, 2, 1), 'K')
    ic.d(R(7, 10, 2, 2), 'white')
    ic = new('Veranda Chat', 'VerandaChat')
    ic.s(U(RR(1, 1, 9, 6, 2), P((2, 6), (2, 9), (5, 6))), 'lgreen')
    ic.s(U(RR(5, 6, 10, 7, 2), P((13, 12), (14, 15.5), (10, 12))), 'sky')
    for x in (7, 9, 11):
        ic.d(R(x, 9, 1, 1), 'navy')
    ic = new('VeraBASIC', 'VBEdit')
    ic.s(RR(0.5, 1, 11, 9, 1), 'navy')
    for y, w in ((3, 5), (5, 3), (7, 2)):
        ic.d(R(2, y, 2, 1), 'yellow')
        ic.d(R(5, y, w, 1), 'sky')
    ic.s(RR(7, 6, 8, 9, 1), 'red', shade='flat')
    ic.d(pix(['####.', '#...#', '####.', '#...#', '####.'], 9, 8), 'white')
    ic = new('VeraBASIC Run', 'VBRun')
    ic.s(RR(0.5, 1, 11, 9, 1), 'navy')
    for y, w in ((3, 5), (5, 3), (7, 2)):
        ic.d(R(2, y, 2, 1), 'yellow')
        ic.d(R(5, y, w, 1), 'sky')
    ic.s(E(10.5, 10.5, 4.3, 4.3), 'green', shade='round')
    ic.d(pix(['#..', '##.', '###', '##.', '#..'], 9, 8), 'white')
    ic = new('Veranda Setup', 'VSetup')
    ic.s(P((4, 6), (10, 6), (13, 9), (13, 15), (4, 15)), 'navy')
    for x in (5, 7, 9):
        ic.d(R(x, 7, 1, 2), 'yellow')
    ic.s(R(6, 10, 5, 4), 'paper', outline=False, shade='flat')
    ic.d(pix(['#...#', '.#.#.', '..#..'], 6, 10.5), 'blue')
    ic.s(P((6, 0), (10, 0), (10, 2.5), (12, 2.5), (8, 7), (4, 2.5), (6, 2.5)), 'green', shade='flat')
    ic = new('Photo Manager', 'PhotoManager')
    ic.s(R(1, 1, 9, 13), 'blue', shade='round')
    ic.d(R(2, 2, 1, 11), 'navy')
    ic.s(R(6, 6, 9, 8), 'paper')
    ic.s(R(7, 7, 7, 6), 'sky', outline=False, shade='flat')
    ic.d(I(R(7, 7, 7, 6), E(10, 13.5, 4, 2.5)), 'green')
    ic.d(R(11, 8, 2, 2), 'yellow')
    ic = new('Text Manager', 'Text Manager')
    ic.s(R(1, 1, 9, 13), 'green', shade='round')
    ic.d(R(2, 2, 1, 11), 'navy')
    ic.s(R(6, 5, 9, 10), 'paper')
    ic.d(R(8, 7, 3, 1), 'red')
    for y in (9, 11, 13):
        ic.d(R(8, y, 5, 1), 'grey')
    ic = new('Wikipedia', 'GeminiStart')
    for x, y, w, m in ((1, 4, 3, 'red'), (4, 2, 4, 'blue'), (8, 3, 3, 'green')):
        ic.s(R(x, y, w, 13 - y), m, shade='flat')
        ic.d(R(x, y + 1, w, 1), 'yellow')
    ic.s(rot(R(11, 4, 3, 9), 11, 13, -14), 'orange', shade='flat')
    ic.s(R(0, 13, 16, 2), 'wood')
    ic = new('Bird Watch', 'BirdWatch')
    ic.s(R(0.5, 12.5, 15, 1.6), 'wood')
    ic.s(U(E(7, 8.5, 5, 3.3), E(11, 5.5, 2.6, 2.6), P((2.5, 8), (0.5, 5.5), (4, 7))), 'blue')
    ic.s(P((13.3, 5), (15.5, 6), (13.3, 6.8)), 'amber', outline=False, shade='flat')
    ic.d(R(11, 5, 1, 1), 'K')
    ic = new('Lighthouse Pinball', 'Lighthouse')
    ic.s(P((6, 4), (10, 4), (11, 15), (5, 15)), 'paper')
    ic.d(U(R(5, 6, 6, 2), R(5, 10, 7, 2)), 'red')
    ic.s(R(6, 1, 4, 3), 'red')
    ic.s(E(13, 12.5, 2, 2), 'metal')
    ic = new('Harbour Walls', 'HarbourWalls')
    ic.s(R(1, 2, 14, 8), 'orange')
    for y, o in ((4, 0), (7, 2)):
        ic.d(R(1, y, 14, 1), 'brown')
        for x in range(4 + o, 15, 4):
            ic.d(R(x, y - 2, 1, 2), 'brown')
    ic.s(R(1, 10, 14, 5), 'blue')
    ic.d(pix(['.#..#..#.', '#.##.##.#'], 3, 11), 'white')
    ic = new('geoWrite', 'geoWrite')
    page(ic, ((5, 5), (5, 7), (5, 9)), 4)
    ic.s(L(14.5, 5, 8.5, 13, 1.8), 'yellow')
    ic = new('Veranda Write document', 'Write Image')   # (V156)
    page(ic, ((5, 7), (5, 9), (5, 11)), 4)
    ic.d(R(5, 4, 4, 1), 'navy')
    ic.s(L(15, 7, 11, 13, 2), 'blue')
    # (V173) TopDesk's small icon gave its room to this one (46 at most;
    # TopDesk is not in the package: its files show the program's)
    ic = new('Colour Paint picture', 'PaintColour')
    page(ic, ())
    ic.s(R(5, 6, 6, 7), 'sky', outline=True, shade='flat')
    ic.d(I(R(5, 6, 6, 7), E(6, 13, 4, 3)), 'green')
    ic.d(R(8, 7, 2, 2), 'yellow')
    ic = new('geoChess', 'GeoChess')
    for (cx, mat) in ((5, 'paper'), (11, 'dark')):
        ic.s(U(E(cx, 4.5, 2, 2), P((cx - 1.4, 6), (cx + 1.4, 6), (cx + 2.4, 12), (cx - 2.4, 12)),
               R(cx - 3.5, 12, 7, 2.5)), mat)
    ic = new('SID Player', 'VSidPlay')
    ic.s(R(1, 3, 14, 10), 'dark')
    for x in (2, 5, 8, 11, 14):
        ic.d(R(x, 3, 1, 1), 'pale')
        ic.d(R(x, 12, 1, 1), 'pale')
    ic.s(U(E(7.5, 9.8, 2.8, 2.1), R(8.6, 3, 2, 6.5), P((8.6, 3), (13, 4.6), (13, 7), (8.6, 5.6))), 'yellow', shade='flat')
    return out


# ------------------------------------------------------------------ rendering
def materials():
    i = {k: NAMES.index(k) + 1 for k in NAMES}
    return {
        'paper': (i['white'], i['white'], i['pale']),
        'white': (i['white'], i['white'], i['pale']),
        'pale': (i['white'], i['pale'], i['grey']),
        'metal': (i['pale'], i['grey'], i['dark']),
        'dark': (i['grey'], i['dark'], i['navy']),
        'blue': (i['sky'], i['blue'], i['navy']),
        'navy': (i['blue'], i['navy'], i['navy']),
        'sky': (i['white'], i['sky'], i['blue']),
        'screen': (i['sky'], i['blue'], i['navy']),
        'yellow': (i['white'], i['yellow'], i['amber']),
        'amber': (i['yellow'], i['amber'], i['brown']),
        'orange': (i['yellow'], i['amber'], i['brown']),
        'wood': (i['amber'], i['brown'], i['dark']),
        'red': (i['amber'], i['red'], i['brown']),
        'green': (i['lgreen'], i['green'], i['navy']),
        'lgreen': (i['white'], i['lgreen'], i['green']),
        'purple': (i['lilac'], i['purple'], i['navy']),
        'lilac': (i['white'], i['lilac'], i['purple']),
        'grey': (i['pale'], i['grey'], i['dark']),
    }, i


def raster(mask, n=N):
    return {(px, py) for py in range(n) for px in range(n) if mask(px + 0.5, py + 0.5)}


def render(ic, n=N):
    """n rows of n values (32; the small icons 16): 0 none, 'K' the ink,
    1-15 an entry"""
    N = n
    mats, idx = materials()
    grid = [[0] * N for _ in range(N)]
    owner = {}
    for k, (m, mat, ol, sh) in enumerate(ic.shapes):
        for p in raster(m, n):
            owner[p] = k
    union = set(owner)
    out = {}
    for (x, y), k in owner.items():
        m, mat, ol, sh = ic.shapes[k]
        hi, mid, lo = mats[mat]
        same = lambda dx, dy: owner.get((x + dx, y + dy)) == k
        c = mid
        if sh != 'flat':
            if not same(0, -1) or not same(-1, 0):
                c = hi
            elif not same(0, 1) or not same(1, 0):
                c = lo
            elif sh == 'round' and (not same(0, 2) or not same(2, 0) or not same(1, 1)):
                c = lo      # (v2) a 2-pixel shade: rounded things read as solid at 1x
        out[(x, y)] = c
    for (x, y), k in owner.items():         # inner outlines: against a lower shape
        if not ic.shapes[k][2]:
            continue
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            q = owner.get((x + dx, y + dy))
            if q is not None and q < k:
                out[(x, y)] = 'K'
                break
    outline = set()
    for (x, y) in union:
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            q = (x + dx, y + dy)
            if q not in union and 0 <= q[0] < N and 0 <= q[1] < N:
                outline.add(q)
    sil = union | outline
    for (x, y), c in out.items():
        grid[y][x] = c
    for (x, y) in outline:
        grid[y][x] = 'K'
    for m, col in ic.decals:
        for (x, y) in raster(m, n):
            if (x, y) in union:
                grid[y][x] = 'K' if col == 'K' else idx[col] if col in idx else mats[col][1]
    sc = idx['grey']                         # the drop shadow
    for (x, y) in list(sil):
        q = (x + 1, y + 1)
        if q not in sil and q[0] < N and q[1] < N:
            grid[q[1]][q[0]] = sc
    return grid


# ------------------------------------------------------------------ sources
def to_rows(grid):
    return [''.join('.' if v == 0 else 'K' if v == 'K' else LETTERS[v - 1] for v in r) for r in grid]


def from_rows(rows, where=''):
    n = len(rows)
    if n not in (N, NS) or any(len(r) != n for r in rows):
        raise ValueError('%s: 32 rows of 32 characters (a small icon: 16 of 16)' % where)
    g = []
    for r in rows:
        row = []
        for ch in r:
            if ch == '.':
                row.append(0)
            elif ch == 'K':
                row.append('K')
            elif ch in LETTERS:
                row.append(LETTERS.index(ch) + 1)
            else:
                raise ValueError('%s: %r is not ., K or a-o' % (where, ch))
        g.append(row)
    return g


def read(path):
    """icon blocks of a source: [(name, {'for': ...}, grid)]"""
    out, name, kv, rows = [], None, {}, []
    for ln in open(path):
        ln = ln.rstrip('\n')
        if not ln or ln.startswith('#'):
            continue
        if ln.startswith('icon '):
            if name is not None:
                out.append((name, kv, from_rows(rows, '%s: %s' % (path, name))))
            name, kv, rows = ln[5:].strip(), {}, []
        elif ln.startswith('for '):
            kv['for'] = ln[4:].strip()
        else:
            rows.append(ln.strip())
    if name is not None:
        out.append((name, kv, from_rows(rows, '%s: %s' % (path, name))))
    return out


HEAD = """# %s: a Veranda Look 3 colour icon (DECISIONS V133), style A "Sunroom";
# written by tools/mkicons3.py write (its geometry is the source: change
# it there). 32 rows: '.' none, 'K' the ink, 'a'-'o' entries 1-15 of the
# icons' palette row (tools/mkicons3.py PAL).
"""


def block(ic):
    s = 'icon %s\n' % ic.name
    if ic.out in ('lib', 'small'):
        s += 'for %s\n' % ('class ' + ic.cls if not ic.cls.startswith('*') else ic.cls[1:].lower())
    return s + '\n'.join(to_rows(render(ic, NS if ic.out == 'small' else N))) + '\n'


def write():
    lib = []
    for ic in subjects():
        if ic.out.startswith('app:'):
            d = os.path.join(ROOT, 'apps', ic.out[4:])
            if not os.path.isdir(d):
                raise SystemExit('mkicons3: no folder %s' % d)
            open(os.path.join(d, 'icon.txt'), 'w').write(HEAD % ic.name + block(ic))
        else:
            lib.append(ic)
    p = os.path.join(ROOT, 'shell', 'icons3.txt')
    s = ("# The shell's library of Veranda Look 3 colour icons (DECISIONS V133), by\n"
         "# class: the shell's own (folder, up, document, card, printer, trash),\n"
         "# the ports of GEOS programs and the programs of other repositories\n"
         "# (Veranda Write, Veranda Calc, Solitaire, the MOD and SID players,\n"
         "# the games), which carry no icon of their own; packed by\n"
         "# tools/mkicons3.py lib into the shell's overlay records 13 and up.\n"
         "# Written by tools/mkicons3.py write (the geometry is the source).\n"
         "# A program of another repository can carry its own instead: its\n"
         "# app.hdr's \"icon3 = icon.txt\" (tools/vpack.py) with its block copied\n"
         "# from here (icon <name> and its 32 rows).\n\n")
    s += '\n'.join(block(ic) for ic in lib)
    open(p, 'w').write(s)
    sm = small_subjects()
    s = ("# The shell's library of Veranda Look 3's small colour icons (16 x 16,\n"
         "# DECISIONS V151), by class as icons3.txt: the list, the small icons'\n"
         "# view and the sidebar; each drawn for 16 pixels (not reduced from its\n"
         "# 32 x 32 one); \"app\" any other program. Packed by tools/mkicons3.py lib\n"
         "# into the shell's overlay record 15. Written by tools/mkicons3.py write\n"
         "# (the geometry is the source). 16 rows: '.' none, 'K' the ink, 'a'-'o'\n"
         "# entries 1-15 of the icons' palette row.\n\n")
    s += '\n'.join(block(ic) for ic in sm)
    open(os.path.join(ROOT, 'shell', 'icons3s.txt'), 'w').write(s)
    return len(subjects()) - len(lib), len(lib), len(sm)


# ------------------------------------------------------------------ packing
SM_LEN = 165       # a small icon: the tiles n (0-4), the map (4: as pack's), the ink (16 rows of 2), 4 tiles
SM_AT = 560         # the small library: [count, 12-byte keys ...] at 0, icon i at SM_AT + SM_LEN i
SM_MAX = (8192 - SM_AT) // SM_LEN


def tile_of(grid, cx, cy):
    return tuple(tuple(0 if grid[cy * 8 + y][cx * 8 + x] in (0, 'K') else grid[cy * 8 + y][cx * 8 + x]
                       for x in range(8)) for y in range(8))


def pack(grid):
    """-> (ICON_LEN bytes, tiles); a small icon (16 x 16): SM_LEN bytes"""
    tiles, mp = [], []
    n = len(grid)
    for cy in range(n // 8):
        for cx in range(n // 8):
            t = tile_of(grid, cx, cy)
            if not any(any(r) for r in t):
                mp.append(0x80)
                continue
            vs = [(t, 0), (tuple(r[::-1] for r in t), 0x10), (t[::-1], 0x20), (tuple(r[::-1] for r in t[::-1]), 0x30)]
            for v, fl in vs:
                if v in tiles:
                    mp.append(tiles.index(v) | fl)
                    break
            else:
                tiles.append(t)
                mp.append(len(tiles) - 1)
    if len(tiles) > n * n // 64:
        raise ValueError('%d tiles (%d at most)' % (len(tiles), n * n // 64))
    ink = bytearray()
    for y in range(n):
        for b in range(n // 8):
            v = 0
            for i in range(8):
                if grid[y][b * 8 + i] == 'K':
                    v |= 0x80 >> i
            ink.append(v)
    td = bytearray()
    for t in tiles:
        for r in t:
            for i in range(0, 8, 2):
                td.append(r[i] << 4 | r[i + 1])
    if n == NS:
        out = bytes([len(tiles)]) + bytes(mp) + bytes(ink) + bytes(td)
        return out + bytes(SM_LEN - len(out)), len(tiles)
    out = bytes([len(tiles), 3]) + bytes(mp) + bytes(ink) + bytes(td)
    return out + bytes(ICON_LEN - len(out)), len(tiles)


def key(what):
    """the library's key of 'class X' or a shell's own ('folder' ...):
    12 bytes, as an info block's class (space padded)"""
    k = what[6:] if what.startswith('class ') else '*' + what.capitalize()
    if what in ('card', 'sd card'):    # (V151: "sd card" was "*Sd card", which no key matched)
        k = '*SD card'
    return k.encode('latin-1')[:12].ljust(12)


PER = 12            # icons a library record: [count, 12-byte keys ...] at 0, icon i at 160 + 658 i


def lib(src, outs):
    icons = read(src)
    if icons and len(icons[0][2]) == NS:        # the small icons: one record
        if len(icons) > SM_MAX:
            raise SystemExit('mkicons3: %d small icons, %d at most' % (len(icons), SM_MAX))
        b = bytearray(SM_AT)
        b[0] = len(icons)
        for i, (n, kv, g) in enumerate(icons):
            if 'for' not in kv:
                raise SystemExit('mkicons3: %s has no "for"' % n)
            b[1 + 12 * i:13 + 12 * i] = key(kv['for'])
            b += pack(g)[0]
        open(outs[0], 'wb').write(bytes(b))
        return len(icons), 1
    recs = [icons[i:i + PER] for i in range(0, len(icons), PER)]
    if len(recs) > len(outs):
        raise SystemExit('mkicons3: %d records needed, %d named' % (len(recs), len(outs)))
    for r, o in zip(recs, outs):
        b = bytearray(160)
        b[0] = len(r)
        for i, (n, kv, g) in enumerate(r):
            if 'for' not in kv:
                raise SystemExit('mkicons3: %s has no "for"' % n)
            b[1 + 12 * i:13 + 12 * i] = key(kv['for'])
        for n, kv, g in r:
            b += pack(g)[0]
        open(o, 'wb').write(bytes(b))
    for o in outs[len(recs):]:
        open(o, 'wb').write(bytes([0]))
    return len(icons), len(recs)


def all_sources():
    fs = sorted(os.path.join(ROOT, 'apps', d, 'icon.txt') for d in os.listdir(os.path.join(ROOT, 'apps'))
                if os.path.exists(os.path.join(ROOT, 'apps', d, 'icon.txt')))
    return fs + [os.path.join(ROOT, 'shell', 'icons3.txt'), os.path.join(ROOT, 'shell', 'icons3s.txt')]


def check(files):
    tot, uniq = 0, set()
    for f in files:
        for n, kv, g in read(f):
            b, nt = pack(g)
            tot += 1
            for cy in range(len(g) // 8):
                for cx in range(len(g) // 8):
                    t = tile_of(g, cx, cy)
                    if any(any(r) for r in t):
                        uniq.add(min(t, tuple(r[::-1] for r in t), t[::-1], tuple(r[::-1] for r in t[::-1])))
            print('%-22s %2d tiles%s' % (n, nt, ' (16 x 16)' if len(g) == NS else ''))
    print('%d icons, %d different tiles in all' % (tot, len(uniq)))


def sheet(out, files):
    from PIL import Image
    icons = [(n, g) for f in files for n, kv, g in read(f)]
    cols = 12
    rows_ = (len(icons) + cols - 1) // cols
    cw, ch = 32 * 3 + 12, 32 * 3 + 12
    W, H = cols * cw, rows_ * ch * 2 + 8
    im = Image.new('RGB', (W, H), (255, 255, 255))
    px = im.load()
    rgb = lambda c: ((c >> 8 & 15) * 17, (c >> 4 & 15) * 17, (c & 15) * 17)
    for half, bg in ((0, 0xFFF), (1, 0x7A8)):
        for yy in range(half * (rows_ * ch + 8), half * (rows_ * ch + 8) + rows_ * ch):
            for xx in range(W):
                px[xx, yy] = rgb(bg)
        for i, (n, g) in enumerate(icons):
            ox, oy = (i % cols) * cw + 6, half * (rows_ * ch + 8) + (i // cols) * ch + 6
            for y in range(len(g)):
                for x in range(len(g)):
                    v = g[y][x]
                    if v == 0:
                        continue
                    c = rgb(0x223) if v == 'K' else rgb(PAL[v - 1])
                    for a in range(3):
                        for b in range(3):
                            px[ox + x * 3 + a, oy + y * 3 + b] = c
    im.save(out)


def main():
    a = sys.argv[1:]
    if not a:
        raise SystemExit(__doc__)
    if a[0] == 'write':
        na, nl, ns = write()
        print('mkicons3: %d application icons (apps/*/icon.txt), %d in shell/icons3.txt, %d small ones in '
              'shell/icons3s.txt' % (na, nl, ns))
    elif a[0] == 'check':
        check(a[1:] or all_sources())
    elif a[0] == 'lib':
        n, r = lib(a[1], a[2:])
        print('mkicons3: %d icons in %d records' % (n, r))
    elif a[0] == 'sheet':
        sheet(a[1], a[2:] or all_sources())
    else:
        raise SystemExit(__doc__)


if __name__ == '__main__':
    main()
