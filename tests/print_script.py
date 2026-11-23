#!/usr/bin/env python3
"""gate print, Paint's file/print: writes tests/print_script.h, the session
the test build of Paint plays with PAINT_PRINT (tests/paint_play.c; the
helpers are tests/paint_script.py's).

usage: print_script.py [out.h]      (default tests/print_script.h)

Paint fills most of the drawing area in pattern 7 on colour 5, a
rectangle on colour 2, a black line and text; the ink becomes red
(options/ink colour). file/print: the page setup box (shot "printdlg"),
"paper" clicked (US Letter), OK; the name typed, "Printed" (Paint adds
.pdf): Printed.pdf, fit to the page. file/print again: "paper" (A4) and
"size" (80 pixels an inch) clicked, OK, "Actual": Actual.pdf. DECISIONS
V38; tests/check_print.py --paint checks both against the dump.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import paint_script as ps  # noqa: E402

AREA = (60, 30, 600, 460)
RED = (200, 150, 450, 350)
# the page setup box (the default box at 640x480: 224-415, 192-287):
# "paper" and "size" (user icons, 16 x 12, at cards 1 and 9, y 44), OK
PAPER, SIZE, OK = (240, 242), (304, 242), (255, 271)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), 'print_script.h')
    ps.L.clear()
    ps.shots.clear()
    ps.P(0, 320, 240, 0)
    f = ps.click(30, *ps.colour(5), c='colour 5')
    f = ps.click(f, *ps.pattern(7), c='pattern 7')
    f = ps.click(f, *ps.TOOL['box'], c='tool: filled rectangle')
    f = ps.drag(f, [AREA[:2], (300, 200), AREA[2:]], 'pattern 7 on colour 5')
    f = ps.click(f + 60, *ps.colour(2), c='colour 2 (red)')
    f = ps.drag(f, [RED[:2], (300, 250), RED[2:]], 'a rectangle on colour 2') + 60
    f = ps.click(f, *ps.TOOL['line'], c='tool: line')
    f = ps.drag(f, [(70, 470), (300, 100), (630, 300)], 'a line')
    f = ps.click(f, *ps.TOOL['text'], c='tool: text')
    f = ps.click(f, 100, 120, 'text at a click')
    f = ps.typ(f, 'Veranda prints', 'typed')
    ps.K(f + 2, '\r')
    f = ps.menu(f + 10, 'options', 0, 'options: ink colour (colour 2: red)')
    f = ps.menu(f, 'file', 5, 'file: print: the page setup box')
    ps.shots.append(('printdlg', f + 40))
    f = ps.click(f + 60, *PAPER, c='paper: US Letter')
    f = ps.click(f + 20, *OK, c='OK')
    f = ps.typ(f + 60, 'Printed', 'the name')
    ps.K(f + 2, '\r', 'print: Printed.pdf (Letter, fit to the page)')
    f = ps.menu(f + 1500, 'file', 5, 'file: print again')
    f = ps.click(f + 60, *PAPER, c='paper: A4')
    f = ps.click(f + 20, *SIZE, c='size: 80 pixels an inch')
    ps.shots.append(('printdlg2', f + 10))
    f = ps.click(f + 20, *OK, c='OK')
    f = ps.typ(f + 60, 'Actual', 'the name')
    ps.K(f + 2, '\r', 'print: Actual.pdf (A4, 80 pixels an inch)')
    f += 1500
    ps.L.append('END(%d)' % f)
    with open(out, 'w') as o:
        o.write('/* gate print: Paint\'s file/print, written by tests/print_script.py */\n')
        for name, fr in ps.shots:
            o.write('/* shot %s %d */\n' % (name, fr))
        o.write('\n'.join(ps.L) + '\n')


if __name__ == '__main__':
    main()
