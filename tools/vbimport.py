#!/usr/bin/env python3
"""vbasic.py import (DECISIONS V99): a tokenized Commodore BASIC V2 program
(a .PRG as the C64, the VIC-20 and the X16's BASIC save it) as VeraBASIC
source text.

usage (through tools/vbasic.py):
       vbasic.py import FILE.PRG [-o OUT.bas]

The PRG: its load address (2 bytes), then lines: the next line's address
(2; 0 ends), the line number (2), the tokens, 0. V2's tokens ($80-$CB, and
$FF for pi) are written as words with a blank before and after them, so a
crunched line (FORI=1TO9) becomes FOR I=1 TO 9; text in quotes, after REM
and in DATA stays as it is. PETSCII becomes Latin-1: letters as letters
(the shifted ones, $C1-$DA, as lower case), a character with no Latin-1
form inside quotes as " + CHR$(n) + ", elsewhere as a comment. An X16
BASIC token ($CE and the next byte: its extended statements) has no
VeraBASIC form: the line keeps it as a REM and a warning names it.
The list of V2's token numbers is published data, written fresh here
(docs/vbasic/manual/from-v2.md; plan section 10).

Python 3 only; run with -I as the other tools. MIT licence (LICENSE).
"""

V2 = ('END FOR NEXT DATA INPUT# INPUT DIM READ LET GOTO RUN IF RESTORE GOSUB RETURN REM STOP ON WAIT LOAD '
      'SAVE VERIFY DEF POKE PRINT# PRINT CONT LIST CLR CMD SYS OPEN CLOSE GET NEW TAB( TO FN SPC( THEN NOT '
      'STEP + - * / ^ AND OR > = < SGN INT ABS USR FRE POS SQR RND LOG EXP COS SIN TAN ATN PEEK LEN STR$ '
      'VAL ASC CHR$ LEFT$ RIGHT$ MID$ GO').split()
TOKENS = {0x80 + i: w for i, w in enumerate(V2)}
TOKENS[0xFF] = 'PI'
# what VeraBASIC writes for a few V2 spellings
SPELL = {'INPUT#': 'INPUT #', 'PRINT#': 'PRINT #', 'GO': 'GO'}
SYMBOLS = set('+-*/^><=')


def petscii(b, quoted):
    """a PETSCII byte -> (text, ok)"""
    if 0x41 <= b <= 0x5A:
        return chr(b), True                     # (upper case in the ROM's first set)
    if 0xC1 <= b <= 0xDA:
        return chr(b - 0x80).lower(), True
    if 0x20 <= b <= 0x5D and b != 0x5C:
        return chr(b), True
    if b == 0x5C:
        return '£', True                   # the pound sign
    return '', False


class ImportError_(Exception):
    pass


def import_prg(data):
    """the PRG's bytes -> (the source text, warnings)"""
    if len(data) < 4:
        raise ImportError_('not a BASIC program')
    i, out, warn = 2, [], []
    while i + 4 <= len(data):
        nxt = data[i] | data[i + 1] << 8
        if nxt == 0:
            break
        num = data[i + 2] | data[i + 3] << 8
        i += 4
        line, quoted, raw = [], False, False    # raw: after REM or in DATA
        while i < len(data) and data[i] != 0:
            b = data[i]
            i += 1
            if quoted or raw:
                if b == 0x22:
                    quoted = not quoted
                    line.append('"')
                    continue
                if raw and not quoted and b == ord(':') and raw == 'DATA':
                    raw = False
                    line.append(':')
                    continue
                t, ok = petscii(b, quoted)
                if ok:
                    line.append(t)
                elif quoted:
                    line.append('" + CHR$(%d) + "' % b)
                else:
                    line.append('?')
                    warn.append('line %d: PETSCII %d after REM' % (num, b))
                continue
            if b == 0x22:
                quoted = True
                line.append('"')
            elif b == 0xCE and i < len(data):
                warn.append('line %d: an X16 BASIC statement ($CE %02X): kept as a comment' % (num, data[i]))
                i += 1
                line.append(" REM X16 BASIC $CE%02X " % data[i - 1])
                raw = 'REM'
            elif b in TOKENS:
                w = SPELL.get(TOKENS[b], TOKENS[b])
                if w in SYMBOLS or len(w) == 1:
                    line.append(w)
                else:
                    # (a function, TAB( and SPC(: no blank before its parenthesis)
                    line.append(' %s' % w if w.endswith('(') or 0xB4 <= b <= 0xCA else ' %s ' % w)
                if w == 'REM':
                    raw = 'REM'
                elif w == 'DATA':
                    raw = 'DATA'
            elif b >= 0x80:
                warn.append('line %d: token %02X unknown: left out' % (num, b))
            else:
                t, ok = petscii(b, False)
                line.append(t if ok else '')
        i += 1
        # blanks: one between words, none at the ends (strings and comments kept)
        out.append('%d %s' % (num, _tidy(''.join(line))))
    return '\n'.join(out) + '\n', warn


def _tidy(s):
    """single blanks outside quotes and REM, none at the ends"""
    r, q, rem, prev = [], False, False, ''
    k = 0
    while k < len(s):
        c = s[k]
        if rem:
            r.append(c)
        elif c == '"':
            q = not q
            r.append(c)
        elif q:
            r.append(c)
        elif c == ' ':
            if r and r[-1] != ' ':
                r.append(' ')
        else:
            r.append(c)
            if ''.join(r).upper().endswith('REM '):
                rem = True
        k += 1
        if not q and not rem and ''.join(r[-4:]).upper() == ' REM':
            rem = True
    return ''.join(r).strip(' ')


def crunch(text, load=0x0801):
    """a V2 listing (upper case, its line numbers) -> PRG bytes, as V2
    tokenizes it (the longest keyword first; nothing in quotes, after REM,
    in DATA): the gates' way to make a PRG to import"""
    words = sorted(((w, t) for t, w in TOKENS.items() if t != 0xFF), key=lambda x: -len(x[0]))
    prg, addr = bytearray(load.to_bytes(2, 'little')), load
    for ln in text.strip('\n').split('\n'):
        num, rest = ln.split(' ', 1) if ' ' in ln else (ln, '')
        body, k, q, raw = bytearray(), 0, False, False
        while k < len(rest):
            c = rest[k]
            if c == '"':
                q = not q
            if q or raw or c == '"':
                if raw == 'DATA' and c == ':' and not q:
                    raw = False
                body.append(ord(c))
                k += 1
                continue
            if c == ' ':
                k += 1
                continue
            for w, t in words:
                if rest.startswith(w, k):
                    body.append(t)
                    k += len(w)
                    if w in ('REM', 'DATA'):
                        raw = w
                    break
            else:
                body.append(ord(c))
                k += 1
        line = int(num).to_bytes(2, 'little') + bytes(body) + b'\0'
        addr += 2 + len(line)
        prg += addr.to_bytes(2, 'little') + line
    return bytes(prg + b'\0\0')
