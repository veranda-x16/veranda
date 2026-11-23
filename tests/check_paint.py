#!/usr/bin/env python3
"""gate paint: check a Paint session (tools/gate_paint.sh).

usage: check_paint.py <run dir> <out dir>
       check_paint.py --band <dump.bin> left top right bottom
       check_paint.py --dialog <dump.bin> <console.txt>

The run dir holds what the test build left: dump.bin (VRAM at the end,
after the document was opened again), SAVED.RAW (the drawing area's rows
when the save started), CLEAR.RAW (after file/new), Picture.cvt (the
document), console.txt; the second picture (SAVED2.RAW, Sketch.cvt), the
drawing area after each file/open (OPENED.RAW: Sketch, chosen after a
scroll and OPEN; OPENED2.RAW: Picture, a double click), Draft 1-5.cvt
(empty documents the test build saves after the first file/open, cancelled).
Long names (DECISIONS V82): the picture saved again as "Holiday sketch from
the lake shore 2026" (SAVED3.RAW) and opened by that name after file/new
(OPENED3.RAW). Colour (phase 9): *.MAP next to each *.RAW, the drawing area's
cards' colours (58 rows of 74); OLD.RAW and OLD.MAP after Zebra (an empty
picture in version 1's format, saved by the test build) was opened.
Writes PNGs of the picture into the out dir.

The Sunroom column (DECISIONS V147): Paint runs in the kernel's tile mode
(layer 0 4 bpp tiles at $13000); a card of the drawing area is the solid
tile of its colour in palette row 0 (mapcol()); the column's cards are
tiles 16 on in rows 2-11. The second picture (Sketch) has the newer
tools: an oval filled by the fill with pattern 2, a filled oval, a brush
stroke, the spray.
"""
import os
import sys

VDUMP = 132878                  # x16emu's VRAM section in a -dump V file
CX, CY, CBYTES, ROWS = 6, 16, 74, 464
BANDH, BANDS = 16, 29
SIG = b'PRG formatted GEOS file V1.0'
APPL_DATA = 7


MAP = 0x1AC00
VRAM_, COMPOSER_, PALETTE_ = 131072, 256, 512


def tilemode(v):
    """layer 0's tile base is $13000 (V101's tile mode)"""
    return v[VRAM_ + COMPOSER_ + PALETTE_ + 2] == 0x98


def mapcol(v, x, y):
    """card x, y's colour in the colour map, either kind"""
    lo, hi = v[MAP + 2 * (y * 128 + x)], v[MAP + 2 * (y * 128 + x) + 1]
    if tilemode(v):
        return lo if hi >> 4 == 0 and lo < 16 else 0
    return hi >> 4


def fail(msg):
    print('FAIL  ' + msg)
    sys.exit(1)


def ok(msg):
    print('ok    ' + msg)


def area(vram):
    """the drawing area's rows from a 640x480 screen"""
    return b''.join(vram[y * 80 + CX:y * 80 + CX + CBYTES] for y in range(CY, CY + ROWS))


def unpack(data, size):
    out = bytearray()
    i = 0
    while i < len(data):
        c = data[i]
        i += 1
        if c < 128:
            out += data[i:i + c + 1]
            i += c + 1
        elif c > 128:
            out += bytes([data[i]]) * (257 - c)
            i += 1
    if len(out) != size:
        raise ValueError('a band unpacks to %d bytes, not %d' % (len(out), size))
    return bytes(out)


def records(cvt):
    """the record table's records (VLIR CVT: docs/APPFORMAT.md)"""
    t, pos, recs = cvt[508:762], 762, []
    for i in range(127):
        n, last = t[2 * i], t[2 * i + 1]
        if n == 0 and last == 0:
            break
        if n == 0:
            recs.append(b'')
            continue
        size = (n - 1) * 254 + last - 1
        recs.append(cvt[pos:pos + size])
        pos += n * 254
    if pos != len(cvt):
        raise ValueError('the file is %d bytes, its records end at %d' % (len(cvt), pos))
    return recs


def png(rows, width, path):
    try:
        from PIL import Image
    except ImportError:
        return
    h = len(rows) // (width // 8)
    img = Image.new('1', (width, h))
    px = img.load()
    for y in range(h):
        for x in range(width):
            px[x, y] = 0 if rows[y * (width // 8) + x // 8] & (0x80 >> (x % 8)) else 1
    img.save(path)


def band(dump, l, t, r, b):
    """during a drag: the foreground differs from the back screen (the
    picture) exactly by the rubber band, a frame l, t, r, b"""
    d = open(dump, 'rb').read()
    v = d[len(d) - VDUMP:]
    fore, back = v[:38400], v[0x9600:0x9600 + 38400]
    diff = set()
    for i in range(CY * 80, 38400):         # the drawing area (the menu bar
        if i % 80 < CX:                     # is drawn on the foreground only)
            continue
        x = fore[i] ^ back[i]
        for k in range(8):
            if x & (0x80 >> k):
                diff.add((i % 80 * 8 + k, i // 80))
    want = {(x, y) for x in range(l, r + 1) for y in (t, b)} | {(x, y) for y in range(t, b + 1) for x in (l, r)}
    # the band may cross ink already there: those pixels do not differ
    if not diff <= want or len(diff) < len(want) // 2:
        fail('the rubber band: %d pixels differ from the back screen, %d outside the frame'
             % (len(diff), len(diff - want)))
    ok('the rubber band is on the foreground only (%d pixels; the back screen keeps the picture)' % len(diff))


# the Open and Save dialog (sdk/lib/vrchoose.c): a box of 38 x 27 cards
# at 400 lines or more, centred: cards 21-58, rows 16-42
DLG = (21 * 8, 16 * 8, 59 * 8 - 1, 43 * 8 - 1)


def dialog(dump, console):
    """the dialog is up: its frame drawn (the box's outline in ink), its
    folder listed (VRF SHOW on the console)"""
    d = open(dump, 'rb').read()
    v = d[len(d) - VDUMP:]
    l, t, r, b = DLG
    def px(x, y):
        return v[y * 80 + x // 8] >> (7 - x % 8) & 1
    top = sum(px(x, t) for x in range(l, r + 1))
    left = sum(px(l, y) for y in range(t, b + 1))
    if top < (r - l) * 3 // 4 or left < (b - t) * 3 // 4:
        fail('the dialog: its frame is not at %s (top %d, left %d pixels)' % (DLG, top, left))
    con = open(console, 'rb').read().decode('latin-1')
    if 'VRF SHOW' not in con:
        fail('the dialog: no VRF SHOW on the console')
    ok('the Open and Save dialog is up at its place (its frame), the folder listed (%s)'
       % con[con.rfind('VRF SHOW'):].splitlines()[0].strip())


def marks(con, ms):
    """the console has ms in this order: their positions"""
    at, p = [], 0
    for m in ms:
        p = con.find(m, p)
        if p < 0:
            fail('the console has not %s in order (%s missing)' % (', '.join(ms), m))
        at.append(p)
        p += len(m)
    return at


def colours(run, vram, cmap, out):
    """the colour map: as drawn, saved, cleared, opened; on the screen"""
    rd = lambda n: open(os.path.join(run, n), 'rb').read()      # noqa: E731
    saved, saved2, clear = rd('SAVED.MAP'), rd('SAVED2.MAP'), rd('CLEAR.MAP')
    op1, op2, old, oldraw = rd('OPENED.MAP'), rd('OPENED2.MAP'), rd('OLD.MAP'), rd('OLD.RAW')
    if len(saved) != 74 * 58 or set(saved) - {0} != {2, 5}:
        fail('the colours at the save: %s (want the cards in colours 2 and 5)' % sorted(set(saved)))
    ok('the colours at the save: %d cards in colour 2 (the pencil), %d in colour 5 (rectangles)'
       % (saved.count(2), saved.count(5)))
    if any(clear):
        fail('file/new left %d cards coloured' % sum(1 for b in clear if b))
    ok('file/new clears the colours')
    if cmap != saved:
        fail('Picture.cvt\'s colour map (records 30, 31) differs from the colours saved in %d cards'
             % sum(1 for a, b in zip(cmap, saved) if a != b))
    ok('Picture.cvt: records 30 and 31 hold the colour map saved (version 3: and the ink, black, in record 0)')
    if op1 != saved2 or op2 != saved:
        fail('the colours opened again differ from those saved (Sketch %d, Picture %d cards)'
             % (sum(1 for a, b in zip(op1, saved2) if a != b), sum(1 for a, b in zip(op2, saved) if a != b)))
    ok('file/open: Sketch\'s and Picture\'s colours equal those saved')
    if any(old) or any(oldraw) or not any(saved2):
        fail('Zebra (version 1) did not open blank in black and white (%d cards coloured)'
             % sum(1 for b in old if b))
    ok('Zebra, a version 1 picture, opens in black and white (the colours of Sketch before it cleared)')
    end = bytes(mapcol(vram, x, y) for y in range(2, 60) for x in range(6, 80))
    if end != saved:
        fail('the colour map in VRAM at the end differs from the one saved in %d cards'
             % sum(1 for a, b in zip(end, saved) if a != b))
    ok('the colour map in VRAM at the end (Picture opened again) equals the one saved')
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'tools'))
    import vram2png
    pic = vram2png.compose(vram)
    bad = 0
    for y in range(16, 480):
        for x in range(48, 640):
            c = saved[(y // 8 - 2) * 74 + x // 8 - 6]
            ink = vram[y * 80 + x // 8] & (0x80 >> (x % 8))
            bad += pic[y][x] != (vram2png.rgb(vram, 1) if ink else vram2png.rgb(vram, c))
    if bad:
        fail('the composed display: %d pixels of the drawing area not in their card\'s colour' % bad)
    ok('the composed display (bitmap and colour map, as VERA shows it): every pixel of the drawing area in its '
       'card\'s colour, the ink black')
    try:
        from PIL import Image
        img = Image.new('RGB', (640, 480))
        px = img.load()
        for y in range(480):
            for x in range(640):
                px[x, y] = pic[y][x]
        img.save(os.path.join(out, 'colour.png'))
    except ImportError:
        pass


def newer(pic, cmap):
    """the newer tools in Sketch (V147): the oval's outline, the fill of
    pattern 2 inside it (aligned to the screen, as the kernel's patterns),
    the filled oval (pattern 2 too), the brush, the spray; their cards in
    colour 5"""
    def px(x, y):
        return pic[(y - CY) * CBYTES + (x // 8 - CX)] >> (7 - x % 8) & 1
    # the oval in the box 520, 30 - 620, 110: a = 50, b = 40, middle 570, 70
    if not (px(520, 70) and px(620, 70) and px(570, 30) and px(570, 110)):
        fail('the oval: its outline is not at its box\'s sides (%d %d %d %d)'
             % (px(520, 70), px(620, 70), px(570, 30), px(570, 110)))
    if px(519, 70) or px(621, 70) or px(570, 29) or px(570, 111):
        fail('the oval: ink outside its box')
    grey = [0xAA, 0x55] * 4
    bad = sum(1 for y in range(50, 91) for x in range(540, 601)
              if px(x, y) != (grey[y & 7] >> (7 - x % 8) & 1))
    if bad:
        fail('the fill: %d pixels inside the oval are not pattern 2' % bad)
    outside = sum(px(x, y) for y in range(130, 200) for x in range(530, 620))
    if outside:
        fail('the fill ran out of the oval (%d pixels set under it)' % outside)
    bad = sum(1 for y in range(392, 449) for x in range(545, 596)
              if px(x, y) != (grey[y & 7] >> (7 - x % 8) & 1))
    if bad or any(px(519, y) or px(621, y) for y in range(380, 461)):
        fail('the filled oval: %d pixels inside not pattern 2, or ink outside its box' % bad)
    brush = sum(px(x, y) for y in range(440, 458) for x in range(150, 290))
    spray = sum(px(x, y) for y in range(50, 71) for x in range(60, 101))
    if brush < 600 or spray < 20:
        fail('the brush (%d pixels) or the spray (%d dots)' % (brush, spray))
    c = lambda x, y: cmap[(y // 8 - 2) * 74 + x // 8 - 6]      # noqa: E731
    if c(570, 70) != 5 or c(570, 420) != 5 or c(200, 450) != 5 or c(70, 60) != 5:
        fail('the newer tools\' cards are not colour 5 (%d %d %d %d)' % (c(570, 70), c(570, 420), c(200, 450),
                                                                      c(70, 60)))
    ok('the newer tools (V147): an oval in its box, the fill of pattern 2 inside it and nowhere else, a '
       'filled oval in pattern 2, a brush stroke (%d pixels), the spray (%d dots), their cards in colour 5' % (brush, spray))


def timings(con):
    """the test build's frame timings (V147): each frame's work while a
    tool is dragged ("TIME drag" and the tool's letter: its column order
    from a) and the fills, at 8 MHz; reported"""
    import re
    names = 'select fill pencil brush spray eraser line text rectangle box oval disc'.split()
    per = {}
    for k, c in re.findall(r'TIME drag ([a-l]) ([0-9A-F]{8})', con):
        per.setdefault(names[ord(k) - 97], []).append(int(c, 16) / 8000)
    fills = [int(c, 16) / 8000 for c in re.findall(r'TIME fill ([0-9A-F]{8})', con)]
    if not per:
        fail('no frame timings on the console')
    ok('a frame\'s work while dragging (ms at 8 MHz, the status included; average / most, frames): ' +
       ', '.join('%s %.1f / %.1f (%d)' % (n, sum(v) / len(v), max(v), len(v)) for n, v in sorted(per.items())) +
       '; the fills %s ms' % ', '.join('%.0f' % t for t in fills))


def column(vram):
    """the Sunroom column (V147): tile mode on, tiles 0-15 solid, the
    column's cards in palette rows 2-11 (the chosen tool row 3), row 15
    the paper"""
    if not tilemode(vram):
        fail('Paint is not in tile mode (layer 0\'s tile base $%02X)' % vram[VRAM_ + COMPOSER_ + PALETTE_ + 2])
    for c in range(16):
        if set(vram[0x13000 + 32 * c:0x13000 + 32 * c + 32]) != {c << 4 | c}:
            fail('tile %d is not solid' % c)
    rows = {vram[MAP + 2 * (y * 128 + x) + 1] >> 4 for y in range(2, 60) for x in range(6)}
    if not rows <= set(range(0, 12)) or 3 not in rows:
        fail('the column\'s cards: palette rows %s' % sorted(rows))
    pal = vram[VRAM_ + COMPOSER_:]
    if any(pal[2 * (15 * 16 + i)] != 0xFF or pal[2 * (15 * 16 + i) + 1] != 0x0F for i in range(16)):
        fail('palette row 15 is not the paper')
    ok('the Sunroom column: tile mode, tiles 0-15 solid, the column in palette rows %s (3: the chosen tool), '
       'row 15 the paper' % sorted(rows))


def main():
    if sys.argv[1] == '--band':
        band(sys.argv[2], *map(int, sys.argv[3:7]))
        return
    if sys.argv[1] == '--dialog':
        dialog(sys.argv[2], sys.argv[3])
        return
    run, out = sys.argv[1], sys.argv[2]
    con = open(os.path.join(run, 'console.txt'), errors='replace').read()
    at = marks(con, ['PAINT RUNNING', 'PAINT NO PICTURES', 'PAINT SAVED', 'PAINT NEW', 'PAINT SAVED', 'PAINT NEW',
                     'PAINT OPENED', 'Sketch', 'PAINT OPENED', 'Picture'])
    if 'PAINT OPENED' in con[:at[6]]:
        fail('a picture was opened before the second save')
    before = con[at[1]:at[2]]
    if before.count('PAINT INVERTED') != 2 or 'PAINT ABOUT' not in before:
        fail('edit/invert twice and options/about before the save: not in the console')
    timings(con)
    ok('the session ran: file/open cancelled (Esc), drawn, edit/invert twice, '
       'options/about, saved, new, a second picture saved, new, opened through the dialog three times (the console in order)')
    for i in range(1, 6):
        if not os.path.exists(os.path.join(run, 'Draft %d.cvt' % i)):
            fail('Draft %d.cvt is missing' % i)

    d = open(os.path.join(run, 'dump.bin'), 'rb').read()
    vram = d[len(d) - VDUMP:]
    column(vram)
    saved = open(os.path.join(run, 'SAVED.RAW'), 'rb').read()
    clear = open(os.path.join(run, 'CLEAR.RAW'), 'rb').read()
    if len(saved) != CBYTES * ROWS or len(clear) != CBYTES * ROWS:
        fail('SAVED.RAW or CLEAR.RAW: %d and %d bytes' % (len(saved), len(clear)))
    ink = sum(bin(b).count('1') for b in saved)
    if ink < 10000:
        fail('the picture has only %d pixels set' % ink)
    # what the script drew: a freehand stroke, lines, rectangles, patterns
    def px(buf, x, y):
        return buf[(y - CY) * CBYTES + (x // 8 - CX)] >> (7 - x % 8) & 1
    probes = [((350, 120), 1, 'the rectangle\'s left side'), ((600, 199), 1, 'the rectangle\'s corner'),
              ((615, 340), 1, 'the black filled rectangle'), ((475, 100), 0, 'inside the rectangle'),
              ((211, 370), 1, 'the two lines cross')]
    for (x, y), v, what in probes:
        if not (px(saved, x, y) == v or (what.startswith('the two') and
                any(px(saved, x + dx, y + dy) for dx in (-2, -1, 0, 1, 2) for dy in (-2, -1, 0, 1, 2)))):
            fail('the picture at %d,%d (%s) is %d' % (x, y, what, px(saved, x, y)))
    ok('the picture at the start of the save: %d pixels set; the shapes where the script drew them' % ink)
    if any(clear):
        fail('file/new left %d bytes set' % sum(1 for b in clear if b))
    ok('file/new clears the drawing area')

    end = area(vram)
    if end != saved:
        n = sum(1 for a, b in zip(end, saved) if a != b)
        png(end, 592, os.path.join(out, 'reloaded.png'))
        fail('the picture opened again differs from the one saved in %d bytes' % n)
    ok('the picture opened again equals the one saved (VRAM: %d bytes)' % len(end))
    saved2 = open(os.path.join(run, 'SAVED2.RAW'), 'rb').read()
    op1 = open(os.path.join(run, 'OPENED.RAW'), 'rb').read()
    op2 = open(os.path.join(run, 'OPENED2.RAW'), 'rb').read()
    if saved2 == saved or sum(bin(b).count('1') for b in saved2) < 500:
        fail('the second picture is the first one, or nearly empty')
    newer(saved2, open(os.path.join(run, 'SAVED2.MAP'), 'rb').read())
    if op1 != saved2:
        fail('Sketch, chosen in the Open dialog, differs from the one saved in %d bytes'
             % sum(1 for a, b in zip(op1, saved2) if a != b))
    if op2 != saved:
        fail('Picture, chosen in the Open dialog, differs from the one saved')
    ok('file/open through the Open dialog: Sketch (\'s\', Return) and Picture (\'p\', Return) equal the pictures saved')

    cvt = open(os.path.join(run, 'Picture.cvt'), 'rb').read()
    if len(cvt) < 762 or SIG[:24] not in cvt[30:60]:
        fail('Picture.cvt is not a CVT file')
    e, info = cvt[0:30], bytes(2) + cvt[254:508]
    name = e[3:19].rstrip(b'\xa0')
    cls = info[77:97].split(b'\0')[0]
    parent = info[117:137].split(b'\0')[0]
    if name != b'Picture' or e[22] != APPL_DATA or e[21] != 1 or info[69] != APPL_DATA or info[70] != 1:
        fail('Picture.cvt: name %r, type %d, structure %d' % (name, e[22], e[21]))
    if cls != b'Paint Image V1.0' or parent != b'Paint       V1.0':
        fail('Picture.cvt: class %r, parent %r' % (cls, parent))
    # (the entry's block count stays as SaveFile wrote it: the record file's
    # write-back keeps the entry; reported, not checked)
    blocks = len(cvt) // 254 - 1
    ok('Picture.cvt: a VLIR document, APPL_DATA, class "Paint Image V1.0", parent "Paint       V1.0", '
       '%d blocks' % blocks)
    try:
        recs = records(cvt)
        if len(recs) != 1 + BANDS + 2 or recs[0] != b'VPNT\x03' + bytes([CBYTES, BANDH, BANDS, 1]):
            raise ValueError('%d records, record 0 %r' % (len(recs), recs[0][:8]))
        pic = b''.join(unpack(r, CBYTES * BANDH) for r in recs[1:1 + BANDS])
        cmap = bytes(b >> 4 - 4 * k & 15 for r in recs[1 + BANDS:] for b in r for k in (0, 1))
    except (ValueError, IndexError) as x:
        fail('Picture.cvt: %s' % x)
    if pic != saved:
        fail('Picture.cvt holds another picture (%d bytes differ)' % sum(1 for a, b in zip(pic, saved) if a != b))
    ok('Picture.cvt: 29 bands in records 1-29 (%d bytes packed, %d raw) unpack to the picture saved'
       % (sum(len(r) for r in recs[1:1 + BANDS]), len(pic)))
    colours(run, vram, cmap, out)
    png(saved, 592, os.path.join(out, 'picture.png'))

    # file/export (phase 9): Print.bmp, from the back screen, equals the
    # drawing area at the end (Picture, opened again)
    if 'PAINT EXPORTED\nPrint.bmp' not in con[at[-1]:].replace('\r', ''):
        fail('file/export: no "PAINT EXPORTED", "Print.bmp" after the last open')
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import check_color
    want = [[mapcol(vram, x, y) for x in range(80)] for y in range(60)]
    check_color.bmp4(os.path.join(run, 'Print.bmp'), vram, want, 48, 16, 639, 479)
    if check_color.failures:
        sys.exit(1)
    longname(run, con, saved)


LONG = 'Holiday sketch from the lake shore 2026'


def longname(run, con, saved):
    """DECISIONS V82: the picture saved through the Save dialog under a
    39-character name, file/new, opened through the Open dialog by it"""
    c = con.replace('\r', '')
    at = marks(c, ['PAINT EXPORTED', 'VRF NAME ' + LONG, 'PAINT SAVED', 'PAINT NEW', 'VRF NAME ' + LONG + '.cvt',
                   'PAINT OPENED\n' + LONG])
    path = os.path.join(run, LONG + '.cvt')
    if not os.path.exists(path):
        fail('no "%s.cvt" (%s)' % (LONG, sorted(os.listdir(run))))
    if [n for n in os.listdir(run) if '~' in n or n.endswith('.tmp')]:
        fail('a short form or a temporary file left: %s' % [n for n in os.listdir(run) if '~' in n or n.endswith('.tmp')])
    rd = lambda n: open(os.path.join(run, n), 'rb').read()      # noqa: E731
    s3, o3 = rd('SAVED3.RAW'), rd('OPENED3.RAW')
    if s3 != saved or o3 != s3:
        fail('the long-named picture: saved %s the picture, opened %s it'
             % ('as' if s3 == saved else 'NOT as', 'as' if o3 == s3 else 'NOT as'))
    if rd('OPENED3.MAP') != rd('SAVED3.MAP'):
        fail('the long-named picture\'s colours opened differ from those saved')
    cvt = rd(LONG + '.cvt')
    recs = records(cvt)
    pic = b''.join(unpack(r, CBYTES * BANDH) for r in recs[1:1 + BANDS])
    if pic != saved:
        fail('"%s.cvt" holds another picture' % LONG)
    ok('a long name (%d characters): saved through the Save dialog as "%s.cvt" (its 29 bands the picture), '
       'file/new, opened through the Open dialog by its name: the picture and its colours as saved; no '
       'short form or temporary file on the %s' % (len(LONG), LONG, 'folder'))


if __name__ == '__main__':
    main()
