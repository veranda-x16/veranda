#!/usr/bin/env python3
"""Gate disk checks (tests/disk.s): the console lines and the host files.

usage: check_disk.py <run folder> [<part 2 run folder>]
"""
import os
import re
import sys

failures = 0


def check(cond, what):
    global failures
    print(('ok    ' if cond else 'FAIL  ') + what)
    if not cond:
        failures += 1


def main():
    d = sys.argv[1]
    log = [re.sub(r'\\X[0-9A-F]{2}', '', ln).strip()
           for ln in open(os.path.join(d, 'console.txt'), 'rb').read().decode('latin-1').splitlines()]
    try:
        log = log[log.index('DISK START') + 1:log.index('DISK DONE')]
    except ValueError:
        check(False, 'the test ran to its end')
        sys.exit(1)
    errs = [ln for ln in log if ln.startswith('E')]
    check(not errs, 'no call failed%s' % (': %s' % errs if errs else ''))
    want = bytes((i & 255) ^ ((0x1000 + i) >> 8) for i in range(4096)) * 8      # tests/disk.s's pattern
    path = os.path.join(d, 'DATA.BIN')
    got = open(path, 'rb').read() if os.path.exists(path) else b''
    check(got == want, 'FWrite: DATA.BIN on the host is the 32 KB written (%d bytes)' % len(got))
    check('R ok' in log, 'FRead: read back equal, and 0 bytes past the end')
    s = [ln for ln in log if re.fullmatch('S[0-9A-F]{8}', ln)]
    check(s == ['S' + want[1000:1004].hex().upper()], 'FSeek: 4 bytes at 1000 (%s)' % s)
    z = [ln for ln in log if re.fullmatch('Z[0-9A-F]{16}', ln)]
    check(z == ['Z%08X%08X' % (len(want), 1004)], 'FSize: the size equals the host\'s (%d), the position 1004 (%s)' % (len(want), z))
    check('D ok' in log and os.path.exists(os.path.join(d, 'DIRA', 'IN.TXT')),
          'MkDir, ChDir: DIRA/IN.TXT made, back up with ".."')
    check('Q ok' in log and not os.path.exists(os.path.join(d, 'DIRE')), 'RmDir: DIRE made and removed')
    check('N ok' in log and os.path.exists(os.path.join(d, 'NEW.BIN')) and not os.path.exists(os.path.join(d, 'OLD.BIN'))
          and not os.path.exists(os.path.join(d, 'GONE.BIN')), 'FRename, FDelete')
    check('X05' in log, 'FDelete of a missing file: FILE_NOT_FOUND')
    names = [ln[3:] for ln in log if ln.startswith('L')]
    kinds = {ln[3:]: ln[1] for ln in log if ln.startswith('L')}
    check('DATA.BIN' in names and kinds.get('DIRA') == 'D' and kinds.get('NEW.BIN') == 'F',
          'DirOpen, DirNext: the listing has DATA.BIN, NEW.BIN and the directory DIRA (%d names)' % len(names))
    for t, what in (('W', 'write'), ('R', 'read')):
        ln = [x for x in log if x.startswith('T' + t)]
        if ln:
            cyc = int(ln[0].split()[1], 16)
            print('      %s 32 KB: %.0f ms (%.0f KB/s)' % (what, cyc / 8000, 32 / (cyc / 8e6)))
    if len(sys.argv) > 2:
        part2(sys.argv[2])
    sys.exit(1 if failures else 0)


def cvt(path):
    """(directory entry, info block, records or data) of a CVT file"""
    d = open(path, 'rb').read()
    entry, info = d[:30], b'\0\xff' + d[254:508]
    if entry[21] != 1:
        return entry, info, d[508:]
    recs, pos = [], 762
    for i in range(127):
        n, last = d[508 + 2 * i], d[509 + 2 * i]
        if n == 0 and last == 0:
            break
        if n == 0:
            recs.append(None)
            continue
        size = (n - 1) * 254 + last - 1
        recs.append(d[pos:pos + size])
        pos += n * 254
    return entry, info, recs


def part2(d):
    log = [re.sub(r'\\X[0-9A-F]{2}', '', ln).strip()
           for ln in open(os.path.join(d, 'console.txt'), 'rb').read().decode('latin-1').splitlines()]
    try:
        log = log[log.index('DISK2 START') + 1:log.index('DISK2 DONE')]
    except ValueError:
        check(False, 'part 2 ran to its end')
        return
    errs = [ln for ln in log if ln.startswith('E')]
    check(not errs, 'part 2: no call failed%s' % (': %s' % errs if errs else ''))
    check('t07' in log and 'c4E' in log and 'F00' in log,
          'SaveFile, FindFile (type APPL_DATA), GetFHdrInfo (class "N..."), LdFile (600 bytes back, r7 at the end)')
    check('B00' in log, 'FWrite from and FRead into $A000 of the caller\'s own bank (V47)')
    bank = os.path.join(d, 'BANK.BIN')
    check(os.path.exists(bank) and open(bank, 'rb').read() == bytes(i ^ 0xA5 for i in range(256)),
          'BANK.BIN: the 256 bytes written from the bank')
    memo = os.path.join(d, 'Memo.cvt')
    check(os.path.exists(memo) and not os.path.exists(os.path.join(d, 'Notes.cvt')), 'RenameFile: Notes.cvt is Memo.cvt')
    if os.path.exists(memo):
        e, info, data = cvt(memo)
        want = bytes((i & 255) ^ 0x5A for i in range(600))
        check(data == want and e[22] == 7 and e[21] == 0 and info[77:93] == b'Notes       V1.0',
              'Memo.cvt: a sequential APPL_DATA file, its class, its 600 bytes')
    book = os.path.join(d, 'Book.cvt')
    check('u03' in log and 'nC8' in log and 'v02' in log, 'OpenRecordFile again: 3 records; record 1 is 200 bytes of 2')
    if os.path.exists(book):
        e, info, recs = cvt(book)
        want = [b'\x01' * 100, b'X' * 300, b'\x03' * 300]
        check(e[21] == 1 and recs == want, 'Book.cvt on the host: records 100 x 1, 300 x "X" (inserted), 300 x 3')
        blocks = e[28] | e[29] << 8
        check(blocks == len(open(book, 'rb').read()) // 254 - 1,
              'Book.cvt: its directory entry has the size written back (%d blocks)' % blocks)
    else:
        check(False, 'Book.cvt on the host')
    check(not any(f.endswith('.tmp') for f in os.listdir(d)), 'no Name.tmp left behind')
    names = sorted(ln[1:] for ln in log if ln.startswith('='))
    check(names == ['Book', 'Notes'] and 'T02' in log, 'FindFTypes(APPL_DATA): Book, Notes (%s)' % names)


if __name__ == '__main__':
    main()
