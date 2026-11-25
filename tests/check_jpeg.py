#!/usr/bin/env python3
"""Gate gemini (DECISIONS V192): Veranda Gemini's JPEG decoder on the
emulated X16 (tests/jpeg_bench.c: apps/gemini/jpghdr.c, jpegcore.s,
pngplan.c on cc65's cx16 runtime) against tests/jpeg_ref.py: each test
picture decoded with VERA FX's multiplier and without (the plain 65C02
products), the tiles and the map in VRAM (-dump V) index for index the
reference's, both ways; the refused ones' errors; the time of each
(the emulator's cycle counter at 8 MHz).

usage: check_jpeg.py <JB.PRG> <x16emu> <rom.bin> <work folder> [kinds...]
"""
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import jpeg_ref  # noqa: E402

PRG, EMU, ROM, WORK = sys.argv[1:5]
KINDS = sys.argv[5:] or jpeg_ref.KINDS
ERRS = {'progressive': 6, 'corrupt': 3}
TILEV, MAPV = 0x13000, 0x1AC00


def need(c, msg):
    if not c:
        sys.exit('FAIL  jpeg: ' + msg)


def run(kind, data, fx):
    d = os.path.join(WORK, '%s-%d' % (kind, fx))
    os.makedirs(d, exist_ok=True)
    for f in os.listdir(d):
        os.remove(os.path.join(d, f))
    open(os.path.join(d, 'pic.jpg'), 'wb').write(data)
    open(os.path.join(d, 'jb.cfg'), 'w').write('%d pic.jpg\n' % fx)
    env = dict(os.environ, SDL_VIDEODRIVER='dummy')
    p = subprocess.run([EMU, '-rom', ROM, '-prg', os.path.abspath(PRG), '-run', '-warp', '-sound', 'none',
                        '-dump', 'V'], cwd=d, env=env, capture_output=True, timeout=900)
    out = p.stdout.decode('latin-1').replace('\r', '\n')
    line = next((l for l in out.split('\n') if l.startswith('JB ')), None)
    need(line, '%s: no result (%s)' % (kind, out[-300:]))
    vram = open(os.path.join(d, 'dump.bin'), 'rb').read()[:0x20000]
    return line.split(), vram


def tiles(vram, tw, th, tx, ty):
    pic = []
    for y in range(th * 8):
        row = []
        for x in range(tw * 8):
            m = MAPV + ((ty + y // 8) << 8) + ((tx + x // 8) << 1)
            t = vram[m] | ((vram[m + 1] & 3) << 8)
            i = vram[TILEV + t * 32 + (y & 7) * 4 + (x & 7) // 2]
            row.append(i & 15 if x & 1 else i >> 4)
        pic.append(row)
    return pic


done, times = [], []
for kind in KINDS:
    data = jpeg_ref.make(kind)
    res = {}
    for fx in (1, 0):
        r, vram = run(kind, data, fx)
        if kind in ERRS:
            need(r[1] == 'ERR' and int(r[2]) == ERRS[kind], '%s: %s, not error %d' % (kind, r, ERRS[kind]))
            res[fx] = None
            continue
        need(r[1] == 'OK', '%s (%s): %s' % (kind, 'FX' if fx else 'no FX', r))
        pw, ph, ow, oh, tw, th, tx, ty, usedfx, t_open, t_dec = map(int, r[2:13])
        need(usedfx == fx, '%s: FX used %d, asked %d' % (kind, usedfx, fx))
        m, cols, rw, rh, rtw, rth, rtx, rty, out = jpeg_ref.shown(data)
        need((ow, oh, tw, th, tx, ty) == (rw, rh, rtw, rth, rtx, rty),
             '%s: shown %s, the reference %s' % (kind, (ow, oh, tw, th, tx, ty), (rw, rh, rtw, rth, rtx, rty)))
        pic = tiles(vram, tw, th, tx, ty)
        for y in range(th * 8):
            if pic[y] != out[y]:
                x = next(i for i in range(tw * 8) if pic[y][i] != out[y][i])
                sys.exit('FAIL  jpeg: %s (%s): row %d column %d is %d, the reference %d' % (
                    kind, 'FX' if fx else 'no FX', y, x, pic[y][x], out[y][x]))
        res[fx] = (pw, ph, ow, oh, t_open + t_dec, r[13:])
    if kind in ERRS:
        done.append('%s: refused (%d)' % (kind, ERRS[kind]))
        continue
    pw, ph, ow, oh, tf, pf = res[1]
    tn = res[0][4]
    done.append('%s %dx%d -> %dx%d' % (kind, pw, ph, ow, oh))
    times.append('%s (%d bytes) %.2f s with FX, %.2f s without (%.0f%% less)%s' % (
        kind, len(data), tf / 8e6, tn / 8e6, 100.0 * (tn - tf) / tn,
        ' [FX: Huffman %.2f, IDCT %.2f, planes %.2f, rows %.2f s; without: IDCT %.2f]' % (
            tuple(int(v) / 8e6 for v in pf) + (int(res[0][5][1]) / 8e6,)) if len(pf) == 4 else ''))
print('ok    jpeg (the X16, tests/jpeg_bench.c) against jpeg_ref.py: the tiles index for index, with VERA FX\'s '
      'multiplier and without: ' + '; '.join(done))
print('ok    jpeg: the times at 8 MHz: ' + '; '.join(times))
