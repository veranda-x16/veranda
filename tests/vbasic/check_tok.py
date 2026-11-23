#!/usr/bin/env python3
"""Gate vb_tok (DECISIONS V87), guarantee G3: the X16 tokenizer's records
equal tools/vbtokens.py's, byte for byte.

usage: check_tok.py CONSOLE.txt DIR [--errors] [--speed MIN_BYTES_PER_S]

CONSOLE.txt is VeraBASIC Run's test build's log: for each "!tok NAME" of
its VBTEST.LST a "VB TOK NAME" line, then either "VB TOKERR text" or four
"VB REC n HEX" lines and "VB TOKCYC cycles LINES n BYTES n". DIR holds the
NAME files. A program the PC tokenizer finds an error in must give
"VB TOKERR Line n: message" with the PC's first error (line and text);
any other must give the PC's four records exactly. --speed: the
tokenizer's speed over all the programs together (bytes of source a
second at 8 MHz) must be at least that.

MIT licence (LICENSE).
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'tools'))
import vbtokens as T  # noqa: E402

MHZ = 8_000_000


def expected(path):
    prog = T.check_text(open(path, 'rb').read())
    if prog.errors:
        src, msg = sorted(prog.errors, key=lambda e: e[0])[0]
        return 'Line %d: %s' % (src, msg), None
    return None, T.encode(prog)


def main(argv):
    if len(argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    log, d = argv[0], argv[1]
    speed = None
    if '--speed' in argv:
        speed = float(argv[argv.index('--speed') + 1])
    lines = open(log, 'rb').read().decode('latin-1').split('\n')
    runs = []
    cur = None
    for ln in lines:
        ln = ln.rstrip('\r')
        if ln.startswith('VB TOK '):
            cur = {'name': ln[7:], 'recs': {}, 'err': None, 'cyc': None}
            runs.append(cur)
        elif cur is None:
            continue
        elif ln.startswith('VB TOKERR '):
            cur['err'] = ln[10:]
        elif ln.startswith('VB REC '):
            n, _, hx = ln[7:].partition(' ')
            cur['recs'][int(n)] = bytes.fromhex(hx.strip())
        elif ln.startswith('VB TOKCYC '):
            f = ln.split()
            cur['cyc'] = int(f[2], 16)
            cur['bytes'] = int(f[6], 16)
            cur['lines'] = int(f[4], 16)
            cur['prof'] = f[7] if len(f) > 7 else None
    bad = 0
    nok = nerr = 0
    cyc = nbytes = 0
    for r in runs:
        p = os.path.join(d, r['name'])
        msg, recs = expected(p)
        if msg is not None:
            if r['err'] != msg:
                print('FAIL %s: the X16 says %r, the PC %r' % (r['name'], r['err'], msg))
                bad += 1
            else:
                nerr += 1
            continue
        if r['err'] is not None:
            print('FAIL %s: the X16 found an error the PC does not: %s' % (r['name'], r['err']))
            bad += 1
            continue
        for n in range(4):
            got = r['recs'].get(n)
            if got != recs[n]:
                at = next((i for i in range(min(len(got or b''), len(recs[n])))
                           if got[i] != recs[n][i]), min(len(got or b''), len(recs[n])))
                print('FAIL %s: record %d differs at byte %d (X16 %d bytes, PC %d): X16 %s PC %s' % (
                    r['name'], n, at, len(got or b''), len(recs[n]),
                    (got or b'')[max(0, at - 4):at + 8].hex(' '), recs[n][max(0, at - 4):at + 8].hex(' ')))
                bad += 1
                break
        else:
            nok += 1
            if r['cyc']:
                cyc += r['cyc']
                nbytes += r['bytes']
    rate = nbytes / (cyc / MHZ) if cyc else 0
    print('%d programs: %d byte for byte as vbtokens.py (records 0-3), %d with the PC\'s first error; '
          '%d bytes of source in %.3f s at 8 MHz: %.0f bytes a second' % (
              len(runs), nok, nerr, nbytes, cyc / MHZ, rate))
    if speed is not None and rate < speed:
        print('FAIL the speed: %.0f bytes a second (%.0f at least)' % (rate, speed))
        bad += 1
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
