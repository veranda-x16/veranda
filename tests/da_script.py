#!/usr/bin/env python3
"""gate da: writes the sessions of the native desk accessories' test
builds (tests/da_play.c: P, K, END) and Paint's around them
(tests/paint_play.c with PAINT_DA naming the header).

usage: da_script.py <out dir>

Writes <out>/<session>/da_script.h for the accessories' sessions (dex,
cal, prefs1, prefs2, prefs3, prefs4: from their own start) and <out>/paint/da_paint.h,
<out>/paintc/da_paint.h for Paint's (the test builds take the folder with
-I; Paint opens options/accessory, the only accessory in the folder
selected, OPEN; Paint's frames stop while the accessory runs and go on
when RstrAppl gives Paint back). "/* shot NAME FRAME */" lines name
frames for a screenshot (DA_STOP, PAINT_STOP).

The windows at 640x480 (apps/daui/daui.c: card aligned, in the middle):
Dex 560 x 400 at (40, 40); the Calendar 576 x 400 at (32, 40); the
Preferences 480 x 400 at (80, 40). The default dialog box: 224-415 x
192-287, YES (and OK in a message) at 232 + 0 / 360 + 0, 264. Dex's
and the Calendar's questions are the SDK's alerts (vr_alert, V148):
168-471 x 184-287, Yes at 408-455 x 262-277. Dex (V148): the search
field in the toolbar at (472, 24), the list's rows from 56.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import paint_script as ps  # noqa: E402

L = []
shots = []


def P(f, x, y, b, c=None):
    L.append('P(%d, %d, %d, %d),%s' % (f, x, y, b, '  /* %s */' % c if c else ''))


def K(f, ch, c=None):
    code = {'\r': '13', '\b': '8', '\t': '9', '\x1b': '27'}.get(ch, "'%s'" % ch.replace("'", "\\'"))
    L.append('K(%d, %s),%s' % (f, code, '  /* %s */' % c if c else ''))


def click(f, x, y, c=None, wait=12):
    P(f, x, y, 0, c)
    P(f + 1, x, y, 1)
    P(f + 3, x, y, 0)
    return f + wait


def typed(f, s, c=None):
    for i, ch in enumerate(s):
        K(f, ch, c if i == 0 else None)
        f += 5
    return f + 6


YES = (256, 272)                # the default box's YES (DBI_X_0, DBI_Y_2)
OKR = (384, 272)                # its OK or NO (DBI_X_2, DBI_Y_2)
AYES = (432, 270)               # (V148) an alert's Yes (the SDK's vr_alert: 38 x 13 cards
                                # at card 21, card row 23; Yes at card 30, row 78-93)


def write(path, title):
    with open(path, 'w') as o:
        o.write('/* gate da: %s, written by tests/da_script.py */\n' % title)
        for name, fr in shots:
            o.write('/* shot %s %d */\n' % (name, fr))
        o.write('\n'.join(L) + '\n')
    L.clear()
    shots.clear()


# ---------------------------------------------------------------- Dex
DX, DY = 40, 40
FIELD = [(DX + 472 + 20, DY + 24 + 8)] + [(DX + 320 + 20, DY + 72 + 24 * i + 8) for i in range(5)]


def dbtn(i):
    if i < 4:
        return DX + 232 + i * 80 + 36, DY + 200 + 8
    return DX + 232 + (i - 4) * 104 + 48, DY + 224 + 8


SAVE, NEW, DELETE, COPY, CONNECT, EXPORT, IMPORT = range(7)
ROW0 = (DX + 8 + 60, DY + 56 + 8)


def dex():
    f = 40
    cards = [('Alice Example', 'bbs.test:23', 'alice@example.org', '1 Main Street, Springfield', 'Sysop, "the" BBS'),
             ('Bob Builder', '555-0101', 'bob@example.org', '', ''),
             ('Carol Smith', '555-0199', '', 'Elm Road 7', 'Birthday, 3 May')]
    for n, card in enumerate(cards):
        if n:
            f = click(f, *dbtn(NEW), c='New', wait=30)
        f = click(f, *FIELD[1], c='the name field')
        for i, text in enumerate(card):
            if i:
                K(f, '\t')
                f += 6
            if text:
                f = typed(f, text, 'card %d field %d' % (n + 1, i + 1))
        f = click(f, *dbtn(SAVE), c='Save: the book written', wait=240)
    shots.append(('dex', f))
    f = click(f, *FIELD[0], c='the search field')
    f = typed(f, 'bo', 'search: "bo" finds Bob')
    shots.append(('dexfind', f + 30))
    f += 60
    K(f, '\b')
    K(f + 6, '\b')
    f += 40
    f = click(f, *dbtn(EXPORT), c='Export: DEX.CSV', wait=180)
    f = click(f, *ROW0, c='the first card: Alice', wait=30)
    f = click(f, *dbtn(COPY), c='Copy: the Text Scrap', wait=180)
    f = click(f, *dbtn(CONNECT), c='Connect: asked', wait=60)
    shots.append(('dexask', f - 10))    # (V148: the alert, with Dex's icon)
    f = click(f, *AYES, c='Yes: DEX.TEL, Veranda Term starts', wait=60)
    L.append('END(%d)' % (f + 20000))
    return f


# ---------------------------------------------------------------- the Calendar
CX, CY = 32, 40


def cbtn(i):
    return CX + 304 + i * 64 + 28, CY + 400 - 24 + 8


def cal():
    """the test build sets the clock to 2026-11-16 11:59:30: New offers
    12:00 with the alarm on; "Dentist"; Save; the close box"""
    f = 40
    f = click(f, *cbtn(0), c='New: 12:00, the alarm on, the text field', wait=30)
    f = typed(f, 'Dentist', 'the text')
    f = click(f, *cbtn(1), c='Save: Appointments, Veranda Alarms', wait=300)
    shots.append(('cal', f))
    f = click(f + 20, CX + 576 - 11, CY + 8, c='the close glyph (at the right, V79): RstrAppl', wait=60)
    L.append('END(%d)' % (f + 20000))


# ---------------------------------------------------------------- Preferences
PX, PY = 80, 40


def prow(r):
    return PY + 32 + r * 32 + 8


LESS, MORE, SWITCH = PX + 184 + 8, PX + 184 + 16 + 128 + 8, PX + 184 + 32
PSAVE = (PX + 296 + 40, PY + 400 - 24 + 8)


def prefs1():
    """the blanking 10 -> 2 minutes, the paper Cream, the ink Navy (Slate,
    the default since V74, -> Black -> Navy), the
    beep off, the pointer Fast, the desktop TopDesk; Save; close"""
    f = 40
    f = click(f, LESS, prow(0), c='blanking: 5 minutes', wait=20)
    f = click(f, LESS, prow(0), c='blanking: 2 minutes', wait=20)
    f = click(f, MORE, prow(1), c='paper: Cream (shown at once)', wait=20)
    f = click(f, MORE, prow(2), c='ink: Black', wait=20)
    f = click(f, MORE, prow(2), c='ink: Navy', wait=20)
    f = click(f, SWITCH, prow(3), c='beep: off', wait=20)
    f = click(f, MORE, prow(4), c='pointer: Fast', wait=20)
    f = click(f, MORE, prow(6), c='desktop: TopDesk', wait=20)
    f = click(f, *PSAVE, c='Save: Veranda Prefs, DESKTOP.cvt', wait=400)
    shots.append(('prefs', f))
    f = click(f + 20, PX + 480 - 11, PY + 8, c='the close glyph (at the right, V79): RstrAppl', wait=60)
    L.append('END(%d)' % (f + 20000))


PTHEME = (PX + 208 + 40, PY + 400 - 24 + 8)      # the Theme button (by Save)


def prefs3():
    """over the shell: the Theme page, the preset Veranda Blue -> Classic
    -> Graphite; Save; close"""
    f = 40
    f = click(f, *PTHEME, c='the Theme page', wait=40)
    f = click(f, MORE, prow(0), c='preset: Classic', wait=40)
    f = click(f, MORE, prow(0), c='preset: Graphite', wait=40)
    shots.append(('theme', f))
    f = click(f, *PSAVE, c='Save: Veranda Prefs (the theme in bytes 10-13)', wait=400)
    f = click(f + 20, PX + 480 - 11, PY + 8, c='the close glyph (at the right, V79): RstrAppl', wait=60)
    L.append('END(%d)' % (f + 20000))


def prefs4():
    """over the shell (Graphite): the Theme page, the preset back to
    Classic; Save; close"""
    f = 40
    f = click(f, *PTHEME, c='the Theme page', wait=40)
    f = click(f, LESS, prow(0), c='preset: Classic', wait=40)
    f = click(f, *PSAVE, c='Save', wait=400)
    f = click(f + 20, PX + 480 - 11, PY + 8, c='the close glyph (at the right, V79): RstrAppl', wait=60)
    L.append('END(%d)' % (f + 20000))


def prefs2():
    """the desktop back to the shell; Save; close"""
    f = 40
    f = click(f, LESS, prow(6), c="desktop: Veranda's shell", wait=20)
    f = click(f, *PSAVE, c='Save: DESKTOP.cvt deleted', wait=400)
    f = click(f + 20, PX + 480 - 11, PY + 8, c='the close glyph (at the right, V79): RstrAppl', wait=60)
    L.append('END(%d)' % (f + 20000))


# ---------------------------------------------------------------- Paint
def paint(wait_after, alarm_ok=None):
    ps.L.clear()
    ps.P(0, 320, 240, 0)
    f = ps.click(30, *ps.colour(2), c='colour 2')
    f = ps.drag(f, [(80 + i * 10, 100 + (i % 5) * 12) for i in range(30)], 'pencil: a stroke')
    f = ps.click(f, *ps.TOOL['box'], c='tool: filled rectangle')
    f = ps.drag(f, [(120, 200), (200, 260), (300, 330)], 'a filled rectangle')
    f = ps.menu(f, 'paint', 1, 'Paint: desk accessory: the list, the only one selected')
    f = ps.click(f + 300, *ps.OPEN, c='OPEN: GetFile starts the accessory (its own script plays)')
    f += 60
    if alarm_ok:
        f += alarm_ok
        ps.shots.append(('alarm', f - 60))
        f = ps.click(f, *OKR, c='the alarm box: OK')
        f += 120
    f = ps.drag(f + wait_after, [(420, 300), (500, 360), (560, 420)], 'back in Paint: a filled rectangle')
    f += 300
    ps.L.append('END(%d)' % f)
    out = list(ps.L)
    sh = list(ps.shots)
    ps.L.clear()
    ps.shots.clear()
    return out, sh


def write_paint(path, title, lines, sh):
    with open(path, 'w') as o:
        o.write('/* gate da: %s, written by tests/da_script.py */\n' % title)
        for name, fr in sh:
            o.write('/* shot %s %d */\n' % (name, fr))
        o.write('\n'.join(lines) + '\n')


def sub(out, name):
    d = os.path.join(out, name)
    os.makedirs(d, exist_ok=True)
    return d


def main():
    out = sys.argv[1]
    dex()
    write(os.path.join(sub(out, 'dex'), 'da_script.h'), "Dex's session")
    cal()
    write(os.path.join(sub(out, 'cal'), 'da_script.h'), "the Calendar's session")
    prefs1()
    write(os.path.join(sub(out, 'prefs1'), 'da_script.h'), "Preferences' first session")
    prefs2()
    write(os.path.join(sub(out, 'prefs2'), 'da_script.h'), "Preferences' second session")
    prefs3()
    write(os.path.join(sub(out, 'prefs3'), 'da_script.h'), "Preferences' theme: Graphite")
    prefs4()
    write(os.path.join(sub(out, 'prefs4'), 'da_script.h'), "Preferences' theme: Classic")
    write_paint(os.path.join(sub(out, 'paint'), 'da_paint.h'), "Paint's session around an accessory", *paint(60))


if __name__ == '__main__':
    main()
