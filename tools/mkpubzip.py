#!/usr/bin/env python3
"""The public SD-card zip of a GitHub release (DECISIONS V139), for people
who install Veranda by hand instead of with Veranda Update.

    mkpubzip.py <rel-dir> <zip>

<rel-dir>: a release folder from tools/mkrelease.py (UPDATE.LST and its
<crc32>.bin assets: only what tools/release.allow lets in, no port). The
zip holds each file of the list at its path from the card's top
(VERANDA/..., PC/..., DOCUMENTS/...), the list itself as
VERANDA/UPDATE.LST (so Veranda Update knows the build installed) and
INSTALL.txt. Every file is checked against the list's size and CRC-32
first; the zip's dates are the build's date, so the same release gives
the same zip. Nothing else goes in: the zip is what the release already
publishes, in another shape.

Standard library only. MIT licence (see LICENSE)."""
import os
import sys
import zipfile
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mkmanifest  # noqa: E402
import mkrelease  # noqa: E402

INSTALL = '''VERANDA {version} FOR THE COMMANDER X16 (build {build}, {date})

A GEOS-style desktop for the Commander X16: https://veranda-x16.github.io
The manual: https://github.com/veranda-x16/veranda/wiki

TO INSTALL IT
  1. Copy the folders VERANDA, PC and DOCUMENTS to the top of the X16's
     SD card. DOCUMENTS holds examples: skip any file you already have.
     A card that has Veranda already keeps its settings: they are in
     /VERANDA/.SYSTEM, which this zip does not touch.
  2. Put the card in the X16 and type:
         DOS"CD:VERANDA"
         BOOT
     (or LOAD"VERANDA.PRG" and RUN in /VERANDA).
  3. Later versions: Veranda Update (in /VERANDA/APPS) fetches only the
     files that changed.

It needs a Commander X16 with 512 KB of banked RAM or more and a mouse.
The network programs need TexElec's Serial & ESP32 Network Card
(Zimodem). PC/ holds helpers that run on a PC, not on the X16 (see the
manual).

Veranda and the author's own programs: MIT licence, Copyright (c) 2026
Marcin Spoczynski; the source is at https://github.com/veranda-x16/veranda
(tag {tag}). Also in this zip, with credit: geoChess by Scott Hutter
(github.com/geos64128/geochess, modified with his permission; its engine
after BMCP by Maksim Korzh); Solitaire and SID Player (GPL-3.0-or-later,
their source at github.com/veranda-x16); MOD Player (MIT). The ports for
personal use are never in it.
'''


def main():
    if len(sys.argv) != 3:
        sys.exit('usage: mkpubzip.py <rel-dir> <zip>')
    rel, out = sys.argv[1:]
    with open(os.path.join(rel, 'UPDATE.LST'), encoding='latin-1') as f:
        text = f.read()
    head, ents = mkmanifest.parse(text)
    y, m, d = (int(x) for x in head['date'].split('-'))
    when = (y, m, d, 12, 0, 0)
    files = []
    for e in ents:
        with open(os.path.join(rel, e['asset']), 'rb') as f:
            data = f.read()
        if len(data) != e['size'] or (zlib.crc32(data) & 0xFFFFFFFF) != e['crc']:
            sys.exit('mkpubzip: %s: not the bytes of %s' % (e['asset'], e['path']))
        why = mkrelease.denied(e['path'], data)
        if why:
            sys.exit('mkpubzip: %s is a personal-use port (%s): never published' % (e['path'], why))
        files.append((e['path'], data))
    info = INSTALL.format(version=head.get('version') or '(no version)', build=head['build'], date=head['date'],
                          tag=head.get('tag') or '-')
    files.append(('VERANDA/UPDATE.LST', text.encode('latin-1')))
    files.append(('INSTALL.txt', info.replace('\n', '\r\n').encode('ascii')))
    tmp = out + '.tmp'
    with zipfile.ZipFile(tmp, 'w', zipfile.ZIP_DEFLATED) as z:
        for path, data in sorted(files):
            zi = zipfile.ZipInfo(path, when)
            zi.compress_type = zipfile.ZIP_DEFLATED
            zi.external_attr = 0o644 << 16
            z.writestr(zi, data)
    os.replace(tmp, out)
    print('mkpubzip: %s: %d files, %d bytes' % (out, len(files), os.path.getsize(out)))


if __name__ == '__main__':
    main()
