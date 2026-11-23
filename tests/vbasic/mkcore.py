#!/usr/bin/env python3
"""gate vb_core's generated programs: tests/vbasic/core/gen_NN.bas, made
from fixed seeds (the files are committed; run it again only to change
them). Each program exercises the evaluator, strings, arrays, control flow
or procedures with random but valid code, every risky statement inside
TRY, so that a difference between VeraBASIC Run and tools/vbasic.py run
shows as a different line.

usage: mkcore.py [OUT_DIR] [COUNT]      (default tests/vbasic/core, 100)

MIT licence (LICENSE).
"""
import os
import random
import sys

INT_OPS = ['+', '-', '*', '\\', 'MOD', 'AND', 'OR', 'XOR', 'SHL', 'SHR']
CMP_OPS = ['=', '<>', '<', '>', '<=', '>=']
FLT_OPS = ['+', '-', '*', '/', '^']
FLT_FNS = ['SQR(ABS(%s))', 'ABS(%s)', 'INT(%s)', 'SIN(%s)', 'COS(%s)', 'ATN(%s)', 'SGN(%s)',
           'EXP(%s / 50)', 'LOG(ABS(%s) + 1)']
WORDS = ['robin', 'wren', 'tit', 'jay', 'owl', 'kite', 'crow', 'rook', 'lark', 'swift']


class Gen:
    def __init__(self, seed):
        self.r = random.Random(seed)
        self.lines = []

    def emit(self, s):
        self.lines.append(s)

    def ival(self):
        r = self.r
        k = r.random()
        if k < 0.5:
            return str(r.randint(0, 300))
        if k < 0.6:
            return str(r.randint(0, 32767))
        if k < 0.7:
            return '$%X' % r.randint(0, 0xFFFF)
        if k < 0.75:
            return '%' + bin(r.randint(0, 255))[2:]
        return r.choice(['a%', 'b%', 'c%', 'd%'])

    def iexpr(self, depth=0):
        r = self.r
        if depth > 2 or r.random() < 0.3:
            v = self.ival()
            if r.random() < 0.15:
                v = '-' + v
            return v
        k = r.random()
        if k < 0.6:
            op = r.choice(INT_OPS)
            right = self.iexpr(depth + 1)
            if op in ('SHL', 'SHR'):
                right = str(r.randint(0, 17))
            return '(%s %s %s)' % (self.iexpr(depth + 1), op, right)
        if k < 0.75:
            return '(%s %s %s)' % (self.iexpr(depth + 1), r.choice(CMP_OPS), self.iexpr(depth + 1))
        if k < 0.85:
            return 'NOT %s' % self.iexpr(depth + 1)
        if k < 0.92:
            return 'ABS(%s)' % self.iexpr(depth + 1)
        return 'SGN(%s)' % self.iexpr(depth + 1)

    def fval(self):
        r = self.r
        k = r.random()
        if k < 0.4:
            return '%d.%d' % (r.randint(0, 99), r.randint(0, 999))
        if k < 0.5:
            return '%dE%d' % (r.randint(1, 9), r.randint(-5, 5))
        if k < 0.6:
            return str(r.randint(0, 1000))
        return r.choice(['x', 'y', 'z', 'a%'])

    def fexpr(self, depth=0):
        r = self.r
        if depth > 2 or r.random() < 0.3:
            v = self.fval()
            if r.random() < 0.15:
                v = '-' + v
            return v
        k = r.random()
        if k < 0.6:
            op = r.choice(FLT_OPS)
            if op == '^':
                return '(%s ^ %s)' % (self.fexpr(depth + 1), r.choice(['2', '0.5', '3', '-1', '1.5']))
            return '(%s %s %s)' % (self.fexpr(depth + 1), op, self.fexpr(depth + 1))
        return r.choice(FLT_FNS) % self.fexpr(depth + 1)

    def sval(self):
        r = self.r
        k = r.random()
        if k < 0.4:
            return '"%s"' % r.choice(WORDS)
        if k < 0.7:
            return r.choice(['s$', 't$', 'u$'])
        if k < 0.8:
            return 'STR$(%s)' % self.ival()
        return 'CHR$(%d)' % r.randint(65, 90)

    def sexpr(self, depth=0):
        r = self.r
        if depth > 2 or r.random() < 0.35:
            return self.sval()
        k = r.random()
        if k < 0.4:
            return '%s + %s' % (self.sexpr(depth + 1), self.sexpr(depth + 1))
        if k < 0.55:
            return 'LEFT$(%s, %d)' % (self.sexpr(depth + 1), r.randint(0, 9))
        if k < 0.7:
            return 'RIGHT$(%s, %d)' % (self.sexpr(depth + 1), r.randint(0, 9))
        if k < 0.85:
            return 'MID$(%s, %d, %d)' % (self.sexpr(depth + 1), r.randint(1, 6), r.randint(0, 6))
        return 'MID$(%s, %d)' % (self.sexpr(depth + 1), r.randint(1, 6))

    # --- program kinds ---
    def p_int(self, n):
        r = self.r
        self.emit("' generated: integer expressions (the fast path, overflow into floats)")
        self.emit('a%% = %d: b%% = %d: c%% = %d: d%% = %d' % tuple(r.randint(-300, 300) for _ in range(4)))
        for i in range(n):
            e = self.iexpr()
            self.emit('TRY: PRINT %d; %s: CATCH: PRINT %d; "error"; ERR: END TRY' % (i, e, i))
            if r.random() < 0.3:
                v = r.choice(['a%', 'b%', 'c%', 'd%'])
                self.emit('TRY: %s = %s: CATCH: PRINT "store"; ERR: END TRY' % (v, self.iexpr()))
        self.emit('PRINT a%; b%; c%; d%')

    def p_float(self, n):
        r = self.r
        self.emit("' generated: float expressions through the ROM's maths")
        self.emit('x = %s: y = %s: z = %s: a%% = %d' % (self.fval_lit(), self.fval_lit(), self.fval_lit(),
                                                         r.randint(-50, 50)))
        for i in range(n):
            e = self.fexpr()
            self.emit('TRY: PRINT %d; %s: CATCH: PRINT %d; "error"; ERR: END TRY' % (i, e, i))
            if r.random() < 0.3:
                v = r.choice(['x', 'y', 'z'])
                self.emit('TRY: %s = %s: CATCH: PRINT "store"; ERR: END TRY' % (v, self.fexpr()))
        self.emit('PRINT x; y; z')

    def fval_lit(self):
        r = self.r
        return '%s%d.%d' % (r.choice(['', '-']), r.randint(0, 50), r.randint(0, 99))

    def p_mixed(self, n):
        r = self.r
        self.emit("' generated: integers and floats mixed, assignments converting")
        self.emit('a% = 7: b% = -3: c% = 100: d% = 0: x = 2.5: y = -0.75: z = 1E3')
        for i in range(n):
            k = r.random()
            if k < 0.4:
                self.emit('TRY: a%% = %s: PRINT a%%: CATCH: PRINT "error"; ERR: END TRY' % self.fexpr())
            elif k < 0.7:
                self.emit('TRY: x = %s * %s: PRINT x: CATCH: PRINT "error"; ERR: END TRY' % (
                    self.iexpr(), self.fexpr()))
            else:
                self.emit('TRY: PRINT %s %s %s: CATCH: PRINT "error"; ERR: END TRY' % (
                    self.iexpr(), r.choice(CMP_OPS), self.fexpr()))

    def p_string(self, n):
        r = self.r
        self.emit("' generated: strings, the heap and its collector")
        self.emit('s$ = "%s": t$ = "%s": u$ = ""' % (r.choice(WORDS), r.choice(WORDS)))
        for i in range(n):
            k = r.random()
            e = self.sexpr()
            if k < 0.4:
                self.emit('TRY: PRINT "["; %s; "]": CATCH: PRINT "error"; ERR: END TRY' % e)
            elif k < 0.7:
                v = r.choice(['s$', 't$', 'u$'])
                self.emit('TRY: %s = LEFT$(%s, 60): PRINT LEN(%s): CATCH: PRINT "error"; ERR: END TRY' % (v, e, v))
            elif k < 0.85:
                self.emit('TRY: PRINT %s %s %s: CATCH: PRINT "error"; ERR: END TRY' % (
                    e, r.choice(CMP_OPS), self.sexpr()))
            else:
                self.emit('TRY: PRINT ASC(%s + "?"); VAL(%s): CATCH: PRINT "error"; ERR: END TRY' % (
                    e, 'STR$(%s)' % self.ival()))
        self.emit('PRINT s$; "|"; t$; "|"; u$')

    def p_arrays(self, n):
        r = self.r
        self.emit("' generated: arrays of each type, their elements in expressions")
        d1, d2 = r.randint(3, 40), r.randint(2, 9)
        self.emit('DIM n%%(%d), f(%d, %d), w$(%d)' % (d1, d2, d2, d2))
        self.emit('FOR i%% = 0 TO %d: n%%(i%%) = (i%% * %d) MOD 97: NEXT' % (d1, r.randint(3, 50)))
        self.emit('FOR i%% = 0 TO %d: FOR j%% = 0 TO %d: f(i%%, j%%) = i%% / (j%% + 1): NEXT j%%, i%%' % (d2, d2))
        self.emit('FOR i%% = 0 TO %d: w$(i%%) = MID$("%s", i%% + 1, 3): NEXT' % (d2, ''.join(WORDS)))
        for i in range(n):
            k = r.random()
            a = r.randint(0, d1 + 2)
            b, c = r.randint(0, d2 + 1), r.randint(0, d2)
            if k < 0.35:
                self.emit('TRY: PRINT n%%(%d) + n%%(%d) * 2: CATCH: PRINT "error"; ERR: END TRY' % (a, r.randint(0, d1)))
            elif k < 0.6:
                self.emit('TRY: PRINT f(%d, %d): CATCH: PRINT "error"; ERR: END TRY' % (b, c))
            elif k < 0.8:
                self.emit('TRY: w$(%d) = w$(%d) + "%s": PRINT w$(%d): CATCH: PRINT "error"; ERR: END TRY' % (
                    r.randint(0, d2), r.randint(0, d2 + 1), r.choice(WORDS)[:3], r.randint(0, d2)))
            else:
                self.emit('TRY: n%%(%d) = n%%(%d) - %s: PRINT n%%(%d): CATCH: PRINT "error"; ERR: END TRY' % (
                    r.randint(0, d1), r.randint(0, d1), self.ival(), r.randint(0, d1)))
        self.emit('s = 0: FOR i%% = 0 TO %d: s = s + n%%(i%%): NEXT: PRINT s; UBOUND(n%%); UBOUND(f, 2)' % d1)

    def p_flow(self, n):
        r = self.r
        self.emit("' generated: loops, decisions and counters")
        self.emit('c% = 0: t = 0')
        depth = 0
        for i in range(n):
            k = r.random()
            if k < 0.25:
                lo, hi, st = r.randint(-5, 5), r.randint(-5, 15), r.choice(['', ' STEP 2', ' STEP -1', ' STEP 3'])
                self.emit('FOR i%d%% = %d TO %d%s: c%% = c%% + i%d%%: NEXT' % (i, lo, hi, st, i))
            elif k < 0.4:
                self.emit('j%% = 0: WHILE j%% < %d: j%% = j%% + %d: t = t + j%% / 2: WEND' % (
                    r.randint(0, 20), r.randint(1, 3)))
            elif k < 0.55:
                self.emit('IF c%% %s %d THEN c%% = c%% \\ 2 ELSE c%% = c%% + %d' % (
                    r.choice(CMP_OPS), r.randint(-50, 200), r.randint(1, 9)))
            elif k < 0.7:
                self.emit('SELECT CASE c%% MOD %d' % r.randint(2, 7))
                self.emit('  CASE 0: t = t + 1')
                self.emit('  CASE 1, 2: t = t * 1.5')
                self.emit('  CASE IS > 4: t = t - 2')
                self.emit('  CASE ELSE: c% = c% + 1')
                self.emit('END SELECT')
            elif k < 0.85:
                self.emit('k%% = 0: DO: k%% = k%% + 1: IF k%% > %d THEN EXIT DO' % r.randint(0, 9))
                self.emit('LOOP: c% = c% + k%')
            else:
                self.emit('m%% = %d: REPEAT: m%% = m%% - 3: UNTIL m%% < 0: t = t + m%%' % r.randint(0, 30))
            if r.random() < 0.4:
                self.emit('PRINT %d; c%%; t' % i)
        self.emit('PRINT c%; t')

    def p_procs(self, n):
        r = self.r
        self.emit("' generated: SUBs and FUNCTIONs with parameters, locals, recursion")
        self.emit('total% = 0')
        self.emit('FUNCTION F%(a%, b%)')
        self.emit('  LOCAL t%')
        self.emit('  t%% = (a%% * %d + b%%) MOD 1000' % r.randint(2, 30))
        self.emit('  IF a% > 0 THEN t% = t% + F%(a% - 1, b% \\ 2)')
        self.emit('  F% = t%')
        self.emit('END FUNCTION')
        self.emit('FUNCTION G(x)')
        self.emit('  G = x * %s + %s' % (self.fval_lit(), self.fval_lit()))
        self.emit('END FUNCTION')
        self.emit('FUNCTION H$(s$, n%)')
        self.emit('  IF n% <= 0 THEN RETURN s$')
        self.emit('  H$ = H$(LEFT$(s$ + "%s", 30), n%% - 1)' % r.choice(WORDS)[:2])
        self.emit('END FUNCTION')
        self.emit('SUB Acc(BYREF v%, d%)')
        self.emit('  v% = (v% + d%) MOD 30000')
        self.emit('END SUB')
        for i in range(n):
            k = r.random()
            if k < 0.3:
                self.emit('TRY: PRINT F%%(%d, %d): CATCH: PRINT "error"; ERR: END TRY' % (
                    r.randint(0, 8), r.randint(0, 999)))
            elif k < 0.55:
                self.emit('TRY: PRINT G(%s); G(G(%s)): CATCH: PRINT "error"; ERR: END TRY' % (
                    self.fval_lit(), self.fval_lit()))
            elif k < 0.75:
                self.emit('PRINT H$("%s", %d)' % (r.choice(WORDS), r.randint(0, 6)))
            else:
                self.emit('Acc total%%, F%%(%d, %d): PRINT total%%' % (r.randint(0, 4), r.randint(0, 99)))
        self.emit('PRINT total%')


KINDS = ['p_int', 'p_float', 'p_mixed', 'p_string', 'p_arrays', 'p_flow', 'p_procs']


def main(argv):
    out = argv[0] if argv else os.path.join(os.path.dirname(os.path.abspath(__file__)), 'core')
    count = int(argv[1]) if len(argv) > 1 else 100
    os.makedirs(out, exist_ok=True)
    for k in range(count):
        g = Gen(8600 + k)
        kind = KINDS[k % len(KINDS)]
        getattr(g, kind)(g.r.randint(12, 28))
        open(os.path.join(out, 'gen_%02d.bas' % k), 'w').write('\n'.join(g.lines) + '\n')
    print('mkcore: %d programs in %s' % (count, out))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
