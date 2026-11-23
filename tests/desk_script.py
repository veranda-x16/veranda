#!/usr/bin/env python3
"""gate desk: writes tests/desk_script.h, Paint's session for the desk
accessory gate (tests/paint_play.c with PAINT_DESK; the helpers are
tests/paint_script.py's).

usage: desk_script.py [out.h]      (default tests/desk_script.h)

Paint draws (colour 2: a pencil stroke; the ink red: options/ink colour;
pattern 7, the filled rectangle tool, a rectangle), opens
options/accessory: the list of desk accessories (the Calculator
selected), OPEN. Paint's script stops while the accessory
runs (its own script, tests/calc_script.h, plays then: the accessory's
start resets the pointer source) and goes on from the same frame when
RstrAppl gives Paint back: after the snapshots, a second filled
rectangle with the tool and pattern chosen before (Paint's state).
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import paint_script as ps  # noqa: E402


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), 'desk_script.h')
    ps.L.clear()
    ps.P(0, 320, 240, 0)
    f = ps.click(30, *ps.colour(2), c='colour 2')
    f = ps.drag(f, [(80 + i * 10, 100 + (i % 5) * 12) for i in range(30)], 'pencil: a stroke')
    f = ps.menu(f, 'options', 0, 'options: ink colour: red (colour 2)')
    f = ps.click(f, *ps.pattern(7), c='pattern 7')
    f = ps.click(f, *ps.TOOL['box'], c='tool: filled rectangle')
    f = ps.drag(f, [(120, 200), (200, 260), (300, 330)], 'a filled rectangle')
    f = ps.menu(f, 'paint', 1, 'Paint: desk accessory: the list, the Calculator selected')
    f = ps.click(f + 300, *ps.OPEN, c='OPEN: GetFile starts the Calculator (its own script plays)')
    f = ps.drag(f + 600, [(420, 300), (500, 360), (560, 420)],
                'back in Paint: a filled rectangle, the tool and pattern as before')
    f += 300
    ps.L.append('END(%d)' % f)
    with open(out, 'w') as o:
        o.write('/* gate desk: Paint\'s session, written by tests/desk_script.py */\n')
        o.write('\n'.join(ps.L) + '\n')


if __name__ == '__main__':
    main()
