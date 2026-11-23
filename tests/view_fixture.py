#!/usr/bin/env python3
"""gate view: the files View opens (besides the BMPs, which the gate makes
with ExportRect on the emulator: tests/view_scene.c).

usage: view_fixture.py <folder>

  Readme.txt   text: long paragraphs (wrapped), short lines, tabs, CR LF
               and LF and a lone CR, bytes above 127, "needle" twice past
               the first screen (once as NEEDLE)
  Picture.cvt  a Paint document, version 3: shapes, card colours, ink 6
  Sunset.cvt   a Photo Scrap (class Photo Scrap V2.0): 20 cards x 100
               rows, with its colours
  Album.cvt    a photo album (Photo Album V1.0): a scrap without colours,
               an empty record, a scrap with colours
"""
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'tools'))
sys.path.insert(0, HERE)
import vdisk  # noqa: E402

SYSTEM, APPL_DATA = 4, 7


def text():
    rnd = random.Random(7)
    words = ('the viewer wraps long lines at eighty columns and keeps whole words together where '
             'they fit veranda shows text in cells of eight by eight pixels').split()
    out = []
    for p in range(70):
        if p % 9 == 4:
            out.append(b'\tindented\twith\ttabs\t|')
        elif p % 9 == 6:
            out.append(b'short line ' + str(p).encode())
        else:
            n = rnd.randint(4, 60)
            para = ' '.join(rnd.choice(words) for _ in range(n)).encode()
            if p == 41:
                para += b' here is the needle in the haystack'
            if p == 58:
                para += b' and a second NEEDLE much later'
            out.append(para)
        if p == 20:
            out.append(b'bytes above 127: \xe9\xb0\xdb\xb1 and a control \x01 character')
            out.append(b'x' * 200)          # no space: broken hard
    data = b''
    for i, ln in enumerate(out):
        data += ln + (b'\r\n' if i % 3 == 0 else b'\n' if i % 3 == 1 else b'\r')
    return data


def paint():
    bits = vdisk.blank_bits()
    cmap = [[0] * vdisk.P_MW for _ in range(vdisk.P_MH)]
    for y in range(vdisk.P_H):
        for x in range(vdisk.P_W):
            if (x - 296) ** 2 + (y - 232) ** 2 < 150 ** 2 and (x // 6 + y // 6) % 2:
                bits[y][x] = 1
            if x in (0, vdisk.P_W - 1) or y in (0, vdisk.P_H - 1) or abs(x - y) < 2:
                bits[y][x] = 1
    for cy in range(vdisk.P_MH):
        for cx in range(vdisk.P_MW):
            if 5 <= cy < 20 and 3 <= cx < 30:
                cmap[cy][cx] = 7
            elif 30 <= cy < 50 and 40 <= cx < 70:
                cmap[cy][cx] = 13
            elif cy == 57:
                cmap[cy][cx] = cx % 16
    return vdisk.paint_cvt('Picture', vdisk.paint_doc(bits, cmap, 6))


def scrap(w, h, seed, colours):
    rnd = random.Random(seed)
    raw = bytearray()
    for y in range(h):
        for x in range(w):
            raw.append(0xFF if (x + y // 8) % 5 == 0 else (rnd.randrange(256) if y % 16 < 4 else 0x81))
    d = bytes([w, h & 255, h >> 8]) + vdisk.bitmap_pack(bytes(raw))
    if colours:
        cols = bytes(((x + cy) % 15 + 1) | (1 << 4) for cy in range((h + 7) // 8) for x in range(w))
        d += vdisk.bitmap_pack(cols)
    return d


def shell(d, name='Line.bmp', where='host'):
    """SHELL.TST for the shell in <d>: a double click on Line.bmp (or name);
    where 'sd': an SD card's folder (no console.txt there)"""
    import shell_script
    files = sorted(set(os.listdir(d) + ['SHELL.TST', 'SHELL.STP'] + (['console.txt'] if where != 'sd' else [])))
    root = shell_script.listing([], files)
    p = shell_script.Part()
    p.wait(20)
    p.dbl(*shell_script.cell(root.index(name)))
    p.end(shell_script.END_STOP)
    shell_script.write(os.path.join(d, 'SHELL.TST'), [p])


def main():
    if sys.argv[1] == '--shell':
        shell(*sys.argv[2:5])
        return
    d = sys.argv[1]
    os.makedirs(d, exist_ok=True)
    open(os.path.join(d, 'Readme.txt'), 'wb').write(text())
    open(os.path.join(d, 'Picture.cvt'), 'wb').write(paint())
    open(os.path.join(d, 'Sunset.cvt'), 'wb').write(vdisk.make_cvt(
        'Sunset', SYSTEM, b'Photo Scrap V2.0', data=scrap(20, 100, 1, True), info_txt=b'A test scrap.'))
    open(os.path.join(d, 'Album.cvt'), 'wb').write(vdisk.make_cvt(
        'Album', APPL_DATA, b'Photo Album V1.0', recs=[scrap(12, 60, 2, False), None, scrap(30, 200, 3, True)],
        author=b'Veranda', info_txt=b'Two pages.'))


if __name__ == '__main__':
    main()
