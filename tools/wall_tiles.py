"""Wallpaper v2 proposal (not for main until approved): "Sunroom Tiles", a
quiet geometric pattern: touching circles on a lattice, their tones from
sky at the top left to sage at the bottom right, one warm circle at the
right edge. Drawn as tiles (tools/wallkit.py): every circle is four
quarters of the same few edge tiles (flipped), its colours given by its
own palette row, so the whole pattern is a handful of tiles.

usage: wall_tiles.py out.cvt [png prefix]

MIT licence (LICENSE)."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import wallkit as wk  # noqa: E402

CELL = 80
TOP = 16                                    # under the menu bar
R0, R1 = 36, 44                             # each arc's line: radius 36-44 round a corner
# the ground in bands from sky (top) to sage (bottom), a palette row each
# (index 1 the ground, 2 the arcs, 3 the warm loop's), card rows 2-59
# (the end, the ground light and dark, its arcs light and dark: a step
# lighter than the ground, a quiet line)
BANDS = [(96, '9CD', '224', 'ADE', '335'), (176, 'ADD', '234', 'BEE', '345'),
         (256, 'BDD', '244', 'CEE', '355'), (336, 'BDC', '243', 'CED', '354'),
         (416, 'ACB', '233', 'BDC', '344'), (480, '9BA', '232', 'ACB', '343')]
WARM = ('FC9', '864')
LOOP = (560, 336)                           # the warm loop's centre (a grid point)


def corners(i, j):
    """a square's two arcs: 0 round its top left and bottom right corners,
    1 the other two (a fixed hash), the squares round LOOP make a circle"""
    gx, gy = LOOP[0] // CELL, (LOOP[1] - TOP) // CELL
    if (i, j) in ((gx - 1, gy - 1), (gx, gy)):
        return 0
    if (i, j) in ((gx, gy - 1), (gx - 1, gy)):
        return 1
    h = (i * 7 + j * 13 + (i * j) % 5) % 3
    return 0 if h == 0 or (i + j) % 4 == 1 else 1


def main():
    d = wk.Drawing(len(BANDS))

    def f(x, y):
        if y < TOP:
            return 1
        i, j = x // CELL, (y - TOP) // CELL
        u, v = x - i * CELL + 0.5, y - TOP - j * CELL + 0.5
        cs = ((0, 0), (CELL, CELL)) if corners(i, j) == 0 else ((CELL, 0), (0, CELL))
        for cx, cy in cs:
            r2 = (u - cx) ** 2 + (v - cy) ** 2
            if R0 * R0 <= r2 <= R1 * R1:
                return 3 if (i * CELL + cx, TOP + j * CELL + cy) == LOOP else 2
        return 1
    d.fill(f)
    for cy in range(wk.FIRST, wk.CH):
        for cx in range(wk.CW):
            d.card_row(cx, cy, next(k for k, b in enumerate(BANDS) if cy * 8 < b[0]))
    light = [[wk.c12(g), wk.c12(a), wk.c12(WARM[0])] + [wk.c12(g)] * 7 for _, g, _, a, _ in BANDS]
    dark = [[wk.c12(g), wk.c12(a), wk.c12(WARM[1])] + [wk.c12(g)] * 7 for _, _, g, _, a in BANDS]
    wk.write(d, light, dark, 'Sunroom Tiles', sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else None)


if __name__ == '__main__':
    main()
