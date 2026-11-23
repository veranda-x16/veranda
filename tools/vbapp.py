#!/usr/bin/env python3
"""VeraBASIC's Make application on the PC (DECISIONS V99): a program and
VeraBASIC Run made into one standalone Veranda application, byte for byte
as the editor's File > Make application... writes it (apart from the
date in the file's directory entry, bytes 23-27).

usage (through tools/vbasic.py):
       vbasic.py app FILE.bas [-o OUT.cvt] [--run "VeraBASIC Run.cvt"]

The application (docs/vbasic/FORMAT.md 7.3) is VeraBASIC Run's file with:
  - its records 0-11 as they are (the runtime);
  - records 12 on: the program, 8191 bytes a record (a banked overlay's
    most): an 80-byte header ("VBAP", the records' form 1, the token
    format, the four records' sizes, the name) and the program
    document's four records one after the other;
  - its info block's class, author, flags (banked, a tile, APPF_STAY),
    documents and description from the APP lines; its tile (CVT bytes
    96-224) from APP TILE and TILE DATA (else Run's); the GEOS name the
    name's first 16 characters.

The APP lines are read from the text, as the editor reads them (so the
two agree): a line (after its line number, if any) starting with APP or
TILE DATA, its items separated by commas, string literals, colour names
or numbers; a comment (' or REM) ends it. The output defaults to
"<name>.cvt" in the current folder; Run's file to "VeraBASIC Run.cvt"
there (or $VB_RUN).

Python 3 only; run with -I as the other tools. MIT licence (LICENSE).
"""
import datetime
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import vpack  # noqa: E402

RUN_RECORDS = 12                # VeraBASIC Run's records (apps/vbasic/Makefile RECS)
CHUNK = 8191                    # a banked overlay's bytes at most
HDR = 80                        # the program's header in record 12
# the colours APP TILE takes (Look 2's palette entries, vpack.TILE_COLOURS)
COLOURS = [c.upper() for c in vpack.TILE_COLOURS]
BAD = set('/:*?="')


def _alpha(c):
    return 'A' <= c <= 'Z' or 'a' <= c <= 'z' or c == '_'


def _digit(c):
    return '0' <= c <= '9'


def _word(c):
    return _alpha(c) or _digit(c)


class AppError(Exception):
    def __init__(self, line, msg):
        Exception.__init__(self, msg)
        self.line, self.msg = line, msg


def _items(text, ln):
    """a line's rest -> its items: ('s', string) | ('w', WORD) | ('n', int)
    | (',',); a comment ends it"""
    out, i, n = [], 0, len(text)
    while i < n:
        c = text[i]
        if c in ' \t':
            i += 1
        elif c == '"':
            j = text.find('"', i + 1)
            if j < 0:
                raise AppError(ln, 'A string without its closing "')
            out.append(('s', text[i + 1:j]))
            i = j + 1
        elif c == ',':
            out.append((',',))
            i += 1
        elif c == "'":
            break
        elif _digit(c):
            j = i
            while j < n and _digit(text[j]):
                j += 1
            out.append(('n', int(text[i:j])))
            i = j
        elif _alpha(c):
            j = i
            while j < n and _word(text[j]):
                j += 1
            w = text[i:j].upper()
            if w == 'REM':
                break
            out.append(('w', w))
            i = j
        else:
            raise AppError(ln, 'APP lines take strings, colours and words only')
    return out


def app_lines(text, default_name):
    """the APP lines of a source (bytes or str) -> a dict of the fields"""
    if isinstance(text, bytes):
        text = text.decode('latin-1')
    a = {'name': default_name, 'class': None, 'version': '1.0', 'author': '', 'description': '',
         'documents': [], 'colour': None, 'rows': [], 'stay': False}
    for ln, line in enumerate(text.split('\n'), 1):
        s = line.lstrip(' \t')
        k = 0
        while k < len(s) and _digit(s[k]):
            k += 1
        s = s[k:].lstrip(' \t')
        k = 0
        while k < len(s) and _word(s[k]):
            k += 1
        word = s[:k].upper()
        if word == 'APP':
            it = _items(s[k:], ln)
            j = 0
            while j < len(it):
                if it[j][0] != 'w':
                    raise AppError(ln, 'APP: a word expected (NAME, CLASS, TILE ...)')
                w = it[j][1]
                j += 1
                if w in ('NAME', 'CLASS', 'VERSION', 'AUTHOR', 'DESCRIPTION'):
                    if j >= len(it) or it[j][0] != 's':
                        raise AppError(ln, 'APP %s: a string expected' % w)
                    a[w.lower()] = it[j][1]
                    j += 1
                elif w == 'DOCUMENTS':
                    while True:
                        if j >= len(it) or it[j][0] != 's':
                            raise AppError(ln, 'APP DOCUMENTS: a string expected')
                        a['documents'].append(it[j][1].upper())
                        j += 1
                        if j + 1 < len(it) and it[j][0] == ',' and it[j + 1][0] == 's':
                            j += 1
                            continue
                        break
                elif w == 'TILE':
                    if j < len(it) and it[j][0] == 'w' and it[j][1] in COLOURS:
                        a['colour'] = COLOURS.index(it[j][1])
                    elif j < len(it) and it[j][0] == 'n' and it[j][1] < 16:
                        a['colour'] = it[j][1]
                    else:
                        raise AppError(ln, 'APP TILE: a colour expected (SKY, HILL ... or 0-15)')
                    j += 1
                elif w == 'STAY':
                    a['stay'] = True
                elif w == 'CLASSIC':
                    pass
                else:
                    raise AppError(ln, 'APP: no such item: %s' % w)
                if j < len(it):
                    if it[j][0] != ',':
                        raise AppError(ln, 'APP: a comma expected')
                    j += 1
        elif word == 'TILE':
            it = _items(s[k:], ln)
            if not it or it[0] != ('w', 'DATA'):
                continue                # (TILE x, y, name$: the statement)
            for j, t in enumerate(it[1:]):
                if (j % 2 == 0) != (t[0] == 's'):
                    raise AppError(ln, 'TILE DATA: strings separated by commas')
                if t[0] == 's':
                    if len(t[1]) != 32 or set(t[1]) - set('#.'):
                        raise AppError(ln, 'TILE DATA: rows of 32 "#" and "."')
                    a['rows'].append(t[1])
    if not a['class']:
        a['class'] = a['name'][:12]
    checks = [('name', 63, 'The name'), ('class', 12, 'The class'), ('version', 6, 'The version'),
              ('author', 19, 'The author'), ('description', 95, 'The description')]
    for key, most, what in checks:
        if len(a[key]) > most:
            raise AppError(0, '%s is too long (%d characters at most)' % (what, most))
    if not a['name'] or BAD & set(a['name']):
        raise AppError(0, 'The name: 1-63 characters, none of / : * ? = "')
    if len(a['documents']) > 4 or any(not 1 <= len(d) <= 4 or not all(_word(c) and c != '_' for c in d) for d in a['documents']):
        raise AppError(0, 'APP DOCUMENTS: up to four extensions of 1-4 letters or digits')
    if a['rows'] and len(a['rows']) != 32:
        raise AppError(0, 'TILE DATA: 32 rows, not %d' % len(a['rows']))
    return a


def run_records(run):
    """VeraBASIC Run's file -> (its record table's first 2 * 12 bytes, the
    bytes of its records' blocks)"""
    if len(run) < 762 or run[21] != 1 or run[254 + 137 - 2:254 + 141 - 2] != b'VRND':
        raise AppError(0, 'This is not VeraBASIC Run')
    t = run[508:762]
    if t[2 * RUN_RECORDS] != 0 or t[2 * RUN_RECORDS + 1] != 0 or t[2 * RUN_RECORDS - 2] == 0:
        raise AppError(0, 'VeraBASIC Run has not got its %d records' % RUN_RECORDS)
    n = sum(t[2 * i] for i in range(RUN_RECORDS))
    return bytes(t[:2 * RUN_RECORDS]), run[762:762 + n * 254], n


def make(run, recs, a, now=None):
    """the application's bytes: VeraBASIC Run's file, the program's four
    records, the APP fields (app_lines)"""
    table0, body0, nblk = run_records(run)
    hdr = bytearray(HDR)
    hdr[0:4] = b'VBAP'
    hdr[4] = 1                          # the form of these records
    hdr[5] = recs[0][2] if recs[0] else 1       # the token format
    for i, r in enumerate(recs):
        hdr[6 + 2 * i:8 + 2 * i] = len(r).to_bytes(2, 'little')
    nm = a['name'].encode('latin-1')
    hdr[16:16 + len(nm)] = nm
    blob = bytes(hdr) + b''.join(recs)
    chunks = [blob[i:i + CHUNK] for i in range(0, len(blob), CHUNK)]
    if RUN_RECORDS + len(chunks) > 127:
        raise AppError(0, 'The program is too big for an application')
    table = bytearray(254)
    table[:len(table0)] = table0
    body = bytearray(body0)
    for i, c in enumerate(chunks):
        b = -(-len(c) // 254)
        table[2 * (RUN_RECORDS + i)] = b
        table[2 * (RUN_RECORDS + i) + 1] = len(c) - (b - 1) * 254 + 1
        body += c + bytes(b * 254 - len(c))
        nblk += b
    info = bytearray(run[254:508])      # the info block from its byte 2
    def put(at, data, size):
        info[at - 2:at - 2 + size] = data.ljust(size, b'\0')
    put(77, a['class'].encode('latin-1').ljust(12) + b'V' + a['version'].encode('latin-1'), 20)
    put(97, a['author'].encode('latin-1'), 20)
    info[143 - 2] = 1 | vpack.TILE_FLAG | (4 if a['stay'] else 0)
    put(144, b''.join(d.encode('latin-1').ljust(4) for d in a['documents']), 16)
    put(160, a['description'].encode('latin-1'), 96)
    block0 = bytearray(run[0:254])
    block0[3:19] = nm[:16].ljust(16, b'\xa0')
    now = now or datetime.datetime.now()
    block0[23:28] = bytes([now.year - 1900, now.month, now.day, now.hour, now.minute])
    block0[28:30] = min(2 + nblk, 0xFFFF).to_bytes(2, 'little')
    if a['colour'] is not None:
        block0[vpack.TILE_AT] = a['colour']
    if a['rows']:
        block0[vpack.TILE_AT + 1:vpack.TILE_AT + 129] = vpack.tile_bitmap(a['rows'])
    return bytes(block0) + bytes(info) + bytes(table) + bytes(body)


def same(a, b):
    """two applications equal but for the date (directory entry 23-27)?"""
    return len(a) == len(b) and a[:23] == b[:23] and a[28:] == b[28:]


def read_app(data):
    """a made application -> (the header's fields, the four records)"""
    t = data[508:762]
    pos, blob = 762, b''
    for i in range(127):
        b, last = t[2 * i], t[2 * i + 1]
        if b == 0 and last == 0:
            break
        if b == 0:
            continue
        if i >= RUN_RECORDS:
            blob += data[pos:pos + (b - 1) * 254 + last - 1]
        pos += b * 254
    if blob[:4] != b'VBAP':
        raise AppError(0, 'not a made application')
    if blob[4] > 1:
        raise AppError(0, 'Made by a newer VeraBASIC')
    sizes = [int.from_bytes(blob[6 + 2 * i:8 + 2 * i], 'little') for i in range(4)]
    recs, at = [], HDR
    for s in sizes:
        recs.append(blob[at:at + s])
        at += s
    return blob[16:80].split(b'\0')[0].decode('latin-1'), recs
