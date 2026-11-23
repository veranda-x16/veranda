#!/usr/bin/env python3
"""gate canvas (DECISIONS V166): CanvApp's dumps and console.

usage: check_canvas.py shot <dump.bin> menu|closed|dialog
       check_canvas.py console <console.txt> fast|roomy

shot: VERA's registers in canvas mode (layer 0 an 8 bpp bitmap at
$02800, 320 wide; layer 1 the 1 bpp screen at $00000; both shown); every
card of the picture either CanvApp's bytes (tests/canvas_app.c's pix) or
all 0 (covered); menu and dialog: the covered cards are one area with the
box's ink in it; closed: none covered.

console: the lines CanvApp, CanvDA and the test desktop log, in order,
every check BAD 0000 and PAL ok (tests/canvas_app.c); CanvDA saw the
picture hidden; put aside CanvApp held at most MAXB banks (Fast) or its
task file held at most MAXB banks besides its own (Roomy: HUGE); palette
entries 16-255 after it quit as before it started.
"""
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'tools'))
import vram2png  # noqa: E402

MAXB = 6


def pix(x, y):
    v = (2 * y + x) & 255
    return v or 255


def fail(msg):
    print('FAIL  ' + msg)
    sys.exit(1)


def shot(path, what):
    v = vram2png.section(path)
    VR, C, P = vram2png.VRAM, vram2png.COMPOSER, vram2png.PALETTE
    video = v[VR]
    l0 = v[VR + C + P:][:7]
    l1 = v[VR + C + P + 7:][:7]
    regs = (video & 0x30 == 0x30, l0[0] == 0x07, l0[2] == 0x14, l1[0] == 0x04, l1[2] == 0x00)
    if not all(regs):
        fail('registers: DC_VIDEO $%02X, L0 config $%02X tile base $%02X, L1 config $%02X tile base $%02X'
             % (video, l0[0], l0[2], l1[0], l1[2]))
    zero, bad = [], 0
    for cy in range(30):
        for cx in range(40):
            got = [v[0x2800 + (cy * 8 + r) * 320 + cx * 8 + k] for r in range(8) for k in range(8)]
            want = [pix(cx * 8 + k, cy * 8 + r) for r in range(8) for k in range(8)]
            if got == want:
                continue
            if not any(got):
                zero.append((cx, cy))
                continue
            bad += 1
    if bad:
        fail('%d cards are neither the picture nor 0' % bad)
    if what == 'closed':
        if zero:
            fail('%d cards still 0 after the menu closed' % len(zero))
        print('ok    closed: every byte of the picture as CanvApp drew it, the layers as canvas mode sets them')
        return
    if not zero:
        fail('no card covered')
    xs, ys = [c[0] for c in zero], [c[1] for c in zero]
    x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
    inked = sum(1 for (cx, cy) in zero if any(v[(cy * 8 + r) * 40 + cx] for r in range(8)))
    if what == 'menu' and len(zero) != (x1 - x0 + 1) * (y1 - y0 + 1):
        fail('the covered cards are not one rectangle: %d in %d-%d x %d-%d' % (len(zero), x0, x1, y0, y1))
    if inked < len(zero) // 4:
        fail('the covered cards have little ink (%d of %d): no box there?' % (inked, len(zero)))
    print('ok    %s: the layers as canvas mode sets them; %d cards covered (%d-%d x %d-%d, ink in %d), 0; every '
          'other byte as CanvApp drew it' % (what, len(zero), x0, x1, y0, y1, inked))


def console(path, name):
    con = open(path, errors='replace').read().replace('\r', '')
    lines = [ln.strip() for ln in con.split('\n') if re.match(r'\s*CANV', ln)]
    want = ['CANVD 0', 'CANVAS PAL0', 'CANVAS ON', 'CANVAS COVERED', 'CANVAS UNCOVERED', 'CANVAS DIALOG', 'CANVDA',
            'CANVAS DESK', 'CANVD 1', 'CANVD ASIDE', 'CANVAS BACK', 'CANVAS OFF', 'CANVAS QUIT', 'CANVD 2',
            'CANVD PAL', 'CANVD DONE']
    i = 0
    got = {}
    for ln in lines:
        if i < len(want) and ln.startswith(want[i]):
            got[want[i]] = ln
            i += 1
    if i < len(want):
        print('\n'.join(lines))
        fail('%s: "%s" missing (or out of order)' % (name, want[i]))
    for k in ('CANVAS ON', 'CANVAS COVERED', 'CANVAS UNCOVERED', 'CANVAS DIALOG', 'CANVAS DESK', 'CANVAS BACK'):
        ln = got[k]
        if ' L0 07 TB 14 L1 04 ' not in ln or ' BAD 0000 ' not in ln or ' PAL ok' not in ln:
            fail('%s: %s' % (name, ln))
    if ' COV 0000 ' in got['CANVAS COVERED']:
        fail('%s: no card covered by the menu' % name)
    for k in ('CANVAS UNCOVERED', 'CANVAS DIALOG', 'CANVAS DESK', 'CANVAS BACK'):
        if ' COV 0000 ' not in got[k]:
            fail('%s: %s: cards still covered' % (name, got[k]))
    if not re.search(r'CANVDA L0 04 TB 00', got['CANVDA']):
        fail('%s: the accessory did not see the 1 bpp screen on layer 0: %s' % (name, got['CANVDA']))
    if not re.search(r' L0 04 TB 00 ', got['CANVAS OFF']):
        fail('%s: %s' % (name, got['CANVAS OFF']))
    m = re.match(r'CANVD ASIDE (\d+) CARD (\d+)', got['CANVD ASIDE'])
    banks, card = int(m.group(1)), int(m.group(2))
    huge = re.search(r'HUGE ([0-9A-F]{2})', got['CANVAS PAL0'])
    if huge:
        own = int(huge.group(1), 16)
        rest = card - own * 8192
        if not card or rest > MAXB * 8192:
            fail('%s: the task file %d bytes, %d besides its %d banks' % (name, card, rest, own))
        aside = 'on the card: its task file %d bytes, %d besides its own %d banks' % (card, rest, own)
    else:
        if card or not 0 < banks <= MAXB:
            fail('%s: put aside it held %d banks (card %d)' % (name, banks, card))
        aside = 'aside in RAM: %d banks' % banks
    pal0 = int(got['CANVAS PAL0'].split()[2], 16)
    pal = int(got['CANVD PAL'].split()[2])
    if pal != pal0:
        fail('%s: palette entries 16-255 after it quit: %d, before %d' % (name, pal, pal0))
    print('ok    %s: the canvas on (layer 0 $07, tile base $14; layer 1 the 1 bpp screen); the File menu covered '
          'cards and gave every byte back; after the Open box, CanvDA (it saw layer 0 the 1 bpp screen) and '
          'Alt + Tab the picture and palette as drawn' % name)
    print('ok    %s: %s; after it quit palette entries 16-255 as before it started' % (name, aside))
    # (V177) the desktop's mode at each start: steps 1 and 2 (back after Alt +
    # Tab, after CanvApp quit) the one it had at step 0 (or set then)
    modes = {}
    for ln in lines:
        m = re.match(r'CANVD (\d) FREE \d+ OF \d+ MODE (\d)', ln)
        if m:
            modes[int(m.group(1))] = int(m.group(2))
        m = re.match(r'CANVD SET (\d)', ln)
        if m:
            modes[0] = int(m.group(1))
    if sorted(modes) != [0, 1, 2]:
        fail('%s: the desktop\'s modes: %s' % (name, modes))
    if modes[1] != modes[0] or modes[2] != modes[0]:
        fail('%s: the desktop came back in mode %d after Alt + Tab, %d after CanvApp quit (it was in %d)'
             % (name, modes[1], modes[2], modes[0]))
    print('ok    %s: the desktop back in its mode %s (%s) after Alt + Tab and after CanvApp quit'
          % (name, modes[0], ('640 x 480', '640 x 240', '320 x 240')[modes[0]]))


def main():
    if len(sys.argv) != 4 or sys.argv[1] not in ('shot', 'console'):
        sys.exit(__doc__)
    (shot if sys.argv[1] == 'shot' else console)(sys.argv[2], sys.argv[3])


if __name__ == '__main__':
    main()
