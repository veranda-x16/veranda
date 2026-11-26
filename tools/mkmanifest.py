#!/usr/bin/env python3
"""Veranda Update's manifest (DECISIONS V130): UPDATE.LST, the list of a
package's files that apps/update reads.

    mkmanifest.py <pkg-dir> --build <hash> --date <YYYY-MM-DD>
                  [--note TEXT ...] [--notes-file FILE] [--min PATH=DATE ...]
                  [--tag TAG] [--version N.M[.P]] [-o OUT]

<pkg-dir> is a package as tools/mkdist.sh makes it (VERANDA/, PC/,
DOCUMENTS/ at its top). The manifest goes to <pkg-dir>/VERANDA/UPDATE.LST
(or OUT): plain text, one item a line, LF line ends:

    VERANDA-UPDATE 1                     the format and its version
    build <id> <date>                    the build: git short hash, date
    version <N.M[.P]>                    Veranda's version (the file VERSION;
                                         docs/RELEASING.md); a Veranda Update
                                         from before it skips the line
    tag <tag>                            (a release's: its GitHub tag)
    note <text>                          "what's new", up to 8 lines of 76
    file <size> <crc32> <kind> <min> <asset> <path>
    ...
    end <files>                          (a manifest cut short has none)

size in bytes; crc32 eight lower-case hex digits (zlib's CRC-32); kind
system, app, font, help, wallpaper, pc or doc-sample; min the oldest
build date the file may be put over ("-": any); asset the file's name in
a release and on the PC's update server: its CRC-32 and ".bin" (the same
bytes, the same asset: VERANDA.PRG and AUTOBOOT.X16 share one); path from
the card's top, "/" between folders, spaces allowed (the line's rest).

Only VERANDA/, PC/ and DOCUMENTS/ are listed (anything else in the folder
is left out with a warning), never VERANDA/.SYSTEM (the user's settings)
nor the manifest itself. Two files of one asset name but other bytes, or
two updatable files of one name in different folders (Veranda Update
keeps the replaced ones side by side in /VERANDA/.SYSTEM/OLD/<build>/),
are refused.

MIT licence (see LICENSE)."""
import argparse
import os
import re
import sys
import textwrap
import zlib

FORMAT = 'VERANDA-UPDATE 1'
SYSTEM = ('VERANDA/VERANDA.PRG', 'VERANDA/AUTOBOOT.X16', 'VERANDA/VERANDA.SYS', 'VERANDA/RBOOT', 'VERANDA/SHELL.cvt')
NOTE_LINES, NOTE_WIDTH = 8, 76
PATH_MAX = 63           # (the X16's paths: Veranda's 64-byte path buffers)
BUILD_RE = re.compile(r'^[0-9A-Za-z._+-]{1,15}$')
DATE_RE = re.compile(r'^\d{4}-\d\d-\d\d$')
VERSION_RE = re.compile(r'^\d{1,3}\.\d{1,3}(\.\d{1,3})?(-[0-9A-Za-z]{1,6})?$')


class ManifestError(Exception):
    pass


def kind_of(path):
    """the kind of a file at path (from the card's top), None: not listed"""
    if path in SYSTEM:
        return 'system'
    top, _, rest = path.partition('/')
    if top == 'PC':
        return 'pc'
    if top == 'DOCUMENTS':
        return 'doc-sample'
    if top != 'VERANDA' or not rest:
        return None
    sub, _, name = rest.partition('/')
    if not name:                        # (a file in /VERANDA itself)
        if rest in ('UPDATE.LST',):
            return None
        if rest.endswith('.cvt'):
            return 'app'                # (Veranda Setup)
        return 'help'                   # (README.txt)
    if sub.startswith('.'):
        return None                     # (.SYSTEM: the user's)
    return {'APPS': 'app', 'DICT': 'app', 'TEMPLATES': 'app', 'FONTS': 'font', 'HELP': 'help', 'WALLPAPERS': 'wallpaper'}.get(sub)


def crc32(data):
    return zlib.crc32(data) & 0xFFFFFFFF


def asset_name(crc):
    return '%08x.bin' % crc


def scan(pkg):
    """[(path, bytes)] of a package folder, sorted; warnings for what is left out"""
    out, left = [], []
    for root, dirs, files in os.walk(pkg):
        dirs.sort()
        for f in sorted(files):
            full = os.path.join(root, f)
            rel = os.path.relpath(full, pkg).replace(os.sep, '/')
            if kind_of(rel) is None:
                left.append(rel)
                continue
            with open(full, 'rb') as fh:
                out.append((rel, fh.read()))
    return out, left


def entries(files, mins=None):
    """the manifest's file lines' fields from [(path, bytes)]"""
    mins = mins or {}
    by_asset, by_base, ents = {}, {}, []     # (asset: (bytes, path))
    for path, data in files:
        k = kind_of(path)
        if k is None:
            raise ManifestError('%s: not a file Veranda Update may list' % path)
        if len(path) > PATH_MAX or '\n' in path or '\r' in path or '//' in path or '..' in path.split('/'):
            raise ManifestError('%s: a path the X16 cannot take (at most %d characters, no "..")' % (path, PATH_MAX))
        # (Veranda Update's okpath, apps/update/man.c: CMDR-DOS's separators
        # and wildcards in a name refuse the whole list on the X16; V139)
        bad = [c for c in path if ord(c) < 32 or c in '"*?:=,'] + (['/.'] if '/.' in path else [])
        if bad:
            raise ManifestError('%s: a name Veranda Update refuses (%s): the X16 would refuse the whole list'
                                % (path, ' '.join(repr(c) for c in bad)))
        c = crc32(data)
        a = asset_name(c)
        if a in by_asset and by_asset[a][0] != data:
            raise ManifestError('%s and %s: one CRC-32, other bytes' % (path, by_asset[a][1]))
        by_asset.setdefault(a, (data, path))
        if k != 'doc-sample':
            base = path.rsplit('/', 1)[-1].lower()
            if base in by_base:
                raise ManifestError('%s and %s: one name in two folders' % (path, by_base[base]))
            by_base[base] = path
        m = mins.get(path, '-')
        if m != '-' and not DATE_RE.match(m):
            raise ManifestError('%s: --min wants a date YYYY-MM-DD' % path)
        ents.append({'size': len(data), 'crc': c, 'kind': k, 'min': m, 'asset': a, 'path': path})
    return ents


def wrap_notes(notes):
    lines = []
    for n in notes:
        n = ' '.join(n.split())
        if n:
            lines += textwrap.wrap(n, NOTE_WIDTH)
    lines = [''.join(ch if 32 <= ord(ch) < 127 else '?' for ch in l) for l in lines]
    return lines[:NOTE_LINES]


def render(build, date, ents, notes=(), tag=None, version=None):
    if version is not None and (len(version) > 15 or not VERSION_RE.match(version)):
        raise ManifestError('version %r: N.M or N.M.P (digits; a -suffix of up to 6 letters and digits)' % version)
    if not BUILD_RE.match(build):
        raise ManifestError('build %r: 1-15 of letters, digits and ._+-' % build)
    if not DATE_RE.match(date):
        raise ManifestError('date %r: YYYY-MM-DD' % date)
    out = [FORMAT, 'build %s %s' % (build, date)]
    if version:
        out.append('version %s' % version)
    if tag:
        out.append('tag %s' % tag)
    out += ['note ' + l for l in wrap_notes(notes)]
    for e in ents:
        out.append('file %d %08x %s %s %s %s' % (e['size'], e['crc'], e['kind'], e['min'], e['asset'], e['path']))
    out.append('end %d' % len(ents))
    return '\n'.join(out) + '\n'


def parse(text):
    """(header dict, [entries]) of a manifest; ManifestError if it is not one"""
    lines = text.split('\n')
    if not lines or lines[0].strip() != FORMAT:
        raise ManifestError('not a %s manifest' % FORMAT)
    head, ents, ended = {'notes': []}, [], False
    for l in lines[1:]:
        l = l.rstrip('\r')
        if not l:
            continue
        w, _, rest = l.partition(' ')
        if w == 'build':
            head['build'], head['date'] = rest.split(' ', 1)
        elif w == 'tag':
            head['tag'] = rest
        elif w == 'version':
            head['version'] = rest
        elif w == 'note':
            head['notes'].append(rest)
        elif w == 'file':
            f = rest.split(' ', 5)
            ents.append({'size': int(f[0]), 'crc': int(f[1], 16), 'kind': f[2], 'min': f[3], 'asset': f[4], 'path': f[5]})
        elif w == 'end':
            if int(rest) != len(ents):
                raise ManifestError('end %s, %d files' % (rest, len(ents)))
            ended = True
    if not ended:
        raise ManifestError('no end line: cut short')
    return head, ents


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('pkg')
    ap.add_argument('--build', required=True)
    ap.add_argument('--date', required=True)
    ap.add_argument('--note', action='append', default=[])
    ap.add_argument('--notes-file')
    ap.add_argument('--min', action='append', default=[], help='PATH=DATE')
    ap.add_argument('--tag')
    ap.add_argument('--version')
    ap.add_argument('-o', '--out')
    a = ap.parse_args()
    notes = list(a.note)
    if a.notes_file:
        with open(a.notes_file, encoding='utf-8') as f:
            notes += f.read().split('\n')
    mins = dict(m.split('=', 1) for m in a.min)
    try:
        files, left = scan(a.pkg)
        text = render(a.build, a.date, entries(files, mins), notes, a.tag, a.version or None)
    except ManifestError as e:
        sys.exit('mkmanifest: %s' % e)
    for l in left:
        print('mkmanifest: left out (not a Veranda folder): %s' % l, file=sys.stderr)
    out = a.out or os.path.join(a.pkg, 'VERANDA', 'UPDATE.LST')
    with open(out, 'w', newline='\n') as f:
        f.write(text)
    print('mkmanifest: %s: %d files, build %s %s' % (out, len(files), a.build, a.date))


if __name__ == '__main__':
    main()
