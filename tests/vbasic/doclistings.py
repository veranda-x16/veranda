#!/usr/bin/env python3
"""gate vb_core: every listing of the manual's chapters, as a program.

usage: doclistings.py OUT_DIR FILE.md...

Each fenced ```basic block of the files becomes OUT_DIR/<file>_<n>.bas
(n from 1); a ```keys block right after one gives the keys typed while it
runs (<file>_<n>.key, a line end is Return), a ```mouse block its mouse
script (<file>_<n>.ms: tests/vbasic/ui_mouse.py). Blocks marked ```basic
nocheck (a fragment that is not a whole program) are left out. Prints
the names. MIT licence (LICENSE).
"""
import os
import re
import sys


def main(argv):
    if len(argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    out = argv[0]
    os.makedirs(out, exist_ok=True)
    n_all = 0
    for path in argv[1:]:
        base = re.sub(r'[^a-z0-9]', '', os.path.basename(path).rsplit('.', 1)[0].lower())[:8]
        text = open(path, encoding='utf-8').read()
        blocks = re.findall(r'^```(\w+)([^\n]*)\n(.*?)^```', text, re.S | re.M)
        n = 0
        last = None
        for kind, rest, body in blocks:
            if kind == 'basic' and 'nocheck' not in rest:
                n += 1
                last = '%s_%d' % (base, n)
                open(os.path.join(out, last + '.bas'), 'w', encoding='latin-1').write(body)
                print(last)
                n_all += 1
            elif kind == 'keys' and last:
                open(os.path.join(out, last + '.key'), 'w', encoding='latin-1').write(body)
                last = None
            elif kind == 'mouse' and last:
                open(os.path.join(out, last + '.ms'), 'w', encoding='latin-1').write(body)
                last = None
            else:
                last = None
    print('%d listings' % n_all, file=sys.stderr)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
