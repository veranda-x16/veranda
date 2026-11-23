#!/usr/bin/env python3
"""Gate Mono: Veranda's monospaced font, drawn here (MIT, like the rest).

usage: gatemono.py <out.png>        a specimen of both sizes (scaled 3x)

Used by tools/fontcvt.py testfonts (which writes Gate Mono.cvt).

Size 10: a cell 6 columns wide and 10 rows tall; the glyphs are drawn 5
wide (the sixth column is the gap between characters) on rows 1-9:
capitals and digits 7 rows (1-7), the baseline on row 7, the x-height
5 rows (3-7), descenders on rows 8-9; row 0 is the line's gap above.

Size 12: the same cell width, 12 rows: each size-10 glyph with one row
of its body (rows 3-6: the x-height and the capitals both grow by one)
and its first descender row (or row 9 when it has none) drawn twice: capitals 8 rows (1-8), the
baseline on row 8, the x-height 6 (3-8), descenders 9-11. The row drawn
twice is chosen per glyph (an empty row, else a row equal to its
neighbour, else one of vertical strokes only, nearest the middle) or given in TWICE below.
"""
import sys

W = 5            # a glyph's columns; the cell is W + 1

# each glyph: rows 1-9 of the 10-row cell (missing rows at the bottom
# are empty); '#' ink, '.' paper
SRC = {
    ' ': '',
    '!': '..#.. ..#.. ..#.. ..#.. ..#.. ..... ..#..',
    '"': '.#.#. .#.#. .#.#.',
    '#': '.#.#. .#.#. ##### .#.#. ##### .#.#. .#.#.',
    '$': '..#.. .#### #.#.. .###. ..#.# ####. ..#..',
    '%': '##... ##..# ...#. ..#.. .#... #..## ...##',
    '&': '.##.. #..#. #.#.. .#... #.#.# #..#. .##.#',
    "'": '..#.. ..#.. .#...',
    '(': '...#. ..#.. .#... .#... .#... .#... ..#.. ...#.',
    ')': '.#... ..#.. ...#. ...#. ...#. ...#. ..#.. .#...',
    '*': '..... ..#.. #.#.# .###. #.#.# ..#..',
    '+': '..... ..#.. ..#.. ##### ..#.. ..#..',
    ',': '..... ..... ..... ..... ..... ..##. ..##. ...#. ..#..',
    '-': '..... ..... ..... ##### ',
    '.': '..... ..... ..... ..... ..... ..##. ..##.',
    '/': '....# ...#. ...#. ..#.. .#... .#... #....',
    '0': '.###. #...# #..## #.#.# ##..# #...# .###.',
    '1': '..#.. .##.. ..#.. ..#.. ..#.. ..#.. .###.',
    '2': '.###. #...# ....# ...#. ..#.. .#... #####',
    '3': '##### ...#. ..#.. ...#. ....# #...# .###.',
    '4': '...#. ..##. .#.#. #..#. ##### ...#. ...#.',
    '5': '##### #.... ####. ....# ....# #...# .###.',
    '6': '..##. .#... #.... ####. #...# #...# .###.',
    '7': '##### ....# ...#. ..#.. .#... .#... .#...',
    '8': '.###. #...# #...# .###. #...# #...# .###.',
    '9': '.###. #...# #...# .#### ....# ...#. .##..',
    ':': '..... ..... ..##. ..##. ..... ..##. ..##.',
    ';': '..... ..... ..##. ..##. ..... ..##. ..##. ...#. ..#..',
    '<': '...#. ..#.. .#... #.... .#... ..#.. ...#.',
    '=': '..... ..... ##### ..... ##### ',
    '>': '.#... ..#.. ...#. ....# ...#. ..#.. .#...',
    '?': '.###. #...# ....# ...#. ..#.. ..... ..#..',
    '@': '.###. #...# #.### #.#.# #.### #.... .####',
    'A': '.###. #...# #...# ##### #...# #...# #...#',
    'B': '####. #...# #...# ####. #...# #...# ####.',
    'C': '.###. #...# #.... #.... #.... #...# .###.',
    'D': '###.. #..#. #...# #...# #...# #..#. ###..',
    'E': '##### #.... #.... ####. #.... #.... #####',
    'F': '##### #.... #.... ####. #.... #.... #....',
    'G': '.###. #...# #.... #.### #...# #...# .####',
    'H': '#...# #...# #...# ##### #...# #...# #...#',
    'I': '.###. ..#.. ..#.. ..#.. ..#.. ..#.. .###.',
    'J': '..### ...#. ...#. ...#. ...#. #..#. .##..',
    'K': '#...# #..#. #.#.. ##... #.#.. #..#. #...#',
    'L': '#.... #.... #.... #.... #.... #.... #####',
    'M': '#...# ##.## #.#.# #.#.# #...# #...# #...#',
    'N': '#...# #...# ##..# #.#.# #..## #...# #...#',
    'O': '.###. #...# #...# #...# #...# #...# .###.',
    'P': '####. #...# #...# ####. #.... #.... #....',
    'Q': '.###. #...# #...# #...# #.#.# #..#. .##.#',
    'R': '####. #...# #...# ####. #.#.. #..#. #...#',
    'S': '.#### #.... #.... .###. ....# ....# ####.',
    'T': '##### ..#.. ..#.. ..#.. ..#.. ..#.. ..#..',
    'U': '#...# #...# #...# #...# #...# #...# .###.',
    'V': '#...# #...# #...# #...# #...# .#.#. ..#..',
    'W': '#...# #...# #...# #.#.# #.#.# #.#.# .#.#.',
    'X': '#...# #...# .#.#. ..#.. .#.#. #...# #...#',
    'Y': '#...# #...# .#.#. ..#.. ..#.. ..#.. ..#..',
    'Z': '##### ....# ...#. ..#.. .#... #.... #####',
    '[': '.###. .#... .#... .#... .#... .#... .#... .###.',
    '\\': '#.... .#... .#... ..#.. ...#. ...#. ....#',
    ']': '.###. ...#. ...#. ...#. ...#. ...#. ...#. .###.',
    '^': '..#.. .#.#. #...#',
    '_': '..... ..... ..... ..... ..... ..... ..... #####',
    '`': '.#... ..#.. ...#.',
    'a': '..... ..... .###. ....# .#### #...# .####',
    'b': '#.... #.... #.##. ##..# #...# #...# ####.',
    'c': '..... ..... .###. #.... #.... #...# .###.',
    'd': '....# ....# .##.# #..## #...# #...# .####',
    'e': '..... ..... .###. #...# ##### #.... .###.',
    'f': '..##. .#..# .#... ####. .#... .#... .#...',
    'g': '..... ..... .#### #...# #...# #...# .#### ....# .###.',
    'h': '#.... #.... #.##. ##..# #...# #...# #...#',
    'i': '..#.. ..... .##.. ..#.. ..#.. ..#.. .###.',
    'j': '...#. ..... ..##. ...#. ...#. ...#. ...#. #..#. .##..',
    'k': '#.... #.... #..#. #.#.. ##... #.#.. #..#.',
    'l': '.##.. ..#.. ..#.. ..#.. ..#.. ..#.. .###.',
    'm': '..... ..... ##.#. #.#.# #.#.# #.#.# #.#.#',
    'n': '..... ..... #.##. ##..# #...# #...# #...#',
    'o': '..... ..... .###. #...# #...# #...# .###.',
    'p': '..... ..... ####. #...# #...# #...# ####. #.... #....',
    'q': '..... ..... .#### #...# #...# #...# .#### ....# ....#',
    'r': '..... ..... #.##. ##..# #.... #.... #....',
    's': '..... ..... .###. #.... .###. ....# ####.',
    't': '.#... .#... ####. .#... .#... .#..# ..##.',
    'u': '..... ..... #...# #...# #...# #..## .##.#',
    'v': '..... ..... #...# #...# #...# .#.#. ..#..',
    'w': '..... ..... #...# #...# #.#.# #.#.# .#.#.',
    'x': '..... ..... #...# .#.#. ..#.. .#.#. #...#',
    'y': '..... ..... #...# #...# #...# #...# .#### ....# .###.',
    'z': '..... ..... ##### ...#. ..#.. .#... #####',
    '{': '...#. ..#.. ..#.. .#... ..#.. ..#.. ..#.. ...#.',
    '|': '..#.. ..#.. ..#.. ..#.. ..#.. ..#.. ..#.. ..#..',
    '}': '.#... ..#.. ..#.. ...#. ..#.. ..#.. ..#.. .#...',
    '~': '..... ..... .#... #.#.# ...#.',
    '\x7f': '#.#.# .#.#. #.#.# .#.#. #.#.# .#.#. #.#.#',
}

# size 12: the size-10 row (3-6) drawn twice, where the rule's choice is
# not the best
TWICE = {}


def rows10(ch):
    """character ch at size 10: 10 rows of W 0/1"""
    r = SRC[ch].split()
    assert len(r) <= 9 and all(len(x) == W for x in r), repr(ch)
    r = ['.' * W] + r + ['.' * W] * (9 - len(r))
    return [[1 if c == '#' else 0 for c in x] for x in r]


def twice(ch, g):
    """the body row of size 10 drawn twice at size 12"""
    if ch in TWICE:
        return TWICE[ch]
    order = (5, 4, 6, 3)
    for r in order:                       # an empty row (a gap, a dot)
        if not any(g[r]):
            return r
    for r in order:                       # a row equal to its neighbour
        if any(g[r]) and (g[r] == g[r - 1] or g[r] == g[r + 1]):
            return r
    for r in order:                       # vertical strokes only
        if any(g[r]) and not any(a and b for a, b in zip(g[r], g[r][1:])):
            return r
    return 5


def rows12(ch):
    g = rows10(ch)
    d = twice(ch, g)
    e = 9 if not any(g[9]) else 8          # a descender's first row, or none
    out = g[:d + 1] + [g[d][:]] + g[d + 1:e + 1] + [g[e][:]] + g[e + 1:]
    assert len(out) == 12
    return out


def glyphs(size):
    """the 96 glyphs of characters 32-127, each with its gap column"""
    f = rows10 if size == 10 else rows12
    return [[row + [0] for row in f(chr(c))] for c in range(32, 128)]


_HI = {}


def hi10(ch):
    """a character of $A0-$FF at size 10 (tools/latin10.py): 10 rows of W"""
    if not _HI:
        import latin10
        st = latin10.mono_style(rows10)
        for c, g in zip(latin10.HIGH, st.high()):
            assert len(g[0]) == W, repr(c)
            _HI[c] = g
    return [r[:] for r in _HI[ch]]


def hi12(ch):
    """size 12 from size 10, as rows12 does"""
    g = hi10(ch)
    d = twice(ch, g)
    e = 9 if not any(g[9]) else 8
    return g[:d + 1] + [g[d][:]] + g[d + 1:e + 1] + [g[e][:]] + g[e + 1:]


def high(size):
    """the 96 glyphs of $A0-$FF (ISO-8859-16, DECISIONS V140), each with
    its gap column (an extended record's, V141)"""
    f = hi10 if size == 10 else hi12
    return [[row + [0] for row in f(bytes([c]).decode('iso8859_16'))] for c in range(0xA0, 0x100)]


BASELINE = {10: 7, 12: 8}


def specimen(out, records, scale=3):
    """records: [(label, parsed record)] -> a PNG: each size's 96 glyphs
    in three lines of 32 and a sample sentence"""
    import fontcvt
    from PIL import Image
    lines = []
    for label, f in records:
        lines.append((None, label))
        for k in range(3):
            lines.append((f, ''.join(chr(c) for c in range(32 + 32 * k, 64 + 32 * k))))
        if f.get('ext'):
            for k in range(3):
                lines.append((f, bytes(range(0xA0 + 32 * k, 0xC0 + 32 * k))))
            lines.append((f, 'Zażółć gęślą jaźń. ZAŻÓŁĆ GĘŚLĄ JAŹŃ.'))
        for s in ('The quick brown fox jumps over the lazy dog.',
                  'PACK MY BOX WITH FIVE DOZEN LIQUOR JUGS! 0123456789',
                  'if (x[i] != y) { return "a_b" + 1; } /* ~@#$%^&* */ |\\`\''):
            lines.append((f, s))
        lines.append((None, ''))
    rendered = []
    for f, s in lines:
        rendered.append(fontcvt.render(f or records[0][1], s) if s else [[]] * 6)
    w = max(len(r[0]) if r and r[0] else 0 for r in rendered) + 8
    h = sum(len(r) + 2 for r in rendered) + 8
    img = Image.new('1', (w, h), 1)
    px = img.load()
    y = 4
    for r in rendered:
        for yy, row in enumerate(r):
            for x, v in enumerate(row):
                if v:
                    px[x + 4, y + yy] = 0
        y += len(r) + 2
    img.resize((w * scale, h * scale)).save(out)


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    import fontcvt
    recs = [('Gate Mono %d' % s, fontcvt.parse_record(fontcvt.build_record(glyphs(s), BASELINE[s], high(s))))
            for s in (10, 12)]
    specimen(sys.argv[1], recs)


if __name__ == '__main__':
    sys.path.insert(0, __import__('os').path.dirname(__import__('os').path.abspath(__file__)))
    main()
