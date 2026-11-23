#!/usr/bin/env python3
"""Random VeraBASIC programs for the tokenizer's gates (tools/gate_vb_spec.sh).

usage: vbfuzz.py SEED [-o FILE]

A program from the seed alone (the same seed, the same bytes): structured
or line-numbered (V2 style), every block closed, names that are neither
keywords nor constants, keywords in random case and the spaces between
tokens at random (only where the tokens stay apart), so its canonical form
differs from it. Structurally valid: prepare finds no error in it.

MIT licence (LICENSE).
"""
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import vbtokens_gen as G  # noqa: E402

SYLL = ['ro', 'bin', 'wren', 'tit', 'kes', 'trel', 'fin', 'ch', 'lark', 'sw', 'ift', 'jay', 'owl', 'gull', 'tern',
        'kite', 'pip', 'it', 'dun', 'lin', 'mar', 'tin', 'ow', 'z']
RESERVED = set(G.KEYWORDS) | set(G.CONSTANTS)
STMT_TEMPLATES = [
    'BOX {n}, {n}, {n}, {n}', 'FRAME {n}, {n}, {n}, {n}', 'LINE {n}, {n}, {n}, {n}', 'PLOT {n}, {n}',
    'TEXT {n}, {n}, {s}', 'PAPER {n}, {n}, {n}, {n}, YELLOW', 'CARDS {n}, {n}, {s}', 'PATTERN {n}', 'CLS',
    'SOUND SND_ERROR', 'BEEP', 'VOICE 0, {n}, 63, PULSE', 'POKE {n}, {n}', 'SLEEP {n}', 'DOEVENTS',
    'WINDOW STATUS #1, {s}, {s}', 'MSGBOX {s}', 'POINTER BUSY', 'INK $0223', 'SPRITE 2 AT {n}, {n}',
    'TIMER 1 OFF', 'MENU ENABLE {s}, {s}, 1', 'CLIPBOARD {s}', 'PRINT #1, {s}', 'SEEK #1, {n}',
]
FUNCS_N = ['ABS({n})', 'INT({n})', 'SGN({n})', 'SQR({n})', 'LEN({s})', 'ASC({s})', 'VAL({s})', 'PEEK({n})',
           'POINT({n}, {n})', 'MOUSEX', 'MOUSEY', 'TI', 'RND(1)', 'TEXTWIDTH({s})', 'UBOUND(arr%)']
FUNCS_S = ['LEFT$({s}, {n})', 'RIGHT$({s}, {n})', 'MID$({s}, {n})', 'MID$({s}, {n}, {n})', 'CHR$({n})',
           'STR$({n})', 'INKEY$', 'TIME$', 'CURDIR$', 'DIR$()', 'FOLDER$(DOCS)']
OPS = ['+', '-', '*', '/', '\\', 'MOD', 'AND', 'OR', 'XOR', 'SHL', '=', '<>', '<', '>', '<=', '>=']


class Fuzz:
    def __init__(self, seed):
        self.r = random.Random(seed)
        self.numbered = self.r.random() < 0.3
        self.names = set()
        self.vars = []
        self.svars = []
        self.subs = []          # (name, nparams)
        self.labels = []
        self.lines = []
        self.depth = 0

    def name(self, suffix=''):
        while True:
            n = ''.join(self.r.choice(SYLL) for _ in range(self.r.randint(1, 3)))
            n = ''.join(c.upper() if self.r.random() < 0.3 else c for c in n)
            if n.upper() + suffix not in RESERVED and n.upper() not in RESERVED and \
                    (n.upper() + suffix) not in self.names and n.upper() not in self.names:
                self.names.add(n.upper() + suffix)
                self.names.add(n.upper())
                return n + suffix

    def kw(self, w):
        """a keyword in random case"""
        if self.r.random() < 0.6:
            return w
        return ''.join(c.lower() if self.r.random() < 0.5 else c for c in w)

    def num(self):
        r = self.r.random()
        if r < 0.5:
            return str(self.r.randint(0, 999))
        if r < 0.6:
            return '$%X' % self.r.randint(0, 0xFFFF)
        if r < 0.65:
            return '%' + format(self.r.randint(0, 255), 'b')
        if r < 0.85:
            return self.r.choice(['1.5', '.25', '3.', '1E3', '2.5e-3', '1.0E+10', '0.1', '40000', '123456789'])
        return self.r.choice(self.vars) if self.vars else '7'

    def string(self):
        if self.svars and self.r.random() < 0.4:
            return self.r.choice(self.svars)
        txt = self.r.choice(['', 'a', 'Hello', 'say ""hi""', 'x, y: z', "it's", 'caf\xe9', '  spaced  '])
        return '"%s"' % txt

    def expr(self, d=0):
        r = self.r.random()
        if d > 2 or r < 0.35:
            return self.num()
        if r < 0.5:
            return self.fill(self.r.choice(FUNCS_N), d)
        if r < 0.6:
            return '-' + self.expr(d + 1)
        if r < 0.7:
            return '(' + self.expr(d + 1) + ')'
        if r < 0.75:
            return self.kw('NOT') + ' ' + self.expr(d + 1)
        op = self.r.choice(OPS)
        if op[0].isalpha():
            op = self.kw(op)
        return self.expr(d + 1) + ' ' + op + ' ' + self.expr(d + 1)

    def sexpr(self, d=0):
        if d > 1 or self.r.random() < 0.5:
            return self.string()
        if self.r.random() < 0.5:
            return self.fill(self.r.choice(FUNCS_S), d)
        return self.sexpr(d + 1) + ' + ' + self.sexpr(d + 1)

    def fill(self, t, d=0):
        out, i = [], 0
        while i < len(t):
            if t.startswith('{n}', i):
                out.append(self.expr(d + 1))
                i += 3
            elif t.startswith('{s}', i):
                out.append(self.sexpr(d + 1))
                i += 3
            else:
                j = i
                while j < len(t) and t[j] != '{':
                    j += 1
                out.append(self.kwtext(t[i:j]))
                i = j
        return ''.join(out)

    def kwtext(self, text):
        """keywords inside a template in random case (names are kept)"""
        out, w = [], ''
        for c in text + ' ':
            if c.isalnum() or c in '_$%':
                w += c
                continue
            if w:
                out.append(self.kw(w) if w.upper() in G.KEYWORDS else w)
                w = ''
            out.append(c)
        return ''.join(out)[:-1]

    def emit(self, text, indent):
        self.lines.append((indent, text))

    # statements: each returns nothing, emits lines
    def simple(self):
        r = self.r.random()
        if r < 0.25 and self.vars:
            v = self.r.choice(self.vars)
            return (self.kw('LET') + ' ' if self.r.random() < 0.1 else '') + v + ' = ' + self.expr()
        if r < 0.35 and self.svars:
            return self.r.choice(self.svars) + ' = ' + self.sexpr()
        if r < 0.5:
            items = [self.r.choice([self.expr, self.sexpr])() for _ in range(self.r.randint(0, 3))]
            seps = [self.r.choice(['; ', ', ', ';', ',']) for _ in items]
            body = ''.join(i + s for i, s in zip(items, seps))
            if body and self.r.random() < 0.6:
                body = body.rstrip(';, ')
            return self.kw('PRINT') + ((' ' + body) if body else '')
        if r < 0.6 and self.subs:
            n, k = self.r.choice(self.subs)
            args = ', '.join(self.expr() for _ in range(k))
            if self.r.random() < 0.4 or not k:   # a bare name and ":" would be a label
                return self.kw('CALL') + ' ' + n + ('(' + args + ')' if k else '')
            return n + ((' ' + args) if k else '')
        if r < 0.65:
            return 'arr%(' + self.expr() + ') = ' + self.expr()
        if r < 0.7:
            return self.kw('DATA') + ' ' + ', '.join(self.r.choice(['1', '-2.5', '"a,b"', 'word', '']) for _ in
                                                    range(self.r.randint(1, 4)))
        if r < 0.75:
            return self.kw('READ') + ' ' + (self.r.choice(self.vars) if self.vars else 'q')
        return self.fill(self.r.choice(STMT_TEMPLATES))

    def block(self, indent, budget):
        while budget > 0:
            budget -= 1
            r = self.r.random()
            if self.depth >= 3 or r < 0.45:
                stmts = [self.simple() for _ in range(self.r.randint(1, 3 if self.r.random() < 0.3 else 1))]
                text = ': '.join(stmts)
                if self.r.random() < 0.15:
                    text += " ' note " + str(self.r.randint(0, 99))
                self.emit(text, indent)
                continue
            self.depth += 1
            if r < 0.55:
                self.emit(self.kw('IF') + ' ' + self.expr() + ' ' + self.kw('THEN') + ' ' + self.simple() +
                          ((' ' + self.kw('ELSE') + ' ' + self.simple()) if self.r.random() < 0.4 else ''), indent)
            elif r < 0.65:
                self.emit(self.kw('IF') + ' ' + self.expr() + ' ' + self.kw('THEN'), indent)
                self.block(indent + 2, self.r.randint(1, 3))
                for _ in range(self.r.randint(0, 2)):
                    self.emit(self.kw('ELSEIF') + ' ' + self.expr() + ' ' + self.kw('THEN'), indent)
                    self.block(indent + 2, self.r.randint(1, 2))
                if self.r.random() < 0.5:
                    self.emit(self.kw('ELSE'), indent)
                    self.block(indent + 2, self.r.randint(1, 2))
                self.emit(self.kw('END') + ' ' * self.r.randint(1, 2) + self.kw('IF'), indent)
            elif r < 0.73:
                v = self.r.choice(self.vars) if self.vars else 'i'
                step = (' ' + self.kw('STEP') + ' ' + self.expr()) if self.r.random() < 0.3 else ''
                self.emit('%s %s = %s %s %s%s' % (self.kw('FOR'), v, self.expr(), self.kw('TO'), self.expr(), step),
                          indent)
                self.block(indent + 2, self.r.randint(1, 3))
                if self.r.random() < 0.2:
                    self.emit(self.kw('IF') + ' ' + self.expr() + ' ' + self.kw('THEN') + ' ' +
                              self.kw('EXIT') + ' ' + self.kw('FOR'), indent + 2)
                self.emit(self.kw('NEXT') + ((' ' + v) if self.r.random() < 0.5 else ''), indent)
            elif r < 0.79:
                self.emit(self.kw('WHILE') + ' ' + self.expr(), indent)
                self.block(indent + 2, self.r.randint(1, 3))
                self.emit(self.kw('WEND'), indent)
            elif r < 0.84:
                self.emit(self.kw('REPEAT'), indent)
                self.block(indent + 2, self.r.randint(1, 3))
                self.emit(self.kw('UNTIL') + ' ' + self.expr(), indent)
            elif r < 0.89:
                top = self.r.choice(['', ' ' + self.kw('WHILE') + ' ' + self.expr(), ' ' + self.kw('UNTIL') + ' ' +
                                     self.expr()])
                self.emit(self.kw('DO') + top, indent)
                self.block(indent + 2, self.r.randint(1, 2))
                self.emit(self.kw('IF') + ' ' + self.expr() + ' ' + self.kw('THEN') + ' ' + self.kw('EXIT') + ' ' +
                          self.kw('DO'), indent + 2)
                bottom = '' if top else self.r.choice(['', ' ' + self.kw('UNTIL') + ' ' + self.expr()])
                self.emit(self.kw('LOOP') + bottom, indent)
            elif r < 0.95:
                self.emit(self.kw('SELECT') + ' ' + self.kw('CASE') + ' ' + self.expr(), indent)
                for _ in range(self.r.randint(1, 3)):
                    c = self.r.choice([lambda: self.expr(), lambda: self.expr() + ' ' + self.kw('TO') + ' ' + self.expr(),
                                       lambda: self.kw('IS') + ' > ' + self.expr()])
                    self.emit(self.kw('CASE') + ' ' + ', '.join(c() for _ in range(self.r.randint(1, 2))), indent + 2)
                    self.block(indent + 4, 1)
                if self.r.random() < 0.5:
                    self.emit(self.kw('CASE') + ' ' + self.kw('ELSE'), indent + 2)
                    self.block(indent + 4, 1)
                self.emit(self.kw('END') + ' ' + self.kw('SELECT'), indent)
            else:
                self.emit(self.kw('TRY'), indent)
                self.block(indent + 2, self.r.randint(1, 2))
                if self.r.random() < 0.8:
                    self.emit(self.kw('CATCH'), indent)
                    self.emit(self.kw('PRINT') + ' ' + self.kw('ERR$'), indent + 2)
                self.emit(self.kw('END') + ' ' + self.kw('TRY'), indent)
            self.depth -= 1

    def program(self):
        self.emit("' fuzz program", 0)
        if self.r.random() < 0.3:
            self.emit(self.kw('OPTION') + ' ' + self.kw('INTEGER'), 0)
        self.emit(self.kw('DIM') + ' arr%(20)', 0)
        for _ in range(self.r.randint(2, 5)):
            v = self.name(self.r.choice(['', '%', '%']))
            self.vars.append(v)
            self.emit('%s = %s' % (v, self.num() if self.vars[:-1] else '1'), 0)
        for _ in range(self.r.randint(1, 2)):
            s = self.name('$')
            self.svars.append(s)
            self.emit('%s = %s' % (s, self.string()), 0)
        subs = [(self.name(), self.r.randint(0, 2)) for _ in range(self.r.randint(0, 3))]
        self.subs = subs
        self.block(0, self.r.randint(6, 16))
        if not self.numbered:
            lab = self.name()
            self.emit(self.kw('GOTO') + ' ' + lab, 0)
            self.emit(lab + ':', 0)
        self.emit(self.kw('END'), 0)
        for n, k in subs:
            params = [self.name(self.r.choice(['', '%', '$'])) for _ in range(k)]
            plist = ['%s%s' % (self.kw('BYREF') + ' ' if self.r.random() < 0.2 else '', p) for p in params]
            self.emit('%s %s%s' % (self.kw('SUB'), n, '(' + ', '.join(plist) + ')' if k else ''), 0)
            saved = self.vars
            self.vars = self.vars + [p for p in params if not p.endswith('$')]
            loc = self.name('%')
            self.emit(self.kw('LOCAL') + ' ' + loc, 2)
            self.vars.append(loc)
            subs_saved, self.subs = self.subs, []
            self.block(2, self.r.randint(1, 4))
            self.subs = subs_saved
            self.vars = saved
            self.emit(self.kw('END') + ' ' + self.kw('SUB'), 0)
        out = []
        no = 10
        for indent, text in self.lines:
            if self.numbered and not text.startswith(self.kw('SUB')[:0] + "'"):
                if any(text.upper().startswith(w) for w in ('SUB ', 'END SUB', 'LOCAL')):
                    out.append(' ' * indent + text)
                else:
                    out.append('%d %s%s' % (no, ' ' * indent, text))
                    no += self.r.choice([1, 10, 10, 5])
            else:
                out.append(' ' * indent + text)
        return '\n'.join(self.respace(t) for t in out) + '\n'

    def respace(self, line):
        """vary the spaces between tokens (outside strings and comments)"""
        out, i, q = [], 0, False
        while i < len(line):
            c = line[i]
            if c == '"':
                q = not q
            if not q and c == "'":
                out.append(line[i:])
                break
            if not q and c == ' ' and out and i + 1 < len(line):
                prev, nxt = out[-1][-1:], line[i + 1]
                word = (prev.isalnum() or prev in '_$%.') and (nxt.isalnum() or nxt in '_$%.')
                if word or prev in '-+' or nxt in "'" or self.r.random() < 0.5:
                    out.append(' ' * (1 if word or self.r.random() < 0.7 else 2))
                i += 1
                continue
            out.append(c)
            i += 1
        return ''.join(out)


def generate(seed):
    return Fuzz(seed).program()


def main(argv):
    if not argv:
        print(__doc__, file=sys.stderr)
        return 2
    text = generate(int(argv[0]))
    if len(argv) == 3 and argv[1] == '-o':
        open(argv[2], 'w', encoding='latin-1', newline='\n').write(text)
    else:
        sys.stdout.write(text)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
