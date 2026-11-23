#!/usr/bin/env python3
"""Generate Veranda's API files from api/veranda.api.

usage: apigen.py <api file> <out dir> [--doc docs/API.md]

Writes into <out dir>:
  veranda.inc    assembly: calls, variables (with byte views), constants
  jumptab.s      the kernel's jump tables (classic at CLASSIC_BASE, wide and
                 new at NEW_BASE); entry NAME jumps to k_NAME, a dropped
                 GEOS call to k_Unsupported
  impl.txt       the k_ names the kernel must define (one per line)
  veranda.h      C header: prototypes, variables, constants
  veranda_c.s    C bindings for cc65: one function per call that moves the
                 arguments into the registers and calls the jump table
and, with --doc, the reference.

Checks (exit status 1 on a problem): unique names; classic slots on GEOS's
3-byte grid, in increasing order, below NEW_BASE; the new table inside the
resident core; variables inside their areas and not overlapping; register
names and types known.
"""
import os
import re
import sys

REGS = {('r%d' % i): 2 + 2 * i for i in range(16)}
TYPES = {'u8': ('unsigned char', 1), 'i8': ('signed char', 1), 'u16': ('unsigned int', 2),
         'i16': ('int', 2), 'ptr': ('void *', 2), 'flag': (None, 0)}
errors = []


def err(msg):
    errors.append(msg)


def num(s):
    s = s.strip()
    return int(s[1:], 16) if s.startswith('$') else int(s)


def parse_args(field, where):
    if field.strip() in ('-', ''):
        return []
    if field.strip() == 'inline':
        return 'inline'
    out = []
    for tok in field.split():
        parts = tok.split(':')
        if len(parts) != 3:
            err('%s: argument %r is not REG:NAME:TYPE' % (where, tok))
            continue
        reg, name, typ = parts
        ok = reg in ('a', 'x', 'y', 'c', 'n') or reg in REGS or (reg[:-1] in REGS and reg[-1] in 'LH')
        if not ok:
            err('%s: unknown register %s' % (where, reg))
        if typ not in TYPES:
            err('%s: unknown type %s' % (where, typ))
        if (reg in REGS) and typ in ('u8', 'i8'):
            err('%s: %s is a word register but %s is a byte' % (where, reg, name))
        if (reg[-1:] in 'LH' and reg[:-1] in REGS or reg in ('a', 'x', 'y')) and typ in ('u16', 'i16', 'ptr'):
            err('%s: %s is a byte register but %s is a word' % (where, reg, name))
        out.append((reg, name, typ))
    return out


def parse(path):
    api = {'calls': [], 'vars': [], 'consts': [], 'areas': [], 'paths': []}
    for n, line in enumerate(open(path), 1):
        line = line.split('#', 1)[0].rstrip()
        if not line.strip():
            continue
        where = '%s:%d' % (path, n)
        kw, rest = line.split(None, 1)
        f = [x.strip() for x in rest.split('|')]
        if kw == 'call':
            if len(f) != 6:
                err('%s: a call has 6 fields' % where)
                continue
            name, kind, slot, fin, fout, desc = f
            if kind not in ('classic', 'drop', 'wide', 'new'):
                err('%s: unknown kind %s' % (where, kind))
            api['calls'].append({'name': name, 'kind': kind, 'slot': None if slot == '-' else num(slot),
                                 'in': parse_args(fin, where), 'out': parse_args(fout, where),
                                 'desc': desc, 'noc': '[noc]' in desc or fin.strip() == 'inline',
                                 'where': where})
        elif kw == 'var':
            name, addr, size, desc = f
            api['vars'].append((name, num(addr), num(size), desc, where))
        elif kw == 'const':
            name, value, desc = f
            api['consts'].append((name, num(value), desc))
        elif kw == 'path':
            name, value, desc = f
            if not value or '"' in value or '\\' in value:
                err('%s: a path is plain text' % where)
            api['paths'].append((name, value, desc))
        elif kw == 'area':
            name, addr, size, desc = f
            api['areas'].append((name, num(addr), num(size), desc))
        else:
            err('%s: unknown line kind %s' % (where, kw))
    return api


def layout(api):
    c = dict((n, v) for n, v, _ in api['consts'])
    cbase, nbase = c['CLASSIC_BASE'], c['NEW_BASE']
    areas = dict((n, (a, s)) for n, a, s, _ in api['areas'])
    res_lo, res_size = areas['RESIDENT']
    names, last = set(), None
    nslot = 0
    for e in api['calls']:
        if e['name'] in names:
            err('%s: %s defined twice' % (e['where'], e['name']))
        names.add(e['name'])
        if e['kind'] in ('classic', 'drop'):
            s = e['slot']
            if s is None or (s - 0xC100) % 3 or s < 0xC100:
                err('%s: classic slot must be $C100 + 3n' % e['where'])
                continue
            if last is not None and s <= last:
                err('%s: classic slots must increase' % e['where'])
            last = s
            e['addr'] = cbase + s - 0xC100
            if e['addr'] + 3 > nbase:
                err('%s: classic table runs into NEW_BASE' % e['where'])
        else:
            if e['slot'] is not None:
                err('%s: wide and new calls take slot -' % e['where'])
            e['addr'] = nbase + 3 * nslot
            nslot += 1
    end = nbase + 3 * nslot
    if not res_lo <= nbase and end <= res_lo + res_size:
        err('the new table ($%04X-$%04X) is outside the resident core' % (nbase, end))
    # variables: inside an area, no overlap
    spans = []
    for name, addr, size, desc, where in api['vars']:
        if name in names:
            err('%s: %s is also a call' % (where, name))
        names.add(name)
        inside = addr < 0x22 or any(a <= addr and addr + size <= a + s for _, a, s, _ in api['areas'])
        if not inside:
            err('%s: %s ($%04X, %d) is outside every area' % (where, name, addr, size))
        for n2, a2, s2 in spans:
            if addr < a2 + s2 and a2 < addr + size:
                err('%s: %s overlaps %s' % (where, name, n2))
        spans.append((name, addr, size))
    return end


def gen_inc(api):
    o = ['; Veranda API: generated from api/veranda.api by tools/apigen.py; do not edit', '',
         '.ifndef VERANDA_INC', 'VERANDA_INC = 1', '']
    o.append('; ---- constants')
    for name, value, desc in api['consts']:
        o.append('%-20s = $%04X   ; %s' % (name, value, desc))
    o.append('')
    o.append('; ---- the folders (strings: .byte NAME, 0)')
    for name, value, desc in api['paths']:
        o.append('.define %-20s "%s"   ; %s' % (name, value, desc))
    o.append('')
    o.append('; ---- memory map')
    for name, addr, size, desc in api['areas']:
        o.append('%-20s = $%04X   ; %d bytes: %s' % (name, addr, size, desc))
        o.append('%-20s = %d' % (name + '_SIZE', size))
    o.append('')
    o.append('; ---- variables')
    for name, addr, size, desc, _ in api['vars']:
        o.append('%-20s = $%04X   ; %d: %s' % (name, addr, size, desc))
        if size == 2 and (name in REGS or re.match(r'^a\d$', name)):
            o.append('%-20s = $%04X' % (name + 'L', addr))
            o.append('%-20s = $%04X' % (name + 'H', addr + 1))
    o.append('')
    o.append('; ---- calls')
    for e in api['calls']:
        tag = {'drop': ' (not on Veranda)'}.get(e['kind'], '')
        o.append('%-20s = $%04X   ; %s%s' % (e['name'], e['addr'], e['desc'], tag))
    o += ['', '.endif', '']
    return '\n'.join(o)


def gen_jumptab(api):
    o = ['; Veranda jump tables: generated by tools/apigen.py; do not edit', '',
         '.segment "JUMPTAB"', '']
    impl = []
    for e in api['calls']:
        if e['kind'] == 'drop':
            target = 'k_Unsupported'
        else:
            target = 'k_' + e['name']
            impl.append(target)
        if e['kind'] in ('wide', 'new') and api['calls'][api['calls'].index(e) - 1]['kind'] in ('classic', 'drop'):
            o.append('.segment "JUMPTAB2"')
        o.append('.import %s' % target)
        o.append('.assert * = $%04X, error, "%s moved"' % (e['addr'], e['name']))
        o.append('\tjmp %s\t\t; %s' % (target, e['name']))
    o.append('.import k_Unsupported')
    return '\n'.join(o) + '\n', sorted(set(impl + ['k_Unsupported']))


CTYPE = {'flag': 'unsigned char', 'u8': 'unsigned char', 'i8': 'signed char', 'u16': 'unsigned int', 'i16': 'int', 'ptr': 'void *'}


C_KEYWORDS = {'char', 'int', 'long', 'short', 'signed', 'unsigned', 'void', 'const', 'volatile', 'static',
              'register', 'auto', 'extern', 'if', 'else', 'for', 'while', 'do', 'return', 'switch', 'case',
              'default', 'break', 'continue', 'goto', 'sizeof', 'struct', 'union', 'enum', 'typedef', 'float',
              'double'}


def cname(n, api):
    """a C parameter name that is neither a keyword nor one of the header's macros"""
    macros = set(v[0] for v in api['vars']) | set(c[0] for c in api['consts']) | set(c[0] for c in api['paths'])
    macros |= set(v[0] + s for v in api['vars'] for s in 'LH')
    return n + '_' if n in C_KEYWORDS or n in macros else n


def cargs(e):
    return [(r, n, t) for r, n, t in e['in'] if t != 'flag']


def gen_h(api):
    o = ['/* Veranda API for C (cc65): generated from api/veranda.api by tools/apigen.py */',
         '#ifndef VERANDA_H', '#define VERANDA_H', '']
    o.append('/* constants */')
    for name, value, desc in api['consts']:
        o.append('#define %-20s 0x%04X /* %s */' % (name, value, desc))
    o.append('')
    o.append('/* the folders (DECISIONS V71) */')
    for name, value, desc in api['paths']:
        o.append('#define %-20s "%s" /* %s */' % (name, value, desc))
    o.append('')
    o.append('/* system variables and registers */')
    for name, addr, size, desc, _ in api['vars']:
        if size == 1:
            o.append('#define %-20s (*(volatile unsigned char *)0x%04X) /* %s */' % (name, addr, desc))
        elif size == 2:
            o.append('#define %-20s (*(volatile unsigned int *)0x%04X) /* %s */' % (name, addr, desc))
            if name in REGS or re.match(r'^a\d$', name):
                o.append('#define %-20s (*(volatile unsigned char *)0x%04X)' % (name + 'L', addr))
                o.append('#define %-20s (*(volatile unsigned char *)0x%04X)' % (name + 'H', addr + 1))
        else:
            o.append('#define %-20s ((volatile unsigned char *)0x%04X) /* %d bytes: %s */' % (name, addr, size, desc))
    o.append('')
    o.append('/* calls (the first result is returned; the others stay in the registers) */')
    for e in api['calls']:
        if e['noc'] or e['kind'] == 'drop':
            continue
        ret = CTYPE[e['out'][0][2]] if e['out'] else 'void'
        args = cargs(e)
        a = ', '.join('%s %s' % (CTYPE[t], cname(n, api)) for _, n, t in args) or 'void'
        o.append('%s __fastcall__ %s(%s); /* %s */' % (ret, e['name'], a, e['desc']))
    o += ['', '#endif', '']
    return '\n'.join(o)


def store(reg, typ):
    """code that stores A (and X for words) into reg; a/x/y go to temporaries"""
    if reg in REGS:
        return ['\tsta %s' % reg, '\tstx %s+1' % reg]
    if reg[:-1] in REGS and reg[-1] in 'LH':
        return ['\tsta %s%s' % (reg[:-1], '' if reg[-1] == 'L' else '+1')]
    return ['\tsta tmp_%s' % reg]


def gen_c(api):
    o = ['; Veranda C bindings for cc65: generated by tools/apigen.py; do not edit',
         '; cc65 passes the last argument in A/X, the others on the C stack',
         '; (pushed in order: popped here in reverse).', '',
         '.include "veranda.inc"', '.import popa, popax', '',
         '.segment "BSS"', 'tmp_a:\t.res 1', 'tmp_x:\t.res 1', 'tmp_y:\t.res 1', '',
         '.segment "CODE"', '']
    for e in api['calls']:
        if e['noc'] or e['kind'] == 'drop':
            continue
        args = cargs(e)
        o.append('.export _%s' % e['name'])
        o.append('_%s:' % e['name'])
        for i, (reg, name, typ) in enumerate(reversed(args)):
            if i:
                o.append('\tjsr %s' % ('popa' if TYPES[typ][1] == 1 else 'popax'))
            o += store(reg, typ)
        for reg, name, typ in args:
            if reg in ('a', 'x', 'y'):
                o.append('\tld%s tmp_%s' % (reg, reg))
        o.append('\tjsr %s' % e['name'])
        if e['out']:
            reg, name, typ = e['out'][0]
            if reg == 'a':
                o.append('\tldx #0')
            elif reg == 'x':
                o += ['\ttxa', '\tldx #0']
            elif reg == 'y':
                o += ['\ttya', '\tldx #0']
            elif reg == 'c':
                o += ['\tlda #0', '\trol', '\tldx #0']
            elif reg in REGS:
                o += ['\tlda %s' % reg, '\tldx %s+1' % reg]
            else:
                o += ['\tlda %s%s' % (reg[:-1], '' if reg[-1] == 'L' else '+1'), '\tldx #0']
        o += ['\trts', '']
    return '\n'.join(o)


def gen_geos64(api):
    """the same names at GEOS 64's addresses: the oracle tests assemble a scene
    for the GEOS 64 KERNAL with it (classic calls only; zero page and
    registers are the same)"""
    o = ['; GEOS 64 addresses of the classic calls (tests only): generated by tools/apigen.py',
         '.ifndef GEOS64_INC', 'GEOS64_INC = 1']
    for name, value, desc in api['consts']:
        o.append('%-20s = $%04X' % (name, value))
    for name, addr, size, desc, _ in api['vars']:
        if addr < 0x100:
            o.append('%-20s = $%04X' % (name, addr))
            if size == 2 and (name in REGS or re.match(r'^a\d$', name)):
                o.append('%-20s = $%04X' % (name + 'L', addr))
                o.append('%-20s = $%04X' % (name + 'H', addr + 1))
    for e in api['calls']:
        if e['kind'] in ('classic', 'drop'):
            o.append('%-20s = $%04X' % (e['name'], e['slot']))
    o += ['.endif', '']
    return '\n'.join(o)


def regtext(args):
    if args == 'inline':
        return 'inline parameters'
    return ', '.join('%s %s (%s)' % (r, n, t) for r, n, t in args) or '-'


def gen_doc(api):
    o = ['# Veranda API reference', '',
         'Generated from `api/veranda.api` by `tools/apigen.py`; do not edit.', '',
         'Registers r0-r15 are the words at `$02-$21` (rNL/rNH the bytes). A "wide" call is the 16-bit Y twin of a classic GEOS call. Dropped GEOS calls keep their address and return x = `UNSUPPORTED`.', '']
    for title, kinds in (('Classic GEOS calls', ('classic',)), ('Wide calls (16-bit Y)', ('wide',)),
                         ('New calls', ('new',)), ('GEOS calls not on Veranda', ('drop',))):
        o += ['## ' + title, '', '| Call | Address | In | Out | |', '|---|---|---|---|---|']
        for e in api['calls']:
            if e['kind'] in kinds:
                o.append('| `%s` | `$%04X` | %s | %s | %s |' % (e['name'], e['addr'], regtext(e['in']),
                                                           regtext(e['out']), e['desc'].replace('|', '/')))
        o.append('')
    o += ['## System variables', '', '| Name | Address | Size | |', '|---|---|---|---|']
    for name, addr, size, desc, _ in api['vars']:
        o.append('| `%s` | `$%04X` | %d | %s |' % (name, addr, size, desc))
    o += ['', '## Constants', '', '| Name | Value | |', '|---|---|---|']
    for name, value, desc in api['consts']:
        o.append('| `%s` | `$%X` | %s |' % (name, value, desc))
    o += ['', '## Folders', '', '| Name | Path | |', '|---|---|---|']
    for name, value, desc in api['paths']:
        o.append('| `%s` | `%s` | %s |' % (name, value, desc))
    return '\n'.join(o) + '\n'


def main():
    a = sys.argv[1:]
    if len(a) < 2:
        sys.exit(__doc__)
    src, out = a[0], a[1]
    doc = a[a.index('--doc') + 1] if '--doc' in a else None
    api = parse(src)
    if not errors:
        end = layout(api)
    if errors:
        for e in errors:
            print('apigen: ' + e)
        sys.exit(1)
    os.makedirs(out, exist_ok=True)
    w = lambda n, t: open(os.path.join(out, n), 'w').write(t)   # noqa: E731
    w('veranda.inc', gen_inc(api))
    jt, impl = gen_jumptab(api)
    w('jumptab.s', jt)
    w('impl.txt', '\n'.join(impl) + '\n')
    w('veranda.h', gen_h(api))
    w('veranda_c.s', gen_c(api))
    w('geos64.inc', gen_geos64(api))
    if doc:
        open(doc, 'w').write(gen_doc(api))
    n = {k: sum(1 for e in api['calls'] if e['kind'] == k) for k in ('classic', 'drop', 'wide', 'new')}
    print('apigen: %(classic)d classic, %(drop)d dropped, %(wide)d wide, %(new)d new calls;' % n,
          'new table ends at $%04X; %d variables, %d constants' % (end, len(api['vars']), len(api['consts'])))


if __name__ == '__main__':
    main()
