#!/usr/bin/env python3
"""Gate update's host tests (DECISIONS V130): the release's allowlist
(tools/release.allow, tools/mkrelease.py), the manifest
(tools/mkmanifest.py) and the PC's update server (tools/update_server.py).
No network: the server listens on 127.0.0.1 only.

    test_mkrelease.py <work-dir>

The guarantee checked: no geoWrite or TopDesk file can ever
enter a release, whatever it is called, whatever the allowlist says. Each
case below builds a package and runs mkrelease; a port that gets through
fails the test.

MIT licence (see LICENSE)."""
import http.client
import os
import shutil
import subprocess
import sys
import threading
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.join(os.path.dirname(HERE), 'tools')
sys.path.insert(0, TOOLS)
import mkmanifest  # noqa: E402
import mkrelease  # noqa: E402
import update_server  # noqa: E402

W = sys.argv[1]
SIG = b'PRG formatted GEOS file V1.0'


def fail(m):
    print('FAIL  ' + m)
    sys.exit(1)


def cvt(cls, author='Veranda', parent=b''):
    """a CVT file's first 508 bytes with this class, author and parent class"""
    d = bytearray(600)
    d[30:30 + len(SIG)] = SIG
    info = bytearray(256)
    c = cls.encode('latin-1').ljust(12)[:12] + b'V1.0'
    info[77:77 + len(c)] = c
    a = author.encode('latin-1')[:19]
    info[97:97 + len(a)] = a
    info[117:117 + len(parent)] = parent
    d[254:508] = info[2:256]
    return bytes(d)


def package(root, extra):
    if os.path.exists(root):
        shutil.rmtree(root)
    base = {
        'VERANDA/VERANDA.PRG': b'prg' * 100, 'VERANDA/AUTOBOOT.X16': b'prg' * 100,
        'VERANDA/VERANDA.SYS': b'sys' * 300, 'VERANDA/RBOOT': b'rb', 'VERANDA/SHELL.cvt': cvt('Shell'),
        'VERANDA/APPS/Paint.cvt': cvt('VerandaPaint'), 'VERANDA/APPS/Veranda Calc.cvt': cvt('VerandaCalc'),
        'VERANDA/APPS/Veranda Write.cvt': cvt('CmdrWrite'),
        'VERANDA/APPS/Colour Paint.cvt': cvt('ColourPaint'),     # (V173: next to Paint)
        'VERANDA/README.txt': b'geoWrite, TopDesk and geoChess are ports for personal use: do not share this folder.\n',
        'PC/update_server.py': b'# server\n', 'DOCUMENTS/VeraBASIC Examples/Dice.bas': b'10 PRINT\n',
        'TILEHW/TILEHW.PRG': b'hw',
    }
    base.update(extra)
    for p, b in base.items():
        f = os.path.join(root, *p.split('/'))
        os.makedirs(os.path.dirname(f), exist_ok=True)
        open(f, 'wb').write(b)
    subprocess.check_call([sys.executable, '-I', '-B', os.path.join(TOOLS, 'mkmanifest.py'), root, '--build',
                           'abc1234', '--date', '2026-11-21', '--note', 'a test'], stdout=subprocess.DEVNULL,
                          stderr=subprocess.DEVNULL)


def release(pkg, out, allow=mkrelease.DEFAULT_ALLOW):
    if os.path.exists(out):
        shutil.rmtree(out)
    return mkrelease.build(pkg, out, allow=allow, log=lambda m: None)


def no_port(out):
    """every file of the folder checked: none of a port's, by name or by content"""
    text = open(os.path.join(out, 'UPDATE.LST')).read().lower()
    for n in ('geowrite', 'topdesk', 'tony requist', 'geos-user-club'):
        if n in text:
            fail('a port in the release\'s manifest: %s' % n)
    for f in os.listdir(out):
        if f == 'NOTES.md':
            continue
        d = open(os.path.join(out, f), 'rb').read()
        c = mkrelease.cvt_fields(d)
        if c and any(x.startswith(('geowrite', 'topdesk')) for x in c[:2]):
            fail('a port\'s CVT in the release: %s %s' % (f, c))
        for author in ('tony requist', 'geos-user-club'):
            if c and c[2].startswith(author):
                fail('a port\'s author in the release: %s' % f)


n = 0
# 1. the ports as the package has them: left out
P = os.path.join(W, 'pkg')
ports = {'VERANDA/APPS/geoWrite.cvt': cvt('geoWrite', 'Tony Requist'),
         'VERANDA/APPS/TopDesk.cvt': cvt('TopDesk', 'GEOS-USER-CLUB'),
         'VERANDA/APPS/geoChess.cvt': cvt('GeoChess', 'Scott Hutter'),
         'DOCUMENTS/Letter.geoWrite': b'a document', 'VERANDA/APPS/MOD Player.cvt': cvt('ModPlayer'),
         'VERANDA/APPS/Solitaire.cvt': cvt('Solitaire')}
# (V162) the wallpapers: Dusk and the three drawn as tiles shipped; the
# Meadow (the earlier packages') no longer, should a package still hold it
walls = ('Dusk', 'Still Water', 'Low Hills', 'Sunroom Tiles')
ports.update({'VERANDA/WALLPAPERS/%s.cvt' % w: cvt('Wallpaper') for w in walls + ('Meadow',)})
package(P, ports)
text, cmd = release(P, os.path.join(W, 'rel'))
no_port(os.path.join(W, 'rel'))
_, ents = mkmanifest.parse(text)
paths = {e['path'] for e in ents}
for p in ('VERANDA/README.txt', 'TILEHW/TILEHW.PRG', 'VERANDA/WALLPAPERS/Meadow.cvt'):
    if p in paths:
        fail('%s is in the release (not in the allowlist)' % p)
for p in ('VERANDA/VERANDA.SYS', 'VERANDA/APPS/Veranda Calc.cvt', 'VERANDA/APPS/Veranda Write.cvt', 'PC/update_server.py',
          'VERANDA/APPS/MOD Player.cvt', 'VERANDA/APPS/Solitaire.cvt', 'VERANDA/APPS/geoChess.cvt',
          'VERANDA/APPS/Colour Paint.cvt') \
        + tuple('VERANDA/WALLPAPERS/%s.cvt' % w for w in walls):
    if p not in paths:
        fail('%s is not in the release' % p)
if 'gh release create veranda-2026-11-21-abc1234 --repo veranda-x16/veranda' not in cmd:
    fail('the gh command: %s' % cmd)
if len([f for f in os.listdir(os.path.join(W, 'rel')) if f.endswith('.bin')]) != len({e['asset'] for e in ents}):
    fail('the assets are not one a distinct file')
n += 1

# 2. a port under another name (its class and author tell)
for name, data in (('VERANDA/APPS/Paint.cvt', cvt('geoWrite', 'Tony Requist')),
                   ('VERANDA/APPS/Paint.cvt', cvt('Writer', 'Tony Requist')),
                   ('VERANDA/APPS/Veranda Calc.cvt', cvt('TopDesk', 'someone')),
                   ('VERANDA/APPS/Veranda Write.cvt', cvt('CmdrWrite', 'x', b'geoWrite    V2.1'))):
    package(P, {name: data})
    try:
        release(P, os.path.join(W, 'rel'))
    except mkrelease.ReleaseError as e:
        if 'personal-use port' not in str(e):
            fail('refused for another reason: %s' % e)
        n += 1
        continue
    fail('%s with a port\'s class or author went into a release' % name)

# 3. an allowlist that names a port: refused
allow = os.path.join(W, 'bad.allow')
for port in ('VERANDA/APPS/geoWrite.cvt', 'VERANDA/APPS/TopDesk.cvt', 'DOCUMENTS/x.geowrite'):
    open(allow, 'w').write(open(mkrelease.DEFAULT_ALLOW).read() + port + '\n')
    package(P, ports)
    try:
        release(P, os.path.join(W, 'rel'), allow)
    except mkrelease.ReleaseError as e:
        if 'personal-use port' not in str(e) and 'never released' not in str(e):
            fail('refused for another reason: %s' % e)
        n += 1
        continue
    fail('an allowlist naming %s made a release' % port)

# 4. the real allowlist names no port
for p in mkrelease.read_allow(mkrelease.DEFAULT_ALLOW):
    if mkrelease.denied(p, b''):
        fail('tools/release.allow names %s' % p)
n += 1
print('ok    mkrelease: %d cases: the ports (geoWrite, TopDesk) never in a release; geoChess, MOD Player and Solitaire in it: by name, by a .cvt\'s '
      'class, parent class or author under another name, nor when the allowlist names them (refused); README.txt, '
      'the Meadow (V162: Dusk, Still Water, Low Hills, Sunroom Tiles in), MOD Player, Solitaire and files outside the allowlist left out; one asset a distinct file; the gh command printed' % n)

# 5. the manifest: what may be listed, the round trip, a cut-short one
try:
    mkmanifest.entries([('VERANDA/.SYSTEM/ASK.CFG', b'x')])
    fail('a .SYSTEM file was listed')
except mkmanifest.ManifestError:
    pass
try:
    mkmanifest.entries([('VERANDA/APPS/a.cvt', b'1'), ('VERANDA/HELP/a.cvt', b'2')])
    fail('two files of one name in two folders')
except mkmanifest.ManifestError:
    pass
t = mkmanifest.render('abc1234', '2026-11-21', mkmanifest.entries([('VERANDA/APPS/Paint.cvt', b'paint'),
                                                                     ('PC/x.py', b'x')]), ['what\'s new ' * 20], 'tag-1')
h, e = mkmanifest.parse(t)
if h['build'] != 'abc1234' or len(e) != 2 or e[0]['crc'] != zlib.crc32(b'paint') or len(h['notes']) < 2:
    fail('the manifest\'s round trip: %s' % t)
try:
    mkmanifest.parse(t.rsplit('end', 1)[0])
    fail('a manifest without its end line was taken')
except mkmanifest.ManifestError:
    pass
for bad in ('VERANDA/HELP/Music, games.txt', 'VERANDA/APPS/a=b.cvt', 'VERANDA/APPS/what?.cvt'):
    try:
        mkmanifest.entries([(bad, b'x')])
        fail('%s: a name Veranda Update refuses, listed' % bad)
    except mkmanifest.ManifestError:
        pass
print('ok    the manifest: never .SYSTEM nor two files of one name; notes wrapped to 76; its end line required; '
      'no name Veranda Update refuses (a comma, =, ?, *, :, a quote)')

# 6. update_server.py: the manifest and an asset by name, 404, a changed file, LAN only
S = os.path.join(W, 'lan')
package(S, {})
srv = update_server.Server(('127.0.0.1', 0), update_server.Handler)
srv.pkg = S
threading.Thread(target=srv.serve_forever, daemon=True).start()
port = srv.server_address[1]


def get(path):
    c = http.client.HTTPConnection('127.0.0.1', port, timeout=10)
    c.request('GET', path)
    r = c.getresponse()
    return r.status, r.read(), r.getheader('Content-Length'), r.getheader('Connection')


st, body, cl, conn = get('/UPDATE.LST')
if st != 200 or not body.startswith(b'VERANDA-UPDATE 1') or int(cl) != len(body) or conn != 'close':
    fail('update_server: UPDATE.LST %s %s %s' % (st, cl, conn))
_, ents = mkmanifest.parse(body.decode('latin-1'))
e = [x for x in ents if x['path'] == 'VERANDA/VERANDA.SYS'][0]
st, body, _, _ = get('/' + e['asset'])
if st != 200 or zlib.crc32(body) & 0xFFFFFFFF != e['crc']:
    fail('update_server: an asset')
if get('/../../etc/passwd')[0] != 404 or get('/VERANDA/VERANDA.SYS')[0] != 404:
    fail('update_server: a path that is not an asset was served')
open(os.path.join(S, 'VERANDA', 'VERANDA.SYS'), 'ab').write(b'changed')
if get('/' + e['asset'])[0] != 409:
    fail('update_server: a file changed since its manifest was served')
for a in ('192.168.1.20', '10.0.0.5', '172.16.3.4', '127.0.0.1', '::1', 'fe80::1%eth0'):
    if not update_server.allowed_client(a):
        fail('update_server refuses %s' % a)
for a in ('8.8.8.8', '203.0.113.9', '172.32.0.1', '2001:db8::1', 'nonsense'):
    if update_server.allowed_client(a):
        fail('update_server allows %s' % a)
srv.shutdown()
print('ok    update_server.py: UPDATE.LST and the assets by name (Content-Length, Connection: close), 404 for '
      'anything else, 409 for a file changed since its manifest; private addresses only')

# 7. the version (docs/RELEASING.md): UPDATE.LST's version line, the tag veranda-<version>; the Test channel
t = mkmanifest.render('abc1234', '2026-11-21', mkmanifest.entries([('VERANDA/APPS/Paint.cvt', b'paint')]), ['n'],
                      None, '1.0')
h, _ = mkmanifest.parse(t)
if h.get('version') != '1.0' or t.split('\n')[2] != 'version 1.0':
    fail('the version line: %s' % t)
for good in ('1.0', '1.0.1', '1.0.1-rc1'):
    if mkmanifest.parse(mkmanifest.render('abc1234', '2026-11-21', [], [], None, good))[0].get('version') != good:
        fail('version %r refused' % good)
for bad in ('1', 'v1.0', '1.0 x', '1.0-toolongsuffix', '1.0.0.0'):
    try:
        mkmanifest.render('abc1234', '2026-11-21', [], [], None, bad)
        fail('version %r taken' % bad)
    except mkmanifest.ManifestError:
        pass
package(P, {})
subprocess.check_call([sys.executable, '-I', '-B', os.path.join(TOOLS, 'mkmanifest.py'), P, '--build', 'abc1234',
                       '--date', '2026-11-21', '--version', '1.0', '--note', 'a test'], stdout=subprocess.DEVNULL)
text, cmd = release(P, os.path.join(W, 'rel'))
h, _ = mkmanifest.parse(text)
if h.get('tag') != 'v1.0' or h.get('version') != '1.0' or 'gh release create v1.0 ' not in cmd \
        or ' --latest ' not in cmd:
    fail('a stable release of 1.0: %s / %s' % (h, cmd))
shutil.rmtree(os.path.join(W, 'rel'))
# the organisation's tag, v<version> (DECISIONS V139)
text, cmd = mkrelease.build(P, os.path.join(W, 'rel'), log=lambda m: None, tag='v1.0')
h, _ = mkmanifest.parse(text)
if h.get('tag') != 'v1.0' or 'gh release create v1.0 --repo veranda-x16/veranda ' not in cmd:
    fail('a stable release tagged v1.0: %s / %s' % (h, cmd))
shutil.rmtree(os.path.join(W, 'rel'))
for bad in (('test', 'v1.0'), ('stable', 'v1.0; rm')):
    try:
        mkrelease.build(P, os.path.join(W, 'rel'), log=lambda m: None, channel=bad[0], tag=bad[1])
        fail('--tag %r on %s taken' % (bad[1], bad[0]))
    except mkrelease.ReleaseError:
        pass
    shutil.rmtree(os.path.join(W, 'rel'), ignore_errors=True)
text, cmd = mkrelease.build(P, os.path.join(W, 'rel'), log=lambda m: None, channel='test')
h, _ = mkmanifest.parse(text)
if h.get('tag') != 'test' or 'gh release create test ' not in cmd or '--prerelease --latest=false' not in cmd \
        or 'gh release upload test ' not in cmd or '--clobber' not in cmd:
    fail('a test release: %s / %s' % (h, cmd))
no_port(os.path.join(W, 'rel'))
print('ok    the version: UPDATE.LST\'s "version 1.0" line (N.M or N.M.P only), the tag v1.0 (--latest, by default or with --tag); '
      'the Test channel: the tag "test", a pre-release, never latest, its assets replaced (--clobber)')
