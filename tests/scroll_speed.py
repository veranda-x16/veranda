#!/usr/bin/env python3
"""gates vb_ide and edit: how long scrolling takes (DECISIONS V215).

usage: scroll_speed.py ide|edit CARD [--check]   the session's files (the
                                        program or text, IDE.PLY / EDIT.PLY);
                                        --check: the redraw check after
                                        every step ('L' $80 + n: the test
                                        build compares the window with a
                                        full redraw of it)
       scroll_speed.py report CARD [--max ms,ms] [--check]
                                        the console's TIME lines as a table
                                        (milliseconds at 8 MHz); --max: the
                                        line's and the page's limits;
                                        --check: a REDRAW line for every
                                        step, no row unlike the full
                                        redraw's

The test build's player (tests/edit_play.s) times a record exactly ('Z'
then 'Y'): from the moment it plays it to the program's first idle pass
(or the pass where only the status bar waits: it waits while keys come)
with nothing waiting (tests/tk_hash.s's test_idle). VeraBASIC: a program of 200 lines in colour (the
gutter on: line numbers, keywords, strings, comments, numbers); Veranda
Edit: 3,000 lines of plain text. Each way of scrolling at the window's
edge: a line down and up, a page down and up, a wheel notch (3 lines) and
five at once, the scroll bar's arrow (VeraBASIC) and track, Down held for
40 repeats two frames apart (the time after the last repeat is what the
user waits), and for comparison a key in the window (no scroll) and a
character typed.

MIT licence (see LICENSE).
"""
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'vbasic'))
from ide_play import Play, RET, DOWN, UP, PGDN, PGUP, CTRL_HOME, CTRL  # noqa: E402

ROWS, TY = 54, 32
FRAME = 134400                          # 8 MHz cycles a frame (VERA's 59.52 Hz)
HELD, EVERY = 40, 2

NAMES = {
    'm': 'Down inside the window (no scroll)',
    'k': 'a character typed',
    'd': 'Down at the last row: a line',
    'u': 'Up at the first row: a line',
    'p': 'Page Down',
    'q': 'Page Up',
    'w': 'the wheel: a notch (3 lines)',
    'W': 'the wheel: 5 notches at once',
    'a': 'the scroll bar: its arrow (a line)',
    't': 'the scroll bar: its track (a page)',
    'h': 'Down held: after the last of 40 repeats',
    'H': 'Down held: 40 repeats, 2 frames apart',
}

BAS = [
    "' Birds at the feeder, counted every %d minutes",
    "SUB Count%d(n%%, name$)",
    "  LOCAL k%%, total",
    "  FOR k%% = 1 TO n%% STEP 2",
    "    total = total + k%% * 1.5E2 / %d",
    "    PRINT \"Bird \"; name$; \" seen\"; k%%; \" times\"",
    "  NEXT k%%",
    "  IF total > %d THEN PRINT \"many\" ELSE PRINT \"few\"",
    "END SUB",
    "REM the next species, number %d",
]

WORDS = ('the quick brown fox jumps over a lazy dog while seven birds sing at the '
         'feeder near an old oak tree and rain falls softly on green meadows').split()


def bas_text():
    return '\n'.join(BAS[i % len(BAS)].replace('%%', '%') if '%d' not in BAS[i % len(BAS)]
                     else BAS[i % len(BAS)] % (i + 3) for i in range(200)) + '\n'


def plain_text():
    x, out = 7, []
    for i in range(3000):
        words, w = [], 0
        target = 40 + (x >> 4) % 36
        while w < target:
            x = (x * 1103515245 + 12345) & 0x7FFFFFFF
            s = WORDS[(x >> 8) % len(WORDS)]
            words.append(s)
            w += len(s) + 1
        out.append('%d: %s' % (i + 1, ' '.join(words)))
    return '\n'.join(out) + '\n'


def main(app, card, check=False):
    p = Play()
    nchk = [0]

    def timed(label, f):
        p.b += b'Z'
        f()
        p.b += bytes([ord('Y'), ord(label)])
        if check:
            nchk[0] += 1
            p.L(0x80 + nchk[0])

    def key(k):
        return lambda: p.K(k)

    if app == 'ide':
        name, text, sbx = 'Speed of scrolling.bas', bas_text(), 78 * 8 + 8
        open(os.path.join(card, name), 'w', encoding='latin-1', newline='\n').write(text)
        p.W(150)
        p.ctrl('o')
        p.W(30)
        p.K(ord('S'))
        p.W(10)
        p.K(RET)
        p.W(40)
    else:
        name, text, sbx = 'SPEED.TXT', plain_text(), 79 * 8 + 4
        open(os.path.join(card, name), 'w', encoding='latin-1', newline='\n').write(text)
        p.W(60)
        p.K(ord('o'), CTRL)
        p.W(30)
        p.K(ord('s'))
        p.W(10)
        p.K(RET)
        p.W(40)
    p.K(CTRL_HOME, CTRL)
    p.W(10)
    timed('m', key(DOWN))
    timed('k', lambda: p.K(ord('x')))
    for _ in range(ROWS - 2):
        p.K(DOWN)
    p.W(10)
    for _ in range(3):
        timed('d', key(DOWN))           # (top 3)
    timed('H', lambda: p.b.extend(bytes([ord('R'), DOWN, HELD])))
    p.W(10)                             # (top 43)
    timed('p', key(PGDN))               # (top 96)
    timed('q', key(PGUP))               # (top 43)
    p.click(100, TY + 3)                # the cursor to the first row (line 44)
    p.W(20)
    for _ in range(3):
        timed('u', key(UP))             # (top 40)
    for _ in range(2):
        timed('w', lambda: p.b.extend(bytes([ord('H'), 1])))
    timed('W', lambda: p.b.extend(bytes([ord('H'), 5])))    # (top 61)
    if app == 'ide':
        p.P(sbx, TY + ROWS * 8 - 8)     # the down arrow (top 63)
        for _ in range(2):
            timed('a', lambda: p.b.extend(b'D'))
            p.W(4)
            p.b += b'U'
            p.W(10)
    p.P(sbx, TY + ROWS * 8 - 30)        # the track below the thumb (a page on)
    timed('t', lambda: p.b.extend(b'D'))
    p.W(4)
    p.b += b'U'
    p.W(30)
    p.stop()
    open(os.path.join(card, 'IDE.PLY' if app == 'ide' else 'EDIT.PLY'), 'wb').write(p.data())
    return 0


def report(card, limits=None, check=False):
    """the TIME lines (ms at 8 MHz: the text drawn; the status bar waits
    while keys come, V215); with check, every timed step's REDRAW line"""
    con = open(os.path.join(card, 'console.txt'), 'rb').read().decode('latin-1')
    times = {}
    steps = 0
    for mt in re.finditer(r'TIME (.) ([0-9A-F]{8})', con):
        if mt.group(1) in NAMES:
            times.setdefault(mt.group(1), []).append(int(mt.group(2), 16))
            steps += 1
    bad = 0
    if 'H' in times:
        times['h'] = [t - (HELD - 1) * EVERY * FRAME for t in times['H']]
    for k, name in NAMES.items():
        if k not in times:
            continue
        print('%-44s %s ms' % (name, ', '.join('%.1f' % (t / 8000) for t in times[k])))
    red = re.findall(r'REDRAW (\d+) (\d+) (\d+)', con)
    for n, rows, first in red:
        if int(rows):
            print('redraw check %s: %s rows unlike a full redraw (the first %s)' % (n, rows, first))
            bad = 1
    if check:
        print('redraw check: %d steps of %d, %d with a row unlike a full redraw'
              % (len(red), steps, sum(1 for r in red if int(r[1]))))
        if len(red) != steps or not steps:
            bad = 1
    if 'HUNG' in con:
        print('HUNG')
        bad = 1
    if limits:
        line, page = limits
        for k, lim in (('d', line), ('u', line), ('a', line), ('w', line), ('p', page), ('q', page), ('t', page)):
            for t in times.get(k, []):
                if t / 8000 > lim:
                    print('%s: %.1f ms, more than %g' % (NAMES[k], t / 8000, lim))
                    bad = 1
    return bad


if __name__ == '__main__':
    if sys.argv[1] == 'report':
        lim = None
        if '--max' in sys.argv:
            lim = [float(x) for x in sys.argv[sys.argv.index('--max') + 1].split(',')]
        sys.exit(report(sys.argv[2], lim, '--check' in sys.argv))
    sys.exit(main(sys.argv[1], sys.argv[2], '--check' in sys.argv))
