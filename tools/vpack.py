#!/usr/bin/env python3
"""A Veranda application as a GEOS file in CVT format (docs/APPFORMAT.md).

usage: vpack.py [-o out.cvt] [--load ADDR] <app.hdr> <main> [<overlay>...]
       vpack.py [-o out.cvt] --doc <doc.hdr>
       vpack.py --list <file.cvt>
       vpack.py -o out.cvt --icon3 <icon.txt> <file.cvt>

main: the program, a PRG (its first two bytes the load address) or, with
--load, raw bytes loaded there. Overlays (raw bytes) make the file a VLIR
file: record 0 the program, records 1.. the overlays.

app.hdr, one "key = value" a line (# comments):
  name         the GEOS file name (up to 16 characters)        required
  class        the class (up to 12 characters)                 required
  version      x.y                                             default 1.0
  author       up to 19 characters
  description  up to 95 characters
  mode         640x480, 640x240, 320x240 or keep               default keep
  api          the API level the application needs            default 1
  start        the start address ($hex or decimal)             default load
  icon         a 24x21 PBM or PNG (relative to app.hdr)        default icon
  type         application, or deskacc (a desk accessory: GEOS
               type DESK_ACC, sequential, mode keep)            default application
  overlays     packed, or banked: each overlay in a RAM bank of
               its own from $A000, to run there (at most 8191
               bytes each; flags bit 0; API 2)                  default packed
  documents    the plain files it opens, by extension: up to four
               of 1-4 characters, by spaces (e.g. "X16S CSV"); the
               shell opens such a file with it (info block 144-159)
  tile         its tile for the shell (Veranda Look 2, DECISIONS
               V77): a text file (relative to app.hdr), "colour
               <name>" (a palette entry of Look 2, TILE_COLOURS)
               and 32 rows of 32 characters, "#" ink; stored in the
               CVT signature block's padding (bytes 96-224) with
               flags bit 1 (docs/APPFORMAT.md)                  default none
  icon3        its colour icon (Veranda Look 3, DECISIONS V133): an
               icon source of tools/mkicons3.py (relative to
               app.hdr; 32 rows of '.', 'K' and 'a'-'o'), packed
               (658 bytes) at the file's end, found by bytes
               225-229 of the signature block ("I3", its offset)
               with flags bit 3 (docs/APPFORMAT.md)            default none
  stay         yes: never put aside by the switcher, which asks to
               quit it instead (flags bit 2, APPF_STAY; API 6,
               DECISIONS V83)                                   default no
The output defaults to "<name>.cvt" next to app.hdr. Inputs are only read.

--icon3: a copy of a GEOS file (an application of another repository,
a port) with a colour icon added (or replaced): the package builder's way
to give a program built elsewhere its Look 3 icon (DECISIONS V133).

--doc: a sequential GEOS document (APPL_DATA) that the shell opens with
its application (DECISIONS V87, V128); doc.hdr has name, class, version,
author, description, icon and tile as above, and
  parent       the application's class (up to 12 characters: the
               shell matches the first 12 of the info block's
               parent, written padded with "V1.0" after)       required
  data         its data: a line of text, written with CR LF     default none
A tile makes the info block Veranda's ("VRND", flags bit 1) and puts the
tile in the signature block as an application's (the shell reads any
file's).
"""
import datetime
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import vicon  # noqa: E402

APPLICATION = 6
DESK_ACC = 5
TYPES = {'application': APPLICATION, 'deskacc': DESK_ACC}
CBM_USR = 0x83
MODES = {'640x480': 0, '640x240': 1, '320x240': 2, 'keep': 0xFF}
SIG = b'PRG formatted GEOS file V1.0'
APP_LO, APP_HI = 0x0801, 0x8800            # application memory: [lo, hi)
BAD_NAME = set('/:*?="')
# the tile block (DECISIONS V77): in the CVT's first block, after the
# signature (bytes 30-57, zero padded to 253): the colour at 96, the
# bitmap (32 x 32, 4 bytes a row, bit 7 the left pixel, 1 ink) 97-224
TILE_AT, TILE_FLAG = 96, 0x02
# the colour icon (Look 3, DECISIONS V133): appended at the file's end,
# "I3" and its offset (3 bytes, little-endian) at 225 of the first block
ICON3_AT, ICON3_FLAG = 225, 0x08
# Look 2's palette entries (sdk/lib/theme.h: PAPER ... DUSK), by name
TILE_COLOURS = ['paper', 'ink', 'chrome', 'sidebar', 'select', 'title', 'yellow', 'red', 'green', 'purple',
                'orange', 'cyan', 'sky', 'sky2', 'hill', 'dusk']


class PackError(Exception):
    pass


def num(s):
    s = s.strip()
    return int(s[1:], 16) if s.startswith('$') else int(s, 0)


def read_hdr(path):
    h = {}
    for n, line in enumerate(open(path, encoding='utf-8'), 1):
        line = line.split('#', 1)[0].strip()
        if not line:
            continue
        if '=' not in line:
            raise PackError('%s:%d: "key = value" expected' % (path, n))
        k, v = line.split('=', 1)
        h[k.strip().lower()] = v.strip()
    for k in ('name', 'class'):
        if k not in h:
            raise PackError('%s: no %s' % (path, k))
    return h


def text(s, size, what):
    b = s.encode('latin-1')
    if len(b) > size:
        raise PackError('%s is too long (at most %d characters)' % (what, size))
    return b


def read_tiles(path):
    """the tiles of a tile file: [(name, {key: value}, rows)]. Blocks
    "tile <name>" (then "for ...", "colour <name>", 32 rows of 32
    characters, "#" ink, "." none) and "mini <name>" (11 rows of 11); a
    file of one tile needs no "tile" line. "#" lines that are not rows
    are comments."""
    out, cur = [], None
    for n, line in enumerate(open(path, encoding='utf-8'), 1):
        line = line.rstrip()
        if not line:
            continue
        w = line.split(None, 1)
        if w[0] in ('tile', 'mini') and len(w) == 2:
            cur = (w[1], {'kind': w[0]}, [], 11 if w[0] == 'mini' else 32)
            out.append(cur)
            continue
        if w[0] in ('colour', 'color', 'for'):
            if cur is None:
                cur = ('', {'kind': 'tile'}, [], 32)
                out.append(cur)
            if len(w) != 2 or cur[2]:
                raise PackError('%s:%d: "%s <value>" before the rows' % (path, n, w[0]))
            cur[1]['colour' if w[0] == 'color' else w[0]] = w[1].strip()
            continue
        if cur is None or len(line) != cur[3] or set(line) - set('#.'):
            if line.startswith('#'):
                continue
            raise PackError('%s:%d: a row of %d characters ("#", ".") expected' % (path, n, cur[3] if cur else 32))
        if len(cur[2]) >= cur[3]:
            raise PackError('%s:%d: more than %d rows' % (path, n, cur[3]))
        cur[2].append(line)
    for name, kv, rows, size in out:
        if len(rows) != size:
            raise PackError('%s: "%s" has %d rows, not %d' % (path, name, len(rows), size))
    return [(a, b, c) for a, b, c, _ in out]


def tile_colour(name):
    if name not in TILE_COLOURS:
        raise PackError('tile colour "%s": one of %s' % (name, ', '.join(TILE_COLOURS)))
    return TILE_COLOURS.index(name)


def tile_bitmap(rows):
    """rows of "#" and "." -> bytes, (width + 7) / 8 a row, bit 7 the left"""
    b = bytearray()
    for r in rows:
        for x in range(0, len(r), 8):
            v = 0
            for i, ch in enumerate(r[x:x + 8]):
                if ch == '#':
                    v |= 0x80 >> i
            b.append(v)
    return bytes(b)


def tile_bytes(path):
    """a tile file of one tile -> (colour, 128 bytes)"""
    t = [x for x in read_tiles(path) if x[1]['kind'] == 'tile']
    if len(t) != 1:
        raise PackError('%s: one tile expected' % path)
    _, kv, rows = t[0]
    return tile_colour(kv.get('colour', 'chrome')), tile_bitmap(rows)


def blocks(n):
    return -(-n // 254)


def pack(hdr, hdr_dir, main, load, overlays):
    name = text(hdr['name'], 16, 'name')
    if not name or BAD_NAME & set(hdr['name']):
        raise PackError('name: 1-16 characters, none of / : * ? = "')
    if load is None:
        if len(main) < 2:
            raise PackError('main: not a PRG')
        load, main = main[0] | main[1] << 8, main[2:]
    end = load + len(main)
    if load < APP_LO or end > APP_HI:
        raise PackError('the program is at $%04X-$%04X, outside $%04X-$%04X' % (load, end - 1, APP_LO, APP_HI - 1))
    start = num(hdr['start']) if 'start' in hdr else load
    if not load <= start < end:
        raise PackError('start $%04X is outside the program' % start)
    mode = hdr.get('mode', 'keep').lower()
    if mode not in MODES:
        raise PackError('mode: one of ' + ', '.join(MODES))
    api = num(hdr.get('api', '1'))
    gtype = TYPES.get(hdr.get('type', 'application').lower())
    if gtype is None:
        raise PackError('type: application or deskacc')
    if gtype == DESK_ACC and (overlays or mode != 'keep'):
        raise PackError('a desk accessory has no overlays and keeps the video mode (mode = keep)')
    version = hdr.get('version', '1.0')
    vlir = bool(overlays)
    if len(overlays) > 126:
        raise PackError('at most 126 overlays')
    ovmode = hdr.get('overlays', 'packed').lower()
    if ovmode not in ('packed', 'banked'):
        raise PackError('overlays: packed or banked')
    flags = 1 if ovmode == 'banked' else 0
    if hdr.get('stay', 'no').lower() in ('yes', '1', 'true'):
        flags |= 4                              # APPF_STAY (V83)
    tile = tile_bytes(os.path.join(hdr_dir, hdr['tile'])) if 'tile' in hdr else None
    if tile:
        flags |= TILE_FLAG
    icon3 = icon3_bytes(os.path.join(hdr_dir, hdr['icon3'])) if 'icon3' in hdr else None
    if icon3:
        flags |= ICON3_FLAG
    if flags & 1 and api < 2:
        raise PackError('overlays = banked needs api = 2')
    for i, o in enumerate(overlays):
        if flags & 1 and len(o) > 8191:
            raise PackError('overlay %d: %d bytes, more than a bank holds (8191)' % (i + 1, len(o)))

    info = bytearray(256)
    info[0], info[1] = 0, 0xFF
    info[2], info[3], info[4] = 3, 21, 0xBF
    icon = os.path.join(hdr_dir, hdr['icon']) if 'icon' in hdr else None
    info[5:68] = vicon.icon_bytes(icon)
    info[68], info[69], info[70] = CBM_USR, gtype, 1 if vlir else 0
    info[71:73] = load.to_bytes(2, 'little')
    info[73:75] = end.to_bytes(2, 'little')
    info[75:77] = start.to_bytes(2, 'little')
    cls = text(hdr['class'], 12, 'class').ljust(12) + b'V' + text(version, 6, 'version')
    info[77:77 + len(cls)] = cls
    au = text(hdr.get('author', ''), 19, 'author')
    info[97:97 + len(au)] = au
    info[137:141] = b'VRND'
    info[141], info[142], info[143] = api, MODES[mode], flags
    docs = hdr.get('documents', '').upper().split()
    if len(docs) > 4 or any(not 1 <= len(d) <= 4 or not d.isalnum() for d in docs):
        raise PackError('documents: up to four extensions of 1-4 letters or digits')
    for i, d in enumerate(docs):
        info[144 + 4 * i:148 + 4 * i] = d.ljust(4).encode('latin-1')
    de = text(hdr.get('description', ''), 95, 'description')
    info[160:160 + len(de)] = de

    if vlir:
        recs = [main] + list(overlays)
        table = bytearray(254)
        body = b''
        for i, r in enumerate(recs):
            if not r:
                table[2 * i], table[2 * i + 1] = 0, 0xFF
                continue
            n = blocks(len(r))
            table[2 * i], table[2 * i + 1] = n, len(r) - (n - 1) * 254 + 1
            body += r + bytes(n * 254 - len(r))
        data = bytes(table) + body
        size = 1 + 1 + sum(blocks(len(r)) for r in recs if r)      # header, table, records
    else:
        data = main
        size = 1 + blocks(len(main))

    now = datetime.datetime.now()
    entry = bytearray(30)
    entry[0] = CBM_USR
    entry[3:19] = name.ljust(16, b'\xa0')
    entry[21], entry[22] = 1 if vlir else 0, gtype
    entry[23:28] = bytes([now.year - 1900, now.month, now.day, now.hour, now.minute])
    entry[28:30] = min(size, 0xFFFF).to_bytes(2, 'little')
    block0 = bytearray(bytes(entry) + SIG.ljust(254 - 30, b'\0'))
    if tile:
        block0[TILE_AT] = tile[0]
        block0[TILE_AT + 1:TILE_AT + 129] = tile[1]
    return with_icon3(block0, bytes(info[2:256]) + data, icon3)


def icon3_bytes(path):
    """an icon source of one icon (tools/mkicons3.py) -> its 658 bytes"""
    import mkicons3
    ics = mkicons3.read(path)
    if len(ics) != 1:
        raise PackError('%s: one icon expected' % path)
    try:
        return mkicons3.pack(ics[0][2])[0]
    except ValueError as e:
        raise PackError('%s: %s' % (path, e))


def with_icon3(block0, rest, icon3):
    """the file: block0 (a bytearray), the rest, the colour icon at the end
    (V133: GEOS and the loader read the records by their table, a
    sequential file's data to the end: there it lands after the program,
    in its BSS, which the program's start clears)"""
    if icon3:
        off = 254 + len(rest)
        block0[ICON3_AT:ICON3_AT + 5] = b'I3' + off.to_bytes(3, 'little')
    return bytes(block0) + rest + (icon3 or b'')


APPL_DATA = 7


def pack_doc(name, cls, data, gtype=APPL_DATA, icon=None, version='1.0', author='', description='',
             parent='', tile=None, icon3=None):
    """a sequential GEOS document (a data file: GEOS type APPL_DATA unless
    gtype says otherwise) in CVT format: its info block's class (12
    characters + V + version), author, parent class, description; icon
    the 63 bytes of a 24 x 21 icon (vicon's) or None (Veranda's default);
    the data from byte 508 (docs/APPFORMAT.md); tile (colour, 128 bytes:
    tile_bytes's) or None"""
    nm = text(name, 16, 'name')
    if not nm or BAD_NAME & set(name):
        raise PackError('name: 1-16 characters, none of / : * ? = "')
    info = bytearray(256)
    info[0], info[1] = 0, 0xFF
    info[2], info[3], info[4] = 3, 21, 0xBF
    info[5:68] = icon if icon is not None else vicon.icon_bytes(None)
    info[68], info[69], info[70] = CBM_USR, gtype, 0
    c = text(cls, 12, 'class').ljust(12) + b'V' + text(version, 6, 'version')
    info[77:77 + len(c)] = c
    au = text(author, 19, 'author')
    info[97:97 + len(au)] = au
    pa = text(parent, 19, 'parent class')
    info[117:117 + len(pa)] = pa
    de = text(description, 95, 'description')
    info[160:160 + len(de)] = de
    if tile or icon3:
        info[137:141] = b'VRND'
        info[143] = (TILE_FLAG if tile else 0) | (ICON3_FLAG if icon3 else 0)
    now = datetime.datetime.now()
    entry = bytearray(30)
    entry[0] = CBM_USR
    entry[3:19] = nm.ljust(16, b'\xa0')
    entry[21], entry[22] = 0, gtype
    entry[23:28] = bytes([now.year - 1900, now.month, now.day, now.hour, now.minute])
    entry[28:30] = min(1 + blocks(len(data)), 0xFFFF).to_bytes(2, 'little')
    block0 = bytearray(bytes(entry) + SIG.ljust(254 - 30, b'\0'))
    if tile:
        block0[TILE_AT] = tile[0]
        block0[TILE_AT + 1:TILE_AT + 129] = tile[1]
    return with_icon3(block0, bytes(info[2:256]) + bytes(data), icon3)


def pack_doc_hdr(hdr, hdr_dir):
    """--doc: a document from its header (the keys above)"""
    if 'parent' not in hdr:
        raise PackError('no parent')
    icon = vicon.icon_bytes(os.path.join(hdr_dir, hdr['icon'])) if 'icon' in hdr else None
    tile = tile_bytes(os.path.join(hdr_dir, hdr['tile'])) if 'tile' in hdr else None
    icon3 = icon3_bytes(os.path.join(hdr_dir, hdr['icon3'])) if 'icon3' in hdr else None
    parent = text(hdr['parent'], 12, 'parent').decode('latin-1').ljust(12) + 'V1.0'
    data = (hdr['data'] + '\r\n').encode('latin-1') if hdr.get('data') else b''
    return pack_doc(hdr['name'], hdr['class'], data, icon=icon, version=hdr.get('version', '1.0'),
                    author=hdr.get('author', ''), description=hdr.get('description', ''), parent=parent, tile=tile,
                    icon3=icon3)


def add_icon3(data, icon3):
    """a CVT file with its colour icon (an old one dropped)"""
    parse(data)
    if data[ICON3_AT:ICON3_AT + 2] == b'I3' and data[395] & ICON3_FLAG:
        data = data[:int.from_bytes(data[ICON3_AT + 2:ICON3_AT + 5], 'little')]
    b0 = bytearray(data[:254])
    rest = bytearray(data[254:])
    if rest[137 - 2:141 - 2] != b'VRND':
        rest[137 - 2:141 - 2] = b'VRND'
        rest[143 - 2] = 0
    rest[143 - 2] |= ICON3_FLAG
    return with_icon3(b0, bytes(rest), icon3)


def parse(data):
    """the fields of a CVT file (raises PackError)"""
    if len(data) < 508 or SIG[:24] not in data[30:60]:
        raise PackError('not a CVT file')
    e, info = data[0:30], bytes(2) + data[254:508]
    out = {
        'name': e[3:19].rstrip(b'\xa0').decode('latin-1'),
        'cbm type': '$%02X' % e[0], 'geos type': e[22], 'structure': 'VLIR' if e[21] == 1 else 'sequential',
        'blocks': e[28] | e[29] << 8,
        'date': '%04d-%02d-%02d %02d:%02d' % (1900 + e[23], e[24], e[25], e[26], e[27]),
        'load': '$%04X' % (info[71] | info[72] << 8), 'end': '$%04X' % (info[73] | info[74] << 8),
        'start': '$%04X' % (info[75] | info[76] << 8),
        'class': info[77:97].split(b'\0')[0].decode('latin-1'),
        'author': info[97:117].split(b'\0')[0].decode('latin-1'),
        'veranda': info[137:141] == b'VRND',
        'api': info[141], 'flags': info[143], 'mode': {v: k for k, v in MODES.items()}.get(info[142], '$%02X' % info[142]),
        'description': info[160:256].split(b'\0')[0].decode('latin-1'),
        'documents': ' '.join(info[144 + 4 * i:148 + 4 * i].decode('latin-1').strip()
                              for i in range(4) if info[144 + 4 * i]),
    }
    if info[143] & TILE_FLAG:
        out['tile'] = '%s, %d ink pixels' % (TILE_COLOURS[data[TILE_AT] & 15],
                                            sum(bin(x).count('1') for x in data[TILE_AT + 1:TILE_AT + 129]))
    end = len(data)
    if info[143] & ICON3_FLAG and data[ICON3_AT:ICON3_AT + 2] == b'I3':
        off = int.from_bytes(data[ICON3_AT + 2:ICON3_AT + 5], 'little')
        if off + 658 != len(data) or not 1 <= data[off] <= 16 or data[off + 1] != 3:
            raise PackError('the colour icon at %d is not one' % off)
        out['icon3'] = '%d tiles, %d ink pixels' % (data[off], sum(bin(x).count('1') for x in data[off + 18:off + 146]))
        end = off
    if e[21] == 1:
        t, pos, recs = data[508:762], 762, []
        for i in range(127):
            n, last = t[2 * i], t[2 * i + 1]
            if n == 0 and last == 0:
                break
            if n == 0:
                recs.append(0)
                continue
            size = (n - 1) * 254 + last - 1
            if last < 2 or pos + size > len(data):
                raise PackError('record %d runs past the end' % i)
            recs.append(size)
            pos += n * 254
        out['records'] = recs
    else:
        out['size'] = end - 508
    return out


def main():
    a = sys.argv[1:]
    try:
        if len(a) == 2 and a[0] == '--list':
            for k, v in parse(open(a[1], 'rb').read()).items():
                print('%-12s %s' % (k, v))
            return
        out, load, doc = None, None, False
        while a and a[0].startswith('-'):
            if a[0] == '-o' and len(a) > 1:
                out, a = a[1], a[2:]
            elif a[0] == '--doc':
                doc, a = True, a[1:]
            elif a[0] == '--icon3' and len(a) > 2:
                cvt = add_icon3(open(a[2], 'rb').read(), icon3_bytes(a[1]))
                open(out or a[2], 'wb').write(cvt)
                return
            elif a[0] == '--load' and len(a) > 1:
                load, a = num(a[1]), a[2:]
            else:
                sys.exit(__doc__)
        if doc and len(a) == 1:
            hdr = read_hdr(a[0])
            cvt = pack_doc_hdr(hdr, os.path.dirname(os.path.abspath(a[0])))
            open(out or os.path.join(os.path.dirname(a[0]), hdr['name'] + '.cvt'), 'wb').write(cvt)
            return
        if len(a) < 2 or doc:
            sys.exit(__doc__)
        hdr = read_hdr(a[0])
        cvt = pack(hdr, os.path.dirname(os.path.abspath(a[0])), open(a[1], 'rb').read(), load,
                   [open(p, 'rb').read() for p in a[2:]])
        out = out or os.path.join(os.path.dirname(a[0]), hdr['name'] + '.cvt')
        open(out, 'wb').write(cvt)
    except (PackError, ValueError, OSError) as e:
        sys.exit('vpack: %s' % e)


if __name__ == '__main__':
    main()
