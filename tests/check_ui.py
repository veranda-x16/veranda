#!/usr/bin/env python3
"""Gate ui checks (phase 4): a session on GEOS 64 against the same session
on Veranda in its 320x240 mode.

usage: check_ui.py <GEOS64_REF> <dump.bin> <console.txt> <session64.bin> <session64.lab> <outdir> <name>

A session (tests/ui_*.s, assembled for both) exports
  UiSession   the code: clears the screens, sets up menus, icons, a dialog
              box ..., and goes to the main loop
  UiScript    the input: entries of 6 bytes, frame (word), x (word), y
              (byte), flags (byte: bit 0 the button down; bit 7 a key, its
              code in x's low byte); frame $FFFF ends the table, its x is
              the frame the screens are compared at
  UiMask      areas not compared (card left, card right, top, bottom
              rows, inclusive), $FF ends: the system icons of dialog boxes
              are Veranda's own pictures
On GEOS 64 the session runs in the old project's GEOS 64 simulator
(GEOS64_REF/tools/x16/geos64sim.py: GEOS 64's KERNAL, its interrupt every
16,400 instructions, the pointer and button set from the script, keys into
GEOS's queue) for the given number of frames; on Veranda tests/ui.s plays
the same script through mouseSource (absolute positions) and dumps VRAM at
that frame. The foregrounds are compared (rows 0-199, the masks left out).
"""
import os
import sys

W, H = 40, 200
FG = 0x00000
VDUMP = 132878                  # x16emu's VRAM section: 128 KB and 1,806 bytes after it
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


def save_png(path, data, diff=None, mask=None):
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
            if mask is not None and mask[y * W + x // 8]:
                c = (0, 0, 160) if on else (190, 190, 255)
            if diff is not None and (diff[y * W + x // 8] ^ data[y * W + x // 8]) & (0x80 >> (x % 8)):
                c = (220, 0, 0)
            px[x, y] = c
    img.resize((640, 2 * H)).save(path)


def main():
    if len(sys.argv) != 8:
        sys.exit(__doc__)
    ref, dump, console, session, lab, outdir, name = sys.argv[1:]
    sys.path.insert(0, os.path.join(ref, 'tools', 'x16'))
    from geos64sim import Geos64
    syms = labels(lab)
    blank = os.path.join(outdir, 'blank.d64')
    os.makedirs(outdir, exist_ok=True)
    open(blank, 'wb').write(bytes(174848))
    g = Geos64(os.path.join(ref, 'build', 'bsw', 'kernal', 'kernal.bin'),
               os.path.join(ref, 'build', 'bsw', 'drv', 'drv1541.bin'), blank)
    g.cpu.sp = 0xFF
    assert g.run_call(0xC271, frames=50) == 'returned'          # FirstInit
    # the button up, nothing pending (FirstInit leaves mouseData 0, "down",
    # which the simulator's first frame would report as a release)
    g.m[0x8505] = 0x80
    g.m[0x39] &= ~0x20
    s = open(session, 'rb').read()
    g.m[0x0400:0x0400 + len(s)] = s

    def word(a):
        return g.m[a] | g.m[a + 1] << 8
    script, a, end = [], syms['UiScript'], None
    while True:
        f, x, y, fl = word(a), word(a + 2), g.m[a + 4], g.m[a + 5]
        a += 6
        if f == 0xFFFF:
            end = x
            break
        script.append((f, ('key', x & 0xFF) if fl & 0x80 else (x, y, bool(fl & 1))))
    mask = bytearray(W * H)
    a = syms['UiMask']
    while g.m[a] != 0xFF:
        c0, c1, y0, y1 = g.m[a:a + 4]
        for y in range(y0, y1 + 1):
            for c in range(c0, c1 + 1):
                mask[y * W + c] = 1
        a += 4
    g.mouse = list(script[0][1]) if script and script[0][1][0] != 'key' else [160, 100, False]
    r = g.run_call(syms['UiSession'], frames=end, script=script)
    print('      GEOS 64: %s after %d frames' % (r, g.frames))
    log = open(console, 'rb').read().decode('latin-1')
    check('UI DONE' in log, 'Veranda ran the session to frame %d' % end)
    model = bytes(g.m[0xA000 + (y >> 3) * 320 + bx * 8 + (y & 7)] for y in range(H) for bx in range(W))
    v = open(dump, 'rb').read()
    v = v[len(v) - VDUMP:]                                      # (-dump BV: VRAM last)
    ver = bytes(v[FG:FG + W * H])
    bad = [i for i in range(W * H) if not mask[i] and model[i] != ver[i]]
    where = '' if not bad else ' (%d bytes differ; first at row %d, card %d)' % (len(bad), bad[0] // W, bad[0] % W)
    check(not bad, '%s: the screen equals GEOS 64\'s%s%s' % (name, ' (system icons left out)' if any(mask) else '',
                                                        where))
    save_png(os.path.join(outdir, 'model.png'), model, mask=mask)
    save_png(os.path.join(outdir, 'veranda.png'), ver, model if bad else None, mask)
    print('      pictures: %s/model.png, veranda.png (red: differs, blue: not compared)' % outdir)
    sys.exit(1 if failures else 0)


if __name__ == '__main__':
    main()
