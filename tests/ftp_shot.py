#!/usr/bin/env python3
"""Gate ftp (DECISIONS V100): a screen written by Veranda FTP's test build
(tests/ftp_play.c, snap) as a PNG, as VERA shows it: the foreground's
1 bpp bitmap (ink: palette entry 1) over each card's paper colour (the
colour map; 0: palette entry 0).

usage: ftp_shot.py <screen.raw> <out.png>
       ftp_shot.py --text <screen.raw> <font.bin> ...   (not used)

The file: 480 rows of 80 bytes (bit 7 the left pixel, 1 ink), 60 rows of
80 card colours, 16 palette entries ($0RGB, low byte first).
"""
import sys

from PIL import Image


def load(path):
    d = open(path, 'rb').read()
    bits, cards, pal = d[:38400], d[38400:43200], d[43200:43232]
    rgb = []
    for i in range(16):
        gb, r = pal[2 * i], pal[2 * i + 1]
        rgb.append(((r & 15) * 17, (gb >> 4) * 17, (gb & 15) * 17))
    return bits, cards, rgb


def image(path):
    bits, cards, rgb = load(path)
    im = Image.new('RGB', (640, 480))
    px = im.load()
    for y in range(480):
        for x in range(640):
            ink = bits[y * 80 + (x >> 3)] & (0x80 >> (x & 7))
            px[x, y] = rgb[1] if ink else rgb[cards[(y >> 3) * 80 + (x >> 3)] & 15]
    return im


def cells(path, y, x0, n):
    """the bitmap's 8 x 8 cells at pixel row y, cards x0 .. x0 + n - 1, as bytes"""
    bits = open(path, 'rb').read()[:38400]
    return [bytes(bits[(y + r) * 80 + x] for r in range(8)) for x in range(x0, x0 + n)]


if __name__ == '__main__':
    image(sys.argv[1]).save(sys.argv[2])
