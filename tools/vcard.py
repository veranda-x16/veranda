#!/usr/bin/env python3
"""SD card images (FAT32) for the X16 emulator's -sdcard, without mtools.

usage: vcard.py make [--mb N] [--cluster-kb K] <sd.img> <folder>
                                    a new image (MBR, one FAT32 partition;
                                    default 2048 MB, 32 KB clusters, sparse on
                                    the host) with the folder's files and
                                    subdirectories, long names kept
       vcard.py add <sd.img> <file> [<dir/in/image>]
                                    one more file (into an existing directory)
       vcard.py ls <sd.img>         every file: path and size
       vcard.py free <sd.img>       the free bytes (FSInfo's count)
       vcard.py get <sd.img> <path> <out>
                                    copy a file out (long or short name)

The file system is made by sfdisk and mkfs.fat (a standard layout); files
are written in one run of clusters each; reading follows the FAT chain, so
files the X16 wrote are read correctly. Names are stored as an 8.3 name
plus long name entries (VFAT); directory names likewise.
(Adapted from the old project's tools/x16/fat32.py.)
"""
import os
import struct
import subprocess
import sys
import time

SIZE_MB = 2048
CLUSTER_KB = 32
PART_START = 2048                         # sectors
EOC = 0x0FFFFFFF
LFN_OFFS = [1, 3, 5, 7, 9, 14, 16, 18, 20, 22, 24, 28, 30]
SHORT_OK = set('ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!#$%&\'()-@^_`{}~')


def lfn_sum(short):
    s = 0
    for b in short:
        s = (((s & 1) << 7) + (s >> 1) + b) & 0xFF
    return s


class Fat32:
    def __init__(self, path):
        self.f = open(path, 'r+b')
        mbr = self.read(0, 512)
        if mbr[510:512] != b'\x55\xaa':
            raise ValueError('no MBR')
        self.part = struct.unpack_from('<I', mbr, 446 + 8)[0] * 512
        bpb = self.read(self.part, 512)
        self.bps = struct.unpack_from('<H', bpb, 11)[0]
        self.spc = bpb[13]
        self.reserved = struct.unpack_from('<H', bpb, 14)[0]
        self.nfats = bpb[16]
        self.fatsz = struct.unpack_from('<I', bpb, 36)[0]
        self.root = struct.unpack_from('<I', bpb, 44)[0]
        self.fsinfo = struct.unpack_from('<H', bpb, 48)[0]
        self.fat0 = self.part + self.reserved * self.bps
        self.data0 = self.fat0 + self.nfats * self.fatsz * self.bps
        self.csize = self.spc * self.bps
        self.nclusters = self.fatsz * self.bps // 4
        tot = struct.unpack_from('<I', bpb, 32)[0]
        self.ndata = (tot - (self.data0 - self.part) // self.bps) // self.spc   # data clusters
        self.next_free = 2

    def read(self, off, n):
        self.f.seek(off)
        return self.f.read(n)

    def write(self, off, data):
        self.f.seek(off)
        self.f.write(data)

    def fat(self, c):
        return struct.unpack('<I', self.read(self.fat0 + 4 * c, 4))[0] & 0x0FFFFFFF

    def set_fat(self, c, v):
        for i in range(self.nfats):
            self.write(self.fat0 + i * self.fatsz * self.bps + 4 * c, struct.pack('<I', v))

    def cluster(self, c):
        return self.data0 + (c - 2) * self.csize

    def chain(self, c):
        out = []
        while 2 <= c < 0x0FFFFFF8:
            out.append(c)
            c = self.fat(c)
        return out

    def alloc(self, n):
        """n clusters in one run, chained"""
        start, run = None, 0
        for c in range(self.next_free, self.nclusters):
            if self.fat(c) == 0:
                if run == 0:
                    start = c
                run += 1
                if run == n:
                    break
            else:
                run = 0
        else:
            raise RuntimeError('no room')
        for i in range(n):
            self.set_fat(start + i, start + i + 1 if i + 1 < n else EOC)
        self.next_free = start + n
        return start

    def write_data(self, data):
        if not data:
            return 0
        n = -(-len(data) // self.csize)
        start = self.alloc(n)
        for i in range(n):
            chunk = data[i * self.csize:(i + 1) * self.csize]
            self.write(self.cluster(start + i), chunk + bytes(self.csize - len(chunk)))
        return start

    # --- directories -------------------------------------------------
    def entries(self, dirc):
        """(offset, 32 bytes) of every slot of directory cluster chain dirc"""
        for c in self.chain(dirc):
            for i in range(self.csize // 32):
                off = self.cluster(c) + 32 * i
                yield off, self.read(off, 32)

    def listdir(self, dirc):
        """[(long name, entry 32 bytes)]"""
        out, parts = [], []
        for _, e in self.entries(dirc):
            if e[0] == 0:
                break
            if e[0] == 0xE5:
                parts = []
                continue
            if e[11] == 0x0F:
                s = b''.join(e[o:o + 2] for o in LFN_OFFS).decode('utf-16-le', 'replace')
                parts.insert(0, s.split('\0')[0].rstrip('￿'))
                continue
            if e[11] & 0x08:
                parts = []
                continue
            if parts:
                name = ''.join(parts)
            else:
                base, ext = e[0:8].decode('latin-1').rstrip(), e[8:11].decode('latin-1').rstrip()
                name = base + ('.' + ext if ext else '')
            parts = []
            out.append((name, e))
        return out

    def free_slots(self, dirc, n):
        """offsets of n consecutive free slots (the directory grows if needed)"""
        run = []
        for off, e in self.entries(dirc):
            if e[0] in (0, 0xE5):
                run.append(off)
                if len(run) == n:
                    return run
            else:
                run = []
        last = self.chain(dirc)[-1]
        new = self.alloc(1)
        self.set_fat(last, new)
        self.write(self.cluster(new), bytes(self.csize))
        return self.free_slots(dirc, n)

    def short_name(self, dirc, name):
        taken = {e[0:11] for _, e in self.listdir(dirc)}
        base, _, ext = name.rpartition('.') if '.' in name.lstrip('.') else (name, '', '')
        clean = lambda s: ''.join(ch if ch in SHORT_OK else '_' for ch in s.upper().replace(' ', ''))  # noqa: E731
        b, x = clean(base), clean(ext)[:3]
        cand = (b[:8].ljust(8) + x.ljust(3)).encode('ascii')
        if cand not in taken and b[:8] == base and x == ext and len(base) <= 8:
            return cand, False
        for i in range(1, 1000):
            tail = '~%d' % i
            cand = ((b[:8 - len(tail)] + tail).ljust(8) + x.ljust(3)).encode('ascii')
            if cand not in taken:
                return cand, True
        raise RuntimeError('no short name for ' + name)

    def link(self, dirc, name, start, size, attr, mtime=None):
        short, need_lfn = self.short_name(dirc, name)
        lfn = []
        if need_lfn:
            u = name.encode('utf-16-le') + b'\0\0'
            u += b'\xff' * (-len(u) % 26)
            pieces = [u[i:i + 26] for i in range(0, len(u), 26)]
            ck = lfn_sum(short)
            for i, p in enumerate(pieces):
                e = bytearray(32)
                e[0] = (i + 1) | (0x40 if i == len(pieces) - 1 else 0)
                for j, o in enumerate(LFN_OFFS):
                    e[o:o + 2] = p[2 * j:2 * j + 2]
                e[11], e[13] = 0x0F, ck
                lfn.insert(0, bytes(e))
        ent = bytearray(32)
        ent[0:11] = short
        ent[11] = attr
        struct.pack_into('<H', ent, 20, start >> 16)
        struct.pack_into('<H', ent, 26, start & 0xFFFF)
        struct.pack_into('<I', ent, 28, size)
        if mtime is not None:                           # the time of the last change (local)
            t = time.localtime(mtime)
            dt = (t.tm_hour << 11) | (t.tm_min << 5) | (t.tm_sec // 2)
            dd = ((t.tm_year - 1980) << 9) | (t.tm_mon << 5) | t.tm_mday
            struct.pack_into('<HH', ent, 14, dt, dd)        # created
            struct.pack_into('<H', ent, 18, dd)             # accessed
            struct.pack_into('<HH', ent, 22, dt, dd)        # written
        slots = self.free_slots(dirc, len(lfn) + 1)
        for off, e in zip(slots, lfn + [bytes(ent)]):
            self.write(off, e)
        self.fsinfo_count()

    def fsinfo_count(self):
        """FSInfo's free cluster count and next free cluster, counted from the
        FAT (as mkfs.fat and a PC keep them: CMDR-DOS reports the free
        space from them)"""
        fat = self.read(self.fat0, (self.ndata + 2) * 4)
        free = [c for c in range(2, self.ndata + 2) if struct.unpack_from('<I', fat, 4 * c)[0] & 0x0FFFFFFF == 0]
        fi = self.part + self.fsinfo * self.bps
        self.write(fi + 488, struct.pack('<II', len(free), free[0] if free else 0xFFFFFFFF))

    def free_bytes(self):
        fi = self.part + self.fsinfo * self.bps
        return struct.unpack_from('<I', self.read(fi + 488, 4))[0] * self.csize

    def find(self, path):
        """(directory cluster, entry) of a path, or the root"""
        dirc, e = self.root, None
        for part in [p for p in path.split('/') if p]:
            for name, ent in self.listdir(dirc):
                if name.upper() == part.upper():
                    e = ent
                    dirc = struct.unpack_from('<H', ent, 20)[0] << 16 | struct.unpack_from('<H', ent, 26)[0]
                    break
            else:
                raise KeyError(path)
        return dirc, e

    def mkdir(self, parent, name, mtime=None):
        c = self.alloc(1)
        blk = bytearray(self.csize)
        for i, (n, cl) in enumerate(((b'.          ', c), (b'..         ', 0 if parent == self.root else parent))):
            e = blk[32 * i:32 * i + 32]
            e[0:11], e[11] = n, 0x10
            struct.pack_into('<H', e, 20, cl >> 16)
            struct.pack_into('<H', e, 26, cl & 0xFFFF)
            blk[32 * i:32 * i + 32] = e
        self.write(self.cluster(c), bytes(blk))
        self.link(parent, name, c, 0, 0x10, mtime)
        return c

    def add_file(self, dirc, name, data, mtime=None):
        self.link(dirc, name, self.write_data(data), len(data), 0x20, mtime)

    def add_tree(self, dirc, folder):
        for n in sorted(os.listdir(folder)):
            p = os.path.join(folder, n)
            if os.path.isdir(p):
                self.add_tree(self.mkdir(dirc, n, os.path.getmtime(p)), p)
            elif os.path.isfile(p):
                self.add_file(dirc, n, open(p, 'rb').read(), os.path.getmtime(p))

    def walk(self, dirc=None, prefix=''):
        for name, e in self.listdir(self.root if dirc is None else dirc):
            if name in ('.', '..') or e[11] & 0x08:
                continue
            c = struct.unpack_from('<H', e, 20)[0] << 16 | struct.unpack_from('<H', e, 26)[0]
            if e[11] & 0x10:
                yield prefix + name + '/', None
                yield from self.walk(c, prefix + name + '/')
            else:
                yield prefix + name, struct.unpack_from('<I', e, 28)[0]

    def get(self, path):
        _, e = self.find(path)
        if e is None or e[11] & 0x10:
            raise KeyError(path)
        c = struct.unpack_from('<H', e, 20)[0] << 16 | struct.unpack_from('<H', e, 26)[0]
        size = struct.unpack_from('<I', e, 28)[0]
        return b''.join(self.read(self.cluster(x), self.csize) for x in self.chain(c))[:size]


def make(path, folder, mb=SIZE_MB, cluster_kb=CLUSTER_KB):
    with open(path, 'wb') as f:
        f.truncate(mb * 1024 * 1024)
    subprocess.run(['sfdisk', '-q', path], input='%d,,c\n' % PART_START, text=True, check=True,
                   capture_output=True)
    size_kb = (mb * 1024 * 1024 - PART_START * 512) // 1024
    subprocess.run(['mkfs.fat', '-F', '32', '-s', str(cluster_kb * 2), '-n', 'VERANDA',
                    '--offset', str(PART_START), path, str(size_kb)], check=True, capture_output=True)
    fs = Fat32(path)
    if folder:
        fs.add_tree(fs.root, folder)
    fs.fsinfo_count()


def main():
    a = sys.argv[1:]
    if a[:1] == ['make'] and len(a) >= 2:
        a = a[1:]
        opts = {'--mb': SIZE_MB, '--cluster-kb': CLUSTER_KB}
        while a and a[0] in opts:
            opts[a[0]] = int(a[1])
            a = a[2:]
        make(a[0], a[1] if len(a) > 1 else None, opts['--mb'], opts['--cluster-kb'])
    elif a[:1] == ['add'] and len(a) in (3, 4):
        fs = Fat32(a[1])
        dirc = fs.find(a[3])[0] if len(a) == 4 else fs.root
        fs.add_file(dirc, os.path.basename(a[2]), open(a[2], 'rb').read())
    elif a[:1] == ['ls'] and len(a) == 2:
        for p, size in Fat32(a[1]).walk():
            print(p if size is None else '%-40s %d' % (p, size))
    elif a[:1] == ['free'] and len(a) == 2:
        print(Fat32(a[1]).free_bytes())
    elif a[:1] == ['get'] and len(a) == 4:
        open(a[3], 'wb').write(Fat32(a[1]).get(a[2]))
    else:
        sys.exit(__doc__)


if __name__ == '__main__':
    main()
