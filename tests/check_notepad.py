#!/usr/bin/env python3
"""gate notepad: Paint, Note Pad over it, Paint again (tests/desk_script.py,
tests/note_script.py).

usage: check_notepad.py <run dir> first|second

The console in order (the pages turned: "NOTE PAGE n of m"); both
screens and the colour map when GetFile returned equal those when the
accessory opened (PRE.RAW, POST.RAW, PRE.MAP, POST.MAP: Paint's test
build writes them in its folder); the Note File in VERANDA/.SYSTEM: a VLIR CVT
file of type APPL_DATA, class "Note File   V1.0", whose records are the
pages typed (tests/note_script.py's PAGES).
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import note_script  # noqa: E402

failures = 0


def check(cond, what):
    global failures
    print(('ok    ' if cond else 'FAIL  ') + what)
    if not cond:
        failures += 1


def records(d):
    """a VLIR CVT file's records"""
    tab = d[508:762]
    out = []
    off = 762
    for i in range(0, 254, 2):
        blocks, last = tab[i], tab[i + 1]
        if blocks == 0 and last == 0:
            break
        if blocks == 0:
            out.append(None)
            continue
        n = (blocks - 1) * 254 + last - 1
        out.append(d[off:off + n])
        off += blocks * 254
    return out


def main():
    run, which = sys.argv[1], sys.argv[2]
    con = open(os.path.join(run, 'console.txt'), 'rb').read().decode('latin-1')
    if which == 'first':
        want = ['PAINT RUNNING', 'NOTE RUNNING 1 1', 'NOTE PAGE 2 2', 'NOTE PAGE 3 3', 'NOTE PAGE 2 3',
                'NOTE PAGE 2 2', 'NOTE CLOSED', 'PAINT DESK BACK']
    else:
        want = ['PAINT RUNNING', 'NOTE RUNNING 1 2', 'NOTE PAGE 2 2', 'NOTE CLOSED', 'PAINT DESK BACK']
    i = 0
    for w in want:
        j = con.find(w, i)
        if j < 0:
            break
        i = j + len(w)
    else:
        w = None
    check(w is None, 'the console in order: %s%s' % (', '.join(want), '' if w is None else ' (not: %s)' % w))
    same = all(os.path.exists(os.path.join(run, n)) for n in ('PRE.RAW', 'POST.RAW', 'PRE.MAP', 'POST.MAP'))
    if same:
        for a, b in (('PRE.RAW', 'POST.RAW'), ('PRE.MAP', 'POST.MAP')):
            same = same and open(os.path.join(run, a), 'rb').read() == open(os.path.join(run, b), 'rb').read()
    check(same, 'both screens and the colour map when GetFile returned equal those when Note Pad opened '
          '(in Paint\'s folder: Note Pad went back to it)')
    p = os.path.join(run, 'VERANDA', '.SYSTEM', 'Note File.cvt')
    d = open(p, 'rb').read() if os.path.exists(p) else b''
    check(len(d) > 762 and d[21] == 1 and d[22] == 7 and d[254 + 75:254 + 91] == b'Note File   V1.0',
          'VERANDA/.SYSTEM/Note File.cvt: a record file of type APPL_DATA, class "Note File   V1.0"')
    pages = [r.decode('latin-1') if r else '' for r in records(d)] if d else []
    check(pages == note_script.PAGES, 'its records are the pages typed: %r' % pages)
    if failures:
        sys.exit(1)


if __name__ == '__main__':
    main()
