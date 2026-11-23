#!/usr/bin/env python3
"""Gate gfx1 checks (tests/gfx1.s): the VRAM dump and the console.

usage: check_gfx1.py <dump.bin> <console.txt> <outdir>
"""
import os
import re
import sys

W, H = 80, 480                  # bytes a row, rows
FG, BG = 0x00000, 0x09600
failures = 0


def check(cond, what):
    global failures
    print(('ok    ' if cond else 'FAIL  ') + what)
    if not cond:
        failures += 1


def rows(v, base, r0, r1, c0=0, c1=W):
    return [bytes(v[base + W * r + c0:base + W * r + c1]) for r in range(r0, r1 + 1)]


def png(path, v, base):
    try:
        from PIL import Image
    except ImportError:
        return
    img = Image.new('1', (640, 480))
    px = img.load()
    for y in range(480):
        for c in range(W):
            b = v[base + W * y + c]
            for k in range(8):
                px[c * 8 + k, y] = 0 if b & (0x80 >> k) else 1
    img.save(path)


def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    dump, console, outdir = sys.argv[1:]
    v = open(dump, 'rb').read()
    log = open(console, 'rb').read().decode('latin-1').splitlines()
    check(len(v) >= 0x20000, 'dump.bin holds VRAM')
    check(any('GFX1 DONE' in ln for ln in log), 'the test ran to its end')

    for name, base in (('foreground', FG), ('back screen', BG)):
        a, b = rows(v, base, 16, 84), rows(v, base, 316, 384)
        ink = sum(bin(x).count('1') for r in a for x in r)
        check(a == b and ink > 2000, '%s: the shape at y 320 equals the one at y 20, row for row (%d ink pixels)'
              % (name, ink))
        src, dst = rows(v, base, 20, 80, 2, 27), rows(v, base, 140, 200, 40, 65)
        check(src == dst, '%s: CopyRect: cards 40-64 of rows 140-200 equal cards 2-26 of rows 20-80' % name)
        check(rows(v, base, 405, 405, 60, 80)[0] == b'\xff' * 20 and rows(v, base, 410, 410, 60, 80)[0] == bytes(20)
              and all(r == bytes(20) for r in rows(v, base, 475, 479, 60, 80)),
              '%s: ScrollRect: the line from row 410 is on row 405, the bottom 5 rows are paper' % name)
    check(all(r == bytes(9) for r in rows(v, FG, 200, 230, 2, 11)),
          'RecoverRectangle: the foreground got the (empty) back screen back')
    fg_i, bg_i = rows(v, FG, 200, 220, 37, 43), rows(v, BG, 200, 220, 37, 43)
    check(fg_i == bg_i and any(any(r) for r in fg_i), 'ImprintRectangle: the back screen got the foreground\'s rectangle')
    # the system font line (tests/gfx1.s): rows 444-452 from x 100, as
    # tools/mkfont.py draws its glyphs
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'tools'))
    import mkfont
    text, x0, base = 'Veranda 0.1: Hello, X16! {gjpqy}', 100, 450
    want = [[0] * 640 for _ in range(9)]
    x = x0
    for ch in text:
        g = mkfont.G[ch]
        for r in range(9):
            for i, c in enumerate(g[r]):
                if c == '#':
                    want[r][x + i] = 1
        x += len(g[0])
    got = [[1 if v[FG + W * (base - 6 + r) + px // 8] & (0x80 >> (px % 8)) else 0 for px in range(640)]
           for r in range(9)]
    bad = sum(1 for r in range(9) for px in range(x0, x) if want[r][px] != got[r][px])
    check(bad == 0 and x > x0, 'the system font (fast path): "%s" as tools/mkfont.py draws it (%d pixels differ)'
          % (text, bad))
    # PutCards (API 2): tests/gfx1.s's five calls against the font's formula
    def glyph(c, r, flags=0):
        g = ((8 * c + r) * 37 ^ c) & 255
        if flags & 2:
            g |= g >> 1
        if flags & 1:
            g ^= 255
        return g

    def cards(base, text, x, y, flags=0, rows=range(8)):
        return all(v[base + W * (y + r) + x + i] == glyph(ord(ch), r, flags)
                   for i, ch in enumerate(text) for r in rows)
    check(cards(FG, 'AZaz09{}', 1, 241) and cards(BG, 'AZaz09{}', 1, 241),
          'PutCards: 8 characters at row 241 (unaligned), card 1, on both screens, byte for byte')
    check(cards(FG, 'Bold', 20, 250, 3) and all(v[BG + W * (250 + r) + 20 + i] == 0 for r in range(8) for i in range(4)),
          'PutCards: reverse and bold on the foreground only')
    check(cards(FG, 'Bold', 30, 260, 0, range(2, 6))
          and all(v[FG + W * (260 + r) + 30 + i] == 0 for r in (0, 1, 6, 7) for i in range(4)),
          'PutCards: only the clip window\'s rows (262-265)')
    check(cards(FG, 'AZaz', 76, 280) and v[FG + W * 280 + 79 + 1] == 0,
          'PutCards: clipped at the screen\'s right edge (4 of 8 characters)')
    check(cards(FG, 'Zero', 40, 290, 1) and all(v[FG + W * (290 + r) + 44] == 0 for r in range(8)),
          'PutCards: up to a 0 (4 of 20 characters), reverse')
    tp = None
    for i, ln in enumerate(log):
        if ln.strip() == 'TP' and i + 1 < len(log):
            tp = log[i + 1].strip()
    check(tp == '1001', 'TestPoint: (16,20) ink, (17,20) paper, (639,0) paper, (220,320) ink: %s' % tp)

    t = {}
    for ln in log:
        ln = re.sub(r'\\X[0-9A-F]{2}', '', ln)      # the emulator's escapes (ISO mode's $0F)
        if ln.startswith('TIME '):
            f = ln.split()
            t[f[1]] = int(f[2], 16)
    if 'text1000' in t:
        us = t['text1000'] / 8 / 1000
        print('      text: %.0f us a character (the system font, 1000 characters)' % us)
        check(us <= 250, 'text at most 250 us a character (docs/PLAN.md phase 2)')
    if 'cards4800' in t:
        us = t['cards4800'] / 8 / 4800
        print('      PutCards: %.1f us a character, a full screen (4,800 characters) in %.0f ms'
              % (us, t['cards4800'] / 8000))
        check(us <= 40, 'PutCards at most 40 us a character (a full 80 x 60 screen)')
    else:
        check(False, 'a TIME cards4800 line')
    if len(t) >= 4:
        print('      full-screen fill (38,400 bytes): %.2f ms' % (t['fill'] / 8000))
        if 'fill2' in t:
            print('      fill of x 4-635, all rows, 50 %% grey (row by row): %.2f ms' % (t['fill2'] / 8000))
        if 'fill3' in t:
            print('      full-screen fill, 50 %% grey: %.2f ms' % (t['fill3'] / 8000))
        print('      full-screen copy (CopyRect, 480 rows of 80 bytes): %.2f ms' % (t['copy'] / 8000))
        cross = (t['bank256'] - t['res256']) / 256
        print('      a call into a kernel bank costs %.0f cycles more than a resident call (SetPattern vs GetVersion)'
              % cross)
        check(cross <= 200, 'bank crossing at most 200 cycles over a resident call (target 120 for the gate alone)')
    else:
        check(False, 'four TIME lines')
    # window operations (DECISIONS V80: before it 90, 53, 27, 33, 95, 18 and
    # 96 ms; the limits leave room for the plain engine, -D NOFX, and an
    # interrupt or two)
    limits = [('outline', 'the drag outline\'s step (erase and draw, 384 x 312)', 60000),
              ('frame', 'a 384 x 312 frame, both screens', 60000),
              ('vline', 'a vertical line of 312 rows, both screens', 30000),
              ('shadow', 'a window\'s shadow (6 x 312, both screens)', 50000),
              ('move', 'a 384 x 312 window moved (CopyRect, both screens)', 480000),
              ('recover', 'a menu\'s area (160 x 160) recovered', 130000),
              ('copy', 'a full-screen CopyRect', 520000)]
    # the second batch (DECISIONS V81; before it: the UI font 913 us a
    # character, bold 963, a UseFont pair 1.77 ms, a tile 5.8 ms; a string
    # outside the clip was drawn and its spans cut)
    limits += [('ui1000', 'the UI font: 1,000 characters', 1000 * 8 * 600),
               ('uibold1000', 'the UI font in bold: 1,000 characters', 1000 * 8 * 650),
               ('usefont100', '100 UseFont and UseSystemFont pairs', 100 * 8 * 200),
               ('rawtile100', '100 tiles as raw rows (4 cards by 32 rows, both screens)', 100 * 8 * 1500),
               ('tile100', '100 tiles compacted (the same)', 100 * 8 * 10000),
               ('clipin1100', '100 strings of 11 UI characters with the clip on (in it)', 1100 * 8 * 800),
               ('clipout1100', 'the same right of the clip (skipped)', 1100 * 8 * 100)]
    for k, what, most in limits:
        if k not in t:
            check(False, 'a TIME %s line' % k)
            continue
        print('      %s: %.2f ms' % (what, t[k] / 8000))
        check(t[k] <= most, '%s at most %.1f ms' % (what, most / 8000))
    if 'rawtile100' in t and 'tile100' in t:
        check(t['rawtile100'] * 5 <= t['tile100'], 'raw rows at least 5 times as fast as compacted ones (V81)')
    os.makedirs(outdir, exist_ok=True)
    png(os.path.join(outdir, 'foreground.png'), v, FG)
    png(os.path.join(outdir, 'back.png'), v, BG)
    print('      pictures: %s/foreground.png, back.png' % outdir)
    sys.exit(1 if failures else 0)


if __name__ == '__main__':
    main()
