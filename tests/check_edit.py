#!/usr/bin/env python3
"""gate edit: what Veranda Edit's session (tests/edit_script.py) left.

usage: check_edit.py <run folder> [--partial]

The console's "EDIT STATE" lines against expect.json's states (the line,
the column, the size, the lines, modified, the selection, the line ends,
the name); the files the session saved against the model's text, byte
for byte (their line ends too); the Text Scrap the session wrote (in
VERANDA/.SYSTEM: a GEOS SYSTEM file of class "Text  Scrap V2.0", its data a
length, a NEWCARDSET, the text with CR line ends); no HUNG. The TIME
lines are printed. The cursor's blink (tests/check_blink.py: 30 frames
shown, 30 hidden, the main loop fast and slowed). --partial: a session stopped early (a screenshot):
the states logged so far only.
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_blink  # noqa: E402

FIELDS = ('n', 'line', 'col', 'len', 'lines', 'modified', 'lo', 'hi', 'top', 'eol')


def main():
    run = sys.argv[1]
    partial = '--partial' in sys.argv
    exp = json.load(open(os.path.join(run, 'expect.json')))
    con = open(os.path.join(run, 'console.txt'), 'rb').read().decode('latin-1')
    got = {}
    times = []
    bad = []
    for line in con.split('\n'):
        i = line.find('EDIT STATE ')
        if i >= 0:
            p = line[i + 11:].split(' ', len(FIELDS))
            v = {k: int(x, 16) for k, x in zip(FIELDS, p)}
            v['name'] = p[len(FIELDS)].strip() if len(p) > len(FIELDS) else ''
            got[v['n']] = v
        i = line.find('TIME ')
        if i >= 0:
            times.append(line[i + 5:].strip())
    if 'HUNG' in con:
        bad.append('the session hung (HUNG)')
    for n, want in exp['states']:
        g = got.get(n)
        if g is None:
            if not partial:
                bad.append('state %d: not logged' % n)
            continue
        for k, v in want.items():
            if g.get(k) != v:
                bad.append('state %d: %s %r, want %r' % (n, k, g.get(k), v))
    if not partial:
        for name, text in exp['files'].items():
            p = os.path.join(run, name)
            want = text.encode('latin-1')
            d = open(p, 'rb').read() if os.path.exists(p) else None
            if d != want:
                if d is None:
                    bad.append('%s: missing' % name)
                else:
                    i = next((i for i in range(min(len(d), len(want))) if d[i] != want[i]), min(len(d), len(want)))
                    bad.append('%s: %d bytes, want %d; first difference at %d: %r, want %r'
                               % (name, len(d), len(want), i, d[i - 10:i + 20], want[i - 10:i + 20]))
        p = os.path.join(run, 'VERANDA', '.SYSTEM', 'Text  Scrap.cvt')
        d = open(p, 'rb').read() if os.path.exists(p) else b''
        want = exp['scrap'].encode('latin-1').replace(b'\n', b'\r')
        if len(d) < 514:
            bad.append('the Text Scrap: missing or short')
        else:
            if d[0] != 0x83 or d[3:19] != b'Text  Scrap'.ljust(16, b'\xa0') or d[21] != 0 or d[22] != 4:
                bad.append('the Text Scrap: its directory entry (USR, "Text  Scrap", sequential, SYSTEM)')
            if d[30:58] != b'PRG formatted GEOS file V1.0':
                bad.append('the Text Scrap: not a CVT file')
            if d[254 + 75:254 + 91] != b'Text  Scrap V2.0':
                bad.append('the Text Scrap: its class %r' % d[254 + 75:254 + 91])
            size = d[508] | d[509] << 8
            body = d[510:]
            if size != len(body) or body[:4] != bytes([23, 9, 0, 0]) or body[4:] != want:
                bad.append('the Text Scrap: its data (%d bytes, %r ...), want %d bytes' % (size, body[:24], len(want) + 4))
    if not partial:
        # the dialog's lines (sdk/lib/vrchoose.c), in this order ('*': any number)
        lines = [l[l.find('VRF '):].strip() for l in con.split('\n') if 'VRF ' in l]
        i, last = 0, 0
        for w in exp.get('vrf', []):
            def match(l):
                if ' ? ' in w:
                    a, b = w.split(' ? ')
                    p = l[len(a) + 1:].split(' ', 1) if l.startswith(a + ' ') else []
                    return len(p) == 2 and p[1] == b and p[0].isdigit()
                if ' * ' not in w:
                    return l == w
                a, b = w.split(' * ')
                p = l[len(a) + 1:].split(' ', 1) if l.startswith(a + ' ') else []
                return len(p) == 2 and p[1] == b and p[0].isdigit() and int(p[0]) > last
            while i < len(lines) and not match(lines[i]):
                i += 1
            if i == len(lines):
                bad.append('the dialog: no %r after the ones before it' % w)
                break
            if lines[i].startswith('VRF SHOW '):
                last = int(lines[i].split()[2])
            i += 1
    bb, blink = check_blink.check(con, 30, 30)
    bad += bb
    for t in times:
        print('time  ', t)
    for b in bad:
        print('check_edit:', b)
    if bad:
        sys.exit(1)
    print('ok   ', blink)
    print('ok    the session: %d states as the model, %s' % (
        len([n for n, _ in exp['states'] if n in got]),
        'stopped at %s' % exp['stop'] if partial else '%d files saved byte for byte, the Text Scrap' % len(exp['files'])))


if __name__ == '__main__':
    main()
