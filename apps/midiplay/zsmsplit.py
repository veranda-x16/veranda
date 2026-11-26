#!/usr/bin/env python3
"""MIDI Player (apps/midiplay): ZSMKit's binary (vendor/zsmkit, built at
$A000 over two banks) as two overlay records, one a bank (app.hdr:
overlays = banked; the loader keeps record n in bank first + n, so the two
are adjacent, as ZSMKit v3 needs). The first bank's record ends where its
code and data end (ld65's map: ZSMKIT0), not at its BSS: a banked overlay
is at most 8191 bytes, and ZSMKit clears its BSS itself.

usage: zsmsplit.py <zsmkit-a000.bin> <zsmkit.map> <out.a> <out.b>
MIT licence (see LICENSE)."""
import re
import sys

binf, mapf, outa, outb = sys.argv[1:5]
data = open(binf, 'rb').read()
m = re.search(r'^ZSMKIT0\s+([0-9A-F]{6})\s+([0-9A-F]{6})', open(mapf).read(), re.M)
if not m:
    sys.exit('zsmsplit: no ZSMKIT0 in ' + mapf)
end = int(m.group(2), 16) + 1 - 0xA000
if end > 8191 or len(data) <= 8192:
    sys.exit('zsmsplit: ZSMKit does not fit (bank 0 to $%04X, %d bytes in all)' % (end + 0xA000, len(data)))
open(outa, 'wb').write(data[:end])
open(outb, 'wb').write(data[8192:])
print('zsmsplit: ZSMKit %d + %d bytes' % (end, len(data) - 8192))
