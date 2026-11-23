#!/usr/bin/env python3
"""gate edit: Veranda Edit's three parts call each other only as they may
(apps/edit/misc.c): overlay 1 is mapped for good, overlay 2 only through
call2(), so code in main RAM or in overlay 2 must not call into overlay
1 (main RAM code may run for overlay 2), nor main RAM or overlay 1 into
overlay 2 directly. A static check of the C sources: each file's
functions, which part they are in (its "#pragma code-name"; textkit's
sources, sdk/lib/textkit, by the part apps/edit/Makefile compiles each
into: TK_MAIN, TK_OVL1, TK_OVL2), what they call.

usage: check_edit_banks.py <apps/edit>
"""
import os
import re
import sys

FN = re.compile(r'^(?:static\s+)?(?:const\s+)?(?:unsigned\s+|signed\s+)?(?:void|char|int|long)\s*\*?\s*'
                r'(?:__fastcall__\s+)?(\w+)\s*\(([^;{]*?)\)\s*\{(.*?)^\}', re.M | re.S)


def part(src):
    m = re.search(r'#pragma\s+code-name\s*\(\s*"OVERLAY(\d)"', src)
    return int(m.group(1)) if m else 0


def tk_parts(d):
    """textkit's sources (DECISIONS V93) and their parts, from the Makefile"""
    mk = open(os.path.join(d, 'Makefile')).read()
    parts = {}
    for var, p in (('TK_MAIN', 0), ('TK_OVL1', 1), ('TK_OVL2', 2)):
        m = re.search(r'^%s\s*:=\s*(.*)$' % var, mk, re.M)
        for n in (m.group(1).split() if m else []):
            parts[n + '.c'] = p
    return parts


def main():
    d = sys.argv[1]
    tk = os.path.join(d, '..', '..', 'sdk', 'lib', 'textkit')
    tkp = tk_parts(d)
    files = [(d, f, None) for f in sorted(os.listdir(d)) if f.endswith('.c')]
    files += [(tk, f, p) for f, p in sorted(tkp.items())]
    defs, bodies = {}, []
    for fd, f, tp0 in files:
        src = open(os.path.join(fd, f)).read()
        src = re.sub(r'/\*.*?\*/', '', src, flags=re.S)
        p = part(src) if tp0 is None else tp0
        for m in FN.finditer(src):
            defs[m.group(1)] = (f, p)
            bodies.append((f, p, m.group(1), m.group(3)))
    bad = []
    for f, p, fn, body in bodies:
        for c in set(re.findall(r'\b(\w+)\s*\(', body)):
            if c not in defs or c == fn:
                continue
            tf, tp = defs[c]
            if (fn, c) == ('main', 'a_main'):
                continue                # (the start: overlay 1 mapped first)
            if tp == 1 and p in (0, 2):
                bad.append('%s: %s (%s) calls %s (overlay 1)' % (f, fn, 'main RAM' if p == 0 else 'overlay 2', c))
            if tp == 2 and p in (0, 1):
                bad.append('%s: %s calls %s (overlay 2) directly, not through call2' % (f, fn, c))
    for b in bad:
        print('check_edit_banks:', b)
    if bad:
        sys.exit(1)
    print('ok    the overlays: %d functions, no call into a bank that may not be mapped' % len(defs))


if __name__ == '__main__':
    main()
