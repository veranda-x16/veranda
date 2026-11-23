#!/usr/bin/env python3
"""gate paint: writes tests/paint_script.h, the session that the test build
of Paint plays (tests/paint_play.c's P, K and END macros).

usage: paint_script.py [out.h]      (default tests/paint_script.h)

Frames at 60 a second. Paint's screen (the Sunroom column, DECISIONS
V147: apps/paint/mkart.py): the tools in 24 x 24 cells from y 16, two a
row; the patterns in 16 x 16 cells from y 168, three a row; the colours
in 16 x 16 cells from y 344, three a row; the drawing area from x 48, y
16. TOOL, pattern() and colour() below give the middle of each (the
other gates' Paint sessions use them). The menus: the Veranda look's menu
bar (DECISIONS V74, V79: tests/look_menu.py, in the UI font), MENUS below.
Lines "/* shot NAME FRAME */" name frames worth a screenshot.

File/Open and Save as are the SDK's dialog (sdk/lib/vrchoose.c,
DECISIONS V79, V82), driven by keys: when saving, letters and Backspace
edit the name, Return saves; when opening, a letter selects the next name
starting with it (the folder's .cvt files: AUTOSTART, Draft 1-5, Picture,
Sketch, Zebra, the long-named one), Return opens, Esc cancels. Export and
print still ask for their name in a GEOS box (16 characters).
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import look_menu  # noqa: E402

L = []
shots = []

# the column (apps/paint/paint.h, mkart.py): each tool's, pattern's and
# colour's middle
TOOLS = ['select', 'fill', 'pencil', 'brush', 'spray', 'eraser', 'line', 'text', 'rect', 'box', 'oval', 'disc']
TOOL = {n: ((i & 1) * 24 + 12, 16 + (i >> 1) * 24 + 12) for i, n in enumerate(TOOLS)}


def pattern(i):
    return ((i % 3) * 16 + 7, 168 + (i // 3) * 16 + 7)


def colour(i):
    return ((i % 3) * 16 + 7, 344 + (i // 3) * 16 + 7)


def P(f, x, y, b, c=None):
    L.append('P(%d, %d, %d, %d),%s' % (f, x, y, b, '  /* %s */' % c if c else ''))


def K(f, ch, c=None):
    code = {'\r': '13', '\b': '8', '\x1b': '27'}.get(ch, "'%s'" % ch)
    L.append('K(%d, %s),%s' % (f, code, '  /* %s */' % c if c else ''))


def click(f, x, y, c=None):
    P(f, x, y, 0, c)
    P(f + 1, x, y, 1)
    P(f + 3, x, y, 0)
    return f + 10


def drag(f, pts, c=None, shot=None):
    """press at the first point, a point a frame, hold the last for 6
    frames (the rubber band catches up), release"""
    x, y = pts[0]
    P(f, x, y, 0, c)
    P(f + 1, x, y, 1)
    f += 2
    for x, y in pts[1:]:
        P(f, x, y, 1)
        f += 1
    if shot:
        shots.append((shot, f + 5))
    P(f + 6, x, y, 0)
    return f + 12


# the menu bar (apps/paint/paint.c): each menu's bar item's middle; its
# sub menu opens under the item, its items 16 lines apart from line 16
# (Paint: about, desk accessory; File; Edit; Options: ink colour, text font)
MENUS = dict(zip(('paint', 'file', 'edit', 'options'), look_menu.centres(['Paint', 'File', 'Edit', 'Options'], True)))


def menu(f, name, item, c):
    """open a menu (pressed on its bar item: the sub menu opens at once),
    let go on the item (as the shell's scripts do), press it"""
    mx = MENUS[name]
    P(f, mx, 7, 0, c)
    P(f + 1, mx, 7, 1)
    y = look_menu.item_y(item)
    P(f + 2, mx, y, 0)
    P(f + 4, mx, y, 0)
    P(f + 10, mx, y, 1)
    P(f + 12, mx, y, 0)
    return f + 70


# Paint > desk accessory's list (a GEOS box, DBGETFILES 4, 4, at the
# default place: 224-415, 192-287): the file list's rows of 11 from y 197,
# the scroll strip at y 252-263; OPEN at 360-407, 200-215
ROW0, UP, DOWN, OPEN = 202, (259, 258), (320, 258), (384, 207)


def row(i):
    """the middle of the accessory list's row i"""
    return (290, ROW0 + 11 * i)


# a long name (DECISIONS V82): 39 characters
LONG = 'Holiday sketch from the lake shore 2026'
DLG = 90                        # frames from a menu's end to the dialog's keys


def choose(f, letter, c, shot=None):
    """in the Open dialog: the next name starting with letter, Return"""
    K(f + DLG, letter, c)
    if shot:
        shots.append((shot, f + DLG + 30))
    K(f + DLG + 40, '\r', 'Return: open')
    return f + DLG + 42


def typ(f, s, c=None):
    for i, ch in enumerate(s):
        K(f + 2 * i, ch, c if i == 0 else None)
    return f + 2 * len(s)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), 'paint_script.h')
    P(0, 320, 240, 0)
    f = menu(10, 'file', 1, 'file: open: the dialog (Paint itself, AUTOSTART.cvt, the only .cvt file)')
    K(f + DLG, chr(27), 'Esc: cancelled (then the test build saves Draft 1-5 and Zebra)')
    f = click(f + 900, *colour(2), c='colour 2')
    f = drag(f, [(int(80 + i * 8), int(110 + 40 * math.sin(i / 5.0))) for i in range(40)],
             'pencil (the first tool): a freehand stroke')
    f = drag(f, [(70, 200), (90, 230), (110, 190), (140, 260), (170, 200), (190, 240)], 'pencil: a zigzag')
    f = click(f, *TOOL['line'], c='tool: line')
    f = drag(f, [(120, 300), (150, 320), (200, 350), (260, 400), (300, 440)], 'a line, rubber-banded')
    f = drag(f, [(60, 460), (200, 330), (330, 300)], 'another line')
    f = click(f, *TOOL['rect'], c='tool: rectangle')
    f = drag(f, [(350, 40), (400, 80), (500, 150), (600, 200)], 'a rectangle')
    f = click(f, *colour(5), c='colour 5')
    f = click(f, *pattern(7), c='pattern 7')
    f = click(f, *TOOL['box'], c='tool: filled rectangle')
    f = drag(f, [(380, 240), (450, 300), (560, 400)], 'a filled rectangle', shot='band')
    f = click(f, *pattern(12), c='pattern 12')
    f = drag(f, [(320, 260), (260, 200), (200, 120)], 'a filled rectangle, dragged up and left')
    f = click(f, *pattern(1), c='pattern 1 (black)')
    f = drag(f, [(600, 300), (620, 330), (630, 350)], 'a small black one')
    f = click(f, *TOOL['text'], c='tool: text')
    f = click(f, 420, 430, 'text at a click')
    f = typ(f, 'Veranda', 'typed')
    K(f + 2, '\r')
    f = click(f + 10, *TOOL['eraser'], c='tool: eraser')
    f = drag(f, [(400, 300), (440, 310), (480, 320), (540, 330)], 'erase across the pattern')
    f = menu(f, 'edit', 1, 'edit: invert')
    f = menu(f, 'edit', 1, 'edit: invert (back again)')
    f = menu(f, 'paint', 0, 'Paint: about')
    K(f, '\r', 'Return: OK')
    f = menu(f + 20, 'file', 3, 'file: save as: the dialog')
    f = typ(f + DLG, 'Picture', 'the name')
    shots.append(('dialog', f + 1))
    K(f + 2, '\r', 'save (about 2 s on the host folder, more on the SD card)')
    # (V147: timings, not saved: a big oval's rubber band growing to most
    # of the drawing area, the fill of most of what is inside it)
    f = click(f + 1200, *TOOL['oval'], c='tool: oval (the timings)')
    f = drag(f, [(60 + 57 * i, 24 + 44 * i) for i in range(11)],
             'a big oval, its band timed (TIME drag k)')
    f = click(f + 60, *TOOL['fill'], c='tool: fill (after the oval is drawn)')
    f = click(f + 10, 330, 380, 'the fill inside it, timed (TIME fill)')
    f = menu(f + 600, 'file', 0, 'file: new')
    f = click(f + 300, *TOOL['line'], c='tool: line')
    f = drag(f, [(100, 100), (300, 250), (500, 400)], 'a second picture: a line')
    f = drag(f, [(100, 400), (300, 250), (500, 100)], 'and another')
    # the newer tools (V147): an oval filled with pattern 2 by the fill,
    # a filled oval, the brush, the spray
    f = click(f, *TOOL['oval'], c='tool: oval')
    f = drag(f, [(520, 30), (560, 60), (620, 110)], 'an oval', shot='oval')
    f = click(f, *pattern(2), c='pattern 2 (50 % grey)')
    f = click(f, *TOOL['fill'], c='tool: fill')
    f = click(f + 10, 570, 70, 'the fill inside the oval')
    f += 120                                # (the fill: about a second)
    f = click(f, *TOOL['disc'], c='tool: filled oval')
    f = drag(f, [(520, 380), (580, 420), (620, 460)], 'a filled oval')
    f = click(f, *pattern(1), c='pattern 1 (black)')
    f = click(f, *TOOL['brush'], c='tool: brush')
    f = drag(f, [(150 + 15 * i, 450 - (i & 1) * 6) for i in range(10)], 'a brush stroke')
    f = click(f, *TOOL['spray'], c='tool: spray')
    f = drag(f, [(70, 60)] * 8 + [(70 + 4 * i, 60) for i in range(6)], 'the spray, held, then moved')
    f = menu(f, 'file', 3, 'file: save as')
    f = typ(f + DLG, 'Sketch', 'the name')
    K(f + 2, '\r', 'save')
    f = menu(f + 1200, 'file', 0, 'file: new')
    f = menu(f + 60, 'file', 1, 'file: open: AUTOSTART, Draft 1-5, Picture, Sketch, Zebra')
    shots.append(('files', f + DLG))
    f = choose(f, 's', 'Sketch', shot='opendlg')
    f = menu(f + 900, 'file', 1, 'file: open: Zebra (version 1: no colours)')
    f = choose(f, 'z', 'Zebra')
    f = menu(f + 900, 'file', 1, 'file: open again')
    f = choose(f, 'p', 'Picture')
    f = menu(f + 900, 'file', 4, 'file: export (the name: Picture, the document\'s)')
    f = typ(f, '\b' * 7, 'deleted')
    f = typ(f, 'Print', 'a name typed (Paint adds .bmp)')
    K(f + 2, '\r', 'export: Print.bmp from the back screen')
    f += 1500                               # (the 4 bpp export: about 6 s on the SD card)
    f = menu(f, 'file', 3, 'file: save as a long name (V82): the field holds Picture')
    f = typ(f + DLG, '\b' * len('Picture'), 'deleted')
    f = typ(f, LONG, 'the long name typed')
    shots.append(('savelong', f + 20))
    K(f + 30, '\r', 'save: "%s.cvt"' % LONG)
    f = menu(f + 1230, 'file', 0, 'file: new')
    f = menu(f + 60, 'file', 1, 'file: open: the long name among the others')
    f = choose(f, 'h', 'the long-named picture', shot='openlong')
    f += 900
    L.append('END(%d)' % f)
    with open(out, 'w') as o:
        o.write('/* gate paint: the session, written by tests/paint_script.py */\n')
        for name, fr in shots:
            o.write('/* shot %s %d */\n' % (name, fr))
        o.write('\n'.join(L) + '\n')


if __name__ == '__main__':
    main()
