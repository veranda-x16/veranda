#!/usr/bin/env python3
"""tests/vrcs_test.c's output (sim65) against Python's iso8859_16 codec
(DECISIONS V140): usage check_vrcs.py <out.txt>; prints ok/FAIL lines."""
import sys


def main():
    lines = open(sys.argv[1]).read().split('\n')
    bad = []
    strs = []
    n = 0
    for ln in lines:
        p = ln.split()
        if not p:
            continue
        if p[0] == 'S':
            strs.append(bytes(int(x, 16) for x in p[2:]))
            continue
        if p[0] == 'B':
            got = [int(x, 16) for x in p[1:]]
            exp = [0, 0, 0, 0xE9]     # n tilde (D1 is N acute), r caron, an em dash, e acute
            if got != exp:
                bad.append('cs_byte of U+00F1 U+0159 U+2014 U+00E9: %s, wanted %s' % (got, exp))
            continue
        c, u = int(p[0], 16), int(p[1], 16)
        sl = p.index('/')
        utf = bytes(int(x, 16) for x in p[2:sl])
        back = int(p[sl + 1], 16)
        eu = c if 0x80 <= c < 0xA0 else ord(bytes([c]).decode('iso8859_16'))
        eb = 0 if 0x80 <= c < 0xA0 else c
        if u != eu or utf != chr(eu).encode('utf-8') or back != eb:
            bad.append('byte %02X: U+%04X %s back %02X' % (c, u, utf.hex(), back))
        n += 1
    want = ['Zażółć gęślą jaźń'.encode('iso8859_16'), 'ZAŻÓŁĆ GĘŚLĄ JAŹŃ'.encode('iso8859_16'),
            b'?|?|\xa4|?|||?|\xfe']     # (a sequence cut short: dropped)
    for i, (g, w) in enumerate(zip(strs, want)):
        if g != w:
            bad.append('string %d: %r, wanted %r' % (i + 1, g, w))
    if len(strs) != 3 or n != 256:
        bad.append('%d strings, %d bytes' % (len(strs), n))
    for b in bad:
        print('FAIL  vrcs: ' + b)
    if bad:
        sys.exit(1)
    print('ok    vrcs: 256 bytes to Unicode, UTF-8 and back equal Python\'s iso8859_16; '
          '"Zażółć gęślą jaźń" in both cases and broken UTF-8 decoded')


if __name__ == '__main__':
    main()
