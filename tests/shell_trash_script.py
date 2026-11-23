#!/usr/bin/env python3
"""Gate shell, the trash from /VERANDA/APPS (DECISIONS V182): the run
folder and SHELL.TST (shell/play.s; tests/shell_script.py's records).

usage: shell_trash_script.py make <folder> [apps]   the fixtures
       shell_trash_script.py script <folder>        SHELL.TST
       shell_trash_script.py check <folder> <apps|''> <console>
                                                    the console and the files after

The fixtures: /VERANDA/APPS (a package's APPS folder copied when given,
else three stubs) with letter.cvt (a geoWrite document: VLIR, Write Image
V2.1, as the user's) and a long-named document; a /DOCUMENTS/letter.cvt
too; LIST.DEF (the windows open in the list).

The user's report (pkg-0.9.0-54b3dbd): a geoWrite document in /VERANDA/APPS, Delete:
it stayed; Delete again: "Use file > empty trash."; the trash empty (V71's
vr_insys refused everything inside /VERANDA).

One part, the windows logging their rows (view > by name: SHELL LIST,
SHELL ROW); the shell starts in /DOCUMENTS:
1. Apps (the sidebar), letter.cvt selected (Home, then Tab), file >
   delete, YES; the list (without it);
2. the long-named document selected, the Del key, YES; the list;
3. Documents (the sidebar), view > by icon, its letter.cvt deleted (file
   > delete, YES): letter~2.cvt in the trash; the list;
4. disk > trash (window 1): its rows (the three); letter~2.cvt deleted
   for good there (Del, YES); view > up a folder: .SYSTEM's rows, TRASH
   selected, file > delete: kept ("Use Disk > Empty trash."), its OK;
5. Veranda (window 0's sidebar: /VERANDA), SHELL.cvt selected, file >
   delete: kept ("Veranda needs this"), its OK; then APPS the same;
6. disk > empty trash, YES (SHELL EMPTIED 2); disk > trash: no rows;
the end.
"""
import os
import re
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import shell_script as S  # noqa: E402
import shell_subst  # noqa: E402

LONG = 'A letter to Ada about the garden.cvt'


def doc(name):
    page = b'\x11' + bytes(32) + b'\x10\x01\x00\x00Dear Ada\r' + b'x' * 300 + b'\0'
    return shell_subst.cvt(name, 'Write Image V2.1', 'geoWrite    V2.1', {0: page})


def apps_list(d):
    return ['..'] + S.listing([], os.listdir(os.path.join(d, 'VERANDA', 'APPS')))


def make(d, apps):
    a = os.path.join(d, 'VERANDA', 'APPS')
    os.makedirs(a, exist_ok=True)
    os.makedirs(os.path.join(d, 'DOCUMENTS'), exist_ok=True)
    if apps:
        for n in os.listdir(apps):
            shutil.copy(os.path.join(apps, n), a)
    else:
        for n in ('Calculator', 'Note Pad', 'View'):
            open(os.path.join(a, n + '.cvt'), 'wb').write(doc(n))
    open(os.path.join(a, 'letter.cvt'), 'wb').write(doc('letter'))
    open(os.path.join(a, LONG), 'wb').write(doc('Ada letter'))
    open(os.path.join(d, 'DOCUMENTS', 'letter.cvt'), 'wb').write(doc('letter'))
    open(os.path.join(d, 'LIST.DEF'), 'wb').close()


def select(p, i):
    p.key(0x13)                                 # Home (ISO): select > first
    p.wait(10)
    for _ in range(i):
        p.key(9)                                # Tab: select > next
        p.wait(6)
    p.wait(10)


def yes(p):
    p.wait(20)
    p.click(S.YES_X, S.YES_Y)
    p.wait(60)


def script(d):
    apps = apps_list(d)
    p = S.Part()
    p.wait(30)
    p.click(*S.place(1))                        # Apps
    p.wait(60)
    p.menu('view', 'name')
    select(p, apps.index('letter.cvt'))
    p.menu('file', 'delete')
    yes(p)
    p.menu('view', 'name')
    apps.remove('letter.cvt')
    select(p, apps.index(LONG))
    p.key(0x19)                                 # Del (ISO): file > delete
    yes(p)
    p.menu('view', 'name')
    p.click(*S.place(2))                        # Documents
    p.wait(60)
    p.menu('view', 'icon')
    select(p, 1)                                # (.., letter.cvt)
    p.menu('file', 'delete')
    yes(p)
    p.menu('view', 'name')
    p.menu('disk', 'trash')
    p.wait(30)
    p.menu('view', 'name')
    trash = ['..'] + S.listing([], [LONG, 'letter.cvt', 'letter~2.cvt'])
    select(p, trash.index('letter~2.cvt'))
    p.key(0x19)                                 # Del: for good
    yes(p)
    p.menu('view', 'name')
    p.menu('view', 'up')                       # /VERANDA/.SYSTEM
    p.wait(30)
    p.menu('view', 'name')
    select(p, 1)                                # (.., TRASH: its only folder)
    p.menu('file', 'delete')
    yes(p)                                      # (the warning's OK is where YES is)
    p.click(*S.place(0))                        # Veranda (/VERANDA), window 0
    p.wait(60)
    sysl = ['..'] + S.listing(['APPS'], ['SHELL.cvt'])
    for n in ('SHELL.cvt', 'APPS'):
        select(p, sysl.index(n))
        p.menu('file', 'delete')
        yes(p)
    p.menu('disk', 'empty')
    yes(p)
    p.menu('disk', 'trash')
    p.wait(30)
    p.menu('view', 'name')
    p.wait(30)
    p.end(S.END_DONE)
    S.write(os.path.join(d, 'SHELL.TST'), [p])


def want():
    """the console's lines (SHELL TRASHED ... KEPT; each list's rows of ..,
    the two documents and TRASH, joined), in order"""
    j = '|'.join
    return ['LIST 0', j(['..', LONG, 'letter.cvt']),                   # Apps
            'TRASHED letter.cvt AS letter.cvt', 'LIST 0', j(['..', LONG]),
            'TRASHED %s AS %s' % (LONG, LONG), 'LIST 0', '..',
            'TRASHED letter.cvt AS letter~2.cvt', 'LIST 0', '..',      # /DOCUMENTS
            'LIST 1', j(['..', LONG, 'letter.cvt', 'letter~2.cvt']),   # the trash
            'DELETED letter~2.cvt', 'LIST 1', j(['..', LONG, 'letter.cvt']),
            'LIST 1', '..|TRASH', 'KEPT TRASH',                        # .SYSTEM
            'KEPT SHELL.cvt', 'KEPT APPS', 'EMPTIED 2', 'LIST 1', '..', 'DONE']


def log(console):
    """the console as want()'s lines: the rows of a list joined (only ..,
    the documents and TRASH: the applications' rows left out)"""
    out, rows = [], None
    for ln in open(console, 'rb').read().decode('latin-1').replace('\r', '\n').split('\n'):
        m = re.search(r'SHELL (TRASHED|DELETED|KEPT|EMPTIED|DONE|LIST [01]|ROW)( ?.*)$', ln)
        if not m:
            continue
        k, rest = m.group(1), m.group(2).strip()
        if k == 'ROW':
            n = rest.split('|')[0]
            if n in ('..', LONG, 'letter.cvt', 'letter~2.cvt', 'TRASH') and rows is not None:
                rows.append(n)
            continue
        if rows is not None:
            out.append('|'.join(rows))
            rows = None
        out.append(k if k.startswith('LIST') else (k + ' ' + rest).strip())
        if k.startswith('LIST'):
            rows = []
    if rows is not None:
        out.append('|'.join(rows))
    return out


def check(card, apps, console):
    got, w = log(console), want()
    if got != w:
        sys.exit('shell_trash_script: the console has\n  %s\nnot\n  %s' % ('\n  '.join(got), '\n  '.join(w)))
    a = os.path.join(card, 'VERANDA', 'APPS')
    left = sorted(os.listdir(a))
    exp = sorted(os.listdir(apps)) if apps else ['Calculator.cvt', 'Note Pad.cvt', 'View.cvt']
    if left != exp:
        sys.exit('shell_trash_script: APPS holds %s, not %s' % (left, exp))
    for n in exp:
        if apps and open(os.path.join(a, n), 'rb').read() != open(os.path.join(apps, n), 'rb').read():
            sys.exit('shell_trash_script: APPS/%s changed' % n)
    if os.listdir(os.path.join(card, 'DOCUMENTS')):
        sys.exit('shell_trash_script: /DOCUMENTS is not empty: %s' % os.listdir(os.path.join(card, 'DOCUMENTS')))
    t = os.path.join(card, 'VERANDA', '.SYSTEM', 'TRASH')
    if not os.path.isdir(t) or os.listdir(t):
        sys.exit('shell_trash_script: the trash is not an empty folder')
    if not os.path.isfile(os.path.join(card, 'VERANDA', 'SHELL.cvt')):
        sys.exit('shell_trash_script: /VERANDA/SHELL.cvt is gone')
    print('shell_trash_script: %d lines in order; APPS without the two documents (%d left, unchanged), '
          '/DOCUMENTS empty, the trash empty, SHELL.cvt kept' % (len(w), len(exp)))


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    what, d = sys.argv[1], sys.argv[2]
    if what == 'make':
        make(d, sys.argv[3] if len(sys.argv) > 3 else None)
    elif what == 'script':
        script(d)
    elif what == 'check' and len(sys.argv) > 4:
        check(d, sys.argv[3] or None, sys.argv[4])
    else:
        sys.exit(__doc__)


if __name__ == '__main__':
    main()
