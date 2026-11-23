#!/usr/bin/env python3
"""Gate gfx checks (phase 2): tests/scene.s on the GEOS 64 KERNAL against
Veranda in its 320x240 mode.

usage: check_gfx2.py <GEOS64_REF> <dump.bin> <console.txt> <scene64.bin> <scene64.lab> <outdir>

Runs the scene (built for GEOS 64, at $0400) on GEOS 64's KERNAL
(GEOS64_REF/build/bsw/kernal/kernal.bin, loaded at $5000) in the old
project's simulator (GEOS64_REF/tools/x16/sim6502.py), then compares its
screens with Veranda's VRAM dump:
  foreground   C64 $A000 (card layout)  vs VRAM $00000 (40 bytes a row)
  back screen  C64 $6000                vs VRAM $09600
rows 0-199. Writes model.png, veranda.png and diff.png (red = differs).
"""
import os
import sys

W, H = 40, 200
FG, BG = 0x00000, 0x09600
failures = 0


def check(cond, what):
    global failures
    print(('ok    ' if cond else 'FAIL  ') + what)
    if not cond:
        failures += 1


def labels(path):
    syms = {}
    for line in open(path):
        p = line.split()
        if len(p) == 3 and p[0] == 'al':
            syms[p[2].lstrip('.')] = int(p[1], 16)
    return syms


def card_to_linear(mem, base):
    return bytes(mem[base + (y >> 3) * 320 + bx * 8 + (y & 7)] for y in range(H) for bx in range(W))


def save_png(path, data, diff=None):
    try:
        from PIL import Image
    except ImportError:
        return
    img = Image.new('RGB', (320, H))
    px = img.load()
    for y in range(H):
        for x in range(320):
            on = data[y * W + x // 8] & (0x80 >> (x % 8))
            c = (0, 0, 0) if on else (255, 255, 255)
            if diff is not None and (diff[y * W + x // 8] ^ data[y * W + x // 8]) & (0x80 >> (x % 8)):
                c = (220, 0, 0)
            px[x, y] = c
    img.resize((640, 2 * H)).save(path)


def main():
    if len(sys.argv) != 7:
        sys.exit(__doc__)
    ref, dump, console, scene, lab, outdir = sys.argv[1:]
    sys.path.insert(0, os.path.join(ref, 'tools', 'x16'))
    from sim6502 import CPU
    mem = bytearray(65536)
    k = open(os.path.join(ref, 'build', 'bsw', 'kernal', 'kernal.bin'), 'rb').read()
    mem[0x5000:0x5000 + len(k)] = k
    s = open(scene, 'rb').read()
    mem[0x0400:0x0400 + len(s)] = s
    cpu = CPU(mem)
    cpu.call(labels(lab)['GfxScene'])
    print('      GEOS 64: %d instructions' % cpu.cycles)
    v = open(dump, 'rb').read()
    check(any('GFX2 DONE' in ln for ln in open(console, 'rb').read().decode('latin-1').splitlines()),
          'Veranda ran the scene')
    os.makedirs(outdir, exist_ok=True)
    for name, cbase, vbase, tag in (('foreground', 0xA000, FG, ''), ('back screen', 0x6000, BG, '-back')):
        model = card_to_linear(mem, cbase)
        ver = bytes(v[vbase:vbase + W * H])
        bad = [i for i in range(W * H) if model[i] != ver[i]]
        where = '' if not bad else ' (%d bytes differ; first at row %d, card %d)' % (len(bad), bad[0] // W, bad[0] % W)
        check(not bad, '%s equals GEOS 64\'s byte for byte%s' % (name, where))
        save_png(os.path.join(outdir, 'model%s.png' % tag), model)
        save_png(os.path.join(outdir, 'veranda%s.png' % tag), ver, model if bad else None)
    print('      pictures: %s/model.png, veranda.png (red: differs)' % outdir)
    sys.exit(1 if failures else 0)


if __name__ == '__main__':
    main()
