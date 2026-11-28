#!/usr/bin/env python3
"""gate vb_ide: a click on an empty line (DECISIONS V216).

usage: ide_blank.py CARD          the session's files (IDE.PLY, the program)
       ide_blank.py check CARD    what it left: the saved program, the states

A program of 200 lines, every fourth empty, opened; clicks on empty lines
(past their end: the cursor at the line's start) with the view at the top,
after the wheel and after the scroll bar's arrow, a character typed at each:
the text must change at that line and nowhere else. (textkit's gb_at_col
kept the position before a character in t3, which the reader's first read
of a run clobbers: a line's LF first, an empty line, gave a position far
away, and the typing went there.)
MIT licence (LICENSE).
"""
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ide_play import Play, RET  # noqa: E402

NAME = 'Blank lines.bas'
N = 200
ROWS, TY, SB_X = 54, 32, 78


def main(card):
    lines = [('' if i % 4 == 3 else 'REM line %03d' % (i + 1)) for i in range(N)] + ['']
    open(os.path.join(card, NAME), 'w', encoding='latin-1', newline='\n').write('\n'.join(lines))
    p = Play()
    states = {}
    m = {'line': 0, 'col': 0}

    def L(n):
        p.L(n)
        states[n] = [m['line'] + 1, m['col'] + 1]

    def typ(c):
        p.K(ord(c))
        s = lines[m['line']]
        lines[m['line']] = s[:m['col']] + c + s[m['col']:]
        m['col'] += 1

    def click(r, c, line):
        p.click(c * 8 + 2, TY + r * 8 + 3)
        p.W(20)                         # (not a double click)
        m['line'], m['col'] = line, min(c, len(lines[line]))

    p.W(150)
    p.ctrl('o')
    p.W(30)
    p.K(ord('B'))
    p.W(10)
    p.K(RET)
    p.W(40)
    click(2, 5, 2)                      # 1. a line with text, then an empty one
    L(1)
    click(3, 5, 3)
    typ('a')
    L(2)
    p.b += bytes([ord('H'), 5])         # 2. the wheel (top 15): row 4, line 19
    p.W(20)
    click(4, 10, 19)
    typ('b')
    L(3)
    for _ in range(3):                  # 3. the scroll bar's arrow (top 18)
        p.click(SB_X * 8 + 8, TY + ROWS * 8 - 8)
        p.W(20)
    click(5, 0, 23)
    typ('c')
    L(4)
    p.b += bytes([ord('H'), 10])        # 4. the wheel (top 48): row 3, line 51
    p.W(20)
    click(3, 20, 51)
    typ('d')
    L(5)
    click(4, 3, 52)                     # 5. then a line with text
    typ('e')
    L(6)
    p.ctrl('s')
    p.W(40)
    p.W(30)
    p.stop()
    open(os.path.join(card, 'IDE.PLY'), 'wb').write(p.data())
    json.dump({'states': states, 'saved': '\n'.join(lines)},
              open(os.path.join(card, 'blank.json'), 'w'), indent=1)
    return 0


def check(card):
    exp = json.load(open(os.path.join(card, 'blank.json')))
    con = open(os.path.join(card, 'console.txt'), encoding='latin-1').read()
    bad = 0
    got = {}
    for mt in re.finditer(r'IDE STATE (\d+) (\d+) (\d+) ', con):
        got[mt.group(1)] = [int(mt.group(2)), int(mt.group(3))]
    for n, want in exp['states'].items():
        if got.get(n) != want:
            print('state %s: the cursor at %s, wanted %s' % (n, got.get(n), want))
            bad = 1
    have = open(os.path.join(card, NAME), encoding='latin-1').read()
    if have != exp['saved']:
        a, b = have.split('\n'), exp['saved'].split('\n')
        for i in range(max(len(a), len(b))):
            x = a[i] if i < len(a) else None
            y = b[i] if i < len(b) else None
            if x != y:
                print('line %d: saved %r, wanted %r' % (i + 1, x, y))
                bad = 1
    return bad


if __name__ == '__main__':
    if sys.argv[1] == 'check':
        sys.exit(check(sys.argv[2]))
    sys.exit(main(sys.argv[1]))
