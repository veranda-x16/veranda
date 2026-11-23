#!/usr/bin/env python3
"""Generate VeraBASIC's token tables, help and reference from the keyword
table (vbasic/keywords.tbl; its head describes the line format).

usage: vbgen.py [--tbl vbasic/keywords.tbl] [--api api/veranda.api]
                [--out DIR] [--check-only]

Writes, under DIR (default: the repository), the same paths as committed:
  vbasic/gen/tokens.inc            ca65: token constants, the keyword
                                   lookup table, compounds, per-token flags,
                                   names and the dispatch table
  tools/vbtokens_gen.py            the same tables for tools/vbtokens.py
  vbasic/gen/HELP/KEYWORDS.HLP     the editor's help pages (help markup,
                                   docs/vbasic/FORMAT.md); with ERRORS.HLP
                                   (the run-time errors), TUTORIAL.HLP and
                                   EDITOR.HLP (docs/vbasic/manual's
                                   tutorial.md and editor.md as help)
  docs/vbasic/manual/reference.md  the manual's language reference
  docs/vbasic/manual/tokens.md     the appendix: the token list
  vbasic/gen/idekw.h               VeraBASIC's editor (C): the keywords'
                                   words (its colouring), their syntax lines
                                   (its status bar), the tokens' names and
                                   classes (its Format)

Fails (exit status 1, every problem listed) when a keyword or constant
lacks its syntax, help or example; on a duplicate name or token, a token
out of its page, a retired number given again, a compound whose words are
not keywords, an unknown kind, overlay, group, flag or argument code, a
kernel name that is neither in api/veranda.api nor in sdk/lib/*.h, a
"see" that names nothing, a constant whose value differs from the API's
or theme.h's, a keyword spelling a constant also has; and when a
hand-written chapter of docs/vbasic/manual names a {KEYWORD} the table
does not have.

MIT licence (LICENSE).
"""
import glob
import os
import re
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
KINDS = ('stmt', 'func', 'op', 'word')
OVERLAYS = ('core', 'gfx', 'file', 'dlg', 'snd', 'msg', 'tok')   # in this order: overlay ids
FLAG_WORDS = ('block', 'ref=line', 'ref=stmt', 'ref=proc', 'raw=rem', 'raw=data')
ARG_CODES = set('nisxvahclp')
GENERATED = ('reference.md', 'tokens.md', 'appendix-errors.md')

# per-token flag bits (tokens.inc VBF_*, vbtokens_gen FLAGS)
FBIT = {'stmt': 0x01, 'func': 0x02, 'op': 0x04, 'block': 0x08, 'ref=line': 0x10,
        'ref=stmt': 0x20, 'ref=proc': 0x40, 'raw': 0x80}
# second flag byte
F2BIT = {'noparen': 0x01, 'value': 0x02, 'compound': 0x04, 'raw=data': 0x08, 'procarg': 0x10}

errors = []


def err(msg):
    errors.append(msg)


def num(s):
    s = s.strip()
    if s.startswith('$'):
        return int(s[1:], 16)
    return int(s)


class Entry:
    def __init__(self, what, name, where):
        self.what, self.name, self.where = what, name, where
        self.syntax, self.help, self.example, self.see = [], [], [], []
        self.token = None
        self.kind = self.args = self.overlay = self.group = None
        self.kernel = []
        self.flags = []
        self.value = None
        self.apiname = self.themename = None
        self.members = []          # apiconst: [(name, value, description)]

    @property
    def page(self):
        return 2 if self.token is not None and self.token > 0xFF else 1


def read_api(path):
    names, consts = set(), {}
    for ln in open(path, encoding='latin-1'):
        ln = ln.split('#', 1)[0] if ln.lstrip().startswith('#') else ln
        f = [x.strip() for x in ln.split('|')]
        if not f or not f[0]:
            continue
        head = f[0].split()
        if len(head) == 2 and head[0] in ('call', 'var', 'const', 'area', 'path'):
            names.add(head[1])
            if head[0] == 'const' and len(f) >= 2:
                try:
                    consts[head[1]] = (num(f[1]), f[2] if len(f) > 2 else '')
                except ValueError:
                    pass
    return names, consts


def read_sdk_names():
    names = set()
    for h in glob.glob(os.path.join(ROOT, 'sdk', 'lib', '*.h')):
        names.update(re.findall(r'\b([A-Za-z_][A-Za-z0-9_]*)\b', open(h, encoding='latin-1').read()))
    return names


def read_theme():
    out = {}
    path = os.path.join(ROOT, 'sdk', 'lib', 'theme.h')
    for m in re.finditer(r'#define\s+([A-Z0-9_]+)\s+(0x[0-9A-Fa-f]+|\d+)', open(path).read()):
        out[m.group(1)] = int(m.group(2), 0)
    return out


def parse(tbl, api_path):
    groups, entries, retired = [], [], {}
    cur = None
    api_names, api_consts = read_api(api_path)
    for no, raw in enumerate(open(tbl, encoding='latin-1'), 1):
        where = '%s:%d' % (os.path.relpath(tbl, ROOT), no)
        line = raw.rstrip('\n')
        if not line.strip() or line.lstrip().startswith('#'):
            continue
        if line[0] in ' \t':
            if cur is None:
                err('%s: a field line outside an entry' % where)
                continue
            body = line.strip()
            m = re.match(r'(syntax|help|example|see):(.*)$', body)
            if not m:
                err('%s: unknown field line %r' % (where, body))
                continue
            key, val = m.group(1), m.group(2)
            if key == 'example':
                val = val[1:] if val.startswith(' ') else val
                cur.example.append(val.rstrip())
            elif key == 'help':
                cur.help.append(val.strip())
            elif key == 'syntax':
                cur.syntax.append(val.strip())
            else:
                cur.see += [s.strip() for s in val.split(',') if s.strip()]
            continue
        f = [x.strip() for x in line.split('|')]
        head = f[0].split(None, 1)
        what = head[0]
        if what == 'group':
            if len(head) != 2 or len(f) != 2:
                err('%s: group ID | Title' % where)
                cur = None
                continue
            cur = Entry('group', head[1], where)
            cur.title = f[1]
            groups.append(cur)
        elif what == 'kw':
            if len(f) not in (7, 8) or len(head) != 2:
                err('%s: kw NAME | TOKEN | KIND | ARGS | OVERLAY | KERNEL | GROUP [| FLAGS]' % where)
                cur = None
                continue
            e = cur = Entry('kw', head[1].upper(), where)
            if head[1] != head[1].upper():
                err('%s: %s: keywords are written in upper case' % (where, head[1]))
            try:
                e.token = num(f[1])
            except ValueError:
                err('%s: %s: bad token %r' % (where, e.name, f[1]))
            e.kind, e.args, e.overlay = f[2], f[3], f[4]
            e.kernel = [] if f[5] == '-' else f[5].split()
            e.group = f[6]
            for fl in (f[7].split() if len(f) == 8 else []):
                if fl.startswith('value='):
                    e.value = num(fl[6:])
                elif fl in FLAG_WORDS:
                    e.flags.append(fl)
                else:
                    err('%s: %s: unknown flag %r' % (where, e.name, fl))
            entries.append(e)
        elif what == 'const':
            if len(f) not in (3, 4) or len(head) != 2:
                err('%s: const NAME | VALUE | GROUP [| api=NAME | theme=NAME]' % where)
                cur = None
                continue
            e = cur = Entry('const', head[1].upper(), where)
            try:
                e.value = num(f[1])
            except ValueError:
                err('%s: %s: bad value %r' % (where, e.name, f[1]))
            e.group = f[2]
            for fl in (f[3].split() if len(f) == 4 else []):
                if fl.startswith('api='):
                    e.apiname = fl[4:]
                elif fl.startswith('theme='):
                    e.themename = fl[6:]
                else:
                    err('%s: %s: unknown flag %r' % (where, e.name, fl))
            entries.append(e)
        elif what == 'apiconst':
            if len(f) != 2 or len(head) != 2:
                err('%s: apiconst PREFIX | GROUP' % where)
                cur = None
                continue
            e = cur = Entry('apiconst', head[1], where)
            e.group = f[1]
            e.members = sorted(((n, v, d) for n, (v, d) in api_consts.items() if n.startswith(e.name)),
                               key=lambda m: (m[1], m[0]))
            if not e.members:
                err('%s: no const %s... in the API table' % (where, e.name))
            entries.append(e)
        elif what == 'retired':
            if len(f) != 2:
                err('%s: retired TOKEN | NAME' % where)
                continue
            retired[num(head[1])] = f[1]
            cur = None
        else:
            err('%s: unknown line %r' % (where, what))
            cur = None
    return groups, entries, retired, api_names, api_consts


def check(groups, entries, retired, api_names, api_consts):
    gids = [g.name for g in groups]
    if len(set(gids)) != len(gids):
        err('a group ID is given twice')
    for g in groups:
        if not g.title:
            err('%s: group %s has no title' % (g.where, g.name))
    sdk = read_sdk_names()
    theme = read_theme()
    kws = [e for e in entries if e.what == 'kw']
    consts = [e for e in entries if e.what == 'const']
    names = {}
    for e in entries:
        for n in ([e.name] if e.what != 'apiconst' else [m[0] for m in e.members]):
            if n in names:
                err('%s: %s is already at %s' % (e.where, n, names[n].where))
            names[n] = e
    kwnames = {e.name: e for e in kws}
    tokens = {}
    for e in kws:
        if e.token is None:
            continue
        if e.page == 1 and not 0x80 <= e.token <= 0xFE:
            err('%s: %s: a first-page token is $80-$FE' % (e.where, e.name))
        if e.page == 2 and not (0xFF01 <= e.token <= 0xFFFF):
            err('%s: %s: a second-page token is $FF01-$FFFF' % (e.where, e.name))
        if e.token in tokens:
            err('%s: %s: token $%X is already %s\'s' % (e.where, e.name, e.token, tokens[e.token].name))
        if e.token in retired:
            err('%s: %s: token $%X is retired (%s): never given again' % (e.where, e.name, e.token, retired[e.token]))
        tokens[e.token] = e
        if e.kind not in KINDS:
            err('%s: %s: unknown kind %r' % (e.where, e.name, e.kind))
        if e.overlay != '-' and e.overlay not in OVERLAYS:
            err('%s: %s: unknown overlay %r' % (e.where, e.name, e.overlay))
        if e.kind in ('stmt', 'func') and e.overlay == '-':
            err('%s: %s: a statement or function needs an overlay' % (e.where, e.name))
        if e.kind == 'word' and e.overlay != '-':
            err('%s: %s: a word has no code of its own (overlay -)' % (e.where, e.name))
        if ' ' in e.name:
            words = e.name.split()
            if len(words) != 2 or any(w not in kwnames for w in words):
                err('%s: %s: a compound is two keywords' % (e.where, e.name))
        elif not re.fullmatch(r'[A-Z][A-Z0-9_]*[$%]?|<=|<>|>=', e.name):
            err('%s: %s: not a word' % (e.where, e.name))
        check_args(e)
        for k in e.kernel:
            if k.startswith(('VERA:', 'ROM:', 'new:')):
                continue
            if k not in api_names and k not in sdk:
                err('%s: %s: kernel name %s is not in api/veranda.api or sdk/lib/*.h' % (e.where, e.name, k))
    seen = {}
    for e in kws:
        a = ('TK_' if e.page == 1 else 'TX_') + asm_name(e.name)
        if a in seen:
            err('%s: %s and %s are both %s in tokens.inc' % (e.where, e.name, seen[a], a))
        seen[a] = e.name
    for e in consts:
        if e.apiname:
            if e.apiname not in api_consts:
                err('%s: %s: api=%s is not an API constant' % (e.where, e.name, e.apiname))
            elif api_consts[e.apiname][0] != e.value:
                err('%s: %s = %d but %s = %d' % (e.where, e.name, e.value, e.apiname, api_consts[e.apiname][0]))
        if e.themename:
            if e.themename not in theme:
                err('%s: %s: theme=%s is not in sdk/lib/theme.h' % (e.where, e.name, e.themename))
            elif theme[e.themename] != e.value:
                err('%s: %s = %d but theme.h\'s %s = %d' % (e.where, e.name, e.value, e.themename,
                                                           theme[e.themename]))
    for e in entries:
        if e.group not in gids:
            err('%s: %s: unknown group %r' % (e.where, e.name, e.group))
        # the completeness check
        if len(e.syntax) != 1 or not e.syntax[0]:
            err('%s: %s has no syntax line (exactly one)' % (e.where, e.name))
        if not any(h for h in e.help):
            err('%s: %s has no help text' % (e.where, e.name))
        if not any(x.strip() for x in e.example):
            err('%s: %s has no example' % (e.where, e.name))
        for s in e.see:
            if s not in names and s not in kwnames:
                err('%s: %s: see %s names nothing' % (e.where, e.name, s))
    return kws, consts


def arg_positions(args):
    """the argument codes by position (brackets dropped), or None for *"""
    a = args.strip()
    if a in ('*', '-'):
        return None if a == '*' else []
    return [p.strip().strip('[]').strip() for p in a.replace('[', ',[').split(',') if p.strip().strip('[]')]


def check_args(e):
    a = e.args.strip()
    if e.kind == 'func':
        m = re.fullmatch(r'(\[?\((.*)\)\]?)?->([nis])', a)
        if not m:
            err('%s: %s: a function\'s ARGS are (args)->type or ->type' % (e.where, e.name))
            return
        inner = m.group(2) or ''
        codes = re.sub(r'[\[\],.\s]', '', inner)
    elif a in ('*', '-'):
        return
    else:
        codes = re.sub(r'[\[\],.\s=]', '', a)
        if 'p' in codes and e.kind != 'stmt':
            err('%s: %s: only a statement takes a procedure argument' % (e.where, e.name))
    bad = set(codes) - ARG_CODES
    if bad:
        err('%s: %s: unknown argument codes %s' % (e.where, e.name, ''.join(sorted(bad))))


# ----------------------------------------------------------------------
# outputs

def asm_name(name):
    n = name.replace(' ', '_').replace('$', '_S').replace('%', '_I')
    return {'<=': 'LE', '<>': 'NE', '>=': 'GE'}.get(name, n)


def flags_of(e):
    f1 = FBIT.get(e.kind, 0)
    for fl in e.flags:
        if fl in FBIT:
            f1 |= FBIT[fl]
        if fl.startswith('raw='):
            f1 |= FBIT['raw']
    f2 = 0
    if e.kind == 'func' and e.args.startswith('->'):
        f2 |= F2BIT['noparen']
    if e.value is not None:
        f2 |= F2BIT['value']
    if ' ' in e.name:
        f2 |= F2BIT['compound']
    if 'raw=data' in e.flags:
        f2 |= F2BIT['raw=data']
    pos = arg_positions(e.args) if e.kind == 'stmt' else None
    if pos and 'p' in pos:
        f2 |= F2BIT['procarg']
    return f1, f2


def entries_by_overlay(kws):
    out = {o: [] for o in OVERLAYS}
    for e in sorted(kws, key=lambda e: e.token):
        if e.overlay in out and e.kind in ('stmt', 'func'):
            out[e.overlay].append(e)
    return out


def gen_inc(kws, consts, apiconsts):
    L = []
    w = L.append
    w('; VeraBASIC tokens: generated by tools/vbgen.py from vbasic/keywords.tbl.')
    w('; Do not edit; docs/vbasic/FORMAT.md describes the format.')
    w('; MIT licence (LICENSE).')
    w('')
    w('VB_TOKFORMAT    = 1             ; the token format\'s version')
    w('')
    w('; tags of the token stream')
    for n, v, d in (('TAG_EOL', 0, 'end of a line record'),
                    ('TAG_INTDEC', 1, 'integer, decimal spelling: 2 bytes'),
                    ('TAG_INTHEX', 2, 'integer, hexadecimal spelling: 2 bytes'),
                    ('TAG_INTBIN', 3, 'integer, binary spelling: 2 bytes'),
                    ('TAG_FLOAT', 4, 'float: 5-byte value, length, spelling'),
                    ('TAG_STRING', 5, 'string: length, bytes'),
                    ('TAG_VAR', 6, 'variable: slot (2; bit 15 = a local\'s frame slot)'),
                    ('TAG_LINEREF', 7, 'line number (2), cached record address (3)'),
                    ('TAG_NAMEREF', 8, 'label or procedure: symbol (2), target (3)'),
                    ('TAG_COMMENT', 9, 'comment: length, raw text'),
                    ('TAG_DATA', 10, 'DATA item: length, raw text'),
                    ('TAG_BLOCK', 11, 'block partner offset (2)'),
                    ('TAG_EXT', 0xFF, 'the second page: the next byte is the token')):
        w('%-15s = $%02X             ; %s' % (n, v, d))
    w('')
    w('; per-token flags (vb_flags1/2), first byte')
    for k, v in FBIT.items():
        w('VBF_%-11s = $%02X' % (asm_name(k.replace('=', '_')).upper(), v))
    w('; second byte (vb_xflags1/2)')
    for k, v in F2BIT.items():
        w('VBX_%-11s = $%02X' % (asm_name(k.replace('=', '_')).upper(), v))
    w('')
    w('; overlays')
    for i, o in enumerate(OVERLAYS):
        w('VBO_%-11s = %d' % (o.upper(), i))
    w('VBO_NONE        = $FF')
    w('')
    w('; first page: one byte')
    for e in sorted((e for e in kws if e.page == 1), key=lambda e: e.token):
        w('TK_%-12s = $%02X             ; %s' % (asm_name(e.name), e.token, e.name))
    w('')
    w('; second page: TAG_EXT, then this byte')
    for e in sorted((e for e in kws if e.page == 2), key=lambda e: e.token):
        w('TX_%-12s = $%02X             ; %s' % (asm_name(e.name), e.token & 0xFF, e.name))
    w('')
    w('; predefined constants (names, not tokens)')
    for e in consts:
        w('VBC_%-11s = $%04X' % (asm_name(e.name), e.value & 0xFFFF))
    for e in apiconsts:
        for n, v, _ in e.members:
            w('VBC_%-11s = $%04X' % (n, v & 0xFFFF))
    w('')
    w('; The predefined constants, for prepare (a macro: the X16 tokenizer')
    w('; puts the table where it needs it): the name\'s length, the name')
    w('; (upper case), the value (2 bytes); a 0 byte ends the list.')
    w('.macro vb_consts_table')
    allc = [(e.name, e.value) for e in consts] + [(n, v) for e in apiconsts for n, v, _ in e.members]
    for n, v in allc:
        w('        .byte   %d, "%s"' % (len(n), n))
        w('        .word   $%04X' % (v & 0xFFFF))
    w('        .byte   0')
    w('.endmacro')
    w('')
    # the lexer's tables (VB_LEXTABLES: the X16 tokenizer's overlay, phase 2,
    # DECISIONS V87) are a part of the full set (VB_TABLES)
    w('.if .defined(VB_TABLES) .or .defined(VB_LEXTABLES)')
    single = sorted((e for e in kws if ' ' not in e.name and re.match(r'[A-Z]', e.name)),
                    key=lambda e: (len(e.name), e.name))
    maxlen = max(len(e.name) for e in single)
    w('; The keyword lookup (whole words: letters, digits, "_", a "$" or "%%" at')
    w('; the end), bucketed by length and sorted inside a bucket: for length')
    w('; L = 1..VB_KW_MAXLEN, vb_kw_len holds the bucket\'s address and count;')
    w('; an entry is L upper-case bytes, then the token (page 1: tk, 0;')
    w('; page 2: $FF, nn): L + 2 bytes.')
    w('VB_KW_MAXLEN    = %d' % maxlen)
    w('VB_KW_COUNT     = %d' % len(single))
    w('vb_kw_len:')
    for L_ in range(1, maxlen + 1):
        n = sum(1 for e in single if len(e.name) == L_)
        w('        .addr   vb_kw_l%d' % L_ if n else '        .addr   0')
        w('        .byte   %d' % n)
    for L_ in range(1, maxlen + 1):
        bucket = [e for e in single if len(e.name) == L_]
        if not bucket:
            continue
        w('vb_kw_l%d:' % L_)
        for e in bucket:
            tb = (e.token, 0) if e.page == 1 else (0xFF, e.token & 0xFF)
            w('        .byte   "%s", $%02X, $%02X' % (e.name, tb[0], tb[1]))
    w('')
    w('; The two-character operators: the characters, the token.')
    w('vb_ops2:')
    for e in kws:
        if e.name in ('<=', '<>', '>='):
            w('        .byte   "%s", $%02X' % (e.name, e.token))
    w('        .byte   0')
    w('')
    w('; Compounds: the first word\'s token, the second\'s, the compound\'s')
    w('; (two bytes each: tk, 0 or $FF, nn); a 0 byte ends the list.')
    w('vb_compound:')
    byname = {e.name: e for e in kws}

    def tb(e):
        return '$%02X, $%02X' % ((e.token, 0) if e.page == 1 else (0xFF, e.token & 0xFF))
    for e in sorted((e for e in kws if ' ' in e.name), key=lambda e: e.token):
        a, b = e.name.split()
        w('        .byte   %s, %s, %s ; %s' % (tb(byname[a]), tb(byname[b]), tb(e), e.name))
    w('        .byte   0')
    w('')
    for page, lo, hi in ((1, 0x80, 0xFE), (2, 0x01, 0xFF)):
        tok = {(e.token if page == 1 else e.token & 0xFF): e for e in kws if e.page == page}
        sfx = str(page)
        rng = range(lo, hi + 1)
        w('; page %d, tokens $%02X-$%02X: VB_PAGE%d_FIRST is the first index' % (page, lo, hi, page))
        w('VB_PAGE%d_FIRST  = $%02X' % (page, lo))
        w('VB_PAGE%d_COUNT  = %d' % (page, len(rng)))
        for k, label in ((0, 'vb_flags'), (1, 'vb_xflags')):
            vals = [flags_of(tok[t])[k] if t in tok else 0 for t in rng]
            w('%s%s:' % (label, sfx))
            for i in range(0, len(vals), 16):
                w('        .byte   ' + ', '.join('$%02X' % v for v in vals[i:i + 16]))
    w('.endif')
    w('')
    w('.ifdef VB_LEXTABLES')
    w('; The statements with a procedure argument (VBX_PROCARG): the token')
    w('; (tk, 0 or $FF, nn) and the argument\'s position (0 the first); 0 ends.')
    w('vb_procarg:')
    for e in sorted(kws, key=lambda e: e.token):
        pos = arg_positions(e.args) if e.kind == 'stmt' else None
        if pos and 'p' in pos:
            t = (e.token, 0) if e.page == 1 else (0xFF, e.token & 0xFF)
            for i, c in enumerate(pos):
                if c == 'p':
                    w('        .byte   $%02X, $%02X, %d ; %s' % (t[0], t[1], i, e.name))
    w('        .byte   0')
    w('.endif')
    w('')
    w('.ifdef VB_TABLES')
    by_ovl = entries_by_overlay(kws)
    entry_no = {}
    for o, lst in by_ovl.items():
        for i, e in enumerate(lst):
            entry_no[e.name] = i
    names_off, pool = {}, []
    off = 0
    for e in sorted(kws, key=lambda e: e.token):
        names_off[e.name] = off
        bs = e.name.encode('latin-1')
        pool.append((e.name, bs))
        off += len(bs)
    for page, lo, hi in ((1, 0x80, 0xFE), (2, 0x01, 0xFF)):
        tok = {(e.token if page == 1 else e.token & 0xFF): e for e in kws if e.page == page}
        sfx = str(page)
        rng = range(lo, hi + 1)
        w('; page %d: the dispatch, the values, the names' % page)
        rows = {'flags': [], 'xflags': [], 'ovl': [], 'ent': [], 'value': []}
        for t in rng:
            e = tok.get(t)
            if e is None:
                rows['flags'].append(0)
                rows['xflags'].append(0)
                rows['ovl'].append(0xFF)
                rows['ent'].append(0xFF)
                rows['value'].append(0)
                continue
            f1, f2 = flags_of(e)
            rows['flags'].append(f1)
            rows['xflags'].append(f2)
            if e.name in entry_no:
                rows['ovl'].append(OVERLAYS.index(e.overlay))
                rows['ent'].append(entry_no[e.name])
            else:
                rows['ovl'].append(0xFF)
                rows['ent'].append(0xFF)
            rows['value'].append(e.value or 0)
        for key, label in (('ovl', 'vb_ovl'), ('ent', 'vb_ent'), ('value', 'vb_value')):
            w('%s%s:' % (label, sfx))
            vals = rows[key]
            for i in range(0, len(vals), 16):
                w('        .byte   ' + ', '.join('$%02X' % v for v in vals[i:i + 16]))
        w('vb_name%s:                       ; offset in vb_names, length' % sfx)
        for t in rng:
            e = tok.get(t)
            if e is None:
                w('        .word   0\n        .byte   0')
            else:
                w('        .word   %d\n        .byte   %d   ; %s' % (names_off[e.name], len(e.name), e.name))
        w('')
    w('; the keywords\' names (canonical spelling, compounds with one space)')
    w('vb_names:')
    for name, bs in pool:
        w('        .byte   "%s"' % name.replace('"', '\\"'))
    w('.endif')
    w('')
    w('; The run-time entries of each overlay, in this order (the dispatch')
    w('; table\'s entry numbers): an overlay\'s jump table is "vb_entries_X".')
    for o in OVERLAYS:
        lst = by_ovl[o]
        w('.macro vb_entries_%s' % o)
        for e in lst:
            w('        .addr   vb%s_%s' % ('f' if e.kind == 'func' else 's', asm_name(e.name)))
        w('.endmacro')
        w('VB_ENTRIES_%s = %d' % (o.upper(), len(lst)))
    return '\n'.join(L) + '\n'


def gen_py(kws, consts, apiconsts):
    L = ['"""VeraBASIC\'s token tables: generated by tools/vbgen.py from',
         'vbasic/keywords.tbl. Do not edit. MIT licence (LICENSE)."""', '',
         'FORMAT = 1', '',
         '# name: (token, kind, args, overlay, flags, value); token > $FF is $FF nn',
         'KEYWORDS = {']
    for e in sorted(kws, key=lambda e: e.token):
        L.append('    %r: (0x%X, %r, %r, %r, %r, %r),' % (e.name, e.token, e.kind, e.args, e.overlay,
                                                      ' '.join(e.flags), e.value))
    L.append('}')
    L.append('')
    L.append('# predefined constants: name -> value')
    L.append('CONSTANTS = {')
    for e in consts:
        L.append('    %r: %d,' % (e.name, e.value))
    for e in apiconsts:
        for n, v, _ in e.members:
            L.append('    %r: %d,' % (n, v))
    L.append('}')
    by_ovl = entries_by_overlay(kws)
    L.append('')
    L.append('# overlay -> its entries in order (the dispatch table\'s entry numbers)')
    L.append('OVERLAYS = %r' % (OVERLAYS,))
    L.append('ENTRIES = {')
    for o in OVERLAYS:
        L.append('    %r: %r,' % (o, [e.name for e in by_ovl[o]]))
    L.append('}')
    return '\n'.join(L) + '\n'


def c_str(s):
    """a C string literal (Latin-1; escapes for quotes, backslashes, others)"""
    out = []
    for ch in s:
        o = ord(ch)
        if ch in '"\\':
            out.append('\\' + ch)
        elif 32 <= o < 127:
            out.append(ch)
        else:
            out.append('\\%03o' % o)
    return '"' + ''.join(out) + '"'


def ide_class(e):
    """Format's class of a keyword (tools/vbtokens.py detok_line): 1 an
    operator, 2 a keyword, 3 a value (a function without parentheses), 4 a
    function; bit 4 raw=rem, bit 5 raw=data, bit 6 ref=stmt, bit 7 DEFINT"""
    if e.kind == 'op':
        c = 2 if e.name == 'NOT' else 1
    elif e.kind == 'func':
        c = 3 if e.args.startswith('->') else 4
    else:
        c = 2
    if 'raw=rem' in e.flags:
        c |= 0x10
    if 'raw=data' in e.flags:
        c |= 0x20
    if 'ref=stmt' in e.flags:
        c |= 0x40
    if e.name == 'DEFINT':
        c |= 0x80
    return c


def gen_idekw(kws, consts):
    """vbasic/gen/idekw.h: VeraBASIC's editor (apps/vbasic/ide, DECISIONS
    V93): the words the colouring makes bold, the status bar's syntax
    lines, Format's token names and classes"""
    words = sorted(set(w for e in kws for w in e.name.split(' ') if w[0].isalpha()))
    names = sorted(e.name for e in kws)
    by_name = {e.name: e for e in kws}
    L = ['/* VeraBASIC, the editor (apps/vbasic/ide, DECISIONS V93): generated by',
         '   tools/vbgen.py from vbasic/keywords.tbl. Do not edit. Each table is',
         '   compiled where its IDEKW_ name is defined (IDEKW_EXTERN: for other files',
         '   too). MIT licence (LICENSE). */', '',
         '#ifdef IDEKW_EXTERN', '#define IDEKW_SCOPE', '#else', '#define IDEKW_SCOPE static', '#endif', '']
    L.append('#ifdef IDEKW_WORDS')
    L.append('/* the words that are keywords (alone, or in a compound), sorted:')
    L.append('   kw_word[i] at kw_wtxt + kw_woff[i], 0-ended */')
    L.append('#define KW_NWORDS %d' % len(words))
    off, offs, txt = 0, [], []
    for w in words:
        offs.append(off)
        txt.append(w)
        off += len(w) + 1
    L.append('IDEKW_SCOPE const char kw_wtxt[] =')
    for i in range(0, len(txt), 8):
        L.append('    ' + ' '.join(c_str(w + '\0').replace('\\000"', '\\0"') for w in txt[i:i + 8]))
    L[-1] += ';'
    L.append('IDEKW_SCOPE const unsigned int kw_woff[KW_NWORDS] = {')
    for i in range(0, len(offs), 12):
        L.append('    ' + ', '.join(str(o) for o in offs[i:i + 12]) + ',')
    L.append('};')
    L.append('#endif')
    L.append('')
    L.append('#ifdef IDEKW_SYNTAX')
    L.append('/* every keyword (compounds too) and predefined constant, sorted, with')
    L.append('   its syntax line: name, 0, syntax, 0 (the status bar; F1 finds the page)')
    L.append('   one after the other; KW_NSYN of them) */')
    ent = [(n, by_name[n].syntax[0].split('   or   ')[0].strip()) for n in names]
    ent += [(c.name, '%s = %d (a constant)' % (c.name, c.value)) for c in consts]
    ent.sort()
    L.append('#define KW_NSYN %d' % len(ent))
    off, offs = 0, []
    L.append('IDEKW_SCOPE const char kw_syn[] =')
    for n, s in ent:
        offs.append(off)
        L.append('    ' + c_str(n + '\0' + s + '\0').replace('\\000', '\\0'))
        off += len(n) + len(s) + 2
    L[-1] += ';'
    L.append('#endif')
    L.append('')
    L.append('#ifdef IDEKW_DETOK')
    L.append('/* Format: each token\'s name (dt_name + dt_off[t]) and class (dt_cls[t];')
    L.append('   tools/vbgen.py ide_class); t = token - $80 on the first page, 127 + nn')
    L.append('   for $FF nn; dt_off $FFFF: no such token */')
    tab = [None] * (127 + 256)
    for e in kws:
        t = e.token - 0x80 if e.token < 0x100 else 127 + (e.token & 0xFF)
        tab[t] = e
    blob, offs, cls, seen = [], [], [], {}
    off = 0
    for e in tab:
        if e is None:
            offs.append(0xFFFF)
            cls.append(0)
            continue
        if e.name not in seen:
            seen[e.name] = off
            blob.append(e.name)
            off += len(e.name) + 1
        offs.append(seen[e.name])
        cls.append(ide_class(e))
    L.append('IDEKW_SCOPE const char dt_name[] =')
    for i in range(0, len(blob), 8):
        L.append('    ' + ' '.join(c_str(w + '\0').replace('\\000"', '\\0"') for w in blob[i:i + 8]))
    L[-1] += ';'
    L.append('IDEKW_SCOPE const unsigned int dt_off[%d] = {' % len(tab))
    for i in range(0, len(offs), 12):
        L.append('    ' + ', '.join('0x%X' % o if o == 0xFFFF else str(o) for o in offs[i:i + 12]) + ',')
    L.append('};')
    L.append('IDEKW_SCOPE const unsigned char dt_cls[%d] = {' % len(tab))
    for i in range(0, len(cls), 16):
        L.append('    ' + ', '.join('0x%02X' % c for c in cls[i:i + 16]) + ',')
    L.append('};')
    L.append('#endif')
    return '\n'.join(L) + '\n'


def wrap(text, width=76):
    out, cur = [], ''
    for word in text.split():
        if cur and len(cur) + 1 + len(word) > width:
            out.append(cur)
            cur = word
        else:
            cur = word if not cur else cur + ' ' + word
    if cur:
        out.append(cur)
    return out


def paragraphs(help_lines):
    paras, cur = [], []
    for h in help_lines:
        if not h:
            if cur:
                paras.append(' '.join(cur))
            cur = []
        else:
            cur.append(h)
    if cur:
        paras.append(' '.join(cur))
    return paras


def hlp_link(name):
    return '@' + name if re.fullmatch(r'[A-Za-z0-9_$%]+', name) else '@{%s}' % name


def gen_hlp(groups, entries):
    L = ['= Contents', 'VeraBASIC keywords, by group. F1 on a word in the editor opens its page.', '']
    for g in groups:
        L.append(hlp_link(g.title))
    L += ['', 'Every keyword: @Index. Learning: @Tutorial. The editor\'s keys: @{The editor}.',
          'The debugger: @Debugging.',
          'The run-time errors: @Errors. The whole manual: @Manual.', '']
    L.append('= Index')
    line = ''
    for n in sorted(set(e.name for e in entries if e.what != 'apiconst') | {e.name for e in entries if e.what == 'apiconst'}):
        lk = hlp_link(n)
        if line and len(line) + 1 + len(lk) > 76:
            L.append(line)
            line = lk
        else:
            line = lk if not line else line + ' ' + lk
    L += [line, '', 'See also: @Contents', '']
    for g in groups:
        L.append('= ' + g.title)
        for p in paragraphs(g.help):
            L += wrap(p)
            L.append('')
        mem = [e for e in entries if e.group == g.name]
        line = ''
        for e in mem:
            names = [e.name] if e.what != 'apiconst' else [e.name + '...']
            for n in names:
                lk = hlp_link(n if e.what != 'apiconst' else e.name)
                if line and len(line) + 1 + len(lk) > 76:
                    L.append(line)
                    line = lk
                else:
                    line = lk if not line else line + ' ' + lk
        if line:
            L.append(line)
        L.append('')
        for e in mem:
            L.append('= ' + e.name)
            for alt in e.syntax[0].split('   or   '):
                L += wrap_code(alt.strip(), '', '    ')
            L.append('')
            for p in paragraphs(e.help):
                L += wrap(p)
                L.append('')
            if e.what == 'apiconst':
                for n, v, d in e.members:
                    L += wrap_code('%-14s %5d  %s' % (n, v, d), '', ' ' * 22)
                L.append('')
            elif e.what == 'const':
                L.append('Value: %d' % e.value)
                L.append('')
            for x in e.example:
                L.append('  ' + x)
            L.append('')
            if e.see:
                L += wrap('See also: ' + ' '.join(hlp_link(s) for s in e.see), 77)
                L.append('')
    hlp_check('KEYWORDS.HLP', L)
    pages = [ln[2:] for ln in L if ln.startswith('= ')]
    for pg in sorted(set(p for p in pages if pages.count(p) > 1)):
        err('KEYWORDS.HLP has two pages named %r (a group title and a keyword?)' % pg)
    return '\n'.join(L).rstrip('\n') + '\n'


# the help viewer (apps/vbasic/ide/help.c; V149, Sunroom: its scroll bar
# at card columns 78-79) shows 77 columns from column 1 and MAXL lines a
# page
HLP_COLS = 77
HLP_MAXL = 320


def hlp_check(name, L):
    for n, ln in enumerate(L, 1):
        if len(ln) > HLP_COLS:
            err('%s: help line %d is longer than %d characters: %r' % (name, n, HLP_COLS, ln))
    n = 0
    for ln in L + ['= ']:
        if ln.startswith('= '):
            if n > HLP_MAXL:
                err('%s: a page of %d lines (the viewer shows %d)' % (name, n, HLP_MAXL))
            n = 0
        n += 1


def wrap_code(text, first, rest, width=77):
    """a syntax line broken at blanks, continuation lines indented"""
    out, cur = [], first
    for word in text.split(' '):
        if len(cur) + len(word) + 1 > width and cur.strip():
            out.append(cur.rstrip())
            cur = rest
        cur = cur + word + ' ' if word or cur.strip() else cur + ' '
    out.append(cur.rstrip())
    return out


def anchor(name):
    return 'kw-' + re.sub(r'[^a-z0-9]+', '-', name.lower().replace('$', '-s').replace('%', '-i')
                          .replace('<=', 'le').replace('<>', 'ne').replace('>=', 'ge')).strip('-')


def gen_reference(groups, entries):
    L = ['# VeraBASIC language reference', '',
         '*Generated by `tools/vbgen.py` from `vbasic/keywords.tbl`; do not edit.*', '',
         'Every keyword and predefined constant, by group: its syntax, what it does,',
         'an example, and the kernel calls it maps to. In the syntax, `[ ]` marks',
         'what may be left out, `|` alternatives and `...` repetition.', '']
    for g in groups:
        L.append('- [%s](#group-%s)' % (g.title, g.name))
    L.append('')
    for g in groups:
        L.append('<a id="group-%s"></a>' % g.name)
        L.append('')
        L.append('## ' + g.title)
        L.append('')
        for p in paragraphs(g.help):
            L.append(p)
            L.append('')
        for e in (x for x in entries if x.group == g.name):
            L.append('<a id="%s"></a>' % anchor(e.name))
            L.append('')
            L.append('### %s' % (e.name if e.what != 'apiconst' else e.name + '...'))
            L.append('')
            L.append('`%s`' % e.syntax[0])
            L.append('')
            for p in paragraphs(e.help):
                L.append(p)
                L.append('')
            if e.what == 'apiconst':
                L.append('| Name | Value | |')
                L.append('|---|---|---|')
                for n, v, d in e.members:
                    L.append('| `%s` | %d | %s |' % (n, v, d))
                L.append('')
            L.append('```basic')
            L += e.example
            L.append('```')
            L.append('')
            facts = []
            if e.what == 'kw':
                facts.append('Token `%s`' % ('$%02X' % e.token if e.page == 1 else '$FF $%02X' % (e.token & 0xFF)))
                facts.append({'stmt': 'statement', 'func': 'function', 'op': 'operator', 'word': 'word'}[e.kind])
                if e.overlay != '-':
                    facts.append('overlay `%s`' % e.overlay)
                if e.kernel:
                    facts.append('maps to ' + ', '.join('`%s`' % k for k in e.kernel))
            elif e.what == 'const':
                facts.append('constant, value %d' % e.value)
            L.append(' · '.join(facts) + ('.' if facts else ''))
            L.append('')
            if e.see:
                L.append('See also: ' + ', '.join('[%s](#%s)' % (s, anchor(s)) for s in e.see) + '.')
                L.append('')
    return '\n'.join(L).rstrip('\n') + '\n'


# the groups VeraBASIC Run carries out now (phase 1, DECISIONS V86); the
# others are read and checked but their statements give error 20
CARD_NOW = ('program', 'console', 'flow', 'loops', 'select', 'procs', 'data', 'errors', 'operators',
            'strings', 'maths', 'system', 'events')
CARD_ERRORS = [(1, 'Stopped'), (2, 'Syntax error'), (3, 'RETURN without GOSUB'), (4, 'Out of DATA'),
               (5, 'Illegal quantity'), (6, 'Overflow'), (7, 'Out of memory'), (8, 'Undefined line'),
               (9, 'Subscript out of range'), (10, 'Array already dimensioned'), (11, 'Division by zero'),
               (12, 'Not an array'), (13, 'Type mismatch'), (14, 'String too long'),
               (15, 'Formula too complex'), (16, 'Stack overflow'), (17, 'RESUME without error'),
               (18, 'NEXT without FOR'), (19, 'Wrong number of arguments'), (20, 'Not available yet'),
               (21, 'Made by a newer VeraBASIC'), (22, 'Not inside a SUB'), (23, 'BYREF needs a variable')]


def card_text(help_lines):
    """a help text's first sentence, cut to about 70 characters"""
    t = ' '.join(h for h in help_lines if h).split('. ')[0].rstrip('.')
    if len(t) > 72:
        t = t[:70].rsplit(' ', 1)[0].rstrip(',;:') + ' ...'
    return t.replace('|', '\\|')


def gen_refcard(groups, entries):
    """the reference card (v0): every statement and function on one line,
    by group; the operators, the types, the errors"""
    L = ['# VeraBASIC reference card', '',
         '*Version 0, generated by `tools/vbgen.py` from `vbasic/keywords.tbl`; do not edit.*', '',
         '`[ ]` may be left out, `|` one of, `...` more. Groups marked *later* are',
         'checked and tokenized now; their statements run from the phase named in',
         'the plan (VeraBASIC Run gives error 20 until then).', '',
         '## Types and names', '',
         '| | | |', '|---|---|---|',
         '| `a%` | integer | -32768 .. 32767 |',
         '| `a` | float (an integer after `OPTION INTEGER`) | about 9 digits, ±1.7E38 |',
         '| `a$` | string | 0 .. 255 characters |',
         '| `12` `1.5E3` `$FF` `%1010` `"x"` | literals | `""` a quote in a string |', '',
         '## Operators, from the highest priority', '',
         '`^` · unary `-` · `*` `/` `\\` `MOD` · `+` `-` · `SHL` `SHR` · '
         '`=` `<>` `<` `>` `<=` `>=` · `NOT` · `AND` · `OR` `XOR`', '',
         'Comparisons give -1 (true) or 0. Integer `+ - *` stay integers (a result',
         'that does not fit becomes a float); `/` and `^` give floats.', '']
    for g in groups:
        kws = [e for e in entries if e.group == g.name and e.what == 'kw' and e.kind in ('stmt', 'func')
               and e.syntax]
        if not kws:
            continue
        L.append('## %s%s' % (g.title, '' if g.name in CARD_NOW else ' (later)'))
        L.append('')
        L.append('| | |')
        L.append('|---|---|')
        for e in kws:
            L.append('| `%s` | %s |' % (e.syntax[0].replace('|', '\\|'), card_text(e.help)))
        L.append('')
    L += ['## Errors', '', '| | | | |', '|---|---|---|---|']
    half = (len(CARD_ERRORS) + 1) // 2
    for i in range(half):
        a = CARD_ERRORS[i]
        b = CARD_ERRORS[i + half] if i + half < len(CARD_ERRORS) else ('', '')
        L.append('| %s | %s | %s | %s |' % (a[0], a[1], b[0], b[1]))
    L.append('| 200-255 | the program\'s own (`ERROR n, text`) | | |')
    L.append('')
    L += ['## Running', '', '| | |', '|---|---|',
          '| Ctrl+C, STOP | stops the program (error 1) |',
          '| Alt+Tab | puts VeraBASIC Run aside, the program in the middle of its work |',
          '| `vbasic.py build F.bas -o F.cvt` | the program document VeraBASIC Run opens |',
          '| `vbasic.py run --rom rom.bin F.bas` | the reference interpreter on the PC |', '']
    return '\n'.join(L)


def gen_tokens_md(kws):
    L = ['# Appendix B: the token list', '',
         '*Generated by `tools/vbgen.py` from `vbasic/keywords.tbl`; do not edit.*', '',
         'Once released, a token keeps its number (docs/vbasic/FORMAT.md). The',
         'first page is one byte; the second is `$FF` and a byte.', '',
         '| Token | Keyword | Kind | Overlay | Entry |', '|---|---|---|---|---|']
    by_ovl = entries_by_overlay(kws)
    ent = {e.name: i for lst in by_ovl.values() for i, e in enumerate(lst)}
    for e in sorted(kws, key=lambda e: e.token):
        t = '$%02X' % e.token if e.page == 1 else '$FF $%02X' % (e.token & 0xFF)
        L.append('| `%s` | `%s` | %s | %s | %s |' % (t, e.name, e.kind, e.overlay,
                                                  ent[e.name] if e.name in ent else '-'))
    return '\n'.join(L) + '\n'


# the error pages (ERRORS.HLP): each run-time error's number and message
# (tools/vbasic.py ERRORS, the runtime's overlay 1 has the same texts) and
# what it means
ERROR_HELP = {
    1: 'Ctrl+C, the STOP key, Run > Stop or (in VeraBASIC Run) a STOP statement stopped the program. In the editor a STOP statement stops it as a breakpoint does, to go on (F6).',
    2: 'A statement the runtime could not read: a word missing or one too many.',
    3: 'RETURN came with no GOSUB to go back to.',
    4: 'READ found no more DATA items: the program read more than its DATA lines hold. RESTORE starts them again.',
    5: 'A number out of the range the statement or function takes: a negative length, a colour above 15, CHR$(300).',
    6: 'A number too large for a float, or an integer (%) outside -32768 .. 32767 where an integer is needed.',
    7: 'The program needs more RAM banks than there are (its arrays, its strings, OPTION MEMORY), or more room for names in main RAM.',
    8: 'GOTO, GOSUB or THEN names a line number the program has not got.',
    9: 'An array index below 0 or above its DIM.',
    10: 'DIM of an array that is already dimensioned; REDIM changes its size.',
    11: 'A division (/, \\ or MOD) by zero.',
    12: 'A name used with an index that is not an array.',
    13: 'A string where a number is needed, or a number where a string is.',
    14: 'A string longer than 255 characters.',
    15: 'An expression nested too deep for the value stack: split it with a variable.',
    16: 'Too many FOR, GOSUB, procedure or TRY levels at once (about 300): a recursion that does not end?',
    17: 'RESUME outside an ON ERROR handler.',
    18: 'NEXT with no FOR open.',
    19: 'A SUB, FUNCTION or built-in function called with the wrong number of arguments.',
    20: 'A statement this version of VeraBASIC has not got yet.',
    21: 'The program document was made by a newer VeraBASIC than this one.',
    22: 'EXIT SUB, RETURN with a value or LOCAL outside a SUB or FUNCTION.',
    23: 'A BYREF parameter was given a value, not a variable.',
    24: 'FONT names a font that is not in /VERANDA/FONTS.',
    25: 'A window number with no WINDOW open.',
    26: 'More menus or menu items than Veranda\'s menu bar holds.',
    50: 'No file of that name in the folder. The message has the kernel\'s error too, (kernel 5), as ERRFILE gives it.',
    51: 'More than three files open at once.',
    52: 'A file number outside 1 .. 255.',
    53: 'PRINT #, INPUT # or CLOSE of a file number that is not open.',
    54: 'OPEN of a file number that is open already.',
    55: 'A file opened for reading written to, or the other way round, or a mode other than "r", "w", "a", "m".',
    56: 'INPUT #, LINE INPUT # or GET # past the file\'s end: test EOF first.',
    57: 'The card or the folder said no. The message has the kernel\'s error too, (kernel n), as ERRFILE gives it.',
    58: 'A file or folder of that name is there already.',
    59: 'A picture string that is not one (PICTURE$ makes them).',
    60: 'LABEL, FIELD or BUTTON outside a DIALOG block.',
}


def read_errors():
    """tools/vbasic.py's ERRORS (read as text: it imports the generated tables)"""
    src = open(os.path.join(ROOT, 'tools', 'vbasic.py'), encoding='utf-8').read()
    m = re.search(r'^ERRORS = \{(.*?)^\}', src, re.S | re.M)
    return {int(n): t for n, t in re.findall(r"(\d+): '([^']*)'", m.group(1))}


def gen_errors_hlp():
    errs = read_errors()
    for n in errs:
        if n not in ERROR_HELP:
            err('vbgen.py ERROR_HELP: no text for error %d (%s)' % (n, errs[n]))
    L = ['= Errors', 'The run-time errors: the editor shows one in the status bar, with its line',
         'in red, and whole in the pane at the right: the number and the message, a',
         'file\'s kernel error, the line, the procedure, the statement as Format writes',
         'it (Error 13, Type mismatch, in line 57 (SUB Tick): total% = name$); F1 there',
         'opens its page. The console says Error 13, Type mismatch, in line 57.',
         'TRY ... CATCH and ON ERROR GOTO catch them: ERR is the number, ERR$ the',
         'message, ERL the line, ERRFILE the kernel\'s error. Check finds the other',
         'kind before a program runs: see @{Check messages}. See also: @Debugging.', '']
    line = ''
    for n in sorted(errs):
        lk = '@{Error %d}' % n
        if line and len(line) + 1 + len(lk) > 76:
            L.append(line)
            line = lk
        else:
            line = lk if not line else line + ' ' + lk
    L += [line, '', 'See also: @TRY @ERR @ERL @ERROR @Contents', '']
    for n in sorted(errs):
        L.append('= Error %d' % n)
        L.append(errs[n])
        L.append('')
        L += wrap(ERROR_HELP.get(n, ''))
        L += ['', 'See also: @Errors', '']
    L += ['= Check messages',
          'Check (Ctrl+K), and Run before a program starts, read the whole program',
          'first: these are found then, with the line they are in, and F8 goes to the',
          'next. The tokenizer: Unexpected character, Line too long, String too long,',
          'Number too big, Name too long, Line number out of range, Too many names,',
          'Program too big. The blocks: X without Y (NEXT without FOR), Y missing for',
          'X in line N (END IF missing for IF in line 40), NEXT j does not match FOR i,',
          'Two ELSE parts, CASE expected after SELECT CASE, THEN missing after IF, X',
          'inside a one-line IF. Procedures: SUB B inside SUB A, defined twice, EXIT',
          'SUB outside SUB, LOCAL outside a SUB or FUNCTION. Names: Undefined label X,',
          'Undefined line N, Undefined SUB X, Label X defined twice, Cannot assign to',
          'constant X.', '', 'See also: @Errors @{The editor}', '']
    return '\n'.join(L).rstrip('\n') + '\n'


def gen_errors_md():
    """the manual's appendix of the run-time errors (DECISIONS V99), from the
    same table as ERRORS.HLP"""
    errs = read_errors()
    L = ['# Appendix A: error messages', '',
         'The run-time errors, from the same table as the runtime\'s messages and',
         'the help\'s pages (`ERRORS.HLP`; tools/vbgen.py writes all three). The',
         'editor shows one whole in the debugger\'s pane (chapter 6): `Error 13,',
         'Type mismatch, in line 57 (SUB Tick): total% = name$`; a file\'s error',
         'has the kernel\'s code too, `(kernel 5)`. `{TRY}` ... `{CATCH}` and',
         '`{ON}` `{ERROR}` `{GOTO}` catch them: `{ERR}` is the number, `{ERR$}` the',
         'message, `{ERL}` the line, `{ERRFILE}` the kernel\'s error.', '',
         '| Number | Message | What it means |', '|---|---|---|']
    for n in sorted(errs):
        L.append('| %d | %s | %s |' % (n, errs[n], ERROR_HELP.get(n, '').replace('|', '\\|')))
    L += ['', '## Check\'s messages', '',
          'Check (Ctrl+K), Run before a program starts, and `vbasic.py check` read',
          'the whole program first and report these with their line:', '',
          '- the tokenizer: *Unexpected character*, *Line too long*, *String too',
          '  long*, *Number too big*, *Name too long*, *Line number out of range*,',
          '  *Too many names*, *Program too big*;',
          '- the blocks: *X without Y* (*NEXT without FOR*), *Y missing for X in',
          '  line N*, *NEXT j does not match FOR i*, *Two ELSE parts*, *CASE expected',
          '  after SELECT CASE*, *THEN missing after IF*;',
          '- procedures: *SUB B inside SUB A*, *defined twice*, *EXIT SUB outside',
          '  SUB*, *LOCAL outside a SUB or FUNCTION*;',
          '- names: *Undefined label X*, *Undefined line N*, *Undefined SUB X*,',
          '  *Label X defined twice*, *Cannot assign to constant X*.', '',
          'Make application adds its own (chapter 7): *APP: NAME "...", CLASS',
          '"...", TILE SKY ...* for an `{APP}` line it cannot read, *TILE DATA: 32',
          'rows of 32 "#" and "."*, *APP DOCUMENTS: up to 4 of 1-4 letters*, *The',
          'name: 1-63 characters*; and VeraBASIC Run, given a program made by a',
          'later version, *Made by a newer VeraBASIC*.', '']
    return '\n'.join(L)


# the manual in help form (MANUAL.HLP, DECISIONS V99): the chapters that
# have no help file of their own (the tutorial, the editor and debugging
# are TUTORIAL.HLP and EDITOR.HLP; the reference, and with it every
# statement of the extensions' chapters by group, is KEYWORDS.HLP), with a
# first page that lists them all; 40 KB at most, so that the viewer has it
# and KEYWORDS.HLP in the 12 RAM banks VeraBASIC leaves free at rest
# (512 KB)
MANUAL_HLP = [('getting-started.md', 'Getting started'), ('language.md', 'The language'),
              ('events.md', 'Events'), ('making-apps.md', 'Making applications'),
              ('from-v2.md', 'Coming from V2 BASIC'), ('appendix-limits.md', 'Memory limits'),
              ('appendix-maths.md', 'The ROM maths')]


def gen_manual_hlp():
    mdir = os.path.join(ROOT, 'docs', 'vbasic', 'manual')
    L = ['= Manual', 'The VeraBASIC manual, chapter by chapter:', '']
    for _, t in MANUAL_HLP:
        L.append('@{%s}' % t)
    L += ['@Tutorial', '@{The editor}', '@Debugging', '@Errors', '@Contents', '',
          'The Veranda statements (windows, menus, graphics, files, dialogs ...)',
          'are in the keywords\' pages, by group: @Contents.', '']
    text = '\n'.join(L) + '\n'
    for f, t in MANUAL_HLP:
        text += '\n' + md_to_hlp(os.path.join(mdir, f), t)
    if len(text.encode('latin-1', 'replace')) > 40960:
        err('MANUAL.HLP is %d bytes: 40 KB at most (5 RAM banks beside KEYWORDS.HLP)' % len(text))
    return text


def md_to_hlp(path, first):
    """a Markdown chapter as help pages: '#' and '##' headings start pages
    (the first named `first`), ```basic blocks indented by 2, {KEYWORD} a
    link, tables and paragraphs wrapped at 76; *, `, ** dropped"""
    L, para, code, page1 = [], [], False, True

    def inline(t):
        t = re.sub(r'\{([A-Z][A-Z0-9_$% ]*)\}', lambda m: hlp_link(m.group(1)), t)
        t = re.sub(r'\[([^\]]*)\]\([^)]*\)', r'\1', t)
        return t.replace('**', '').replace('`', '').replace('*', '')

    def flush():
        if para:
            L.extend(wrap(inline(' '.join(para))))
            L.append('')
            para.clear()
    for raw in open(path, encoding='utf-8'):
        ln = raw.rstrip('\n')
        if code:
            if ln.startswith('```'):
                code = False
                L.append('')
            else:
                L.append(('  ' + ln)[:77].rstrip())
            continue
        if ln.startswith('```'):
            flush()
            code = True
            continue
        if ln.startswith('#'):
            flush()
            title = ln.lstrip('#').strip()
            if page1:
                title, page1 = first, False
            L.append('= ' + inline(title).replace('@', '').replace('{', '').replace('}', ''))
            continue
        if ln.startswith('|'):
            flush()
            cells = [inline(c.strip()) for c in ln.strip('|').split('|')]
            if all(re.fullmatch(r'-*', c) for c in cells):
                continue
            L.extend(wrap(': '.join(c for c in cells if c), 76))
            continue
        if ln.startswith('- ') or ln.startswith('1. '):
            flush()
            para.append(ln)
            continue
        if not ln.strip():
            flush()
            continue
        para.append(ln.strip())
    flush()
    L.append('See also: @Contents')
    # the first page lists the others
    pages = [i for i, ln in enumerate(L) if ln.startswith('= ')]
    if len(pages) > 1:
        L[pages[1]:pages[1]] = ['@{%s}' % L[i][2:] for i in pages[1:]] + ['']
    hlp_check(os.path.relpath(path, ROOT), L)
    return '\n'.join(L).rstrip('\n') + '\n'


def check_manual(names):
    mdir = os.path.join(ROOT, 'docs', 'vbasic', 'manual')
    for path in sorted(glob.glob(os.path.join(mdir, '*.md'))):
        if os.path.basename(path) in GENERATED:
            continue
        for no, line in enumerate(open(path, encoding='utf-8'), 1):
            for m in re.finditer(r'\{([A-Z][A-Z0-9_$% ]*)\}', line):
                if m.group(1) not in names:
                    err('%s:%d: {%s} is not in the keyword table' % (os.path.relpath(path, ROOT), no, m.group(1)))


def main(argv):
    tbl = os.path.join(ROOT, 'vbasic', 'keywords.tbl')
    api = os.path.join(ROOT, 'api', 'veranda.api')
    out = ROOT
    only_check = False
    i = 0
    while i < len(argv):
        a = argv[i]
        if a in ('--tbl', '--api', '--out') and i + 1 < len(argv):
            if a == '--tbl':
                tbl = argv[i + 1]
            elif a == '--api':
                api = argv[i + 1]
            else:
                out = argv[i + 1]
            i += 2
        elif a == '--check-only':
            only_check = True
            i += 1
        else:
            print(__doc__, file=sys.stderr)
            return 2
    groups, entries, retired, api_names, api_consts = parse(tbl, api)
    kws, consts = check(groups, entries, retired, api_names, api_consts)
    names = {e.name for e in entries} | {m[0] for e in entries if e.what == 'apiconst' for m in e.members}
    check_manual(names)
    if errors:
        for e in errors:
            print('vbgen: ' + e, file=sys.stderr)
        print('vbgen: %d problem(s)' % len(errors), file=sys.stderr)
        return 1
    apiconsts = [e for e in entries if e.what == 'apiconst']
    files = {
        'vbasic/gen/tokens.inc': gen_inc(kws, consts, apiconsts),
        'tools/vbtokens_gen.py': gen_py(kws, consts, apiconsts),
        'vbasic/gen/HELP/KEYWORDS.HLP': gen_hlp(groups, entries),
        'docs/vbasic/manual/reference.md': gen_reference(groups, entries),
        'docs/vbasic/manual/tokens.md': gen_tokens_md(kws),
        'docs/vbasic/manual/refcard.md': gen_refcard(groups, entries),
        'vbasic/gen/idekw.h': gen_idekw(kws, consts),
        'vbasic/gen/HELP/ERRORS.HLP': gen_errors_hlp(),
        'docs/vbasic/manual/appendix-errors.md': gen_errors_md(),
        'vbasic/gen/HELP/MANUAL.HLP': gen_manual_hlp(),
        'vbasic/gen/HELP/TUTORIAL.HLP': md_to_hlp(os.path.join(ROOT, 'docs', 'vbasic', 'manual', 'tutorial.md'),
                                                  'Tutorial'),
        'vbasic/gen/HELP/EDITOR.HLP': md_to_hlp(os.path.join(ROOT, 'docs', 'vbasic', 'manual', 'editor.md'),
                                                'The editor')
        + '\n' + md_to_hlp(os.path.join(ROOT, 'docs', 'vbasic', 'manual', 'debugging.md'), 'Debugging'),
    }
    if errors:
        for e in errors:
            print('vbgen: ' + e, file=sys.stderr)
        print('vbgen: %d problem(s)' % len(errors), file=sys.stderr)
        return 1
    p1 = sum(1 for e in kws if e.page == 1)
    nconst = len(consts) + sum(len(e.members) for e in apiconsts)
    if not only_check:
        for rel, text in files.items():
            path = os.path.join(out, rel)
            os.makedirs(os.path.dirname(path), exist_ok=True)
            enc = 'latin-1' if rel.endswith(('.HLP', '.inc')) else 'utf-8'
            with open(path, 'w', encoding=enc, newline='\n') as f:
                f.write(text)
    print('vbgen: %d keywords (%d first page, %d second), %d compounds, %d constants, %d groups'
          % (len(kws), p1, len(kws) - p1, sum(1 for e in kws if ' ' in e.name), nconst, len(groups)))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
