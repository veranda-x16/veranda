#!/usr/bin/env python3
"""Gate shell, the dragged icon's ghost (DECISIONS V193): the run folder
and SHELL.TST (tests/shell_script.py's records), the checks on the dump
(the sprite attributes and the picture in VRAM), and the screenshots with
the sprites drawn (tools/vram2png.py's compose() has none).

usage: shell_ghost_script.py make <folder> <look> <wall> [apps]   the fixtures
       shell_ghost_script.py script <folder> <run>         SHELL.TST
       shell_ghost_script.py check <folder> <run>          the dump
       shell_ghost_script.py png <dump> <out.png>          with the sprites

The fixtures: the card's layout (/VERANDA/SHELL.cvt, /VERANDA/APPS,
/DOCUMENTS where the shell starts): /DOCUMENTS holds Letter.cvt (a
geoWrite document) and, when a package's APPS folder is given, two of
its applications (their own colour icons), else two more documents; the
package's APPS in /VERANDA/APPS and PINS.DEF: the dock's default pins.
<look>: light (no settings: Sunroom), dark (Look 2's preset in dark mode),
wall (Sunroom on the tile desktop: <wall>, tools/mkwall.py's Dusk.cvt made
by the gate, in /VERANDA/WALLPAPERS and WALLPAPER.CFG naming it; else -).

<run>:
  mid    Letter pressed in window 0 and dragged to the desktop's middle
         (the button held), the end: the ghost shown
  over   the same, then on over the dock (the button held: its second pin,
         else its trash), the end
  pin    the dock's first pin dragged up (held), the end (with pins)
  desk   the desktop's card icon dragged left (held), the end
  after  Letter dragged into its own window's empty part and let go (a
         drop there does nothing), the end: the ghost gone
  esc    Letter dragged onto the dock's trash, Esc before the release: the
         ghost gone, nothing deleted
check: mid, over, desk, pin: sprite 2 on (8 bpp, 32 x 32, its picture at
$17800, in front of the layers), at the pointer less the press's place in
the icon, its picture's pixels each the screen's colour there (the first
pixel's colour and every other pixel left out), at least 40 of them;
after, esc: sprite 2 off; esc: Letter.cvt still in /DOCUMENTS.
"""
import os
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, '..', 'tools'))
import shell_script as S  # noqa: E402
import shell_trash_script as T  # noqa: E402
import vram2png  # noqa: E402

NPINS = 6                       # (shell/pins.c's defaults, all in a package)
MIDDLE = (300, 250)             # where the drags go (window 0's body: the icons' grid starts at its top left)
DESKMID = (540, 240)            # (the desktop left of its icons' column, right of window 0)
VRAM = 131072
ATTR = 0x1FC00


def files(d):
    return S.listing([], os.listdir(os.path.join(d, 'DOCUMENTS')))


def make(d, look, wall, apps):
    os.makedirs(os.path.join(d, 'VERANDA', 'APPS'), exist_ok=True)
    os.makedirs(os.path.join(d, 'VERANDA', '.SYSTEM'), exist_ok=True)
    doc = os.path.join(d, 'DOCUMENTS')
    os.makedirs(doc, exist_ok=True)
    open(os.path.join(doc, 'Letter.cvt'), 'wb').write(T.doc('Letter'))
    names = sorted(n for n in os.listdir(apps) if n.endswith('.cvt'))[:2] if apps else []
    for n in names:
        shutil.copy(os.path.join(apps, n), doc)
    if apps:                            # (the package's programs: the dock's default pins, PINS.DEF)
        for n in os.listdir(apps):
            shutil.copy(os.path.join(apps, n), os.path.join(d, 'VERANDA', 'APPS'))
        open(os.path.join(d, 'PINS.DEF'), 'wb').close()
    for i in range(2 - len(names)):
        open(os.path.join(doc, 'Note %d.cvt' % i), 'wb').write(T.doc('Note %d' % i))
    if look == 'wall':
        w = os.path.join(d, 'VERANDA', 'WALLPAPERS')
        os.makedirs(w, exist_ok=True)
        shutil.copy(wall, w)
        c = bytearray(64)               # (gate wall's WALLPAPER.CFG: the picture's name, its folder)
        c[0:3] = b'WP\x01'
        n = os.path.basename(wall)[:-4].encode()
        c[8:8 + len(n)] = n
        c[32:51] = b'/VERANDA/WALLPAPERS'
        open(os.path.join(d, 'VERANDA', '.SYSTEM', 'WALLPAPER.CFG'), 'wb').write(bytes(c))
    if look == 'dark':
        import check_theme
        check_theme.prefs(os.path.join(d, 'VERANDA', '.SYSTEM', 'Veranda Prefs.cvt'), 5, 13, 4, 0, 129)


def cell_of(d, name):
    """the middle of name's icon in window 0 (the shell starts in /DOCUMENTS)"""
    return S.cell(files(d).index(name) + 1)     # (after '..')


def held(p, a, b, steps=8):
    p.at(a[0], a[1], 0, 4)
    p.at(a[0], a[1], 1, 4)
    for i in range(1, steps + 1):
        p.at(a[0] + (b[0] - a[0]) * i // steps, a[1] + (b[1] - a[1]) * i // steps, 1, 3)
    p.at(b[0], b[1], 1, 20)


def script(d, run):
    p = S.Part()
    p.wait(40)
    letter = cell_of(d, 'Letter.cvt')
    if run in ('mid', 'over'):
        held(p, letter, DESKMID)
        if run == 'over':
            held_on(p, DESKMID, dockspot(d))
    elif run == 'desk':
        held(p, S.DESK['card'], DESKMID)
    elif run == 'pin':
        held(p, S.dock_item(0, NPINS), DESKMID)
    elif run == 'after':
        held(p, letter, MIDDLE)
        p.at(MIDDLE[0], MIDDLE[1], 0, 40)
    elif run == 'esc':
        held(p, letter, S.dock_item(0, 0))      # (the dock's trash: no pins)
        p.key(0x1B, 10)
        p.at(*S.dock_item(0, 0), 0, 60)
    p.wait(20)
    p.end(S.END_DONE)
    S.write(os.path.join(d, 'SHELL.TST'), [p])
    open(os.path.join(d, 'GHOST.TXT'), 'w').write('%s %d %d %d %d\n' % ((run,) + tuple(press_end(d, run))))


def dockspot(d):
    pins = os.path.exists(os.path.join(d, 'PINS.DEF'))
    return S.dock_item(1, NPINS) if pins else S.dock_item(0, 0)


def held_on(p, a, b, steps=8):
    for i in range(1, steps + 1):
        p.at(a[0] + (b[0] - a[0]) * i // steps, a[1] + (b[1] - a[1]) * i // steps, 1, 3)
    p.at(b[0], b[1], 1, 20)


def press_end(d, run):
    letter = cell_of(d, 'Letter.cvt')
    return {'mid': letter + DESKMID, 'over': letter + dockspot(d), 'pin': S.dock_item(0, NPINS) + DESKMID, 'desk': S.DESK['card'] + DESKMID,
            'after': letter + MIDDLE, 'esc': letter + S.dock_item(0, 0)}[run]


def sprite(v, n):
    a = v[ATTR + 8 * n:ATTR + 8 * n + 8]
    return {'addr': (a[0] | (a[1] & 15) << 8) << 5, 'bpp8': a[1] >> 7, 'x': a[2] | (a[3] & 3) << 8,
            'y': a[4] | (a[5] & 3) << 8, 'z': (a[6] >> 2) & 3, 'hf': a[6] & 1, 'vf': a[6] & 2,
            'w': 8 << ((a[7] >> 4) & 3), 'h': 8 << (a[7] >> 6), 'pal': a[7] & 15}


def check(d, run):
    v = vram2png.section(os.path.join(d, 'dump.bin'))
    _, px, py, ex, ey = open(os.path.join(d, 'GHOST.TXT')).read().split()
    px, py, ex, ey = int(px), int(py), int(ex), int(ey)
    s = sprite(v, 2)
    if run in ('after', 'esc'):
        if s['z']:
            sys.exit('shell_ghost_script: %s: sprite 2 still shown: %s' % (run, s))
        if run == 'esc' and not os.path.exists(os.path.join(d, 'DOCUMENTS', 'Letter.cvt')):
            sys.exit('shell_ghost_script: esc: Letter.cvt was deleted (the drop after Esc)')
        print('shell_ghost_script: %s: the ghost gone (sprite 2 off)%s' % (
            run, '; Letter.cvt kept' if run == 'esc' else ''))
        return
    want = {'addr': 0x17800, 'bpp8': 1, 'z': 3, 'w': 32, 'h': 32, 'pal': 0, 'hf': 0, 'vf': 0}
    bad = {k: s[k] for k in want if s[k] != want[k]}
    if bad:
        sys.exit('shell_ghost_script: %s: sprite 2 %s, not %s' % (run, s, want))
    cx, cy = px - 16, py - 16                   # (the icon's tile: the press at its middle)
    if (s['x'], s['y']) != (ex - 16, ey - 16):
        sys.exit('shell_ghost_script: %s: the ghost at %d, %d, not %d, %d (the pointer %d, %d less 16, 16)'
                 % (run, s['x'], s['y'], ex - 16, ey - 16, ex, ey))
    scr = vram2png.compose(v)
    n = 0
    for y in range(32):
        for x in range(32):
            c = v[0x17800 + y * 32 + x]
            if not c:
                continue
            if (x + y) & 1:
                sys.exit('shell_ghost_script: %s: the ghost\'s pixel %d, %d is not left out (every other)' % (run, x, y))
            if vram2png.rgb(v, c) != scr[cy + y][cx + x]:
                sys.exit('shell_ghost_script: %s: the ghost\'s pixel %d, %d (entry %d, %s) is not the screen\'s %s'
                         % (run, x, y, c, vram2png.rgb(v, c), scr[cy + y][cx + x]))
            n += 1
    if n < 40:
        sys.exit('shell_ghost_script: %s: the ghost has %d pixels' % (run, n))
    print('shell_ghost_script: %s: the ghost shown at %d, %d (the pointer %d, %d), %d pixels, each the screen\'s '
          'colour at the icon (%d, %d)' % (run, s['x'], s['y'], ex, ey, n, cx, cy))


def png(dump, out):
    from PIL import Image
    v = vram2png.section(dump)
    rows = vram2png.compose(v)
    img = Image.new('RGB', (640, 480))
    px = img.load()
    for y, row in enumerate(rows):
        for x, c in enumerate(row):
            px[x, y] = c
    video = v[VRAM]
    for n in range(7, -1, -1) if video & 0x40 else ():     # (the lower index in front)
        s = sprite(v, n)
        if not s['z']:
            continue
        for y in range(s['h']):
            for x in range(s['w']):
                if s['bpp8']:
                    c = v[s['addr'] + y * s['w'] + x]
                else:
                    b = v[s['addr'] + (y * s['w'] + x) // 2]
                    c = b & 15 if x & 1 else b >> 4
                    c = c and c + 16 * s['pal']
                X, Y = (s['x'] + (s['w'] - 1 - x if s['hf'] else x)) & 1023, (s['y'] + y) & 1023
                if c and X < 640 and Y < 480:
                    px[X, Y] = vram2png.rgb(v, c)
    img.save(out)


def main():
    a = sys.argv[1:]
    if len(a) >= 4 and a[0] == 'make':
        make(a[1], a[2], a[3], a[4] if len(a) > 4 else None)
    elif len(a) == 3 and a[0] == 'script':
        script(a[1], a[2])
    elif len(a) == 3 and a[0] == 'check':
        check(a[1], a[2])
    elif len(a) == 3 and a[0] == 'png':
        png(a[1], a[2])
    else:
        sys.exit(__doc__)


if __name__ == '__main__':
    main()
