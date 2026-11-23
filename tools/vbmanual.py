#!/usr/bin/env python3
"""Turn the VeraBASIC manual's Markdown (docs/vbasic/manual) into HTML and PDF.

usage: vbmanual.py OUTDIR [--chapters a.md b.md ...] [--refcard refcard.md]
                   [--check]

Writes, under OUTDIR:
  html/index.html                  the contents: each chapter by its first
                                   heading, with its ## sections
  html/<chapter>.html              a page a chapter, with Contents,
                                   Previous and Next; headings carry
                                   GitHub-style ids, so chapter.md#anchor
                                   links resolve as chapter.html#anchor
  html/refcard.html                the reference card as a page
  VeraBASIC-manual.pdf             the whole manual: a title page, the
                                   contents with page numbers, the chapters
                                   (each from a new page), bookmarks and
                                   internal links
  VeraBASIC-reference-card.pdf     the reference card on exactly two A4
                                   pages, four columns, the type size
                                   chosen to fit

The chapters default to CHAPTERS below, in that order, from
docs/vbasic/manual; one that does not exist (yet) is skipped with a
warning. A chapter given on the command line is a path (or a name in
docs/vbasic/manual). The PDFs use the standard fonts (Helvetica and
Courier, WinAnsiEncoding, nothing embedded) and need nothing but Python's
standard library. --check re-reads what was written (the PDFs' xref
tables, the card's page count, the HTML's links; qpdf and pdftotext too
when they are installed) and exits with status 1 on a problem.

As a module: build(outdir, chapters, refcard_md) returns the files written,
check(outdir) the problems found (an empty list when there are none).

MIT licence (LICENSE).
"""
import argparse
import html
import os
import re
import shutil
import subprocess
import sys
import unicodedata
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MANUAL_DIR = os.path.join(ROOT, 'docs', 'vbasic', 'manual')

# The manual's chapters, in their order.
CHAPTERS = [
    'getting-started.md', 'language.md', 'extensions.md', 'extensions2.md',
    'events.md', 'tutorial.md', 'editor.md', 'debugging.md',
    'making-apps.md', 'from-v2.md', 'appendix-errors.md', 'tokens.md',
    'appendix-limits.md', 'appendix-maths.md', 'reference.md',
]
REFCARD = 'refcard.md'

MANUAL_PDF = 'VeraBASIC-manual.pdf'
REFCARD_PDF = 'VeraBASIC-reference-card.pdf'
TITLE = 'The VeraBASIC manual'


# ---------------------------------------------------------------- Markdown
#
# Blocks are tuples: ('h', level, text), ('p', text), ('list', items) with
# items (depth, number or None, text), ('table', head, rows), ('code', kind,
# lines), ('anchor', id), ('rule',). Text stays Markdown until the inline
# parser turns it into spans.

FENCE = re.compile(r'^\s*```\s*([\w-]*)(.*)$')
HEADING = re.compile(r'^(#{1,6})\s+(.*?)\s*#*\s*$')
ANCHOR = re.compile(r'^\s*<a\s+(?:id|name)="([^"]+)"\s*>\s*</a>\s*$')
ITEM = re.compile(r'^(\s*)([-*+]|\d+[.)])\s+(.*)$')
TABLE_SEP = re.compile(r'^\s*\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?\s*$')
RULE = re.compile(r'^\s*([-*_])(\s*\1){2,}\s*$')


def split_row(line):
    """A table row's cells; '\\|' is a | inside a cell."""
    line = line.strip()
    if line.startswith('|'):
        line = line[1:]
    if line.endswith('|') and not line.endswith('\\|'):
        line = line[:-1]
    cells = re.split(r'(?<!\\)\|', line)
    return [c.strip().replace('\\|', '|') for c in cells]


def starts_block(lines, i):
    """Whether line i starts a block that ends a paragraph."""
    line = lines[i]
    if FENCE.match(line) or HEADING.match(line) or ANCHOR.match(line):
        return True
    m = ITEM.match(line)
    if m and (not m.group(2)[0].isdigit() or m.group(2)[:-1] == '1'):
        return True
    return (line.lstrip().startswith('|') and i + 1 < len(lines)
            and TABLE_SEP.match(lines[i + 1]) is not None)


def parse_blocks(text):
    lines = text.expandtabs(4).split('\n')
    blocks = []
    i = 0
    n = len(lines)
    while i < n:
        line = lines[i]
        if not line.strip():
            i += 1
            continue
        m = FENCE.match(line)
        if m:
            kind = m.group(1).lower()
            body = []
            i += 1
            while i < n and not lines[i].strip().startswith('```'):
                body.append(lines[i])
                i += 1
            blocks.append(('code', kind, body))
            i += 1
            continue
        m = ANCHOR.match(line)
        if m:
            blocks.append(('anchor', m.group(1)))
            i += 1
            continue
        m = HEADING.match(line)
        if m:
            blocks.append(('h', len(m.group(1)), m.group(2)))
            i += 1
            continue
        if line.startswith('    '):
            # An indented code block, blank lines inside it kept.
            body = []
            while i < n and (lines[i].startswith('    ') or not lines[i].strip()):
                body.append(lines[i][4:])
                i += 1
            while body and not body[-1].strip():
                body.pop()
            blocks.append(('code', '', body))
            continue
        if line.lstrip().startswith('|') and i + 1 < n and TABLE_SEP.match(lines[i + 1]):
            head = split_row(line)
            rows = []
            i += 2
            while i < n and lines[i].lstrip().startswith('|'):
                rows.append(split_row(lines[i]))
                i += 1
            blocks.append(('table', head, rows))
            continue
        if RULE.match(line):
            blocks.append(('rule',))
            i += 1
            continue
        m = ITEM.match(line)
        if m:
            items = []
            while i < n:
                m = ITEM.match(lines[i])
                if m:
                    depth = len(m.group(1)) // 2
                    mark = m.group(2)
                    num = mark[:-1] if mark[0].isdigit() else None
                    items.append([depth, num, m.group(3)])
                    i += 1
                elif lines[i].strip() and lines[i].startswith(' '):
                    items[-1][2] += ' ' + lines[i].strip()    # continuation
                    i += 1
                elif not lines[i].strip():
                    # A blank line ends the list unless an item follows.
                    j = i
                    while j < n and not lines[j].strip():
                        j += 1
                    if j < n and ITEM.match(lines[j]):
                        i = j
                    else:
                        break
                else:
                    break
            blocks.append(('list', [tuple(it) for it in items]))
            continue
        para = [line.strip()]
        i += 1
        while i < n and lines[i].strip() and not starts_block(lines, i):
            para.append(lines[i].strip())
            i += 1
        text = ' '.join(para)
        if text.startswith('>'):
            text = re.sub(r'(^|\s)>\s?', r'\1', text)    # a quote: as text
        blocks.append(('p', text))
    return blocks


class Span:
    """A run of text in one style, perhaps a link."""
    __slots__ = ('text', 'bold', 'italic', 'code', 'link')

    def __init__(self, text, bold=False, italic=False, code=False, link=None):
        self.text = text
        self.bold = bold
        self.italic = italic
        self.code = code
        self.link = link


KEYWORD = re.compile(r'\{([A-Z][A-Z0-9$%#]*(?: [A-Z][A-Z0-9$%#]*)*)\}')
INLINE = re.compile(
    r'(?P<esc>\\[\\`*_{}\[\]()#+\-.!|<>])'
    r'|(?P<code>(?P<ticks>`+)(?P<ctext>.+?)(?P=ticks))'
    r'|(?P<link>\[(?P<ltext>(?:[^\[\]]|`[^`]*`)*)\]\((?P<url>[^)\s]*)\))'
    r'|(?P<kw>\{[A-Z][A-Z0-9$%#]*(?: [A-Z][A-Z0-9$%#]*)*\})'
    r'|(?P<html><a\s[^>]*>|</a>|<br\s*/?>)'
    r'|(?P<star>\*\*|\*)')
CLOSE_BOLD = re.compile(r'(?<=[^\s*])\*\*')
CLOSE_ITALIC = re.compile(r'(?<=[^\s*])\*(?!\*)')


def parse_inline(text, link=None, bold=False, italic=False):
    """Markdown text to a list of Spans."""
    spans = []
    plain = []

    def flush():
        if plain:
            spans.append(Span(''.join(plain), bold, italic, False, link))
            plain.clear()

    pos = 0
    for m in INLINE.finditer(text):
        plain.append(text[pos:m.start()])
        pos = m.end()
        if m.group('esc'):
            plain.append(m.group('esc')[1])
        elif m.group('code'):
            flush()
            code = m.group('ctext')
            if code.startswith(' ') and code.endswith(' ') and code.strip():
                code = code[1:-1]
            spans.append(Span(KEYWORD.sub(r'\1', code), bold, italic, True, link))
        elif m.group('link'):
            flush()
            spans.extend(parse_inline(m.group('ltext'), m.group('url'), bold, italic))
        elif m.group('kw'):
            flush()
            spans.append(Span(m.group('kw')[1:-1], bold, italic, True, link))
        elif m.group('html'):
            pass
        else:
            star = m.group('star')
            before = text[m.start() - 1] if m.start() else ' '
            after = text[m.end()] if m.end() < len(text) else ' '
            on = bold if star == '**' else italic
            # An opening star needs a closing one further on.
            closer = CLOSE_BOLD if star == '**' else CLOSE_ITALIC
            if (on and not before.isspace()) or (
                    not on and not after.isspace() and closer.search(text, m.end() + 1)):
                flush()
                if star == '**':
                    bold = not bold
                else:
                    italic = not italic
            else:
                plain.append(star)
    plain.append(text[pos:])
    flush()
    return [s for s in spans if s.text]


def plain_text(text):
    return ''.join(s.text for s in parse_inline(text))


def slugify(text):
    """GitHub's heading ids: lower case, punctuation gone, spaces to -."""
    s = plain_text(text).lower()
    s = ''.join(c for c in s if c.isalnum() or c in ' -_')
    return s.replace(' ', '-')


class Chapter:
    def __init__(self, path):
        self.path = path
        self.name = os.path.splitext(os.path.basename(path))[0]
        with open(path, encoding='utf-8') as f:
            self.blocks = parse_blocks(f.read())
        # Each heading's id, duplicates numbered as GitHub numbers them.
        self.ids = {}
        seen = {}
        for k, b in enumerate(self.blocks):
            if b[0] == 'h':
                slug = slugify(b[2])
                if slug in seen:
                    seen[slug] += 1
                    slug = '%s-%d' % (slug, seen[slug])
                else:
                    seen[slug] = 0
                self.ids[k] = slug
        heads = [b for b in self.blocks if b[0] == 'h']
        self.title = plain_text(heads[0][2]) if heads else self.name
        self.sections = [(plain_text(b[2]), self.ids[k])
                         for k, b in enumerate(self.blocks)
                         if b[0] == 'h' and b[1] == 2]


class Links:
    """Where a link goes: ('chapter', name, anchor) for a page of the manual
    (or the card), else ('web', url) or ('outside', path)."""

    def __init__(self, names, card=None):
        self.names = set(names)
        self.card = card

    def resolve(self, url, cur):
        if re.match(r'[a-z]+:', url):
            return ('web', url)
        path, _, anchor = url.partition('#')
        if not path:
            return ('chapter', cur, anchor)
        name, ext = os.path.splitext(path)
        if ext == '.md' and '/' not in path and (name in self.names or name == self.card):
            return ('chapter', name, anchor)
        return ('outside', path)


# -------------------------------------------------------------------- HTML

STYLE = """
body { font: 16px/1.5 -apple-system, "Segoe UI", Helvetica, Arial, sans-serif;
  color: #1d1d1f; background: #fff; margin: 0; }
main { max-width: 52em; margin: 0 auto; padding: 1em 1.2em 3em; }
nav { background: #f2f2f4; border-bottom: 1px solid #ddd; padding: .5em 1.2em;
  font-size: 14px; }
nav a { margin-right: 1.2em; }
a { color: #0b57a4; }
h1 { font-size: 1.9em; border-bottom: 2px solid #ccc; padding-bottom: .2em; }
h2 { font-size: 1.4em; margin-top: 1.8em; border-bottom: 1px solid #e0e0e0; }
h3 { font-size: 1.15em; margin-top: 1.5em; }
code, pre { font-family: Menlo, Consolas, "DejaVu Sans Mono", monospace;
  font-size: .9em; }
code { background: #f3f3f5; padding: 0 .2em; border-radius: 3px; }
pre { background: #f3f3f5; border: 1px solid #e2e2e6; border-radius: 4px;
  padding: .6em .8em; overflow-x: auto; line-height: 1.35; }
pre code { background: none; padding: 0; }
.label { font-size: .8em; font-style: italic; color: #666; margin: 0 0 -.8em; }
table { border-collapse: collapse; margin: 1em 0; font-size: .92em; }
th, td { border: 1px solid #d0d0d6; padding: .3em .6em; vertical-align: top;
  text-align: left; }
th { background: #f0f0f3; }
ul.toc > li { margin: .5em 0; }
ul.toc ul { font-size: .92em; }
@media print {
  nav { display: none; }
  main { max-width: none; padding: 0; }
  body { font-size: 11pt; }
  a { color: inherit; text-decoration: none; }
  pre, table, h2, h3 { page-break-inside: avoid; }
  h2, h3 { page-break-after: avoid; }
}
"""


def html_inline(spans, links, cur):
    out = []
    for s in spans:
        t = html.escape(s.text, quote=False)
        if s.code:
            t = '<code>%s</code>' % t
        if s.italic:
            t = '<em>%s</em>' % t
        if s.bold:
            t = '<strong>%s</strong>' % t
        out.append((s.link, t))
    # Neighbouring spans of one link share one <a>.
    res = []
    k = 0
    while k < len(out):
        link = out[k][0]
        j = k
        while j < len(out) and out[j][0] == link:
            j += 1
        body = ''.join(t for _, t in out[k:j])
        if link is None:
            res.append(body)
        else:
            where = links.resolve(link, cur)
            if where[0] == 'chapter':
                href = ('%s.html' % where[1] if where[1] != cur else '') + \
                    ('#' + where[2] if where[2] else '')
                res.append('<a href="%s">%s</a>' % (html.escape(href or '#'), body))
            elif where[0] == 'web':
                res.append('<a href="%s">%s</a>' % (html.escape(where[1]), body))
            else:
                res.append('<span title="%s">%s</span>'
                           % (html.escape(os.path.normpath('docs/vbasic/' + where[1])), body))
        k = j
    return ''.join(res)


def html_blocks(ch, links):
    out = []
    inl = lambda text: html_inline(parse_inline(text), links, ch.name)
    for k, b in enumerate(ch.blocks):
        kind = b[0]
        if kind == 'h':
            out.append('<h%d id="%s">%s</h%d>' % (b[1], ch.ids[k], inl(b[2]), b[1]))
        elif kind == 'p':
            out.append('<p>%s</p>' % inl(b[1]))
        elif kind == 'anchor':
            out.append('<a id="%s"></a>' % html.escape(b[1]))
        elif kind == 'rule':
            out.append('<hr>')
        elif kind == 'code':
            label = {'keys': 'Keys typed:', 'mouse': 'Mouse script:'}.get(b[1])
            if label:
                out.append('<p class="label">%s</p>' % label)
            out.append('<pre class="%s"><code>%s</code></pre>'
                       % (b[1] or 'plain', html.escape('\n'.join(b[2]), quote=False)))
        elif kind == 'list':
            depth = -1
            tags = []
            for d, num, text in b[1]:
                while depth < d:
                    tag = 'ol' if num is not None else 'ul'
                    out.append('<%s>' % tag)
                    tags.append(tag)
                    depth += 1
                while depth > d:
                    out.append('</li></%s>' % tags.pop())
                    depth -= 1
                if out[-1] not in ('<ul>', '<ol>'):
                    out.append('</li>')
                out.append('<li>%s' % inl(text))
            while tags:
                out.append('</li></%s>' % tags.pop())
        elif kind == 'table':
            out.append('<table>')
            head, rows = b[1], b[2]
            if any(head):
                out.append('<thead><tr>%s</tr></thead>'
                           % ''.join('<th>%s</th>' % inl(c) for c in head))
            out.append('<tbody>')
            for row in rows:
                row = (row + [''] * len(head))[:max(len(head), len(row))]
                out.append('<tr>%s</tr>' % ''.join('<td>%s</td>' % inl(c) for c in row))
            out.append('</tbody></table>')
    return '\n'.join(out)


def html_page(title, nav, body):
    return ('<!DOCTYPE html>\n<html lang="en">\n<head>\n<meta charset="utf-8">\n'
            '<meta name="viewport" content="width=device-width, initial-scale=1">\n'
            '<title>%s</title>\n<style>%s</style>\n</head>\n<body>\n'
            '<nav>%s</nav>\n<main>\n%s\n</main>\n<nav>%s</nav>\n</body>\n</html>\n'
            % (html.escape(title), STYLE, nav, body, nav))


def write_html(outdir, chapters, card, links):
    hdir = os.path.join(outdir, 'html')
    os.makedirs(hdir, exist_ok=True)
    written = []

    def save(name, text):
        path = os.path.join(hdir, name)
        with open(path, 'w', encoding='utf-8', newline='\n') as f:
            f.write(text)
        written.append(path)

    toc = ['<h1>%s</h1>' % TITLE, '<ul class="toc">']
    for ch in chapters:
        toc.append('<li><a href="%s.html">%s</a>' % (ch.name, html.escape(ch.title)))
        if ch.sections and ch.name != 'reference':
            toc.append('<ul>%s</ul>' % ''.join(
                '<li><a href="%s.html#%s">%s</a></li>' % (ch.name, sid, html.escape(t))
                for t, sid in ch.sections))
        toc.append('</li>')
    toc.append('</ul>')
    toc.append('<h2>Also</h2><ul>')
    if card:
        toc.append('<li><a href="refcard.html">%s</a> (and as a two-page '
                   '<a href="../%s">PDF</a>)</li>' % (html.escape(card.title), REFCARD_PDF))
    toc.append('<li>The whole manual as a <a href="../%s">PDF</a></li></ul>' % MANUAL_PDF)
    save('index.html', html_page(TITLE, '<a href="index.html">Contents</a>', '\n'.join(toc)))

    for k, ch in enumerate(chapters):
        nav = ['<a href="index.html">Contents</a>']
        if k > 0:
            nav.append('<a href="%s.html">Previous: %s</a>'
                       % (chapters[k - 1].name, html.escape(chapters[k - 1].title)))
        if k + 1 < len(chapters):
            nav.append('<a href="%s.html">Next: %s</a>'
                       % (chapters[k + 1].name, html.escape(chapters[k + 1].title)))
        save(ch.name + '.html', html_page('%s - %s' % (ch.title, TITLE), ''.join(nav),
                                          html_blocks(ch, links)))
    if card:
        save('refcard.html', html_page(card.title, '<a href="index.html">Contents</a>',
                                       html_blocks(card, links)))
    return written


# -------------------------------------------------------------- PDF fonts

# Glyph widths (1/1000 em) of codes 32-255 in WinAnsiEncoding, from Adobe's
# AFM files; Helvetica-Oblique's are Helvetica's, and Courier's are all 600.
HELVETICA = [
    278, 278, 355, 556, 556, 889, 667, 191, 333, 333, 389, 584, 278, 333, 278, 278,
    556, 556, 556, 556, 556, 556, 556, 556, 556, 556, 278, 278, 584, 584, 584, 556,
    1015, 667, 667, 722, 722, 667, 611, 778, 722, 278, 500, 667, 556, 833, 722, 778,
    667, 778, 722, 667, 611, 722, 667, 944, 667, 667, 611, 278, 278, 278, 469, 556,
    333, 556, 556, 500, 556, 556, 278, 556, 556, 222, 222, 500, 222, 833, 556, 556,
    556, 556, 333, 500, 278, 556, 500, 722, 500, 500, 500, 334, 260, 334, 584, 350,
    556, 350, 222, 556, 333, 1000, 556, 556, 333, 1000, 667, 333, 1000, 350, 611, 350,
    350, 222, 222, 333, 333, 350, 556, 1000, 333, 1000, 500, 333, 944, 350, 500, 667,
    278, 333, 556, 556, 556, 556, 260, 556, 333, 737, 370, 556, 584, 333, 737, 333,
    400, 584, 333, 333, 333, 556, 537, 278, 333, 333, 365, 556, 834, 834, 834, 611,
    667, 667, 667, 667, 667, 667, 1000, 722, 667, 667, 667, 667, 278, 278, 278, 278,
    722, 722, 778, 778, 778, 778, 778, 584, 778, 722, 722, 722, 722, 667, 667, 611,
    556, 556, 556, 556, 556, 556, 889, 500, 556, 556, 556, 556, 278, 278, 278, 278,
    556, 556, 556, 556, 556, 556, 556, 584, 611, 556, 556, 556, 556, 500, 556, 500,
]
HELVETICA_BOLD = [
    278, 333, 474, 556, 556, 889, 722, 238, 333, 333, 389, 584, 278, 333, 278, 278,
    556, 556, 556, 556, 556, 556, 556, 556, 556, 556, 333, 333, 584, 584, 584, 611,
    975, 722, 722, 722, 722, 667, 611, 778, 722, 278, 556, 722, 611, 833, 722, 778,
    667, 778, 722, 667, 611, 722, 667, 944, 667, 667, 611, 333, 278, 333, 584, 556,
    333, 556, 611, 556, 611, 556, 333, 611, 611, 278, 278, 556, 278, 889, 611, 611,
    611, 611, 389, 556, 333, 611, 556, 778, 556, 556, 500, 389, 280, 389, 584, 350,
    556, 350, 278, 556, 500, 1000, 556, 556, 333, 1000, 667, 333, 1000, 350, 611, 350,
    350, 278, 278, 500, 500, 350, 556, 1000, 333, 1000, 556, 333, 944, 350, 500, 667,
    278, 333, 556, 556, 556, 556, 280, 556, 333, 737, 370, 556, 584, 333, 737, 333,
    400, 584, 333, 333, 333, 611, 556, 278, 333, 333, 365, 556, 834, 834, 834, 611,
    722, 722, 722, 722, 722, 722, 1000, 722, 667, 667, 667, 667, 278, 278, 278, 278,
    722, 722, 778, 778, 778, 778, 778, 584, 778, 722, 722, 722, 722, 667, 667, 611,
    556, 556, 556, 556, 556, 556, 889, 556, 556, 556, 556, 556, 278, 278, 278, 278,
    611, 611, 611, 611, 611, 611, 611, 584, 611, 611, 611, 611, 611, 556, 611, 556,
]
COURIER = [600] * 224

# Style key: (resource name, base font, widths).
FONTS = {
    'R': ('F1', 'Helvetica', HELVETICA),
    'B': ('F2', 'Helvetica-Bold', HELVETICA_BOLD),
    'I': ('F3', 'Helvetica-Oblique', HELVETICA),
    'C': ('F4', 'Courier', COURIER),
    'CB': ('F5', 'Courier-Bold', COURIER),
}

# Close ASCII for characters WinAnsi lacks.
FALLBACK = {'\u2192': '->', '\u2190': '<-', '\u2264': '<=', '\u2265': '>=',
            '\u2260': '<>', '\u2212': '-', '\u2713': 'v', '\u2191': '^',
            '\u2193': 'v', '\u00a0': ' ', '\u2009': ' ', '\u2002': ' ',
            '\u2003': ' ', '\u2011': '-', '\u2010': '-'}


def winansi(text):
    """Text to WinAnsiEncoding bytes, else a close ASCII fallback."""
    out = bytearray()
    for c in text:
        if c in FALLBACK:
            out += FALLBACK[c].encode('ascii')
            continue
        try:
            b = c.encode('cp1252')
        except UnicodeEncodeError:
            b = unicodedata.normalize('NFKD', c).encode('ascii', 'ignore') or b'?'
        if b[0] < 32:
            b = b' '
        out += b
    return bytes(out)


def width(text, font, size):
    w = FONTS[font][2]
    return sum(w[b - 32] if b >= 32 else 0 for b in winansi(text)) * size / 1000.0


def pdf_string(data):
    """Bytes as a PDF literal string."""
    out = bytearray(b'(')
    for b in data:
        if b in b'()\\':
            out += b'\\' + bytes([b])
        elif b < 32 or b > 126:
            out += b'\\%03o' % b
        else:
            out.append(b)
    return bytes(out + b')')


def pdf_text_string(text):
    """A text string outside a content stream (bookmarks, info): UTF-16."""
    return b'<FEFF' + text.encode('utf-16-be').hex().upper().encode() + b'>'


def num(x):
    s = '%.2f' % x
    return s.rstrip('0').rstrip('.') if '.' in s else s


# ------------------------------------------------------------- PDF layout

A4 = (595.0, 842.0)
LINK_RGB = (0.04, 0.27, 0.55)    # the colour of a link's text


class Page:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.ops = []
        self.links = []    # (x0, y0, x1, y1, destination name)

    def text(self, x, y, s, font, size, grey=None, rgb=None):
        if not s:
            return
        colour = '%s g ' % num(grey) if grey is not None else ''
        if rgb:
            colour = '%s %s %s rg ' % tuple(num(c) for c in rgb)
        reset = ' 0 g' if colour else ''
        self.ops.append('%sBT /%s %s Tf %s %s Td %s Tj ET%s' % (
            colour, FONTS[font][0], num(size), num(x), num(y),
            pdf_string(winansi(s)).decode('latin-1'), reset))

    def fill(self, x, y, w, h, grey):
        self.ops.append('%s g %s %s %s %s re f 0 g' % (num(grey), num(x), num(y), num(w), num(h)))

    def stroke_rect(self, x, y, w, h, grey=0.6, lw=0.5):
        self.ops.append('%s G %s w %s %s %s %s re S 0 G' % (
            num(grey), num(lw), num(x), num(y), num(w), num(h)))

    def line(self, x0, y0, x1, y1, grey=0.6, lw=0.5):
        self.ops.append('%s G %s w %s %s m %s %s l S 0 G' % (
            num(grey), num(lw), num(x0), num(y0), num(x1), num(y1)))


class Word:
    """A word of a paragraph: segments of text (font, link) with no break
    between them, and the space before it."""
    __slots__ = ('segs', 'w', 'space')

    def __init__(self, space):
        self.segs = []    # [text, font, link, width]
        self.w = 0.0
        self.space = space

    def add(self, text, font, link, size):
        w = width(text, font, size)
        if self.segs and self.segs[-1][1] == font and self.segs[-1][2] == link:
            self.segs[-1][0] += text
            self.segs[-1][3] += w
        else:
            self.segs.append([text, font, link, w])
        self.w += w


def span_font(s):
    if s.code:
        return 'CB' if s.bold else 'C'
    return 'B' if s.bold else ('I' if s.italic else 'R')


def make_words(spans, size, code_scale=0.94, force_bold=False):
    """Spans to Words; a code span keeps its runs of spaces."""
    words = []
    pending = None    # the space before the next word, None: glue on
    for s in spans:
        font = span_font(s)
        if force_bold:
            font = 'CB' if s.code else 'B'
        fsize = size * code_scale if s.code else size
        for tok in re.findall(r'\s+|\S+', s.text):
            if tok.isspace():
                n = len(tok) if s.code else 1
                pending = (pending or 0) + n * width(' ', font, fsize)
                continue
            if pending is not None or not words:
                words.append(Word(pending or 0))
                pending = None
            words[-1].add(tok, font, s.link, fsize)
    return words


def split_word(word, avail, size, code_scale=0.94):
    """A word wider than the line, cut into pieces that fit."""
    pieces = []
    cur = Word(word.space)
    for text, font, link, _ in word.segs:
        fsize = size * code_scale if font in ('C', 'CB') else size
        for c in text:
            cw = width(c, font, fsize)
            if cur.w + cw > avail and cur.segs:
                pieces.append(cur)
                cur = Word(0)
            cur.add(c, font, link, fsize)
    pieces.append(cur)
    return pieces


def break_lines(words, first, rest, size):
    """Greedy line breaking: the first line `first` wide, the others `rest`."""
    lines = [[]]
    used = 0.0
    avail = first
    queue = list(words)
    while queue:
        w = queue.pop(0)
        need = w.w + (w.space if lines[-1] else 0)
        if lines[-1] and used + need > avail:
            lines.append([])
            used = 0.0
            avail = rest
            need = w.w
        if not lines[-1] and w.w > avail:
            pieces = split_word(w, avail, size)
            queue[0:0] = pieces[1:]
            w = pieces[0]
            need = w.w
        lines[-1].append(w)
        used += need
    return lines


class Layout:
    """Flows blocks down the columns of pages: one column for the manual,
    several for the card. Destinations (name -> page, y) and links are
    recorded as it goes."""

    def __init__(self, size, cols, margin_top, margin_bottom, st):
        self.pw, self.ph = size
        self.cols = cols
        self.top = self.ph - margin_top
        self.bottom = margin_bottom
        self.st = st
        self.pages = []
        self.dests = {}
        self.marks = []
        self.outline = []    # (level, title, destination name)
        self.footer_title = {}
        self.new_page()

    # Where we are.
    def new_page(self):
        self.pages.append(Page(self.pw, self.ph))
        self.page = self.pages[-1]
        self.col = 0
        self.y = self.top

    @property
    def x0(self):
        return self.cols[self.col][0]

    @property
    def x1(self):
        return self.cols[self.col][1]

    def next_column(self):
        if self.col + 1 < len(self.cols):
            self.col += 1
            self.y = self.top
        else:
            self.new_page()

    def at_top(self):
        return self.y >= self.top - 0.01

    def ensure(self, h):
        """Room for h points, else the next column; then the marks waiting
        for this place get it."""
        if self.y - h < self.bottom and not self.at_top():
            self.next_column()
        for name in self.marks:
            self.dests[name] = (len(self.pages) - 1, self.y)
        self.marks = []

    def mark(self, name):
        self.marks.append(name)

    def gap(self, h):
        if not self.at_top():
            self.y -= h

    # Paragraph text.
    def draw_line(self, words, x, base, size):
        first = True
        for w in words:
            if not first:
                x += w.space
            first = False
            for text, font, link, sw in w.segs:
                fsize = size * 0.94 if font in ('C', 'CB') else size
                self.page.text(x, base, text, font, fsize, rgb=LINK_RGB if link else None)
                if link:
                    self.page.links.append((x, base - size * 0.25, x + sw, base + size * 0.8, link))
                x += sw

    def paragraph(self, words, size, leading, indent=0.0, hang=0.0, keep=1):
        """Words as lines from x0 + indent (the lines after the first from
        indent + hang). The first `keep` lines stay together."""
        avail = self.x1 - self.x0 - indent
        lines = break_lines(words, avail, avail - hang, size)
        self.ensure(leading * min(keep, len(lines)))
        for k, line in enumerate(lines):
            if k:
                self.ensure(leading)
            self.y -= leading
            self.draw_line(line, self.x0 + indent + (hang if k else 0),
                           self.y + (leading - size) * 0.5 + size * 0.22, size)
        return lines


def link_dest(links, cur):
    """The resolver for the PDF: a link to a page of the manual becomes a
    destination name, anything else no link."""
    def resolve(url):
        where = links.resolve(url, cur)
        if where[0] == 'chapter' and where[1] in links.names:
            return where[1] + ('#' + where[2] if where[2] else '')
        return None
    return resolve


def resolve_spans(spans, resolve):
    for s in spans:
        if s.link:
            s.link = resolve(s.link)
    return spans


def lay_blocks(L, ch, blocks, resolve, heads=True):
    """Lay one chapter's blocks out."""
    st = L.st
    size = st['body']
    lead = st['lead']
    for k, b in enumerate(blocks):
        kind = b[0]
        if kind == 'anchor':
            L.mark('%s#%s' % (ch.name, b[1]))
        elif kind == 'h':
            level = b[1]
            hs = st['h'][min(level, len(st['h'])) - 1]
            spans = resolve_spans(parse_inline(b[2]), resolve)
            L.gap(st['h_gap'][min(level, 3) - 1])
            L.mark('%s#%s' % (ch.name, ch.ids.get(k, '')))
            if level == 1:
                L.mark(ch.name)
            if heads and level <= 2:
                L.outline.append((level, plain_text(b[2]), '%s#%s' % (ch.name, ch.ids[k])))
            words = make_words(spans, hs, force_bold=True)
            avail = L.x1 - L.x0
            n = len(break_lines(words, avail, avail, hs))
            # A heading stays with three lines of what follows.
            L.ensure(n * hs * 1.25 + 3 * lead)
            L.paragraph(words, hs, hs * 1.25)
            if level <= 2 and st.get('rule_under'):
                L.page.line(L.x0, L.y - 2, L.x1, L.y - 2, 0.75, 0.6 if level == 1 else 0.4)
            L.y -= hs * 0.45
        elif kind == 'p':
            spans = resolve_spans(parse_inline(b[1]), resolve)
            L.paragraph(make_words(spans, size), size, lead, keep=2)
            L.y -= st['p_gap']
        elif kind == 'list':
            for depth, number, text in b[1]:
                indent = st['indent'] * (depth + 1)
                spans = resolve_spans(parse_inline(text), resolve)
                L.ensure(lead)
                top = L.y
                mark = '%s.' % number if number is not None else '\u2022'
                L.paragraph(make_words(spans, size), size, lead, indent=indent)
                mw = width(mark, 'R', size)
                L.page.text(L.x0 + indent - mw - size * 0.45,
                            top - lead + (lead - size) * 0.5 + size * 0.22, mark, 'R', size)
                L.y -= st['item_gap']
            L.y -= st['p_gap']
        elif kind == 'code':
            lay_code(L, b[1], b[2])
        elif kind == 'table':
            lay_table(L, b[1], b[2], resolve)
        elif kind == 'rule':
            L.ensure(lead)
            L.y -= lead * 0.5
            L.page.line(L.x0, L.y, L.x1, L.y, 0.7)
            L.y -= lead * 0.5


def lay_code(L, kind, lines):
    """A code block on a grey box, split between columns only between
    lines; a line too long goes on with a marker in the margin."""
    st = L.st
    if kind == 'mouse' and st.get('skip_mouse'):
        return
    size = st['code']
    lead = size * 1.22
    pad = st['code_pad']
    label = {'keys': 'Keys typed:', 'mouse': 'Mouse script:'}.get(kind)
    cw = size * 0.6
    maxch = max(10, int((L.x1 - L.x0 - 2 * pad) / cw))
    rows = []    # (text, whether it goes on from the row before)
    for line in lines:
        line = line.rstrip()
        rows.append((line[:maxch], False))
        line = line[maxch:]
        while line:
            rows.append((line[:maxch], True))
            line = line[maxch:]
    if not rows:
        return
    if label:
        L.ensure(st['small'] * 1.3 + lead * min(3, len(rows)) + 2 * pad)
        L.y -= st['small'] * 1.3
        L.page.text(L.x0, L.y + 2, label, 'I', st['small'], 0.35)
    k = 0
    while k < len(rows):
        L.ensure(lead * min(3, len(rows) - k) + 2 * pad)
        room = int((L.y - L.bottom - 2 * pad) / lead)
        n = max(1, min(room, len(rows) - k))
        # Do not leave a single line behind.
        if 0 < len(rows) - k - n < 2 and n > 2:
            n -= 1
        h = n * lead + 2 * pad
        L.page.fill(L.x0, L.y - h, L.x1 - L.x0, h, 0.93)
        y = L.y - pad
        for text, cont in rows[k:k + n]:
            y -= lead
            if cont:
                L.page.text(L.x0 + 0.5, y + lead * 0.22, '\u00bb', 'C', size * 0.75, 0.5)
            L.page.text(L.x0 + pad, y + lead * 0.22, text, 'C', size)
        L.y -= h
        k += n
        if k < len(rows):
            L.next_column()
    L.y -= st['p_gap'] + 2


def lay_table(L, head, rows, resolve, size=None):
    """A grid with column widths from its content; a wide one in smaller
    type; the header row again at the top of a new column."""
    st = L.st
    ncol = max([len(head)] + [len(r) for r in rows])
    head = head + [''] * (ncol - len(head))
    rows = [r + [''] * (ncol - len(r)) for r in rows]
    has_head = any(head)
    avail = L.x1 - L.x0
    pad = st['cell_pad']

    def cells_at(sz):
        grid = []
        for r, row in enumerate(([head] if has_head else []) + rows):
            bold = has_head and r == 0
            grid.append([make_words(resolve_spans(parse_inline(c), resolve), sz,
                                    force_bold=bold) for c in row])
        return grid

    def widths_of(grid):
        nat = [0.0] * ncol
        mn = [0.0] * ncol
        for row in grid:
            for c, words in enumerate(row):
                total = sum(w.w for w in words) + sum(w.space for w in words[1:])
                nat[c] = max(nat[c], total)
                mn[c] = max([mn[c]] + [w.w for w in words])
        return nat, mn

    size = size or st['table']
    grid = cells_at(size)
    nat, mn = widths_of(grid)
    if sum(nat) + 2 * pad * ncol > avail and size > st['table_small']:
        size = st['table_small']
        grid = cells_at(size)
        nat, mn = widths_of(grid)
    nat = [n + 2 * pad + 0.5 for n in nat]
    mn = [min(m + 2 * pad + 0.5, avail / ncol * 1.6) for m in mn]
    if sum(nat) <= avail:
        cw = nat
    elif sum(mn) >= avail:
        cw = [m * avail / sum(mn) for m in mn]
    else:
        flex = [n - m for n, m in zip(nat, mn)]
        extra = avail - sum(mn)
        cw = [m + extra * f / sum(flex) for m, f in zip(mn, flex)]
    lead = size * 1.25

    laid = []
    for row in grid:
        cells = [break_lines(words, cw[c] - 2 * pad, cw[c] - 2 * pad, size) if words else []
                 for c, words in enumerate(row)]
        laid.append((cells, max(1, max(len(x) for x in cells)) * lead + 2 * pad - lead * 0.15))

    def draw_row(cells, h, shade):
        L.ensure(h)
        top = L.y
        x = L.x0
        if shade:
            L.page.fill(x, top - h, sum(cw), h, 0.9)
        for c, lines in enumerate(cells):
            y = top - pad
            for line in lines:
                y -= lead
                L.draw_line(line, x + pad, y + lead * 0.25, size)
            L.page.stroke_rect(x, top - h, cw[c], h, 0.55, 0.4)
            x += cw[c]
        L.y -= h

    L.ensure(laid[0][1] + (laid[1][1] if has_head and len(laid) > 1 else 0))
    for r, (cells, h) in enumerate(laid):
        if r and L.y - h < L.bottom and not L.at_top():
            L.next_column()
            if has_head:
                draw_row(laid[0][0], laid[0][1], True)
        draw_row(cells, h, has_head and r == 0)
    L.y -= st['p_gap'] + 3


# ------------------------------------------------------- the PDF itself

def write_pdf(path, pages, dests, outline, title):
    """Pages to a PDF 1.4 file: the base-14 fonts, Flate content streams,
    links and bookmarks to destinations."""
    objs = []

    def alloc():
        objs.append(None)
        return len(objs)

    catalog = alloc()
    pages_id = alloc()
    info = alloc()
    font_ids = {}
    for key, (res, base, _) in FONTS.items():
        fid = alloc()
        font_ids[res] = fid
        objs[fid - 1] = ('<< /Type /Font /Subtype /Type1 /BaseFont /%s '
                         '/Encoding /WinAnsiEncoding >>' % base).encode()
    page_ids = [alloc() for _ in pages]
    content_ids = [alloc() for _ in pages]
    fonts = ' '.join('/%s %d 0 R' % (r, i) for r, i in font_ids.items())

    def dest(name):
        if name not in dests:
            return None
        p, y = dests[name]
        return '[%d 0 R /XYZ 0 %s 0]' % (page_ids[p], num(min(y + 6, pages[p].h)))

    for k, pg in enumerate(pages):
        annots = []
        for x0, y0, x1, y1, name in pg.links:
            d = dest(name)
            if d:
                annots.append('<< /Type /Annot /Subtype /Link /Rect [%s %s %s %s] '
                              '/Border [0 0 0] /Dest %s >>' % (num(x0), num(y0), num(x1), num(y1), d))
        objs[page_ids[k] - 1] = (
            '<< /Type /Page /Parent %d 0 R /MediaBox [0 0 %s %s] '
            '/Resources << /Font << %s >> >> /Contents %d 0 R%s >>'
            % (pages_id, num(pg.w), num(pg.h), fonts, content_ids[k],
               ' /Annots [%s]' % ' '.join(annots) if annots else '')).encode()
        data = zlib.compress('\n'.join(pg.ops).encode('latin-1'), 9)
        objs[content_ids[k] - 1] = (b'<< /Length %d /Filter /FlateDecode >>\nstream\n'
                                    % len(data) + data + b'\nendstream')
    objs[pages_id - 1] = ('<< /Type /Pages /Kids [%s] /Count %d >>' % (
        ' '.join('%d 0 R' % i for i in page_ids), len(pages))).encode()

    # Bookmarks: level 1 items with their level 2 children.
    outline = [o for o in outline if o[2] in dests]
    tops = []
    for level, text, name in outline:
        if level == 1 or not tops:
            tops.append([alloc(), text, name, []])
        else:
            tops[-1][3].append([alloc(), text, name, []])
    root = None
    if tops:
        root = alloc()

        def chain(items, parent):
            for k, (oid, text, name, kids) in enumerate(items):
                d = ['/Title %s' % pdf_text_string(text).decode(), '/Parent %d 0 R' % parent,
                     '/Dest %s' % dest(name)]
                if k:
                    d.append('/Prev %d 0 R' % items[k - 1][0])
                if k + 1 < len(items):
                    d.append('/Next %d 0 R' % items[k + 1][0])
                if kids:
                    d.append('/First %d 0 R /Last %d 0 R /Count -%d'
                             % (kids[0][0], kids[-1][0], len(kids)))
                    chain(kids, oid)
                objs[oid - 1] = ('<< %s >>' % ' '.join(d)).encode()
        chain(tops, root)
        objs[root - 1] = ('<< /Type /Outlines /First %d 0 R /Last %d 0 R /Count %d >>'
                          % (tops[0][0], tops[-1][0], len(tops))).encode()
    objs[catalog - 1] = ('<< /Type /Catalog /Pages %d 0 R%s >>' % (
        pages_id, ' /Outlines %d 0 R /PageMode /UseOutlines' % root if root else '')).encode()
    objs[info - 1] = ('<< /Title %s /Producer (tools/vbmanual.py) >>'
                      % pdf_text_string(title).decode()).encode()

    out = bytearray(b'%PDF-1.4\n%\xe2\xe3\xcf\xd3\n')
    offsets = []
    for k, body in enumerate(objs):
        offsets.append(len(out))
        out += b'%d 0 obj\n' % (k + 1) + body + b'\nendobj\n'
    xref = len(out)
    out += b'xref\n0 %d\n0000000000 65535 f \n' % (len(objs) + 1)
    for off in offsets:
        out += b'%010d 00000 n \n' % off
    out += (b'trailer\n<< /Size %d /Root %d 0 R /Info %d 0 R >>\nstartxref\n%d\n%%%%EOF\n'
            % (len(objs) + 1, catalog, info, xref))
    with open(path, 'wb') as f:
        f.write(out)


# --------------------------------------------------------- the manual PDF

MARGIN = 56.0
MANUAL_STYLE = {
    'body': 10.0, 'lead': 13.6, 'small': 8.0,
    'h': [20.0, 14.0, 11.5, 10.5], 'h_gap': [0.0, 12.0, 8.0],
    'p_gap': 5.0, 'item_gap': 1.5, 'indent': 16.0,
    'code': 8.6, 'code_pad': 6.0,
    'table': 9.0, 'table_small': 8.0, 'cell_pad': 3.5,
    'rule_under': True,
}


def footer(L, first, titles):
    """Page numbers (and the chapter's title) at the foot of each page."""
    for k, pg in enumerate(L.pages):
        if k < first:
            continue
        s = str(k + 1)
        pg.text((pg.w - width(s, 'R', 9)) / 2, 30, s, 'R', 9, 0.3)
        t = titles.get(k)
        if t:
            pg.text(MARGIN, 30, t, 'I', 8, 0.45)


def toc_entries(chapters):
    out = []
    for ch in chapters:
        out.append((1, ch.title, ch.name))
        if ch.name != 'reference':
            for t, sid in ch.sections:
                out.append((2, t, '%s#%s' % (ch.name, sid)))
        else:
            # The reference's groups, by their own anchors.
            for k, b in enumerate(ch.blocks):
                if b[0] == 'h' and b[1] == 2:
                    out.append((2, plain_text(b[2]), '%s#%s' % (ch.name, ch.ids[k])))
    return out


def manual_layout(chapters, links, page_of):
    L = Layout(A4, [(MARGIN, A4[0] - MARGIN)], MARGIN, MARGIN + 10, MANUAL_STYLE)
    # The title page.
    pg = L.page
    t = TITLE
    pg.text((A4[0] - width(t, 'B', 30)) / 2, 560, t, 'B', 30)
    sub = 'VeraBASIC for Veranda on the Commander X16'
    pg.text((A4[0] - width(sub, 'R', 13)) / 2, 525, sub, 'R', 13, 0.3)
    pg.line(MARGIN + 60, 505, A4[0] - MARGIN - 60, 505, 0.6, 0.8)
    note = 'Generated by tools/vbmanual.py from docs/vbasic/manual.'
    pg.text((A4[0] - width(note, 'I', 9)) / 2, 90, note, 'I', 9, 0.45)

    # The contents.
    L.new_page()
    toc_first = len(L.pages) - 1
    L.y -= 20
    L.page.text(L.x0, L.y, 'Contents', 'B', 20)
    L.dests['contents'] = (toc_first, L.top)
    L.y -= 18
    for level, text, name in toc_entries(chapters):
        size = 11.0 if level == 1 else 9.5
        lead = 19.0 if level == 1 else 12.6
        font = 'B' if level == 1 else 'R'
        L.ensure(lead + (12.6 if level == 1 else 0))
        L.y -= lead
        x = L.x0 + (0 if level == 1 else 16)
        n = str(page_of[name] + 1) if name in page_of else ''
        nw = width(n, font, size)
        room = L.x1 - x - nw - 20
        while width(text, font, size) > room and len(text) > 4:
            text = text[:-4].rstrip() + '...'
        L.page.text(x, L.y, text, font, size)
        tw = width(text, font, size)
        L.page.text(L.x1 - nw, L.y, n, font, size)
        # Dotted leaders between the title and the number.
        dot = width(' .', 'R', size)
        d0 = x + tw + 6
        ndots = int((L.x1 - nw - 6 - d0) / dot)
        if ndots > 0:
            L.page.text(L.x1 - nw - 6 - ndots * dot, L.y, ' .' * ndots, 'R', size, 0.55)
        L.page.links.append((x, L.y - 3, L.x1, L.y + size, name))

    titles = {}
    for ch in chapters:
        L.new_page()
        start = len(L.pages) - 1
        resolve = link_dest(links, ch.name)
        lay_blocks(L, ch, ch.blocks, resolve)
        for p in range(start, len(L.pages)):
            titles[p] = ch.title
    footer(L, 1, titles)
    return L


def write_manual(path, chapters, links):
    # Twice: the first to learn the pages the contents give.
    page_of = {}
    for _ in range(3):
        L = manual_layout(chapters, links, page_of)
        new = {name: p for name, (p, _) in L.dests.items()}
        if new == page_of:
            break
        page_of = new
    write_pdf(path, L.pages, L.dests, L.outline, TITLE)
    return len(L.pages)


# ------------------------------------------------------ the reference card

CARD_SIZE = (842.0, 595.0)    # A4 landscape
CARD_COLS = 4
CARD_MARGIN = 24.0
CARD_GUTTER = 12.0


def card_style(s):
    return {
        'body': s, 'lead': s * 1.18, 'small': s * 0.9,
        'h': [s * 1.9, s * 1.2, s * 1.05, s], 'h_gap': [0.0, s * 0.6, s * 0.4],
        'p_gap': s * 0.35, 'item_gap': 0.0, 'indent': s * 1.4,
        'code': s * 0.92, 'code_pad': s * 0.5,
        'table': s, 'table_small': s, 'cell_pad': s * 0.3,
        'skip_mouse': True,
    }


def lay_card_entries(L, rows):
    """A two-column table of the card as entries: the syntax, then what it
    does, its lines after the first indented."""
    st = L.st
    s = st['body']
    for row in rows:
        row = row + ['', '']
        first = parse_inline(row[0])
        for sp in first:
            if not sp.code:
                sp.bold = True
        words = make_words(first, s)
        rest = make_words(parse_inline(row[1]), s)
        if rest and words:
            rest[0].space = s * 0.8
        L.paragraph(words + rest, s, st['lead'], hang=s * 1.2)
        L.y -= s * 0.12


def card_layout(card, s):
    w, h = CARD_SIZE
    colw = (w - 2 * CARD_MARGIN - (CARD_COLS - 1) * CARD_GUTTER) / CARD_COLS
    cols = [(CARD_MARGIN + k * (colw + CARD_GUTTER),
             CARD_MARGIN + k * (colw + CARD_GUTTER) + colw) for k in range(CARD_COLS)]
    L = Layout(CARD_SIZE, cols, CARD_MARGIN, CARD_MARGIN + 6, card_style(s))
    resolve = lambda url: None
    for k, b in enumerate(card.blocks):
        if b[0] == 'table' and len(b[1]) == 2 and not any(b[1]):
            lay_card_entries(L, b[2])
            L.y -= L.st['p_gap']
        else:
            lay_blocks(L, card, [b], resolve, heads=False)
    return L


def write_card(path, card):
    size = 7.5
    while True:
        L = card_layout(card, size)
        if len(L.pages) <= 2 or size <= 5.0:
            break
        size = round(size - 0.1, 2)
    while len(L.pages) < 2:
        L.new_page()
    for k, pg in enumerate(L.pages):
        s = '%s, page %d of %d' % (card.title, k + 1, len(L.pages))
        pg.text(pg.w - CARD_MARGIN - width(s, 'I', 6), 14, s, 'I', 6, 0.45)
    write_pdf(path, L.pages, L.dests, [], card.title)
    return len(L.pages), size


# ------------------------------------------------------------- building

def find_chapter(name):
    if os.path.exists(name):
        return name
    path = os.path.join(MANUAL_DIR, name)
    return path if os.path.exists(path) else None


def build(outdir, chapters=None, refcard_md=None):
    """Write the HTML pages and the two PDFs; return the files written."""
    chapters = chapters or CHAPTERS
    found = []
    for name in chapters:
        path = find_chapter(name)
        if path:
            found.append(Chapter(path))
        else:
            print('vbmanual: warning: no chapter %s, skipped' % name, file=sys.stderr)
    if not found:
        raise SystemExit('vbmanual: no chapters')
    card_path = find_chapter(refcard_md or REFCARD)
    card = Chapter(card_path) if card_path else None
    if not card:
        print('vbmanual: warning: no reference card %s' % (refcard_md or REFCARD),
              file=sys.stderr)
    os.makedirs(outdir, exist_ok=True)
    links = Links([c.name for c in found], card.name if card else None)

    written = write_html(outdir, found, card, links)
    path = os.path.join(outdir, MANUAL_PDF)
    pages = write_manual(path, found, links)
    written.append(path)
    print('vbmanual: %d chapters, %s: %d pages' % (len(found), MANUAL_PDF, pages))
    if card:
        path = os.path.join(outdir, REFCARD_PDF)
        pages, size = write_card(path, card)
        written.append(path)
        print('vbmanual: %s: %d pages at %.1f pt' % (REFCARD_PDF, pages, size))
    return written


# ------------------------------------------------------------- checking

def check_pdf(path):
    """Problems with a PDF's structure: the xref's offsets must each point
    at their object. Returns (problems, page count)."""
    problems = []
    with open(path, 'rb') as f:
        data = f.read()
    name = os.path.basename(path)
    if not data.startswith(b'%PDF-'):
        return ['%s: no %%PDF header' % name], 0
    m = re.search(rb'startxref\s+(\d+)\s+%%EOF\s*$', data)
    if not m:
        return ['%s: no startxref' % name], 0
    xref = int(m.group(1))
    if data[xref:xref + 4] != b'xref':
        return ['%s: startxref does not point at the xref' % name], 0
    m = re.compile(rb'xref\s+(\d+) (\d+)\s+').match(data, xref)
    first, count = int(m.group(1)), int(m.group(2))
    pos = m.end()
    for k in range(count):
        entry = data[pos + 20 * k:pos + 20 * k + 20]
        if len(entry) != 20 or not re.match(rb'\d{10} \d{5} [nf][ \r][\n\r]', entry):
            problems.append('%s: bad xref entry %d' % (name, first + k))
            break
        if entry[17:18] == b'n':
            off = int(entry[:10])
            if not data.startswith(b'%d 0 obj' % (first + k), off):
                problems.append('%s: object %d not at offset %d' % (name, first + k, off))
    trailer = data[pos + 20 * count:]
    m = re.search(rb'/Size (\d+)', trailer)
    if not m or int(m.group(1)) != first + count:
        problems.append('%s: trailer /Size is not %d' % (name, first + count))
    # Every stream's /Length must reach its endstream.
    for m in re.finditer(rb'/Length (\d+)[^>]*>>\nstream\n', data):
        end = m.end() + int(m.group(1))
        if data[end:end + 10] != b'\nendstream':
            problems.append('%s: a stream at %d has a wrong /Length' % (name, m.start()))
    pages = len(re.findall(rb'/Type /Page\b(?!s)', data))
    if shutil.which('qpdf'):
        r = subprocess.run(['qpdf', '--check', path], capture_output=True, text=True)
        if r.returncode != 0:
            problems.append('%s: qpdf --check: %s' % (name, (r.stdout + r.stderr).strip()[-300:]))
    if shutil.which('pdftotext'):
        r = subprocess.run(['pdftotext', '-q', path, '-'], capture_output=True)
        if r.returncode != 0 or b'VeraBASIC' not in r.stdout:
            problems.append('%s: pdftotext finds no text' % name)
    return problems, pages


def check(outdir):
    """Re-read what build() wrote; return the problems found."""
    problems = []
    for name in (MANUAL_PDF, REFCARD_PDF):
        path = os.path.join(outdir, name)
        if not os.path.exists(path):
            problems.append('%s: missing' % name)
            continue
        p, pages = check_pdf(path)
        problems += p
        if name == REFCARD_PDF and pages != 2:
            problems.append('%s: %d pages, not 2' % (name, pages))
    # The HTML pages' links must reach a page and an id that exist.
    hdir = os.path.join(outdir, 'html')
    ids = {}
    hrefs = []
    for name in sorted(os.listdir(hdir)) if os.path.isdir(hdir) else []:
        if name.endswith('.html'):
            with open(os.path.join(hdir, name), encoding='utf-8') as f:
                text = f.read()
            ids[name] = set(re.findall(r'\sid="([^"]*)"', text))
            hrefs += [(name, h) for h in re.findall(r'href="([^"]*)"', text)]
    for page, href in hrefs:
        if re.match(r'[a-z]+:', href) or href.startswith('../'):
            continue
        target, _, anchor = html.unescape(href).partition('#')
        target = target or page
        if target not in ids:
            problems.append('html/%s: link to missing %s' % (page, target))
        elif anchor and anchor not in ids[target]:
            problems.append('html/%s: link to missing %s#%s' % (page, target, anchor))
    return problems


def main(argv):
    ap = argparse.ArgumentParser(description='The VeraBASIC manual as HTML and PDF.')
    ap.add_argument('outdir')
    ap.add_argument('--chapters', nargs='+', help='the chapters, in order')
    ap.add_argument('--refcard', help='the reference card (default: refcard.md)')
    ap.add_argument('--check', action='store_true', help='check what was written')
    args = ap.parse_args(argv)
    build(args.outdir, args.chapters, args.refcard)
    if args.check:
        problems = check(args.outdir)
        for p in problems:
            print('vbmanual: %s' % p, file=sys.stderr)
        if problems:
            return 1
        print('vbmanual: check passed%s' % (
            '' if shutil.which('qpdf') or shutil.which('pdftotext')
            else ' (structure only: no qpdf or pdftotext here)'))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
