#!/usr/bin/env python3
"""gate vb_files: what a session left on the card, checked on the host.

usage: check_files.py scrap FOLDER TEXT       the Text Scrap (FOLDER/VERANDA/
                                               .SYSTEM or FOLDER) as Veranda
                                               Edit writes it (DECISIONS V54:
                                               tests/check_edit.py's rules),
                                               its text TEXT ("\\n": a line end)
       check_files.py photo FOLDER W H         the Photo Scrap: W cards by H
                                               lines, its bitmap whole
       check_files.py dir LOG FOLDER           dir.bas's listings (its console
                                               lines in Run's LOG) against the
                                               folder's names
MIT licence (LICENSE)."""
import fnmatch
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'tools'))
from vbveranda2 import unpack  # noqa: E402


def scrap_file(folder, name):
    for d in (os.path.join(folder, 'VERANDA', '.SYSTEM'), folder):
        p = os.path.join(d, name + '.cvt')
        if os.path.exists(p):
            return open(p, 'rb').read()
    sys.exit('no %s in %s' % (name, folder))


def cvt(d, name, cls):
    bad = []
    if len(d) < 514:
        bad.append('short')
    elif d[0] != 0x83 or d[3:19] != name.ljust(16, b'\xa0') or d[21] != 0 or d[22] != 4:
        bad.append('its directory entry (USR, "%s", sequential, SYSTEM)' % name.decode())
    elif d[30:58] != b'PRG formatted GEOS file V1.0':
        bad.append('not a CVT file')
    elif d[254 + 75:254 + 91] != cls:
        bad.append('its class %r' % d[254 + 75:254 + 91])
    return bad


def main(argv):
    if argv[0] == 'scrap':
        d = scrap_file(argv[1], 'Text  Scrap')
        want = argv[2].replace('\\n', '\n').encode('latin-1').replace(b'\n', b'\r')
        bad = cvt(d, b'Text  Scrap', b'Text  Scrap V2.0')
        size = d[508] | d[509] << 8
        body = d[510:]
        if size != len(body) or body[:4] != bytes([23, 9, 0, 0]) or body[4:] != want:
            bad.append('its data (%d bytes, %r), want %r' % (size, body[:40], want[:40]))
        if bad:
            sys.exit('the Text Scrap: ' + '; '.join(bad))
        print('ok    the Text Scrap as Veranda Edit writes it (USR, SYSTEM, "Text  Scrap V2.0", '
              'NEWCARDSET BSW 9, CR line ends): %d bytes of text' % len(want))
        return 0
    if argv[0] == 'photo':
        d = scrap_file(argv[1], 'Photo Scrap')
        w, h = int(argv[2]), int(argv[3])
        bad = cvt(d, b'Photo Scrap', b'Photo Scrap V2.0')
        body = d[508:]
        if body[:3] != bytes([w, h & 255, h >> 8]):
            bad.append('its size %r, want %d x %d' % (body[:3], w, h))
        elif unpack(body[3:], w * h) is None:
            bad.append('its bitmap is not %d bytes compacted' % (w * h))
        if bad:
            sys.exit('the Photo Scrap: ' + '; '.join(bad))
        print('ok    the Photo Scrap: %d cards by %d lines, "Photo Scrap V2.0", the bitmap whole' % (w, h))
        return 0
    if argv[0] == 'dir':
        lines = [ln[4:].rstrip('\n') for ln in open(argv[1], encoding='latin-1') if ln.startswith('VB| ')]
        names = sorted(x + ('/' if os.path.isdir(os.path.join(argv[2], x)) else '') for x in os.listdir(argv[2]))
        got = {k: sorted(ln[len(k) + 1:] for ln in lines if ln.startswith(k + ' ')) for k in ('all', 'txt', 'three')}
        want = {'all': names,
                'txt': [x for x in names if fnmatch.fnmatch(x.lower(), '*.txt')],
                'three': [x for x in names if fnmatch.fnmatch(x.lower(), 'birds*3.txt')]}
        for k in want:
            if got[k] != want[k]:
                sys.exit('DIR$ (%s): %r, the folder has %r' % (k, got[k], want[k]))
        print('ok    DIR$: the folder\'s %d names, %d by "*.txt", %d by "birds*3.TXT", as on the host'
              % (len(names), len(want['txt']), len(want['three'])))
        return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
