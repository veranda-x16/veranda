#!/usr/bin/env python3
"""Gate shell, the window operations' times (DECISIONS V80, V81): one
part of SHELL.TST (shell/play.s) for a run in the card's layout (the
shell in /VERANDA, starting in /DOCUMENTS), and the check of the times
the shell logs in testing mode ("TIME <what> <cycles>": shell/mouse.c,
"SHELL MOVED IN <cycles> CYCLES": shell/wops.c).

usage: shell_speed_script.py make <folder>
       shell_speed_script.py script <folder> [<steps>]
       shell_speed_script.py times <console.txt> [<limits>]

make: /DOCUMENTS gets 30 text files (the list scrolls in window 0);
script: the part:
   1  a click on icon 1 of window 0, then on icon 2     SELECT, SELECT
   2  a double click on the card's desktop icon:         DESKSELECT, DESKOPEN
      window 1 opens over window 0
   3  window 1 dragged 80 left and 40 up, over window 0  MOVE
   4  window 1 closed (over window 0)                    CLOSE
   5  the card again (window 1 where it was moved)       DESKSELECT, DESKOPEN
   6  window 1 resized by its grip, 64 narrower and      RESIZE
      48 lower
   7  window 0 brought to the front (its title band)     FRONT
   8  window 0: the list (the toolbar's toggle)          LIST
   9  the list's SIZE header                              HEADER
  10  the scroll bar's down arrow                         SCROLL
  11  back to icons                                       ICONS
  12  zoom, unzoom                                        ZOOM, UNZOOM
  13  the next page (the scroll bar's track: V151)         PAGE
  14  the trash's desktop icon selected                   DESKSELECT
  then the end (a VRAM dump).
times: the times in order, one "what cycles ms" a line; with limits
("WHAT=cycles,..."), exit 1 if any operation took longer.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import shell_script as ss  # noqa: E402

WIN0 = ss.WIN0
WIN1 = ss.WIN1
ORDER = ['SELECT', 'SELECT', 'DESKSELECT', 'DESKOPEN', 'MOVE', 'CLOSE', 'DESKSELECT', 'DESKOPEN', 'RESIZE', 'FRONT', 'LIST', 'HEADER',
         'SCROLL', 'ICONS', 'ZOOM', 'UNZOOM', 'PAGE', 'DESKSELECT']


def make(d):
    docs = os.path.join(d, 'DOCUMENTS')
    os.makedirs(docs, exist_ok=True)
    for i in range(30):
        with open(os.path.join(docs, 'Note %02d.txt' % i), 'w') as f:
            f.write('a note, %d\n' % i * (i + 1))


def script(d, upto=None):
    """the part; upto: only the first upto steps (the numbers above)"""
    p = ss.Part()
    p.wait(30)
    w1 = (WIN1[0] - 80, WIN1[1] - 40, WIN1[2] - 80, WIN1[3] - 40)
    tb = ss.toolbar(WIN0)
    x0 = ss.grid(WIN0)[0] * 8 - 8           # the contents' left

    def s1():
        p.click(*ss.cell(1))
        p.click(*ss.cell(2))

    def s2():
        p.dbl(*ss.DESK['card'])
        p.wait(40)

    def s3():                               # window 1 (its default place) by its title band
        a = (WIN1[0] + 100, WIN1[1] + 8)
        p.drag(a, (a[0] - 80, a[1] - 40))
        p.wait(20)

    def s4():
        p.click(w1[2] - 8, w1[1] + 8)       # its close glyph
        p.wait(20)

    def s6():
        g = ss.status(w1)['grip']
        p.drag(g, (g[0] - 64, g[1] + 48))
        p.wait(20)

    def s7():
        p.click(WIN0[0] + 200, WIN0[1] + 8)     # window 0's title band: to the front
        p.wait(20)

    def s8():
        p.click(*tb['list'])
        p.wait(20)

    def s9():
        p.click(x0 + 210, WIN0[1] + ss.TITLEH + ss.TOOLH + 8)      # SIZE
        p.wait(20)

    def s10():
        p.click(*ss.status(WIN0)['down'])                          # the scroll bar's down arrow
        p.wait(20)

    def s11():
        p.click(*tb['icons'])
        p.wait(20)

    def s12():
        p.click(WIN0[2] - 26, WIN0[1] + 8)      # zoom
        p.wait(30)
        p.click(69 * 8 - 1 - 26, 24 + 8)        # zoomed: cards 1-68 from row 24 (bars.c), its zoom glyph
        p.wait(30)

    def s13():
        p.click(*ss.status(WIN0)['next'])
        p.wait(20)

    def s14():
        p.click(*ss.DESK['trash'])
        p.wait(30)

    for f in [s1, s2, s3, s4, s2, s6, s7, s8, s9, s10, s11, s12, s13, s14][:upto]:
        f()
    p.end(ss.END_DONE)
    ss.write(os.path.join(d, 'SHELL.TST'), [p])


def times(console):
    out = []
    for line in open(console, 'rb').read().decode('latin-1').replace('\r', '').split('\n'):
        m = re.search(r'TIME ([A-Z]+) ([0-9]+)', line)
        if m and m.group(1) != 'SORT':
            out.append((m.group(1), int(m.group(2))))
    return out


def main():
    a = sys.argv[1:]
    if len(a) == 2 and a[0] == 'make':
        make(a[1])
    elif len(a) in (2, 3) and a[0] == 'script':
        script(a[1], int(a[2]) if len(a) == 3 else None)
    elif len(a) in (2, 3) and a[0] == 'times':
        t = times(a[1])
        for k, c in t:
            print('%-10s %9d %6.1f' % (k, c, c / 8000))
        got = [k for k, c in t]
        if got != ORDER:
            sys.exit('shell_speed_script: the operations were %s, not %s' % (got, ORDER))
        if len(a) == 3:
            lim = dict((k, int(v)) for k, v in (x.split('=') for x in a[2].split(',')))
            bad = [(k, c, lim[k]) for k, c in t if k in lim and c > lim[k]]
            if bad:
                sys.exit('shell_speed_script: too slow: ' + ', '.join('%s %d (limit %d)' % b for b in bad))
    else:
        sys.exit(__doc__)


if __name__ == '__main__':
    main()
