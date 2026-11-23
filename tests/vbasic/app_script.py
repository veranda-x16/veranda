#!/usr/bin/env python3
"""gate vb_app (DECISIONS V99): Make application in VeraBASIC, then the made
application from the shell. Writes CARD/SHELL.TST (the shell's parts,
tests/shell_script.py) and CARD/app.ms (tests/vbasic/ui_mouse.py's script:
real mouse packets for the programs) for a card in Veranda's layout
(/VERANDA/SHELL.cvt; /VERANDA/APPS: VeraBASIC, VeraBASIC Run;
/DOCUMENTS: Bird Watch.bas, Garden.brd).

usage: app_script.py CARD full|make|apps IDEMAP RUNMAP

IDEMAP, RUNMAP: VeraBASIC's and VeraBASIC Run's maps (vbide.map, vbrun.map:
the mouse script's waits)

full, the session:
  0  the shell (in /DOCUMENTS): Bird Watch.bas double-clicked: VeraBASIC;
     File > Make application..., the Save dialog (in /VERANDA/APPS), Return:
     "Bird Watch.cvt" written; File > Quit
  1  the shell: Apps in the sidebar, Bird Watch (its own tile) double-clicked:
     it starts; Birds > Add a bird; File > Put aside (ASIDE: the switcher's
     TASK_ASIDE, as Alt+Tab)
(the mouse script waits for the application by its name in main RAM, then
for each handler by the count of its events, read from its map; a hold
first, long enough for the shell's part between: $APP_SLOW times it for an
SD card image)
  2  the shell with the dock: Bird Watch's dock item clicked: it comes back
     (its count still 1); Birds > Add a bird, File > Save the count
     (/DOCUMENTS/Sightings.brd: 2), File > Quit (END: back to the shell)
  3  the shell: Documents, Garden.brd (42 birds, .brd: APP DOCUMENTS)
     double-clicked: Bird Watch starts with it (DOCUMENT$: 42); Birds > Add
     a bird, File > Save the count (into Garden.brd: 43); the end (the
     dump: the window, "43 birds")
make: part 0 up to the Save dialog, the end there (a screenshot)
apps: the shell shows /VERANDA/APPS (a card with the made application),
      the end (a screenshot of its tile)
MIT licence (LICENSE)."""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
import shell_script as S  # noqa: E402

IDE_BAR = '"VeraBASIC" "File" "Edit" "Search" "Run" "Help"'
APP_BAR = '"Bird Watch" "File" "Birds"'
F_MAKE, F_QUIT = 5, 6               # the editor's File menu (ide/cmd.c)
A_SAVE, A_ASIDE, A_QUIT = 0, 1, 2   # Bird Watch's File menu
B_ADD = 0                           # its Birds menu


def ls(d, sub, extra=()):
    p = os.path.join(d, sub)
    n = os.listdir(p) + list(extra)
    return ['..'] + S.listing([x for x in n if os.path.isdir(os.path.join(p, x))],
                              sorted(set(x for x in n if not os.path.isdir(os.path.join(p, x)))))


def main():
    if len(sys.argv) != 5 or sys.argv[2] not in ('full', 'make', 'apps'):
        sys.exit(__doc__)
    d, how, idemap, runmap = sys.argv[1:]
    docs = ls(d, 'DOCUMENTS')
    parts, ms = [], []
    if how == 'apps':
        p = S.Part()
        p.wait(30)
        p.click(*S.place(1))
        p.wait(60)
        p.end(S.END_DONE)
        S.write(os.path.join(d, 'SHELL.TST'), [p])
        open(os.path.join(d, 'app.ms'), 'w').write('pause 30\n')
        return
    # 0: VeraBASIC with Bird Watch.bas, Make application...
    p = S.Part()
    p.wait(20)
    p.dbl(*S.cell(docs.index('Bird Watch.bas')))
    p.end(S.END_STOP)
    parts.append(p)
    ms += ['map ' + idemap, 'hold 1500', 'bar ' + IDE_BAR, 'pick 1 %d' % F_MAKE, 'hold 600']
    if how == 'make':
        ms += ['pause 60', 'exit']
        S.write(os.path.join(d, 'SHELL.TST'), parts)
        open(os.path.join(d, 'app.ms'), 'w').write('\n'.join(slow(ms)) + '\n')
        return
    ms += ['type \\n', 'hold 900', 'home', 'bar ' + IDE_BAR, 'pick 1 %d' % F_QUIT, 'hold 300']
    # 1: Apps, Bird Watch double-clicked; a bird; put aside
    apps = ls(d, 'VERANDA/APPS', ['Bird Watch.cvt'])
    p = S.Part()
    p.wait(30)
    p.click(*S.place(1))
    p.wait(60)
    p.dbl(*S.cell(apps.index('Bird Watch.cvt')))
    p.end(S.END_STOP)
    parts.append(p)
    ms += ['hold 900', 'map ' + runmap, 'name Bi', 'ready', 'pause 30', 'home', 'bar ' + APP_BAR,
           'pick 2 %d 60' % B_ADD, 'events 1', 'pause 30', 'home', 'pick 1 %d 60' % A_ASIDE, 'hold 1200']
    # 2: the dock: back; a bird, the count saved, quit
    p = S.Part()
    p.wait(40)
    p.click(*S.dock_item(0, 1))
    p.end(S.END_STOP)
    parts.append(p)
    ms += ['hold 1200', 'name Bi', 'ready', 'pause 30', 'home', 'pick 2 %d 60' % B_ADD, 'events 3', 'pause 30',
           'home', 'pick 1 %d 60' % A_SAVE, 'events 4', 'pause 30', 'home', 'pick 1 %d 60' % A_QUIT, 'hold 300']
    # 3: Documents, Garden.brd: Bird Watch with its document
    docs3 = ls(d, 'DOCUMENTS', ['Sightings.brd'])
    p = S.Part()
    p.wait(30)
    p.click(*S.place(2))
    p.wait(60)
    p.dbl(*S.cell(docs3.index('Garden.brd')))
    p.end(S.END_STOP)
    parts.append(p)
    ms += ['hold 900', 'name Bi', 'ready', 'pause 30', 'home', 'pick 2 %d 60' % B_ADD, 'events 1', 'pause 30',
           'home', 'pick 1 %d 60' % A_SAVE, 'events 2', 'hold 60', 'exit']
    S.write(os.path.join(d, 'SHELL.TST'), parts)
    open(os.path.join(d, 'app.ms'), 'w').write('\n'.join(slow(ms)) + '\n')


def slow(ms):
    """$APP_SLOW (an SD card image: its loads take longer) times each hold"""
    k = int(os.environ.get('APP_SLOW', '1'))
    return [('hold %d' % (int(m.split()[1]) * k)) if m.startswith('hold ') else m for m in ms]


if __name__ == '__main__':
    main()
