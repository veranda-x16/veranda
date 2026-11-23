#!/usr/bin/env python3
"""Gate disktools (DECISIONS V119): the host's side of Disk Tools' test.

usage: check_disktools.py plant <sd.img>
           the faults planted in an image made by tools/vcard.py from the
           gate's folder (its /DOCUMENTS/BAD/ files): a chain cut short,
           chains crossing, a chain pointing past the end, a file longer
           than its size, a chain running into a free cluster, a sector
           of the second FAT changed
       check_disktools.py card <sd.img>
           the card's numbers as Disk Tools logs them ("DT CARD ...")
       check_disktools.py expect <sd.img>
           Check's fault lines and its summary, from the image, by the same
           walk as apps/disktools/check.c (written again here in Python)
       check_disktools.py space <sd.img | folder> <path>
           the folders in path with their totals, as Space use logs them
       check_disktools.py log <session> <console.txt> <sd.img | folder> [<before>]
           the console's "DT ..." lines against the above (host, sdcheck,
           sdmod); Space use against <before> (the card or folder as it
           was before the session: its counts come before the clean-up)
"""
import os
import re
import struct
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'tools'))
import vcard  # noqa: E402

EOC = 0x0FFFFFF8
BADC = 0x0FFFFFF7
LFN_OFFS = [1, 3, 5, 7, 9, 14, 16, 18, 20, 22, 24, 28, 30]


def fail(msg):
    print('FAIL  ' + msg)
    sys.exit(1)


def ok(msg):
    print('ok    ' + msg)


# ---------------------------------------------------------------- the image
class Card:
    def __init__(self, path):
        self.fs = vcard.Fat32(path)
        f = self.fs
        bpb = f.read(f.part, 512)
        self.part_lba = f.part // 512
        tot = struct.unpack_from('<H', bpb, 19)[0] or struct.unpack_from('<I', bpb, 32)[0]
        mbr = f.read(0, 512)
        self.part_sec = struct.unpack_from('<I', mbr, 446 + 12)[0]
        self.tot = tot
        self.spc = f.spc
        self.resv = f.reserved
        self.nfats = f.nfats
        self.fatsz = f.fatsz
        self.nclus = (tot - f.reserved - f.nfats * f.fatsz) // f.spc
        if self.nclus > f.fatsz * 128 - 2:
            self.nclus = f.fatsz * 128 - 2
        self.maxc = self.nclus + 1
        self.root = f.root
        fi = f.read(f.part + f.fsinfo * 512, 512)
        self.fsi_free = struct.unpack_from('<I', fi, 488)[0]
        self.fat1 = f.read(f.fat0, f.fatsz * 512)
        self.fat2 = f.read(f.fat0 + f.fatsz * 512, f.fatsz * 512) if f.nfats > 1 else None
        self.vlabel = bpb[71:82].decode('latin-1')

    def fat(self, c):
        return struct.unpack_from('<I', self.fat1, 4 * c)[0] & 0x0FFFFFFF

    def sector(self, cl, s):
        f = self.fs
        return f.read(f.data0 + (cl - 2) * f.csize + s * 512, 512)

    def label(self):
        """the root's volume label entry (what CMDR-DOS lists and R-H writes)"""
        for _, e in self.fs.entries(self.root):
            if e[0] == 0:
                break
            if e[0] != 0xE5 and e[11] != 0x0F and e[11] & 0x08:
                return e[0:11].decode('latin-1').rstrip()
        return ''


def ui_num(v):
    return str(v)


def ui_size(v):
    def tenths(v, sh, unit):
        w = v >> sh
        d = ((v - (w << sh)) >> (sh - 4)) * 10 // 16
        return str(w) + ('.%d' % d if w < 100 else '') + unit
    if v < 1024:
        return '%d %s' % (v, 'byte' if v == 1 else 'bytes')
    if v < 0x100000:
        return tenths(v, 10, ' KB')
    if v < 0x40000000:
        return tenths(v, 20, ' MB')
    return tenths(v, 30, ' GB')


def join(a, b):
    if len(a) + len(b) + 1 > 63:
        return None
    return a + b if a.endswith('/') else a + '/' + b


def sum83(e):
    s = 0
    for b in e[:11]:
        s = (((s & 1) << 7) + (s >> 1) + b) & 0xFF
    return s


# ---------------------------------------------------------------- check.c again
def expect(path):
    """check.c's walk, line for line: (faults, summary numbers)"""
    k = Card(path)
    maxc = k.maxc
    marked = set()
    faults = []
    stack = []
    n = {'dirs': 0, 'files': 0}
    dirmax = 4096 // k.spc

    def chain(start, need, isdir, cpath):
        """the chain's good clusters (as chain_step and chain_end)"""
        show = cpath or '/'
        c, cnt = start, 0
        if c < 2 or c > maxc:
            if c or isdir or need:
                faults.append(show + (': its first cluster is past the end of the card: %d' % c if c
                                      else ': it has no cluster (0)'))
            return 0, False
        okc = True
        while True:
            if c in marked:
                faults.append(show + ': its chain crosses another chain (or itself) at cluster %d' % c)
                okc = False
                break
            marked.add(c)
            cnt += 1
            if (cnt > dirmax) if isdir else (cnt > need and not (need == 0 and cnt == 1)):
                if isdir:
                    faults.append(show + ": the folder's chain goes on past 2 MB (a loop?) at cluster %d" % c)
                else:
                    faults.append(cpath + ': its chain is longer than its size needs (%d cluster%s)'
                                  % (need, '' if need == 1 else 's'))
                okc = False
                break
            v = k.fat(c)
            if v >= EOC:
                break
            if v == BADC:
                faults.append(show + ': a bad cluster mark (or an unreadable FAT) after cluster %d' % c)
                okc = False
                break
            if v == 0:
                faults.append(show + ': its chain runs into a free cluster after cluster %d' % c)
                okc = False
                break
            if v < 2 or v > maxc:
                faults.append(show + ': its chain points past the end of the card: $%08X' % v)
                okc = False
                break
            c = v
        if okc and not isdir and cnt < need:
            faults.append(cpath + ': its chain has %d of the %d clusters its size needs' % (cnt, need))
        return cnt, okc

    def read_dir(first, nclus, dpath):
        lfn, lsum, lok = None, 0, False
        cl = first
        for ci in range(nclus):
            if ci:
                cl = k.fat(cl)
            for s in range(k.spc):
                sec = k.sector(cl, s)
                for i in range(16):
                    e = sec[32 * i:32 * i + 32]
                    if e[0] == 0:
                        return
                    if e[0] == 0xE5:
                        lok = False
                        continue
                    if e[11] == 0x0F:
                        seq = (e[0] & 0x1F) - 1
                        if e[0] & 0x40:
                            lfn, lsum, lok = [''] * 64, e[13], True
                        if not lok or seq > 4:
                            continue
                        for j, o in enumerate(LFN_OFFS):
                            ch = struct.unpack_from('<H', e, o)[0]
                            if ch in (0, 0xFFFF):
                                break
                            at = seq * 13 + j
                            if at < 63:
                                lfn[at] = chr(ch) if 32 <= ch < 128 else '?'
                        continue
                    if e[11] & 0x08 or (e[0] == 0x2E and e[1] in (0x20, 0x2E)):
                        lok = False
                        continue
                    if lok and lsum == sum83(e):
                        nm = ''
                        for ch in lfn:
                            if not ch:
                                break
                            nm += ch
                    else:
                        base = e[0:8].decode('latin-1').split(' ')[0]
                        ext = e[8:11].decode('latin-1').split(' ')[0]
                        nm = base + ('.' + ext if e[8] != 0x20 else '')
                    lok = False
                    clu = struct.unpack_from('<H', e, 20)[0] << 16 | struct.unpack_from('<H', e, 26)[0]
                    size = struct.unpack_from('<I', e, 28)[0]
                    p = join(dpath or '/', nm) or '(a long path)'
                    if e[11] & 0x10:
                        if clu < 2 or clu > maxc:
                            faults.append(p + (": the folder's first cluster is past the end of the card: %d" % clu
                                               if clu else ': the folder has no cluster (0)'))
                        else:
                            stack.append((clu, p[:59]))
                        continue
                    n['files'] += 1
                    if not clu and not size:
                        continue
                    csz = k.spc * 512
                    chain(clu, (size + csz - 1) // csz, False, p)

    # the root, then the stack
    cnt, _ = chain(k.root, 0, True, '')
    n['dirs'] += 1
    read_dir(k.root, cnt, '')
    while stack:
        clu, p = stack.pop()
        cnt, _ = chain(clu, 0, True, p)
        n['dirs'] += 1
        read_dir(clu, cnt, p)
    # the whole FAT
    free = lost = diff = 0
    for s in range(k.fatsz):
        a = k.fat1[512 * s:512 * s + 512]
        if k.fat2 is not None and a != k.fat2[512 * s:512 * s + 512]:
            diff += 1
        for i in range(128):
            c = s * 128 + i
            if c < 2:
                continue
            if c > maxc:
                break
            v = struct.unpack_from('<I', a, 4 * i)[0] & 0x0FFFFFFF
            if not v:
                free += 1
            elif v != BADC and c not in marked:
                lost += 1
    if diff:
        faults.append('%d sectors of the FAT differ from its second copy' % diff)
    if lost:
        faults.append('%d lost clusters: in use, in no file or folder (%s)' % (lost, ui_size(lost * k.spc * 512)))
    summary = '%d %d %d %d %d %d %d' % (n['dirs'], n['files'], len(faults), lost, free, diff, k.fsi_free)
    return faults, summary


# ---------------------------------------------------------------- the faults planted
def plant(path):
    f = vcard.Fat32(path)

    def first(p):
        _, e = f.find(p)
        return struct.unpack_from('<H', e, 20)[0] << 16 | struct.unpack_from('<H', e, 26)[0]

    def free_cluster(after):
        c = after
        while f.fat(c):
            c += 1
        return c

    def set1(c, v):                     # the first FAT only
        f.write(f.fat0 + 4 * c, struct.pack('<I', v))

    # SHORT.TXT (3 clusters): cut after its first (its two others lost)
    c = first('/DOCUMENTS/BAD/SHORT.TXT')
    f.set_fat(c, 0x0FFFFFFF)
    # CROSS.TXT (2 clusters): its first points into VICTIM.TXT's chain
    v = first('/DOCUMENTS/BAD/VICTIM.TXT')
    c = first('/DOCUMENTS/BAD/CROSS.TXT')
    f.set_fat(c, f.fat(v))
    # PAST.TXT (2 clusters): its first points past the card's end
    c = first('/DOCUMENTS/BAD/PAST.TXT')
    f.set_fat(c, f.ndata + 40)
    # LONG.TXT (100 bytes, 1 cluster): two more clusters chained on
    c = first('/DOCUMENTS/BAD/LONG.TXT')
    x = free_cluster(f.ndata // 2)
    y = free_cluster(x + 1)
    f.set_fat(c, x)
    f.set_fat(x, y)
    f.set_fat(y, 0x0FFFFFFF)
    # FREE.TXT (2 clusters): its first points to a free cluster
    c = first('/DOCUMENTS/BAD/FREE.TXT')
    f.set_fat(c, free_cluster(y + 10))
    # a sector of the second FAT changed (a free cluster's entry there)
    z = free_cluster(f.ndata - 300)
    f.write(f.fat0 + f.fatsz * f.bps + 4 * z, struct.pack('<I', 0x0FFFFFFF))
    print('planted: SHORT cut, CROSS into VICTIM, PAST past the end, LONG two clusters on, FREE into a '
          'free cluster, the second FAT at cluster %d' % z)


def card_line(path):
    k = Card(path)
    return '0 1 %d %d %d %d' % (k.part_sec, k.spc, k.nclus, k.fsi_free)


# ---------------------------------------------------------------- Space use
def space(where, path):
    """[(total bytes, files, name)] of the folders in path, largest first;
    the files in path itself: (bytes, files); everything"""
    out = []
    if os.path.isdir(where):
        base = os.path.join(where, path.strip('/'))
        own = [0, 0]
        for n in os.listdir(base):
            p = os.path.join(base, n)
            if os.path.isdir(p):
                t = cnt = 0
                for d, _, fs in os.walk(p):
                    for x in fs:
                        t += os.path.getsize(os.path.join(d, x))
                        cnt += 1
                out.append((t, cnt, n))
            else:
                own[0] += os.path.getsize(p)
                own[1] += 1
    else:
        fs = vcard.Fat32(where)
        pre = path.strip('/') + '/' if path.strip('/') else ''
        own = [0, 0]
        tops = {}
        for p, size in fs.walk():
            if not p.upper().startswith(pre.upper()):
                continue
            rest = p[len(pre):]
            if not rest:
                continue
            top, sep, _ = rest.partition('/')
            if size is None:
                if not sep or rest == top + '/':
                    tops.setdefault(top, [0, 0])
                continue
            if sep:
                t = tops.setdefault(top, [0, 0])
                t[0] += size
                t[1] += 1
            else:
                own[0] += size
                own[1] += 1
        out = [(v[0], v[1], k) for k, v in tops.items()]
    out.sort(key=lambda x: -x[0])
    return out, tuple(own)


# ---------------------------------------------------------------- the logs
def dtlines(console):
    t = open(console, 'rb').read().decode('latin-1').replace('\r', '\n')
    return re.findall(r'(?:DT|BOX) [^\n]*', t)


def space_blocks(lines):
    """each counted Space use: (its folder, rows, own, total line)"""
    out, cur = [], None
    for ln in lines:
        if ln.startswith('DT SPACE START '):
            cur = [ln[15:], [], None, None]
        elif cur and ln.startswith('DT SPACE TOTAL '):
            cur[3] = ln[15:]
            out.append(cur)
            cur = None
        elif cur and ln.startswith('DT SPACE STOPPED'):
            cur = None
        elif cur and ln.startswith('DT SPACE ') and ln.endswith(' (files here)'):
            a = ln[9:].split(' ')
            cur[2] = (int(a[0]), int(a[1]))
        elif cur and ln.startswith('DT SPACE '):
            a = ln[9:].split(' ', 2)
            cur[1].append((int(a[0]), int(a[1]), a[2]))
    return out


def check_space(lines, where, ignore=()):
    blocks = space_blocks(lines)
    if not blocks:
        fail('no Space use counted')
    for path, rows, own, _ in blocks:
        want, wown = space(where, path)
        got = [r for r in rows if r[2] not in ignore]
        want = [r for r in want if r[2] not in ignore]
        if sorted(got, key=lambda r: r[2]) != sorted(want, key=lambda r: r[2]):
            fail('Space use of %s: %s, the host computes %s' % (path, got, want))
        if path != '/' and own != wown:
            fail('Space use of %s: its own files %s, the host %s' % (path, own, wown))
    ok('Space use: %d counts, each folder\'s total equal to the host\'s (%s)' % (
        len(blocks), ', '.join('%s %d folders' % (b[0], len(b[1])) for b in blocks)))
    return blocks


def main():
    a = sys.argv[1:]
    if a[:1] == ['plant']:
        plant(a[1])
    elif a[:1] == ['card']:
        print(card_line(a[1]))
    elif a[:1] == ['expect']:
        faults, summary = expect(a[1])
        for f in faults:
            print(f)
        print('DONE ' + summary)
    elif a[:1] == ['space']:
        rows, own = space(a[1], a[2])
        for r in rows:
            print(r)
        print('own', own)
    elif a[:1] == ['log']:
        log(a[1], a[2], a[3], a[4] if len(a) > 4 else None)
    else:
        sys.exit(__doc__)


def log(session, console, where, before):
    lines = dtlines(console)
    if 'DT END' not in lines:
        fail('the session did not end ("DT END")')
    if session == 'host':
        if not any(x.startswith('DT CARD 1 0 ') and x.endswith(' Host folder') for x in lines):
            fail('the card: not the host folder')
        ok('the card: the host folder (no FAT)')
        blocks = check_space(lines, before or where, ignore=())
        paths = [b[0] for b in blocks]
        if paths[:3] != ['/', '/DOCUMENTS', '/']:
            fail('Down, Return and Backspace: the counts were %s' % paths)
        ok('Down and Return went into the largest folder (/DOCUMENTS), Backspace back to the top')
        if 'DT SPACE STOPPED Esc' not in lines:
            fail('Esc did not stop a count')
        ok('Esc stopped a count')
        i = lines.index('DT ASIDE') if 'DT ASIDE' in lines else -1
        if i < 0 or 'DT SPACE STOPPED put aside; the card may have changed' not in lines[i:]:
            fail('Alt+Tab: the count was not stopped')
        ok('Alt+Tab during a count: put aside, back from the test desktop, the count stopped and said so')
        if not any(x.startswith('BOX The host folder has no FAT:') for x in lines):
            fail('Check on the host folder: no box')
        ok('Check on the host folder: its box (no FAT)')
        want = ['DT TRASH KEPT', 'DT TRASH EMPTIED 3', 'DT TRASH ITEMS 0']
        got = [x for x in lines if x.startswith('DT TRASH KEPT') or x.startswith('DT TRASH EMPTIED')
               or x == 'DT TRASH ITEMS 0']
        if got[:3] != want:
            fail('the trash: %s' % got)
        ok('the trash: Cancel kept it, OK emptied it (2 items, 3 deletions: a file, a folder and its file)')
        left = sorted(x for x in lines if x.startswith('DT LEFT '))
        wl = sorted(['DT LEFT ASK /VERANDA/.SYSTEM|ASK.TMP', 'DT LEFT EDIT /DOCUMENTS|~VEDIT.TMP',
                     'DT LEFT FONT /VERANDA/FONTS|Gate Sans.tmp', 'DT LEFT VB /DOCUMENTS/Small|~VBASIC.TMP'])
        if left != wl:
            fail('leftovers: %s' % left)
        ok('leftovers: the four kinds found (Orphan.tmp, with no .cvt, and a lone ASK.TMP not)')
        dels = sorted(x for x in lines if x.startswith('DT DELETED '))
        if dels != ['DT DELETED ASK.TMP', 'DT DELETED ~VBASIC.TMP', 'DT DELETED ~VEDIT.TMP']:
            fail('deleted: %s' % dels)
        ok('each kind deleted after its OK; the Font Editor\'s kept after Cancel')
    elif session == 'sdcheck':
        faults, summary = expect(where)
        got = [x[9:] for x in lines if x.startswith('DT FAULT ')]
        if got != faults:
            fail('Check\'s faults:\n  %s\nthe host finds:\n  %s' % ('\n  '.join(got), '\n  '.join(faults)))
        done = [x[14:] for x in lines if x.startswith('DT CHECK DONE ')]
        if done != [summary]:
            fail('Check\'s summary %s, the host\'s %s' % (done, summary))
        for f in faults:
            print('      ' + f)
        ok('Check: %d faults, each equal to the host\'s own walk of the image; summary (folders files faults '
           'lost free fatdiff fsinfo) %s' % (len(faults), summary))
        j = [int(x.split()[-1]) for x in lines if x.startswith('DT CHECK JIFFIES ')]
        if j:
            ok('Check took %.1f s at 8 MHz (%d clusters, %d folders)' % (j[0] / 60, Card(where).nclus,
                                                                     int(summary.split()[0])))
        cl = [x for x in lines if x.startswith('DT CARD ')]
        want = card_line(where)
        if not cl or not cl[0][8:].startswith(want + ' '):
            fail('the card: %s, the host: %s' % (cl, want))
        ok('the card: partition sectors, cluster size, clusters and FSInfo\'s count as the host reads them (%s)'
           % want)
    elif session == 'sdmod':
        k = Card(where)
        # (R49's R-H writes the boot sector's label and marks the root's
        # label entry deleted: the DOS then lists the boot sector's)
        if k.vlabel.rstrip() != 'X16CARD' or k.label() not in ('', 'X16CARD'):
            fail('the card\'s name in the image: "%s" (the root\'s entry "%s")' % (k.vlabel, k.label()))
        if not any(x.startswith('DT RENAME 00,') for x in lines):
            fail('R-H: %s' % [x for x in lines if x.startswith('DT RENAME')])
        cl = [x for x in lines if x.startswith('DT CARD ')]
        if len(cl) < 2 or not cl[1].endswith(' X16CARD'):
            fail('the name read back: %s' % cl)
        ok('Rename: R-H answered 00, the boot sector\'s label in the image is X16CARD (the root\'s old label '
           'entry deleted), the DOS lists it so')
        check_space(lines, before or where, ignore=())
        if 'DT TRASH EMPTIED 3' not in lines:
            fail('the trash on the card: %s' % [x for x in lines if 'TRASH' in x])
        ok('the trash emptied on the card (3 deletions)')
        faults, summary = expect(where)
        done = [x[14:] for x in lines if x.startswith('DT CHECK DONE ')]
        if faults or not done or done[0].split()[2] != '0':
            fail('Check after the DOS\'s own writes: %s / %s' % (done, faults))
        if done[0].split()[:5] != summary.split()[:5]:
            fail('Check\'s summary %s, the host\'s %s' % (done, summary))
        ok('Check after the DOS\'s rename and deletions: no problems (as the host finds: %s)' % summary)
    else:
        fail('no such session ' + session)


if __name__ == '__main__':
    main()
