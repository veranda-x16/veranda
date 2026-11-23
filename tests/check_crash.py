#!/usr/bin/env python3
"""Gate crash (DECISIONS V50): a session of crashing programs, each started
from the shell, each back in the shell after its panic box.

usage: check_crash.py <run dir> <kernel build dir> <apps dir>

<run dir>: console.txt, dump.bin (x16emu -dump BV: the banked RAM, then
VRAM), CRASH.TXT. <apps dir>: crashN.lab, each program's labels (Crash: the
instruction that crashes). Checks:
  - the console in order: the shell, the program, its PANIC line, the
    shell again ... SHELL DONE;
  - each PANIC line: the program's name, why, the address and RAM bank
    (BRK and Panic at Crash in bank 1; the BRK in kernel bank U at its
    entry table; the stack overflow in the recursion; the jump at $7000);
  - CRASH.TXT (open for writing when program 1 crashed) has its line: the
    channels were closed;
  - the kernel banks' code as loaded (VERANDA.SYS), and their copy (the
    KERNEL_BANKS banks under them) equal to VERANDA.SYS whole but for the
    desktop's path in bank S's (deskPath, DESK_SIZE bytes: SysPrefs
    DESK_SET writes it there too, DECISIONS V63), which holds the shell's
    folder.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_banks  # noqa: E402

BANKS = check_banks.BANKS
NAMES = {1: 'Crash1Brk', 2: 'Crash2Panic', 3: 'Crash3Bank', 4: 'Crash4Stack', 5: 'Crash5Jump'}
WHY = {1: 'It ran into a BRK at', 2: 'It called Panic at', 3: 'It ran into a BRK at',
       4: 'Its stack was full at', 5: 'It ran into a BRK at'}
bad = 0


def check(ok, msg):
    global bad
    print(('ok    ' if ok else 'FAIL  ') + msg)
    if not ok:
        bad += 1


def label(path, name):
    for line in open(path):
        f = line.split()
        if len(f) >= 3 and f[2].lstrip('.') == name:
            return int(f[1], 16)
    raise SystemExit('check_crash: no %s in %s' % (name, path))


def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    run, kdir, adir = sys.argv[1:]
    log = open(os.path.join(run, 'console.txt'), 'rb').read().decode('latin-1')
    log = re.sub(r'\\X[0-9A-F]{2}', '', log)
    ev = re.findall(r'SHELL READY \d|CRASH \d START|CRASH DID NOT|PANIC [^\n]*|SHELL DONE', log)
    want = ['SHELL READY 0']
    for k in range(1, 6):
        want += ['CRASH %d START' % k, 'PANIC', 'SHELL READY %d' % k]
    want += ['SHELL DONE']
    got = [e if not e.startswith('PANIC') else 'PANIC' for e in ev]
    check(got == want, 'the console in order: the shell, each program, its panic box, the shell again '
          '(5 times), SHELL DONE' + ('' if got == want else ': %s' % got))
    panics = [e for e in ev if e.startswith('PANIC')]
    d = open(os.path.join(run, 'dump.bin'), 'rb').read()
    ram = d[:len(d) - 132878]
    nb = len(ram) // 8192
    base = nb - len(BANKS)
    for k, p in zip(range(1, 6), panics):
        m = re.match(r'PANIC (\S+) (.*) \$([0-9A-F]{4}) \(RAM bank (\d+)\)$', p)
        if not m:
            check(False, 'program %d: the panic line %r' % (k, p))
            continue
        name, why, pc, bank = m.group(1), m.group(2), int(m.group(3), 16), int(m.group(4))
        crash = label(os.path.join(adir, 'crash%d.lab' % k), 'Crash')
        if k == 3:
            where = 0xA000 <= pc < 0xA100 and bank == base + 2
            exp = '$A0xx in RAM bank %d (kernel bank U)' % (base + 2)
        elif k == 5:
            where = pc == 0x7000 and bank == 1
            exp = '$7000, RAM bank 1'
        else:
            where = pc == crash and bank == 1
            exp = '$%04X, RAM bank 1' % crash
        check(name == NAMES[k] and why == WHY[k] and where,
              'program %d: "%s %s $%04X (RAM bank %d)" (want %s, %s %s)' % (k, name, why, pc, bank, NAMES[k],
                                                                            WHY[k], exp))
    try:
        txt = open(os.path.join(run, 'CRASH.TXT'), 'rb').read()
    except OSError:
        txt = None
    check(txt == b'written before the crash\n', 'CRASH.TXT, open for writing at the BRK, has its line (closed by '
          'the crash handler): %r' % txt)

    sysimg = open(os.path.join(kdir, 'VERANDA.SYS'), 'rb').read()[2:]
    desk = next(int(ln.split()[1], 16) for ln in open(os.path.join(kdir, 'k', 'bank_S.lab'))
                if ln.split()[2] == '.deskPath')
    nc = len(BANKS) - 1         # (V165: bank C, the last, has no copy)
    for i, b in enumerate(BANKS):
        img = sysimg[i * 8192:(i + 1) * 8192]
        n = check_banks.ro_end(os.path.join(kdir, 'k', 'bank_%s.map' % b))
        live = ram[(base + i) * 8192:(base + i) * 8192 + 8192]
        if b == 'C':
            check(live[:n] == img[:n], 'kernel bank C (RAM bank %d): its code as loaded (%d bytes; no copy)'
                  % (base + i, n))
            continue
        copy = ram[(base - nc + i) * 8192:(base - nc + i + 1) * 8192]
        if b == 'S':            # (the desktop's path: the shell's, V63)
            d = desk - 0xA000
            check(copy[d:d + 64].split(b'\0')[0] == b'/', "bank S's copy: the desktop's path is the shell's "
                  "folder, /: %r" % copy[d:d + 64].split(b'\0')[0])
            copy = copy[:d] + img[d:d + 64] + copy[d + 64:]
        if b == 'T':            # (BASIC's zero page $A9-$FF at $BF00, V73)
            z = 0x1F00
            check(copy[z + 0xE7 - 0xA9] == 0xE6, "bank T's copy: BASIC's zero page (CHRGET)")
            copy = copy[:z] + img[z:z + 87] + copy[z + 87:]
        check(live[:n] == img[:n] and copy == img,
              'kernel bank %s (RAM bank %d): its code as loaded (%d bytes); its copy (RAM bank %d) equal to '
              'VERANDA.SYS' % (b, base + i, n, base - nc + i))
    sys.exit(1 if bad else 0)


if __name__ == '__main__':
    main()
