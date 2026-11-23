#!/usr/bin/env python3
"""gate vb_debug: VeraBASIC Run's box when an error stops a program
(DECISIONS V97; V95 left it saying "stopped with an error: see the
console" with the console under the program's windows and the text past
the box). Writes <folder>/SHELL.TST (a double click on the program
document) and <folder>/box.ms (tests/vbasic/ui_mouse.py's script: wait,
then the emulator stops with the box up: its screenshot).

usage: runbox_script.py <folder> <document.cvt>

MIT licence (LICENSE)."""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
import shell_script as S  # noqa: E402


def main():
    d, name = sys.argv[1:3]
    dirs = [n for n in os.listdir(d) if os.path.isdir(os.path.join(d, n))]
    files = sorted(set([n for n in os.listdir(d) if not os.path.isdir(os.path.join(d, n))]
                       + ['SHELL.TST', 'SHELL.STP', 'console.txt', 'mouse.txt', 'box.ms']))
    root = S.listing(dirs, files)
    q = S.Part()
    q.wait(20)
    q.dbl(*S.cell(root.index(name)))
    q.end(S.END_STOP)
    S.write(os.path.join(d, 'SHELL.TST'), [q])
    open(os.path.join(d, 'box.ms'), 'w').write('pause 900\nexit\n')


if __name__ == '__main__':
    main()
