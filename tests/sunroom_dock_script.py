#!/usr/bin/env python3
"""Look 3 "Sunroom", stage E's pictures (tools/sunroom_shots.sh;
DECISIONS V152, V153): the shell's script (SHELL.TST) for a run in the
card's layout (the shell in /VERANDA, starting in /DOCUMENTS, which holds
the mockup's programs; "Veranda Write" and "Veranda Gemini" are the
switcher's test program, tests/switch_app.s, under those names: it puts
itself aside ten main loop passes after it starts).

usage: sunroom_dock_script.py <folder> [<name to select at the end>]

  0  Paint, Veranda Write, Veranda Calc, Solitaire pinned (options >
     pin); Veranda Write double-clicked: it starts, goes aside
  1  Veranda Gemini double-clicked: it starts, goes aside
  2  (the dock: four pins, Veranda Write's and Gemini's dots) the named
     icon selected, the end
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import shell_script as ss  # noqa: E402


def main():
    if len(sys.argv) not in (2, 3):
        sys.exit(__doc__)
    d = sys.argv[1]
    docs = os.path.join(d, 'DOCUMENTS')
    names = os.listdir(docs)
    order = ['..'] + ss.listing([n for n in names if os.path.isdir(os.path.join(docs, n))],
                                [n for n in names if not os.path.isdir(os.path.join(docs, n))])
    parts = []
    p = ss.Part()
    p.wait(30)
    for n in ('Paint.cvt', 'Veranda Write.cvt', 'Veranda Calc.cvt', 'Solitaire.cvt'):
        p.click(*ss.cell(order.index(n)))
        p.wait(10)
        p.menu('options', 'pin')
        p.wait(20)
    p.dbl(*ss.cell(order.index('Veranda Write.cvt')))
    p.end(ss.END_STOP)
    parts.append(p)
    p = ss.Part()
    p.wait(30)
    p.dbl(*ss.cell(order.index('Veranda Gemini.cvt')))
    p.end(ss.END_STOP)
    parts.append(p)
    p = ss.Part()
    p.wait(40)
    if len(sys.argv) == 3:
        p.click(*ss.cell(order.index(sys.argv[2])))
        p.wait(20)
    p.wait(30)
    p.end(ss.END_DONE)
    parts.append(p)
    ss.write(os.path.join(d, 'SHELL.TST'), parts)


if __name__ == '__main__':
    main()
