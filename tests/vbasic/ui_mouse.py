#!/usr/bin/env python3
"""gate vb_ui: a session's mouse script (x16emu -mousescript, the emulator's
branch mousescript: real PS/2 packets through the KERNAL's mouse_scan) from
a test's NAME.ms.

usage: ui_mouse.py NAME.ms vbrun.map OUT.txt

NAME.ms, a command a line ('#' a comment):
    ready             wait until the program waits for events, none queued
    events N          wait until N handlers (not the timers') have started,
                      then ready
    waitmem A V       wait until main RAM's byte at A (hex) is V
    dialog N          wait until dialog box N is up (vbx.s _vx_dlg: the boxes
                      of a program counted from 1)
    dpc N             wait until the program has passed N event points
    click X Y [B]     the pointer to X, Y (screen pixels), button B (1 left,
                      2 right) down and up
    press X Y [B]     down only; release [B]: up; drag X Y: move with it held
    move X Y          the pointer to X, Y
    wheel N           a wheel movement (-8 .. 7)
    type TEXT         keys, as typed
    pause F           F frames
    hold F            F frames, kept before a wait that follows (pause's
                      frames count only for the next move or click)
    bar NAME ...      the menu bar's texts (the first: the program's name)
    pick M I [F]      a click on bar item M, then (F frames later: 20) on its
                      menu's item I
    open M            a click on bar item M (its menu stays open)
    home              the pointer's place not known: the next move goes
                      to 0, 0 first (after a program, a dialog box or a
                      menu moved it)
    exit              the emulator stops (its dumps)
    name TEXT         wait until the program's docname (main.c: its name, a
                      made application's) starts with TEXT (2 characters)
    map FILE          the addresses (ready, events ...) from another
                      program's map from here on (a session that goes
                      from one program to another: gate vb_app)
The pointer starts at 0, 0 (a move of -2000, -2000); the program's
_vx_idle and _vx_evn (vbx.s) are read from the map. MIT licence (LICENSE).
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)) + '/..')
import look_menu  # noqa: E402


def addr(mapfile, name):
    m = re.search(r'^%s\s+([0-9A-F]{6})' % name, open(mapfile).read(), re.M)
    if not m:
        m = re.search(r'\b%s\s+([0-9A-F]{6})' % name, open(mapfile).read())
    if not m:                   # (not imported by another module: the label file)
        lbl = os.path.splitext(mapfile)[0] + '.lbl'
        m = re.search(r'^al ([0-9A-F]{6}) \.%s$' % name, open(lbl).read(), re.M)
    return int(m.group(1), 16)


def main(argv):
    src, mapfile, out = argv
    mp = mapfile                # (map: another program's)
    idle, evn = addr(mapfile, '_vx_idle'), addr(mapfile, '_vx_evn')
    dlg = addr(mapfile, '_vx_dlg')
    dpc = idle - 2                  # (vbx.s: _vx_dpc, then _vx_idle)
    lines = ['0 id 3']
    f = [80]                    # the frame (since the last wait)
    pos = [-1000, 0]             # (not known: to 0, 0 before the first move)
    bar = []

    def at(cmd, gap=4):
        f[0] += gap
        lines.append('%d %s' % (f[0], cmd))

    def wait(a, v):
        lines.append('wait %04X %X' % (a, v))   # (both hex)
        f[0] = 0

    def move(x, y):
        if pos[0] < 0:
            at('move -2000 -2000', 2)
            pos[:] = [0, 0]
        dx, dy = x - pos[0], y - pos[1]
        while dx or dy:
            sx = max(-100, min(100, dx))
            sy = max(-100, min(100, dy))
            at('move %d %d' % (sx, sy), 2)
            dx -= sx
            dy -= sy
        pos[:] = [x, y]
        f[0] += 4

    def click(x, y, b=1):
        move(x, y)
        at('down %d' % b)
        at('up %d' % b, 6)
        f[0] += 6

    for ln in open(src):
        ln = ln.split('#', 1)[0].strip()
        if not ln:
            continue
        w = ln.split()
        c = w[0]
        if c == 'map':
            mp = ln.split(None, 1)[1]
            idle, evn, dlg = addr(mp, '_vx_idle'), addr(mp, '_vx_evn'), addr(mp, '_vx_dlg')
            dpc = idle - 2
        elif c == 'name':
            dn = addr(mp, '_docname')
            for k, ch in enumerate(w[1][:2]):
                wait(dn + k, ord(ch))
        elif c == 'ready':
            wait(idle, 1)
        elif c == 'dpc':
            wait(dpc, int(w[1]))
        elif c == 'dialog':
            wait(dlg, int(w[1]))
            f[0] = 20
        elif c == 'waitmem':
            wait(int(w[1], 16), int(w[2]))
        elif c == 'events':
            wait(evn, int(w[1]) & 255)
            wait(idle, 1)
        elif c == 'click':
            click(int(w[1]), int(w[2]), int(w[3]) if len(w) > 3 else 1)
        elif c == 'press':
            move(int(w[1]), int(w[2]))
            at('down %d' % (int(w[3]) if len(w) > 3 else 1))
        elif c == 'release':
            at('up %d' % (int(w[1]) if len(w) > 1 else 1))
        elif c in ('drag', 'move'):
            move(int(w[1]), int(w[2]))
        elif c == 'wheel':
            at('wheel %d' % int(w[1]))
        elif c == 'type':
            at('type ' + ln.split(None, 1)[1], 4)
            f[0] += 30
        elif c == 'pause':
            f[0] += int(w[1])
        elif c == 'hold':
            at('id 3', int(w[1]))      # (a line of no effect at that frame)
        elif c == 'bar':
            bar = re.findall(r'"([^"]*)"', ln)
        elif c in ('pick', 'open'):
            xs = look_menu.bar(bar, ui=True)
            m = int(w[1])
            click((xs[m][0] + xs[m][1]) // 2, 8)
            f[0] += int(w[3]) if c == 'pick' and len(w) > 3 else 20
            if c == 'pick':
                # the pointer stays on the title (V137): down to item I's
                # middle
                move((xs[m][0] + xs[m][1]) // 2, look_menu.item_y(int(w[2])))
                at('down 1')
                at('up 1', 6)
                f[0] += 20
                # (not known after the item: back to 0, 0 before the next
                # move, as before V137; gate vb_quit's click on the
                # program's close glyph after Run > Run missed without it)
                pos[0] = -1000
        elif c == 'home':
            pos[:] = [-1000, 0]
        elif c == 'exit':
            at('exit', 30)
        else:
            raise SystemExit('%s: %s?' % (src, ln))
    open(out, 'w').write('\n'.join(lines) + '\n')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
