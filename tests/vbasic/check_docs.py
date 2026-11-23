#!/usr/bin/env python3
"""gate vb_app (DECISIONS V99): the docs check. Every listing of the whole
manual (tools/vbmanual.py's chapters, the reference card, the examples)
checks and runs: each fenced ```basic block (not "nocheck") is a program
(tests/vbasic/doclistings.py), tools/vbasic.py check passes on it, and the
reference interpreter runs it (with the ROM's floats, its ```keys as the
keys typed) without an error; each example program checks and runs too.
The Veranda statements are checked and logged by the reference, their
events not played (the X16 gates vb_ui, vb_files, vb_debug run them with
their mouse scripts). Also: `vbasic.py import` of a crunched V2 listing
gives the listing back, runnable.

usage: check_docs.py OUT_DIR ROM
MIT licence (LICENSE)."""
import glob
import os
import subprocess
import sys

TOP = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..')
sys.path.insert(0, os.path.join(TOP, 'tools'))
import vbmanual  # noqa: E402
import vbimport  # noqa: E402

# chapters whose blocks are fragments the generator writes (the reference's
# examples are gate vb_spec's: every keyword's example tokenizes)
SKIP = ('reference.md', 'tokens.md')
PY = [sys.executable, '-I', '-B']
# listings that end in an error on the PC, as they should: the chapter
# shows the error; or the machine has what the PC has not (the clipboard's
# text, a tile's file on the card: gate vb_files runs them on the X16)
EXPECT = {'getting-started/gettings_3': 11, 'extensions2/extensio_8': 5, 'extensions2/extensio_9': 50}


def run(args, **kw):
    return subprocess.run(PY + [os.path.join(TOP, 'tools', 'vbasic.py')] + args, capture_output=True,
                          text=True, encoding='latin-1', timeout=300, **kw)


def main(argv):
    if len(argv) != 2:
        sys.exit(__doc__)
    out, rom = argv
    os.makedirs(out, exist_ok=True)
    mdir = os.path.join(TOP, 'docs', 'vbasic', 'manual')
    chapters = [os.path.join(mdir, c) for c in vbmanual.CHAPTERS + [vbmanual.REFCARD]
                if c not in SKIP and os.path.exists(os.path.join(mdir, c))]
    progs = []
    for c in chapters:                  # (a folder each: extensions and extensions2 share a prefix)
        lst = os.path.join(out, 'listings', os.path.basename(c)[:-3])
        r = subprocess.run(PY + [os.path.join(TOP, 'tests', 'vbasic', 'doclistings.py'), lst, c],
                           capture_output=True, text=True)
        if r.returncode:
            sys.exit('check_docs: doclistings: ' + r.stderr)
        progs += sorted(glob.glob(os.path.join(lst, '*.bas')))
    progs += sorted(glob.glob(os.path.join(TOP, 'docs', 'vbasic', 'examples', '*.bas')))
    bad, n = [], 0
    files = os.path.join(out, 'files')
    os.makedirs(files, exist_ok=True)
    for p in progs:
        c = run(['check', p])
        if c.returncode:
            bad.append('%s does not check: %s' % (p, (c.stdout + c.stderr).strip()))
            continue
        k = p[:-4] + '.key'
        x = run(['run', p, '--rom', rom, '--dir', files] + (['--input', k] if os.path.exists(k) else []))
        text = x.stdout + x.stderr
        errs = [ln for ln in text.splitlines() if ln.startswith('Error')]
        key = '%s/%s' % (os.path.basename(os.path.dirname(p)), os.path.basename(p)[:-4])
        if 'Traceback' in text or (errs and not errs[0].startswith('Error %d,' % EXPECT.get(key, -1))):
            bad.append('%s: %s' % (p, text.strip().splitlines()[-1]))
        n += 1
    # vbasic.py import: a crunched V2 listing in, the same program out
    v2 = ('10 REM CRUNCHED, AS V2 SAVES IT\n20 FORI=1TO5:PRINTI;I*I:NEXTI\n30 A$="COMMODORE":B$=""\n'
          '40 FORI=LEN(A$)TO1STEP-1:B$=B$+MID$(A$,I,1):NEXT\n50 PRINTB$\n60 DATA 1,2,THREE:READX,Y,Z$\n'
          '70 PRINTX+Y;Z$:END\n')
    prg = os.path.join(out, 'V2.PRG')
    open(prg, 'wb').write(vbimport.crunch(v2))
    bas = os.path.join(out, 'v2.bas')
    i = run(['import', prg, '-o', bas])
    if i.returncode:
        bad.append('vbasic.py import: ' + i.stderr.strip())
    else:
        x = run(['run', bas, '--rom', rom])
        want = ' 1  1 \n 2  4 \n 3  9 \n 4  16 \n 5  25 \nERODOMMOC\n 3 THREE\n'
        if x.stdout != want:
            bad.append('vbasic.py import: the program runs as %r' % x.stdout)
    for b in bad:
        print('check_docs:', b)
    if bad:
        return 1
    print('ok    the docs: %d listings of %d chapters and the reference card, and %d examples, check and run'
          % (n - len(glob.glob(os.path.join(TOP, 'docs', 'vbasic', 'examples', '*.bas'))), len(chapters) - 1,
             len(glob.glob(os.path.join(TOP, 'docs', 'vbasic', 'examples', '*.bas')))))
    print('ok    vbasic.py import: a crunched V2 program (as a .PRG) comes back as a listing that runs')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
