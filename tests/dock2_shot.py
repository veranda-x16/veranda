#!/usr/bin/env python3
"""The dock as a launcher's picture (tools/dock2_shots.sh; DECISIONS
V163): the shell's script (SHELL.TST) for a run in the card's layout (as
tests/sunroom_dock_script.py: the shell in /VERANDA, starting in
/DOCUMENTS, which holds the programs; "Veranda Write" and "Veranda
Gemini" are the switcher's test program, which puts itself aside).

usage: dock2_shot.py <folder>

  0  Paint pinned (options > pin), then Veranda Write, Veranda Calc,
     Veranda Edit, Veranda Claude, Veranda Ask, Solitaire and MOD Player
     dragged from the window onto the dock, each at its end; Veranda
     Write double-clicked: it starts, goes aside
  1  Veranda Gemini double-clicked: it starts, goes aside
  2  (the dock: eight pins, Write's dot, Gemini aside) Gemini selected,
     the end
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import shell_script as ss  # noqa: E402

PINS = ['Paint', 'Veranda Write', 'Veranda Calc', 'Veranda Edit', 'Veranda Claude', 'Veranda Ask',
        'Solitaire', 'MOD Player']


def main():
    d = sys.argv[1]
    docs = os.path.join(d, 'DOCUMENTS')
    names = os.listdir(docs)
    order = ['..'] + ss.listing([n for n in names if os.path.isdir(os.path.join(docs, n))],
                                [n for n in names if not os.path.isdir(os.path.join(docs, n))])
    pins = [n for n in PINS if n + '.cvt' in names]
    parts = []
    p = ss.Part()
    p.wait(30)
    for k, n in enumerate(pins):
        a = ss.cell(order.index(n + '.cvt'))
        if not k:
            p.click(*a)
            p.wait(10)
            p.menu('options', 'pin')
        else:
            x, y = ss.dock_item(k - 1, k)
            p.drag(a, (x + 12, y))
        p.wait(40)
    p.dbl(*ss.cell(order.index('Veranda Write.cvt')))
    p.end(ss.END_STOP)
    parts.append(p)
    p = ss.Part()
    p.wait(40)
    p.dbl(*ss.cell(order.index('Veranda Gemini.cvt')))
    p.end(ss.END_STOP)
    parts.append(p)
    p = ss.Part()
    p.wait(40)
    p.click(*ss.cell(order.index('Veranda Gemini.cvt')))
    p.wait(60)
    p.end(ss.END_DONE)
    parts.append(p)
    ss.write(os.path.join(d, 'SHELL.TST'), parts)


if __name__ == '__main__':
    main()
