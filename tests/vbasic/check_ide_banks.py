#!/usr/bin/env python3
"""gate vb_ide: VeraBASIC's editor (apps/vbasic/ide) calls across its banks
only as it may (ide/ide.h): code in a bank calls LOW (its main RAM part)
and its own bank; another bank's function only through xcall (XCALL),
which maps it. A static check of the C sources: each function, the bank
apps/vbasic/Makefile compiles its file into (IDE_LOW, IDE_B1 ... IDE_B8;
textkit's sources from sdk/lib/textkit), what it calls by name.

usage: check_ide_banks.py apps/vbasic
MIT licence (LICENSE)."""
import os
import re
import sys

FN = re.compile(r'^(?:static\s+)?(?:const\s+)?(?:unsigned\s+|signed\s+)?(?:void|char|int|long)\s*\*?\s*'
                r'(?:__fastcall__\s+)?(\w+)\s*\(([^;{]*?)\)\s*\{(.*?)^\}', re.M | re.S)


# functions a bank's file puts in LOW (#pragma code-name: textkit's TK_PUT_SEG)
LOW_TOO = ('tk_put_ul', 'tk_put_s')


def main():
    d = sys.argv[1]
    mk = open(os.path.join(d, 'Makefile')).read()
    tk = os.path.join(d, '..', '..', 'sdk', 'lib', 'textkit')
    parts = {}
    for m in re.finditer(r'^IDE_(LOW|B\d+)\s*:=\s*(.*)$', mk, re.M):
        for n in m.group(2).split():
            parts[n] = m.group(1)
    defs, bodies = {}, []
    for n, part in sorted(parts.items()):
        path = os.path.join(d, 'ide', n + '.c')
        if not os.path.exists(path):
            path = os.path.join(tk, n + '.c')
        if not os.path.exists(path):
            continue                    # (the SDK's scrap sources: their own calls only)
        src = re.sub(r'/\*.*?\*/', '', open(path).read(), flags=re.S)
        src = re.sub(r'^#.*$', '', src, flags=re.M)
        for m in FN.finditer(src):
            defs.setdefault(m.group(1), {})[n] = part
            bodies.append((n, part, m.group(1), m.group(3)))
    for name in LOW_TOO:
        for n in defs.get(name, {}):
            defs[name][n] = 'LOW'
    bad = []
    for f, part, fn, body in bodies:
        body = re.sub(r'XCALL\s*\(\s*\w+\s*,\s*\w+\s*\)', '', body)
        for c in set(re.findall(r'\b(\w+)\s*\(', body)):
            if c not in defs or c == fn:
                continue
            tf = f if f in defs[c] else sorted(defs[c])[0]
            tp = defs[c][tf]
            if tp != 'LOW' and tp != part:
                bad.append('%s.c: %s (%s) calls %s (%s, %s.c) directly' % (f, fn, part, c, tp, tf))
    for b in bad:
        print('check_ide_banks:', b)
    if bad:
        sys.exit(1)
    print('ok    the editor\'s banks: %d functions, every call to another bank through xcall' % len(defs))


if __name__ == '__main__':
    main()
