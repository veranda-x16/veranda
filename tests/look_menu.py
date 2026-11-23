#!/usr/bin/env python3
"""The Veranda look's menu geometry (kernel/u/menu.s, DECISIONS V74, V79),
for the tests' scripts: where the kernel puts a native program's menu bar
items and its sub menus' items.

The bar: item 0 (the program's name, bold: one pixel more a character)
from x 0 with the mark before it (24 pixels), each other item 6 pixels
from its text on both sides; each item's right end rounded up to a card.
A sub menu opens under its bar item (from its left, on a card), 16 lines
an item from line 16. The text's widths are the menu font's: the system
font's (mkfont.G), or the UI font's (mkfont.U: its glyphs hold their spacing column) when the
program's menus are in the UI font (uiFont = FONT_UI).
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'tools'))
import mkfont  # noqa: E402

ITEM_Y0, ITEM_H = 16, 16


def textw(t, ui=False):
    if ui:
        return sum(len(mkfont.U[c][0]) for c in t)
    return sum(len(mkfont.G[c][0]) for c in t)


def bar(names, ui=False):
    """each bar item's (left, right end) for the bar's texts"""
    out, b = [], 0
    for i, t in enumerate(names):
        e = b + (24 + textw(t, ui) + len(t) if i == 0 else 6 + textw(t, ui))
        e = (e + 6 + 7) & ~7
        out.append((b, e))
        b = e
    return out


def centres(names, ui=False):
    """each bar item's middle"""
    return [(a + b) // 2 for a, b in bar(names, ui)]


def item_y(n):
    """the middle of a sub menu's item n"""
    return ITEM_Y0 + ITEM_H * n + ITEM_H // 2
