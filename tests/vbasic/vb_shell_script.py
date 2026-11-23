#!/usr/bin/env python3
"""Gate vb_tok (DECISIONS V87): the shell opens VeraBASIC programs with
VeraBASIC Run. Writes <folder>/SHELL.TST (tests/shell_script.py's records)
for a run whose top folder holds the shell, VeraBASIC Run's test build
(as "VeraBASIC Run.cvt": started with a document it runs it, logs its
console and goes back to the shell) and:

  DOC1  a program document (vbasic.py build): its parent class VBRun
  Docs/DOC2  another in a folder: Run is found in the top folder
(a .bas file opens in VeraBASIC, the editor, since V93: gate vb_ide)

usage: vb_shell_script.py <folder> [<extra name>...]
       vb_shell_script.py --want     the console lines expected
       vb_shell_script.py --names    the four programs' names (logs)

The parts:
  0  double-click DOC1 (Run in the same folder, by its class)
  1  open Docs, double-click DOC2 there
  2  the end (SHELL DONE, a VRAM dump)

MIT licence (LICENSE).
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
import shell_script as S  # noqa: E402

DOC1 = 'Bird Watch from the lake.cvt'
DOC2 = 'Squares and a table of them.cvt'
NAMES = [DOC1[:-4], DOC2[:-4]]


def want():
    out = []
    for n in NAMES:
        out += ['SHELL STARTED', 'VB RUN ' + n, 'VB END', 'VB DONE']
    return out + ['SHELL STARTED', 'SHELL DONE']


def main():
    if sys.argv[1] == '--want':
        print('\n'.join(want()))
        return
    if sys.argv[1] == '--names':
        print('\n'.join(NAMES))
        return
    d = sys.argv[1]
    dirs = [n for n in os.listdir(d) if os.path.isdir(os.path.join(d, n))]
    files = sorted(set([n for n in os.listdir(d) if not os.path.isdir(os.path.join(d, n))]
                       + ['SHELL.TST', 'SHELL.STP'] + sys.argv[2:]))
    root = S.listing(dirs, files)
    docs = S.listing([], sorted(os.listdir(os.path.join(d, 'Docs'))))
    parts = []
    p = S.Part()
    p.wait(20)
    p.dbl(*S.cell(root.index(DOC1)))
    p.end(S.END_STOP)
    parts.append(p)
    p = S.Part()
    p.wait(20)
    p.dbl(*S.cell(root.index('Docs')))
    p.wait(30)
    p.dbl(*S.cell(1 + docs.index(DOC2)))         # (after "..")
    p.end(S.END_STOP)
    parts.append(p)
    p = S.Part()
    p.wait(30)
    p.end(S.END_DONE)
    parts.append(p)
    S.write(os.path.join(d, 'SHELL.TST'), parts)


if __name__ == '__main__':
    main()
