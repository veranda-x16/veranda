#!/usr/bin/env python3
"""Build the Veranda kernel: VERANDA.PRG and VERANDA.SYS.

usage: kbuild.py [--out build] [-D NAME=VALUE ...] [--sysfont font.bin]

1. api/veranda.api -> build/gen (tools/apigen.py)
2. kernel/exports.txt (which bank has which routine) -> build/kgen:
   far.inc (F_<name> = bank * 256 + index), stubs.s (the resident entry of
   every banked API call: FARCALL), notyet.s (API calls without code yet:
   k_Unsupported), entries_<bank>.s (each bank's table of jmp at $A000)
3. assemble kernel/res, kernel/<bank>/*.s
4. link the resident core ($8800-$9EFF, cfg/resident.cfg) first; then
   each bank alone at $A000 (cfg/bank.cfg) against the resident core's
   exported symbols only: a direct reference to another bank's code does
   not link (use FARCALL)
5. VERANDA.SYS: two header bytes, then the banks in order (8 KB each:
   G, G2, U, F, S, X, P, T, W);
   VERANDA.PRG: loader/loader.s with the resident image
Prints the sizes. -D passes a define to every source (test builds).
--sysfont: a GEOS font file as the system font, without the fast path
(gate ui: GEOS 64's font, built from the reference at gate time).
"""
import os
import re
import subprocess
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
BANKS = ['G', 'G2', 'U', 'F', 'S', 'X', 'P', 'T', 'W', 'C']    # logical order: kernel.inc BANK_*
DIRS = {'R': 'res', 'G': 'g', 'G2': 'g2', 'U': 'u', 'F': 'f', 'S': 's', 'X': 'x', 'P': 'p', 'T': 't', 'W': 'w', 'C': 'c'}
# bank W (the switcher, DECISIONS V83) puts aside a program's state that
# lives in other banks' variables: it is assembled after those banks are
# linked, with their addresses (kgen/kvars.inc: <bank>_<name> = $xxxx), and
# reaches them with BankCopy. Only these, each exported by its module:
KVARS = {'F': ['RecVars', 'RecVarsEnd', 'LdVars', 'LdVarsEnd', 'StrOpen', 'StrDir'],
         'S': ['kColorOn', 'kCov', 'isDesk'], 'U': ['UnderFree']}
LATE_BANKS = ('W', 'C')         # (V165: bank C, the canvas, writes bank S's and U's too)


def run(cmd):
    r = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
    if r.returncode:
        sys.stderr.write(r.stdout + r.stderr)
        raise SystemExit('kbuild: failed: %s' % ' '.join(cmd))
    return r.stdout


def exports_of(obj):
    out = run(['od65', '--dump-exports', obj])
    return set(re.findall(r'Name:\s+"([^"]+)"', out))


def main():
    a = sys.argv[1:]
    out = os.path.join(ROOT, a[a.index('--out') + 1]) if '--out' in a else os.path.join(ROOT, 'build')
    defs = []
    for i, x in enumerate(a):
        if x == '-D':
            defs += ['-D', a[i + 1]]
    gen, kgen, kobj = os.path.join(out, 'gen'), os.path.join(out, 'kgen'), os.path.join(out, 'k')
    for d in (gen, kgen, kobj):
        os.makedirs(d, exist_ok=True)
    run(['python3', '-I', '-B', 'tools/apigen.py', 'api/veranda.api', gen])
    run(['python3', '-I', '-B', 'tools/mkfont.py', os.path.join(kgen, 'system.bin')])
    run(['python3', '-I', '-B', 'tools/mkfont.py', '--ui', os.path.join(kgen, 'uifont.bin')])
    run(['python3', '-I', '-B', 'tools/mkicons.py', os.path.join(kgen, 'sysicons.inc')])
    run(['python3', '-I', '-B', 'tools/mkfax.py', os.path.join(kgen, 'faxcodes.inc')])
    run(['python3', '-I', '-B', 'tools/mkpointers.py', os.path.join(kgen, 'pointers.inc')])
    run(['python3', '-I', '-B', 'tools/mksounds.py', os.path.join(kgen, 'sounds.inc')])
    if '--sysfont' in a:
        font = open(a[a.index('--sysfont') + 1], 'rb').read()
        open(os.path.join(kgen, 'system.bin'), 'wb').write(font)
        defs += ['-D', 'NOFASTFONT']
    impl = [x for x in open(os.path.join(gen, 'impl.txt')).read().split() if x]

    # where each routine lives
    where, order, nostub = {}, {b: [] for b in ['R'] + BANKS}, set()
    for n, line in enumerate(open(os.path.join(ROOT, 'kernel', 'exports.txt')), 1):
        line = line.split('#', 1)[0].split()
        if not line:
            continue
        b, names = line[0], line[1:]
        if b not in order:
            raise SystemExit('kernel/exports.txt:%d: unknown bank %s' % (n, b))
        for nm in names:
            if nm.startswith('-'):      # (V141) an entry in its bank's table only: no resident
                nm = nm[1:]             # stub (the core is full); called through FarGo by hand
                nostub.add(nm)
            if nm in where:
                raise SystemExit('kernel/exports.txt:%d: %s listed twice' % (n, nm))
            where[nm] = b
            order[b].append(nm)
    for b in BANKS:
        if len(order[b]) > 85:
            raise SystemExit('bank %s: more than 85 entries' % b)

    w = lambda n, t: open(os.path.join(kgen, n), 'w').write(t)   # noqa: E731
    # a resident stub for every banked routine (kernel/res/farcall.s)
    stubs = ['; generated: resident stubs of the banked routines (kernel/res/farcall.s)',
             '.include "kernel.inc"', '.import FarGo, gA, gT', '.segment "CODE"']
    # 8 bytes a stub: the entry's offset, then the bank's shared tail (its
    # bank number to FarGo); 3 cycles more than a stub with its own tail
    for b in BANKS:
        if not order[b]:
            continue
        k = BANKS.index(b)
        if all(nm in nostub for nm in order[b]):    # (V165: bank C, no resident stubs, no tail:
            for i, nm in enumerate(order[b]):       # bank S's GoC reaches it)
                stubs += ['.export E_%s' % nm, 'E_%s = $A000 + %d' % (nm, 3 * i)]
            continue
        stubs += ['.export Tail%d' % k, 'Tail%d:' % k, '\tsta gT', '\tlda #%d' % k, '\tjmp FarGo']
        for i, nm in enumerate(order[b]):
            if nm not in nostub:
                stubs += ['.export S_%s' % nm, 'S_%s:' % nm, '\tsta gA', '\tlda #%d' % (3 * i),
                          '\tjmp Tail%d' % k]
            # its entry in the bank's table, for code that maps the bank
            # itself (the interrupt: kernel/res/irq.s)
            stubs += ['.export E_%s' % nm, 'E_%s = $A000 + %d' % (nm, 3 * i)]
    notyet = ['; generated: API calls without code yet', '.include "kernel.inc"', '.import k_Unsupported',
              '.segment "CODE"']
    for nm in impl:
        b = where.get(nm)
        if b is None:
            notyet += ['.export %s' % nm, '%s = k_Unsupported' % nm]     # (no jmp of its own: 3 bytes each, V80)
        elif b != 'R':
            stubs += ['.export %s' % nm, '%s = S_%s' % (nm, nm)]
    w('stubs.s', '\n'.join(stubs) + '\n')
    w('notyet.s', '\n'.join(notyet) + '\n')
    for b in BANKS:
        e = ['; generated: bank %s entry table at $A000' % b, '.segment "ENTRY"']
        for nm in order[b]:
            e += ['.import %s' % nm, '\tjmp %s' % nm]
        w('entries_%s.s' % b, '\n'.join(e) + '\n')

    inc = ['-I', os.path.join(ROOT, 'inc'), '-I', gen, '-I', kgen, '-I', os.path.join(ROOT, 'kernel'),
           '--bin-include-dir', kgen] + defs

    def asm(src, obj):
        run(['ca65', '--cpu', '65C02'] + inc + [src, '-o', obj])
        return obj

    objs = {b: [] for b in ['R'] + BANKS}

    def assemble(b):
        d = DIRS[b]
        sd = os.path.join(ROOT, 'kernel', d)
        if os.path.isdir(sd):
            for f in sorted(os.listdir(sd)):
                if f.endswith('.s'):
                    objs[b].append(asm(os.path.join(sd, f), os.path.join(kobj, '%s_%s.o' % (d, f[:-2]))))
        # every listed routine must be exported by its bank
        have = set()
        for o in objs[b]:
            have |= exports_of(o)
        missing = [nm for nm in order[b] if nm not in have]
        if missing:
            raise SystemExit('kbuild: bank %s does not define %s' % (b, ' '.join(missing)))
    for b in ['R'] + BANKS:
        if b not in LATE_BANKS:
            assemble(b)
    res = objs['R'] + [asm(os.path.join(gen, 'jumptab.s'), os.path.join(kobj, 'jumptab.o')),
                       asm(os.path.join(kgen, 'stubs.s'), os.path.join(kobj, 'stubs.o')),
                       asm(os.path.join(kgen, 'notyet.s'), os.path.join(kobj, 'notyet.o'))]
    run(['ld65', '-C', 'cfg/resident.cfg', '-o', os.path.join(kobj, 'resident.bin'),
         '-Ln', os.path.join(kobj, 'resident.lab'), '-m', os.path.join(kobj, 'resident.map')] + res)
    labels = {}
    for line in open(os.path.join(kobj, 'resident.lab')):
        f = line.split()
        labels[f[2].lstrip('.')] = int(f[1], 16)
    resexp = set()                              # what the resident core implements itself
    for o in objs['R']:
        resexp |= exports_of(o)
    resexp |= set('S_' + nm for b in BANKS for nm in order[b] if nm not in nostub)   # and the stubs
    resexp |= set('E_' + nm for nm in nostub)  # (and the stubless entries: V141, with
    resexp |= set('Tail%d' % BANKS.index(where[nm]) for nm in nostub
                  if not all(n in nostub for n in order[where[nm]]))    # their banks' tails)
    syms = ['; generated: the resident core\'s exports, for the banks and the loader']
    for nm in sorted(resexp):
        syms += ['.export %s' % nm, '%s = $%04X' % (nm, labels[nm])]
    w('ressyms.s', '\n'.join(syms) + '\n')
    ressyms = asm(os.path.join(kgen, 'ressyms.s'), os.path.join(kobj, 'ressyms.o'))

    sizes = []
    image = bytearray([0x00, 0xA0])             # LOAD skips two header bytes
    for b in BANKS:
        if b in LATE_BANKS:
            kv = ['; generated: other banks\' variables for bank %s (tools/kbuild.py KVARS)' % b]
            for ob, names in KVARS.items():
                lab = {}
                for line in open(os.path.join(kobj, 'bank_%s.lab' % ob)):
                    f = line.split()
                    lab[f[2].lstrip('.')] = int(f[1], 16)
                for nm in names:
                    if nm not in lab:
                        raise SystemExit('kbuild: bank %s does not export %s (KVARS)' % (ob, nm))
                    kv.append('%s_%s = $%04X' % (ob, nm, lab[nm]))
            w('kvars.inc', '\n'.join(kv) + '\n')
            assemble(b)
        ent = asm(os.path.join(kgen, 'entries_%s.s' % b), os.path.join(kobj, 'entries_%s.o' % b))
        bb = os.path.join(kobj, 'bank_%s.bin' % b)
        run(['ld65', '-C', 'cfg/bank.cfg', '-o', bb, '-Ln', os.path.join(kobj, 'bank_%s.lab' % b),
             '-m', os.path.join(kobj, 'bank_%s.map' % b), ent] + objs[b] + [ressyms])
        data = open(bb, 'rb').read()
        image += data
        u = used(os.path.join(kobj, 'bank_%s.map' % b))
        if b == 'G' and u > 0x2000 - 2 * 97:
            raise SystemExit('kbuild: bank G (%d bytes) reaches IDX_COPY, its last 194 bytes (kernel.inc)' % u)
        if b == 'C' and u > 0x1F00:
            raise SystemExit('kbuild: bank C (%d bytes) reaches C_TASKMSK, its last page (kernel.inc, V183)' % u)
        sizes.append('%s %d' % (b, u))
    # (the results written whole under another name, then renamed: a gate
    # copying them while another gate builds never gets half a kernel, V106)
    # (each run its own names, so two builds at once, make -j, never rename
    # each other's files, V108)
    tmp = '.new%d' % os.getpid()
    open(os.path.join(out, 'VERANDA.SYS' + tmp), 'wb').write(image)

    run(['ca65', '--cpu', '65C02'] + inc + ['--bin-include-dir', kobj, os.path.join(ROOT, 'loader', 'loader.s'),
         '-o', os.path.join(kobj, 'loader.o')])
    lo = os.path.join(kobj, 'loader.o')
    run(['ld65', '-C', 'cfg/loader.cfg', '-o', os.path.join(out, 'VERANDA.PRG' + tmp), lo, ressyms])
    run(['ca65', '--cpu', '65C02'] + inc + [os.path.join(ROOT, 'loader', 'rboot.s'), '-o', os.path.join(kobj, 'rboot.o')])
    run(['ld65', '-C', 'cfg/rboot.cfg', '-o', os.path.join(out, 'RBOOT' + tmp), os.path.join(kobj, 'rboot.o')])
    for f in ('VERANDA.SYS', 'VERANDA.PRG', 'RBOOT'):
        os.replace(os.path.join(out, f + tmp), os.path.join(out, f))
    rsize = os.path.getsize(os.path.join(kobj, 'resident.bin'))
    print('kbuild: resident core %d of %d bytes ($8800-$%04X); banks (bytes used): %s; VERANDA.PRG %d bytes, RBOOT %d'
          % (rsize, 0x1700, 0x8800 + rsize - 1, ', '.join(sizes), os.path.getsize(os.path.join(out, 'VERANDA.PRG')),
             os.path.getsize(os.path.join(out, 'RBOOT'))))


def used(mapfile):
    """bytes from $A000 to the end of the last segment (with variables)"""
    end = 0xA000
    tail = 0
    seg = False
    for line in open(mapfile):
        if line.startswith('Segment list:'):
            seg = True
            continue
        if seg:
            m = re.match(r'^(\w+)\s+([0-9A-F]{6})\s+([0-9A-F]{6})\s+([0-9A-F]{6})', line)
            if m and m.group(1) == 'TAIL':      # (bank T's code after RBIMG, V81: its bytes)
                tail = int(m.group(4), 16)
            elif m and int(m.group(4), 16) and m.group(1) != 'RBIMG':   # (bank T's fixed $BC00-$BFFF, V64)
                end = max(end, int(m.group(3), 16) + 1)
            elif line.startswith('Exports list') or line.startswith('Imports list'):
                break
    return end - 0xA000 + tail


if __name__ == '__main__':
    main()
