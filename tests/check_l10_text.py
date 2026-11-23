#!/usr/bin/env python3
"""(DECISIONS V143) text in Veranda's set (ISO-8859-16) on a screen dump,
drawn in the X16 ROM's 8 x 8 glyphs: ASCII from the ROM's ISO set (or
CP437 with --cp437), $A0-$FF from its ISO-8859-16 upper half (ROM bank 6,
found by its A ogonek), as Veranda Edit, Note Pad, Chat and FTP draw it.

usage: check_l10_text.py [--raw] <dump.bin> <rom.bin> [--cp437] <text> ...
       (--raw: a test build's screen, 480 rows of 80 bytes first)

Each text (UTF-8 on the command line) must appear somewhere on the 1 bpp
screen as whole cards in a row (any pixel row, any card column), in ink
on paper or reversed; prints ok/FAIL lines.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'tools'))
from vram2png import section, VRAM, COMPOSER, PALETTE  # noqa: E402

SIG0 = bytes([0xC3, 0x99, 0x91, 0x91, 0x91, 0x9F, 0xC1, 0xFF])
SIGA = bytes([0x18, 0x3C, 0x24, 0x66, 0x7E, 0x66, 0x66, 0x00])
SIGL10 = bytes([0x18, 0x3C, 0x24, 0x66, 0x7E, 0x66, 0x0C, 0x06])
SMILEY = bytes([0x7E, 0x81, 0xA5, 0x81, 0xBD, 0x99, 0x81, 0x7E])


def rom_glyphs(rom, cp437=False):
    b6 = open(rom, 'rb').read()[6 * 16384:7 * 16384]
    base = None
    for a in range(0, 16384, 0x800):
        if cp437 and b6[a + 8:a + 16] == SMILEY:
            base = a
            break
        if not cp437 and b6[a:a + 8] == SIG0 and b6[a + 0x41 * 8:a + 0x42 * 8] == SIGA:
            base = a
            break
    i = next(i for i in range(8, 16384, 8) if b6[i:i + 8] == SIGL10)
    low, hi = b6[base:base + 1024], b6[i - 8:i - 8 + 768]
    return lambda c: low[c * 8:c * 8 + 8] if c < 0x80 else hi[(c - 0xA0) * 8:(c - 0xA0) * 8 + 8]


def screen(dump):
    v = section(dump)
    layers = [v[VRAM + COMPOSER + PALETTE + 7 * i:][:7] for i in range(2)]
    video = v[VRAM]
    on = [bool(video & 0x10), bool(video & 0x20)]
    b = [i for i in range(2) if on[i] and layers[i][0] & 0x04][-1]
    base = (layers[b][2] >> 2) << 11
    return v[base:base + 80 * 480]


def find(scr, rows):
    n = len(rows[0])
    for inv in (0, 0xFF):
        want = [bytes(x ^ inv for x in r) for r in rows]
        for y in range(0, 480 - 7):
            line = scr[y * 80:(y + 1) * 80]
            for x in range(0, 81 - n):
                if line[x:x + n] == want[0] and all(scr[(y + k) * 80 + x:(y + k) * 80 + x + n] == want[k]
                                                    for k in range(1, 8)):
                    return x, y
    return None


def main():
    a = sys.argv[1:]
    cp = '--cp437' in a
    raw = '--raw' in a
    a = [x for x in a if x not in ('--cp437', '--raw')]
    dump, rom, texts = a[0], a[1], a[2:]
    g = rom_glyphs(rom, cp)
    scr = open(dump, 'rb').read()[:38400] if raw else screen(dump)
    bad = 0
    for t in texts:
        bts = t.encode('iso8859_16')
        rows = [bytes(g(c)[k] for c in bts) for k in range(8)]
        at = find(scr, rows)
        if at:
            print('ok    "%s" on the screen in the ROM\'s glyphs (card %d, row %d)' % (t, at[0], at[1]))
        else:
            print('FAIL  "%s" not on the screen in the ROM\'s glyphs' % t)
            bad = 1
    sys.exit(bad)


if __name__ == '__main__':
    main()
