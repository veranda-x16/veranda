#!/usr/bin/env python3
"""Gate switch, the dock as a launcher (DECISIONS V163): sessions of the
shell (tests/shell_script.py's records) with test programs PinA ... PinK
(tests/shell_app.s: each logs "APP 1 RAN" and returns to the shell), run
by tests/dock_gate.sh.

usage: dock2_script.py <folder> drag|full|old|prefs|defaults
       dock2_script.py --want drag|full|old|prefs|defaults   the console lines expected
       dock2_script.py --dsk <file> <version> <dir> <name>...   a desk file with those pins
       dock2_script.py --prefs <out dir>    <out>/prefsdock/da_script.h (Preferences' Dock page)

drag (the top folder; SHELL.DSK version 4, no pins):
  0  PinA pinned (Options > Pin); PinB dragged from the window onto the
     dock left of it, PinC right of the pins: B, A, C; PinC dragged along
     the dock to the front: C, B, A; PinB dragged off the dock (onto the
     desktop): unpinned; PinA dragged onto the dock's trash: unpinned (the
     files stay); PinD dropped at the end, PinC (pinned already) dropped
     after it: D, C; PinA double-clicked: it runs, the shell again
  1  (a restart) the dock read back: D, C; PinC clicked in the dock: it
     starts (one click), the shell again
  2  the end
full: SHELL.DSK version 4 with ten pins (PinA ... PinJ), PinK dropped on
  the dock: "SHELL DOCK FULL", the box's OK; the end (the dock's picture)
old: SHELL.DSK version 3 with four pins (PinA ... PinD): the dock shows them
prefs (the card's layout: the shell in /VERANDA, starting in /DOCUMENTS,
  which holds PinA, PinB and Preferences): /VERANDA/APPS holds PinK,
  /VERANDA/.SYSTEM/SHELL.DSK pins PinA and PinB; Preferences (its test build, the Dock page: Add..., PinK, Move up,
  Save, close) changes them: the dock shows A, K, B when it closes; PinA
  double-clicked: it runs; the shell again (a restart): A, K, B still
defaults: no SHELL.DSK, PINS.DEF (the gates' leave), /VERANDA/APPS with
  "Veranda Edit", Paint and Term: those three pinned
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import shell_script as S  # noqa: E402

HDR = 16 + 61 + 2
PSZ = 62 + 68
OFF = (600, 300)                # the desktop, off the dock and the windows


def dsk(path, version, d, names):
    b = bytearray(HDR)
    b[0:4] = b'VSD' + bytes([version])
    b[4] = 0                    # (no window places for this mode)
    b[16] = ord('/')
    b[HDR - 1] = len(names)
    for n in (names if version == 4 else (names + [''] * 4)[:4]):
        p = bytearray(PSZ)
        if n:
            p[0:len(d)] = d.encode()
            p[62:62 + len(n) + 4] = (n + '.cvt').encode()
        b += p
    os.makedirs(os.path.dirname(path) or '.', exist_ok=True)
    open(path, 'wb').write(bytes(b))


def want(run):
    if run == 'drag':
        return ['SHELL STARTED', 'SHELL PINNED PinA.cvt', 'SHELL PINNED PinB.cvt', 'SHELL PINNED PinC.cvt',
                'SHELL DOCK MOVED PinC.cvt', 'SHELL UNPINNED PinB.cvt', 'SHELL UNPINNED PinA.cvt',
                'SHELL PINNED PinD.cvt', 'SHELL PINNED PinC.cvt', 'APP 1 RAN', 'SHELL STARTED',
                'SHELL DOCK PinD, PinC', 'SHELL DOCK START PinC', 'APP 1 RAN', 'SHELL STARTED', 'SHELL DONE']
    if run == 'full':
        return ['SHELL STARTED', 'SHELL DOCK ' + ', '.join('Pin' + c for c in 'ABCDEFGHIJ'),
                'SHELL DOCK FULL', 'SHELL DONE']
    if run == 'old':
        return ['SHELL STARTED', 'SHELL DOCK PinA, PinB, PinC, PinD', 'SHELL DONE']
    if run == 'prefs':
        return ['SHELL STARTED', 'SHELL DOCK PinA, PinB', 'PREFS DOCK PAGE', 'PREFS DOCK PinA, PinB',
                'PREFS DOCK PinA, PinB, PinK', 'PREFS DOCK PinA, PinK, PinB', 'PREFS DOCK SAVED',
                'PREFS CLOSED', 'SHELL DOCK PinA, PinK, PinB', 'APP 1 RAN', 'SHELL STARTED',
                'SHELL DOCK PinA, PinK, PinB', 'SHELL DONE']
    if run == 'defaults':
        return ['SHELL STARTED', 'SHELL PINS DEFAULT 3', 'SHELL DOCK Veranda Edit, Paint, Term', 'SHELL DONE']
    sys.exit('dock2_script: no run ' + run)


def root(d, extra=()):
    dirs = [n for n in os.listdir(d) if os.path.isdir(os.path.join(d, n))]
    files = sorted(set([n for n in os.listdir(d) if not os.path.isdir(os.path.join(d, n))]
                       + ['SHELL.TST', 'SHELL.STP', 'console.txt'] + list(extra)))
    return S.listing(dirs, files)


def left(i, n):
    x, y = S.dock_item(i, n)
    return x - 12, y


def right(i, n):
    x, y = S.dock_item(i, n)
    return x + 12, y


def main():
    a = sys.argv[1:]
    if a[0] == '--want':
        print('\n'.join(want(a[1])))
        return
    if a[0] == '--dsk':
        dsk(a[1], int(a[2]), a[3], a[4:])
        return
    if a[0] == '--prefs':
        import da_script as da
        f = 40
        f = da.click(f, da.PX + 16 + 28, da.PY + 400 - 24 + 8, c='the Dock page', wait=40)
        f = da.click(f, da.PX + 320 + 68, da.PY + 32 + 8, c='Add...: the applications of /VERANDA/APPS', wait=80)
        f = da.click(f, da.PX + 16 + 20, da.PY + 32 + 20 + 11, c='the first: PinK', wait=40)
        da.shots.append(('dock', f))
        f = da.click(f, da.PX + 320 + 68, da.PY + 32 + 2 * 24 + 8, c='Move up', wait=40)
        f = da.click(f, *da.PSAVE, c='Save: SHELL.DSK', wait=400)
        f = da.click(f + 20, da.PX + 480 - 11, da.PY + 8, c='the close glyph: RstrAppl', wait=60)
        da.L.append('END(%d)' % (f + 20000))
        da.write(os.path.join(da.sub(a[1], 'prefsdock'), 'da_script.h'), "Preferences' Dock page")
        return
    d, run = a[0], a[1]
    if run == 'prefs':          # (the card's layout: the shell in /VERANDA, starting in /DOCUMENTS)
        docs = os.path.join(d, 'DOCUMENTS')
        o = ['..'] + S.listing([], sorted(os.listdir(docs)))
    else:
        o = root(d)
    parts = []
    p = S.Part()
    p.wait(20)
    if run == 'drag':
        p.click(*S.cell(o.index('PinA.cvt')))
        p.menu('options', 'pin')
        p.wait(30)
        p.drag(S.cell(o.index('PinB.cvt')), left(0, 1))
        p.wait(30)
        p.drag(S.cell(o.index('PinC.cvt')), right(1, 2))
        p.wait(30)
        p.drag(S.dock_item(2, 3), left(0, 3))
        p.wait(30)
        p.drag(S.dock_item(1, 3), OFF)
        p.wait(30)
        p.drag(S.dock_item(1, 2), S.dock_item(2, 2))       # the trash
        p.wait(30)
        p.drag(S.cell(o.index('PinD.cvt')), right(0, 1))
        p.wait(30)
        p.drag(S.cell(o.index('PinC.cvt')), right(1, 2))
        p.wait(30)
        p.dbl(*S.cell(o.index('PinA.cvt')))
        p.end(S.END_STOP)
        parts.append(p)
        p = S.Part()
        p.wait(30)
        p.click(*S.dock_item(1, 2))
        p.end(S.END_STOP)
        parts.append(p)
        p = S.Part()
        p.wait(30)
    elif run == 'full':
        p.drag(S.cell(o.index('PinK.cvt')), right(9, 10))
        p.wait(30)
        p.click(S.YES_X, S.YES_Y)       # the box's OK
        p.wait(60)
    elif run == 'prefs':
        p.dbl(*S.cell(o.index('Preferences.cvt')))
        p.wait(1500)
        p.dbl(*S.cell(o.index('PinA.cvt')))
        p.end(S.END_STOP)
        parts.append(p)
        p = S.Part()
        p.wait(30)
    else:
        p.wait(40)
    p.end(S.END_DONE)
    parts.append(p)
    S.write(os.path.join(d, 'SHELL.TST'), parts)


if __name__ == '__main__':
    main()
