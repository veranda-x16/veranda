#!/usr/bin/env python3
"""gate vb_core: VeraBASIC Run's logs (the emulator's console) against the
reference interpreter's (tools/vbasic.py run --log).

usage: check_core.py CONSOLE.txt EXPECTED_DIR [--only NAME...]

CONSOLE.txt holds, for each program VBTEST.LST named, "VB RUN NAME", its
console lines ("VB| ..."), "VB END" / "VB ERROR n" / "VB INPUT", "VB GC n";
EXPECTED_DIR/NAME.log the reference's lines for it. A NAME.exp file
instead is compared as it is (the programs whose end the reference cannot
know: Ctrl+C); "~" lines there match by regular expression, in order, other
lines between them allowed. NAME.need: lines that must come (in order, as
.exp's) besides an equal .log, the test's own lines ("VB ASIDE", "VB
CTRL+C", "DESK ...") left out of the comparison. Prints one line a
program; exits 1 on any difference. MIT licence (LICENSE).
"""
import os
import re
import sys


def runs(console):
    """NAME -> [lines] in the order they came"""
    out = {}
    order = []
    cur = None
    text = open(console, 'rb').read().decode('latin-1')
    for raw in text.split('\n'):
        i = raw.find('VB')
        j = raw.find('DESK')
        if i < 0 and j < 0:
            continue
        if i < 0 or (0 <= j < i):
            line = raw[j:]
        else:
            line = raw[i:]
        if line.startswith('VB RUN '):
            cur = line[7:].strip().upper()
            order.append(cur)
            out[cur] = []
            continue
        if cur is None:
            continue
        if line.startswith('VB DONE'):
            cur = None
            continue
        out[cur].append(line.rstrip('\r'))
    return out, order


def in_order(g, exp, name):
    """the lines exp in g, in order; "~" lines are regular expressions"""
    k = 0
    for e in exp:
        if e.startswith('~'):
            pat = re.compile(e[1:])
            while k < len(g) and not pat.fullmatch(g[k]):
                k += 1
        else:
            while k < len(g) and g[k] != e:
                k += 1
        if k >= len(g):
            print('FAIL  %s: no line %r (in order)' % (name, e))
            return False
        k += 1
    return True


def main(argv):
    if len(argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    got, order = runs(argv[0])
    exp_dir = argv[1]
    only = argv[3:] if len(argv) > 2 and argv[2] == '--only' else None
    names = only or sorted(n[:-4] for n in os.listdir(exp_dir) if n.endswith(('.log', '.exp')))
    bad = 0
    gcs = 0
    for name in names:
        key = name.upper()
        if os.path.exists(os.path.join(exp_dir, name + '.exp')):
            exp = open(os.path.join(exp_dir, name + '.exp'), encoding='latin-1').read().split('\n')
            literal = True
        else:
            exp = open(os.path.join(exp_dir, name + '.log'), encoding='latin-1').read().split('\n')
            literal = False
        exp = [e for e in exp if e]
        if key not in got:
            print('FAIL  %s: not run' % name)
            bad += 1
            continue
        g = [x for x in got[key] if not x.startswith(('VB GC', 'VB BANKS'))]
        need = os.path.join(exp_dir, name + '.need')
        if os.path.exists(need) and not literal:
            want = [e for e in open(need, encoding='latin-1').read().split('\n') if e]
            if not in_order(g, want, name):
                bad += 1
                continue
            g = [x for x in g if not (x.startswith('VB ASIDE') or x.startswith('VB CTRL+C')
                                      or x.startswith('DESK'))]
        for x in got[key]:
            m = re.match(r'VB GC (\d+)', x)
            if m:
                gcs += int(m.group(1))
        if literal:
            ok = in_order(g, exp, name)
        else:
            ok = g == exp
            if not ok:
                n = next((i for i in range(min(len(g), len(exp))) if g[i] != exp[i]), min(len(g), len(exp)))
                print('FAIL  %s: line %d: X16 %r, reference %r' % (
                    name, n + 1, g[n] if n < len(g) else '(none)', exp[n] if n < len(exp) else '(none)'))
        if ok:
            print('ok    %s (%d lines)' % (name, len(g)))
        else:
            bad += 1
    print('%d programs, %d differ; %d collections of the heap' % (len(names), bad, gcs))
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
