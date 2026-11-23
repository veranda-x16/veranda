#!/usr/bin/env python3
"""Gate gopher (DECISIONS V109): Veranda Gopher's sessions checked (tools/
gate_gopher.sh): the console's "GO ..." lines (tests/gopher_play.c and the
test build's own), the server's log (tests/gopher_server.py), the modem's
log, the files on the card.

usage: check_gopher.py <session> <run folder> <port> <closed port>
"""
import os
import re
import sys

SESS, R, PORT, CPORT = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
raw = open(os.path.join(R, 'log.txt'), encoding='utf-8', errors='replace').read()   # (the console: UTF-8)
log = raw.split('\n')


def need(c, msg):
    if not c:
        sys.exit('FAIL  ' + msg)


def ok(msg):
    print('ok    ' + msg)


def val(key):
    m = re.search(r'^%s(-?\d+)$' % re.escape(key), raw, re.M)
    return int(m.group(1)) if m else None


# (V143) a server's text as doc.c's doc_text keeps it: UTF-8 (a byte that
# is not, Latin-1), the font's private box glyphs ($80-$9F), quotes and
# dashes plain, Veranda's set (ISO-8859-16), else '?'
PRIV = [0xE3, 0xFE, 0xFB, 0xB0, 0xB1, 0xB2, 0xB3, 0xB4, 0xBF, 0xC0, 0xC1, 0xC2, 0xC3, 0xC4, 0xC5, 0xD9,
        0xDA, 0xDB, 0xDC, 0xDD, 0xDE, 0xDF, 0xBA, 0xCD, 0xC9, 0xBB, 0xC8, 0xBC, 0xCC, 0xB9, 0xCB, 0xCA]
PV = {ord(bytes([b]).decode('cp437')): 0x80 + i for i, b in enumerate(PRIV)}


def cpt(u):
    if u in (0x2018, 0x2019):
        return 39
    if u in (0x201C, 0x201D, 0x201E):
        return 34
    if u in (0x2013, 0x2014):
        return 45
    if u == 0x2026:
        return 46
    if u in PV:
        return PV[u]
    if 0x80 <= u < 0xA0:
        return 63
    try:
        return chr(u).encode('iso8859_16')[0]
    except UnicodeEncodeError:
        return 63


def conv(data):
    out, i = bytearray(), 0
    while i < len(data):
        c = data[i]
        n = 1 if 0xC2 <= c < 0xE0 else 2 if 0xE0 <= c < 0xF0 else 3 if 0xF0 <= c < 0xF5 else 0
        seq = data[i + 1:i + 1 + n]
        if c < 0x80:
            out.append(c)
        elif n and len(seq) == n and all(b & 0xC0 == 0x80 for b in seq):
            out.append(63 if n == 3 else cpt(ord(data[i:i + 1 + n].decode('utf-8'))))
            i += n
        else:
            out.append(63 if c < 0xA0 else cpt(c))
        i += 1
    return bytes(out)


def con(c):
    """a byte as the console shows it (EMU_STDOUT: $A1-$FF as ISO-8859-15)"""
    return chr(c) if c < 0x80 else bytes([c]).decode('iso8859_15') if c >= 0xA1 else '\ufffd'


def pages():
    """every page logged: [(address, [lines], (lines, full, bytes))]"""
    out, cur = [], None
    for l in log:
        if l.startswith('GO PAGE END '):
            if cur:
                cur[2] = tuple(int(x) for x in l[12:].split())
                out.append(tuple(cur))
            cur = None
        elif l.startswith('GO PAGE '):
            cur = [l[8:], [], None]
        elif l.startswith('GO L') and cur is not None:
            cur[1].append(l[5:] if len(l) > 4 else '')
    return out


def boxes():
    return [l[7:] for l in log if l.startswith('GO BOX ')]


need('GO TEST STUCK' not in raw and 'GO TEST FAILED' not in raw,
     'the test stopped: %s' % re.findall(r'GO TEST (?:STUCK|FAILED)[^\n]*', raw))
need('GO END' in log, 'no end')

if SESS == 'nomodem':
    need(any(b.startswith('The modem does not answer.|') for b in boxes()), 'no modem: the boxes %s' % boxes())
    ok('no modem on the port: the address typed, the box "The modem does not answer." (vrnet: NET_ENOMODEM)')
    sys.exit(0)

slog = [l[4:] for l in open(os.path.join(R, 'srv', 'gopher.log'), encoding='latin-1').read().split('\n')
        if l.startswith('SEL ')]
mlog = open(os.path.join(R, 'modem.log'), encoding='latin-1').read().split('\n')
ats = [l.split(' ', 1)[1] for l in mlog if l.startswith('@')]
atc = [a for a in ats if a.startswith('ATC"')]
need(all(a.startswith('ATC"127.0.0.1:') for a in atc), 'ATC: %s' % atc[:3])
P = pages()

if SESS == 'reread':
    need(P and P[0][0] == '', 'the first page is not the bookmarks page: %s' % (P[:1],))
    want = ['iYour bookmarks: click one. Bookmarks > Add this page adds one.', 'i', '1Gate root', '0Gate text']
    need(P[0][1] == want, 'the bookmarks read back: %s' % P[0][1])
    need(slog == [''], 'the selectors: %s' % slog)
    need(len(P) == 2 and P[1][0] == 'gopher://127.0.0.1:%d/' % PORT, 'the bookmark followed: %s' % [p[0] for p in P])
    ok('GOPHER.MARKS written as on a PC (LF only, a line that is not an item) read back: its two items listed, '
       '"Gate root" followed (selector "", 127.0.0.1:%d): the root menu' % PORT)
    sys.exit(0)

# ---------------------------------------------------------------- main
D = os.path.join(R, 'srv', 'files')
book0 = ['iYour bookmarks: click one. Bookmarks > Add this page adds one.', 'i',
         '1Floodgap Systems', '7Veronica-2: search Gopherspace', '1Quux.org',
         '1SDF Public Access UNIX System', '1Bitreich']
need(P[0][0] == '' and P[0][1] == book0, 'the bookmarks page (the defaults): %s' % (P[0],))
ok('no GOPHER.MARKS: the bookmarks page shows the defaults (Floodgap, Veronica-2, Quux.org, SDF, Bitreich)')

ROOT = 'gopher://127.0.0.1:%d/' % PORT
root = ['iWelcome to the gate\'s Gopher server.', 'i', '1A submenu', '0A text file', '0A long text',
        '7Search the gate', '9A binary file', 'gA picture', 'hThe web',
        '3An error line: this item is gone', '1A closed port', '1A menu that stalls',
        ''.join(con(c) for c in conv('i╔══╗ box lines ░▒▓'.encode())),
        ''.join(con(c) for c in conv('iPolish (V143): Zażółć gęślą jaźń, ZAŻÓŁĆ GĘŚLĄ JAŹŃ'.encode()))]
roots = [p for p in P if p[0] == ROOT]
need(roots and roots[0][1] == root, 'the root menu: %s' % (roots[:1],))
need(all(p[1] == root for p in roots), 'the root menu again')
need(roots[0][2][1] == 0, 'the root: cut?')
ok('the address typed (gopher://127.0.0.1:%d/1): the root menu, %d lines: info lines (one empty, one of box lines and one of Polish in UTF-8: V143), '
   'the marks DIR TXT ? BIN IMG WWW ERR, Gopher\'s "." dropped; shown %d times (Back, the item '
   'with no host)' % (PORT, len(root), len(roots)))

sub = [p for p in P if p[0] == ROOT + '1/sub']
need(len(sub) == 2 and sub[0][1] == ['iThe submenu', '0The text again', '1Back to the top'],
     'the submenu: %s' % sub)
need(val('GO TEST BACK SEL ') == 2, 'Back: the selection kept (%s)' % val('GO TEST BACK SEL '))
need(val('GO TEST HPOS ') == 3 and val('GO TEST HN ') == 4, 'the history: %s %s' % (val('GO TEST HPOS '), val('GO TEST HN ')))
ok('a submenu followed (a click); the toolbar\'s Back: the root, its selection where it was; Go > Forward: the '
   'submenu; "Back to the top" (no host, no port: the page\'s server): the root, a new entry (the history: '
   '4 entries, the 4th shown, Forward\'s dropped)')


def wrap(data, w=76):                   # (WRAPW: 78 before V149's Sunroom scroll bar)
    """doc.c's wrap: the starts of the lines shown, then the lines rendered"""
    starts, ls, sp, col, spcol = [0], 0, 0, 0, 0
    for o, c in enumerate(data):
        if c == 10:
            col = 0
            starts.append(o + 1)
            ls, sp = o + 1, 0
            continue
        if c == 13:
            continue
        nc = (col | 7) + 1 if c == 9 else col + 1
        if nc > w:
            if sp > ls:
                col -= spcol
                starts.append(sp)
                ls, sp = sp, 0
            else:
                col = 0
                starts.append(o)
                ls, sp = o, 0
            nc = (col | 7) + 1 if c == 9 else col + 1
            nc = min(nc, w)
        col = nc
        if c in (32, 9):
            sp, spcol = o + 1, col
    if starts[-1] >= len(data):
        starts.pop()
    lines = []
    for i, s in enumerate(starts):
        e = starts[i + 1] if i + 1 < len(starts) else len(data)
        b = data[s:e].split(b'\n')[0].replace(b'\r', b'')
        row, col = [' '] * 76, 0
        for c in b:
            if col >= 76:
                break
            if c == 9:
                col = (col | 7) + 1
                continue
            row[col] = con(c)
            col += 1
        lines.append(''.join(row).rstrip(' '))
    if lines and lines[-1] == '.':
        lines.pop()
    return lines


TEXT = conv(open(os.path.join(D, 'text.txt'), 'rb').read() + b'.\r\n')
want = wrap(TEXT)
tx = [p for p in P if p[0] == ROOT + '0/text.txt']
need(tx and tx[0][1] == want, 'the text: %s\nwanted %s' % (tx[0][1] if tx else None, want))
need(any(len(l) == 76 for l in want) and any(l.startswith('word.') or l.startswith('spaces,') for l in want), 'the text has no wrapped lines?')
ok('a text: %d lines as wrapped at 76 columns (a paragraph at its spaces, a 98-character word cut), tabs to '
   'columns of 8, CR LF and LF, UTF-8 (box lines, Polish) and Latin-1 in Veranda\'s set (V143), "." dropped; equal to the gate\'s own wrap' % len(want))

lg = [p for p in P if p[0] == ROOT + '0/long.txt']
need(lg and lg[0][2][1] == 1 and lg[0][2][2] == 49152, 'the long text: %s' % (lg[0][2] if lg else None,))
need(val('GO TEST LONG FULL ') == 1, 'the long text not cut')
lines = lg[0][2][0]
need(val('GO TEST LONG TOP ') == lines + 2 - 34, 'End: the top %s (lines %d)' % (val('GO TEST LONG TOP '), lines))
LONG = b''.join(b'Line %05d: the quick brown fox jumps over the lazy dog.\r\n' % i for i in range(1, 2000))[:49152]
need(lg[0][1] == wrap(LONG)[:80], 'the long text\'s first lines')
ok('a long text (80,000 bytes): 49,152 kept (6 RAM banks), %d lines, the rest not read (the connection closed), '
   'the note "Cut here" after them; End shows the last 34 lines (12 pixels a line)' % lines)

se = [p for p in P if p[0] == ROOT + '7/search%09veranda']
need(se and se[0][1] == ['iYou searched for: veranda', '0A result'], 'the search: %s' % [p[0] for p in P])
need('/search<TAB>veranda' in slog, 'the search\'s selector: %s' % slog)
B = boxes()
need(any(b.startswith('Search Search the gate:|') for b in B), 'the search\'s box: %s' % B)
ok('a search (7): the box "Search Search the gate:", "veranda" typed: the selector, a tab, the query sent; the '
   'results menu; its address gopher://.../7/search%09veranda')

need('A web page (Veranda Gopher shows no web pages):|http://example.com/a/page.html' in B, 'the web box: %s' % B)
need('The server says:|An error line: this item is gone' in B, 'the error line\'s box: %s' % B)
need('Could not connect to 127.0.0.1|(refused, or no such host)' in B, 'the refused box: %s' % B)
need(any(a == 'ATC"127.0.0.1:%d"' % CPORT for a in atc), 'no ATC to the closed port')
ok('a web link (h, URL:): the box with its address, nothing fetched; an error line (3): its text in a box; a '
   'port nothing listens on: "Could not connect to 127.0.0.1 (refused, or no such host)"')

need('GO TEST STALLED' in log and '/slow' in slog, 'the stall')
st = [l for l in log if l.startswith('GO STATUS') and 'stopped' in l]
need(st, 'Esc: no "stopped"')
ok('a menu that stalls: its first lines shown as they came, Esc: stopped at once (%s)' % st[0][10:])

alt = val('GO ALT+TAB AT ')
need(alt is not None and 0 < alt < 40960, 'Alt+Tab at %s' % alt)
need('GO ASIDE' in log and 'GO FILE REOPENED' in raw, 'aside, reopened')
need('Download big.bin|to /DOCUMENTS?' in B, 'the download\'s box')
need(val('GO TEST DOWNLOADED ') == 40960, 'downloaded %s' % val('GO TEST DOWNLOADED '))
got = open(os.path.join(R, 'DOCUMENTS', 'big.bin'), 'rb').read()
need(got == open(os.path.join(D, 'big.bin'), 'rb').read(), 'big.bin differs (%d bytes)' % len(got))
ok('the binary (9) followed: the box "Download big.bin to /DOCUMENTS?", Yes: 40,960 bytes, equal byte for byte; '
   'Alt+Tab at byte %d: put aside (vrnet\'s aside, the file closed), the desktop 3 s, back (the file opened '
   'again at its place), on to the end' % alt)
got = open(os.path.join(R, 'DOCUMENTS', 'pic.gif'), 'rb').read()
need(got == open(os.path.join(D, 'pic.gif'), 'rb').read() and val('GO TEST PICTURE ') == 3000, 'pic.gif differs')
ok('the picture (g) selected with Down, File > Download: 3,000 bytes, equal')

need('GO STATUS Bookmark added: Back to the top' in raw, 'Add this page')
need('Remove the bookmark|Bitreich' in B, 'the remove box: %s' % B)
mk = open(os.path.join(R, 'VERANDA', '.SYSTEM', 'GOPHER.MARKS'), 'rb').read()
wantmk = (b'1Floodgap Systems\t\tgopher.floodgap.com\t70\r\n7Veronica-2: search Gopherspace\t/v2/vs\tgopher.floodgap.com\t70\r\n'
          b'1Quux.org\t\tgopher.quux.org\t70\r\n1SDF Public Access UNIX System\t\tsdf.org\t70\r\n'
          b'1Back to the top\t\t127.0.0.1\t%d\r\n' % PORT)
need(mk == wantmk, 'GOPHER.MARKS: %r' % mk)
last = [p for p in P if p[0] == '']
need(last[-1][1] == book0[:-1] + ['1Back to the top'], 'the bookmarks page at the end: %s' % last[-1][1])
ok('Bookmarks > Add this page (the root: "Back to the top"); Go > Home: the page with it; Bitreich selected '
   'with Down, Bookmarks > Remove..., Yes: GOPHER.MARKS has the 4 other defaults and the new one (CR LF)')

# (V110) the long menu: every kind, info lines, CP437 box characters
mn = [p for p in P if p[0] == ROOT + '1/many']
want = []
for l in ''.join(con(c) for c in conv(open(os.path.join(R, 'srv', 'many.txt'), 'rb').read())).split('\r\n'):
    if l in ('.', ''):
        continue
    t, text = l[0], l[1:].split('\t')[0]
    want.append((t + ''.join('?' if ord(c) < 32 else c for c in text[:73])).rstrip(' '))   # (MTW: 75 before V149)
need(mn and mn[0][1] == want[:80], 'the long menu: %s\nwanted %s' % (mn[0][1] if mn else None, want))
ok('a long menu (/many, %d lines: a box of lines in UTF-8, info lines, 13 kinds of item four times), as the server '
   'sent it' % len(want))
bench = {k: val('GO BENCH %s ' % k) for k in ('TEXT PAGE', 'TEXT SCROLL', 'MENU PAGE', 'MENU SCROLL')}
need(all(v is not None for v in bench.values()), 'the timings: %s' % bench)
need(bench['TEXT PAGE'] <= 8 * 17 and bench['MENU PAGE'] <= 8 * 17, 'the page is slow: %s' % bench)
ok('the timings (frames of 1/60 s, a mean of 8): a text\'s page drawn %.1f, scrolled a page %.1f; a menu\'s page '
   '%.1f, scrolled %.1f' % (bench['TEXT PAGE'] / 8, bench['TEXT SCROLL'] / 8, bench['MENU PAGE'] / 8,
                            bench['MENU SCROLL'] / 8))

order = ['', '/sub', '', '/sub', '', '/text.txt', '', '/long.txt', '', '/search<TAB>veranda', '', '/slow', '',
         '/big.bin', '/pic.gif', '/many']
need(slog == order, 'the selectors: %s' % slog)
gap, lost, oe, bad, pk, xr = (val('GO MAXGAP '), val('GO LOST '), val('GO OE '), val('GO BADCRC '), val('GO PACKETS '),
                              val('GO XONRETRY '))
need(lost == 0 and oe == 0 and bad == 0, 'lost %s, overruns %s, bad CRC %s' % (lost, oe, bad))
need(gap is not None and gap < 30, 'the main loop\'s longest gap: %s frames' % gap)
ok('the server got %d selectors, in order; the main loop\'s longest gap %d frames (boxes excluded); %d packets, '
   '%d XON retries; nothing lost in the UART, no bad CRC; %d connections (ATC)' % (len(slog), gap, pk, xr, len(atc)))
