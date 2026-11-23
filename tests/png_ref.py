#!/usr/bin/env python3
"""Gate gemini (DECISIONS V124): PNG pictures for Veranda Gemini's picture
viewer, and a reference decoder for them, with Python's zlib only.

    make(kind)        the test pictures (bytes): every colour type, bit
                      depths 1-16, the five filters, a big one, broken ones
    decode(data)      (width, height, rows of (r, g, b)): the picture as
                      Veranda Gemini's decoder must see it before it is
                      scaled: 16-bit samples by their high byte, alpha (and
                      a palette's tRNS) laid over white
    shown(...)        the picture as the viewer shows it: scaled (a box
                      filter across, the nearest row down), its 16 colours
                      and the ordered dither (apps/gemini/img.c's rules)
"""
import random
import struct
import zlib

SIG = b'\x89PNG\r\n\x1a\n'


def chunk(t, data):
    return struct.pack('>I', len(data)) + t + data + struct.pack('>I', zlib.crc32(t + data) & 0xFFFFFFFF)


def paeth(a, b, c):
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    return b if pb <= pc else c


def filt(rows, bpp, choose):
    """raw rows (bytes) filtered: choose(y) the filter of row y"""
    out = bytearray()
    prev = bytes(len(rows[0]))
    for y, r in enumerate(rows):
        f = choose(y)
        out.append(f)
        for i, x in enumerate(r):
            a = r[i - bpp] if i >= bpp else 0
            b = prev[i]
            c = prev[i - bpp] if i >= bpp else 0
            p = (0, a, b, (a + b) >> 1, paeth(a, b, c))[f]
            out.append((x - p) & 255)
        prev = r
    return bytes(out)


def png(w, h, depth, ctype, rows, plte=None, trns=None, choose=lambda y: 0, level=9, interlace=0, split=None):
    ch = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[ctype]
    bpp = max(1, ch * depth // 8)
    data = zlib.compress(filt(rows, bpp, choose), level)
    out = SIG + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, depth, ctype, 0, 0, interlace))
    if plte:
        out += chunk(b'PLTE', bytes(c for rgb in plte for c in rgb))
    if trns:
        out += chunk(b'tRNS', bytes(trns))
    out += chunk(b'tEXt', b'Comment\0Veranda Gemini\'s gate')
    split = split or len(data)
    for i in range(0, len(data), split):
        out += chunk(b'IDAT', data[i:i + split])
    return out + chunk(b'IEND', b'')


def pack(samples, depth):
    """a row's samples (each < 2^depth) into bytes"""
    if depth == 8:
        return bytes(samples)
    if depth == 16:
        return b''.join(struct.pack('>H', s) for s in samples)
    out, acc, n = bytearray(), 0, 0
    for s in samples:
        acc = (acc << depth) | s
        n += depth
        if n == 8:
            out.append(acc)
            acc = n = 0
    if n:
        out.append(acc << (8 - n))
    return bytes(out)


def make(kind):
    r = random.Random(kind)
    if kind == 'gray1':                 # 1-bit grayscale, a checker and a circle; Sub and Up filters
        w, h = 120, 64
        rows = [pack([1 if ((x // 8 + y // 8) & 1) ^ ((x - 60) ** 2 + (y - 32) ** 2 < 600) else 0
                      for x in range(w)], 1) for y in range(h)]
        return png(w, h, 1, 0, rows, choose=lambda y: (1, 2)[y & 1])
    if kind == 'pal1':                  # a 1-bit palette (2 colours)
        w, h = 96, 48
        rows = [pack([(x * y // 64 + x // 12) & 1 for x in range(w)], 1) for y in range(h)]
        return png(w, h, 1, 3, rows, plte=[(200, 30, 40), (250, 240, 200)])
    if kind == 'pal4':                  # a 4-bit palette of 12 colours, a tRNS: shown exactly (no dither)
        w, h = 100, 60
        pl = [(r.randrange(256), r.randrange(256), r.randrange(256)) for _ in range(12)]
        rows = [pack([(x // 10 + y // 10) % 12 for x in range(w)], 4) for y in range(h)]
        return png(w, h, 4, 3, rows, plte=pl, trns=[255] * 11 + [0], choose=lambda y: y % 5)
    if kind == 'pal8':                  # an 8-bit palette of 200 colours
        w, h = 160, 90
        pl = [(i, (i * 7) & 255, 255 - i) for i in range(200)]
        rows = [bytes((x + y * 2) % 200 for x in range(w)) for y in range(h)]
        return png(w, h, 8, 3, rows, plte=pl, choose=lambda y: y % 5)
    if kind == 'gray8':                 # 8-bit grayscale gradients; all five filters
        w, h = 200, 100
        rows = [bytes((x * 255 // (w - 1) + (y * 3 if (x // 25) & 1 else 0)) & 255 for x in range(w)) for y in range(h)]
        return png(w, h, 8, 0, rows, choose=lambda y: y % 5)
    if kind == 'rgb':                   # truecolour, filtered (all five), in three IDATs
        w, h = 150, 80
        rows = [bytes(c for x in range(w) for c in ((x * 255 // w), (y * 255 // h), ((x + y) * 2) & 255))
                for y in range(h)]
        return png(w, h, 8, 2, rows, choose=lambda y: (y * 3) % 5, split=3000)
    if kind == 'rgba':                  # RGBA: an alpha ramp over white
        w, h = 128, 64
        rows = [bytes(c for x in range(w) for c in (40, 90, 200, x * 2)) for y in range(h)]
        return png(w, h, 8, 6, rows, choose=lambda y: 4)
    if kind == 'gray16':                # 16-bit grayscale with alpha: the high bytes
        w, h = 64, 32
        rows = [b''.join(struct.pack('>HH', (x * 1024 + y * 7) & 0xFFFF, 0xFFFF if x < 48 else 0x4000)
                         for x in range(w)) for y in range(h)]
        return png(w, h, 16, 4, rows, choose=lambda y: y % 5)
    if kind == 'small':                 # 24 x 16: shown at 2x
        w, h = 24, 16
        rows = [bytes(255 if (x ^ y) & 4 else 0 for x in range(w)) for y in range(h)]
        return png(w, h, 8, 0, rows)
    if kind == 'comic':                 # 740 x 300, grayscale lines and blocks (about 40 KB): the timing
        w, h = 740, 300
        img = [[255] * w for _ in range(h)]
        for _ in range(60):             # panels' lines, boxes, scribbles
            x0, y0 = r.randrange(w), r.randrange(h)
            x1, y1 = min(w - 1, x0 + r.randrange(200)), min(h - 1, y0 + r.randrange(120))
            g = r.choice((0, 0, 0, 96, 160))
            for x in range(x0, x1 + 1):
                img[y0][x] = img[y1][x] = g
            for y in range(y0, y1 + 1):
                img[y][x0] = img[y][x1] = g
        for _ in range(9000):           # "text": short dashes
            x, y = r.randrange(w - 6), r.randrange(h)
            for k in range(r.randrange(1, 6)):
                img[y][x + k] = 0
        for _ in range(2600):           # noise: a scan's grain
            img[r.randrange(h)][r.randrange(w)] = r.randrange(256)
        rows = [bytes(row) for row in img]
        return png(w, h, 8, 0, rows, choose=lambda y: 2 if y else 1, level=6)
    if kind == 'interlaced':
        w, h = 16, 16
        rows = [bytes(16) for _ in range(h)]
        return png(w, h, 8, 0, rows, interlace=1)
    if kind == 'corrupt':               # a broken deflate stream (CRCs right)
        good = make('gray8')
        i = good.index(b'IDAT') + 4
        n = struct.unpack('>I', good[i - 8:i - 4])[0]
        data = bytearray(good[i:i + n])
        for k in range(40, len(data), 7):
            data[k] ^= 0x5A
        return good[:i - 8] + chunk(b'IDAT', bytes(data)) + good[i + n + 4:]
    if kind == 'big':                   # noise: does not compress (over the test's limit)
        w, h = 120, 200
        rows = [bytes(r.randrange(256) for _ in range(w * 3)) for _ in range(h)]
        return png(w, h, 8, 2, rows)
    # (V138) Gemipedia's gallery (tests/gemini_server.py's stand-in): a flag as Wikimedia's
    # thumbnails of SVGs are (an 8-bit palette), a picture behind a URL longer than 255, a map
    if kind == 'flag':
        w, h = 160, 100
        rows = [bytes(0 if y < 50 else 1 for x in range(w)) for y in range(h)]
        return png(w, h, 8, 3, rows, plte=[(255, 255, 255), (220, 20, 60)])
    if kind == 'castle':                # truecolour: a sky, a wall, towers
        w, h = 220, 150
        rows = []
        for y in range(h):
            row = []
            for x in range(w):
                wall = y > 70 + (20 if (x // 30) & 1 else 0) - (30 if 90 < x < 120 else 0)
                row += (150 + y // 3, 90 + x // 4, 60) if wall else (120 + y, 170 + y // 2, 250)
            rows.append(bytes(row))
        return png(w, h, 8, 2, rows, choose=lambda y: (y * 2) % 5)
    if kind == 'map':                   # grey, behind a link with no extension (shown by its MIME type)
        w, h = 180, 170
        rows = [bytes(255 if (x - 90) ** 2 + (y - 85) ** 2 > 70 ** 2 else 120 + ((x * 3 + y * 5) % 90)
                      for x in range(w)) for y in range(h)]
        return png(w, h, 8, 0, rows, choose=lambda y: y % 5)
    raise KeyError(kind)


# ---------------------------------------------------------------- the reference decoder

def decode(data):
    assert data[:8] == SIG
    p, idat, plte, trns = 8, b'', None, None
    while p < len(data):
        n = struct.unpack('>I', data[p:p + 4])[0]
        t = data[p + 4:p + 8]
        d = data[p + 8:p + 8 + n]
        if t == b'IHDR':
            w, h, depth, ctype, _, _, inter = struct.unpack('>IIBBBBB', d)
        elif t == b'PLTE':
            plte = [tuple(d[i:i + 3]) for i in range(0, len(d), 3)]
        elif t == b'tRNS':
            trns = d
        elif t == b'IDAT':
            idat += d
        p += 12 + n
    if inter:
        raise ValueError('interlaced')
    raw = zlib.decompress(idat)
    ch = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[ctype]
    bpp = max(1, ch * depth // 8)
    rb = (w * ch * depth + 7) // 8
    prev = bytes(rb)
    out = []
    pal = None
    if ctype == 3:
        pal = []
        for i, (cr, cg, cb) in enumerate(plte):
            a = trns[i] if trns and i < len(trns) else 255
            pal.append(tuple(over(c, a) for c in (cr, cg, cb)))
    for y in range(h):
        f = raw[y * (rb + 1)]
        line = bytearray(raw[y * (rb + 1) + 1:(y + 1) * (rb + 1)])
        for i in range(rb):
            a = line[i - bpp] if i >= bpp else 0
            b = prev[i]
            c = prev[i - bpp] if i >= bpp else 0
            line[i] = (line[i] + (0, a, b, (a + b) >> 1, paeth(a, b, c))[f]) & 255
        prev = bytes(line)
        out.append(pixels(line, w, depth, ctype, pal))
    return w, h, out


def over(c, a):
    """c (0-255) with alpha a over white, as img.c does it"""
    x = c * a + 255 * (255 - a)
    return (x + 1 + (x >> 8)) >> 8


def pixels(line, w, depth, ctype, pal):
    ch = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[ctype]
    if depth < 8:
        s = []
        for byte in line:
            for k in range(8 // depth):
                s.append((byte >> (8 - depth * (k + 1))) & ((1 << depth) - 1))
        s = s[:w]
        if ctype == 3:
            return [pal[v] for v in s]
        g = [v * (255 // ((1 << depth) - 1)) for v in s]
        return [(v, v, v) for v in g]
    step = depth // 8
    hi = line[::step] if step == 2 else line
    px = [tuple(hi[x * ch:(x + 1) * ch]) for x in range(w)]
    if ctype == 0:
        return [(v[0],) * 3 for v in px]
    if ctype == 3:
        return [pal[v[0]] for v in px]
    if ctype == 4:
        return [(over(v[0], v[1]),) * 3 for v in px]
    if ctype == 2:
        return [tuple(v) for v in px]
    return [tuple(over(c, v[3]) for c in v[:3]) for v in px]


# ---------------------------------------------------------------- as the viewer shows it (img.c's rules)

THR = [7, 135, 39, 167, 199, 71, 231, 103, 55, 183, 23, 151, 247, 119, 215, 87]
GRAY, COLOUR, DIRECT = 0, 1, 2


def div255(x):
    return (x + 1 + (x >> 8)) >> 8


def plan(w, h):
    s = min(512, 624 * 256 // w, 408 * 256 // h)
    while True:
        ow, oh = max(1, w * s >> 8), max(1, h * s >> 8)
        tw, th = (ow + 7) >> 3, (oh + 7) >> 3
        if tw * th <= 912:
            return ow, oh, tw, th, 1 + ((78 - tw) >> 1), 7 + ((51 - th) >> 1)
        s -= (s >> 5) + 1


def info(data):
    p = 8
    plte, trns = None, None
    while p < len(data):
        n = struct.unpack('>I', data[p:p + 4])[0]
        t, d = data[p + 4:p + 8], data[p + 8:p + 8 + n]
        if t == b'IHDR':
            w, h, depth, ctype = struct.unpack('>IIBB', d[:10])
        elif t == b'PLTE':
            plte = [tuple(d[i:i + 3]) for i in range(0, len(d), 3)]
        elif t == b'tRNS':
            trns = d
        p += 12 + n
    return w, h, depth, ctype, plte, trns


def shown(data):
    """(mode, the 16 colours ($RGB), tw, th, tx, ty, the rows of indices
    tw*8 wide, th*8 high)"""
    w, h, depth, ctype, plte, trns = info(data)
    _, _, rows = decode(data)
    pal = None
    if ctype == 3:
        pal = [tuple(over(c, trns[i] if trns and i < len(trns) else 255) for c in rgb) for i, rgb in enumerate(plte)]
    mode = GRAY if ctype in (0, 4) else COLOUR
    if ctype == 3:
        mode = DIRECT if len(pal) <= 16 else GRAY if all(r == g == b for r, g, b in pal) else COLOUR
    if mode == GRAY:
        colours = [k * 0x111 for k in range(16)]
    elif mode == COLOUR:
        colours = [(0xF00 if k >> 3 else 0) | (((k >> 1) & 3) * 5 << 4) | (0xF if k & 1 else 0) for k in range(16)]
    else:
        colours = [((r + 8) // 17 << 8) | ((g + 8) // 17 << 4) | ((b + 8) // 17) for r, g, b in pal] + \
            [0xFFF] * (16 - len(pal))
    ow, oh, tw, th, tx, ty = plan(w, h)
    # the palette's indices of a palette picture (DIRECT keeps them)
    idx = None
    if ctype == 3:
        idx = []
        raw = zlib.decompress(b''.join(chunks(data, b'IDAT')))
        rb = (w * depth + 7) // 8
        prev = bytes(rb)
        for y in range(h):
            f = raw[y * (rb + 1)]
            line = bytearray(raw[y * (rb + 1) + 1:(y + 1) * (rb + 1)])
            for i in range(rb):
                a = line[i - 1] if i >= 1 else 0
                b = prev[i]
                c = prev[i - 1] if i >= 1 else 0
                line[i] = (line[i] + (0, a, b, (a + b) >> 1, paeth(a, b, c))[f]) & 255
            prev = bytes(line)
            s = []
            for byte in line:
                for k in range(8 // depth):
                    s.append((byte >> (8 - depth * (k + 1))) & ((1 << depth) - 1))
            idx.append(s[:w])
    out = []
    accy = 0
    for y in range(h):
        accy += oh
        n = 0
        while accy >= h:
            accy -= h
            n += 1
        if not n:
            continue
        row = []
        acc = 0
        sums, cnt, cur = [0, 0, 0], 0, (255, 255, 255)
        oy = len(out)
        ci = 15
        for x in range(w):
            if mode == DIRECT:
                ci = idx[y][x]
                cnt = 0
            else:
                for k in range(3):
                    sums[k] += rows[y][x][k]
                cnt += 1
            acc += ow
            while acc >= w:
                acc -= w
                if cnt:
                    cur = tuple((sums[k] + (cnt >> 1)) // cnt for k in range(3))
                    sums, cnt = [0, 0, 0], 0
                row.append(dither(mode, cur, ci, len(row), oy))
        while len(row) < tw * 8:
            row.append(dither(mode, (255, 255, 255), 15, len(row), oy))
        for _ in range(n):
            out.append(row)
            oy = len(out)
            # (the same pixels again: img.c dithers the row once, as oy was at its first)
    while len(out) < th * 8:
        out.append([15] * (tw * 8))
    return mode, colours, ow, oh, tw, th, tx, ty, out


def dither(mode, c, ci, ox, oy):
    t = THR[((oy & 3) << 2) | (ox & 3)]
    if mode == DIRECT:
        return ci
    if mode == GRAY:
        return div255(c[0] * 15 + t)
    return (div255(c[0] + t) << 3) | (div255(c[1] * 3 + t) << 1) | div255(c[2] + t)


def chunks(data, kind):
    p, out = 8, []
    while p < len(data):
        n = struct.unpack('>I', data[p:p + 4])[0]
        if data[p + 4:p + 8] == kind:
            out.append(data[p + 8:p + 8 + n])
        p += 12 + n
    return out


def row_sums(data):
    """each decoded row's r + 2g + 3b (mod 65536), as png.c's test hook sums it"""
    _, _, rows = decode(data)
    return [sum(r + 2 * g + 3 * b for r, g, b in row) & 0xFFFF for row in rows]


if __name__ == '__main__':
    import sys
    for k in sys.argv[1:]:
        d = make(k)
        try:
            w, h, rows = decode(d)
            print(k, len(d), w, h)
        except Exception as e:
            print(k, len(d), 'error', e)
