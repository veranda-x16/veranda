#!/usr/bin/env python3
"""Gate feedback, part 2 (DECISIONS V96): the real shell blanked under ROM
R49 with real PS/2 input; compares -dump V dumps.

usage: check_blank.py blanked <ref>
       check_blank.py same <ref> <dump> <paper>
       check_blank.py menu <ref> <dump>
       check_blank.py tst <folder> <program>

<ref> a session that exits while blanked (as long after the blanking as
the others), <dump> one woken by a mouse move (and moved back) or a key.
blanked: the display window closed (DC_VSTOP 0: no active line, all
border), the border entry 0, palette entry 0 black; DC_VIDEO as awake
(layer 0 or both layers and the sprites).
same: <dump> is <ref> awake: DC_VSTOP $F0 again, palette entry 0 the
paper (<paper>, $0RGB hex), the rest equal: VRAM (the screen, the back
screen, the pointer's pictures, the colour map and its tiles, the
palette, the sprites' attributes), the composer, the layers, the
sprites; not what nothing has written here, whose power-up contents
differ from run to run (the save-under $12C00-$16BFF; sprite 0's slot's
own picture $16C00-$16DFF and its end past the pointer's shapes
$17380-$173FF; $1F800-$1F9BF), nor DC_VIDEO's bit 7 (the current field).
menu: after the wake a click on the bar's File: its menu drawn below it
(the shell answers), the display awake.
tst: <folder>/SHELL.TST: the shell (its flat layout: the folder's root)
double-clicks <program>.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import shell_script as S  # noqa: E402

VRAM, COMPOSER, PALETTE, LAYERS, SPRITES = 131072, 256, 512, 14, 1024
TAIL = VRAM + COMPOSER + PALETTE + LAYERS + SPRITES
UNSET = [range(0x12C00, 0x16E00), range(0x17380, 0x17400), range(0x1F800, 0x1F9C0)]


def load(f):
    d = open(f, 'rb').read()
    if len(d) < TAIL:
        sys.exit('check_blank: %s: no VRAM section' % f)
    return bytearray(d[-TAIL:])


def comp(t):
    return t[VRAM:VRAM + 8]


def pal0(t):
    return t[VRAM + COMPOSER] | t[VRAM + COMPOSER + 1] << 8


def fail(msg):
    print('FAIL  ' + msg)
    sys.exit(1)


def blanked(t, what):
    c = comp(t)
    if c[7] != 0 or c[3] != 0 or pal0(t) != 0:
        fail('%s: not blanked: DC_VSTOP $%02X, DC_BORDER $%02X, palette entry 0 $%04X' % (what, c[7], c[3], pal0(t)))
    if c[0] & 0x70 not in (0x50, 0x70):
        fail('%s: blanked with DC_VIDEO $%02X: want the layers and sprites as awake' % (what, c[0]))


def awake(t, what):
    c = comp(t)
    if c[7] != 0xF0 or c[3] != 0 or c[0] & 0x70 not in (0x50, 0x70):
        fail('%s: not awake: DC_VIDEO $%02X, DC_VSTOP $%02X, DC_BORDER $%02X' % (what, c[0], c[7], c[3]))


def main():
    a = sys.argv[1:]
    if not a or a[0] not in ('blanked', 'same', 'menu', 'tst'):
        sys.exit(__doc__)
    if a[0] == 'tst':
        d, name = a[1:3]
        root = S.listing([], sorted(set(os.listdir(d) + ['SHELL.TST', 'SHELL.STP', 'console.txt', 'mouse.txt'])))
        q = S.Part()
        q.wait(20)
        q.dbl(*S.cell(root.index(name)))
        q.end(S.END_STOP)
        S.write(os.path.join(d, 'SHELL.TST'), [q])
        return
    ref = load(a[1])
    blanked(ref, a[1])
    if a[0] == 'blanked':
        c = comp(ref)
        print('ok    blanked: DC_VSTOP $00, DC_BORDER $00, palette entry 0 $000; DC_VIDEO $%02X (as awake)'
              % (c[0] & 0x7F))
        return
    t = load(a[2])
    awake(t, a[2])
    if a[0] == 'menu':
        fg = [(x, y) for y in range(16, 80) for x in range(80, 200)
              if ref[y * 80 + x // 8] >> (7 - x % 8) & 1 != t[y * 80 + x // 8] >> (7 - x % 8) & 1]
        if len(fg) < 400:
            fail('the click on File after the wake: the screen below it changed in %d pixels only' % len(fg))
        print('ok    the shell answers after the wake: File\'s menu drawn (%d pixels below the bar)' % len(fg))
        return
    paper = int(a[3], 16)
    if pal0(t) != paper:
        fail('palette entry 0 $%04X after the wake: want the paper $%04X' % (pal0(t), paper))
    want = bytearray(ref)
    want[VRAM + 7] = 0xF0
    want[VRAM + COMPOSER:VRAM + COMPOSER + 2] = bytes([paper & 255, paper >> 8])
    want[0x1FA00:0x1FA02] = t[0x1FA00:0x1FA02]     # (VRAM under entry 0: the emulator's own)
    want[VRAM] = (want[VRAM] & 0x7F) | (t[VRAM] & 0x80)
    for r in UNSET:
        want[r.start:r.stop] = t[r.start:r.stop]
    diff = [i for i in range(TAIL) if want[i] != t[i]]
    if diff:
        fail('after the wake %d bytes differ from before it, from $%05X (%s)'
             % (len(diff), diff[0], ', '.join('$%05X' % i for i in diff[:8])))
    print('ok    awake: the display as before the blanking (DC_VSTOP $F0, palette entry 0 $%03X); VRAM, the colour '
          'map, the palette, the layers and the sprites unchanged' % paper)


if __name__ == '__main__':
    main()
