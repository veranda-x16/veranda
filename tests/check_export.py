#!/usr/bin/env python3
"""gate export: the BMP files ExportRect wrote, against the VRAM dump.

usage: check_export.py <dir with dump.bin, console.txt and the .BMP files> [outdir]
       check_export.py --bmp <file.bmp> <dump.bin> <screen> <left> <top> <right> <bottom>

A file must be a 1 bpp BMP (BITMAPINFOHEADER, two palette entries,
bottom-up rows padded to 4 bytes) whose pixels equal the screen's (screen
0 the foreground, 1 the back screen) in the area, with the palette's
paper and ink (VERA's entries 0 and 1 in the dump) and the padding 0.
Pillow, if there, must read it too (a PC program's view).
"""
import os
import re
import struct
import sys

VDUMP = 132878                  # x16emu's VRAM section: 128 KB and 1,806 bytes
W, H = 640, 480
BASES = (0x00000, 0x09600)
failures = 0


def check(cond, what):
    global failures
    print(('ok    ' if cond else 'FAIL  ') + what)
    if not cond:
        failures += 1


def vram(dump):
    d = open(dump, 'rb').read()
    return d[len(d) - VDUMP:]


def palette(v, i):
    p = v[131072 + 256:]
    gb, r = p[2 * i], p[2 * i + 1]
    return ((gb & 15) * 17, (gb >> 4) * 17, (r & 15) * 17)       # B, G, R


def pixel(v, screen, x, y):
    return 1 if v[BASES[screen] + y * 80 + x // 8] & (0x80 >> (x % 8)) else 0


def bmp_ok(path, v, screen, l, t, r, b, name=None):
    """the file against the area; a short report"""
    name = name or os.path.basename(path)
    if not os.path.exists(path):
        check(False, '%s: written' % name)
        return
    d = open(path, 'rb').read()
    w, h = r - l + 1, b - t + 1
    n = (w + 7) // 8
    p = (n + 3) & ~3
    bad = []
    if d[:2] != b'BM':
        bad.append('no BM')
    size, _, off = struct.unpack_from('<IIi', d, 2)
    hs, bw, bh, planes, bpp, comp, isz = struct.unpack_from('<IiiHHII', d, 14)
    if size != len(d) or off != 62 or hs != 40 or (bw, bh) != (w, h) or (planes, bpp, comp) != (1, 1, 0) \
            or isz != p * h or len(d) != 62 + p * h:
        bad.append('header: size %d of %d, %dx%d, %d bpp, rows %d' % (size, len(d), bw, bh, bpp, isz))
    for i in range(2):
        if tuple(d[54 + 4 * i:57 + 4 * i]) != palette(v, i) or d[57 + 4 * i]:
            bad.append('palette entry %d' % i)
    diff = pad = 0
    if not bad:
        for row in range(h):
            y = b - row                     # bottom-up
            o = 62 + row * p
            for x in range(w):
                if (d[o + x // 8] >> (7 - x % 8)) & 1 != pixel(v, screen, l + x, y):
                    diff += 1
            if w % 8 and d[o + n - 1] & (0xFF >> (w % 8)):
                pad += 1
            if any(d[o + n:o + p]):
                pad += 1
    if diff:
        bad.append('%d pixels differ' % diff)
    if pad:
        bad.append('%d rows with bits set past the width' % pad)
    try:
        from PIL import Image
        im = Image.open(path)
        im.load()
        if im.size != (w, h):
            bad.append('Pillow reads %dx%d' % im.size)
        else:
            ink = palette(v, 1)[::-1]
            px = im.convert('RGB').load()
            c = sum(1 for x in range(0, w, max(1, w // 37)) for y in range(0, h, max(1, h // 29))
                    if (px[x, y] == ink) != bool(pixel(v, screen, l + x, t + y)))
            if c:
                bad.append('Pillow: %d sampled pixels differ' % c)
    except ImportError:
        pass
    ink = sum(pixel(v, screen, l + x, b - y) for y in range(h) for x in range(w))
    check(not bad, '%s: %dx%d of the %s at %d,%d: %s (%d ink pixels)' % (
        name, w, h, ('foreground', 'back screen')[screen], l, t, '; '.join(bad) or 'equal, pixel for pixel', ink))


def main():
    a = sys.argv[1:]
    if a and a[0] == '--bmp':
        path, dump = a[1], a[2]
        s, l, t, r, b = map(int, a[3:8])
        bmp_ok(path, vram(dump), s, l, t, r, b)
        sys.exit(1 if failures else 0)
    if not a:
        sys.exit(__doc__)
    d = a[0]
    v = vram(os.path.join(d, 'dump.bin'))
    log = open(os.path.join(d, 'console.txt'), 'rb').read().decode('latin-1')
    log = re.sub(r'\\X[0-9A-F]{2}', '', log)
    errs = dict(re.findall(r'EXPORT (\d) ([0-9A-F]{2})', log))
    check('EXPORT DONE' in log, 'the test ran to its end')
    check(all(errs.get(str(i)) == '00' for i in range(1, 6)), 'five pictures written without an error: %s' % errs)
    check(errs.get('6') == '%02X' % 14, 'an empty area: INCOMPATIBLE (14), nothing written: %s'
          % (errs.get('6'),))
    check(not os.path.exists(os.path.join(d, 'NONE.BMP')), 'no NONE.BMP')
    bmp_ok(os.path.join(d, 'FULL.BMP'), v, 0, 0, 0, 639, 479)
    bmp_ok(os.path.join(d, 'PART.BMP'), v, 0, 13, 7, 300, 250)
    bmp_ok(os.path.join(d, 'BACK.BMP'), v, 1, 101, 301, 517, 470)
    bmp_ok(os.path.join(d, 'THIN.BMP'), v, 0, 7, 5, 7, 60)
    bmp_ok(os.path.join(d, 'CLIP.BMP'), v, 0, 600, 400, 639, 479)
    m = re.search(r'TIME full ([0-9A-F]{8})', log)
    if m:
        print('      the whole foreground to a file: %.0f ms (38,462 bytes)' % (int(m.group(1), 16) / 8000))
    if len(a) > 1:
        try:
            from PIL import Image
            for f in ('FULL', 'PART', 'BACK'):
                Image.open(os.path.join(d, f + '.BMP')).save(os.path.join(a[1], f.lower() + '.png'))
        except Exception:
            pass
    sys.exit(1 if failures else 0)


if __name__ == '__main__':
    main()
