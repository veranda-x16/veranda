#!/usr/bin/env python3
"""Gate vb_spec: vbasic/gen/tokens.inc as the X16 sees it.

usage: check_tokens_inc.py wrap OUT_DIR       write the wrappers (tables.s, entries.s, tables.cfg)
       check_tokens_inc.py check BIN LABELS   the linked tables against tools/vbtokens_gen.py

tables.s includes tokens.inc with VB_TABLES (the tables, linked at $A000 as
an overlay's are); entries.s defines a stub for every run-time entry and
expands each overlay's vb_entries_X macro. The check decodes the linked
bytes the way the X16 lexer and detokenizer will: every keyword found by
the length buckets with its token; every token's name, flags, overlay and
entry; the compounds and the two-character operators.

MIT licence (LICENSE).
"""
import os
import re
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..'))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
import vbtokens_gen as G  # noqa: E402
import vbtokens as V  # noqa: E402
import vbgen  # noqa: E402

TABLES_S = '''; gate vb_spec: the tables of tokens.inc, linked alone
VB_TABLES = 1
.segment "RODATA"
.include "tokens.inc"
'''
CFG = '''MEMORY { M: start = $A000, size = $2000, file = %O, fill = no; }
SEGMENTS { RODATA: load = M, type = ro; }
'''


def wrap(out):
    os.makedirs(out, exist_ok=True)
    open(os.path.join(out, 'tables.s'), 'w').write(TABLES_S)
    open(os.path.join(out, 'tables.cfg'), 'w').write(CFG)
    lines = ['; gate vb_spec: every overlay\'s entry macro, with stub entries', '.include "tokens.inc"',
             '.segment "RODATA"']
    for o in G.OVERLAYS:
        for name in G.ENTRIES[o]:
            kind = G.KEYWORDS[name][1]
            lines.append('vb%s_%s: rts' % ('f' if kind == 'func' else 's', vbgen.asm_name(name)))
    for o in G.OVERLAYS:
        lines.append('vb_entries_%s_table:' % o)
        lines.append('        vb_entries_%s' % o)
        lines.append('.assert * - vb_entries_%s_table = 2 * VB_ENTRIES_%s, error, "entries"' % (o, o.upper()))
    open(os.path.join(out, 'entries.s'), 'w').write('\n'.join(lines) + '\n')


def check(binpath, labpath):
    data = open(binpath, 'rb').read()
    base = 0xA000
    lab = {}
    for ln in open(labpath):
        m = re.match(r'al\s+(?:00)?([0-9A-Fa-f]+)\s+\.(\S+)', ln)
        if m:
            lab[m.group(2)] = int(m.group(1), 16)
    bad = []

    def at(name):
        if name not in lab:
            raise SystemExit('FAIL  no label %s in %s' % (name, labpath))
        return lab[name] - base

    def word(off):
        return data[off] | data[off + 1] << 8

    maxlen = max(len(n) for n in G.KEYWORDS if ' ' not in n and n[0].isalpha())
    lens = at('vb_kw_len')
    found = 0
    for name, (code, kind, args, ovl, flags, value) in G.KEYWORDS.items():
        if ' ' in name or not name[0].isalpha():
            continue
        L = len(name)
        if L > maxlen:
            bad.append('%s longer than the buckets' % name)
            continue
        addr, count = word(lens + 3 * (L - 1)), data[lens + 3 * (L - 1) + 2]
        lo, hi, hit = 0, count - 1, None
        while lo <= hi:                      # the lexer's binary search
            mid = (lo + hi) // 2
            e = addr - base + mid * (L + 2)
            w = data[e:e + L].decode('latin-1')
            if w == name:
                hit = e
                break
            if w < name:
                lo = mid + 1
            else:
                hi = mid - 1
        if hit is None:
            bad.append('%s not found in its bucket' % name)
            continue
        t1, t2 = data[hit + L], data[hit + L + 1]
        want = (code, 0) if code <= 0xFF else (0xFF, code & 0xFF)
        if (t1, t2) != want:
            bad.append('%s: token %02X %02X, expected %02X %02X' % (name, t1, t2, *want))
        found += 1
    # per-token tables and names
    names = at('vb_names')
    for page, first, count in ((1, 0x80, 127), (2, 0x01, 255)):
        for t in range(first, first + count):
            code = t if page == 1 else 0xFF00 | t
            i = t - first
            info = V.KWINFO.get(code)
            no = at('vb_name%d' % page) + 3 * i
            off, ln = word(no), data[no + 2]
            fl = data[at('vb_flags%d' % page) + i]
            ov = data[at('vb_ovl%d' % page) + i]
            en = data[at('vb_ent%d' % page) + i]
            if info is None:
                if ln or fl or ov != 0xFF:
                    bad.append('token %X: a free token with a name or flags' % code)
                continue
            nm = data[names + off:names + off + ln].decode('latin-1')
            if nm != info['name']:
                bad.append('token %X: name %r, expected %r' % (code, nm, info['name']))
            if bool(fl & vbgen.FBIT['block']) != ('block' in info['flags']):
                bad.append('%s: the block flag' % info['name'])
            if bool(fl & vbgen.FBIT['raw']) != any(f.startswith('raw=') for f in info['flags']):
                bad.append('%s: the raw flag' % info['name'])
            if info['name'] in G.ENTRIES.get(info['overlay'], []):
                if ov != G.OVERLAYS.index(info['overlay']) or en != G.ENTRIES[info['overlay']].index(info['name']):
                    bad.append('%s: dispatch %d/%d' % (info['name'], ov, en))
            elif ov != 0xFF or en != 0xFF:
                bad.append('%s: dispatched, but it is a word or an operator' % info['name'])
            if info['value'] is not None and data[at('vb_value%d' % page) + i] != info['value']:
                bad.append('%s: value' % info['name'])
    # compounds
    comp, k, seen = at('vb_compound'), 0, set()
    while data[comp + k]:
        a, b, c = (data[comp + k], data[comp + k + 1]), (data[comp + k + 2], data[comp + k + 3]), \
            (data[comp + k + 4], data[comp + k + 5])

        def code(p):
            return p[0] if p[0] != 0xFF else 0xFF00 | p[1]
        seen.add((code(a), code(b), code(c)))
        k += 6
    want = {(a, b, c) for (a, b), c in V.COMPOUND.items()}
    if seen != want:
        bad.append('the compounds: %d, expected %d' % (len(seen), len(want)))
    ops, k, nops = at('vb_ops2'), 0, 0
    while data[ops + k]:
        op = data[ops + k:ops + k + 2].decode()
        if V.KW.get(op) != data[ops + k + 2]:
            bad.append('operator %s' % op)
        k += 3
        nops += 1
    for b in bad[:20]:
        print('FAIL  ' + b)
    if bad:
        return 1
    print('ok    the linked tables (%d bytes at $A000): %d keywords by their buckets, %d tokens\' names, flags and '
          'dispatch, %d compounds, %d operators' % (len(data), found, len(V.KWINFO), len(seen), nops))
    return 0


if __name__ == '__main__':
    if len(sys.argv) == 3 and sys.argv[1] == 'wrap':
        wrap(sys.argv[2])
        sys.exit(0)
    if len(sys.argv) == 4 and sys.argv[1] == 'check':
        sys.exit(check(sys.argv[2], sys.argv[3]))
    print(__doc__, file=sys.stderr)
    sys.exit(2)
