"""Wallpaper v2 proposal (not for main until approved): a wallpaper drawn
as tiles from the start, for tools/wall_*.py.

A drawing is a 640 x 480 picture of palette indices 1-10 (0 is the paper:
never used) and a palette row a card (0 .. rows - 1, the file's rows from
2 on), each row 10 colours, light and dark (designed, not darkened: the
same tiles and map). Every card is a tile of the drawing exactly: a card
of one index is solid tile c (tiles 0-15, which cost nothing), the others
are kept once with their H, V and HV flips; so the number of tiles is the
drawing's own (no merging, no dither) and the screen is the drawing pixel
for pixel. The file is tools/mkwall.py's version 3 (docs/APPFORMAT.md,
"Wallpapers"), its header giving the tiles and rows used.

MIT licence (LICENSE)."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mkwall  # noqa: E402
import vpack  # noqa: E402

W, H, CW, CH = 640, 480, 80, 60
FIRST = mkwall.FIRSTCARD                    # card rows 0-1: the menu bar (tile 0)


def c12(h):
    """'8BE' -> $08BE"""
    return int(h, 16)


class Drawing:
    def __init__(self, rows=1):
        self.px = bytearray([1]) * (W * H)
        self.row = bytearray(CW * CH)
        self.nrows = rows

    def put(self, x, y, c):
        if 0 <= x < W and 0 <= y < H:
            self.px[y * W + x] = c

    def get(self, x, y):
        return self.px[y * W + x]

    def fill(self, f):
        """f(x, y) -> index, for every pixel"""
        for y in range(H):
            o = y * W
            for x in range(W):
                self.px[o + x] = f(x, y)

    def card_row(self, cx, cy, r):
        self.row[cy * CW + cx] = r


def _flips(t):
    """a tile (64 indices) -> its H, V and HV flips"""
    rows = [t[i * 8:i * 8 + 8] for i in range(8)]
    h = bytes(b for r in rows for b in reversed(r))
    v = bytes(b for r in reversed(rows) for b in r)
    hv = bytes(b for r in reversed(rows) for b in reversed(r))
    return ((t, 0), (h, 4), (v, 8), (hv, 12))


def build(d, light, dark):
    """-> (data of the wallpaper, tiles in all with the 16 solid ones, rows)
    light, dark: d.nrows rows of 10 $0RGB colours each"""
    assert len(light) == len(dark) == d.nrows and all(len(r) == 10 for r in light + dark)
    tiles = [bytes([c << 4 | c]) * 32 for c in range(16)]
    known = {}                              # 64 indices -> (tile, flip bits)
    mp = bytearray(CW * CH * 2)
    for cy in range(FIRST, CH):
        for cx in range(CW):
            t = bytes(d.px[(cy * 8 + y) * W + cx * 8 + x] for y in range(8) for x in range(8))
            if not all(1 <= b <= 10 for b in t):
                raise ValueError('card %d, %d: an index outside 1-10' % (cx, cy))
            if len(set(t)) == 1:
                n, fl = t[0], 0
            elif t in known:
                n, fl = known[t]
            else:
                n = len(tiles)
                tiles.append(bytes(t[i] << 4 | t[i + 1] for i in range(0, 64, 2)))
                for f, bits in _flips(t):
                    known.setdefault(f, (n, bits))
                fl = 0
            r = mkwall.ROW0 + d.row[cy * CW + cx]
            e = 2 * (cy * CW + cx)
            mp[e] = n & 255
            mp[e + 1] = r << 4 | fl | n >> 8
    if len(tiles) > mkwall.WALLMAX:
        raise ValueError('%d tiles: more than %d' % (len(tiles), mkwall.WALLMAX))
    pal = lambda rows: b''.join(c.to_bytes(2, 'little') for r in rows for c in [0] + r + [0] * 5)
    data = (mkwall.MAGIC + bytes([mkwall.VERSION, 2, CW, CH]) + len(tiles).to_bytes(2, 'little')
            + bytes([mkwall.ROW0, d.nrows]) + bytes(4) + pal(light) + pal(dark) + bytes(mp) + b''.join(tiles))
    return data, len(tiles), d.nrows


def line(name, n, rows, size):
    return '%s: %d tiles (%d drawn, 16 solid), %d palette row%s, %d bytes of data' % (
        name, n, n - 16, rows, 's' if rows > 1 else '', size)


def document(d, light, dark, name):
    """-> (the GEOS document, its data, the light picture as VERA shows
    it, tiles, rows)"""
    data, n, rows = build(d, light, dark)
    view = mkwall.render(data, 0)
    flat = [tuple(float(v) for v in p) for r in view for p in r]
    cvt = vpack.pack_doc(name, 'Wallpaper', data, icon=mkwall.icon(flat), version='3.0', author='Veranda',
                         description='A desktop picture for the shell (Preferences, Desktop).')
    return cvt, data, view, n, rows


def write(d, light, dark, name, out, png=None):
    """the wallpaper file (and its light and dark pictures as VERA shows
    them: png-light.png, png-dark.png); prints a line"""
    cvt, data, view, n, rows = document(d, light, dark, name)
    open(out, 'wb').write(cvt)
    if png:
        from PIL import Image
        for v, s in ((0, 'light'), (1, 'dark')):
            rows_ = view if v == 0 else mkwall.render(data, 1)
            img = Image.new('RGB', (W, H))
            img.putdata([p for r in rows_ for p in r])
            img.save('%s-%s.png' % (png, s))
    print(line(name, n, rows, len(data)))
    return n, rows
