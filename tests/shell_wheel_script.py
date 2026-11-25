#!/usr/bin/env python3
"""Gate shell, the mouse wheel in the desktop's windows (DECISIONS V185):
the run folder and SHELL.TST (shell/play.s: a record with flags bit 4
turns the wheel by its key byte's notches; tests/shell_script.py's
records).

usage: shell_wheel_script.py make <folder> [apps]   the fixtures
       shell_wheel_script.py script <folder> <view> <run>
                                                    SHELL.TST
       shell_wheel_script.py check <console> <view> <run> <cols>
                                                    the console's pages
       shell_wheel_script.py same <ref dump> <dump>
                                                    window 0's pixels equal

The fixtures: /VERANDA/APPS (a package's APPS folder copied when given,
else 36 stub documents: more than a window shows in either view), an
empty /DOCUMENTS (the shell starts there), LIST.DEF (the list) for view
list.

<view> list (LIST.DEF: the windows open in the list) or icon (none); <run>:
  ref   Apps opened (window 0's sidebar), the pointer over its contents,
        the end (the dump: the first page)
  down  as ref, then one notch down, the end (the dump: scrolled)
  both  as ref, then: a notch up at the top (nothing: clamped), a notch
        down, a notch up, the pointer over the desktop beside the window
        and below it (the dock's place): a notch down each (nothing:
        no window there);
        the end (the dump: the first page again)
check: the view_page lines (SHELL PAGE 0 FIRST n) after Apps opened: down:
3 rows a notch in the list (FIRST 1, 2, 3), a row of icons (<cols>) in
the icons; both: the same down, then back up to FIRST 0, nothing else.
"""
import os
import re
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import shell_script as S  # noqa: E402
import shell_trash_script as T  # noqa: E402

BODY = (300, 250)               # window 0's contents (S.WIN0: 16-495, 32-399)
DESK = (560, 300)               # the desktop right of window 0 (no icon there)
DOCK = (320, 452)               # below window 0 (the dock's place; no pins: the desktop)


def make(d, apps):
    a = os.path.join(d, 'VERANDA', 'APPS')
    os.makedirs(a, exist_ok=True)
    os.makedirs(os.path.join(d, 'DOCUMENTS'), exist_ok=True)
    if apps:
        for n in os.listdir(apps):
            shutil.copy(os.path.join(apps, n), a)
    else:
        for i in range(36):
            n = 'Stub %02d' % i
            open(os.path.join(a, n + '.cvt'), 'wb').write(T.doc(n))


def wheel(p, n, gap=40):
    p.recs.append((p.f, 0, 0, 0x10, n & 255))
    p.f += gap


def script(d, view, run, listdef):
    p = S.Part()
    p.wait(30)
    if view == 'icon' and listdef:
        os.remove(os.path.join(d, 'LIST.DEF'))
    if view == 'list':
        open(os.path.join(d, 'LIST.DEF'), 'wb').close()
    p.click(*S.place(1))                        # Apps
    p.wait(60)
    p.at(*BODY, 0, 20)
    if run in ('down', 'both'):
        if run == 'both':
            wheel(p, -1)                        # at the top: nothing
        wheel(p, 1)
    if run == 'both':
        wheel(p, -1)
        p.at(*DESK, 0, 20)
        wheel(p, 1)
        p.at(*DOCK, 0, 20)
        wheel(p, 1)
        p.at(*BODY, 0, 20)
    p.wait(30)
    p.end(S.END_DONE)
    S.write(os.path.join(d, 'SHELL.TST'), [p])


def pages(console):
    txt = open(console, 'rb').read().decode('latin-1').replace('\r', '\n')
    return [int(m) for m in re.findall(r'SHELL PAGE 0 FIRST (\d+)', txt)]


def check(console, view, run, cols):
    got = pages(console)
    down = [1, 2, 3] if view == 'list' else [cols]
    want = {'ref': [], 'down': down, 'both': down + ([2, 1, 0] if view == 'list' else [0])}[run]
    if got != want:
        sys.exit('shell_wheel_script: %s %s: the first entries %s, not %s' % (view, run, got, want))
    if 'SHELL DONE' not in open(console, 'rb').read().decode('latin-1'):
        sys.exit('shell_wheel_script: %s %s: the session did not end' % (view, run))
    print('shell_wheel_script: %s %s: the first entries %s' % (view, run, got or 'unchanged'))


VRAM = 131072


def same(ref, dump):
    a, b = open(ref, 'rb').read(), open(dump, 'rb').read()
    tail = VRAM + 256 + 512 + 14 + 1024
    a, b = a[-tail:], b[-tail:]
    x0, y0, x1, y1 = S.WIN0
    diff = [(x, y) for y in range(y0, y1 + 1) for x in range(x0 // 8, x1 // 8 + 1)
            if a[y * 80 + x] != b[y * 80 + x]]
    if diff:
        sys.exit('shell_wheel_script: window 0 differs from the first page in %d bytes (from card %d, line %d)'
                 % (len(diff), diff[0][0], diff[0][1]))
    print('shell_wheel_script: window 0 pixel for pixel as before the wheel')


def main():
    a = sys.argv[1:]
    if len(a) >= 2 and a[0] == 'make':
        make(a[1], a[2] if len(a) > 2 else None)
    elif len(a) == 4 and a[0] == 'script':
        script(a[1], a[2], a[3], os.path.exists(os.path.join(a[1], 'LIST.DEF')))
    elif len(a) == 5 and a[0] == 'check':
        check(a[1], a[2], a[3], int(a[4]))
    elif len(a) == 3 and a[0] == 'same':
        same(a[1], a[2])
    else:
        sys.exit(__doc__)


if __name__ == '__main__':
    main()
