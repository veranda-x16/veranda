#!/usr/bin/env python3
"""gate view: View's screens drawn again on a PC and compared.

usage: check_view.py <folder> <rom.bin> <png folder>
           every screen View wrote in the folder (tests/view_play.c's
           snapshots) against this file's own drawing of the same file;
           SCENE.RAW against the BMPs ExportRect made from it; the Text
           Scrap and the Photo Scrap View copied; a PNG of each screen
       check_view.py doc <folder> <rom.bin> <name>
           DOC.RAW (View started by the shell with <name>, a BMP or, by
           its .txt, a text) is the screen of <name> opened

What View draws is defined in apps/view/view.c; the functions here
follow it (the same names): the text's wrap(), draw_line(), the
pictures' load_bmp(), geometry(), draw_pic(), show_info().
"""
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'tools'))
import vdisk  # noqa: E402
sys.path.insert(0, HERE)
import uitext  # noqa: E402

# the window (Veranda Look 2, DECISIONS V79): the view at card rows 4-57,
# the text's 78 columns and its scroll bar at cards 78-79 (V148: not
# compared), the status bar's text in the UI font (vrwin.c's
# vr_win_status: from x 6, baseline 474, cut at 627 pixels; lines
# 465-479 compared)
AREAY, AREAH, AREAW, ROWS, COLS, TCOLS = 32, 432, 640, 54, 80, 78
STATY0, STATY1, STATX, STATB, STATW = 465, 480, 6, 474, 627
MAXW = 640
VPAL = [0xFFF, 0x000, 0x800, 0xAFE, 0xC4C, 0x0C5, 0x00A, 0xEE7,
        0xD85, 0x640, 0xF77, 0x333, 0x777, 0xAF6, 0x08F, 0xBBB]
SNAP = 38400 + 4800 + 4
TNAME = ["not GEOS", "BASIC", "assembly", "data", "system", "desk accessory", "application",
         "document", "font", "printer driver", "input driver", "disk driver", "boot",
         "temporary", "auto-exec", "input 128"]


def fail(m):
    print('check_view: ' + m)
    sys.exit(1)


def rom_font(rom):
    d = open(rom, 'rb').read()[6 * 16384:7 * 16384]
    smiley = bytes([0x7E, 0x81, 0xA5, 0x81, 0xBD, 0x99, 0x81, 0x7E])
    for a in range(0, 16384, 2048):
        if d[a + 8:a + 16] == smiley:
            return d[a:a + 2048]
    fail('no CP437 set in the ROM')


class Snap:
    def __init__(self, path):
        d = open(path, 'rb').read()
        if len(d) != SNAP:
            fail('%s: %d bytes, not %d' % (path, len(d), SNAP))
        self.bits = [[d[y * 80 + x // 8] >> (7 - x % 8) & 1 for x in range(640)] for y in range(480)]
        self.cards = [list(d[38400 + y * 80:38400 + y * 80 + 80]) for y in range(60)]
        self.paper = d[-4] | d[-3] << 8
        self.ink = d[-2] | d[-1] << 8

    def png(self, path):
        def rgb(v):
            return ((v >> 8 & 15) * 17, (v >> 4 & 15) * 17, (v & 15) * 17)
        ink, paper = rgb(self.ink), rgb(self.paper)
        rows = []
        for y in range(480):
            r = []
            for x in range(640):
                c = self.cards[y // 8][x // 8]
                r.append(ink if self.bits[y][x] else rgb(VPAL[c]) if c else paper)
            rows.append(r)
        vdisk.write_png(path, rows)


class Screen:
    """what View draws: the area (rows 32-463), the status cells, the
    cards, the ink"""
    def __init__(self, font):
        self.font = font
        self.bits = [[0] * 640 for _ in range(480)]
        self.cards = [[0] * 80 for _ in range(60)]
        self.ink = 0x000
        self.xmax = 640             # (a text: its scroll bar from x 624 not compared)

    def cells(self, s, x, y, rev=0):
        for i, c in enumerate(s):
            for r in range(8):
                b = self.font[c * 8 + r] ^ (0xFF if rev else 0)
                for k in range(8):
                    self.bits[y + r][(x + i) * 8 + k] = b >> (7 - k) & 1

    def field(self, s, x, w, y, rev=0):
        s = bytes(glyph(c) for c in s[:w]) + b' ' * (w - min(len(s), w))
        self.cells(s, x, y, rev)

    def status(self, s):
        uitext.put(self.bits, uitext.fit(s[:63], STATW), STATX, STATB)    # (vrwin.c: 63 characters at most)

    def text(self, s, x, y, bold=False):
        uitext.put(self.bits, s, x, y, bold)

    def compare(self, snap, what):
        for y in list(range(STATY0, STATY1)) + list(range(AREAY, AREAY + AREAH)):
            x0, x1 = (0, 640) if y >= STATY0 else (0, self.xmax)
            if snap.bits[y][x0:x1] != self.bits[y][x0:x1]:
                x = next(i for i in range(x0, x1) if snap.bits[y][i] != self.bits[y][i])
                fail('%s: the pixel at %d,%d is %d, want %d' % (what, x, y, snap.bits[y][x], self.bits[y][x]))
        for cy in range(2, 60):
            if snap.cards[cy] != self.cards[cy]:
                cx = next(i for i in range(80) if snap.cards[cy][i] != self.cards[cy][i])
                fail('%s: card %d,%d has colour %d, want %d' % (what, cx, cy, snap.cards[cy][cx], self.cards[cy][cx]))
        if snap.ink != self.ink:
            fail('%s: the ink is $%03X, want $%03X' % (what, snap.ink, self.ink))
        if snap.paper != 0xFFF:
            fail('%s: the paper is $%03X' % (what, snap.paper))


def glyph(c):
    return 46 if c < 32 or c == 127 else c


# ------------------------------------------------------------------ text
class Text:
    def __init__(self, data, name):
        self.t, self.name = data, name
        self.wrap()
        self.top, self.mat, self.mlen = 0, 0, 0

    def wrap(self):
        t, n = self.t, len(self.t)
        lines = [0]
        i = s = brk = col = 0
        while i < n:
            c = t[i]
            if c in (13, 10):
                i += 1
                if c == 13 and i < n and t[i] == 10:
                    i += 1
                s, col, brk = i, 0, 0
                if s < n:
                    lines.append(s)
                continue
            w = 8 - (col & 7) if c == 9 else 1
            if col + w > TCOLS:
                if c == 32:
                    i += 1
                    s, col = i, 0
                    if s < n:
                        lines.append(s)
                elif brk > s:
                    s = brk
                    col = self.cols(s, i)
                    lines.append(s)
                else:
                    s, col = i, 0
                    lines.append(s)
                brk = 0
                continue
            col += w
            i += 1
            if c == 32:
                brk = i
        self.lines = lines

    def cols(self, s, e):
        c = 0
        for b in self.t[s:e]:
            c += 8 - (c & 7) if b == 9 else 1
        return c

    def line(self, k):
        return self.lines[k] if k < len(self.lines) else len(self.t)

    def maxtop(self):
        return max(0, len(self.lines) - ROWS)

    def find(self, pat):
        t, n = self.t.lower(), len(pat)
        p = pat.lower()
        start = self.mat + 1 if self.mlen else self.line(self.top)
        hits = [i for i in range(start, len(t) - n + 1) if t[i:i + n] == p]
        if not hits:
            hits = [i for i in range(0, min(start, len(t) - n + 1)) if t[i:i + n] == p]
        if not hits:
            return False
        self.mat, self.mlen = hits[0], n
        k = max(i for i in range(len(self.lines)) if self.lines[i] <= self.mat)
        if k < self.top or k >= self.top + ROWS:
            self.top = min(k, self.maxtop())
        return True

    def draw(self, sc, status=None):
        sc.xmax = TCOLS * 8
        for r in range(ROWS):
            k = self.top + r
            row, h0, h1 = [], None, 0
            if k < len(self.lines):
                s, e = self.line(k), self.line(k + 1)
                col = 0
                while s < e and col < TCOLS:
                    c = self.t[s]
                    if c in (13, 10):
                        break
                    n = 8 - (col & 7) if c == 9 else 1
                    if self.mlen and self.mat <= s < self.mat + self.mlen:
                        if h0 is None:
                            h0 = col
                        h1 = col + n
                    while n and col < TCOLS:
                        row.append(32 if c == 9 else glyph(c))
                        col += 1
                        n -= 1
                    s += 1
            row = bytes(row) + b' ' * (TCOLS - len(row))
            sc.cells(row, 0, AREAY + 8 * r)
            if h0 is not None:
                h1 = min(h1, TCOLS)
                sc.cells(row[h0:h1], h0, AREAY + 8 * r, 1)
        if status is None:
            status = b'%s  %d lines  line %d' % (self.name, len(self.lines), self.top + 1)
        sc.status(status)

    def scrap(self):
        """the Text Scrap's data: the page's characters, CR LF and LF as CR"""
        out, prev = bytearray(), 0
        for c in self.t[self.line(self.top):self.line(self.top + ROWS)]:
            if c == 10 and prev == 13:
                prev = 0
                continue
            prev = c
            if c == 10:
                c = 13
            if 32 <= c < 127 or c in (9, 13):
                out.append(c)
        d = bytes([23, 9, 0, 0]) + bytes(out)
        return struct.pack('<H', len(d)) + d


# ------------------------------------------------------------------ pictures
class Pic:
    """bits[ih][iw], cards[ch][cw] (paper), hascol, ink ($0RGB), inkcell"""
    def __init__(self, bits, cards, ink, inkcell, src, name, extra=b''):
        self.bits, self.cards, self.ink, self.inkcell = bits, cards, ink, inkcell
        self.iw, self.ih = len(bits[0]), len(bits)
        self.hascol = any(any(r) for r in cards)
        self.src, self.name, self.extra = src, name, extra
        self.fit = self.iw > AREAW or self.ih > AREAH
        self.px = self.py = 0

    def geometry(self):
        iw, ih = self.iw, self.ih
        if not self.fit:
            return min(iw - self.px, AREAW), min(ih - self.py, AREAH)
        if iw <= AREAW and ih <= AREAH:
            z = min(AREAW // iw, AREAH // ih)
            return iw * z, ih * z
        if iw * AREAH > ih * AREAW:
            return AREAW, max(1, ih * AREAW // iw)
        return max(1, iw * AREAH // ih), AREAH

    def draw(self, sc):
        dw, dh = self.geometry()
        for y in range(AREAH):
            if y >= dh:
                continue
            sy = y * self.ih // dh if self.fit else y + self.py
            for x in range(min(dw, 640)):
                sx = x * self.iw // dw if self.fit else x + self.px
                sc.bits[AREAY + y][x] = self.bits[sy][sx]
        if self.hascol:
            for cy in range(AREAH // 8):
                y = cy * 8
                for cx in range(COLS):
                    x, c = cx * 8, 0
                    if y < dh and x < dw:
                        sy = y * self.ih // dh if self.fit else y + self.py
                        sx = x * self.iw // dw if self.fit else x + self.px
                        c = self.cards[sy >> 3][sx >> 3]
                    sc.cards[cy + AREAY // 8][cx] = c
        sc.ink = self.ink
        st = b'%s  %s%s  %d x %d' % (self.name, self.src, self.extra, self.iw, self.ih)
        st += b'  fit' if self.fit else b'  1:1 at %d,%d' % (self.px, self.py)
        sc.status(st)

    def pan(self, dx, dy):
        mx = (self.iw - AREAW + 7) & ~7 if self.iw > AREAW else 0
        my = (self.ih - AREAH + 7) & ~7 if self.ih > AREAH else 0
        self.px = max(0, min(mx, self.px + dx))
        self.py = max(0, min(my, self.py + dy))


def u32(d, o):
    return struct.unpack_from('<I', d, o)[0]


def lum(b, g, r):
    return (r * 77 + g * 150 + b * 29) >> 8


def nearest(r, g, b):
    best, bd = 2, 1 << 30
    for i in range(2, 16):
        dr, dg, db = (r >> 4) - (VPAL[i] >> 8), (g >> 4) - (VPAL[i] >> 4 & 15), (b >> 4) - (VPAL[i] & 15)
        d = dr * dr + dg * dg + db * db
        if d < bd:
            bd, best = d, i
    return best


def inkof(rgb):
    return next((i for i in range(1, 16) if VPAL[i] == rgb), 1)


def bmp(d, name):
    """load_bmp(): the picture as View keeps it"""
    off, w, hh, bpp = u32(d, 10), u32(d, 18), struct.unpack_from('<i', d, 22)[0], d[28]
    h = abs(hh)
    npal = u32(d, 46) or (1 << bpp if bpp <= 8 else 0)
    p0 = 14 + u32(d, 14)
    pal = [tuple(d[p0 + 4 * i:p0 + 4 * i + 3]) for i in range(npal)]     # (b, g, r)
    k = 1
    while (w + k - 1) // k > MAXW:
        k += 1
    ow, oh = (w + k - 1) // k, (h + k - 1) // k
    stride = (w * bpp + 31) // 32 * 4
    bits = [[0] * ow for _ in range(oh)]
    cw, ch = (ow + 7) // 8, (oh + 7) // 8
    cards = [[0] * cw for _ in range(ch)]
    hist = {}

    def rgb12(p):
        return (p[2] >> 4) << 8 | (p[1] >> 4) << 4 | p[0] >> 4
    inkbit, cmap = 1, list(range(16))
    if bpp == 1:
        inkbit = 0 if lum(*pal[0]) < lum(*pal[1]) else 1
        ink = rgb12(pal[inkbit])
    elif bpp == 4:
        ink = rgb12(pal[1])
        cmap = [0, 1] + [nearest(pal[i][2], pal[i][1], pal[i][0]) for i in range(2, 16)]
    else:
        ink = 0
    for fy in range(h):
        y = h - 1 - fy if hh > 0 else fy
        if y % k:
            continue
        y //= k
        rb = d[off + fy * stride:off + (fy + 1) * stride]
        for sx in range(0, w, k):
            x = sx // k
            if bpp == 1:
                v = int((rb[sx >> 3] >> (7 - (sx & 7)) & 1) == inkbit)
            elif bpp == 4:
                v = rb[sx >> 1] & 15 if sx & 1 else rb[sx >> 1] >> 4
            elif bpp == 8:
                v = int(lum(*pal[rb[sx]]) < 128)
            else:
                v = int(lum(*rb[3 * sx:3 * sx + 3]) < 128)
            if bpp == 4 and v != 1:
                hist.setdefault((x >> 3, y >> 3), [0] * 16)[cmap[v]] += 1
            elif v:
                bits[y][x] = 1
    for (cx, cy), hs in hist.items():
        best = max(range(16), key=lambda i: (hs[i], -i))
        cards[cy][cx] = best if hs[best] else 0
    return Pic(bits, cards, ink, inkof(ink), b'BMP', name, b' %d bpp' % bpp)


def scrap_pic(data, name, src, extra=b''):
    """load_scrap(): a Photo Scrap's bits and, if any, its colours"""
    w, h = data[0], data[1] | data[2] << 8
    raw, used = vdisk.bitmap_unpack(data[3:], w * h)
    bits = [[raw[y * w + x // 8] >> (7 - x % 8) & 1 for x in range(w * 8)] for y in range(h)]
    ch = (h + 7) // 8
    cards = [[0] * w for _ in range(ch)]
    rest = data[3 + used:]
    if rest:
        try:
            cols, _ = vdisk.bitmap_unpack(rest, w * ch)
        except vdisk.ImageError:
            cols = b''
        for i, c in enumerate(cols):
            cards[i // w][i % w] = c & 15
    return Pic(bits, cards, 0x000, 1, src, name, extra)


def paint_pic(cvt, name):
    bits, cmap, ink = vdisk.paint_decode(cvt)
    ink = ink if 2 <= ink < 16 else 1
    return Pic(bits, cmap, VPAL[ink], ink, b'Paint', name)


# ------------------------------------------------------------------ info
IX, VX, IR = 16, 120, 624


def info_screen(sc, cvt, name):
    """view.c's show_info (V148): the UI font, the labels in a column"""
    e, info, _ = vdisk.parse_cvt(cvt) if cvt[21] == 1 else (cvt[:30], bytes(2) + cvt[254:508], None)
    icon = info[5:68]
    for y in range(21):
        for x in range(24):
            sc.bits[44 + y][16 + x] = icon[y * 3 + x // 8] >> (7 - x % 8) & 1

    def until(b, n):
        out = bytearray()
        for c in b[:n]:
            if c in (0, 0xA0):
                break
            out.append(c)
        return bytes(out)
    t = info[69]
    sc.text(until(e[3:19], 16), 56, 54, True)
    sc.text((TNAME[t] if t < 16 else 'other').encode() + (b', VLIR' if e[21] == 1 else b', sequential'), 56, 68)
    for x in range(IX, IR):
        sc.bits[78][x] = 1
    rows = [(b'Class', until(info[77:], 20)), (b'Author', until(info[97:], 20)),
            (b'Application', until(info[117:], 20)),
            (b'Date', b'%d-%02d-%02d  %02d:%02d' % (1900 + e[23], e[24] % 100, e[25] % 100, e[26] % 100, e[27] % 100)),
            (b'Size', b'%d blocks' % (e[28] | e[29] << 8)), (b'File', until(name, 47))]
    if info[137:141] == b'VRND':
        ln = b'API %d' % info[141]
        first = True
        for i in range(0, 16, 4):
            if not info[144 + i]:
                continue
            ln += b', opens ' if first else b' '
            first = False
            ln = (ln + info[144 + i:148 + i]).rstrip(b' ')
        rows.append((b'Veranda', ln))
    y = 98
    for label, v in rows:
        sc.text(label, IX, y)
        sc.text(v, VX, y)
        y += 14
    sc.text(b'Description', IX, y)
    d = until(info[160:256], 96)
    i = 0
    while i < len(d):
        w, b, n = 0, 0, 0
        while i + n < len(d):
            w += uitext.cw(d[i + n])
            if w > IR - VX:
                break
            if d[i + n] == 32:
                b = n + 1
            n += 1
        if i + n < len(d) and b:
            n = b
        sc.text(d[i:i + n], VX, y)
        i += n
        y += 14
    sc.status(name + b'  info')


# ------------------------------------------------------------------ the checks
def visible(s, cx, cy):
    """a card's paper as a picture can show it: none (0) when every pixel
    of the card is ink"""
    full = all(s.bits[cy * 8 + r][cx * 8 + k] for r in range(8) for k in range(8))
    return 0 if full else s.cards[cy][cx]


def check_scene(folder):
    """the BMPs ExportRect wrote equal SCENE.RAW (DECISIONS V28, V32)"""
    sc = Snap(os.path.join(folder, 'SCENE.RAW'))
    d = open(os.path.join(folder, 'Line.bmp'), 'rb').read()
    if d[:2] != b'BM' or d[28] != 1 or u32(d, 18) != 400 or u32(d, 22) != 300:
        fail('Line.bmp is not a 400 x 300 1 bpp BMP')
    p = bmp(d, b'Line.bmp')
    for y in range(300):
        if p.bits[y] != sc.bits[40 + y][44:444]:
            fail('Line.bmp: row %d is not the scene\'s' % y)
    if p.ink != sc.ink:
        fail('Line.bmp: its ink $%03X, the scene $%03X' % (p.ink, sc.ink))
    d = open(os.path.join(folder, 'Color.bmp'), 'rb').read()
    if d[28] != 4 or u32(d, 18) != 640 or u32(d, 22) != 480:
        fail('Color.bmp is not a 640 x 480 4 bpp BMP')
    p = bmp(d, b'Color.bmp')
    for y in range(480):
        if p.bits[y] != sc.bits[y]:
            fail('Color.bmp: row %d is not the scene\'s' % y)
    for cy in range(60):
        for cx in range(80):
            if p.cards[cy][cx] != visible(sc, cx, cy):
                fail('Color.bmp: card %d,%d is %d, the scene %d' % (cx, cy, p.cards[cy][cx], sc.cards[cy][cx]))
    print('check_view: Line.bmp (1 bpp, 400 x 300 from x 44) and Color.bmp (4 bpp, the whole screen) '
          'equal the scene ExportRect wrote them from: the bits, the cards\' colours, the ink $%03X' % sc.ink)
    sc.png(os.path.join(PNG, 'scene.png'))


def snap(folder, name, sc, what):
    s = Snap(os.path.join(folder, name))
    sc.compare(s, what)
    png = os.path.join(PNG, name.lower().replace('.raw', '.png'))
    s.png(png)
    print('check_view: %-26s equal to the drawing here (%s)' % (what, png))


def new(font):
    return Screen(font)


def main():
    global PNG
    if sys.argv[1] == 'doc':
        folder, rom, name = sys.argv[2], sys.argv[3], sys.argv[4]
        PNG = folder
        sc = new(rom_font(rom))
        d = open(os.path.join(folder, name), 'rb').read()
        if name.lower().endswith('.txt'):       # (gate help, V134: the manual as text)
            Text(d, name.encode()).draw(sc)
        else:
            bmp(d, name.encode()).draw(sc)
        snap(folder, 'DOC.RAW', sc, 'the shell\'s ' + name)
        return
    folder, rom, PNG = sys.argv[1], sys.argv[2], sys.argv[3]
    os.makedirs(PNG, exist_ok=True)
    font = rom_font(rom)
    f = lambda n: open(os.path.join(folder, n), 'rb').read()   # noqa: E731
    check_scene(folder)

    t = Text(f('Readme.txt'), b'Readme.txt')
    sc = new(font)
    t.draw(sc)
    snap(folder, 'TEXT1.RAW', sc, 'Readme.txt')
    for n, what in ((2, 'find NEEDLE'), (3, 'find again')):
        if not t.find(b'NEEDLE'):
            fail('no needle')
        sc = new(font)
        t.draw(sc, b'Readme.txt  "NEEDLE" at line %d' % (t.top + 1))
        snap(folder, 'TEXT%d.RAW' % n, sc, what)
    e, info, data = vdisk.parse_cvt(f('Text  Scrap.cvt'))
    if data[:len(t.scrap())] != t.scrap() or info[77:93] != b'Text  Scrap V2.0':
        fail('the Text Scrap is not the page shown')
    print('check_view: copy: the Text Scrap holds the page shown (%d bytes, CR at each line\'s end)' % len(t.scrap()))

    sc = new(font)
    bmp(f('Line.bmp'), b'Line.bmp').draw(sc)
    snap(folder, 'BMP1.RAW', sc, 'Line.bmp (1 bpp, 1:1)')
    p = bmp(f('Color.bmp'), b'Color.bmp')
    sc = new(font)
    p.draw(sc)
    snap(folder, 'BMP4F.RAW', sc, 'Color.bmp (4 bpp, fit)')
    p.fit = False
    for _ in range(4):
        p.pan(0, 8)
    sc = new(font)
    p.draw(sc)
    snap(folder, 'BMP4A.RAW', sc, 'Color.bmp (1:1, panned)')
    scn = Snap(os.path.join(folder, 'SCENE.RAW'))
    shown = Snap(os.path.join(folder, 'BMP4A.RAW'))
    a, b = AREAY, AREAY + AREAH
    if shown.bits[a:b] != scn.bits[a:b] or shown.ink != scn.ink or any(
            shown.cards[cy][cx] != visible(scn, cx, cy) for cy in range(a // 8, b // 8) for cx in range(80)):
        fail('Color.bmp panned to 0,%d is not the scene\'s rows %d-%d' % (a, a, b - 1))
    print('check_view: Color.bmp at 1:1 panned to 0,%d shows the scene\'s rows %d-%d as they were (bits, cards, ink)'
          % (a, a, b - 1))
    e, info, data = vdisk.parse_cvt(f('Photo Scrap.cvt'))
    got = scrap_pic(data, b'', b'')
    if got.bits != p.bits or got.cards != p.cards:
        fail('the Photo Scrap is not Color.bmp')
    print('check_view: copy: the Photo Scrap is Color.bmp, 640 x 480 with its cards\' colours')

    sc = new(font)
    paint_pic(f('Picture.cvt'), b'Picture.cvt').draw(sc)
    snap(folder, 'PAINT.RAW', sc, 'Picture.cvt (Paint)')
    sc = new(font)
    scrap_pic(vdisk.parse_cvt(f('Sunset.cvt'))[2], b'Sunset.cvt', b'Photo Scrap').draw(sc)
    snap(folder, 'SCRAP.RAW', sc, 'Sunset.cvt (Photo Scrap)')
    recs = [r for r in vdisk.parse_cvt(f('Album.cvt'))[2] if r is not None]
    for i, r in enumerate(recs):
        sc = new(font)
        scrap_pic(r, b'Album.cvt', b'album', b' %d/%d' % (i + 1, len(recs))).draw(sc)
        snap(folder, 'ALBUM%d.RAW' % (i + 1), sc, 'Album.cvt page %d' % (i + 1))
    sc = new(font)
    info_screen(sc, f('View.cvt'), b'View.cvt')
    snap(folder, 'INFO.RAW', sc, 'View.cvt (info)')
    sc = new(font)
    Text(f('Line.bmp'), b'Line.bmp').draw(sc)
    snap(folder, 'ASTEXT.RAW', sc, 'Line.bmp as text')
    long = 'Holiday photos from the lake 2026.bmp'      # (the Open dialog: V82)
    if f(long) != f('Line.bmp'):
        fail('%s is not Line.bmp\'s picture (the scene exports both)' % long)
    sc = new(font)
    bmp(f(long), long.encode()).draw(sc)
    snap(folder, 'LONG.RAW', sc, long + ' (the Open dialog)')


if __name__ == '__main__':
    main()
