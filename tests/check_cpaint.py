#!/usr/bin/env python3
"""gate cpaint (DECISIONS V167): Colour Paint's session against a Python
reference of its tools (apps/cpaint/draw.c: the same algorithms).

usage: check_cpaint.py oldpic <dir>          Oldpic's records (Paint's black and
                                              white format) as rec0.bin .. rec29.bin
       check_cpaint.py run <run dir>         the session's checks

run: the steps of tests/cpaint_script.py replayed on a 320 x 240 picture
(the pencil's and eraser's samples from the console's "CPS" lines);
STEPA.PIC .. (the test build's snapshots) equal each step's picture byte for
byte; the undo gives back the step before; Colours.cvt (the save) is a
VLIR file of class "PaintColour V1.0" whose record 0 and 10 bands decode
to the picture saved (SAVED.PIC), OPENED0.PIC (it opened again) the same;
OPENED1.PIC Paint's Oldpic at half size; the dump's view (scrolled to 40,
14) shows the picture; the TIME lines.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'tools'))
import cpaint_script as cs  # noqa: E402
import check_paint  # noqa: E402
import vram2png  # noqa: E402

PW, PH = 320, 240


def fail(msg):
    print('FAIL  ' + msg)
    sys.exit(1)


def cdiv(a, b):
    """C's division (toward zero)"""
    q = abs(a) // abs(b)
    return q if (a >= 0) == (b > 0) else -q


class Pic:
    def __init__(self):
        self.p = bytearray(PW * PH)
        self.a, self.b = 1, 0

    def plot(self, x, y, c):
        if 0 <= x < PW and 0 <= y < PH:
            self.p[y * PW + x] = c

    def get(self, x, y):
        return self.p[y * PW + x]

    def span(self, l, r, y, c):
        if not 0 <= y < PH:
            return
        l, r = max(l, 0), min(r, PW - 1)
        for x in range(l, r + 1):
            self.p[y * PW + x] = c

    def line(self, x0, y0, x1, y1):
        dx, sx = abs(x1 - x0), 1 if x1 >= x0 else -1
        dy, sy = -abs(y1 - y0), 1 if y1 >= y0 else -1
        err = dx + dy
        while True:
            self.plot(x0, y0, self.a)
            if x0 == x1 and y0 == y1:
                break
            e2 = 2 * err
            if e2 >= dy:
                err += dy
                x0 += sx
            if e2 <= dx:
                err += dx
                y0 += sy

    def rect(self, l, t, r, b, filled):
        if filled:
            for y in range(t + 1, b):
                self.span(l + 1, r - 1, y, self.b)
        self.span(l, r, t, self.a)
        self.span(l, r, b, self.a)
        for y in range(t + 1, b):
            self.span(l, l, y, self.a)
            self.span(r, r, y, self.a)

    def oval(self, l, t, r, b, filled):
        mn, mx = {}, {}

        def op(x, y):
            if not 0 <= y < PH:
                return
            mn[y] = min(mn.get(y, 32767), x)
            mx[y] = max(mx.get(y, -32768), x)
            self.plot(x, y, self.a)
        a, bb = r - l, b - t
        b1 = bb & 1
        dx = 4 * (1 - a) * bb * bb
        dy = 4 * (b1 + 1) * a * a
        err = dx + dy + b1 * a * a
        x0, x1 = l, r
        y0 = t + (bb + 1) // 2
        y1 = y0 - b1
        a8, b8 = 8 * a * a, 8 * bb * bb
        while True:
            op(x1, y0)
            op(x0, y0)
            op(x0, y1)
            op(x1, y1)
            e2 = 2 * err
            if e2 <= dy:
                y0 += 1
                y1 -= 1
                dy += a8
                err += dy
            if e2 >= dx or 2 * err > dy:
                x0 += 1
                x1 -= 1
                dx += b8
                err += dx
            if x0 > x1:
                break
        while y0 - y1 < bb:
            op(x0 - 1, y0)
            op(x1 + 1, y0)
            y0 += 1
            op(x0 - 1, y1)
            op(x1 + 1, y1)
            y1 -= 1
        if filled:
            for y in range(t + 1, b):
                if y in mn and mn[y] < mx[y] - 1:
                    self.span(mn[y] + 1, mx[y] - 1, y, self.b)

    def erase(self, x, y):
        for k in range(8):
            self.span(x, x + 7, y + k, 0)

    def erase_to(self, lx, ly, x, y):
        dx, dy = x - lx, y - ly
        n = max(abs(dx), abs(dy))
        s = cdiv(n, 4)
        for i in range(1, s + 1):
            self.erase(lx + cdiv(dx * i, s), ly + cdiv(dy * i, s))
        self.erase(x, y)

    def stamp(self, x, y):
        """the brush's disc: rows 3, 5, 5, 5, 3 wide (V171)"""
        for dy, w in ((-2, 1), (-1, 2), (0, 2), (1, 2), (2, 1)):
            self.span(x - w, x + w, y + dy, self.a)

    def brush(self, x0, y0, x1, y1):
        dx, sx = abs(x1 - x0), 1 if x1 >= x0 else -1
        dy, sy = -abs(y1 - y0), 1 if y1 >= y0 else -1
        err = dx + dy
        while True:
            self.stamp(x0, y0)
            if x0 == x1 and y0 == y1:
                break
            e2 = 2 * err
            if e2 >= dy:
                err += dy
                x0 += sx
            if e2 <= dx:
                err += dx
                y0 += sy

    seed = 1

    def rnd17(self):
        Pic.seed = (Pic.seed * 25173 + 13849) & 0xFFFF
        return (Pic.seed >> 8) % 17 - 8

    def spray(self, x, y):
        for _ in range(8):
            while True:
                dx, dy = self.rnd17(), self.rnd17()
                if dx * dx + dy * dy <= 64:
                    break
            self.plot(x + dx, y + dy, self.a)

    def fill(self, x, y):
        old = self.get(x, y)
        if old == self.a:
            return
        todo = [(x, y)]
        seen = {(x, y)}
        while todo:
            px, py = todo.pop()
            self.p[py * PW + px] = self.a
            for qx, qy in ((px - 1, py), (px + 1, py), (px, py - 1), (px, py + 1)):
                if 0 <= qx < PW and 0 <= qy < PH and (qx, qy) not in seen and self.get(qx, qy) == old:
                    seen.add((qx, qy))
                    todo.append((qx, qy))


def dither(pic, pal, w, h):
    """export.c's: 2 x 2 dots a pixel, as many ink as its colour is dark;
    rows of w // 4 bytes"""
    lvl = []
    for v in pal:
        s_ = ((v >> 8) & 15) + ((v >> 4) & 15) + (v & 15)
        lvl.append(((45 - s_) * 4 + 22) // 45)
    rows = []
    for y in range(h):
        a, b = bytearray(w // 4), bytearray(w // 4)
        for x in range(w):
            ll = lvl[pic[y * PW + x]]
            d, m = x >> 2, 0x80 >> ((x & 3) * 2)
            if ll >= 1:
                a[d] |= m
            if ll >= 2:
                b[d] |= m >> 1
            if ll >= 3:
                a[d] |= m >> 1
            if ll >= 4:
                b[d] |= m
        rows += [bytes(a), bytes(b)]
    return rows


def exports(d, pic, defpal):
    """(V172) Untitled BW.cvt (Paint's format, version 1, dithered),
    Untitled.bmp, Untitled.pdf (640 x 480 dots), the picture of the last
    step with the palette editor's entry 5"""
    import struct
    import check_print
    pal = list(defpal)
    pal[5] = 0x0F0F
    f = os.path.join(d, 'Untitled BW.cvt')
    if not os.path.exists(f):
        fail('no Untitled BW.cvt (export for Paint)')
    cvt = open(f, 'rb').read()
    if b'Paint Image V1.0' not in cvt[:512]:
        fail('Untitled BW.cvt: not of class Paint Image V1.0')
    recs = check_paint.records(cvt)
    if recs[0] != b'VPNT\x01\x4a\x10\x1d' or len(recs) != 30:
        fail('Untitled BW.cvt: record 0 %r, %d records' % (recs[0], len(recs)))
    want = dither(pic, pal, 296, 232)
    got = b''.join(check_paint.unpack(recs[1 + b], 74 * 16) for b in range(29))
    if got != b''.join(r[:74] for r in want):
        fail('Untitled BW.cvt: the dots are not the dither of the picture')
    f = os.path.join(d, 'Untitled.bmp')
    bmp = open(f, 'rb').read() if os.path.exists(f) else b''
    if len(bmp) != 1078 + 76800 or bmp[:2] != b'BM' or struct.unpack_from('<iiHH', bmp, 18) != (320, 240, 1, 8):
        fail('Untitled.bmp: %d bytes, not an 8-bit BMP of 320 x 240' % len(bmp))
    for i in range(256):
        v = pal[i]
        if bmp[54 + 4 * i:58 + 4 * i] != bytes([(v & 15) * 17, (v >> 4 & 15) * 17, (v >> 8 & 15) * 17, 0]):
            fail('Untitled.bmp: palette entry %d' % i)
    for y in range(240):
        if bmp[1078 + (239 - y) * 320:1078 + (240 - y) * 320] != pic[y * PW:(y + 1) * PW]:
            fail('Untitled.bmp: row %d' % y)
    f = os.path.join(d, 'Untitled.pdf')
    if not os.path.exists(f):
        fail('no Untitled.pdf (print)')
    pdf = check_print.Pdf(f)
    if not pdf.ok or len(pdf.pages) != 1:
        fail('Untitled.pdf: not a PDF of one page')
    xo = pdf.pages[0]['/Resources']['/XObject']
    img, data = pdf.obj[xo['/I'][0]]
    if (img['/Width'], img['/Height']) != (1240, 1754):
        fail('Untitled.pdf: the page image %d x %d, want A4 at 150 dpi' % (img['/Width'], img['/Height']))
    rows = check_print.decode(data, 1240, 1754)
    want = dither(pic, pal, 320, 240)
    if [r[:80] for r in rows[:480]] != want or any(any(r[80:]) for r in rows[:480]) or any(any(r) for r in rows[480:]):
        fail('Untitled.pdf: the page is not the dither of the picture at its top left')
    print('ok    exports: for Paint (Untitled BW.cvt, version 1, 29 bands: the picture\'s 296 x 232 dithered to 2 x 2 '
          'dots each), as BMP (8 bits, the palette with entry 5 edited, the rows), printed (A4 at 150 dpi: 640 x 480 dots at '
          'the top left, the same dither): each as the reference')


def old_picture():
    """Oldpic: Paint's 592 x 464, one bit a pixel, ink 1 (a pattern)"""
    rows = []
    for y in range(464):
        row = bytearray(74)
        for x in range(592):
            ink = (x // 37 + y // 29) % 3 == 0 or abs(x - y) < 3 or (x - 300) ** 2 + (y - 230) ** 2 < 90 ** 2 \
                and (x + y) % 7 < 2
            if ink:
                row[x >> 3] |= 0x80 >> (x & 7)
        rows.append(bytes(row))
    return rows


def packbits(data):
    out, i = bytearray(), 0
    while i < len(data):
        j = i + 1
        while j < len(data) and j - i < 128 and data[j] == data[i]:
            j += 1
        if j - i >= 3:
            out += bytes([257 - (j - i), data[i]])
            i = j
            continue
        j = i
        while j < len(data) and j - i < 128 and not (j + 2 < len(data) and data[j] == data[j + 1] == data[j + 2]):
            j += 1
        out += bytes([j - i - 1]) + data[i:j]
        i = j
    return bytes(out)


def oldpic(d):
    rows = old_picture()
    open(os.path.join(d, 'rec0.bin'), 'wb').write(b'VPNT' + bytes([3, 74, 16, 29, 1]))
    for b in range(29):
        open(os.path.join(d, 'rec%d.bin' % (b + 1)), 'wb').write(packbits(b''.join(rows[b * 16:b * 16 + 16])))


def old_expected():
    rows = old_picture()
    p = bytearray(PW * PH)
    for y in range(232):
        for x in range(296):
            k = 0
            for (sx, sy) in ((2 * x, 2 * y), (2 * x + 1, 2 * y), (2 * x, 2 * y + 1), (2 * x + 1, 2 * y + 1)):
                if rows[sy][sx >> 3] & (0x80 >> (sx & 7)):
                    k = 1
            p[y * PW + x] = k
    return p


def first_diff(a, b):
    for i in range(min(len(a), len(b))):
        if a[i] != b[i]:
            return '(%d, %d): %d, want %d' % (i % PW, i // PW, a[i], b[i])
    return 'lengths %d, %d' % (len(a), len(b))


def run(d):
    con = open(os.path.join(d, 'console.txt'), errors='replace').read().replace('\r', '')
    lines = [ln.strip() for ln in con.split('\n')]
    # the strokes' samples: CPS lines until each "CPAINT STROKE"
    strokes, cur = [], []
    for ln in lines:
        m = re.match(r'CPS ([0-9A-F]{3}) ([0-9A-F]{2})$', ln)
        if m:
            cur.append((int(m.group(1), 16), int(m.group(2), 16)))
        elif ln == 'CPAINT STROKE':
            strokes.append(cur)
            cur = []
    pic = Pic()
    sel, clip, pal_clicks = None, [], []
    scr = [0, 0]
    tool = cs.PENCIL
    snaps = []
    stroke_i = 0
    hist = []

    def pp(pt):
        return (min(max(pt[0] - cs.VX + scr[0], 0), PW - 1), min(max(pt[1] - cs.VY + scr[1], 0), PH - 1))
    for s in cs.STEPS:
        k = s[0]
        if k == 'colour_a':
            pic.a = s[1]
        elif k == 'colour_b':
            pic.b = s[1]
        elif k == 'tool':
            tool = s[1]
        elif k == 'pencil':
            if stroke_i >= len(strokes):
                fail('stroke %d: no samples in the console' % stroke_i)
            sm = strokes[stroke_i]
            stroke_i += 1
            hist.append(bytes(pic.p))
            if tool == cs.BRUSH:
                pic.brush(*sm[0], *sm[0])
                for i in range(1, len(sm)):
                    pic.brush(*sm[i - 1], *sm[i])
            elif tool == cs.SPRAY:
                for pt in sm:
                    pic.spray(*pt)
            elif tool == cs.ERASER:
                pic.erase(*sm[0])
                for i in range(1, len(sm)):
                    pic.erase_to(*sm[i - 1], *sm[i])
            else:
                pic.line(*sm[0], *sm[0])
                for i in range(1, len(sm)):
                    pic.line(*sm[i - 1], *sm[i])
        elif k == 'drag':
            (x0, y0), (x1, y1) = pp(s[1]), pp(s[2])
            l, r, t, b = min(x0, x1), max(x0, x1), min(y0, y1), max(y0, y1)
            if tool == cs.SELECT:
                sel = (l, t, r, b)
                continue
            hist.append(bytes(pic.p))
            if tool == cs.LINE:
                pic.line(x0, y0, x1, y1)
            elif tool in (cs.RECT, cs.BOX):
                pic.rect(l, t, r, b, tool == cs.BOX)
            elif tool in (cs.OVAL, cs.DISC):
                pic.oval(l, t, r, b, tool == cs.DISC)
        elif k == 'click':
            x, y = pp(s[1])
            if tool == cs.FILL:
                hist.append(bytes(pic.p))
                pic.fill(x, y)
            elif tool == cs.PICK:
                pic.a = pic.get(x, y)
        elif k == 'menu' and s[1] == 'edit' and s[2] == 0:
            pic.p = bytearray(hist.pop())
        elif k == 'menu' and s[1] == 'edit' and s[2] in (1, 2):      # cut, copy
            l, t, r, b = sel
            clip = [bytes(pic.p[y * PW + l:y * PW + r + 1]) for y in range(t, b + 1)]
            if s[2] == 1:
                for y in range(t, b + 1):
                    pic.span(l, r, y, 0)
        elif k == 'paste':
            x, y = pp(s[1])
            for j, row in enumerate(clip):
                for i, c in enumerate(row):
                    if 0 <= x + i < PW and 0 <= y + j < PH:
                        pic.p[(y + j) * PW + x + i] = c
        elif k == 'textat':
            box = [ln for ln in lines if ln.startswith('CPB ')]
            rows = [ln for ln in lines if ln.startswith('CPT ')]
            if not box or not rows:
                fail('the text: no CPB or CPT lines in the console')
            bl, bt, br, bb = [int(v, 16) for v in box[0].split()[1:]]
            for ln in rows:
                f = ln.split()
                y, cx0, bits = int(f[1], 16), int(f[2], 16), bytes.fromhex(f[3])
                for k2, m in enumerate(bits):
                    for bit in range(8):
                        x = (cx0 + k2) * 8 + bit
                        if m & (0x80 >> bit) and bl <= x <= br:
                            pic.plot(x - cs.VX + scr[0], y - cs.VY + scr[1], pic.a)
        elif k == 'palclick':
            pal_clicks.append(s[1])
        elif k == 'key' and s[1] == cs.RIGHT:
            scr[0] = min(scr[0] + 8, PW - cs.VW)
        elif k == 'key' and s[1] == cs.DOWN:
            scr[1] = min(scr[1] + 8, PH - cs.VH)
        elif k == 'snap':
            snaps.append(bytes(pic.p))
    names = ['pencil', 'line', 'rectangle', 'filled rectangle', 'oval', 'filled oval', 'fill (inside; 6 seeds: its passes)',
             'fill (the background)', 'eraser', 'eyedropper, pencil', 'undo',
             'scrolled, pencil', 'brush', 'spray', 'text', 'copy, paste', 'cut', 'the palette (the picture unchanged)']
    for i, want in enumerate(snaps):
        f = os.path.join(d, 'STEP%s.PIC' % chr(65 + i))
        if not os.path.exists(f):
            fail('STEP%s.PIC (%s): not written' % (chr(65 + i), names[i]))
        got = open(f, 'rb').read()
        if got != want:
            n = sum(1 for a, b in zip(got, want) if a != b)
            fail('step %d (%s): %d bytes differ from the reference, first %s' % (i, names[i], n, first_diff(got, want)))
    print('ok    each tool exactly as the reference (%s): %d steps' % (', '.join(names), len(snaps)))
    # (V171) the Photo Scrap of the copy: black and white, a pixel ink when
    # its palette colour's R + G + B < 23
    import glob
    import check_clip
    defpal = []
    for ln in open(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'apps', 'cpaint', 'defpal.h')):
        defpal += [int(t, 16) for t in ln.replace(',', ' ').split() if t.startswith('0x')]
    found = glob.glob(os.path.join(d, '**', 'Photo Scrap.cvt'), recursive=True)
    if not found:
        fail('the copy wrote no Photo Scrap.cvt')
    w, h, bits, cols, _ = check_clip.photo(found[0])
    cw = len(clip[0])
    if (w, h) != ((cw + 7) // 8, len(clip)) or cols is not None:
        fail('the Photo Scrap: %d cards x %d rows%s, want %d x %d, black and white'
             % (w, h, ' with colours' if cols else '', (cw + 7) // 8, len(clip)))
    for y, row in enumerate(clip):
        for x, c in enumerate(row):
            v = defpal[c]
            ink = ((v >> 8) & 15) + ((v >> 4) & 15) + (v & 15) < 23
            if bool(bits[y * w + x // 8] & (0x80 >> (x % 8))) != ink:
                fail('the Photo Scrap: pixel (%d, %d) %s' % (x, y, 'paper, want ink' if ink else 'ink, want paper'))
    print('ok    copy: the Photo Scrap black and white (%d x %d cards x rows: a pixel ink where its colour is dark)'
          % (w, h))
    exports(d, snaps[-1], defpal)
    final = snaps[-1]
    saved = open(os.path.join(d, 'SAVED.PIC'), 'rb').read()
    if saved != final:
        fail('SAVED.PIC is not the picture after the last step: %s' % first_diff(saved, final))
    cvt = open(os.path.join(d, 'Colours.cvt'), 'rb').read()
    if cvt[0x1E + 0x4D:0x1E + 0x4D + 16] != b'PaintColour V1.0' and b'PaintColour V1.0' not in cvt[:512]:
        fail('Colours.cvt: no class PaintColour V1.0')
    recs = check_paint.records(cvt)
    if len(recs) != 11:
        fail('Colours.cvt: %d records, want 11' % len(recs))
    r0 = recs[0]
    if len(r0) != 519 or r0[0] != 1 or r0[1] | r0[2] << 8 != 320 or r0[3] | r0[4] << 8 != 240:
        fail('Colours.cvt record 0: %r' % r0[:7])
    # (V171) the palette editor: entry 5 R 15, G 0, B 15 (the clicks)
    e5 = r0[7 + 10] | r0[7 + 11] << 8
    if e5 != 0x0F0F:
        fail('Colours.cvt: palette entry 5 $%04X, want $0F0F (the palette editor)' % e5)
    dec = b''.join(check_paint.unpack(recs[1 + b], 24 * PW) for b in range(10))
    if dec != saved:
        fail('Colours.cvt decodes to another picture: %s' % first_diff(dec, saved))
    sizes = [len(r) for r in recs[1:]]
    opened = open(os.path.join(d, 'OPENED0.PIC'), 'rb').read()
    if opened != saved:
        fail('opened again: %s' % first_diff(opened, saved))
    print('ok    saved as Colours.cvt (class PaintColour V1.0, record 0: version 1, 320 x 240, colours %d and %d, '
          'the palette, entry 5 $0F0F from the palette editor; bands %s bytes packed): decoded, it is the picture; '
          'opened again, the same bytes' % (r0[5], r0[6], '/'.join(str(n) for n in sizes)))
    old = open(os.path.join(d, 'OPENED1.PIC'), 'rb').read()
    if old != bytes(old_expected()):
        fail("Paint's Oldpic opened: %s" % first_diff(old, bytes(old_expected())))
    print("ok    Paint's black and white picture (Oldpic, 592 x 464) opened at half size, as the reference")
    times = {}
    for ln in lines:
        m = re.search(r'TIME (\S+) ([0-9A-F]{8})$', ln)
        if m:
            times.setdefault(m.group(1), []).append(int(m.group(2), 16) / 8e3)
    print('ok    timings (ms, 8 MHz): ' + '; '.join('%s %s' % (k, ', '.join('%.1f' % t for t in v[:6]))
                                                   for k, v in sorted(times.items())))
    return old


def view(dump, pic, sx, sy):
    v = vram2png.section(dump)
    bad = 0
    for y in range(cs.VH):
        row = v[0x2800 + (cs.VY + y) * 320 + cs.VX:][:cs.VW]
        if row != pic[(sy + y) * PW + sx:][:cs.VW]:
            bad += 1
    if bad:
        fail('the view: %d rows not the picture at (%d, %d)' % (bad, sx, sy))
    if any(any(v[0x2800 + y * 320:0x2800 + y * 320 + 320]) for y in range(14)):
        fail('the menu bar rows of the picture are not 0')
    ink = [y for y in range(cs.VY, 240) if any(v[y * 40 + 5:y * 40 + 40])]
    if ink:
        fail('the view: ink on the 1 bpp screen in rows %s (a menu left behind?)' % ink[:8])
    print('ok    the view at the end: the picture from (%d, %d), the menu bar rows 0, no ink over the view' % (sx, sy))


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    if sys.argv[1] == 'oldpic':
        oldpic(sys.argv[2])
    elif sys.argv[1] == 'run':
        old = run(sys.argv[2])
        view(os.path.join(sys.argv[2], 'dump.bin'), old, 40, 16)
    else:
        sys.exit(__doc__)


if __name__ == '__main__':
    main()
