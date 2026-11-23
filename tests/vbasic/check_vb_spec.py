#!/usr/bin/env python3
"""Gate vb_spec's checks of the PC tokenizer (tools/vbtokens.py).

usage: check_vb_spec.py corpus DIR          G1, G2, the program document
       check_vb_spec.py examples TBL        G1, G2 on every example of the table
       check_vb_spec.py fuzz FIRST COUNT    G1, G2 on generated programs
       check_vb_spec.py fuzzfiles DIR       the committed fuzz_NN.bas are vbfuzz's
       check_vb_spec.py errors DIR          prepare reports the planted errors
       check_vb_spec.py floats              the 5-byte float encoding

G1: tok(detok(T)) == T, byte for byte (all four records), for the
tokenizer's output T and for the prepared program.
G2: detok(tok(S)) == canon(S) where canon is the expected canonical form:
the file itself, or NAME.canon next to it (fuzz programs have none), and
canon(canon(S)) == canon(S); tok(canon(S)) == tok(S) (the canonical form
means the same program).

MIT licence (LICENSE).
"""
import glob
import os
import re
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..'))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
import vbtokens as V  # noqa: E402
import vbfuzz  # noqa: E402
import vpack  # noqa: E402

failures = []
partners = 0


def fail(what, msg):
    failures.append('%s: %s' % (what, msg))


def first_diff(a, b):
    for n, (x, y) in enumerate(zip(a, b)):
        if x != y:
            return n
    return min(len(a), len(b))


def same_records(what, a, b, label):
    ra, rb = V.encode(a), V.encode(b)
    for n in range(4):
        if ra[n] != rb[n]:
            k = first_diff(ra[n], rb[n])
            fail(what, '%s: record %d differs at byte %d (%d and %d bytes)' % (label, n, k, len(ra[n]), len(rb[n])))
            return False
    return True


def g1_g2(what, src, expect=None, prepare=True):
    """returns (source bytes, token bytes) or None"""
    t = V.tokenize(src)
    if t.errors:
        fail(what, 'tokenize: line %d: %s' % t.errors[0])
        return None
    text = V.detok(t)
    t2 = V.tokenize(text)
    if t2.errors:
        fail(what, 'the detokenized text does not tokenize: line %d: %s' % t2.errors[0])
        return None
    if not same_records(what, t, t2, 'G1 (tokens)'):
        return None
    # G2
    if expect is not None and text != expect:
        a, b = expect.split('\n'), text.split('\n')
        k = first_diff(a, b)
        fail(what, 'G2: line %d of the canonical form is %r, expected %r'
             % (k + 1, b[k] if k < len(b) else '', a[k] if k < len(a) else ''))
        return None
    if V.detok(V.tokenize(text)) != text:
        fail(what, 'G2: canon(canon(S)) != canon(S)')
        return None
    size = sum(len(ln.toks) for ln in t.lines)
    if prepare:
        p = V.prepare(V.tokenize(src))
        if p.errors:
            fail(what, 'prepare: line %d: %s' % p.errors[0])
            return None
        ptext = V.detok(p)
        if ptext != text:
            fail(what, 'the prepared program detokenizes differently')
            return None
        p2 = V.prepare(V.tokenize(ptext))
        if not same_records(what, p, p2, 'G1 (prepared)'):
            return None
        global partners
        partners += check_prepared(what, p) or 0
        # the program document: written, read back by vpack and by vbtokens
        recs = V.encode(p)
        doc = V.write_document('Test', recs)
        info = vpack.parse(doc)
        if info.get('structure') != 'VLIR' or info.get('records') != [len(r) for r in recs]:
            fail(what, 'the document\'s records as vpack reads them: %r' % (info.get('records'),))
            return None
        if info['class'] != 'VeraBASIC   V1.0':
            fail(what, 'the document\'s class is %r' % info['class'])
        back = V.read_document(doc)
        if not same_records(what, p, back, 'the document read back'):
            return None
        if V.detok(back) != text:
            fail(what, 'the document read back detokenizes differently')
            return None
    return len(src.encode('latin-1')), size


PARTNERS = {
    'IF': ('ELSEIF', 'ELSE', 'END IF', 'EOL'), 'ELSEIF': ('ELSEIF', 'ELSE', 'END IF'), 'ELSE': ('END IF', 'EOL'),
    'WHILE': ('WEND',), 'WEND': ('WHILE',), 'REPEAT': ('UNTIL',), 'UNTIL': ('REPEAT',), 'DO': ('LOOP',),
    'LOOP': ('DO',), 'FOR': ('NEXT',), 'NEXT': ('FOR',), 'SELECT CASE': ('CASE', 'CASE ELSE', 'END SELECT'),
    'CASE': ('CASE', 'CASE ELSE', 'END SELECT'), 'CASE ELSE': ('END SELECT',), 'SUB': ('END SUB',),
    'FUNCTION': ('END FUNCTION',), 'TRY': ('CATCH', 'END TRY'), 'CATCH': ('END TRY',), 'EXIT FOR': ('NEXT',),
    'EXIT WHILE': ('WEND',), 'EXIT DO': ('LOOP',), 'EXIT REPEAT': ('UNTIL',), 'EXIT SUB': ('END SUB',),
    'EXIT FUNCTION': ('END FUNCTION',), 'DIALOG': ('END DIALOG',)}


def check_prepared(what, p):
    """every block offset points at its partner; name targets, the line and
    DATA indexes point where they should"""
    at = {}                 # absolute offset -> keyword name, or 'EOL'
    starts = set()
    for ln in p.lines:
        starts.add(ln.off)
        for t in V.decode(ln.toks):
            if t.tag == 'kw':
                at[ln.off + 6 + t.pos] = V.KWINFO[t.val]['name']
            if t.tag == 'data':
                at[ln.off + 6 + t.pos] = 'DATA ITEM'
        at[ln.off + 6 + len(ln.toks)] = 'EOL'
    n = 0
    for ln in p.lines:
        toks = V.decode(ln.toks)
        for k, t in enumerate(toks):
            if t.tag != 'blk':
                continue
            kw = V.KWINFO[toks[k - 1].val]['name']
            if t.val == 0:
                if kw in ('FOR', 'NEXT'):
                    continue            # matched at run time (a one-line IF)
                fail(what, 'line %d: %s has no partner' % (ln.src, kw))
                return
            if at.get(t.val) not in PARTNERS[kw]:
                fail(what, 'line %d: %s points at %s' % (ln.src, kw, at.get(t.val)))
                return
            n += 1
        for t in toks:
            if t.tag == 'nref':
                s = p.syms[t.val]
                if s.kind & V.K_LABEL and t.raw not in starts:
                    fail(what, 'line %d: label %s points at %d' % (ln.src, s.name, t.raw))
                if s.kind & (V.K_SUB | V.K_FUNCTION) and at.get(t.raw) not in ('SUB', 'FUNCTION'):
                    fail(what, 'line %d: %s points at %s' % (ln.src, s.name, at.get(t.raw)))
    nums = [ln for ln in p.lines if ln.number]
    if [x[0] for x in p.line_index] != sorted(ln.number for ln in nums) or \
            any(next(ln for ln in nums if ln.number == num).off != off for num, off in p.line_index):
        fail(what, 'the line index')
    if any(at.get(off) != 'DATA ITEM' for off in p.data_index):
        fail(what, 'the DATA index')
    return n


def corpus(d):
    files = sorted(glob.glob(os.path.join(d, '*.bas')))
    src_bytes = tok_bytes = 0
    for f in files:
        src = open(f, 'rb').read().decode('latin-1')
        name = os.path.basename(f)
        cf = f[:-4] + '.canon'
        expect = None
        if os.path.exists(cf):
            expect = open(cf, 'rb').read().decode('latin-1')
        elif not name.startswith('fuzz_'):
            expect = src
        r = g1_g2(name, src, expect)
        if r:
            src_bytes += r[0]
            tok_bytes += r[1]
    if not failures:
        print('ok    G1 and G2 on %d corpus programs (%d source bytes, %d token bytes: %.2f a byte);'
              ' %d block offsets at their partners' % (len(files), src_bytes, tok_bytes,
                                                       tok_bytes / max(1, src_bytes), partners))


def examples(tbl):
    blocks, cur = [], None
    for line in open(tbl, encoding='latin-1'):
        if re.match(r'(kw|const|apiconst|group)\s', line):
            cur = [line.split('|')[0].split(None, 1)[1].strip(), []]
            blocks.append(cur)
        elif cur is not None and re.match(r'\s+example:', line):
            ex = line.split('example:', 1)[1]
            cur[1].append(ex[1:].rstrip('\n') if ex.startswith(' ') else ex.rstrip('\n'))
    n = 0
    for name, lines in blocks:
        if not lines:
            continue
        n += 1
        g1_g2('example of %s' % name, '\n'.join(lines) + '\n', None, prepare=False)
    if not failures:
        print('ok    every keyword\'s example tokenizes; G1 and G2 on %d examples' % n)


def fuzz(first, count):
    for seed in range(first, first + count):
        g1_g2('fuzz %d' % seed, vbfuzz.generate(seed), None)
    if not failures:
        print('ok    G1 and G2 on %d generated programs (seeds %d-%d); %d block offsets at their partners'
              % (count, first, first + count - 1, partners))


def fuzzfiles(d):
    n = 0
    for f in sorted(glob.glob(os.path.join(d, 'fuzz_*.bas'))):
        seed = 1000 + int(re.search(r'fuzz_(\d+)', f).group(1))
        if open(f, 'rb').read().decode('latin-1') != vbfuzz.generate(seed):
            fail(os.path.basename(f), 'is not what tools/vbfuzz.py %d makes' % seed)
        n += 1
    if not failures:
        print('ok    the %d committed fuzz programs are tools/vbfuzz.py\'s' % n)


def errors(d):
    files = sorted(glob.glob(os.path.join(d, '*.bas')))
    total = 0
    for f in files:
        src = open(f, 'rb').read().decode('latin-1')
        want = set()
        for line in src.split('\n'):
            m = re.match(r"' expect (\d+): (.*)$", line)
            if m:
                for msg in m.group(2).split(' | '):
                    want.add((int(m.group(1)), msg))
        got = set(V.check_text(src).errors)
        name = os.path.basename(f)
        if not want:
            fail(name, 'plants no error')
        for e in sorted(want - got):
            fail(name, 'line %d: expected "%s", not reported' % e)
        for e in sorted(got - want):
            fail(name, 'line %d: reported "%s", not expected' % e)
        total += len(want)
    if not failures:
        print('ok    prepare reports the %d planted errors of %d programs, each at its line' % (total, len(files)))


def floats():
    cases = {'1': '8100000000', '0.5': '8000000000', '-1': '8180000000', '10': '8420000000',
             '0.1': '7D4CCCCCCD', '0': '0000000000', '3.14159265358979': '82490FDAA2',
             '65535': '907FFF0000', '1E9': '9E6E6B2800', '.25': '7F00000000'}
    for text, hexval in cases.items():
        got = V.float5(('-' if text.startswith('-') else '') + text.lstrip('-')).hex().upper()
        if got != hexval:
            fail('float %s' % text, 'encoded %s, expected %s' % (got, hexval))
    if not failures:
        print('ok    the 5-byte float encoding (%d values)' % len(cases))


def main(argv):
    if not argv:
        print(__doc__, file=sys.stderr)
        return 2
    cmd = argv[0]
    if cmd == 'corpus':
        corpus(argv[1])
    elif cmd == 'examples':
        examples(argv[1])
    elif cmd == 'fuzz':
        fuzz(int(argv[1]), int(argv[2]))
    elif cmd == 'fuzzfiles':
        fuzzfiles(argv[1])
    elif cmd == 'errors':
        errors(argv[1])
    elif cmd == 'floats':
        floats()
    else:
        print(__doc__, file=sys.stderr)
        return 2
    for f in failures[:20]:
        print('FAIL  ' + f)
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
