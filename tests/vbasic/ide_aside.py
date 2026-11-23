#!/usr/bin/env python3
"""gate vb_ide: the switcher with VeraBASIC (one application, the editor
and its program): Alt+Tab puts it aside while the editor shows and again
while a program runs; the test desktop (tests/vbasic/vb_desk.s as
SHELL.cvt) brings it back each time. Writes IDE.PLY into CARD.

usage: ide_aside.py CARD

The states the console must show (tools/gate_vb_ide.sh): 1 the text typed;
DESK RESUME; 2 the same text, the cursor where it was; Run, the program
counting; DESK RESUME; Ctrl+C: 3 stopped in its loop.
MIT licence (LICENSE)."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ide_play import Play, TAB, ALT  # noqa: E402

PROG = ['n = 0', 'DO', 'n = n + 1', 'LOOP']


def main():
    p = Play()
    p.W(120)
    for t in PROG[:-1]:
        p.line(t)
    p.T(PROG[-1])
    p.L(1)
    p.K(TAB, ALT)                       # aside: the desktop brings it back
    p.W(120)
    p.L(2)
    p.ctrl('r')
    p.W(60)
    p.K(TAB, ALT)                       # aside while the program runs
    p.W(120)
    p.ctrl('c')
    p.W(60)
    p.L(3)
    p.W(20)
    p.stop()
    open(os.path.join(sys.argv[1], 'IDE.PLY'), 'wb').write(p.data())


if __name__ == '__main__':
    main()
