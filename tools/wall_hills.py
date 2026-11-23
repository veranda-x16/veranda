"""Wallpaper v2 proposal (not for main until approved): "Low Hills",
layered hills in flat tones under a sun disc and its halo; at night (dark mode) the
same hills under the moon. One palette row of 10 colours, drawn as tiles
(tools/wallkit.py): each hill is a few gentle humps of one shape, so their
edges repeat.

usage: wall_hills.py out.cvt [png prefix]

MIT licence (LICENSE)."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import wallkit as wk  # noqa: E402

S1, S2, S3, SUN, H1, H2, H3, H4, HALO = range(1, 10)           # (index 10 not used)
LIGHT = ['ACE', 'CDE', 'EED', 'FC8', 'BBD', '9BB', '7A8', '587', 'FEC', '587']
DARK = ['123', '234', '346', 'DDB', '345', '244', '233', '132', '245', '132']

SKY = [(136, S1), (232, S2), (480, S3)]
FADE = (2, 3, 4, 5, 6, 12, 13, 14, 22, 23)
SUNX, SUNY, SUNR, HALOR = 560, 224, 34, 46


def bell(x, c, w, h):
    """a hump of height h, half width w, centred on c"""
    u = (x - c) / w
    return h * (0.5 + 0.5 * math.cos(math.pi * u)) if abs(u) < 1 else 0.0


# each hill: its base line and its humps (centre, half width, height);
# the nearer, the lower and wider
HILLS = [
    (H1, 304, [(96, 216, 72), (560, 216, 72)]),
    (H2, 344, [(320, 232, 64), (-160, 232, 64), (800, 232, 64)]),
    (H3, 392, [(128, 208, 48), (608, 208, 48)]),
    (H4, 440, [(400, 288, 40), (-176, 288, 40)]),
]


def top(base, humps, x):
    return base - max(bell(x + 0.5, c, w, h) for c, w, h in humps)


def main():
    d = wk.Drawing(1)
    tops = [[top(b, hs, x) for x in range(wk.W)] for _, b, hs in HILLS]

    def f(x, y):
        c = None
        for (col, _, _), t in zip(HILLS, tops):
            if y + 0.5 >= t[x]:
                c = col
        if c is not None:
            return c
        if (x + 0.5 - SUNX) ** 2 + (y + 0.5 - SUNY) ** 2 <= SUNR * SUNR:
            return SUN
        if (x + 0.5 - SUNX) ** 2 + (y + 0.5 - SUNY) ** 2 <= HALOR * HALOR:
            return HALO
        for i, (e, col) in enumerate(SKY):
            if y < e:
                if i + 1 < len(SKY) and e - 1 - y in FADE:
                    return SKY[i + 1][1]
                return col
    d.fill(f)
    wk.write(d, [[wk.c12(c) for c in LIGHT]], [[wk.c12(c) for c in DARK]], 'Low Hills', sys.argv[1],
             sys.argv[2] if len(sys.argv) > 2 else None)


if __name__ == '__main__':
    main()
