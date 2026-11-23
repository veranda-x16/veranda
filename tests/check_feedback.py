#!/usr/bin/env python3
"""Gate feedback (DECISIONS V51): tests/feedback.s's log and dump.

usage: check_feedback.py <run dir> <png dir>

The dump (-dump V): sprite 0's slot holds every shape of
tools/mkpointers.py from PTR_SLOT_OFFSET; sprite 0 shows the crosshair
(16x16) with its hot spot at the pointer (300, 200); palette entries
17-20. The log: each shape's address in turn, the busy one animated;
the busy pointer by itself during a long call and the arrow after it;
the beep's PSG values frame by frame; blanking after 2 s idle and the
wake on a key and on a press, neither passed on, and a later click
passed on. Writes ptr-<shape>.png (8 times enlarged) from the dump.
"""
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'tools'))
import mkpointers  # noqa: E402
import mksounds  # noqa: E402

SPRITES, SPRATTR, PAL = 0x16C00, 0x1FC00, 0x1FA00
bad = 0


def check(ok, msg):
    global bad
    print(('ok    ' if ok else 'FAIL  ') + msg)
    if not ok:
        bad += 1


def addr(slot):
    return ((SPRITES + mkpointers.SLOT_OFFSET + 128 * slot) >> 5)


def main():
    run, pngdir = sys.argv[1:3]
    v = open(os.path.join(run, 'dump.bin'), 'rb').read()[-132878:]
    shapes = mkpointers.shapes()
    base = SPRITES + mkpointers.SLOT_OFFSET
    same = [v[base + 128 * i:base + 128 * (i + 1)] == mkpointers.packed(s[1]) for i, s in enumerate(shapes)]
    check(all(same), 'sprite 0\'s slot from +%d: the %d shapes of tools/mkpointers.py (%s)'
          % (mkpointers.SLOT_OFFSET, len(shapes), ', '.join(s[0] for s in shapes)))
    a = v[SPRATTR:SPRATTR + 8]
    x, y = a[2] | (a[3] & 3) << 8, a[4] | (a[5] & 3) << 8
    check((a[0] | a[1] << 8) & 0xFFF == addr(2) and a[7] == 0x51 and (x, y) == (300 - 7, 200 - 7),
          'sprite 0 shows the crosshair (16x16, address $%03X) at %d, %d: the pointer (300, 200) less its hot spot'
          % ((a[0] | a[1] << 8) & 0xFFF, x, y))
    pal = [v[131072 + 256 + 2 * i] | v[131072 + 256 + 2 * i + 1] << 8 for i in range(17, 21)]
    check(pal == mkpointers.PAL, 'palette entries 17-20: %s' % ['$%03X' % p for p in pal])

    from PIL import Image
    cols = [None] + [((p >> 8 & 15) * 17, (p >> 4 & 15) * 17, (p & 15) * 17) for p in mkpointers.PAL]
    for i, (name, _, _, _) in enumerate(shapes):
        if name.startswith('busy') and name != 'busy0':
            continue
        img = Image.new('RGB', (16 * 8, 16 * 8), (0, 128, 128))
        for yy in range(16):
            for xx in range(16):
                b = v[base + 128 * i + yy * 8 + xx // 2]
                c = (b >> 4) if xx % 2 == 0 else b & 15
                if c:
                    for k in range(64):
                        img.putpixel((xx * 8 + k % 8, yy * 8 + k // 8), cols[c])
        img.save(os.path.join(pngdir, 'ptr-%s.png' % name.rstrip('0')))

    log = re.sub(r'\\X[0-9A-F]{2}', '', open(os.path.join(run, 'console.txt'), 'rb').read().decode('latin-1'))
    lines = [ln.strip() for ln in log.split('\n') if ln.strip()]
    ev = []                     # (kind, data)
    for ln in lines:
        m = re.match(r'F ([0-9A-F]{4}) A ([0-9A-F]{4}) ([0-9A-F]{2}) V ([0-9A-F]{2}) W ([0-9A-F]{2}) '
                     r'P ([0-9A-F]{4}) Q ([0-9A-F]{4}) ([0-9A-F]{2}) ([0-9A-F]{2})$', ln)
        if m:
            g = [int(x, 16) for x in m.groups()]
            ev.append(('F', g[:4] + g[5:] + [g[4]]))     # d[8]: DC_VSTOP
        elif re.match(r'(SPIN START|SPIN END|IDLE|KEY|IDLE2|PRESS|CLICK|FEEDBACK DONE)$', ln):
            ev.append((ln, None))
        elif re.match(r'(R|K|C) [0-9A-F]{2}$', ln):
            ev.append((ln, None))

    def shape_of(ad):
        ad &= 0xFFF
        for i in range(len(shapes)):
            if ad == addr(i):
                return shapes[i][0]
        return '?%03X' % ad

    # the pointer's addresses in order, up to SPIN START
    seq, fr = [], {}
    for k, d in ev:
        if k == 'SPIN START':
            break
        if k == 'F':
            s = shape_of(d[1])
            if not seq or seq[-1] != s:
                seq.append(s)
                fr.setdefault(s, d[0])
    busy = [s for s in seq if s.startswith('busy')]
    check(seq[:3] == ['arrow', 'ibeam', 'cross'] and len(busy) >= 6 and seq[-1] == 'arrow'
          and busy[:4] == ['busy0', 'busy1', 'busy2', 'busy3'],
          'SetPointer: the arrow, the I-beam, the crosshair, the busy pointer animated (%d pictures), the arrow: %s'
          % (len(busy), ' '.join(seq)))
    check(('R 01', None) in ev, 'SetPointer returns the shape before (R 01: PTR_BUSY)')
    i0 = ev.index(('SPIN START', None))
    i1 = ev.index(('SPIN END', None))
    spin = [shape_of(d[1]) for k, d in ev[i0:i1] if k == 'F']
    after = [shape_of(d[1]) for k, d in ev[i1:i1 + 4] if k == 'F']
    check(len([s for s in spin if s.startswith('busy')]) >= 3 and 'arrow' in after,
          'a long call (70 frames without the main loop): the busy pointer by itself (%s), the arrow after (%s)'
          % (' '.join(spin), ' '.join(after)))
    # the beep
    q = [(d[0], d[5], d[6], d[7]) for k, d in ev if k == 'F' and d[5]]
    tr = mksounds.trace(mksounds.api_ids()['ERROR'], 15)    # (V72: tools/mksounds.py's SND_ERROR)
    want = [r for _, r in tr if r[1] & 63]
    got = [(f, vv, w) for _, f, vv, w in q]
    frames = [f for f, _, _, _ in q]
    end = [d for k, d in ev if k == 'F' and d[0] == frames[-1] + 1] if frames else []
    f0 = frames[0] if frames else 0
    check(got == want and frames == [f0 + x[0] - tr[0][0] for x in tr if x[1][1] & 63] and end
          and end[0][5] == 0 and not end[0][6] & 63,
          'the beep: voice 15 as SND_ERROR\'s table (A5 4 frames, E5 fading for 12, a square at full volume), '
          'then silent (frames %s)' % frames)
    # blanking
    ii = ev.index(('IDLE', None))
    fs = [(n, d) for n, (k, d) in enumerate(ev) if k == 'F' and n > ii]
    # (V96: the display window closed, DC_VIDEO left as it is: the ROM's
    # mouse_scan turns the sprites on at every packet)
    vid = [d[3] for n, d in fs][0] if fs else None
    blank = [(n, d) for n, d in fs if not d[8]]
    check(len(blank) >= 2 and blank[0][1][4] == 0 and all(d[3] == vid for n, d in fs),
          'blanked: DC_VSTOP $00 (no active line: the border), palette entry 0 $%04X; DC_VIDEO $%02X throughout'
          % (blank[0][1][4], vid) if blank else 'blanked: never')
    if blank:
        ik = ev.index(('KEY', None))
        wake = [d for n, d in fs if n > ik and d[8]]
        check(bool(wake) and wake[0][4] == 0xFFF and wake[0][8] == 240,
              'a key wakes it: DC_VSTOP $%02X, palette entry 0 $%04X' % (wake[0][8], wake[0][4]) if wake else
              'a key wakes it: no')
        check(not any(k.startswith('K ') for k, _ in ev), 'the key that woke it did not reach keyVector')
        ip = ev.index(('PRESS', None))
        ic = ev.index(('CLICK', None))
        wake2 = [d for n, d in fs if n > ip and d[8]]
        again = [d for n, d in fs if n > ik and not d[8]]
        check(bool(wake) and bool(again) and 115 <= again[0][0] - wake[0][0] <= 185,
              'blanked again 2 s after the key (no input since): frames $%04X to $%04X'
              % (wake[0][0], again[0][0]) if wake and again else 'blanked again: never')
        check(len(blank) >= 2 and bool(wake2), 'blanked again; a press wakes it')
        check(not any(k.startswith('C ') for k, _ in ev[:ic]), 'the press that woke it (and its release) did not '
              'reach otherPressVec')
        check(('C 00', None) in ev[ic:] and ('C 80', None) in ev[ic:], 'a click after it does (C 00, C 80)')
    check(('FEEDBACK DONE', None) in ev, 'the session ended')
    sys.exit(1 if bad else 0)


if __name__ == '__main__':
    main()
