#!/usr/bin/env python3
"""Gate vb_tok (DECISIONS V87): the programs G3 is checked on.

usage: mktokset.py OUT_DIR [--fuzz N] [--big]

Writes into OUT_DIR every program of tests/vbasic/corpus, errors, core,
special and speed, every listing of the manual (doclistings.py), every
example of vbasic/keywords.tbl (EX_<n>.bas; a fragment, so prepare may
find errors in it: then the X16 must report the PC's first one), N
programs of tools/vbfuzz.py (FZ_<seed>.bas), programs of float spellings
(FL_<n>.bas, from a seed) and, with --big, one large program (BIG.bas,
about 40 KB, the fuzz programs one after the other with their names
apart) for the speed. Prints the file names, one a line.

MIT licence (LICENSE).
"""
import os
import random
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, '..', '..'))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
import vbfuzz  # noqa: E402


def examples(tbl):
    blocks, cur = [], None
    for line in open(tbl, encoding='latin-1'):
        if re.match(r'(kw|const|apiconst|group)\s', line):
            cur = []
            blocks.append(cur)
        elif cur is not None and re.match(r'\s+example:', line):
            ex = line.split('example:', 1)[1]
            cur.append(ex[1:].rstrip('\n') if ex.startswith(' ') else ex.rstrip('\n'))
    return ['\n'.join(b) + '\n' for b in blocks if b]


def floats(seed, n):
    r = random.Random(seed)
    out = []
    for i in range(n):
        k = r.randint(1, 18)
        ds = ''.join(r.choice('0123456789') for _ in range(k))
        p = r.randint(0, k)
        t = ds[:p] + '.' + ds[p:]
        if r.random() < 0.6:
            t += r.choice('Ee') + r.choice(['', '+', '-']) + str(r.randint(0, 40))
        if not re.search(r'\d', t.split('E')[0].split('e')[0]):
            t = '1' + t
        out.append('f%d = %s' % (i, t))
    return '\n'.join(out) + '\n'


def big_program():
    """about 40 KB: 120 procedures of the usual statements, called from
    the main lines, and a V2-style part with line numbers"""
    L = ["' A large program for the tokenizer's speed (gate vb_tok)", 'OPTION INTEGER', 'DIM table%(100)']
    for i in range(120):
        L.append('Proc%d %d, "w%d"' % (i, i, i))
    L.append('GOSUB 1000')
    L.append('END')
    for i in range(120):
        L += ['SUB Proc%d(a%%, b$)' % i,
              '  LOCAL t%, s$, x',
              '  t%% = a%% * 2 + %d : s$ = b$ + "x%d" : x = 1.25 * a%% + .5' % (i, i),
              '  IF t% > 10 THEN',
              '    PRINT "big"; t%, s$',
              '  ELSEIF t% < 0 THEN',
              '    PRINT "negative"',
              '  ELSE',
              '    table%%(%d) = t%% : PRINT s$; TAB(10); LEN(s$)' % (i % 100),
              '  END IF',
              '  FOR k% = 1 TO 3 : t% = t% + k% : NEXT k%',
              '  WHILE t% > 0 : t% = t% \\ 2 : WEND',
              '  SELECT CASE a% MOD 3',
              '    CASE 0 : PRINT "zero"',
              '    CASE 1, 2 : PRINT "one or two"',
              '  END SELECT',
              'END SUB']
    for n in range(1000, 1400, 10):
        L.append('%d IF table%%(%d) > 5 THEN PRINT "row"; %d : GOTO %d' % (n, n % 100, n, n + 10))
    L.append('1400 RETURN')
    return '\n'.join(L) + '\n'


def fuzz(seed):
    return vbfuzz.program(seed) if hasattr(vbfuzz, 'program') else subprocess.run(
        [sys.executable, '-I', '-B', os.path.join(ROOT, 'tools', 'vbfuzz.py'), str(seed)],
        capture_output=True, check=True).stdout.decode('latin-1')


def main(argv):
    if not argv:
        print(__doc__, file=sys.stderr)
        return 2
    out = argv[0]
    nfuzz = int(argv[argv.index('--fuzz') + 1]) if '--fuzz' in argv else 100
    os.makedirs(out, exist_ok=True)
    names = []

    def put(name, data):
        if isinstance(data, str):
            data = data.encode('latin-1')
        open(os.path.join(out, name), 'wb').write(data)
        names.append(name)

    for sub, pre in (('corpus', ''), ('errors', ''), ('core', 'C_'), ('special', 'S_'), ('speed', 'P_')):
        d = os.path.join(HERE, sub)
        for f in sorted(os.listdir(d)):
            if f.endswith('.bas'):
                put(pre + f, open(os.path.join(d, f), 'rb').read())
    man = os.path.join(ROOT, 'docs', 'vbasic', 'manual')
    tmp = os.path.join(out, '_man')
    subprocess.run([sys.executable, '-I', '-B', os.path.join(HERE, 'doclistings.py'), tmp] +
                   [os.path.join(man, f) for f in sorted(os.listdir(man)) if f.endswith('.md')],
                   check=True, capture_output=True)
    for f in sorted(os.listdir(tmp)):
        if f.endswith('.bas'):
            put('M_' + f, open(os.path.join(tmp, f), 'rb').read())
            os.remove(os.path.join(tmp, f))
        else:
            os.remove(os.path.join(tmp, f))
    os.rmdir(tmp)
    for i, ex in enumerate(examples(os.path.join(ROOT, 'vbasic', 'keywords.tbl'))):
        put('EX_%03d.bas' % i, ex)
    for s in range(nfuzz):
        put('FZ_%03d.bas' % s, fuzz(5000 + s))
    for s in range(10):
        put('FL_%d.bas' % s, floats(77 + s, 60))
    if '--big' in argv:
        put('BIG.bas', big_program())
    print('\n'.join(names))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
