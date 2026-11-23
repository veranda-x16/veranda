#!/usr/bin/env python3
"""Gate switch, its dock part (DECISIONS V83): a session of the shell's
dock with the switcher's test programs (tests/switch_app.s: SwOne, SwTwo
put themselves aside ten main loop passes after they start or come back,
quit the second time back). Writes <folder>/SHELL.TST
(tests/shell_script.py's records) for a run whose top folder holds the
shell, SwOne.cvt and SwTwo.cvt.

usage: dock_script.py <folder> [shot] [<extra name>...]     shot: the end after part 2's
                                           minimise (the dock's picture)
       dock_script.py <folder> before|restore   (V117) the end at part 2's
                                           start, or after its window came
                                           back from the dock: the same screen
       dock_script.py --want              the console lines expected

  0  SwOne selected, options > pin (the dock: SwOne); SwTwo double-clicked:
     it starts, puts itself aside: the shell again
  1  the dock: SwOne (pinned), SwTwo (aside: a dot); SwOne clicked: it
     starts, and goes aside
  2  window 0 minimised (the dock: SwOne, SwTwo, the window), its item
     clicked: open again; SwTwo clicked: it comes back (SAME), goes aside
  3  SwTwo right-clicked: its menu, Quit, YES (TASK_END); SwOne
     right-clicked: Quit and Unpin, Quit, YES; the end
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import shell_script as S  # noqa: E402

MIN_X, MIN_Y = (2 + 60) * 8 - 1 - 44, 40         # window 0's minimise glyph (chrome.c)


def want():
    return ['SHELL STARTED', 'SW 2 START', 'TASK ASIDE SwTwo', 'SHELL STARTED', 'SHELL DOCK START SwOne',
            'SW 1 START', 'TASK ASIDE SwOne', 'SHELL STARTED', 'SHELL DOCK MIN /', 'SHELL DOCK RESTORE /',
            'SHELL DOCK RESUME SwTwo', 'TASK BACK SwTwo', 'SW 2 SAME', 'TASK ASIDE SwTwo', 'SHELL STARTED',
            'SHELL DOCK MENU SwTwo', 'SHELL DOCK QUIT SwTwo', 'SHELL DOCK MENU SwOne', 'SHELL DOCK QUIT SwOne',
            'SHELL DONE']


def rclick(p, x, y):
    p.at(x, y, 0, 4)
    p.at(x, y, 2, 3)
    p.at(x, y, 0, 30)


def main():
    if sys.argv[1] == '--want':
        print('\n'.join(want()))
        return
    d = sys.argv[1]
    shot = 'shot' in sys.argv[2:]
    shot2 = 'shot2' in sys.argv[2:]
    before = 'before' in sys.argv[2:]
    restore = 'restore' in sys.argv[2:]
    extra = [a for a in sys.argv[2:] if a not in ('shot', 'shot2', 'before', 'restore')]
    dirs = [n for n in os.listdir(d) if os.path.isdir(os.path.join(d, n))]
    files = sorted(set([n for n in os.listdir(d) if not os.path.isdir(os.path.join(d, n))]
                       + ['SHELL.TST', 'SHELL.STP'] + extra))
    root = S.listing(dirs, files)
    parts = []
    p = S.Part()
    p.wait(20)
    p.click(*S.cell(root.index('SwOne.cvt')))
    p.menu('options', 'pin')
    p.wait(30)
    p.dbl(*S.cell(root.index('SwTwo.cvt')))
    p.end(S.END_STOP)
    parts.append(p)
    p = S.Part()
    p.wait(30)
    p.click(*S.dock_item(0, 2))
    p.end(S.END_STOP)
    parts.append(p)
    p = S.Part()
    p.wait(30)
    if before:
        p.wait(60)
        p.end(S.END_DONE)
        parts.append(p)
        S.write(os.path.join(d, 'SHELL.TST'), parts)
        return
    p.click(MIN_X, MIN_Y)
    p.wait(40)
    if shot:
        p.end(S.END_DONE)
        parts.append(p)
        S.write(os.path.join(d, 'SHELL.TST'), parts)
        return
    p.click(*S.dock_item(2, 3))
    p.wait(60)
    if restore:
        p.end(S.END_DONE)
        parts.append(p)
        S.write(os.path.join(d, 'SHELL.TST'), parts)
        return
    p.click(*S.dock_item(1, 2))
    p.end(S.END_STOP)
    parts.append(p)
    p = S.Part()
    p.wait(30)
    x, y = S.dock_item(1, 2)
    rclick(p, x, y)
    p.wait(20)
    if os.environ.get('DOCK_STOP') == 'menu':
        p.end(S.END_DONE)
        parts.append(p)
        S.write(os.path.join(d, 'SHELL.TST'), parts)
        return
    p.click(x - 8, (S.DOCK_ROW - 2) * 8 + 8)       # Quit
    p.wait(90)                                     # (the question's box)
    p.click(S.YES_X, S.YES_Y)
    p.wait(60)
    if shot2:
        p.end(S.END_DONE)
        parts.append(p)
        S.write(os.path.join(d, 'SHELL.TST'), parts)
        return
    x, y = S.dock_item(0, 1)
    rclick(p, x, y)
    p.wait(20)
    p.click(x - 8, (S.DOCK_ROW - 4) * 8 + 8)       # Quit (Unpin below it)
    p.wait(90)
    p.click(S.YES_X, S.YES_Y)
    p.wait(60)
    p.end(S.END_DONE)
    parts.append(p)
    S.write(os.path.join(d, 'SHELL.TST'), parts)


if __name__ == '__main__':
    main()
