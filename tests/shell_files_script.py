#!/usr/bin/env python3
"""Gate shell, the file utilities (shell/files.c, DECISIONS V61): the run
folders and SHELL.TST (shell/play.s; the records as tests/shell_script.py
makes them, plus bit 5: a record that plays while the shell is busy).

usage: shell_files_script.py make <folder>            the fixtures of session A
       shell_files_script.py make-big <folder>        session B's (the trash, Big)
       shell_files_script.py a <folder> [extra...]    SHELL.TST: session A
       shell_files_script.py find <folder> [extra...] A up to the find results, the end
       shell_files_script.py b <folder> [extra...]    empty the trash; copy Big, cancel
       shell_files_script.py progress <folder> [...]  copy Big, the end during it
       shell_files_script.py check-a <before> <after> session A's results on the host
       shell_files_script.py check-b <before> <after> <console>

The shell starts in /DOCUMENTS (DECISIONS V71; /VERANDA holds SHELL.cvt),
its first cell "..".

Session A: up to the top folder; view/find "deep*": one result,
/A/B/C/Deep.txt, selected and revealed (the shell shows /A/B/C with
Deep.txt selected); view/up a folder three times; Tree picked (file/copy),
Dest opened, file/put here (Tree copied, folders, an empty folder and a
20 KB file in it); up; Mover picked (file/move), Box opened, put here; up;
Gone.txt and the folder Old deleted (YES): both in /VERANDA/.SYSTEM/TRASH; Info
(a GEOS file) file/get info: its description cleared and typed again;
the end.

Session B: up; disk > empty trash (YES): the trash's files and folders
deleted, TRASH stays; Big picked, Dest opened, put here; 30 frames into
the copy a press on the progress box's cancel (bit 5): the copy stops
(SHELL STOPPED n), the files copied so far are whole; the end.
"""
import filecmp
import os
import random
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, '..', 'tools'))
import shell_script as S  # noqa: E402
import vdisk  # noqa: E402

ASYNC = 0x20
CANCEL = (479 - 76 + 30, 279 - 24 + 7)          # shell/files.c: the cancel button
# the find results in window 0's contents (shell/files.c: from cx0, cy0,
# the contents' corner: right of the sidebar, 2 rows into the body)
CX0, CY0, CX1 = S.WIN0[0] + S.SIDEW * 8, S.WIN0[1] + S.TITLEH + S.TOOLH + 2, S.WIN0[2] - 1
RESULT0 = (CX0 + 88, CY0 + 16 + 6)              # the first result's row (window 0)
REVEAL = (CX1 - 4 - 2 * 56 + 26, CY0 + 5)       # the results' reveal button
OLD_DESC = b'Old words, to be replaced.'
NEW_DESC = b'Edited by the gate.'


def put(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, 'wb').write(data)


def make_a(d):
    rnd = random.Random(5)
    put(os.path.join(d, 'A/a.txt'), b'a\n')
    put(os.path.join(d, 'A/B/b.txt'), b'b\n')
    put(os.path.join(d, 'A/B/C/Deep.txt'), b'three folders down\n')
    put(os.path.join(d, 'A/B/C/other.txt'), b'other\n')
    put(os.path.join(d, 'Tree/t1.txt'), b'tree one\n')
    put(os.path.join(d, 'Tree/t2.bin'), bytes(rnd.randrange(256) for _ in range(20000)))
    put(os.path.join(d, 'Tree/Sub/s1.txt'), b'sub\n')
    put(os.path.join(d, 'Tree/Sub/Leaf/l1.txt'), b'leaf\n')
    os.makedirs(os.path.join(d, 'Tree/Empty'), exist_ok=True)
    os.makedirs(os.path.join(d, 'Dest'), exist_ok=True)
    put(os.path.join(d, 'Mover/m1.txt'), b'moved one\n')
    put(os.path.join(d, 'Mover/In/m2.txt'), b'moved two\n')
    put(os.path.join(d, 'Box/box.txt'), b'box\n')
    put(os.path.join(d, 'Gone.txt'), b'to the trash\n')
    put(os.path.join(d, 'Old/o1.txt'), b'old one\n')
    put(os.path.join(d, 'Old/Inner/o2.txt'), b'old two\n')
    put(os.path.join(d, 'Info.cvt'), vdisk.make_cvt('Info', 7, b'Info Test   V1.0', data=b'some data\r',
                                                     author=b'The gate', info_txt=OLD_DESC))


def make_b(d):
    rnd = random.Random(9)
    put(os.path.join(d, 'VERANDA/.SYSTEM/TRASH/Junk.txt'), b'junk\n')
    put(os.path.join(d, 'VERANDA/.SYSTEM/TRASH/Dir/x.txt'), b'x\n')
    put(os.path.join(d, 'VERANDA/.SYSTEM/TRASH/Dir/Sub/y.txt'), b'y\n')
    for i in range(40):
        put(os.path.join(d, 'Big/f%02d.bin' % i), bytes(rnd.randrange(256) for _ in range(8192)))
    os.makedirs(os.path.join(d, 'Dest'), exist_ok=True)


def root_listing(d, extra):
    dirs = [n for n in os.listdir(d) if os.path.isdir(os.path.join(d, n))]
    files = [n for n in os.listdir(d) if not os.path.isdir(os.path.join(d, n))]
    return dirs, sorted(set(files + ['SHELL.TST', 'SHELL.STP'] + extra))


def menu(p, main, item):
    p.menu(main, item)


def a_part(d, extra, upto_find=False):
    dirs, files = root_listing(d, extra)
    root = S.listing(dirs, files)
    p = S.Part()
    p.wait(20)
    p.dbl(*S.cell(0))                           # ".." in /DOCUMENTS
    p.wait(30)
    p.menu('file', 'find')
    p.wait(20)
    for c in b'deep*':
        p.key(c)
    p.key(13)
    p.wait(60)
    if upto_find:
        p.click(*RESULT0)
        p.wait(20)
        p.end(S.END_DONE)
        return p
    p.click(*RESULT0)
    p.click(*REVEAL)
    p.wait(40)
    for _ in range(3):
        p.menu('view', 'up')
        p.wait(30)
    p.click(*S.cell(root.index('Tree')))
    p.menu('file', 'copy')
    p.dbl(*S.cell(root.index('Dest')))
    p.wait(30)
    p.menu('file', 'put')
    p.wait(40)
    p.dbl(*S.cell(0))                           # ".." in Dest
    p.wait(30)
    p.click(*S.cell(root.index('Mover')))
    p.menu('file', 'move')
    p.dbl(*S.cell(root.index('Box')))
    p.wait(30)
    p.menu('file', 'put')
    p.wait(40)
    p.dbl(*S.cell(0))                           # ".." in Box
    p.wait(30)
    dirs = [n for n in dirs if n != 'Mover']
    root = S.listing(dirs, files)
    p.click(*S.cell(root.index('Gone.txt')))
    p.menu('file', 'delete')
    p.wait(20)
    p.click(S.YES_X, S.YES_Y)
    p.wait(40)
    files = [n for n in files if n != 'Gone.txt']
    root = S.listing(dirs, files)
    p.click(*S.cell(root.index('Old')))
    p.menu('file', 'delete')
    p.wait(20)
    p.click(S.YES_X, S.YES_Y)
    p.wait(40)
    dirs = [n for n in dirs if n != 'Old']
    root = S.listing(dirs, files)
    p.click(*S.cell(root.index('Info.cvt')))
    p.menu('file', 'info')
    p.wait(30)
    for _ in range(len(OLD_DESC)):
        p.key(8)
    for c in NEW_DESC:
        p.key(c)
    p.key(13)
    p.wait(40)
    p.end(S.END_DONE)
    return p


def async_at(p, x, y, b, gap):
    p.recs.append((p.f, x, y, b | ASYNC, 0))
    p.f += gap


def b_part(d, extra, cancel):
    dirs, files = root_listing(d, extra)
    root = S.listing(dirs, files)
    p = S.Part()
    p.wait(20)
    p.dbl(*S.cell(0))
    p.wait(30)
    if cancel:
        p.menu('disk', 'empty')
        p.wait(20)
        p.click(S.YES_X, S.YES_Y)
        p.wait(40)
    p.click(*S.cell(root.index('Big')))
    p.menu('file', 'copy')
    p.dbl(*S.cell(root.index('Dest')))
    p.wait(30)
    # file/put here: the menu's click, then records that play while the
    # shell copies
    x, y = S.MENU_X['file'], S.ITEM_Y0 + S.ITEM_H * S.MENU_ITEMS['file'].index('put') + 8
    p.at(x, 7, 0, 4)
    p.at(x, 7, 1, 2)
    p.at(x, y, 0, 30)
    p.at(x, y, 0, 4)
    p.at(x, y, 1, 3)
    p.at(x, y, 0, 2)
    p.f += 30
    if not cancel:
        p.recs.append((p.f, 0, 0, 0x40 | ASYNC, S.END_DONE))
        return p
    async_at(p, CANCEL[0], CANCEL[1], 0, 4)
    async_at(p, CANCEL[0], CANCEL[1], 1, 4)
    async_at(p, CANCEL[0], CANCEL[1], 0, 2)
    p.wait(60)
    p.end(S.END_DONE)
    return p


def tree(d):
    out = {}
    for base, ds, fs in os.walk(d):
        r = os.path.relpath(base, d)
        out[r] = None
        for f in fs:
            out[os.path.join(r, f)] = open(os.path.join(base, f), 'rb').read()
    return out


def fail(m):
    print('shell_files_script: ' + m)
    sys.exit(1)


def check_a(before, after):
    for src, dst in (('Tree', 'Dest/Tree'), ('Mover', 'Box/Mover'), ('Old', 'VERANDA/.SYSTEM/TRASH/Old')):
        a, b = tree(os.path.join(before, src)), tree(os.path.join(after, dst))
        if a != b:
            fail('%s is not %s: %s' % (dst, src, sorted(set(a) ^ set(b)) or 'contents differ'))
    for gone in ('Mover', 'Old', 'Gone.txt'):
        if os.path.exists(os.path.join(after, gone)):
            fail('%s is still there' % gone)
    if tree(os.path.join(before, 'Tree')) != tree(os.path.join(after, 'Tree')):
        fail('Tree changed')
    if tree(os.path.join(after, 'Box'))['./box.txt'] != b'box\n':
        fail('Box/box.txt')
    if open(os.path.join(after, 'VERANDA/.SYSTEM/TRASH/Gone.txt'), 'rb').read() != b'to the trash\n':
        fail('VERANDA/.SYSTEM/TRASH/Gone.txt')
    a, b = open(os.path.join(before, 'Info.cvt'), 'rb').read(), open(os.path.join(after, 'Info.cvt'), 'rb').read()
    want = a[:412] + NEW_DESC.ljust(96, b'\0') + a[508:]
    if b != want:
        diff = [i for i in range(min(len(a), len(b))) if b[i] != want[i]][:8]
        fail('Info.cvt: %d bytes, differs at %s (want the description at 412 only)' % (len(b), diff))
    print('shell_files_script: Dest/Tree equals Tree (%d files and folders, an empty one, a 20 KB file); '
          'Box/Mover equals Mover, Mover gone; Gone.txt and Old in VERANDA/.SYSTEM/TRASH; Info.cvt\'s '
          'description is "%s", its other bytes as they were' % (len(tree(os.path.join(before, 'Tree'))),
                                                                 NEW_DESC.decode()))


def check_b(before, after, console):
    log = open(console, 'rb').read().decode('latin-1')
    t = os.path.join(after, 'VERANDA/.SYSTEM/TRASH')
    if not os.path.isdir(t) or os.listdir(t):
        fail('the trash is not there and empty: %s' % (os.listdir(t) if os.path.isdir(t) else None))
    import re
    m = re.search(r'SHELL STOPPED (\d+)', log)
    if not m:
        fail('no SHELL STOPPED on the console (the cancel came too late?)')
    n = int(m.group(1))
    got = sorted(os.listdir(os.path.join(after, 'Dest/Big')))
    if not 0 < n < 40 or len(got) != n:
        fail('stopped after %d files, Dest/Big has %d' % (n, len(got)))
    for f in got:
        if not filecmp.cmp(os.path.join(before, 'Big', f), os.path.join(after, 'Dest/Big', f), shallow=False):
            fail('Dest/Big/%s is not whole' % f)
    if len(os.listdir(os.path.join(after, 'Big'))) != 40:
        fail('Big changed')
    print('shell_files_script: empty trash left an empty TRASH; the copy of Big (40 files) was cancelled '
          'after %d, each of them whole' % n)


def main():
    cmd, d = sys.argv[1], sys.argv[2]
    if cmd == 'make':
        make_a(d)
    elif cmd == 'make-big':
        make_b(d)
    elif cmd in ('a', 'find'):
        S.write(os.path.join(d, 'SHELL.TST'), [a_part(d, sys.argv[3:], cmd == 'find')])
    elif cmd in ('b', 'progress'):
        S.write(os.path.join(d, 'SHELL.TST'), [b_part(d, sys.argv[3:], cmd == 'b')])
    elif cmd == 'check-a':
        check_a(d, sys.argv[3])
    elif cmd == 'check-b':
        check_b(d, sys.argv[3], sys.argv[4])
    else:
        sys.exit(__doc__)


if __name__ == '__main__':
    main()
