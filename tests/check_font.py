#!/usr/bin/env python3
"""Gate font checks (tests/font.s): fonts from RAM banks (DECISIONS V62).

usage: check_font.py <dump.bin> <console.txt> <fonts dir> <outdir>
       check_font.py --fonted <saved.cvt> <original.cvt>
       check_font.py --paint <dump.bin> <fonts dir> <outdir>

- the console: FontList (from a folder, the current directory kept),
  FontSizes, the built-in fonts, the errors, each test record's handle
  and FontInfo
- the screen: each test record's line in every style drawn from the
  program's memory (top half) equals the same line drawn from RAM banks
  (240 rows below) byte for byte, and its plain part equals the record
  drawn by tools/fontcvt.py
- italic (V122): an italic run's lean drawn whole, before plain text, at
  a string's end and before the next WPutString, as fontcvt.render_runs
- timings: the system font at most 250 us a character; the banked fonts
"""
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'tools'))
import fontcvt  # noqa: E402

W = 80
failures = 0
TESTS = [('Gate Sans', 9, 4), ('Gate Sans', 12, 20), ('Gate Sans', 18, 40), ('Gate Sans', 27, 66),
         ('Gate Mono', 10, 100)]
ITESTS = [('Gate Sans', 27, 124), ('Gate Sans', 18, 156), ('Gate Mono', 10, 180),   # tests/font.s 2b
          ('Gate Sans', 9, 113)]        # (Gate Sans 9: the system font's record)
IRUNS = [('Italic', 'i'), ('plain', ''), ('Wf', 'ib'), ('Hm', ''), ('u', 'u'), ('lW', 'i')]


def check(cond, what):
    global failures
    print(('ok    ' if cond else 'FAIL  ') + what)
    if not cond:
        failures += 1


def png(path, v, y0=0, y1=480):
    try:
        from PIL import Image
    except ImportError:
        return
    img = Image.new('1', (640, y1 - y0))
    px = img.load()
    for y in range(y0, y1):
        for c in range(W):
            b = v[W * y + c]
            for k in range(8):
                px[c * 8 + k, y - y0] = 0 if b & (0x80 >> k) else 1
    img.save(path)


def crop(path, v, y, h, w, scale=3):
    """rows y .. y + h + 1, columns 0 .. w - 1, enlarged"""
    try:
        from PIL import Image
    except ImportError:
        return
    img = Image.new('1', (w, h + 2))
    px = img.load()
    for r in range(h + 2):
        for x in range(w):
            px[x, r] = 0 if v[W * (y + r) + x // 8] & (0x80 >> (x % 8)) else 1
    img.resize((w * scale, (h + 2) * scale)).save(path)


def glyphs(f):
    """its glyphs: 32-127, and $A0-$FF in an extended record (V141)"""
    return [fontcvt.glyph(f, c) for c in list(range(32, 128)) + (list(range(0xA0, 0x100)) if f.get('ext') else [])]


def scale(gl, base, ns, size):
    """apps/fonted's new_size: nearest pixel, its integer arithmetic"""
    oh = len(gl[0])
    nh = oh * ns // size
    out = []
    for g in gl:
        w = len(g[0])
        nw = w * ns // size
        if w and not nw:
            nw = 1
        out.append([[g[r * oh // nh][x * w // nw] for x in range(nw)] for r in range(nh)])
    nb = (base + 1) * nh // oh
    return out, nb - 1 if nb else 0


def fonted(saved, orig):
    """the Font Editor's session (tests/font_script.py): Gate Sans 12's A
    changed and widened, saved; then size 24 made from it, saved"""
    try:
        name, fid, fonts = fontcvt.check(saved, [9, 12, 18, 24, 27], 'Gate Sans')
    except fontcvt.FontError as e:
        check(False, 'the saved file: %s' % e)
        return failures
    check(True, 'the saved file is a valid GEOS font: "%s", ID %d, sizes 9 12 18 24 27, the info block\'s list too'
          % (name, fid))
    n0, fid0, rec0, h0 = fontcvt.read_cvt(open(orig, 'rb').read())
    n1, fid1, rec1, h1 = fontcvt.read_cvt(open(saved, 'rb').read())
    check(fid0 == fid1 and all(rec0[s] == rec1[s] for s in (9, 18, 27)),
          'sizes 9, 18 and 27 as they were, byte for byte; the font ID kept')
    f0 = fontcvt.parse_record(rec0[12])
    want = glyphs(f0)
    a = [row + [0] for row in want[ord('A') - 32]]           # Width +
    a[0][0] = 1
    a[11][1] = 1
    for x in range(6):
        a[10][x] = 1
    want[ord('A') - 32] = a
    got = glyphs(fonts[12])
    check(got == want and fonts[12]['baseline'] == f0['baseline'] and fonts[12]['height'] == 12
          and fonts[12]['ext'] == f0['ext'],
          'size 12: A with (0, 0), (1, 11) and row 10 (0-5) set and a column more; the other %d glyphs as they were%s'
          % (len(want) - 1, ' ($A0-$FF of the extended record kept: V141)' if f0['ext'] else ''))
    g24, b24 = scale(want, f0['baseline'], 24, 12)
    check(glyphs(fonts[24]) == g24 and fonts[24]['baseline'] == b24 and fonts[24]['height'] == 24
          and fonts[24]['ext'] == f0['ext'],
          'size 24 (new): size 12 as edited, scaled to 24 rows (nearest pixel), baseline %d%s'
          % (b24, ', $A0-$FF too' if f0['ext'] else ''))
    return failures


def paint(dump, fonts, out):
    """Paint's text tool in Gate Sans 18 (tests/font_script.py): "Veranda"
    at (200, 300), the text's top (GetString's y)"""
    v = open(dump, 'rb').read()
    n, fid, recs, hdr = fontcvt.read_cvt(open(os.path.join(fonts, 'Gate Sans.cvt'), 'rb').read())
    f = fontcvt.parse_record(recs[18])
    rows = fontcvt.render(f, 'Veranda')
    top = 300
    ok = True
    for r in range(f['height']):
        for x in range(len(rows[0]) + 8):
            p = (v[W * (top + r) + (200 + x) // 8] >> (7 - (200 + x) % 8)) & 1
            if p != (rows[r][x] if x < len(rows[0]) else 0):
                ok = False
    check(ok, 'Paint: "Veranda" typed with the text tool in Gate Sans 18 (the picker\'s choice), as the record draws it')
    png(os.path.join(out, 'paint-text.png'), v)
    return failures


def main():
    if sys.argv[1] == '--fonted':
        return fonted(sys.argv[2], sys.argv[3])
    if sys.argv[1] == '--paint':
        return paint(*sys.argv[2:5])
    dump, console, fonts, out = sys.argv[1:5]
    v = open(dump, 'rb').read()
    t = open(console, 'rb').read().decode('latin-1')
    lines = [x.strip() for x in t.splitlines()]
    i = next((k for k, x in enumerate(lines) if x.endswith('FONT LIST')), None)
    check(i is not None and lines[i + 1:i + 5] == ['System', 'Veranda UI', 'Gate Mono', 'Gate Sans'],
          'FontList: System, Veranda UI, then the fonts folder in order (Gate Mono, Gate Sans)')
    check('FONT CWD OK' in t, 'FontList lists the fonts folder from inside it: the current directory is the same after')
    j = next((k for k, x in enumerate(lines) if x.startswith('FONT SIZES')), None)
    check(j is not None and lines[j + 1].split() == ['9', '12', '18', '27'], 'FontSizes("Gate Sans"): 9 12 18 27')
    got = [x.split()[2:4] for x in lines if x.startswith('FONT GOT') or 'FONT GOT' in x]
    got = [x.split('FONT GOT ')[1].split()[:2] for x in lines if 'FONT GOT' in x]
    check(got[:4] == [['0', '0'], ['1', '0'], ['255', '5'], ['255', '5']],
          'LoadFont: System 9 -> 0, Veranda UI 12 -> FONT_UI, no such file and no such size -> FONT_NONE, FILE_NOT_FOUND')
    hs = [int(x[0]) for x in got[4:9]]
    check(len(hs) == 5 and all(x[1] == '0' for x in got[4:9]) and len(set(hs)) == 5 and all(2 <= h <= 16 for h in hs),
          'LoadFont of the five test records: handles %s, no error' % hs)
    infos = [x.split('FONT INFO ')[1] for x in lines if 'FONT INFO' in x]
    want = []
    recs = {}
    for name, size, y in TESTS:
        n, fid, rr, hdr = fontcvt.read_cvt(open(os.path.join(fonts, name + '.cvt'), 'rb').read())
        f = fontcvt.parse_record(rr[size])
        recs[(name, size)] = f
        want.append('%d %d %d %s' % (size, f['height'], f['baseline'], name))
    check(infos == want, 'FontInfo: size, height, baseline, name of each (%s)' % '; '.join(infos))

    # the screen: memory vs banks
    same = True
    for name, size, y in TESTS:
        f = recs[(name, size)]
        h = f['height'] + 2
        a = v[W * y:W * (y + h)]
        b = v[W * (y + 240):W * (y + 240 + h)]
        ink = sum(bin(x).count('1') for x in a)
        ok = a == b and ink > 50
        same &= ok
        check(ok, '%s %d: %d rows in every style, from banks = from the program\'s memory, byte for byte (%d pixels set)'
              % (name, size, h, ink))
        # the plain part against the host's drawing of the record
        txt = 'Veranda Zażółć ŻÓŁĆ {gjpqy} '      # (V141: the glyphs of $A0-$FF)
        rows = fontcvt.render(f, txt)
        wpx = 0                         # (whole characters on the screen: one past
        for ch in fontcvt.encode(txt):  # its right edge is not drawn)
            gw = len(fontcvt.glyph(f, ch)[0])
            if 8 + wpx + gw > 640:
                break
            wpx += gw
        okp = True
        for r in range(f['height']):
            for x in range(wpx):
                px = (v[W * (y + r) + (8 + x) // 8] >> (7 - (8 + x) % 8)) & 1
                if px != rows[r][x]:
                    okp = False
        check(okp, '%s %d: its plain text with Polish letters ("Veranda Zażółć ŻÓŁĆ") as tools/fontcvt.py draws the record' % (name, size))

    # (V141) tests/font.s part 2c: the system font draws '?' for $BF (it has
    # no $A0-$FF) and for $90 (no character): "a??b" at x 400, y 113, as the
    # system font's record (Gate Sans 9) draws it
    f9 = recs[('Gate Sans', 9)]
    rows = fontcvt.render(f9, 'a??b')
    okq = True
    for r in range(f9['height']):
        for x in range(len(rows[0])):
            if (v[W * (113 + r) + (400 + x) // 8] >> (7 - (400 + x) % 8)) & 1 != rows[r][x]:
                okq = False
    check(okq, "the system font: '?' for $BF (no glyphs of $A0-$FF) and for $90 (no character), as \"a??b\"")

    # italic's lean (V122): tests/font.s part 2b against fontcvt.render_runs
    for name, size, y in ITESTS:
        f = recs[(name, size)]
        rows = fontcvt.render_runs(f, IRUNS)
        okp = True
        for r in range(f['height']):
            for x in range(len(rows[0]) + 8):
                px = (v[W * (y + r) + (8 + x) // 8] >> (7 - (8 + x) % 8)) & 1
                if px != (rows[r][x] if x < len(rows[0]) else 0):
                    okp = False
        check(okp, '%s: italic leaning whole: after an italic run plain text, bold italic at a string\'s end, '
              'the next WPutString going on, italic at its end, as tools/fontcvt.py render_runs draws them'
              % ('the system font' if y == 113 else '%s %d' % (name, size)))
        tag = 'system' if y == 113 else '%s%d' % (name.split()[1].lower(), size)
        crop(os.path.join(out, 'italic-%s.png' % tag), v, y, f['height'], len(rows[0]) + 16)

    tm = {}
    for x in lines:                     # (a DOS command's echo may come first)
        m = re.search(r'TIME (\w+) ([0-9A-F]{8})', x)
        if m:
            tm[m.group(1)] = int(m.group(2), 16)
    us = lambda k: tm[k] / 8 / 1000                               # noqa: E731
    if 'text1000' in tm:
        print('      the system font: %.1f us a character (10 lines of 100), %.1f (50 lines of 20)'
              % (us('text1000'), us('sys20')))
        check(us('text1000') <= 250, 'the system font at most 250 us a character (V6; the banked path costs it nothing)')
        for s in (12, 27):
            r, bk = us('ram%d' % s), us('bank%d' % s)
            print('      Gate Sans %d: %.0f us a character from the program\'s memory, %.0f from banks (+%.0f %%)'
                  % (s, r, bk, 100 * (bk - r) / r))
            check(bk <= r * 1.3, 'Gate Sans %d from banks at most 30 %% slower than from memory' % s)
        print('      LoadFont from the file (host folder or card): %s'
              % ', '.join('%s %.1f ms' % (k[4:], tm[k] / 8000) for k in ('load9', 'load12', 'load18', 'load27')))
        print('      LoadFont of a font loaded already: %.2f ms' % (tm['loadcached'] / 8000))
        check(tm['loadcached'] < 8000 * 2, 'LoadFont again: from RAM, under 2 ms')
    check('FONT DONE' in t, 'the test ran to its end')
    png(os.path.join(out, 'font-screen.png'), v)
    print('      picture: %s' % os.path.join(out, 'font-screen.png'))
    return failures


if __name__ == '__main__':
    sys.exit(1 if main() else 0)
