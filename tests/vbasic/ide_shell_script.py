#!/usr/bin/env python3
"""gate vb_ide: the shell opens a .bas file with VeraBASIC, the editor
(documents = BAS; DECISIONS V93), not VeraBASIC Run, which is in the
folder too and no longer says BAS. Writes <folder>/SHELL.TST (tests/shell_script.py's records: a
double click on the long-named .bas, then the end) and IDE.PLY for the
editor's test build (its state logged, the document's name in it; Ctrl+Q:
back to the shell).

usage: ide_shell_script.py <folder> <extra name>...
MIT licence (LICENSE)."""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import shell_script as S  # noqa: E402
from ide_play import Play  # noqa: E402

BAS = 'Hello from VeraBASIC on the card.bas'


def main():
    d = sys.argv[1]
    p = Play()
    p.W(120)
    p.L(1)
    p.W(20)
    p.ctrl('q')
    p.W(250)                            # (the shell takes the pointer's place)
    open(os.path.join(d, 'IDE.PLY'), 'wb').write(p.data())
    dirs = [n for n in os.listdir(d) if os.path.isdir(os.path.join(d, n))]
    files = sorted(set([n for n in os.listdir(d) if not os.path.isdir(os.path.join(d, n))]
                       + ['SHELL.TST', 'SHELL.STP'] + sys.argv[2:]))
    root = S.listing(dirs, files)
    parts = []
    q = S.Part()
    q.wait(20)
    q.dbl(*S.cell(root.index(BAS)))
    q.end(S.END_STOP)
    parts.append(q)
    q = S.Part()
    q.wait(30)
    q.end(S.END_DONE)
    parts.append(q)
    S.write(os.path.join(d, 'SHELL.TST'), parts)


if __name__ == '__main__':
    main()
