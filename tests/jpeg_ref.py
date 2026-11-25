#!/usr/bin/env python3
"""Gate gemini (DECISIONS V192): JPEG pictures for Veranda Gemini's picture
viewer, and a reference decoder for them: the X16's integer steps exactly
(apps/gemini/jpghdr.c, jpegcore.s), so that its tiles can be compared index
for index.

    make(kind)        the test pictures (bytes; Pillow's encoder): 4:2:0,
                      4:2:2, 4:4:4, grey, restart markers, odd sizes, a big
                      one (decoded at 1/8), progressive and damaged ones
    decode(data)      (mode, width, height, rows of (r, g, b)) as the
                      decoder makes them before they are scaled: baseline
                      Huffman, the dequantisation with AAN's scales, the
                      AAN IDCT in 16-bit integers (libjpeg's "ifast",
                      its products floor(x * c / 256), the odd part's two
                      products of a sum in one), chroma by the nearest
                      sample, YCbCr by libjpeg's constants in tables
    shown(data)       the picture as the viewer shows it: png_ref's plan,
                      scaling and dither
    pillow_diff(data) how far decode() is from Pillow's (libjpeg-turbo's)
                      decoding: the mean and the largest difference
"""
import io
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import png_ref  # noqa: E402

GRAY, COLOUR = png_ref.GRAY, png_ref.COLOUR

ZZ = [0, 1, 8, 16, 9, 2, 3, 10, 17, 24, 32, 25, 18, 11, 4, 5, 12, 19, 26, 33, 40, 48, 41, 34, 27, 20, 13, 6, 7, 14,
      21, 28, 35, 42, 49, 56, 57, 50, 43, 36, 29, 22, 15, 23, 30, 37, 44, 51, 58, 59, 52, 45, 38, 31, 39, 46, 53, 60,
      61, 54, 47, 55, 62, 63]
AAN = [16384, 22725, 21407, 19266, 16384, 12873, 8867, 4520,
       22725, 31521, 29692, 26722, 22725, 17855, 12299, 6270,
       21407, 29692, 27969, 25172, 21407, 16819, 11585, 5906,
       19266, 26722, 25172, 22654, 19266, 15137, 10426, 5315,
       16384, 22725, 21407, 19266, 16384, 12873, 8867, 4520,
       12873, 17855, 16819, 15137, 12873, 10114, 6967, 3552,
       8867, 12299, 11585, 10426, 8867, 6967, 4799, 2446,
       4520, 6270, 5906, 5315, 4520, 3552, 2446, 1247]

# the errors (apps/gemini/png.h)
E_DATA, E_BIG, E_PROG = 3, 5, 6
MAXW = 1568                     # the planes' room in VRAM (jpghdr.c): a row's samples
PLANES = 37632                  # $09600-$128FF: an MCU row


class Bad(Exception):
    def __init__(self, code):
        Exception.__init__(self, code)
        self.code = code


def w16(x):
    return ((x + 0x8000) & 0xFFFF) - 0x8000


def mul(a, c):
    return w16((a * c) >> 8)


def mul2(a, c1, b, c2):
    return w16((a * c1 + b * c2) >> 8)


def idct1(x):
    """one 8-point pass (jpegcore.s's idct1): 8 int16 in, 8 out"""
    x0, x1, x2, x3, x4, x5, x6, x7 = x
    t10 = w16(x0 + x4)
    t11 = w16(x0 - x4)
    t13 = w16(x2 + x6)
    t12 = w16(mul(w16(x2 - x6), 362) - t13)
    e0, e3 = w16(t10 + t13), w16(t10 - t13)
    e1, e2 = w16(t11 + t12), w16(t11 - t12)
    z13 = w16(x5 + x3)
    z10 = w16(x5 - x3)
    z11 = w16(x1 + x7)
    z12 = w16(x1 - x7)
    t7 = w16(z11 + z13)
    o11 = mul(w16(z11 - z13), 362)
    o10 = mul2(z12, -196, z10, -473)
    o12 = mul2(z10, -196, z12, 473)
    t6 = w16(o12 - t7)
    t5 = w16(o11 - t6)
    t4 = w16(o10 + t5)
    return [w16(e0 + t7), w16(e1 + t6), w16(e2 + t5), w16(e3 - t4),
            w16(e3 + t4), w16(e2 - t5), w16(e1 - t6), w16(e0 - t7)]


def desc(v):
    v = (w16(v + 16) >> 5) + 128
    return 0 if v < 0 else 255 if v > 255 else v


def idct(c):
    """64 coefficients (natural order, dequantised) -> 64 samples"""
    ws = [0] * 64
    for col in range(8):
        x = [c[r * 8 + col] for r in range(8)]
        if not any(x[1:]):
            o = [x[0]] * 8
        else:
            o = idct1(x)
        for r in range(8):
            ws[r * 8 + col] = o[r]
    out = []
    for r in range(8):
        x = ws[r * 8:r * 8 + 8]
        if not any(x[1:]):
            out += [desc(x[0])] * 8
        else:
            out += [desc(v) for v in idct1(x)]
    return out


def tables():
    rcr = [(91881 * (i - 128) + 32768) >> 16 for i in range(256)]
    bcb = [(116130 * (i - 128) + 32768) >> 16 for i in range(256)]
    gcb = [(-22554 * (i - 128) + 32768) >> 16 for i in range(256)]
    gcr = [(-46802 * (i - 128) + 32768) >> 16 for i in range(256)]
    return rcr, bcb, gcb, gcr


def clamp(v):
    return 0 if v < 0 else 255 if v > 255 else v


class Bits:
    """the entropy-coded data, its bits first the highest; 0xFF 0x00 a 0xFF;
    a marker stops it (zeros after)"""

    def __init__(self, d, p):
        self.d, self.p, self.b, self.n, self.marker = d, p, 0, 0, None

    def byte(self):
        if self.marker is not None or self.p >= len(self.d):
            return 0
        v = self.d[self.p]
        if v == 0xFF:
            n = self.d[self.p + 1] if self.p + 1 < len(self.d) else 0xD9
            if n == 0:
                self.p += 2
                return 0xFF
            self.marker = n
            return 0
        self.p += 1
        return v

    def bit(self):
        if not self.n:
            self.b, self.n = self.byte(), 8
        self.n -= 1
        return (self.b >> self.n) & 1

    def get(self, s):
        v = 0
        for _ in range(s):
            v = (v << 1) | self.bit()
        return v

    def restart(self):
        self.n = 0
        while self.marker is None and self.p < len(self.d):
            self.byte()
        if self.marker is None or not 0xD0 <= self.marker <= 0xD7:
            raise Bad(E_DATA)
        self.marker = None
        self.p += 2


def huff(counts, syms):
    """canonical codes: (length, code) -> symbol"""
    t, code, k = {}, 0, 0
    for ln in range(1, 17):
        for _ in range(counts[ln - 1]):
            t[(ln, code)] = syms[k]
            k += 1
            code += 1
        code <<= 1
    return t


def decsym(bits, t):
    code = 0
    for ln in range(1, 17):
        code = (code << 1) | bits.bit()
        if (ln, code) in t:
            return t[(ln, code)]
    raise Bad(E_DATA)


def extend(v, s):
    return v - (1 << s) + 1 if s and v < (1 << (s - 1)) else v


def parse(data):
    if data[:2] != b'\xff\xd8':
        raise Bad(2)
    p = 2
    j = {'qt': {}, 'dc': {}, 'ac': {}, 'dri': 0}
    while True:
        while p < len(data) and data[p] != 0xFF:
            p += 1
        while p < len(data) and data[p] == 0xFF:
            p += 1
        if p + 2 >= len(data):
            raise Bad(E_DATA)
        m = data[p]
        p += 1
        if m in (0xD8, 0x01) or 0xD0 <= m <= 0xD7:
            continue
        if m == 0xD9:
            raise Bad(E_DATA)
        n = (data[p] << 8) | data[p + 1]
        seg = data[p + 2:p + n]
        p += n
        if m == 0xDB:
            i = 0
            while i < len(seg):
                pq, tq = seg[i] >> 4, seg[i] & 15
                i += 1
                if tq > 3:
                    raise Bad(E_DATA)
                if pq:
                    q = [(seg[i + 2 * k] << 8) | seg[i + 2 * k + 1] for k in range(64)]
                    i += 128
                else:
                    q = list(seg[i:i + 64])
                    i += 64
                j['qt'][tq] = q
        elif m == 0xC4:
            i = 0
            while i < len(seg):
                tc, th = seg[i] >> 4, seg[i] & 15
                counts = list(seg[i + 1:i + 17])
                syms = list(seg[i + 17:i + 17 + sum(counts)])
                i += 17 + sum(counts)
                if th > 1 or tc > 1 or sum(counts) > (16 if tc == 0 else 256):
                    raise Bad(E_DATA)
                j['ac' if tc else 'dc'][th] = huff(counts, syms)
        elif m == 0xDD:
            j['dri'] = (seg[0] << 8) | seg[1]
        elif m in (0xC0, 0xC1):
            if seg[0] != 8:
                raise Bad(E_BIG)
            j['h'] = (seg[1] << 8) | seg[2]
            j['w'] = (seg[3] << 8) | seg[4]
            nc = seg[5]
            j['comps'] = [(seg[6 + 3 * k], seg[7 + 3 * k] >> 4, seg[7 + 3 * k] & 15, seg[8 + 3 * k]) for k in range(nc)]
        elif 0xC2 <= m <= 0xCF and m not in (0xC4, 0xC8, 0xCC):
            raise Bad(E_PROG)
        elif m == 0xDA:
            if 'comps' not in j:
                raise Bad(E_DATA)
            ns = seg[0]
            j['scan'] = [(seg[1 + 2 * k], seg[2 + 2 * k] >> 4, seg[2 + 2 * k] & 15) for k in range(ns)]
            j['data'] = p
            return j


def check(j):
    w, h, comps = j['w'], j['h'], j['comps']
    if not w or not h:
        raise Bad(E_DATA)
    if len(comps) == 3:
        if any(c[1] != 1 or c[2] != 1 for c in comps[1:]) or comps[0][1] not in (1, 2) or comps[0][2] not in (1, 2):
            raise Bad(E_BIG)
        if len(j['scan']) != 3:
            raise Bad(E_BIG)
    elif len(comps) != 1:
        raise Bad(E_BIG)
    if w > MAXW * 8:
        raise Bad(E_BIG)


def scale_for(w, h):
    ow, oh = png_ref.plan(w, h)[:2]
    k = 8 if (w + 7) // 8 >= ow and (h + 7) // 8 >= oh else 1
    if (w + k - 1) // k > MAXW:
        raise Bad(E_BIG)
    return k


def decode(data):
    """(mode, pw, ph, rows of (r, g, b)): pw, ph the decoded size (1/8 of it
    when the picture is shown at 1/8 or less)"""
    j = parse(data)
    check(j)
    w, h, comps = j['w'], j['h'], j['comps']
    k = scale_for(w, h)
    bs = 8 // k                         # a block's samples across
    hmax = max(c[1] for c in comps) if len(comps) == 3 else 1
    vmax = max(c[2] for c in comps) if len(comps) == 3 else 1
    mw, mh = 8 * hmax, 8 * vmax
    mx, my = (w + mw - 1) // mw, (h + mh - 1) // mh
    if mx * hmax * bs * vmax * bs + (mx * bs * 2 * bs if len(comps) == 3 else 0) > PLANES:
        raise Bad(E_BIG)
    qs = {}
    for t, q in j['qt'].items():
        qs[t] = [0] * 64
        for i in range(64):
            qs[t][i] = ((q[i] * AAN[ZZ[i]] + 2048) >> 12) & 0xFFFF
    planes = []
    for ci, c in enumerate(comps):
        hc, vc = (c[1], c[2]) if len(comps) == 3 else (1, 1)
        planes.append([[0] * (mx * hc * bs) for _ in range(my * vc * bs)])
    order = {cid: (td, ta) for cid, td, ta in j['scan']}
    bits = Bits(data, j['data'])
    pred = [0] * len(comps)
    n = 0
    for y in range(my):
        for x in range(mx):
            if j['dri'] and n and n % j['dri'] == 0:
                bits.restart()
                pred = [0] * len(comps)
            n += 1
            for ci, c in enumerate(comps):
                hc, vc = (c[1], c[2]) if len(comps) == 3 else (1, 1)
                td, ta = order[c[0]]
                if c[3] not in qs or td not in j['dc'] or ta not in j['ac']:
                    raise Bad(E_DATA)
                q = qs[c[3]]
                for by in range(vc):
                    for bx in range(hc):
                        s = decsym(bits, j['dc'][td])
                        if s > 11:
                            raise Bad(E_DATA)
                        pred[ci] = w16(pred[ci] + extend(bits.get(s), s))
                        coef = [0] * 64
                        coef[0] = w16(pred[ci] * q[0])
                        kk = 1
                        while kk < 64:
                            rs = decsym(bits, j['ac'][ta])
                            r, s = rs >> 4, rs & 15
                            if not s:
                                if r != 15:
                                    break
                                kk += 16
                                continue
                            kk += r
                            if kk > 63:
                                raise Bad(E_DATA)
                            v = extend(bits.get(s), s)
                            if bs == 8:
                                coef[ZZ[kk]] = w16(v * q[kk])
                            kk += 1
                        if kk > 64:
                            raise Bad(E_DATA)
                        if bs == 8:
                            out = idct(coef)
                        else:
                            out = [desc(coef[0])]
                        py, px = (y * vc + by) * bs, (x * hc + bx) * bs
                        for r in range(bs):
                            planes[ci][py + r][px:px + bs] = out[r * bs:r * bs + bs]
    pw, ph = (w + k - 1) // k, (h + k - 1) // k
    rows = []
    if len(comps) == 1:
        for y in range(ph):
            rows.append([(v, v, v) for v in planes[0][y][:pw]])
        return GRAY, pw, ph, rows
    rcr, bcb, gcb, gcr = tables()
    hy, vy = comps[0][1], comps[0][2]
    for y in range(ph):
        row = []
        for x in range(pw):
            yy = planes[0][y][x]
            cb, cr = planes[1][y // vy][x // hy], planes[2][y // vy][x // hy]
            row.append((clamp(yy + rcr[cr]), clamp(yy + gcb[cb] + gcr[cr]), clamp(yy + bcb[cb])))
        rows.append(row)
    return COLOUR, pw, ph, rows


def shown(data):
    """(mode, the 16 colours, ow, oh, tw, th, tx, ty, the rows of indices)"""
    j = parse(data)
    w, h = j['w'], j['h']
    mode, pw, ph, rows = decode(data)
    if mode == GRAY:
        colours = [k * 0x111 for k in range(16)]
    else:
        colours = [(0xF00 if k >> 3 else 0) | (((k >> 1) & 3) * 5 << 4) | (0xF if k & 1 else 0) for k in range(16)]
    ow, oh, tw, th, tx, ty = png_ref.plan(w, h)
    out = []
    accy = 0
    for y in range(ph):
        accy += oh
        n = 0
        while accy >= ph:
            accy -= ph
            n += 1
        if not n:
            continue
        row = []
        acc = 0
        sums, cnt, cur = [0, 0, 0], 0, (255, 255, 255)
        oy = len(out)
        for x in range(pw):
            for c in range(3):
                sums[c] += rows[y][x][c]
            cnt += 1
            acc += ow
            while acc >= pw:
                acc -= pw
                if cnt:
                    cur = tuple((sums[c] + (cnt >> 1)) // cnt for c in range(3))
                    sums, cnt = [0, 0, 0], 0
                row.append(png_ref.dither(mode, cur, 15, len(row), oy))
        while len(row) < tw * 8:
            row.append(png_ref.dither(mode, (255, 255, 255), 15, len(row), oy))
        for _ in range(n):
            out.append(row)
    while len(out) < th * 8:
        out.append([15] * (tw * 8))
    return mode, colours, ow, oh, tw, th, tx, ty, out


def row_sums(data):
    """each decoded row's r + 2g + 3b (mod 65536), as the test hook sums it"""
    _, _, _, rows = decode(data)
    return [sum(r + 2 * g + 3 * b for r, g, b in row) & 0xFFFF for row in rows]


def scene(w, h, seed):
    """a photograph's stand-in: a sky, hills, a sun, a house, some texture"""
    from PIL import Image, ImageDraw
    rnd = random.Random(seed)
    im = Image.new('RGB', (w, h))
    px = im.load()
    for y in range(h):
        for x in range(w):
            if y < h * 0.55 + 18 * ((x * 7 // w) % 3):
                px[x, y] = (90 + y * 100 // h, 150 + y * 60 // h, 235)
            else:
                v = rnd.randrange(30)
                px[x, y] = (40 + v + x * 60 // w, 120 + v, 40 + v // 2)
    d = ImageDraw.Draw(im)
    d.ellipse((w * 0.7, h * 0.08, w * 0.85, h * 0.08 + w * 0.15), fill=(250, 220, 60))
    d.rectangle((w * 0.2, h * 0.45, w * 0.45, h * 0.75), fill=(200, 60, 50))
    d.polygon([(w * 0.18, h * 0.45), (w * 0.325, h * 0.28), (w * 0.47, h * 0.45)], fill=(110, 40, 30))
    d.rectangle((w * 0.28, h * 0.58, w * 0.33, h * 0.75), fill=(240, 240, 230))
    for _ in range(12):
        x, y = rnd.randrange(w), rnd.randrange(h)
        d.line((x, y, x + rnd.randrange(-40, 40), y + rnd.randrange(-40, 40)), fill=(0, 0, 0), width=2)
    return im


KINDS = ['photo', 'p444', 'p422', 'gray', 'restart', 'odd', 'big', 'progressive', 'corrupt']


def make(kind):
    from PIL import Image
    b = io.BytesIO()
    if kind == 'photo':             # Gemipedia's thumbnails: 440 px, 4:2:0
        scene(440, 293, 1).save(b, 'JPEG', quality=85, subsampling=2)
    elif kind == 'p444':
        scene(200, 120, 2).save(b, 'JPEG', quality=90, subsampling=0)
    elif kind == 'p422':
        scene(210, 130, 3).save(b, 'JPEG', quality=75, subsampling=1)
    elif kind == 'gray':
        scene(300, 200, 4).convert('L').save(b, 'JPEG', quality=80)
    elif kind == 'restart':
        scene(160, 100, 5).save(b, 'JPEG', quality=85, subsampling=2, restart_marker_blocks=5)
    elif kind == 'odd':             # not a multiple of the MCU, scaled up twice
        scene(101, 67, 6).save(b, 'JPEG', quality=95, subsampling=2)
    elif kind == 'big':             # 3200 x 2000: shown at 1/8 (the blocks' DC alone)
        scene(400, 250, 7).resize((3200, 2000), Image.BILINEAR).save(b, 'JPEG', quality=60, subsampling=2)
    elif kind == 'progressive':
        scene(200, 120, 8).save(b, 'JPEG', quality=85, progressive=True)
    elif kind == 'corrupt':
        scene(200, 120, 9).save(b, 'JPEG', quality=85)
        d = bytearray(b.getvalue())
        sos = d.find(b'\xff\xda')
        n = (d[sos + 2] << 8) | d[sos + 3]
        p = sos + 2 + n + 40        # (the data from its 40th byte all 1 bits: no such code)
        d[p:p + 400] = b'\xff\x00' * 200
        return bytes(d)
    return b.getvalue()


def pillow_diff(data):
    from PIL import Image
    _, pw, ph, rows = decode(data)
    im = Image.open(io.BytesIO(data)).convert('RGB')
    if im.size != (pw, ph):
        im = im.reduce(8) if (im.width + 7) // 8 == pw else im
    px = im.load()
    tot, big, n = 0, 0, 0
    for y in range(min(ph, im.height)):
        for x in range(min(pw, im.width)):
            for a, b in zip(rows[y][x], px[x, y]):
                d = abs(a - b)
                tot += d
                big = max(big, d)
                n += 1
    return tot / max(n, 1), big


if __name__ == '__main__':
    for k in sys.argv[1:] or KINDS:
        d = make(k)
        try:
            mode, pw, ph, _ = decode(d)
            m, big = pillow_diff(d) if k != 'corrupt' else (0, 0)
            print(k, len(d), pw, ph, 'mean %.2f max %d' % (m, big))
        except Bad as e:
            print(k, len(d), 'refused', e.code)
