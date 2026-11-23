#!/usr/bin/env python3
"""The colour icons' tiles in a shell's screen (DECISIONS V153): from an
x16emu dump (-dump V), the tiles the cards of palette rows 11 and 12 (the
icons', look3.c) show: how many, which ranges, the highest.

usage: tile_budget.py <dump.bin>
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_theme as ct  # noqa: E402


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    v = ct.section(sys.argv[1])
    ts = set()
    for y in range(60):
        for x in range(80):
            a = ct.MAP + 2 * (y * 128 + x)
            t, row = v[a] | (v[a + 1] & 3) << 8, v[a + 1] >> 4
            if row in (11, 12):
                ts.add(t)
    lo = sorted(t for t in ts if t < 480)
    hi = sorted(t for t in ts if t >= 480)
    print('icon tiles shown: %d (wallpaper area %d: %s; pool %d: %s)' % (
        len(ts), len(lo), '%d-%d' % (lo[0], lo[-1]) if lo else '-', len(hi), '%d-%d' % (hi[0], hi[-1]) if hi else '-'))


if __name__ == '__main__':
    main()
