#!/usr/bin/env python3
"""Veranda Look 3's pictures (tools/look3_shots.sh; DECISIONS V132, V133):
the shell's script (SHELL.TST) for a run in the card's layout (the shell
in /VERANDA, starting in /DOCUMENTS).

usage: look3_script.py <folder> icons|list|small|menu|about [<name to select>]

  icons   the named icon selected (window 0, icon view), the end
  list    the same, then View > By name (the list), the end
  small   the same, then View > By small icon (V151), the end
  menu    the same, then the File menu opened (pressed on its name,
          released in it), the end with it open
  about   Veranda > About, the end with its box open
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import shell_script as ss  # noqa: E402


def main():
    if len(sys.argv) not in (3, 4):
        sys.exit(__doc__)
    d, what = sys.argv[1:3]
    docs = os.path.join(d, 'DOCUMENTS')
    names = os.listdir(docs)
    order = ['..'] + ss.listing([n for n in names if os.path.isdir(os.path.join(docs, n))],
                                [n for n in names if not os.path.isdir(os.path.join(docs, n))])
    p = ss.Part()
    p.wait(30)
    if len(sys.argv) == 4 and what != 'about':
        p.click(*ss.cell(order.index(sys.argv[3])))
        p.wait(20)
    if what == 'list':
        p.menu('view', 'name')
    elif what == 'small':
        p.menu('view', 'small')
    elif what == 'menu':
        x = ss.MENU_X['file']
        p.at(x, 7, 0, 4)
        p.at(x, 7, 1, 2)
        p.at(x, 60, 0, 60)                  # (released in it: it stays open)
    elif what == 'about':
        p.menu('geos', 'about')
        p.wait(40)
    p.wait(30)
    p.end(ss.END_DONE)
    ss.write(os.path.join(d, 'SHELL.TST'), [p])


if __name__ == '__main__':
    main()
