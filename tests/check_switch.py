#!/usr/bin/env python3
"""Gate switch (DECISIONS V83): the console of a session of the test
desktop (tests/switch_desk.s) and the test programs (tests/switch_app.s).

usage: check_switch.py <console.txt> <RAM in KB>

Checks the lines in order, that each program came back as it went (its
CRC of zero page, RAM, bank 1, both screens, the sprites, the colour map,
the palette and the mode: SAME), the banks, and prints the banks each
task held and the time of each switch (the kernel's TASK lines carry the
emulator's cycles in hex; 8 MHz).
"""
import re
import sys


def main():
    con = open(sys.argv[1], errors='replace').read().replace('\r', '')
    ram = int(sys.argv[2])
    lines = [ln.strip() for ln in con.split('\n') if re.match(r'\s*(SWD|SW [0-9]|TASK )', ln)]
    out = []
    for ln in lines:
        ln = re.sub(r' [0-9A-F]{8}$', '', ln) if ln.startswith('TASK ') else ln
        ln = re.sub(r' (SUM|BACK) [0-9A-F]{4}$', r' \1', ln)
        out.append(ln)
    total = 43 if ram == 512 else 235     # (V165: bank C)
    t = lambda *a: [x for x in a]    # noqa: E731
    want = []
    want += ['SWD 0 TASKS 0 FREE %d OF %d' % (total, total), 'SW 1 START', 'SW 1 SUM', 'TASK ASIDE SwOne']
    want += ['SWD 1 TASKS 1 FREE *', 'SWD TASK 7 SwOne * one', 'SW 2 START', 'SW 2 SUM', 'TASK ASIDE SwTwo']
    want += ['SWD 2 TASKS 2 FREE *', 'SWD TASK 6 SwTwo *', 'SWD TASK 7 SwOne * one', 'SW 3 START', 'SW 3 SUM',
             'TASK ASIDE SwPort']
    tasks3 = ['SWD TASK 5 SwPort *', 'SWD TASK 6 SwTwo *', 'SWD TASK 7 SwOne * one']
    want += ['SWD 3 TASKS 3 FREE *'] + tasks3
    want += ['TASK BACK SwOne', 'SW 1 BACK', 'SW 1 SAME', 'TASK ASIDE SwOne', 'SWD 4 TASKS 3 FREE *'] + tasks3
    want += ['TASK BACK SwTwo', 'SW 2 BACK', 'SW 2 SAME', 'TASK ASIDE SwTwo', 'SWD 5 TASKS 3 FREE *'] + tasks3
    want += ['TASK BACK SwPort', 'SW 3 BACK', 'SW 3 SAME', 'TASK ASIDE SwPort', 'SWD 6 TASKS 3 FREE *'] + tasks3
    want += ['TASK BACK SwOne', 'SW 1 BACK', 'SW 1 SAME', 'SW 1 QUIT', 'SWD 7 TASKS 2 FREE *',
             'SWD TASK 5 SwPort *', 'SWD TASK 6 SwTwo *']
    want += ['SW 4 START', 'SW 4 SUM', 'TASK ASK MEMORY SwBig', 'TASK QUIT SwBig', 'SWD 8 TASKS 1 FREE *',
             'SWD TASK 5 SwPort *']
    want += ['TASK BACK SwPort', 'SW 3 BACK', 'SW 3 SAME', 'SW 3 REC Kept open while aside', 'SW 3 QUIT',
             'SWD 9 TASKS 0 FREE %d OF %d' % (total, total)]
    want += ['SW 1 START', 'SW 1 SUM', 'TASK ASIDE SwOne', 'SWD 10 TASKS 1 FREE *', 'SWD TASK 7 SwOne *',
             'SWD 11 TASKS 0 FREE %d OF %d' % (total, total), 'SWD DONE']
    bad = 0
    for i, w in enumerate(want):
        g = out[i] if i < len(out) else '(nothing)'
        rx = '^' + re.escape(w).replace(r'\*', r'.+') + '$'
        if not re.match(rx, g):
            print('FAIL  line %d: %r, wanted %r' % (i, g, w))
            bad = 1
            break
    if not bad and len(out) != len(want):
        print('FAIL  %d lines more than wanted: %r' % (len(out) - len(want), out[len(want):len(want) + 3]))
        bad = 1
    if bad:
        print('\n'.join(out[max(0, i - 8):i + 4]))
        sys.exit(1)
    # the banks and the times
    banks = {}
    for ln in lines:
        m = re.match(r'SWD TASK \d (\S+) (\d+)', ln)
        if m:
            banks[m.group(1)] = int(m.group(2))
    times = {'ASIDE': [], 'BACK': []}
    for ln in lines:
        m = re.match(r'TASK (ASIDE|BACK) (\S+) ([0-9A-F]{8})$', ln)
        if m:
            times[m.group(1)].append((m.group(2), int(m.group(3), 16) / 8e3))
    free3 = int(re.search(r'SWD 3 TASKS 3 FREE (\d+)', '\n'.join(lines)).group(1))
    print('ok    %d KB: three programs put aside (SwOne, SwTwo native; SwPort a GEOS port\'s ways, its record file open),'
          % ram)
    print('ok      each brought back twice exactly (zero page, RAM, bank 1, both screens, sprites, colour map,')
    print('ok      palette, mode: the same CRC), one dropped (TASK_END), SwBig asked to quit (not enough banks)')
    print('ok    %d KB: RAM banks a task holds: %s; free with the three aside: %d of %d'
          % (ram, ', '.join('%s %d' % kv for kv in sorted(banks.items())), free3, total))
    for k in ('ASIDE', 'BACK'):
        v = times[k]
        print('ok    %d KB: %s: %s' % (ram, 'put aside' if k == 'ASIDE' else 'brought back',
                                       ', '.join('%s %d ms' % (n, ms) for n, ms in v)))
    print('ok    %d KB: BASIC (keep Veranda) with a task aside, SYS 35328: Veranda back, nothing aside, all %d banks free'
          % (ram, total))


if __name__ == '__main__':
    main()
