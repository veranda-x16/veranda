#!/usr/bin/env python3
"""Gate gemini (DECISIONS V124): apps/gemini/png.c on the host (tests/png_host.c,
built with gcc) against tests/png_ref.py: for each test picture, every
decoded row (before scaling: r + 2g + 3b summed, as the X16's test build
logs it) and the picture as shown (its 16 colours, the tiles' indices after
scaling and the dither), index for index.

usage: check_png.py <png_host binary> <work folder> [kinds...]
"""
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import png_ref  # noqa: E402

HOST, WORK = sys.argv[1], sys.argv[2]
KINDS = sys.argv[3:] or ['gray1', 'pal1', 'pal4', 'pal8', 'gray8', 'rgb', 'rgba', 'gray16', 'small', 'comic',
                         'big', 'interlaced', 'corrupt']
ERRS = {'interlaced': 4, 'corrupt': 3}


def need(c, msg):
    if not c:
        sys.exit('FAIL  png (host): ' + msg)


def run(kind):
    data = png_ref.make(kind)
    f = os.path.join(WORK, kind + '.png')
    open(f, 'wb').write(data)
    o = os.path.join(WORK, kind + '.out')
    subprocess.run([HOST, f, o], check=True)
    return data, open(o).read().split('\n')


def parse(lines):
    head = lines[0].split()
    if head[0] == 'err':
        return int(head[1]), None
    w, h, ow, oh, mode, tw, th, tx, ty = map(int, head[1:])
    colours = [int(c, 16) for c in lines[1].split()]
    pic = [[int(c, 16) for c in l] for l in lines[2:2 + th * 8]]
    i = lines.index('rows')
    sums = [int(l) for l in lines[i + 1:] if l]
    return 0, (w, h, ow, oh, mode, tw, th, tx, ty, colours, pic, sums)


done = []
for kind in KINDS:
    data, lines = run(kind)
    err, r = parse(lines)
    if kind in ERRS:
        need(err == ERRS[kind], '%s: error %s, not %d' % (kind, err, ERRS[kind]))
        done.append('%s: refused (%d)' % (kind, err))
        continue
    need(not err, '%s: error %d' % (kind, err))
    w, h, ow, oh, mode, tw, th, tx, ty, colours, pic, sums = r
    ref = png_ref.row_sums(data)
    need(len(sums) == h, '%s: %d rows decoded, not %d' % (kind, len(sums), h))
    bad = [y for y in range(h) if sums[y] != ref[y]]
    need(not bad, '%s: rows %s differ from the reference (first: %d, not %d)' % (kind, bad[:5], sums[bad[0]] if bad else 0,
                                                                              ref[bad[0]] if bad else 0))
    m, cols, rw, rh, rtw, rth, rtx, rty, out = png_ref.shown(data)
    need((ow, oh, tw, th, tx, ty, mode) == (rw, rh, rtw, rth, rtx, rty, m),
         '%s: shown %s, the reference %s' % (kind, (ow, oh, tw, th, tx, ty, mode), (rw, rh, rtw, rth, rtx, rty, m)))
    need(colours == cols, '%s: the colours %s, the reference %s' % (kind, colours, cols))
    for y in range(th * 8):
        if pic[y] != out[y]:
            x = next(i for i in range(tw * 8) if pic[y][i] != out[y][i])
            sys.exit('FAIL  png (host): %s: row %d column %d is %d, the reference %d' % (kind, y, x, pic[y][x], out[y][x]))
    done.append('%s %dx%d -> %dx%d (%s)' % (kind, w, h, ow, oh, ('grey', 'colour', 'palette')[mode]))
print('ok    png.c on the host against png_ref.py: every row decoded equal, the picture shown index for index: '
      + '; '.join(done))
