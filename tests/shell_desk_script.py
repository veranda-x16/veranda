#!/usr/bin/env python3
"""Gate shell, Shell 2 (DECISIONS V70): the desktop and its windows.

usage: shell_desk_script.py make <folder> <AppOne.cvt>  the fixtures
       shell_desk_script.py script <folder> [extra...] SHELL.TST
       shell_desk_script.py check <folder> <console> [sd.img]
                                                      the session's results

The run folder (or card): /VERANDA (SHELL.cvt), /DOCUMENTS (the shell
starts there, window 0: DECISIONS V71), Docs/Readme.txt, Many (60 files), AppOne.cvt (an application),
Big.bin, Junk.txt, Note.txt, Pic.bmp (a 1-bit BMP), each with a date of
its own.

Part 0 (the shell in /DOCUMENTS, window 0 in its default place):
  window 0's resize grip dragged (256 x 200), its title band dragged down
  (y 256: CopyRect, the rest drawn again); the card's desktop icon double-
  clicked: window 1 on the top folder; its title band dragged to the top
  left, its grip to 536 x 256; Note.txt dragged from window 1 into
  window 0 (a copy into /DOCUMENTS); Junk.txt dragged onto the trash;
  Pic.bmp onto the printer (Pic.pdf); AppOne dragged onto the desktop (a
  pin); window 1 by name (the list), its Size header clicked, by date;
  its scroll bar's down arrow; Look 2's toolbar and sidebar (DECISIONS
  V77): the search "Pic", the place Documents, back, forward, the first
  crumb (the top folder), the zoom box twice; window 0 up to the top
  folder, into Many (61 entries, 6 a page): the status bar's page arrow
  (page 2), page > next (3), page > previous (2); File > Set as Mods
  folder (DECISIONS V84): window 0's folder, Many, is the Mods place's
  (MODS.CFG), window 1's place Mods goes there; the pin double-clicked:
  AppOne starts (APP 1 RAN) and goes back to the shell.
Part 1: the shell again, both windows where they were (the desk file);
  window 1's first crumb (the top folder), then its place Mods: Many again
  (read from MODS.CFG); the end (SHELL DONE, a dump).
"""
import os
import re
import struct
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import shell_script as S  # noqa: E402

W0 = S.WIN0                     # (16, 32, 495, 399)
W0R = (16, 256, 271, 455)       # resized (256 x 200: no sidebar, 3 x 2 icons) and moved
W1 = S.WIN1                     # its default place (160, 120, 543, 399)
W1R = (8, 24, 543, 279)         # moved and resized (536 x 256: 5 x 2 icons beside the scroll bar (V151), 11 list rows)
DATES = {
    'Docs': '2021-02-03 04:05', 'Many': '2021-06-07 08:09',
    'AppOne.cvt': '2022-10-11 12:13', 'Big.bin': '2025-05-06 07:08', 'Junk.txt': '2023-09-10 11:12',
    'Note.txt': '2024-01-02 03:04', 'Pic.bmp': '2020-12-24 18:30',
}


def stamp(p, d):
    t = time.mktime(time.strptime(d, '%Y-%m-%d %H:%M'))
    os.utime(p, (t, t))


def bmp(w, h):
    """a 1-bit BMP: a frame and a diagonal"""
    stride = (w + 31) // 32 * 4
    rows = []
    for y in range(h):
        r = bytearray(stride)
        for x in range(w):
            if x in (0, w - 1) or y in (0, h - 1) or x == y * w // h:
                r[x // 8] |= 0x80 >> (x % 8)
        rows.append(bytes(r))
    pix = b''.join(reversed(rows))
    pal = bytes([255, 255, 255, 0, 0, 0, 0, 0])
    off = 14 + 40 + len(pal)
    return (b'BM' + struct.pack('<IHHI', off + len(pix), 0, 0, off)
            + struct.pack('<IiiHHIIiiII', 40, w, h, 1, 1, 0, len(pix), 2835, 2835, 2, 2) + pal + pix)


def make(d, app):
    os.makedirs(os.path.join(d, 'VERANDA'), exist_ok=True)
    os.makedirs(os.path.join(d, 'DOCUMENTS'), exist_ok=True)
    os.makedirs(os.path.join(d, 'Docs'), exist_ok=True)
    os.makedirs(os.path.join(d, 'Many'), exist_ok=True)
    open(os.path.join(d, 'Docs', 'Readme.txt'), 'w').write('read me\n')
    for i in range(60):
        open(os.path.join(d, 'Many', 'f%02d.txt' % i), 'w').write('file %d\n' % i)
    open(os.path.join(d, 'Note.txt'), 'w').write('a note\n')
    open(os.path.join(d, 'Junk.txt'), 'w').write('junk\n')
    open(os.path.join(d, 'Big.bin'), 'wb').write(bytes((i * 7) & 255 for i in range(20000)))
    open(os.path.join(d, 'Pic.bmp'), 'wb').write(bmp(64, 32))
    open(os.path.join(d, 'AppOne.cvt'), 'wb').write(open(app, 'rb').read())
    for n, t in DATES.items():
        stamp(os.path.join(d, n), t)


def root(d, extra, gone=(), new=()):
    dirs = [n for n in os.listdir(d) if os.path.isdir(os.path.join(d, n))]
    files = [n for n in os.listdir(d) if not os.path.isdir(os.path.join(d, n))]
    files = sorted((set(files) | {'SHELL.TST', 'SHELL.STP'} | set(extra) | set(new)) - set(gone))
    return S.listing(dirs, files)


def script(d, extra):
    p = S.Part()
    p.wait(30)
    # window 0: its corner, then its title bar
    p.drag(S.status(W0)['grip'], (268, 227))
    p.wait(30)
    p.drag((130, W0[1] + 4), (130, 260))
    p.wait(30)
    # the card: window 1 on the top folder
    p.dbl(*S.DESK['card'])
    p.wait(60)
    p.drag((350, W1[1] + 4), (198, 28))
    p.wait(30)
    p.drag(S.status((8, 24, 8 + W1[2] - W1[0], 24 + W1[3] - W1[1]))['grip'], (543, 275))
    p.wait(40)
    top = root(d, extra)
    c1 = lambda n, r=None: S.cell((r or top).index(n), W1R, 5)    # noqa: E731
    # Note.txt into window 0 (a copy), Junk.txt onto the trash, Pic.bmp
    # onto the printer, AppOne onto the desktop (a pin)
    p.drag(c1('Note.txt'), S.cell(5, W0R, 3))
    p.wait(60)
    p.drag(c1('Junk.txt'), S.DESK['trash'])
    p.wait(60)
    top = root(d, extra, gone=['Junk.txt'])
    p.drag(c1('Pic.bmp', top), S.DESK['printer'])
    p.wait(90)
    top = root(d, extra, gone=['Junk.txt'], new=['Pic.pdf'])
    p.drag(c1('AppOne.cvt', top), (420, 300))
    p.wait(60)
    # the list: by name, the Size header, by date; the scroll bar
    p.menu('view', 'name')
    p.wait(40)
    p.click((W1R[0] // 8 + S.SIDEW) * 8 + 215, W1R[1] + S.TITLEH + S.TOOLH + 6)
    p.wait(40)
    p.menu('view', 'date')
    p.wait(40)
    p.click(W1R[2] - 4, W1R[3] - S.STATH - 5)     # the scroll bar's down arrow
    p.wait(40)
    # Look 2's toolbar and sidebar (window 1): the search, a place, back,
    # forward, the first crumb; the zoom box twice
    tb = S.toolbar(W1R)
    p.click(*tb['search'])
    p.wait(30)
    for c in b'Pic':
        p.key(c)
    p.key(13)
    p.wait(60)
    p.click(*S.place(2, W1R))                   # Documents
    p.wait(60)
    p.click(*tb['back'])
    p.wait(60)
    p.click(*tb['forward'])
    p.wait(60)
    p.click(*tb['crumb0'])                      # the card's top folder
    p.wait(60)
    p.click(W1R[2] - 28, W1R[1] + 8)            # zoom
    p.wait(60)
    p.click(551 - 28, 24 + 8)                   # (zoomed: x 8-551) zoom again
    p.wait(60)
    # window 0: up to the top folder, into Many; its pages
    p.dbl(*S.cell(0, W0R, 3))
    p.wait(40)
    p.dbl(*S.cell(top.index('Many'), W0R, 3))
    p.wait(60)
    p.click(*S.status(W0R)['next'])             # the scroll bar's track: a page (V151)
    p.wait(30)
    p.menu('page', 'next')
    p.wait(30)
    p.menu('page', 'previous')
    p.wait(30)
    # (V84) File > Set as Mods folder: window 0's folder; window 1's place
    # Mods goes there
    p.menu('file', 'mods')
    p.wait(60)
    p.click(*S.place(3, W1R))
    p.wait(90)
    # the pin: AppOne starts, and comes back
    p.dbl(*S.desk_pin(0))
    p.end(S.END_STOP)
    q = S.Part()
    q.wait(60)
    q.click(*tb['crumb0'])                      # window 1: the top folder
    q.wait(60)
    q.click(*S.place(3, W1R))                   # Mods: Many, from MODS.CFG
    q.wait(90)
    q.end(S.END_DONE)
    S.write(os.path.join(d, 'SHELL.TST'), [p, q])


def fail(m):
    print('FAIL  ' + m)
    sys.exit(1)


def lines(console):
    t = open(console, 'rb').read().decode('latin-1').replace('\r', '')
    t = re.sub(r'\\X[0-9A-F]{2}', '', t)
    return re.findall(r'(?:SHELL [A-Z]|APP )[^\n]*?(?=CD:|SHELL [A-Z]|APP |\n|$)', t)


def check(d, console, img=None):
    log = lines(console)
    want = ['SHELL WINDOW 0 SIZE 256 200', 'SHELL WINDOW 0 AT 16 256', 'SHELL WINDOW 1 OPEN /',
            'SHELL WINDOW 1 AT 8 24', 'SHELL WINDOW 1 SIZE 536 256',
            'SHELL DROP COPY Note.txt TO /DOCUMENTS', 'SHELL COPIED 1', 'SHELL TRASHED Junk.txt AS Junk.txt',
            'SHELL PRINTED Pic.bmp AS Pic.pdf', 'SHELL PINNED AppOne.cvt',
            'SHELL LIST 1 BY NAME', 'SHELL LIST 1 BY SIZE', 'SHELL LIST 1 BY DATE', 'SHELL PAGE 1 FIRST 1',
            # Look 2 (DECISIONS V77): the search, a place, back, forward, a crumb, the zoom box
            'SHELL SEARCH Pic', 'SHELL STATUS 1 /: 2 files, ', 'SHELL STATUS 1 /DOCUMENTS: ',
            'SHELL STATUS 1 /: ', 'SHELL STATUS 1 /DOCUMENTS: ', 'SHELL STATUS 1 /: ',
            'SHELL WINDOW 1 ZOOMED 544 448', 'SHELL WINDOW 1 UNZOOMED 536 256',
            'SHELL PAGE 0 FIRST 6', 'SHELL PAGE 0 FIRST 12', 'SHELL PAGE 0 FIRST 6',
            # File > Set as Mods folder (V84), the place Mods; after the restart, again
            'SHELL MODS /Many', 'SHELL STATUS 1 /Many: 60 files, ', 'APP 1 RAN',
            'SHELL STATUS 1 /: ', 'SHELL STATUS 1 /Many: 60 files, ', 'SHELL DONE']
    at = 0
    for w in want:
        for i in range(at, len(log)):
            if log[i].strip() == w or (w.endswith(' ') and log[i].startswith(w)):
                at = i + 1
                break
        else:
            fail('the console has no "%s" after "%s"' % (w, log[at - 1] if at else '(the start)'))
    print('ok    the console in order: ' + ', '.join(want))
    # the files
    f = (lambda *p: os.path.join(d, *p))
    if open(f('DOCUMENTS', 'Note.txt'), 'rb').read() != open(f('Note.txt'), 'rb').read():
        fail('DOCUMENTS/Note.txt is not a copy of Note.txt')
    if os.path.exists(f('Junk.txt')) or open(f('VERANDA', '.SYSTEM', 'TRASH', 'Junk.txt')).read() != 'junk\n':
        fail('Junk.txt is not in the trash')
    pdf = open(f('Pic.pdf'), 'rb').read()
    if not pdf.startswith(b'%PDF-') or b'/CCITTFaxDecode' not in pdf or not pdf.rstrip().endswith(b'%%EOF'):
        fail('Pic.pdf is not a PDF with a picture')
    dsk = open(f('VERANDA', '.SYSTEM', 'SHELL.DSK'), 'rb').read()
    if dsk[:4] != b'VSD\x04' or b'AppOne.cvt' not in dsk:       # (version 3: long pin names, V82; the dock, V83;
        fail('the desk file has no pin')                        # version 4: up to ten pins, V163)
    if dsk[3] != 4:
        fail('the desk file is not version 4 (V163)')
    mods = open(f('VERANDA', '.SYSTEM', 'MODS.CFG'), 'rb').read()
    if mods != b'/Many\n':
        fail('MODS.CFG holds %r, want the Mods folder /Many and a line feed' % mods)
    print('ok    the files: DOCUMENTS/Note.txt = Note.txt (dragged: a copy), Junk.txt in VERANDA/.SYSTEM/TRASH, Pic.pdf '
          '(%d bytes, a CCITT G4 picture), VERANDA/.SYSTEM/SHELL.DSK with the pin AppOne.cvt, '
          'VERANDA/.SYSTEM/MODS.CFG "/Many" (V84)' % len(pdf))
    # the lists: by name, size, date
    i0 = log.index('SHELL LIST 1 BY NAME')
    lists = {}
    for k in ('NAME', 'SIZE', 'DATE'):
        i = log.index('SHELL LIST 1 BY ' + k, i0)
        rows = []
        for r in log[i + 1:]:
            if not r.startswith('SHELL ROW '):
                break
            rows.append(r[10:].split('|'))
        lists[k] = rows
    rows = lists['NAME']
    names = [r[0] for r in rows]
    if sorted(names) != sorted(lists['SIZE'][i][0] for i in range(len(rows))):
        fail('the lists differ')
    for r in rows:
        name, size, date, typ = r
        p = f(name)
        if not os.path.exists(p):
            fail('row %s: no such file on the host' % name)
        if os.path.isdir(p):
            if size != '-' or typ != 'folder':
                fail('row %s: %s %s, want a folder' % (name, size, typ))
        elif name not in ('SHELL.STP', 'console.txt') and int(size) != os.path.getsize(p):
            fail('row %s: size %s, the file has %d' % (name, size, os.path.getsize(p)))
        if name in DATES and date != DATES[name]:
            fail('row %s: date %s, want %s' % (name, date, DATES[name]))
    key = lambda r: (0 if r[3] == 'folder' else 1)                     # noqa: E731
    if names != [r[0] for r in sorted(rows, key=lambda r: (key(r), r[0].lower()))]:
        fail('by name: %s' % names)
    sz = lists['SIZE']
    if [r[0] for r in sz] != [r[0] for r in sorted(sz, key=lambda r: (key(r), -int(r[1]) if r[1] != '-' else 0,
                                                                   r[0].lower()))]:
        fail('by size: %s' % [r[0] for r in sz])
    dt = lists['DATE']
    if [r[0] for r in dt] != [r[0] for r in sorted(dt, key=lambda r: (key(r), [-ord(c) for c in r[2]],
                                                                   r[0].lower()))]:
        fail('by date: %s' % [r[0] for r in dt])
    print('ok    the list (%d rows): sizes and dates as the files have them (%s); by name, by size (the largest '
          'first), by date (the newest first), folders first' % (len(rows), ', '.join(
              '%s %s' % (n, DATES[n]) for n in ('Note.txt', 'Big.bin') if n in DATES)))
    # the status line, after the session: window 1's top folder
    st = [r for r in log if r.startswith('SHELL STATUS 1 /:')]
    if not st:
        fail('no status line for window 1')
    m = re.match(r'SHELL STATUS 1 /: (\d+) files?, (\d) selected, (\d+) Kbytes used, (\d+) Kbytes free', st[-1])
    if not m:
        fail('the status line: %s' % st[-1])
    n, used = 0, 0
    for e in os.listdir(d):
        if e in ('.', '..') or (not img and e == 'dump.bin'):  # (the emulator's dump, at the end)
            continue
        n += 1
        if os.path.isfile(f(e)) and e != 'console.txt':
            used += os.path.getsize(f(e))
    if img:
        sys.path.insert(0, os.path.join(HERE, '..', 'tools'))
        import vcard
        free = vcard.Fat32(img).free_bytes() // 1024
        if int(m.group(4)) != free:
            fail('the status line: %s Kbytes free, the card has %d' % (m.group(4), free))
    # (on the host folder console.txt grows after the listing: its size is not counted)
    if int(m.group(1)) != n or (img and int(m.group(3)) != (used + 1023) // 1024) \
            or (not img and not 0 <= int(m.group(3)) - (used + 1023) // 1024 <= 64):
        fail('the status line: %s; the folder has %d entries, %d bytes' % (st[-1], n, used))
    print('ok    the status line after the session (window 1, the top folder): %s; the folder has %d entries, '
          '%d bytes%s' % (st[-1][18:], n, used, ', the card %s Kbytes free' % m.group(4) if img else ''))


def main():
    a = sys.argv[1:]
    if len(a) >= 3 and a[0] == 'make':
        make(a[1], a[2])
    elif len(a) >= 2 and a[0] == 'script':
        script(a[1], a[2:])
    elif len(a) >= 3 and a[0] == 'check':
        check(a[1], a[2], a[3] if len(a) > 3 else None)
    else:
        sys.exit(__doc__)


if __name__ == '__main__':
    main()
