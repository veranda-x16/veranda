#!/usr/bin/env python3
"""Text on a screenshot in the ROM's 8 x 8 glyphs, as cs_draw draws it
(DECISIONS V143: Veranda Claude, Ask, Gemini, Gopher): CP437 for $20-$7F,
the ROM's ISO-8859-16 set (CHARLAE, found by its A ogonek) for $A0-$FF.

usage: check_glyphs.py <shot.RAW> <rom.bin> <what> <text> [<text> ...]

shot.RAW: a test's snap (the foreground's 480 rows of 80 bytes first).
Each text (UTF-8 here, made Veranda's set) must be on the screen as its
glyphs in consecutive cards at some pixel row (plain or reversed).
Prints ok/FAIL lines; exit 1 on a failure.
"""
import sys

SMILEY = bytes([0x7E, 0x81, 0xA5, 0x81, 0xBD, 0x99, 0x81, 0x7E])
AOGON = bytes([0x18, 0x3C, 0x24, 0x66, 0x7E, 0x66, 0x0C, 0x06])


def font(rom):
    b6 = open(rom, 'rb').read()[6 * 16384:7 * 16384]
    a = next(g for g in range(0, 16384, 0x800) if b6[g + 8:g + 16] == SMILEY)
    l = next(g for g in range(0, 16384, 0x100) if b6[g + 8:g + 16] == AOGON)

    def glyph(c):
        if c >= 0xA0:
            return b6[l + (c - 0xA0) * 8:l + (c - 0xA0) * 8 + 8]
        return b6[a + c * 8:a + c * 8 + 8]
    return glyph


def find(fg, glyph, text):
    want = [glyph(c) for c in text]
    n = len(want)
    hits = []
    for inv in (0, 0xFF):
        pat = [bytes(g[r] ^ inv for g in want) for r in range(8)]
        for y in range(480 - 8):
            row = fg[y * 80:(y + 1) * 80]
            x = row.find(pat[0])
            while x >= 0:
                if x + n <= 80 and all(fg[(y + r) * 80 + x:(y + r) * 80 + x + n] == pat[r] for r in range(1, 8)):
                    hits.append((x, y, inv))
                x = row.find(pat[0], x + 1)
    return hits


def main():
    raw, rom, what = sys.argv[1:4]
    fg = open(raw, 'rb').read()[:38400]
    glyph = font(rom)
    bad = 0
    for t in sys.argv[4:]:
        b = t.encode('iso8859_16')
        h = find(fg, glyph, b)
        if h:
            x, y, inv = h[0]
            print('ok    %s: "%s" on the screen in the ROM\'s glyphs (ISO-8859-16 above $9F), card %d, row %d%s'
                  % (what, t, x, y, ', reversed' if inv else ''))
        else:
            print('FAIL  %s: "%s" not on the screen as the ROM\'s glyphs' % (what, t))
            bad = 1
    sys.exit(bad)


if __name__ == '__main__':
    main()
