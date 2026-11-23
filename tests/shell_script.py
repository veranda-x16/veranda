#!/usr/bin/env python3
"""Gate shell: SHELL.TST, the shell's test script (shell/play.s).

usage: shell_script.py <folder> [<extra name>...]
       shell_script.py --probe <out>
       shell_script.py --crash <folder> [<extra name>...]
       shell_script.py --home <folder>
       shell_script.py --theme <folder> probe|menu|closed|desk [<extra name>...]

Writes <folder>/SHELL.TST for a run in <folder> (the root the shell will
list: the folder's entries, SHELL.TST, SHELL.STP and the extra names, such
as the emulator's console.txt). --probe: one part that only ends (a
screenshot of the first screen). --crash (gate crash, tools/gate_crash.sh):
a part for each Crash*.cvt in the folder (by name: a double click; the
program crashes, its panic box's OK leads back to the shell), then the
end; CRASH.TXT is listed from the second part on (the first program
writes it).
--home (DECISIONS V63, V71): the shell's own folder; the shell starts in
<folder>/DOCUMENTS (SHELL.cvt is in /VERANDA), which holds Docs
(AppCrash.cvt, Readme.txt) and AppGo.cvt; AppGo (opens .txt) changes to
/Mods (ChDir, curDirName) before it quits, AppCrash crashes there:
  0  double-click AppGo (the shell must come back in /DOCUMENTS)
  1  open Docs, double-click Readme.txt: AppGo (the top folder's copy)
     with it, in /DOCUMENTS/Docs (the shell must come back there)
  2  double-click AppCrash: the panic box, OK (back in /DOCUMENTS/Docs)
  3  the end

A record: frame, x, y (words), flags (bit 0 the button, bit 7 a key, bit 6
the end of a part), key. The shell plays part n at its n-th start; the
frame counter stands still while the shell is busy (disk, drawing).

--theme (the colours, DECISIONS V65): one part: the second icon selected,
then probe: the end; menu: the geos menu opened (pressed on its name,
released in it), the end with it open; closed: the
geos menu opened and closed by a click outside it, then geos > about and
its box's OK, the end; desk: a double click on Preferences.cvt (its test
build plays its own script and closes), then the end.

The parts:
  0  double-click AppOne (it logs, returns to the shell)
  1  double-click AppTwo
  2  double-click Note.txt: AppOne opens .txt files (its documents), so
     it starts with Note.txt as its document
  3  open the folder Docs, double-click Readme.txt: AppOne is in the top
     folder; it starts with Readme.txt, the folder /Docs
  4  (the shell starts in Docs) go up (its ".." icon); duplicate Note.txt,
     rename the copy to Memo.txt (typed into the dialog box), delete
     Junk.txt (YES); geos > 640 x 240, geos > 640 x 480; view > refresh;
     the end: SHELL DONE on the console and a VRAM dump
"""
import os
import struct
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'tools'))
import mkfont  # noqa: E402

# Shell 2 (shell/win.c, view.c; DECISIONS V70) in Veranda Look 2 (V77) at
# 640x480: window 0 in its default place, cards 2-61 (x 16-495), rows 4-49
# (y 32-399): the title band (2 card rows), the toolbar (3), the body (the
# sidebar, 12 cards, in a window of 40 cards or more; the contents), the
# status bar (2). Large icons in cells of 9 x 9 cards from card 1 of the
# contents and row 1 of the body: the tile 2 cards in, its name under it;
# window 0 has five a row, four rows a page (grid(): any window)
WIN0 = (16, 32, 495, 399)
TITLEH, TOOLH, STATH, SIDEW, SIDEMIN = 16, 24, 16, 12, 40
CELLW, CELLH = 72, 72
# window 1's default place (it overlaps window 0)
WIN1 = (160, 120, 543, 399)    # (V83: above the dock; was to 431)
# the desktop's icons: a column of tiles at x 576-607, 7 card rows apart
# from y 32 (the card, the printer, the trash, then the pins); their middles
DESK_X = 592
DESK = {'card': (DESK_X, 32 + 16), 'printer': (DESK_X, 88 + 16), 'trash': (DESK_X, 144 + 16)}
PIN_Y0 = 200 + 16               # the first pin's middle; 56 apart


def grid(win=WIN0):
    """a window's icon grid: (first cell's card x, card y, columns, rows)"""
    x, w = win[0] // 8, (win[2] + 1) // 8 - win[0] // 8
    side = SIDEW if w >= SIDEMIN else 0
    body = (win[3] + 1 - win[1] - TITLEH - TOOLH - STATH) // 8
    return x + side + 1, (win[1] + TITLEH + TOOLH) // 8 + 1, max(1, (w - side - 3) // 9), \
        (body - 8) // 9 + 1 if body >= 8 else 1     # (a label's second line: V132)


def toolbar(win=WIN0):
    """the toolbar's parts' middles: back, forward, the icons and list
    toggles, the search field; the first crumb"""
    r, y = (win[2] + 1) // 8, win[1] + TITLEH + 11
    search = r - win[0] // 8 >= 44
    tog = (r - (22 if search else 7)) * 8
    return {'back': (win[0] + 18, y), 'forward': (win[0] + 42, y), 'icons': (tog + 12, y),
            'list': (tog + 36, y), 'search': ((r - 15) * 8 + 40, win[1] + TITLEH + 6),
            'crumb0': (win[0] + 72, y)}


def place(i, win=WIN0):
    """the middle of the sidebar's place i (Veranda, Apps, Documents, Mods,
    the card, the trash, the printer: shown card, printer, trash, V151)"""
    k = i ^ 3 if i >= 5 else i
    y = (win[1] + TITLEH + TOOLH) // 8 + 2 + 2 * k + (3 if k >= 4 else 0)
    return win[0] + 40, y * 8 + 8


def status(win=WIN0):
    """the scroll bar (V151: the body's right 2 cards): the page before
    and after (its track at the top and the bottom: the thumb must not be
    there), the row before and after (its arrows); the resize grip"""
    x, t, b = win[2] - 7, win[1] + TITLEH + TOOLH, win[3] - STATH
    return {'prev': (x, t + 20), 'next': (x, b - 20), 'up': (x, t + 8), 'down': (x, b - 8),
            'grip': (win[2] - 6, win[3] - 6)}


def textw(t):
    """the menus' font's width of t: the UI font's (tools/mkfont.py; the
    shell's menus are in it, theme_menus: DECISIONS V79)"""
    return sum(len(mkfont.U[c][0]) for c in t)


# the menus (shell/main.c), in the Veranda look (kernel/u/menu.s, DECISIONS
# V74; the UI font, V79): the menu bar's item 0 the mark (24 pixels) and "Veranda" in bold
# (+1 a character), each item 6 pixels from its text on both sides, its
# limits rounded up to a card; a sub menu opens under its item, 16 lines
# an item from line 16. MENUS: (key, the bar's text, its items' keys)
MENUS = [
    ('geos', 'Veranda', ['about', 'desk accessory', 'help']),
    ('file', 'File', ['open', 'duplicate', 'rename', 'delete', 'info', 'view', 'copy', 'move', 'put', 'print',
                      'find', 'mods']),
    ('view', 'View', ['icon', 'small', 'name', 'size', 'date', 'type', 'refresh', 'up']),
    ('disk', 'Disk', ['card', 'new window', 'close', 'trash', 'empty', 'documents']),
    ('select', 'Select', ['first', 'next', 'previous', 'none']),
    ('page', 'Page', ['next', 'previous']),
    ('options', 'Options', ['640x480', '640x240', '320x240', 'prefs', 'pin',  # (V180: Preferences..., was the pattern)
                            # (pin: "Pin to the dock", V91)
                  'unpin', 'basic', 'quit']),
]
MENU_X, MENU_ITEMS, MENU_LIM = {}, {}, {}
_b = 0
for _i, (_n, _t, _items) in enumerate(MENUS):
    _e = _b + (24 + textw(_t) + len(_t) if _i == 0 else 6 + textw(_t))
    _e = (_e + 6 + 7) & ~7
    MENU_X[_n] = (_b + _e) // 2
    MENU_LIM[_n] = (_b, _e)
    MENU_ITEMS[_n] = _items
    _b = _e
ITEM_Y0, ITEM_H = 16, 16
# the default dialog box at 640x480: left 224, top 192; YES at DBI_X_0,
# DBI_Y_2 (6 cards by 16 lines)
YES_X, YES_Y = 224 + 8 + 20, 192 + 72 + 8
NO_X = 224 + 8 + 17 * 8 + 20

END_STOP, END_DONE = 0, 1
LIMIT = 2048                    # the shell's script buffer


class Part:
    def __init__(self):
        self.recs = []
        self.f = 10

    def at(self, x, y, b=0, gap=2):
        self.recs.append((self.f, x, y, b, 0))
        self.f += gap

    def click(self, x, y):
        self.at(x, y, 0, 4)
        self.at(x, y, 1, 3)
        self.at(x, y, 0, 20)

    def dbl(self, x, y):
        self.at(x, y, 0, 4)
        self.at(x, y, 1, 3)
        self.at(x, y, 0, 4)
        self.at(x, y, 1, 3)
        self.at(x, y, 0, 40)

    def key(self, c, gap=3):
        self.recs.append((self.f, 0, 0, 0x80, c))
        self.f += gap

    def wait(self, n):
        self.f += n

    def drag(self, a, b, steps=6, mods_wait=4):
        """press at a, move to b with the button held, let go"""
        self.at(a[0], a[1], 0, 4)
        self.at(a[0], a[1], 1, 4)
        for i in range(1, steps + 1):
            self.at(a[0] + (b[0] - a[0]) * i // steps, a[1] + (b[1] - a[1]) * i // steps, 1, 3)
        self.at(b[0], b[1], 1, mods_wait)
        self.at(b[0], b[1], 0, 40)

    def menu(self, main, item):
        # the press opens the sub menu at once; the release is already on
        # its item (the pointer above a vertical sub menu closes it)
        if isinstance(item, str):
            item = MENU_ITEMS[main].index(item)
        x, y = MENU_X[main], ITEM_Y0 + ITEM_H * item + 8
        self.at(x, 7, 0, 4)
        self.at(x, 7, 1, 2)
        self.at(x, y, 0, 30)
        self.click(x, y)
        self.wait(30)

    def end(self, action):
        self.recs.append((self.f, 0, 0, 0x40, action))

    def bytes(self):
        return b''.join(struct.pack('<HHHBB', *r) for r in self.recs)


def cell(i, win=WIN0, cols=None):
    """the middle of icon slot i's tile (on its page) of a window (cols:
    checked against the window's, when given)"""
    x0, y0, c, r = grid(win)
    if cols is not None and cols != c:
        sys.exit('shell_script: the window has %d columns, not %d' % (c, cols))
    if i >= c * r:
        sys.exit('shell_script: icon %d is not on the first page (%d a page)' % (i, c * r))
    return (x0 + 2 + (i % c) * 9) * 8 + 16, (y0 + (i // c) * 9) * 8 + 16


def desk_pin(i, n=None):
    """pin i's tile in the dock (V83: the pins are there; n the dock's
    items, the pins by default as many as i + 1)"""
    return dock_item(i, n or i + 1)


DOCK_ROW = 53                   # the dock's first card row at 480 lines (V83; V152: 52 before)
DOCK_STEP = 6                   # (V152) an item every 6 cards (5 before), the first 2 in, the trash last


def dock_item(i, n, w=640, h=480):
    """the middle of item i's tile of a dock of n items (640 x 480; V180:
    any mode, w x h its pixels); i n: the trash"""
    st, cols = DOCK_STEP, w // 8
    while n * st + 8 > cols:    # (V163) closer when they do not fit
        st -= 1
    x0 = (cols - (n * st + 8)) // 2
    return (x0 + 2 + i * st) * 8 + 16, (h // 8 - 7 + 1) * 8 + 16


def listing(dirs, files):
    """the shell's order: folders, then files, each by name (case ignored)"""
    return sorted(dirs, key=str.lower) + sorted(files, key=str.lower)


def write(out, parts):
    data = b''.join(p.bytes() for p in parts)
    if len(data) > LIMIT:
        sys.exit('shell_script: %d bytes, the shell reads %d' % (len(data), LIMIT))
    open(out, 'wb').write(data)


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    if sys.argv[1] == '--probe':
        p = Part()
        p.wait(30)
        p.end(END_DONE)
        write(sys.argv[2], [p])
        return
    if sys.argv[1] == '--crash':
        d = sys.argv[2]
        files = sorted(set(os.listdir(d) + ['SHELL.TST', 'SHELL.STP'] + sys.argv[3:]))
        apps = sorted((n for n in files if n.startswith('Crash') and n.endswith('.cvt')), key=str.lower)
        parts = []
        for i, a in enumerate(apps):
            root = listing([], files + (['CRASH.TXT'] if i else []))
            p = Part()
            p.wait(20)
            p.dbl(*cell(root.index(a)))
            p.end(END_STOP)
            parts.append(p)
        p = Part()
        p.wait(30)
        p.end(END_DONE)
        parts.append(p)
        write(os.path.join(d, 'SHELL.TST'), parts)
        return
    if sys.argv[1] == '--home':
        d = sys.argv[2]
        def ls(sub):
            p = os.path.join(d, sub)
            n = os.listdir(p)
            return ['..'] + listing([x for x in n if os.path.isdir(os.path.join(p, x))],
                                    [x for x in n if not os.path.isdir(os.path.join(p, x))])
        sysd, docs = ls('DOCUMENTS'), ls('DOCUMENTS/Docs')
        parts = []
        p = Part()
        p.wait(20)
        p.dbl(*cell(sysd.index('AppGo.cvt')))
        p.end(END_STOP)
        parts.append(p)
        p = Part()
        p.wait(20)
        p.dbl(*cell(sysd.index('Docs')))
        p.wait(30)
        p.dbl(*cell(docs.index('Readme.txt')))
        p.end(END_STOP)
        parts.append(p)
        p = Part()
        p.wait(20)
        p.dbl(*cell(docs.index('AppCrash.cvt')))
        p.end(END_STOP)
        parts.append(p)
        p = Part()
        p.wait(30)
        p.end(END_DONE)
        parts.append(p)
        write(os.path.join(d, 'SHELL.TST'), parts)
        return
    if sys.argv[1] == '--theme':
        d, what = sys.argv[2], sys.argv[3]
        dirs = [n for n in os.listdir(d) if os.path.isdir(os.path.join(d, n))]
        files = [n for n in os.listdir(d) if not os.path.isdir(os.path.join(d, n))]
        root = listing(dirs, sorted(set(files + ['SHELL.TST', 'SHELL.STP'] + sys.argv[4:])))
        p = Part()
        p.wait(20)
        p.click(*cell(1))
        x = MENU_X['geos']
        if what == 'menu':
            p.at(x, 7, 0, 4)
            p.at(x, 7, 1, 2)
            p.at(x, 40, 0, 60)                  # (released in it: it stays open)
        elif what == 'closed':
            p.at(x, 7, 0, 4)
            p.at(x, 7, 1, 2)
            p.at(x, 40, 0, 30)
            p.click(536, 300)                   # outside: the menu closes
            p.wait(30)
            p.menu('geos', 'about')             # about: a dialog box
            p.wait(30)
            p.click(YES_X, YES_Y)               # its OK
            p.wait(40)
        elif what == 'desk':
            p.dbl(*cell(root.index('Preferences.cvt')))
            p.wait(60)
        p.wait(30)
        p.end(END_DONE)
        write(os.path.join(d, 'SHELL.TST'), [p])
        return
    d = sys.argv[1]
    dirs = [n for n in os.listdir(d) if os.path.isdir(os.path.join(d, n))]
    files = [n for n in os.listdir(d) if not os.path.isdir(os.path.join(d, n))]
    files = sorted(set(files + ['SHELL.TST', 'SHELL.STP'] + sys.argv[2:]))
    root = listing(dirs, files)
    parts = []

    p = Part()
    p.dbl(*cell(root.index('AppOne.cvt')))
    p.end(END_STOP)
    parts.append(p)

    p = Part()
    p.dbl(*cell(root.index('AppTwo.cvt')))
    p.end(END_STOP)
    parts.append(p)

    p = Part()
    p.dbl(*cell(root.index('Note.txt')))        # AppOne opens .txt (documents)
    p.end(END_STOP)
    parts.append(p)

    p = Part()
    p.dbl(*cell(root.index('Docs')))
    p.wait(30)
    p.dbl(*cell(1))                             # Readme.txt (after ".."): AppOne
    p.end(END_STOP)                             # is in the top folder
    parts.append(p)

    p = Part()                                  # (the shell starts in Docs)
    p.dbl(*cell(0))                             # ".." in Docs
    p.wait(30)
    p.click(*cell(root.index('Note.txt')))
    p.menu('file', 'duplicate')
    root = listing(dirs, files + ['Copy of Note.txt'])
    p.click(*cell(root.index('Copy of Note.txt')))
    p.menu('file', 'rename')
    p.wait(20)
    for _ in range(len('Copy of Note.txt')):
        p.key(8)
    for c in b'Memo.txt':
        p.key(c)
    p.key(13)                                   # Return ends the box
    p.wait(40)
    root = listing(dirs, files + ['Memo.txt'])
    p.click(*cell(root.index('Junk.txt')))
    p.menu('file', 'delete')
    p.wait(20)
    p.click(YES_X, YES_Y)
    p.wait(40)
    p.menu('options', '640x240')
    p.wait(40)
    p.menu('options', '640x480')
    p.wait(40)
    p.menu('view', 'refresh')
    p.wait(40)
    p.end(END_DONE)
    parts.append(p)
    write(os.path.join(d, 'SHELL.TST'), parts)


if __name__ == '__main__':
    main()
