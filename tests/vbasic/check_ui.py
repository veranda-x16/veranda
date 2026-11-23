#!/usr/bin/env python3
"""gate vb_ui: each session's screen against its golden.

usage: check_ui.py SESSIONS_DIR golden.txt NAME...

A golden is a hash of the screen as VERA shows it (tools/vram2png.py
compose(): the bitmap, the colour map, the palette) with some rectangles
masked: always the menu bar's clock (x 504-639, y 0-15), and those the
golden's line names (a TIME$ in a status band). golden.txt, a line each:
    NAME SHA256 [x0,y0,x1,y1 ...]
With VB_GOLDEN=1 the hashes are written anew (the masks kept). MIT licence.
"""
import hashlib
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'tools'))
import vram2png  # noqa: E402

CLOCK = (504, 0, 639, 15)


def digest(dump, masks):
    rows = vram2png.compose(vram2png.section(dump))
    for x0, y0, x1, y1 in masks:
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                rows[y][x] = (0, 0, 0)
    h = hashlib.sha256()
    for row in rows:
        h.update(bytes(c for px in row for c in px))
    return h.hexdigest()[:32]


def main(argv):
    sdir, gold, names = argv[0], argv[1], argv[2:]
    table = {}
    if os.path.exists(gold):
        for ln in open(gold):
            w = ln.split()
            if w and not w[0].startswith('#'):
                table[w[0]] = (w[1], [tuple(int(v) for v in m.split(',')) for m in w[2:]])
    write = os.environ.get('VB_GOLDEN') == '1'
    bad = 0
    for n in names:
        old, masks = table.get(n, ('-', []))
        d = digest(os.path.join(sdir, n, 'dump.bin'), [CLOCK] + masks)
        if write:
            table[n] = (d, masks)
        elif d != old:
            print('FAIL  %s: the screen differs from its golden (%s, not %s): %s' % (
                n, d, old, os.path.join(sdir, n, 'screen.png')))
            bad += 1
    if write:
        with open(gold, 'w') as f:
            f.write('# gate vb_ui: the screens (tests/vbasic/check_ui.py); NAME HASH [masked x0,y0,x1,y1]\n')
            for n in sorted(table):
                d, masks = table[n]
                f.write(' '.join([n, d] + ['%d,%d,%d,%d' % m for m in masks]) + '\n')
        print('ok    the goldens written: %s' % gold)
        return 0
    if bad:
        return 1
    print('ok    %d screens equal their goldens (VRAM, the colour map, the palette)' % len(names))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
