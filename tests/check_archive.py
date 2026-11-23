#!/usr/bin/env python3
"""gate archive: checks Archive's run against tools/vdisk.py (the oracle).

usage: check_archive.py log <console.txt> <image>...
           the console's listings (ARCHIVE IMAGE ... and a line a file) are
           vdisk.py's for each image, in order; the files extracted (ARCHIVE
           GOT) are the copyable ones; the Paint documents made (ARCHIVE
           PAINT) are vdisk.py's conversions
       check_archive.py listing <console.txt> <image>
           the console's first listing only
       check_archive.py files <folder> <image> [--paint]
           every file extracted from the image is in the folder (the
           image's own) and equal byte for byte to vdisk.py's; with --paint
           every Paint document converted equals vdisk.py's conversion as a
           picture (the bitmap, the card colours, the ink)
       check_archive.py screen <dump.bin> <rom.bin> <image> <name> <first> [<selected>...]
           the list on the screen (a VRAM dump; Veranda Look 3, DECISIONS
           V148): each row's texts in the UI font (tests/uitext.py: the
           columns' pixels equal its drawing of vdisk.py's listing from
           file <first>), each row's icon (the info block's, or Archive's
           own for a plain file), the selected rows' cards in the
           selection colour and the others' none, the status bar's right
           the image's kind, name, files and free blocks
       check_archive.py paint <folder> <document.cvt>
           Paint opened the document: OPENED.RAW (the drawing area's rows)
           and OPENED.MAP (its cards' colours) are the document's picture
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'tools'))
import vdisk  # noqa: E402
sys.path.insert(0, HERE)
import uitext  # noqa: E402

TOP, ROWH, ROWS = 48, 24, 17                        # apps/archive/archive.c
MAP = 0x1AC00                                       # the colour map: 128 entries a card row
SELECT = 5                                          # Sunroom's selection colour (sdk theme.h TITLE)
# the columns (archive.c: X_NAME ...): x, width; the size right aligned at 368
COLS = [(40, 136), (184, 96), (288, 40), (None, 64), (384, 128), (520, 96)]
VRAM = 131072
TAIL = 132878
DOCICON = bytes([
    0x7F, 0xFF, 0xC0, 0x40, 0x00, 0x60, 0x40, 0x00, 0x50, 0x40, 0x00, 0x78, 0x40, 0x00, 0x08,
    0x40, 0x00, 0x08, 0x40, 0x00, 0x08, 0x40, 0x00, 0x08, 0x40, 0x00, 0x08, 0x40, 0x00, 0x08,
    0x40, 0x00, 0x08, 0x40, 0x00, 0x08, 0x40, 0x00, 0x08, 0x40, 0x00, 0x08, 0x40, 0x00, 0x08,
    0x40, 0x00, 0x08, 0x40, 0x00, 0x08, 0x40, 0x00, 0x08, 0x40, 0x00, 0x08, 0x40, 0x00, 0x08,
    0x7F, 0xFF, 0xF8])


def fail(msg):
    print('check_archive: ' + msg)
    sys.exit(1)


def conversions(im):
    """[(file entry, [(document name, records)])] as Archive converts"""
    out = []
    for e in im.entries():
        if not e.geos:
            continue
        content = im.records(e) if e.vlir else im.data(e)
        if vdisk.classify(e.cls, content, e.vlir) is None:
            continue
        out.append((e, vdisk.to_paint(e.name, e.cls, e.vlir, content)))
    return out


def cmd_log(console, images, only=False):
    lines = [ln.split('ARCHIVE ', 1)[1].rstrip('\r') for ln in
             open(console, 'rb').read().decode('latin-1').replace('\r', '\n').split('\n') if 'ARCHIVE ' in ln]
    pos = 0
    for path in images:
        im = vdisk.Image.load(path)
        want, es = im.listing()
        while pos < len(lines) and not lines[pos].startswith('IMAGE|'):
            pos += 1
        got = lines[pos:pos + len(want)]
        if got != want:
            for a, b in zip(want + [''] * 99, got + [''] * 99):
                if a != b:
                    fail('%s: the listing has %r, vdisk.py %r' % (os.path.basename(path), b, a))
        pos += len(want)
        if only:
            print('check_archive: %s: the listing (%d files) equals vdisk.py\'s' % (os.path.basename(path), len(es)))
            continue
        copied = [e.file for e in es if e.copyable]
        got = [ln[4:] for ln in lines[pos:pos + len(copied)] if ln.startswith('GOT ')]
        if got != copied:
            fail('%s: extracted %s, want %s' % (os.path.basename(path), got, copied))
        pos += len(copied)
        if lines[pos] != 'EXTRACTED %d' % len(copied):
            fail('%s: %r after the files' % (os.path.basename(path), lines[pos]))
        pos += 1
        conv = pos < len(lines) and lines[pos].startswith('PAINT ')
        if conv:
            docs = [n for _, parts in conversions(im) for n, _ in parts]
            got = [ln[6:] for ln in lines[pos:pos + len(docs)]]
            if got != docs:
                fail('%s: Paint documents %s, want %s' % (os.path.basename(path), got, docs))
            pos += len(docs)
            if lines[pos] != 'CONVERTED %d' % len(conversions(im)):
                fail('%s: %r after the conversions' % (os.path.basename(path), lines[pos]))
            pos += 1
        print('check_archive: %s: the listing (%d files) equals vdisk.py\'s; %d files extracted%s' % (
            os.path.basename(path), len(es), len(copied),
            ', its pictures converted (as vdisk.py names them)' if conv else ''))


def cmd_files(folder, path, paint):
    im = vdisk.Image.load(path)
    n = 0
    for e in im.entries():
        if not e.copyable:
            continue
        got = os.path.join(folder, e.file)
        if not os.path.isfile(got):
            fail('%s: no %s' % (os.path.basename(path), e.file))
        if open(got, 'rb').read() != im.extract(e):
            fail('%s: %s differs from vdisk.py\'s' % (os.path.basename(path), e.file))
        n += 1
    docs = 0
    for e, parts in conversions(im) if paint else []:
        for name, recs in parts:
            got = os.path.join(folder, name + '.cvt')
            if not os.path.isfile(got):
                fail('%s: no Paint document %s' % (os.path.basename(path), name))
            a = vdisk.paint_decode(open(got, 'rb').read())
            b = vdisk.paint_decode(vdisk.paint_cvt(name, recs))
            what = ['the bitmap', 'the card colours', 'the ink']
            for i in range(3):
                if a[i] != b[i]:
                    fail('%s: %s: %s differs from vdisk.py\'s' % (os.path.basename(path), name, what[i]))
            e2, info, _ = vdisk.parse_cvt(open(got, 'rb').read())
            if e2[22] != 7 or vdisk.cstr(info[77:97]) != b'Paint Image V1.0' or vdisk.cstr(info[117:137]) != b'Paint       V1.0':
                fail('%s: %s is not a Paint document (type, class, parent)' % (os.path.basename(path), name))
            docs += 1
    print('check_archive: %s: %d files equal vdisk.py\'s byte for byte%s' % (
        os.path.basename(path), n, ', %d Paint documents equal its conversions' % docs if docs else ''))


def rom_font(rom):
    d = open(rom, 'rb').read()[6 * 16384:7 * 16384]
    smiley = bytes([0x7E, 0x81, 0xA5, 0x81, 0xBD, 0x99, 0x81, 0x7E])
    for a in range(0, 16384, 2048):
        if d[a + 8:a + 16] == smiley:
            return d[a:a + 2048]
    fail('no CP437 set in the ROM')


class Screen:
    def __init__(self, dump, rom):
        d = open(dump, 'rb').read()
        if len(d) < TAIL:
            fail('no VRAM in ' + dump)
        self.v = d[len(d) - TAIL:][:VRAM]
        font = rom_font(rom)
        self.glyphs = {}
        for c in list(range(32, 127)) + list(range(256)):
            self.glyphs.setdefault(font[c * 8:c * 8 + 8], c)

    def text(self, x, w, y, rev=False):
        s = ''
        for cx in range(x, x + w):
            cell = bytes(self.v[(y + i) * 80 + cx] ^ (0xFF if rev else 0) for i in range(8))
            c = self.glyphs.get(cell)
            s += '\x7f' if c is None else chr(c)
        return s

    def icon(self, y):
        return bytes(self.v[(y + r) * 80 + 1 + b] for r in range(21) for b in range(3))


def fld(s, w):
    return (s + ' ' * w)[:w]


def cmd_screen(dump, rom, path, name, first, sel):
    im = vdisk.Image.load(path)
    lines, es = im.listing()
    sc = Screen(dump, rom)
    bits = [[sc.v[y * 80 + x // 8] >> (7 - x % 8) & 1 for x in range(640)] for y in range(480)]

    def paper(cx, cy):
        return sc.v[MAP + (cy * 128 + cx) * 2 + 1] >> 4
    for r in range(ROWS):
        i = first + r
        y0 = TOP + r * ROWH
        want = [[0] * 640 for _ in range(y0)] + [[0] * 640 for _ in range(ROWH)]
        if i < len(es):
            e = es[i]
            form = 'VLIR' if e.vlir else 'Seq' if e.geos else '-'
            for (x, w), t in zip(COLS, [e.name, e.kind, form, str(e.blocks), e.cls, e.file or '']):
                if x is None:
                    x = 368 - uitext.width(t)
                uitext.put(want, uitext.fit(t, w), x, y0 + 15)
            icon = e.info[5:68] if e.geos else DOCICON
            if sc.icon(y0 + 1) != icon:
                fail('row %d (%s): the icon is not %s' % (r, e.name, 'its info block\'s' if e.geos else 'Archive\'s own'))
        for y in range(y0, y0 + ROWH):
            for x in range(40, 624):
                if bits[y][x] != want[y][x]:
                    fail('row %d (%s): the pixel at %d,%d is %d, want %d' % (
                        r, es[i].name if i < len(es) else '-', x, y, bits[y][x], want[y][x]))
        if i >= len(es) and any(bits[y][x] for y in range(y0, y0 + ROWH) for x in range(0, 40)):
            fail('row %d is not empty' % r)
        c = paper(5, y0 // 8)
        if c != (SELECT if i in sel else 0):
            fail('row %d: its cards in colour %d, want %d' % (r, c, SELECT if i in sel else 0))
    right = '%s  "%s"  %d %s, %d blocks free' % (im.kind, im.disk_name(), len(es),
                                                 'file' if len(es) == 1 else 'files', im.free())
    want = [[0] * 640 for _ in range(480)]
    n = uitext.width(uitext.fit(right, 623))
    uitext.put(want, uitext.fit(right[:63], 623), 639 - 8 - n, 474)
    for y in range(466, 479):
        for x in range(639 - 8 - n, 632):
            if bits[y][x] != want[y][x]:
                fail('the status bar\'s right does not read %r (the pixel at %d,%d)' % (right, x, y))
    print('check_archive: the screen lists %s from file %d as vdisk.py does: %d rows (the UI font\'s texts, icons%s); %s' % (
        name, first + 1, min(ROWS, len(es) - first), ', %d selected in the selection colour' % len(sel) if sel else '', right))


def cmd_paint(folder, doc):
    bits, cmap, ink = vdisk.paint_decode(open(doc, 'rb').read())
    raw = open(os.path.join(folder, 'OPENED.RAW'), 'rb').read()
    for y in range(vdisk.P_H):
        row = raw[y * 74:(y + 1) * 74]
        got = [row[x // 8] >> (7 - x % 8) & 1 for x in range(vdisk.P_W)]
        if got != bits[y]:
            fail('Paint\'s drawing area, row %d, differs from %s' % (y, os.path.basename(doc)))
    m = open(os.path.join(folder, 'OPENED.MAP'), 'rb').read()
    for cy in range(vdisk.P_MH):
        if list(m[cy * 74:(cy + 1) * 74]) != cmap[cy]:
            fail('Paint\'s colours, card row %d, differ from %s' % (cy, os.path.basename(doc)))
    print('check_archive: Paint opened %s: its drawing area and its cards\' colours are the picture (ink %d)' % (
        os.path.basename(doc), ink))


def main():
    a = sys.argv[1:]
    if len(a) >= 3 and a[0] == 'log':
        cmd_log(a[1], a[2:])
    elif len(a) == 3 and a[0] == 'listing':
        cmd_log(a[1], a[2:], True)
    elif len(a) in (3, 4) and a[0] == 'files':
        cmd_files(a[1], a[2], a[3:] == ['--paint'])
    elif len(a) >= 6 and a[0] == 'screen':
        cmd_screen(a[1], a[2], a[3], a[4], int(a[5]), [int(x) for x in a[6:]])
    elif len(a) == 3 and a[0] == 'paint':
        cmd_paint(a[1], a[2])
    else:
        sys.exit(__doc__)


if __name__ == '__main__':
    main()
