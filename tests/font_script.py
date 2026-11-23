#!/usr/bin/env python3
"""gate font: writes tests/font_paint_script.h, Paint's session with the
font picker (tests/paint_play.c with PAINT_FONT; the helpers are
tests/paint_script.py's).

usage: font_script.py [outdir]      (default tests/)

It writes tests/fonted_script.h too: the Font Editor's session (tests/
fonted_play.c): Open (the picker: Gate Sans, 12, OK); the character A
(the characters' cells: 24 x 24 from 344, 56, twelve a row); presses on
the grid's cells (0, 0) and (1, 11), a drag along row 10 over cells 0-5
(the grid from 16, 56: 16 x 16 cells for 12 rows); Width +; Save; New
size 24 (Return); Save. Shots: edited, sized.

options/text font opens the picker (sdk/lib/fontpick.s: the box at
160-479 x 130-349; the font list's rows 14 high from y 150, x 168-343;
the size list x 352-399; OK at 408-455 x 150-165): the fonts are System,
Veranda UI, Gate Mono, Gate Sans; Gate Sans (row 3) shows its sizes 9,
12, 18, 27 and a preview; 18 (row 2), OK. Then the text tool, a click at
(200, 300), "Veranda" typed and Return: the text in Gate Sans 18 with
its baseline at y 300. Lines "/* shot NAME FRAME */": the picker open
(picker), the end (text).
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import paint_script as ps  # noqa: E402

TEXT = 'Veranda'
X, Y = 200, 300


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.abspath(__file__))
    ps.L.clear()
    ps.shots.clear()
    ps.P(0, 320, 240, 0)
    f = ps.menu(30, 'options', 1, 'options: text font: the picker')
    f = ps.click(f + 120, 250, 157 + 14 * 3, 'Gate Sans: its sizes, the preview')
    f = ps.click(f + 120, 375, 157 + 14 * 2, 'size 18')
    ps.shots.append(('picker', f + 120))
    f = ps.click(f + 130, 430, 157, 'OK')
    f = ps.click(f + 60, *ps.TOOL['text'], c='tool: text')
    f = ps.click(f, X, Y, 'text at a click')
    f = ps.typ(f + 20, TEXT, 'typed')
    ps.K(f + 2, '\r')
    ps.shots.append(('text', f + 60))
    ps.L.append('END(%d)' % (f + 60))
    with open(os.path.join(out, 'font_paint_script.h'), 'w') as o:
        o.write('/* gate font: Paint\'s session with the font picker, written by tests/font_script.py */\n')
        for name, fr in ps.shots:
            o.write('/* shot %s %d */\n' % (name, fr))
        o.write('\n'.join(ps.L) + '\n')
    fonted(out)


def fonted(out):
    ps.L.clear()
    ps.shots.clear()
    ps.P(0, 320, 240, 0)
    f = ps.click(40, 40, 34, 'Open: the picker')
    f = ps.click(f + 150, 250, 157 + 14 * 3, 'Gate Sans')
    f = ps.click(f + 120, 375, 157 + 14 * 1, 'size 12')
    f = ps.click(f + 60, 430, 157, 'OK: the font read')
    f = ps.click(f + 200, 344 + 9 * 24 + 12, 56 + 2 * 24 + 12, "the character A")
    cell = lambda x, y: (16 + 16 * x + 8, 56 + 16 * y + 8)      # noqa: E731
    f = ps.click(f + 150, *cell(0, 0), c='toggle (0, 0)')
    f = ps.click(f + 30, *cell(1, 11), c='toggle (1, 11)')
    f = ps.drag(f + 30, [cell(x, 10) for x in range(6)], 'paint row 10, cells 0-5')
    f = ps.click(f + 20, 448, 34, 'Width +')
    ps.shots.append(('edited', f + 120))
    f = ps.click(f + 130, 110, 34, 'Save')
    f = ps.click(f + 600, 200, 34, 'New size...')
    f = ps.typ(f + 60, '24', 'the size')
    ps.K(f + 2, '\r')
    ps.shots.append(('sized', f + 890))
    f = ps.click(f + 900, 110, 34, 'Save')
    ps.L.append('END(%d)' % (f + 1500))
    with open(os.path.join(out, 'fonted_script.h'), 'w') as o:
        o.write('/* gate font: the Font Editor\'s session, written by tests/font_script.py */\n')
        for name, fr in ps.shots:
            o.write('/* shot %s %d */\n' % (name, fr))
        o.write('\n'.join(ps.L) + '\n')


if __name__ == '__main__':
    main()
