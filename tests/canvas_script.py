#!/usr/bin/env python3
"""gate canvas: CanvApp's session (tests/canvas_app.c), written as
tests/canvas_script.h (tests/sdk_play.s's format through canvas_app.c's
P, K and END). 320 x 240 coordinates.

usage: canvas_script.py <out.h>
"""
import sys

FILE = (92, 6)          # the menu bar's File
CLOSE = (100, 22)       # its item Close (GotoFirstMenu)
SHOTS = {'menu': 230, 'closed': 420, 'dialog': 600}


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    out = ['/* gate canvas: the session, written by tests/canvas_script.py */']
    out += ['/* shot %s %d */' % (k, v) for k, v in sorted(SHOTS.items(), key=lambda kv: kv[1])]
    ev = []

    def click(f, x, y, what=None):
        ev.append((f, 'P(%d, %d, %d, 0),%s' % (f, x, y, '  /* %s */' % what if what else '')))
        ev.append((f + 2, 'P(%d, %d, %d, 1),' % (f + 2, x, y)))     # (held 8 frames: CanvApp's
        ev.append((f + 10, 'P(%d, %d, %d, 0),' % (f + 10, x, y)))   # checks take a while)
    ev.append((0, 'P(0, 160, 120, 0),'))
    click(100, FILE[0], FILE[1], 'File: the menu opens (the shot)')
    click(300, CLOSE[0], CLOSE[1], 'Close: the menu closes')
    ev.append((620, 'K(620, 27),  /* Esc: the Open box (CanvApp opened it at frame 480) ends */'))
    ev.append((60000, 'END(60000)'))
    out += [t for _, t in sorted(ev, key=lambda e: e[0])]
    open(sys.argv[1], 'w').write('\n'.join(out) + '\n')


if __name__ == '__main__':
    main()
