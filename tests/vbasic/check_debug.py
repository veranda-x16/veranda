#!/usr/bin/env python3
"""gate vb_debug: what the debugger's sessions (tests/vbasic/debug_script.py)
logged, against what they must (tools/gate_vb_debug.sh).

usage: check_debug.py SESSIONS_DIR ROM

  debug     the breaks in order (line, why), the call stack at each (its
            procedures and lines, FUNCTION Fact four deep), the variables
            and watches' values, the local changed (k = 99), the arrays'
            bounds and elements, the program's console after Continue
  screen    screen_a's screen and screen_b's (a break, a watch, steps, a
            dialog box, Continue) the same: the bitmap, the colour map, the
            palette (tests/vbasic/check_ui.py's digest, the clock masked)
            and sprites 2-7; screen_b's timer went on after the break
  trace     the trace pane's lines (the last 200) those of
            tools/vbasic.py run --trace, and the runtime's own "VB TRON"
            lines all of them
  error     the messages: the statement in canonical form, the procedure,
            the kernel's code

MIT licence (LICENSE)."""
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TOP = os.path.join(HERE, '..', '..')
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(TOP, 'tools'))
import check_ui  # noqa: E402
import vram2png  # noqa: E402

errors = []


def check(c, msg):
    if not c:
        errors.append(msg)
    return c


def log(sdir, s):
    t = open(os.path.join(sdir, s, 'console.txt'), encoding='latin-1').read()
    return [ln.strip('\r') for ln in t.replace('\r', '\n').split('\n')]


def breaks(lines):
    """[(line, why, [stack], {name: value})], each break with what was
    answered last before the next one"""
    out = []
    for ln in lines:
        m = re.search(r'IDE BREAK (\d+) (\d+) (\d+)', ln)
        if m:
            out.append([int(m.group(1)), int(m.group(2)), [], {}])
            continue
        if not out:
            continue
        m = re.search(r'IDE STACK (\d+) (\d+) (.*) (\d+)$', ln)
        if m:
            i = int(m.group(1))
            st = out[-1][2]
            if i == 0:
                del st[:]
            st.append((m.group(3), int(m.group(4))))
            continue
        m = re.search(r'IDE VALUE \d+ (.*?) = (.*)$', ln)
        if m and m.group(1):
            out[-1][3][m.group(1)] = m.group(2)
    return out


def check_debug(sdir):
    lines = log(sdir, 'debug')
    b = breaks(lines)
    want = [(15, 1), (16, 2), (23, 2), (19, 1), (19, 1), (19, 1), (19, 1), (24, 2), (24, 3)]
    got = [(x[0], x[1]) for x in b]
    check(got == want, 'debug: the breaks (line, why) %r, not %r' % (got, want))
    if len(b) < 9:
        return
    stacks = {0: [('SUB Twice', 15), ('main', 22)], 1: [('SUB Twice', 16), ('main', 22)],
              2: [('main', 23)], 3: [('FUNCTION Fact', 19), ('main', 23)],
              6: [('FUNCTION Fact', 19)] + [('FUNCTION Fact', 20)] * 3 + [('main', 23)],
              8: [('main', 24)]}
    for i, st in stacks.items():
        check(b[i][2] == st, 'debug: break %d: the call stack %r, not %r' % (i + 1, b[i][2], st))
    v0 = {'n': '55', 'k': '0', 'squares': '5', 'grid': '2, 3', 'total': '55', 'name$': '"feeder"', 'i': '6'}
    for k, v in v0.items():
        check(b[0][3].get(k) == v, 'debug: break 1: %s = %r, not %r' % (k, b[0][3].get(k), v))
    w = {'total * 2': '110', 'squares(3) + 1': '10', 'LEFT$(name$, 4) + "!"': '"feed!"', 'k': '99'}
    for k, v in w.items():
        check(b[1][3].get(k) == v, 'debug: break 2: %s = %r, not %r' % (k, b[1][3].get(k), v))
    text = '\n'.join(lines)
    check('IDE SET 99' in text, 'debug: the change of k not logged')
    el = dict(re.findall(r'IDE VALUE \d+ (squares \d+|grid \d+) = (\S+)', text))
    sq = [el.get('squares %d' % i) for i in range(6)]
    check(sq == ['0', '1', '4', '9', '16', '25'], 'debug: squares() elements %r' % sq)
    gr = [el.get('grid %d' % i) for i in range(12)]
    check(gr == ['0'] * 6 + ['12'] + ['0'] * 5, 'debug: grid() elements %r' % gr)
    con = [ln[4:].rstrip() for ln in lines if ln.startswith('VB| ')]
    wc = ['Twice 55  99', 'Fact 24', 'Total: 55  at the feeder', 'done']
    check(con == wc, 'debug: the console %r, not %r' % (con, wc))
    check(any('IDE ANSWER 3 5' in ln for ln in lines), 'debug: the program did not end after Continue')
    return b


def sprites(path):
    v = vram2png.section(path)
    o = vram2png.VRAM + vram2png.COMPOSER + vram2png.PALETTE + 14
    return v[o + 16:o + 64]


def check_screen(sdir):
    a = os.path.join(sdir, 'screen_a', 'dump.bin')
    b = os.path.join(sdir, 'screen_b', 'dump.bin')
    if not (check(os.path.exists(a) and os.path.exists(b), 'screen: a session did not end')):
        return
    da = check_ui.digest(a, [check_ui.CLOCK])
    db = check_ui.digest(b, [check_ui.CLOCK])
    check(da == db, 'screen: after the break %s, without one %s (%s/screen.png)' % (db, da, os.path.join(sdir, 'screen_b')))
    check(sprites(a) == sprites(b), 'screen: sprites 2-7 differ after the break')
    lb = log(sdir, 'screen_b')
    check([x[:2] for x in breaks(lb)] == [[40, 1], [41, 2], [42, 2]],
          'screen_b: the breaks %r' % [x[:2] for x in breaks(lb)])
    check('VB| ticks 6 ' in lb, 'screen_b: the timer did not go on after the break')
    check('VB| ticks 6 ' in log(sdir, 'screen_a'), 'screen_a: the timer')
    return da


def check_trace(sdir, rom):
    lines = log(sdir, 'trace')
    pane = [int(m.group(1)) for m in (re.search(r'IDE TRACE (\d+)$', ln) for ln in lines) if m]
    vb = [int(ln.split()[2]) for ln in lines if ln.startswith('VB TRON ')]
    ref = subprocess.run([sys.executable, '-I', '-B', os.path.join(TOP, 'tools', 'vbasic.py'), 'run',
                          os.path.join(HERE, 'debug', 'trace.bas'), '--rom', rom, '--trace'],
                         capture_output=True, text=True, encoding='latin-1').stdout.split('\n')
    rt = [int(ln.split()[2]) for ln in ref if ln.startswith('VB TRON ')]
    check(len(rt) > 200, 'trace: the reference traced %d lines' % len(rt))
    check(vb == rt, 'trace: the runtime traced %d lines, the reference %d (first other at %s)' % (
        len(vb), len(rt), next((i for i, (x, y) in enumerate(zip(vb, rt)) if x != y), '-')))
    check(pane == rt[-200:], 'trace: the pane holds %d lines, not the reference\'s last 200' % len(pane))
    return len(rt), len(pane)


def check_errors(sdir):
    want = {'error': 'Error 13, Type mismatch, in line 8 (SUB Tick): total = n + name$',
            'kerror': 'Error 50, File not found (kernel 5), in line 4: OPEN #1, "No such file.txt", "r"'}
    for s, w in want.items():
        got = [ln[ln.index('IDE ERROR ') + 10:] for ln in log(sdir, s) if 'IDE ERROR ' in ln]
        check(got == [w], '%s: the message %r, not %r' % (s, got, w))


def main(argv):
    sdir, rom = argv[0], argv[1]
    b = check_debug(sdir)
    d = check_screen(sdir)
    t = check_trace(sdir, rom)
    check_errors(sdir)
    if errors:
        for e in errors:
            print('FAIL  ' + e)
        return 1
    print('ok    debug: %d breaks (breakpoints, Step, Step out, Step over, STOP), the call stack four FUNCTION calls deep,' % len(b))
    print('ok      the variables (locals first), 3 watches, k changed to 99, squares() and grid() element by element')
    print('ok    the screen: the same after a break as without one (%s; sprites 2-7), its timer going on' % d)
    print('ok    the trace: the pane\'s 200 lines the last of the reference\'s %d (tools/vbasic.py run --trace)' % t[0])
    print('ok    the messages: the statement in canonical form, the procedure, the kernel\'s code')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
