#!/usr/bin/env python3
"""C64/C128 disk images (D64, D71, D81) and their GEOS files, on the PC.

usage: vdisk.py ls <image>                 the directory, as Veranda's
                                           Archive lists and logs it
       vdisk.py get <image> <name> [<out>] one file: a GEOS file as a CVT
                                           file, a plain file as it is
       vdisk.py getall <image> <folder>    every file, named as Archive
                                           names them
       vdisk.py paint <file> <out.png>     a geoPaint document (a CVT file,
                                           or <image>:<name>) as a picture:
                                           640 x 720, the C64's colours
       vdisk.py topaint <file> <folder>    geoPaint documents, Photo Scraps
                                           and photo albums as Veranda Paint
                                           documents (CVT), as Archive
                                           converts them
       vdisk.py new <image> <disk name>    a new, empty GEOS disk (D64, D71
                                           or D81 by the extension)
       vdisk.py put <image> <file>         a CVT file onto the disk (or a
                                           plain file: --type PRG|SEQ|USR,
                                           --name NAME)

Written from the published formats (the 1541, 1571 and 1581 disk layouts;
GEOS's file headers, VLIR files, geoPaint's and the Photo Scrap's
compaction; Convert's CVT layout as docs/APPFORMAT.md gives it). MIT
licence (see LICENSE).

Names. GEOS names are ASCII; plain CBM names PETSCII. Shown: bytes $20-$7E
as they are, $C1-$DA as A-Z, anything else '?'. On the card (FAT32): the
shown name with / \\ : * ? " < > | = , made '_' (a leading $ # @ too),
trailing spaces and dots dropped; a GEOS file becomes "<name>.cvt" (the
GEOS name itself is kept inside the CVT), a plain file "<name>.PRG",
".SEQ" or ".USR". A name met before in the same image (case ignored) ends
in ~2, ~3 ...

The listing (ls; Archive's log, "ARCHIVE" before each line):
    IMAGE|<D64, D71 or D81>|<disk name>|<files>|<blocks free>
    <blocks>|<kind>|<S, V or ->|<name>|<file on the card>|<class>
"""
import os
import struct
import sys
import zlib

# ------------------------------------------------------------------ geometry


def spt1541(t):
    return 21 if t <= 17 else 19 if t <= 24 else 18 if t <= 30 else 17


class Geometry:
    def __init__(self, kind, tracks):
        self.kind, self.tracks = kind, tracks
        self.start = [0]
        for t in range(1, tracks + 1):
            self.start.append(self.start[-1] + self.spt(t))
        self.total = self.start[-1]

    def spt(self, t):
        if self.kind == 'D81':
            return 40
        if self.kind == 'D71' and t > 35:
            return spt1541(t - 35)
        return spt1541(t)

    def valid(self, t, s):
        return 1 <= t <= self.tracks and 0 <= s < self.spt(t)

    def index(self, t, s):
        if not self.valid(t, s):
            raise ImageError('a link to track %d sector %d, outside the disk' % (t, s))
        return self.start[t - 1] + s

    def header(self):
        return (40, 0) if self.kind == 'D81' else (18, 0)


SIZES = {174848: ('D64', 35), 175531: ('D64', 35), 196608: ('D64', 40), 197376: ('D64', 40),
         349696: ('D71', 70), 351062: ('D71', 70), 819200: ('D81', 80), 822400: ('D81', 80)}


class ImageError(Exception):
    pass


GEOS_TYPES = ['not GEOS', 'BASIC', 'assembly', 'data', 'system', 'desk acc', 'application',
              'document', 'font', 'printer', 'input', 'disk driver', 'boot', 'temporary',
              'auto exec', 'input 128']
CBM_TYPES = ['DEL', 'SEQ', 'PRG', 'USR', 'REL', 'CBM', 'T6', 'T7']
BAD = set('/\\:*?"<>|=,')
SIG = b'PRG formatted GEOS file V1.0'
APPL_DATA = 7


def shown(raw):
    """a name (or class) as Archive shows it"""
    out = ''
    for b in raw:
        if 0x20 <= b <= 0x7E:
            out += chr(b)
        elif 0xC1 <= b <= 0xDA:
            out += chr(b - 0x80)
        else:
            out += '?'
    return out


def fat_base(name):
    s = ''.join('_' if c in BAD else c for c in name)
    if s and s[0] in '$#@':
        s = '_' + s[1:]
    s = s.rstrip(' .')
    return s or '_'


def cstr(b):
    return b.split(b'\0')[0]


class Entry:
    def __init__(self, img, raw):
        self.raw = bytes(raw)                       # bytes 2-31 of the 32
        e = self.raw
        self.cbm = e[0]
        self.first = (e[1], e[2])
        self.rawname = e[3:19].rstrip(b'\xa0')
        self.name = shown(self.rawname)
        self.blocks = e[28] | e[29] << 8
        self.ctype = e[0] & 7
        self.info = None
        self.geos = bool(e[19]) and self.ctype in (1, 2, 3)
        if self.geos:
            try:
                self.info = img.block(e[19], e[20])
            except ImageError:
                self.geos = False
        self.vlir = self.geos and e[21] == 1
        self.gtype = e[22] if self.geos else 0
        cls = cstr(self.info[77:97]) if self.geos else b''
        self.cls = shown(cls)
        if self.geos:
            self.kind = GEOS_TYPES[self.gtype] if self.gtype < 16 else 'type %d' % self.gtype
        else:
            self.kind = CBM_TYPES[self.ctype]
        self.copyable = self.geos or self.ctype in (1, 2, 3)
        self.file = None

    def line(self):
        return '%d|%s|%s|%s|%s|%s' % (self.blocks, self.kind, 'V' if self.vlir else 'S' if self.geos else '-',
                                      self.name, self.file or '', self.cls)


class Image:
    def __init__(self, data, kind=None):
        if kind is None:
            if len(data) not in SIZES:
                raise ImageError('%d bytes: not a D64, D71 or D81 image' % len(data))
            kind, tracks = SIZES[len(data)]
        else:
            tracks = {'D64': 35, 'D71': 70, 'D81': 80}[kind]
        self.g = Geometry(kind, tracks)
        self.kind = kind
        self.d = bytearray(data[:self.g.total * 256])
        if len(self.d) < self.g.total * 256:
            self.d += bytes(self.g.total * 256 - len(self.d))

    @classmethod
    def load(cls, path):
        return cls(open(path, 'rb').read())

    def block(self, t, s):
        i = self.g.index(t, s) * 256
        return bytes(self.d[i:i + 256])

    def put(self, t, s, data):
        assert len(data) == 256
        i = self.g.index(t, s) * 256
        self.d[i:i + 256] = data

    # -------------------------------------------------------------- reading
    def disk_name(self):
        h = self.block(*self.g.header())
        return shown((h[4:20] if self.kind == 'D81' else h[0x90:0xA0]).rstrip(b'\xa0'))

    def free(self):
        n = 0
        if self.kind == 'D81':
            for t in range(1, 81):
                if t != 40:
                    b = self.block(40, 1 if t <= 40 else 2)
                    n += b[0x10 + 6 * ((t - 1) % 40)]
            return n
        b = self.block(18, 0)
        for t in range(1, 36):
            if t != 18:
                n += b[4 * t]
        if self.kind == 'D71':
            for t in range(36, 71):
                if t != 53:
                    n += b[0xDD + t - 36]
        return n

    def dir_blocks(self):
        h = self.block(*self.g.header())
        t, s = h[0], h[1]
        seen = set()
        while t:
            if (t, s) in seen or len(seen) > 64:
                raise ImageError('the directory runs in a loop')
            seen.add((t, s))
            b = self.block(t, s)
            yield b
            t, s = b[0], b[1]

    def entries(self):
        out, names = [], set()
        for b in self.dir_blocks():
            for i in range(8):
                raw = b[i * 32 + 2:i * 32 + 32]
                if raw[0] == 0:
                    continue
                e = Entry(self, raw)
                out.append(e)
                if e.copyable:
                    e.file = unique(names, fat_base(e.name), e)
        return out

    def chain(self, t, s):
        """the data of a chain of blocks; the number of blocks"""
        out, n = bytearray(), 0
        while True:
            n += 1
            if n > self.g.total:
                raise ImageError('a chain of blocks runs in a loop')
            b = self.block(t, s)
            if b[0] == 0:
                if b[1] < 1:
                    raise ImageError('a last block with %d bytes' % (b[1] - 1))
                out += b[2:b[1] + 1]
                return bytes(out), n, b[1]
            out += b[2:]
            t, s = b[0], b[1]

    def records(self, e):
        """a VLIR file's records: data, or None for an empty one"""
        idx = self.block(*e.first)
        recs = []
        for i in range(127):
            t, s = idx[2 + 2 * i], idx[3 + 2 * i]
            if t == 0 and s == 0:
                break
            recs.append(None if t == 0 else self.chain(t, s)[0])
        return recs

    def data(self, e):
        return self.chain(*e.first)[0]

    def cvt(self, e):
        """a GEOS file as Veranda's CVT bytes (docs/APPFORMAT.md)"""
        entry = bytearray(e.raw)
        entry[1] = entry[2] = 0
        entry[19] = entry[20] = 0
        out = bytes(entry) + SIG.ljust(224, b'\0') + e.info[2:256]
        if not e.vlir:
            return out + self.data(e)
        idx = self.block(*e.first)
        table, body = bytearray(254), bytearray()
        for i in range(127):
            t, s = idx[2 + 2 * i], idx[3 + 2 * i]
            if t == 0:
                table[2 * i], table[2 * i + 1] = 0, s
                continue
            data, n, last = self.chain(t, s)
            table[2 * i], table[2 * i + 1] = n, last
            body += data + bytes(n * 254 - len(data))
        return out + bytes(table) + bytes(body)

    def extract(self, e):
        return self.cvt(e) if e.geos else self.data(e)

    def find(self, name):
        for e in self.entries():
            if name in (e.name, e.file, shown(e.rawname)):
                return e
        raise ImageError('no file %r on the disk' % name)

    def listing(self):
        es = self.entries()
        lines = ['IMAGE|%s|%s|%d|%d' % (self.kind, self.disk_name(), len(es), self.free())]
        return lines + [e.line() for e in es], es

    # -------------------------------------------------------------- writing
    def format(self, name, disk_id=b'vd'):
        self.d = bytearray(self.g.total * 256)
        self.used = set()
        nm = name.encode('latin-1')[:16].ljust(16, b'\xa0')
        if self.kind == 'D81':
            h = bytearray(256)
            h[0], h[1], h[2] = 40, 3, 0x44
            h[4:20] = nm
            h[0x14:0x16] = b'\xa0\xa0'
            h[0x16:0x18] = disk_id[:2]
            h[0x18], h[0x19], h[0x1A] = 0xA0, 0x33, 0x44
            h[0x1B:0x1D] = b'\xa0\xa0'
            self.put(40, 0, h)
            for s in (0, 1, 2, 3):
                self.used.add((40, s))
            d = bytearray(256)
            d[1] = 0xFF
            self.put(40, 3, d)
        else:
            h = bytearray(256)
            h[0], h[1], h[2] = 18, 1, 0x41
            h[0x90:0xA0] = nm
            h[0xA0:0xA2] = b'\xa0\xa0'
            h[0xA2:0xA4] = disk_id[:2]
            h[0xA4], h[0xA5], h[0xA6] = 0xA0, 0x32, 0x41
            h[0xA7:0xAB] = b'\xa0' * 4
            if self.kind == 'D71':
                h[3] = 0x80
            self.put(18, 0, h)
            self.used |= {(18, 0), (18, 1)}
            if self.kind == 'D71':
                self.used |= {(53, s) for s in range(self.g.spt(53))}
            d = bytearray(256)
            d[1] = 0xFF
            self.put(18, 1, d)
        # a GEOS disk: the border block, and the ID in the header
        bt = 19 if self.kind != 'D81' else 41
        self.used.add((bt, 0))
        bb = bytearray(256)
        bb[1] = 0xFF
        self.put(bt, 0, bb)
        h = bytearray(self.block(*self.g.header()))
        h[0xAB], h[0xAC] = bt, 0
        h[0xAD:0xBD] = b'GEOS format V1.0'
        self.put(*self.g.header(), h)
        self.write_bam()

    def dirtrack(self):
        return 40 if self.kind == 'D81' else 18

    def write_bam(self):
        if self.kind == 'D81':
            for half, s in ((0, 1), (1, 2)):
                b = bytearray(self.block(40, s))
                b[0], b[1] = (40, 2) if s == 1 else (0, 0xFF)
                b[2], b[3], b[4], b[5], b[6], b[7] = 0x44, 0xBB, 0x76, 0x64, 0xC0, 0
                for k in range(40):
                    t = half * 40 + k + 1
                    bits = sum(1 << sec for sec in range(40) if (t, sec) not in self.used)
                    b[0x10 + 6 * k] = bin(bits).count('1')
                    b[0x11 + 6 * k:0x16 + 6 * k] = bits.to_bytes(5, 'little')
                self.put(40, s, b)
            return
        b = bytearray(self.block(18, 0))
        for t in range(1, 36):
            n = self.g.spt(t)
            bits = sum(1 << sec for sec in range(n) if (t, sec) not in self.used)
            b[4 * t] = bin(bits).count('1')
            b[4 * t + 1:4 * t + 4] = bits.to_bytes(3, 'little')
        if self.kind == 'D71':
            b2 = bytearray(256)
            for t in range(36, 71):
                n = self.g.spt(t)
                bits = sum(1 << sec for sec in range(n) if (t, sec) not in self.used)
                b[0xDD + t - 36] = bin(bits).count('1')
                b2[3 * (t - 36):3 * (t - 36) + 3] = bits.to_bytes(3, 'little')
            self.put(53, 0, b2)
        self.put(18, 0, b)

    def alloc(self, near):
        """the next free block: interleave 10 on a 1541/1571 disk, 1 on a 1581,
        tracks outwards from the directory"""
        il = 1 if self.kind == 'D81' else 10
        dt = self.dirtrack()
        t, s = near
        tracks = sorted((x for x in range(1, self.g.tracks + 1) if x != dt and not (self.kind == 'D71' and x == 53)),
                        key=lambda x: (abs(x - t) if t else 0, abs(x - dt), x))
        if t and t != dt:
            n = self.g.spt(t)
            for k in range(n):
                c = (s + il + k) % n
                if (t, c) not in self.used:
                    self.used.add((t, c))
                    return t, c
        for x in tracks:
            for c in range(self.g.spt(x)):
                if (x, c) not in self.used:
                    self.used.add((x, c))
                    return x, c
        raise ImageError('the disk is full')

    def write_chain(self, data, near=(0, 0)):
        chunks = [data[i:i + 254] for i in range(0, len(data), 254)] or [b'']
        blocks = []
        for _ in chunks:
            near = self.alloc(near)
            blocks.append(near)
        for i, c in enumerate(chunks):
            b = bytearray(256)
            if i + 1 < len(chunks):
                b[0], b[1] = blocks[i + 1]
            else:
                b[0], b[1] = 0, len(c) + 1
            b[2:2 + len(c)] = c
            self.put(*blocks[i], b)
        return blocks

    def add_entry(self, e):
        dt = self.dirtrack()
        blocks = list(self.dir_chain())
        for (t, s) in blocks:
            b = bytearray(self.block(t, s))
            for i in range(8):
                if b[i * 32 + 2] == 0:
                    b[i * 32 + 2:i * 32 + 32] = e
                    self.put(t, s, b)
                    return
        lt, ls = blocks[-1]
        n = self.g.spt(dt)
        step = 1 if self.kind == 'D81' else 3
        for k in range(1, n):
            s = (ls + step * k) % n
            if (dt, s) not in self.used:
                break
        else:
            raise ImageError('the directory is full')
        self.used.add((dt, s))
        d = bytearray(256)
        d[1] = 0xFF
        d[2:32] = e
        self.put(dt, s, d)
        b = bytearray(self.block(lt, ls))
        b[0], b[1] = dt, s
        self.put(lt, ls, b)

    def dir_chain(self):
        h = self.block(*self.g.header())
        t, s = h[0], h[1]
        while t:
            yield t, s
            t, s = self.block(t, s)[:2]

    def add_cvt(self, cvt):
        """a GEOS file from its CVT bytes"""
        if len(cvt) < 508 or cvt[30:30 + len(SIG) - 4] != SIG[:-4]:
            raise ImageError('not a CVT file')
        e = bytearray(cvt[:30])
        info = bytearray(2) + cvt[254:508]
        info[0], info[1] = 0, 0xFF
        ht, hs = self.alloc((0, 0))
        self.put(ht, hs, bytes(info))
        n = 1
        if e[21] == 1:
            table = cvt[508:762]
            pos = 762
            idx = bytearray(256)
            idx[1] = 0xFF
            it, is_ = self.alloc((ht, hs))
            n += 1
            near = (it, is_)
            for i in range(127):
                c, last = table[2 * i], table[2 * i + 1]
                if c == 0:
                    idx[2 + 2 * i], idx[3 + 2 * i] = 0, last
                    continue
                size = (c - 1) * 254 + last - 1
                blocks = self.write_chain(cvt[pos:pos + size], near)
                near = blocks[-1]
                pos += c * 254
                idx[2 + 2 * i], idx[3 + 2 * i] = blocks[0]
                n += len(blocks)
            self.put(it, is_, bytes(idx))
            first = (it, is_)
        else:
            blocks = self.write_chain(cvt[508:], (ht, hs))
            n += len(blocks)
            first = blocks[0]
        e[1], e[2] = first
        e[19], e[20] = ht, hs
        e[28], e[29] = n & 255, n >> 8
        self.add_entry(bytes(e))
        self.write_bam()

    def add_plain(self, name, data, ctype):
        blocks = self.write_chain(data)
        e = bytearray(30)
        e[0] = 0x80 | CBM_TYPES.index(ctype)
        e[1], e[2] = blocks[0]
        nm = name if isinstance(name, bytes) else name.encode('latin-1')
        e[3:19] = nm[:16].ljust(16, b'\xa0')
        e[28], e[29] = len(blocks) & 255, len(blocks) >> 8
        self.add_entry(bytes(e))
        self.write_bam()


def unique(names, base, e):
    ext = '.cvt' if e.geos else '.' + CBM_TYPES[e.ctype]
    base = base[:16]
    k = 1
    b = base
    while (b + ext).lower() in names:
        k += 1
        b = base[:16 - 1 - len(str(k))] + '~' + str(k)
    names.add((b + ext).lower())
    return b + ext


# ---------------------------------------------------------------- CVT files


def parse_cvt(data):
    """(entry, info block (256), sequential data or a list of records)"""
    if len(data) < 508 or data[30:54] != SIG[:24]:
        raise ImageError('not a CVT file')
    e = data[:30]
    info = bytes(2) + data[254:508]
    if e[21] != 1:
        return e, info, data[508:]
    t, pos, recs = data[508:762], 762, []
    for i in range(127):
        n, last = t[2 * i], t[2 * i + 1]
        if n == 0 and last == 0:
            break
        if n == 0:
            recs.append(None)
            continue
        size = (n - 1) * 254 + last - 1
        recs.append(data[pos:pos + size])
        pos += n * 254
    return e, info, recs


def make_cvt(name, gtype, cls, recs=None, data=None, author=b'', parent=b'', info_txt=b'', icon=None,
             cbm=0x83, date=(126, 11, 16, 12, 0), extra=None):
    """a CVT file from parts (the fixtures; Paint documents)"""
    info = bytearray(256)
    info[0], info[1] = 0, 0xFF
    info[2], info[3], info[4] = 3, 21, 0xBF
    info[5:68] = icon if icon else bytes(63)
    info[68], info[69], info[70] = cbm, gtype, 1 if recs is not None else 0
    cls = cls if isinstance(cls, bytes) else cls.encode('latin-1')
    info[77:77 + len(cls)] = cls
    info[97:97 + len(author)] = author
    info[117:117 + len(parent)] = parent
    if extra:
        for off, b in extra.items():
            info[off:off + len(b)] = b
    info[160:160 + len(info_txt)] = info_txt
    e = bytearray(30)
    e[0] = cbm
    nm = name if isinstance(name, bytes) else name.encode('latin-1')
    e[3:19] = nm[:16].ljust(16, b'\xa0')
    e[21], e[22] = 1 if recs is not None else 0, gtype
    e[23:28] = bytes(date)
    if recs is None:
        body = data
        size = 1 + -(-len(data) // 254)
    else:
        table, rb = bytearray(254), bytearray()
        size = 2
        for i, r in enumerate(recs):
            if r is None:
                table[2 * i], table[2 * i + 1] = 0, 0xFF
                continue
            n = max(1, -(-len(r) // 254))
            table[2 * i], table[2 * i + 1] = n, len(r) - (n - 1) * 254 + 1
            rb += r + bytes(n * 254 - len(r))
            size += n
        body = bytes(table) + bytes(rb)
    e[28], e[29] = size & 255, size >> 8
    return bytes(e) + SIG.ljust(224, b'\0') + bytes(info[2:]) + body


# ------------------------------------------------------------------ pictures

C64 = [(0, 0, 0), (255, 255, 255), (136, 0, 0), (170, 255, 238), (204, 68, 204), (0, 204, 85),
       (0, 0, 170), (238, 238, 119), (221, 136, 85), (102, 68, 0), (255, 119, 119), (51, 51, 51),
       (119, 119, 119), (170, 255, 102), (0, 136, 255), (187, 187, 187)]
PAGE_W, PAGE_H = 640, 720
REC_LEN = 1448                  # a geoPaint record unpacked: 1280 + 8 + 160


def geopaint_unpack(d):
    """a geoPaint record: 1280 bytes of bitmap (two card rows of 80 cards,
    8 bytes a card), 8 unused, 160 colour bytes (a card's ink in the high
    nibble, its paper in the low one). Codes: 1-63 that many bytes follow;
    64-127 the next 8 bytes (a card) repeated n - 64 times; 128-255 the
    next byte repeated n - 128 times; 0 nothing."""
    out = bytearray()
    i = 0
    while i < len(d) and len(out) < REC_LEN:
        c = d[i]
        i += 1
        if c < 64:
            out += d[i:i + c]
            i += c
        elif c < 128:
            out += d[i:i + 8] * (c - 64)
            i += 8
        else:
            out += bytes([d[i] if i < len(d) else 0]) * (c - 128)
            i += 1
    out = out[:REC_LEN]
    return bytes(out) + bytes(REC_LEN - len(out))


def geopaint_pack(raw):
    """the fixtures' encoder: runs of a byte, repeated cards, literals"""
    out = bytearray()
    i, lit = 0, bytearray()

    def flush():
        nonlocal lit
        while lit:
            out.append(min(63, len(lit)))
            out.extend(lit[:63])
            lit = lit[63:]
    while i < len(raw):
        j = i
        while j < len(raw) and raw[j] == raw[i] and j - i < 127:
            j += 1
        if j - i >= 4:
            flush()
            out += bytes([128 + j - i, raw[i]])
            i = j
            continue
        if i % 8 == 0 and i + 16 <= len(raw) and raw[i:i + 8] == raw[i + 8:i + 16] and i < 1280:
            k = i + 8
            while k + 8 <= min(len(raw), 1280) and raw[k:k + 8] == raw[i:i + 8] and (k - i) // 8 < 63:
                k += 8
            flush()
            out += bytes([64 + (k - i) // 8]) + raw[i:i + 8]
            i = k
            continue
        lit.append(raw[i])
        i += 1
    flush()
    return bytes(out)


def geopaint_page(recs):
    """(bits, colours): bits[y][x] 0/1 for 640 x 720; colours[cy][cx] bytes"""
    bits = [[0] * PAGE_W for _ in range(PAGE_H)]
    cols = [[0] * 80 for _ in range(90)]
    for r in range(45):
        rec = recs[r] if r < len(recs) else None
        if rec is None:
            continue
        u = geopaint_unpack(rec)
        for half in range(2):
            for cx in range(80):
                card = u[half * 640 + cx * 8:half * 640 + cx * 8 + 8]
                for row in range(8):
                    v = card[row]
                    y = r * 16 + half * 8 + row
                    for b in range(8):
                        bits[y][cx * 8 + b] = v >> (7 - b) & 1
                cols[r * 2 + half][cx] = u[1288 + half * 80 + cx]
    return bits, cols


def bitmap_unpack(d, n):
    """GEOS's compacted bitmap (BitmapUp): count < $80 the next byte count
    times; $80-$DB count - $80 bytes follow; $DC + n a pattern of n bytes
    (compacted itself) follows its repeat count. n bytes out; the input
    used."""
    out = bytearray()
    i = 0

    def simple(d, i, out, limit):
        c = d[i]
        i += 1
        if c < 0x80:
            out += bytes([d[i]]) * c
            return i + 1
        k = c - 0x80
        out += d[i:i + k]
        return i + k
    while len(out) < n:
        if i >= len(d):
            raise ImageError('the bitmap ends early')
        c = d[i]
        if c >= 0xDC:
            plen, rep = c - 0xDC, d[i + 1]
            pat = d[i + 2:i + 2 + plen]
            p = bytearray()
            j = 0
            while j < len(pat):
                j = simple(pat, j, p, None)
            out += bytes(p) * rep
            i += 2 + plen
        else:
            i = simple(d, i, out, None)
    return bytes(out[:n]), i


def bitmap_pack(raw):
    """the fixtures' encoder (no patterns)"""
    out = bytearray()
    i, lit = 0, bytearray()

    def flush():
        nonlocal lit
        while lit:
            out.append(0x80 + min(91, len(lit)))
            out.extend(lit[:91])
            lit = lit[91:]
    while i < len(raw):
        j = i
        while j < len(raw) and raw[j] == raw[i] and j - i < 127:
            j += 1
        if j - i >= 3:
            flush()
            out += bytes([j - i, raw[i]])
            i = j
        else:
            lit.append(raw[i])
            i += 1
    flush()
    return bytes(out)


def scrap_bits(d):
    """a Photo Scrap: width (cards), height (rows, a word), the compacted
    bitmap; bits[y][x]"""
    if len(d) < 3:
        raise ImageError('a Photo Scrap of %d bytes' % len(d))
    w, h = d[0], d[1] | d[2] << 8
    raw, _ = bitmap_unpack(d[3:], w * h)
    return [[raw[y * w + x // 8] >> (7 - x % 8) & 1 for x in range(w * 8)] for y in range(h)]


# Veranda Paint documents (apps/paint/paint.c): version 3
P_BYTES, P_ROWS, P_BANDS = 74, 16, 29
P_W, P_H = P_BYTES * 8, P_ROWS * P_BANDS          # 592 x 464
P_MW, P_MH = 74, 58


def packbits(band):
    out = bytearray()
    i = 0
    n = len(band)
    while i < n:
        c = band[i]
        j = i + 1
        while j < n and j - i < 128 and band[j] == c:
            j += 1
        if j - i >= 3:
            out += bytes([257 - (j - i), c])
            i = j
            continue
        j = i
        while j < n and j - i < 128:
            if j + 2 < n and band[j] == band[j + 1] == band[j + 2]:
                break
            j += 1
        out.append(j - i - 1)
        out += band[i:j]
        i = j
    return bytes(out)


def unpackbits(d, n):
    out = bytearray()
    i = 0
    while i < len(d):
        c = d[i]
        i += 1
        if c < 128:
            out += d[i:i + c + 1]
            i += c + 1
        elif c > 128:
            out += bytes([d[i]]) * (257 - c)
            i += 1
    if len(out) != n:
        raise ImageError('a Paint band unpacks to %d bytes' % len(out))
    return bytes(out)


def paper(c):
    """a C64 colour as a Paint card colour: white the normal paper (0),
    black the ink's cell (1), the others VERA's palette entry, the same"""
    return 0 if c == 1 else 1 if c == 0 else c


def ink_of(c):
    return 1 if c < 2 else c


def paint_doc(bits, cmap, ink):
    """Paint's records from 592 x 464 bits and 58 x 74 card colours"""
    recs = [b'VPNT' + bytes([3, P_BYTES, P_ROWS, P_BANDS, ink])]
    for b in range(P_BANDS):
        band = bytearray()
        for y in range(b * P_ROWS, b * P_ROWS + P_ROWS):
            row = bits[y]
            for x in range(P_BYTES):
                v = 0
                for k in range(8):
                    v = v << 1 | row[x * 8 + k]
                band.append(v)
        recs.append(packbits(bytes(band)))
    for half in range(2):
        m = bytearray()
        for r in range(29):
            row = cmap[half * 29 + r]
            for cx in range(0, P_MW, 2):
                m.append(row[cx] << 4 | row[cx + 1])
        recs.append(bytes(m))
    return recs


def paint_cvt(name, recs):
    icon = bytearray(63)
    for i in range(21):
        if i in (0, 20):
            icon[i * 3:i * 3 + 3] = b'\x7f\xff\xfe'
        else:
            icon[i * 3:i * 3 + 3] = b'\x40\x00\x02'
    for i in range(4, 17):
        icon[i * 3 + (i + 2) // 8] |= 0x80 >> ((i + 2) & 7)
    return make_cvt(name, APPL_DATA, b'Paint Image V1.0', recs=recs, author=b'Veranda',
                    parent=b'Paint       V1.0', info_txt=b'A picture from Paint.', icon=bytes(icon))


def paint_decode(cvt):
    """(bits 592 x 464, map 58 x 74, ink) of a Paint document (CVT)"""
    e, info, recs = parse_cvt(cvt)
    h = recs[0]
    if h[:4] != b'VPNT' or h[5:8] != bytes([P_BYTES, P_ROWS, P_BANDS]):
        raise ImageError('not a Paint document')
    ver = h[4]
    ink = h[8] if ver == 3 else 1
    bits = []
    for b in range(P_BANDS):
        band = unpackbits(recs[1 + b], P_BYTES * P_ROWS)
        for r in range(P_ROWS):
            row = band[r * P_BYTES:(r + 1) * P_BYTES]
            bits.append([row[x // 8] >> (7 - x % 8) & 1 for x in range(P_W)])
    cmap = [[0] * P_MW for _ in range(P_MH)]
    if ver >= 2:
        for half in range(2):
            m = recs[1 + P_BANDS + half]
            for r in range(29):
                for cx in range(P_MW):
                    v = m[r * 37 + cx // 2]
                    cmap[half * 29 + r][cx] = v & 15 if cx & 1 else v >> 4
    return bits, cmap, ink


def blank_bits():
    return [[0] * P_W for _ in range(P_H)]


def geopaint_to_paint(recs):
    """a geoPaint page as Paint documents: part 1 its records 0-28 (rows
    0-463), part 2 records 29-44 (rows 464-719; only if one of them is
    there); the left 592 of the 640 columns. Each card's paper from its
    colour byte; the ink the most common ink of the cards with ink in
    them (the lowest colour of a tie)."""
    bits, cols = geopaint_page(recs)
    parts = []
    for p in range(2):
        r0 = 29 * p
        if p == 1 and not any(recs[r] is not None for r in range(29, min(45, len(recs)))):
            break
        pb, cm = blank_bits(), [[0] * P_MW for _ in range(P_MH)]
        count = [0] * 16
        for y in range(P_H):
            py = r0 * 16 + y
            if py < PAGE_H:
                pb[y] = bits[py][:P_W]
        for cy in range(P_MH):
            pcy = r0 * 2 + cy
            if pcy >= 90:
                break
            for cx in range(P_MW):
                rec = pcy // 2
                if rec >= len(recs) or recs[rec] is None:
                    continue
                c = cols[pcy][cx]
                cm[cy][cx] = paper(c & 15)
                if any(any(bits[pcy * 8 + k][cx * 8:cx * 8 + 8]) for k in range(8)):
                    count[c >> 4] += 1
        best = max(range(16), key=lambda c: (count[c], -c))
        ink = ink_of(best) if count[best] else 1
        parts.append(paint_doc(pb, cm, ink))
    return parts


def scrap_to_paint(d):
    s = scrap_bits(d)
    pb = blank_bits()
    for y in range(min(P_H, len(s))):
        row = s[y][:P_W]
        pb[y][:len(row)] = row
    return paint_doc(pb, [[0] * P_MW for _ in range(P_MH)], 1)


def classify(cls, recs_or_data, vlir):
    c = cls.lower()
    if vlir and c.startswith('paint image'):
        r0 = recs_or_data[0] if recs_or_data else None
        if r0 is not None and r0[:4] == b'VPNT':
            return None
        return 'geopaint'
    if not vlir and c.startswith('photo scrap'):
        return 'scrap'
    if vlir and c.startswith('photo album'):
        return 'album'
    return None


def part_name(base, n):
    s = ' %d' % n
    return base[:16 - len(s)] + s


def to_paint(name, cls, vlir, content):
    """[(GEOS name, records)] for a picture, as Archive converts it"""
    kind = classify(cls, content, vlir)
    base = fat_base(name)
    if kind == 'geopaint':
        return [(part_name(base, i + 1), r) for i, r in enumerate(geopaint_to_paint(content))]
    if kind == 'scrap':
        return [(part_name(base, 1), scrap_to_paint(content))]
    if kind == 'album':
        out = []
        for i, r in enumerate(content):
            if r is None:
                continue
            try:
                out.append((part_name(base, i + 1), scrap_to_paint(r)))
            except (ImageError, IndexError):
                pass
        return out
    raise ImageError('%s: not a geoPaint document, Photo Scrap or photo album' % name)


def write_png(path, rows):
    w, h = len(rows[0]), len(rows)
    raw = b''.join(b'\0' + bytes(v for px in r for v in px) for r in rows)

    def chunk(t, d):
        c = t + d
        return struct.pack('>I', len(d)) + c + struct.pack('>I', zlib.crc32(c) & 0xFFFFFFFF)
    png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
    png += chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b'')
    open(path, 'wb').write(png)


def geopaint_png(recs, path):
    bits, cols = geopaint_page(recs)
    rows = []
    for y in range(PAGE_H):
        row = []
        for x in range(PAGE_W):
            c = cols[y // 8][x // 8]
            if y // 16 >= len(recs) or recs[y // 16] is None:
                c = 0x01
            row.append(C64[c >> 4] if bits[y][x] else C64[c & 15])
        rows.append(row)
    write_png(path, rows)


# ----------------------------------------------------------------------- main


def load_file(spec):
    """a CVT file, or <image>:<name>: (name, class, vlir, records or data)"""
    if os.path.isfile(spec):
        data = open(spec, 'rb').read()
        e, info, content = parse_cvt(data)
        return shown(e[3:19].rstrip(b'\xa0')), shown(cstr(info[77:97])), e[21] == 1, content
    img, _, name = spec.rpartition(':')
    im = Image.load(img)
    e = im.find(name)
    if not e.geos:
        raise ImageError('%s is not a GEOS file' % name)
    return e.name, e.cls, e.vlir, im.records(e) if e.vlir else im.data(e)


def main():
    a = sys.argv[1:]
    try:
        if len(a) == 2 and a[0] == 'ls':
            lines, _ = Image.load(a[1]).listing()
            print('\n'.join(lines))
        elif len(a) in (3, 4) and a[0] == 'get':
            im = Image.load(a[1])
            e = im.find(a[2])
            if not e.copyable:
                raise ImageError('%s: a %s file is not copied' % (a[2], e.kind))
            open(a[3] if len(a) == 4 else e.file, 'wb').write(im.extract(e))
        elif len(a) == 3 and a[0] == 'getall':
            im = Image.load(a[1])
            os.makedirs(a[2], exist_ok=True)
            for e in im.entries():
                if e.copyable:
                    open(os.path.join(a[2], e.file), 'wb').write(im.extract(e))
                    print(e.file)
        elif len(a) == 3 and a[0] == 'paint':
            name, cls, vlir, recs = load_file(a[1])
            if classify(cls, recs, vlir) != 'geopaint':
                raise ImageError('%s is not a geoPaint document (class %s)' % (name, cls))
            geopaint_png(recs, a[2])
        elif len(a) == 3 and a[0] == 'topaint':
            name, cls, vlir, content = load_file(a[1])
            os.makedirs(a[2], exist_ok=True)
            for n, recs in to_paint(name, cls, vlir, content):
                open(os.path.join(a[2], n + '.cvt'), 'wb').write(paint_cvt(n, recs))
                print(n + '.cvt')
        elif len(a) == 3 and a[0] == 'new':
            kind = os.path.splitext(a[1])[1][1:].upper()
            if kind not in ('D64', 'D71', 'D81'):
                raise ImageError('the image name ends in .d64, .d71 or .d81')
            im = Image(b'', kind)
            im.format(a[2])
            open(a[1], 'wb').write(im.d)
        elif len(a) >= 3 and a[0] == 'put':
            im = Image.load(a[1])
            im.used = set()
            reload_used(im)
            data = open(a[2], 'rb').read()
            opts = dict(zip(a[3::2], a[4::2]))
            if '--type' in opts:
                im.add_plain(opts.get('--name', os.path.basename(a[2]).upper()), data, opts['--type'].upper())
            else:
                im.add_cvt(data)
            open(a[1], 'wb').write(im.d)
        else:
            sys.exit(__doc__)
    except (ImageError, OSError, IndexError, KeyError) as x:
        sys.exit('vdisk: %s' % x)


def reload_used(im):
    """the used blocks, from the BAM"""
    g = im.g
    if im.kind == 'D81':
        for t in range(1, 81):
            b = im.block(40, 1 if t <= 40 else 2)
            bits = int.from_bytes(b[0x11 + 6 * ((t - 1) % 40):0x16 + 6 * ((t - 1) % 40)], 'little')
            for s in range(40):
                if not bits >> s & 1:
                    im.used.add((t, s))
        return
    b = im.block(18, 0)
    for t in range(1, 36):
        bits = int.from_bytes(b[4 * t + 1:4 * t + 4], 'little')
        for s in range(g.spt(t)):
            if not bits >> s & 1:
                im.used.add((t, s))
    if im.kind == 'D71':
        b2 = im.block(53, 0)
        for t in range(36, 71):
            bits = int.from_bytes(b2[3 * (t - 36):3 * (t - 36) + 3], 'little')
            for s in range(g.spt(t)):
                if not bits >> s & 1:
                    im.used.add((t, s))


if __name__ == '__main__':
    main()
