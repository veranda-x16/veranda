"""Dusk, Veranda's first desktop picture (DECISIONS V78), drawn again as
tiles (V175, tools/wallkit.py): the dusk sky from deep blue through pale
blue to pink in flat bands (softened by thinner lines of the next band),
a purple range and two green ridges in front of it, the nearest darkest.
Each range repeats one profile across the screen (a period of 320 or 160
pixels), so its edge tiles repeat. One palette row of 10 colours; dark
mode a night version (the same tiles and map). Replaces mkwall.py's
dithered Dusk of 352 tiles, which left too few tiles for colour icons.

usage: wall_dusk.py out.cvt [png prefix]
       (tools/mkwall.py --dusk writes the same file)

MIT licence (LICENSE)."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import wallkit as wk  # noqa: E402

S1, S2, S3, S4, S5, S6, PURPLE, G1, G2, G3 = range(1, 11)
#        deep blue ... pale blue, lilac, pink  purple   greens, near to dark
LIGHT = ['248', '36A', '58C', '7AD', 'A9C', 'DAC', '76A', '486', '364', '243']
DARK = ['012', '123', '134', '235', '324', '434', '323', '132', '121', '010']

SKY = [(96, S1), (160, S2), (216, S3), (264, S4), (304, S5), (480, S6)]
FADE = (2, 3, 4, 5, 6, 12, 13, 14, 22, 23)


def bell(u, w):
    """a smooth hump of half width w at u (0 outside)"""
    return 0.5 + 0.5 * math.cos(math.pi * u / w) if abs(u) < w else 0.0


def ridge(x, base, period, peaks):
    """the range's top at x: its base less the highest of its peaks
    (offset in the period, half width, height), repeated every period"""
    u = (x + 0.5) % period
    h = 0.0
    for c, w, a in peaks:
        for k in (-1, 0, 1):
            h = max(h, a * bell(u - c - k * period, w))
    return base - h


# (colour, base, period, peaks)
RANGES = [
    (PURPLE, 336, 320, [(64, 128, 60), (208, 104, 40), (296, 64, 22)]),
    (G1, 376, 160, [(56, 96, 34), (136, 56, 14)]),
    (G2, 424, 320, [(160, 192, 34)]),
    (G3, 460, 640, [(480, 288, 22)]),
]


def main():
    d = wk.Drawing(1)
    tops = [[ridge(x, b, p, pk) for x in range(wk.W)] for _, b, p, pk in RANGES]

    def f(x, y):
        c = None
        for (col, _, _, _), t in zip(RANGES, tops):
            if y + 0.5 >= t[x]:
                c = col
        if c is not None:
            return c
        for i, (e, col) in enumerate(SKY):
            if y < e:
                if i + 1 < len(SKY) and e - 1 - y in FADE:
                    return SKY[i + 1][1]
                return col
    d.fill(f)
    return d


def rows():
    return [[wk.c12(c) for c in LIGHT]], [[wk.c12(c) for c in DARK]]


def document(name='Dusk'):
    """-> (the GEOS document, a line: its tiles and rows) (mkwall.py --dusk)"""
    cvt, data, _, n, r = wk.document(main(), *rows(), name)
    return cvt, wk.line(name, n, r, len(data))


def write(out, png=None):
    return wk.write(main(), *rows(), 'Dusk', out, png)


if __name__ == '__main__':
    write(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else None)
