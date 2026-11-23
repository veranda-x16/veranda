#!/usr/bin/env python3
"""gate clip: writes the sessions of the clipboard gate (the helpers are
tests/paint_script.py's):

  tests/clip_script.h       Paint's (tests/paint_play.c with PAINT_CLIP)
  tests/photoman_script.h   the Photo Manager's, from its start (tests/man_play.c)
  tests/textman_script.h    the Text Manager's

usage: clip_script.py [outdir]      (default tests/)

Paint: a filled rectangle in colour 5 and pattern 7, two lines in no
colour (the second over the rectangle); edit/select, an area dragged
(snapped to cards: 96-231 x 96-207, 17 cards by 112 rows); edit/copy;
edit/paste: the picture floats under the pointer, which moves to (404,
300); a press puts it down at (400, 296); options/accessory: the Photo
Manager (the list's first row): add, copy, the close box; edit/select
480-575 x 96-151, edit/cut; options/accessory: the Text Manager (the
second row): add (the Text Scrap the gate put there), copy, the close
box. Lines "/* shot NAME FRAME */" name frames for a screenshot (the
copy check stops there too).

The managers' window is the whole screen: the close box at 6-17, 2-12,
the buttons 56 x 14 from x 8, 64 apart, at y 18-31 (previous, next, add,
copy, delete).
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import paint_script as ps  # noqa: E402

BTN = {'prev': 0, 'next': 1, 'add': 2, 'copy': 3, 'delete': 4}


def btn(name):
    return 8 + BTN[name] * 64 + 28, 24


def write(path, title, shots):
    with open(path, 'w') as o:
        o.write('/* gate clip: %s, written by tests/clip_script.py */\n' % title)
        for name, fr in shots:
            o.write('/* shot %s %d */\n' % (name, fr))
        o.write('\n'.join(ps.L) + '\n')


def paint(path):
    ps.L.clear()
    ps.shots.clear()
    ps.P(0, 320, 240, 0)
    f = ps.click(30, *ps.colour(5), c='colour 5')
    f = ps.click(f, *ps.pattern(7), c='pattern 7')
    f = ps.click(f, *ps.TOOL['box'], c='tool: filled rectangle')
    f = ps.drag(f, [(100, 100), (160, 150), (220, 200)], 'a filled rectangle in colour 5')
    f = ps.click(f, *ps.colour(0), c='colour 0 (none)')
    f = ps.click(f, *ps.TOOL['line'], c='tool: line')
    f = ps.drag(f, [(60, 420), (300, 250), (600, 60)], 'a line')
    f = ps.drag(f, [(90, 205), (160, 150), (230, 98)], 'a line over the rectangle')
    f = ps.menu(f, 'edit', 2, 'edit: select')
    f = ps.drag(f, [(100, 100), (160, 160), (227, 207)], 'the selection: 96-231 x 96-207', shot='select')
    f = ps.menu(f, 'edit', 4, 'edit: copy (the Photo Scrap)')
    ps.shots.append(('copied', f + 500))
    f = ps.menu(f + 600, 'edit', 5, 'edit: paste: the picture floats under the pointer')
    f += 120
    for i in range(31):
        ps.P(f + i, 45 + (404 - 45) * i // 30, 91 + (300 - 91) * i // 30, 0, 'moved' if i == 0 else None)
    f += 31
    ps.shots.append(('floating', f + 60))
    f = ps.click(f + 90, 404, 300, 'a press puts it down at 400, 296')
    ps.shots.append(('pasted', f + 200))
    f = ps.menu(f + 300, 'paint', 1, 'Paint: desk accessory: the list (Photo Manager first)')
    f = ps.click(f + 300, *ps.OPEN, c='OPEN: the Photo Manager (its own script plays)')
    f = ps.menu(f + 600, 'edit', 2, 'back in Paint: edit: select')
    f = ps.drag(f, [(484, 100), (520, 130), (570, 150)], 'the selection: 480-575 x 96-151')
    f = ps.menu(f, 'edit', 3, 'edit: cut')
    f = ps.menu(f + 600, 'paint', 1, 'Paint: desk accessory')
    f = ps.click(f + 300, *ps.row(1), c='the Text Manager (the second row)')
    f = ps.click(f + 20, *ps.OPEN, c='OPEN: the Text Manager (its own script plays)')
    f += 600
    ps.L.append('END(%d)' % f)
    write(path, "Paint's session", ps.shots)


def manager(path, title, shot):
    ps.L.clear()
    ps.shots.clear()
    ps.P(0, 320, 240, 0)
    f = ps.click(60, *btn('add'), c='add: the clipboard into the album')
    ps.shots.append((shot, f + 400))
    f = ps.click(f + 500, *btn('copy'), c='copy: the page back to the clipboard')
    f = ps.click(f + 400, 627, 7, c='the close box (at the title band\'s right, V148): RstrAppl')
    ps.L.append('END(60000)')
    write(path, title, ps.shots)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.abspath(__file__))
    paint(os.path.join(out, 'clip_script.h'))
    manager(os.path.join(out, 'photoman_script.h'), "the Photo Manager's session", 'photoman')
    manager(os.path.join(out, 'textman_script.h'), "the Text Manager's session", 'textman')


if __name__ == '__main__':
    main()
