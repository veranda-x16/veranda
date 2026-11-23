#!/usr/bin/env python3
"""Gate mouse's menu tracking scripts (tools/gate_mouse.sh; DECISIONS V137):
the menus of tests/menutrack (Menu Track) and of the shell through the
X16's real mouse path (the emulator's -mousescript: PS/2 packets, moves
relative), as a hand makes them on a real X16.

usage: menutrack_script.py <case> > mouse.txt

Menu Track's bar (Veranda look, 640 x 480): Track x 16-63, Long 64-103,
Next 104-143, Act 144-; lists under their title, 16 lines an item from
y 16: Track's at x 16, Long's at x 64-151 (28 items: Item 00 .. Item 26
at y 16 .. 447, More at 448-463), More's 6 beside it, moved up to end at
the screen's bottom (y 384-479). The shell's Veranda menu: About the
shell, Desk accessory, Help (y 16, 32, 48).

The cases (each ends with exit, 60 frames after its last step):
  wobble    Long pressed, dragged down slowly to Item 26 (16 lines every
            4 frames) swinging 10 pixels either side of the list's left
            edge, released on it: chosen (TRACK L 26)
  sticky    Track clicked (9 frames), the pointer down to Last swinging
            the same way, a click: TRACK T 02
  outside   Track clicked, a click on the desktop: the menu closed, the
            press not the program's (no TRACK PRESS)
  next      Track clicked, the pointer along the bar onto Long (Long's
            menu opens), down to Item 05 without a click, a click
  bottom    Long clicked, More clicked (its menu beside, moved up),
            More 5 at the screen's last item row clicked: TRACK M 05
  parent    Long, More clicked; into More, then left onto Long's Item 20
            (More closes), a click: TRACK L 20
  slip      Track pressed, the pointer 12 lines down onto First while
            the button is held 6 frames: the menu open, nothing chosen
  keys      Track clicked, Down twice, Return: TRACK T 01
  esc       Track clicked, Esc: closed
  shell     the shell's Veranda menu pressed, dragged down to Help
            swinging 10 pixels either side of the list's right edge,
            released: Help (the shell looks in /VERANDA/HELP)
  shellclk  the same with a click, the pointer down swinging, a click
  title     (V155) Track clicked, the pointer pushed up onto the bar's top
            line (y 0) on its own title, left still 60 frames: the menu
            stays open and is not closed and opened again every poll
  titlebot  the same on the bar's last line (y 15)
  titleleft Track clicked, the pointer on its title's first column (x 0)
  edge      Long, More clicked; the pointer onto More's first column in
            Long's list (x 64), still: More stays open
"""
import sys


def start(x, dev=3):
    return ['0 id %d' % dev, '400 move -2000 -2000', '440 move %d 7' % x]


def wobble(t, rows, dx=10, step=16, every=4):
    """rows steps of `step` lines down, x swinging +-dx around where it is"""
    out, side = [], -1
    for i in range(rows):
        mx = side * dx if i == 0 else side * 2 * dx
        out.append('%d move %d %d' % (t, mx, step))
        side = -side
        t += every
    # back to the middle
    out.append('%d move %d 0' % (t, side * dx))
    return out, t + every


def steps(t, x, y, n=8):
    """a move of x, y in n packets a frame apart (a hand's, not a jump)"""
    return ['%d move %d %d' % (t + i, x * (i + 1) // n - x * i // n, y * (i + 1) // n - y * i // n)
            for i in range(n)]


def click(t):
    return ['%d down' % t, '%d up' % (t + 9)]


def main():
    case = sys.argv[1]
    out = []
    if case == 'wobble':
        out += start(70) + ['460 down']
        w, t = wobble(470, 27)                   # y 7 + 432 = 439: Item 26
        out += w + ['%d up' % (t + 10)]
        t += 10
    elif case == 'sticky':
        out += start(24) + click(460)
        w, t = wobble(490, 3)                    # y 55: Last
        out += w + click(t + 10)
        t += 19
    elif case == 'outside':
        out += start(24) + click(460) + steps(490, 376, 293) + click(510)
        t = 519
    elif case == 'next':
        out += start(24) + click(460)
        t = 490
        for _ in range(6):                       # x 24 -> 84: Long
            out.append('%d move 10 0' % t)
            t += 4
        out += ['%d move 0 97' % (t + 10)] + click(t + 30)   # y 104: Item 05
        t += 39
    elif case in ('bottom', 'parent'):
        out += start(80) + click(460)
        out += steps(480, 0, 448) + click(510)   # y 455: More
        if case == 'bottom':
            out += ['540 move 90 16'] + click(560)           # x 170, y 471: More 5
            t = 569
        else:
            out += ['540 move 90 -55']                       # x 170, y 400: More 2
            out += ['560 move -45 -28', '564 move -45 -28']  # x 80, y 344: Item 20
            out += click(600)
            t = 609
    elif case == 'slip':
        out += start(24) + ['460 down', '463 move 0 12', '466 up']
        t = 466
    elif case == 'keys':
        out += start(24) + click(460)
        out += ['490 keydown 84', '494 keyup 84', '500 keydown 84', '504 keyup 84',
                '510 keydown 43', '514 keyup 43']
        t = 514
    elif case == 'esc':
        out += start(24) + click(460) + ['490 keydown 110', '494 keyup 110']
        t = 494
    elif case == 'shell':
        # (the list is x 0-95: the swing about x 90 leaves it by 5)
        out += start(30) + ['460 down', '464 move 0 16', '468 move 60 0']
        w, t = wobble(472, 2)                    # y 55: Help
        out += w + ['%d up' % (t + 10)]
        t += 10
    elif case == 'shellclk':
        out += start(30) + click(460) + ['482 move 0 16', '486 move 60 0']
        w, t = wobble(490, 2)
        out += w + click(t + 10)
        t += 19
    elif case in ('title', 'titlebot', 'titleleft'):
        out += start(24) + click(460)
        out += ['480 move %s' % {'title': '0 -20', 'titlebot': '0 8', 'titleleft': '-30 0'}[case]]
        t = 480
    elif case == 'edge':
        out += start(80) + click(460)
        out += steps(480, 0, 448) + click(510)   # y 455: More
        out += ['540 move -16 0']                # x 64: Long's left edge
        t = 540
    else:
        sys.exit('menutrack_script.py: no case ' + case)
    out.append('%d exit' % (t + 60))
    print('\n'.join(out))


if __name__ == '__main__':
    main()
