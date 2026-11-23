#!/usr/bin/env python3
"""After a session: the kernel banks' code is what was loaded (the old
project's D66: nothing wrote into it).

usage: check_banks.py <dump.bin> <kernel build dir>

dump.bin from x16emu -dump BV: the banked RAM, then the VRAM section. Each
bank of VERANDA.SYS (2 header bytes, then 8 KB a bank) is found in the
dump by its entry table; its ENTRY, CODE and RODATA (from its map file)
must be unchanged. DATA and BSS are its variables.
"""
import os
import sys

BANKS = ['G', 'G2', 'U', 'F', 'S', 'X', 'P', 'T', 'W', 'C']


def ro_end(mapfile):
    end, seg = 0xA000, False
    for line in open(mapfile):
        if line.startswith('Segment list:'):
            seg = True
            continue
        if seg:
            f = line.split()
            if not f:
                if end > 0xA000:
                    break
                continue
            if f[0] in ('ENTRY', 'CODE', 'RODATA', 'PAGED'):     # (bank T's UI font; LATE, after the
                                                                # variables in bank G, is not checked)
                end = max(end, int(f[2], 16) + 1)
    return end - 0xA000


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    d = open(sys.argv[1], 'rb').read()
    ram = d[:len(d) - 132878]          # (x16emu's VRAM section: 128 KB and 1,806 bytes)
    sysimg = open(os.path.join(sys.argv[2], 'VERANDA.SYS'), 'rb').read()[2:]
    nb = len(ram) // 8192
    bad = 0
    for i, b in enumerate(BANKS):
        img = sysimg[i * 8192:(i + 1) * 8192]
        n = ro_end(os.path.join(sys.argv[2], 'k', 'bank_%s.map' % b))
        if n == 0:
            continue
        found = [k for k in range(nb) if ram[k * 8192:k * 8192 + 48] == img[:48]]
        if not found:
            print('FAIL  bank %s: not found in RAM' % b)
            bad += 1
            continue
        k = found[-1]
        got = ram[k * 8192:k * 8192 + n]
        diff = [j for j in range(n) if got[j] != img[j]]
        if diff:
            print('FAIL  bank %s (RAM bank %d): %d code bytes changed, first at $%04X' % (b, k, len(diff), 0xA000 + diff[0]))
            bad += 1
    print(('FAIL  ' if bad else 'ok    ') + 'the kernel banks\' code is unchanged after the session')
    sys.exit(1 if bad else 0)


if __name__ == '__main__':
    main()
