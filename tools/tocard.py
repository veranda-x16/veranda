#!/usr/bin/env python3
"""tools/tocard.sh's checks (docs/RELEASING.md): what a package may write to
an SD card, what it must not, and afterwards that it did just that.

    tocard.py plan <pkg> <card> <work> [--force]
        writes <work>/copy.lst (the package's files to copy), skip.lst
        (DOCUMENTS files the card has already: never overwritten),
        move.lst (files of an earlier package that this one no longer has:
        to /VERANDA/.SYSTEM/OLD/), user.sums (every other file of the
        card's VERANDA, DOCUMENTS, PC and TILEHW: the user's, checksummed);
        exits 3, and writes refuse.lst, when the package would overwrite a
        file that looks like the user's (see below); --force takes them too
    tocard.py move <card> <work>
        moves move.lst's files into VERANDA/.SYSTEM/OLD/ (name~2 when taken)
    tocard.py verify <pkg> <card> <work>
        every copied file the same bytes as the package's, every moved file
        whole at its new place, every file of user.sums unchanged

The user's file (the package would overwrite it, and its bytes differ):
  - anything in VERANDA/.SYSTEM (a package never has one);
  - a name the user keeps (any case): TOCARD_KEEP (names, comma separated),
    else the file $VERANDA_DIST/tocard.keep (a name a line; VERANDA_DIST
    defaults to ~/Projects/veranda-dist), outside the tree: the names of
    one's own files are one's own (DECISIONS V139);
  - a file the card's VERANDA/UPDATE.LST lists, whose size or CRC-32 is no
    longer what the list says (changed on the card since it was installed;
    VERANDA/README.txt, CHANGES.txt and UPDATE.LST excepted: the
    package's own texts);
  - a file the list does not name, written more than an hour after the
    card's VERANDA/VERANDA.SYS (the last install): written on the card.
DOCUMENTS: a file the card has is never written, whatever it holds.

MIT licence (see LICENSE)."""
import hashlib
import os
import sys
import zlib

TOPS = ('VERANDA', 'DOCUMENTS', 'PC', 'TILEHW')


def keep_names():
    """the user's own file names (lower case): TOCARD_KEEP, else $VERANDA_DIST/tocard.keep"""
    v = os.environ.get('TOCARD_KEEP')
    if v is None:
        dist = os.environ.get('VERANDA_DIST') or os.path.join(os.path.expanduser('~'), 'Projects', 'veranda-dist')
        try:
            with open(os.path.join(dist, 'tocard.keep'), encoding='utf-8') as f:
                v = ','.join(l.split('#', 1)[0].strip() for l in f)
        except OSError:
            v = ''
    return tuple(n.strip().lower() for n in v.split(',') if n.strip())


USER_NAMES = keep_names()
PKG_TEXT = ('VERANDA/README.txt', 'VERANDA/CHANGES.txt', 'VERANDA/UPDATE.LST')
DROPPED = ('VERANDA/APPS/TopDesk.cvt',)          # (dropped before the card had UPDATE.LST's to say so)
OLD = 'VERANDA/.SYSTEM/OLD'
HOUR = 3600


def files(root):
    out = []
    for top in TOPS:
        for d, dirs, fs in os.walk(os.path.join(root, top)):
            dirs.sort()
            for f in sorted(fs):
                out.append(os.path.relpath(os.path.join(d, f), root).replace(os.sep, '/'))
    return out


def sha(p):
    h = hashlib.sha256()
    with open(p, 'rb') as f:
        for b in iter(lambda: f.read(1 << 20), b''):
            h.update(b)
    return h.hexdigest()


def crc(p):
    with open(p, 'rb') as f:
        return zlib.crc32(f.read()) & 0xFFFFFFFF


def card_list(card):
    """the card's VERANDA/UPDATE.LST: {path: (size, crc, kind)}"""
    m = {}
    p = os.path.join(card, 'VERANDA', 'UPDATE.LST')
    if not os.path.isfile(p):
        return None
    for l in open(p, encoding='latin-1'):
        if l.startswith('file '):
            f = l.rstrip('\n').split(' ', 6)
            m[f[6]] = (int(f[1]), int(f[2], 16), f[3])
    return m


def same(a, b):
    if os.path.getsize(a) != os.path.getsize(b):
        return False
    with open(a, 'rb') as fa, open(b, 'rb') as fb:
        while True:
            x, y = fa.read(1 << 20), fb.read(1 << 20)
            if x != y:
                return False
            if not x:
                return True


def write(path, lines):
    with open(path, 'w', encoding='utf-8') as f:
        for l in lines:
            f.write(l + '\n')


def read(path):
    if not os.path.exists(path):
        return []
    return [l.rstrip('\n') for l in open(path, encoding='utf-8') if l.strip()]


def plan(pkg, card, work, force):
    pk = files(pkg)
    pset = set(pk)
    lst = card_list(card)
    sysf = os.path.join(card, 'VERANDA', 'VERANDA.SYS')
    installed = os.path.getmtime(sysf) if os.path.isfile(sysf) else None
    copy, skip, refuse, move, same_n = [], [], [], [], 0
    for p in pk:
        c = os.path.join(card, p)
        if not os.path.exists(c):
            copy.append(p)
            continue
        if not os.path.isfile(c):
            refuse.append('%s\tthe card has a folder of that name' % p)
            continue
        if same(c, os.path.join(pkg, p)):
            same_n += 1
            copy.append(p)          # (the same bytes: rsync leaves it, verify still checks it)
            continue
        if p.startswith('DOCUMENTS/'):
            skip.append(p)
            continue
        why = None
        low = p.rsplit('/', 1)[-1].lower()
        if p.startswith('VERANDA/.SYSTEM/'):
            why = 'in VERANDA/.SYSTEM (the user\'s settings)'
        elif low in USER_NAMES:
            why = 'a name of the user\'s files'
        elif p in PKG_TEXT:
            pass
        elif lst is not None and p in lst:
            size, cr, _ = lst[p]
            if os.path.getsize(c) != size or crc(c) != cr:
                why = 'changed on the card since it was installed (its size or CRC-32 is not what the card\'s UPDATE.LST says)'
        elif (lst is None or p not in lst) and installed is not None and os.path.getmtime(c) > installed + HOUR:
            why = 'written on the card after the last install (newer than VERANDA/VERANDA.SYS by %d min)' % (
                (os.path.getmtime(c) - installed) // 60)
        if why:
            refuse.append('%s\t%s' % (p, why))
            if not force:
                continue
        copy.append(p)
    # what an earlier package put there that this one no longer has
    cands = []
    if lst is not None:
        cands += [(p, lst[p]) for p in sorted(lst) if lst[p][2] != 'doc-sample']
    cands += [(p, None) for p in DROPPED if lst is None or p not in lst]
    kept = []
    for p, ent in cands:
        c = os.path.join(card, p)
        if p in pset or not os.path.isfile(c) or p.startswith('VERANDA/.SYSTEM/') or not p.startswith(('VERANDA/', 'PC/')):
            continue
        if ent is not None and (os.path.getsize(c) != ent[0] or crc(c) != ent[1]):
            kept.append('%s\tno longer in the package, but changed since it was installed: left where it is' % p)
            continue
        if ent is None and installed is not None and os.path.getmtime(c) > installed + HOUR:
            kept.append('%s\tno longer in the package, but written on the card: left where it is' % p)
            continue
        move.append(p)
    mset = set(move)
    cset = set(copy)
    user = []
    for p in files(card):
        if p in cset or p in mset:
            continue
        user.append('%s  %s' % (sha(os.path.join(card, p)), p))
    write(os.path.join(work, 'copy.lst'), copy)
    write(os.path.join(work, 'skip.lst'), skip)
    write(os.path.join(work, 'move.lst'), move)
    write(os.path.join(work, 'kept.lst'), kept)
    write(os.path.join(work, 'refuse.lst'), refuse)
    write(os.path.join(work, 'user.sums'), user)
    print('tocard: the package: %d files; to copy %d (%d the same bytes already), DOCUMENTS kept as the card has '
          'them %d, to move to %s %d, the user\'s files checksummed %d%s'
          % (len(pk), len(copy), same_n, len(skip), OLD, len(move), len(user),
             '' if lst is not None else ' (the card has no VERANDA/UPDATE.LST)'))
    for l in skip:
        print('tocard:   kept (DOCUMENTS, the card\'s own): %s' % l)
    for l in move:
        print('tocard:   to move to %s: %s' % (OLD, l))
    for l in kept:
        print('tocard:   %s' % l.replace('\t', ': '))
    if refuse:
        for l in refuse:
            print('tocard:   %s: %s' % ('OVERWRITTEN (--force)' if force else 'REFUSED', l.replace('\t', ': ')))
        if not force:
            print('tocard: the package would overwrite %d file(s) that look like the user\'s: nothing written '
                  '(look at them; --force overwrites them, after the backup)' % len(refuse))
            sys.exit(3)


def do_move(card, work):
    done = []
    od = os.path.join(card, *OLD.split('/'))
    os.makedirs(od, exist_ok=True)
    for p in read(os.path.join(work, 'move.lst')):
        src = os.path.join(card, *p.split('/'))
        base = p.rsplit('/', 1)[-1]
        stem, ext = os.path.splitext(base)
        dst, n = os.path.join(od, base), 2
        while os.path.exists(dst):
            dst = os.path.join(od, '%s~%d%s' % (stem, n, ext))
            n += 1
        h = sha(src)
        os.rename(src, dst)
        rel = os.path.relpath(dst, card).replace(os.sep, '/')
        done.append('%s  %s  %s' % (h, p, rel))
        print('tocard: moved %s -> %s' % (p, rel))
    write(os.path.join(work, 'moved.lst'), done)


def verify(pkg, card, work):
    bad = []
    copy = read(os.path.join(work, 'copy.lst'))
    for p in copy:
        if not os.path.isfile(os.path.join(card, p)) or not same(os.path.join(pkg, p), os.path.join(card, p)):
            bad.append('not the package\'s bytes: %s' % p)
    for l in read(os.path.join(work, 'moved.lst')):
        h, _, rest = l.partition('  ')
        src, _, dst = rest.partition('  ')
        if not os.path.isfile(os.path.join(card, dst)) or sha(os.path.join(card, dst)) != h:
            bad.append('moved but not whole: %s -> %s' % (src, dst))
        if os.path.exists(os.path.join(card, src)) and src not in copy:
            bad.append('moved but still there: %s' % src)
    user = read(os.path.join(work, 'user.sums'))
    for l in user:
        h, _, p = l.partition('  ')
        c = os.path.join(card, p)
        if not os.path.isfile(c):
            bad.append('the user\'s file is gone: %s' % p)
        elif sha(c) != h:
            bad.append('the user\'s file changed: %s' % p)
    for b in bad:
        print('tocard: FAIL %s' % b)
    if bad:
        sys.exit(1)
    print('tocard: verified: %d files the package\'s bytes (compared byte for byte), %d moved whole, '
          '%d files of the user\'s untouched (SHA-256 before and after)'
          % (len(copy), len(read(os.path.join(work, 'moved.lst'))), len(user)))


def main():
    a = sys.argv[1:]
    if a[:1] == ['plan'] and len(a) >= 4:
        plan(a[1], a[2], a[3], '--force' in a)
    elif a[:1] == ['move'] and len(a) == 3:
        do_move(a[1], a[2])
    elif a[:1] == ['verify'] and len(a) == 4:
        verify(a[1], a[2], a[3])
    else:
        sys.exit(__doc__)


if __name__ == '__main__':
    main()
