#!/usr/bin/env python3
"""A GEOS file icon (24x21, 1 bpp, 63 bytes) from a PBM or PNG picture.

usage: vicon.py <in.pbm|in.png> <out.bin>
       vicon.py --default <out.bin>     Veranda's default application icon
       vicon.py --alert <icon.txt> <out.c> [<name>]
                                        (DECISIONS V148) a program's alert icon
                                        (the SDK's vralert.h): its Look 3 colour
                                        icon (V133's icon.txt) in one bit, 32 x 32
                                        (128 bytes, 4 a row): the ink's outline,
                                        the colours as ordered dithers by their
                                        lightness (white for the light ones), the
                                        drop shadow a 50 % one; a C source that
                                        defines  const unsigned char <name>[128]
                                        (default vr_icon)

Black (or dark) pixels are ink. The picture must be 24x21. PBM (P1 and P4)
is read here; PNG needs Pillow.
"""
import sys

W, H = 24, 21


def default():
    rows = []
    for y in range(H):
        r = ''
        for x in range(W):
            r += '#' if y in (0, H - 1) or x in (0, W - 1) else '.'
        rows.append(r)
    # a "V" inside the frame
    for y in range(4, 17):
        d = (y - 4) * 5 // 12
        for x in (5 + d, 6 + d, 17 - d, 18 - d):
            rows[y] = rows[y][:x] + '#' + rows[y][x + 1:]
    return rows


def read_pbm(data):
    toks, i = [], 0
    magic = data[:2]
    # header: magic, width, height (comments allowed)
    pos = 2
    while len(toks) < 2:
        while data[pos:pos + 1].isspace():
            pos += 1
        if data[pos:pos + 1] == b'#':
            while data[pos:pos + 1] not in (b'\n', b''):
                pos += 1
            continue
        start = pos
        while not data[pos:pos + 1].isspace():
            pos += 1
        toks.append(int(data[start:pos]))
    w, h = toks
    if magic == b'P4':
        pos += 1
        stride = (w + 7) // 8
        return w, h, [[(data[pos + y * stride + x // 8] >> (7 - x % 8)) & 1 for x in range(w)] for y in range(h)]
    if magic == b'P1':
        bits = [int(c) for c in data[pos:].decode('ascii') if c in '01']
        return w, h, [bits[y * w:(y + 1) * w] for y in range(h)]
    raise ValueError('not a PBM (P1 or P4)')


def read_png(path):
    from PIL import Image
    img = Image.open(path).convert('L')
    return img.width, img.height, [[1 if img.getpixel((x, y)) < 128 else 0 for x in range(img.width)]
                                   for y in range(img.height)]


def icon_bytes(path):
    """63 bytes"""
    if path is None:
        px = [[1 if c == '#' else 0 for c in r] for r in default()]
    elif path.lower().endswith('.png'):
        w, h, px = read_png(path)
    else:
        w, h, px = read_pbm(open(path, 'rb').read())
    if len(px) != H or any(len(r) != W for r in px):
        raise ValueError('%s: an icon is 24x21' % path)
    return bytes(sum(px[y][8 * b + i] << (7 - i) for i in range(8)) for y in range(H) for b in range(3))


# tools/mkicons3.py's PAL: the icons' palette row, entries 1-15 ('a'-'o')
PAL3 = [0xFFF, 0xDDE, 0x99A, 0x556, 0x9DF, 0x48D, 0x237, 0xFE5, 0xFA3, 0xA52, 0xE44, 0x9E6, 0x3A5, 0xC9F, 0x73C]
BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]


def alert_bits(path):
    """icon.txt (32 rows of '.', 'K', 'a'-'o') -> 32 rows of 0/1"""
    rows = [ln.rstrip('\n') for ln in open(path) if not ln.startswith(('#', 'icon'))]
    rows = [r for r in rows if len(r) == 32]
    if len(rows) != 32:
        raise ValueError('%s: a colour icon is 32 rows of 32' % path)
    px = []
    for y, r in enumerate(rows):
        out = []
        for x, ch in enumerate(r):
            if ch == '.':
                b = 0
            elif ch == 'K':
                b = 1
            elif ch == 'c':                     # the drop shadow
                b = (x + y + 1) & 1
            else:
                c = PAL3[ord(ch) - ord('a')]
                lum = .3 * (c >> 8 & 15) + .59 * (c >> 4 & 15) + .11 * (c & 15)
                b = 1 if lum < (BAYER[y & 3][x & 3] + .5) / 16 * 15 * .7 else 0
            out.append(b)
        px.append(out)
    return px


def alert_c(src, out, name='vr_icon'):
    px = alert_bits(src)
    data = bytes(sum(px[y][8 * b + i] << (7 - i) for i in range(8)) for y in range(32) for b in range(4))
    lines = ['/* the alert icon (the SDK\'s vralert.h), 32 x 32, 1 bit: written by',
             '   tools/vicon.py --alert from the colour icon %s */' % src.split('/')[-1],
             'const unsigned char %s[128] = {' % name]
    for y in range(0, 128, 16):
        lines.append('    ' + ', '.join('0x%02X' % v for v in data[y:y + 16]) + ',')
    lines.append('};')
    open(out, 'w').write('\n'.join(lines) + '\n')


def main():
    a = sys.argv[1:]
    if len(a) in (3, 4) and a[0] == '--alert':
        alert_c(*a[1:])
        return
    if len(a) == 2 and a[0] == '--default':
        open(a[1], 'wb').write(icon_bytes(None))
    elif len(a) == 2:
        open(a[1], 'wb').write(icon_bytes(a[0]))
    else:
        sys.exit(__doc__)


if __name__ == '__main__':
    main()
