#!/usr/bin/env python3
"""VeraBASIC's tokenizer on the PC: tokenize, detokenize, prepare, and the
program document's records (docs/vbasic/FORMAT.md).

usage: vbtokens.py check FILE.bas...        structural errors as file:line: message
       vbtokens.py canon FILE.bas [-o OUT]  the canonical form (detok(tok(S)))
       vbtokens.py tok FILE.bas -o OUT.cvt  tokenize, prepare, write the program
                                            document (GEOS VLIR, VeraBASIC V1.0)
       vbtokens.py list FILE.cvt            the program document as source
       vbtokens.py dump FILE.bas            the records, in hex, and the tables

The tables come from tools/vbtokens_gen.py, which tools/vbgen.py makes from
vbasic/keywords.tbl. Python 3 only; run with -I as the other tools.

MIT licence (LICENSE). VeraBASIC's own design: no code or token values of
any other BASIC.
"""
import fractions
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import vbtokens_gen as G  # noqa: E402

T_EOL, T_INTDEC, T_INTHEX, T_INTBIN, T_FLOAT, T_STRING, T_VAR, T_LINEREF, T_NAMEREF, \
    T_COMMENT, T_DATA, T_BLOCK = range(12)
T_EXT = 0xFF
LOCAL_BIT = 0x8000
MAX_TOKENS = 248          # a line record is at most 255 bytes: 6 + 248 + 1
MAX_NAME = 32
PUNCT = set('()+-*/^\\=<>,;:#')
HEADER_SIZE = 24
RUNTIME_VERSION = 1

# symbol kinds (bits)
K_VAR, K_ARRAY, K_CONST, K_SUB, K_FUNCTION, K_LABEL, K_BUILTIN = 1, 2, 4, 8, 16, 32, 64
TY_FLOAT, TY_INT, TY_STR = 0, 1, 2

KW = {}            # name -> code
KWINFO = {}        # code -> dict
COMPOUND = {}      # (code1, code2) -> code
for _name, (_code, _kind, _args, _ovl, _flags, _value) in G.KEYWORDS.items():
    KW[_name] = _code
    _info = {'name': _name, 'code': _code, 'kind': _kind, 'args': _args, 'overlay': _ovl,
             'flags': set(_flags.split()), 'value': _value, 'procpos': set()}
    if _kind == 'stmt' and _args not in ('*', '-'):
        _pos = [p.strip().strip('[]').strip() for p in _args.replace('[', ',[').split(',')
                if p.strip().strip('[]')]
        _info['procpos'] = {i for i, p in enumerate(_pos) if p == 'p'}
    KWINFO[_code] = _info
for _name, _code in KW.items():
    if ' ' in _name:
        _a, _b = _name.split()
        COMPOUND[(KW[_a], KW[_b])] = _code
FIRST_WORDS = {a for a, _ in COMPOUND}


def kw(name):
    return KW[name]


class VBError(Exception):
    pass


# ----------------------------------------------------------------------
# floats: the X16 ROM's 5-byte format (exponent, 4 mantissa bytes, sign in
# the first mantissa byte's top bit), the correctly rounded value

def float5(text):
    v = fractions.Fraction(text)
    if v == 0:
        return bytes(5)
    neg = v < 0
    v = abs(v)
    e = v.numerator.bit_length() - v.denominator.bit_length()
    # v = m * 2**(e - 32) with 2**31 <= m < 2**32
    while True:
        scaled = v * (fractions.Fraction(2) ** (32 - e))
        if scaled >= 2 ** 32:
            e += 1
        elif scaled < 2 ** 31:
            e -= 1
        else:
            break
    m = scaled.numerator // scaled.denominator
    rest = scaled - m
    if rest > fractions.Fraction(1, 2) or (rest == fractions.Fraction(1, 2) and m & 1):
        m += 1
        if m == 2 ** 32:
            m >>= 1
            e += 1
    exp = e + 128
    if exp > 255:
        raise VBError('Number too big')
    if exp < 1:
        return bytes(5)
    mb = m.to_bytes(4, 'big')
    return bytes([exp, (mb[0] & 0x7F) | (0x80 if neg else 0)]) + mb[1:]


def float5_value(b):
    if b[0] == 0:
        return 0.0
    m = ((b[1] | 0x80) << 24) | (b[2] << 16) | (b[3] << 8) | b[4]
    v = m * 2.0 ** (b[0] - 128 - 32)
    return -v if b[1] & 0x80 else v


# ----------------------------------------------------------------------
# the program

class Line:
    def __init__(self, number, src, flags, toks):
        self.number, self.src, self.flags, self.toks = number, src, flags, bytearray(toks)
        self.off = 0          # the record's offset in record 1 (layout())

    @property
    def indent(self):
        return self.flags >> 4


class Sym:
    def __init__(self, spelling):
        self.name = spelling
        self.key = spelling.upper()
        self.type = TY_STR if spelling.endswith('$') else TY_INT if spelling.endswith('%') else TY_FLOAT
        self.kind = 0
        self.target = 0
        self.value = 0
        self.src = 0


class Proc:
    def __init__(self, sym, is_function, start, line):
        self.sym, self.is_function, self.start, self.line = sym, is_function, start, line
        self.end = 0
        self.frame = []       # [(sym, flags)]: F_* below; the index is the frame slot
        self.nparams = 0


F_BYREF, F_ARRAY, F_PARAM, F_RESULT = 1, 2, 4, 8


class Program:
    def __init__(self):
        self.lines = []
        self.syms = []
        self.symidx = {}
        self.procs = []
        self.errors = []      # (source line, message)
        self.line_index = []  # (number, offset)
        self.data_index = []  # offsets of the DATA items
        self.option_integer = False
        self.defint = 0       # bit n: letter A + n
        self.prepared = False

    def sym(self, spelling, src=0):
        k = spelling.upper()
        if k not in self.symidx:
            self.symidx[k] = len(self.syms)
            self.syms.append(Sym(spelling))
            self.syms[-1].src = src
        return self.symidx[k]

    def error(self, src, msg):
        self.errors.append((src, msg))


# ----------------------------------------------------------------------
# tokenize

def is_letter(c):
    return c.isascii() and c.isalpha()


def is_word_char(c):
    return c.isascii() and (c.isalnum() or c == '_')


class Lexer:
    """one source line to tokens"""

    def __init__(self, prog, text, src, first):
        self.p, self.s, self.src = prog, text, src
        self.i = 0
        self.out = bytearray()
        self.stmt_start = True
        self.first_stmt = first      # the line's first statement (a label may start it)
        self.label = False
        self.ref = None              # 'line' after GOTO ..., 'proc' after CALL/SUB
        self.ref_list = False        # ON ... GOTO 10, 20: the list goes on after ","
        self.stmt_kw = None          # the statement's keyword (procedure positions)
        self.argno = 0
        self.arg_start = False
        self.depth = 0
        self.data_mode = False
        self.i_raw = 0

    def fail(self, msg):
        raise VBError(msg)

    def peek_nonspace(self, j=None):
        j = self.i if j is None else j
        while j < len(self.s) and self.s[j] in ' \t':
            j += 1
        return j

    def emit_kw(self, code, at_start):
        if code > 0xFF:
            self.out += bytes([T_EXT, code & 0xFF])
        else:
            self.out.append(code)
        # a block keyword starts a statement (DO WHILE, LOOP UNTIL and RESUME
        # NEXT use the words inside one); ELSE ends one
        if 'block' in KWINFO[code]['flags'] and (at_start or code == KW['ELSE']):
            self.out += bytes([T_BLOCK, 0, 0])

    def read_word(self, j):
        k = j
        while k < len(self.s) and is_word_char(self.s[k]):
            k += 1
        if k < len(self.s) and self.s[k] in '$%':
            k += 1
        return self.s[j:k], k

    def run(self):
        s = self.s
        while True:
            self.i = self.peek_nonspace()
            if self.i >= len(s):
                break
            c = s[self.i]
            if self.data_mode:
                self.lex_data()
                continue
            if c == '"':
                self.lex_string()
                self.after_operand()
            elif c == "'":
                self.out.append(ord("'"))
                self.lex_comment(self.i + 1)
            elif c == '?':
                self.i += 1
                self.keyword(kw('PRINT'))
            elif c.isdigit() or (c == '.' and self.i + 1 < len(s) and s[self.i + 1].isdigit()):
                self.lex_number()
            elif c == '$' or (c == '%' and self.i + 1 < len(s) and s[self.i + 1] in '01'):
                self.lex_radix()
            elif is_letter(c):
                self.lex_word()
            elif c in PUNCT:
                self.lex_punct()
            else:
                self.fail('Unexpected character %r' % c)
        if len(self.out) > MAX_TOKENS:
            self.fail('Line too long')
        return self.out

    # -- context
    def after_operand(self):
        self.stmt_start = False
        self.arg_start = False
        if not self.ref_list:
            self.ref = None

    def new_statement(self):
        self.stmt_start = True
        self.ref = None
        self.ref_list = False
        self.stmt_kw = None
        self.argno = 0
        self.depth = 0
        self.arg_start = False

    # -- pieces
    def lex_string(self):
        s, j = self.s, self.i + 1
        buf = []
        while j < len(s):
            if s[j] == '"':
                if j + 1 < len(s) and s[j + 1] == '"':
                    buf.append('"')
                    j += 2
                    continue
                j += 1
                break
            buf.append(s[j])
            j += 1
        b = ''.join(buf).encode('latin-1')
        if len(b) > 255:
            self.fail('String too long')
        self.out += bytes([T_STRING, len(b)]) + b
        self.i = j

    def lex_comment(self, j):
        b = self.s[j:].encode('latin-1')
        if len(b) > 255:
            self.fail('Line too long')
        self.out += bytes([T_COMMENT, len(b)]) + b
        self.i = len(self.s)

    def lex_data(self):
        """raw DATA items up to ":" (outside quotes) or the line's end"""
        s, j = self.s, self.i_raw
        while True:
            k, q = j, False
            while k < len(s) and (q or s[k] not in ',:'):
                if s[k] == '"':
                    q = not q
                k += 1
            b = s[j:k].encode('latin-1')
            if len(b) > 255:
                self.fail('Line too long')
            self.out += bytes([T_DATA, len(b)]) + b
            if k < len(s) and s[k] == ',':
                self.out.append(ord(','))
                j = k + 1
                continue
            self.i = k
            break
        self.data_mode = False
        self.stmt_start = False

    def lex_number(self):
        s, j = self.s, self.i
        while j < len(s) and s[j].isdigit():
            j += 1
        is_float = False
        if j < len(s) and s[j] == '.':
            is_float = True
            j += 1
            while j < len(s) and s[j].isdigit():
                j += 1
        if j < len(s) and s[j] in 'eE':
            k = j + 1
            if k < len(s) and s[k] in '+-':
                k += 1
            if k < len(s) and s[k].isdigit():
                is_float = True
                while k < len(s) and s[k].isdigit():
                    k += 1
                j = k
        text = s[self.i:j]
        self.i = j
        if self.ref == 'line' or self.ref == 'stmt':
            if is_float or int(text) > 0xFFFF:
                self.fail('Line number expected')
            self.out += bytes([T_LINEREF]) + int(text).to_bytes(2, 'little') + bytes(3)
            self.stmt_start = False
            if not self.ref_list:
                self.ref = None
            self.arg_start = False
            return
        if not is_float and int(text) <= 32767:
            self.out += bytes([T_INTDEC]) + int(text).to_bytes(2, 'little')
        else:
            b = text.encode('latin-1')
            if len(b) > 255:
                self.fail('Number too long')
            self.out += bytes([T_FLOAT]) + float5(text) + bytes([len(b)]) + b
        self.after_operand()

    def lex_radix(self):
        s, j = self.s, self.i + 1
        if s[self.i] == '$':
            while j < len(s) and s[j] in '0123456789abcdefABCDEF':
                j += 1
            if j == self.i + 1:
                self.fail('Unexpected character \'$\'')
            v, tag = int(s[self.i + 1:j], 16), T_INTHEX
        else:
            while j < len(s) and s[j] in '01':
                j += 1
            v, tag = int(s[self.i + 1:j], 2), T_INTBIN
        if v > 0xFFFF:
            self.fail('Number too big')
        if j < len(s) and is_word_char(s[j]):
            self.fail('Unexpected character %r' % s[j])
        self.out += bytes([tag]) + v.to_bytes(2, 'little')
        self.i = j
        self.after_operand()

    def lex_punct(self):
        s, c = self.s, self.s[self.i]
        two = s[self.i:self.i + 2]
        if two in ('<=', '<>', '>='):
            self.i += 2
            self.out.append(kw(two))
            self.stmt_start = False
            self.arg_start = False
            return
        self.i += 1
        self.out.append(ord(c))
        if c == ':' and self.depth == 0:
            self.new_statement()
            return
        if c == '(':
            self.depth += 1
        elif c == ')':
            self.depth = max(0, self.depth - 1)
        if c == ',' and self.depth == 0:
            self.argno += 1
            self.arg_start = True
            if self.ref_list:
                return            # ON n GOTO 10, 20: the list continues
        else:
            self.arg_start = False
        self.stmt_start = False
        if c != ',' or not self.ref_list:
            self.ref = None
            self.ref_list = False

    def lex_word(self):
        word, j = self.read_word(self.i)
        up = word.upper()
        if up in KW:
            code = KW[up]
            if code in FIRST_WORDS:
                k = self.peek_nonspace(j)
                w2, j2 = self.read_word(k) if k < len(self.s) and is_letter(self.s[k]) else ('', k)
                if w2.upper() in KW and (code, KW[w2.upper()]) in COMPOUND:
                    code, j = COMPOUND[(code, KW[w2.upper()])], j2
            self.i = j
            self.keyword(code)
            return
        name = word[:-1] if word[-1] in '$%' else word
        if len(name) > MAX_NAME:
            self.fail('Name too long')
        self.i = j
        sym = self.p.sym(word, self.src)
        nxt = self.peek_nonspace()
        if self.stmt_start:
            nc = self.s[nxt] if nxt < len(self.s) else ''
            if self.first_stmt and nc == ':' and not self.out:
                self.out += bytes([T_NAMEREF]) + sym.to_bytes(2, 'little') + bytes(3)
                self.label = True
                return
            if nc == '=' and self.s[nxt:nxt + 2] not in ('=<', '=>'):
                self.var(sym)
                return
            if nc == '(':
                close = self.match_paren(nxt)
                after = self.peek_nonspace(close)
                if after < len(self.s) and self.s[after] == '=':
                    self.var(sym)
                    return
            self.nameref(sym)          # a SUB call
            self.stmt_start = False
            self.stmt_kw = None
            self.argno = 0
            self.arg_start = True
            return
        if self.ref in ('line', 'proc'):
            self.nameref(sym)
            if not self.ref_list:
                self.ref = None
            self.arg_start = False
            return
        if (self.stmt_kw is not None and self.depth == 0 and self.arg_start
                and self.argno in KWINFO[self.stmt_kw]['procpos']):
            nc = self.s[nxt] if nxt < len(self.s) else ''
            if nc in ('', ',', ':', "'"):
                self.nameref(sym)
                self.arg_start = False
                return
        self.var(sym)

    def match_paren(self, j):
        depth, q = 0, False
        while j < len(self.s):
            c = self.s[j]
            if c == '"':
                q = not q
            elif not q:
                if c == '(':
                    depth += 1
                elif c == ')':
                    depth -= 1
                    if depth == 0:
                        return j + 1
            j += 1
        return j

    def var(self, sym):
        self.out += bytes([T_VAR]) + sym.to_bytes(2, 'little')
        self.after_operand()

    def nameref(self, sym):
        self.out += bytes([T_NAMEREF]) + sym.to_bytes(2, 'little') + bytes(3)

    def keyword(self, code):
        info = KWINFO[code]
        at_start = self.stmt_start
        self.emit_kw(code, at_start)
        fl = info['flags']
        if 'raw=rem' in fl:
            self.lex_comment(self.i)
            return
        if 'raw=data' in fl and at_start:
            self.data_mode = True
            self.i_raw = self.i
            return
        self.ref_list = False
        if 'ref=stmt' in fl:
            k = self.peek_nonspace()
            if k < len(self.s) and self.s[k].isdigit():
                self.ref = 'stmt'
                self.stmt_start = False
            else:
                self.new_statement()
            return
        self.ref = None
        if 'ref=line' in fl:
            self.ref = 'line'
            self.ref_list = code in (kw('GOTO'), kw('GOSUB'))
        elif 'ref=proc' in fl:
            self.ref = 'proc'
        if at_start:
            self.stmt_kw = code
            self.argno = 0
            self.arg_start = True
        else:
            self.arg_start = False
        self.stmt_start = False


def split_lines(text):
    if isinstance(text, bytes):
        text = text.decode('latin-1')
    return text.replace('\r\n', '\n').replace('\r', '\n').split('\n')


def tokenize(text):
    """source text -> Program (not prepared); lexical errors in .errors"""
    prog = Program()
    for src, raw in enumerate(split_lines(text), 1):
        line = raw.rstrip(' \t')
        if not line.strip():
            continue
        j, col = 0, 0
        while j < len(line) and line[j] in ' \t':
            col += 2 if line[j] == '\t' else 1
            j += 1
        number = 0
        if j < len(line) and line[j].isdigit():
            k = j
            while k < len(line) and line[k].isdigit():
                k += 1
            number = int(line[j:k])
            if not 1 <= number <= 0xFFFF:
                prog.error(src, 'Line number out of range')
                continue
            j, col = k, 0
            while j < len(line) and line[j] in ' \t':
                col += 2 if line[j] == '\t' else 1
                j += 1
            col = max(0, col - 1)
        indent = min(15, col // 2)
        lx = Lexer(prog, line[j:], src, True)
        try:
            toks = lx.run()
        except VBError as e:
            prog.error(src, str(e))
            continue
        flags = (indent << 4) | (2 if lx.label else 0)
        prog.lines.append(Line(number, src, flags, toks))
    return prog


# ----------------------------------------------------------------------
# decoding a token stream

class Tok:
    __slots__ = ('pos', 'tag', 'val', 'raw', 'end')

    def __init__(self, pos, tag, val, raw, end):
        self.pos, self.tag, self.val, self.raw, self.end = pos, tag, val, raw, end

    def is_kw(self, *names):
        return self.tag == 'kw' and any(self.val == KW[n] for n in names)

    def is_p(self, c):
        return self.tag == 'p' and self.val == c

    def __repr__(self):
        return 'Tok(%d,%s,%r)' % (self.pos, self.tag, self.val)


def decode(toks):
    out, i, n = [], 0, len(toks)
    while i < n:
        b = toks[i]
        if b in (T_INTDEC, T_INTHEX, T_INTBIN):
            out.append(Tok(i, 'int', toks[i + 1] | toks[i + 2] << 8, b, i + 3))
            i += 3
        elif b == T_FLOAT:
            ln = toks[i + 6]
            out.append(Tok(i, 'float', bytes(toks[i + 1:i + 6]), bytes(toks[i + 7:i + 7 + ln]), i + 7 + ln))
            i += 7 + ln
        elif b in (T_STRING, T_COMMENT, T_DATA):
            ln = toks[i + 1]
            out.append(Tok(i, {T_STRING: 'str', T_COMMENT: 'rem', T_DATA: 'data'}[b], bytes(toks[i + 2:i + 2 + ln]),
                           None, i + 2 + ln))
            i += 2 + ln
        elif b == T_VAR:
            out.append(Tok(i, 'var', toks[i + 1] | toks[i + 2] << 8, None, i + 3))
            i += 3
        elif b in (T_LINEREF, T_NAMEREF):
            out.append(Tok(i, 'lref' if b == T_LINEREF else 'nref', toks[i + 1] | toks[i + 2] << 8,
                           toks[i + 3] | toks[i + 4] << 8 | toks[i + 5] << 16, i + 6))
            i += 6
        elif b == T_BLOCK:
            out.append(Tok(i, 'blk', toks[i + 1] | toks[i + 2] << 8, None, i + 3))
            i += 3
        elif 0x20 <= b <= 0x7F:
            out.append(Tok(i, 'p', chr(b), None, i + 1))
            i += 1
        elif 0x80 <= b <= 0xFE:
            if b not in KWINFO:
                raise VBError('unknown token $%02X' % b)
            out.append(Tok(i, 'kw', b, None, i + 1))
            i += 1
        elif b == T_EXT:
            code = 0xFF00 | toks[i + 1]
            if code not in KWINFO:
                raise VBError('unknown token $FF $%02X' % toks[i + 1])
            out.append(Tok(i, 'kw', code, None, i + 2))
            i += 2
        else:
            raise VBError('bad token byte $%02X at %d' % (b, i))
    return out


# ----------------------------------------------------------------------
# detokenize: the canonical form

def fmt_int(tag, v):
    if tag == T_INTDEC:
        return str(v)
    if tag == T_INTHEX:
        return '$%02X' % v if v < 0x100 else '$%04X' % v
    return '%' + (format(v, '08b') if v < 0x100 else format(v, '016b'))


def local_sym(prog, pos_abs, slot):
    for pr in prog.procs:
        if pr.start <= pos_abs <= pr.end:
            return pr.frame[slot & 0x7FFF][0]
    raise VBError('a local slot outside a procedure')


def detok_line(prog, line):
    toks = decode(line.toks)
    pieces = []       # (text, class)
    in_defint = False
    stmt_first = True
    i = 0
    while i < len(toks):
        t = toks[i]
        if t.tag == 'blk':
            i += 1
            continue
        prev = pieces[-1][1] if pieces else None
        if t.tag == 'int':
            pieces.append((fmt_int(line.toks[t.pos], t.val), 'v'))
        elif t.tag == 'float':
            pieces.append((t.raw.decode('latin-1'), 'v'))
        elif t.tag == 'str':
            pieces.append(('"%s"' % t.val.decode('latin-1').replace('"', '""'), 'v'))
        elif t.tag == 'var':
            sym = local_sym(prog, line.off + 6 + t.pos, t.val) if t.val & LOCAL_BIT else t.val
            nxt = toks[i + 1] if i + 1 < len(toks) else None
            pieces.append((prog.syms[sym].name, 'n' if nxt is not None and nxt.is_p('(') else 'v'))
        elif t.tag == 'nref':
            nxt = toks[i + 1] if i + 1 < len(toks) else None
            cls = 'n' if nxt is not None and nxt.is_p('(') else ('call' if stmt_first else 'v')
            if i == 0 and line.flags & 2:
                cls = 'v'
            pieces.append((prog.syms[t.val].name, cls))
        elif t.tag == 'lref':
            pieces.append((str(t.val), 'v'))
        elif t.tag == 'rem':
            pieces.append((t.val.decode('latin-1'), 'raw'))
        elif t.tag == 'data':
            pieces.append((t.val.decode('latin-1'), 'raw'))
            if i + 1 < len(toks) and toks[i + 1].is_p(','):
                pieces.append((',', 'rawsep'))
                i += 1
        elif t.tag == 'p':
            c = t.val
            if c in '-+' and prev not in ('v', ')'):
                cls = 'u'
            elif c == '-' and in_defint:
                cls = 'u'
            elif c in '(),;:#':
                cls = c
            elif c == "'":
                cls = "'"
            else:
                cls = 'o'
            if in_defint and c == '-':
                cls = 'tight'
            pieces.append((c, cls))
        elif t.tag == 'kw':
            info = KWINFO[t.val]
            name = info['name']
            if info['kind'] == 'op':
                cls = 'o'
                if name == 'NOT':
                    cls = 'k'
            elif info['kind'] == 'func':
                cls = 'v' if info['args'].startswith('->') else 'f'
            else:
                cls = 'k'
            if 'raw=rem' in info['flags'] or ('raw=data' in info['flags'] and stmt_first):
                cls = 'kraw'
            pieces.append((name, cls))
            if t.val == KW['DEFINT']:
                in_defint = True
        stmt_first = False
        if t.is_p(':') or (t.tag == 'kw' and 'ref=stmt' in KWINFO[t.val]['flags']):
            stmt_first = True
            in_defint = False
        i += 1
    out = []
    prev = None
    for text, cls in pieces:
        if prev is not None and space_between(prev, cls, text):
            out.append(' ')
        out.append(text)
        prev = cls
    body = ''.join(out)
    head = ''
    if line.number:
        head = str(line.number)
        if body:
            head += ' ' + '  ' * line.indent
    else:
        head = '  ' * line.indent
    return head + body


def space_between(prev, cls, text):
    if cls in ('raw', 'rawsep') or prev in ('rawsep', 'kraw', "'"):
        return False
    if cls in (',', ';', ':', ')'):
        return False
    if prev in ('(', '#', 'u'):
        return False
    if cls == 'tight' or prev == 'tight':
        return False
    if cls == '(' and prev in ('n', 'f'):
        return False
    return True


def detok(prog):
    out, last = [], 0
    layout(prog)
    for line in prog.lines:
        out += [''] * (line.src - last - 1)
        out.append(detok_line(prog, line))
        last = line.src
    return '\n'.join(out) + '\n' if out else ''


def canon(text):
    prog = tokenize(text)
    if prog.errors:
        raise VBError('%d: %s' % prog.errors[0])
    return detok(prog)


# ----------------------------------------------------------------------
# prepare

def layout(prog):
    off = 0
    for line in prog.lines:
        line.off = off
        off += 6 + len(line.toks) + 1
    return off + 1


OPENERS = {'IF': 'END IF', 'WHILE': 'WEND', 'REPEAT': 'UNTIL', 'DO': 'LOOP', 'FOR': 'NEXT',
           'SELECT CASE': 'END SELECT', 'SUB': 'END SUB', 'FUNCTION': 'END FUNCTION',
           'TRY': 'END TRY', 'DIALOG': 'END DIALOG'}
# block words a one-line IF may not hold (FOR and NEXT there are matched at
# run time, V2's way; EXIT finds its block)
INLINE_BAD = {'ELSEIF', 'END IF', 'WHILE', 'WEND', 'REPEAT', 'UNTIL', 'DO', 'LOOP', 'SELECT CASE', 'CASE',
              'CASE ELSE', 'END SELECT', 'SUB', 'END SUB', 'FUNCTION', 'END FUNCTION', 'TRY', 'CATCH',
              'END TRY', 'DIALOG', 'END DIALOG'}
EXITS = {'EXIT FOR': 'FOR', 'EXIT WHILE': 'WHILE', 'EXIT DO': 'DO', 'EXIT REPEAT': 'REPEAT',
         'EXIT SUB': 'SUB', 'EXIT FUNCTION': 'FUNCTION'}


class Block:
    def __init__(self, kind, line, src, tok):
        self.kind, self.line, self.src, self.tok = kind, line, src, tok
        self.pending = tok          # the part whose $0B points at the next part
        self.pending_line = line
        self.has_else = False
        self.has_case = False
        self.expect_case = kind == 'SELECT CASE'
        self.var = None
        self.exits = []             # EXIT tokens to point at the closer
        self.proc = None


class Preparer:
    def __init__(self, prog):
        self.p = prog
        self.stack = []
        self.blk = {}           # absolute token offset of a $0B -> value
        self.labels = {}        # sym -> (line, src)
        self.namerefs = []      # (line, tok, context, src)
        self.linerefs = []      # (number, src, allow0)
        self.numbers = {}       # line number -> src
        self.proc = None
        self.consts = set()
        self.assigned = []      # (sym, src)
        self.arrays = set()
        self.parens = set()     # syms used as name(
        self.scalars = set()

    def err(self, src, msg):
        self.p.error(src, msg)

    def abs(self, line, tok):
        return line.off + 6 + tok.pos

    def blk_of(self, line, toks, idx):
        """the $0B token after the keyword at toks[idx]"""
        nxt = toks[idx + 1] if idx + 1 < len(toks) else None
        return self.abs(line, nxt) if nxt is not None and nxt.tag == 'blk' else None

    def setblk(self, at, target):
        if at is not None:
            self.blk[at] = target

    def run(self):
        p = self.p
        end = layout(p)
        for line in p.lines:
            if line.number:
                if line.number in self.numbers:
                    self.err(line.src, 'Line number %d used twice (lines %d and %d)'
                             % (line.number, self.numbers[line.number], line.src))
                else:
                    self.numbers[line.number] = line.src
        for line in p.lines:
            self.do_line(line)
        last = p.lines[-1].src if p.lines else 1
        while self.stack:
            b = self.stack.pop()
            self.err(last, '%s missing for %s in line %d' % (OPENERS[b.kind], b.kind, b.src))
        self.finish(end)

    # -- a line: statements, with one-line IFs
    def do_line(self, line):
        toks = decode(line.toks)
        self.inline = []          # open one-line IFs: [Block]
        segs, cur = [], []
        for idx, t in enumerate(toks):
            if t.tag == 'data':
                self.p.data_index.append(self.abs(line, t))
            if t.is_p(':'):
                if cur:
                    segs.append(cur)
                cur = []
            elif t.is_kw('ELSE'):
                if cur:
                    segs.append(cur)
                cur = [idx]
            elif t.tag == 'blk' and cur == [idx - 1] and toks[idx - 1].is_kw('ELSE'):
                segs.append(cur + [idx])
                cur = []
            else:
                cur.append(idx)
                if t.is_kw('THEN'):
                    segs.append(cur)
                    cur = []
        if cur:
            segs.append(cur)
        if line.flags & 2 and toks and toks[0].tag == 'nref':
            sym = toks[0].val
            if sym in self.labels:
                self.err(line.src, 'Label %s defined twice (lines %d and %d)'
                         % (self.p.syms[sym].name, self.labels[sym][1], line.src))
            else:
                self.labels[sym] = (line, line.src)
            if segs and segs[0] == [0]:
                segs = segs[1:]
        eol = line.off + 6 + len(line.toks)
        for n, seg in enumerate(segs):
            self.do_stmt(line, toks, seg, segs[n + 1:], eol)
        for b in self.inline:
            self.setblk(b.at, b.target if b.has_else else eol)

    def do_stmt(self, line, toks, seg, rest, eol):
        src = line.src
        ts = [toks[i] for i in seg]
        first = ts[0]
        if first.tag == 'rem' or first.is_p("'") or first.is_kw('REM'):
            return
        self.scan_names(line, toks, seg)
        sel = self.stack[-1] if self.stack and self.stack[-1].kind == 'SELECT CASE' else None
        if sel is not None and sel.expect_case and not first.is_kw('CASE', 'CASE ELSE', 'END SELECT'):
            self.err(src, 'CASE expected after SELECT CASE in line %d' % sel.src)
            sel.expect_case = False
        if first.tag != 'kw':
            if first.tag == 'var' and len(ts) > 1:
                self.check_assign(ts, src)
            return
        name = KWINFO[first.val]['name']
        b_at = self.blk_of(line, toks, seg[0])
        inl = bool(self.inline)
        if inl and name in INLINE_BAD:
            self.err(src, '%s inside a one-line IF' % name)
            return
        if name == 'IF':
            then = next((t for t in ts if t.is_kw('THEN')), None)
            gto = next((t for t in ts if t.is_kw('GOTO')), None)
            if then is None and gto is None:
                self.err(src, 'THEN missing after IF')
                return
            block = (then is not None and ts[-1] is then and
                     (not rest or (len(rest) == 1 and (toks[rest[0][0]].tag == 'rem' or toks[rest[0][0]].is_p("'")
                                                      or toks[rest[0][0]].is_kw('REM')))))
            b = Block('IF', line, src, first)
            b.at = b_at
            b.target = None
            if block and not inl:
                self.stack.append(b)
            else:
                self.inline.append(b)
        elif name == 'ELSE':
            for b in reversed(self.inline):
                if not b.has_else:
                    b.has_else = True
                    b.target = self.abs(line, first)
                    # inner IFs that already had their ELSE end here too
                    self.setblk(b_at, eol)
                    return
            if inl:
                self.err(src, 'ELSE without IF')
                return
            b = self.top('IF', 'ELSE', src)
            if b is None:
                return
            if b.has_else:
                self.err(src, 'Two ELSE parts for IF in line %d' % b.src)
                return
            self.link_pending(b, line, first)
            b.has_else = True
        elif name == 'ELSEIF':
            b = self.top('IF', 'ELSEIF', src)
            if b is None:
                return
            if b.has_else:
                self.err(src, 'ELSEIF after ELSE for IF in line %d' % b.src)
                return
            if not ts[-1].is_kw('THEN'):
                self.err(src, 'THEN missing after ELSEIF')
            self.link_pending(b, line, first)
        elif name in ('WHILE', 'REPEAT', 'DO', 'TRY', 'DIALOG', 'SELECT CASE'):
            if inl:
                self.err(src, '%s inside a one-line IF' % name)
                return
            self.stack.append(Block(name, line, src, first))
        elif name == 'FOR':
            if inl:
                return              # a V2-style one-line FOR: matched at run time
            b = Block('FOR', line, src, first)
            var = ts[2] if len(ts) > 2 and ts[1].tag == 'blk' and ts[2].tag == 'var' else None
            b.var = var.val if var is not None else None
            if b.var is not None:
                self.assigned.append((b.var, src))
            self.stack.append(b)
        elif name == 'NEXT':
            if inl:
                return              # NEXT in a one-line IF: matched at run time
            names = [t.val for t in ts if t.tag == 'var']
            if not names:
                b = self.close('FOR', 'NEXT', src)
                if b is not None:
                    self.link_close(b, line, first, b_at)
                return
            first_for = None
            for v in names:
                k = self.find('FOR')
                if k < 0:
                    self.err(src, 'NEXT without FOR')
                    return
                named = [j for j in range(k, -1, -1) if self.stack[j].kind == 'FOR' and self.stack[j].var == v]
                if self.stack[-1].kind == 'FOR' and self.stack[-1].var in (v, None):
                    b = self.stack.pop()
                elif named and all(self.stack[j].kind not in ('SUB', 'FUNCTION') for j in range(named[0], len(self.stack))):
                    top = self.stack[-1]
                    self.err(src, '%s missing for %s in line %d' % (OPENERS[top.kind], top.kind, top.src))
                    del self.stack[named[0] + 1:]
                    b = self.stack.pop()
                else:
                    top = self.stack[k]
                    self.err(src, 'NEXT %s does not match FOR %s in line %d'
                             % (self.p.syms[v].name, self.p.syms[top.var].name if top.var is not None else '', top.src))
                    return
                self.setblk(self.blk_of(b.line, decode(b.line.toks), self.index_of(b.line, b.tok)),
                            self.abs(line, first))
                for e in b.exits:
                    self.setblk(e, self.abs(line, first))
                if first_for is None:
                    first_for = b
                    self.setblk(b_at, self.abs(b.line, b.tok))
        elif name in ('WEND', 'UNTIL', 'LOOP'):
            want = {'WEND': 'WHILE', 'UNTIL': 'REPEAT', 'LOOP': 'DO'}[name]
            b = self.close(want, name, src)
            if b is not None:
                self.link_close(b, line, first, b_at)
        elif name in ('CASE', 'CASE ELSE'):
            b = self.top('SELECT CASE', name, src)
            if b is None:
                return
            if b.has_else:
                self.err(src, '%s after CASE ELSE' % name)
                return
            b.expect_case = False
            self.link_pending(b, line, first)
            b.has_else = name == 'CASE ELSE'
        elif name == 'CATCH':
            b = self.top('TRY', 'CATCH', src)
            if b is None:
                return
            if b.has_else:
                self.err(src, 'Two CATCH parts for TRY in line %d' % b.src)
                return
            self.link_pending(b, line, first)
            b.has_else = True
        elif name in ('END IF', 'END SELECT', 'END TRY', 'END DIALOG'):
            want = {'END IF': 'IF', 'END SELECT': 'SELECT CASE', 'END TRY': 'TRY', 'END DIALOG': 'DIALOG'}[name]
            if inl:
                self.err(src, '%s in a one-line IF' % name)
                return
            b = self.close(want, name, src)
            if b is not None:
                self.link_pending(b, line, first)
        elif name in ('SUB', 'FUNCTION'):
            self.do_proc(line, toks, seg, ts, name, src, inl)
        elif name in ('END SUB', 'END FUNCTION'):
            want = name[4:]
            b = self.close(want, name, src)
            if b is not None:
                self.setblk(self.blk_of(b.line, decode(b.line.toks), self.index_of(b.line, b.tok)),
                            self.abs(line, first))
                for e in b.exits:
                    self.setblk(e, self.abs(line, first))
                b.proc.end = self.abs(line, first)
                self.proc = None
        elif name in EXITS:
            want = EXITS[name]
            k = self.find(want)
            if k < 0:
                self.err(src, '%s outside %s' % (name, want))
            else:
                self.stack[k].exits.append(b_at)
        elif name == 'LOCAL' or name == 'SHARED':
            if self.proc is None:
                self.err(src, '%s outside a SUB or FUNCTION' % name)
                return
            for k, t in enumerate(ts[1:], 1):
                if t.tag != 'var':
                    continue
                if k > 1 and not ts[k - 1].is_p(','):
                    continue
                arr = k + 1 < len(ts) and ts[k + 1].is_p('(')
                self.declare(t.val, name, src, arr)
        elif name == 'CONST':
            for k, t in enumerate(ts):
                if t.tag == 'var' and k + 1 < len(ts) and ts[k + 1].is_p('=') and (k == 1 or ts[k - 1].is_p(',')):
                    if t.val in self.consts:
                        self.err(src, 'Constant %s defined twice' % self.p.syms[t.val].name)
                    self.consts.add(t.val)
        elif name in ('DIM', 'REDIM'):
            depth = 0
            for k, t in enumerate(ts):
                if t.is_p('('):
                    depth += 1
                elif t.is_p(')'):
                    depth -= 1
                elif t.tag == 'var' and depth == 0 and k + 1 < len(ts) and ts[k + 1].is_p('('):
                    self.arrays.add(t.val)
        elif name == 'RETURN':
            if len(ts) > 1 and not (self.proc is not None and self.proc.is_function):
                self.err(src, 'RETURN with a value outside a FUNCTION')
        elif name == 'LET':
            if len(ts) > 1 and ts[1].tag == 'var':
                self.check_assign(ts[1:], src)
        elif name == 'OPTION':
            if len(ts) > 1 and ts[1].is_kw('INTEGER'):
                self.p.option_integer = True
        elif name == 'DEFINT':
            letters = [t for t in ts[1:]]
            k = 0
            while k < len(letters):
                t = letters[k]
                if t.tag == 'var' and len(self.p.syms[t.val].name) == 1:
                    a = self.p.syms[t.val].key
                    b_ = a
                    if k + 2 < len(letters) and letters[k + 1].is_p('-') and letters[k + 2].tag == 'var':
                        b_ = self.p.syms[letters[k + 2].val].key
                        k += 2
                    for c in range(ord(a), ord(b_[0]) + 1):
                        self.p.defint |= 1 << (c - ord('A'))
                elif t.tag == 'var' or t.tag == 'nref':
                    self.err(src, 'DEFINT takes letters')
                k += 1
        # an IF's statement after THEN is a segment of its own: nothing more

    def check_assign(self, ts, src):
        t = ts[0]
        if t.tag == 'var' and len(ts) > 1 and (ts[1].is_p('=') or ts[1].is_p('(')):
            self.assigned.append((t.val, src))

    def declare(self, sym, how, src, arr):
        pr = self.proc
        if how == 'SHARED':
            if any(s == sym for s, _ in pr.frame):
                self.err(src, '%s is LOCAL and SHARED' % self.p.syms[sym].name)
            pr.shared = getattr(pr, 'shared', set()) | {sym}
            return
        if any(s == sym for s, _ in pr.frame):
            self.err(src, '%s is already local in %s %s' % (self.p.syms[sym].name,
                                                          'FUNCTION' if pr.is_function else 'SUB',
                                                          self.p.syms[pr.sym].name))
            return
        if sym in getattr(pr, 'shared', set()):
            self.err(src, '%s is LOCAL and SHARED' % self.p.syms[sym].name)
        pr.frame.append((sym, F_ARRAY if arr else 0))

    def do_proc(self, line, toks, seg, ts, name, src, inl):
        if inl:
            self.err(src, '%s inside a one-line IF' % name)
            return
        if self.proc is not None:
            nm = self.p.syms[ts[2].val].name + ' ' if len(ts) > 2 and ts[2].tag == 'nref' else ''
            self.err(src, '%s %sinside %s %s (line %d)' % (name, nm, 'FUNCTION' if self.proc.is_function else 'SUB',
                                                         self.p.syms[self.proc.sym].name, self.proc.line))
            return
        if self.stack:
            b = self.stack[-1]
            self.err(src, '%s missing for %s in line %d' % (OPENERS[b.kind], b.kind, b.src))
            self.stack = []
        if len(ts) < 3 or ts[2].tag != 'nref':
            self.err(src, 'Name expected after %s' % name)
            return
        sym = ts[2].val
        pr = Proc(sym, name == 'FUNCTION', self.abs(line, ts[0]), src)
        if any(q.sym == sym for q in self.p.procs):
            other = next(q for q in self.p.procs if q.sym == sym)
            self.err(src, '%s %s defined twice (lines %d and %d)' % (name, self.p.syms[sym].name, other.line, src))
        if pr.is_function:
            pr.frame.append((sym, F_RESULT))
        self.p.procs.append(pr)
        self.proc = pr
        # parameters: ( [BYREF] name [()] , ... )
        k = 3
        if k < len(ts) and ts[k].is_p('('):
            k += 1
            while k < len(ts) and not ts[k].is_p(')'):
                byref = False
                if ts[k].is_kw('BYREF'):
                    byref = True
                    k += 1
                if k >= len(ts) or ts[k].tag != 'var':
                    self.err(src, 'Parameter name expected')
                    break
                psym = ts[k].val
                k += 1
                arr = False
                if k + 1 < len(ts) and ts[k].is_p('(') and ts[k + 1].is_p(')'):
                    arr = True
                    k += 2
                if any(s == psym for s, _ in pr.frame):
                    self.err(src, 'Parameter %s given twice' % self.p.syms[psym].name)
                pr.frame.append((psym, F_PARAM | (F_BYREF if byref else 0) | (F_ARRAY if arr else 0)))
                pr.nparams += 1
                if k < len(ts) and ts[k].is_p(','):
                    k += 1
            if k >= len(ts):
                self.err(src, '")" missing after the parameters')
        b = Block(name, line, src, ts[0])
        b.proc = pr
        self.stack.append(b)

    def scan_names(self, line, toks, seg):
        ts = [toks[i] for i in seg]
        ctx = 'call'
        for k, t in enumerate(ts):
            if t.tag == 'kw' and 'ref=line' in KWINFO[t.val]['flags']:
                ctx = 'goto'
            if t.tag == 'lref':
                allow0 = any(x.is_kw('ON') for x in ts[:k]) and any(x.is_kw('ERROR') for x in ts[:k])
                self.linerefs.append((t.val, line.src, allow0))
            elif t.tag == 'nref':
                if k == 0 and line.flags & 2 and seg[0] == 0:
                    continue
                c = ctx
                pv = [x for x in ts[:k] if x.tag != 'blk']
                if pv and pv[-1].is_kw('SUB', 'FUNCTION'):
                    c = 'def'
                elif pv and pv[-1].is_kw('CALL'):
                    c = 'call'
                self.namerefs.append((line, t, c, line.src))
            elif t.tag == 'var' and not t.val & LOCAL_BIT:
                if k + 1 < len(ts) and ts[k + 1].is_p('('):
                    self.parens.add(t.val)
                else:
                    self.scalars.add(t.val)

    def index_of(self, line, tok):
        for i, t in enumerate(decode(line.toks)):
            if t.pos == tok.pos:
                return i
        raise VBError('internal: token not found')

    def link_pending(self, b, line, tok):
        pl = b.pending_line
        self.setblk(self.blk_of(pl, decode(pl.toks), self.index_of(pl, b.pending)), self.abs(line, tok))
        b.pending = tok
        b.pending_line = line

    def link_close(self, b, line, tok, b_at):
        self.setblk(self.blk_of(b.line, decode(b.line.toks), self.index_of(b.line, b.tok)), self.abs(line, tok))
        self.setblk(b_at, self.abs(b.line, b.tok))
        for e in b.exits:
            self.setblk(e, self.abs(line, tok))

    def find(self, want):
        """the index of the innermost open block of that kind, not across a
        procedure (unless a procedure is wanted); -1 if none"""
        for k in range(len(self.stack) - 1, -1, -1):
            b = self.stack[k]
            if b.kind == want:
                return k
            if b.kind in ('SUB', 'FUNCTION'):
                return -1
        return -1

    def top(self, want, what, src, pop=False, quiet=False):
        k = self.find(want)
        if k < 0:
            if not quiet:
                self.err(src, '%s without %s' % (what, want))
            return None
        if k != len(self.stack) - 1:
            b = self.stack[-1]
            self.err(src, '%s missing for %s in line %d' % (OPENERS[b.kind], b.kind, b.src))
            del self.stack[k + 1:]
        return self.stack.pop() if pop else self.stack[-1]

    def close(self, want, what, src, quiet=False):
        return self.top(want, what, src, pop=True, quiet=quiet)

    # -- after the last line
    def finish(self, end):
        p = self.p
        procs = {pr.sym: pr for pr in p.procs}
        for n, src, allow0 in self.linerefs:
            if n == 0 and allow0:
                continue
            if n not in self.numbers:
                p.error(src, 'Undefined line %d' % n)
        for sym, (line, src) in self.labels.items():
            if sym in procs:
                p.error(src, '%s is both a label and a %s' % (p.syms[sym].name,
                                                            'FUNCTION' if procs[sym].is_function else 'SUB'))
        for line, t, ctx, src in self.namerefs:
            nm = p.syms[t.val].name
            if ctx == 'def':
                continue
            if ctx == 'goto':
                if t.val not in self.labels:
                    p.error(src, 'Undefined label %s' % nm)
            elif t.val not in procs:
                p.error(src, 'Undefined SUB %s' % nm)
        for sym, src in self.assigned:
            if sym & LOCAL_BIT:
                continue
            if sym in self.consts:
                p.error(src, 'Cannot assign to constant %s' % p.syms[sym].name)
            elif p.syms[sym].key in G.CONSTANTS:
                p.error(src, 'Cannot assign to constant %s' % p.syms[sym].name)
        # symbol kinds, types, targets
        for i, s in enumerate(p.syms):
            k = 0
            if i in self.consts:
                k |= K_CONST
            if s.key in G.CONSTANTS:
                k |= K_BUILTIN
                s.value = G.CONSTANTS[s.key] & 0xFFFF
            if i in procs:
                k |= K_FUNCTION if procs[i].is_function else K_SUB
                s.target = procs[i].start
            if i in self.labels:
                k |= K_LABEL
                s.target = self.labels[i][0].off
            if i in self.arrays or (i in self.parens and not k & K_FUNCTION):
                k |= K_ARRAY
            if i in self.scalars and not k & (K_CONST | K_BUILTIN):
                k |= K_VAR
            if not k:
                k = K_VAR
            s.kind = k
            if s.type == TY_FLOAT and (p.option_integer or (s.key[0].isalpha() and p.defint >> (ord(s.key[0]) - 65) & 1)):
                s.type = TY_INT
            if k & K_BUILTIN and k & (K_ARRAY | K_SUB | K_FUNCTION | K_LABEL | K_CONST):
                p.error(s.src, '%s is a built-in constant' % s.name)
        # locals: rewrite the variable references inside each procedure
        for pr in p.procs:
            slots = {}
            for n, (sym, fl) in enumerate(pr.frame):
                slots.setdefault(sym, n)
            for line in p.lines:
                if line.off + 6 + len(line.toks) < pr.start or (pr.end and line.off > pr.end):
                    continue
                toks = decode(line.toks)
                for k, t in enumerate(toks):
                    a = line.off + 6 + t.pos
                    if t.tag != 'var' or t.val & LOCAL_BIT or a <= pr.start or (pr.end and a >= pr.end):
                        continue
                    if t.val not in slots:
                        continue
                    slot = slots[t.val]
                    if pr.frame[slot][1] & F_RESULT:
                        nxt = toks[k + 1] if k + 1 < len(toks) else None
                        if nxt is not None and nxt.is_p('('):
                            continue      # a recursive call, not the result
                    line.toks[t.pos + 1:t.pos + 3] = (LOCAL_BIT | slot).to_bytes(2, 'little')
        # name references' targets
        for line in p.lines:
            for t in decode(line.toks):
                if t.tag == 'nref':
                    tgt = p.syms[t.val].target if (p.syms[t.val].kind & (K_SUB | K_FUNCTION | K_LABEL)) else 0
                    line.toks[t.pos + 3:t.pos + 6] = tgt.to_bytes(3, 'little')
        # block offsets
        for line in p.lines:
            for t in decode(line.toks):
                if t.tag == 'blk':
                    v = self.blk.get(line.off + 6 + t.pos, 0)
                    line.toks[t.pos + 1:t.pos + 3] = v.to_bytes(2, 'little')
        p.line_index = sorted((ln.number, ln.off) for ln in p.lines if ln.number)
        p.errors.sort(key=lambda e: e[0])
        p.prepared = True


def prepare(prog):
    """fills the block offsets, name targets, procedures, locals, the line
    and DATA indexes; structural errors go to prog.errors"""
    if prog.errors:
        return prog
    Preparer(prog).run()
    return prog


def check_text(text):
    prog = tokenize(text)
    if not prog.errors:
        prepare(prog)
    return prog


# ----------------------------------------------------------------------
# the records (docs/vbasic/FORMAT.md)

def encode(prog):
    """the four records of the program document"""
    size = layout(prog)
    r1 = bytearray()
    for line in prog.lines:
        r = bytearray([6 + len(line.toks) + 1]) + line.number.to_bytes(2, 'little') + \
            line.src.to_bytes(2, 'little') + bytes([line.flags]) + line.toks + b'\0'
        r1 += r
    r1.append(0)
    assert len(r1) == size
    if len(r1) > 0xFFFF:
        raise VBError('Program too big')
    h = bytearray(HEADER_SIZE)
    h[0:2] = b'VB'
    h[2] = G.FORMAT
    h[3] = RUNTIME_VERSION
    h[4:6] = len(prog.syms).to_bytes(2, 'little')
    h[6:8] = len(prog.procs).to_bytes(2, 'little')
    h[8:10] = len(prog.lines).to_bytes(2, 'little')
    h[10:12] = len(r1).to_bytes(2, 'little')
    h[12:14] = len(prog.line_index).to_bytes(2, 'little')
    h[14:16] = len(prog.data_index).to_bytes(2, 'little')
    h[16] = (1 if prog.option_integer else 0) | (0x80 if prog.prepared else 0)
    h[17:21] = prog.defint.to_bytes(4, 'little')
    r0 = bytearray(h)
    for s in prog.syms:
        nm = s.name.encode('latin-1')
        r0 += bytes([s.kind, s.type]) + s.target.to_bytes(3, 'little') + s.value.to_bytes(2, 'little') + \
            bytes([len(nm)]) + nm
    for pr in prog.procs:
        r0 += pr.sym.to_bytes(2, 'little') + pr.start.to_bytes(2, 'little') + pr.end.to_bytes(2, 'little') + \
            bytes([pr.nparams, len(pr.frame), 1 if pr.is_function else 0])
        for sym, fl in pr.frame:
            r0 += sym.to_bytes(2, 'little') + bytes([fl])
    r2 = bytearray()
    for n, off in prog.line_index:
        r2 += n.to_bytes(2, 'little') + off.to_bytes(2, 'little')
    r3 = bytearray()
    for off in prog.data_index:
        r3 += off.to_bytes(2, 'little')
    return [bytes(r0), bytes(r1), bytes(r2), bytes(r3)]


def decode_records(recs):
    r0, r1, r2, r3 = recs
    if r0[0:2] != b'VB':
        raise VBError('not a VeraBASIC program')
    if r0[2] > G.FORMAT:
        raise VBError('Made by a newer VeraBASIC')
    prog = Program()
    nsym = int.from_bytes(r0[4:6], 'little')
    nproc = int.from_bytes(r0[6:8], 'little')
    nlines = int.from_bytes(r0[8:10], 'little')
    prog.option_integer = bool(r0[16] & 1)
    prog.prepared = bool(r0[16] & 0x80)
    prog.defint = int.from_bytes(r0[17:21], 'little')
    i = HEADER_SIZE
    for _ in range(nsym):
        ln = r0[i + 7]
        s = Sym(r0[i + 8:i + 8 + ln].decode('latin-1'))
        s.kind, s.type = r0[i], r0[i + 1]
        s.target = int.from_bytes(r0[i + 2:i + 5], 'little')
        s.value = int.from_bytes(r0[i + 5:i + 7], 'little')
        prog.symidx[s.key] = len(prog.syms)
        prog.syms.append(s)
        i += 8 + ln
    for _ in range(nproc):
        sym = int.from_bytes(r0[i:i + 2], 'little')
        pr = Proc(sym, bool(r0[i + 8] & 1), int.from_bytes(r0[i + 2:i + 4], 'little'), 0)
        pr.end = int.from_bytes(r0[i + 4:i + 6], 'little')
        pr.nparams, nframe = r0[i + 6], r0[i + 7]
        i += 9
        for _ in range(nframe):
            pr.frame.append((int.from_bytes(r0[i:i + 2], 'little'), r0[i + 2]))
            i += 3
        prog.procs.append(pr)
    j = 0
    while r1[j]:
        ln = r1[j]
        prog.lines.append(Line(int.from_bytes(r1[j + 1:j + 3], 'little'), int.from_bytes(r1[j + 3:j + 5], 'little'),
                               r1[j + 5], r1[j + 6:j + ln - 1]))
        j += ln
    if len(prog.lines) != nlines:
        raise VBError('the line count does not match')
    for k in range(0, len(r2), 4):
        prog.line_index.append((int.from_bytes(r2[k:k + 2], 'little'), int.from_bytes(r2[k + 2:k + 4], 'little')))
    for k in range(0, len(r3), 2):
        prog.data_index.append(int.from_bytes(r3[k:k + 2], 'little'))
    layout(prog)
    for pr in prog.procs:
        pr.line = next((ln.src for ln in prog.lines if ln.off <= pr.start < ln.off + 7 + len(ln.toks)), 0)
    return prog


# the program document: a GEOS VLIR file in CVT format (docs/APPFORMAT.md)
DOC_CLASS = 'VeraBASIC'
DOC_PARENT = 'VBRun       V1.0'


def write_document(name, recs, description='A VeraBASIC program.'):
    import datetime
    import vpack
    import vicon
    nm = vpack.text(name, 16, 'name')
    info = bytearray(256)
    info[0], info[1] = 0, 0xFF
    info[2], info[3], info[4] = 3, 21, 0xBF
    info[5:68] = vicon.icon_bytes(None)
    info[68], info[69], info[70] = vpack.CBM_USR, vpack.APPL_DATA, 1
    c = DOC_CLASS.ljust(12).encode('latin-1') + b'V1.0'
    info[77:77 + len(c)] = c
    pa = DOC_PARENT.encode('latin-1')
    info[117:117 + len(pa)] = pa
    de = description.encode('latin-1')[:95]
    info[160:160 + len(de)] = de
    table = bytearray(254)
    body = bytearray()
    for n, r in enumerate(recs):
        if not r:
            table[2 * n], table[2 * n + 1] = 0, 0xFF
            continue
        blocks = (len(r) + 253) // 254
        table[2 * n] = blocks
        table[2 * n + 1] = len(r) - (blocks - 1) * 254 + 1
        body += r + bytes(blocks * 254 - len(r))
    now = datetime.datetime.now()
    entry = bytearray(30)
    entry[0] = vpack.CBM_USR
    entry[3:19] = nm.ljust(16, b'\xa0')
    entry[21], entry[22] = 1, vpack.APPL_DATA
    entry[23:28] = bytes([now.year - 1900, now.month, now.day, now.hour, now.minute])
    entry[28:30] = min(2 + len(body) // 254, 0xFFFF).to_bytes(2, 'little')
    return bytes(entry) + vpack.SIG.ljust(254 - 30, b'\0') + bytes(info[2:256]) + bytes(table) + bytes(body)


def read_document(data):
    if len(data) < 762 or data[21] != 1:
        raise VBError('not a VLIR file')
    cls = data[254 + 77 - 2:254 + 97 - 2].split(b'\0')[0].decode('latin-1')
    if not cls.startswith(DOC_CLASS):
        raise VBError('not a VeraBASIC program (class %r)' % cls)
    t, pos, recs = data[508:762], 762, []
    for n in range(4):
        b, last = t[2 * n], t[2 * n + 1]
        if b == 0:
            recs.append(b'')
            continue
        size = (b - 1) * 254 + last - 1
        recs.append(data[pos:pos + size])
        pos += b * 254
    return decode_records(recs)


# ----------------------------------------------------------------------

def dump(prog):
    recs = encode(prog)
    out = []
    for n, r in enumerate(recs):
        out.append('record %d: %d bytes' % (n, len(r)))
        for k in range(0, len(r), 16):
            out.append('  %04X  %s' % (k, ' '.join('%02X' % b for b in r[k:k + 16])))
    out.append('symbols:')
    kinds = ('var', 'array', 'const', 'SUB', 'FUNCTION', 'label', 'builtin')
    for i, s in enumerate(prog.syms):
        out.append('  %4d %-20s %-6s %-24s target $%04X' % (
            i, s.name, ('float', 'int', 'string')[s.type],
            ','.join(k for b, k in enumerate(kinds) if s.kind >> b & 1), s.target))
    for pr in prog.procs:
        out.append('%s %s: $%04X-$%04X, frame %s' % (
            'FUNCTION' if pr.is_function else 'SUB', prog.syms[pr.sym].name, pr.start, pr.end,
            ', '.join(prog.syms[s].name + ('*' if f & F_PARAM else '') for s, f in pr.frame)))
    return '\n'.join(out)


def main(argv):
    if len(argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    cmd, args = argv[0], argv[1:]
    out = None
    if '-o' in args:
        k = args.index('-o')
        out = args[k + 1]
        args = args[:k] + args[k + 2:]
    if cmd == 'check':
        bad = 0
        for f in args:
            prog = check_text(open(f, 'rb').read())
            for src, msg in prog.errors:
                print('%s:%d: %s' % (f, src, msg))
                bad += 1
        return 1 if bad else 0
    if cmd in ('canon', 'tok', 'dump'):
        prog = check_text(open(args[0], 'rb').read())
        if prog.errors:
            for src, msg in prog.errors:
                print('%s:%d: %s' % (args[0], src, msg), file=sys.stderr)
            return 1
        if cmd == 'canon':
            text = detok(prog)
            if out:
                open(out, 'w', encoding='latin-1', newline='\n').write(text)
            else:
                sys.stdout.write(text)
        elif cmd == 'dump':
            print(dump(prog))
        else:
            if not out:
                print('tok: -o OUT.cvt', file=sys.stderr)
                return 2
            # the GEOS name inside: the document's own (its first 16 characters;
            # the shell and Run use the whole FAT name, DECISIONS V82)
            base = os.path.basename(out)
            if base.lower().endswith('.cvt'):
                base = base[:-4]
            base = base[:16]
            open(out, 'wb').write(write_document(base, encode(prog)))
        return 0
    if cmd == 'list':
        prog = read_document(open(args[0], 'rb').read())
        sys.stdout.write(detok(prog))
        return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
