#!/usr/bin/env python3
"""The kernel's UI font (tools/mkfont.py's U, DECISIONS V62) drawn as the
kernel's PutString draws it, for the checks that compare a screen (V148:
View's status bar and info page, Archive's list): a glyph's columns with
its spacing column, its row 0 at the baseline - 8; bold (SET_BOLD) as the
kernel does it: each glyph ORed one pixel to the right too, one pixel
wider. Characters outside $20-$7E are drawn as the programs give them:
'?' (the programs map them so)."""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'tools'))
import mkfont  # noqa: E402

BASE = mkfont.UBASE


def ch(c):
    if isinstance(c, int):
        c = chr(c)
    return c if ' ' <= c <= '~' else '?'


def cw(c, bold=False):
    return len(mkfont.U[ch(c)][0]) + (1 if bold else 0)


def width(s, bold=False):
    return sum(cw(c, bold) for c in s)


def put(bits, s, x, y, bold=False):
    """s at x, baseline y into bits (rows of 0/1 lists); the end x"""
    for c in s:
        g = mkfont.U[ch(c)]
        for r, row in enumerate(g):
            yy = y - BASE + r
            for k, p in enumerate(row):
                if p == '#':
                    for d in ((0, 1) if bold else (0,)):
                        xx = x + k + d
                        if 0 <= yy < len(bits) and 0 <= xx < len(bits[0]):
                            bits[yy][xx] = 1
        x += cw(c, bold)
    return x


def fit(s, w, bold=False):
    """s's head that fits in w pixels (vrwin.c's fit)"""
    n = t = 0
    while n < len(s) and t + cw(s[n], bold) <= w:
        t += cw(s[n], bold)
        n += 1
    return s[:n]
