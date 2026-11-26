#!/usr/bin/env python3
"""Gate tile (DECISIONS V156): the icons of a package's whole APPS folder
in the shell's Apps window, on the plain tile desktop and on a picture.

usage: apps_icons.py script <run folder> [page] [--pins a,b] [--view name] [--prefs 1|menu] [--mode 640x240]
       apps_icons.py check <dump> <APPS folder> plain|picture [page] [--all 1]
       apps_icons.py pixels <dump> <APPS folder> plain|picture [page] [--pins a,b] [--least n]
       apps_icons.py small <dump> <APPS folder>
       apps_icons.py dock <dump> <APPS folder> --pins a,b --mode 640x240
       apps_icons.py files <APPS folder>
       apps_icons.py root <run folder>
       apps_icons.py rootcheck <dump> <run folder>
       apps_icons.py speed <run folder>
       apps_icons.py times <console.txt> open=n,page=n,scroll=n,move=n

script: SHELL.TST for a run in the card's layout (the shell in /VERANDA,
the programs in /VERANDA/APPS): the sidebar's Apps (window 0, icon view),
then Page > Next page times, the end (a VRAM dump).

check: each icon cell of that page (window 0 in its default place, 20 a
page; the folder's order, ".." first) is
  colour   a colour icon (its cards tiles of palette row 12),
  look2    Look 2's tile (its cards of one colour, not the paper),
  bare     its 1-bit picture alone on the paper (V156: no colour icon);
a program "has" a colour icon when its file carries one (tools/vpack.py's
icon3) or its class is in the shell's library (shell/icons3.txt).
plain: every program that has one shows it (colour), the others bare;
picture: a program that has one is colour, or Look 2's tile when the
tiles ran out (V153's budget: never bare); one that has none is bare.
Prints the counts. (V175) check and pixels --all 1: on a picture too
every program that has one in colour (0 Look 2 tiles: Dusk and the V162
pictures leave enough tiles), and the desktop's card, printer and trash
in colour.

(V161) script --pins: those programs pinned to the dock first, then
Apps again; --view: View > that (name: the list); --prefs 1: a double
click on Preferences.cvt (its test build plays its session, which
changes the desktop, and closes) first. pixels: each program's cell
pixel for pixel the colour icon it should show (the library's by its
class, else its own I3 block, decoded as the shell reads it), as VERA
shows the screen; on a picture Look 2's tile also (no tiles left), at
least --least in colour; the dock's pins pixel for pixel their colour
icons (plain and picture). small: the list's first programs' small icons
pixel for pixel. files: every program of the folder has a colour icon,
its own I3 block sound (the flags, "I3", its offset, version 3, 16 tiles
at most, its map's tiles given); (V207) and its class in the small
library (shell/icons3s.txt), not the generic program's.

root (V157, the user's card: a root of about 60 entries, mostly folders,
on a picture): the Apps window's two pages first (34 programs: more than
a picture's tiles hold), then the sidebar's SD card: the root's page 2
(the page kept); rootcheck: every folder of it the one colour folder
icon, the desktop's card, printer and trash colour icons (their cards
tiles of row 12, on the picture's plate).

speed (V165): the Apps window opened, its pages turned, a row scrolled
and the window dragged (on an SD card image: CMDR-DOS reading the card as
on the X16, where the host folder costs no cycles); times: each within
its limit in cycles, and no whole screen drawn again after a folder is
shown.

MIT licence (LICENSE).
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, '..', 'tools'))
import shell_script as ss  # noqa: E402


def names(apps):
    return ['..'] + ss.listing([], [n for n in os.listdir(apps) if n.lower().endswith('.cvt')])


def script(d, page, pins=(), view=None, prefs=False, mode=None):
    order = names(os.path.join(d, 'VERANDA', 'APPS'))
    p = ss.Part()
    p.wait(30)
    if prefs == 'menu':             # (V180) Options > Preferences... before the Apps folder
        p.menu('options', 'prefs')
        p.wait(1200)
    p.click(*ss.place(1))
    p.wait(60)
    if prefs and prefs != 'menu':   # (V161) Preferences (a test build) changes the desktop
        p.dbl(*ss.cell(order.index('Preferences.cvt')))
        p.wait(1200)
    for n in pins:                  # (V161) pinned to the dock, then Select > none
        p.click(*ss.cell(order.index(n)))
        p.wait(10)
        p.menu('options', 'pin')
        p.wait(30)
    if pins or prefs:               # (no selection: its ring)
        p.menu('select', 'none')
        p.wait(30)
    for _ in range(page):
        p.menu('page', 'next')
        p.wait(60)
    if view:
        p.menu('view', view)
        p.wait(60)
    if mode:                        # (V180) Options > 640 x 240 or 320 x 240 last
        p.menu('options', mode)
        p.wait(150)
    p.wait(60)
    p.end(ss.END_DONE)
    ss.write(os.path.join(d, 'SHELL.TST'), [p])


def speed(d):
    """(V165) the Apps window opened (the sidebar), its pages turned by the
    scroll bar's track (next, back, next, back), a row down and up by its
    arrows, the window dragged away and back, Veranda and Apps again"""
    p = ss.Part()
    p.wait(30)
    p.click(*ss.place(1))
    p.wait(120)
    sb = ss.status()
    for k in ('next', 'prev', 'next', 'prev', 'down', 'up'):
        p.click(*sb[k])
        p.wait(90)
    p.drag((200, 40), (280, 104), steps=4)
    p.wait(90)
    p.drag((280, 104), (200, 40), steps=4)
    p.wait(90)
    p.click(*ss.place(0))
    p.wait(90)
    p.click(*ss.place(1))
    p.wait(120)
    p.end(ss.END_DONE)
    ss.write(os.path.join(d, 'SHELL.TST'), [p])


TIMES = re.compile(r'(TIME [A-Z]+ \d+|SHELL FOLDER SHOWN IN \d+|SHELL ALL IN \d+)')


def times(console, lim):
    """(V165) the speed session's times (the emulator's cycles at 8 MHz)
    within lim: open=, page=, scroll=, move= (the window drawn, a page
    turned, a row scrolled, a window let go); no whole screen drawn again
    after a folder is shown (V161's restart of the colour icons' cache)"""
    lim = dict((k, int(v)) for k, v in (x.split('=') for x in lim.split(',')))
    got = TIMES.findall(open(console, 'rb').read().decode('latin-1').replace('\r', ''))
    out, bad, seen = {'open': [], 'page': [], 'scroll': [], 'move': []}, [], False
    for g in got:
        n = int(g.split()[-1])
        if g.startswith('SHELL ALL'):
            if seen:
                bad.append('the whole screen drawn again (%s) after a folder was shown' % g)
            continue
        if g.startswith('SHELL FOLDER'):
            out['open'].append(n)
            seen = True
            continue
        k = g.split()[1].lower()
        if k in out:
            out[k].append(n)
    for k, v in out.items():
        if not v:
            bad.append('no %s time' % k)
        for n in v:
            if n > lim[k]:
                bad.append('%s %d cycles (at most %d)' % (k, n, lim[k]))
    print('; '.join('%s %s ms' % (k, '/'.join('%.0f' % (n / 8000) for n in v)) for k, v in out.items()))
    for b in bad:
        print('  ' + b)
    sys.exit(1 if bad else 0)


def root(d):
    p = ss.Part()
    p.wait(30)
    p.click(*ss.place(1))
    p.wait(60)
    p.menu('page', 'next')
    p.wait(60)
    p.click(*ss.place(4))
    p.wait(90)
    p.end(ss.END_DONE)
    ss.write(os.path.join(d, 'SHELL.TST'), [p])


def classify(v, cx, cy):
    import check_theme as ct
    cols, rows = set(), set()
    for y in range(cy, cy + 4):
        for x in range(cx, cx + 4):
            c = ct.card(v, x, y)[0]
            cols.add(c)
            if c == -1:
                rows.add(v[ct.MAP + 2 * (y * 128 + x) + 1] >> 4)
    return 'colour' if rows & {11, 12} else 'bare' if cols == {0} else 'look2'


def desk_icons(v, bad):
    """the desktop's card, printer and trash: their colour icons"""
    for n, y in (('the card', 4), ('the printer', 11), ('the trash', 18)):
        what = classify(v, 72, y)
        if what != 'colour':
            bad.append('the desktop\'s %s: %s, want its colour icon' % (n, what))


def rootcheck(dump, d):
    import check_theme as ct
    v = ct.section(dump)
    ents = os.listdir(d)
    order = ss.listing([n for n in ents if os.path.isdir(os.path.join(d, n))],
                       [n for n in ents if not os.path.isdir(os.path.join(d, n))])
    bad, nf = [], 0
    for s in range(20):
        i = 20 + s
        if i >= len(order) or not os.path.isdir(os.path.join(d, order[i])):
            continue
        mx, my = ss.cell(s)
        what = classify(v, (mx - 16) // 8, (my - 16) // 8)
        nf += 1
        if what != 'colour':
            bad.append('folder %s: %s, want the colour folder icon' % (order[i], what))
    desk_icons(v, bad)
    print('      the root (%d entries), page 2: %d folders in colour; the desktop\'s card, printer, trash in colour'
          % (len(order), nf - len([b for b in bad if b.startswith('folder')])))
    if bad:
        print('\n'.join('FAIL  ' + b for b in bad))
        sys.exit(1)


def has_colour(path, lib):
    b = open(path, 'rb').read()
    info = b[254:508]
    cls = info[75:87]
    if cls in lib:
        return True
    return bool(info[135:139] == b'VRND' and info[141] & 8)


def check(dump, apps, kind, page, every=False):
    import check_theme as ct
    import mkicons3
    v = ct.section(dump)
    lib = {mkicons3.key(kv['for']) for _, kv, _ in mkicons3.read(os.path.join(HERE, '..', 'shell', 'icons3.txt'))}
    order = names(apps)
    per = 20
    got = {'colour': [], 'look2': [], 'bare': []}
    bad = []
    for s in range(per):
        i = page * per + s
        if i >= len(order):
            break
        n = order[i]
        mx, my = ss.cell(s)
        cx, cy = (mx - 16) // 8, (my - 16) // 8
        cols, rows = set(), set()
        for y in range(cy, cy + 4):
            for x in range(cx, cx + 4):
                c = ct.card(v, x, y)[0]
                cols.add(c)
                if c == -1:
                    rows.add(v[ct.MAP + 2 * (y * 128 + x) + 1] >> 4)
        what = 'colour' if 12 in rows else 'bare' if cols == {0} else 'look2'
        got[what].append(n)
        if n == '..':
            if what != 'colour':
                bad.append('%s: %s, want colour' % (n, what))
            continue
        want = ('colour',) if has_colour(os.path.join(apps, n), lib) else ('bare',)
        if kind == 'picture' and want == ('colour',) and not every:
            want = ('colour', 'look2')
        if what not in want:
            bad.append('%s: %s, want %s' % (n, what, ' or '.join(want)))
    if every:
        desk_icons(v, bad)
    print('      page %d: %d colour, %d Look 2 tiles (no tiles left), %d bare (%s)%s'
          % (page + 1, len(got['colour']), len(got['look2']), len(got['bare']), ', '.join(got['bare']) or 'none',
             '; the desktop\'s card, printer, trash in colour' if every else ''))
    if bad:
        print('\n'.join('FAIL  ' + b for b in bad))
        sys.exit(1)


# ---------------------------------------------------------------- the pixels
# (icons v2 fix) each icon cell compared pixel for pixel with the icon the
# shell should show: the library's by the file's class (shell/icons3.txt,
# icons3s.txt), else the file's own (its I3 block, decoded as the shell
# reads it); its pixels the paper (entry 0), the ink (1) or entry 1-15 of
# palette row 12, as VERA shows the screen (tools/vram2png.py compose)

def decode(b, n):
    """packed icon bytes (mkicons3.pack: 658, a small one 165) -> n rows
    of n values: 0 none, 'K' the ink, 1-15"""
    if n == 32:
        if len(b) < 658 or b[1] != 3 or b[0] > 16:
            return None
        mp, ink, td = b[2:18], b[18:146], b[146:658]
    else:
        mp, ink, td = b[1:5], b[5:37], b[37:165]
    g = [[0] * n for _ in range(n)]
    for k, e in enumerate(mp):
        if e & 0x80:
            continue
        if (e & 15) >= b[0]:
            return None
        cx, cy = k % (n // 8), k // (n // 8)
        t = td[(e & 15) * 32:(e & 15) * 32 + 32]
        for y in range(8):
            for x in range(8):
                sx = 7 - x if e & 0x10 else x
                sy = 7 - y if e & 0x20 else y
                c = t[sy * 4 + sx // 2]
                g[cy * 8 + y][cx * 8 + x] = c >> 4 if sx % 2 == 0 else c & 15
    for y in range(n):
        for x in range(n):
            if ink[y * (n // 8) + x // 8] & (0x80 >> (x % 8)):
                g[y][x] = 'K'
    return g


def libs():
    import mkicons3
    top = os.path.join(HERE, '..', 'shell')
    big = {mkicons3.key(kv['for']): mkicons3.pack(g)[0] for _, kv, g in mkicons3.read(os.path.join(top, 'icons3.txt'))}
    sm = {mkicons3.key(kv['for']): mkicons3.pack(g)[0] for _, kv, g in mkicons3.read(os.path.join(top, 'icons3s.txt'))}
    return big, sm


def own_icon(path):
    """a file's own colour icon (its I3 block) as bytes; b'' a broken one
    (flags say it has one, the block or its offset are wrong), None none"""
    b = open(path, 'rb').read()
    info = b[254:508]
    if not (info[135:139] == b'VRND' and info[141] & 8):
        return None
    if b[225:227] != b'I3':
        return b''
    o = int.from_bytes(b[227:230], 'little')
    blk = b[o:o + 658]
    return blk if len(blk) == 658 and blk[1] == 3 and blk[0] <= 16 else b''


def want(path, big, small=False, sm=None):
    """the icon the shell should show for a file: (grid, where) or (None, why)"""
    b = open(path, 'rb').read()
    cls = b[254 + 75:254 + 87]
    if small:
        k = cls if cls in sm else b'*App        '
        return decode(sm[k], 16), 'small library'
    if cls in big:
        return decode(big[cls], 32), 'library'
    o = own_icon(path)
    if o is None:
        return None, 'no colour icon (no I3 block, class not in the library)'
    if not o or decode(o, 32) is None:
        return None, 'a broken I3 block'
    return decode(o, 32), 'its own I3'


def colours(v):
    import vram2png as vp
    return vp.rgb(v, 0), vp.rgb(v, 1), [vp.rgb(v, 192 + i) for i in range(16)]


def same(img, x0, y0, g, cols, paper=None):
    """pixels of grid g at x0, y0 that differ from the screen"""
    pp, ink, row = cols
    pp = pp if paper is None else paper
    bad = 0
    for y, r in enumerate(g):
        for x, c in enumerate(r):
            w = ink if c == 'K' else pp if c == 0 else row[c]
            if img[y0 + y][x0 + x] != w:
                bad += 1
    return bad


def dock(dump, apps, pins, mode):
    """(V180) the dock's pins pixel for pixel their colour icons in the
    video mode (640x480, 640x240, 320x240): the screen as VERA shows it in
    that mode's pixels, the items placed as dock.c places them"""
    import check_theme as ct
    import vram2png as vp
    w, h = (int(x) for x in mode.split('x'))
    v = ct.section(dump)
    img = vp.compose(v, w, h)
    cols = colours(v)
    big, _ = libs()
    bad = []
    for i, nm in enumerate(pins):
        g, why = want(os.path.join(apps, nm), big)
        mx, my = ss.dock_item(i, len(pins), w, h)
        d = same(img, mx - 16, my - 16, g, cols) if g else 1024
        if d:
            bad.append('the dock\'s %s: %d of 1,024 pixels differ from %s' % (nm, d, why))
    print('      %s: the dock\'s %d pins pixel for pixel their colour icons' % (mode, len(pins) - len(bad)))
    if bad:
        print('\n'.join('FAIL  ' + b for b in bad))
        sys.exit(1)


def pixels(dump, apps, kind, page, pins=(), least=0, every=False):
    """every program of the page's cell: its colour icon pixel for pixel
    (plain), or on a picture that or Look 2's tile (no tiles left), at
    least <least> of them in colour; the dock's pinned programs (pins)
    their colour icons pixel for pixel, on a picture too"""
    import check_theme as ct
    import vram2png as vp
    v = ct.section(dump)
    img = vp.compose(v)
    cols = colours(v)
    big, _ = libs()
    order = names(apps)
    bad, n = [], 0
    for s in range(20):
        i = page * 20 + s
        if i >= len(order) or order[i] == '..':
            continue
        nm = order[i]
        g, why = want(os.path.join(apps, nm), big)
        mx, my = ss.cell(s)
        if g is None:
            bad.append('%s: %s' % (nm, why))
            continue
        d = same(img, mx - 16, my - 16, g, cols)
        if d == 0:
            n += 1
            continue
        cx, cy = (mx - 16) // 8, (my - 16) // 8
        if kind == 'picture' and classify(v, cx, cy) == 'look2' and not every:
            continue
        bad.append('%s: %d of 1,024 pixels differ from %s' % (nm, d, why))
    if n < least:
        bad.append('page %d: %d programs in colour, want %d or more' % (page + 1, n, least))
    for i, nm in enumerate(pins):
        g, why = want(os.path.join(apps, nm), big)
        mx, my = ss.dock_item(i, len(pins))
        d = same(img, mx - 16, my - 16, g, cols) if g else 1024
        if d:
            bad.append('the dock\'s %s: %d of 1,024 pixels differ from %s' % (nm, d, why))
    if every:
        desk_icons(v, bad)
    print('      page %d: %d programs pixel for pixel their colour icon%s%s' % (page + 1, n,
          ', the dock\'s %d too' % len(pins) if pins else '',
          '; the desktop\'s card, printer, trash in colour' if every else ''))
    if bad:
        print('\n'.join('FAIL  ' + b for b in bad))
        sys.exit(1)


# (V207) a plain file's library key by its extension (shell/prg.c's ic3_ext)
EXT = {e: b'*Music      ' for e in ('mid', 'midi', 'zsm', 'zcm', 'wav', 'mod', 'sid')}
EXT['spv'] = b'*Video      '


def small(dump, apps, first=12):
    """the list view (View > name): the first programs' small icons pixel
    for pixel (shell/icons3s.txt by class), each in the window's body;
    (V207) and the folder's music and video files' (by their extension)"""
    import check_theme as ct
    import vram2png as vp
    v = ct.section(dump)
    img = vp.compose(v)
    cols = colours(v)
    big, sm = libs()
    bad, n = [], 0
    # (V207) the players' plain documents, by their extension (shell/prg.c's ic3_ext)
    docs = sorted(n for n in os.listdir(apps) if '.' in n and n.rsplit('.', 1)[-1].lower() in EXT)
    for nm in names(apps)[1:first + 1] + docs:
        if nm in docs:
            g = decode(sm[EXT[nm.rsplit('.', 1)[-1].lower()]], 16)
        else:
            g, _ = want(os.path.join(apps, nm), big, True, sm)
        c0 = g[0][0]
        w0 = cols[1] if c0 == 'K' else cols[0] if c0 == 0 else cols[2][c0]
        hit = any(img[y][x] == w0 and same(img, x, y, g, cols) == 0
                  for y in range(ss.WIN0[1] + 40, ss.WIN0[3] - 32) for x in range(ss.WIN0[0] + 96, ss.WIN0[2] - 32))
        if hit:
            n += 1
        else:
            bad.append('%s: its small icon not in the list' % nm)
    print('      the list: %d small icons pixel for pixel (%d programs\', %d music and video files\')'
          % (n, len(names(apps)[1:first + 1]), len(docs)))
    if bad:
        print('\n'.join('FAIL  ' + b for b in bad))
        sys.exit(1)


def files(apps):
    """the package's programs: their colour icons (no check of the screen):
    every one has one, own or the library's, and an own I3 block is sound"""
    big, sm = libs()
    bad = []
    for nm in names(apps)[1:]:
        g, why = want(os.path.join(apps, nm), big)
        o = own_icon(os.path.join(apps, nm))
        cls = open(os.path.join(apps, nm), 'rb').read()[254 + 75:254 + 87]
        if g is None:
            bad.append('%s: %s' % (nm, why))
        elif o is not None and (not o or decode(o, 32) is None):
            bad.append('%s: a broken I3 block (the library has its class)' % nm)
        elif cls not in sm:         # (V207: MIDI Player's list icon was the generic program's)
            bad.append('%s: no small icon of its own (class %r not in shell/icons3s.txt)' % (nm, cls.decode('latin-1')))
    print('      %d programs, each with a colour icon and a small one of its own' % (len(names(apps)) - 1 - len(bad)))
    if bad:
        print('\n'.join('FAIL  ' + b for b in bad))
        sys.exit(1)


def main():
    a = sys.argv[1:]
    opt = {}
    while len(a) > 2 and a[-2].startswith('--'):
        opt[a[-2][2:]] = a[-1]
        a = a[:-2]
    pins = [n + '.cvt' for n in opt['pins'].split(',')] if opt.get('pins') else []
    if len(a) >= 2 and a[0] == 'script':
        pf = opt.get('prefs')
        script(a[1], int(a[2]) if len(a) > 2 else 0, pins, opt.get('view'), pf if pf == 'menu' else pf == '1',
               opt.get('mode'))
    elif len(a) == 2 and a[0] == 'root':
        root(a[1])
    elif len(a) == 2 and a[0] == 'speed':
        speed(a[1])
    elif len(a) == 3 and a[0] == 'times':
        times(a[1], a[2])
    elif len(a) == 3 and a[0] == 'rootcheck':
        rootcheck(a[1], a[2])
    elif len(a) >= 4 and a[0] == 'pixels':
        pixels(a[1], a[2], a[3], int(a[4]) if len(a) > 4 else 0, pins, int(opt.get('least', 0)),
               opt.get('all') == '1')
    elif len(a) == 3 and a[0] == 'dock':
        dock(a[1], a[2], pins, opt.get('mode', '640x480'))
    elif len(a) == 3 and a[0] == 'small':
        small(a[1], a[2])
    elif len(a) == 2 and a[0] == 'files':
        files(a[1])
    elif len(a) >= 4 and a[0] == 'check':
        check(a[1], a[2], a[3], int(a[4]) if len(a) > 4 else 0, opt.get('all') == '1')
    else:
        sys.exit(__doc__)


if __name__ == '__main__':
    main()
