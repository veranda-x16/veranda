#!/usr/bin/env python3
"""The X16 ROM's maths library, run in a small 65C02 emulator, for
VeraBASIC's reference interpreter (tools/vbasic.py run).

VeraBASIC's floats are the ROM's: the runtime on the X16 calls the maths
library through its public jump table (ROM bank 4, $FE00) and nothing of
it is copied into VeraBASIC. The reference interpreter must give the same
bits, so it runs the same routines of the user's own ROM image (read at
run time from the file given, never stored): each float operation here is
exactly the call sequence the runtime makes (apps/vbasic/fp.s), operands
and results packed in the 5-byte format between operations.

    m = Maths('rom.bin')
    m.op('mul', a5, b5) -> c5          (a5, b5, c5: 5-byte packed floats)

Errors of the library (overflow, division by zero, illegal quantity) come
back as MathError(code) with the X16 BASIC error number in x, caught where
the library jumps through BASIC's error vector ($0300), as the runtime
catches them.

MIT licence (LICENSE). The emulator is VeraBASIC's own.
"""
import sys

BANK = 4                # ROM bank of BASIC and the maths library
JT = {                  # the library's public jump table (x16-rom math/jumptab.s)
    'ayint': 0xFE00, 'givayf': 0xFE03, 'fout': 0xFE06, 'val': 0xFE09, 'getadr': 0xFE0C,
    'fsub': 0xFE12, 'fsubt': 0xFE15, 'fadd': 0xFE18, 'faddt': 0xFE1B, 'fmult': 0xFE1E,
    'fmultt': 0xFE21, 'fdiv': 0xFE24, 'fdivt': 0xFE27, 'log': 0xFE2A, 'int': 0xFE2D,
    'sqr': 0xFE30, 'fpwrt': 0xFE39, 'exp': 0xFE3C, 'cos': 0xFE3F, 'sin': 0xFE42,
    'tan': 0xFE45, 'atn': 0xFE48, 'abs': 0xFE4E, 'sign': 0xFE51, 'fcomp': 0xFE54,
    'rnd': 0xFE57, 'conupk': 0xFE5A, 'movfm': 0xFE63, 'movmf': 0xFE66, 'negfac': 0xFE78, 'mul10': 0xFE7B, 'div10': 0xFE7E,
    'qint': 0xFE8D,
}
FAC = 0xC3              # the library's zero page (facexp .. facsgn, then ARG at $CA)
FACMO = FAC + 3         # ayint's result: facmo+1 (low), facmo (high) -> $C6/$C7
OPA = 0x0400            # where the emulated runtime keeps its two operands
OPB = 0x0408
RES = 0x0410
STRBUF = 0x0420         # VAL's text
FBUFFR = 0x0100         # fout's text
IERROR = 0x0300         # BASIC's error vector: the runtime points it at its handler
TRAP = 0x0480           # the handler: an address where the emulator stops
RET = 0x0490            # the return address of a call: where it stops
RNDX = 0x03CE           # the library's random seed (FPVARS)
SEED = bytes([0x80, 0x4F, 0xC7, 0x52, 0x58])  # VeraBASIC's starting seed (vbasic.py and fp.s)


class MathError(Exception):
    def __init__(self, code):
        Exception.__init__(self, code)
        self.code = code


class CPU:
    """a 65C02 with flat RAM below $C000 and one ROM bank above"""

    def __init__(self, rom):
        self.m = bytearray(0x10000)
        self.m[0xC000:] = rom
        self.a = self.x = self.y = 0
        self.s = 0xFF
        self.p = 0x24
        self.pc = 0
        self.count = 0

    # flags: N V - B D I Z C
    def rd(self, a):
        return self.m[a]

    def wr(self, a, v):
        if a < 0xC000:
            self.m[a] = v

    def nz(self, v):
        self.p = (self.p & 0x7D) | (v & 0x80) | (0 if v else 2)
        return v

    def push(self, v):
        self.m[0x100 + self.s] = v
        self.s = (self.s - 1) & 0xFF

    def pull(self):
        self.s = (self.s + 1) & 0xFF
        return self.m[0x100 + self.s]

    def adc(self, v):
        c = self.p & 1
        a = self.a
        if self.p & 8:
            lo = (a & 15) + (v & 15) + c
            hi = (a >> 4) + (v >> 4)
            if lo > 9:
                lo += 6
            if lo > 15:
                hi += 1
            r = (a + v + c) & 0xFF
            v_ = (~(a ^ v) & (a ^ (hi << 4)) & 0x80)
            if hi > 9:
                hi += 6
            res = ((hi << 4) | (lo & 15)) & 0xFF
            self.p = (self.p & 0x3C) | (1 if hi > 15 else 0) | (0x40 if v_ else 0)
            self.a = res
            self.nz(res)
            del r
            return
        r = a + v + c
        self.p = (self.p & 0x3C) | (1 if r > 0xFF else 0) | (0x40 if (~(a ^ v) & (a ^ r) & 0x80) else 0)
        self.a = r & 0xFF
        self.nz(self.a)

    def sbc(self, v):
        if self.p & 8:
            c = self.p & 1
            a = self.a
            r = a - v - (1 - c)
            lo = (a & 15) - (v & 15) - (1 - c)
            hi = (a >> 4) - (v >> 4)
            if lo < 0:
                lo -= 6
                hi -= 1
            if hi < 0:
                hi -= 6
            res = ((hi << 4) | (lo & 15)) & 0xFF
            self.p = (self.p & 0x3C) | (1 if r >= 0 else 0) | (0x40 if ((a ^ v) & (a ^ r) & 0x80) else 0)
            self.a = res
            self.nz(res)
            return
        self.adc(v ^ 0xFF)

    def cmp(self, r, v):
        d = r - v
        self.p = (self.p & 0x7C) | (1 if d >= 0 else 0) | (d & 0x80) | (2 if d & 0xFF == 0 else 0)

    def run(self, stop, limit=20000000):
        m = self.m
        n = 0
        while True:
            pc = self.pc
            if pc == stop or pc == TRAP:
                self.count += n
                return pc
            op = m[pc]
            n += 1
            if n > limit:
                raise RuntimeError('vbrom: runaway at $%04X' % pc)
            f = OPS[op]
            if f is None:
                raise RuntimeError('vbrom: opcode $%02X at $%04X' % (op, pc))
            f(self)


# --- addressing (return the effective address; advance pc) ---
def a_imm(c):
    a = c.pc + 1
    c.pc += 2
    return a


def a_zp(c):
    a = c.m[c.pc + 1]
    c.pc += 2
    return a


def a_zpx(c):
    a = (c.m[c.pc + 1] + c.x) & 0xFF
    c.pc += 2
    return a


def a_zpy(c):
    a = (c.m[c.pc + 1] + c.y) & 0xFF
    c.pc += 2
    return a


def a_abs(c):
    a = c.m[c.pc + 1] | c.m[c.pc + 2] << 8
    c.pc += 3
    return a


def a_absx(c):
    a = ((c.m[c.pc + 1] | c.m[c.pc + 2] << 8) + c.x) & 0xFFFF
    c.pc += 3
    return a


def a_absy(c):
    a = ((c.m[c.pc + 1] | c.m[c.pc + 2] << 8) + c.y) & 0xFFFF
    c.pc += 3
    return a


def a_izx(c):
    z = (c.m[c.pc + 1] + c.x) & 0xFF
    c.pc += 2
    return c.m[z] | c.m[(z + 1) & 0xFF] << 8


def a_izy(c):
    z = c.m[c.pc + 1]
    c.pc += 2
    return ((c.m[z] | c.m[(z + 1) & 0xFF] << 8) + c.y) & 0xFFFF


def a_izp(c):
    z = c.m[c.pc + 1]
    c.pc += 2
    return c.m[z] | c.m[(z + 1) & 0xFF] << 8


MODES = {'imm': a_imm, 'zp': a_zp, 'zpx': a_zpx, 'zpy': a_zpy, 'abs': a_abs, 'absx': a_absx,
         'absy': a_absy, 'izx': a_izx, 'izy': a_izy, 'izp': a_izp}
OPS = [None] * 256


def reg(code, mode, fn):
    am = MODES[mode]

    def f(c):
        fn(c, am(c))
    OPS[code] = f


def i_lda(c, a):
    c.a = c.nz(c.m[a])


def i_ldx(c, a):
    c.x = c.nz(c.m[a])


def i_ldy(c, a):
    c.y = c.nz(c.m[a])


def i_sta(c, a):
    c.wr(a, c.a)


def i_stx(c, a):
    c.wr(a, c.x)


def i_sty(c, a):
    c.wr(a, c.y)


def i_stz(c, a):
    c.wr(a, 0)


def i_adc(c, a):
    c.adc(c.m[a])


def i_sbc(c, a):
    c.sbc(c.m[a])


def i_and(c, a):
    c.a = c.nz(c.a & c.m[a])


def i_ora(c, a):
    c.a = c.nz(c.a | c.m[a])


def i_eor(c, a):
    c.a = c.nz(c.a ^ c.m[a])


def i_cmp(c, a):
    c.cmp(c.a, c.m[a])


def i_cpx(c, a):
    c.cmp(c.x, c.m[a])


def i_cpy(c, a):
    c.cmp(c.y, c.m[a])


def i_bit(c, a):
    v = c.m[a]
    c.p = (c.p & 0x3D) | (v & 0xC0) | (0 if v & c.a else 2)


def i_bitimm(c, a):
    v = c.m[a]
    c.p = (c.p & 0xFD) | (0 if v & c.a else 2)


def rmw(fn):
    def g(c, a):
        c.wr(a, fn(c, c.m[a]))
    return g


def f_asl(c, v):
    c.p = (c.p & 0xFE) | (v >> 7)
    return c.nz((v << 1) & 0xFF)


def f_lsr(c, v):
    c.p = (c.p & 0xFE) | (v & 1)
    return c.nz(v >> 1)


def f_rol(c, v):
    r = ((v << 1) | (c.p & 1)) & 0xFF
    c.p = (c.p & 0xFE) | (v >> 7)
    return c.nz(r)


def f_ror(c, v):
    r = (v >> 1) | ((c.p & 1) << 7)
    c.p = (c.p & 0xFE) | (v & 1)
    return c.nz(r)


def f_inc(c, v):
    return c.nz((v + 1) & 0xFF)


def f_dec(c, v):
    return c.nz((v - 1) & 0xFF)


def i_tsb(c, a):
    v = c.m[a]
    c.p = (c.p & 0xFD) | (0 if v & c.a else 2)
    c.wr(a, v | c.a)


def i_trb(c, a):
    v = c.m[a]
    c.p = (c.p & 0xFD) | (0 if v & c.a else 2)
    c.wr(a, v & ~c.a & 0xFF)


def group(base_name, fn, table):
    for code, mode in table:
        reg(code, mode, fn)


group('ora', i_ora, [(0x09, 'imm'), (0x05, 'zp'), (0x15, 'zpx'), (0x0D, 'abs'), (0x1D, 'absx'),
                     (0x19, 'absy'), (0x01, 'izx'), (0x11, 'izy'), (0x12, 'izp')])
group('and', i_and, [(0x29, 'imm'), (0x25, 'zp'), (0x35, 'zpx'), (0x2D, 'abs'), (0x3D, 'absx'),
                     (0x39, 'absy'), (0x21, 'izx'), (0x31, 'izy'), (0x32, 'izp')])
group('eor', i_eor, [(0x49, 'imm'), (0x45, 'zp'), (0x55, 'zpx'), (0x4D, 'abs'), (0x5D, 'absx'),
                     (0x59, 'absy'), (0x41, 'izx'), (0x51, 'izy'), (0x52, 'izp')])
group('adc', i_adc, [(0x69, 'imm'), (0x65, 'zp'), (0x75, 'zpx'), (0x6D, 'abs'), (0x7D, 'absx'),
                     (0x79, 'absy'), (0x61, 'izx'), (0x71, 'izy'), (0x72, 'izp')])
group('sta', i_sta, [(0x85, 'zp'), (0x95, 'zpx'), (0x8D, 'abs'), (0x9D, 'absx'),
                     (0x99, 'absy'), (0x81, 'izx'), (0x91, 'izy'), (0x92, 'izp')])
group('lda', i_lda, [(0xA9, 'imm'), (0xA5, 'zp'), (0xB5, 'zpx'), (0xAD, 'abs'), (0xBD, 'absx'),
                     (0xB9, 'absy'), (0xA1, 'izx'), (0xB1, 'izy'), (0xB2, 'izp')])
group('cmp', i_cmp, [(0xC9, 'imm'), (0xC5, 'zp'), (0xD5, 'zpx'), (0xCD, 'abs'), (0xDD, 'absx'),
                     (0xD9, 'absy'), (0xC1, 'izx'), (0xD1, 'izy'), (0xD2, 'izp')])
group('sbc', i_sbc, [(0xE9, 'imm'), (0xE5, 'zp'), (0xF5, 'zpx'), (0xED, 'abs'), (0xFD, 'absx'),
                     (0xF9, 'absy'), (0xE1, 'izx'), (0xF1, 'izy'), (0xF2, 'izp')])
group('ldx', i_ldx, [(0xA2, 'imm'), (0xA6, 'zp'), (0xB6, 'zpy'), (0xAE, 'abs'), (0xBE, 'absy')])
group('ldy', i_ldy, [(0xA0, 'imm'), (0xA4, 'zp'), (0xB4, 'zpx'), (0xAC, 'abs'), (0xBC, 'absx')])
group('stx', i_stx, [(0x86, 'zp'), (0x96, 'zpy'), (0x8E, 'abs')])
group('sty', i_sty, [(0x84, 'zp'), (0x94, 'zpx'), (0x8C, 'abs')])
group('stz', i_stz, [(0x64, 'zp'), (0x74, 'zpx'), (0x9C, 'abs'), (0x9E, 'absx')])
group('cpx', i_cpx, [(0xE0, 'imm'), (0xE4, 'zp'), (0xEC, 'abs')])
group('cpy', i_cpy, [(0xC0, 'imm'), (0xC4, 'zp'), (0xCC, 'abs')])
group('bit', i_bit, [(0x24, 'zp'), (0x34, 'zpx'), (0x2C, 'abs'), (0x3C, 'absx')])
group('bit#', i_bitimm, [(0x89, 'imm')])
group('tsb', i_tsb, [(0x04, 'zp'), (0x0C, 'abs')])
group('trb', i_trb, [(0x14, 'zp'), (0x1C, 'abs')])
for _fn, _tab in ((f_asl, [(0x06, 'zp'), (0x16, 'zpx'), (0x0E, 'abs'), (0x1E, 'absx')]),
                  (f_lsr, [(0x46, 'zp'), (0x56, 'zpx'), (0x4E, 'abs'), (0x5E, 'absx')]),
                  (f_rol, [(0x26, 'zp'), (0x36, 'zpx'), (0x2E, 'abs'), (0x3E, 'absx')]),
                  (f_ror, [(0x66, 'zp'), (0x76, 'zpx'), (0x6E, 'abs'), (0x7E, 'absx')]),
                  (f_inc, [(0xE6, 'zp'), (0xF6, 'zpx'), (0xEE, 'abs'), (0xFE, 'absx')]),
                  (f_dec, [(0xC6, 'zp'), (0xD6, 'zpx'), (0xCE, 'abs'), (0xDE, 'absx')])):
    group('', rmw(_fn), _tab)


def acc(fn):
    def g(c):
        c.a = fn(c, c.a)
        c.pc += 1
    return g


OPS[0x0A] = acc(f_asl)
OPS[0x4A] = acc(f_lsr)
OPS[0x2A] = acc(f_rol)
OPS[0x6A] = acc(f_ror)
OPS[0x1A] = acc(f_inc)
OPS[0x3A] = acc(f_dec)


def imp(code, fn):
    def g(c):
        fn(c)
        c.pc += 1
    OPS[code] = g


def _set(attr):
    def g(c):
        setattr(c, attr[1], c.nz(getattr(c, attr[0])))
    return g


imp(0xAA, _set(('a', 'x')))
imp(0xA8, _set(('a', 'y')))
imp(0x8A, _set(('x', 'a')))
imp(0x98, _set(('y', 'a')))
imp(0xBA, _set(('s', 'x')))
imp(0x9A, lambda c: setattr(c, 's', c.x))
imp(0xE8, lambda c: setattr(c, 'x', c.nz((c.x + 1) & 0xFF)))
imp(0xC8, lambda c: setattr(c, 'y', c.nz((c.y + 1) & 0xFF)))
imp(0xCA, lambda c: setattr(c, 'x', c.nz((c.x - 1) & 0xFF)))
imp(0x88, lambda c: setattr(c, 'y', c.nz((c.y - 1) & 0xFF)))
imp(0x18, lambda c: setattr(c, 'p', c.p & 0xFE))
imp(0x38, lambda c: setattr(c, 'p', c.p | 1))
imp(0x58, lambda c: setattr(c, 'p', c.p & 0xFB))
imp(0x78, lambda c: setattr(c, 'p', c.p | 4))
imp(0xD8, lambda c: setattr(c, 'p', c.p & 0xF7))
imp(0xF8, lambda c: setattr(c, 'p', c.p | 8))
imp(0xB8, lambda c: setattr(c, 'p', c.p & 0xBF))
imp(0xEA, lambda c: None)
imp(0x48, lambda c: c.push(c.a))
imp(0xDA, lambda c: c.push(c.x))
imp(0x5A, lambda c: c.push(c.y))
imp(0x08, lambda c: c.push(c.p | 0x30))
imp(0x68, lambda c: setattr(c, 'a', c.nz(c.pull())))
imp(0xFA, lambda c: setattr(c, 'x', c.nz(c.pull())))
imp(0x7A, lambda c: setattr(c, 'y', c.nz(c.pull())))
imp(0x28, lambda c: setattr(c, 'p', (c.pull() & 0xCF) | 0x20))


def branch(code, mask, want):
    def g(c):
        if (c.p & mask) == want:
            d = c.m[c.pc + 1]
            c.pc = (c.pc + 2 + (d - 256 if d > 127 else d)) & 0xFFFF
        else:
            c.pc += 2
    OPS[code] = g


branch(0x10, 0x80, 0)
branch(0x30, 0x80, 0x80)
branch(0x50, 0x40, 0)
branch(0x70, 0x40, 0x40)
branch(0x90, 1, 0)
branch(0xB0, 1, 1)
branch(0xD0, 2, 0)
branch(0xF0, 2, 2)
branch(0x80, 0, 0)


def i_jmp(c):
    c.pc = c.m[c.pc + 1] | c.m[c.pc + 2] << 8


def i_jmpi(c):
    a = c.m[c.pc + 1] | c.m[c.pc + 2] << 8
    c.pc = c.m[a] | c.m[(a + 1) & 0xFFFF] << 8


def i_jmpix(c):
    a = ((c.m[c.pc + 1] | c.m[c.pc + 2] << 8) + c.x) & 0xFFFF
    c.pc = c.m[a] | c.m[(a + 1) & 0xFFFF] << 8


def i_jsr(c):
    r = c.pc + 2
    c.push(r >> 8)
    c.push(r & 0xFF)
    c.pc = c.m[c.pc + 1] | c.m[c.pc + 2] << 8


def i_rts(c):
    lo = c.pull()
    c.pc = ((c.pull() << 8 | lo) + 1) & 0xFFFF


def i_rti(c):
    c.p = (c.pull() & 0xCF) | 0x20
    lo = c.pull()
    c.pc = c.pull() << 8 | lo


OPS[0x4C] = i_jmp
OPS[0x6C] = i_jmpi
OPS[0x7C] = i_jmpix
OPS[0x20] = i_jsr
OPS[0x60] = i_rts
OPS[0x40] = i_rti


def bbx(code, bit, setv):
    def g(c):
        v = c.m[c.m[c.pc + 1]]
        d = c.m[c.pc + 2]
        if bool(v & (1 << bit)) == setv:
            c.pc = (c.pc + 3 + (d - 256 if d > 127 else d)) & 0xFFFF
        else:
            c.pc += 3
    OPS[code] = g


def rsmb(code, bit, setv):
    def g(c):
        z = c.m[c.pc + 1]
        c.m[z] = (c.m[z] | (1 << bit)) if setv else (c.m[z] & ~(1 << bit) & 0xFF)
        c.pc += 2
    OPS[code] = g


for _b in range(8):
    bbx(0x0F + 16 * _b, _b, False)
    bbx(0x8F + 16 * _b, _b, True)
    rsmb(0x07 + 16 * _b, _b, False)
    rsmb(0x87 + 16 * _b, _b, True)


class Maths:
    """the ROM's maths library, by the runtime's call sequences"""

    def __init__(self, rom_path):
        data = open(rom_path, 'rb').read()
        if len(data) < (BANK + 1) * 16384:
            raise ValueError('vbrom: %s is not an X16 ROM image' % rom_path)
        self.cpu = CPU(data[BANK * 16384:(BANK + 1) * 16384])
        m = self.cpu.m
        m[IERROR] = TRAP & 0xFF
        m[IERROR + 1] = TRAP >> 8
        m[RNDX:RNDX + 5] = SEED
        self.cache = {}

    def call(self, name, a=0, x=0, y=0, flags=None):
        c = self.cpu
        c.a, c.x, c.y = a, x, y
        if flags is not None:
            c.p = (c.p & 0x7D) | flags
        c.s = 0xFF
        r = RET - 1
        c.push(r >> 8)
        c.push(r & 0xFF)
        c.pc = JT[name]
        if c.run(RET) == TRAP:
            raise MathError(c.x)

    # the packed operands
    def put(self, at, v5):
        self.cpu.m[at:at + 5] = v5

    def get(self, at):
        return bytes(self.cpu.m[at:at + 5])

    def load_fac(self, v5):
        self.put(OPA, v5)
        self.call('movfm', OPA & 0xFF, 0, OPA >> 8)

    def store_fac(self):
        self.call('movmf', 0, RES & 0xFF, RES >> 8)
        return self.get(RES)

    def op(self, name, a5, b5):
        """a OP b for add, sub, mul, div, pow: ARG = a, FAC = b, FAC = ARG op FAC"""
        key = (name, a5, b5)
        r = self.cache.get(key)
        if r is not None:
            return r
        self.put(OPB, a5)
        self.call('conupk', OPB & 0xFF, 0, OPB >> 8)      # ARG = a
        self.load_fac(b5)                                 # FAC = b
        self.call({'add': 'faddt', 'sub': 'fsubt', 'mul': 'fmultt', 'div': 'fdivt', 'pow': 'fpwrt'}[name],
                  flags=self._expflags())
        r = self.store_fac()
        if len(self.cache) > 50000:
            self.cache.clear()
        self.cache[key] = r
        return r

    def _expflags(self):
        # the "fixed" entries set their flags themselves; a = facexp
        e = self.cpu.m[FAC]
        self.cpu.a = e
        return (e & 0x80) | (0 if e else 2)

    def fn(self, name, a5):
        """FAC = f(a) for int, sqr, sin, cos, tan, atn, exp, log, abs"""
        key = (name, a5)
        r = self.cache.get(key)
        if r is not None:
            return r
        self.load_fac(a5)
        self.call(name)
        r = self.store_fac()
        self.cache[key] = r
        return r

    @staticmethod
    def neg(a5):
        """-a: the sign bit turned over (not the library's negfac, which
        complements the mantissa); 0 stays 0"""
        if a5[0] == 0:
            return a5
        return bytes([a5[0], a5[1] ^ 0x80]) + a5[2:]

    def cmp(self, a5, b5):
        """-1, 0, 1 as a < b, a = b, a > b (FAC = a compared with b)"""
        self.load_fac(a5)
        self.put(OPB, b5)
        self.call('fcomp', OPB & 0xFF, 0, OPB >> 8)
        v = self.cpu.a
        return -1 if v == 0xFF else v

    def from_int(self, n):
        n &= 0xFFFF
        self.call('givayf', n >> 8, 0, n & 0xFF)
        return self.store_fac()

    def to_int(self, a5):
        """the value as a signed 16-bit integer (ayint); MathError when out of range"""
        self.load_fac(a5)
        self.call('ayint')
        m = self.cpu.m
        v = m[FACMO + 1] | m[FACMO] << 8
        return v - 0x10000 if v & 0x8000 else v

    def text(self, a5):
        """the value as PRINT shows it (fout)"""
        key = ('fout', a5)
        r = self.cache.get(key)
        if r is not None:
            return r
        self.load_fac(a5)
        self.call('fout')
        m = self.cpu.m
        i = FBUFFR
        while m[i]:
            i += 1
        r = bytes(m[FBUFFR:i]).decode('latin-1')
        self.cache[key] = r
        return r

    def mul10(self, a5):
        self.load_fac(a5)
        self.call('mul10')
        return self.store_fac()

    def div10(self, a5):
        self.load_fac(a5)
        self.call('div10')
        return self.store_fac()

    def rnd(self, a5):
        """RND(a): a < 0 seeds from a, a > 0 the next number, 0 is not offered here"""
        self.load_fac(a5)
        self.call('sign')
        v = self.cpu.a
        self.call('rnd', 0, 0, 0, flags=(v & 0x80) | (0 if v else 2))
        return self.store_fac()

    def reseed(self):
        self.cpu.m[RNDX:RNDX + 5] = SEED


if __name__ == '__main__':
    m = Maths(sys.argv[1])
    one = m.from_int(1)
    three = m.from_int(3)
    print(m.text(m.op('div', one, three)), m.text(m.op('sub', one, three)), m.text(m.fn('sqr', m.from_int(2))))
