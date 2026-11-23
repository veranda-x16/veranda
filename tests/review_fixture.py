#!/usr/bin/env python3
"""gate review's files (DECISIONS V68).

usage: review_fixture.py fonts <dir>   Rev A (sizes 10-19), Rev B (20-29):
                                       records of 300 bytes; Rev Big: size 9,
                                       a record of 8200 bytes (two banks);
                                       Rev Tiny: size 9, 211 bytes;
                                       Rev C (10-19), as Rev A
       review_fixture.py files <dir>   APPL_DATA files for FindFTypes: a
                                       16-character name, a name with a dot,
                                       a plain one; a FONT file (not listed)
       review_fixture.py fill <sd.img> every free cluster used (a full card)
       review_fixture.py rec <dir>     record files: REC1 (one record of 10
                                       bytes), REC3 (one of 20000: three
                                       banks), RECW (one of 5000)
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'tools'))
import fontcvt  # noqa: E402

APPL_DATA = 7


def record(height, length=0):
    """a valid font record: an empty bitmap, padded to length"""
    setw = 1
    r = bytearray([0, setw, 0, height, 8, 0, (8 + 194) & 255, (8 + 194) >> 8])
    r += bytes(194)
    r += bytes(setw * height)
    if length:
        r += bytes(length - len(r))
    return bytes(r)


def typed(data, t):
    d = bytearray(data)
    d[22] = t                       # the directory entry's GEOS type
    d[30 + 224 + 68 - 2 + 1] = t    # the info block's (header byte 69)
    return bytes(d)


def main(a):
    if len(a) != 2:
        raise SystemExit(__doc__)
    d = a[1]
    if a[0] != 'fill':
        os.makedirs(d, exist_ok=True)
    w = lambda n, b: open(os.path.join(d, n), 'wb').write(b)  # noqa: E731
    if a[0] == 'fonts':
        w('Rev A.cvt', fontcvt.write_cvt('Rev A', 900, {s: record(s - 8, 300) for s in range(10, 20)}))
        w('Rev B.cvt', fontcvt.write_cvt('Rev B', 901, {s: record(s - 18, 300) for s in range(20, 30)}))
        w('Rev Big.cvt', fontcvt.write_cvt('Rev Big', 902, {9: record(9, 8200)}))
        w('Rev C.cvt', fontcvt.write_cvt('Rev C', 909, {s: record(s - 8, 300) for s in range(10, 20)}))
        w('Rev Tiny.cvt', fontcvt.write_cvt('Rev Tiny', 908, {9: record(9)}))
    elif a[0] == 'files':
        for n in ('Sixteen Chars Ab', 'Letter 1.5', 'Plain'):
            w(n + '.cvt', typed(fontcvt.write_cvt(n, 903, {10: record(2)}), APPL_DATA))
        w('Afont.cvt', fontcvt.write_cvt('Afont', 904, {10: record(2)}))
    elif a[0] == 'rec':
        w('REC1.cvt', typed(fontcvt.write_cvt('REC1', 905, {0: bytes(range(10))}), APPL_DATA))
        w('REC3.cvt', typed(fontcvt.write_cvt('REC3', 906, {0: bytes(i * 7 & 255 for i in range(20000))}), APPL_DATA))
        w('RECW.cvt', typed(fontcvt.write_cvt('RECW', 907, {0: bytes(i * 3 & 255 for i in range(5000))}), APPL_DATA))
    elif a[0] == 'fill':
        # every free cluster of the image marked used (no file holds them),
        # the FS info's free count unknown: a full card
        import struct
        import vcard
        fs = vcard.Fat32(d)
        bpb = fs.read(fs.part, 512)
        total = struct.unpack_from('<I', bpb, 32)[0] * fs.bps
        n = 2 + (total - (fs.data0 - fs.part)) // fs.csize
        for c in range(2, min(n, fs.nclusters)):
            if fs.fat(c) == 0:
                fs.set_fat(c, vcard.EOC)
        fs.write(fs.part + fs.fsinfo * fs.bps + 488, struct.pack('<II', 0xFFFFFFFF, 0xFFFFFFFF))
    else:
        raise SystemExit(__doc__)


if __name__ == '__main__':
    main(sys.argv[1:])
