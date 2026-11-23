"""Wallpaper v2 proposal (not for main until approved): "Still Water", a
soft sunrise over calm water; at night (dark mode) the same scene under the
moon. Flat bands, one palette row of 10 colours, drawn as tiles
(tools/wallkit.py).

usage: wall_stillwater.py out.cvt [png prefix]

MIT licence (LICENSE)."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import wallkit as wk  # noqa: E402

# indices
S1, S2, S3, S4, S5, SUN, LAND, W1, W2, W3 = range(1, 11)
LIGHT = ['8BD', 'ACE', 'CDE', 'EDD', 'FDB', 'FB7', '8A9', 'BCD', '9BC', '7AB']
DARK = ['123', '134', '235', '245', '346', 'DDB', '122', '235', '124', '013']

HORIZON = 304
SKY = [(112, S1), (176, S2), (232, S3), (272, S4), (HORIZON, S5)]
WATER = [(336, W1), (392, W2), (480, W3)]
SUNX, SUNY, SUNR = 560, 300, 40
# long thin clouds: (y, x0, x1, height)
CLOUDS = [(146, 296, 520, 6), (154, 352, 456, 4), (206, 64, 232, 6), (246, 392, 472, 4)]


# a band's edge softened: thinner lines of the next band above it
# (from the edge up: 5 pixels at 2-6, 3 at 12-14, 2 at 22-23)
FADE = (2, 3, 4, 5, 6, 12, 13, 14, 22, 23)


def band(y, bands, fade=True):
    for i, (e, c) in enumerate(bands):
        if y < e:
            if fade and i + 1 < len(bands) and e - 1 - y in FADE:
                return bands[i + 1][1]
            return c
    return bands[-1][1]


def land(x):
    """the far shore's height above the horizon (0: none)"""
    if x > 296:
        return 0
    u = x / 296.0
    return max(0.0, 18 * math.sin(math.pi * u) ** 0.7 + 6 * math.sin(3 * math.pi * u) * (1 - u))


def capsule(x, y, cy, x0, x1, h):
    r = h / 2.0
    if abs(y + 0.5 - cy) > r:
        return False
    if x0 + r <= x <= x1 - r:
        return True
    ex = x0 + r if x < x0 + r else x1 - r
    return (x + 0.5 - ex) ** 2 + (y + 0.5 - cy) ** 2 <= r * r


def streaks():
    """the sun's reflection: (y, half length) of 2-pixel lines, wider and
    further apart toward the bottom"""
    out = []
    y, k = HORIZON + 4, 0
    while y < 470:
        d = (y - HORIZON) / 176.0
        half = 14 + 34 * d + (10 if k % 3 == 1 else 0) - (8 if k % 4 == 3 else 0)
        out.append((y, half))
        y += 6 + int(10 * d) + (2 if k % 2 else 0)
        k += 1
    return out


def ripples():
    """faint long lines on the water: (y, x0, x1, index)"""
    return [(318, 40, 216, S5), (326, 248, 360, S5), (352, 16, 160, W1), (364, 200, 344, W1),
            (376, 96, 248, W1), (410, 24, 136, W2), (424, 168, 400, W2), (446, 56, 248, W2),
            (462, 304, 448, W2)]


def main():
    d = wk.Drawing(1)
    st = streaks()
    rp = ripples()

    def f(x, y):
        if y < HORIZON:
            if (x + 0.5 - SUNX) ** 2 + (y + 0.5 - SUNY) ** 2 <= SUNR * SUNR:
                return SUN
            if y >= HORIZON - land(x):
                return LAND
            for cy, x0, x1, h in CLOUDS:
                if capsule(x, y, cy, x0, x1, h):
                    return S5 if cy < 232 else S3
            return band(y, SKY)
        for sy, half in st:
            if sy <= y < sy + 2 and abs(x + 0.5 - SUNX) <= half:
                return SUN
        for ry, x0, x1, c in rp:
            if y == ry and x0 <= x < x1:
                return c
        return band(y, WATER, False)
    d.fill(f)
    wk.write(d, [[wk.c12(c) for c in LIGHT]], [[wk.c12(c) for c in DARK]], 'Still Water', sys.argv[1],
             sys.argv[2] if len(sys.argv) > 2 else None)


if __name__ == '__main__':
    main()
