#!/usr/bin/env python3
"""Gate tile (tools/gate_tile.sh; DECISIONS V101): the shell's scripts
(SHELL.TST, shell/play.s) for a run in the card's layout (the shell in
/VERANDA, starting in /DOCUMENTS, which holds what <folder>/DOCUMENTS
holds).

usage: tile_script.py <folder> probe|shot|menu|dialog|closed|moved|app|aside|asideshot|picaside

  probe      the end (the desktop as drawn at the start)
  shot       the end through the shell's export (play.s's end 2: the
             screen to SHOT.BMP with ExportRect, then the dump)
  menu       the Veranda menu opened (pressed on its name, released in
             it), the end with it open
  dialog     window 0 closed, Veranda > About, the end with its box open
  closed     window 0 dragged 80 right and down, closed (its close glyph),
             the Veranda menu opened and closed by a click outside it,
             Veranda > About and its OK: the end (the whole desktop)
  moved      window 0 dragged 80 right and down: the end (its corners on
             the picture where it went: DECISIONS V102)
  app        TileApp double-clicked (tests/tile_app.s: it logs, quits);
             part 1, the shell again: the end
  aside      TileApp (built -D ASIDE: it puts itself aside, as Alt + Tab);
             part 1: the dock's item clicked (it comes back, quits);
             part 2: the end
  asideshot  as aside, part 1 the end (the shell with TileApp aside)
  picaside   as aside with PicApp (gate pic, tests/pic_app.c -D ASIDE: a
             program in tile mode, DECISIONS V105)
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import shell_script as ss  # noqa: E402

WIN0 = ss.WIN0
TITLE = (250, WIN0[1] + 8)
MOVED = (TITLE[0] + 80, TITLE[1] + 80)
CLOSE_AT = (WIN0[2] + 80 - 8, WIN0[1] + 80 + 8)
END_SHOT = 2


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    d, what = sys.argv[1:]
    docs = os.path.join(d, 'DOCUMENTS')
    names = os.listdir(docs)
    order = ['..'] + ss.listing([n for n in names if os.path.isdir(os.path.join(docs, n))],
                                [n for n in names if not os.path.isdir(os.path.join(docs, n))])
    parts = []
    p = ss.Part()
    p.wait(30)
    x = ss.MENU_X['geos']
    if what == 'menu':
        p.at(x, 7, 0, 4)
        p.at(x, 7, 1, 2)
        p.at(x, 40, 0, 60)                  # (released in it: it stays open)
    elif what == 'dialog':
        p.click(WIN0[2] - 8, WIN0[1] + 8)   # window 0 closed: the box over the picture
        p.wait(40)
        p.menu('geos', 'about')
        p.wait(40)
    elif what == 'moved':
        p.drag(TITLE, MOVED)
        p.wait(40)
    elif what == 'closed':
        p.drag(TITLE, MOVED)
        p.wait(40)
        p.click(*CLOSE_AT)
        p.wait(40)
        p.at(x, 7, 0, 4)
        p.at(x, 7, 1, 2)
        p.at(x, 40, 0, 30)
        p.click(300, 300)                   # outside: the menu closes
        p.wait(30)
        p.menu('geos', 'about')
        p.wait(30)
        p.click(ss.YES_X, ss.YES_Y)         # its OK
        p.wait(40)
    elif what in ('app', 'aside', 'asideshot', 'picaside'):
        p.dbl(*ss.cell(order.index('PicApp.cvt' if what == 'picaside' else 'TileApp.cvt')))
        p.end(ss.END_STOP)
        parts.append(p)
        p = ss.Part()
        p.wait(40)
        if what in ('aside', 'picaside'):
            p.click(*ss.dock_item(0, 1))
            p.end(ss.END_STOP)
            parts.append(p)
            p = ss.Part()
            p.wait(40)
    p.wait(30)
    p.end(END_SHOT if what in ('shot', 'asideshot') else ss.END_DONE)
    parts.append(p)
    ss.write(os.path.join(d, 'SHELL.TST'), parts)


if __name__ == '__main__':
    main()
