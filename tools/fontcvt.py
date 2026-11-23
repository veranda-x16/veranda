#!/usr/bin/env python3
"""GEOS font files (CVT) on the host: read, check, write, draw (DECISIONS V62).

usage: fontcvt.py check <font.cvt> [--sizes 9,12] [--name NAME]
       fontcvt.py list <font.cvt>
       fontcvt.py png <font.cvt> <size> <out.png> [text]
       fontcvt.py specimen <font.cvt> <size> <out.png>   ASCII, $A0-$FF, Polish lines
       fontcvt.py make <out.cvt> <GEOS name> <id> <size>=<record.bin> ...
       fontcvt.py record <font.cvt> <size> <out.bin>
       fontcvt.py testfonts <dir>     Gate Sans and Gate Mono (the package, the font gate)

A GEOS font file is a record file (VLIR) of GEOS type FONT: record n is
the font at n points; the info block has the font's ID at $80 (a word)
and its sizes at $82 (up to 15 words: ID << 6 | size). A record (as
tools/mkfont.py writes one): byte 0 the baseline, word 1 the set width
(bytes a bitmap row), byte 3 the height, word 4 the index table's offset,
word 6 the bitmap's; the index table: 97 words, the bit position of
characters 32-127 and the end; the bitmap: height rows of set width bytes.

Veranda's extended record (DECISIONS V141): the index table is 193 words
(characters $20-$7F, then $A0-$FF of the character set, ISO-8859-16:
V140, then the end) and the bitmap begins 386 bytes after it (a GEOS
font: 194), the 96 high glyphs after the 96 of ASCII in the same rows; so
entry 96 is $7F's end and $A0's start, and a program that knows only
GEOS's 96 characters reads it as before. A high glyph of width 0, any
character of $80-$9F, and $A0-$FF of a font without them draw as '?'
(the kernel's rule). Text is given as str (encoded ISO-8859-16) or bytes.

The CVT layout is docs/APPFORMAT.md's (Archive, apps/archive, writes the
same): a 30-byte directory entry, the signature padded to 254 bytes, the
info block (254 bytes: the 256-byte header without its first two), the
record table (254 bytes: blocks, bytes in the last block + 1; 0/$FF an
empty record, 0/0 the end), the records, each padded to 254-byte blocks.
"""
import os
import sys

FONT = 8
SIG = b'PRG formatted GEOS file V1.0'


class FontError(Exception):
    pass


EXT = 2 * 193                   # an extended record's index table (bytes)


def parse_record(rec):
    """a record -> dict(baseline, setw, height, index[97 or 193], ext, bitmap)
    (raises FontError)"""
    if len(rec) < 8:
        raise FontError('a record of %d bytes' % len(rec))
    base, setw, h = rec[0], rec[1] | rec[2] << 8, rec[3]
    io, bo = rec[4] | rec[5] << 8, rec[6] | rec[7] << 8
    if not 1 <= h <= 32:
        raise FontError('height %d' % h)
    if base >= h:
        raise FontError('baseline %d, height %d' % (base, h))
    ext = bo - io == EXT
    n = 193 if ext else 97
    if io + 2 * n > len(rec):
        raise FontError('the index table past the record')
    if bo + setw * h > len(rec):
        raise FontError('the bitmap past the record (%d + %d x %d > %d)' % (bo, setw, h, len(rec)))
    idx = [rec[io + 2 * i] | rec[io + 2 * i + 1] << 8 for i in range(n)]
    for i in range(n - 1):
        if idx[i + 1] < idx[i]:
            raise FontError('character %d: the index goes back' % ((32 + i) if i < 96 else (0xA0 + i - 96)))
    if idx[n - 1] > setw * 8:
        raise FontError('the index past the set width')
    return dict(baseline=base, setw=setw, height=h, index=idx, ext=ext, bitmap=rec[bo:bo + setw * h])


def slot(f, ch):
    """character ch's entry in f's index as the kernel finds it: $20-$7F
    themselves (below: the space), $A0-$FF in an extended record if their
    width is not 0, else '?'"""
    if ch < 32:
        ch = 32
    if ch < 128:
        return ch - 32
    if 0xA0 <= ch <= 0xFF and f.get('ext'):
        i = ch - 0xA0 + 96
        if f['index'][i + 1] > f['index'][i]:
            return i
    return ord('?') - 32


def encode(text):
    """str (ISO-8859-16, V140) or bytes -> bytes"""
    return bytes(text) if isinstance(text, (bytes, bytearray)) else text.encode('iso8859_16')


def glyph(f, ch):
    """character ch's rows as lists of 0/1"""
    c = slot(f, ch)
    a, b = f['index'][c], f['index'][c + 1]
    rows = []
    for r in range(f['height']):
        row = f['bitmap'][r * f['setw']:(r + 1) * f['setw']]
        rows.append([(row[x >> 3] >> (7 - (x & 7))) & 1 for x in range(a, b)])
    return rows


def build_record(glyphs, baseline, hi=None):
    """glyphs: 96 lists of rows (lists of 0/1, equal heights) -> a record;
    hi: 96 more for $A0-$FF (an empty list or None: none): the extended
    record (V141)"""
    ext = hi is not None
    if ext:
        glyphs = list(glyphs) + list(hi)
    h = len(glyphs[0])
    pos, x = [], 0
    for g in glyphs:
        pos.append(x)
        x += len(g[0]) if g and g[0] is not None else 0
    pos.append(x)
    setw = (x + 7) // 8
    bm = bytearray(setw * h)
    for g, p in zip(glyphs, pos):
        for r, row in enumerate(g):
            for i, v in enumerate(row):
                if v:
                    bm[r * setw + (p + i) // 8] |= 0x80 >> ((p + i) % 8)
    bo = 8 + (EXT if ext else 194)
    out = bytearray([baseline, setw & 255, setw >> 8, h, 8, 0, bo & 255, bo >> 8])
    for p in pos:
        out += bytes([p & 255, p >> 8])
    return bytes(out + bm)


def blocks(n):
    return (n + 253) // 254


def write_cvt(name, font_id, records, desc='A font.'):
    """records: {size: bytes} -> the CVT file"""
    sizes = sorted(records)
    nm = name.encode('latin-1')[:16]
    total = sum(blocks(len(records[s])) for s in sizes) + 1
    ent = bytearray(30)
    ent[0] = 0x83
    ent[3:19] = nm + b'\xa0' * (16 - len(nm))
    ent[21], ent[22] = 1, FONT
    ent[23:28] = bytes([126, 11, 16, 12, 0])
    ent[28], ent[29] = (total + 1) & 255, (total + 1) >> 8
    sig = SIG + bytes(224 - len(SIG))
    hdr = bytearray(256)
    hdr[0], hdr[1], hdr[2], hdr[3], hdr[4] = 0, 0xFF, 3, 21, 0xBF
    icon = [0xFF, 0xFF, 0xFF] + [0x80, 0, 0x01] * 19 + [0xFF, 0xFF, 0xFF]
    icon[3 * 6 + 1] = 0x7E                       # an "A"-ish mark
    hdr[5:5 + 63] = bytes(icon)
    hdr[68], hdr[69], hdr[70] = 0x83, FONT, 1
    cls = (name[:12].ljust(12) + 'V1.0').encode('latin-1')
    hdr[77:77 + len(cls)] = cls
    hdr[0x80], hdr[0x81] = font_id & 255, font_id >> 8
    for i, s in enumerate(sizes[:15]):
        v = font_id << 6 | s
        hdr[0x82 + 2 * i], hdr[0x83 + 2 * i] = v & 255, v >> 8
    a = b'Veranda'
    hdr[97:97 + len(a)] = a
    d = desc.encode('latin-1')[:95]
    hdr[0xA0:0xA0 + len(d)] = d
    tab = bytearray(254)
    last = max(sizes)
    for n in range(last + 1):
        if n in records:
            r = records[n]
            tab[2 * n], tab[2 * n + 1] = blocks(len(r)), (len(r) - 1) % 254 + 2
        else:
            tab[2 * n], tab[2 * n + 1] = 0, 0xFF
    data = bytearray()
    for s in range(last + 1):
        if s in records:
            r = records[s]
            data += r + bytes(blocks(len(r)) * 254 - len(r))
    return bytes(ent + sig + hdr[2:] + tab + data)


def read_cvt(data):
    """the CVT file -> (name, font_id, {size: record}) (raises FontError)"""
    if len(data) < 762 or not data[30:30 + len(SIG)].startswith(SIG[:20]):
        raise FontError('not a CVT file')
    if data[21] != 1:
        raise FontError('not a record file')
    hdr = b'\0\xff' + data[254:508]
    if hdr[69] != FONT:
        raise FontError('GEOS type %d, not FONT' % hdr[69])
    name = data[3:19].split(b'\xa0')[0].decode('latin-1')
    fid = hdr[0x80] | hdr[0x81] << 8
    tab = data[508:762]
    recs, off = {}, 762
    for n in range(127):
        b, l = tab[2 * n], tab[2 * n + 1]
        if b == 0 and l == 0:
            break
        if b == 0:
            continue
        ln = (b - 1) * 254 + l - 1
        if off + ln > len(data):
            raise FontError('record %d past the file' % n)
        recs[n] = data[off:off + ln]
        off += b * 254
    return name, fid, recs, hdr


def check(path, sizes=None, name=None):
    name0, fid, recs, hdr = read_cvt(open(path, 'rb').read())
    if not recs:
        raise FontError('no records')
    fonts = {}
    for n, r in recs.items():
        if not 1 <= n <= 63:
            raise FontError('record %d: not a point size' % n)
        try:
            fonts[n] = parse_record(r)
        except FontError as e:
            raise FontError('record %d: %s' % (n, e))
    listed = []
    for i in range(15):
        v = hdr[0x82 + 2 * i] | hdr[0x83 + 2 * i] << 8
        if v:
            if v >> 6 != fid:
                raise FontError('size list: font ID %d, the file %d' % (v >> 6, fid))
            listed.append(v & 63)
    if sorted(listed) != sorted(recs)[:15]:
        raise FontError('the info block lists sizes %s, the records are %s' % (sorted(listed), sorted(recs)))
    if sizes is not None and sorted(recs) != sorted(sizes):
        raise FontError('sizes %s, wanted %s' % (sorted(recs), sorted(sizes)))
    if name is not None and name0 != name[:16]:
        raise FontError('name %r, wanted %r' % (name0, name))
    return name0, fid, fonts


def render(f, text):
    """text drawn plain -> rows of 0/1"""
    rows = [[] for _ in range(f['height'])]
    for ch in encode(text):
        g = glyph(f, ch)
        for r in range(f['height']):
            rows[r] += g[r]
    return rows


def render_runs(f, runs):
    """runs of (text, styles: 'b' bold, 'i' italic, 'u' underline) drawn one
    after another as Veranda's kernel draws them (DECISIONS V122): every
    character at its plain advance (bold: + 1), bold as each pixel and the
    one right of it, italic's rows leaning right by (baseline + 2 - row) / 2
    (none below baseline + 2, as GEOS), the lean drawn whole (nothing cut
    at a run's or the string's end), underline the row below the baseline
    across the advance; all ink ORed -> rows of 0/1 (height rows, the
    advances plus the most lean plus 2 columns wide)"""
    base, h = f['baseline'], f['height']
    adv = sum(len(glyph(f, ch)[0]) + ('b' in st) for t, st in runs for ch in encode(t))
    w = adv + (base + 2) // 2 + 2
    rows = [[0] * w for _ in range(h)]
    x = 0
    for t, st in runs:
        for ch in encode(t):
            g = glyph(f, ch)
            gw = len(g[0])
            for r in range(h):
                lean = (base + 2 - r) // 2 if 'i' in st and base + 2 >= r else 0
                for c in range(gw):
                    if g[r][c]:
                        rows[r][x + c + lean] = 1
                        if 'b' in st:
                            rows[r][x + c + lean + 1] = 1
            cw = gw + ('b' in st)
            if 'u' in st and base + 1 < h:     # (the strip's rows: the font's)
                for c in range(cw):
                    rows[base + 1][x + c] = 1
            x += cw
    return rows


def png(f, text, out, scale=3):
    from PIL import Image
    rows = render(f, text)
    w = max(1, len(rows[0]))
    img = Image.new('1', (w + 4, f['height'] + 4), 1)
    px = img.load()
    for y, row in enumerate(rows):
        for x, v in enumerate(row):
            if v:
                px[x + 2, y + 2] = 0
    img.resize(((w + 4) * scale, (f['height'] + 4) * scale)).save(out)


def specimen(f, out, scale=4):
    """f's characters (ASCII, $A0-$FF in lines of 16) and Polish lines,
    drawn as the kernel draws them, scaled"""
    from PIL import Image
    lines = [bytes(range(c, c + 32)) for c in (32, 64, 96)]
    lines += [bytes(range(c, c + 16)) for c in range(0xA0, 0x100, 16)]
    lines += ['Zażółć gęślą jaźń', 'ZAŻÓŁĆ GĘŚLĄ JAŹŃ', 'Pchnąć w tę łódź jeża lub ośm skrzyń fig.']
    rend = [render(f, t) for t in lines]
    w = max(len(r[0]) for r in rend) + 8
    h = sum(f['height'] + 3 for _ in rend) + 6
    img = Image.new('1', (w, h), 1)
    px = img.load()
    y = 3
    for rows in rend:
        for yy, row in enumerate(rows):
            for x, v in enumerate(row):
                if v:
                    px[x + 4, y + yy] = 0
        y += f['height'] + 3
    img.resize((w * scale, h * scale)).save(out)


def scaled(f, sx, sy):
    """a record: f's glyphs scaled by whole numbers (the test fonts; an
    extended record stays one)"""
    def big(c):
        rows = []
        for row in glyph(f, c):
            b = [v for v in row for _ in range(sx)]
            rows += [b[:] for _ in range(sy)]
        return rows
    hi = [big(c) if slot(f, c) != ord('?') - 32 else [[] for _ in range(f['height'] * sy)]
          for c in range(0xA0, 0x100)] if f.get('ext') else None
    return build_record([big(c) for c in range(32, 128)], f['baseline'] * sy + sy - 1, hi)


def testfonts(d, root):
    """Gate Sans (records 9: the system font's glyphs, 12: the UI font's,
    18: the system font doubled, 27: tripled and five times as wide, two
    banks) and Gate Mono (10 and 12: monospaced, tools/gatemono.py); all
    extended records (V141): the glyphs of $A0-$FF too (tools/latin10.py)"""
    import subprocess
    os.makedirs(d, exist_ok=True)
    tmp = os.path.join(d, 'sys.bin')
    subprocess.run([sys.executable, '-I', '-B', os.path.join(root, 'tools', 'mkfont.py'), '--ext', tmp],
                   check=True, capture_output=True)
    ui = os.path.join(d, 'ui.bin')
    subprocess.run([sys.executable, '-I', '-B', os.path.join(root, 'tools', 'mkfont.py'), '--ext', '--ui', ui],
                   check=True, capture_output=True)
    sysr, uir = open(tmp, 'rb').read(), open(ui, 'rb').read()
    sf = parse_record(sysr)
    recs = {9: sysr, 12: uir, 18: scaled(sf, 2, 2), 27: scaled(sf, 5, 3)}
    open(os.path.join(d, 'Gate Sans.cvt'), 'wb').write(write_cvt('Gate Sans', 300, recs, 'Test font: Veranda.'))
    for s, r in recs.items():
        open(os.path.join(d, 'gs%d.bin' % s), 'wb').write(r)
    # Gate Mono 10 and 12: Veranda's monospaced font (tools/gatemono.py)
    sys.path.insert(0, os.path.join(root, 'tools'))
    import gatemono
    mono = {s: build_record(gatemono.glyphs(s), gatemono.BASELINE[s], gatemono.high(s)) for s in (10, 12)}
    open(os.path.join(d, 'Gate Mono.cvt'), 'wb').write(write_cvt('Gate Mono', 301, mono, 'Veranda monospaced.'))
    for s, r in mono.items():
        open(os.path.join(d, 'gm%d.bin' % s), 'wb').write(r)
    os.remove(tmp)
    os.remove(ui)


def main():
    a = sys.argv[1:]
    if not a:
        sys.exit(__doc__)
    try:
        if a[0] == 'check':
            sizes = [int(x) for x in a[a.index('--sizes') + 1].split(',')] if '--sizes' in a else None
            name = a[a.index('--name') + 1] if '--name' in a else None
            n, fid, fonts = check(a[1], sizes, name)
            print('fontcvt: %s: "%s", ID %d, sizes %s' % (a[1], n, fid, ' '.join(
                '%d (height %d, baseline %d, %d bytes a row)' % (s, f['height'], f['baseline'], f['setw'])
                for s, f in sorted(fonts.items()))))
        elif a[0] == 'list':
            n, fid, recs, hdr = read_cvt(open(a[1], 'rb').read())
            print('"%s" ID %d sizes %s' % (n, fid, sorted(recs)))
        elif a[0] == 'png':
            n, fid, recs, hdr = read_cvt(open(a[1], 'rb').read())
            f = parse_record(recs[int(a[2])])
            png(f, a[4] if len(a) > 4 else 'The quick brown fox jumps over the lazy dog 0123456789 Zażółć gęślą jaźń',
                a[3])
        elif a[0] == 'specimen':
            n, fid, recs, hdr = read_cvt(open(a[1], 'rb').read())
            specimen(parse_record(recs[int(a[2])]), a[3])
        elif a[0] == 'make':
            recs = {}
            for x in a[4:]:
                s, p = x.split('=', 1)
                recs[int(s)] = open(p, 'rb').read()
            open(a[1], 'wb').write(write_cvt(a[2], int(a[3]), recs))
        elif a[0] == 'record':
            n, fid, recs, hdr = read_cvt(open(a[1], 'rb').read())
            open(a[3], 'wb').write(recs[int(a[2])])
        elif a[0] == 'testfonts':
            testfonts(a[1], os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')))
        else:
            sys.exit(__doc__)
    except FontError as e:
        sys.exit('fontcvt: %s' % e)


if __name__ == '__main__':
    main()
