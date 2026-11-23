#!/usr/bin/env python3
"""gate notepad: writes tests/note_script.h, the sessions Note Pad's test
build plays (tests/note_play.c), from the accessory's start.

usage: note_script.py [out.h]      (default tests/note_script.h)

The window (apps/notepad/notepad.c) at 640x480: 320 x 208 at (160, 136);
the close box at 462-472, 139-149 (vrwin.h); the buttons at y 320-335:
Prev 176-223, Next 232-279, New 368-407, Delete 416-463 (V148). The first session
(NOTE_FIRST): "Shopping list", Return, "Milk", Return, "Bread" typed;
PgDn (a new page 2), "Second page"; New (page 3), "third"; PgUp (page
2), Delete (page 2 goes: "third" is page 2 of 2), "!"; the close box.
The Note File: two pages, "Shopping list\\nMilk\\nBread" and "third żółw!"
(V143: "żółw" typed in Veranda's set, ISO-8859-16).
The second session (the file there already): Next (page 2 of 2), Escape.
"/* shot NAME FRAME */" lines name frames for a screenshot (NOTE_STOP).
"""
import os
import sys

X0, Y0 = 160, 136
L = []
shots = []
L10 = 'third żółw'.encode('iso8859_16').decode('latin-1')     # (V143: typed in the set's bytes)
PAGES = ['Shopping list\nMilk\nBread', L10 + '!']


def P(f, x, y, b, c=None):
    L.append('P(%d, %d, %d, %d),%s' % (f, x, y, b, '  /* %s */' % c if c else ''))


def K(f, code, c=None):
    L.append('K(%d, %d),%s' % (f, code, '  /* %s */' % c if c else ''))


def click(f, x, y, c=None):
    P(f, x, y, 0, c)
    P(f + 6, x, y, 1)                   # (the pointer there first, the button
    P(f + 16, x, y, 0)                  # held a while)
    return f + 40


def typed(f, s, c=None):
    for i, ch in enumerate(s):
        K(f, 13 if ch == '\n' else ord(ch), c if i == 0 else None)
        f += 4
    return f + 10


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), 'note_script.h')
    f = 40
    L.append('#ifdef NOTE_FIRST')
    f = typed(f, 'Shopping list\nMilk\nBread', 'page 1')
    K(f, 0x02, 'PgDn: a new page 2')
    f = typed(f + 30, 'Second page')
    f = click(f, 380, 327, 'New: page 3')
    f = typed(f, L10)
    shots.append(('note', f + 10))
    K(f + 20, 0x82, 'PgUp: page 2')
    f = click(f + 60, 432, 327, 'Delete: page 2 goes, "third" is page 2 of 2')
    f = typed(f, '!')
    f = click(f + 20, 467, 144, 'the close box: RstrAppl')
    L.append('#else')
    f2 = click(200, 256, 327, 'Next: page 2 of 2')
    K(f2 + 30, 27, 'Escape')
    L.append('#endif')
    L.append('END(60000)')
    with open(out, 'w') as o:
        o.write('/* gate notepad: Note Pad\'s sessions, written by tests/note_script.py */\n')
        for name, fr in shots:
            o.write('/* shot %s %d */\n' % (name, fr))
        o.write('\n'.join(L) + '\n')


if __name__ == '__main__':
    main()
