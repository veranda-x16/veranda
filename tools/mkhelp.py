#!/usr/bin/env python3
"""The Veranda manual (docs/manual, GitHub Markdown) as plain text for the
X16 (DECISIONS V134): the desktop's Veranda > Help opens the first file in
View, whose Esc lists the others (View's Open box shows .TXT files).

    tools/mkhelp.py <dir>       write the files into <dir> (VERANDA/HELP)
    tools/mkhelp.py --check     convert, check, write nothing

Files (the parts follow _Sidebar.md's groups):
    Veranda manual.txt                          the start page: how to
                                                move around, the contents
    Veranda manual 1 - Getting started.txt      ...
    Veranda manual 5 - Reference.txt

The text is ASCII (letters with accents lose them: View draws the X16's
CP437 font, Latin-1 would show wrong), lines of 76 columns at most (View
wraps at 80), a page starting with a line "== Title" (so Show > Find
"== Paint" goes to it); pictures are left out, a link to another page is
its title in brackets, a web link its text and address. Each part is
48 KB at most, so that View (which keeps a text in RAM banks with a
quarter more for its lines) opens it with programs put aside on a 512 KB
X16. MIT licence (see LICENSE).
"""
import os
import re
import sys
import unicodedata

HERE = os.path.dirname(os.path.abspath(__file__))
MANUAL = os.path.join(HERE, '..', 'docs', 'manual')
WIDTH = 76
PART_MAX = 48 * 1024
START = 'Veranda manual.txt'
# _Sidebar.md's groups into the parts (a group not named here: an error)
PARTS = [
    ('Getting started', ['Getting started']),
    ('Programs', ['Programs', 'Desk accessories']),
    ('Network', ['Network']),
    ('Music, games and BASIC', ['Music, games, BASIC']),
    ('Reference', ['Reference']),
]

errors = []


def ascii_text(s):
    s = s.replace('ł', 'l').replace('Ł', 'L').replace('−', '-')
    s = s.replace('‘', "'").replace('’', "'").replace('“', '"').replace('”', '"')
    s = s.replace('–', '-').replace('—', '-').replace('…', '...')
    s = s.replace('×', 'x').replace('÷', '/').replace('±', '+/-').replace('π', 'pi').replace('√', 'sqrt ')
    s = s.replace('⌫', '<-')
    s = unicodedata.normalize('NFKD', s)
    s = ''.join(c for c in s if not unicodedata.combining(c))
    return s.encode('ascii', 'replace').decode('ascii')


def inline(t, titles):
    """Markdown inline to plain text: code spans kept as they are, links
    by kind, emphasis dropped"""
    spans = []

    def keep(m):
        spans.append(m.group(1))
        return '\0%d\0' % (len(spans) - 1)
    t = re.sub(r'`([^`]*)`', keep, t)
    t = re.sub(r'!\[[^\]]*\]\([^)]*\)', '', t)

    def link(m):
        text, target = m.group(1), m.group(2)
        if re.match(r'https?://', target):
            return text if text in target else '%s (%s)' % (text, target)
        page = target.split('#')[0]
        if page.endswith('.md') and '/' not in page:
            if page[:-3] not in titles:
                errors.append('a link to %s, which is not a page' % target)
            return '[%s]' % titles.get(page[:-3], text)
        return text
    t = re.sub(r'\[([^\]]*)\]\(([^)]*)\)', link, t)
    t = t.replace('**', '').replace('__', '')
    t = re.sub(r'(?<![\w*])\*([^*\s][^*]*)\*(?![\w*])', r'\1', t)
    t = re.sub(r'\0(\d+)\0', lambda m: spans[int(m.group(1))], t)
    return t


def wrap(text, first, rest, width=WIDTH):
    """text in lines of width at most (a longer word alone), the first
    line starting with first, the others with rest"""
    out, line, empty = [], first, True
    for w in text.split():
        if not empty and len(line) + 1 + len(w) > width:
            out.append(line)
            line, empty = rest, True
        line += w if empty else ' ' + w
        empty = False
    if not empty:
        out.append(line)
    return out


def table(rows, titles):
    cells = [[inline(c.strip(), titles) for c in r.strip().strip('|').split('|')] for r in rows]
    cells = [r for r in cells if not all(re.fullmatch(r':?-+:?', c) for c in r)]
    n = max(len(r) for r in cells)
    for r in cells:
        r += [''] * (n - len(r))
    w = [max(len(r[i]) for r in cells) for i in range(n)]
    if sum(w) + 2 * (n - 1) + 2 <= WIDTH:
        out = []
        for k, r in enumerate(cells):
            out.append(('  ' + '  '.join(r[i].ljust(w[i]) for i in range(n))).rstrip())
            if k == 0:
                out.append('  ' + '  '.join('-' * w[i] for i in range(n)))
        return out
    out = []                            # (too wide: a row a list item, the header left out)
    for r in cells[1:]:
        rest = '; '.join(c for c in r[1:] if c)
        out += wrap((r[0] + ': ' + rest) if rest else r[0], '  - ', '    ')
    return out


def page(path, titles):
    """one Markdown page as text lines"""
    out, para, rows = [], [], []
    code = False
    lines = open(path, encoding='utf-8').read().split('\n')
    bullet = None                       # (the open list item's first-line prefix, its indent)

    def flush():
        nonlocal bullet
        if para:
            text = inline(' '.join(para), titles)
            if bullet:
                out.extend(wrap(text, bullet[0], bullet[1]))
            else:
                out.extend(wrap(text, '', ''))
            para.clear()
        bullet = None

    def flush_table():
        if rows:
            out.extend(table(rows, titles))
            out.append('')
            rows.clear()
    for ln in lines:
        if code:
            if ln.strip().startswith('```'):
                code = False
                out.append('')
            else:
                out.append('    ' + ln)
            continue
        if ln.strip().startswith('```'):
            flush()
            flush_table()
            code = True
            continue
        if ln.startswith('|'):
            flush()
            rows.append(ln)
            continue
        flush_table()
        if not ln.strip():
            flush()
            if out and out[-1] != '':
                out.append('')
            continue
        if re.match(r' {4,}\S', ln) and not para and bullet is None:
            out.append(ln.rstrip())     # (an indented block: code)
            continue
        m = re.match(r'(#+)\s+(.*)', ln)
        if m:
            flush()
            t = inline(m.group(2), titles)
            if out and out[-1] != '':
                out.append('')
            if len(m.group(1)) == 1:
                out += ['== ' + t, '']
            else:
                out += [t, ('-' if len(m.group(1)) == 2 else '.') * len(t), '']
            continue
        m = re.match(r'(\s*)([-*]|\d+\.)\s+(.*)', ln)
        if m:
            flush()
            ind = '  ' * (len(m.group(1)) // 2)
            mark = '-' if m.group(2) in '-*' else m.group(2)
            bullet = (ind + mark + ' ', ind + ' ' * (len(mark) + 1))
            para.append(m.group(3))
            continue
        if re.match(r'\s+\S', ln) and re.match(r'\s{4,}', ln) and not para:
            out.append(ln.rstrip())
            continue
        para.append(ln.strip())
    flush()
    flush_table()
    while out and out[-1] == '':
        out.pop()
    return out


def sidebar():
    """_Sidebar.md: [(group, [page names])]"""
    groups = []
    for ln in open(os.path.join(MANUAL, '_Sidebar.md'), encoding='utf-8'):
        m = re.match(r'\*\*([^*\[]+)\*\*\s*$', ln.strip())
        if m:
            groups.append((m.group(1), []))
            continue
        m = re.match(r'- \[[^\]]*\]\(([^)]+)\.md\)', ln.strip())
        if m and groups:
            groups[-1][1].append(m.group(1))
    return groups


def title_of(name):
    for ln in open(os.path.join(MANUAL, name + '.md'), encoding='utf-8'):
        if ln.startswith('# '):
            return ln[2:].strip()
    errors.append('%s.md has no "# " title' % name)
    return name


def build():
    groups = dict(sidebar())
    names = [f[:-3] for f in os.listdir(MANUAL) if f.endswith('.md') and not f.startswith('_')]
    titles = {n: title_of(n) for n in names}
    named = set()
    for _, gs in PARTS:
        for g in gs:
            if g not in groups:
                errors.append('_Sidebar.md has no group "%s"' % g)
    for g, pages in groups.items():
        if not any(g in gs for _, gs in PARTS):
            errors.append('_Sidebar.md\'s group "%s" is in no part (tools/mkhelp.py PARTS)' % g)
        named.update(pages)
    for n in names:
        if n != 'Home' and n not in named:
            errors.append('%s.md is not in _Sidebar.md' % n)
    files = {}
    contents = []
    for k, (ptitle, gs) in enumerate(PARTS, 1):
        fname = 'Veranda manual %d - %s.txt' % (k, ptitle.replace(',', ''))   # (no comma: CMDR-DOS's separator; V139)
        pages = [p for g in gs for p in groups.get(g, [])]
        L = ['VERANDA MANUAL, PART %d: %s' % (k, ptitle.upper()), '',
             'Press Esc for the other parts. Show > Find... "== " and a title goes to',
             'a page.', '', 'In this part:']
        L += ['  ' + titles[p] for p in pages]
        contents.append((fname, ptitle, [titles[p] for p in pages]))
        for p in pages:
            L += ['', '', ''] + page(os.path.join(MANUAL, p + '.md'), titles)
        files[fname] = L
    home = page(os.path.join(MANUAL, 'Home.md'), titles)
    intro = []
    for ln in home[1:]:
        if ln.startswith('Start here'):
            break
        intro.append(ln)
    S = ['VERANDA MANUAL', '', 'Veranda > Help in the desktop opens this page.', '']
    while intro and not intro[-1].strip():
        intro.pop()
    while intro and not intro[0].strip():
        intro.pop(0)
    S += intro
    S += ['', 'How to read it', '--------------', '',
          'This manual is in parts, one file each, in /VERANDA/HELP. In View:',
          '',
          '  Up, Down          a line',
          '  PgUp, PgDn, Space a page',
          '  Home, End         the start, the end of the part',
          '  Esc               the Open box: choose another part, press Return',
          '',
          'To go to a page, use Show > Find... with "== " and its title, for',
          'example "== Paint". Show > Find again finds the next place.',
          'A link to another page is its title in brackets: [Paint].',
          'The pictures are in the manual on GitHub (docs/manual).', '',
          'The parts', '---------', '']
    for fname, ptitle, ts in contents:
        S.append(fname)
        S += wrap(', '.join(ts) + '.', '    ', '    ')
        S.append('')
    files[START] = S
    text = {}
    for f, L in files.items():
        t = ascii_text('\n'.join(L).rstrip('\n') + '\n')
        for n, ln in enumerate(t.split('\n'), 1):
            if len(ln) > WIDTH + 4:
                errors.append('%s: line %d is %d characters: %r' % (f, n, len(ln), ln))
        if len(t) > PART_MAX:
            errors.append('%s is %d bytes: %d at most (split the part)' % (f, len(t), PART_MAX))
        if len(f) > 63:
            errors.append('%s: a name longer than 63 characters' % f)
        text[f] = t
    return text


def main(argv):
    if len(argv) != 1 or argv[0] in ('-h', '--help'):
        print(__doc__, file=sys.stderr)
        return 2
    text = build()
    if errors:
        for e in errors:
            print('mkhelp: ' + e, file=sys.stderr)
        return 1
    if argv[0] == '--check':
        for f, t in sorted(text.items()):
            print('%6d  %s' % (len(t), f))
        return 0
    os.makedirs(argv[0], exist_ok=True)
    for f, t in text.items():
        with open(os.path.join(argv[0], f), 'w', encoding='ascii', newline='\n') as o:
            o.write(t)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
