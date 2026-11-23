#!/usr/bin/env python3
"""Gate input checks (tests/input.s): the event lines, the pointer sprite.

usage: check_input.py <dump.bin> <console.txt>
"""
import re
import sys

EXPECTED = [
    'M',                    # frame 12: the program's mouseVector, which
    'D 01A4 00F0',          #           passes it on (DefMouse): pressed at (420, 240)
    'M',                    # frame 14
    'U 01A4 00F0',          #           released
    'F 10',                 # frame 21: past the right edge (539)
    'T1',                   # frame 33
    'K 61 00',              # frame 45: 'a'
    'K 0D 00',              #           RETURN
    'K 81 00',              #           PgUp (API 2: KEY_PGUP)
    'K 82 00',              #           PgDn ($02, without Ctrl)
    'K 83 00',              #           End ($04)
    'K 89 00',              #           F9 ($10, was KEY_UP)
    'K 8A 00',              #           F10 ($15)
    'K 8B 00',              #           F11 ($16, was KEY_STOP)
    'K 8C 00',              #           F12 ($17)
    'K 01 00',              #           F1 (KEY_F1, no modifier)
    'K 08 00',              # frame 50: Backspace (BACKSPACE)
    'K 08 10',              #           left (KEY_LEFT, the same code; KEYM_ARROW)
    'K 1E 10',              #           right (KEY_RIGHT, KEYM_ARROW)
    'K 01 02',              # frame 55: Ctrl+A: 1 as F1, keyDataMods Ctrl
    'K 02 02',              #           Ctrl+B: 2, not PgDn
    'W',                    # frame 60: Sleep 60 is over
    'T2',                   # frame 66; then the process is frozen (no T3 at 99)
    'F 80',                 # frame 70: past the top edge (50)
    'E 021B 0032 32',       # frame 110: (539, 50), the classic byte 50
]
VRAM_SPRATTR = 0x1FC00
failures = 0


def check(cond, what):
    global failures
    print(('ok    ' if cond else 'FAIL  ') + what)
    if not cond:
        failures += 1


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    v = open(sys.argv[1], 'rb').read()
    log = [re.sub(r'\\X[0-9A-F]{2}', '', ln).strip()
           for ln in open(sys.argv[2], 'rb').read().decode('latin-1').splitlines()]
    check('INPUT DONE' in log, 'the test ran to its end')
    try:
        got = log[log.index('INPUT START') + 1:log.index('INPUT DONE')]
    except ValueError:
        got = []
    check(got == EXPECTED, 'the events, in order: keys, a click (press, release), faults, processes '
          '(one frozen after two runs), Sleep')
    if got != EXPECTED:
        print('      expected: %s' % EXPECTED)
        print('      got:      %s' % got)
    a = v[VRAM_SPRATTR:VRAM_SPRATTR + 8] if len(v) > VRAM_SPRATTR + 8 else b''
    check(len(a) == 8 and a[2:6] == bytes([0x1B, 0x02, 0x32, 0x00]) and a[6] & 0x0C == 0x0C,
          'the pointer (sprite 0) is at (539, 50), in front: %s' % a.hex(' '))
    sys.exit(1 if failures else 0)


if __name__ == '__main__':
    main()
