#!/usr/bin/env python3
"""Gate gemini (tools/gate_gemini.sh; DECISIONS V128): the shell's script
(SHELL.TST, shell/play.s) for the Wikipedia launcher, in the card's layout
(the shell in /VERANDA, starting in /DOCUMENTS, which holds what
<folder>/DOCUMENTS holds: Wikipedia.cvt).

usage: gemini_launch.py <folder> probe|launch

  probe   the end (the shell's window with the launcher's tile: a
          screenshot)
  launch  Wikipedia.cvt double-clicked: the shell starts its parent
          application, Veranda Gemini (in /VERANDA/APPS), with it as its
          document; Veranda Gemini's test build plays GEMINI.TST and ends
          the run
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import shell_script as ss  # noqa: E402


def main():
    if len(sys.argv) != 3 or sys.argv[2] not in ('probe', 'launch'):
        sys.exit(__doc__)
    d, what = sys.argv[1:]
    docs = os.path.join(d, 'DOCUMENTS')
    names = os.listdir(docs)
    order = ['..'] + ss.listing([n for n in names if os.path.isdir(os.path.join(docs, n))],
                                [n for n in names if not os.path.isdir(os.path.join(docs, n))])
    p = ss.Part()
    p.wait(30)
    if what == 'launch':
        p.dbl(*ss.cell(order.index('Wikipedia.cvt')))
        p.end(ss.END_STOP)
    else:
        p.wait(30)
        p.end(ss.END_DONE)
    ss.write(os.path.join(d, 'SHELL.TST'), [p])


if __name__ == '__main__':
    main()
