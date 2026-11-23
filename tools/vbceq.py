#!/usr/bin/env python3
"""VeraBASIC Run's C overlays (apps/vbasic/vbc.cfg; DECISIONS V90): what the
second link takes from the first.

The Open and Save dialog, the clipboard and the tile are C (the SDK's
vrchoose.c, scrap*.c, vrtile.c), linked by a link of their own into two RAM
banks (records 10 and 11). Every symbol the main link exports below $A000
(cc65's runtime, the C library, the kernel's bindings, the theme, the zero
page) is given to that link as an absolute equate here, so the second link
uses the main program's copies; what main RAM has not got is linked from
the libraries into the banks, to be copied into main RAM (the console's
font, free while a box is open) for the call.

Only exported symbols: the label file (ld65 -Ln) also has a module's own
labels (condes.o's "jmpvec" is a JSR, the runtime's a JMP), so the exports
are read from the modules the map lists (od65; a library's members taken
out with ar65), their addresses from the label file.

usage: vbceq.py vbrun.lbl vbrun.map OUT.s     the equates (ca65)
       vbceq.py --defs vbrun.lbl               cl65 -Wl -D options: the font's
                                               and the scratch's addresses
       vbceq.py vbide.lbl vbide.map OUT.s --lc  the same, cc65's __lower names
                                               too (VeraBASIC's editor)
       vbceq.py --ide vbide.lbl                the same: VeraBASIC's editor's
                                               main RAM part's place (ide/ide.cfg)
MIT licence (LICENSE)."""
import os
import re
import subprocess
import sys
import tempfile


def labels(path):
    out = {}
    for ln in open(path):
        m = re.match(r'al ([0-9A-F]{6}) \.([A-Za-z_][A-Za-z0-9_]*)$', ln.strip())
        if m and m.group(2) not in out:
            out[m.group(2)] = int(m.group(1), 16)
    return out


def exports(obj):
    r = subprocess.run(['od65', '--dump-exports', obj], capture_output=True, text=True, check=True)
    return set(re.findall(r'Name:\s+"([^"]+)"', r.stdout))


def modules(mapfile):
    """the map's modules: object files, (library, member) pairs"""
    text = open(mapfile).read().split('Segment list:')[0]
    objs, members = [], []
    for ln in text.split('\n'):
        m = re.match(r'^(\S.*\.o\)?):$', ln)
        if not m:
            continue
        name = m.group(1)
        lm = re.match(r'^(.*)\((.*\.o)\)$', name)
        if lm:
            members.append((lm.group(1), lm.group(2)))
        else:
            objs.append(name)
    return objs, members


def main(argv):
    if argv and argv[0] == '--ide':     # VeraBASIC's editor (DECISIONS V93): its main RAM part's place
        lb = labels(argv[1])
        print('-Wl -D,__IDELOW__=0x%04X -Wl -D,__IDESIZE__=0x%04X -Wl -D,__IDEDYN__=0x%04X '
              '-Wl -D,_IDEDYN=0x%04X -Wl -D,__VRWIN__=0x%04X -Wl -D,__VRTITLE__=0x%04X -Wl -D,__VRSTATUS__=0x%04X'
              % (lb['_ide_s0'], lb['_ide_s1'] - lb['_ide_s0'], lb['__BSS_RUN__'] + lb['__BSS_SIZE__'], lb['__BSS_RUN__'] + lb['__BSS_SIZE__'],
                 lb['_vr_win'], lb['_vr_win_title'], lb['_vr_win_status']))
        return 0
    if argv and argv[0] == '--defs':
        lb = labels(argv[1])
        print('-Wl -D,__LOWSTART__=0x%04X -Wl -D,__SCRSTART__=0x%04X' % (lb['_vb_font'], lb['_vb_scratch']))
        return 0
    lc = '--lc' in argv                 # (the editor's link: the runtime's __lower names too, __bzero)
    argv = [a for a in argv if a != '--lc']
    lb = labels(argv[0])
    objs, members = modules(argv[1])
    names = set()
    for o in objs:
        if not os.path.exists(o):       # (the map names them without their folder)
            o = os.path.join(os.path.dirname(argv[1]), os.path.basename(o))
        names |= exports(o)
    with tempfile.TemporaryDirectory() as t:
        libs = {}
        for lib, mem in members:
            libs.setdefault(lib, []).append(mem)
        for lib, mems in libs.items():
            subprocess.run(['ar65', 'x', os.path.abspath(lib)] + sorted(set(mems)), cwd=t, check=True)
            for mem in set(mems):
                names |= exports(os.path.join(t, mem))
    lines = []
    for name in sorted(names):
        a = lb.get(name)
        if a is None or a >= 0xA000 or (name.startswith('__') and name != '__STARTUP__'
                                         and not (lc and not name.isupper())):
            continue
        lines.append('%s = $%04X\n%s %s\n' % (name, a, '.exportzp' if a < 0x100 else '.export', name))
    open(argv[2], 'w').write("; vbceq.py: the main link's exports below $A000\n" + ''.join(lines))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
