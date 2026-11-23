#!/usr/bin/env python3
"""gate print: the PDF files tests/print.s (and Paint) wrote, checked on
the host (docs/DECISIONS.md V38).

usage: check_print.py <dir with dump.bin, console.txt and the PDF files> [outdir]
       check_print.py --paint <dir> <name.pdf> <paper: a4|letter> <fit: 0|1> [outdir]

Every file is parsed here (no PDF library needed): the header, the cross
reference table (every offset at its "n 0 obj"), the trailer, the page
tree, each page's media box, resources and content stream, every
stream's length (direct or an indirect object) against its bytes. Each
page's image (CCITT Group 4, /K -1) is decoded with libtiff (Pillow) and
compared with the bitmap it must be: the test patterns (band_page1,
band_page2, the same formulas as tests/print.s), or the screen area in
the VRAM dump scaled as PrintRect scales it. With colour: the paper
colours' image against the colour map's cards and VERA's palette, its
placement, the ink's colour. qpdf --check, if installed, must pass too.
outdir: page 1 of each file as a PNG (pdftoppm, if installed).
"""
import os
import re
import shutil
import subprocess
import sys
import zlib  # noqa: F401  (not used: the images are CCITT)

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'tools'))
import mkfax  # noqa: E402

VDUMP = 132878
MAP = 0x1AC00


def mapcol(v, x, y):
    """card x, y's colour: the classic map's, or in tile mode (Paint's since
    V147) a solid tile of palette row 0"""
    lo, hi = v[MAP + y * 256 + x * 2], v[MAP + y * 256 + x * 2 + 1]
    if v[131072 + 256 + 512 + 2] == 0x98:
        return lo if hi >> 4 == 0 and lo < 16 else 0
    return hi >> 4
FORMATS = {(0, 150): (1240, 1754, 155), (1, 150): (1275, 1650, 160),
           (0, 300): (2480, 3508, 310), (1, 300): (2550, 3300, 319)}
BOX = {0: [0, 0, 595.2, 841.92], 1: [0, 0, 612, 792]}
failures = 0


def check(cond, what):
    global failures
    print(('ok    ' if cond else 'FAIL  ') + what)
    if not cond:
        failures += 1
    return cond


# ------------------------------------------------------------- a small PDF parser
TOK = re.compile(rb'\s*(?:(<<|>>|\[|\]|/[^\s/<>\[\]()]*|<[0-9A-Fa-f\s]*>|-?\d*\.\d+|-?\d+|[A-Za-z]+))')


class Ref(tuple):
    pass


def parse(data, i):
    """the object at data[i:] -> (value, next index)"""
    m = TOK.match(data, i)
    if not m:
        raise ValueError('bad token at %d' % i)
    t, i = m.group(1), m.end()
    if t == b'<<':
        d = {}
        while True:
            m = TOK.match(data, i)
            if m.group(1) == b'>>':
                return d, m.end()
            k, i = parse(data, i)
            v, i = parse(data, i)
            d[k] = v
    if t == b'[':
        a = []
        while True:
            m = TOK.match(data, i)
            if m.group(1) == b']':
                return a, m.end()
            v, i = parse(data, i)
            a.append(v)
    if t.startswith(b'/'):
        return t.decode(), i
    if t.startswith(b'<'):
        return bytes.fromhex(re.sub(rb'\s', b'', t[1:-1]).decode()), i
    if re.match(rb'-?\d+$', t):
        m2 = re.match(rb'\s+(\d+)\s+R\b', data[i:])
        if m2:
            return Ref((int(t), int(m2.group(1)))), i + m2.end()
        return int(t), i
    if re.match(rb'-?\d*\.\d+$', t):
        return float(t), i
    return t.decode(), i              # true, false, null


class Pdf:
    def __init__(self, path):
        self.name = os.path.basename(path)
        self.data = d = open(path, 'rb').read()
        self.ok = True
        self.obj = {}
        c = lambda cond, what: check(cond, '%s: %s' % (self.name, what))   # noqa: E731
        self.c = c
        c(d.startswith(b'%PDF-1.4\n'), 'PDF 1.4 header')
        m = re.search(rb'startxref\n(\d+)\n%%EOF\n$', d)
        if not c(m is not None, 'ends with startxref and %%EOF'):
            self.ok = False
            return
        x = int(m.group(1))
        m = re.match(rb'xref\n0 (\d+)\n', d[x:])
        if not c(m is not None, 'startxref points at the xref table'):
            self.ok = False
            return
        n = int(m.group(1))
        e = x + m.end()
        ent = [d[e + 20 * k:e + 20 * k + 20] for k in range(n)]
        c(ent[0] == b'0000000000 65535 f\r\n', 'xref entry 0 free')
        offs = {}
        good = True
        for k in range(1, n):
            mm = re.match(rb'(\d{10}) 00000 n\r\n$', ent[k])
            if not mm:
                good = False
                continue
            offs[k] = int(mm.group(1))
            if not d[offs[k]:].startswith(b'%d 0 obj\n' % k):
                good = False
        c(good, 'xref: %d objects, each offset at its "n 0 obj"' % (n - 1))
        t = d[e + 20 * n:]
        mt = re.match(rb'trailer\n', t)
        tr, _ = parse(t, mt.end()) if mt else ({}, 0)
        c(tr.get('/Size') == n and tr.get('/Root') == (1, 0), 'trailer: /Size %d, /Root 1 0 R' % n)
        # the objects
        good = True
        for k, o in offs.items():
            i = o + len(b'%d 0 obj\n' % k)
            v, i = parse(d, i)
            if isinstance(v, dict) and d[i:i + 8] == b'\nstream\n':
                s0 = i + 8
                ln = v['/Length']
                if isinstance(ln, Ref):
                    ln = self.later(offs, ln[0])
                if d[s0 + ln:s0 + ln + 17] != b'\nendstream\nendobj':
                    good = False
                    print('      object %d: /Length %d does not end at endstream' % (k, ln))
                v = (v, d[s0:s0 + ln])
            elif not d[i:].startswith(b'\nendobj\n'):
                good = False
                print('      object %d: no endobj' % k)
            self.obj[k] = v
        c(good, 'every object ends with endobj; every stream\'s length is its bytes')
        cat = self.obj.get(1)
        pages = self.obj.get(2)
        c(isinstance(cat, dict) and cat.get('/Type') == '/Catalog' and cat.get('/Pages') == (2, 0),
          'object 1 the catalogue')
        self.pages = []
        if c(isinstance(pages, dict) and pages.get('/Type') == '/Pages'
             and pages.get('/Count') == len(pages.get('/Kids', [])), 'object 2 the page tree'):
            self.pages = [self.obj[r[0]] for r in pages['/Kids']]

    def later(self, offs, k):
        v, _ = parse(self.data, offs[k] + len(b'%d 0 obj\n' % k))
        return v

    def page(self, n, fmt):
        """page n's image as rows of bytes (1 = ink), its content tokens,
        its colours' image (or None)"""
        p = self.pages[n]
        W, H, rb = FORMATS[fmt]
        c = self.c
        c(p.get('/Type') == '/Page' and p.get('/Parent') == (2, 0) and p.get('/MediaBox') == BOX[fmt[0]],
          'page %d: a page of the tree, its media box %s' % (n + 1, BOX[fmt[0]]))
        xo = p['/Resources']['/XObject']
        img, data = self.obj[xo['/I'][0]]
        c(img.get('/Subtype') == '/Image' and img.get('/ImageMask') == 'true' and (img['/Width'], img['/Height']) == (W, H)
          and img.get('/Filter') == '/CCITTFaxDecode'
          and img.get('/DecodeParms') == {'/K': -1, '/Columns': W, '/Rows': H},
          'page %d: an image mask %d x %d, CCITT G4' % (n + 1, W, H))
        rows = decode(data, W, H)
        cont = self.obj[p['/Contents'][0]][1].split()
        k = None
        if '/K' in xo:
            k = self.obj[xo['/K'][0]]
        return rows, cont, k, len(data)


def decode(data, w, h):
    """libtiff: the rows, packed, 1 = black (the ink), padding 0"""
    import io
    import struct
    from PIL import Image
    tags = [(256, 4, w), (257, 4, h), (258, 3, 1), (259, 3, 4), (262, 3, 0), (273, 4, 0),
            (277, 3, 1), (278, 4, h), (279, 4, len(data)), (293, 4, 0)]
    off = 8 + 2 + 12 * len(tags) + 4
    ifd = struct.pack('<H', len(tags))
    for t, typ, v in tags:
        v = off if t == 273 else v
        ifd += struct.pack('<HHI', t, typ, 1) + (struct.pack('<HH', v, 0) if typ == 3 else struct.pack('<I', v))
    tif = b'II*\0' + struct.pack('<I', 8) + ifd + b'\0\0\0\0' + data
    im = Image.open(io.BytesIO(tif))
    im.load()
    raw = im.tobytes()               # mode 1: 1 = white
    rb = (w + 7) // 8
    pad = (0xFF << (8 - w % 8)) & 0xFF if w % 8 else 0xFF
    out = []
    for y in range(h):
        r = bytearray(255 - x for x in raw[y * rb:(y + 1) * rb])
        r[-1] &= pad
        out.append(bytes(r))
    return out


# ------------------------------------------------------------- what the pages must be
def tab():
    s, t = 1, []
    for _ in range(256):
        c = s & 1
        s >>= 1
        if c:
            s ^= 0xB8
        t.append(s)
    return t


TAB = tab()


def band_page1(y):
    r = bytearray(310)
    for b in range(310):
        bl = b & 255
        if y < 1000:
            v = 0xFF if ((y >> 4) ^ (bl >> 1)) & 1 else 0
        elif y < 1400:
            v = TAB[(y * 3 + bl) & 255] & (0xFF if y < 1100 else 0x11)
        elif (y & 63) < 24 and (bl & 7) < 5:
            v = TAB[(y + 5 * bl) & 255] & 0x7E
        else:
            v = 0
        r[b] = v
    r[0] |= 0xC0
    r[309] |= 0x03
    return bytes(r)


def band_page2(y):
    if y >= 1000:
        return bytes(310)
    return bytes(TAB[(y + (b & 255)) & 255] & TAB[(7 * y + 3 * (b & 255)) & 255] & 0x18 for b in range(310))


def vram(path):
    d = open(path, 'rb').read()
    return d[len(d) - VDUMP:]


def place(fmt, l, t, r, b, fit):
    """PrintRect's arithmetic (kernel/x/printrect.s)"""
    W, H, rb = FORMATS[fmt]
    dpi = fmt[1]
    w, h = r - l + 1, b - t + 1
    m = 37 if dpi == 150 else 75
    PW, PH = W - 2 * m, H - 2 * m
    if fit:
        Wd, Hd = PW, h * PW // w
        if Hd > PH:
            Hd, Wd = PH, w * PH // h
    else:
        den = 8 if dpi == 150 else 4
        w, h = min(w, PW * den // 15), min(h, PH * den // 15)
        Wd, Hd = w * 15 // den, h * 15 // den
    x0 = m + (PW - Wd) // 2
    return w, h, Wd, Hd, x0, m


def rect_page(v, screen, fmt, l, t, r, b, fit):
    W, H, rb = FORMATS[fmt]
    w, h, Wd, Hd, x0, y0 = place(fmt, l, t, r, b, fit)
    base = 0x9600 if screen else 0
    white = bytes(rb)
    rows = [white] * H
    for sy in range(h):
        src = v[base + (t + sy) * 80:base + (t + sy + 1) * 80]
        bits = int.from_bytes(src, 'big')
        row = 0
        for i in range(Wd):
            sx = l + i * w // Wd
            if (bits >> (639 - sx)) & 1:
                row |= 1 << (rb * 8 - 1 - (x0 + i))
        rowb = row.to_bytes(rb, 'big')
        j0 = -(-sy * Hd // h)
        j1 = -(-(sy + 1) * Hd // h)
        for j in range(j0, j1):
            rows[y0 + j] = rowb
    return rows


def frac(n):
    return {0: '0', 15: '1'}.get(n, ('%.3f' % (n / 15)).lstrip('0').rstrip('0'))


def palette(v):
    p = v[131072 + 256:]
    return [(p[2 * i + 1] & 15, p[2 * i] >> 4, p[2 * i] & 15) for i in range(16)]   # R, G, B


def compare(name, got, want):
    bad = [y for y in range(len(want)) if got[y] != want[y]]
    if bad:
        y = bad[0]
        x = next(i for i in range(len(want[y])) if got[y][i] != want[y][i])
        print('      %d rows differ, the first %d (byte %d: %02X, not %02X)' % (len(bad), y, x, got[y][x], want[y][x]))
    return check(not bad, '%s: the bitmap equals the expected one, %d rows' % (name, len(want)))


def rect_check(pdf, n, v, fmt, screen, area, fit, colour):
    rows, cont, k, size = pdf.page(n, fmt)
    W, H, rb = FORMATS[fmt]
    l, t, r, b = area
    compare('%s page %d (%s %d,%d-%d,%d, %s)' % (pdf.name, n + 1, 'back' if screen else 'fore', l, t, r, b,
                                                 'fit' if fit else '80 px an inch'),
            rows, rect_page(v, screen, fmt, l, t, r, b, fit))
    s = '0.48' if fmt[1] == 150 else '0.24'
    want = ['q', s, '0', '0', s, '0', '0', 'cm']
    if colour and check(k is not None, '%s page %d: the paper colours\' image (the map is shown)' % (pdf.name, n + 1)):
        w, h, Wd, Hd, x0, y0 = place(fmt, l, t, r, b, fit)
        card, cards = l >> 3, ((l + w - 1) >> 3) - (l >> 3) + 1
        crow, crows = t >> 3, ((t + h - 1) >> 3) - (t >> 3) + 1
        cx = x0 - (l & 7) * Wd // w
        cw = 8 * cards * Wd // w
        top = y0 - (t & 7) * Hd // h
        ch = 8 * crows * Hd // h
        cy = H - top - ch
        want += [str(x0), str(H - y0 - Hd), str(Wd), str(Hd), 're', 'W', 'n', 'q', str(cw), '0', '0', str(ch),
                 str(cx), str(cy), 'cm', '/K', 'Do', 'Q']
        kd, kdata = k
        pal = palette(v)
        check(kd.get('/Subtype') == '/Image' and (kd['/Width'], kd['/Height']) == (cards, crows)
              and kd.get('/BitsPerComponent') == 8
              and kd.get('/ColorSpace') == ['/Indexed', '/DeviceRGB', 15,
                                            bytes(17 * c for e in pal for c in e)],
              '%s page %d: the paper colours, %d x %d cards, indexed in VERA\'s 16 palette entries'
              % (pdf.name, n + 1, cards, crows))
        cards_want = bytes(mapcol(v, card + x, crow + y) for y in range(crows) for x in range(cards))
        check(kdata == cards_want, '%s page %d: each card\'s colour is the colour map\'s' % (pdf.name, n + 1))
    if colour:
        pal = palette(v)
        want += [frac(c) for c in pal[1]] + ['rg']
    want += [str(W), '0', '0', str(H), '0', '0', 'cm', '/I', 'Do', 'Q']
    got = [x.decode() for x in cont]
    if not check(got == want, '%s page %d: the content stream (%s)' % (pdf.name, n + 1, ' '.join(got))):
        print('      want: %s' % ' '.join(want))
    return size


def qpdf(path):
    if not shutil.which('qpdf'):
        print('skip  qpdf --check (no qpdf)')
        return
    r = subprocess.run(['qpdf', '--check', path], capture_output=True, text=True)
    check(r.returncode == 0 and 'No syntax or stream encoding errors' in r.stdout,
          '%s: qpdf --check' % os.path.basename(path))


def png(path, out, name, r=50):
    if out and shutil.which('pdftoppm'):
        subprocess.run(['pdftoppm', '-r', str(r), '-png', '-f', '1', '-l', '1', '-singlefile', path,
                        os.path.join(out, name)], check=False)
        return os.path.join(out, name + '.png')


def main():
    a = sys.argv[1:]
    if a and a[0] == '--paint':
        return paint(a[1:])
    if not a:
        sys.exit(__doc__)
    d = a[0]
    out = a[1] if len(a) > 1 else None
    if out:
        os.makedirs(out, exist_ok=True)
    con = open(os.path.join(d, 'console.txt'), 'rb').read().decode('latin-1')
    res = dict(re.findall(r'PRINT (\w) ([0-9A-F]{2})', con))
    want = {'a': '0E', 'b': '0E', 'c': '00', 'd': '0E', 'e': '00', 'f': '00', 'g': '00', 'h': '00', 'i': '00',
            'j': '00', 'k': '00', 'l': '00', 'm': '00', 'n': '00', 'o': '00', 'p': '00', 'q': '00', 'r': '00',
            's': '00', 't': '00', 'u': '0E', 'v': '00'}
    check(res == want and 'PRINT DONE' in con,
          'the calls\' errors: none, but INCOMPATIBLE with no document, a second PrintOpen, an empty area')
    dims = re.findall(r'DIMS (\w+) (\w+) (\w+)', con)
    check([tuple(int(x, 16) for x in t) for t in dims] == [(310, 3508, 2480), (155, 1754, 1240), (310, 3508, 2480),
                                                            (160, 1650, 1275)],
          'PrintOpen gives bytes a row, rows, dots: A4 300, A4 150, A4 300, Letter 150')
    times = {k: int(x, 16) for k, x in re.findall(r'TIME (\w) ([0-9A-F]{8})', con)}
    v = vram(os.path.join(d, 'dump.bin'))

    # BANDS.PDF: two pages of bands
    p = Pdf(os.path.join(d, 'BANDS.PDF'))
    qpdf(os.path.join(d, 'BANDS.PDF'))
    if p.ok and check(len(p.pages) == 2, 'BANDS.PDF: two pages'):
        rows, cont, k, s1 = p.page(0, (0, 300))
        compare('BANDS.PDF page 1 (3,508 rows in bands of 16 from main RAM)', rows,
                [band_page1(y) for y in range(3508)])
        rows, cont, k, s2 = p.page(1, (0, 300))
        compare('BANDS.PDF page 2 (1,000 rows in bands of 26 from a RAM bank, then PrintPage)', rows,
                [band_page2(y) for y in range(3508)])
        check(' '.join(x.decode() for x in cont) == 'q 0.24 0 0 0.24 0 0 cm 2480 0 0 3508 0 0 cm /I Do Q',
              'BANDS.PDF: the content stream draws the page\'s image over the page')
    png(os.path.join(d, 'BANDS.PDF'), out, 'bands', 30)

    sizes = {}
    p = Pdf(os.path.join(d, 'TEXT150.PDF'))
    qpdf(os.path.join(d, 'TEXT150.PDF'))
    if p.ok and check(len(p.pages) == 2, 'TEXT150.PDF: two pages'):
        sizes['150'] = rect_check(p, 0, v, (0, 150), 0, (0, 0, 639, 479), True, False)
        rect_check(p, 1, v, (0, 150), 0, (13, 7, 300, 250), False, False)
    png(os.path.join(d, 'TEXT150.PDF'), out, 'text150', 72)
    p = Pdf(os.path.join(d, 'TEXT300.PDF'))
    qpdf(os.path.join(d, 'TEXT300.PDF'))
    if p.ok and check(len(p.pages) == 1, 'TEXT300.PDF: one page'):
        sizes['300'] = rect_check(p, 0, v, (0, 300), 0, (0, 0, 639, 479), True, False)
    png(os.path.join(d, 'TEXT300.PDF'), out, 'text300', 72)
    p = Pdf(os.path.join(d, 'COLOR.PDF'))
    qpdf(os.path.join(d, 'COLOR.PDF'))
    if p.ok and check(len(p.pages) == 2, 'COLOR.PDF: two pages'):
        rect_check(p, 0, v, (1, 150), 1, (40, 20, 600, 460), True, True)
        rect_check(p, 1, v, (1, 150), 0, (13, 7, 300, 250), False, True)
    png(os.path.join(d, 'COLOR.PDF'), out, 'color', 72)
    p = Pdf(os.path.join(d, 'NONE.PDF'))
    check(p.ok and len(p.pages) == 0, 'NONE.PDF: a valid document of no pages')

    for f in ('BANDS', 'TEXT150', 'TEXT300', 'COLOR'):
        print('size  %s.PDF %d bytes' % (f, os.path.getsize(os.path.join(d, f + '.PDF'))))
    for k, what in (('1', 'BANDS.PDF page 1 (PrintBand calls)'), ('2', 'BANDS.PDF page 2 and close'),
                    ('3', 'A4 150 dpi text page (PrintRect, fit)'), ('4', 'A4 300 dpi text page (PrintRect, fit)'),
                    ('5', 'Letter 150 dpi colour page (PrintRect, fit)')):
        if k in times:
            print('time  %s: %.2f s' % (what, times[k] / 8e6))
    for k, s in sizes.items():
        print('size  the A4 %s dpi text page\'s image: %d bytes' % (k, s))
    sys.exit(1 if failures else 0)


def paint(a):
    """Paint's file/print: the drawing area (the back screen, 48,16 -
    639,479) on one page, in colour"""
    d, name, paper, fit = a[0], a[1], a[2], a[3] == '1'
    out = a[4] if len(a) > 4 else None
    fmt = (1 if paper == 'letter' else 0, 150)
    v = vram(os.path.join(d, 'dump.bin'))
    path = os.path.join(d, name)
    if not check(os.path.exists(path), '%s written' % name):
        sys.exit(1)
    p = Pdf(path)
    qpdf(path)
    if p.ok and check(len(p.pages) == 1, '%s: one page' % name):
        rect_check(p, 0, v, fmt, 1, (48, 16, 639, 479), fit, True)
    if out:
        os.makedirs(out, exist_ok=True)
        print('png   %s' % png(path, out, 'paint', 72))
    sys.exit(1 if failures else 0)


if __name__ == '__main__':
    main()
