#!/usr/bin/env python3
"""Gate update (DECISIONS V130): the fixtures and the checks.

    check_update.py fixture <fx-dir> <shell.cvt>
        three packages of a small made-up Veranda (pkgA, pkgB1, pkgB2:
        their files, the manifests by tools/mkmanifest.py), the GitHub
        releases of A and B1 (tools/mkrelease.py, the real allowlist), and
        the card to start from (card0: A installed, with the user's files)
    check_update.py check <session> <fx-dir> <card> <log> <requests.log>
        the card and the logs after a session, against what it must be

(V198) Veranda Write's dictionaries: relD, a release as Write's
tools/mkdict.py makes it (DICT.LST, tag dict-1, the assets by their
names: EN.DIC, EN.DIC.txt, PL.DIC, PL.DIC.txt), served for
veranda-x16/veranda-write; the card has an older PL.DIC (a package made
before V198 had the dictionaries), which nothing but a chosen download
may change. A build's VERANDA/DICT holds SPELL.OVL (every build) and, in
B1, a stray EN.DIC: never in a release.

The user's files (in /DOCUMENTS, /VERANDA/.SYSTEM's settings, an
application of the user's own in /VERANDA/APPS, VERANDA/README.txt) are
checksummed in card0 and must be the same after every session.

MIT licence (see LICENSE)."""
import json
import os
import random
import re
import shutil
import subprocess
import sys
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.join(os.path.dirname(HERE), 'tools')
sys.path.insert(0, TOOLS)
import mkmanifest  # noqa: E402

BUILDS = {'A': ('a1a1a1a', '2026-11-01'), 'B1': ('b1b1b1b', '2026-11-10'), 'B2': ('b2b2b2b', '2026-11-20')}
USER = {
    'DOCUMENTS/Letter.txt': b'Dear Ada,\r\nthe card is mine.\r\n',
    'DOCUMENTS/VeraBASIC Examples/Dice.bas': b'10 REM my own dice, edited\r\n20 PRINT RND(6)\r\n',
    'DOCUMENTS/Chats/Claude/first.chat': b'U hello\nA hi\n',
    'VERANDA/.SYSTEM/GEMINI.CFG': b'web=1\r\n',
    'VERANDA/.SYSTEM/ASK.CFG': b'key=sk-not-real\r\n',
    'VERANDA/.SYSTEM/PREFS.CFG': b'paper=1\r\n',
    'VERANDA/.SYSTEM/NOTES.cvt': bytes(range(256)) * 4,
    'VERANDA/APPS/My Own.cvt': b'MINE' * 500,
    'VERANDA/README.txt': b'the README of the card as it came\r\n',
}


def rnd(seed, n):
    r = random.Random(seed)
    return bytes(r.getrandbits(8) for _ in range(n))


# (V198) an older PL.DIC (from a package before V198); the dictionaries'
# release, as Write's tools/mkdict.py makes it
USER['VERANDA/DICT/PL.DIC'] = rnd('plold', 48000)
DICTS = {'EN.DIC': rnd('en', 30000), 'EN.DIC.txt': b'SCOWL: its notice\n' * 20,
         'PL.DIC': rnd('pl', 50000), 'PL.DIC.txt': b'CC BY-SA 4.0, Morfologik: BSD\n' * 20}
DTAG = 'dict-1'


def files_of(build, shell):
    """{path: bytes} of a made-up package"""
    prg = rnd('prg', 6203)
    f = {
        'VERANDA/VERANDA.PRG': prg, 'VERANDA/AUTOBOOT.X16': prg,
        'VERANDA/VERANDA.SYS': rnd('sys', 20000), 'VERANDA/RBOOT': rnd('rboot', 394),
        'VERANDA/SHELL.cvt': shell,
        'VERANDA/Veranda Setup.cvt': rnd('setup', 3000),
        'VERANDA/APPS/Paint.cvt': rnd('paint', 12000),
        'VERANDA/APPS/Veranda Gemini.cvt': rnd('gemini', 40000),
        'VERANDA/APPS/About this X16.cvt': rnd('about', 8000),
        'VERANDA/APPS/Disk Tools.cvt': rnd('disk', 6000),
        'VERANDA/APPS/geoWrite.cvt': rnd('geowrite', 5000),        # (a port: never in a release)
        'VERANDA/FONTS/Gate Sans.cvt': rnd('font', 3000),
        'VERANDA/HELP/KEYWORDS.HLP': rnd('kw', 9000),
        'VERANDA/WALLPAPERS/Dusk.cvt': rnd('dusk', 5000),
        'VERANDA/DICT/SPELL.OVL': rnd('spell', 2200),                # (V198: Write's spelling code)
        'PC/update_server.py': open(os.path.join(TOOLS, 'update_server.py'), 'rb').read(),
        'DOCUMENTS/VeraBASIC Examples/Dice.bas': b'10 REM dice\r\n20 PRINT INT(RND(1)*6)+1\r\n',
    }
    if build == 'B1':
        f['VERANDA/DICT/EN.DIC'] = rnd('enstray', 3000)              # (V198: never in a release)
    if build in ('B1', 'B2'):
        f['VERANDA/APPS/Veranda Gemini.cvt'] = rnd('gemini2', 41000)
        f['VERANDA/APPS/Paint.cvt'] = rnd('paint2', 12000)          # (the same size: the CRC tells)
        f['VERANDA/HELP/KEYWORDS.HLP'] = rnd('kw2', 9100)
    if build == 'B2':
        prg = rnd('prg2', 6203)
        f['VERANDA/VERANDA.PRG'] = f['VERANDA/AUTOBOOT.X16'] = prg
        f['VERANDA/VERANDA.SYS'] = rnd('sys2', 20100)
        f['VERANDA/APPS/About this X16.cvt'] = rnd('about2', 8100)
        f['VERANDA/FONTS/Gate Sans.cvt'] = rnd('font2', 3000)
        f['VERANDA/APPS/Wikipedia.cvt'] = rnd('wiki', 700)          # new
        f['PC/web_proxy.py'] = b'# a new PC helper\n' * 40              # new, a new file in PC/
        f['DOCUMENTS/VeraBASIC Examples/Dice.bas'] = b'10 REM dice 2\r\n'   # (a doc-sample: never written)
        f['VERANDA/APPS/geoWrite.cvt'] = rnd('geowrite2', 5100)
    return f


# (V210) the timing session: build T, A with twelve applications more of
# the sizes of twelve of Veranda 1.0.4's (616 KB; 1.0.3 to 1.0.4 changed
# 47 files, 2,385 KB, some 51 KB a file, as these), their bytes made to
# deflate about as the real ones do (2:1)
TSIZES = (155956, 10656, 23680, 33932, 92456, 21889, 50950, 47902, 26895, 99568, 42060, 9990)
# (a short text: zlib's fixed codes, as for the release's small files)
TEXTRA = {'VERANDA/HELP/ERRORS.HLP': b'?SYNTAX ERROR: the line is not BASIC.\r\n?OUT OF DATA: READ past the last DATA.\r\n'}
TNAMES = ('Veranda Write', 'Note Pad', 'Calendar', 'Archive', 'Bird Watch', 'Calculator', 'MIDI Player', 'Colour Paint',
          'Preferences', 'VeraBASIC Run', 'Term', 'TextMgr')       # (release.allow's)


def code(seed, n):
    """n bytes that deflate about 2:1, as Veranda's programs do: words of a
    small vocabulary, bytes at random between, now and then a run of
    zeros (a buffer's room in a .cvt: matches of 258 at a distance of 1)"""
    r = random.Random(seed)
    voc = [bytes(r.getrandbits(8) for _ in range(r.randint(2, 7))) for _ in range(400)]
    w = [1.0 / (i + 1) for i in range(len(voc))]
    out = bytearray()
    while len(out) < n:
        x = r.random()
        if x < 0.0007:
            out += bytes(r.randint(100, 1500))
        elif x < 0.35:
            out += bytes(r.getrandbits(8) for _ in range(r.randint(1, 3)))
        else:
            out += r.choices(voc, w)[0]
    return bytes(out[:n])


def files_t(shell):
    f = files_of('A', shell)
    for i, n in enumerate(TSIZES):
        f['VERANDA/APPS/%s.cvt' % TNAMES[i]] = code('t%d' % i, n)
    f.update(TEXTRA)
    return f


def blocks(rel):
    """(V210) the kinds of deflate blocks the release's pack starts its files
    with: 0 stored, 1 fixed, 2 dynamic"""
    head, ents = mkmanifest.parse(open(os.path.join(rel, 'UPDATE.LST'), encoding='latin-1').read())
    p = open(os.path.join(rel, head['pack'][0]), 'rb').read()
    return {(p[e['z'][0]] >> 1) & 3 for e in ents if 'z' in e}


def write_tree(root, files):
    for p, b in files.items():
        full = os.path.join(root, *p.split('/'))
        os.makedirs(os.path.dirname(full), exist_ok=True)
        with open(full, 'wb') as fh:
            fh.write(b)


def snapshot(root):
    out = {}
    for top in ('VERANDA', 'PC', 'DOCUMENTS'):
        for r, _, fs in os.walk(os.path.join(root, top)):
            for f in fs:
                full = os.path.join(r, f)
                rel = os.path.relpath(full, root).replace(os.sep, '/')
                b = open(full, 'rb').read()
                out[rel] = (len(b), zlib.crc32(b) & 0xFFFFFFFF)
    return out


def fixture(fx, shell_path):
    shell = open(shell_path, 'rb').read()
    if os.path.exists(fx):
        shutil.rmtree(fx)
    os.makedirs(fx)
    for name, (bid, date) in BUILDS.items():
        pkg = os.path.join(fx, 'pkg' + name)
        write_tree(pkg, files_of(name, shell))
        subprocess.check_call([sys.executable, '-I', '-B', os.path.join(TOOLS, 'mkmanifest.py'), pkg, '--build', bid,
                               '--date', date] + (['--version', '1.0.1'] if name == 'B2' else []) +
                              ['--note', 'Build %s of the gate\'s made-up Veranda: a few files changed, '
                               'the rest the same; nothing of the user\'s touched.' % name],
                              stdout=subprocess.DEVNULL)
        # (the releases as they are published, V140: A with the tag
        # mkrelease gives by itself, B1 with release.yml's v<version>, At
        # the Test channel's pre-release, tagged "test")
        rels = {'A': [('A', []), ('At', ['--channel', 'test'])], 'B1': [('B1', ['--tag', 'v1.0.1']), ('B1p', ['--tag', 'v1.0.1', '--no-pack'])]}
        for rel, extra in rels.get(name, []):
            out = subprocess.run([sys.executable, '-I', '-B', os.path.join(TOOLS, 'mkrelease.py'), pkg,
                                  os.path.join(fx, 'rel' + rel), '--repo', 'veranda-x16/veranda'] + extra,
                                 capture_output=True, text=True)
            if out.returncode:
                sys.exit('mkrelease %s: %s' % (rel, out.stderr))
            if 'geoWrite' in open(os.path.join(fx, 'rel' + rel, 'UPDATE.LST')).read():
                sys.exit('FAIL  geoWrite in release %s' % rel)
            if '.DIC' in open(os.path.join(fx, 'rel' + rel, 'UPDATE.LST')).read() or \
                    'VERANDA/DICT/SPELL.OVL' not in open(os.path.join(fx, 'rel' + rel, 'UPDATE.LST')).read():
                sys.exit('FAIL  release %s: a dictionary in it, or no SPELL.OVL (V198)' % rel)
    # (V210) the timing session's build T and its release
    pkg = os.path.join(fx, 'pkgT')
    write_tree(pkg, files_t(shell))
    subprocess.check_call([sys.executable, '-I', '-B', os.path.join(TOOLS, 'mkmanifest.py'), pkg, '--build', 'tttttt1',
                           '--date', '2026-11-25', '--note', 'The timing session\'s build: twelve programs more.'],
                          stdout=subprocess.DEVNULL)
    for rel, extra in (('relT', []), ('relTp', ['--no-pack'])):     # (relTp: a release as before V210)
        out = subprocess.run([sys.executable, '-I', '-B', os.path.join(TOOLS, 'mkrelease.py'), pkg,
                              os.path.join(fx, rel), '--repo', 'veranda-x16/veranda', '--tag', 'v1.0.9'] + extra,
                             capture_output=True, text=True)
        if out.returncode:
            sys.exit('mkrelease %s: %s' % (rel, out.stderr))
    # (V210) every kind of deflate block in the packs the sessions inflate
    kinds = blocks(os.path.join(fx, 'relT')) | blocks(os.path.join(fx, 'relB1'))
    if kinds != {0, 1, 2}:
        sys.exit('FAIL  the packs start their files with blocks %s, not stored, fixed and dynamic' % sorted(kinds))
    rd = os.path.join(fx, 'relD')
    os.makedirs(rd)
    ents = []
    for n, b in DICTS.items():
        open(os.path.join(rd, n), 'wb').write(b)
        ents.append({'size': len(b), 'crc': zlib.crc32(b) & 0xFFFFFFFF, 'kind': 'app', 'min': '-', 'asset': n,
                     'path': 'VERANDA/DICT/' + n})
    open(os.path.join(rd, 'DICT.LST'), 'w').write(mkmanifest.render(
        'dict1', '2026-11-25', ents, ['Veranda Write\'s dictionaries: English and Polish.'], DTAG, '1.0'))
    card = os.path.join(fx, 'card0')
    a = files_of('A', shell)
    write_tree(card, {p: b for p, b in a.items() if not p.startswith('DOCUMENTS/') and 'geoWrite' not in p})
    write_tree(card, USER)
    shutil.copy(os.path.join(fx, 'relA', 'UPDATE.LST'), os.path.join(card, 'VERANDA', 'UPDATE.LST'))
    json.dump(snapshot(card), open(os.path.join(fx, 'card0.json'), 'w'), indent=0)
    print('ok    fixtures: packages A, B1, B2 (%d, %d, %d files), releases A and B1 (no geoWrite; of VERANDA/DICT only '
          'SPELL.OVL, B1\'s EN.DIC left out), the dictionaries\' release dict-1 (4 files), the card %s'
          % tuple([len(files_of(n, shell)) for n in ('A', 'B1', 'B2')] + [card]))


# ------------------------------------------------------------------ checks

def fail(msg):
    print('FAIL  ' + msg)
    sys.exit(1)


def expected(fx, build, source, rel=None):
    """the card as it must be with build installed (paths of VERANDA/, PC/, DOCUMENTS/); rel: the
    release's folder when not rel<build>"""
    base = json.load(open(os.path.join(fx, 'card0.json')))
    exp = {p: tuple(v) for p, v in base.items()}
    if build == 'A':
        return exp
    pkg = os.path.join(fx, 'pkg' + build)
    man = os.path.join(fx, rel or 'rel' + build, 'UPDATE.LST') if source == 'github' else os.path.join(pkg, 'VERANDA', 'UPDATE.LST')
    _, ents = mkmanifest.parse(open(man, encoding='latin-1').read())
    for e in ents:
        if e['kind'] == 'doc-sample':
            continue
        exp[e['path']] = (e['size'], e['crc'])
    b = open(man, 'rb').read()
    exp['VERANDA/UPDATE.LST'] = (len(b), zlib.crc32(b) & 0xFFFFFFFF)
    return exp


def expected_dict(fx, names):
    """(V198) the card at A with these dictionaries' files of relD"""
    exp = expected(fx, 'A', 'github')
    for n in names:
        b = DICTS[n]
        exp['VERANDA/DICT/' + n] = (len(b), zlib.crc32(b) & 0xFFFFFFFF)
    return exp


def dict_reqs(reqs, session):
    """(V198) the dictionaries' list asked of their release, never of Veranda's"""
    r = [x for x in reqs if x['host'] == 'github']
    if not r or r[0]['path'] != '/veranda-x16/veranda-write/releases/download/%s/DICT.LST' % DTAG:
        fail('%s: the dictionaries\' list not asked of veranda-write\'s %s: %s' % (session, DTAG, r[:1]))
    if any('/latest/' in x['path'] or x['path'].startswith('/veranda-x16/veranda/') for x in r):
        fail('%s: a request to Veranda\'s releases: %s' % (session, r))
    return r


def compare(card, exp, what, ignore=('VERANDA/.SYSTEM/UPD/', 'VERANDA/.SYSTEM/OLD/', 'VERANDA/.SYSTEM/UPDATE.CFG')):
    got = snapshot(card)
    g = {p: v for p, v in got.items() if not p.startswith(ignore)}
    e = {p: v for p, v in exp.items() if not p.startswith(ignore)}
    if g != e:
        diff = sorted(set(g) ^ set(e)) + sorted(p for p in set(g) & set(e) if g[p] != e[p])
        fail('%s: the card is not as it must be: %s' % (what, ', '.join(diff[:8])))
    return got


def user_ok(card, fx):
    base = json.load(open(os.path.join(fx, 'card0.json')))
    got = snapshot(card)
    for p in USER:
        if tuple(base[p]) != got.get(p):
            fail('the user\'s %s changed' % p)


def lines(log, pfx):
    return [l for l in log if l.startswith(pfx)]


def need(log, s, what):
    if not any(s in l for l in log):
        fail('%s: no "%s" in the log' % (what, s))


def num(log, key):
    v = lines(log, 'UP N %s ' % key)
    return int(v[-1].split()[-1]) if v else None


def check(session, fx, card, logf, reqf):
    log = []
    for l in open(logf, encoding='latin-1'):         # (the console's other output may run into a line)
        m = re.search(r'(UP [A-Z+]|BOX2? )', l)
        if m:
            log.append(l[m.start():].rstrip('\n'))
    reqs = [json.loads(l) for l in open(reqf)] if os.path.exists(reqf) else []
    need(log, 'UP END', session)
    for r in reqs:
        if r.get('bad'):
            fail('%s: a request was not as it must be: %s' % (session, r['bad']))
    user_ok(card, fx)
    A = BUILDS['A'][0]
    if session == 'uptodate':
        need(log, 'UP UPTODATE', session)
        if num(log, 'CHANGED') or num(log, 'NEW'):
            fail('uptodate: changes found')
        compare(card, expected(fx, 'A', 'github'), session)
        r = [x for x in reqs if x['host'] == 'github']
        a = [x for x in reqs if x['host'] == 'assets']
        tag = re.search(r'^tag (\S+)', open(os.path.join(fx, 'relA', 'UPDATE.LST')).read(), re.M).group(1)
        if len(r) < 2 or not r[0]['path'].endswith('/releases/latest/download/UPDATE.LST') or \
                r[0]['status'] != 302 or r[1]['path'] != '/veranda-x16/veranda/releases/download/%s/UPDATE.LST' % tag:
            fail('uptodate: latest/download did not go on to the tag\'s download (%s): %s' % (tag, r[:2]))
        r = r[1:]
        if r[0]['status'] != 302 or r[0].get('location_len', 0) < 900 or not a or a[0]['status'] != 200:
            fail('uptodate: the manifest did not come through the 302 and the long address: %s' % reqs)
        if r[0].get('hosthdr') != '127.0.0.1:%s' % r[0].get('hosthdr', ':').split(':')[-1] or \
                not str(a[0].get('hosthdr', '')).startswith('localhost:'):
            fail('uptodate: the Host headers %r %r' % (r[0].get('hosthdr'), a[0].get('hosthdr')))
        print('ok    up to date: the manifest through GitHub\'s two 302s (latest to the tag %s, then the other host: '
              'Location %d bytes, %s), every file compared (%d, %d skipped: doc-sample), "Up to date"; the card unchanged'
              % (tag, r[0]['location_len'], a[0]['how'][0], num(log, 'ENTS'), num(log, 'SKIP')))
    elif session == 'chan':
        need(log, 'UP UPTODATE', session)
        compare(card, expected(fx, 'A', 'github'), session)
        r = [x for x in reqs if x['host'] == 'github']
        if not r or not r[0]['path'].endswith('/releases/download/test/UPDATE.LST') or \
                any('/latest/' in x['path'] for x in r):
            fail('chan: the Test channel did not ask the release "test": %s' % r)
        print('ok    the Test channel (channel=test): the list from releases/download/test/UPDATE.LST, never '
              '.../latest/; "Up to date", the card unchanged')
    elif session == 'missing':
        if num(log, 'CHANGED') != 3 or num(log, 'NEW') != 0:
            fail('missing: not 3 changed files (%s, %s)' % (num(log, 'CHANGED'), num(log, 'NEW')))
        need(log, 'the release does not have it', session)
        need(log, 'BOX2 Refused: nothing on the card was changed.', session)
        compare(card, expected(fx, 'A', 'github'), session)
        if [x for x in reqs if x.get('status') == 206]:
            fail('missing: a Range asked of a release without a pack')
        print('ok    3 changed files found (Paint.cvt of the same size: its CRC); a release (V210: one without a pack, as '
              'before V210) missing one (GitHub\'s 404): refused, the card unchanged')
    elif session == 'crc':
        need(log, 'UP REFUSED VERANDA/APPS/Paint.cvt', session)
        need(log, 'failed its CRC-32 check', session)
        need(log, 'UP NOT FROM THE PACK VERANDA/APPS/Paint.cvt', session)
        compare(card, expected(fx, 'A', 'github'), session)
        print('ok    a CRC mismatch (a byte changed on the way, in the pack and in the file\'s own asset): the pack\'s '
              'part not taken, the file\'s own then refused, the card unchanged')
    elif session == 'drop':
        need(log, 'connection dropped', session)
        compare(card, expected(fx, 'A', 'github'), session)
        dropped = [x for x in reqs if 'dropped' in x.get('how', [])]
        if not dropped:
            fail('drop: the server did not drop a connection')
        ver = [l.split(' ', 2)[2] for l in lines(log, 'UP VERIFIED ')]
        upd = os.path.join(card, 'VERANDA', '.SYSTEM', 'UPD')
        kept = sorted(os.listdir(upd)) if os.path.isdir(upd) else []
        if 'DL.TMP' in kept:
            fail('drop: the cut-short file stayed (DL.TMP)')
        assets = [f for f in kept if f.endswith('.bin')]
        if not assets:
            fail('drop: nothing verified was kept in .SYSTEM/UPD')
        print('ok    a connection dropped half way through Veranda Gemini.cvt (%s, %s): the card unchanged, the '
              'cut-short file gone; kept in .SYSTEM/UPD for the next try: %s%s' % (
                  dropped[0]['name'], dropped[0]['how'][0], ', '.join(assets),
                  ' (verified in this session: %s)' % ', '.join(ver) if ver else ' (verified by an earlier try)'))
    elif session == 'resume':
        ready = num(log, 'READY') if lines(log, 'UP N READY ') else 0
        r0 = [l for l in log if l.startswith('UP N READY ')]
        first_ready = int(r0[0].split()[-1]) if r0 else 0
        if first_ready < 1:
            fail('resume: nothing fetched before was kept (READY %s)' % ready)
        need(log, 'UP ASIDE', session)
        need(log, 'UP BACK', session)
        need(log, 'UP DONE ' + BUILDS['B1'][0], session)
        need(log, 'UP NO RESTART', session)
        got = compare(card, expected(fx, 'B1', 'github'), session)
        # (V210: from the pack, each file's part of it: its seg)
        names = [x.get('seg') or x['name'] for x in reqs
                 if x['host'] == 'assets' and x.get('status') in (200, 206) and x.get('name') != 'UPDATE.LST']
        packed = [x for x in reqs if x['host'] == 'assets' and x.get('status') == 206]
        if not packed or any(x.get('status') == 200 and x.get('name') != 'UPDATE.LST' for x in reqs if x['host'] == 'assets'):
            fail('resume: the files did not all come from the pack (V210): %s' % [x.get('name') for x in reqs])
        expired = [x for x in reqs if x['host'] == 'assets' and x.get('status') == 403]
        if not expired:
            fail('resume: the pack\'s address never expired (fake.json\'s expire 1)')
        need(log, 'UP NOT FROM THE PACK', session)
        if not [x for x in reqs if x.get('closed_kept')]:
            fail('resume: no kept connection was closed by the server (fake.json\'s keepmax 1)')
        if len(names) != len(set(names)) + 1:
            fail('resume: assets fetched %s (each once, the one put aside twice)' % names)
        if len(set(names)) != 3 - first_ready:
            fail('resume: %d fetched, %d were ready already' % (len(set(names)), first_ready))
        old = os.path.join(card, 'VERANDA', '.SYSTEM', 'OLD', A)
        base = json.load(open(os.path.join(fx, 'card0.json')))
        for p in ('VERANDA/APPS/Paint.cvt', 'VERANDA/APPS/Veranda Gemini.cvt', 'VERANDA/HELP/KEYWORDS.HLP', 'VERANDA/UPDATE.LST'):
            b = open(os.path.join(old, p.rsplit('/', 1)[1]), 'rb').read()
            if (len(b), zlib.crc32(b) & 0xFFFFFFFF) != tuple(base[p]):
                fail('resume: OLD/%s/%s is not the old one' % (A, p))
        if open(os.path.join(card, 'VERANDA', '.SYSTEM', 'OLD', 'LAST.UPD')).read().strip() != A:
            fail('resume: LAST.UPD')
        if os.path.isdir(os.path.join(card, 'VERANDA', '.SYSTEM', 'UPD')):
            fail('resume: .SYSTEM/UPD left behind')
        print('ok    resumed: %d file(s) kept from the dropped try not fetched again, %d fetched (one put aside with '
              'Alt+Tab half way and fetched again), the card at build %s, the old versions in .SYSTEM/OLD/%s, no restart '
              '(no system file changed); (V210) each from the release\'s pack (%d Ranges, 206), its address asked '
              'again after each of %d refusals (403: expired), a connection kept alive and closed by the server made '
              'again' % (first_ready, len(set(names)), BUILDS['B1'][0], A, len(packed), len(expired)))
        return got
    elif session in ('undo', 'undo2'):
        need(log, 'UP UNDONE ' + A, session)
        compare(card, expected(fx, 'A', 'github'), session)
        if os.path.exists(os.path.join(card, 'VERANDA', '.SYSTEM', 'OLD', A)):
            fail('%s: OLD/%s left behind' % (session, A))
        if os.path.exists(os.path.join(card, 'VERANDA', '.SYSTEM', 'OLD', 'LAST.UPD')):
            fail('%s: LAST.UPD left behind' % session)
        if session == 'undo2':
            need(log, 'UP RESTART', session)
        else:
            need(log, 'UP NO RESTART', session)
        print('ok    undo: the card back to build %s byte for byte (its manifest too), the backup removed%s'
              % (A, '; Restart to finish (system files)' if session == 'undo2' else ''))
    elif session == 'lan':
        need(log, 'UP DONE ' + BUILDS['B2'][0], session)
        need(log, 'UP RESTART', session)
        compare(card, expected(fx, 'B2', 'pc'), session)
        sw = [l for l in log if l.startswith('UP SWAP ')]
        kinds = ['SYSTEM' in l for l in sw if 'UPDATE.LST' not in l]
        if not any(kinds) or kinds != sorted(kinds):
            fail('lan: the system files were not swapped last: %s' % sw)
        if 'UPDATE.LST' not in sw[-1]:
            fail('lan: the manifest was not put in place last: %s' % sw[-1])
        nsys = sum(kinds)
        print('ok    the PC source (PC/update_server.py on localhost: the full package, geoWrite.cvt too): %d changed, '
              '%d new (a new file in PC/), the doc-sample not written; %d files swapped, the %d system files last, '
              'the manifest after them; Restart to finish' % (num(log, 'CHANGED'), num(log, 'NEW'), len(sw), nsys))
    elif session == 'dcrc':
        need(log, 'UP REQUEST dict', session)
        dict_reqs(reqs, session)
        need(log, 'UP REFUSED VERANDA/DICT/EN.DIC', session)
        compare(card, expected(fx, 'A', 'github'), session)
        if os.path.exists(os.path.join(card, 'VERANDA', '.SYSTEM', 'UPDATE.REQ')):
            fail('dcrc: UPDATE.REQ left behind')
        print('ok    dictionaries asked for (UPDATE.REQ, read and deleted): the list of veranda-write\'s %s, never '
              'Veranda\'s; EN.DIC with a byte changed on the way: refused, the card unchanged' % DTAG)
    elif session == 'dspace':
        need(log, 'UP NOROOM ', session)
        dict_reqs(reqs, session)
        if [x for x in reqs if x['host'] == 'assets' and x.get('name') != 'DICT.LST']:
            fail('dspace: an asset was fetched')
        compare(card, expected(fx, 'A', 'github'), session)
        print('ok    the card with 100 KB free: "%s", nothing fetched, the card unchanged'
              % [l for l in log if l.startswith('UP NOROOM ')][0][10:])
    elif session in ('dict', 'handoff'):
        need(log, 'BOX Get the English dictionary', session)
        need(log, 'BOX Get the Polish dictionary', session)
        need(log, 'UP DONE ' + DTAG, session)
        dict_reqs(reqs, session)
        got = [x['name'] for x in reqs if x['host'] == 'assets' and x.get('name') != 'DICT.LST']
        if sorted(got) != ['EN.DIC', 'EN.DIC.txt']:
            fail('%s: fetched %s, not English\'s two' % (session, got))
        compare(card, expected_dict(fx, ['EN.DIC', 'EN.DIC.txt']), session)
        man = open(os.path.join(card, 'VERANDA', 'UPDATE.LST'), 'rb').read()
        if man != open(os.path.join(fx, 'relA', 'UPDATE.LST'), 'rb').read():
            fail('%s: VERANDA/UPDATE.LST changed' % session)
        undo = open(os.path.join(card, 'VERANDA', '.SYSTEM', 'OLD', DTAG, 'UNDO.LST')).read()
        if 'N VERANDA/DICT/EN.DIC\n' not in undo or 'UPDATE.LST' in undo or 'PL.DIC' in undo:
            fail('%s: OLD/%s/UNDO.LST: %r' % (session, DTAG, undo))
        if open(os.path.join(card, 'VERANDA', '.SYSTEM', 'OLD', 'LAST.UPD')).read().strip() != DTAG:
            fail('%s: LAST.UPD' % session)
        if session == 'handoff':
            for l in ('STANDIN ASIDE', 'UP REQUEST dict', 'UP BACK TO Veranda Write', 'STANDIN BACK'):
                if not any(l in x for x in open(logf, encoding='latin-1')):
                    fail('handoff: no "%s" in the log' % l)
            for f in ('START.REQ', 'UPDATE.REQ'):
                if os.path.exists(os.path.join(card, 'VERANDA', '.SYSTEM', f)):
                    fail('handoff: %s left behind' % f)
            print('ok    hand-off: the desktop (the real shell) started a stand-in as Veranda Write from a START.REQ; it '
                  'wrote START.REQ and UPDATE.REQ and put itself aside; the desktop started Veranda Update from '
                  'START.REQ, which checked the dictionaries, fetched English, and its Quit brought Veranda Write '
                  'back; both requests deleted')
        else:
            print('ok    dictionaries: English chosen, Polish not (its older PL.DIC left as it was): EN.DIC and its licence '
                  'fetched, their CRC-32 checked, put in /VERANDA/DICT; Veranda\'s build (UPDATE.LST) unchanged; the '
                  'backup OLD/%s apart from the builds\'' % DTAG)
    elif session == 'dundo':
        need(log, 'UP UNDONE ' + DTAG, session)
        need(log, 'BOX Undo the dictionaries fetched last?', session)
        compare(card, expected(fx, 'A', 'github'), session)
        if os.path.exists(os.path.join(card, 'VERANDA', '.SYSTEM', 'OLD', DTAG)):
            fail('dundo: OLD/%s left behind' % DTAG)
        print('ok    undo: the dictionaries fetched removed, the card as it was (the older PL.DIC kept)')
    elif session in ('timing', 'timing0'):
        need(log, 'UP DONE tttttt1', session)
        if (session == 'timing') != bool([x for x in reqs if x.get('status') == 206]):
            fail('%s: the pack %s' % (session, 'not used' if session == 'timing' else 'asked of a release without one'))
        compare(card, expected(fx, 'T', 'github', 'relT' if session == 'timing' else 'relTp'), session)
        t = {k: num_t(log, k) for k in ('TIME', 'TSETUP', 'TBODY', 'TPULLS', 'TPACKETS', 'TEMPTIES', 'TRETRIES')}
        nb = sum(TSIZES) + sum(len(v) for v in TEXTRA.values())
        wire = sum(x.get('sent', 0) for x in reqs)
        print('ok    %s: %d files, %d bytes (%d on the line, the headers too) in %.1f s of the emulated X16 '
              '(%.2f KB/s of files): %.1f s from the requests to the first body bytes (%.2f s a file), %.1f s of '
              'bodies; %d XONs, %d packets (%.1f ms a packet), %d empty, %d XONs again'
              % ('timing, from the pack' if session == 'timing' else 'timing0, a release without a pack',
                 len(TSIZES) + len(TEXTRA), nb, wire, t['TIME'] / 60, nb / 1024 / (t['TIME'] / 60), t['TSETUP'] / 60,
                 t['TSETUP'] / 60 / len(TSIZES), t['TBODY'] / 60, t['TPULLS'], t['TPACKETS'],
                 t['TIME'] / 60 * 1000 / max(1, t['TPACKETS']), t['TEMPTIES'], t['TRETRIES']))
        if t['TRETRIES']:
            fail('timing: XONs sent again (an XON lost)')
        ranges = [x for x in reqs if x.get('status') == 206]
        conns = [x for x in ranges if x.get('conn_req') == 1]
        if ranges:
            print('      (the pack: %d Ranges on %d connections to the asset host)' % (len(ranges), len(conns)))
    else:
        fail('no session %s' % session)


def num_t(log, key):
    v = lines(log, 'UP %s ' % key)
    if not v:
        fail('timing: no "UP %s" in the log' % key)
    return int(v[-1].split()[-1])


def main():
    if sys.argv[1] == 'fixture':
        fixture(sys.argv[2], sys.argv[3])
    elif sys.argv[1] == 'check':
        check(*sys.argv[2:7])
    else:
        sys.exit(__doc__)


if __name__ == '__main__':
    main()
