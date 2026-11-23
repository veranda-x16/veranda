#!/usr/bin/env python3
"""The X16's ROM BASIC programs as text and back (DECISIONS V123): the host
reference for Veranda Claude's and Veranda Ask's tokenizer (apps/claude/
code.c), and the table it is built with.

usage: x16basic.py tok IN.txt OUT.PRG      text (Latin-1 or CP437 bytes) to a PRG
       x16basic.py detok IN.PRG [OUT.txt]  a PRG to text (as the app does it)
       x16basic.py table OUT.h             the keyword table for code.c

The tokenizer is a port of the ROM's own (x16-rom basic/code2.s, `crunch`,
R49): left to right, spaces kept, '?' for PRINT, digits, ':' and ';' as
they are, text in quotes, after REM and in DATA (to a ':') as it is, at
every other place the first keyword of the table that matches (V2's
table, then the X16's statements and functions as $CE and a byte), the
characters that match none as they are. The line number is read as the
ROM's linget reads it (spaces skipped), lines sorted (the last of a number
kept, one with nothing after its number dropped), each line's link the
address of the next from $0801 on, the program ended by two zero bytes.

The text, as the apps write it and read it: letters (either case) are the
PETSCII letters $41-$5A (the capitals the X16 shows at its start); pi is
CP437's pi ($E3, PETSCII $FF); "{XX}" (two hex digits) is the byte XX
(the detokenizer writes it for every byte that has no plain form: control
and colour codes, shifted letters, graphics, '{' itself), so a PRG made
text and tokenized again is the same, byte for byte. The keyword lists
are facts of the X16's ROM (its token numbers), written out here.

MIT licence (LICENSE).
"""
import sys

V2 = ('END FOR NEXT DATA INPUT# INPUT DIM READ LET GOTO RUN IF RESTORE GOSUB RETURN REM STOP ON WAIT LOAD '
      'SAVE VERIFY DEF POKE PRINT# PRINT CONT LIST CLR CMD SYS OPEN CLOSE GET NEW TAB( TO FN SPC( THEN NOT '
      'STEP + - * / ^ AND OR > = < SGN INT ABS USR FRE POS SQR RND LOG EXP COS SIN TAN ATN PEEK LEN STR$ '
      'VAL ASC CHR$ LEFT$ RIGHT$ MID$ GO').split()
X2 = ('MON DOS OLD GEOS VPOKE VLOAD SCREEN PSET LINE FRAME RECT CHAR MOUSE COLOR TEST RESET CLS CODEX LOCATE '
      'BOOT KEYMAP BLOAD BVLOAD BVERIFY BANK FMINIT FMNOTE FMDRUM FMINST FMVIB FMFREQ FMVOL FMPAN FMPLAY '
      'FMCHORD FMPOKE PSGINIT PSGNOTE PSGVOL PSGWAV PSGFREQ PSGPAN PSGPLAY PSGCHORD').split()
X3 = ('REBOOT POWEROFF I2CPOKE SLEEP BSAVE MENU REN LINPUT# LINPUT BINPUT# HELP BANNER EXEC TILE EDIT SPRITE '
      'SPRMEM MOVSPR BASLOAD OVAL RING HBLOAD').split()
XF = 'VPEEK MX MY MB JOY HEX$ BIN$ I2CPEEK POINTER STRPTR RPT$ MWHEEL TDATA TATTR MOD'.split()
NSTAT = len(X2) + len(X3)       # 66: $CE $80 ... $C1; the functions $CE $D0 ...
assert len(V2) == 76 and NSTAT == 66

PRINT, DATA, REM, PI = 0x99, 0x83, 0x8F, 0xFF


def table(words):
    """the ROM's form: each word's last character with bit 7 set, a 0 at the end"""
    out = bytearray()
    for w in words:
        b = w.encode('ascii')
        out += b[:-1] + bytes([b[-1] | 0x80])
    return bytes(out) + b'\0'


T1, T2, T3 = table(V2), table(X2), table(X3 + XF)


def match(buf, x, tab, count, step_count=True):
    """crunch's search of one table from buf[x]: (count, x after) of the
    first keyword that matches, else (count reached, None)"""
    y = 0
    while tab[y]:
        i, j = x, y
        while True:
            c = buf[i]
            if 97 <= c < 128:
                c -= 32
            d = (c - tab[j]) & 0xFF
            if d == 0:
                i += 1
                j += 1
                continue
            if d == 0x80:
                return count, i + 1
            break
        count += 1
        while not tab[y] & 0x80:
            y += 1
        y += 1
    return count, None


def crunch(line):
    """one line's text (PETSCII bytes, after its number) as the ROM stores it"""
    buf = bytes(line) + b'\0'
    out = bytearray()
    x = 0
    dores = 4

    def stuffed(c):
        nonlocal dores
        if c == ord(':'):
            dores = 0
        elif c == DATA:
            dores = 0x49
        return c == REM

    while True:
        c = buf[x]
        if c >= 128:
            if c != PI:
                x += 1
                continue
            out.append(c)
            x += 1
            if c == 0:
                break
            continue
        if c == 0:
            break
        if c == 32:
            out.append(c)
            x += 1
            continue
        if c == 34:
            out.append(c)
            x += 1
            while buf[x] and buf[x] != 34:
                out.append(buf[x])
                x += 1
            if buf[x] == 34:
                out.append(34)
                x += 1
                continue
            break
        if dores & 0x40:
            out.append(c)
            x += 1
            stuffed(c)
            continue
        if c == ord('?'):
            out.append(PRINT)
            x += 1
            continue
        if ord('0') <= c < 60:
            out.append(c)
            x += 1
            stuffed(c)
            continue
        n, after = match(buf, x, T1, 0)
        if after is not None:
            tok = 0x80 | n
            out.append(tok)
            x = after
            if stuffed(tok):
                while buf[x]:
                    out.append(buf[x])
                    x += 1
                break
            continue
        n, after = match(buf, x, T2, 0)
        if after is None:
            n, after = match(buf, x, T3, n)
        if after is not None:
            out += bytes([0xCE, 0x80 | n if n < NSTAT else n - NSTAT + 0xD0])
            x = after
            continue
        out.append(c)
        x += 1
        stuffed(c)
    return bytes(out)


def to_petscii(t):
    """the text's bytes (CP437 or Latin-1) as PETSCII: letters to $41-$5A,
    {XX} to the byte XX, pi, a tab a space, anything else past ASCII '?'"""
    out = bytearray()
    i = 0
    while i < len(t):
        c = t[i]
        if c == ord('{') and i + 3 < len(t) and t[i + 3] == ord('}'):
            try:
                out.append(int(t[i + 1:i + 3].decode('ascii'), 16))
                i += 4
                continue
            except ValueError:
                pass
        if 97 <= c <= 122:
            c -= 32
        elif c == 9:
            c = 32
        elif c == 0xE3:
            c = PI
        elif c >= 127 or c < 32:
            c = ord('?')
        out.append(c)
        i += 1
    return bytes(out)


def tokenize(text):
    """text (bytes, lines ended by LF, CR or CR LF) to a PRG; ValueError
    names a line without a number, a number past 63999 or a line too long"""
    lines = {}
    for k, l in enumerate(text.replace(b'\r\n', b'\n').replace(b'\r', b'\n').split(b'\n')):
        p = to_petscii(l)
        i = 0
        while i < len(p) and p[i] == 32:
            i += 1
        if i == len(p):
            continue
        if not 48 <= p[i] <= 57:
            raise ValueError('line %d has no number' % (k + 1))
        n = 0
        while i < len(p) and (48 <= p[i] <= 57 or p[i] == 32):
            if p[i] != 32:
                n = n * 10 + p[i] - 48
                if n > 63999:
                    raise ValueError('line %d: its number is past 63999' % (k + 1))
            i += 1
        body = crunch(p[i:])
        if len(body) > 250:
            raise ValueError('line %d is too long' % (k + 1))
        if body:
            lines[n] = body
        else:
            lines.pop(n, None)
    out = bytearray(b'\x01\x08')
    a = 0x0801
    for n in sorted(lines):
        b = lines[n]
        a += 4 + len(b) + 1
        out += bytes([a & 255, a >> 8, n & 255, n >> 8]) + b + b'\0'
    return bytes(out + b'\0\0')


def word(tok, ext=None):
    if ext is None:
        return V2[tok - 0x80]
    if ext >= 0xD0:
        return XF[ext - 0xD0] if ext - 0xD0 < len(XF) else None
    i = ext - 0x80
    return (X2 + X3)[i] if i < NSTAT else None


def plain(c):
    """a byte's text: itself, a capital, pi, else {XX}"""
    if c == PI:
        return b'\xe3'
    if 32 <= c <= 0x5F and c != 0x5C or c == 0x5C or 0x7C <= c <= 0x7E:
        return bytes([c])
    return b'{%02X}' % c


def detokenize(prg):
    """a PRG (from $0801) as text, lines ended by LF; ValueError when it is not BASIC"""
    if len(prg) < 4 or prg[0] != 1 or prg[1] != 8:
        raise ValueError('not a BASIC program (load address $0801)')
    out = []
    p = 2
    while p + 1 < len(prg) and (prg[p] or prg[p + 1]):
        if p + 4 > len(prg):
            raise ValueError('cut short')
        n = prg[p + 2] | prg[p + 3] << 8
        p += 4
        t = bytearray(b'%d ' % n)
        quote = rem = False
        while p < len(prg) and prg[p]:
            c = prg[p]
            p += 1
            if c == 34:
                quote = not quote
            if c >= 0x80 and c != PI and not quote and not rem:
                if c == 0xCE and p < len(prg):
                    w = word(c, prg[p])
                    if w is None:
                        t += b'{CE}'
                        continue
                    p += 1
                else:
                    if c > 0xCB:
                        t += b'{%02X}' % c
                        continue
                    w = word(c)
                    rem = c == REM
                t += w.encode('ascii')
                continue
            t += plain(c)
        p += 1
        out.append(bytes(t))
    return b'\n'.join(out) + (b'\n' if out else b'')


def ctable(path):
    """code.c's table: the three lists as the ROM keeps them"""
    def arr(name, b):
        rows = ', '.join('0x%02X' % c for c in b)
        return 'static const unsigned char %s[%d] = { %s };\n' % (name, len(b), rows)
    with open(path, 'w') as f:
        f.write('/* the X16 ROM BASIC keywords (R49), as its tables keep them: each\n'
                '   word\'s last character with bit 7 set, a 0 after the last. Written\n'
                '   by tools/x16basic.py table (DECISIONS V123). */\n')
        f.write('#define BT_NSTAT %d\n' % NSTAT)
        f.write(arr('bt_v2', T1) + arr('bt_x2', T2) + arr('bt_x3', T3))


def main():
    a = sys.argv[1:]
    if len(a) == 3 and a[0] == 'tok':
        open(a[2], 'wb').write(tokenize(open(a[1], 'rb').read()))
    elif len(a) in (2, 3) and a[0] == 'detok':
        t = detokenize(open(a[1], 'rb').read())
        if len(a) == 3:
            open(a[2], 'wb').write(t)
        else:
            sys.stdout.buffer.write(t)
    elif len(a) == 2 and a[0] == 'table':
        ctable(a[1])
    else:
        sys.exit(__doc__)


if __name__ == '__main__':
    main()
