#!/usr/bin/env python3
"""Veranda's character set on the PC (DECISIONS V140): ISO-8859-16.

Text above $7F in Veranda (documents, the Text Scrap, the fonts, the
keyboard) is ISO-8859-16 (Latin-10); $80-$9F are not characters. This is
the SDK's sdk/lib/vrcs.s for host tools and gates (Python's iso8859_16
codec; tests/check_vrcs.py checks that the two agree).

usage: vrcs.py to <in.utf8> <out>     UTF-8 to the set (unknown: '?')
       vrcs.py from <in> <out.utf8>   the set to UTF-8
       vrcs.py table                  the 96 characters of $A0-$FF
"""
import sys

CODEC = 'iso8859_16'
BAD = b'?'


def encode(text):
    """a str -> Veranda bytes (a character the set has none of: '?')"""
    out = bytearray()
    for ch in text:
        try:
            b = ch.encode(CODEC)
        except UnicodeEncodeError:
            b = BAD
        if 0x80 <= b[0] < 0xA0:
            b = BAD
        out += b
    return bytes(out)


def decode(data):
    """Veranda bytes -> a str ($80-$9F as U+FFFD)"""
    return ''.join('�' if 0x80 <= c < 0xA0 else bytes([c]).decode(CODEC) for c in data)


def main():
    a = sys.argv[1:]
    if a[:1] == ['to'] and len(a) == 3:
        open(a[2], 'wb').write(encode(open(a[1], encoding='utf-8').read()))
    elif a[:1] == ['from'] and len(a) == 3:
        open(a[2], 'w', encoding='utf-8').write(decode(open(a[1], 'rb').read()))
    elif a == ['table']:
        for r in range(0xA0, 0x100, 16):
            print('%02X  %s' % (r, ' '.join(decode(bytes([c])) for c in range(r, r + 16))))
    else:
        sys.exit(__doc__)


if __name__ == '__main__':
    main()
