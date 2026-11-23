#!/usr/bin/env python3
"""Gate shell (DECISIONS V135): a document whose application is missing
opens with a substitute (shell/dir.c, dir_open_data's tSubst).

usage: shell_subst.py <folder> subst|geowrite

Writes into <folder> (a run's top: /VERANDA/SHELL.cvt, the shell starting
in /DOCUMENTS, DECISIONS V71) two GEOS documents in /DOCUMENTS and
SHELL.TST, tests/shell_script.py's records:

  GeoLetter.cvt  a geoWrite document: VLIR, class "Write Image V2.1",
                 parent "geoWrite    V2.1" (its info block as geoWrite
                 writes it), page 1 a line of text
  Mystery.cvt    class "Mystery Doc V1.0", parent "NoSuchApp   V1.0":
                 neither its application nor a substitute is there

subst (Veranda Write in /VERANDA/APPS, no geoWrite):
  0  double-click GeoLetter: Veranda Write starts with it
  1  double-click Mystery: "No application opens this document.", OK;
     the end (SHELL DONE, a VRAM dump)
geowrite (geoWrite in /VERANDA/APPS too):
  0  double-click GeoLetter: geoWrite starts with it
  1  the end

MIT licence (LICENSE).
"""
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import shell_script as S  # noqa: E402


def cvt(name, cls, parent, recs):
    """a VLIR GEOS document (APPL_DATA) in CVT format: the entry and
    signature, the info block, the record table, the records"""
    b0 = bytearray(254)
    b0[0] = 0x83
    nm = name.encode('latin-1')
    b0[3:19] = nm + b'\xa0' * (16 - len(nm))
    b0[21], b0[22] = 1, 7                       # VLIR, APPL_DATA
    b0[23:28] = bytes([126, 11, 21, 12, 0])
    sig = b'PRG formatted GEOS file V1.0'
    b0[30:30 + len(sig)] = sig
    info = bytearray(254)                       # (the info block from its byte 2)
    info[0:3] = b'\x03\x15\xbf'
    info[66:69] = bytes([0x83, 7, 1])
    info[75:75 + len(cls)] = cls.encode('latin-1')          # bytes 77-96
    info[115:115 + len(parent)] = parent.encode('latin-1')  # bytes 117-136
    tbl = bytearray(254)
    body = bytearray()
    for n in range(max(recs) + 1):
        if n in recs:
            r = recs[n]
            blocks = max(1, (len(r) + 253) // 254)
            tbl[2 * n] = blocks
            tbl[2 * n + 1] = len(r) - (blocks - 1) * 254 + 1
            body += r + b'\0' * (blocks * 254 - len(r))
        else:
            tbl[2 * n + 1] = 0xFF
    return bytes(b0 + info + tbl + body)


def main():
    if len(sys.argv) < 3 or sys.argv[2] not in ('subst', 'geowrite'):
        sys.exit(__doc__)
    d, what = sys.argv[1], sys.argv[2]
    docs = os.path.join(d, 'DOCUMENTS')
    os.makedirs(docs, exist_ok=True)
    ruler = bytes([0x11]) + struct.pack('<HHH', 0, 479, 0) + bytes(26)
    page = ruler + bytes([0x10]) + struct.pack('<HB', 1, 0) + b'A letter from geoWrite.\r\0'
    open(os.path.join(docs, 'GeoLetter.cvt'), 'wb').write(
        cvt('GeoLetter', 'Write Image V2.1', 'geoWrite    V2.1', {0: page}))
    open(os.path.join(docs, 'Mystery.cvt'), 'wb').write(
        cvt('Mystery', 'Mystery Doc V1.0', 'NoSuchApp   V1.0', {0: b'?\0'}))
    root = ['..'] + S.listing([], os.listdir(docs))
    parts = []
    p = S.Part()
    p.wait(20)
    p.dbl(*S.cell(root.index('GeoLetter.cvt')))
    p.end(S.END_STOP)
    parts.append(p)
    p = S.Part()
    p.wait(20)
    if what == 'subst':
        p.dbl(*S.cell(root.index('Mystery.cvt')))
        p.wait(40)
        p.click(S.YES_X, S.YES_Y)               # the box's OK
        p.wait(40)
    p.end(S.END_DONE)
    parts.append(p)
    S.write(os.path.join(d, 'SHELL.TST'), parts)


if __name__ == '__main__':
    main()
