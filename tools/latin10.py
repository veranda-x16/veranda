#!/usr/bin/env python3
"""The glyphs of ISO-8859-16's $A0-$FF for Veranda's fonts (DECISIONS V140,
V141), drawn here (MIT, like the rest).

Letters with marks are composed: the font's own base letter (capitals
shortened where the font has no room above them) and a mark drawn for
that font's size; the rest (Ł ł Đ đ, € § © ¶ « » ° Æ æ Œ œ ß ...) are
drawn by hand per font below. Used by tools/mkfont.py (the system font's
and the UI font's styles: Gate Sans 9 and 12) and tools/gatemono.py
(Gate Mono 10, and 12 made from it).

A glyph is a list of rows, each a list of 0/1, without its gap column
(the caller adds it).
"""
import unicodedata

CODEC = 'iso8859_16'
HIGH = [bytes([c]).decode(CODEC) for c in range(0xA0, 0x100)]

MARK = {'́': 'acute', '̀': 'grave', '̂': 'circ', '̆': 'breve',
        '̈': 'diaer', '̌': 'caron', '̇': 'dot', '̋': 'dacute',
        '̨': 'ogonek', '̧': 'cedilla', '̦': 'comma'}

# marks above: two-row and one-row forms
ABOVE2 = {
    'acute': ['.#', '#.'],
    'grave': ['#.', '.#'],
    'circ': ['.#.', '#.#'],
    'breve': ['#..#', '.##.'],
    'diaer': ['#.#'],
    'caron': ['#.#', '.#.'],
    'dot': ['#'],
    'dacute': ['.#.#', '#.#.'],
}
ABOVE1 = {
    'acute': ['.##'],
    'grave': ['##.'],
    'circ': ['###'],
    'breve': ['#..#'],
    'diaer': ['#.#'],
    'caron': ['#.#'],
    'dot': ['#'],
    'dacute': ['##.##'],
}


def parse(s, h):
    """rows separated by spaces (top first), padded to h -> 0/1 rows"""
    r = s.split()
    w = len(r[0])
    assert all(len(x) == w for x in r), s
    assert len(r) <= h, s
    r += ['.' * w] * (h - len(r))
    return [[1 if c == '#' else 0 for c in x] for x in r]


def width(g):
    return len(g[0]) if g else 0


def ink_cols(g, rows=None):
    cols = [x for x in range(width(g)) for y in (rows if rows is not None else range(len(g))) if g[y][x]]
    return (min(cols), max(cols)) if cols else (0, width(g) - 1)


def shrink(rows, n):
    """rows with n rows taken out of the middle: one equal to a
    neighbour first, else one of vertical strokes only, else the middle"""
    rows = [r[:] for r in rows]
    for _ in range(n):
        k = len(rows)
        mid = (k - 1) / 2
        order = sorted(range(1, k - 1), key=lambda i: abs(i - mid))
        pick = None
        for i in order:
            if rows[i] == rows[i - 1] or rows[i] == rows[i + 1]:
                pick = i
                break
        if pick is None:
            for i in order:
                r = rows[i]
                if not any(a and b for a, b in zip(r, r[1:])):
                    pick = i
                    break
        if pick is None:
            pick = order[0]
        del rows[pick]
    return rows


def place(g, mark, top, centre):
    """mark (strings) ORed into g with its first row at top, centred on
    column centre (a float); g widened when it does not fit"""
    m = [[1 if c == '#' else 0 for c in x] for x in mark]
    mw = len(m[0])
    x0 = int(round(centre - (mw - 1) / 2.0))
    if x0 < 0:
        g = [[0] * -x0 + r for r in g]
        x0 = 0
    if x0 + mw > width(g):
        g = [r + [0] * (x0 + mw - width(g)) for r in g]
    for dy, row in enumerate(m):
        for dx, v in enumerate(row):
            if v:
                g[top + dy][x0 + dx] = 1
    return g


class Style:
    """a font's measures: H rows, the baseline, the capitals' and the
    x-height's top rows, how capitals with a mark above are made, and the
    font's own glyphs (get(ch) -> rows without the gap) and hand-drawn ones"""

    def __init__(self, get, h, base, captop, xtop, lc_mark_top, lc_marks, cap_body, cap_marks, extra,
                 mono=None, caps=None):
        self.caps = caps or {}
        self.get, self.h, self.base, self.captop, self.xtop = get, h, base, captop, xtop
        self.lc_mark_top, self.lc_marks = lc_mark_top, lc_marks
        self.cap_body, self.cap_marks = cap_body, cap_marks   # capitals: rows (top) .. baseline
        self.extra = extra
        self.mono = mono

    def compose(self, ch):
        if ch in self.extra:
            return parse(self.extra[ch], self.h)
        d = unicodedata.decomposition(ch).split()
        if not d or d[0].startswith('<'):
            raise KeyError('no glyph for %r (U+%04X)' % (ch, ord(ch)))
        base, marks = chr(int(d[0], 16)), [MARK[chr(int(x, 16))] for x in d[1:]]
        mk = marks[0]
        g = [r[:] for r in self.get(base)]
        if mk in ('ogonek', 'cedilla', 'comma'):
            return self.below(g, mk, base)
        if base.isupper():
            body = g[self.captop:self.base + 1]
            n = len(body) - (self.base + 1 - self.cap_body)
            if base in self.caps:
                body = parse(self.caps[base], self.base + 1 - self.cap_body)
            elif n > 0:
                body = shrink(body, n)
            g = [[0] * width(g) for _ in range(self.cap_body)] + body + g[self.base + 1:]
            assert len(g) == self.h
            mark = self.cap_marks[mk]
            top = 0
            lo, hi = ink_cols(g, range(self.cap_body, self.base + 1))
        else:
            if base in 'ij':                    # dotless first
                for y in range(self.xtop):
                    g[y] = [0] * width(g)
            mark = self.lc_marks[mk]
            top = self.lc_mark_top
            if len(mark) == 1 and self.xtop - self.lc_mark_top >= 3:
                top += 1                        # (one row: the lower, a gap below it)
            lo, hi = ink_cols(g, range(self.xtop, self.base + 1))
        centre = (lo + hi) / 2.0
        if mk == 'acute':
            centre += 0.5
        elif mk == 'grave':
            centre -= 0.5
        return place(g, mark, top, centre)

    def below(self, g, mk, base):
        b = self.base
        lo, hi = ink_cols(g, [b])
        dh = self.h - b - 1                     # descender rows
        if mk == 'ogonek':
            # a tail from the bottom right, down and to the left, its
            # end turned right
            r = hi
            if dh >= 3:
                pts = [(b + 1, r - 1), (b + 2, r - 2), (b + 3, r - 1), (b + 3, r)]
            else:
                pts = [(b + 1, r - 1), (b + 2, r - 1), (b + 2, r)]
        else:                                   # a cedilla, a comma below
            c = (lo + hi) // 2
            if mk == 'cedilla':
                pts = [(b + 1, c), (b + 2, c + 1)] if dh < 3 else [(b + 1, c), (b + 2, c + 1), (b + 3, c)]
            else:
                pts = [(b + 2, c), (b + 3, c - 1)] if dh >= 3 else [(b + 1, c), (b + 2, c - 1)]
        for y, x in pts:
            if y < self.h and 0 <= x:
                while x >= width(g):
                    g = [r + [0] for r in g]
                g[y][x] = 1
        return g

    def high(self):
        """the 96 glyphs of $A0-$FF (rows without the gap column)"""
        out = []
        for ch in HIGH:
            g = self.compose(ch)
            assert len(g) == self.h, ch
            out.append(g)
        return out


# ---------------------------------------------------------------------
# hand-drawn: the system font's style (9 rows, capitals 0-6, the
# baseline on row 6, the x-height 2-6, descenders 7-8)
SYS = {
    '\xa0': '... ... ...',
    '\xad': '.... .... .... .... ####',
    'Ł': '.#.... .#.... .#.#.. .##... ##.... .#.... .#####',
    'ł': '.#.. .#.. .#.# .##. ##.. .#.. .#..',
    'Đ': '.####. .#...# .#...# ###..# .#...# .#...# .####.',
    'đ': '...#. ..### ...#. .###. #..#. #..#. .###.',
    '€': '..###. .#.... ####.. .#.... ####.. .#.... ..###.',
    '„': '..... ..... ..... ..... ..... .#.#. .#.#. #.#..',
    '”': '.#.#. .#.#. #.#..',
    '§': '.###. #.... .##.. #..#. .##.. ...#. ###..',
    '©': '.####. #....# #.##.# #.#..# #.##.# #....# .####.',
    '«': '...... ...... ..#..# .#..#. #..#.. .#..#. ..#..#',
    '»': '...... ...... #..#.. .#..#. ..#..# .#..#. #..#..',
    '°': '.#. #.# .#.',
    '±': '..... ..#.. ..#.. ##### ..#.. ..#.. #####',
    '¶': '.#### ###.# ###.# .##.# ..#.# ..#.# ..#.#',
    '·': '. . . #',
    'Æ': '..#####. .#.#.... #..#.... #####... #..#.... #..#.... #..####.',
    'æ': '....... ....... .##.##. ...#..# .###### #..#... .##.###',
    'Œ': '.######. #..#.... #..#.... #..####. #..#.... #..#.... .######.',
    'œ': '....... ....... .##.##. #..#..# #..#### #..#... .##.###',
    'ß': '.##.. #..#. #..#. #.#.. #..#. #..#. #.##.',
}

# capitals shortened by hand (a mark above them), the rule's choice not
# the best: rows from the shortened top to the baseline
SYS_CAPS = {
    'Z': '##### ...#. ..#.. .#... #.... #####',
}

# the UI font's style (12 rows, capitals 0-8, the baseline on row 8, the
# x-height 3-8, descenders 9-11)
UI = {
    '\xa0': '.... .... ....',
    '\xad': '.... .... .... .... ####',
    'Ł': '.#..... .#..... .#..... .#.#... .##.... ##..... .#..... .#..... .#####.',
    'ł': '.#.. .#.. .#.. .#.# .##. ##.. .#.. .#.. .#..',
    'Đ': '.####.. .#...#. .#....# .#....# ####..# .#....# .#....# .#...#. .####..',
    'đ': '....#. ..#### ....#. .####. #...#. #...#. #...#. #...#. .####.',
    '€': '...####. ..#....# .#...... ######.. .#...... #####... .#...... ..#....# ...####.',
    '„': '..... ..... ..... ..... ..... ..... ..... .#.#. .#.#. #.#..',
    '”': '.#.# .#.# #.#.',
    '§': '.###. #...# #.... .###. #...# .###. ....# #...# .###.',
    '©': '..####.. .#....#. #..##..# #.#....# #.#....# #..##..# .#....#. ..####..',
    '«': '...... ...... ...... ..#..# .#..#. #..#.. .#..#. ..#..#',
    '»': '...... ...... ...... #..#.. .#..#. ..#..# .#..#. #..#..',
    '°': '.##. #..# #..# .##.',
    '±': '..... ..... ..#.. ..#.. ##### ..#.. ..#.. ..... #####',
    '¶': '.##### ####.# ####.# ####.# .###.# ...#.# ...#.# ...#.# ...#.#',
    '·': '. . . . #',
    'Æ': '...######. ..#..#.... ..#..#.... .#...#.... .######... .#...#.... #....#.... #....#.... #....#####',
    'æ': '.......... .......... .......... .###..###. ....##...# .#####.### #...#####. #...##.... .###..####',
    'Œ': '..#######. .#...#.... #....#.... #....#.... #....####. #....#.... #....#.... .#...#.... ..#######.',
    'œ': '.......... .......... .......... .###..###. #...##...# #...#####. #...##.... #...##...# .###..###.',
    'ß': '.###. #...# #...# #..#. #.#.. #..#. #...# #...# #.##.',
}

UI_CAPS = {
    'Z': '###### ....#. ...#.. ..#... .#.... #..... ######',
}

# Gate Mono 10's style (5 columns, row 0 the line's gap, capitals 1-7,
# the baseline on row 7, the x-height 3-7, descenders 8-9)
MONO = {
    '\xa0': '..... ..... .....',
    '\xad': '..... ..... ..... ..... .###.',
    'Ł': '..... #.... #.... #.#.. ##... #.... #.... #####',
    'ł': '..... .##.. ..#.. ..#.# ..##. .##.. ..#.. .###.',
    'Đ': '..... ###.. #..#. #...# ###.# #...# #..#. ###..',
    'đ': '..... ...#. ..### .##.# #..## #...# #...# .####',
    '€': '..... ..### .#... ####. .#... ####. .#... ..###',
    '„': '..... ..... ..... ..... ..... ..... ##.## ##.## .#..#',
    '”': '..... ##.## ##.## .#..#',
    '§': '..... .###. #.... .###. #...# .###. ....# .###.',
    '©': '..... .###. #...# #.#.# ##..# #.#.# #...# .###.',
    '«': '..... ..... ..... ..#.# .#.#. #.#.. .#.#. ..#.#',
    '»': '..... ..... ..... #.#.. .#.#. ..#.# .#.#. #.#..',
    '°': '..... .##.. #..#. #..#. .##..',
    '±': '..... ..... ..#.. ..#.. ##### ..#.. ..#.. #####',
    '¶': '..... .#### ###.# ###.# .##.# ..#.# ..#.# ..#.#',
    '·': '..... ..... ..... ..... ..##. ..##.',
    'Æ': '..... .#### #.#.. #.#.. ##### #.#.. #.#.. #.###',
    'æ': '..... ..... ..... ##.#. ..#.# ##### #.#.. .#.##',
    'Œ': '..... .#### #.#.. #.#.. #.### #.#.. #.#.. .####',
    'œ': '..... ..... ..... .#.#. #.#.# #.### #.#.. .#.##',
    'ß': '..... .##.. #..#. #..#. #.##. #...# #...# #.##.',
}


def sys_style(G):
    """the system font's (tools/mkfont.py G: rows with their gap column)"""
    get = lambda ch: [[1 if c == '#' else 0 for c in r[:-1]] for r in G[ch]]   # noqa: E731
    return Style(get, 9, 6, 0, 2, 0, ABOVE2, 1, ABOVE1, SYS, caps=SYS_CAPS)


def ui_style(U):
    """the UI font's (tools/mkfont.py U)"""
    get = lambda ch: [[1 if c == '#' else 0 for c in r[:-1]] for r in U[ch]]   # noqa: E731
    return Style(get, 12, 8, 0, 3, 0, ABOVE2, 2, ABOVE2, UI, caps=UI_CAPS)


def mono_style(rows10):
    """Gate Mono 10's (tools/gatemono.py rows10)"""
    return Style(rows10, 10, 7, 1, 3, 1, ABOVE2, 1, ABOVE1, MONO, mono=5)
