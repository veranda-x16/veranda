#!/usr/bin/env python3
"""The Veranda website (DECISIONS V139): https://veranda-x16.github.io

    tools/site/build.py [--out DIR] [--repo OWNER/REPO] [--api]
                        [--changes CHANGES.txt] [--manual DIR]

Writes plain HTML and one CSS file (no JavaScript) into DIR (default
build/site):

    index.html          what Veranda is, the desktop, the main programs with
                        their screenshots, the download (the newest release),
                        how to install it on the SD card
    releases.html       every release and its notes
    manual/*.html       the manual (docs/manual) rendered into the site, with
                        its contents at the side; the wiki has the same pages
    about.html          about, the licences and the credits
    style.css, img/     the Sunroom look's palette, light and dark

The releases: --api reads GitHub's releases API (read only; GH_TOKEN, if
set, raises the rate limit); else (or when the API has none) the
package's CHANGES.txt (--changes), else docs/releases. Every screenshot is
a real one: the gates' (docs/manual/img), the programs' own gates, and
Paint's picture drawn by Paint itself in the emulator (tools/site/shots.sh,
tools/site/paint_picture.py). The site says what the programs do, not
where they were tested.

Standard library only. MIT licence (see LICENSE)."""
import argparse
import datetime
import html
import json
import os
import re
import shutil
import sys
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
TOP = os.path.dirname(os.path.dirname(HERE))
ORG = 'veranda-x16'

# ------------------------------------------------------------------ Markdown
# The subset docs/manual uses: ATX headings, paragraphs, lists (nested by
# indent, ordered and not), tables, code blocks (indented or fenced), block
# quotes, images, links, **bold**, *italic*, `code`.


def slug(text):
    s = re.sub(r'<[^>]+>', '', text).strip().lower()
    s = re.sub(r'[^\w\- ]', '', s)
    return s.replace(' ', '-')


class Md:
    def __init__(self, link=None, img=None):
        self.link = link or (lambda t: t)       # a link's target, rewritten
        self.img = img or (lambda t: t)
        self.toc = []

    def inline(self, s):
        out, i = [], 0
        codes = []

        def keep(m):
            codes.append('<code>%s</code>' % html.escape(m.group(1)))
            return '\0%d\0' % (len(codes) - 1)
        s = re.sub(r'`([^`]+)`', keep, s)
        s = html.escape(s, quote=False)

        def image(m):
            return '<img src="%s" alt="%s" loading="lazy">' % (html.escape(self.img(m.group(2))), m.group(1))

        def link(m):
            return '<a href="%s">%s</a>' % (html.escape(self.link(m.group(2))), m.group(1))
        s = re.sub(r'!\[([^\]]*)\]\(([^)\s]+)\)', image, s)
        s = re.sub(r'\[([^\]]+)\]\(([^)\s]+)\)', link, s)
        s = re.sub(r'(?<![\w"=])(https?://[^\s<)]+[^\s<).,;:])', r'<a href="\1">\1</a>', s)
        s = re.sub(r'\*\*(.+?)\*\*', r'<strong>\1</strong>', s)
        s = re.sub(r'(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])', r'<em>\1</em>', s)
        s = re.sub(r'(?<![\w])_(?!\s)(.+?)(?<!\s)_(?![\w])', r'<em>\1</em>', s)
        s = re.sub(r'\0(\d+)\0', lambda m: codes[int(m.group(1))], s)
        out.append(s)
        return ''.join(out)

    def render(self, text):
        lines = text.replace('\t', '    ').split('\n')
        return self.blocks(lines)

    def blocks(self, lines):
        out = []
        i, n = 0, len(lines)
        while i < n:
            l = lines[i]
            if not l.strip():
                i += 1
                continue
            m = re.match(r'^(#{1,6})\s+(.*?)\s*#*$', l)
            if m:
                lvl, t = len(m.group(1)), self.inline(m.group(2))
                sid = slug(t)
                if lvl == 2:
                    self.toc.append((sid, t))
                out.append('<h%d id="%s">%s</h%d>' % (lvl, sid, t, lvl))
                i += 1
                continue
            if l.startswith('```'):
                j = i + 1
                while j < n and not lines[j].startswith('```'):
                    j += 1
                out.append('<pre><code>%s</code></pre>' % html.escape('\n'.join(lines[i + 1:j])))
                i = j + 1
                continue
            if l.startswith('    '):
                j = i
                while j < n and (lines[j].startswith('    ') or not lines[j].strip()):
                    j += 1
                while j > i and not lines[j - 1].strip():
                    j -= 1
                out.append('<pre><code>%s</code></pre>' % html.escape('\n'.join(x[4:] for x in lines[i:j])))
                i = j
                continue
            if l.startswith('|') and i + 1 < n and re.match(r'^\|[\s:|-]+\|\s*$', lines[i + 1]):
                head = self.cells(l)
                j = i + 2
                rows = []
                while j < n and lines[j].startswith('|'):
                    rows.append(self.cells(lines[j]))
                    j += 1
                t = ['<div class="table"><table><thead><tr>']
                t += ['<th>%s</th>' % self.inline(c) for c in head]
                t.append('</tr></thead><tbody>')
                for r in rows:
                    t.append('<tr>' + ''.join('<td>%s</td>' % self.inline(c) for c in r) + '</tr>')
                t.append('</tbody></table></div>')
                out.append(''.join(t))
                i = j
                continue
            if l.startswith('>'):
                j = i
                while j < n and lines[j].startswith('>'):
                    j += 1
                out.append('<blockquote>%s</blockquote>' % self.blocks([x[1:].lstrip() for x in lines[i:j]]))
                i = j
                continue
            if re.match(r'^\s*([-*+]|\d+\.)\s+', l):
                i = self.list_(lines, i, out)
                continue
            j = i
            para = []
            while j < n and lines[j].strip() and not re.match(r'^(#{1,6}\s|```|\||>|\s*([-*+]|\d+\.)\s+)', lines[j]):
                para.append(lines[j].strip())
                j += 1
            if not para:            # (a line nothing else takes)
                para, j = [l.strip()], i + 1
            body = self.inline(' '.join(para))
            if re.fullmatch(r'<img [^>]+>', body):
                out.append('<figure>%s</figure>' % body)
            else:
                out.append('<p>%s</p>' % body)
            i = j
        return '\n'.join(out)

    @staticmethod
    def cells(l):
        l = l.strip()
        if l.startswith('|'):
            l = l[1:]
        if l.endswith('|'):
            l = l[:-1]
        return [c.strip() for c in re.split(r'(?<!\\)\|', l)]

    def list_(self, lines, i, out):
        n = len(lines)
        m = re.match(r'^(\s*)([-*+]|\d+\.)\s+', lines[i])
        base = len(m.group(1))
        tag = 'ol' if m.group(2)[0].isdigit() else 'ul'
        items = []
        while i < n:
            l = lines[i]
            m = re.match(r'^(\s*)([-*+]|\d+\.)\s+(.*)$', l)
            if m and len(m.group(1)) == base:
                items.append([m.group(3)])
                cont = len(m.group(1)) + len(m.group(2)) + 1
                i += 1
                continue
            if not l.strip():
                # a blank line: the list goes on if the next line is indented or another item
                k = i + 1
                if k < n and (lines[k].startswith(' ' * (base + 2)) or
                              re.match(r'^\s{%d}([-*+]|\d+\.)\s+' % base, lines[k])):
                    items[-1].append('')
                    i += 1
                    continue
                break
            ind = len(l) - len(l.lstrip())
            if ind > base:
                items[-1].append(l[min(ind, cont):] if ind >= cont else l.lstrip())
                i += 1
                continue
            break
        out.append('<%s>' % tag)
        for it in items:
            sub = any(re.match(r'^\s*([-*+]|\d+\.)\s+', x) for x in it[1:]) or '' in it or \
                any(x.startswith('    ') for x in it[1:])
            if sub:
                first, rest = [it[0]], it[1:]
                while rest and rest[0].strip() and not re.match(r'^\s*([-*+]|\d+\.)\s+', rest[0]) \
                        and not rest[0].startswith('    '):
                    first.append(rest.pop(0).strip())
                out.append('<li>%s%s</li>' % (self.inline(' '.join(first)), self.blocks(rest)))
            else:
                out.append('<li>%s</li>' % self.inline(' '.join(x.strip() for x in it)))
        out.append('</%s>' % tag)
        return i


# ------------------------------------------------------------------ the releases
def api_releases(repo):
    url = 'https://api.github.com/repos/%s/releases?per_page=100' % repo
    req = urllib.request.Request(url, headers={'Accept': 'application/vnd.github+json',
                                               'User-Agent': 'veranda-site-builder'})
    tok = os.environ.get('GH_TOKEN') or os.environ.get('GITHUB_TOKEN')
    if tok:
        req.add_header('Authorization', 'Bearer ' + tok)
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            data = json.load(r)
    except Exception as e:      # noqa: BLE001 (the site is built without them)
        print('site: the releases API: %s (the site is built without it)' % e, file=sys.stderr)
        return None
    out = []
    for d in data:
        if d.get('draft'):
            continue
        zipa = [a for a in d.get('assets', []) if a['name'].endswith('-sdcard.zip')]
        out.append({
            'tag': d['tag_name'], 'name': d.get('name') or d['tag_name'],
            'date': (d.get('published_at') or '')[:10], 'pre': d.get('prerelease', False),
            'url': d.get('html_url'), 'body': d.get('body') or '',
            'zip': zipa[0]['browser_download_url'] if zipa else None,
            'zipsize': zipa[0]['size'] if zipa else 0,
        })
    return out


def changes_releases(path):
    """CHANGES.txt (tools/relnotes.py): 'VERSION (DATE, build H; since ...)' sections,
    'BUILD h (since ...)' ones, '  - ' points"""
    out, cur = [], None
    for l in open(path, encoding='latin-1'):
        l = l.rstrip('\n')
        m = re.match(r'^(\d+\.\d+(?:\.\d+)?\S*) \((\d{4}-\d\d-\d\d), build ([0-9a-f]+)', l)
        m2 = re.match(r'^(BUILD|EARLIER|BEFORE THAT|ALSO [A-Z ]+?) ?([0-9a-f]{7})? ?\(since ([0-9a-f]+)\)', l)
        if m:
            cur = {'tag': 'v' + m.group(1), 'name': 'Veranda ' + m.group(1), 'date': m.group(2), 'pre': False,
                   'url': None, 'points': [], 'zip': None, 'build': m.group(3)}
            out.append(cur)
        elif m2:
            what = 'build %s' % m2.group(2) if m2.group(2) else 'the builds after %s' % m2.group(3)
            cur = {'tag': None, 'name': 'Before the versions: %s' % what, 'date': '', 'pre': True, 'url': None,
                   'points': [], 'zip': None}
            out.append(cur)
        elif cur is not None and re.match(r'^\s+- ', l):
            cur['points'].append(l.strip()[2:])
        elif cur is not None and cur['points'] and l.startswith('    ') and l.strip():
            cur['points'][-1] += ' ' + l.strip()
    return out


# ------------------------------------------------------------------ the pages
NAV = [('index.html', 'Home'), ('releases.html', 'Releases'), ('manual/index.html', 'Manual'), ('about.html', 'About')]


def page(title, body, here, depth=0, desc=''):
    up = '../' * depth
    nav = ''.join('<a href="%s%s"%s>%s</a>' % (up, h, ' aria-current="page"' if h == here else '', t) for h, t in NAV)
    return '''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>%s</title>
<meta name="description" content="%s">
<link rel="stylesheet" href="%sstyle.css">
<link rel="icon" href="%simg/icon.png">
</head>
<body>
<header class="bar">
  <a class="brand" href="%sindex.html"><img src="%simg/icon.png" alt="" width="20" height="20"> Veranda</a>
  <nav>%s</nav>
</header>
%s
<footer>
  <p>Veranda is free software under the MIT licence, Copyright &copy; 2026 Marcin Spoczynski.
  Source: <a href="https://github.com/%s">github.com/%s</a>. Not affiliated with the Commander X16 project.</p>
</footer>
</body>
</html>
''' % (html.escape(title), html.escape(desc), up, up, up, up, nav, body, ORG, ORG)


FEATURES = [
    # (title, picture, manual page, text)
    ('Veranda Write', 'img/veranda-write.png', 'Veranda-Write',
     'A word processor: fonts and sizes, paragraph styles, pages with headers and footers, tables, templates, '
     'spelling in English and Polish, export as PDF, and Word (.DOCX) and OpenDocument (.ODT) files; optional AI help '
     'through Veranda Ask.'),
    ('Veranda Calc', 'img/calc.png', 'Veranda-Calc',
     'A spreadsheet: 16 worksheets, formulas, bar, line and pie charts; it reads and writes Excel (.XLSX) and CSV '
     'files and reads LibreOffice (.ODS) files.'),
    ('Gemini, web pages and Wikipedia', 'manual/img/gemini-wiki.png', 'Veranda-Gemini',
     'A browser for Gemini capsules; web pages as text through a proxy, PNG pictures, and Wikipedia.'),
    ('Claude and Ask', 'manual/img/claude.png', 'Veranda-Claude',
     'Chat with Anthropic\'s Claude (or your own Claude Code on a PC) and with OpenAI\'s models '
     '(Veranda Ask), through the Wi-Fi modem.'),
    ('Paint', 'img/paint.png', 'Paint',
     'Pictures of 592 x 464 with colour by 8 x 8 blocks: the drawing tools, 24 patterns, text in the fonts of '
     '/VERANDA/FONTS, cut and paste, export to BMP and print to PDF.'),
    ('Colour Paint', 'manual/img/cpaint.png', 'Colour-Paint',
     'Pictures of 320 x 240 in 256 colours: pencil, brush, spray, lines, shapes, fill, text, cut and paste, '
     'a palette editor; it opens Paint pictures and exports pictures for Paint.'),
    ('Desktop pictures', 'manual/img/wallpapers.png', 'The-desktop',
     'Four pictures for the desktop: Still Water, Low Hills, Sunroom Tiles and Dusk; Still Water and Low Hills '
     'turn to night in dark mode. Or a plain colour, or a pattern. Choose one in Preferences.'),
    ('VeraBASIC', 'img/verabasic.png', 'VeraBASIC',
     'A structured BASIC with Veranda\'s windows, menus, dialog boxes, graphics and sound. The editor colours '
     'the program and gives help on any keyword with F1; a debugger with breakpoints; File > Make application '
     'turns a program into a program of its own on the desktop.'),
    ('Bird Watch, made with VeraBASIC', 'img/birdwatch.png', 'VeraBASIC',
     'The tutorial\'s example, made into an application with File > Make application: its own window, menus '
     'and icon.'),
    ('Music and video', [('manual/img/modplayer.png', 'MOD-Player', 'MOD Player'),
                         ('manual/img/sidplayer.png', 'SID-Player', 'SID Player'),
                         ('manual/img/midi-player.png', 'MIDI-Player', 'MIDI Player'),
                         ('manual/img/vidkit-player.png', 'VIDKIT-Player', 'VIDKIT Player')], 'MOD-Player',
     'MOD Player for Amiga modules, SID Player for C64 tunes on a SID card, MIDI Player for MIDI and ZSM songs on '
     'the YM2151, and VIDKIT Player for SPV videos and WAV and ZCM audio from the SD card.',
     'MIDI Player plays with Melodius and ZSMKit by MooingLemur; VIDKIT Player is by Anthony W. Henry.'),
    ('Games', [('img/game-pinball.png', 'Lighthouse-Pinball', 'Lighthouse Pinball'),
               ('img/game-harbour-walls.png', 'Harbour-Walls', 'Harbour Walls'),
               ('img/game-solitaire.png', 'Solitaire', 'Solitaire'),
               ('img/game-geochess.png', 'geoChess', 'geoChess')], 'Lighthouse-Pinball',
     'Lighthouse Pinball, Harbour Walls, Solitaire (Klondike, FreeCell, Spider and more) and geoChess.'),
]
# under the games' card (the gallery's geoChess is Scott Hutter's)
GAMES_CREDIT = ('geoChess is by Scott Hutter and the authors in its history (github.com/geos64128/geochess); '
                'its engine is derived from BMCP by Maksim Korzh, after micro-Max by H.G. Muller.')


def build(a):
    out = a.out
    if os.path.exists(out):
        shutil.rmtree(out)
    os.makedirs(os.path.join(out, 'manual', 'img'))
    os.makedirs(os.path.join(out, 'img'))
    shutil.copyfile(os.path.join(HERE, 'style.css'), os.path.join(out, 'style.css'))
    for f in sorted(os.listdir(os.path.join(HERE, 'img'))):
        shutil.copyfile(os.path.join(HERE, 'img', f), os.path.join(out, 'img', f))
    man = a.manual
    for f in sorted(os.listdir(os.path.join(man, 'img'))):
        shutil.copyfile(os.path.join(man, 'img', f), os.path.join(out, 'manual', 'img', f))

    # the releases
    rels = api_releases(a.repo) if a.api else None
    source = 'GitHub'
    if not rels:
        source = None
        if a.changes and os.path.isfile(a.changes):
            rels, source = changes_releases(a.changes), 'CHANGES.txt'
    rels = rels or []
    stable = [r for r in rels if r['tag'] and not r['pre']]
    latest = stable[0] if stable else None

    # ---- the manual
    pages = sorted(f[:-3] for f in os.listdir(man) if f.endswith('.md') and not f.startswith('_'))
    side = Md(link=lambda t: mlink(t, pages)).render(open(os.path.join(man, '_Sidebar.md'), encoding='utf-8').read())
    titles = {}
    for p in pages:
        src = open(os.path.join(man, p + '.md'), encoding='utf-8').read()
        m = re.search(r'^# (.+)$', src, re.M)
        titles[p] = m.group(1).strip() if m else p.replace('-', ' ')
        md = Md(link=lambda t: mlink(t, pages, a.repo))
        body = md.render(src)
        fn = 'index.html' if p == 'Home' else p + '.html'
        wiki = 'https://github.com/%s/wiki/%s' % (a.repo, '' if p == 'Home' else p)
        html_ = ('<div class="manual"><aside class="side"><details open><summary>Contents</summary>%s</details></aside>'
                 '<main class="doc">%s<p class="note">This page is also in the '
                 '<a href="%s">wiki</a>, and on the X16 (the desktop\'s Veranda &gt; Help).</p></main></div>'
                 % (side, body, wiki))
        with open(os.path.join(out, 'manual', fn), 'w', encoding='utf-8') as f:
            f.write(page('%s - the Veranda manual' % titles[p], html_, 'manual/index.html', 1,
                         'The Veranda manual: %s' % titles[p]))

    # ---- home
    feats = []
    for f in FEATURES:
        t, img, mp, text = f[:4]
        note = f[4] if len(f) > 4 else (GAMES_CREDIT if t == 'Games' else '')
        if isinstance(img, list):       # a gallery: 2 x 2 screens, each its page
            pics = '<div class="gallery">%s</div>' % ''.join(
                '<a href="manual/%s.html"><img src="%s" alt="%s" title="%s" loading="lazy" width="640" height="480">'
                '</a>' % (gp, gi, html.escape(gt), html.escape(gt)) for gi, gp, gt in img)
            credit = '<p class="credit">%s</p>' % html.escape(note) if note else ''
        else:
            pics = ('<a href="manual/%s.html"><img src="%s" alt="%s" loading="lazy" width="640" height="480"></a>'
                    % (mp, img, html.escape(t)))
            credit = ''
        feats.append('<article class="card">%s<div><h3><a href="manual/%s.html">%s</a></h3><p>%s</p>%s'
                     '</div></article>' % (pics, mp, html.escape(t), html.escape(text), credit))
    if latest:
        zipl = latest['zip'] or 'https://github.com/%s/releases/download/%s/veranda-%s-sdcard.zip' % (
            a.repo, latest['tag'], latest['tag'].lstrip('v'))
        dl = ('<p class="ver"><strong>%s</strong>%s</p><p><a class="button" href="%s">Download the SD-card zip</a> '
              '<a href="releases.html">What is new</a></p>'
              % (html.escape(latest['name']), ', ' + latest['date'] if latest['date'] else '', html.escape(zipl)))
        if source != 'GitHub':
            dl += '<p class="small">(The release as the package\'s CHANGES.txt lists it: the link works once it is published on GitHub.)</p>'
    else:
        dl = '<p>No release is published yet. <a href="https://github.com/%s/releases">The releases</a></p>' % a.repo
    install = Md(link=lambda t: mlink(t, pages, a.repo)).render(INSTALL)
    home = '''<div class="sage"><section class="hero">
  <div class="intro">
    <h1>A desktop for the Commander X16</h1>
    <p class="lead">Veranda is a graphical desktop and a set of programs for the Commander X16, written for the
    machine: 640 x 480 in colour, windows, menus, icons, a dock and Alt+Tab, long file names on the SD card,
    and a network through a Wi-Fi modem. Programs use the GEOS programming interface, with a modern layer on top.</p>
    <p class="lead">It is free software, MIT licensed, and runs on a stock X16 with 512 KB of RAM.</p>
    <div class="download" id="download">
      <h2>Download</h2>
      %s
    </div>
  </div>
  <figure class="shot"><img src="manual/img/desktop-icons.png" alt="The Veranda desktop in the Sunroom look: a window
  on the Documents folder with colour icons, the sidebar, the menu bar" width="640" height="480">
  <figcaption>The desktop, in the Sunroom look.</figcaption></figure>
</section></div>
<main>
<section>
  <h2>The programs</h2>
  <p>Twenty-odd programs come with it: a word processor, a spreadsheet, a paint program, a text editor, network
  programs, music players, games and a BASIC. A few of them:</p>
  <div class="cards">%s</div>
  <p>All of them, and the rest, are in the <a href="manual/index.html">manual</a>.</p>
</section>
<section class="install" id="install">
  <h2>Install it on the SD card</h2>
  %s
  <p>More in the manual: <a href="manual/Installing.html">Installing Veranda</a>.</p>
</section>
</main>''' % (dl, ''.join(feats), install)
    with open(os.path.join(out, 'index.html'), 'w', encoding='utf-8') as f:
        f.write(page('Veranda: a desktop for the Commander X16', home, 'index.html', 0,
                     'Veranda, a GEOS-style graphical desktop and programs for the Commander X16.'))

    # ---- releases
    rs = []
    for r in rels:
        if r.get('body') is not None and 'points' not in r:
            notes = Md().render(r['body'])
        else:
            notes = '<ul>%s</ul>' % ''.join('<li>%s</li>' % Md().inline(p) for p in r['points']) if r['points'] else ''
        links = []
        if r.get('zip'):
            links.append('<a class="button" href="%s">SD-card zip</a>' % html.escape(r['zip']))
        if r.get('url'):
            links.append('<a href="%s">On GitHub</a>' % html.escape(r['url']))
        badge = '<span class="badge">test build</span>' if r['pre'] and r['tag'] else ''
        rs.append('<article class="release"><h2 id="%s">%s %s</h2><p class="date">%s</p>%s<p>%s</p></article>'
                  % (html.escape(r['tag'] or slug(r['name'])), html.escape(r['name']), badge,
                     html.escape(r['date'] or ''), notes, ' '.join(links)))
    rel = '''<main class="narrow">
<h1>Releases</h1>
<p>Each release has an SD-card zip for a new card, and the files <a href="manual/Veranda-Update.html">Veranda
Update</a> fetches on the X16 (only the files that changed). Test builds are for Veranda Update's Test channel.
%s</p>
%s
</main>''' % ('(Listed from %s.)' % source if source else '', '\n'.join(rs) or '<p>None yet.</p>')
    with open(os.path.join(out, 'releases.html'), 'w', encoding='utf-8') as f:
        f.write(page('Releases - Veranda', rel, 'releases.html', 0, 'Every Veranda release and its notes.'))

    # ---- about
    lic = open(os.path.join(man, 'Licences.md'), encoding='utf-8').read()
    lic = re.sub(r'^# .*\n', '', lic)
    licmd = Md(link=lambda t: mlink(t, pages, a.repo, prefix='manual/'), img=lambda t: 'manual/' + t)
    about = '''<main class="narrow">
<h1>About Veranda</h1>
<p>Veranda is a graphical system for the Commander X16, an 8-bit computer of today built around a 65C02 and the VERA
video chip. It follows GEOS, Berkeley Softworks' desktop for the Commander 64, in its programming interface, so that
GEOS programs with source can be ported, and adds what the X16 makes possible: the full 640 x 480 screen in colour,
banked RAM, FAT32 with long names, a network through a Wi-Fi modem.</p>
<p>It is written by Marcin Spoczynski. The source, the issues and the releases are on
<a href="https://github.com/%s">GitHub</a>; the manual is <a href="manual/index.html">here</a> and in the
<a href="https://github.com/%s/wiki">wiki</a>.</p>
<h2>Credits</h2>
<ul>
<li><strong>The Commander X16</strong>, its ROM and its emulator
(<a href="https://github.com/X16Community/x16-emulator">x16emu</a>), by the X16 community.</li>
<li><strong>cc65</strong>, the C compiler and assembler every part is built with.</li>
<li><strong>Zimodem</strong> by Bo Zimmerman, the Wi-Fi modem's firmware the network programs talk to.</li>
<li><strong>geoChess</strong> by Scott Hutter and the authors in its history; its engine is derived from BMCP by
Maksim Korzh, after micro-Max by H.G. Muller.</li>
<li><strong>PySolFC</strong> and PySol (Markus F.X.J. Oberhumer, Skomoroh and its contributors): Solitaire's rules.</li>
<li><strong>micromod</strong> by Martin Cameron (BSD 3-Clause): MOD Player's test reference.</li>
<li><strong>NewsWaffle</strong> and <strong>Gemipedia</strong> by Acidus (gemi.dev): web pages and Wikipedia in
Veranda Gemini.</li>
<li><strong>Packet16</strong>, the author's FTP client: the network programs' FTP and modem code.</li>
</ul>
<h2 id="licences">Licences</h2>
%s
</main>''' % (a.repo, a.repo, licmd.render(lic))
    with open(os.path.join(out, 'about.html'), 'w', encoding='utf-8') as f:
        f.write(page('About - Veranda', about, 'about.html', 0, 'About Veranda, the credits and the licences.'))
    n = sum(1 for _ in os.scandir(os.path.join(out, 'manual'))) - 1
    print('site: %s: home, releases (%d, from %s), manual (%d pages), about' % (out, len(rels), source or 'none', n))


INSTALL = '''1. Download the SD-card zip above and unzip it.
2. Copy its folders `VERANDA`, `PC` and `DOCUMENTS` to the top of the X16's SD card
   (`DOCUMENTS` holds examples: skip a file you already have).
3. Put the card in the X16 and type:

        DOS"CD:VERANDA"
        BOOT

4. Later versions: **Veranda Update** (in `/VERANDA/APPS`) fetches only the files that changed.

You need a Commander X16 with 512 KB of banked RAM or more, its SD card and a mouse. The network programs need
TexElec's Serial & ESP32 Network Card ([Network setup](Network-setup.md)).
'''


def mlink(t, pages, repo=ORG + '/veranda', prefix=''):
    """a link of the manual: Page.md to Page.html, the rest to GitHub"""
    if re.match(r'[a-z]+:', t) or t.startswith('#'):
        return t
    path, _, frag = t.partition('#')
    if '/' not in path and path.endswith('.md') and path[:-3] in pages:
        name = 'index' if path == 'Home.md' else path[:-3]
        return prefix + name + '.html' + ('#' + frag if frag else '')
    rel = os.path.normpath(os.path.join('docs/manual', path)).replace(os.sep, '/')
    return 'https://github.com/%s/blob/main/%s%s' % (repo, rel, '#' + frag if frag else '')


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--out', default=os.path.join(TOP, 'build', 'site'))
    ap.add_argument('--repo', default=ORG + '/veranda')
    ap.add_argument('--api', action='store_true')
    ap.add_argument('--changes')
    ap.add_argument('--manual', default=os.path.join(TOP, 'docs', 'manual'))
    a = ap.parse_args()
    build(a)


if __name__ == '__main__':
    main()
