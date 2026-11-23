#!/usr/bin/env python3
"""Gate pic (DECISIONS V105): a program's full-colour picture (the SDK's
vr_pic, mkwall.py --tiles) in an x16emu dump (-dump V) and console.

usage: check_pic.py files <OUT> <picture.png> ...
       check_pic.py shown <dump> <OUT> <picture.png> <row0> <row1>
       check_pic.py console <console.txt> [aside]
       check_pic.py kept <dump> <console.txt>

files: mkwall --tiles's OUT.map, .pal, .tiles and OUT.vram.N records
agree (the records' chunks rebuild the rows, tiles 16 on and the first
map), and OUT-k.png equals picture k pixel for pixel (a picture in few
colours: exact).
shown: tile mode ($62, tile base $98, the map at $1AC00); tiles 0-15
solid, the tiles from 16 the file's, the map's rows 2-59 the file's,
palette rows row0-row1 the file's, row 15 entry 0's colour; the screen as
VERA shows it equals the picture on every card but those with ink (the
program's line, "PICAPP"), whose ink is on both screens; the back screen
holds nothing else.
console: tests/pic_app.c's lines: START (tile mode off), ON (tile mode,
its VRAM); [aside] BACK equal to ON (its tiles, map and rows again after
the switcher), OFF: tile mode off, palette entries 32-255 as at START.
kept: the shell after it in tile mode, VRAM_TILEPAL ($12C00) as the
program's START (the rows it found, kept for the next).
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'tools'))
import check_tile as ct  # noqa: E402
import mkwall  # noqa: E402
import vram2png  # noqa: E402

MAP, TILES, BACK, TILEPAL = 0x1AC00, 0x13000, 0x09600, 0x12C00


def fail(m):
    print('FAIL ', m)
    sys.exit(1)


def records(out):
    k, recs = 1, []
    while os.path.exists('%s.vram.%d' % (out, k)):
        recs.append(open('%s.vram.%d' % (out, k), 'rb').read())
        k += 1
    return recs


def chunks(rec):
    i, out = 0, []
    while True:
        a = rec[i] | rec[i + 1] << 8 | rec[i + 2] << 16
        n = rec[i + 3] | rec[i + 4] << 8
        i += 5
        if not n:
            if i != len(rec):
                fail('a record goes on after its end')
            return out
        out.append((a, rec[i:i + n]))
        i += n


def files(out, pics):
    from PIL import Image
    mp, pb, tiles = (open(out + e, 'rb').read() for e in ('.map', '.pal', '.tiles'))
    if len(mp) != 9600 * len(pics):
        fail('%s.map: %d bytes for %d pictures' % (out, len(mp), len(pics)))
    recs = records(out)
    if not recs or any(len(r) > 8000 for r in recs):
        fail('the records: %s' % [len(r) for r in recs])
    vram = {}
    for k, r in enumerate(recs):
        for a, d in chunks(r):
            if k == 0 and not (0x1FA40 <= a < 0x1FBC0):
                fail('record 1 is not the palette rows alone')
            for j, b in enumerate(d):
                vram[a + j] = b
    row0 = (min(a for a in vram if a >= 0x1FA00) - 0x1FA00) // 32
    for j, b in enumerate(pb):
        if vram.get(0x1FA00 + 32 * row0 + j) != b:
            fail('the records\' palette rows are not %s.pal' % out)
    n = len(tiles) // 32
    for t in range(n):
        tt = t + 16
        a = TILES + 32 * (tt if tt < 480 else tt + 64)
        if bytes(vram.get(a + j) for j in range(32)) != tiles[32 * t:32 * t + 32]:
            fail('the records\' tile %d is not %s.tiles\'' % (tt, out))
    for y in range(2, 60):
        if bytes(vram.get(MAP + 256 * y + j) for j in range(160)) != mp[160 * y:160 * y + 160]:
            fail('the records\' map row %d' % y)
    for k, p in enumerate(pics):
        a = Image.open(p).convert('RGB').tobytes()
        b = Image.open('%s-%d.png' % (out, k)).convert('RGB').tobytes()
        if a[640 * 3 * 16:] != b[640 * 3 * 16:]:
            fail('%s-%d.png is not %s' % (out, k, p))
    print('ok    %s: %d tiles (16 solid), %d picture(s), %d records (%s bytes): the chunks rebuild the rows, the tiles '
          'and the first map; each picture exact (OUT-k.png)' % (os.path.basename(out), n + 16, len(pics), len(recs),
                                                                 ', '.join(str(len(r)) for r in recs)))


def shown(v, out, pic, row0, row1):
    from PIL import Image
    l0 = ct.layers(v)[0]
    if (l0[0], l0[2]) != (0x62, 0x98) or l0[1] != MAP >> 9:
        fail('layer 0: config $%02X, map $%02X, tile base $%02X: not tile mode' % (l0[0], l0[1], l0[2]))
    mp, pb, tiles = (open(out + e, 'rb').read() for e in ('.map', '.pal', '.tiles'))
    for c in range(16):
        if v[TILES + 32 * c:TILES + 32 * c + 32] != bytes([c * 17]) * 32:
            fail('tile %d is not solid colour %d' % (c, c))
    n = len(tiles) // 32
    lo = tiles[:min(n, 464) * 32]
    if v[TILES + 512:TILES + 512 + len(lo)] != lo:
        fail('the tiles in VRAM are not the file\'s')
    for y in range(2, 60):
        if v[MAP + 256 * y:MAP + 256 * y + 160] != mp[160 * y:160 * y + 160]:
            fail('map row %d is not the file\'s' % y)
    for i in range(16 * (row1 - row0 + 1)):
        if i % 16 and ct.pal(v, row0 * 16 + i) != pb[2 * i] | pb[2 * i + 1] << 8:
            fail('palette entry %d is not the file\'s' % (row0 * 16 + i))
    if any(ct.pal(v, 240 + i) != ct.pal(v, 0) for i in range(16)):
        fail('palette row 15 is not the paper')
    want = Image.open(pic).convert('RGB').tobytes()
    rows = vram2png.compose(v)
    inked = 0
    for cy in range(2, 60):
        for cx in range(80):
            ink = any(v[(cy * 8 + j) * 80 + cx] for j in range(8))
            if ink:
                inked += 1
                for j in range(8):
                    if v[(cy * 8 + j) * 80 + cx] != v[BACK + (cy * 8 + j) * 80 + cx]:
                        fail('card %d, %d: its ink is not on the back screen' % (cx, cy))
                continue
            for j in range(8):
                y = cy * 8 + j
                for i in range(8):
                    x = cx * 8 + i
                    if tuple(rows[y][x]) != tuple(want[3 * (y * 640 + x):3 * (y * 640 + x) + 3]):
                        fail('pixel %d, %d: %s on the screen, not %s\'s' % (x, y, rows[y][x], os.path.basename(pic)))
    if not 1 <= inked <= 12:
        fail('%d cards with ink (the program\'s line: 6 or so)' % inked)
    if any(v[BACK + 80 * y + x] for y in range(480) for x in range(80)
           if not any(v[(y // 8 * 8 + j) * 80 + x] for j in range(8))):
        fail('the back screen holds more than the program\'s ink')
    print('ok    tile mode ($62, $98), tiles 0-15 solid, the file\'s %d tiles, map and palette rows %d-%d, row 15 the '
          'paper; the screen as VERA shows it equals %s on every card without ink (%d with the program\'s line, '
          'on both screens); the back screen otherwise clear' % (n + 16, row0, row1, os.path.basename(pic), inked))


def lines(console):
    t = open(console, 'rb').read().decode('latin-1').replace('\r', '')
    got = {}
    for m in re.finditer(r'PICAPP (START|ON|BACK|OFF) L0 ([0-9A-F]{2}) TB ([0-9A-F]{2}) PAL ([0-9A-F]{4}) '
                         r'VRAM ([0-9A-F]{4})', t):
        got[m.group(1)] = tuple(int(m.group(k), 16) for k in range(2, 6))
    return t, got


def console(path, aside):
    t, got = lines(path)
    for k in ('START', 'ON') + (('BACK', 'OFF') if aside else ()):
        if k not in got:
            fail('no "PICAPP %s" line' % k)
    if got['START'][1] == 0x98:
        fail('tile mode at the start')
    if got['ON'][:2] != (0x62, 0x98):
        fail('after vr_pic_on: layer 0 $%02X, tile base $%02X' % got['ON'][:2])
    msg = 'START: tile mode off; ON: tile mode ($62, $98), palette sum %04X, VRAM sum %04X' % got['ON'][2:]
    if aside:
        if got['BACK'] != got['ON']:
            fail('back from the switcher %s, not as it left %s' % (got['BACK'], got['ON']))
        if got['OFF'][1] == 0x98 or got['OFF'][2] != got['START'][2]:
            fail('after vr_pic_off: tile base $%02X, palette sum %04X (at the start %04X)'
                 % (got['OFF'][1], got['OFF'][2], got['START'][2]))
        if 'PICAPP QUIT' not in t:
            fail('it did not quit')
        msg += ('; put aside (TASK_ASIDE) and back: vr_pic_back() 1, its rows from record 1, BACK equal to ON; '
                'vr_pic_off: tile mode off, palette entries 32-255 as at START (%04X)' % got['START'][2])
    print('ok    ' + msg)


def kept(v, path):
    _, got = lines(path)
    s = sum(v[TILEPAL:TILEPAL + 448]) & 0xFFFF
    if ct.layers(v)[0][2] != 0x98:
        fail('the shell after it is not in tile mode')
    if s != got['START'][2]:
        fail('the shell kept rows summing to %04X, not the ones the program found (%04X)' % (s, got['START'][2]))
    print('ok    the shell after it: tile mode, VRAM_TILEPAL the rows the program found (%04X)' % s)


def main():
    a = sys.argv[1:]
    if len(a) >= 3 and a[0] == 'files':
        files(a[1], a[2:])
    elif len(a) == 6 and a[0] == 'shown':
        shown(ct.section(a[1]), a[2], a[3], int(a[4]), int(a[5]))
    elif len(a) in (2, 3) and a[0] == 'console':
        console(a[1], len(a) == 3)
    elif len(a) == 3 and a[0] == 'kept':
        kept(ct.section(a[1]), a[2])
    else:
        sys.exit(__doc__)


if __name__ == '__main__':
    main()
