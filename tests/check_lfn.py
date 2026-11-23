#!/usr/bin/env python3
"""Gate disk, part 4 (tests/lfn.s; DECISIONS V82): long names in the GEOS
file calls. The console's lines and the files the test left.

usage: check_lfn.py <run folder>   (console.txt and the files in it)

Also a module: short(name) is the kernel's short form (kernel/f/load.s).
"""
import binascii
import os
import re
import sys

failures = 0


def check(cond, what):
    global failures
    print(('ok    ' if cond else 'FAIL  ') + what)
    if not cond:
        failures += 1


def short(n):
    """dataFileName for the long name n: as it is up to 16 characters; else
    the first 11 less the extension's (a dot and 1-4 characters at the
    end), "~", the CRC-16 (CCITT, from $FFFF: the ROM's memory_crc) of n
    in four hexadecimal digits, the extension"""
    if len(n) <= 16:
        return n
    ext = ''
    for k in range(2, 6):
        if n[-k] == '.':
            ext = n[-k:]
            break
    return n[:11 - len(ext)] + '~%04X' % binascii.crc_hqx(n.encode('latin-1'), 0xFFFF) + ext


DOCS = ['Exactly sixteen!', 'Seventeen letters', 'Holiday photos from the lake 2026.txt', 'Budget for the year.X16S',
        'A picture with a long name', 'A name ending in a dot.',
        'A record file whose name is sixty-three characters long exactly']
PIC = 'A picture with a long name for the test'
MAX = 'A record file whose name is sixty-three characters long exactly'
TEXT = b'Long names reach the file.\0'
CHANGED = b'Changed by its short form.\0'


def records(path):
    """a CVT record file's records (its table at 508)"""
    b = open(path, 'rb').read()
    out, pos = [], 762
    for i in range(127):
        t, s = b[508 + 2 * i], b[509 + 2 * i]
        if t == 0 and s == 0:
            break
        if t == 0:
            out.append(None)
            continue
        n = (t - 1) * 254 + s - 1
        out.append(b[pos:pos + n])
        pos += t * 254
    return out


def main():
    d = sys.argv[1]
    log = [re.sub(r'\\X[0-9A-F]{2}', '', ln).strip()
           for ln in open(os.path.join(d, 'console.txt'), 'rb').read().decode('latin-1').splitlines()]
    try:
        log = log[log.index('LFN START') + 1:log.index('LFN DONE')]
    except ValueError:
        check(False, 'the test ran to its end')
        sys.exit(1)
    log = [ln for ln in log if not ln.startswith(('P\x0b', 'S:', 'R:', '@:')) and ln]
    errs = [ln for ln in log if re.fullmatch('E[a-zA-Z][0-9A-F]{2}', ln)]
    check(not errs, 'no call failed%s' % (': %s' % errs if errs else ''))
    g = [ln[2:] for ln in log if ln.startswith('G ')]
    want = ['%s|%s' % (short(n), n) for n in DOCS] + ['Holiday photos f|Holiday photos f']
    check(g == want, 'GetFile (ST_LD_DATA): dataLongName the whole name, dataFileName its short form (%s); '
          'GEOS\'s 16 characters without longNames' % ', '.join(short(n) for n in DOCS[1:]))
    if g != want:
        for a, b in zip(g, want):
            print('      got %r want %r' % (a, b))
    check(len(set(short(n) for n in DOCS)) == len(DOCS) and all(len(short(n)) <= 16 for n in DOCS),
          'the short forms are distinct and 16 characters at most')
    check('P ' + TEXT[:-1].decode() in log, 'FOpen(dataFileName) without longNames (a GEOS program) read the long '
          'plain file "Holiday photos from the lake 2026.txt"')
    hol = os.path.join(d, 'Holiday photos from the lake 2026.txt')
    check(os.path.exists(hol) and open(hol, 'rb').read() == TEXT, 'the plain file has its long name on the host')
    rr = [ln for ln in log if ln.startswith('R ')]
    check(rr == ['R ' + TEXT[:-1].decode()] * 2 and log.count('u02') == 2,
          'record files of 39 and 63 characters: made (SaveFile), written, closed, opened again: 2 records, record 1 read')
    check('H LongRec     V1.0' in log, 'FindFile of the 39-character name, GetFHdrInfo(dirEntryBuf): its class')
    check('Q00' in log, 'a sequential file of 34 characters: SaveFile, FindFile, LdFile(dirEntryBuf) loaded it')
    for n in (PIC, MAX):
        p = os.path.join(d, n + '.cvt')
        check(os.path.exists(p), '%s.cvt (%d characters) on the host' % (n, len(n)))
    if os.path.exists(os.path.join(d, PIC + '.cvt')):
        r = records(os.path.join(d, PIC + '.cvt'))
        check(len(r) == 2 and r[0] == TEXT[:4] and r[1] == CHANGED,
              'the 39-character file after a GEOS program wrote it by dataFileName\'s short form: record 1 "%s"'
              % (r[1][:-1].decode('latin-1') if len(r) > 1 and r[1] else r))
    if os.path.exists(os.path.join(d, MAX + '.cvt')):
        r = records(os.path.join(d, MAX + '.cvt'))
        check(len(r) == 2 and r[1] == TEXT, 'the 63-character file\'s records (written back through VRTEMP.tmp: '
              '"R:" 67 characters "=VRTEMP.tmp" fills kName\'s 80 bytes)')
    check('S ' + CHANGED[:-1].decode() in log, 'without longNames: OpenRecordFile(dataFileName), a record written, '
          'closed, opened again by dataFileName: the change read back')
    files = os.listdir(d)
    check(not [f for f in files if f.endswith('.tmp')], 'no temporary file left (%s)'
          % [f for f in files if f.endswith('.tmp')])
    check(not [f for f in files if '~' in f], 'no file under a short form')
    check('D00' in log and 'd05' in log and not os.path.exists(os.path.join(d, 'A file with a long name to delete.cvt')),
          'DeleteFile of a long name: gone (FindFile: FILE_NOT_FOUND)')
    check('N0B' in log, 'RenameFile of two long names, one command too long: BFR_OVERFLOW, nothing renamed')
    check('n00' in log and os.path.exists(os.path.join(d, 'Short.cvt'))
          and not os.path.exists(os.path.join(d, 'A sequential file with a long name.cvt')),
          'RenameFile of the long sequential file to "Short": Short.cvt')
    check('C05' in log and 'c00' in log and os.path.exists(os.path.join(d, 'Application Seven.cvt')),
          'without longNames FindFile("Application Seven") looks for its first 16 characters (FILE_NOT_FOUND), '
          'with them it finds Application Seven.cvt')
    sys.exit(1 if failures else 0)


if __name__ == '__main__':
    main()
