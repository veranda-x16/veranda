#!/usr/bin/env python3
"""Veranda Update's GitHub release (DECISIONS V130): a package filtered
through the public allowlist, as release assets.

    mkrelease.py <pkg-dir> <out-dir> [--repo OWNER/REPO] [--allow FILE]
                 [--channel stable|test] [--tag TAG] [--no-pack]

<pkg-dir>: a package from tools/mkdist.sh (its VERANDA/UPDATE.LST gives
the build, the date and the notes). <out-dir>: a new or empty folder; it
gets
    UPDATE.LST      the public manifest (tools/mkmanifest.py's format, with
                    the release's tag): only the allowed files
    <crc32>.bin     one asset for each distinct file (the bytes as they are:
                    the X16 fetches each file whole, with nothing to unpack)
    <crc32>.pak     (V210) the pack: the same files deflated, one after
                    another (tools/mkmanifest.py's pack(); the manifest's
                    pack and z lines say where each is); a Veranda Update
                    from V210 on fetches from it, an older one never asks
                    for it. Named by its CRC-32: a Test channel's X16 half
                    way through an update keeps the pack its list names.
                    --no-pack: none (a release as before V210)
    NOTES.md        the release's notes (what's new, the files, the licence)
Then it prints the gh command that publishes it; mkrelease never runs it
and never talks to GitHub.

The channels (docs/RELEASING.md): stable (the default) is a release of its
own, tagged v<version> (the manifest's version line; a package
without one: veranda-<date>-<build>), published as GitHub's latest:
Veranda Update's Stable reads releases/latest/download/UPDATE.LST. test
is the one release tagged "test", a pre-release (never "latest"), whose
assets are replaced by each test build (gh release upload --clobber): its
Test channel reads releases/download/test/UPDATE.LST. The assets are
named by their CRC-32, so the ones a test build no longer lists can stay:
an X16 half way through an update still finds every file of the list it
fetched. --tag (or RELEASE_TAG) names a stable release's tag instead: the
organisation's repositories tag a version v<version> (tools/publish.sh,
the release workflow; DECISIONS V139), and the X16 fetches the files from
the tag its UPDATE.LST names.

The allowlist (tools/release.allow) names every path that may go in;
anything else is left out and listed. A file of the personal-use ports
(geoWrite, TopDesk: by name, or by a .cvt's class, parent class
or author) is never released: it is refused even when the allowlist names
it (mkrelease fails), and the finished folder is checked again.

MIT licence (see LICENSE)."""
import argparse
import os
import shlex
import sys
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mkmanifest  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_ALLOW = os.path.join(HERE, 'release.allow')
DEFAULT_REPO = 'veranda-x16/veranda'

# the release's licence and credits (release.allow's "Other people's work")
CREDITS = ("Veranda and the author's own programs: MIT licence, Copyright (c) 2026 Marcin Spoczynski. "
           "Also in this release, with credit: geoChess by Scott Hutter (github.com/geos64128/geochess, "
           "modified with his permission; its engine after BMCP by Maksim Korzh); Solitaire and SID Player "
           "(GPL-3.0-or-later, their source at github.com/veranda-x16); MOD Player (MIT). "
           "The ports for personal use are never in it.")
# the personal-use ports: never in a public release
DENY_NAMES = ('geowrite', 'topdesk', 'geo write', 'top desk')
DENY_CLASSES = ('geowrite', 'topdesk', 'write image')
DENY_AUTHORS = ('tony requist', 'geos-user-club', 'berkeley softworks')


class ReleaseError(Exception):
    pass


def read_allow(path):
    out = []
    with open(path, encoding='utf-8') as f:
        for l in f:
            l = l.rstrip('\n').rstrip('\r')
            if l.strip() and not l.lstrip().startswith('#'):
                out.append(l.strip())
    if len(set(out)) != len(out):
        raise ReleaseError('%s names a path twice' % path)
    return out


def cvt_fields(data):
    """(class, parent class, author) of a CVT file, lower case; None if it is not one"""
    if len(data) < 508 or b'PRG formatted GEOS file' not in data[30:60]:
        return None
    info = bytes(2) + data[254:508]

    def f(a, b):
        return info[a:b].split(b'\0')[0].decode('latin-1').strip().lower()
    return f(77, 97), f(117, 137), f(97, 117)


def denied(path, data):
    """why a file must never be released, or None"""
    low = path.lower()
    for n in DENY_NAMES:
        if n in low:
            return 'its name (%s)' % n
    c = cvt_fields(data)
    if c:
        cls, parent, author = c
        for n in DENY_CLASSES:
            if cls.startswith(n) or parent.startswith(n):
                return 'its GEOS class (%s / %s)' % (cls or '-', parent or '-')
        for n in DENY_AUTHORS:
            if author.startswith(n):
                return 'its author (%s)' % author
    return None


def build(pkg, out, repo=DEFAULT_REPO, allow=DEFAULT_ALLOW, log=print, channel='stable', tag=None, packed=True):
    """the release into out; returns (manifest text, the gh command)"""
    allowed = read_allow(allow)
    allowset = set(allowed)
    for p in allowed:
        why = denied(p, b'')
        if why:
            raise ReleaseError('the allowlist names %s, a personal-use port (%s): never released' % (p, why))
    man = os.path.join(pkg, 'VERANDA', 'UPDATE.LST')
    if not os.path.isfile(man):
        raise ReleaseError('%s: no manifest (a package from tools/mkdist.sh has one)' % man)
    with open(man, encoding='latin-1') as f:
        head, _ = mkmanifest.parse(f.read())
    files, _left = mkmanifest.scan(pkg)
    take, leftout = [], []
    for path, data in files:
        why = denied(path, data)
        if why:
            if path in allowset:
                raise ReleaseError('%s is a personal-use port (%s) but the allowlist names it: refused' % (path, why))
            leftout.append((path, 'a personal-use port: never released'))
            continue
        if path not in allowset:
            leftout.append((path, 'not in the allowlist'))
            continue
        take.append((path, data))
    have = {p for p, _ in take}
    missing = [p for p in allowed if p not in have]
    if not any(mkmanifest.kind_of(p) == 'system' for p in have):
        raise ReleaseError('no system files in %s: not a Veranda package' % pkg)
    if os.path.exists(out) and os.listdir(out):
        raise ReleaseError('%s is not empty' % out)
    os.makedirs(out, exist_ok=True)
    if channel not in ('stable', 'test'):
        raise ReleaseError('channel %r: stable or test' % channel)
    version = head.get('version')
    if tag and (channel == 'test' or not all(c.isalnum() or c in '.-_' for c in tag)):
        raise ReleaseError('--tag %r: a stable release\'s tag (letters, digits, . - _)' % tag)
    if tag:
        pass
    elif channel == 'test':
        tag = 'test'
    elif version:
        tag = 'v%s' % version
    else:
        tag = 'veranda-%s-%s' % (head['date'], head['build'])
    ents = mkmanifest.entries(take)
    pak, where = None, None
    if packed:
        data = {e['asset']: d for (_, d), e in zip(take, ents)}
        pdata, where = mkmanifest.pack(ents, lambda e: data[e['asset']])
        pak = (mkmanifest.pack_name(pdata), len(pdata))
        with open(os.path.join(out, pak[0]), 'wb') as f:
            f.write(pdata)
    text = mkmanifest.render(head['build'], head['date'], ents, head['notes'], tag, version, pak, where)
    with open(os.path.join(out, 'UPDATE.LST'), 'w', newline='\n') as f:
        f.write(text)
    assets = {}
    for (path, data), e in zip(take, ents):
        if e['asset'] not in assets:
            with open(os.path.join(out, e['asset']), 'wb') as f:
                f.write(data)
            assets[e['asset']] = path
    with open(os.path.join(out, 'NOTES.md'), 'w') as f:
        f.write('Veranda %sfor the Commander X16, build %s (%s)%s.\n\n' % (
            version + ' ' if version else '', head['build'], head['date'],
            ', a test build (the Test channel of Veranda Update)' if channel == 'test' else ''))
        if head['notes']:
            f.write('%s\n\n' % ' '.join(head['notes']))
        f.write('Install it with **Veranda Update** (in /VERANDA/APPS: Check, then Update), '
                'or copy the files to the card by hand: each asset `<crc32>.bin` is one file, '
                'named in UPDATE.LST (`file <size> <crc32> <kind> <min> <asset> <path>`).\n\n')
        f.write('| File | Size | Asset |\n|---|---:|---|\n')
        for e in ents:
            f.write('| %s | %d | %s |\n' % (e['path'], e['size'], e['asset']))
        f.write('\n' + CREDITS + '\n')
    verify(out)
    for p, why in leftout:
        log('mkrelease: left out %s (%s)' % (p, why))
    for p in missing:
        log('mkrelease: WARNING: the allowlist names %s, which the package does not have' % p)
    log('mkrelease: %s: %d files (%d assets, %d bytes), tag %s%s' % (
        out, len(ents), len(assets), sum(e['size'] for e in ents), tag,
        ', the pack %s (%d bytes)' % pak if pak else ''))
    q = shlex.quote
    title = 'Veranda %s (%s, %s)' % (version, head['build'], head['date']) if version else \
        'Veranda %s (%s)' % (head['date'], head['build'])
    files = '%s %s' % (q(os.path.join(out, 'UPDATE.LST')),
                       ' '.join(q(os.path.join(out, a)) for a in sorted(assets) + ([pak[0]] if pak else [])))
    notes = q(os.path.join(out, 'NOTES.md'))
    if channel == 'test':
        title = 'Veranda test build %s (%s)' % (head['build'], head['date'])
        cmd = ('# the first time (no release "test" yet):\n'
               'gh release create test --repo %s --title %s --notes-file %s --prerelease --latest=false %s\n'
               '# after that (the same tag, its assets replaced):\n'
               'gh release upload test --repo %s --clobber %s && '
               'gh release edit test --repo %s --title %s --notes-file %s --prerelease --latest=false'
               % (q(repo), q(title), notes, files, q(repo), files, q(repo), q(title), notes))
    else:
        cmd = ('gh release create %s --repo %s --title %s --notes-file %s --latest %s'
               % (q(tag), q(repo), q(title), notes, files))
    return text, cmd


def verify(out):
    """the finished folder checked again: the manifest's assets, nothing else, no port"""
    with open(os.path.join(out, 'UPDATE.LST'), encoding='latin-1') as f:
        head, ents = mkmanifest.parse(f.read())
    names = {e['asset'] for e in ents}
    if 'pack' in head:
        # (V210) the pack: its size, and each z line's bytes inflate to its file
        pname, psize = head['pack']
        names.add(pname)
        with open(os.path.join(out, pname), 'rb') as f:
            pdata = f.read()
        if len(pdata) != psize or mkmanifest.pack_name(pdata) != pname:
            raise ReleaseError('%s: not the pack the manifest names' % pname)
        for e in ents:
            if e['kind'] == 'doc-sample':
                if 'z' in e:
                    raise ReleaseError('%s: a doc-sample in the pack' % e['path'])
                continue
            if 'z' not in e:
                raise ReleaseError('%s: not in the pack' % e['path'])
            o, z = e['z']
            with open(os.path.join(out, e['asset']), 'rb') as f:
                want = f.read()
            try:
                d = zlib.decompressobj(-15)
                got = d.decompress(pdata[o:o + z]) + d.flush()
                if not d.eof or d.unused_data:
                    raise zlib.error('not one whole stream')
            except zlib.error as x:
                raise ReleaseError('%s: its bytes in the pack do not inflate (%s)' % (e['path'], x))
            if got != want:
                raise ReleaseError('%s: its bytes in the pack are not its own' % e['path'])
    for e in ents:
        why = denied(e['path'], b'')
        if why:
            raise ReleaseError('the manifest lists %s: a personal-use port' % e['path'])
        with open(os.path.join(out, e['asset']), 'rb') as f:
            data = f.read()
        if len(data) != e['size'] or (zlib.crc32(data) & 0xFFFFFFFF) != e['crc']:
            raise ReleaseError('%s: not %s\'s bytes' % (e['asset'], e['path']))
        why = denied(e['path'], data)
        if why:
            raise ReleaseError('%s (%s) is a personal-use port (%s)' % (e['asset'], e['path'], why))
    for f in os.listdir(out):
        if f not in names and f not in ('UPDATE.LST', 'NOTES.md'):
            raise ReleaseError('%s: not in the manifest' % f)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('pkg')
    ap.add_argument('out')
    ap.add_argument('--repo', default=os.environ.get('REPO') or DEFAULT_REPO)
    ap.add_argument('--allow', default=DEFAULT_ALLOW)
    ap.add_argument('--channel', default=os.environ.get('CHANNEL') or 'stable', choices=('stable', 'test'))
    ap.add_argument('--tag', default=os.environ.get('RELEASE_TAG') or None)
    ap.add_argument('--no-pack', action='store_true', help='no pack (a release as before V210)')
    a = ap.parse_args()
    try:
        _, cmd = build(a.pkg, a.out, a.repo, a.allow, channel=a.channel, tag=a.tag, packed=not a.no_pack)
    except (ReleaseError, mkmanifest.ManifestError, OSError) as e:
        sys.exit('mkrelease: %s' % e)
    print('mkrelease: to publish it (you run this; mkrelease does not):')
    print(cmd)


if __name__ == '__main__':
    main()
