#!/usr/bin/env python3
"""Gate gemini (DECISIONS V118): Veranda Gemini's sessions checked (tools/
gate_gemini.sh): the console's "GE ..." lines (tests/gemini_play.c and the
test build's own), the server's log (tests/gemini_server.py), the modem's
log, the files on the card. The pages are compared with this file's own
model of apps/gemini/doc.c (the folding to CP437, gemtext's kinds of line,
the wrap) and of render().

usage: check_gemini.py <session> <run folder> <port>
  sessions: main, nomodem, launch (V128: Veranda Gemini started by the
  shell with the Wikipedia launcher; the run folder's console has the
  shell's lines too), quit (V196: qclose, ckey, fmenu: a picture shown,
  then Quit; the test desktop's lines after Gemini's)
"""
import os
import re
import sys

SESS, R, PORT = sys.argv[1], sys.argv[2], int(sys.argv[3])
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import png_ref  # noqa: E402
import jpeg_ref  # noqa: E402
PICS = ['gray1', 'pal1', 'pal4', 'pal8', 'gray8', 'rgb', 'rgba', 'gray16', 'small', 'comic', 'interlaced', 'corrupt', 'big']
JPICS = ['photo', 'progressive']        # (V192: shown, refused)
EXITS = ['wheel', 'click', 'backspace', 'back', 'aside', 'key', 'menu']    # (V196: the ways out of a picture)
PICNAMES = [k + '.png' for k in PICS[:10]] + ['photo.jpg'] + [k + '.png' for k in PICS[10:]] + ['progressive.jpg']
raw = open(os.path.join(R, 'log.txt'), encoding='utf-8', errors='replace').read()
log = raw.split('\n')


def need(c, msg):
    if not c:
        sys.exit('FAIL  ' + msg)


def ok(msg):
    print('ok    ' + msg)


def val(key):
    m = re.search(r'%s(-?\d+)$' % re.escape(key), raw, re.M)     # (a DOS write's echo may come first on the line)
    return int(m.group(1)) if m else None


def boxes():
    return [l[l.index('GE BOX ') + 7:] for l in log if 'GE BOX ' in l]     # (a DOS command's echo may come first)


need('GE TEST STUCK' not in raw and 'GE TEST FAILED' not in raw and 'GE TEST SCRIPT FULL' not in raw,
     'the test stopped: %s' % re.findall(r'GE TEST (?:STUCK|FAILED|SCRIPT)[^\n]*', raw))
if SESS == 'quit':                      # (V196) Quit from a picture: Gemini ends, the desktop's lines
    how = re.findall(r'GE QUIT (\w)$', raw, re.M)
    need(len(how) == 1, 'the quit: %s' % how)
    need('GE PIC SHOWN ' in raw and raw.index('GE PIC SHOWN ') < raw.index('GE QUIT '), 'no picture shown first')
    need('TERMDESK' in raw[raw.index('GE QUIT '):], 'Gemini did not end (no test desktop after the quit): %s'
         % log[-6:])
    need('GE END' not in log, 'the session went on')
    need(not os.path.exists(os.path.join(R, 'VERANDA', '.SYSTEM', 'GEMINI.TMP')), 'GEMINI.TMP left behind')
    d = open(os.path.join(R, 'dump.bin'), 'rb').read()
    v = d[len(d) - 132878:]
    l0 = v[131072 + 256 + 512]
    need(l0 & 3 != 2 or not v[131072] & 0x10, 'tile mode left on (layer 0 config $%02X)' % l0)
    pal, kept = v[131072 + 256 + 64:131072 + 256 + 512], v[0x12C00:0x12C00 + 448]
    need(pal == kept, 'palette entries 32-255 not as they were before the picture (the first unlike: %s)'
         % next((i // 2 + 32 for i in range(448) if pal[i] != kept[i]), None))
    ok('Quit (%s) while a picture is shown: Gemini ended at once (the test desktop started after it), GEMINI.TMP '
       'deleted, tile mode off (layer 0 config $%02X), palette entries 32-255 as before the picture'
       % ({'q': 'the close box', 'c': 'Ctrl+Q', 'f': 'Veranda Gemini > Quit'}[how[0]], l0))
    sys.exit(0)
need('GE END' in log, 'no end')

if SESS == 'nomodem':
    need(any(b.startswith('The modem does not answer.|') for b in boxes()), 'no modem: the boxes %s' % boxes())
    ok('no modem on the port: the address typed, the box "The modem does not answer." (vrnet: NET_ENOMODEM)')
    sys.exit(0)

# ---------------------------------------------------------------- the model (doc.c)
FOLD = ("AAAAAAACEEEEIIIIDNOOOOOxOUUUUYPsaaaaaaaceeeeiiiidnooooo/ouuuuypy"
        "AaAaAaCcCcCcCcDdDdEeEeEeEeEeGgGgGgGgHhHhIiIiIiIiIiIiJjKkkLlLlLlLlLlNnNnNnnNnOoOoOoOoRrRrRrSsSsSsSsTtTtTtUuUuUuUuUuUuWwYyYZzZzZzs")
SPEC = {}
for cps, s in (((0x2018, 0x2019, 0x201A, 0x201B, 0x2032, 0x2035), b"'"),
               ((0x201C, 0x201D, 0x201E, 0x201F, 0x2033), b'"'),
               ((0x2010, 0x2011, 0x2012, 0x2013, 0x2014, 0x2015, 0x2212, 0x2043), b'-'),
               ((0x2026,), b'...'), ((0x00A0, 0x2007, 0x202F, 0x205F, 0x3000), b' '),
               ((0x00AD, 0x200B, 0x200C, 0x200D, 0x2060, 0xFEFF), b''),
               ((0x25CF, 0x2023, 0x25E6, 0x2027), b'\x07'), ((0x2713, 0x2714, 0x2705), b'\x82'),
               ((0x2717, 0x2718, 0x274C, 0x00D7), b'x'), ((0x21D2,), b'=>'), ((0x21D0,), b'<='),
               ((0x27A1, 0x2794, 0x2192), b'\x1a'), ((0x2190,), b'\x1b'),
               ((0x2122,), b'TM'), ((0x00AE,), b'(R)'),
               # (V124)
               ((0xFE0F, 0xFE0E), b''), ((0x2022,), b'\x07'), ((0x2716,), b'x'), ((0x2B05,), b'\x1b'),
               ((0x2191, 0x2B06), b'\x18'), ((0x2193, 0x2B07), b'\x19'), ((0x23E9,), b'>>'), ((0x23EA,), b'<<'),
               ((0x23ED,), b'>>|'), ((0x23EE,), b'|<<'), ((0x25B6,), b'>'), ((0x25C0,), b'<'),
               ((0x2B50, 0x2605, 0x2606, 0x2728, 0x1F3B2), b'*'), ((0x26A0, 0x2757), b'!'), ((0x2795,), b'+'),
               ((0x2796,), b'-'), ((0x1F449,), b'->'), ((0x1F448, 0x1F519), b'<-'), ((0x1F51D,), b'^')):
    for c in cps:
        SPEC[c] = s


# (V143) the font's upper half: $80-$9F private glyphs (CP437's pi, square,
# root, shades, blocks and box lines: copy.s's cs_font), $A0-$FF Veranda's
# set, ISO-8859-16
PRIV = [0xE3, 0xFE, 0xFB, 0xB0, 0xB1, 0xB2, 0xB3, 0xB4, 0xBF, 0xC0, 0xC1, 0xC2, 0xC3, 0xC4, 0xC5, 0xD9,
        0xDA, 0xDB, 0xDC, 0xDD, 0xDE, 0xDF, 0xBA, 0xCD, 0xC9, 0xBB, 0xC8, 0xBC, 0xCC, 0xB9, 0xCB, 0xCA]
FONT = {ord(bytes([b]).decode('cp437')): 0x80 + i for i, b in enumerate(PRIV)}
FONT.update({ord(bytes([c]).decode('iso8859_16')): c for c in range(0xA0, 0x100)})


def fold(text):
    out = bytearray()
    for ch in text:
        v = ord(ch)
        if v > 0xFFFF and v in SPEC:
            out += SPEC[v]
        elif v > 0xFFFF:
            out += b'?'
        elif v < 128:
            if ch in '\n\t' or 32 <= v < 127:
                out.append(v)
        elif v in SPEC:
            out += SPEC[v]
        elif 0x2000 <= v <= 0x200A:
            out += b' '
        else:
            b = FONT.get(v)
            if b:
                out.append(b)
            elif 0xC0 <= v < 0x180:
                out += FOLD[v - 0xC0].encode()
            else:
                out += b'?'
    return bytes(out)


K_TEXT, K_LINK, K_H1, K_PRE, K_PLAIN, K_LIST, K_QUOTE, K_CONT = 0, 1, 2, 7, 8, 5, 6, 0x80
LK = {'gemini:': 0, 'http:': 1, 'https:': 1, 'gopher:': 2, 'mailto:': 3}


class Doc:
    """doc.c's parser: rows [(start, kind)] of the stored bytes"""

    def __init__(self, mode):
        self.mode, self.rows, self.d = mode, [], bytearray()
        self.st, self.pf, self.pre, self.fence = 'START', [], False, False
        self.rk, self.col, self.spcol, self.lstart, self.rs, self.sp = (K_PLAIN, 0, 0, 0, 0, 0)
        self.ww = 76                    # (V149: PLAINW, cards 1-76; 78 before the Sunroom scroll bar)
        if mode == 'plain':
            self.newrow(0, K_PLAIN)

    def newrow(self, o, k):
        self.rows.append((o, k))
        self.rs, self.sp = o, 0

    def wrapc(self, c, o):
        tab = c == 9 and self.mode == 'plain'
        nc = (self.col | 7) + 1 if tab else self.col + 1
        if nc > self.ww:
            if self.sp > self.rs:
                self.col -= self.spcol
                self.newrow(self.sp, self.rk | K_CONT)
            else:
                self.col = 0
                self.newrow(o, self.rk | K_CONT)
            nc = (self.col | 7) + 1 if tab else self.col + 1
            nc = min(nc, self.ww)
        self.col = nc
        if c in (32, 9):
            self.sp, self.spcol = o + 1, self.col

    def first(self, o, k):
        self.newrow(o, k)
        self.col, self.st = 0, 'BODY'

    def url_kind(self):
        u = self.url.lower()
        k = 0
        m = re.match(r'([^/?#:]*):', u)
        if m:
            k = LK.get(u[:len(m.group(0))], 5) if len(m.group(0)) <= 7 else 5
        pth = re.split(r'[?#]', u)[0]     # (V138: the path's end, not the query's: Gemipedia's media.png?...)
        if k == 0 and len(pth) >= 4 and pth[-4:] in ('.png', '.jpg', 'jpeg', '.gif', '.bmp'):
            k = 4
        return K_LINK | (k << 4)

    def body(self, c, o):
        s = c in (32, 9)
        if self.st == 'WS':
            if s:
                return
            if self.rk == K_LINK:
                self.st, self.uo, self.url = 'URL', o, chr(c)
                return
            self.first(o, self.rk)
        elif self.st == 'URL':
            if not s:
                self.url += chr(c)
                return
            self.rk, self.st = self.url_kind(), 'WS2'
            return
        elif self.st == 'WS2':
            if s:
                return
            self.first(o, self.rk)
        elif self.st != 'BODY':
            return
        self.wrapc(c, o)

    def decide(self, fin):
        pf, np = self.pf, len(self.pf)
        n = 0
        while n < np and pf[n] == 96:
            n += 1
        if not np:
            self.newrow(self.lstart, K_PRE if self.pre else K_TEXT)
            self.st = 'NONE'
            return
        c0 = pf[0]
        if c0 == 96 and n == np and np < 3 and not fin:
            return
        if n >= 3:
            self.fence, self.st = True, 'NONE'
            return
        if self.pre:
            self.newrow(self.lstart, K_PRE)
            self.st = 'NONE'
            return
        k, b = K_TEXT, 0
        if c0 in (61, 42):
            if np < 2 and not fin:
                return
            if np >= 2 and pf[1] == (62 if c0 == 61 else 32):
                k, b = (K_LINK if c0 == 61 else K_LIST), 2
        elif c0 == 35:
            while b < np and pf[b] == 35:
                b += 1
            if b == np and np < 3 and not fin:
                return
            k = K_H1 - 1 + b
        elif c0 == 62:
            k, b = K_QUOTE, 1
        self.rk, self.ww = k, 73     # (GEMW; 75 before V149)
        if k == K_TEXT:
            self.first(self.lstart, K_TEXT)
        else:
            self.st = 'WS'
        for i in range(b, np):
            self.body(pf[i], self.lstart + i)

    def eol(self, o):
        if self.st == 'START':
            self.decide(True)
        if self.st == 'WS':
            self.newrow(self.lstart, K_TEXT) if self.rk == K_LINK else self.newrow(o, self.rk)
        elif self.st in ('URL', 'WS2'):
            if self.st == 'URL':
                self.rk = self.url_kind()
            self.newrow(self.uo, self.rk)
        if self.fence:
            self.pre, self.fence = not self.pre, False
        self.st, self.pf, self.lstart = 'START', [], o + 1

    def put(self, c):
        o = len(self.d)
        self.d.append(c)
        if self.mode == 'plain':
            if c == 10:
                self.col = 0
                self.newrow(o + 1, K_PLAIN)
            else:
                self.wrapc(c, o)
            return
        if c == 10:
            self.eol(o)
        elif self.st == 'START':
            self.pf.append(c)
            self.decide(False)
        else:
            self.body(c, o)

    def end(self):
        if self.mode == 'gem':
            if self.st != 'START' or self.pf:
                self.eol(len(self.d))
        elif self.rows and self.rows[-1][0] >= len(self.d):
            self.rows.pop()

    def render(self):
        """the rows as page_log writes them: (kind, text)"""
        out = []
        for i, (o, k) in enumerate(self.rows):
            e = self.rows[i + 1][0] if i + 1 < len(self.rows) else len(self.d)
            if e <= o:
                e = len(self.d)
            e = min(e, o + 255)
            b = bytes(self.d[o:e]).split(b'\n')[0]
            t = k & 15
            rawk = t in (K_PRE, K_PLAIN)
            row = [' '] * 76                # (ROWW, V149)
            col = 0 if rawk else 3
            if t == K_LIST and not k & K_CONT:
                row[1] = '\x07'
            elif t == K_QUOTE:
                row[1] = '\xb3'
            for c in b:
                if col >= 76:
                    break
                if c == 9 and rawk:
                    col = (col | 7) + 1
                    continue
                row[col] = (' ' if c == 9 else '?') if c < 32 else chr(c)
                col += 1
            if k == (K_LINK | 4 << 4) and col < 64 and (i + 1 >= len(self.rows) or not self.rows[i + 1][1] & K_CONT):
                row[col + 1:col + 13] = list('[Show image]')    # (a picture link's one row, V125)
            out.append(('%02x' % k, ''.join(row).rstrip(' ')))
        return out


def model(text, mode='gem', folded=None):
    d = Doc(mode)
    for c in (folded if folded is not None else fold(text)):
        d.put(c)
    d.end()
    return d


def pages():
    out, cur = [], None
    for l in log:
        if l.startswith('GE PAGE END '):
            if cur:
                cur[2] = tuple(int(x) for x in l[12:].split())
                out.append(tuple(cur))
            cur = None
        elif l.startswith('GE PAGE '):
            cur = [l[8:], [], None]
        elif l.startswith('GE L ') and cur is not None:
            cur[1].append((l[5:7], l[8:]))
    return out


# the console's text is the CP437 bytes as the emulator writes them (its
# EMU_STDOUT: 9, 10, 13 and 32-126 as they are, $A1-$FF as ISO-8859-15, the
# rest U+FFFD)
def console(t):
    out = ''
    for c in t:
        b = ord(c)
        out += c if b in (9, 10, 13) or 32 <= b < 127 else bytes([b]).decode('iso8859_15') if b >= 0xA1 else '�'
    return out


def as_console(rows):
    return [(k, console(t)) for k, t in rows]


def same(got, want, what):
    w = as_console(want)
    if got != w:
        for i, (a, b) in enumerate(zip(got, w)):
            if a != b:
                sys.exit('FAIL  %s: row %d is %r, the model says %r' % (what, i, a, b))
        sys.exit('FAIL  %s: %d rows, the model %d' % (what, len(got), len(w)))


P = pages()
slog = [l[4:] for l in open(os.path.join(R, 'srv', 'gemini.log'), encoding='utf-8').read().split('\n')
        if l.startswith('REQ ')]
mlog = open(os.path.join(R, 'modem.log'), encoding='latin-1').read().split('\n')
ats = [l.split(' ', 1)[1] for l in mlog if l.startswith('@')]
atc = [a for a in ats if a.startswith('ATC')]
B = 'gemini://127.0.0.1:%d/' % PORT
F = os.path.join(R, 'srv', 'files')
WPB = B + 'cgi-bin/wp.cgi/'


def wiki_page(lang, title):
    return model(open(os.path.join(F, 'wiki-%s-%s.gmi' % (lang, title.replace(' ', '_'))), 'rb').read().decode('utf-8'))


if SESS == 'launch':
    # (V128) the shell's double click on the Wikipedia document: Veranda
    # Gemini started with it (ST_LD_DATA), its line "wp" typed: the box
    need(any(l.endswith('GE START DOC Wikipedia|wp') for l in log), 'the start document: %s' % [l for l in log if 'START DOC' in l])
    bx = boxes()
    need(bx[:1] == ['Look up in Wikipedia:|'], 'the first box: %s' % bx[:3])
    need(slog == [WPB + 'view?Ada%20Lovelace'], 'the requests: %s' % slog)
    need(P and P[0][0] == '' and P[-1][0] == WPB + 'view?Ada%20Lovelace', 'the pages: %s' % [p[0] for p in P])
    same(P[-1][1], wiki_page('en', 'Ada Lovelace').render(), 'the article')
    need(re.search(r'SHELL', raw) is not None, 'the shell did not run')
    ok('the Wikipedia launcher (/DOCUMENTS/Wikipedia.cvt, a GEOS document of class GeminiStart, parent VerandaGemi) '
       'double-clicked in the shell: Veranda Gemini (in /VERANDA/APPS) started with it (GetFile, ST_LD_DATA; its data '
       '"wp"), the box "Look up in Wikipedia:" at once (no bookmark, no click), "Ada Lovelace": the request '
       '%sview?Ada%%20Lovelace, the article (%d rows equal to the model\'s; launch.png)'
       % (WPB, len(P[-1][1])))
    sys.exit(0)

# ---------------------------------------------------------------- the bookmarks page
DEFAULTS = ['=> gemini://geminiprotocol.net/ Project Gemini',
            '=> gemini://kennedy.gemi.dev/ Kennedy: search Geminispace',
            '=> gemini://geminispace.info/ geminispace.info: search',
            '=> gemini://antenna.flounder.online/ Antenna: what is new in Geminispace',
            '=> gemini://gemi.dev/ gemi.dev',
            '=> gemini://gemi.dev/cgi-bin/waffle.cgi NewsWaffle: web pages as gemtext',
            '=> gemini://gemi.dev/cgi-bin/wp.cgi/ Gemipedia: Wikipedia',
            '=> gemini://gemi.dev/cgi-bin/wp.cgi/featured Wikipedia: featured articles']
KEPT = DEFAULTS[:4] + DEFAULTS[5:]      # (after gemi.dev is removed)


def marks_text(marks):
    return ('# Bookmarks\nClick one, or move to it with Tab and press Return. Bookmarks > Add this page adds '
            'the page shown.\n\n' + ''.join(m + '\n' for m in marks))


need(P and P[0][0] == '', 'the first page is not the bookmarks page: %s' % (P[:1],))
same(P[0][1], model(marks_text(DEFAULTS)).render(), 'the bookmarks page')
ok('no GEMINI.MARKS: the bookmarks page (gemtext: a heading, a paragraph wrapped, 8 links: Project Gemini, '
   'Kennedy, geminispace.info, Antenna, gemi.dev, NewsWaffle, Gemipedia, its featured articles) as the model renders it')

# ---------------------------------------------------------------- the root
root_b = open(os.path.join(F, 'root.gmi'), 'rb').read()
root = model(root_b.decode('utf-8'))
roots = [p for p in P if p[0] == B]
need(roots, 'the root was not shown: %s' % [p[0] for p in P])
for p in roots:
    same(p[1], root.render(), 'the root page')
    need(p[2] == (len(root.rows), 0, len(root.d)), 'the root: rows %s, the model %d %d' % (p[2], len(root.rows), len(root.d)))
sym = [t for _, t in as_console(root.render()) if t.startswith('   Symbols (V124)')]
need(sym and sym[0].strip() == 'Symbols (V124): >> next << back * random ! mind ? dot * star ? unknown.', 'the symbols: %r' % sym)   # (the bullet, CP437 7, is ? on the console)
ok('symbols and emoji (V124): ⏩ >>, ⏪ <<, 🎲 *, ⚠️ ! (its variation selector dropped), • as CP437\'s bullet, ⭐ *, an unknown emoji ?')
kinds = sorted(set(k for k, _ in root.render()))
need({'00', '01', '02', '03', '04', '05', '06', '07', '11', '21', '31', '41', '80', '85', '86'} <= set(kinds),
     'the root\'s kinds of row: %s' % kinds)
ok('the root (%d bytes of UTF-8, %d stored in the font\'s bytes: V143, ISO-8859-16 and the private box glyphs; Polish kept): %d rows equal to the model\'s: headings (3 levels), a paragraph '
   'wrapped at its spaces, a 98-character word cut, list items (one wrapped), a quote wrapped (its bar on each row), '
   'a preformatted block (no wrap, its tab, "##" and "=>" kept, the fences hidden), links (relative, tabs, no label, '
   'the web, gopher, mail, a picture; "=>" alone as text), accents, quotes, a dash, an ellipsis, an emoji folded; '
   'shown %d times' % (len(root_b), len(root.d), len(root.rows), len(roots)))

# ---------------------------------------------------------------- requests
want = [B, B + 'sub/page.gmi', B + 'input', B + 'input?Ada%20Lovelace', B + 'secret',
        B + 'secret?p4ss%20w0rd%26', B + 'redirect', B + 'sub/page.gmi', B + 'moved',
        'gemini://localhost:%d/sub/page.gmi' % PORT] + [B + 'loop'] * 6 + [
        B + 'missing', B + 'cert', B + 'cgi-bin/waffle.cgi/view?https%3A%2F%2Fexample.com%2Fpage.html',
        'https://example.com/page.html', 'https://example.com/varieties/cherry', 'https://example.com/typed',
        B + 'plain.txt', B + 'latin1.gmi', B + 'big.bin', B + 'slow', B, B + 'pics.gmi'] + [
        B + 'pic/%s' % k for k in PICNAMES] + [B + 'pic/pal4.png', B + 'pic/rgb.png'] + [
        B + 'pic/small.png'] * len(EXITS) + [B + 'pics.gmi'] + [
        WPB + 'view?Ada%20Lovelace', WPB + 'view?Gemini%20%28protocol%29', WPB + 'view?no%20such%20thing',
        WPB + 'search?no+such+thing', WPB + 'view/pl?Warszawa']
# (V138) Gemipedia's gallery: its page, then its pictures' links (relative: the
# media route), the unreachable one (a closed port) never reaching the server
GAL = ['flag', 'castle', 'map', 'wawel', 'unreachable']
gal_t = open(os.path.join(F, 'gallery.gmi'), 'rb').read().decode('utf-8')
gal_links = [l.split(' ')[1] for l in gal_t.split('\n') if l.startswith('=> ')]
i = len(want) - want[::-1].index(B + 'pics.gmi')       # (after the ways out's Reload, V196: the gallery)
want[i:i] = [WPB + 'images?Poland'] + [B + gal_links[j][1:] for j in (1, 2, 4, 3)]     # (the order clicked: flag, castle, map, wawel)
got = [u for u in slog if u != B]
wantn = [u for u in want if u != B]
need(got == wantn, 'the requests: the first unlike %s' % [(g[:100], w[:100]) for g, w in zip(got + [''] * 9, wantn + [''] * 9) if g != w][:2])
need(slog[:3] == [B, B + 'sub/page.gmi', B + 'input'],
     'Back and Forward fetched again (the cache): %s' % slog[:4])
ok('the server got %d requests, in order (%d of the root); Back and Forward after the relative link came from the '
   'cache (no request; "kept from before")' % (len(slog), slog.count(B)))
need(any('kept from before' in l for l in log if l.startswith('GE STATUS ')), 'no page from the cache')

sub = [p for p in P if p[0].endswith('/sub/page.gmi')]
need(sub, 'the sub page')
sm = model(open(os.path.join(F, 'sub.gmi'), 'rb').read().decode('utf-8'))
for p in sub:
    same(p[1], sm.render(), 'the sub page')
need([p[0] for p in P[1:5]] == [B, B + 'sub/page.gmi', B, B + 'sub/page.gmi'],
     'the relative link, Back, Forward: %s' % [p[0] for p in P[1:6]])
need(val('GE TEST HPOS ') == 1 and val('GE TEST HN ') == 3, 'the history: %s %s' % (val('GE TEST HPOS '), val('GE TEST HN ')))
ok('the relative link (sub/page.gmi) resolved to %ssub/page.gmi; the toolbar\'s Back, Go > Forward, Back: the '
   'history 3 entries, the 2nd shown' % B)

# ---------------------------------------------------------------- questions, redirects
bx = boxes()
need('What is your name?|' in bx, 'the question\'s box: %s' % bx)
hello = [p for p in P if p[0] == B + 'input?Ada%20Lovelace']
need(hello and hello[0][1] == as_console(model('# Hello\nHello, Ada Lovelace!\n').render()), 'the answer: %s' % hello)
need('A password, please (it shows as you type)|' in bx, 'the sensitive question\'s box: %s' % bx)
ok('10: Tab to "Ask my name", Return: the box "What is your name?", "Ada Lovelace": %sinput?Ada%%20Lovelace '
   '(percent-encoded), its page; 11: the box with "(it shows as you type)", "p4ss w0rd&" sent as %%20 and %%26' % B)
need([p[0] for p in P if 'sub/page.gmi' in p[0]].count(B + 'sub/page.gmi') >= 3, 'the redirect\'s page')
need('The capsule sends you to another host.|Go to localhost?' in bx, 'the other host\'s box: %s' % bx)
need(any(p[0] == 'gemini://localhost:%d/sub/page.gmi' % PORT for p in P), 'the other host\'s page')
need('The capsule redirects more than 5 times:|Veranda Gemini stopped.' in bx, 'the loop: %s' % bx)
need(any(l.startswith('GE STATUS Redirected to %ssub/page.gmi' % B) for l in log), 'the redirect\'s status')
ok('30 (relative: sub/page.gmi) followed; 31 to gemini://localhost:%d/...: the box "The capsule sends you to another '
   'host.", Yes: followed; a loop: 6 requests, the box "redirects more than 5 times"' % PORT)
need('51 Not found.|Not found here' in bx, '51: %s' % bx)
need('This capsule asks for a client certificate:|Veranda Gemini has none (not supported).' in bx, '60: %s' % bx)
need('Web pages are off (File > Settings...):|https://example.com/page.html' in bx, 'the web: %s' % bx)
need('An e-mail address:|someone@example.com' in bx, 'mail: %s' % bx)
ok('51: "51 Not found." and the meta; 60: "client certificate ... not supported"; the web link and the mail link: '
   'their boxes, nothing fetched')

# ---------------------------------------------------------------- plain text, Latin-1
pl = [p for p in P if p[0] == B + 'plain.txt']
pm = model(open(os.path.join(F, 'plain.txt'), 'rb').read().decode('utf-8'), 'plain')
need(pl, 'the plain text')
same(pl[0][1], pm.render(), 'the plain text')
la = [p for p in P if p[0] == B + 'latin1.gmi']
lm = model(open(os.path.join(F, 'latin1.gmi'), 'rb').read().decode('latin-1'))
need(la, 'the Latin-1 page')
same(la[0][1], lm.render(), 'the Latin-1 page')
ok('text/plain; charset=utf-8: %d rows (12 pixels), wrapped at 76, tabs to 8; text/gemini; charset=ISO-8859-1: '
   'its accents in Veranda\'s set (V143)' % len(pm.rows))

# ---------------------------------------------------------------- the download
big = open(os.path.join(F, 'big.bin'), 'rb').read()
dl = os.path.join(R, 'DOCUMENTS', 'big.bin')
need(os.path.exists(dl), 'no DOCUMENTS/big.bin')
need(open(dl, 'rb').read() == big, 'big.bin is not equal (%d bytes)' % os.path.getsize(dl))
need('Download big.bin (application/octet-stream)|to /DOCUMENTS?' in bx, 'the download\'s box: %s' % bx)
at, back = val('GE ALT+TAB AT '), val('GE BACK AT ')
need(at and back and 'GE ASIDE' in raw and 'GE FILE REOPENED' in raw, 'Alt+Tab: %s %s' % (at, back))
ok('a binary (20 application/octet-stream): the box "Download big.bin ... to /DOCUMENTS?", Yes: 40,960 bytes, equal; '
   'Alt+Tab at byte %d (aside, the file closed, the desktop, back, reopened)' % at)

# ---------------------------------------------------------------- Esc, Find, bookmarks
sl = [p for p in P if p[0] == B + 'slow']
need(sl and len(sl[0][1]) >= 2 and 'GE TEST STOPPED' in log, 'the page that stalls: %s' % sl)
need(any(l.startswith('GE STATUS ') and 'stopped' in l for l in log), 'no "stopped"')
ok('a page that stalls: its first rows shown as they came, Esc: stopped (%d rows)' % len(sl[0][1]))
fr = val('GE TEST FOUND ')
need(fr is not None and fr < len(root.rows) and 'needle' in root.render()[fr][1], 'Find: row %s' % fr)
need('Find in this page:|' in bx, 'Find\'s box: %s' % bx)
ok('File > Find...: "needle" on row %d' % (fr + 1))
marks = open(os.path.join(R, 'VERANDA', '.SYSTEM', 'GEMINI.MARKS'), 'rb').read()
wantm = ''.join(m + '\r\n' for m in KEPT + ['=> %s Veranda Gemini\'s gate' % B]).encode()
need(marks == wantm, 'GEMINI.MARKS: %r' % marks)
need('Remove the bookmark|gemi.dev' in bx, 'the remove box: %s' % bx)
mp = [p for p in P if p[0] == '']
need(len(mp) >= 3, 'the bookmarks pages: %d' % len(mp))
same(mp[1][1], model(marks_text(DEFAULTS + ['=> %s Veranda Gemini\'s gate' % B])).render(), 'the bookmarks page with the new one')
same(mp[2][1], model(marks_text(KEPT + ['=> %s Veranda Gemini\'s gate' % B])).render(), 'the bookmarks page after Remove')
ok('Bookmarks > Add this page (the root, named by its first heading); Go > Home: the page with it; Tab to gemi.dev, '
   'Bookmarks > Remove..., Yes: GEMINI.MARKS the 7 other defaults and the new one (CR LF)')

# ---------------------------------------------------------------- web pages (V124)
WB = 'Open the web page https://example.com/page.html'
need(bx.count(WB) == 3, 'the web page\'s box (Yes, No, Cancel): %d %s' % (bx.count(WB), bx))
wf = [p for p in P if p[0] == B + 'cgi-bin/waffle.cgi/view?https%3A%2F%2Fexample.com%2Fpage.html']
need(wf and wf[0][1] == as_console(model('# NewsWaffle\nThe page: https://example.com/page.html\n').render()),
     'NewsWaffle\'s page: %s' % wf)
ok('the web link (https://example.com/page.html): the box "Open the web page ... Yes: through NewsWaffle, No: '
   'through my proxy, Cancel"; Yes: the request %scgi-bin/waffle.cgi/view?https%%3A%%2F%%2Fexample.com%%2Fpage.html '
   '(NewsWaffle\'s /view with the URL percent-encoded as its query; here a stand-in named in GEMINI.CFG), its page' % B)
wg = open(os.path.join(F, 'web.gmi'), 'rb').read().decode('utf-8')
wm = model(wg)
wp_ = [p for p in P if p[0] == 'https://example.com/page.html']
need(wp_, 'the proxied page was not shown: %s' % [p[0] for p in P])
same(wp_[0][1], wm.render(), 'the page through the proxy')
need(wg.startswith('# Tomatoes on a Balcony\n'), 'the converted page: %r' % wg[:60])
need(val('GE TEST PROXY LINK BOXES ') == 0, 'a link on the proxy\'s page asked: %s' % val('GE TEST PROXY LINK BOXES '))
need(any(p[0] == 'https://example.com/varieties/cherry' for p in P), 'the link on the proxied page')
ok('No: the request line https://example.com/page.html (the absolute URL: a Gemini proxy request) to the proxy; '
   'tests/web/article.html converted by tools/web_proxy.py and shown: %d rows equal to the model\'s (web.png); its '
   'link "[1] cherry variety" followed through the proxy without a box' % len(wm.rows))
need(val('GE TEST CANCELLED ') is not None and val('GE TEST TYPED BOXES ') == 0, 'Cancel, the typed address')
need(any(b.startswith('Web pages (now 0): 0 ask each time') for b in bx) and any(b.startswith('Web pages (now 2)') for b in bx) and any(b.startswith('Pictures: the largest') for b in bx) and any(b.startswith('My proxy, host:port') for b in bx),
     'the setting\'s boxes: %s' % bx)
cfg = open(os.path.join(R, 'VERANDA', '.SYSTEM', 'GEMINI.CFG'), 'rb').read()
wantc = ('web=3\r\nproxy=localhost:%d\r\npictures=56\r\nwplang=pl\r\nwaffle=gemini://127.0.0.1:%d/cgi-bin/waffle.cgi/view\r\n'
         'wiki=gemini://127.0.0.1:%d/cgi-bin/wp.cgi\r\n' % (PORT, PORT, PORT)).encode()
need(cfg == wantc, 'GEMINI.CFG: %r' % cfg)
ok('Cancel: nothing fetched; File > Settings... 2 (always my proxy): https://example.com/typed typed in the '
   'address line went through the proxy, no box; 3 (never): the link\'s box "Web pages are off"; GEMINI.CFG %r' % cfg)

# ---------------------------------------------------------------- Wikipedia (V128)
WL = 'Look up in Wikipedia:|'
need(bx.count(WL) == 1 and 'Look up in Wikipedia (pl):|' in bx, 'Wikipedia\'s boxes: %s' % [b for b in bx if 'Wikipedia' in b])
for lang, t, u in (('en', 'Ada Lovelace', 'view?Ada%20Lovelace'), ('en', 'Gemini (protocol)', 'view?Gemini%20%28protocol%29'),
                   ('pl', 'Warszawa', 'view/pl?Warszawa')):
    pg = [p for p in P if p[0] == WPB + u]
    need(pg, 'the article %s was not shown' % t)
    same(pg[0][1], wiki_page(lang, t).render(), 'the article ' + t)
sr = [p for p in P if p[0] == WPB + 'search?no+such+thing']
need(sr, 'the search after the redirect: %s' % [p[0] for p in P][-8:])
same(sr[0][1], model(open(os.path.join(F, 'wiki-search.gmi'), 'rb').read().decode('utf-8')).render(), 'the search')
lb = [b for b in bx if b.startswith("Wikipedia's language (now ")]
need(len(lb) == 3 and all(b.startswith("Wikipedia's language (now en): a code, such as en,|pl, de or fr:") for b in lb), 'the language\'s boxes: %s' % lb)
need(cfg.find(b'wplang=pl\r\n') > 0, 'GEMINI.CFG: no wplang=pl')
ok('Wikipedia through Gemipedia (V128; a stand-in at %s, named in GEMINI.CFG\'s wiki=): Go > Wikipedia...: the box '
   '"Look up in Wikipedia:", "Ada Lovelace": the request %sview?Ada%%20Lovelace (Gemipedia\'s article route, the '
   'text percent-encoded as its query), the article (%d rows equal to the model\'s; wiki.png); "wp Gemini (protocol)" '
   'typed in the address line: view?Gemini%%20%%28protocol%%29; "w no such thing": view?no%%20such%%20thing, its 30 to '
   'search?no+such+thing (as Gemipedia redirects) followed; File > Settings... Wikipedia\'s language "PL": pl (GEMINI.CFG '
   'wplang=pl); "wp" alone: the box "Look up in Wikipedia (pl):", "Warszawa": view/pl?Warszawa, the Polish article '
   '(its letters in Veranda\'s set)' % (WPB, WPB, len([p for p in P if p[0] == WPB + 'view?Ada%20Lovelace'][0][1])))

bp, bc = val('GE BENCH PAGE '), val('GE BENCH CACHE ')
need(bp is not None and bc is not None, 'no timings')
ok('the timings (frames of 1/60 s, a mean of 4): the root\'s page drawn (25 rows of 16 pixels) %.1f; the page read back '
   'from the cache and parsed (1,403 bytes) %.1f' % (bp / 4, bc / 4))

# ---------------------------------------------------------------- the modem, the loop
CLOSED = int(open(os.path.join(R, 'srv', 'ready')).read().split()[1])
tls = [a for a in atc if a.startswith('ATCS"') and a != 'ATCS"127.0.0.1:%d"' % CLOSED]
refused = [l for l in mlog if l.startswith('ERROR connect 127.0.0.1:%d:' % PORT)]
closed = [a for a in atc if a == 'ATCS"127.0.0.1:%d"' % CLOSED]
need(len(refused) == 1 and len(closed) == 2, 'the refused connections: %s, to the closed port: %d' % (refused, len(closed)))
need(tls and len(tls) == len(slog) + 1 and all(a in ('ATCS"127.0.0.1:%d"' % PORT, 'ATCS"localhost:%d"' % PORT) for a in tls),
     'the connections: %s (requests %d)' % (atc[:4], len(slog)))
seq = []                                # (each ATCS to the server, and whether it was refused)
for l in mlog:
    if l.startswith('@') and ' ' in l and l.split(' ', 1)[1] in ('ATCS"127.0.0.1:%d"' % PORT, 'ATCS"localhost:%d"' % PORT):
        seq.append([l.split(' ', 1)[1], False])
    elif l.startswith('ERROR connect 127.0.0.1:%d:' % PORT) and seq:
        seq[-1][1] = True
need([a for a, _ in seq] == tls and sum(1 for _, r in seq if r) == 1, 'the refused connection in order: %s' % seq[:3])
tls = [a for a, r in seq if not r]      # (the one refused: its request came on the next)
for a, u in zip(tls, slog):
    need((a == 'ATCS"localhost:%d"' % PORT) == (u.startswith('http') or u.startswith('gemini://localhost')),
         'a connection\'s host: %s for %s' % (a, u))
sec = sum(1 for l in mlog if 'SECURE' in l)
need(sec == sum(1 for a in atc if a.startswith('ATCS')), 'SECURE in the modem\'s log: %d' % sec)
# (V138) every connection the server closed hung up (ATH<id>) before the next ATCS
eofs, bad = [], []
for l in mlog:
    if l.startswith('NO CARRIER '):
        eofs.append(l.split()[2])
    elif l.startswith('@') and ' ATH' in l and l.split(' ', 1)[1][3:] in eofs:
        eofs.remove(l.split(' ', 1)[1][3:])
    elif l.startswith('@') and ' ATCS' in l and eofs:
        bad.append((eofs[:], l))
need(not bad, 'an ATCS before the one before\'s ATH: %s' % bad[:2])
nhang = sum(1 for l in mlog if l.startswith('NO CARRIER '))
gap = val('GE MAXGAP ')
need(val('GE LOST ') == 0 and val('GE OE ') == 0 and val('GE BADCRC ') == 0, 'the UART lost bytes')
ok('%d connections the server closed (NO CARRIER), each hung up with ATH<id> before the next ATCS (V138)' % nhang)
ok('%d connections, each ATCS"host:port" (the modem\'s TLS; the emulator\'s SECURE, plain TCP); the main loop\'s '
   'longest gap %s frames (boxes excluded); %s packets, %s XON retries; nothing lost, no bad CRC'
   % (len(tls), gap, val('GE PACKETS '), val('GE XONRETRY ')))

# ---------------------------------------------------------------- pictures (V125)
groups, cur_pic = {}, None
for l in log:
    m = re.search(r'GE PIC (\w+)$', l)
    if m and m.group(1) == 'exits':     # (V196: small.png shown again and again: not its group)
        cur_pic = None
        continue
    if m and m.group(1) in PICS + JPICS + GAL:
        cur_pic = m.group(1)
        groups[cur_pic] = {'rows': [], 'shown': []}
        continue
    m = re.search(r'GE IROW (\d+) (\d+)$', l)
    if m and cur_pic:
        groups[cur_pic]['rows'].append((int(m.group(1)), int(m.group(2))))
    m = re.search(r'GE PIC SHOWN (\d+)$', l)
    if m and cur_pic:
        groups[cur_pic]['shown'].append(int(m.group(1)))
need(sorted(groups) == sorted(PICS + JPICS + GAL), 'the pictures tried: %s' % sorted(groups))
done, jdone = [], []
for k, name in list(enumerate(PICS[:10] + ['photo'])) + [(17 + j, GAL[j]) for j in range(4)]:
    jpg = name in ('photo', 'wawel')    # (V192: the gallery's Wawel is jpeg_ref's p422)
    data = jpeg_ref.make('p422' if name == 'wawel' else name) if jpg else png_ref.make(name)
    g = groups[name]
    need(g['shown'], '%s was not shown' % name)
    if name != 'comic' and not jpg:
        ref = png_ref.row_sums(data)
        need([y for y, _ in g['rows']] == list(range(len(ref))), '%s: its rows %s' % (name, [y for y, _ in g['rows']][:8]))
        bad = [y for y, s in g['rows'] if s != ref[y]]
        need(not bad, '%s: rows %s decoded unlike the reference (row %d: %d, not %d)'
             % (name, bad[:6], bad[0] if bad else 0, g['rows'][bad[0]][1] if bad else 0, ref[bad[0]] if bad else 0))
    d = open(os.path.join(R, 'P%s.DMP' % ('J' if k == 10 else chr(48 + k))), 'rb').read()
    w, h, ow, oh = (int.from_bytes(d[i:i + 2], 'little') for i in (0, 2, 4, 6))
    mode, tw, th, tx, ty = d[8:13]
    pal = [int.from_bytes(d[13 + 2 * i:15 + 2 * i], 'little') & 0xFFF for i in range(16)]
    m, cols, rw, rh, rtw, rth, rtx, rty, out = (jpeg_ref if jpg else png_ref).shown(data)
    iw, ih = (jpeg_ref.parse(data)['w'], jpeg_ref.parse(data)['h']) if jpg else png_ref.info(data)[:2]
    need((w, h, ow, oh, mode, tw, th, tx, ty) == (iw, ih, rw, rh, m, rtw, rth, rtx, rty),
         '%s: shown as %s, the reference %s' % (name, (w, h, ow, oh, mode, tw, th, tx, ty), (iw, ih, rw, rh, m, rtw, rth, rtx, rty)))
    need(pal == cols, '%s: palette row 2 %s, the reference %s' % (name, pal, cols))
    tiles = d[45:]
    need(len(tiles) == tw * th * 32, '%s: %d bytes of tiles' % (name, len(tiles)))
    for y in range(th * 8):
        for x in range(tw * 8):
            b = tiles[((y >> 3) * tw + (x >> 3)) * 32 + (y & 7) * 4 + ((x & 7) >> 1)]
            v = b >> 4 if not x & 1 else b & 15
            if v != out[y][x]:
                sys.exit('FAIL  %s: the shown picture at %d,%d is %d, the reference %d' % (name, x, y, v, out[y][x]))
    (jdone if jpg else done).append('%s %dx%d -> %dx%d (%s, %.1f s)' % (
        name, w, h, ow, oh, ('grey', 'colour', 'palette')[mode], g['shown'][-1] / 60))
ok('pictures shown (tests/png_ref.py\'s, through the server): each row decoded equal to the reference decoder '
   '(r + 2g + 3b summed, before scaling), the tiles in VRAM index for index the reference\'s scaling and dither, '
   'palette row 2 its colours: ' + '; '.join(done))
ok('JPEG pictures shown (V192: tests/jpeg_ref.py\'s, through the server, decoded with VERA FX\'s multiplier): the '
   'tiles in VRAM index for index the reference\'s, the size, the colours: ' + '; '.join(jdone))
c = groups['comic']
need(val('GE PIC ASIDE AT ') and 'GE ASIDE' in raw and len(c['shown']) == 1, 'the comic and Alt+Tab: %s' % c)
need(val('GE PIC HANDLES ') == 2, 'a stream left open before the comic: %s' % val('GE PIC HANDLES '))
ok('the comic (740 x 300 grey, %d bytes): Alt+Tab at row %d while drawn (the file closed), drawn again from its start '
   'when back; decoded and shown in %d frames: %.1f s at 8 MHz (without the test\'s sums)'
   % (len(png_ref.make('comic')), val('GE PIC ASIDE AT '), c['shown'][0], c['shown'][0] / 60))
bx = boxes()
for b in ('Interlaced PNG pictures are not shown here:|save it (File > Download).', 'The picture is damaged.|',
          'The picture is larger than 56 KB (the limit).|Save it to /DOCUMENTS instead?',
          "Progressive JPEGs aren't shown here:|save it (File > Download)."):
    need(b in bx, 'the box %r: %s' % (b, bx[-12:]))
need(any(b.startswith('The picture gemini://') and 'pal4.png' in b for b in bx), 'Return\'s box: %s' % bx[-6:])
for name in ('pal4', 'rgb'):
    f = os.path.join(R, 'DOCUMENTS', name + '.png')
    need(os.path.exists(f) and open(f, 'rb').read() == png_ref.make(name), '/DOCUMENTS/%s.png' % name)
need(not os.path.exists(os.path.join(R, 'VERANDA', '.SYSTEM', 'GEMINI.TMP')), 'GEMINI.TMP left behind')

# ---------------------------------------------------------------- the ways out of a picture (V196)
shown_c = dict(re.findall(r'GE EXIT SHOWN (\w+) (\d+)$', raw, re.M))
after = {m[0]: tuple(int(x) for x in m[1:]) for m in re.findall(r'GE EXIT (\w+) (\d+) (\d+) (\d+)$', raw, re.M)}
need(sorted(shown_c) == sorted(EXITS) and sorted(after) == sorted(EXITS), 'the ways out tried: %s, %s' % (shown_c, after))
for e in EXITS:
    need(after[e][:2] == (0, 0), '%s: the picture still shown after it (viewing %d, the address line %d)'
         % (e, after[e][0], after[e][1]))
    need(shown_c[e] == '2' and after[e][2] != 2, '%s: layer 0 %s while shown, %d after (2: 4 bpp, tile mode)'
         % (e, shown_c[e], after[e][2]))
need('GE EXIT ASIDE BACK' in raw, 'Alt+Tab while the picture was shown')
ok('the ways out of a picture (small.png, V196): the wheel, a click on it, Backspace, the toolbar\'s Back, the wheel '
   'after Alt+Tab, a key ("x": the address line, Esc), Go > Reload: each time the page again at once (the viewer off, '
   'tile mode off: layer 0 4 bpp while shown, 1 bpp after), and the link clicked next followed (small.png shown '
   'again; after the last, the gallery)')

# ---------------------------------------------------------------- Gemipedia's gallery (V138)
gp = [p for p in P if p[0] == WPB + 'images?Poland']
need(gp, 'the gallery was not shown: %s' % [p[0] for p in P][-6:])
gm = model(gal_t).render()
same(gp[0][1], gm, 'the gallery')
shows = [t.strip() for k, t in as_console(gm) if t.endswith('[Show image]')]
need(len(shows) == 4 and not any(t.startswith('Image: a map') for t in shows), 'the gallery\'s [Show image]: %s' % shows)
need(len(gal_links[2]) == 281 and len(B) + len(gal_links[2]) - 1 > 255, 'the long link: %d' % len(gal_links[2]))
rt = [l for l in log if l.endswith('GE RETRY')]
need(len(rt) == 2, 'the retries: %d' % len(rt))
ub = 'Could not connect: refused, or no such host.|' + ('gemini://127.0.0.1:%d/cgi-bin/wp.cgi/media/media.png?https' % CLOSED)[:48] + '...'
need(ub in bx, 'the unreachable picture\'s box %r: %s' % (ub, bx[-6:]))
need(not any(b.startswith("JPEG can't be shown here") for b in bx), 'a JPEG box: %s' % bx[-8:])
ok('Gemipedia\'s image gallery (its stand-in: GalleryRenderer\'s lines, MediaProxyUrl\'s links '
   '/cgi-bin/wp.cgi/media/media<ext>?<the Wikimedia thumbnail\'s URL UrlEncode\'d>): the page as the model renders it '
   '(%d rows; [Show image] on the 4 links whose path ends .png or .jpg before the query); the flag: its first '
   'connection refused (the server not listening), "GE RETRY", tried again a second later and shown; a link of %d '
   'characters (%d resolved: rel cut at 128, the rest sent from the page): its request whole, shown; a link with no '
   'extension answering image/png: shown by its type; the JPEG: shown (V192); a closed port: tried twice, then '
   '"%s"' % (len(gm), len(gal_links[2]), len(B) + len(gal_links[2]) - 1, ub))

ok('interlaced: refused ("save it"); damaged: its box; over the limit (56 KB): "Save it instead?" (No); a '
   'progressive JPEG: refused ("save it"); Return on pal4.png: Show/Save/Cancel, No: /DOCUMENTS/pal4.png '
   'equal; rgb.png shown, the toolbar\'s Save: /DOCUMENTS/rgb.png equal; GEMINI.TMP deleted')
st = val('GE STACK ')
need(st is not None and st < 0x300, 'the C stack: %s bytes of %s' % (st, val('GE STACKSIZE ')))
ok('the C stack\'s deepest: %d bytes (of its 1,024)' % st)
