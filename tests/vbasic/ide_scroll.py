#!/usr/bin/env python3
"""gate vb_ide: editing after the view was scrolled (DECISIONS V214).

usage: ide_scroll.py CARD [--redraw]    the session's files (IDE.PLY, the
                                        program); --redraw: F1, Esc at its end
       ide_scroll.py check CARD [CARD2] what it left: the saved program, the
                                        states; the screen against CARD2's

A program of 200 numbered lines opened; the view scrolled every way the
editor has (Down past the window's last row, Page Down, the wheel, the
scroll bar's arrow and its track, a click below the text) and at each a
line clicked or reached, a character typed, one deleted (Delete,
Backspace), Return pressed: the text must change at that line and nowhere
else (the saved file against the model below), the cursor's line logged
there (IDE STATE), and the screen the one a full redraw makes (the last
VRAM dump against the same session's with F1 and Esc at its end: the help
over the window, then the window drawn again whole).
MIT licence (LICENSE).
"""
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'tools'))
import vram2png  # noqa: E402
from ide_play import Play, F1, ESC, BS, DEL, RET, DOWN, UP, HOME, PGDN, PGUP, CTRL_HOME, CTRL  # noqa: E402

NAME = 'Scrolled program.bas'
N = 200
ROWS, TY, SB_X = 54, 32, 78


def row_y(r):
    return TY + r * 8 + 3


def main(card, redraw=False):
    lines = ['REM line %03d' % (i + 1) for i in range(N)] + ['']
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
        """row r, column c: the model's line (the view's first line + r)"""
        p.click(c * 8 + 2, row_y(r))
        p.W(20)                         # (not a double click)
        m['line'], m['col'] = line, min(c, len(lines[line]))

    p.W(150)
    p.ctrl('o')
    p.W(30)
    p.K(ord('S'))
    p.W(10)
    p.K(RET)
    p.W(40)
    # 1. Down past the window's last row: the view follows (top 17)
    p.K(CTRL_HOME, CTRL)
    for _ in range(70):
        p.K(DOWN)
    m['line'], m['col'] = 70, 0
    typ('a')
    L(1)
    # 2. Page Down (top 70, the cursor 53 lines on)
    p.K(HOME)
    p.K(PGDN)
    m['line'], m['col'] = 123, 0
    typ('b')
    L(2)
    # 3. the wheel: five notches down (top 85); a click on row 10
    p.b += bytes([ord('H'), 5])
    p.W(20)
    click(10, 0, 95)
    typ('c')
    L(3)
    # 4. the scroll bar's down arrow three times (top 88); a click on row 0
    for _ in range(3):
        p.click(SB_X * 8 + 8, TY + ROWS * 8 - 8)
        p.W(20)
    click(0, 0, 88)
    typ('d')
    L(4)
    # 5. its track below the thumb: a page (top 141); a click on row 20
    p.click(SB_X * 8 + 8, TY + 400)
    p.W(20)
    click(20, 0, 161)
    typ('e')
    L(5)
    # 6. the wheel five notches more (top 156); a click below the text:
    # its last line (200)
    p.b += bytes([ord('H'), 5])
    p.W(20)
    click(50, 0, 200)
    typ('f')
    L(6)
    # 7. Delete on row 5 (line 161: the 'e'), Backspace on row 6 col 3
    click(5, 0, 161)
    p.K(DEL)
    lines[161] = lines[161][1:]
    click(6, 3, 162)
    p.K(BS)
    lines[162] = lines[162][:2] + lines[162][3:]
    m['col'] = 2
    L(7)
    # 8. Return at the start of row 8 (line 164), then a character
    click(8, 0, 164)
    p.K(RET)
    lines.insert(164, '')
    m['line'], m['col'] = 165, 0
    typ('g')
    L(8)
    # 9. back up: Page Up, Up past the window's first row; a character
    p.K(HOME)
    p.K(PGUP)                           # (top 103, the cursor at line 112)
    for _ in range(12):
        p.K(UP)                         # (100: the view follows, top 100)
    m['line'], m['col'] = 100, 0
    typ('h')
    L(9)
    # 10. the wheel up (top 85), a click on row 3, a character
    p.b += bytes([ord('H'), 0xFB])
    p.W(20)
    click(3, 0, 88)
    typ('i')
    L(10)
    # 11. the wheel ten notches down (top 115): the cursor above the
    # window; a click on row 7
    p.b += bytes([ord('H'), 10])
    p.W(20)
    click(7, 0, 122)
    typ('j')
    L(11)
    # 12. the cursor in the first row, the scroll bar's down arrow twice
    # (top 117: the cursor above the window), a click on row 0
    click(0, 0, 115)
    for _ in range(2):
        p.click(SB_X * 8 + 8, TY + ROWS * 8 - 8)
        p.W(20)
    click(0, 0, 117)
    typ('k')
    L(12)
    # 13-15. keys that come together (drawn once they are all in, as a
    # fast typist's on the X16): Home, Page Down and a character (the view
    # stays: no page below); Home, six Downs and a character (top 123);
    # Home, Page Up and a character (top 70)
    for keys, line, c, n in (([HOME, PGDN], 170, 'l', 13), ([HOME] + [DOWN] * 6, 176, 'm', 14),
                             ([HOME, PGUP], 123, 'n', 15)):
        p.T(bytes(keys) + c.encode())
        m['line'], m['col'] = line, 0
        s = lines[line]
        lines[line] = c + s
        m['col'] = 1
        L(n)
    p.ctrl('s')
    p.W(40)
    if redraw:                          # F1 (the help over the window), Esc:
        p.K(F1)                         # the window drawn again whole (view_all)
        p.W(40)
        p.K(ESC)
        p.W(40)
    p.W(30)
    p.stop()
    open(os.path.join(card, 'IDE.PLY'), 'wb').write(p.data())
    json.dump({'states': states, 'saved': '\n'.join(lines)},
              open(os.path.join(card, 'scroll.json'), 'w'), indent=1)
    return 0


def screen(dump):
    """the text's rows and the scroll bar as VERA shows them"""
    v = vram2png.section(dump)
    return [row for row in vram2png.compose(v)[TY:TY + ROWS * 8]]


def same_screen(a, b):
    """the two screens' text areas alike, but for the cursor (2 x 8 pixels at
    a card's left edge: its blink)"""
    diff = [(y, x) for y in range(len(a)) for x in range(640) if a[y][x] != b[y][x]]
    if not diff:
        return True
    ys = {y // 8 for y, _ in diff}
    xs = {x // 8 for _, x in diff}
    return len(ys) == 1 and len(xs) == 1 and all(x % 8 < 2 for _, x in diff)


def check(card, card2=None):
    exp = json.load(open(os.path.join(card, 'scroll.json')))
    con = open(os.path.join(card, 'console.txt'), encoding='latin-1').read()
    bad = 0
    got = {}
    for mt in re.finditer(r'IDE STATE (\d+) (\d+) (\d+) ', con):
        got[mt.group(1)] = [int(mt.group(2)), int(mt.group(3))]
    for n, want in exp['states'].items():
        if got.get(n) != want:
            print('state %s: the cursor at %s, wanted %s' % (n, got.get(n), want))
            bad = 1
    f = os.path.join(card, NAME)
    have = open(f, encoding='latin-1').read()
    if have != exp['saved']:
        a, b = have.split('\n'), exp['saved'].split('\n')
        for i in range(max(len(a), len(b))):
            x = a[i] if i < len(a) else None
            y = b[i] if i < len(b) else None
            if x != y:
                print('line %d: saved %r, wanted %r' % (i + 1, x, y))
                bad = 1
    if card2 and not same_screen(screen(os.path.join(card, 'dump.bin')), screen(os.path.join(card2, 'dump.bin'))):
        print('the screen is not the one the window drawn again whole shows')
        bad = 1
    return bad


if __name__ == '__main__':
    if sys.argv[1] == 'check':
        sys.exit(check(*sys.argv[2:4]))
    sys.exit(main(sys.argv[1], '--redraw' in sys.argv))
