#!/usr/bin/env python3
"""gate archive: synthetic GEOS disk images, made here with tools/vdisk.py
(no commercial GEOS disk is used or needed).

usage: archive_fixture.py <folder>

Writes into the folder:
  Disks/Test.d64   a GEOS disk: a geoPaint picture (part 2 too, two empty
                   records), a Photo Scrap, a photo album (three scraps and
                   an empty record), a geoWrite document, a font (Veranda's
                   system font in GEOS's format, 9 point), a Text Scrap (a
                   sequential GEOS file), an application (sequential), and
                   plain files: README (SEQ), GAME (PRG, 40 blocks), a
                   second GAME (PRG: GAME~2.PRG), A/B:C? (a name to clean),
                   a DEL separator (listed, not copied)
  Disks/Big.d81    a 1581 disk: the same files and 24 small documents more
                   (four directory blocks; the list scrolls)
  Disks/Side.d71   a 1571 disk: three files, one on the second side
Each GEOS file has an icon of its own.
"""
import os
import random
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'tools'))
import vdisk  # noqa: E402


def icon(seed):
    r = random.Random(seed)
    out = bytearray(63)
    for y in range(21):
        for x in range(24):
            edge = y in (0, 20) or x in (0, 23)
            inside = 3 <= x <= 20 and 3 <= y <= 17 and r.random() < 0.45
            if edge or inside:
                out[y * 3 + x // 8] |= 0x80 >> (x % 8)
    return bytes(out)


def geopaint_records(seed):
    """45 records of a page: frames, circles, diagonals, a checkerboard,
    coloured cards; records 20 and 21 empty, 37-44 empty"""
    r = random.Random(seed)
    W, H = 640, 720
    bits = [[0] * W for _ in range(H)]

    def px(x, y):
        if 0 <= x < W and 0 <= y < H:
            bits[y][x] = 1
    for k in range(0, 200, 12):                     # nested frames
        for x in range(20 + k, 620 - k):
            px(x, 20 + k)
            px(x, 300 - k // 2)
        for y in range(20 + k, 300 - k // 2):
            px(20 + k, y)
            px(619 - k, y)
    for i in range(700):                            # diagonals
        px(i, i)
        px(639 - i * 640 // 720, i)
    for cy in range(380, 460):                      # a circle (filled ring)
        for cx in range(400, 600):
            d = (cx - 500) ** 2 + ((cy - 420) * 2) ** 2
            if 1600 <= d <= 3600:
                px(cx, cy)
    for y in range(470, 560):                       # a checkerboard
        for x in range(40, 300):
            if (x // 8 + y // 8) & 1:
                px(x, y)
    for _ in range(3000):                           # noise
        px(r.randrange(W), r.randrange(H))
    recs = []
    for rec in range(45):
        if rec in (20, 21) or rec >= 37:
            recs.append(None)
            continue
        raw = bytearray()
        for half in range(2):
            for cx in range(80):
                for row in range(8):
                    y = rec * 16 + half * 8 + row
                    v = 0
                    for b in range(8):
                        v = v << 1 | bits[y][cx * 8 + b]
                    raw.append(v)
        raw += bytes(8)
        for half in range(2):
            cy = rec * 2 + half
            for cx in range(80):
                if 10 <= cx < 20 and 4 <= cy < 14:
                    c = 0x02            # black on red
                elif 50 <= cx < 66 and 30 <= cy < 40:
                    c = 0x67            # blue on yellow
                elif 70 <= cx < 80 and 6 <= cy < 10:
                    c = 0x10            # white on black
                elif cy >= 58:
                    c = 0x6F            # blue on light grey (part 2: a blue ink)
                else:
                    c = 0x01            # black on white
                raw.append(c)
        recs.append(vdisk.geopaint_pack(bytes(raw)))
        assert vdisk.geopaint_unpack(recs[-1]) == bytes(raw)
    return recs


def scrap(w, h, seed):
    r = random.Random(seed)
    raw = bytearray()
    for y in range(h):
        for x in range(w):
            if y in (0, h - 1) or x in (0, w - 1):
                raw.append(0xFF)
            elif (y // 4) % 3 == 0:
                raw.append(0x00)
            else:
                raw.append(r.randrange(256) & (0xAA if y & 1 else 0x55))
    d = bytes([w, h & 255, h >> 8]) + vdisk.bitmap_pack(bytes(raw))
    assert vdisk.bitmap_unpack(d[3:], w * h)[0] == bytes(raw)
    return d


def geowrite_records():
    ruler = bytes([0x11]) + bytes([0, 0, 0x7F, 0x02]) + bytes(22)
    page = ruler + bytes([0x17, 0, 0, 0]) + b'Dear reader,\rthis is a geoWrite page made for the gate.\r' + bytes([0x0C])
    page2 = ruler + b'The second page.\r' + bytes([0])
    return [page, page2] + [None] * 59 + [b'', b'', b'']


def font_cvt(fontbin):
    data = open(fontbin, 'rb').read()
    recs = [None] * 9 + [data]
    fid = 300
    extra = {128: fid.to_bytes(2, 'little'), 130: ((fid << 6) | 9).to_bytes(2, 'little'),
             0x61: b''}
    return vdisk.make_cvt('Veranda', 8, b'Veranda     V1.0', recs=recs, author=b'Veranda', extra=extra,
                          info_txt=b'A 9 point font.', icon=icon(8))


def geos_files(fontbin):
    out = []
    out.append(vdisk.make_cvt('Sunset', 7, b'Paint Image V1.1', recs=geopaint_records(1), author=b'',
                              parent=b'geoPaint    V2.0', info_txt=b'A picture.', icon=icon(1)))
    out.append(vdisk.make_cvt('Photo Scrap', 7, b'Photo Scrap V1.1', data=scrap(12, 60, 2), icon=icon(2)))
    out.append(vdisk.make_cvt('Holiday', 7, b'photo album V2.1',
                              recs=[scrap(8, 40, 3), scrap(30, 100, 4), None, scrap(40, 200, 5)],
                              parent=b'Photo Manager V1.1', icon=icon(3)))
    out.append(vdisk.make_cvt('Letter', 7, b'Write Image V2.1', recs=geowrite_records(),
                              parent=b'geoWrite    V2.1', icon=icon(4)))
    out.append(font_cvt(fontbin))
    out.append(vdisk.make_cvt('Text  Scrap', 7, b'Text  Scrap V1.1',
                              data=bytes([40, 0]) + b'Some text in a scrap.\r' + bytes(18), icon=icon(6)))
    out.append(vdisk.make_cvt('Hello', 6, b'Hello       V1.0', data=bytes(range(256)) * 3, icon=icon(7),
                              extra={71: b'\x00\x04', 73: b'\x00\x07', 75: b'\x00\x04'}))
    return out


def plain(img):
    img.add_plain(b'README', b'A plain sequential file.\r' * 8, 'SEQ')
    img.add_plain(b'GAME', bytes([0x01, 0x08]) + bytes((i * 7) & 255 for i in range(40 * 254 - 2)), 'PRG')
    img.add_plain(b'GAME', bytes([0x01, 0x08, 1, 2, 3]), 'PRG')
    img.add_plain(b'A/B:C?', b'odd name', 'PRG')
    e = bytearray(30)
    e[0] = 0x80
    e[3:19] = b'----------------'
    img.add_entry(bytes(e))


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    out = os.path.join(sys.argv[1], 'Disks')
    os.makedirs(out, exist_ok=True)
    fontbin = os.path.join(sys.argv[1], 'font.bin')
    subprocess.run([sys.executable, '-I', '-B', os.path.join(HERE, '..', 'tools', 'mkfont.py'), fontbin],
                   check=True, stdout=subprocess.DEVNULL)
    files = geos_files(fontbin)

    d = vdisk.Image(b'', 'D64')
    d.format('Archive Test')
    for f in files:
        d.add_cvt(f)
    plain(d)
    open(os.path.join(out, 'Test.d64'), 'wb').write(d.d)

    d = vdisk.Image(b'', 'D81')
    d.format('Big Disk')
    for f in files:
        d.add_cvt(f)
    plain(d)
    for i in range(24):
        d.add_cvt(vdisk.make_cvt('Note %02d' % (i + 1), 7, b'Text  Scrap V1.1',
                                 data=bytes([10, 0]) + b'note %02d\r' % (i + 1), icon=icon(100 + i)))
    open(os.path.join(out, 'Big.d81'), 'wb').write(d.d)

    d = vdisk.Image(b'', 'D71')
    d.format('Two Sides')
    d.add_cvt(files[1])
    keep = set(d.used)                          # side one taken for a moment:
    side1 = {(t, s) for t in range(1, 36) for s in range(d.g.spt(t))}
    d.used |= side1                             # FAR goes onto side two
    d.add_plain(b'FAR', bytes(range(256)) * 4, 'SEQ')
    d.used = keep | (d.used - side1)
    d.add_cvt(files[3])
    d.write_bam()
    open(os.path.join(out, 'Side.d71'), 'wb').write(d.d)


if __name__ == '__main__':
    main()
