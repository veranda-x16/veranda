#!/usr/bin/env python3
"""A Veranda wallpaper (the desktop picture: Veranda Look 2 step C,
docs/DECISIONS.md V78; in full colour since V101) from a picture, as a
GEOS document.

usage: mkwall.py [-o out.cvt] [--name NAME] [--dark-level F] [--stretch] [--max N]
                 [--dither | --no-dither] [--v2] <picture | --dusk | --dusk-scene | --from old.cvt>
       mkwall.py --png out.png [--dark] <wallpaper.cvt>
       mkwall.py --check <wallpaper.cvt>
       mkwall.py --tiles OUT [--rows A-B] [--colours N] [--max N] [--paper RGB]
                 [--first-card N] [--dither | --no-dither] <picture> [picture ...]

<picture>: any picture Pillow reads (PNG, JPEG ...), cropped to 4:3 round
its middle (--stretch: not cropped) and resized to 640 x 480; --dusk:
Dusk, the wallpaper Veranda ships (since V175 drawn as tiles by
tools/wall_dusk.py: 113 tiles in one palette row; with --v2 the scene
below converted as before); --dusk-scene: the built-in dusk scene (the
Look 2 proposal's, a gradient: Dusk until V175) converted, dithered;
--from: a wallpaper of version 1 or 2 as it showed, made again (as
version 3); --v2: a version 2 file (the shell shows it without its colour
chrome).

The shell shows a wallpaper on VERA's layer 0 as 4 bpp tiles of 8 x 8
pixels (DECISIONS V101) under the 1 bpp bitmap, which is 0 (no ink) over
the picture. A wallpaper is
  - up to 480 tiles (VRAM $13000-$16BFF; 352 by default, --max: the
    rest are the shell's colour icons', V153); tiles 0-15 are solid
    (tile c: every pixel c), the shell's own colours a card use them;
  - a map entry a card (VERA's: the tile, its palette row, its flips);
  - palette rows 2-10 (9 rows of 10 colours; index 0 is transparent:
    the picture uses 1-10; 11-15 of each row are the shell's chrome
    shades, DECISIONS V102), in a light and a dark version (dark mode
    swaps the rows; the same tiles and map). Row 0 is the UI's, row 1
    the pointer's, 11 and 12 the shell's colour icons' (V133, V153), 13
    the shell's chrome, 14 the menus' highlight, 15 the covered cards'
    paper. (Before V153 rows 2-12: the shell shows such a file with
    Look 2's tiles for icons. Version 2, V101: rows 2-13 of 15 colours.)
The conversion (tools/wallcv.c, a C helper this script compiles once
into ~/.cache/veranda; about two seconds a picture): palette rows by
k-means, each card to its best row, its pixels to that row's colours (a
4 x 4 Bayer dither for gradients: on unless the picture has few exact
12-bit colours, --dither / --no-dither), equal tiles merged with H and V
flips, the rest merged greedily to 352 (--max) and refined. A picture in few
colours that fits comes out exact. The dark rows are the
light ones darkened (--dark-level, 0.55).

The file (docs/APPFORMAT.md, "Wallpapers"): a sequential GEOS document
(APPL_DATA, class "Wallpaper   V3.0"), its data
    0   "VWAL"   4 version (3)   5 variants (2: light, dark)
    6   80 (cards across)        7 60 (card rows)
    8   the tiles (a word, 16-480)
    10  the first palette row (2)   11 the rows (9; 11 before V153)   12-15 0
    16  the light rows: rows * 16 words ($0RGB, little-endian; index 0 0)
    16 + rows * 32  the dark rows
    16 + rows * 64  the map: 60 rows of 80 entries of 2 bytes (rows 0-1,
                    under the menu bar, are tile 0)
    + 9600  the tiles, 32 bytes each (4 bpp, high nibble the left pixel)
Version 2 (V101) is the same with rows 2-13 of 15 colours. Version 1
(V78: a 1 bpp bitmap over a colour a card) is read by --png, --check and
--from; the shell shows the pattern for it.

--png renders a wallpaper file as VERA shows it (light, or --dark);
--check checks a file's structure. Inputs are only read.

--tiles (DECISIONS V105): a program's own full-screen picture, for the
SDK's vr_pic (vrpic.h): the kernel's tile mode while the program runs.
Each picture is 640 x 480 (resized if not); several are converted
together (up to 4: a program's other states, e.g. its lamps lit): the
same tiles and palette rows, a map each. --rows the palette rows it may
use (2-13: 14 and 15 are the kernel's, 0 the UI's, 1 the pointer's; a
program with 4 bpp sprites keeps their rows out), --colours the indices
of a row (1 .. 15), --max the tiles in all with the 16 solid ones (480:
VRAM $13000-$16BFF, the save-under stack's room; up to 928 when the
program keeps no sprite pictures in sprite slots 1-7, $17400-$1ABFF:
tiles 544-991; tiles 480-543 are sprite slot 0, the pointer's, and are
skipped),
--first-card the first card row (2: rows 0-1 are the menu bar's, tile 0,
the paper), --paper the colour a tile's pixel 0 shows (palette entry 0,
for OUT-*.png). Writes
    OUT.map      a map a picture: 60 rows of 80 VERA entries (2 bytes:
                 the tile's low byte; palette row << 4 | vflip << 3 |
                 hflip << 2 | the tile's bits 8-9), tile numbers as in VRAM
    OUT.pal      the rows: 16 words each ($0RGB; index 0 is 0)
    OUT.tiles    the tiles from 16 on, 32 bytes each, in VRAM order (tile t
                 at $13000 + 32 t; from 544 on at $17400 + 32 (t - 544))
    OUT.vram.1 ...  records for vr_vram_load: VRAM chunks (3 bytes the
                 address, 2 the length, the bytes; a length 0 ends), at
                 most 8,000 bytes each: record 1 the palette rows alone (a
                 program puts them back after vr_pic_back), then the tiles
                 and the first picture's map
    OUT-0.png ...  each picture as VERA shows it
and prints a line: tiles, unique cards, PSNR.
"""
import hashlib
import math
import os
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import vpack  # noqa: E402

W, H = 640, 480
CW, CH = 80, 60
MAGIC = b'VWAL'
VERSION = 3
HEAD = 16
ROW0, ROWS = 2, 9                            # the picture's palette rows (V153: 2-10; 11 before,
                                             # so the colour icons' rows 11-12 are free)
NCOL = 10                                    # their colours: indices 1-10 (11-15: the shell's)
ROWS2, NCOL2 = 12, 15                        # version 2's (V101)
MAXTILES = 480                               # $13000-$16BFF
WALLMAX = 352                                # (V153) a wallpaper's by default: tiles 352-479 are the
                                             # shell's colour icons' (--max 480: all for the picture)
FIRSTCARD = 2                                # card rows 0-1: the menu bar
MAPLEN = CW * CH * 2
# version 1 (V78)
V1_VARIANT = 8 + CW * CH + W * H // 8        # 43208
V1_FREE = (12, 13, 14, 15)
# Look 2's palette (sdk/lib/theme.c), light and dark
LIGHT = [0x0FFF, 0x0223, 0x0DDE, 0x0EEF, 0x09CF, 0x0ACE, 0x0FD5, 0x0F87,
         0x08D9, 0x0B9F, 0x0FA5, 0x06CE, 0x036A, 0x08BE, 0x05A7, 0x0DAC]
DARK = [0x0334, 0x0EEF, 0x0223, 0x0223, 0x0357, 0x0346, 0x0A82, 0x0A44,
        0x0385, 0x0649, 0x0A62, 0x0278, 0x0124, 0x0247, 0x0253, 0x0535]
BAYER = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]


def rgb(c):
    """$0RGB -> 8-bit channels, as VERA's 4-bit ones show"""
    return ((c >> 8 & 15) * 17, (c >> 4 & 15) * 17, (c & 15) * 17)


def word(p):
    """8-bit channels -> the nearest $0RGB"""
    q = [min(15, max(0, int(round(v / 17.0)))) for v in p]
    return q[0] << 8 | q[1] << 4 | q[2]


# ---------------------------------------------------------------- pictures
def dusk(x, y):
    """the built-in scene: a dusk sky over two lines of hills (the
    proposal's mockup, look/mock.py)"""
    def mix(a, b, t):
        return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t)
    top, mid, low = (40, 70, 140), (120, 170, 225), (225, 170, 200)
    t = y / 330
    sky = mix(top, mid, min(1, t * 1.6)) if t < .62 else mix(mid, low, min(1, (t - .62) / .38))
    h1 = 300 + 28 * math.sin(x / 70) + 14 * math.sin(x / 23 + 1)
    h2 = 350 + 20 * math.sin(x / 55 + 2) + 9 * math.sin(x / 17)
    if y > h2:
        return mix((70, 140, 100), (30, 60, 50), min(1, (y - h2) / 110))
    if y > h1:
        return mix((120, 110, 160), (90, 80, 130), min(1, (y - h1) / 60))
    return sky


def dusk_pixels():
    return [dusk(x, y) for y in range(H) for x in range(W)]


def picture_pixels(path, stretch=False):
    from PIL import Image
    img = Image.open(path).convert('RGB')
    if not stretch:
        w, h = img.size
        if w * 3 > h * 4:                   # wider than 4:3
            nw = h * 4 // 3
            img = img.crop(((w - nw) // 2, 0, (w - nw) // 2 + nw, h))
        elif w * 3 < h * 4:
            nh = w * 3 // 4
            img = img.crop((0, (h - nh) // 2, w, (h - nh) // 2 + nh))
    if img.size != (W, H):
        img = img.resize((W, H), Image.LANCZOS)
    b = img.tobytes()
    return [(float(b[i]), float(b[i + 1]), float(b[i + 2])) for i in range(0, len(b), 3)]


def rgb_bytes(px):
    return bytes(min(255, max(0, int(round(v)))) for p in px for v in p)


def few_colours(raw):
    """1 if the picture is in exact 12-bit colours, few enough for the
    rows (no dither then: it comes out exact when its tiles fit)"""
    cols = set()
    for i in range(0, len(raw), 3):
        c = raw[i:i + 3]
        if c[0] % 17 or c[1] % 17 or c[2] % 17:
            return False
        cols.add(c)
        if len(cols) > ROWS * NCOL:
            return False
    return True


# ---------------------------------------------------------------- the converter
def helper():
    """tools/wallcv.c compiled (once per version of it) into the cache"""
    src = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'wallcv.c')
    code = open(src, 'rb').read()
    cache = os.environ.get('VERANDA_CACHE') or os.path.join(
        os.environ.get('XDG_CACHE_HOME') or os.path.join(os.path.expanduser('~'), '.cache'), 'veranda')
    exe = os.path.join(cache, 'wallcv-' + hashlib.sha1(code).hexdigest()[:12])
    if os.path.exists(exe):
        return exe
    os.makedirs(cache, exist_ok=True)
    cc = os.environ.get('CC', 'cc')
    tmp = exe + '.%d' % os.getpid()
    for flags in (['-O2', '-fopenmp'], ['-O2']):
        r = subprocess.run([cc] + flags + ['-o', tmp, src, '-lm'], capture_output=True, text=True)
        if r.returncode == 0:
            os.replace(tmp, exe)
            return exe
    raise ValueError('cannot compile %s with %s:\n%s' % (src, cc, r.stderr))


def convert(raw, dither, log=None, v2=False):
    """640 x 480 RGB bytes -> (tiles, map, light rows (words), result line)"""
    exe = helper()
    rows, ncol = (ROWS2, NCOL2) if v2 else (ROWS, NCOL)
    with tempfile.TemporaryDirectory() as d:
        i = os.path.join(d, 'in.rgb')
        open(i, 'wb').write(raw)
        o = os.path.join(d, 'out')
        r = subprocess.run([exe, i, o, str(ROW0), str(rows), str(WALLMAX), '1' if dither else '0',
                            str(FIRSTCARD), str(ncol)], capture_output=True, text=True)
        if r.returncode:
            raise ValueError('wallcv: ' + (r.stderr or r.stdout).strip())
        tiles = open(o + '.tiles', 'rb').read()
        mp = open(o + '.map', 'rb').read()
        p = open(o + '.pal', 'rb').read()
    rows = [p[2 * i] | p[2 * i + 1] << 8 for i in range(len(p) // 2)]
    res = r.stdout.strip()
    if log:
        log('mkwall: %s (dither %s)' % (res, 'on' if dither else 'off'))
    return tiles, mp, rows, res


def darken(rows, level):
    return [0 if i % 16 == 0 else word(tuple(v * level for v in rgb(c))) for i, c in enumerate(rows)]


def icon(px):
    """a 24 x 21 icon: the picture's light, dithered"""
    out = bytearray()
    for y in range(21):
        for b in range(3):
            v = 0
            for i in range(8):
                x = b * 8 + i
                if x == 0 or x == 23 or y == 0 or y == 20:
                    v |= 0x80 >> i
                    continue
                sx, sy = x * W // 24, y * H // 21
                t = px[sy * W + sx]
                lum = (t[0] * 0.3 + t[1] * 0.59 + t[2] * 0.11) / 255
                if BAYER[(y & 3) * 4 + (x & 3)] >= lum * 16:
                    v |= 0x80 >> i
            out.append(v)
    return bytes(out)


def make(px, name, dark_level=0.55, dither=None, log=None, v2=False):
    raw = rgb_bytes(px)
    if dither is None:
        dither = not few_colours(raw)
    tiles, mp, light, _ = convert(raw, dither, log, v2)
    dark = darken(light, dark_level)
    n = len(tiles) // 32
    data = (MAGIC + bytes([2 if v2 else VERSION, 2, CW, CH]) + n.to_bytes(2, 'little')
            + bytes([ROW0, ROWS2 if v2 else ROWS]) + bytes(4)
            + b''.join(c.to_bytes(2, 'little') for c in light + dark) + mp + tiles)
    return vpack.pack_doc(name, 'Wallpaper', data, icon=icon(px), version='2.0' if v2 else '3.0', author='Veranda',
                          description='A desktop picture for the shell (Preferences, Desktop).')


# ---------------------------------------------------------------- reading
def read(path):
    """a wallpaper file -> its data (raises ValueError)"""
    d = open(path, 'rb').read()
    try:
        info = vpack.parse(d)
    except vpack.PackError as e:
        raise ValueError(str(e))
    if info['structure'] != 'sequential' or not info['class'].startswith('Wallpaper'):
        raise ValueError('%s: not a wallpaper (class %s)' % (path, info['class']))
    data = d[508:]
    if data[:4] != MAGIC or data[4] not in (1, 2, 3) or data[6] != CW or data[7] != CH:
        raise ValueError('%s: not a wallpaper of version 1, 2 or 3' % path)
    want = HEAD + data[5] * V1_VARIANT if data[4] == 1 else size2(data)
    if len(data) != want:
        raise ValueError('%s: %d bytes of data, not %d' % (path, len(data), want))
    return data


def size2(data):
    return HEAD + 2 * data[11] * 32 + MAPLEN + (data[8] | data[9] << 8) * 32


def parts2(data, v):
    """version 2 or 3, variant v -> (palette (256 words: rows 0-1 and 14-15 as
    the shell sets them; version 3's entries 11-15 of the picture's rows and
    row 13 0, the shell's chrome), map, tiles)"""
    r0, nr = data[10], data[11]
    o = HEAD + v * nr * 32
    pal = [0] * 256
    pal[:16] = DARK if v else LIGHT
    for i in range(nr * 16):
        pal[r0 * 16 + i] = data[o + 2 * i] | data[o + 2 * i + 1] << 8
    for i in range(16):
        pal[240 + i] = pal[0]
    m = HEAD + 2 * nr * 32
    n = data[8] | data[9] << 8
    return pal, data[m:m + MAPLEN], data[m + MAPLEN:m + MAPLEN + n * 32]


def parts(data, v):
    """version 1, variant v -> (16 palette entries, colours, bitmap)"""
    o = HEAD + v * V1_VARIANT
    pal = list(DARK if v else LIGHT)
    for j, f in enumerate(V1_FREE):
        pal[f] = data[o + 2 * j] | data[o + 2 * j + 1] << 8
    return pal, data[o + 8:o + 8 + CW * CH], data[o + 8 + CW * CH:o + V1_VARIANT]


def tile_pixel(tiles, t, x, y, flags):
    if flags & 4:
        x = 7 - x
    if flags & 8:
        y = 7 - y
    b = tiles[t * 32 + y * 4 + x // 2]
    return b & 15 if x & 1 else b >> 4


def render(data, v):
    """as VERA shows it: a list of rows of RGB (version 2: the menu bar's
    rows as paper)"""
    rows = []
    if data[4] == 1:
        pal, cols, bm = parts(data, v)
        ink = rgb(pal[1])
        for y in range(H):
            r = []
            for x in range(W):
                if bm[y * (W // 8) + x // 8] & (0x80 >> (x & 7)):
                    r.append(ink)
                else:
                    r.append(rgb(pal[cols[(y // 8) * CW + x // 8] & 15]))
            rows.append(r)
        return rows
    pal, mp, tiles = parts2(data, v)
    cache = {}
    for y in range(H):
        r = []
        for x in range(W):
            e = 2 * ((y // 8) * CW + x // 8)
            lo, hi = mp[e], mp[e + 1]
            t = lo | (hi & 3) << 8
            k = (t, hi & 12, x & 7, y & 7)
            p = cache.get(k)
            if p is None:
                p = cache[k] = tile_pixel(tiles, t, x & 7, y & 7, hi)
            r.append(rgb(pal[(hi >> 4) * 16 + p] if p else pal[0]))
        rows.append(r)
    return rows


def check2(data):
    """version 2's or 3's structure -> lines"""
    n = data[8] | data[9] << 8
    r0, nr = data[10], data[11]
    last, ncol = (13, NCOL2) if data[4] == 2 else (12, NCOL)       # (version 3 of before V153: rows 2-12)
    if not 16 <= n <= MAXTILES:
        raise ValueError('%d tiles: 16-%d' % (n, MAXTILES))
    if r0 < 2 or r0 + nr > last + 1:
        raise ValueError('palette rows %d-%d: 2-%d only' % (r0, r0 + nr - 1, last))
    out = []
    for v in range(2):
        pal, mp, tiles = parts2(data, v)
        for c in range(16):
            if tiles[c * 32:c * 32 + 32] != bytes([c << 4 | c]) * 32:
                raise ValueError('tile %d is not solid colour %d' % (c, c))
        used = set()
        rows = set()
        for cy in range(CH):
            for cx in range(CW):
                e = 2 * (cy * CW + cx)
                t = mp[e] | (mp[e + 1] & 3) << 8
                if t >= n:
                    raise ValueError('card %d, %d: tile %d of %d' % (cx, cy, t, n))
                if cy < FIRSTCARD:
                    continue
                r = mp[e + 1] >> 4
                if not r0 <= r < r0 + nr:
                    raise ValueError('card %d, %d: palette row %d' % (cx, cy, r))
                if t not in used and t >= 16 and max(max(b >> 4, b & 15) for b in tiles[t * 32:t * 32 + 32]) > ncol:
                    raise ValueError('tile %d: a pixel above %d (version %d)' % (t, ncol, data[4]))
                if t < 16 and t > ncol:
                    raise ValueError('card %d, %d: solid tile %d (version %d: 1-%d)' % (cx, cy, t, data[4], ncol))
                used.add(t)
                rows.add(r)
        out.append('version %d, variant %d: %d tiles (%d used), palette rows %d-%d (%d used) of %d colours, row %d $%s' % (
            data[4], v, n, len(used), r0, r0 + nr - 1, len(rows), ncol, r0,
            ' $'.join('%03X' % pal[r0 * 16 + i] for i in range(1, ncol + 1))))
    return out


# ---------------------------------------------------------------- a program's picture (V105)
PIC_TILES = 0x13000
PIC_SLOT0, PIC_SLOT1 = 480, 544              # tiles 480-543: sprite slot 0 (the pointer)
PIC_MAX = 480 + (0x1AC00 - 0x17400) // 32    # 928 (the last, 991, ends at $1ABFF)
PIC_MAP = 0x1AC00
PIC_PALETTE = 0x1FA00


def pic_addr(t):
    """tile t's VRAM address (t as in the map)"""
    if PIC_SLOT0 <= t < PIC_SLOT1:
        raise ValueError('tile %d: in sprite slot 0' % t)
    return PIC_TILES + 32 * t


def chunks_to_records(chunks, size=8000):
    """[(address, bytes)] -> records of chunks (cut where they must be),
    each ended by a chunk of length 0"""
    recs, cur = [], bytearray()
    for addr, data in chunks:
        data = bytes(data)
        while data:
            room = size - len(cur) - 5 - 5
            if room < 32:
                recs.append(bytes(cur + bytes(5)))
                cur = bytearray()
                continue
            k = data[:room]
            cur += bytes([addr & 255, addr >> 8 & 255, addr >> 16]) + len(k).to_bytes(2, 'little') + k
            addr += len(k)
            data = data[len(k):]
    if cur:
        recs.append(bytes(cur + bytes(5)))
    return recs


def pic_render(mp, tiles_by_index, pal):
    """a map (9600 bytes) -> rows of RGB as VERA shows it (pal: 256 words)"""
    rows = []
    cache = {}
    for y in range(H):
        r = []
        for x in range(W):
            e = 2 * ((y // 8) * CW + x // 8)
            lo, hi = mp[e], mp[e + 1]
            t = lo | (hi & 3) << 8
            k = (t, hi, x & 7, y & 7)
            c = cache.get(k)
            if c is None:
                xx, yy = (7 - (x & 7)) if hi & 4 else x & 7, (7 - (y & 7)) if hi & 8 else y & 7
                b = tiles_by_index[t][yy * 4 + xx // 2]
                v = b & 15 if xx & 1 else b >> 4
                c = cache[k] = rgb(pal[(hi >> 4) * 16 + v] if v else pal[0])
            r.append(c)
        rows.append(r)
    return rows


def pic_make(out, paths, row0=2, row1=13, ncol=15, maxt=480, dither=None, first=FIRSTCARD, paper=0,
             log=None):
    from PIL import Image
    if not (1 <= len(paths) <= 4):
        raise ValueError('1-4 pictures')
    if not (2 <= row0 <= row1 <= 13):
        raise ValueError('palette rows %d-%d: 2-13 only' % (row0, row1))
    if not (17 <= maxt <= PIC_MAX):
        raise ValueError('--max %d: 17-%d' % (maxt, PIC_MAX))
    if not (1 <= ncol <= 15):
        raise ValueError('--colours %d: 1-15' % ncol)
    raw = b''
    for p in paths:
        img = Image.open(p).convert('RGB')
        if img.size != (W, H):
            img = img.resize((W, H), Image.LANCZOS)
        raw += img.tobytes()
    if dither is None:
        dither = not few_colours(raw)
    exe = helper()
    with tempfile.TemporaryDirectory() as d:
        i = os.path.join(d, 'in.rgb')
        open(i, 'wb').write(raw)
        o = os.path.join(d, 'out')
        r = subprocess.run([exe, i, o, str(row0), str(row1 - row0 + 1), str(maxt), '1' if dither else '0',
                            str(first), str(ncol)], capture_output=True, text=True)
        if r.returncode:
            raise ValueError('wallcv: ' + (r.stderr or r.stdout).strip())
        tiles = open(o + '.tiles', 'rb').read()
        mp = bytearray(open(o + '.map', 'rb').read())
        pb = open(o + '.pal', 'rb').read()
    n = len(tiles) // 32
    # tile numbers as in VRAM: from 480 on past sprite slot 0
    vram = lambda t: t if t < PIC_SLOT0 else t + PIC_SLOT1 - PIC_SLOT0
    for e in range(0, len(mp), 2):
        t = vram(mp[e] | (mp[e + 1] & 3) << 8)
        mp[e] = t & 255
        mp[e + 1] = (mp[e + 1] & 0xFC) | t >> 8
    by_index = {vram(t): tiles[32 * t:32 * t + 32] for t in range(n)}
    pal = [0] * 256
    pal[0] = paper
    for k in range(len(pb) // 2):
        if k % 16:
            pal[row0 * 16 + k] = pb[2 * k] | pb[2 * k + 1] << 8
    open(out + '.map', 'wb').write(bytes(mp))
    open(out + '.pal', 'wb').write(pb)
    open(out + '.tiles', 'wb').write(tiles[16 * 32:])
    chunks = [(PIC_PALETTE + 32 * row0, pb)]
    recs = chunks_to_records(chunks)
    body = [(pic_addr(16), tiles[16 * 32:min(n, PIC_SLOT0) * 32])]
    if n > PIC_SLOT0:
        body.append((pic_addr(PIC_SLOT1), tiles[PIC_SLOT0 * 32:]))
    for y in range(first, CH):
        body.append((PIC_MAP + 256 * y, mp[y * CW * 2:(y + 1) * CW * 2]))
    recs += chunks_to_records(body)
    for f in os.listdir(os.path.dirname(os.path.abspath(out))):
        if f.startswith(os.path.basename(out) + '.vram.'):
            os.remove(os.path.join(os.path.dirname(os.path.abspath(out)), f))
    for k, rec in enumerate(recs):
        open('%s.vram.%d' % (out, k + 1), 'wb').write(rec)
    for s in range(len(paths)):
        rows = pic_render(mp[s * 9600:(s + 1) * 9600], by_index, pal)
        img = Image.new('RGB', (W, H))
        img.putdata([p for rr in rows for p in rr])
        img.save('%s-%d.png' % (out, s))
    res = r.stdout.strip().replace('RESULT ', '')
    line = 'mkwall --tiles: %d picture(s), %s (dither %s), %d records (%s bytes)' % (
        len(paths), res, 'on' if dither else 'off', len(recs), ', '.join(str(len(x)) for x in recs))
    if log:
        log(line)
    return line


def main():
    a = sys.argv[1:]
    if a and a[0] == '--tiles':
        try:
            a.pop(0)
            out = a.pop(0)
            kw = {}
            while a and a[0].startswith('--'):
                o = a.pop(0)
                if o == '--rows':
                    x, y = a.pop(0).split('-')
                    kw['row0'], kw['row1'] = int(x), int(y)
                elif o == '--colours':
                    kw['ncol'] = int(a.pop(0))
                elif o == '--max':
                    kw['maxt'] = int(a.pop(0))
                elif o == '--first-card':
                    kw['first'] = int(a.pop(0))
                elif o == '--paper':
                    kw['paper'] = int(a.pop(0).lstrip('$'), 16)
                elif o == '--dither':
                    kw['dither'] = True
                elif o == '--no-dither':
                    kw['dither'] = False
                else:
                    sys.exit(__doc__)
            if not a:
                sys.exit(__doc__)
            print(pic_make(out, a, **kw))
        except (ValueError, OSError, IndexError) as e:
            sys.exit('mkwall: %s' % e)
        return
    a = sys.argv[1:]
    out, name, level, stretch, dark, png, check, dither, old, v2 = None, None, 0.55, False, False, None, False, None, None, False
    try:
        while a and a[0].startswith('-') and a[0] not in ('--dusk', '--dusk-scene'):
            o = a.pop(0)
            if o == '-o' and a:
                out = a.pop(0)
            elif o == '--name' and a:
                name = a.pop(0)
            elif o == '--dark-level' and a:
                level = float(a.pop(0))
            elif o == '--stretch':
                stretch = True
            elif o == '--dark':
                dark = True
            elif o == '--png' and a:
                png = a.pop(0)
            elif o == '--check':
                check = True
            elif o == '--dither':
                dither = True
            elif o == '--no-dither':
                dither = False
            elif o == '--v2':
                v2 = True
            elif o == '--from' and a:
                old = a.pop(0)
            elif o == '--max' and a:
                global WALLMAX
                WALLMAX = int(a.pop(0))
                if not 17 <= WALLMAX <= MAXTILES:
                    sys.exit('mkwall: --max 17-480')
            else:
                sys.exit(__doc__)
        if len(a) != (0 if old else 1):
            sys.exit(__doc__)
        if png or check:
            data = read(a[0])
            if check:
                if data[4] >= 2:
                    print('\n'.join(check2(data)))
                else:
                    for v in range(data[5]):
                        pal, cols, bm = parts(data, v)
                        if any(c > 15 or c < 2 for c in cols):
                            raise ValueError('variant %d: a card colour outside 2-15' % v)
                        print('version 1, variant %d: entries 12-15 %s, %d cards in them, %d ink pixels' % (
                            v, ' '.join('$%03X' % pal[f] for f in V1_FREE), sum(c >= 12 for c in cols),
                            sum(bin(b).count('1') for b in bm)))
            if png:
                from PIL import Image
                rows = render(data, 1 if dark else 0)
                img = Image.new('RGB', (W, H))
                img.putdata([p for r in rows for p in r])
                img.save(png)
            return
        if old:
            data = read(old)
            px = [tuple(float(c) for c in p) for r in render(data, 0) for p in r]
            name = name or vpack.parse(open(old, 'rb').read())['name'].strip()
        elif a[0] == '--dusk' and not v2:       # (V175) drawn as tiles
            import wall_dusk
            cvt, msg = wall_dusk.document(name or 'Dusk')
            print('mkwall: ' + msg, file=sys.stderr)
            open(out or (name or 'Dusk') + '.cvt', 'wb').write(cvt)
            return
        elif a[0] in ('--dusk', '--dusk-scene'):
            px, name = dusk_pixels(), name or 'Dusk'
        else:
            px = picture_pixels(a[0], stretch)
            name = name or os.path.splitext(os.path.basename(a[0]))[0][:16]
        cvt = make(px, name, level, dither, log=lambda s: print(s, file=sys.stderr), v2=v2)
        out = out or name + '.cvt'
        open(out, 'wb').write(cvt)
    except (ValueError, OSError, vpack.PackError) as e:
        sys.exit('mkwall: %s' % e)


if __name__ == '__main__':
    main()
