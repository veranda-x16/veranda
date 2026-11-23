#!/usr/bin/env python3
"""Gate wall (tools/gate_wall.sh; DECISIONS V78): the shell's scripts
(SHELL.TST, shell/play.s) and Preferences' sessions (tests/da_play.c).

usage: wall_script.py shell <folder> probe|move|closed|mode|desk
       wall_script.py prefs <out dir>

shell: <folder> is a run in the card's layout (DECISIONS V71: the shell
in /VERANDA, starting in /DOCUMENTS, which holds what <folder>/DOCUMENTS
holds); one part:
  probe   the end (the desktop as drawn at the start)
  move    window 0 dragged by its title band 80 right and 80 down (to 96,
          112), the end: what it uncovered drawn again
  closed  the same drag, then window 0 closed (its close glyph), the
          Veranda menu opened and closed by a click outside it, Veranda >
          About and its box's OK: the end with the whole desktop shown
  mode    options > 640 x 240, the end
  desk    a double click on Preferences.cvt (its test build plays its own
          session and closes), the end
prefs: <out>/wall1/da_script.h (the Desktop page, Background: Plain
colour, Save, close) and <out>/wall2/da_script.h (the Desktop page,
Choose, the second picture of the list, OPEN, Save, close).
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import shell_script as ss  # noqa: E402
import da_script as da  # noqa: E402

WIN0 = ss.WIN0
TITLE = (250, WIN0[1] + 8)             # window 0's title band
MOVED = (TITLE[0] + 80, TITLE[1] + 80)
CLOSE_AT = (WIN0[2] + 80 - 8, WIN0[1] + 80 + 8)     # the close glyph, moved


def shell(d, what):
    docs = os.path.join(d, 'DOCUMENTS')
    names = os.listdir(docs)
    order = ['..'] + ss.listing([n for n in names if os.path.isdir(os.path.join(docs, n))],
                                [n for n in names if not os.path.isdir(os.path.join(docs, n))])
    p = ss.Part()
    p.wait(30)
    if what in ('move', 'closed'):
        p.drag(TITLE, MOVED)
        p.wait(40)
    if what == 'closed':
        p.click(*CLOSE_AT)
        p.wait(40)
        x = ss.MENU_X['geos']
        p.at(x, 7, 0, 4)
        p.at(x, 7, 1, 2)
        p.at(x, 40, 0, 30)
        p.click(300, 300)                   # outside: the menu closes
        p.wait(30)
        p.menu('geos', 'about')
        p.wait(30)
        p.click(ss.YES_X, ss.YES_Y)         # its OK
        p.wait(40)
    if what == 'mode':
        p.menu('options', '640x240')
        p.wait(60)
    if what == 'desk':
        p.dbl(*ss.cell(order.index('Preferences.cvt')))
        p.wait(60)
    p.wait(30)
    p.end(ss.END_DONE)
    ss.write(os.path.join(d, 'SHELL.TST'), [p])


# Preferences (apps/prefs/prefs.c): the Desktop button left of Theme, its
# rows as the other pages' (da_script.prow)
PDESK = (da.PX + 120 + 40, da.PY + 400 - 24 + 8)
CHOOSE = (da.PX + 184 + 32, da.prow(1))
# the file list of the default dialog box (224-415 x 192-287): rows of 11
# pixels from its top + 4; OPEN at DBI_X_2, DBI_Y_0
ROW1 = (280, 192 + 4 + 11 + 5)
OPEN = (224 + 17 * 8 + 20, 192 + 8 + 8)


def wall1():
    f = 40
    f = da.click(f, *PDESK, c='the Desktop page', wait=40)
    f = da.click(f, da.MORE, da.prow(0), c='background: Plain colour', wait=40)
    f = da.click(f, *da.PSAVE, c='Save: Veranda Prefs, WALLPAPER.CFG', wait=400)
    f = da.click(f + 20, da.PX + 480 - 11, da.PY + 8, c='the close glyph (at the right, V79): RstrAppl', wait=60)
    da.L.append('END(%d)' % (f + 20000))


def wall2():
    f = 40
    f = da.click(f, *PDESK, c='the Desktop page', wait=40)
    f = da.click(f, *CHOOSE, c='Choose: the pictures of /VERANDA/WALLPAPERS', wait=200)
    f = da.click(f, *ROW1, c='the second picture', wait=40)
    f = da.click(f, *OPEN, c='OPEN', wait=100)
    da.shots.append(('desk', f))
    f = da.click(f, *da.PSAVE, c='Save: Veranda Prefs, WALLPAPER.CFG', wait=400)
    f = da.click(f + 20, da.PX + 480 - 11, da.PY + 8, c='the close glyph (at the right, V79): RstrAppl', wait=60)
    da.L.append('END(%d)' % (f + 20000))


def main():
    a = sys.argv[1:]
    if len(a) == 3 and a[0] == 'shell':
        shell(a[1], a[2])
    elif len(a) == 2 and a[0] == 'prefs':
        wall1()
        da.write(os.path.join(da.sub(a[1], 'wall1'), 'da_script.h'), "Preferences' desktop: a plain colour")
        wall2()
        da.write(os.path.join(da.sub(a[1], 'wall2'), 'da_script.h'), "Preferences' desktop: another picture")
    else:
        sys.exit(__doc__)


if __name__ == '__main__':
    main()
