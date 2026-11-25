#!/usr/bin/env python3
"""gate desk: the Calculator's scripted session (tests/calc_script.py's
CASES) against Python: each case's "CALC = <display>" line on the
console, in order; a number within one unit of its 9th significant digit
of Python's value (the display shows 9 at most), a text exactly.

usage: check_calc.py <console.txt>      (also: the keys' times, "TIME key")
"""
import math
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import calc_script  # noqa: E402


def close(got, want):
    try:
        v = float(got)
    except ValueError:
        return False
    if want == 0:
        return got == '0'
    unit = 10 ** (math.floor(math.log10(abs(want))) - 8)
    digits = len(re.sub(r'[^0-9]', '', got.split('E')[0]).lstrip('0'))
    return abs(v - want) <= 1.01 * unit and digits <= 9


def main():
    con = open(sys.argv[1], 'rb').read().decode('latin-1')
    con = re.sub(r'\\X[0-9A-F]{2}', '', con).replace('\r', '')
    con = con[con.find('CALC RUNNING'):]
    got = re.findall(r'CALC = (\S+)', con)
    cases = calc_script.CASES + [calc_script.PRESS_CASE[:2] + ('Error',)]
    bad = 0
    for i, (how, keys, want) in enumerate(cases):
        g = got[i] if i < len(got) else None
        ok = g is not None and (g == want if isinstance(want, str) else close(g, want))
        if not ok:
            bad += 1
            k = keys if how == 't' else ' '.join(keys)
            print('FAIL  case %d (%s): %r -> %s, want %s' % (i, 'typed' if how == 't' else 'clicked',
                                                         k, g, want))
    n = len(cases)
    print(('ok    ' if not bad and len(got) == n else 'FAIL  ') +
          'the Calculator: %d cases (%d typed, %d clicked), %d as Python has them; %d results on the console' %
          (n, sum(1 for c in cases if c[0] == 't'), sum(1 for c in cases if c[0] == 'k'), n - bad, len(got)))
    t = sorted(int(c, 16) / 8000 for c in re.findall(r'TIME key ([0-9A-F]{8})', con))
    if t:
        print('      a key\'s work and the display drawn again: %d keys, median %.0f ms, the slowest %.0f ms' %
              (len(t), t[len(t) // 2], t[-1]))
    sys.exit(1 if bad or len(got) != n else 0)


if __name__ == '__main__':
    main()
