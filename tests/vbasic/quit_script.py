#!/usr/bin/env python3
"""gate vb_quit (DECISIONS V95): a program started from the shell and
quit, then the shell must come back. Writes <folder>/SHELL.TST (a double
click on the program's file, then at the shell's next start SHELL DONE)
and <folder>/quit.ms (tests/vbasic/ui_mouse.py's script for the program).

usage: quit_script.py <folder> <program> <path> <way>

<program>  bird1 .. bird7 (tests/vbasic/ui), notes, dice, addressbook,
           tiles (docs/vbasic/examples): the folder holds it as
           NAME.bas (path ide) or NAME.cvt (path run)
<path>     ide: the .bas double-clicked opens VeraBASIC, the editor; Run >
           Run; the program quit; then the editor's File > Quit
           run: the program document double-clicked opens VeraBASIC Run
<way>      close: the window's close glyph (ON CLOSE's handler ENDs)
           item: the program's own Quit item (its handler ENDs)
           stop: Run > Stop (the editor) or Program > Stop (VeraBASIC Run:
           its box "stopped", OK), as Ctrl+C
           quit: VeraBASIC Run > Quit while the program runs (run only)
The ways a program has: ways(program, path). MIT licence (LICENSE)."""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
import shell_script as S  # noqa: E402

# the window #1's place in cards (x, y, w) and the program's menus: the
# bar's names and its Quit item (menu, item), or None
BIRD = (10, 6, 60)
PROGS = {
    'bird1': (BIRD, None, None),
    'notes': ((4, 4, 72), ['Notes', 'File', 'Edit'], (1, 3)),
    'dice': (BIRD, None, None),
    'addressbook': ((4, 4, 72), ['Address book', 'File'], (1, 2)),
    'tiles': ((2, 2, 76), None, None),
}
for n in range(2, 8):
    PROGS['bird%d' % n] = (BIRD, ['Bird Watch', 'File', 'Birds'] if n > 2 else ['Bird Watch', 'File'], (1, 0))
IDE_BAR = ['VeraBASIC', 'File', 'Edit', 'Search', 'Run', 'Help']
IDE_RUNBAR = ['VeraBASIC', 'Run']           # while a program without menus runs
RUN_BAR = ['VeraBASIC Run', 'Program']
# VeraBASIC Run's message box (main.c message()): its OK icon's middle
OK_X, OK_Y = 383, 271


def ways(prog, path):
    _, bar, item = PROGS[prog]
    w = ['close']
    if item:
        w.append('item')
    if not bar:                     # the runtime's own bar is there
        w.append('stop')
        if path == 'run':
            w.append('quit')
    return w


def bar_line(names):
    return 'bar ' + ' '.join('"%s"' % n for n in names)


def script(prog, path, way):
    (wx, wy, ww), bar, item = PROGS[prog]
    m = []
    if path == 'ide':
        m += ['pause 1500', bar_line(IDE_BAR), 'pick 4 0']
    else:
        m += ['pause 400']
    m += ['ready', 'pause 30']
    if way == 'close':
        m.append('click %d %d' % ((wx + ww) * 8 - 12, wy * 8 + 7))
    elif way == 'item':
        m += [bar_line(bar), 'pick %d %d' % item]
    elif way == 'stop':
        m += [bar_line(IDE_RUNBAR if path == 'ide' else RUN_BAR), 'pick 1 0']
        if path == 'run':           # "stopped with an error": its box's OK
            m += ['pause 200', 'home', 'click %d %d' % (OK_X, OK_Y)]
    elif way == 'quit':
        m += [bar_line(RUN_BAR), 'pick 0 2']
    else:
        sys.exit('quit_script: no way %s' % way)
    m.append('pause 300')
    if path == 'ide':               # the editor's File > Quit
        m += ['home', bar_line(IDE_BAR), 'pick 1 6']    # (Quit: the seventh item since V99)
    m.append('pause 900')
    return '\n'.join(m) + '\n'


def main():
    if len(sys.argv) == 3 and sys.argv[1] == '--ways':
        for p in PROGS:
            for w in ways(p, sys.argv[2]):
                print(p, w)
        return
    if len(sys.argv) != 5:
        sys.exit(__doc__)
    d, prog, path, way = sys.argv[1:]
    if way not in ways(prog, path):
        sys.exit('quit_script: %s has no way %s on path %s' % (prog, way, path))
    name = prog + ('.bas' if path == 'ide' else '.cvt')
    dirs = [n for n in os.listdir(d) if os.path.isdir(os.path.join(d, n))]
    files = sorted(set([n for n in os.listdir(d) if not os.path.isdir(os.path.join(d, n))]
                       + ['SHELL.TST', 'SHELL.STP', 'console.txt', 'mouse.txt', 'quit.ms']))
    root = S.listing(dirs, files)
    q = S.Part()
    q.wait(20)
    q.dbl(*S.cell(root.index(name)))
    q.end(S.END_STOP)
    q2 = S.Part()
    q2.wait(30)
    q2.end(S.END_DONE)
    S.write(os.path.join(d, 'SHELL.TST'), [q, q2])
    open(os.path.join(d, 'quit.ms'), 'w').write(script(prog, path, way))


if __name__ == '__main__':
    main()
