#!/usr/bin/env python3
"""gate edit: Veranda Edit's scripted sessions and what they must leave.

usage: edit_script.py <run folder> [--stop NAME]

Writes into the run folder the test files (BIG.TXT, about 100 KB of LF
text; HUGE.TXT, 237,800 bytes (V83: the ninth kernel bank took 16 KB; V165: the tenth 8 KB), more than application RAM; Docs/ with a
CR LF file, a CR file and an LF file with a lone CR in it; VERANDA/.SYSTEM/Text
Scrap.cvt, a styled scrap from "geoWrite"), the session EDIT.PLY for
tests/edit_play.s, and expect.json: the files the session must leave and
the states its 'L' records must log. With --stop the session ends with a
VRAM dump at that point (a screenshot).

The session, as a user would: Ctrl+O, 'b', Return (BIG.TXT through the
file chooser); text typed at the start (Ctrl+Home), in the middle (go to
line 1000, End) and at the end (Ctrl+End); find and replace all (the
dialog: Tab between its fields, Alt+A); three lines selected with
Shift+Down and deleted; "oops" typed and undone, then the deletion undone;
the styled scrap pasted (plain); two lines copied and pasted at the end
(the scrap written); saved (Ctrl+S); the mouse (a click, a drag, a double
click on a word, the wheel); a key and a page timed; Save as into Docs
through the chooser; the CR LF, LF and CR files opened (by letter, by a
double click), edited and saved; HUGE.TXT opened, edited at both ends,
saved.
"""
import json
import os
import sys

KEY_UP, KEY_DOWN, KEY_RIGHT, KEY_LEFT = 0x91, 0x11, 0x1D, 0x9D
HOME, END, PGUP, PGDN, DEL, BS, RET, TAB, ESC = 0x13, 0x04, 0x82, 0x02, 0x19, 0x14, 0x0D, 0x09, 0x1B
CTRL_HOME, CTRL_END = 0x82, 0x84        # what the kernel's key hook makes of them (with Ctrl)
SHIFT, ALT, CTRL = 1, 2, 4

WORDS = ('lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor incididunt ut '
         'labore et dolore magna aliqua Lorem enim ad minim veniam quis nostrud exercitation ullamco '
         'laboris nisi aliquip ex ea commodo consequat Duis aute irure in reprehenderit voluptate velit '
         'esse cillum fugiat nulla pariatur caf\xe9 \xfcber na\xefve LOREM').split()


def text_of(n, seed):
    """about n bytes of lines of words (LF), deterministic"""
    x = seed
    out = []
    size = 0
    line = 0
    while size < n:
        words = []
        w = 0
        target = 30 + (x >> 3) % 45
        while w < target:
            x = (x * 1103515245 + 12345) & 0x7FFFFFFF
            s = WORDS[(x >> 8) % len(WORDS)]
            words.append(s)
            w += len(s) + 1
        line += 1
        lead = '\t' if line % 17 == 0 else ''
        s = ('%s%d: ' % (lead, line)) + ' '.join(words) + '\n'
        out.append(s)
        size += len(s)
    return ''.join(out).encode('latin-1')


class Model:
    """the editor's text, cursor and selection, as the session changes them"""

    def __init__(self, t):
        self.t = bytearray(t)
        self.cur = 0
        self.anchor = 0
        self.undo = []

    def lines(self):
        return self.t.count(b'\n') + 1

    def line_start(self, p):
        return self.t.rfind(b'\n', 0, p) + 1

    def line_of(self, p):
        return self.t.count(b'\n', 0, p) + 1

    def col_of(self, p):
        c = 0
        for b in self.t[self.line_start(p):p]:
            c = (c | 7) + 1 if b == 9 else c + 1
        return c + 1

    def snap(self):
        self.undo.append(bytes(self.t))

    def sel(self):
        return min(self.cur, self.anchor), max(self.cur, self.anchor)

    def move(self, p, extend=False):
        self.cur = p
        if not extend:
            self.anchor = p

    def goto(self, n):
        p = 0
        for _ in range(n - 1):
            q = self.t.find(b'\n', p)
            if q < 0:
                p = len(self.t)
                break
            p = q + 1
        self.move(p)

    def end(self):
        q = self.t.find(b'\n', self.cur)
        self.move(len(self.t) if q < 0 else q)

    def down(self, k, extend):
        """k lines down from the start of a line, at column 0"""
        p = self.cur
        for _ in range(k):
            q = self.t.find(b'\n', p)
            if q < 0:
                break
            p = q + 1
        self.move(p, extend)

    def type(self, s, new_step=True):
        if new_step:
            self.snap()
        a, b = self.sel()
        self.t[a:b] = s
        self.move(a + len(s))

    def delete_sel(self):
        self.snap()
        a, b = self.sel()
        del self.t[a:b]
        self.move(a)

    def replace_all(self, pat, rep):
        self.snap()
        lo = bytes(self.t).lower()
        out = bytearray()
        i = 0
        n = 0
        last = None
        while True:
            j = lo.find(pat.lower(), i)
            if j < 0:
                break
            out += self.t[i:j] + rep
            last = len(out)
            i = j + len(pat)
            n += 1
        out += self.t[i:]
        self.t = out
        lo = None
        if last is not None:
            self.move(last)
        return n

    def do_undo(self):
        self.t = bytearray(self.undo.pop())


class Script:
    def __init__(self):
        self.b = bytearray()
        self.names = {}         # stop name -> offset
        self.states = []        # expected states, by 'L' number

    def P(self, x, y):
        self.b += bytes([ord('P'), x & 255, x >> 8, y & 255, y >> 8])

    def click(self, x, y, n=1):
        self.P(x, y)
        for _ in range(n):
            self.b += b'D'
            self.W(4)
            self.b += b'U'

    def drag(self, x0, y0, x1, y1):
        self.P(x0, y0)
        self.b += b'D'
        for i in range(1, 5):
            self.P(x0 + (x1 - x0) * i // 4, y0 + (y1 - y0) * i // 4)
        self.b += b'U'

    def K(self, k, mods=0):
        if mods & CTRL and 0x40 <= k < 0x80:
            k &= 0x1F                   # Ctrl + a letter: the ROM gives its control code
        if mods:
            self.b += bytes([ord('M'), mods])
        self.b += bytes([ord('K'), k])
        if mods:
            self.b += bytes([ord('M'), 0])

    def T(self, s):
        s = s.encode('latin-1') if isinstance(s, str) else s
        for i in range(0, len(s), 8):
            c = s[i:i + 8]
            self.b += bytes([ord('T'), len(c)]) + c

    def W(self, n):
        self.b += bytes([ord('W'), n])

    def H(self, n):
        self.b += bytes([ord('H'), n & 255])

    def L(self, n, want):
        self.b += bytes([ord('L'), n])
        self.states.append((n, want))

    def B(self, m, n=7):
        """the blink probe: n changes of the cursor, the main loop slowed
        by m (tests/edit_play.s, tests/check_blink.py)"""
        self.b += bytes([ord('B'), m, n])

    def Z(self):
        self.b += b'Z'

    def Y(self, c):
        self.b += bytes([ord('Y'), ord(c)])

    def stop(self, name):
        self.names[name] = len(self.b)


def state(m, name, top=None, eol=0, modified=1):
    a, b = m.sel()
    return {'line': m.line_of(m.cur), 'col': m.col_of(m.cur), 'len': len(m.t), 'lines': m.lines(),
            'modified': modified, 'lo': a, 'hi': b, 'eol': eol, 'name': name}


# the Open and Save dialog (sdk/lib/vrchoose.c, DECISIONS V79) at 640x480:
# 38 x 27 cards, centred (card 21, card row 16) until it is moved; bands of
# 2 card rows: the title band at row 0, the field at 3, "In:" at 6 (cards
# 9-35), the list's rows from row 9 (cards 2-34), the buttons at row 24
# (New folder 2-10, the type filter 12-19, Cancel 21-27, Save/Open 29-35)
DLG = [21, 16]


def dlg_xy(card, crow):
    """the middle of the band at card, card row (relative to the box)"""
    return (DLG[0] + card) * 8 + 4, (DLG[1] + crow) * 8 + 8


def dlg_row(i):
    return dlg_xy(2, 9 + 2 * i)[1]


def dialog_session(s, files):
    """the dialog's own checks, after the session (the root folder is the
    current one): a new document; Save as: the box moved by its title
    band, a new folder with a long name made (typed into the field) and
    entered, a long file name typed, saved there; Open, Esc (cancelled);
    Open: Backspace up a folder, the type filter's button (all files),
    Esc; Open: the folder pop-up's SD card, 'b', Return. Returns the
    console lines the dialog must log, in this order ('?': any count, '*':
    a count larger than the one before it: the root has more files than
    the filter's, TXT MD INI LOG, shows)."""
    folder, name = 'A folder with a long name', 'Notes from the dialog.txt'
    s.K(ord('n'), CTRL)                         # a new document
    s.T('Dialog test\r')
    m = Model(b'')
    m.type(b'Dialog test\n')
    s.L(23, state(m, ''))
    s.K(ord('s'), CTRL | SHIFT)                 # Save as
    s.stop('savedlg')
    x, y = dlg_xy(12, 0)
    s.drag(x, y, x - 96, y - 64)                # the title band dragged: 12 cards left, 8 rows up
    DLG[0] -= 12
    DLG[1] -= 8
    s.W(30)
    s.stop('moved')
    s.click(*dlg_xy(5, 24))                     # New folder
    s.T(folder + '\r')
    for _ in range(len('Untitled.txt')):
        s.K(BS)
    s.T(name)
    s.stop('newfolder')
    s.K(RET)
    s.L(24, state(m, name, modified=0))
    files[folder + '/' + name] = bytes(m.t)
    s.K(ord('o'), CTRL)                         # Open, Esc: nothing changes
    s.W(20)
    s.K(ESC)
    s.L(25, state(m, name, modified=0))
    s.K(ord('o'), CTRL)                         # Open: up to the root, all files, Esc
    s.W(20)
    s.K(BS)
    s.click(*dlg_xy(14, 24))
    s.stop('allfiles')
    s.K(ESC)
    s.K(ord('o'), CTRL)                         # Open: In: > SD card, 'b', Return
    s.W(20)
    s.click(*dlg_xy(20, 6))
    s.stop('popup')
    s.click(dlg_xy(10, 0)[0], dlg_row(3))       # (the folder, Documents, Apps, SD card)
    s.K(ord('b'))
    s.K(RET)
    s.L(26, state(Model(SAVED_BIG[0]), 'BIG.TXT', modified=0))
    s.K(ord('o'), CTRL)                         # (V82) Open: the long name saved above,
    s.W(20)                                     # 'a' (the folder), Return into it,
    s.K(ord('a'))                               # 'n', Return: reopened
    s.K(RET)
    s.W(20)
    s.K(ord('n'))
    s.K(RET)
    s.L(27, state(Model(bytes(m.t)), name, modified=0))
    return ['VRF MOVED 9 8', 'VRF NEW ' + folder, 'VRF SHOW 1 /' + folder, 'VRF OK /' + folder,
            'VRF NAME ' + name, 'VRF CANCEL', 'VRF SHOW ? /', 'VRF SHOW * /', 'VRF CANCEL', 'VRF SHOW ? /',
            'VRF OK /', 'VRF NAME BIG.TXT', 'VRF SHOW ? /', 'VRF SHOW 2 /' + folder, 'VRF OK /' + folder,
            'VRF NAME ' + name]


SAVED_BIG = [None]

# (V143) a UTF-8 file in Polish: decoded into Veranda's set (ISO-8859-16)
POLISH = 'Zażółć gęślą jaźń\nZAŻÓŁĆ GĘŚLĄ JAŹŃ\n'


def polish_session(s, files):
    """(V143) ZAZOLC.TXT, UTF-8: opened (Ctrl+O, Backspace up to the root,
    'z', Return) and shown in the set's glyphs (the 'polish' screenshot,
    tests/check_edit.py --polish); "Żółw" typed in the set's bytes at the
    end and saved: UTF-8 again; Ctrl+E (the set when saving) and Save as
    Polski.txt: the set's bytes"""
    s.K(ord('o'), CTRL)
    s.W(20)
    s.K(BS)
    s.K(ord('z'))
    s.K(RET)
    m = Model(POLISH.encode('iso8859_16'))
    s.L(28, state(m, 'ZAZOLC.TXT', modified=0))
    s.stop('polish')
    s.K(CTRL_END, CTRL)
    s.T(b'\xaf\xf3\xb3w\r')
    m.move(len(m.t))
    m.type('Żółw\n'.encode('iso8859_16'))
    s.K(ord('s'), CTRL)
    s.L(29, state(m, 'ZAZOLC.TXT', modified=0))
    files['ZAZOLC.TXT'] = bytes(m.t).decode('iso8859_16').encode('utf-8')
    s.K(ord('e'), CTRL)
    s.K(ord('s'), CTRL | SHIFT)
    s.W(20)
    for _ in range(len('ZAZOLC.TXT')):
        s.K(BS)
    s.T('Polski.txt\r')
    s.L(30, state(m, 'Polski.txt', modified=0))
    files['Polski.txt'] = bytes(m.t)


def styled_scrap():
    """a Text Scrap as geoWrite writes one: a NEWCARDSET, a ruler, bold,
    a picture escape, CR line ends"""
    ruler = bytes([17]) + bytes(range(26))
    data = (bytes([23, 9, 0, 0]) + ruler + b'Styled ' + bytes([23, 9, 0, 0x40]) + b'bold' +
            bytes([23, 9, 0, 0]) + b' text\r' + bytes([16, 4, 20, 0, 1]) + b'second line\r')
    body = bytes([len(data) & 255, len(data) >> 8]) + data
    ent = bytearray(30)
    ent[0] = 0x83
    ent[3:19] = b'Text  Scrap'.ljust(16, b'\xa0')
    ent[22] = 4
    sig = b'PRG formatted GEOS file V1.0'.ljust(224, b'\0')
    info = bytearray(254)
    info[0:2] = bytes([3, 21])
    info[2] = 0xBF
    info[66] = 0x83
    info[67] = 4
    info[75:91] = b'Text  Scrap V2.0'
    return bytes(ent) + sig + bytes(info) + body, b'Styled bold text\nsecond line\n'


def main():
    run = sys.argv[1]
    stop = sys.argv[sys.argv.index('--stop') + 1] if '--stop' in sys.argv else None
    os.makedirs(os.path.join(run, 'Docs'), exist_ok=True)
    os.makedirs(os.path.join(run, 'VERANDA', '.SYSTEM'), exist_ok=True)
    big = text_of(100000, 7)
    huge = text_of(237800, 11)
    crlf = text_of(3000, 3).replace(b'\n', b'\r\n')
    crlf = crlf[:200] + b'a lone CR\rin a CR LF file' + crlf[200:]
    mac = text_of(2000, 5).replace(b'\n', b'\r')
    lone = b'LF text with a lone\rCR in it\nsecond line\n'
    files = {'BIG.TXT': big, 'HUGE.TXT': huge, 'Docs/CRLF Long Name File.txt': crlf,
             'Docs/OLD MAC.TXT': mac, 'Docs/Lone.txt': lone, 'ZAZOLC.TXT': POLISH.encode('utf-8')}
    for n, d in files.items():
        open(os.path.join(run, n), 'wb').write(d)
    scrap, scrap_text = styled_scrap()
    open(os.path.join(run, 'VERANDA', '.SYSTEM', 'Text  Scrap.cvt'), 'wb').write(scrap)

    s = Script()
    s.W(60)
    s.L(1, {'line': 1, 'col': 1, 'len': 0, 'lines': 1, 'modified': 0, 'lo': 0, 'hi': 0, 'eol': 0, 'name': ''})
    s.B(0)                                      # the cursor's blink, fast and slowed
    s.B(40)
    s.B(200)
    # open BIG.TXT through the chooser: 'b' selects it, Return opens it
    s.K(ord('o'), CTRL)
    s.stop('chooser')
    s.K(ord('b'))
    s.stop('chooser2')
    s.K(RET)
    s.stop('opened')
    m = Model(big)
    s.L(2, state(m, 'BIG.TXT', modified=0))
    # the start
    s.K(CTRL_HOME, CTRL)
    s.T('START\r')
    m.type(b'START\n')
    s.L(3, state(m, 'BIG.TXT'))
    # the middle: line 1000, its end
    s.K(ord('l'), CTRL)
    s.T('1000\r')
    s.W(30)
    s.K(END)
    s.T(' MIDDLE')
    m.goto(1000)
    m.end()
    m.type(b' MIDDLE')
    s.L(4, state(m, 'BIG.TXT'))
    # the end
    s.K(CTRL_END, CTRL)
    s.T('\rEND')
    m.move(len(m.t))
    m.type(b'\nEND')
    s.L(5, state(m, 'BIG.TXT'))
    # find and replace all: lorem -> LOREM-X (any case)
    s.K(ord('f'), CTRL)
    s.stop('find')
    s.T('lorem')
    s.K(TAB)
    s.T('Lorem-X')
    s.stop('findfull')
    s.K(0xE1, ALT)                      # Alt+A: Replace all
    n = m.replace_all(b'lorem', b'Lorem-X')
    s.L(6, state(m, 'BIG.TXT'))
    # three lines selected (Shift+Down) at line 500 and deleted
    s.K(ord('l'), CTRL)
    s.T('500\r')
    s.W(30)
    m.goto(500)
    for _ in range(3):
        s.K(KEY_DOWN, SHIFT)
    m.down(3, True)
    s.L(7, state(m, 'BIG.TXT'))
    s.stop('select')
    s.K(DEL)
    m.delete_sel()
    s.L(8, state(m, 'BIG.TXT'))
    # undo: "oops" typed, then undone, then the deletion undone
    s.T('oops')
    m.type(b'oops')
    s.K(ord('z'), CTRL)
    m.do_undo()
    m.move(m.cur - 4)
    s.L(9, state(m, 'BIG.TXT'))
    s.K(ord('z'), CTRL)
    m.do_undo()
    # (the cursor after the deletion undone: after the text put back)
    m.goto(500)
    m.down(3, False)
    s.L(10, state(m, 'BIG.TXT'))
    # the styled scrap pasted at the end, as plain text
    s.K(CTRL_END, CTRL)
    s.K(ord('v'), CTRL)
    m.move(len(m.t))
    m.type(scrap_text)
    s.L(11, state(m, 'BIG.TXT'))
    # two lines copied (line 10, Shift+Down twice) and pasted at the end
    s.K(ord('l'), CTRL)
    s.T('10\r')
    s.W(30)
    m.goto(10)
    s.K(KEY_DOWN, SHIFT)
    s.K(KEY_DOWN, SHIFT)
    m.down(2, True)
    a, b = m.sel()
    copied = bytes(m.t[a:b])
    s.K(ord('c'), CTRL)
    s.K(CTRL_END, CTRL)
    s.K(ord('v'), CTRL)
    m.move(len(m.t))
    m.type(copied)
    s.L(12, state(m, 'BIG.TXT'))
    # saved
    s.K(ord('s'), CTRL)
    s.L(13, state(m, 'BIG.TXT', modified=0))
    saved_big = bytes(m.t)
    SAVED_BIG[0] = saved_big
    # the mouse: a click on row 5 of the window, column 10 (Ctrl+Home: the
    # first rows)
    s.K(CTRL_HOME, CTRL)
    m.move(0)
    s.click(10 * 8 + 2, 32 + 5 * 8 + 3)
    p = m.t.find(b'\n')
    for _ in range(4):
        p = m.t.find(b'\n', p + 1)
    ls = p + 1
    m.move(ls + 10)
    s.L(14, state(m, 'BIG.TXT', modified=0))
    s.W(40)                             # (not a double click)
    # a drag from there to row 7, column 20: a selection
    s.drag(10 * 8 + 2, 32 + 5 * 8 + 3, 20 * 8 + 2, 32 + 7 * 8 + 3)
    l7 = m.t.find(b'\n', m.t.find(b'\n', ls) + 1) + 1
    m.move(ls + 10)
    m.move(l7 + 20, True)
    s.L(15, state(m, 'BIG.TXT', modified=0))
    s.stop('drag')
    # the wheel: two notches down (six lines); the geos menu by the
    # pointer: About, its box closed by Return; then the timings: a key
    # (typed and taken back), a page down, a line scrolled (Ctrl+Down)
    s.H(2)
    s.W(10)
    s.K(ESC)
    m.move(m.cur)
    s.click(125, 7)                     # (V148) the File menu opened (its
    s.W(20)                             # groups, its keys), Esc closes it
    s.stop('filemenu')
    s.K(ESC)
    s.W(10)
    s.click(10, 7)                      # the geos menu (V137: the pointer
    s.W(10)                             # stays on the bar: down to its
    s.P(10, 24)                         # first item, About)
    s.b += b'D'
    s.W(4)
    s.b += b'U'
    s.W(40)                             # (the item flashes, then its action)
    s.stop('about')
    s.K(RET)                            # Return: OK (the box closes after
    s.W(30)                             # its flash)
    s.Z()
    s.K(ord('x'))                       # (the first key here moves the gap)
    s.Y('k')
    s.Z()
    s.K(ord('y'))                       # a key typed
    s.Y('k')
    s.K(BS)
    s.K(BS)
    s.Z()
    s.K(PGDN)                           # a page
    s.Y('p')
    s.K(CTRL_HOME, CTRL)                # to the window's last row, then Down:
    for _ in range(53):                 # the view scrolls one line
        s.K(KEY_DOWN)
    s.Z()
    s.K(KEY_DOWN)
    s.Y('l')
    s.stop('scrolled')
    s.K(CTRL_HOME, CTRL)
    m.move(0)
    s.K(ord('s'), CTRL)                 # (the x and its Backspace: saved again)
    m.t = bytearray(saved_big)
    s.L(16, state(m, 'BIG.TXT', modified=0))
    return_files = {}
    # Save as (Ctrl+Shift+S): into Docs (the list: Down, Up, Return goes
    # into it), a new name typed over the old
    s.K(ord('s'), CTRL | SHIFT)
    s.stop('saveas')
    s.K(KEY_DOWN)
    s.K(KEY_UP)
    s.K(RET)                            # into Docs
    for _ in range(7):
        s.K(BS)
    s.T('Copy of big.txt')
    s.stop('saveas2')
    s.K(RET)
    return_files['Docs/Copy of big.txt'] = saved_big
    s.L(17, state(m, 'Copy of big.txt', modified=0))
    # the CR LF file: Ctrl+O, 'c' twice, Return
    s.K(ord('o'), CTRL)
    s.K(ord('c'))
    s.K(ord('c'))
    s.K(RET)
    m = Model(crlf.replace(b'\r\n', b'\n'))
    s.L(18, state(m, 'CRLF Long Name File.txt', eol=1, modified=0))
    s.K(CTRL_END, CTRL)
    s.T('\rADDED')
    m.move(len(m.t))
    m.type(b'\nADDED')
    s.K(ord('s'), CTRL)
    return_files['Docs/CRLF Long Name File.txt'] = bytes(m.t).replace(b'\n', b'\r\n')
    # Lone.txt by a double click in the chooser (row 3: .., Copy, CRLF, Lone)
    s.K(ord('o'), CTRL)
    s.click(250, dlg_row(3), 2)
    m = Model(lone)
    s.L(19, state(m, 'Lone.txt', eol=0, modified=0))
    s.T('Y')
    m.type(b'Y')
    s.K(ord('s'), CTRL)
    return_files['Docs/Lone.txt'] = bytes(m.t)
    # the CR file
    s.K(ord('o'), CTRL)
    s.K(ord('o'))
    s.K(RET)
    m = Model(mac.replace(b'\r', b'\n'))
    s.L(20, state(m, 'OLD MAC.TXT', eol=2, modified=0))
    s.K(KEY_DOWN)
    s.T('Z')
    m.down(1, False)
    m.type(b'Z')
    s.K(ord('s'), CTRL)
    return_files['Docs/OLD MAC.TXT'] = bytes(m.t).replace(b'\n', b'\r')
    # HUGE.TXT: Backspace (up a folder), 'h', Return
    s.K(ord('o'), CTRL)
    s.K(BS)
    s.K(ord('h'))
    s.K(RET)
    m = Model(huge)
    s.L(21, state(m, 'HUGE.TXT', modified=0))
    s.K(CTRL_END, CTRL)
    s.T('\rHUGE END')
    m.move(len(m.t))
    m.type(b'\nHUGE END')
    s.K(CTRL_HOME, CTRL)
    s.T('HUGE START ')
    m.move(0)
    m.type(b'HUGE START ')
    s.K(ord('s'), CTRL)
    s.L(22, state(m, 'HUGE.TXT', modified=0))
    return_files['HUGE.TXT'] = bytes(m.t)
    return_files['BIG.TXT'] = saved_big
    vrf = dialog_session(s, return_files)
    polish_session(s, return_files)
    s.stop('end')
    if stop:
        s.b = s.b[:s.names[stop]] + b'W\x1eS'
        s.states = [st for st in s.states]
    s.b += b'W\x1eE'
    if len(s.b) > 8192:
        sys.exit('edit_script: the session is %d bytes (8192 at most)' % len(s.b))
    open(os.path.join(run, 'EDIT.PLY'), 'wb').write(s.b)
    exp = {'states': s.states, 'replaced': n, 'files': {k: v.decode('latin-1') for k, v in return_files.items()},
           'scrap': copied.decode('latin-1'), 'stop': stop, 'vrf': vrf}
    json.dump(exp, open(os.path.join(run, 'expect.json'), 'w'))


if __name__ == '__main__':
    main()
