#!/usr/bin/env python3
"""The website's Paint picture (DECISIONS V139): a session that Paint's
test build plays (tests/paint_play.c with PAINT_DA, which includes
"da_paint.h" from the folder given with -I), so the picture is drawn by
Paint itself, with its own tools, patterns and colours, in the emulator.

    paint_picture.py <dir>        writes <dir>/da_paint.h

A summer house: the sky, the sun with its rays, two clouds, the hills, the
meadow, a house (walls, a tiled roof, windows, a door, a path), a tree,
and a label in Gate Sans 18 (options/text font: the font picker). Every
rectangle sits on 8 x 8 cards, so each card's colour is the shape's.
tools/site/shots.sh builds and runs it and keeps the screen.

Paint's screen (apps/paint/paint.c; tests/paint_script.py's helpers): the
tools 24 x 24 from y 18, two a row (pencil, line; rectangle, filled
rectangle; eraser, text); the patterns 24 x 20 from y 96, two a row; the
colours 16 x 16 from y 384, three a row (0 the paper, 1 black, 2 dark
red, 3 sky, 4 purple, 5 green, 6 navy, 7 yellow, 8 tan, 9 brown, 10 rose,
11 dark grey, 12 grey, 13 light green, 14 blue, 15 light grey). MIT
licence (see LICENSE)."""
import os
import sys

TOP = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(TOP, 'tests'))
import paint_script as ps  # noqa: E402

TOOL = {'pencil': (12, 30), 'line': (36, 30), 'rect': (12, 54), 'fill': (36, 54), 'eraser': (12, 78), 'text': (36, 78)}


class S:
    """the session; a tool, colour or pattern clicked only when it changes
    (the script must fit in the test build's memory)"""
    def __init__(self):
        self.f = 30
        self.cur = {'tool': 'pencil', 'colour': 0, 'pattern': 1}
        self.frames = []

    def same(self, k, v):
        if self.cur.get(k) == v:
            return True
        self.cur[k] = v
        return False

    def tool(self, t):
        if not self.same('tool', t):
            self.f = ps.click(self.f, *TOOL[t])

    def colour(self, i):
        if not self.same('colour', i):
            self.f = ps.click(self.f, 8 + 16 * (i % 3), 392 + 16 * (i // 3))

    def pattern(self, p):
        if not self.same('pattern', p):
            self.f = ps.click(self.f, 12 + 24 * (p % 2), 106 + 20 * (p // 2))

    def box(self, x0, y0, x1, y1):
        self.f = ps.drag(self.f, [(x0, y0), (x1, y1)])

    def fill(self, colour, pattern, x0, y0, x1, y1, frame=False):
        self.colour(colour)
        self.pattern(pattern)
        self.tool('fill')
        self.box(x0, y0, x1, y1)
        if frame:
            self.frames.append((colour, x0, y0, x1, y1))

    def draw_frames(self):
        """the frames, after the fills, a colour at a time"""
        for c, x0, y0, x1, y1 in sorted(self.frames):
            self.colour(c)
            self.tool('rect')
            self.box(x0, y0, x1, y1)
        self.frames = []

    def line(self, colour, x0, y0, x1, y1):
        self.colour(colour)
        self.tool('line')
        self.f = ps.drag(self.f, [(x0, y0), (x1, y1)])


def main():
    out = sys.argv[1]
    ps.L.clear()
    ps.shots.clear()
    ps.P(0, 320, 240, 0)
    s = S()
    # the sky, the sun and its rays, two clouds
    s.fill(3, 0, 48, 16, 639, 263)
    s.fill(7, 0, 528, 40, 583, 95, frame=True)
    s.draw_frames()
    for x0, y0, x1, y1 in ((555, 34, 555, 20), (555, 101, 555, 116), (522, 67, 504, 67), (589, 67, 608, 67),
                           (524, 36, 510, 22), (586, 36, 600, 22), (524, 98, 510, 112), (586, 98, 600, 112)):
        s.line(3, x0, y0, x1, y1)
    s.fill(0, 0, 96, 56, 215, 79)
    s.fill(0, 0, 120, 40, 175, 55)
    s.fill(0, 0, 320, 88, 407, 103)
    s.fill(0, 0, 336, 80, 383, 87)
    # the hills, the meadow, the grass at the front
    s.fill(13, 5, 48, 216, 263, 263)
    s.fill(13, 5, 392, 232, 639, 263)
    s.fill(5, 0, 48, 264, 639, 479)
    s.fill(13, 23, 48, 440, 639, 479)
    # the house: the walls, the roof, the windows, the door, the path
    s.fill(8, 0, 152, 248, 311, 383, frame=True)
    s.fill(2, 8, 136, 200, 327, 247, frame=True)
    s.fill(11, 0, 280, 168, 295, 199, frame=True)
    for x in (176, 264):
        s.fill(7, 0, x, 272, x + 31, 303, frame=True)
    s.fill(9, 0, 216, 320, 247, 383, frame=True)
    s.fill(15, 5, 216, 384, 247, 439)
    # the tree: the trunk, the crown
    s.fill(9, 9, 448, 312, 463, 399, frame=True)
    s.fill(13, 3, 408, 224, 503, 311, frame=True)
    # the label's box
    s.fill(7, 0, 480, 416, 631, 455, frame=True)
    s.draw_frames()
    for x in (176, 264):                    # the windows' bars
        s.line(7, x + 16, 272, x + 16, 303)
        s.line(7, x, 288, x + 31, 288)
    # the label, in Gate Sans 18 (the picker: System, Veranda UI, Gate Mono, Gate Sans; 9, 12, 18, 27)
    s.f = ps.menu(s.f, 'options', 1, 'options: text font: the picker')
    s.f = ps.click(s.f + 120, 250, 157 + 14 * 3, 'Gate Sans')
    s.f = ps.click(s.f + 120, 375, 157 + 14 * 2, 'size 18')
    s.f = ps.click(s.f + 130, 430, 157, 'OK') + 120     # (the font loads)
    s.tool('text')
    s.f = ps.click(s.f + 30, 490, 425, 'the label')
    s.f = ps.typ(s.f + 20, 'Summer house')
    ps.K(s.f + 2, '\r')
    s.f += 30
    s.f += 60
    ps.L.append('END(%d)' % s.f)
    with open(os.path.join(out, 'da_paint.h'), 'w') as o:
        o.write('/* the website\'s Paint picture, written by tools/site/paint_picture.py */\n')
        o.write('\n'.join(ps.L) + '\n')
    print('paint_picture: %d frames' % s.f)


if __name__ == '__main__':
    main()
