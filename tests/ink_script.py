#!/usr/bin/env python3
"""gate paint, the ink session: writes tests/ink_script.h, the session the
test build of Paint plays with PAINT_INK (tests/paint_play.c; the helpers
are tests/paint_script.py's).

usage: ink_script.py [out.h]      (default tests/ink_script.h)

Paint fills the drawing area in pattern 7 on colour 5 and a rectangle on
colour 2; the options menu opened over the colours (shot "inkmenu"),
options/about's dialog box over them (shot "inkdlg"); then colour 2
(red) becomes the ink (options/ink colour), the picture is saved as
"Inked", file/new (black ink again), file/open (the dialog: 'i' selects
Inked, Return), file/export (Inked.bmp, 4 bpp). DECISIONS V33.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import paint_script as ps  # noqa: E402

# the two rectangles (tests/check_ink.py has the same)
AREA = (60, 20, 630, 470)
RED = (200, 150, 450, 350)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), 'ink_script.h')
    ps.L.clear()
    ps.shots.clear()
    ps.P(0, 320, 240, 0)
    f = ps.click(30, *ps.colour(5), c='colour 5')
    f = ps.click(f, *ps.pattern(7), c='pattern 7')
    f = ps.click(f, *ps.TOOL['box'], c='tool: filled rectangle')
    f = ps.drag(f, [AREA[:2], (300, 200), AREA[2:]], 'the drawing area in pattern 7 on colour 5')
    f = ps.click(f + 60, *ps.colour(2), c='colour 2 (red)')
    f = ps.drag(f, [RED[:2], (300, 250), RED[2:]], 'a rectangle on colour 2') + 60
    ps.shots.append(('inkmenu', f + 8))
    f = ps.menu(f, 'paint', 0, 'Paint (open: shot inkmenu): about')
    ps.shots.append(('inkdlg', f + 10))
    ps.K(f + 20, '\r', 'Return: OK')
    f = ps.menu(f + 40, 'options', 0, 'options: ink colour (colour 2: red)')
    f = ps.menu(f, 'file', 3, 'file: save as')
    f = ps.typ(f + ps.DLG, 'Inked', 'the name')
    ps.K(f + 2, '\r', 'save')
    f = ps.menu(f + 1200, 'file', 0, 'file: new (black ink again)')
    f = ps.menu(f + 60, 'file', 1, 'file: open: the dialog')
    f = ps.choose(f, 'i', 'Inked (the folder\'s other .cvt file: AUTOSTART)')
    f = ps.menu(f + 900, 'file', 4, 'file: export (the name: Inked, the document\'s)')
    ps.K(f + 2, '\r', 'export: Inked.bmp')
    f += 1500
    ps.L.append('END(%d)' % f)
    with open(out, 'w') as o:
        o.write('/* gate paint: the ink session, written by tests/ink_script.py */\n')
        for name, fr in ps.shots:
            o.write('/* shot %s %d */\n' % (name, fr))
        o.write('\n'.join(ps.L) + '\n')


if __name__ == '__main__':
    main()
