#!/usr/bin/env python3
"""A contact sheet of screenshots (Veranda Look 3 "Sunroom", DECISIONS
V146-V153): rows of labelled pictures, each scaled to a cell.

usage: sunroom_sheet.py <out.png> <title> [--cols N] [--w W] row...
A row is "label=path[|label=path...]"; a missing file shows as a grey
cell with its name. MIT licence (see LICENSE).
"""
import os
import sys
from PIL import Image, ImageDraw


def main():
    a = sys.argv[1:]
    if len(a) < 3:
        sys.exit(__doc__)
    out, title = a[0], a[1]
    a = a[2:]
    cw = 400
    if '--w' in a:
        i = a.index('--w')
        cw = int(a[i + 1])
        del a[i:i + 2]
    rows = [[c.split('=', 1) for c in r.split('|')] for r in a]
    ch = cw * 3 // 4
    ncol = max(len(r) for r in rows)
    pad, lab, head = 8, 16, 28
    W = pad + ncol * (cw + pad)
    H = head + len(rows) * (ch + lab + pad) + pad
    im = Image.new('RGB', (W, H), (250, 250, 248))
    d = ImageDraw.Draw(im)
    d.text((pad, 8), title, fill=(30, 30, 40))
    for y, r in enumerate(rows):
        for x, (label, path) in enumerate(r):
            px = pad + x * (cw + pad)
            py = head + y * (ch + lab + pad)
            d.text((px, py), label, fill=(40, 40, 60))
            if os.path.exists(path):
                p = Image.open(path).convert('RGB')
                p.thumbnail((cw, ch))
                im.paste(p, (px, py + lab))
            else:
                d.rectangle((px, py + lab, px + cw - 1, py + lab + ch - 1), fill=(200, 200, 200))
                d.text((px + 4, py + lab + 4), 'missing: ' + os.path.basename(path), fill=(90, 0, 0))
    im.save(out)
    print(out, im.size)


if __name__ == '__main__':
    main()
