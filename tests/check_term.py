#!/usr/bin/env python3
"""gate term: check Veranda Term's screen against a reference terminal.

usage: check_term.py screen <run dir> <bytes> <rom> [--stop end|menu|dlg|back] [--title T]
       check_term.py speed <run dir> <bbs dir>
       check_term.py xmodem <run dir> <bbs dir>

screen: the bytes the host sent (the fake BBS's sent.bin, or the script's
TERM.IN) go through a reference terminal written here from the same rules
(DECISIONS, apps/term/vt.c's header): the expected 80 x 55 grid of
characters and display attributes (the card's paper colour, reverse,
bold), the cursor and the scrollback. It must equal
  - the model the test build wrote (TERM.SCR: characters, attributes,
    the cursor);
  - the window in VRAM (dump.bin): each cell the ROM's CP437 glyph (bank
    6), bold as v | v >> 1, reversed, the cursor inverted; the title (in
    the menu bar, V149: the test build logs it, as the status bar);
  - the colour map: each card's paper colour (with a menu or a dialog box
    open: the cards under it show the normal paper and keep their colour
    in the tile index, V33);
  back: the window shows the scrollback, 27 lines back.
"""
import json
import os
import sys

COLS, ROWS, TROW = 80, 55, 3
TY = TROW * 8
VRAM_LEN = 131072
TAIL = VRAM_LEN + 256 + 512 + 14 + 1024
A_COL, A_REV, A_BOLD = 0x0F, 0x10, 0x20
FGDARK = [0, 1, 2, 5, 9, 6, 4, 3, 15]
FGBRIGHT = [0, 11, 10, 13, 7, 14, 4, 3, 0]
BGLIGHT = [0, 1, 10, 13, 7, 14, 4, 3, 15]
DECGFX = [0x20, 0x04, 0xB1, 0x09, 0x0C, 0x0D, 0x0A, 0xF8, 0xF1, 0x0A, 0x0B, 0xD9, 0xBF, 0xDA,
          0xC0, 0xC5, 0xC4, 0xC4, 0xC4, 0xC4, 0x5F, 0xC3, 0xB4, 0xC1, 0xC2, 0xB3, 0xF3, 0xF2,
          0xE3, 0xD8, 0x9C, 0xFA]


def fail(msg):
    print('FAIL  ' + msg)
    sys.exit(1)


def ok(msg):
    print('ok    ' + msg)


class VT:
    """the reference: the subset of ANSI/VT100 Veranda Term takes"""

    def __init__(self, scheme=0, colour=1, crin=0):
        self.scheme, self.colour, self.crin = scheme, colour, crin
        self.fg = self.bg = self.sgr = 0
        self.mkattr()
        self.rows = [[(32, self.eattr)] * COLS for _ in range(ROWS)]
        self.hist = []
        self.x = self.y = 0
        self.wrap = 0
        self.top, self.bot = 0, ROWS - 1
        self.g = [0, 0]
        self.gl = 0
        self.state = 0
        self.sx = self.sy = 0
        self.saved = (0, 0, 0, 0, 0)
        self.curshow = 1
        self.autowrap = 1
        self.replies = []

    def mkattr(self):
        fg, bg, sgr = self.fg, self.bg, self.sgr
        dark = bg == 1 or (bg == 0 and self.scheme)
        f = fg if fg else 8
        if dark:
            a = A_REV | (FGBRIGHT[f] if sgr & 1 else FGDARK[f])
        elif bg:
            a = BGLIGHT[bg]
        else:
            a = 0
        if sgr & 1:
            a |= A_BOLD
        if sgr & 2:
            a ^= A_REV
        if not self.colour:
            a &= ~A_COL
        self.cattr = a
        a = (A_REV | FGDARK[f]) if dark else BGLIGHT[bg]
        if sgr & 2:
            a ^= A_REV
        if not self.colour:
            a &= ~A_COL
        self.eattr = a

    def clear(self, r, a, b):
        for c in range(a, b + 1):
            self.rows[r][c] = (32, self.eattr)

    def scroll(self, t, b, n):
        while n > 0:
            if t == 0:
                self.hist.append(self.rows[0])
            self.rows[t:b + 1] = self.rows[t + 1:b + 1] + [[(32, self.eattr)] * COLS]
            n -= 1
        while n < 0:
            self.rows[t:b + 1] = [[(32, self.eattr)] * COLS] + self.rows[t:b]
            n += 1

    def lf(self):
        if self.y == self.bot:
            self.scroll(self.top, self.bot, 1)
        elif self.y < ROWS - 1:
            self.y += 1

    def ri(self):
        if self.y == self.top:
            self.scroll(self.top, self.bot, -1)
        elif self.y:
            self.y -= 1

    def glyph(self, c):
        if self.wrap:
            self.wrap = 0
            self.x = 0
            self.lf()
        self.rows[self.y][self.x] = (c or 32, self.cattr)
        if self.x == COLS - 1:
            self.wrap = self.autowrap
        else:
            self.x += 1

    def clamp(self):
        self.x = min(self.x, COLS - 1)
        self.y = min(self.y, ROWS - 1)
        self.wrap = 0

    def p1(self, i):
        v = self.par[i] if i < len(self.par) and self.par[i] else 1
        return min(v, 255)

    def csi(self, f):
        P = self.par
        n0 = P[0] if P else 0
        if f == 'A':
            n = self.p1(0)
            self.y = self.top if self.y >= self.top and self.y - n < self.top else max(self.y - n, 0)
            self.clamp()
        elif f in 'Be':
            n = self.p1(0)
            self.y = self.bot if self.y <= self.bot and self.y + n > self.bot else min(self.y + n, ROWS - 1)
            self.clamp()
        elif f in 'Ca':
            self.x = min(self.x + self.p1(0), COLS - 1)
            self.clamp()
        elif f == 'D':
            self.x = max(self.x - self.p1(0), 0)
            self.clamp()
        elif f == 'E':
            self.y = min(self.y + self.p1(0), ROWS - 1)
            self.x = 0
            self.clamp()
        elif f == 'F':
            self.y = max(self.y - self.p1(0), 0)
            self.x = 0
            self.clamp()
        elif f in 'G`':
            self.x = self.p1(0) - 1
            self.clamp()
        elif f == 'd':
            self.y = self.p1(0) - 1
            self.clamp()
        elif f in 'Hf':
            self.y = self.p1(0) - 1
            self.x = self.p1(1) - 1
            self.clamp()
        elif f == 'J':
            if n0 == 0:
                self.clear(self.y, self.x, COLS - 1)
                for r in range(self.y + 1, ROWS):
                    self.clear(r, 0, COLS - 1)
            elif n0 == 1:
                for r in range(self.y):
                    self.clear(r, 0, COLS - 1)
                self.clear(self.y, 0, self.x)
            else:
                for r in range(ROWS):
                    self.clear(r, 0, COLS - 1)
                self.x = self.y = 0
            self.wrap = 0
        elif f == 'K':
            if n0 == 0:
                self.clear(self.y, self.x, COLS - 1)
            elif n0 == 1:
                self.clear(self.y, 0, self.x)
            else:
                self.clear(self.y, 0, COLS - 1)
            self.wrap = 0
        elif f == 'X':
            n = min(self.p1(0), COLS - self.x)
            self.clear(self.y, self.x, self.x + n - 1)
        elif f in 'LM':
            if self.top <= self.y <= self.bot:
                n = min(self.p1(0), self.bot - self.y + 1)
                self.scroll(self.y, self.bot, -n if f == 'L' else n)
                self.x = 0
        elif f == 'S':
            self.scroll(self.top, self.bot, self.p1(0))
        elif f == 'T':
            self.scroll(self.top, self.bot, -self.p1(0))
        elif f in 'P@':
            n = min(self.p1(0), COLS - self.x)
            row = self.rows[self.y]
            if f == 'P':
                row[self.x:] = row[self.x + n:] + [(32, self.eattr)] * n
            else:
                row[self.x:] = [(32, self.eattr)] * n + row[self.x:COLS - n]
        elif f == 'm':
            if not P:
                P = [0]
            i = 0
            while i < len(P):
                v = P[i]
                if v == 0:
                    self.fg = self.bg = self.sgr = 0
                elif v == 1:
                    self.sgr |= 1
                elif v == 22:
                    self.sgr &= ~1
                elif v == 7:
                    self.sgr |= 2
                elif v == 27:
                    self.sgr &= ~2
                elif 30 <= v <= 37:
                    self.fg = v - 29
                elif v == 39:
                    self.fg = 0
                elif 40 <= v <= 47:
                    self.bg = v - 39
                elif v == 49:
                    self.bg = 0
                elif 90 <= v <= 97:
                    self.fg = v - 89
                    self.sgr |= 1
                elif 100 <= v <= 107:
                    self.bg = v - 99
                elif v in (38, 48):
                    break
                i += 1
            self.mkattr()
        elif f == 'r':
            r = self.p1(0) - 1
            n = P[1] - 1 if len(P) > 1 and P[1] else ROWS - 1
            n = min(n, ROWS - 1)
            if r < n:
                self.top, self.bot = r, n
            self.x = self.y = 0
            self.wrap = 0
        elif f == 's':
            self.sx, self.sy = self.x, self.y
        elif f == 'u':
            self.x, self.y = self.sx, self.sy
            self.clamp()
        elif f == 'h' or f == 'l':
            if self.priv:
                for v in P:
                    if v == 7:
                        self.autowrap = f == 'h'
                    elif v == 25:
                        self.curshow = f == 'h'

    def esc(self, c):
        self.state = 0
        if c == '[':
            self.state = 2
            self.par = []
            self.priv = 0
            self.inter = 0
        elif c == '(':
            self.state = 3
        elif c == ')':
            self.state = 4
        elif c in ']P_^':
            self.state = 5
        elif c in '#%':
            self.state = 6
        elif c == '7':
            self.saved = (self.x, self.y, self.fg, self.bg, self.sgr)
        elif c == '8':
            self.x, self.y, self.fg, self.bg, self.sgr = self.saved
            self.mkattr()
            self.clamp()
        elif c == 'D':
            self.lf()
        elif c == 'E':
            self.x = 0
            self.lf()
        elif c == 'M':
            self.ri()

    def put(self, c):
        s = self.state
        if s == 0:
            if c >= 32:
                if c == 127:
                    return
                if 0x5F <= c < 0x7F and self.g[self.gl]:
                    c = DECGFX[c - 0x5F]
                self.glyph(c)
                return
        elif s == 2:
            if 48 <= c <= 57:
                if not self.par:
                    self.par = [0]
                self.par[-1] = self.par[-1] * 10 + c - 48
                return
            if c == 59:
                if not self.par:
                    self.par = [0]
                if len(self.par) < 8:
                    self.par.append(0)
                return
            if 0x3C <= c <= 0x3F:
                self.priv = c
                return
            if 0x20 <= c <= 0x2F:
                self.inter = c
                return
            if 0x40 <= c <= 0x7E:
                self.state = 0
                if not self.inter:
                    self.csi(chr(c))
                return
        elif s == 1:
            if c >= 32:
                self.esc(chr(c))
                return
        elif s in (3, 4):
            if c >= 32:
                self.g[s - 3] = c == 0x30
                self.state = 0
                return
        elif s == 5:
            if c in (7, 0x9C):
                self.state = 0
            elif c == 27:
                self.state = 1
            return
        elif s == 6:
            self.state = 0
            return
        if c == 27:
            self.state = 1
        elif c in (24, 26):
            self.state = 0
        elif c == 13:
            self.x = 0
            self.wrap = 0
            if self.crin:
                self.lf()
        elif c in (10, 11, 12):
            self.lf()
        elif c == 8:
            if self.x:
                self.x -= 1
            self.wrap = 0
        elif c == 9:
            self.x = min((self.x | 7) + 1, COLS - 1)
        elif c == 14:
            self.gl = 1
        elif c == 15:
            self.gl = 0


def rom_font(rom):
    d = open(rom, 'rb').read()[6 * 16384:7 * 16384]
    smiley = bytes([0x7E, 0x81, 0xA5, 0x81, 0xBD, 0x99, 0x81, 0x7E])
    for a in range(0, 16384, 2048):
        if d[a + 8:a + 16] == smiley:
            return d[a:a + 2048]
    raise SystemExit('no CP437 set in the ROM')


def cell_bytes(font, c, a, inv=False):
    out = []
    for i in range(8):
        v = font[c * 8 + i]
        if a & A_BOLD:
            v |= v >> 1
        if a & A_REV:
            v ^= 0xFF
        if inv:
            v ^= 0xFF
        out.append(v)
    return out


def tail(dump):
    d = open(dump, 'rb').read()
    if len(d) < TAIL:
        fail('no VRAM in ' + dump)
    t = d[-TAIL:]
    return t[:VRAM_LEN], t[VRAM_LEN]


def check_window(vram, font, lines, cursor, what, cover=None):
    """lines: 55 rows of (char, attr); cursor (x, y) or None; cover: the
    cells a menu or a box may hide (left, top, right, bottom in cells)"""
    bad = 0
    hidden = 0
    for r in range(ROWS):
        for c in range(COLS):
            ch, a = lines[r][c]
            want = cell_bytes(font, ch, a, cursor == (c, r))
            if cover and cover[0] <= c <= cover[2] and cover[1] <= r <= cover[3]:
                if any(vram[(TY + r * 8 + i) * 80 + c] != want[i] for i in range(8)):
                    hidden += 1
                continue
            for i in range(8):
                y = TY + r * 8 + i
                if vram[y * 80 + c] != want[i]:
                    bad += 1
                    if bad < 6:
                        print('      row %d col %d line %d: $%02X, want $%02X (char $%02X attr $%02X)'
                              % (r, c, i, vram[y * 80 + c], want[i], ch, a))
                    break
    if bad:
        fail('%s: %d cells differ from the reference' % (what, bad))
    if cover:
        if not hidden:
            fail('%s: nothing covers the window' % what)
        ok('%s: the window equals the reference outside it (cells %d-%d, rows %d-%d: %d cells covered)'
           % (what, cover[0], cover[2], cover[1], cover[3], hidden))
        return
    ok('%s: the window equals the reference, cell for cell (80 x 55, %s)' % (what, 'the cursor inverted' if cursor else 'no cursor'))


def card_colours(vram, on):
    """(shown, own) colour per card of the window: shown = the attribute's
    background; own = the colour the card keeps (a covered card: in its
    tile index, V33)"""
    shown, own = {}, {}
    for r in range(TROW, TROW + ROWS):
        for c in range(COLS):
            if not on:
                shown[(c, r)] = own[(c, r)] = 0
                continue
            e = 0x1AC00 + (r * 128 + c) * 2
            tile, attr = vram[e], vram[e + 1]
            shown[(c, r)] = attr >> 4
            own[(c, r)] = (tile >> 4) if (tile & 15) else (attr >> 4)
    return shown, own


def screen(args):
    run, src, rom = args[0], args[1], args[2]
    stop = 'end'
    title = None
    if '--stop' in args:
        stop = args[args.index('--stop') + 1]
    if '--title' in args:
        title = args[args.index('--title') + 1]
    font = rom_font(rom)
    vt = VT()
    for b in open(src, 'rb').read():
        vt.put(b)
    # the model the test build wrote
    m = open(os.path.join(run, 'TERM.SCR'), 'rb').read()
    if len(m) != ROWS * 2 * COLS + 5:
        fail('TERM.SCR: %d bytes' % len(m))
    bad = []
    for r in range(ROWS):
        row = m[r * 160:(r + 1) * 160]
        for c in range(COLS):
            if (row[c], row[COLS + c]) != vt.rows[r][c]:
                bad.append((r, c, row[c], row[COLS + c], vt.rows[r][c]))
    for b in bad[:6]:
        print('      model row %d col %d: $%02X/$%02X, want $%02X/$%02X' % (b[0], b[1], b[2], b[3], b[4][0], b[4][1]))
    if bad:
        fail('the model: %d cells differ from the reference' % len(bad))
    cx, cy = m[-5], m[-4]
    if (cx, cy) != (vt.x, vt.y):
        fail('the cursor at %d,%d, want %d,%d' % (cx, cy, vt.x, vt.y))
    cols = sum(1 for r in vt.rows for ch, a in r if a & A_COL)
    ok('the model equals the reference terminal: 80 x 55 cells (%d with a paper colour), the cursor at %d,%d, '
       '%d lines scrolled into the scrollback' % (cols, cx, cy, len(vt.hist)))
    vram, video = tail(os.path.join(run, 'dump.bin'))
    if stop == 'back':
        back = min(27, len(vt.hist))
        allr = vt.hist + vt.rows
        start = len(vt.hist) - back
        check_window(vram, font, allr[start:start + ROWS], None, 'the scrollback (%d lines back)' % back)
        win = allr[start:start + ROWS]
        shown, own = card_colours(vram, video & 0x70 == 0x70)
        diff = [(c, r) for r in range(ROWS) for c in range(COLS) if shown[(c, r + TROW)] != win[r][c][1] & A_COL]
        if diff:
            fail('the scrollback: %d cards in another colour (the first: %s)' % (len(diff), diff[0]))
        ok('the scrollback: the colour map shows those lines\' colours (%d coloured cards)'
           % sum(1 for r in win for ch, a in r if a & A_COL))
        status = logged(run, 'TERM STATUS ')
        if ('Back %d of %d' % (back, len(vt.hist))) not in status:
            fail('the status bar: "%s", want Back %d of %d' % (status, back, len(vt.hist)))
        ok('the status bar says so (V149: the UI font; its text logged): "%s"' % status)
        return
    if stop == 'end':
        check_window(vram, font, vt.rows, (vt.x, vt.y), 'the end')
    elif stop == 'menu':        # file's sub menu: x 0-~130, y 14-85 (rows 0-7 of the window)
        check_window(vram, font, vt.rows, (vt.x, vt.y), 'the menu open', (0, 0, 17, 8))
    elif stop == 'dlg':         # the default box 224-415, 192-287, and its shadow
        check_window(vram, font, vt.rows, (vt.x, vt.y), 'the box open', (28, 21, 52, 33))
    on = video & 0x70 == 0x70
    shown, own = card_colours(vram, on)
    want = {(c, r + TROW): vt.rows[r][c][1] & A_COL for r in range(ROWS) for c in range(COLS)}
    if not on and any(want.values()):
        fail('the colour map is off')
    diff = [k for k in want if own[k] != want[k]]
    if diff:
        k = diff[0]
        fail('%d cards keep another colour than the reference (card %d,%d: %d, want %d)' % (len(diff), k[0], k[1], own[k], want[k]))
    covered = [k for k in want if shown[k] != want[k]]
    if stop == 'end':
        if covered:
            fail('%d cards show another colour (nothing covers them)' % len(covered))
        ok('the colour map: every card of the window in its colour (%d coloured)' % sum(1 for v in want.values() if v))
    else:
        if not covered or any(shown[k] for k in covered):
            fail('%s: the covered cards (%d) should show the normal paper' % (stop, len(covered)))
        xs = [k[0] for k in covered]
        ys = [k[1] for k in covered]
        ok('%s open: %d cards under it show the normal paper (cards %d-%d, %d-%d) and keep their colour in '
           'the tile index; the rest as the reference' % (stop, len(covered), min(xs), max(xs), min(ys), max(ys)))
    if title:
        t = logged(run, 'TERM TITLE ')
        if title != t:
            fail('the title: "%s", want "%s"' % (t, title))
        ok('the title: "%s" (V149: in the menu bar, the UI font, bold; logged)' % t)


def logged(run, key):
    """the last console line starting with key, without it (the test
    build logs the title and the status bar: they are in the UI font)"""
    con = open(os.path.join(run, 'console.txt'), 'rb').read().decode('latin-1').replace('\r', '\n')
    v = [l[len(key):].rstrip() for l in con.split('\n') if l.startswith(key)]
    return v[-1] if v else ''


def decode_row(vram, font, y, rev=False):
    """the text of a row of cells drawn with PutCards (plain or bold,
    reversed or not) at pixel row y"""
    glyphs = {}
    for c in list(range(32, 256)) + list(range(32)):
        for bold in (0, A_BOLD):
            for r in (0, A_REV):
                glyphs.setdefault(bytes(cell_bytes(font, c, bold | r)), c)
    s = ''
    for x in range(COLS):
        cell = bytes(vram[(y + i) * 80 + x] for i in range(8))
        c = glyphs.get(cell, ord('?'))
        s += chr(c) if 32 <= c < 127 else '.'
    return s


def speed(args):
    run, bbs = args
    cap = open(os.path.join(run, 'SPEED.TXT'), 'rb').read()
    sent = open(os.path.join(bbs, 'sent.bin'), 'rb').read()
    # (V94) the modem's rate looked for before the dial: the answers to
    # its commands (AT, ATB9600: those before the init string) are not
    # shown or captured
    cmds = json.load(open(os.path.join(bbs, 'bbs.json')))['commands']
    k = cmds.index('ATV1') if 'ATV1' in cmds else 0
    if sent[:6 * k] != b'\r\nOK\r\n' * k:
        fail('the modem\'s first %d answers are not OK: %r' % (k, sent[:6 * k]))
    sent = sent[6 * k:]
    if cap != sent:
        n = next((i for i in range(min(len(cap), len(sent))) if cap[i] != sent[i]), min(len(cap), len(sent)))
        fail('SPEED.TXT (%d bytes) differs from what was sent (%d bytes) at byte %d' % (len(cap), len(sent), n))
    log = open(os.path.join(run, 'console.txt'), errors='replace').read()
    v = {}
    for line in log.splitlines():
        if line.startswith('TERM ') and line.split()[-1].isdigit():
            v[' '.join(line.split()[1:-1])] = int(line.split()[-1])
    if v.get('LOST') or v.get('OE'):
        fail('bytes lost: %d (the ring), %d (the UART\'s overrun)' % (v.get('LOST', 0), v.get('OE', 0)))
    bps = v['BYTES'] * 60.0 / max(v['FRAMES'], 1)
    ok('capture: SPEED.TXT equals the %d bytes sent, byte for byte; none lost (ring 0, overrun 0)' % len(sent))
    ok('throughput: %d bytes from CONNECT to NO CARRIER in %d frames (%.2f s): %.0f bytes/s, %.0f%% of the line '
       '(%d UART reads)' % (v['BYTES'], v['FRAMES'], v['FRAMES'] / 60.0, bps, 100 * bps * 10 / RATE, v.get('POLLS', 0)))
    if bps * 10 < RATE * 0.9:
        fail('throughput below 90%% of the line')
    print('RATE %.0f' % bps)


RATE = 9600


def xmodem(args):
    run, bbs = args
    res = json.load(open(os.path.join(bbs, 'bbs.json')))
    for n, crc, big in ((1, True, True), (2, False, False)):
        r = res.get('xm%d' % n)
        if not isinstance(r, dict):
            fail('XMODEM file %d: %s' % (n, r))
        got = open(os.path.join(run, 'DL%d.BIN' % n), 'rb').read()
        ref = open(os.path.join(bbs, 'DL%d.REF' % n), 'rb').read()
        if got != ref:
            fail('DL%d.BIN (%d bytes) differs from the file sent (%d bytes)' % (n, len(got), len(ref)))
        if r['crc'] != crc or r['big'] != big:
            fail('XMODEM file %d: crc %s big %s' % (n, r['crc'], r['big']))
        ok('XMODEM file %d: %d bytes, %d blocks of %d, %s, %d NAK(s) answered; DL%d.BIN equals it (the ^Z padding '
           'taken off)' % (n, len(ref), r['blocks'], 1024 if big else 128, 'CRC' if crc else 'checksum', r['naks'], n))
    if res['xm1']['naks'] < 1:
        fail('XMODEM: the bad block was not refused')


def main():
    global RATE
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    if '--rate' in sys.argv:
        i = sys.argv.index('--rate')
        RATE = int(sys.argv[i + 1])
        del sys.argv[i:i + 2]
    {'screen': screen, 'speed': speed, 'xmodem': xmodem}[sys.argv[1]](sys.argv[2:])


if __name__ == '__main__':
    main()
