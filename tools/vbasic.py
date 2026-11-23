#!/usr/bin/env python3
"""VeraBASIC's PC tool (docs/vbasic/manual, docs/vbasic/FORMAT.md).

usage: vbasic.py check FILE.bas...             structural errors as file:line: message
       vbasic.py build FILE.bas -o OUT.cvt     the program document VeraBASIC Run opens
       vbasic.py app FILE.bas [-o OUT.cvt] [--run RUN.cvt]
                                               a standalone application (tools/vbapp.py)
       vbasic.py list FILE.cvt                 a program document (or a made application) as source
       vbasic.py import FILE.PRG [-o OUT.bas]  a Commodore BASIC V2 program as source (tools/vbimport.py)
       vbasic.py doc OUTDIR                    the manual as HTML and PDF, the reference card's PDF
                                               (tools/vbmanual.py)
       vbasic.py canon FILE.bas                the canonical form
       vbasic.py run FILE.bas|FILE.cvt [--rom ROM] [--input KEYS] [--log] [--trace] [--replay LOG] [--dir DIR]
                                               the reference interpreter

run is the reference interpreter (DECISIONS V86), the oracle gates vb_core
and vb_ui compare VeraBASIC Run with; the Veranda statements (V89,
tools/vbveranda.py) are parsed, checked and logged, not drawn, and with
--replay what only the machine knows (the functions' values, the events)
comes from Run's own log. It runs the prepared token form, as the runtime
does, and writes the console's lines to stdout (with --log: "VB| line" as the runtime's test
build logs them, then "VB END" or the error). Floats are the X16 ROM's:
with --rom (or $VB_ROM) it runs the ROM's own maths routines in a small
emulator (tools/vbrom.py), bit for bit as the runtime calls them; without a
ROM image the floats are approximated with the PC's (marked "approx").
--input gives the keys typed (a file; a line end is Return). --trace writes
TRON's trace ("VB TRON n": each line entered, its number or its source
line) without --log too: the debugger's trace pane (DECISIONS V97) is
compared with it. The files and
folders of part 2 (V90, tools/vbveranda2.py) are real: --dir DIR is the
card's top folder for them (the current folder by default), so a gate
compares what Run wrote with what the reference wrote, byte for byte.

Python 3 only; run with -I as the other tools. MIT licence (LICENSE).
"""
import math
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import vbtokens as T  # noqa: E402
import vbveranda as V  # noqa: E402
import vbveranda2 as V2  # noqa: E402

W = 78                  # the console's columns (apps/vbasic/console.s)
STACK_SIZE = 8192 - 32  # the BASIC stack's bytes (apps/vbasic/vb.inc VBSTACK)
# the frames' sizes on the BASIC stack (apps/vbasic/vb.inc), so that
# "Stack overflow" comes at the same depth
FR_GOSUB, FR_FOR, FR_SELECT, FR_TRY, FR_CALL, SLOT = 6, 24, 11, 12, 14, 8
MAXSTR = 255

ERRORS = {
    1: 'Stopped', 2: 'Syntax error', 3: 'RETURN without GOSUB', 4: 'Out of DATA',
    5: 'Illegal quantity', 6: 'Overflow', 7: 'Out of memory', 8: 'Undefined line',
    9: 'Subscript out of range', 10: 'Array already dimensioned', 11: 'Division by zero',
    12: 'Not an array', 13: 'Type mismatch', 14: 'String too long', 15: 'Formula too complex',
    16: 'Stack overflow', 17: 'RESUME without error', 18: 'NEXT without FOR',
    19: 'Wrong number of arguments', 20: 'Not available yet', 21: 'Made by a newer VeraBASIC',
    22: 'Not inside a SUB', 23: 'BYREF needs a variable', 24: 'Font not found', 25: 'No such window',
    26: 'Too many menus or items',
    50: 'File not found', 51: 'Too many files', 52: 'Bad file number', 53: 'File not open',
    54: 'File already open', 55: 'Bad file mode', 56: 'Input past end', 57: 'Disk error',
    58: 'File exists', 59: 'Bad picture', 60: 'Not in a DIALOG',
}
ROMERR = {14: 5, 15: 6, 20: 11}     # the ROM's error numbers to ours

TY_F, TY_I, TY_S = T.TY_FLOAT, T.TY_INT, T.TY_STR
K = T.KW
TK = {n: c for n, c in K.items()}


def tk(name):
    return TK[name]


class BasicError(Exception):
    def __init__(self, code, msg=None, kernel=0):
        Exception.__init__(self, code)
        self.code = code
        self.msg = msg if msg is not None else ERRORS.get(code, 'Error %d' % code)
        self.kernel = kernel


class InputEnd(Exception):
    pass


class EndProgram(Exception):
    pass


ZERO = bytes(5)


# ----------------------------------------------------------------------
# floats: the ROM's, or the PC's

class PCMaths:
    """the PC's floats packed in the 5-byte format: an approximation, for
    when no ROM image is given"""
    approx = True

    @staticmethod
    def pack(x):
        if x == 0 or not math.isfinite(x):
            if not math.isfinite(x):
                raise BasicError(6)
            return ZERO
        m, e = math.frexp(abs(x))         # x = m * 2^e, 0.5 <= m < 1
        mant = int(round(m * (1 << 32)))
        if mant >= 1 << 32:
            mant >>= 1
            e += 1
        if e + 128 > 255:
            raise BasicError(6)
        if e + 128 <= 0:
            return ZERO
        mant &= 0x7FFFFFFF
        if x < 0:
            mant |= 0x80000000
        return bytes([e + 128]) + mant.to_bytes(4, 'big')

    @staticmethod
    def unpack(b):
        return T.float5_value(b)

    def op(self, name, a, b):
        x, y = self.unpack(a), self.unpack(b)
        if name == 'add':
            r = x + y
        elif name == 'sub':
            r = x - y
        elif name == 'mul':
            r = x * y
        elif name == 'div':
            if y == 0:
                raise BasicError(11)
            r = x / y
        else:
            try:
                r = x ** y
            except (OverflowError, ZeroDivisionError):
                raise BasicError(6)
            if isinstance(r, complex):
                raise BasicError(5)
        return self.pack(r)

    def fn(self, name, a):
        x = self.unpack(a)
        try:
            r = {'int': math.floor, 'sqr': math.sqrt, 'sin': math.sin, 'cos': math.cos, 'tan': math.tan,
                 'atn': math.atan, 'exp': math.exp, 'log': math.log, 'abs': abs}[name](x)
        except (ValueError, OverflowError):
            raise BasicError(5 if name != 'exp' else 6)
        return self.pack(float(r))

    def neg(self, a):
        return self.pack(-self.unpack(a))

    def cmp(self, a, b):
        x, y = self.unpack(a), self.unpack(b)
        return (x > y) - (x < y)

    def from_int(self, n):
        return self.pack(float(n))

    def to_int(self, a):
        v = math.floor(self.unpack(a))
        if not -32768 <= v <= 32767:
            raise BasicError(5)
        return v

    def text(self, a):
        x = self.unpack(a)
        if x == int(x) and abs(x) < 1e9:
            s = str(int(x))
        else:
            s = ('%.9G' % x).replace('E+', 'E+').lstrip('0') if abs(x) >= 1 else ('%.9G' % x)
            if 'E' not in s:
                s = s.rstrip('0').rstrip('.') if '.' in s else s
            s = s.replace('0.', '.', 1) if s.startswith('0.') or s.startswith('-0.') else s
        return s if s.startswith('-') else ' ' + s

    def mul10(self, a):
        return self.pack(self.unpack(a) * 10)

    def div10(self, a):
        return self.pack(abs(self.unpack(a)) / 10)

    def rnd(self, a):
        import random
        x = self.unpack(a)
        if x < 0:
            random.seed(x)
        return self.pack(random.random())

    def reseed(self):
        import random
        random.seed(1)


class ROMMaths:
    approx = False

    def __init__(self, path):
        import vbrom
        self.vbrom = vbrom
        self.m = vbrom.Maths(path)

    def _wrap(self, f, *a):
        try:
            return f(*a)
        except self.vbrom.MathError as e:
            raise BasicError(ROMERR.get(e.code, 5))

    def op(self, name, a, b):
        return self._wrap(self.m.op, name, a, b)

    def fn(self, name, a):
        return self._wrap(self.m.fn, name, a)

    def neg(self, a):
        return self.m.neg(a)

    def cmp(self, a, b):
        return self._wrap(self.m.cmp, a, b)

    def from_int(self, n):
        return self._wrap(self.m.from_int, n)

    def to_int(self, a):
        return self._wrap(self.m.to_int, a)

    def text(self, a):
        return self._wrap(self.m.text, a)

    def mul10(self, a):
        return self._wrap(self.m.mul10, a)

    def div10(self, a):
        return self._wrap(self.m.div10, a)

    def rnd(self, a):
        return self._wrap(self.m.rnd, a)

    def reseed(self):
        self.m.reseed()


# ----------------------------------------------------------------------
# storage

class Cell:
    __slots__ = ('ty', 'v')

    def __init__(self, ty):
        self.ty = ty
        self.v = zero_of(ty)


def zero_of(ty):
    return 0 if ty == TY_I else ZERO if ty == TY_F else b''


class Array:
    def __init__(self, ty, dims):
        self.ty = ty
        self.dims = dims            # the largest index of each dimension
        n = 1
        for d in dims:
            n *= d + 1
        self.n = n
        self.data = [zero_of(ty)] * n

    def index(self, subs):
        if len(subs) != len(self.dims):
            raise BasicError(9)
        i = 0
        for s, d in zip(subs, self.dims):
            if s < 0 or s > d:
                raise BasicError(9)
            i = i * (d + 1) + s
        return i


class ElemRef:
    """an array element as a BYREF parameter"""
    __slots__ = ('arr', 'i', 'ty')

    def __init__(self, arr, i):
        self.arr, self.i, self.ty = arr, i, arr.ty

    @property
    def v(self):
        return self.arr.data[self.i]

    @v.setter
    def v(self, x):
        self.arr.data[self.i] = x


class ArrCell:
    """a symbol's array: the Array once dimensioned"""
    __slots__ = ('ty', 'arr')

    def __init__(self, ty):
        self.ty, self.arr = ty, None


class Frame:
    __slots__ = ('kind', 'size', 'a', 'b', 'c', 'd', 'e', 'f')

    def __init__(self, kind, size, a=None, b=None, c=None, d=None, e=None, f=None):
        self.kind, self.size = kind, size
        self.a, self.b, self.c, self.d, self.e, self.f = a, b, c, d, e, f


class ProcInfo:
    def __init__(self, idx, pr, prog):
        self.idx = idx
        self.name = prog.syms[pr.sym].name
        self.is_function = pr.is_function
        self.start, self.end = pr.start, pr.end
        self.nparams = pr.nparams
        self.slots = []     # (type, flags)
        for sym, fl in pr.frame:
            self.slots.append((prog.syms[sym].type, fl))
        self.result_ty = prog.syms[pr.sym].type


# ----------------------------------------------------------------------

class Interp(V.VerandaMixin, V2.Veranda2Mixin):
    def __init__(self, prog, maths, keys=b'', log=False, out=None, replay=None, root=None):
        self.prog = prog
        self.m = maths
        recs = T.encode(prog)
        self.code = recs[1]
        self.keys = bytearray(keys)
        self.log = log
        self.trace_out = False
        self.out = out or sys.stdout
        self.syms = prog.syms
        self.cells = []
        for s in prog.syms:
            if s.kind & T.K_ARRAY and not s.kind & T.K_FUNCTION:
                self.cells.append(ArrCell(s.type))
            else:
                c = Cell(s.type if not s.kind & T.K_BUILTIN else TY_I)
                if s.kind & T.K_BUILTIN:
                    c.v = s.value - 0x10000 if s.value & 0x8000 else s.value
                self.cells.append(c)
        self.procs = [ProcInfo(i, pr, prog) for i, pr in enumerate(prog.procs)]
        self.proc_at = {p.start: p for p in self.procs}
        self.proc_of_sym = {pr.sym: self.procs[i] for i, pr in enumerate(prog.procs)}
        self.lines_at = {}
        self.line_starts = []
        off = 0
        while self.code[off]:
            self.line_starts.append(off)
            off += self.code[off]
        self.line_index = dict(prog.line_index)
        self.data_index = list(prog.data_index)
        self.dataptr = 0
        self.stack = []
        self.bsp = 0
        self.frame = None           # the current procedure's slots
        self.proc = None
        self.col = 0
        self.row = []
        self.ip = 0
        self.stmt_ip = 0
        self.err = 0
        self.errmsg = ''
        self.erl = 0
        self.errfile = 0
        self.onerr = None
        self.inhandler = False
        self.err_ip = None
        self.tron = False
        self.mem = bytearray(0x10000)
        self.lastline = None
        self.m.reseed()
        self.x_init(replay)
        self.x2_init(root)

    # --- the console ---
    def emit(self, text):
        if self.log:
            self.x_out('VB| ' + text)
        else:
            self.out.write(text + '\n')

    def newline(self):
        self.emit(''.join(self.row))
        self.row = []
        self.col = 0

    def putc(self, ch):
        if self.col >= W:
            self.newline()
        self.row.append(ch)
        self.col += 1

    def puts(self, s):
        for ch in s:
            self.putc(ch)

    def message(self, text):
        if self.col:
            self.newline()
        self.puts(text)
        self.newline()

    # --- keys ---
    def key(self):
        if not self.keys:
            return None
        k = self.keys.pop(0)
        return 13 if k == 10 else k

    def read_line(self):
        """the keys up to Return, echoed (Backspace: $14 or $08)"""
        buf = []
        while True:
            k = self.key()
            if k is None:
                raise InputEnd()
            if k == 13:
                break
            if k in (0x14, 0x08):
                if buf:
                    buf.pop()
                    if self.row:
                        self.row.pop()
                        self.col -= 1
                continue
            if k < 32 or 0x80 <= k < 0xA0 or len(buf) >= 250:
                continue
            buf.append(chr(k))
            self.putc(chr(k))
        self.newline()
        return ''.join(buf)

    # --- the token stream ---
    def b(self, at=None):
        return self.code[self.ip if at is None else at]

    def w(self, at):
        return self.code[at] | self.code[at + 1] << 8

    def sw(self, at):
        v = self.w(at)
        return v - 0x10000 if v & 0x8000 else v

    def tok(self):
        """the token at ip: (code, its length); a second-page one as $FFnn"""
        c = self.code[self.ip]
        if c == 0xFF:
            return 0xFF00 | self.code[self.ip + 1], 2
        return c, 1

    def peek(self):
        c = self.code[self.ip]
        if c == 0xFF:
            return 0xFF00 | self.code[self.ip + 1]
        return c

    def skip_tok(self, at):
        """the offset after the token at at"""
        c = self.code[at]
        if c in (T.T_INTDEC, T.T_INTHEX, T.T_INTBIN, T.T_VAR, T.T_BLOCK):
            return at + 3
        if c == T.T_FLOAT:
            return at + 7 + self.code[at + 6]
        if c in (T.T_STRING, T.T_COMMENT, T.T_DATA):
            return at + 2 + self.code[at + 1]
        if c in (T.T_LINEREF, T.T_NAMEREF):
            return at + 6
        if c == 0xFF:
            return at + 2
        return at + 1

    def expect(self, ch):
        if self.b() != ord(ch):
            raise BasicError(2)
        self.ip += 1

    def accept(self, ch):
        if self.b() == ord(ch):
            self.ip += 1
            return True
        return False

    def accept_kw(self, name):
        if self.peek() == K[name]:
            self.ip += 2 if K[name] > 0xFF else 1
            return True
        return False

    def at_end(self):
        """the statement's end: the line's, ':', ELSE, or a ' comment"""
        c = self.b()
        return c == 0 or c == ord(':') or c == K['ELSE'] or c == ord("'")

    def line_of(self, at):
        """the line record holding offset at"""
        lo, hi = 0, len(self.line_starts) - 1
        while lo < hi:
            mid = (lo + hi + 1) // 2
            if self.line_starts[mid] <= at:
                lo = mid
            else:
                hi = mid - 1
        return self.line_starts[lo]

    def line_label(self, rec):
        n = self.w(rec + 1)
        return n if n else self.w(rec + 3)

    def block(self):
        """the $0B offset after the token just read"""
        if self.b() != T.T_BLOCK:
            raise BasicError(2)
        v = self.w(self.ip + 1)
        self.ip += 3
        return v

    def skip_stmt(self):
        """to the end of the statement: ':' or the line's end (ELSE ends
        one too, outside parentheses)"""
        depth = 0
        while True:
            c = self.code[self.ip]
            if c == 0:
                return
            if depth == 0 and (c == ord(':') or c == K['ELSE']):
                return
            if c == ord('('):
                depth += 1
            elif c == ord(')'):
                depth -= 1
            self.ip = self.skip_tok(self.ip)

    # --- frames ---
    def push(self, fr):
        if self.bsp + fr.size > STACK_SIZE:
            raise BasicError(16)
        self.stack.append(fr)
        self.bsp += fr.size

    def pop(self):
        fr = self.stack.pop()
        self.bsp -= fr.size
        return fr

    def pop_inside(self, lo, hi):
        """drops the FOR, SELECT and TRY frames of statements between lo and
        hi (a block being left), down to a GOSUB or procedure frame"""
        while self.stack:
            fr = self.stack[-1]
            if fr.kind in ('FOR', 'SELECT', 'TRY') and lo <= fr.a <= hi:
                self.pop()
            else:
                break

    # --- variables ---
    def cell(self, slot):
        if slot & 0x8000:
            c = self.frame[slot & 0x7FFF]
            return c
        return self.cells[slot]

    def var_type(self, slot):
        return self.cell(slot).ty

    # --- values: (type, v) ---
    def to_float(self, ty, v):
        if ty == TY_F:
            return v
        if ty == TY_I:
            return self.m.from_int(v)
        raise BasicError(13)

    def to_int(self, ty, v):
        if ty == TY_I:
            return v
        if ty == TY_F:
            return self.m.to_int(v)
        raise BasicError(13)

    def convert(self, ty, val):
        vt, v = val
        if ty == TY_S:
            if vt != TY_S:
                raise BasicError(13)
            return v
        if vt == TY_S:
            raise BasicError(13)
        return self.to_int(vt, v) if ty == TY_I else self.to_float(vt, v)

    def num_text(self, val):
        ty, v = val
        if ty == TY_I:
            return (' %d' % v) if v >= 0 else '%d' % v
        return self.m.text(v)

    # --- expressions: precedence climbing ---
    #   1 OR XOR, 2 AND, 3 NOT, 4 comparisons, 5 SHL SHR, 6 + -, 7 * / \ MOD,
    #   8 unary -, 9 ^
    BIN = None

    def expr(self, minp=1):
        c = self.peek()
        if c == K['NOT'] and minp <= 3:
            self.ip += 1
            v = self.expr(4)
            left = (TY_I, ~self.to_int(*v) & 0xFFFF)
            left = (TY_I, left[1] - 0x10000 if left[1] & 0x8000 else left[1])
        else:
            left = self.unary(minp)
        while True:
            c = self.peek()
            p = BINPREC.get(c)
            if p is None or p < minp:
                return left
            self.ip += 1
            if c == ord('^'):
                right = self.unary(9)       # right-associative over unary minus
            else:
                right = self.expr(p + 1)
            left = self.binop(c, left, right)

    def unary(self, minp):
        c = self.peek()
        if c == ord('-'):
            self.ip += 1
            v = self.expr(8) if minp <= 8 else self.primary()
            return self.negate(v)
        if c == ord('+'):
            self.ip += 1
            v = self.expr(8)
            if v[0] == TY_S:
                raise BasicError(13)
            return v
        if c == K['NOT']:
            self.ip += 1
            v = self.expr(4)
            r = ~self.to_int(*v)
            return (TY_I, r)
        v = self.primary()
        if self.peek() == ord('^') and minp <= 9:
            return v
        return v

    def negate(self, v):
        ty, x = v
        if ty == TY_I:
            if x == -32768:
                return (TY_F, self.m.neg(self.m.from_int(x)))
            return (TY_I, -x)
        if ty == TY_F:
            return (TY_F, self.m.neg(x))
        raise BasicError(13)

    def binop(self, op, a, b):
        at, bt = a[0], b[0]
        if op == ord('+') and at == TY_S and bt == TY_S:
            r = a[1] + b[1]
            if len(r) > MAXSTR:
                raise BasicError(14)
            return (TY_S, r)
        if op in CMPOPS:
            if at == TY_S or bt == TY_S:
                if at != bt:
                    raise BasicError(13)
                x, y = a[1], b[1]
                c = (x > y) - (x < y)
            elif at == TY_I and bt == TY_I:
                c = (a[1] > b[1]) - (a[1] < b[1])
            else:
                c = self.m.cmp(self.to_float(*a), self.to_float(*b))
            return (TY_I, -1 if CMPOPS[op](c) else 0)
        if at == TY_S or bt == TY_S:
            raise BasicError(13)
        if op in (K['AND'], K['OR'], K['XOR'], K['SHL'], K['SHR']):
            x, y = self.to_int(*a) & 0xFFFF, self.to_int(*b) & 0xFFFF
            if op == K['AND']:
                r = x & y
            elif op == K['OR']:
                r = x | y
            elif op == K['XOR']:
                r = x ^ y
            elif op == K['SHL']:
                r = (x << y) & 0xFFFF if y < 16 else 0
            else:
                r = x >> y if y < 16 else 0
            return (TY_I, r - 0x10000 if r & 0x8000 else r)
        if op in (ord('\\'), K['MOD']):
            x, y = self.to_int(*a), self.to_int(*b)
            if y == 0:
                raise BasicError(11)
            q = abs(x) // abs(y)
            if (x < 0) != (y < 0):
                q = -q
            if op == K['MOD']:
                return (TY_I, x - q * y)
            if q > 32767:           # -32768 div -1
                return (TY_F, self.m.op('add', self.m.from_int(16384), self.m.from_int(16384)))
            return (TY_I, q)
        if op == ord('/'):
            return (TY_F, self.m.op('div', self.to_float(*a), self.to_float(*b)))
        if op == ord('^'):
            if at == TY_I and bt == TY_I and b[1] >= 0:
                return (TY_F, self.ipow(a[1], b[1]))
            return (TY_F, self.m.op('pow', self.to_float(*a), self.to_float(*b)))
        if at == TY_I and bt == TY_I:
            x, y = a[1], b[1]
            r = x + y if op == ord('+') else x - y if op == ord('-') else x * y
            if -32768 <= r <= 32767:
                return (TY_I, r)
        name = 'add' if op == ord('+') else 'sub' if op == ord('-') else 'mul'
        return (TY_F, self.m.op(name, self.to_float(*a), self.to_float(*b)))

    def ipow(self, base, e):
        """an integer to a power 0 or more: products of floats by squaring
        (exact while they are whole numbers below 2^32)"""
        r = self.m.from_int(1)
        b = self.m.from_int(base)
        while e > 0:
            if e & 1:
                r = self.m.op('mul', r, b)
            e >>= 1
            if e > 0:
                b = self.m.op('mul', b, b)
        return r

    def primary(self):
        c = self.code[self.ip]
        ip = self.ip
        if c in (T.T_INTDEC, T.T_INTHEX, T.T_INTBIN):
            self.ip += 3
            return (TY_I, self.sw(ip + 1))
        if c == T.T_FLOAT:
            self.ip = self.skip_tok(ip)
            return (TY_F, bytes(self.code[ip + 1:ip + 6]))
        if c == T.T_STRING:
            n = self.code[ip + 1]
            self.ip += 2 + n
            return (TY_S, bytes(self.code[ip + 2:ip + 2 + n]))
        if c == ord('('):
            self.ip += 1
            v = self.expr()
            self.expect(')')
            return v
        if c == T.T_VAR:
            slot = self.w(ip + 1)
            self.ip += 3
            if not slot & 0x8000:
                s = self.syms[slot]
                if s.kind & T.K_FUNCTION:
                    return self.call_function(self.proc_of_sym[slot])
            cl = self.cell(slot)
            if isinstance(cl, ArrCell) or self.b() == ord('('):
                arr, i = self.element(slot)
                return (arr.ty, arr.data[i])
            return (cl.ty, cl.v)
        if c == 0xFF:
            return self.ext_function()
        if c >= 0x80:
            return self.function(c)
        raise BasicError(2)

    def subscripts(self):
        self.expect('(')
        subs = []
        while True:
            subs.append(self.to_int(*self.expr()))
            if not self.accept(','):
                break
        self.expect(')')
        return subs

    def array_of(self, slot):
        cl = self.cell(slot)
        if isinstance(cl, ArrRef):
            cl = cl.cell
        if not isinstance(cl, ArrCell):
            raise BasicError(12)
        return cl

    def element(self, slot):
        cl = self.array_of(slot)
        subs = self.subscripts()
        if cl.arr is None:
            if len(subs) > 3:
                raise BasicError(9)
            self.dim(cl, [10] * len(subs))
        return cl.arr, cl.arr.index(subs)

    def dim(self, cl, dims):
        n = 1
        for d in dims:
            if d < 0:
                raise BasicError(5)
            n *= d + 1
        if n > 65535:
            raise BasicError(7)
        cl.arr = Array(cl.ty, dims)

    def args1(self):
        self.expect('(')
        v = self.expr()
        self.expect(')')
        return v

    def function(self, c):
        self.ip += 1
        m = self.m
        if c in (K['ERR'], K['ERL'], K['ERRFILE']):
            return (TY_I, {K['ERR']: self.err, K['ERL']: self.erl, K['ERRFILE']: self.errfile}[c])
        if c == K['ERR$']:
            return (TY_S, self.errmsg.encode('latin-1'))
        if c == K['TI']:
            return (TY_F, m.from_int(0))
        if c == K['TI$']:
            return (TY_S, b'000000')
        if c in (K['SELECT'], K['DATA']):
            return (TY_I, 4 if c == K['SELECT'] else 5)
        if c == K['LEFT$'] or c == K['RIGHT$']:
            self.expect('(')
            s = self.convert(TY_S, self.expr())
            self.expect(',')
            n = self.to_int(*self.expr())
            self.expect(')')
            if n < 0 or n > 255:
                raise BasicError(5)
            if c == K['LEFT$']:
                return (TY_S, s[:n])
            return (TY_S, s[len(s) - n:] if n < len(s) else s)
        if c == K['MID$']:
            self.expect('(')
            s = self.convert(TY_S, self.expr())
            self.expect(',')
            st = self.to_int(*self.expr())
            n = 255
            if self.accept(','):
                n = self.to_int(*self.expr())
            self.expect(')')
            if st < 1 or st > 255 or n < 0 or n > 255:
                raise BasicError(5)
            return (TY_S, s[st - 1:st - 1 + n])
        if c == K['UBOUND']:
            self.expect('(')
            if self.b() != T.T_VAR:
                raise BasicError(12)
            slot = self.w(self.ip + 1)
            self.ip += 3
            cl = self.array_of(slot)
            d = 1
            if self.accept(','):
                d = self.to_int(*self.expr())
            self.expect(')')
            if cl.arr is None:
                raise BasicError(9)
            if d < 1 or d > len(cl.arr.dims):
                raise BasicError(9)
            return (TY_I, cl.arr.dims[d - 1])
        if c == K['FRE']:
            self.args1()
            return (TY_F, m.from_int(0))
        if c in (K['TAB'], K['SPC']):
            n = self.to_int(*self.args1())
            if n < 0 or n > 255:
                raise BasicError(5)
            return (TY_S, b' ' * n)
        v = self.args1()
        if c == K['LEN']:
            return (TY_I, len(self.convert(TY_S, v)))
        if c == K['ASC']:
            s = self.convert(TY_S, v)
            if not s:
                raise BasicError(5)
            return (TY_I, s[0])
        if c == K['CHR$']:
            n = self.to_int(*v)
            if n < 0 or n > 255:
                raise BasicError(5)
            return (TY_S, bytes([n]))
        if c == K['STR$']:
            if v[0] == TY_S:
                raise BasicError(13)
            return (TY_S, self.num_text(v).encode('latin-1'))
        if c == K['VAL']:
            s = self.convert(TY_S, v)
            return self.parse_number(s.decode('latin-1'), False)
        if c == K['PEEK']:
            a = self.address(v)
            return (TY_I, self.mem[a])
        if v[0] == TY_S:
            raise BasicError(13)
        if c == K['SGN']:
            if v[0] == TY_I:
                return (TY_I, (v[1] > 0) - (v[1] < 0))
            return (TY_I, m.cmp(v[1], ZERO))
        if c == K['ABS'] and v[0] == TY_I:
            if v[1] == -32768:
                return (TY_F, m.neg(m.from_int(-32768)))
            return (TY_I, abs(v[1]))
        if c == K['INT'] and v[0] == TY_I:
            return v
        if c == K['RND']:
            return (TY_F, m.rnd(self.to_float(*v)))
        name = {K['INT']: 'int', K['ABS']: 'abs', K['SQR']: 'sqr', K['SIN']: 'sin', K['COS']: 'cos',
                K['TAN']: 'tan', K['ATN']: 'atn', K['EXP']: 'exp', K['LOG']: 'log'}.get(c)
        if name is None:
            raise BasicError(2)
        return (TY_F, m.fn(name, self.to_float(*v)))

    def ext_function(self):
        nn = self.code[self.ip + 1]
        name = EXT.get(nn)
        self.ip += 2
        self.ip -= 2
        return self.x_function()

    def address(self, v):
        ty, x = v
        if ty == TY_I:
            return x & 0xFFFF
        f = self.to_float(ty, x)
        i = self.int_of_float_u16(f)
        return i

    def int_of_float_u16(self, f):
        # 0 .. 65535: as INT, then in range
        if self.m.cmp(f, self.m.from_int(0)) < 0:
            raise BasicError(5)
        hi = self.m.op('add', self.m.from_int(32767), self.m.from_int(32767))
        hi = self.m.op('add', hi, self.m.from_int(2))      # 65536
        if self.m.cmp(f, hi) >= 0:
            raise BasicError(5)
        half = self.m.op('add', self.m.from_int(16384), self.m.from_int(16384))  # 32768
        if self.m.cmp(f, half) >= 0:
            return 32768 + self.m.to_int(self.m.op('sub', f, half))
        return self.m.to_int(f)

    # --- numbers from text (VAL, INPUT, READ): apps/vbasic/num.s ---
    def parse_number(self, s, whole):
        """the number at the start of s; whole: all of s (but blanks) must
        be the number, else None"""
        m = self.m
        i, n = 0, len(s)
        while i < n and s[i] == ' ':
            i += 1
        neg = False
        if i < n and s[i] in '+-':
            neg = s[i] == '-'
            i += 1
        acc = ZERO
        digits = frac = 0
        dot = False
        ival = 0
        while i < n:
            ch = s[i]
            if '0' <= ch <= '9':
                d = ord(ch) - 48
                acc = m.op('add', m.mul10(acc), m.from_int(d))
                ival = ival * 10 + d if ival < 100000 else 100000
                digits += 1
                if dot:
                    frac += 1
            elif ch == '.' and not dot:
                dot = True
            else:
                break
            i += 1
        if digits == 0:
            if whole:
                return None
            return (TY_F, ZERO)
        exp = 0
        e_seen = False
        if i < n and s[i] in 'eE':
            j = i + 1
            eneg = False
            if j < n and s[j] in '+-':
                eneg = s[j] == '-'
                j += 1
            k = j
            while j < n and '0' <= s[j] <= '9':
                exp = min(exp * 10 + ord(s[j]) - 48, 999)
                j += 1
            if j > k:
                e_seen = True
                i = j
                if eneg:
                    exp = -exp
            else:
                exp = 0
        if whole:
            while i < n and s[i] == ' ':
                i += 1
            if i != n:
                return None
        if not dot and not e_seen and ival <= 32767:
            # a whole number that fits: exact either way; the integer
            v = -ival if neg else ival
            return (TY_I, v)
        e = exp - frac
        while e > 0:
            acc = m.mul10(acc)
            e -= 1
        while e < 0:
            acc = m.div10(acc)
            e += 1
        if neg:
            acc = m.neg(acc)
        return (TY_F, acc)

    # --- assignment ---
    def lvalue(self):
        """the target of an assignment (TAG_VAR [subscripts]): (container, key)"""
        if self.b() != T.T_VAR:
            raise BasicError(2)
        slot = self.w(self.ip + 1)
        self.ip += 3
        if not slot & 0x8000 and self.syms[slot].kind & (T.K_CONST | T.K_BUILTIN):
            raise BasicError(2)
        cl = self.cell(slot)
        if isinstance(cl, (ArrCell, ArrRef)) or self.b() == ord('('):
            arr, i = self.element(slot)
            return ElemRef(arr, i)
        return cl

    def store(self, target, val):
        target.v = self.convert(target.ty, val)

    # --- procedures ---
    def call_args(self, p, paren):
        """the arguments of a call to p: the new frame's cells"""
        cells = []
        n = 0
        if paren == 'none':             # a FUNCTION named without (
            paren = False
            empty = True
        else:
            if paren is None:           # CALL: the ( is optional
                paren = self.b() == ord('(')
                if paren:
                    self.ip += 1
            elif paren:
                self.expect('(')
            empty = self.b() == ord(')') if paren else self.at_end()
        params = [s for s in p.slots if s[1] & T.F_PARAM]
        if not empty:
            while True:
                if n >= len(params):
                    raise BasicError(19)
                ty, fl = params[n]
                if fl & T.F_ARRAY:
                    if self.b() != T.T_VAR:
                        raise BasicError(12)
                    slot = self.w(self.ip + 1)
                    self.ip += 3
                    self.expect('(')
                    self.expect(')')
                    cl = self.array_of(slot)
                    cells.append(ArrRef(cl))
                elif fl & T.F_BYREF:
                    if self.b() != T.T_VAR:
                        raise BasicError(23)
                    tgt = self.lvalue()
                    if tgt.ty != ty:
                        raise BasicError(13)
                    cells.append(tgt)
                else:
                    c = Cell(ty)
                    c.v = self.convert(ty, self.expr())
                    cells.append(c)
                n += 1
                if not self.accept(','):
                    break
        if paren:
            self.expect(')')
        if n != len(params):
            raise BasicError(19)
        frame = []
        k = 0
        for ty, fl in p.slots:
            if fl & T.F_PARAM:
                frame.append(cells[k])
                k += 1
            else:
                frame.append(Cell(ty))
        return frame

    def enter(self, p, frame, ret):
        self.push(Frame('CALL', FR_CALL + SLOT * len(p.slots), p.start, ret, self.frame, self.proc))
        self.frame = frame
        self.proc = p
        # the body: after SUB Name(params) to the line's end or ':'
        self.ip = p.start + 1 + 3 + 6
        self.skip_params()

    def skip_params(self):
        if self.b() == ord('('):
            depth = 0
            while True:
                c = self.b()
                if c == ord('('):
                    depth += 1
                elif c == ord(')'):
                    depth -= 1
                    if depth == 0:
                        self.ip += 1
                        break
                self.ip = self.skip_tok(self.ip)

    def leave(self):
        """back from the innermost procedure: its frames popped"""
        while self.stack and self.stack[-1].kind != 'CALL':
            self.pop()
        if not self.stack:
            raise BasicError(22)
        fr = self.pop()
        res = self.frame[0] if self.proc.is_function else None
        self.frame, self.proc = fr.c, fr.d
        self.ip = fr.b
        return res

    def call_function(self, p):
        """a FUNCTION in an expression: its body runs to its end here"""
        frame = self.call_args(p, True if self.b() == ord('(') else 'none')
        depth = len(self.stack)
        self.enter(p, frame, self.ip)
        res = self.run(depth)
        return (res.ty, res.v)

    # --- the statements ---
    def run(self, depth=None):
        """statements until the program ends, or (depth given) until the
        procedure called at that stack depth returns: its result cell"""
        while True:
            try:
                r = self.step(depth)
                if r is not None:
                    return r
            except BasicError as e:
                self.error(e, depth)

    def error(self, e, depth):
        """an error: to the innermost TRY of this run's procedure, else (at
        the top) to ON ERROR's handler; else up: depth is the stack's height
        under the FUNCTION this run() runs (None: the main program)"""
        self.err = e.code
        self.errmsg = e.msg
        self.errfile = e.kernel
        self.erl = self.line_label(self.line_of(self.stmt_ip))
        base = -1 if depth is None else depth
        if e.code != 1:
            k = len(self.stack) - 1
            while k > base and self.stack[k].kind != 'TRY':
                k -= 1
            if k > base:
                self.unwind(k + 1)
                fr = self.pop()
                self.ip = fr.b
                return
            if depth is None and self.onerr is not None and not self.inhandler:
                self.inhandler = True
                self.err_ip = self.stmt_ip
                self.ip = self.onerr
                return
        if depth is not None:
            self.unwind(depth)
        raise e

    def unwind(self, height):
        """frames popped down to height, procedures left as by their END"""
        while len(self.stack) > height:
            if self.stack[-1].kind == 'CALL':
                self.leave()
            else:
                self.pop()

    def next_line(self):
        """ip at a line's $00: on to the next record"""
        nxt = self.ip + 1
        if self.code[nxt] == 0:
            if self.any_bound:          # the main lines' end: events
                self.ip = self.stub
                return
            raise EndProgram()
        self.enter_line(nxt)

    def enter_line(self, rec):
        self.ip = rec + 6
        if self.tron:
            self.trace(rec)

    def trace(self, rec):
        if self.log or self.trace_out:
            self.x_out('VB TRON %d' % self.line_label(rec))

    def line_target(self, at):
        """the line record a TAG_LINEREF or TAG_NAMEREF token at at names"""
        c = self.code[at]
        if c == T.T_LINEREF:
            n = self.w(at + 1)
            if n not in self.line_index:
                raise BasicError(8)
            return self.line_index[n]
        if c == T.T_NAMEREF:
            s = self.syms[self.w(at + 1)]
            if not s.kind & T.K_LABEL:
                raise BasicError(2)
            return s.target
        raise BasicError(2)

    def goto_line(self, at):
        self.enter_line(self.line_target(at))

    def step(self, depth):
        c = self.code[self.ip]
        if c == ord(':'):
            self.ip += 1
            return None
        if c == 0:
            self.next_line()
            return None
        self.stmt_ip = self.ip
        return self.statement(c, depth)

    def end_stmt(self):
        if not self.at_end():
            raise BasicError(2)

    def statement(self, c, depth):
        ip = self.ip
        if c == T.T_VAR:
            tgt = self.lvalue()
            self.expect('=')
            self.store(tgt, self.expr())
            self.end_stmt()
            return None
        if c == T.T_NAMEREF:
            sym = self.w(ip + 1)
            s = self.syms[sym]
            self.ip += 6
            if s.kind & T.K_LABEL:
                self.expect(':')
                return None
            p = self.proc_of_sym.get(sym)
            if p is None:
                raise BasicError(2)
            frame = self.call_args(p, False)
            self.end_stmt()
            self.enter(p, frame, self.ip)
            return None
        if c == T.T_COMMENT or c == ord("'"):
            while self.b() != 0:
                self.ip = self.skip_tok(self.ip)
            return None
        if c == 0xFF:
            return self.x_statement()
        if c < 0x80:
            raise BasicError(2)
        self.ip += 1
        h = STMTS.get(c)
        if h is None:
            raise BasicError(2)
        return h(self, depth)

    # each handler: ip after its token
    def s_rem(self, depth):
        while self.b() != 0:
            self.ip = self.skip_tok(self.ip)

    def s_let(self, depth):
        tgt = self.lvalue()
        self.expect('=')
        self.store(tgt, self.expr())
        self.end_stmt()

    def s_print(self, depth):
        if self.b() == ord('#'):
            return self.x_printh()
        newline = True
        while not self.at_end():
            c = self.peek()
            if c == ord(';'):
                self.ip += 1
                newline = False
                continue
            if c == ord(','):
                self.ip += 1
                t = (self.col // 10 + 1) * 10
                if t >= W:
                    self.newline()
                else:
                    while self.col < t:
                        self.putc(' ')
                newline = False
                continue
            if c in (K['TAB'], K['SPC']):
                self.ip += 1
                n = self.to_int(*self.args1())
                if n < 0 or n > 255:
                    raise BasicError(5)
                if c == K['TAB']:
                    n %= W
                    if self.col >= W:
                        self.newline()
                    while self.col < n:
                        self.putc(' ')
                else:
                    for _ in range(n):
                        self.putc(' ')
                newline = True
                continue
            v = self.expr()
            if v[0] == TY_S:
                self.puts(v[1].decode('latin-1'))
            else:
                self.puts(self.num_text(v) + ' ')
            newline = True
        if newline:
            self.newline()

    def s_input(self, depth, line=False):
        if self.b() == ord('#'):
            return self.x_inputh(line)
        prompt = None
        if self.b() == T.T_STRING:
            save = self.ip
            v = self.primary()
            if self.b() in (ord(';'), ord(',')):
                q = self.b() == ord(';')
                self.ip += 1
                prompt = v[1].decode('latin-1') + ('? ' if q and not line else '')
            else:
                self.ip = save
                raise BasicError(2)
        if prompt is None:
            prompt = '' if line else '? '
        targets_at = self.ip
        while True:
            self.ip = targets_at
            self.puts(prompt)
            if line:
                tgt = self.lvalue()
                if tgt.ty != TY_S:
                    raise BasicError(13)
                text = self.read_line()
                tgt.v = text.encode('latin-1')
                self.end_stmt()
                return
            # the targets, then the fields
            fields = self.fields(self.read_line())
            redo = False
            first = True
            while True:
                tgt = self.lvalue()
                if not fields:
                    self.puts('?? ')
                    fields = self.fields(self.read_line())
                f = fields.pop(0)
                if tgt.ty == TY_S:
                    tgt.v = f.encode('latin-1')
                else:
                    r = self.parse_number(f, True) if f.strip() else (TY_I, 0)
                    if r is None:
                        redo = True
                        break
                    self.store(tgt, r)
                first = False
                if not self.accept(','):
                    break
            if redo:
                self.message('Redo from start')
                continue
            del first
            if fields:
                self.message('Extra ignored')
            self.end_stmt()
            return

    @staticmethod
    def fields(text):
        """INPUT's fields: separated by commas; in quotes a comma is kept"""
        out = []
        i, n = 0, len(text)
        while True:
            while i < n and text[i] == ' ':
                i += 1
            if i < n and text[i] == '"':
                j = text.find('"', i + 1)
                if j < 0:
                    j = n
                out.append(text[i + 1:j])
                i = j + 1
                while i < n and text[i] != ',':
                    i += 1
            else:
                j = text.find(',', i)
                if j < 0:
                    j = n
                out.append(text[i:j].rstrip(' '))
                i = j
            if i >= n:
                break
            i += 1          # the comma
        return out

    def s_line_input(self, depth):
        self.s_input(depth, line=True)

    def s_get(self, depth):
        if self.b() == ord('#'):
            return self.x_geth()
        tgt = self.lvalue()
        if tgt.ty != TY_S:
            raise BasicError(13)
        k = self.key()
        tgt.v = b'' if k is None else bytes([k])
        self.end_stmt()

    def s_goto(self, depth):
        self.goto_line(self.ip)

    def s_gosub(self, depth):
        at = self.ip
        self.ip = self.skip_tok(at)
        self.end_stmt()
        self.push(Frame('GOSUB', FR_GOSUB, self.stmt_ip, self.ip))
        self.goto_line(at)

    def s_return(self, depth):
        if not self.at_end():
            # RETURN value, in a FUNCTION
            if self.proc is None or not self.proc.is_function:
                raise BasicError(2)
            v = self.expr()
            self.end_stmt()
            res = self.frame[0]
            res.v = self.convert(res.ty, v)
            return self.s_end_function(depth)
        while self.stack:
            fr = self.stack[-1]
            if fr.kind == 'GOSUB':
                self.pop()
                self.ip = fr.b
                return None
            if fr.kind == 'CALL':
                break
            self.pop()
        raise BasicError(3)

    def s_on(self, depth):
        if self.b() == 0xFF:
            return self.x_on()
        if self.accept_kw('ERROR'):
            if not self.accept_kw('GOTO'):
                raise BasicError(2)
            at = self.ip
            self.ip = self.skip_tok(at)
            self.end_stmt()
            if self.code[at] == T.T_LINEREF and self.w(at + 1) == 0:
                self.onerr = None
            else:
                self.onerr = self.line_target(at) + 6
            return None
        n = self.to_int(*self.expr())
        if self.accept_kw('GOTO'):
            sub = False
        elif self.accept_kw('GOSUB'):
            sub = True
        else:
            raise BasicError(20)
        targets = []
        while True:
            targets.append(self.ip)
            self.ip = self.skip_tok(self.ip)
            if not self.accept(','):
                break
        self.end_stmt()
        if n < 1 or n > len(targets):
            return None
        if sub:
            self.push(Frame('GOSUB', FR_GOSUB, self.stmt_ip, self.ip))
        self.goto_line(targets[n - 1])
        return None

    def truth(self, v):
        ty, x = v
        if ty == TY_I:
            return x != 0
        if ty == TY_F:
            return x[0] != 0
        raise BasicError(13)

    def s_if(self, depth):
        target = self.block()
        v = self.expr()
        if self.peek() == K['GOTO']:
            # V2's IF ... GOTO line
            self.ip += 1
            if self.truth(v):
                self.goto_line(self.ip)
            else:
                self.if_false(target)
            return None
        if not self.accept_kw('THEN'):
            raise BasicError(2)
        if self.truth(v):
            if self.b() == T.T_LINEREF:
                self.goto_line(self.ip)
            return None
        self.if_false(target)
        return None

    def if_false(self, target):
        """IF or ELSEIF was false: on at its partner"""
        while True:
            c = self.code[target]
            if c == K['ELSEIF']:
                self.ip = target + 1
                nxt = self.block()
                self.stmt_ip = target
                v = self.expr()
                if not self.accept_kw('THEN'):
                    raise BasicError(2)
                if self.truth(v):
                    return
                target = nxt
                continue
            if c == K['ELSE']:
                self.ip = target + 1
                self.block()
                if self.b() == T.T_LINEREF:
                    self.goto_line(self.ip)
                return
            if c == K['END IF']:
                self.ip = target + 1
                return
            # the line's $00 (a one-line IF without ELSE)
            self.ip = target
            return

    def s_else(self, depth):
        # reached after the part before it: on past the IF
        target = self.block()
        self.to_end_if(target)

    def s_elseif(self, depth):
        target = self.block()
        self.to_end_if(target)

    def to_end_if(self, target):
        while True:
            c = self.code[target]
            if c in (K['ELSEIF'], K['ELSE']):
                target = self.w(target + 2)
                continue
            if c == K['END IF']:
                self.ip = target + 1
            else:
                self.ip = target
            return

    def s_end_if(self, depth):
        pass

    # loops
    def s_for(self, depth):
        target = self.block()
        for_at = self.stmt_ip
        if self.b() != T.T_VAR:
            raise BasicError(2)
        tgt = self.lvalue()
        if isinstance(tgt, ElemRef):
            raise BasicError(2)
        self.expect('=')
        self.store(tgt, self.expr())
        if not self.accept_kw('TO'):
            raise BasicError(2)
        limit = self.convert(tgt.ty, self.expr())
        step = 1 if tgt.ty == TY_I else self.m.from_int(1)
        if self.accept_kw('STEP'):
            step = self.convert(tgt.ty, self.expr())
        self.end_stmt()
        # the old FOR of this variable, if any, goes with what is above it
        for k in range(len(self.stack) - 1, -1, -1):
            fr = self.stack[k]
            if fr.kind == 'CALL':
                break
            if fr.kind == 'FOR' and fr.b is tgt:
                while len(self.stack) > k:
                    self.pop()
                break
        if tgt.ty == TY_S:
            raise BasicError(13)
        if target and not self.for_continues(tgt, limit, step):
            # no pass: on past the NEXT's first variable; NEXT j, i goes on
            # with i
            self.ip = target + 1
            self.block()
            if self.b() == T.T_VAR:
                self.lvalue()
            if self.accept(','):
                return self.next_vars(None, False)
            self.end_stmt()
            return None
        self.push(Frame('FOR', FR_FOR, for_at, tgt, limit, step, self.ip))
        return None

    def for_continues(self, tgt, limit, step):
        if tgt.ty == TY_I:
            return tgt.v <= limit if step >= 0 else tgt.v >= limit
        neg = step[0] != 0 and step[1] & 0x80
        c = self.m.cmp(tgt.v, limit)
        return c >= 0 if neg else c <= 0

    def s_next(self, depth):
        return self.next_vars(self.block(), True)

    def next_vars(self, target, first):
        while True:
            var = None
            if self.b() == T.T_VAR:
                var = self.lvalue()
            # the FOR frame: of this NEXT's FOR (the first), of the variable
            k = len(self.stack) - 1
            found = None
            while k >= 0:
                fr = self.stack[k]
                if fr.kind == 'CALL':
                    break
                if fr.kind == 'FOR':
                    if (first and target and fr.a == target and (var is None or fr.b is var)) or \
                       ((not first or not target) and (var is None or fr.b is var)):
                        found = k
                        break
                k -= 1
            if found is None:
                raise BasicError(18)
            while len(self.stack) - 1 > found:
                self.pop()
            fr = self.stack[found]
            tgt = fr.b
            if tgt.ty == TY_I:
                nv = tgt.v + fr.d
                if -32768 <= nv <= 32767:
                    tgt.v = nv
                    go = self.for_continues(tgt, fr.c, fr.d)
                else:
                    go = False
            else:
                tgt.v = self.m.op('add', tgt.v, fr.d)
                go = self.for_continues(tgt, fr.c, fr.d)
            if go:
                self.ip = fr.e
                return None
            self.pop()
            first = False
            if not self.accept(','):
                break
        self.end_stmt()
        return None

    def s_while(self, depth):
        target = self.block()
        at = self.stmt_ip
        v = self.expr()
        self.end_stmt()
        if not self.truth(v):
            self.pop_inside(at, target)
            self.ip = target + 1
            self.block()

    def s_wend(self, depth):
        target = self.block()
        self.ip = target          # the WHILE again
        self.stmt_ip = target
        self.ip += 1
        self.s_while(depth)

    def s_repeat(self, depth):
        self.block()

    def s_until(self, depth):
        target = self.block()
        v = self.expr()
        self.end_stmt()
        if not self.truth(v):
            self.ip = target + 1
            self.block()

    def s_do(self, depth):
        target = self.block()
        at = self.stmt_ip
        if self.accept_kw('WHILE'):
            go = self.truth(self.expr())
        elif self.accept_kw('UNTIL'):
            go = not self.truth(self.expr())
        else:
            go = True
        self.end_stmt()
        if not go:
            self.pop_inside(at, target)
            self.ip = target + 1
            self.block()
            self.skip_stmt()

    def s_loop(self, depth):
        target = self.block()
        if self.accept_kw('WHILE'):
            go = self.truth(self.expr())
        elif self.accept_kw('UNTIL'):
            go = not self.truth(self.expr())
        else:
            go = True
        self.end_stmt()
        if go:
            self.stmt_ip = target
            self.ip = target + 1
            self.s_do(depth)

    def s_exit_loop(self, depth):
        target = self.block()        # the loop's last word: NEXT WEND LOOP UNTIL
        c = self.code[target]
        start = self.w(target + 2)   # its partner: the loop's first word
        self.pop_inside(start, target)
        if c == K['NEXT']:
            # the FOR's frame too
            for k in range(len(self.stack) - 1, -1, -1):
                fr = self.stack[k]
                if fr.kind == 'CALL':
                    break
                if fr.kind == 'FOR' and fr.a == start:
                    while len(self.stack) > k:
                        self.pop()
                    break
        self.ip = target + 1
        self.block()
        if c != K['WEND']:
            self.skip_stmt()

    def s_select(self, depth):
        target = self.block()
        v = self.expr()
        self.end_stmt()
        self.push(Frame('SELECT', FR_SELECT, self.stmt_ip, v))
        self.select_from(target)

    def select_from(self, target):
        sel = self.stack[-1].b
        while True:
            c = self.code[target]
            if c == K['CASE ELSE']:
                self.ip = target + 1
                self.block()
                return
            if c == K['END SELECT']:
                self.pop()
                self.ip = target + 1
                return
            self.ip = target + 1
            nxt = self.block()
            self.stmt_ip = target
            if self.case_matches(sel):
                return
            target = nxt

    def case_matches(self, sel):
        hit = False
        while True:
            if self.accept_kw('IS'):
                op = self.peek()
                if op not in CMPOPS:
                    raise BasicError(2)
                self.ip += 1
                v = self.expr()
                if self.truth(self.binop(op, sel, v)):
                    hit = True
            else:
                v = self.expr()
                if self.accept_kw('TO'):
                    w = self.expr()
                    if self.truth(self.binop(K['>='], sel, v)) and self.truth(self.binop(K['<='], sel, w)):
                        hit = True
                elif self.truth(self.binop(ord('='), sel, v)):
                    hit = True
            if not self.accept(','):
                break
        self.end_stmt()
        return hit

    def s_case(self, depth):
        # the end of the part before: on to END SELECT
        target = self.block()
        while self.code[target] != K['END SELECT']:
            target = self.w(target + 2)
        self.ip = target
        self.ip += 1
        self.s_end_select(depth)

    def s_end_select(self, depth):
        for k in range(len(self.stack) - 1, -1, -1):
            fr = self.stack[k]
            if fr.kind == 'CALL':
                break
            if fr.kind == 'SELECT':
                while len(self.stack) > k:
                    self.pop()
                return
        raise BasicError(2)

    # procedures
    def s_sub(self, depth):
        target = self.block()       # met in the flow: on past END SUB
        self.ip = target + 1

    def s_end_sub(self, depth):
        self.leave()

    def s_end_function(self, depth):
        k = len(self.stack) - 1
        while k >= 0 and self.stack[k].kind != 'CALL':
            k -= 1
        res = self.leave()
        if depth is not None and k == depth:
            return res
        if res is not None:
            raise BasicError(2)
        return None

    def s_exit_proc(self, depth):
        self.block()
        if self.proc is not None and self.proc.is_function:
            return self.s_end_function(depth)
        self.leave()

    def s_call(self, depth):
        if self.b() != T.T_NAMEREF:
            raise BasicError(2)
        sym = self.w(self.ip + 1)
        self.ip += 6
        p = self.proc_of_sym.get(sym)
        if p is None:
            raise BasicError(2)
        frame = self.call_args(p, None)
        self.end_stmt()
        self.enter(p, frame, self.ip)

    def s_local(self, depth):
        self.skip_stmt()

    # data
    def s_data(self, depth):
        self.skip_stmt()

    def s_read(self, depth):
        while True:
            tgt = self.lvalue()
            if self.dataptr >= len(self.data_index):
                raise BasicError(4)
            at = self.data_index[self.dataptr]
            self.dataptr += 1
            n = self.code[at + 1]
            raw = bytes(self.code[at + 2:at + 2 + n]).decode('latin-1')
            text = raw.strip(' ')
            if tgt.ty == TY_S:
                if text.startswith('"'):
                    j = text.find('"', 1)
                    text = text[1:j] if j > 0 else text[1:]
                tgt.v = text.encode('latin-1')
            else:
                r = self.parse_number(text, True) if text else (TY_I, 0)
                if r is None:
                    raise BasicError(13)
                self.store(tgt, r)
            if not self.accept(','):
                break
        self.end_stmt()

    def s_restore(self, depth):
        if self.at_end():
            self.dataptr = 0
            return
        at = self.ip
        self.ip = self.skip_tok(at)
        self.end_stmt()
        rec = self.line_target(at)
        k = 0
        while k < len(self.data_index) and self.data_index[k] < rec:
            k += 1
        self.dataptr = k

    def s_const(self, depth):
        while True:
            if self.b() != T.T_VAR:
                raise BasicError(2)
            slot = self.w(self.ip + 1)
            self.ip += 3
            cl = self.cell(slot)
            self.expect('=')
            cl.v = self.convert(cl.ty, self.expr())
            if not self.accept(','):
                break
        self.end_stmt()

    def s_dim(self, depth, redim=False):
        while True:
            if self.b() != T.T_VAR:
                raise BasicError(2)
            slot = self.w(self.ip + 1)
            self.ip += 3
            cl = self.array_of(slot)
            subs = self.subscripts()
            if len(subs) > 3:
                raise BasicError(9)
            if cl.arr is not None and not redim:
                raise BasicError(10)
            self.dim(cl, subs)
            if not self.accept(','):
                break
        self.end_stmt()

    def s_redim(self, depth):
        self.s_dim(depth, True)

    # errors
    def s_try(self, depth):
        target = self.block()
        # where an error goes: after CATCH, or after END TRY
        c = self.code[target]
        save = self.ip
        self.ip = target + 1
        if c == K['CATCH']:
            self.block()
        catch = self.ip
        self.ip = save
        self.push(Frame('TRY', FR_TRY, self.stmt_ip, catch, target))

    def s_catch(self, depth):
        target = self.block()       # the TRY part ended well: past END TRY
        for k in range(len(self.stack) - 1, -1, -1):
            fr = self.stack[k]
            if fr.kind == 'CALL':
                break
            if fr.kind == 'TRY':
                while len(self.stack) > k:
                    self.pop()
                break
        self.ip = target + 1

    def s_end_try(self, depth):
        # the end of a TRY without CATCH: its frame
        if self.stack and self.stack[-1].kind == 'TRY' and self.stack[-1].c == self.ip - 1:
            self.pop()

    def s_error(self, depth):
        n = self.to_int(*self.expr())
        msg = None
        if self.accept(','):
            msg = self.convert(TY_S, self.expr()).decode('latin-1')
        self.end_stmt()
        if n < 1 or n > 255:
            raise BasicError(5)
        raise BasicError(n, msg)

    def s_resume(self, depth):
        if not self.inhandler:
            raise BasicError(17)
        self.inhandler = False
        if self.accept_kw('NEXT'):
            self.end_stmt()
            self.ip = self.err_ip
            self.skip_one_stmt()
            return
        if self.at_end():
            self.ip = self.err_ip
            return
        at = self.ip
        self.ip = self.skip_tok(at)
        self.end_stmt()
        self.goto_line(at)

    def skip_one_stmt(self):
        """past the statement at ip (RESUME NEXT): to its ':' or line end"""
        c = self.code[self.ip]
        if c == K['IF']:
            # the whole one-line IF, or the block IF's line
            while self.code[self.ip] != 0:
                self.ip = self.skip_tok(self.ip)
            return
        self.ip = self.skip_tok(self.ip)
        self.skip_stmt()

    # the rest
    def s_end(self, depth):
        raise EndProgram()

    def s_stop(self, depth):
        raise BasicError(1)

    def s_nothing(self, depth):
        self.skip_stmt()

    def s_option(self, depth):
        if self.accept_kw('INTEGER'):
            pass
        elif self.accept_kw('MEMORY'):
            n = self.to_int(*self.expr())
            if n < 1 or n > 64:
                raise BasicError(5)
        else:
            raise BasicError(2)
        self.end_stmt()

    def s_poke(self, depth):
        a = self.address(self.expr())
        self.expect(',')
        v = self.to_int(*self.expr())
        self.end_stmt()
        if a >= 0xA000 or v < 0 or v > 255:
            raise BasicError(5)
        self.mem[a] = v

    def s_sys(self, depth):
        a = self.address(self.expr())
        self.end_stmt()
        if a >= 0xA000:
            raise BasicError(5)
        if self.mem[a] != 0x60:
            raise BasicError(20)

    def s_tron(self, depth):
        self.tron = True
        self.end_stmt()

    def s_troff(self, depth):
        self.tron = False
        self.end_stmt()

    def s_wait(self, depth):
        self.accept_kw('EVENTS')
        if not self.any_bound:
            raise EndProgram()
        self.x_wait()

    def s_sleep(self, depth):
        self.x_sleep()

    def s_doevents(self, depth):
        self.end_stmt()
        if self.any_bound:
            self.x_doevents()

    def s_cont(self, depth):
        self.end_stmt()

    # --- the program ---
    def main(self):
        if not self.code[0]:
            return 'END'
        self.enter_line(0)
        try:
            self.run()
        except EndProgram:
            self.finish()
            return 'END'
        except InputEnd:
            self.finish()
            return 'INPUT'
        except V.Stuck:
            self.finish()
            return 'STUCK'
        except BasicError as e:
            if e.code == 1:
                self.message('Stopped in line %d' % self.erl)
            else:
                self.message('Error %d, %s, in line %d' % (e.code, e.msg, self.erl))
            self.finish()
            return 'ERROR %d' % e.code
        return 'END'

    def finish(self):
        if self.col:
            self.newline()
        self.x2_finish()


class ArrRef:
    """an array parameter: the caller's array"""
    __slots__ = ('cell', 'ty')

    def __init__(self, cell):
        self.cell, self.ty = cell, cell.ty


BINPREC = {K['OR']: 1, K['XOR']: 1, K['AND']: 2, ord('='): 4, K['<>']: 4, ord('<'): 4, ord('>'): 4,
           K['<=']: 4, K['>=']: 4, K['SHL']: 5, K['SHR']: 5, ord('+'): 6, ord('-'): 6,
           ord('*'): 7, ord('/'): 7, ord('\\'): 7, K['MOD']: 7, ord('^'): 9}
CMPOPS = {ord('='): lambda c: c == 0, K['<>']: lambda c: c != 0, ord('<'): lambda c: c < 0,
          ord('>'): lambda c: c > 0, K['<=']: lambda c: c <= 0, K['>=']: lambda c: c >= 0}
EXT = {code & 0xFF: name for name, code in K.items() if code > 0xFF}
Interp.Err = BasicError
Interp.Cell = Cell
Interp.KW = K

STMTS = {
    K['REM']: Interp.s_rem, K['LET']: Interp.s_let, K['PRINT']: Interp.s_print, K['INPUT']: Interp.s_input,
    K['LINE INPUT']: Interp.s_line_input, K['GET']: Interp.s_get, K['GOTO']: Interp.s_goto,
    K['GOSUB']: Interp.s_gosub, K['RETURN']: Interp.s_return, K['ON']: Interp.s_on, K['IF']: Interp.s_if,
    K['ELSE']: Interp.s_else, K['ELSEIF']: Interp.s_elseif, K['END IF']: Interp.s_end_if,
    K['FOR']: Interp.s_for, K['NEXT']: Interp.s_next, K['WHILE']: Interp.s_while, K['WEND']: Interp.s_wend,
    K['REPEAT']: Interp.s_repeat, K['UNTIL']: Interp.s_until, K['DO']: Interp.s_do, K['LOOP']: Interp.s_loop,
    K['EXIT FOR']: Interp.s_exit_loop, K['EXIT WHILE']: Interp.s_exit_loop, K['EXIT DO']: Interp.s_exit_loop,
    K['EXIT REPEAT']: Interp.s_exit_loop, K['SELECT CASE']: Interp.s_select, K['CASE']: Interp.s_case,
    K['CASE ELSE']: Interp.s_case, K['END SELECT']: Interp.s_end_select, K['SUB']: Interp.s_sub,
    K['FUNCTION']: Interp.s_sub, K['END SUB']: Interp.s_end_sub, K['END FUNCTION']: Interp.s_end_function,
    K['EXIT SUB']: Interp.s_exit_proc, K['EXIT FUNCTION']: Interp.s_exit_proc, K['CALL']: Interp.s_call,
    K['LOCAL']: Interp.s_local, K['SHARED']: Interp.s_local, K['DATA']: Interp.s_data, K['READ']: Interp.s_read,
    K['RESTORE']: Interp.s_restore, K['CONST']: Interp.s_const, K['DIM']: Interp.s_dim,
    K['REDIM']: Interp.s_redim, K['TRY']: Interp.s_try, K['CATCH']: Interp.s_catch,
    K['END TRY']: Interp.s_end_try, K['ERROR']: Interp.s_error, K['RESUME']: Interp.s_resume,
    K['END']: Interp.s_end, K['STOP']: Interp.s_stop, K['CONT']: Interp.s_cont, K['OPTION']: Interp.s_option,
    K['DEFINT']: Interp.s_nothing, K['POKE']: Interp.s_poke, K['SYS']: Interp.s_sys, K['TRON']: Interp.s_tron,
    K['TROFF']: Interp.s_troff, K['WAIT']: Interp.s_wait, K['DOEVENTS']: Interp.s_doevents,
    K['SLEEP']: Interp.s_sleep,
}


# ----------------------------------------------------------------------

def load(path):
    data = open(path, 'rb').read()
    if path.lower().endswith('.cvt'):
        if len(data) > 400 and data[254 + 137 - 2:254 + 141 - 2] == b'VRND':
            import vbapp            # a made application: its program
            return T.decode_records(vbapp.read_app(data)[1])
        return T.read_document(data)
    prog = T.check_text(data)
    if prog.errors:
        raise SystemExit('\n'.join('%s:%d: %s' % (path, s, m) for s, m in prog.errors))
    return prog


def make_app(rest, opts):
    """vbasic.py app: File > Make application... on the PC (DECISIONS V99)"""
    import vbapp
    if len(rest) != 1:
        print('app: FILE.bas [-o OUT.cvt] [--run RUN.cvt]', file=sys.stderr)
        return 2
    src = rest[0]
    text = open(src, 'rb').read()
    prog = T.check_text(text)
    if prog.errors:
        for s, m in prog.errors:
            print('%s:%d: %s' % (src, s, m), file=sys.stderr)
        return 1
    base = os.path.basename(src)
    if base.lower().endswith('.bas'):
        base = base[:-4]
    try:
        a = vbapp.app_lines(text, base)
        runf = opts.get('--run') or os.environ.get('VB_RUN') or 'VeraBASIC Run.cvt'
        if not os.path.exists(runf):
            raise vbapp.AppError(0, 'VeraBASIC Run is needed (--run): %s' % runf)
        data = vbapp.make(open(runf, 'rb').read(), T.encode(prog), a)
    except vbapp.AppError as e:
        print('%s:%d: %s' % (src, e.line, e.msg) if e.line else '%s: %s' % (src, e.msg), file=sys.stderr)
        return 1
    out = opts.get('-o') or a['name'] + '.cvt'
    open(out, 'wb').write(data)
    return 0


def maths_for(rom):
    rom = rom or os.environ.get('VB_ROM')
    if rom:
        return ROMMaths(rom)
    return PCMaths()


def run_program(prog, maths, keys=b'', log=False, out=None, replay=None, root=None, trace=False):
    sys.setrecursionlimit(20000)
    it = Interp(prog, maths, keys, log, out, replay, root)
    it.trace_out = trace
    how = it.main()
    if log:
        (out or sys.stdout).write('VB %s\n' % how)
    return how


def replay_lines(path):
    """Run's log of one program (a file of its lines): what the reference
    compares, in order (the console, the statements, the values, the events)"""
    keep = ('VB| ', 'VB> ', 'VB= ', 'VB EVENT ', 'VB TRON', 'VB CD ')
    return [ln.rstrip('\n') for ln in open(path, encoding='latin-1') if ln.startswith(keep)]


def main(argv):
    if not argv:
        print(__doc__, file=sys.stderr)
        return 2
    cmd, args = argv[0], argv[1:]
    opts = {}
    rest = []
    i = 0
    while i < len(args):
        if args[i] in ('-o', '--rom', '--input', '--replay', '--dir', '--run'):
            opts[args[i]] = args[i + 1]
            i += 2
        elif args[i] in ('--log', '--trace'):
            opts[args[i]] = True
            i += 1
        else:
            rest.append(args[i])
            i += 1
    if cmd == 'list' and rest and rest[0].lower().endswith('.cvt'):
        import vbapp
        try:
            sys.stdout.write(T.detok(load(rest[0])))     # (a made application too)
        except (T.VBError, vbapp.AppError) as e:
            print('%s: %s' % (rest[0], e), file=sys.stderr)
            return 1
        return 0
    if cmd in ('check', 'canon', 'list', 'dump'):
        return T.main([cmd] + rest + (['-o', opts['-o']] if '-o' in opts else []))
    if cmd == 'build':
        if '-o' not in opts or len(rest) != 1:
            print('build: FILE.bas -o OUT.cvt', file=sys.stderr)
            return 2
        return T.main(['tok', rest[0], '-o', opts['-o']])
    if cmd == 'app':
        return make_app(rest, opts)
    if cmd == 'doc':
        import vbmanual
        if len(rest) != 1:
            print('doc: OUTDIR', file=sys.stderr)
            return 2
        files = vbmanual.build(rest[0])
        bad = vbmanual.check(rest[0])
        for b in bad:
            print('doc: ' + b, file=sys.stderr)
        print('doc: %d files in %s' % (len(files), rest[0]))
        return 1 if bad else 0
    if cmd == 'import':
        import vbimport
        if len(rest) != 1:
            print('import: FILE.PRG [-o OUT.bas]', file=sys.stderr)
            return 2
        try:
            text, warn = vbimport.import_prg(open(rest[0], 'rb').read())
        except vbimport.ImportError_ as e:
            print('%s: %s' % (rest[0], e), file=sys.stderr)
            return 1
        for w in warn:
            print('%s: %s' % (rest[0], w), file=sys.stderr)
        if '-o' in opts:
            open(opts['-o'], 'w', encoding='latin-1', newline='\n').write(text)
        else:
            sys.stdout.write(text)
        return 0
    if cmd == 'run':
        prog = load(rest[0])
        keys = open(opts['--input'], 'rb').read() if '--input' in opts else b''
        m = maths_for(opts.get('--rom'))
        rp = replay_lines(opts['--replay']) if '--replay' in opts else None
        how = run_program(prog, m, keys, opts.get('--log', False), replay=rp, root=opts.get('--dir'),
                          trace=opts.get('--trace', False))
        if m.approx and not opts.get('--log'):
            print('(floats approximated: no ROM image given, --rom or VB_ROM)', file=sys.stderr)
        return 0 if how == 'END' else 1
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
