#!/usr/bin/env python3
"""Gate tile (DECISIONS V181): File > Get Info on a geoWrite document
whose info block has junk in the fields geoWrite leaves alone (from the
user's X16: "letter", class Write Image V2.1: its class, author and
application lines under a band of noise, a second block by the
description, the description "???? b6 ?M?1", the old 1-bit icon).

usage: info_box.py doc <out.cvt> junk|clean
       info_box.py script <run folder> icon|name open|cancel|none
       info_box.py check <dump> <reference dump> <letter.cvt>
       info_box.py same <dump> <dump>

doc: "letter" (VLIR, class "Write Image V2.1", parent "geoWrite    V2.1",
a 1-bit icon: a frame). junk: its author field (bytes 97-116) starts
with ESC_GRAPHICS and a GraphicsString (a dithered rectangle over the
box's lines, as the X16 showed), bytes 137-159 random, the description
(160-255) high bytes, REVON and junk with no 0; clean: the same file
with those fields as the box should show them (shown(): a field ends at
its length, a 0, $A0 or another control byte; a byte past '~' is '?').

script: SHELL.TST for a run in the card's layout (the shell starting in
/DOCUMENTS, window 0): letter selected (icon view: its cell; name: View >
name, its row), File > Get Info; open: the end with the box open; cancel:
its Cancel, then the end; none: no Get Info (what cancel must leave).

check: the box with the junk file is the box with the clean one, pixel
for pixel (the whole screen: no noise anywhere, the text in place); its
icon (cards 8-11, rows 13-16) pixel for pixel the colour icon of its
class (tests/apps_icons.py: the library's "Write Image"); right of its
lines (x 300-590 over the five lines) the box's paper alone, and on
them no reverse block (40 of 64 pixels ink at most in any card). same: two screens
equal (after Cancel the window as it was: the icon's cards given back).

MIT licence (LICENSE).
"""
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, '..', 'tools'))
import shell_script as ss  # noqa: E402
import shell_subst  # noqa: E402

NAME = 'letter'
IBL, IBT = 40, 90               # shell/files.c's box
ICON = (IBL + 24, IBT + 14)     # its icon (cards 8, 13)
LINES = (IBT + 12, IBT + 64)    # its five lines' tops (name ... application)
INFO = 252                      # the file's offset of info block byte 0


def shown(b):
    """a field as the box shows it (shell/files.c's text)"""
    out = bytearray()
    for c in b:
        if c < 0x20 or c == 0xA0:
            break
        out.append(c if c < 0x7F else 0x3F)
    return bytes(out)


def doc(out, kind):
    b = bytearray(shell_subst.cvt(NAME, 'Write Image V2.1', 'geoWrite    V2.1', {0: b'Dear Ada\r\0'}))
    icon = bytearray(63)        # a 1-bit frame (the old path drew it)
    for y in range(21):
        for x in range(3):
            icon[y * 3 + x] = 0xFF if y in (0, 20) else (0x80 if x == 0 else 1 if x == 2 else 0)
    b[INFO + 5:INFO + 68] = icon
    rnd = random.Random(181)
    author = bytes([0x10, 5, 2, 1, 1, 1, IBT + 38, 3, 0x58, 2, IBT + 66]) + bytes(
        rnd.randrange(1, 256) for _ in range(9))
    desc = b'\xff\xfe\xfd\xfc b6 \x12M\x9a1' + bytes(rnd.randrange(1, 256) for _ in range(96 - 13))
    junk = {97: author, 137: bytes(rnd.randrange(256) for _ in range(23)), 160: desc}
    for off, v in junk.items():
        if kind == 'clean' and off != 137:
            v = shown(v).ljust(len(v), b'\0')
        b[INFO + off:INFO + off + len(v)] = v
    open(out, 'wb').write(bytes(b))


def script(d, view, mode):
    docs = os.path.join(d, 'DOCUMENTS')
    names = os.listdir(docs)
    order = ['..'] + ss.listing([n for n in names if os.path.isdir(os.path.join(docs, n))],
                                [n for n in names if not os.path.isdir(os.path.join(docs, n))])
    i = order.index(NAME + '.cvt')
    p = ss.Part()
    p.wait(30)
    if view == 'name':
        p.menu('view', 'name')
        p.wait(60)
        p.click(200, ss.WIN0[1] + 64 + 16 * i)      # (its row: 16 lines a row under the header)
    else:
        p.click(*ss.cell(i))
    p.wait(20)
    if mode != 'none':
        p.menu('file', 'info')
        p.wait(80)
    if mode == 'cancel':
        p.click(IBL + 60 * 8 + 23, IBT + 168 + 7)    # (Cancel: box 60, 168)
        p.wait(80)
    p.end(ss.END_DONE)
    ss.write(os.path.join(d, 'SHELL.TST'), [p])


def screen(dump):
    import vram2png as vp
    v = vp.section(dump)
    return v, vp.compose(v)


def diff(a, b):
    n, box = 0, None
    for y, (ra, rb) in enumerate(zip(a, b)):
        for x, (pa, pb) in enumerate(zip(ra, rb)):
            if pa != pb:
                n += 1
                box = (x, y, x, y) if box is None else (min(box[0], x), min(box[1], y), max(box[2], x), max(box[3], y))
    return n, box


def check(dump, ref, path):
    import apps_icons as ai
    v, img = screen(dump)
    _, rimg = screen(ref)
    bad = []
    n, box = diff(img, rimg)
    if n:
        bad.append('%d pixels differ from the clean file\'s box (x %d-%d, y %d-%d)' % ((n,) + (box[0], box[2], box[1], box[3])))
    big, _ = ai.libs()
    g, why = ai.want(path, big)
    if g is None:
        bad.append('letter: ' + why)
    else:
        d = ai.same(img, ICON[0], ICON[1], g, ai.colours(v))
        if d:
            bad.append('the box\'s icon: %d of 1,024 pixels differ from %s' % (d, why))
    paper = img[IBT + 4][IBL + 4]
    y0, y1 = LINES[0], LINES[1] + 12
    noise = sum(1 for y in range(y0, y1) for x in range(300, 590) if img[y][x] != paper)
    if noise:
        bad.append('%d pixels not the paper right of the lines (x 300-589, y %d-%d)' % (noise, y0, y1 - 1))
    ink = ai.colours(v)[1]
    for cy in range(y0 // 8, y1 // 8):
        for cx in range((IBL + 72) // 8, 300 // 8):
            k = sum(1 for y in range(8) for x in range(8) if img[cy * 8 + y][cx * 8 + x] == ink)
            if k > 40:
                bad.append('a block on the lines: card %d, %d has %d of 64 pixels ink' % (cx, cy, k))
    print('      the Info box: as the clean file\'s pixel for pixel, its colour icon (%s), no noise' % why)
    if bad:
        print('\n'.join('FAIL  ' + b for b in bad))
        sys.exit(1)


def same(a, b):
    n, box = diff(screen(a)[1], screen(b)[1])
    if n:
        print('FAIL  %d pixels differ (x %d-%d, y %d-%d)' % (n, box[0], box[2], box[1], box[3]))
        sys.exit(1)
    print('      the screen after Cancel as without the box')


def main():
    a = sys.argv[1:]
    if len(a) == 3 and a[0] == 'doc':
        doc(a[1], a[2])
    elif len(a) == 4 and a[0] == 'script':
        script(a[1], a[2], a[3])
    elif len(a) == 4 and a[0] == 'check':
        check(a[1], a[2], a[3])
    elif len(a) == 3 and a[0] == 'same':
        same(a[1], a[2])
    else:
        sys.exit(__doc__)


if __name__ == '__main__':
    main()
