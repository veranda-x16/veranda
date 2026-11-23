#!/usr/bin/env python3
"""gate clip: the clipboard's files and screens (tools/gate_clip.sh;
docs/DECISIONS.md V54, docs/APPFORMAT.md "Scraps").

usage: check_clip.py --fixture <Text  Scrap.cvt>
           a Text Scrap as geoWrite 2.1 writes one on Veranda (its
           saveTextscrap through the kernel's SaveFile): GEOS text with a
           NEWCARDSET, a style change, a ruler, a TAB, CRs
       check_clip.py --copy <run dir>
           the session stopped after edit/copy: the Photo Scrap in
           <run>/VERANDA, its format, its bitmap equal to the selection on
           the back screen, its colours to the cards' (COPY.MAP)
       check_clip.py --term <Text  Scrap.cvt> <TERM.IN>
           Veranda Term's options/copy screen after the ANSI page: the
           format; the text is the reference terminal's screen
       check_clip.py --floating <dump.bin> <copy run dir>
           stopped while the paste floats: on the foreground only
       check_clip.py <run dir> <copy run dir> <fixture>
           the whole session: the paste on both screens and its colours,
           the cut, the albums, the scraps after the managers' copies

The format rules are geoWrite 2.1's (its scantextscrap, insertTextScrap-
FromDisk, addPhotoScrapToDoc, testFileVersion): found by name, sequential,
a class whose version is at most 2.1 (bytes 13 and 15 of the class), a
Text Scrap's count word then the text, a Photo Scrap's width, height
(below 145 rows for geoWrite) and compacted bitmap; plus CVT's (the
entry's size in blocks, the signature).
"""
import os
import re
import sys

VDUMP = 132878
BACK = 0x09600
SIG = b'PRG formatted GEOS file V1.0'
SYSTEM = 4
NEWCARDSET, ESC_RULER, ESC_GRAPHICS, PAGE_BREAK = 23, 17, 16, 12
MCARD, MROW, MW = 6, 2, 74


def fail(msg):
    print('FAIL  ' + msg)
    sys.exit(1)


def ok(msg):
    print('ok    ' + msg)


def vram(path):
    d = open(path, 'rb').read()
    return d[len(d) - VDUMP:]


def screen_area(v, base, l, t, r, b):
    return b''.join(v[base + y * 80 + l // 8:base + y * 80 + (r + 1) // 8] for y in range(t, b + 1))


def cvt(path, name, cls):
    """a scrap's CVT file: checked; (entry, info block, data)"""
    if not os.path.exists(path):
        fail('%s is missing' % path)
    f = open(path, 'rb').read()
    e, info, data = f[:30], f[254:508], f[508:]
    if e[0] != 0x83 or e[3:19] != name.encode().ljust(16, b'\xa0') or e[21] != 0 or e[22] != SYSTEM:
        fail('%s: the entry is not a sequential SYSTEM file named "%s" (%s)' % (path, name, e.hex()))
    blocks = -(-len(data) // 254) + 1
    if e[28] | e[29] << 8 != blocks:
        fail('%s: %d blocks in the entry, %d in the file' % (path, e[28] | e[29] << 8, blocks))
    if f[30:30 + len(SIG)] != SIG or any(f[30 + len(SIG):254]):
        fail('%s: no CVT signature' % path)
    if info[0:3] != b'\x03\x15\xbf' or info[66] != 0x83 or info[67] != SYSTEM or info[68] != 0:
        fail('%s: the info block\'s icon or types' % path)
    c = info[75:95]
    if not c.startswith(cls.encode()):
        fail('%s: class %r, not %r' % (path, c, cls))
    # geoWrite's testFileVersion: the class's version at most 2.1
    if not (c[13] < ord('2') or c[13] == ord('2') and c[15] <= ord('1')):
        fail('%s: geoWrite 2.1 refuses class version %c.%c' % (path, c[13], c[15]))
    return e, info, data


def unpack(d, n, at=0):
    """n bytes of GEOS's compacted format from d[at:] -> (bytes, end)"""
    out = bytearray()
    i = at

    def simple(i, sink):
        c = d[i]
        i += 1
        if c >= 0x80:
            k = c - 0x80
            sink += d[i:i + k]
            return i + k
        sink += bytes([d[i]]) * c
        return i + 1
    while len(out) < n:
        if i >= len(d):
            raise ValueError('the data ends after %d of %d bytes' % (len(out), n))
        c = d[i]
        if c >= 0xDC:
            ln, rep = c - 0xDC, d[i + 1]
            pat = i + 2
            for _ in range(rep):
                j = pat
                while j < pat + ln:
                    j = simple(j, out)
            i = pat + ln
        else:
            i = simple(i, out)
    if len(out) != n:
        raise ValueError('a code runs past the bitmap: %d of %d bytes' % (len(out), n))
    return bytes(out), i


def photo(path):
    """the Photo Scrap -> (w, h, bitmap, colours or None, data)"""
    _, _, data = cvt(path, 'Photo Scrap', 'Photo Scrap V2.0')
    w, h = data[0], data[1] | data[2] << 8
    bits, end = unpack(data, w * h, 3)
    cols = None
    if end < len(data):
        cols, end = unpack(data, w * ((h + 7) // 8), end)
    if end != len(data):
        fail('%s: %d bytes after the data' % (path, len(data) - end))
    return w, h, bits, cols, data


def plain(t):
    """GEOS text -> plain text (the escapes dropped), as scrap_get_text"""
    out, i = [], 0
    while i < len(t):
        c = t[i]
        i += 1
        if c == NEWCARDSET:
            i += 3
        elif c == ESC_RULER:
            i += 26
        elif c == ESC_GRAPHICS:
            i += 4
        elif c in (13, PAGE_BREAK):
            out.append('\n')
        elif c == 9 or 32 <= c < 127:
            out.append(chr(c))
    return ''.join(out)


def text(path, author=None):
    """the Text Scrap -> its text (the bytes after the count)"""
    _, info, data = cvt(path, 'Text  Scrap', 'Text  Scrap V2.0')
    n = data[0] | data[1] << 8
    if n != len(data) - 2:
        fail('%s: the count says %d bytes, %d follow' % (path, n, len(data) - 2))
    if author and not info[95:115].startswith(author.encode()):
        fail('%s: author %r' % (path, info[95:115]))
    return data[2:]


def records(path):
    f = open(path, 'rb').read()
    if f[21] != 1:
        fail('%s: not a record file' % path)
    t, pos, recs = f[508:762], 762, []
    for i in range(127):
        n, last = t[2 * i], t[2 * i + 1]
        if n == 0 and last == 0:
            break
        if n == 0:
            recs.append(b'')
            continue
        size = (n - 1) * 254 + last - 1
        recs.append(f[pos:pos + size])
        pos += n * 254
    return f, recs


def cmap(path):
    m = open(path, 'rb').read()
    if len(m) != 58 * 74:
        fail('%s: %d bytes' % (path, len(m)))
    return m


def card(m, cx, cy):
    return m[(cy - MROW) * MW + cx - MCARD]


# ---------------------------------------------------------------- the fixture
FIX_TEXT = (bytes([NEWCARDSET, 9, 0, 0]) + b'A scrap as geoWrite writes it: ' +
            bytes([NEWCARDSET, 9, 0, 0x40]) + b'bold' + bytes([NEWCARDSET, 9, 0, 0]) + b' and plain.\r' +
            bytes([ESC_RULER]) + bytes([0, 0, 0x7F, 0x02]) + bytes(range(16)) + bytes([0, 0, 0x10, 0, 0, 0]) +
            b'Second\tparagraph, after a ruler.\r')
FIX_PLAIN = 'A scrap as geoWrite writes it: bold and plain.\nSecond\tparagraph, after a ruler.\n'


def fixture(path):
    """what geoWrite's saveTextscrap gives through Veranda's SaveFile: the
    header's start and end the scrap's memory addresses, no author, the
    date of the save"""
    data = bytes([len(FIX_TEXT) & 255, len(FIX_TEXT) >> 8]) + FIX_TEXT
    start = 0x3E00
    e = bytearray(30)
    e[0] = 0x83
    e[3:19] = b'Text  Scrap'.ljust(16, b'\xa0')
    e[21], e[22] = 0, SYSTEM
    e[23:28] = bytes([126, 11, 16, 12, 0])
    b = -(-len(data) // 254) + 1
    e[28], e[29] = b & 255, b >> 8
    info = bytearray(254)                       # the header's bytes 2-255
    info[0:3] = b'\x03\x15\xbf'
    for i in range(63):                         # an icon (a frame; not geoWrite's)
        info[3 + i] = 0xFF if i < 3 or i >= 60 else (0x80 if i % 3 == 0 else 1 if i % 3 == 2 else 0)
    info[66], info[67], info[68] = 0x83, SYSTEM, 0
    end = start + len(FIX_TEXT) + 2
    info[69:75] = bytes([start & 255, start >> 8, end & 255, end >> 8, 0, 0])
    info[75:91] = b'Text  Scrap V2.0'
    with open(path, 'wb') as o:
        o.write(bytes(e) + SIG.ljust(224, b'\0') + bytes(info) + data)


# ---------------------------------------------------------------- the checks
SEL = (96, 96, 231, 207)
PASTE = (400, 296)
CUT = (480, 96, 575, 151)


def check_copy(run):
    con = open(os.path.join(run, 'console.txt'), errors='replace').read()
    if 'PAINT SELECTED' not in con or 'PAINT COPIED' not in con:
        fail('the console has no PAINT SELECTED, PAINT COPIED')
    v = vram(os.path.join(run, 'dump.bin'))
    w, h, bits, cols, _ = photo(os.path.join(run, 'VERANDA', '.SYSTEM', 'Photo Scrap.cvt'))
    l, t, r, b = SEL
    if (w, h) != ((r - l + 1) // 8, b - t + 1):
        fail('the Photo Scrap is %d cards x %d rows, not the selection\'s' % (w, h))
    if h >= 145:
        fail('%d rows: too tall for geoWrite' % h)
    if bits != screen_area(v, BACK, l, t, r, b):
        fail('the Photo Scrap\'s bitmap is not the selection on the back screen')
    ink = sum(bin(x).count('1') for x in bits)
    if ink < 1000:
        fail('the selection has only %d pixels set' % ink)
    m = cmap(os.path.join(run, 'COPY.MAP'))
    if cols is None:
        fail('the Photo Scrap has no colours (the selection has colour 5)')
    want = bytes(0x10 | card(m, l // 8 + x, t // 8 + y) for y in range(h // 8) for x in range(w))
    if cols != want:
        fail('the Photo Scrap\'s colours are not the cards\' (ink 1, paper the card\'s)')
    if 5 not in [c & 15 for c in cols] or 0 not in [c & 15 for c in cols]:
        fail('the colours should have 5 and 0 (the line over the rectangle)')
    ok('edit/copy: VERANDA/.SYSTEM/Photo Scrap.cvt is a GEOS Photo Scrap (CVT, sequential, SYSTEM, class '
       '"Photo Scrap V2.0", the blocks right): %d cards x %d rows, its compacted bitmap equal to the '
       'selection 96-231 x 96-207 on the back screen (%d pixels set), its %d colours the cards\' '
       '(ink 1, paper 0 or 5); geoWrite 2.1\'s rules hold (the class version, below 145 rows)'
       % (w, h, ink, len(cols)))


def check_text(path, want):
    t = text(path, 'Veranda')
    if t[:4] != bytes([NEWCARDSET, 9, 0, 0]):
        fail('%s: it does not start with a NEWCARDSET (BSW 9, plain)' % path)
    got = plain(t)
    if got != want:
        fail('%s: the text is %r, not %r' % (path, got[:200], want[:200]))
    ok('%s: a GEOS Text Scrap (the count, a NEWCARDSET, %d characters); the text is the one expected'
       % (path, len(got)))


def check_session(run, crun, fix):
    con = open(os.path.join(run, 'console.txt'), errors='replace').read()
    order = ['PAINT RUNNING', 'PAINT SELECTED', 'PAINT COPIED', 'PAINT FLOATING', 'PAINT PASTED', 'MAN RUNNING',
             'MAN ADDED', 'MAN COPIED', 'MAN CLOSED', 'PAINT DESK BACK', 'PAINT SELECTED', 'PAINT CUT',
             'MAN RUNNING', 'MAN ADDED', 'MAN COPIED', 'MAN CLOSED', 'PAINT DESK BACK']
    at = 0
    for m in order:
        i = con.find(m, at)
        if i < 0:
            fail('the console: no "%s" after position %d' % (m, at))
        at = i + len(m)
    ok('the session ran: select, copy, paste (floating, put down), the Photo Manager (add, copy, close), '
       'select, cut, the Text Manager (add, copy, close): the console in order')
    stamps = re.findall(r'PAINT STAMP 1 ([0-9A-F]{16})', con)
    if len(stamps) != 2 or stamps[0] == stamps[1] or stamps[0] == '0' * 16:
        fail('the Photo Scrap\'s stamps at the copy and the cut: %s' % stamps)
    s0, s1 = bytes.fromhex(stamps[0]), bytes.fromhex(stamps[1])
    if (s1[5] | s1[6] << 8) != (s0[5] | s0[6] << 8) + 2:
        fail('the serial: %s then %s (the Photo Manager\'s copy in between: + 2)' % (stamps[0], stamps[1]))
    ok('scrap_stamp: the Photo Scrap\'s stamp changed between the copy and the cut, its serial + 2 '
       '(the Photo Manager wrote it in between)')

    v = vram(os.path.join(run, 'dump.bin'))
    cw, ch, cbits, ccols, cdata = photo(os.path.join(crun, 'VERANDA', '.SYSTEM', 'Photo Scrap.cvt'))
    x, y = PASTE
    r, b = x + cw * 8 - 1, y + ch - 1
    for base, what in ((0, 'foreground'), (BACK, 'back screen')):
        if screen_area(v, base, x, y, r, b) != cbits:
            fail('the pasted picture at %d,%d on the %s is not the copy' % (x, y, what))
    l, t, rr, bb = SEL
    if screen_area(v, BACK, l, t, rr, bb) != cbits:
        fail('the source area changed')
    pm = cmap(os.path.join(run, 'PASTE.MAP'))
    got = bytes(card(pm, x // 8 + i, y // 8 + j) for j in range(ch // 8) for i in range(cw))
    if got != bytes(c & 15 for c in ccols):
        fail('the pasted cards\' colours are not the copy\'s')
    ok('edit/paste: the picture put down at %d,%d (the press at 404,300, on a card) equals the copy on both '
       'screens; its %d cards have the copy\'s colours; the source is unchanged' % (x, y, len(got)))

    # the Photo Manager: the album's page 0 is the copy; its copy went to the clipboard
    f, recs = records(os.path.join(run, 'VERANDA', '.SYSTEM', 'Photo Album.cvt'))
    if f[22] != 7 or not f[254 + 75:].startswith(b'Photo Album V1.0'):
        fail('Photo Album.cvt: not an APPL_DATA file of class "Photo Album V1.0"')
    if len(recs) != 1 or recs[0] != cdata:
        fail('Photo Album.cvt: %d records; the first is not the Photo Scrap' % len(recs))
    ok('the Photo Manager: Photo Album.cvt (a record file, class "Photo Album V1.0", in VERANDA/.SYSTEM) '
       'has one page, the Photo Scrap\'s data byte for byte')

    # the cut: the Photo Scrap is the area as it was; the area is empty, its cards 0
    pre = open(os.path.join(run, 'PRECUT.RAW'), 'rb').read()
    l, t, r, b = CUT
    was = b''.join(pre[(yy - 16) * 74 + l // 8 - 6:(yy - 16) * 74 + (r + 1) // 8 - 6] for yy in range(t, b + 1))
    w2, h2, bits2, cols2, _ = photo(os.path.join(run, 'VERANDA', '.SYSTEM', 'Photo Scrap.cvt'))
    if (w2, h2) != ((r - l + 1) // 8, b - t + 1) or bits2 != was or cols2 is not None:
        fail('the Photo Scrap after the cut: %d x %d, not the area as it was (or it has colours)' % (w2, h2))
    if sum(bin(c).count('1') for c in was) < 50:
        fail('the cut area had nothing in it')
    for base, what in ((0, 'foreground'), (BACK, 'back screen')):
        if any(screen_area(v, base, l, t, r, b)):
            fail('the cut area is not empty on the %s' % what)
    um = cmap(os.path.join(run, 'CUT.MAP'))
    if any(card(um, cx, cy) for cy in range(t // 8, b // 8 + 1) for cx in range(l // 8, (r + 1) // 8)):
        fail('the cut area\'s cards are not 0')
    ok('edit/cut: the Photo Scrap is the area 480-575 x 96-151 as it was (no colours: none set there); the '
       'area is empty on both screens, its cards 0')

    # the Text Manager: the fixture (geoWrite's format) into the album and back
    fixdata = open(fix, 'rb').read()[508:]
    f, recs = records(os.path.join(run, 'VERANDA', '.SYSTEM', 'Text Album.cvt'))
    if not f[254 + 75:].startswith(b'Text Album V1.0') or len(recs) != 1 or recs[0] != fixdata:
        fail('Text Album.cvt: not one page equal to the Text Scrap geoWrite wrote')
    t = text(os.path.join(run, 'VERANDA', '.SYSTEM', 'Text  Scrap.cvt'), 'Veranda')
    if bytes([len(t) & 255, len(t) >> 8]) + t != fixdata:
        fail('the Text Scrap after the Text Manager\'s copy is not the album\'s page')
    if plain(t) != FIX_PLAIN:
        fail('the text: %r' % plain(t))
    ok('the Text Manager: the Text Scrap in geoWrite\'s format (NEWCARDSET, a bold run, a ruler, a TAB) went '
       'into Text Album.cvt and back to VERANDA/.SYSTEM/Text  Scrap.cvt byte for byte, now in Veranda\'s info block')


def check_floating(dump, crun):
    """stopped while the paste floats at 400,296: on the foreground only"""
    v = vram(dump)
    _, _, cbits, _, _ = photo(os.path.join(crun, 'VERANDA', '.SYSTEM', 'Photo Scrap.cvt'))
    x, y = PASTE
    r, b = x + 17 * 8 - 1, y + 112 - 1
    if screen_area(v, 0, x, y, r, b) != cbits:
        fail('the floating picture is not on the foreground at %d,%d' % (x, y))
    if screen_area(v, BACK, x, y, r, b) == cbits or any(screen_area(v, BACK, x, y, r, b)[:0]):
        fail('the floating picture is on the back screen too')
    ok('the paste floats under the pointer: at 400,296 on the foreground only (the back screen as before)')


def check_term(path, src):
    """Veranda Term's options/copy screen: the reference terminal's rows
    (tests/check_term.py) fed the page, each without its trailing spaces,
    the empty rows at the end left out, non-ASCII as '?'"""
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import check_term
    vt = check_term.VT()
    for b in open(src, 'rb').read():
        vt.put(b)
    rows = [''.join(chr(c) if 32 <= c < 127 else '?' for c, a in r).rstrip() for r in vt.rows]
    while rows and not rows[-1]:
        rows.pop()
    want = ''.join(r + '\n' for r in rows)
    check_text(path, want)
    ok('Veranda Term\'s copy screen: %d rows of the ANSI page, as the reference terminal shows them' % len(rows))


def main():
    a = sys.argv[1:]
    if a[0] == '--term':
        check_term(a[1], a[2])
        return
    if a[0] == '--floating':
        check_floating(a[1], a[2])
        return
    if a[0] == '--fixture':
        fixture(a[1])
        text(a[1])
        ok('the geoWrite-format Text Scrap: %s' % a[1])
    elif a[0] == '--copy':
        check_copy(a[1])
    else:
        check_session(*a[:3])


if __name__ == '__main__':
    main()
