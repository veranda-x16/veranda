#!/usr/bin/env python3
"""gate vb_ide: the editor's session (tests/vbasic/ide_script.py) against
what it must have done.

usage: check_ide.py CARD [--partial] [--rom ROM]

CARD's console.txt (the editor's test build logs "IDE ..." lines, its
runs' console "VB| ..."), expect.json and the files: every 'L' state as
expected (0 or null: any); Check found the planted error at its line and,
after the fix, none; the run's console lines those of tools/vbasic.py run
(the reference, the ROM's floats with --rom); Ctrl+C stopped the program
at the loop's line; F1 showed PRINT's page; the file saved equals the text
typed, byte for byte; the file saved after Format equals
tools/vbtokens.py's canonical form of the careless text (G2). --partial: a
session stopped on the way (a screenshot): only the states it got to.
MIT licence (LICENSE)."""
import json
import os
import re
import subprocess
import sys

TOP = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..')
sys.path.insert(0, os.path.join(TOP, 'tools'))
import vbtokens  # noqa: E402
sys.path.insert(0, os.path.join(TOP, 'tests'))
import check_blink  # noqa: E402

errors = []


def check(c, msg):
    if not c:
        errors.append(msg)


def main(argv):
    card = argv[0]
    partial = '--partial' in argv
    rom = argv[argv.index('--rom') + 1] if '--rom' in argv else None
    exp = json.load(open(os.path.join(card, 'expect.json')))
    con = open(os.path.join(card, 'console.txt'), encoding='latin-1').read()
    lines = con.replace('\r', '\n').split('\n')
    # the states
    got = {}
    for ln in lines:
        m = re.search(r'IDE STATE (\d+) (\d+) (\d+) (\d+) (\d+) (\d+) (\d+) (\d+) ?(.*)$', ln)
        if m:
            got[m.group(1)] = [int(x) for x in m.groups()[1:8]] + [m.group(9)]
    for n, want in exp['states'].items():
        if n not in got:
            check(partial, 'state %s: not logged' % n)
            continue
        for i, (w, g) in enumerate(zip(want, got[n])):
            if w not in (None, 0) or i in (4, 7):
                check(w == g, 'state %s: field %d is %r, not %r (%r)' % (n, i, g, w, got[n]))
    if partial:
        return report(card, 'partial')
    bb, blink = check_blink.check(con, 30, 30)
    errors.extend(bb)
    # the answers: the planted error, then none; the run, the stop
    ans = [ln[ln.index('IDE ANSWER'):].split() for ln in lines if 'IDE ANSWER' in ln]
    check(len(ans) >= 5, 'answers: %r' % ans)
    if len(ans) >= 5:
        check(ans[0][2:5] == ['1', '1', str(exp['err_line'])], 'Check: the planted error: %r' % ans[0])
        check(ans[1][2:4] == ['0', '1'], 'Check after the fix: %r' % ans[1])
        check(ans[2][2:4] == ['3', '2'], 'Run: its end: %r' % ans[2])
        check(ans[3][2:4] == ['4', '2'] and int(ans[3][4]) in exp['stop_lines'],
              'Run, Ctrl+C: stopped in the loop: %r' % ans[3])
        check(got.get('7', [0] * 7)[6] in exp['stop_lines'], 'state 7: the line stopped at marked')
        check(ans[4][2:4] == ['0', '3'], 'Format: %r' % ans[4])
    msg = [ln for ln in lines if 'IDE MSG Line %d: NEXT j does not match FOR i' % exp['err_line'] in ln]
    check(msg, 'the error\'s message in the status bar')
    # the run's console against the reference
    i = next(k for k, ln in enumerate(lines) if 'IDE REQ 2' in ln)
    j = next(k for k in range(i, len(lines)) if 'IDE ANSWER' in lines[k])
    x16 = [ln[ln.index('VB| '):] for ln in lines[i:j] if 'VB| ' in ln]
    src = os.path.join(card, 'run1.bas')
    open(src, 'w', encoding='latin-1', newline='\n').write(exp['run1'])
    cmd = [sys.executable, '-I', '-B', os.path.join(TOP, 'tools', 'vbasic.py'), 'run', src, '--log']
    if rom:
        cmd += ['--rom', rom]
    ref = [ln for ln in subprocess.run(cmd, capture_output=True, text=True, encoding='latin-1').stdout.split('\n')
           if ln.startswith('VB| ')]
    check(x16 == ref and ref, 'the run\'s console: %r, the reference %r' % (x16, ref))
    # help, format
    check(any('IDE HELP PRINT ' in ln for ln in lines), 'F1 on PRINT: its page')
    # the files
    for name, text in exp['saved'].items():
        p = os.path.join(card, name)
        check(os.path.exists(p) and open(p, 'rb').read() == text.encode('latin-1'),
              '%s: not the text typed' % name)
    canon = vbtokens.canon(exp['messy'])
    p = os.path.join(card, exp['name2'])
    got2 = open(p, 'rb').read() if os.path.exists(p) else None
    check(got2 == canon.encode('latin-1'), '%s: not the canonical form:\n%r\n%r' % (exp['name2'], got2, canon))
    fm = [ln for ln in lines if 'IDE FORMAT ' in ln]
    check(fm and fm[0].split()[2] == str(len(canon)), 'Format: %r, %d' % (fm, len(canon)))
    return report(card, '%d states, the planted error at line %d and none after the fix, %d console lines as '
                  'the reference, stopped in the loop (line %s), F1, the file saved, Format = canon; %s' %
                  (len(exp['states']), exp['err_line'], len(ref), ans[3][4], blink))


def report(card, what):
    for e in errors:
        print('check_ide: ' + e)
    if errors:
        return 1
    print('ok    %s: %s' % (card, what))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
