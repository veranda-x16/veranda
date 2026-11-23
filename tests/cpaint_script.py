#!/usr/bin/env python3
"""gate cpaint (DECISIONS V167): Colour Paint's test session, written as
tests/cpaint_script.h (tests/sdk_play.s's format through
tests/cpaint_play.c's P, K and END). 320 x 240 coordinates. The steps are
also STEPS below, which tests/check_cpaint.py replays on its own picture.

usage: cpaint_script.py <out.h>
"""
import sys

VX, VY, VW, VH = 40, 28, 280, 212   # the view (V170: under the title band)
F1 = 0x85                       # the ROM's PETSCII F1: the test build's snapshot
RIGHT, DOWN = 0x1D, 0x11        # cursor keys
RETURN = 13


def tool(t):
    return ((t & 1) * 20 + 10, 16 + (t >> 1) * 18 + 9)


SELECT, FILL, PENCIL, BRUSH, SPRAY, ERASER, LINE, TEXT, RECT, BOX, OVAL, DISC, PICK = range(13)
WELL_A, WELL_B = (10, 155), (28, 155)
MENU_X = {'file': 117, 'edit': 150, 'view': 184}
ITEM_Y0, ITEM_H = 14, 16


def pop(c):
    return (96 + (c & 15) * 8 + 4, 48 + (c >> 4) * 8 + 4)


# the steps the reference replays (screen coordinates; picture = screen -
# (VX, VY) + the scroll)
STEPS = [
    ('colour_a', 0x2A),
    ('pencil', [(60, 40), (64, 44), (70, 47), (78, 52), (90, 50), (101, 41), (110, 35), (118, 38)]),
    ('snap',),
    ('colour_a', 0x05), ('tool', LINE), ('drag', (60, 100), (200, 150)), ('snap',),
    ('colour_a', 0x06), ('tool', RECT), ('drag', (80, 60), (150, 110)), ('snap',),
    ('colour_b', 0x45, 'popup'),
    ('tool', BOX), ('drag', (160, 30), (230, 80)), ('snap',),
    ('colour_a', 0x02), ('tool', OVAL), ('drag', (70, 130), (170, 200)), ('snap',),
    ('colour_b', 0x7E), ('tool', DISC), ('drag', (180, 120), (300, 221)), ('snap',),
    ('colour_a', 0x07), ('tool', FILL), ('click', (120, 190)), ('snap',),
    ('colour_a', 0x0F), ('click', (300, 40)), ('snap',), ('shot', 'tools'),
    ('popup', 'colours'),                                 # the popup over the colours, closed by a key
    ('tool', ERASER), ('pencil', [(250, 190), (262, 193), (275, 196), (290, 200)]), ('snap',),
    ('tool', PICK), ('click', (200, 50)),
    ('tool', PENCIL), ('pencil', [(100, 200), (120, 204), (140, 210)]), ('snap',),
    ('menu', 'edit', 0, 'menu'), ('snap',),               # undo: the stroke gone
    ('key', RIGHT), ('key', RIGHT), ('key', RIGHT), ('key', RIGHT), ('key', RIGHT), ('key', DOWN), ('key', DOWN),
    ('pencil', [(60, 60), (80, 90)]), ('snap',),
    # stage 4 (V171): the brush, the spray, the text, the clipboard, the palette
    ('colour_a', 0x22), ('tool', BRUSH), ('pencil', [(200, 60), (210, 66), (220, 70), (240, 64)]), ('snap',),
    ('tool', SPRAY), ('pencil', [(250, 100), (255, 104), (260, 110)]), ('snap',),
    ('tool', TEXT), ('textat', (120, 50)), ('type', 'Hi X16'), ('key', RETURN), ('snap',),
    ('tool', SELECT), ('drag', (50, 40), (90, 70)), ('menu', 'edit', 2), ('menu', 'edit', 3),
    ('paste', (200, 150)), ('snap',), ('shot', 'pasted'),
    ('drag', (50, 40), (90, 70)), ('menu', 'edit', 1), ('snap',),
    ('menu', 'view', 1), ('palclick', (106, 58)), ('palclick', (281, 115)),
    ('palclick', (222, 133)), ('palclick', (281, 151)), ('shot', 'palette'), ('palclick', (20, 230)), ('snap',),
    # stage 5 (V172): export for Paint, as BMP, print: the names offered (Untitled ...)
    ('menu', 'file', 4), ('key', RETURN), ('wait', 900), ('menu', 'file', 5), ('key', RETURN), ('wait', 900),
    ('menu', 'file', 6), ('key', RETURN), ('wait', 3000),
    ('menu', 'file', 3), ('type', 'Colours'), ('key', RETURN),   # save as
    ('menu', 'file', 0),                                   # new
    ('menu', 'file', 1), ('type', 'C'), ('key', RETURN),   # open Colours
    ('shot', 'opened'),
    ('menu', 'file', 1), ('type', 'O'), ('key', RETURN),   # open Oldpic (Paint's)
    ('menu', 'view', 0), ('shot', 'whole'), ('key', RETURN),
    ('shot', 'end'),
]
WAIT = {'fill': 900, 'menu': 120, 'type': 40}


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    ev, shots = [], {}
    f = [30]

    def at(x, y, b, n=2):
        ev.append('P(%d, %d, %d, %d),' % (f[0], x, y, b))
        f[0] += n

    def key(c, n=20):
        ev.append('K(%d, %d),' % (f[0], c))
        f[0] += n

    def click(x, y, n=40):
        at(x, y, 0, 4)
        at(x, y, 1, 6)
        at(x, y, 0, n)

    cur = PENCIL
    for s in STEPS:
        k = s[0]
        if k in ('colour_a', 'colour_b'):
            click(*(WELL_A if k == 'colour_a' else WELL_B))
            if len(s) > 2:
                shots[s[2]] = f[0]
                f[0] += 60
            click(*pop(s[1]))
        elif k == 'popup':
            click(*WELL_A)
            shots[s[1]] = f[0]
            f[0] += 60
            key(RETURN, 60)
        elif k == 'tool':
            cur = s[1]
            click(*tool(s[1]))
        elif k == 'pencil':
            pts = s[1]
            at(*pts[0], 0, 4)
            at(*pts[0], 1, 30)          # (the press keeps undo's copy)
            for p in pts[1:]:
                at(*p, 1, 6)
            at(*pts[-1], 0, 60)
        elif k == 'drag':
            (a, b) = s[1], s[2]
            at(*a, 0, 4)
            at(*a, 1, 8)
            at((a[0] + b[0]) // 2, (a[1] + b[1]) // 2, 1, 8)
            at(*b, 1, 8)
            at(*b, 0, 120 if cur in (OVAL, DISC) else 60)
        elif k == 'click':
            click(*s[1], WAIT['fill'] if cur == FILL else 40)
        elif k == 'wait':
            f[0] += s[1]
        elif k == 'textat':
            click(*s[1], 60)
        elif k == 'paste':
            at(*s[1], 0, 20)
            click(*s[1], 60)
        elif k == 'palclick':
            click(*s[1], 30)
        elif k == 'snap':
            key(F1, 60)
        elif k == 'key':
            key(s[1], 60 if s[1] != RETURN else 300)
        elif k == 'type':
            for c in s[1]:
                key(ord(c), 10)
            f[0] += WAIT['type']
        elif k == 'menu':
            x = MENU_X[s[1]]
            at(x, 6, 0, 4)
            at(x, 6, 1, 4)
            at(x, ITEM_Y0 + ITEM_H * s[2] + 8, 0, 30)
            if len(s) > 3:
                shots[s[3]] = f[0]
                f[0] += 60
            click(x, ITEM_Y0 + ITEM_H * s[2] + 8, WAIT['menu'])
        elif k == 'shot':
            shots[s[1]] = f[0]
            f[0] += 60
    out = ['/* gate cpaint: the session, written by tests/cpaint_script.py */']
    out += ['/* shot %s %d */' % (k, v) for k, v in sorted(shots.items(), key=lambda kv: kv[1])]
    out += ev
    out.append('END(%d)' % (f[0] + 60))
    open(sys.argv[1], 'w').write('\n'.join(out) + '\n')


if __name__ == '__main__':
    main()
