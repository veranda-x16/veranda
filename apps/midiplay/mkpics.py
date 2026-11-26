#!/usr/bin/env python3
"""MIDI Player's pictures (apps/midiplay, DECISIONS V206) -> pics.h, digits.h.

usage: mkpics.py [folder]       (default: this file's folder)

pics.h    the toolbar's signs (ui.c, main RAM: the kernel reads them):
          raw rows for WBitmapUp (height bit 15), 2 bytes a row, 11 rows,
          bit 7 of the first byte the left pixel
digits.h  the display's big digits (now.c, overlay 6): the Calculator's
          (apps/calc/mkglyphs.py, 20 rows, 12 pixels across) and a colon
          of its own; a row is a 16-bit word, its left pixel the top bit
notes.h   the voices' note names' small letters (vis.c, overlay 4): C D E
          F G A B, a sharp, the digits and a minus, 7 rows (the sharp 5,
          raised), a row a byte, its left pixel the top bit: a note's name
          is put up as one raw WBitmapUp (the kernel's text takes some
          20,000 cycles for three letters, this some 2,000)

The signs are drawn here as pictures ('#' ink, '.' paper; original
designs). MIT licence (see LICENSE).
"""
import importlib.util
import os
import sys

H = 11
PICS = [
    ('PIC_PREV', """
.##.....#.....#.
.##....##....##.
.##...###...###.
.##..####..####.
.##.#####.#####.
.##############.
.##.#####.#####.
.##..####..####.
.##...###...###.
.##....##....##.
.##.....#.....#."""),
    ('PIC_PLAY', """
....##..........
....####........
....######......
....########....
....##########..
....###########.
....##########..
....########....
....######......
....####........
....##.........."""),
    ('PIC_PAUSE', """
....###..###....
....###..###....
....###..###....
....###..###....
....###..###....
....###..###....
....###..###....
....###..###....
....###..###....
....###..###....
....###..###...."""),
    ('PIC_STOP', """
................
...##########...
...##########...
...##########...
...##########...
...##########...
...##########...
...##########...
...##########...
...##########...
................"""),
    ('PIC_NEXT', """
.#.....#.....##.
.##....##....##.
.###...###...##.
.####..####..##.
.#####.#####.##.
.##############.
.#####.#####.##.
.####..####..##.
.###...###...##.
.##....##....##.
.#.....#.....##."""),
    ('PIC_SPEAKER', """
.....#..........
....##.....#....
...###..#...#...
#####.#..#...#..
#.....#...#..#..
#.....#...#..#..
#.....#...#..#..
#####.#..#...#..
...###..#...#...
....##.....#....
.....#.........."""),
    ('PIC_MUTE', """
.....#..........
....##..........
...###..........
#####.#.#...#...
#.....#..#.#....
#.....#...#.....
#.....#..#.#....
#####.#.#...#...
...###..........
....##..........
.....#.........."""),
    ('PIC_ONWARD', """
................
######....#.....
..........##....
######....###...
..........####..
######....#####.
..........####..
######....###...
..........##....
######....#.....
................"""),
    ('PIC_REPEAT', """
.....#..........
.....##.........
.##########.....
.#...##....#....
.#...#......#...
.#..........#...
.#...#......#...
..#....##...#...
...##########...
.......##.......
........#......."""),
]

NOTE_ORDER = 'CDEFGAB#0123456789-'
NOTE = {
    'C': ['.###.', '#...#', '#....', '#....', '#....', '#...#', '.###.'],
    'D': ['####.', '#...#', '#...#', '#...#', '#...#', '#...#', '####.'],
    'E': ['#####', '#....', '#....', '####.', '#....', '#....', '#####'],
    'F': ['#####', '#....', '#....', '####.', '#....', '#....', '#....'],
    'G': ['.###.', '#...#', '#....', '#.###', '#...#', '#...#', '.###.'],
    'A': ['.###.', '#...#', '#...#', '#####', '#...#', '#...#', '#...#'],
    'B': ['####.', '#...#', '#...#', '####.', '#...#', '#...#', '####.'],
    '#': ['.#.#', '####', '.#.#', '####', '.#.#', '....', '....'],
    '0': ['.###.', '#...#', '#..##', '#.#.#', '##..#', '#...#', '.###.'],
    '1': ['..#..', '.##..', '..#..', '..#..', '..#..', '..#..', '.###.'],
    '2': ['.###.', '#...#', '....#', '...#.', '..#..', '.#...', '#####'],
    '3': ['####.', '....#', '....#', '.###.', '....#', '....#', '####.'],
    '4': ['...#.', '..##.', '.#.#.', '#..#.', '#####', '...#.', '...#.'],
    '5': ['#####', '#....', '####.', '....#', '....#', '#...#', '.###.'],
    '6': ['.###.', '#....', '#....', '####.', '#...#', '#...#', '.###.'],
    '7': ['#####', '....#', '...#.', '..#..', '.#...', '.#...', '.#...'],
    '8': ['.###.', '#...#', '#...#', '.###.', '#...#', '#...#', '.###.'],
    '9': ['.###.', '#...#', '#...#', '.####', '....#', '....#', '.###.'],
    '-': ['.....', '.....', '.....', '.###.', '.....', '.....', '.....'],
}

COLON = """
......
......
......
......
......
..##..
..##..
..##..
......
......
......
......
......
......
..##..
..##..
..##..
......
......
......"""


def rows(pic, width=16):
    r = pic.strip('\n').split('\n')
    assert all(len(l) == len(r[0]) for l in r), pic
    assert len(r[0]) <= width
    return len(r[0]), r


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    out = sys.argv[1] if len(sys.argv) > 1 else here
    spec = importlib.util.spec_from_file_location('calcglyphs', os.path.join(here, '..', 'calc', 'mkglyphs.py'))
    calc = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(calc)

    L = ['/* MIDI Player\'s toolbar signs: written by apps/midiplay/mkpics.py (do not edit);',
         '   raw rows for WBitmapUp (2 bytes, %d rows) */' % H,
         '#define PIC_H %d' % H]
    for i, (name, pic) in enumerate(PICS):
        L.append('#define %s %d' % (name, i))
    L.append('static const unsigned char pics[%d][%d] = {' % (len(PICS), 2 * H))
    for name, pic in PICS:
        w, r = rows(pic)
        assert len(r) == H, name
        b = []
        for l in r:
            v = sum(1 << (15 - i) for i, ch in enumerate(l) if ch == '#')
            b += [v >> 8, v & 255]
        L.append('    { %s },  /* %s */' % (', '.join('0x%02X' % x for x in b), name))
    L.append('};')
    open(os.path.join(out, 'pics.h'), 'w').write('\n'.join(L) + '\n')

    D = ['/* MIDI Player\'s big digits: written by apps/midiplay/mkpics.py (do not edit):',
         '   the Calculator\'s 0-9 (apps/calc/mkglyphs.py) and a colon */',
         '#define BIG_H 20',
         '#define BIG_COLON 10',
         'static const unsigned char big_w[11] = { %s };' % ', '.join(
             [str(calc.rows(calc.BIG[c])[0]) for c in '0123456789'] + [str(rows(COLON)[0])]),
         'static const unsigned int big_rows[11][BIG_H] = {']
    for c in '0123456789':
        w, r = calc.rows(calc.BIG[c])
        assert len(r) == 20
        D.append('    { %s },  /* %s */' % (', '.join('0x%04X' % v for v in r), c))
    w, r = rows(COLON)
    D.append('    { %s },  /* : */' % ', '.join('0x%04X' % sum(1 << (15 - i) for i, ch in enumerate(l) if ch == '#')
                                              for l in r))
    D.append('};')
    open(os.path.join(out, 'digits.h'), 'w').write('\n'.join(D) + '\n')

    N = ['/* MIDI Player\'s note names\' letters: written by apps/midiplay/mkpics.py (do not edit) */',
         '#define NOTE_CHARS "%s"' % NOTE_ORDER,
         'static const unsigned char note_w[%d] = { %s };' % (len(NOTE_ORDER), ', '.join(
             str(len(NOTE[c][0])) for c in NOTE_ORDER)),
         'static const unsigned char note_rows[%d][7] = {' % len(NOTE_ORDER)]
    for c in NOTE_ORDER:
        r = NOTE[c]
        assert len(r) == 7 and all(len(l) == len(r[0]) for l in r), c
        N.append('    { %s },  /* %s */' % (', '.join('0x%02X' % sum(1 << (7 - i) for i, ch in enumerate(l) if ch == '#')
                                                    for l in r), c))
    N.append('};')
    open(os.path.join(out, 'notes.h'), 'w').write('\n'.join(N) + '\n')


if __name__ == '__main__':
    main()
