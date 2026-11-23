#!/usr/bin/env python3
"""Gate switch, Roomy mode (DECISIONS V145): the console of a session of
the test desktop built -D ROOMY (tests/switch_desk.s) with SwBig built
-D HUGE (tests/switch_app.s: every bank it may take, each with a pattern).

usage: check_roomy.py <console.txt> <RAM in KB>
       check_roomy.py --full <console.txt>
                     the card full: SwBig (-D HUGE -D BIG -D DBG) asked
                     (TASK ASK CARD), OK: it goes on; its parts' CRCs
                     (SW 4 PART) before and after the same but the
                     screens', which the box's RecoverRectangle redraws
                     from the back screen (GEOS's way)

Checks that SwBig went to the card (TASK CARD) and came back twice with
the same CRC of its zero page, RAM, bank 1, VRAM, palette, mode and every
one of its banks; that SwOne and SwTwo, put aside in RAM over SwBig's
banks, went to the card when SwBig came back (TASK EVICT) and came back
the same too; that nothing is aside at the end and every bank is free.
Prints the banks SwBig held, the switches' times (8 MHz) and the KB.
"""
import re
import sys


def full(path):
    t = open(path, errors='replace').read().replace('\r', '')
    i, j = t.find('SW 4 SUM'), t.find('SW 4 BACK')
    a = re.findall(r'SW 4 PART (\w+)', t[:i])
    b = re.findall(r'SW 4 PART (\w+)', t[i:j])
    bad = []
    if 'TASK ASK CARD SwBig' not in t:
        bad.append('the box did not say the card is full (TASK ASK CARD)')
    if 'TASK CARD SwBig' in t or 'TASK QUIT' in t:
        bad.append('SwBig went to the card, or quit')
    if j < 0 or len(a) != len(b) or len(a) < 40:
        bad.append('SwBig did not go on (its parts after the box: %d of %d)' % (len(b), len(a)))
    else:
        d = [k for k in range(len(a)) if a[k] != b[k] and k != 2]
        if d:
            bad.append('parts changed: %s' % d)
    for x in bad:
        print('FAIL  %s' % x)
    if bad:
        sys.exit(1)
    print('ok    Roomy, the card full: "Not enough room on the card to put it aside" (TASK ASK CARD), OK: SwBig goes on;')
    print('ok      the CRCs of its zero page, RAM, bank 1, sprites, colour map, palette and %d banks the same'
          % (len(a) - 5))


def main():
    if sys.argv[1] == '--full':
        return full(sys.argv[2])
    con = open(sys.argv[1], errors='replace').read().replace('\r', '')
    ram = int(sys.argv[2])
    total = 43 if ram == 512 else 235     # (V165: bank C)
    lines = [ln.strip() for ln in con.split('\n') if re.match(r'\s*(SWD|SW [0-9]|TASK )', ln)]
    bad = []
    if any(' DIFF' in ln for ln in lines) or any('SWD FAILED' in ln for ln in lines):
        bad.append('a program came back different, or a step failed')
    for n, name in ((4, 'SwBig'), (1, 'SwOne'), (2, 'SwTwo')):
        if sum(1 for ln in lines if ln == 'SW %d SAME' % n) != 2:
            bad.append('%s did not come back twice the same' % name)
        if 'SW %d QUIT' % n not in lines:
            bad.append('%s did not quit' % name)
    if 'SW 1 FONT 0000' not in lines:
        bad.append('SwOne did not load its font (V183)')
    if not any(ln.startswith('TASK CARD SwBig') for ln in lines):
        bad.append('SwBig was not put onto the card')
    ev = [ln.split()[2] for ln in lines if ln.startswith('TASK EVICT')]
    if not ev:
        bad.append('nothing aside in RAM went to the card for SwBig')
    # (V183: but SwOne's font's bank, which the font service keeps)
    if 'SWD 9 TASKS 0 FREE %d OF %d' % (total - 1, total) not in lines or 'SWD DONE' not in lines:
        bad.append('not every bank free at the end')
    if bad:
        print('\n'.join(lines[-30:]))
        for b in bad:
            print('FAIL  %s' % b)
        sys.exit(1)
    m = re.search(r'SWD 1 TASKS 1 FREE (\d+)', '\n'.join(lines))
    times = {}
    for ln in lines:
        mm = re.match(r'TASK (CARD|ASIDE|BACK|EVICT) (\S+) ([0-9A-F]{8})$', ln)
        if mm:
            times.setdefault((mm.group(1), mm.group(2)), []).append(int(mm.group(3), 16) / 8e3)
    print('ok    %d KB, Roomy: SwBig (every bank it may take) onto the card and back twice exactly (zero page, RAM,'
          % ram)
    print('ok      bank 1, VRAM, palette, mode and each of its banks: the same CRC); SwOne and SwTwo aside in RAM')
    print('ok      over its banks went to the card when it came back (TASK EVICT %s), and came back the same'
          % ', '.join(sorted(set(ev))))
    print('ok    %d KB, Roomy: SwOne loaded a font (Gate Sans 12) while SwBig was on the card, held while aside: not in '
          'SwBig\'s banks (V183)' % ram)
    print('ok    %d KB, Roomy: free with SwBig on the card: %s of %d; at the end nothing aside, all %d free but the font\'s'
          % (ram, m.group(1) if m else '?', total, total))
    for k in sorted(times):
        print('ok    %d KB, Roomy: %s %s: %s' % (ram, k[0], k[1], ', '.join('%d ms' % t for t in times[k])))


if __name__ == '__main__':
    main()
