#!/usr/bin/env python3
"""Gate gemini (DECISIONS V125): a screen of Veranda Gemini's picture viewer
as a PNG: tests/ftp_shot.py's picture of the snap (the bitmap over the
cards' colours; in tile mode the cards' colours are VERA's tiles) with the
picture's tiles laid in where the bitmap is clear: the tiles, their place
and palette row 2 from the test's dump of VRAM (tests/gemini_pics.c's
P<k>.DMP).

usage: pic_shot.py <screen.raw> <P<k>.raw> <out.png>
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ftp_shot  # noqa: E402

im = ftp_shot.image(sys.argv[1])
bits = open(sys.argv[1], 'rb').read()[:38400]
d = open(sys.argv[2], 'rb').read()
tw, th, tx, ty = d[9:13]
pal = []
for i in range(16):
    v = d[13 + 2 * i] | d[14 + 2 * i] << 8
    pal.append((((v >> 8) & 15) * 17, ((v >> 4) & 15) * 17, (v & 15) * 17))
tiles = d[45:]
px = im.load()
for y in range(th * 8):
    for x in range(tw * 8):
        sx, sy = tx * 8 + x, ty * 8 + y
        if bits[sy * 80 + (sx >> 3)] & (0x80 >> (sx & 7)):
            continue
        b = tiles[((y >> 3) * tw + (x >> 3)) * 32 + (y & 7) * 4 + ((x & 7) >> 1)]
        px[sx, sy] = pal[b >> 4 if not x & 1 else b & 15]
im.save(sys.argv[3])
