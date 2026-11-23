#!/usr/bin/env python3
"""Gate layout (tools/gate_layout.sh, DECISIONS V71): the card's folders.

usage: layout_gate.py card <folder>                 the old card's own files
       layout_gate.py inventory <folder> <out.json>  every file: its bytes' hash
       layout_gate.py check <before.json> <after> <console>
                                                     the migration (Veranda Setup)
       layout_gate.py script <run> <card>            SHELL.TST (and the run's files)
       layout_gate.py after <run> <card> <console>   a run's results

The old card (the user's kind, before V71: everything in /VERANDA): the
system (VERANDA.PRG, VERANDA.SYS, RBOOT, SHELL.cvt, AUTOBOOT.X16 and
Veranda Setup, copied by the gate), the applications and accessories at
the top of /VERANDA (copied by the gate), and here: Veranda Prefs.cvt (the
theme Graphite), Note File.cvt (three pages), Text  Scrap.cvt, SHELL.DSK
(a pin: /VERANDA, Paint.cvt), TERM.CFG, TRASH/ (old.txt, Sub/deep.txt),
the user's documents test.cvt and eeee.cvt (GEOS documents), NOTES.TXT
and song.mod, a folder of the user's (Mods/x.mod, it stays); in the root
README.TXT and DOCUMENTS/NOTES.TXT (taken: the moved NOTES.TXT is kept as
NOTES~2.TXT); APPS/Calculator.cvt (the package copied over the card: the
old Calculator goes to .SYSTEM/OLD).

The runs on the migrated card (the shell starts in /DOCUMENTS, window 0):
  migrate  part 0 (after Setup): the second icon selected; the end
  theme    the same on the migrated card: the settings from .SYSTEM
           (Graphite's colours: tests/check_theme.py)
  look     disk > trash (window 1: the trash, two entries), geos > desk
           accessory (the list from /VERANDA/APPS: SHELL DESK ACCESSORIES
           n), the end with the list open
  note     to /VERANDA/APPS through the windows, Note Pad double-clicked:
           NOTE RUNNING 1 3 (its Note File found in .SYSTEM)
  edit     to /VERANDA/APPS, Veranda Edit double-clicked (no document: it
           works in /DOCUMENTS); its test build's EDIT.PLY (in /DOCUMENTS)
           types a line, Ctrl+S, the name LAYOUT.TXT, Return: saved there
  paint    the pin double-clicked (moved to /VERANDA/APPS by the shell):
           Paint's test build saves Picture, Sketch, Print.bmp, Draft 1-5
           in /DOCUMENTS
  txt      NOTES.TXT double-clicked: Veranda Edit from /VERANDA/APPS
  mod      song.mod double-clicked: the MOD Player from /VERANDA/APPS
  basic    options > BASIC (keep Veranda); G0 in /VERANDA (the system
           folder, BASIC's current one): LOAD"RBOOT"; part 1: the shell
           back in /DOCUMENTS, the end
  boot     (typed: DOS"CD:VERANDA", BOOT: AUTOBOOT.X16) the shell, the end
"""
import hashlib
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, '..', 'tools'))
import shell_script as S  # noqa: E402
import vdisk  # noqa: E402
import check_theme  # noqa: E402
import basic_gate  # noqa: E402
import edit_script  # noqa: E402

SYSTEM = ('VERANDA.PRG', 'VERANDA.SYS', 'RBOOT', 'SHELL.cvt', 'AUTOBOOT.X16', 'Veranda Setup.cvt')
PAGES = [b'The first page.', b'A second page.', b'A third page.']


def put(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, 'wb').write(data)


def card(d):
    v = os.path.join(d, 'VERANDA')
    check_theme.prefs(os.path.join(v, 'Veranda Prefs.cvt'), 15, 0, 12, 2)       # Graphite
    put(os.path.join(v, 'Note File.cvt'), vdisk.make_cvt('Note File', 7, b'Note File   V1.0', recs=PAGES,
                                                         author=b'Veranda', parent=b'Note Pad    V1.0'))
    text = b'\x17\x09\x00\x00A scrap from before.\r'
    put(os.path.join(v, 'Text  Scrap.cvt'), vdisk.make_cvt('Text  Scrap', 4, b'Text  Scrap V2.0',
                                                           data=bytes([len(text), 0]) + text))
    dsk = bytearray(16 + 61 + 1 + 1 + 4 * (62 + 22))
    dsk[0:4] = b'VSD\x01'
    dsk[16] = ord('/')
    dsk[16 + 62] = 1                                    # one pin
    pin = 16 + 62 + 1
    dsk[pin:pin + 8] = b'/VERANDA'
    dsk[pin + 62:pin + 62 + 9] = b'Paint.cvt'
    put(os.path.join(v, 'SHELL.DSK'), bytes(dsk))
    put(os.path.join(v, 'TERM.CFG'), b'old settings')
    put(os.path.join(v, 'TRASH', 'old.txt'), b'thrown away\n')
    put(os.path.join(v, 'TRASH', 'Sub', 'deep.txt'), b'a folder thrown away\n')
    put(os.path.join(v, 'test.cvt'), vdisk.make_cvt('test', 7, b'Test Doc    V1.0', data=b'a test document\r',
                                                    author=b'The user'))
    put(os.path.join(v, 'eeee.cvt'), vdisk.make_cvt('eeee', 3, b'', data=b'eeee\r'))
    put(os.path.join(v, 'NOTES.TXT'), b'Notes kept in /VERANDA before.\n')
    put(os.path.join(v, 'song.mod'), bytes(1084) + bytes(range(256)) * 4)
    put(os.path.join(v, 'Mods', 'x.mod'), b'a module of the user\'s folder\n')
    put(os.path.join(d, 'README.TXT'), b'the card\'s own file\n')
    # the package copied over the card first: APPS has the new Calculator,
    # the old copy at the top goes to .SYSTEM/OLD
    put(os.path.join(v, 'APPS', 'Calculator.cvt'), open(os.path.join(v, 'Calculator.cvt'), 'rb').read())
    put(os.path.join(d, 'DOCUMENTS', 'NOTES.TXT'), b'Notes already in /DOCUMENTS.\n')


def inventory(d):
    out = {}
    for base, ds, fs in os.walk(d):
        for f in fs:
            p = os.path.join(base, f)
            out[os.path.relpath(p, d)] = hashlib.sha1(open(p, 'rb').read()).hexdigest()
    return out


def fail(m):
    print('FAIL  ' + m)
    sys.exit(1)


def ok(m):
    print('ok    ' + m)


def where(path, gtype):
    """the folder Veranda Setup moves a file of the old /VERANDA to"""
    n = path.split('/', 1)[1]
    if '/' in n:                                        # in a folder
        top, rest = n.split('/', 1)
        return 'VERANDA/.SYSTEM/TRASH/' + rest if top == 'TRASH' else path
    if n in SYSTEM:
        return path
    if n in ('Veranda Prefs.cvt', 'Note File.cvt', 'Text  Scrap.cvt', 'SHELL.DSK', 'TERM.CFG'):
        return 'VERANDA/.SYSTEM/' + n
    if n == 'Calculator.cvt':
        return 'VERANDA/.SYSTEM/OLD/' + n                # (APPS has it: the package's)
    if n.lower().endswith('.cvt') and gtype in (5, 6, 14):
        return 'VERANDA/APPS/' + n
    if n == 'NOTES.TXT':
        return 'DOCUMENTS/NOTES~2.TXT'                  # (taken in /DOCUMENTS)
    return 'DOCUMENTS/' + n


def check(before_json, after, console):
    before = json.load(open(before_json))
    types = before.pop('_types')
    got = inventory(after)
    moved = 0
    for p, h in sorted(before.items()):
        if not p.startswith('VERANDA/'):
            want = p
        else:
            want = where(p, types.get(p))
        if want not in got:
            fail('%s: not at %s after the migration' % (p, want))
        moved += want != p
        if want.endswith('SHELL.DSK'):
            continue                                    # (the shell writes it again: the pin's folder)
        if got[want] != h:
            fail('%s: %s has other bytes' % (p, want))
    lost = set(before.values()) - set(got.values())
    if lost:
        fail('%d files\' bytes are nowhere on the card after' % len(lost))
    for gone in ('VERANDA/TRASH/old.txt', 'VERANDA/NOTES.TXT', 'VERANDA/Paint.cvt'):
        if gone in got:
            fail('%s is still there' % gone)
    if os.path.isdir(os.path.join(after, 'VERANDA', 'TRASH')):
        fail('the old VERANDA/TRASH folder is still there')
    log = os.path.join(after, 'VERANDA', '.SYSTEM', 'LAYOUT.LOG')
    if not os.path.exists(log) or b'moved' not in open(log, 'rb').read():
        fail('no VERANDA/.SYSTEM/LAYOUT.LOG (the mark that Setup ran) with the moves')
    con = open(console, 'rb').read().decode('latin-1').replace('\r', '')
    m = re.search(r'SETUP DONE: (\d+) moved, (\d+) left, (\d+) failed', con)
    if not m or int(m.group(3)):
        fail('the console has no "SETUP DONE: n moved, m left, 0 failed"')
    if int(m.group(1)) != moved:
        fail('Setup moved %s files, the inventory %d' % (m.group(1), moved))
    i = con.find('SETUP DONE')
    if not re.search(r'SHELL READY 0 IN /DOCUMENTS', con[i:]):
        fail('the shell did not start in /DOCUMENTS after Setup')
    ok('the migration: %d files moved (the system\'s to VERANDA/.SYSTEM, the trash\'s to .SYSTEM/TRASH, the '
       'applications and accessories to VERANDA/APPS, the documents to /DOCUMENTS, NOTES.TXT as NOTES~2.TXT '
       'beside the one there), %s left (a folder of the user\'s), the system files and Mods/x.mod where they '
       'were; every file of before on the card after, its bytes equal (a host-side inventory: %d files); '
       'LAYOUT.LOG; then the shell in /DOCUMENTS' % (moved, m.group(2), len(before)))


def ls(card_dir, sub):
    p = os.path.join(card_dir, sub)
    names = [n for n in os.listdir(p) if not n.startswith('.')]
    dirs = [n for n in names if os.path.isdir(os.path.join(p, n))]
    files = [n for n in names if not os.path.isdir(os.path.join(p, n))]
    return dirs, files


def to_apps(p, card_dir):
    """window 0 from /DOCUMENTS to /VERANDA/APPS; the listing of APPS"""
    p.dbl(*S.cell(0))                                   # ".."
    p.wait(40)
    d, f = ls(card_dir, '')
    top = S.listing(d, sorted(set(f + ['SHELL.TST', 'SHELL.STP'])))
    p.dbl(*S.cell(top.index('VERANDA')))
    p.wait(40)
    d, f = ls(card_dir, 'VERANDA')
    sysd = ['..'] + S.listing(d, f)
    p.dbl(*S.cell(sysd.index('APPS')))
    p.wait(40)
    d, f = ls(card_dir, 'VERANDA/APPS')
    return ['..'] + S.listing(d, f)


def script(run, c):
    docs = lambda: ['..'] + S.listing(*ls(c, 'DOCUMENTS'))   # noqa: E731
    p = S.Part()
    p.wait(30)
    parts = [p]
    if run in ('migrate', 'theme', 'boot'):
        p.click(*S.cell(1))
        p.wait(30)
        p.end(S.END_DONE)
    elif run == 'look':
        p.menu('disk', 'trash')
        p.wait(60)
        p.menu('geos', 'desk accessory')
        p.wait(60)
        p.end(S.END_DONE)
    elif run in ('note', 'edit'):
        apps = to_apps(p, c)
        p.dbl(*S.cell(apps.index('Note Pad.cvt' if run == 'note' else 'Veranda Edit.cvt')))
        p.end(S.END_STOP)
        if run == 'edit':
            s = edit_script.Script()
            s.W(30)
            s.T('A line saved in /DOCUMENTS.')
            s.K(ord('s'), edit_script.CTRL)                 # Save: a new document, Save as
            s.W(30)
            for _ in range(len('Untitled.txt')):
                s.K(edit_script.BS)
            s.T('LAYOUT.TXT')
            s.K(edit_script.RET)
            s.W(60)
            s.b += b'W\x1eE'
            open(os.path.join(c, 'DOCUMENTS', 'EDIT.PLY'), 'wb').write(s.b)
    elif run == 'paint':
        p.dbl(*S.desk_pin(0))
        p.end(S.END_STOP)
    elif run in ('txt', 'mod'):
        p.dbl(*S.cell(docs().index('NOTES.TXT' if run == 'txt' else 'song.mod')))
        p.end(S.END_STOP)
    elif run == 'basic':
        p.menu('options', 'basic')
        p.end(S.END_STOP)
        q = S.Part()
        q.wait(30)
        q.end(S.END_DONE)
        parts.append(q)
        open(os.path.join(c, 'VERANDA', 'G0'), 'wb').write(
            basic_gate.prg(['10 PRINT "G0 RBOOT":LOAD "RBOOT",8']))
    else:
        sys.exit('layout_gate: no run ' + run)
    S.write(os.path.join(c, 'SHELL.TST'), parts)


def after(run, c, console):
    con = open(console, 'rb').read().decode('latin-1').replace('\r', '')
    con = re.sub(r'\\X[0-9A-F]{2}', '', con)

    def has(*want):
        i = 0
        for w in want:
            j = con.find(w, i)
            if j < 0:
                fail('%s: the console has no "%s" (in order)' % (run, w))
            i = j + len(w)
    has('SHELL READY 0 IN /DOCUMENTS')
    if run == 'look':
        has('SHELL STATUS 1 /VERANDA/.SYSTEM/TRASH: 2 files', 'SHELL DESK ACCESSORIES')
        n = int(re.search(r'SHELL DESK ACCESSORIES (\d+)', con).group(1))
        if n < 5:
            fail('look: the desk accessories\' list has %d' % n)
        ok('the trash found in /VERANDA/.SYSTEM/TRASH (old.txt and the folder Sub, moved there); geos > desk '
           'accessory lists %d accessories from /VERANDA/APPS' % n)
    elif run == 'note':
        has('CD:/VERANDA/APPS', 'NOTE RUNNING 1 3')
        ok('Note Pad started from /VERANDA/APPS found its Note File in /VERANDA/.SYSTEM: three pages')
    elif run == 'edit':
        has('EDIT RUNNING')
        f = os.path.join(c, 'DOCUMENTS', 'LAYOUT.TXT')
        if not os.path.exists(f) or b'A line saved in /DOCUMENTS.' not in open(f, 'rb').read():
            fail('edit: no DOCUMENTS/LAYOUT.TXT with the line typed')
        if os.path.exists(os.path.join(c, 'VERANDA', 'APPS', 'LAYOUT.TXT')):
            fail('edit: LAYOUT.TXT in VERANDA/APPS')
        ok('Veranda Edit started from /VERANDA/APPS without a document: its first Save went to /DOCUMENTS '
           '(DOCUMENTS/LAYOUT.TXT, the line typed)')
    elif run == 'paint':
        has('PAINT RUNNING')
        f = os.path.join(c, 'DOCUMENTS', 'Picture.cvt')
        if not os.path.exists(f) or b'Paint Image V1.0' not in open(f, 'rb').read():
            fail('paint: no DOCUMENTS/Picture.cvt (a Paint Image)')
        for n in ('Sketch.cvt', 'Print.bmp'):
            if not os.path.exists(os.path.join(c, 'DOCUMENTS', n)):
                fail('paint: no DOCUMENTS/' + n)
        if [n for n in os.listdir(os.path.join(c, 'VERANDA', 'APPS')) if n.startswith('Picture')]:
            fail('paint: a picture saved in VERANDA/APPS')
        dsk = open(os.path.join(c, 'VERANDA', '.SYSTEM', 'SHELL.DSK'), 'rb').read()
        if b'/VERANDA/APPS' not in dsk:
            fail('paint: the pin was not moved to /VERANDA/APPS in SHELL.DSK')
        ok('the pin (from before: /VERANDA, Paint.cvt) started Paint from /VERANDA/APPS (SHELL.DSK says so '
           'now); Paint\'s saves went to /DOCUMENTS (Picture.cvt, Sketch.cvt, Print.bmp)')
    elif run == 'txt':
        has('CD:/VERANDA/APPS', 'EDIT RUNNING')
        ok('open with: NOTES.TXT in /DOCUMENTS opened Veranda Edit from /VERANDA/APPS')
    elif run == 'mod':
        has('CD:/VERANDA/APPS', 'VMP RUNNING')
        ok('open with: song.mod in /DOCUMENTS opened the MOD Player from /VERANDA/APPS')
    elif run == 'basic':
        has('VERANDA STAYS IN MEMORY', 'G0 RBOOT', 'SHELL READY 1 IN /DOCUMENTS', 'SHELL DONE')
        ok('options > BASIC (keep Veranda); in BASIC, in /VERANDA, LOAD"RBOOT": the shell back in /DOCUMENTS')
    elif run in ('migrate', 'theme', 'boot'):
        has('SHELL DONE')


def main():
    a = sys.argv[1:]
    if not a:
        sys.exit(__doc__)
    if a[0] == 'card':
        card(a[1])
    elif a[0] == 'inventory':
        inv = inventory(a[1])
        types = {}
        for p in inv:
            if p.lower().endswith('.cvt'):
                types[p] = open(os.path.join(a[1], p), 'rb').read()[22]
        inv['_types'] = types
        json.dump(inv, open(a[2], 'w'), indent=1, sort_keys=True)
    elif a[0] == 'check':
        check(a[1], a[2], a[3])
    elif a[0] == 'script':
        script(a[1], a[2])
    elif a[0] == 'after':
        after(a[1], a[2], a[3])
    else:
        sys.exit(__doc__)


if __name__ == '__main__':
    main()
