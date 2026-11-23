#!/usr/bin/env python3
"""Calls between a C program's banked overlays (DECISIONS V37) that do not
go through its trampoline: code in one overlay calling a function of
another overlay directly would jump into the bank that is mapped (its
own), not the callee's.

usage: check_ovl.py <dir> [<trampoline macro>]      (default XCALL)

A .c file is in overlay n if it has #pragma code-name ("OVERLAYn"), else
it is resident. Each function defined in an overlay is looked for in the
other files: a call `name(` is fine in its own overlay, and elsewhere
only as the macro's argument (`XCALL(bank, name, ...)`). Prints each bad
call; exit 1 if there is one.
"""
import os
import re
import sys


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    d = sys.argv[1]
    macro = sys.argv[2] if len(sys.argv) > 2 else 'XCALL'
    files = {}
    for n in sorted(os.listdir(d)):
        if n.endswith('.c'):
            src = open(os.path.join(d, n)).read()
            src = re.sub(r'/\*.*?\*/', lambda m: '\n' * m.group(0).count('\n'), src, flags=re.S)
            m = re.search(r'#pragma\s+code-name\s*\(\s*"OVERLAY(\d+)"', src)
            files[n] = (int(m.group(1)) if m else 0, src)
    where = {}
    for n, (ovl, src) in files.items():
        if not ovl:
            continue
        for m in re.finditer(r'^[a-z][\w \*]*?\b(\w+)\s*\([^;{]*\)\s*\{', src, re.M):
            if not m.group(0).startswith('static'):
                where[m.group(1)] = ovl
    bad = 0
    for n, (ovl, src) in files.items():
        for i, line in enumerate(src.split('\n'), 1):
            for f, fo in where.items():
                if fo == ovl:
                    continue
                for m in re.finditer(r'\b%s\s*\(' % re.escape(f), line):
                    before = line[:m.start()]
                    if re.search(r'^[a-z][\w \*]*$', before) and line.rstrip().endswith((';', ')')) \
                            and not line.rstrip().endswith('{'):
                        continue                                # a declaration
                    print('%s:%d: %s (overlay %d) called from %s' % (n, i, f, fo, 'overlay %d' % ovl if ovl
                                                                     else 'the resident part'))
                    bad = 1
            del line
    sys.exit(bad)


if __name__ == '__main__':
    main()
