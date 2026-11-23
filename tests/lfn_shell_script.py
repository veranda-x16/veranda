#!/usr/bin/env python3
"""Gate lfn (DECISIONS V82): the shell starts programs and opens documents
by their long names. Writes <folder>/SHELL.TST (tests/shell_script.py's
records) for a run whose root holds:

  Application Seven.cvt   AppTwo (17 characters: GEOS's 16 would miss it)
  AppOne.cvt              opens .txt (-D LFN: logs dataFileName,
                          dataLongName and the document's first line,
                          read by FOpen(dataFileName), as a GEOS program)
  Holiday photos from the lake 2026.txt
  Docs/Notes from a longer trip to the lake in 2026.txt

usage: lfn_shell_script.py <folder> [<extra name>...]
       lfn_shell_script.py --want <folder>   the console lines expected

The parts:
  0  double-click Application Seven.cvt
  1  double-click Holiday photos from the lake 2026.txt: AppOne, in the
     window's folder, opens it
  2  open Docs, double-click the long document there: AppOne from the top
     folder (open with: the applications looked for elsewhere)
  3  (the shell in Docs) up; the desk accessory "Desk accessory with a
     long name.cvt" (32 characters) double-clicked: it logs and returns
     (RstrAppl) to the shell; Application Seven selected, options > pin,
     the pin double-clicked
  4  the end (SHELL DONE, a VRAM dump)
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import shell_script as S  # noqa: E402
from check_lfn import short  # noqa: E402

APP = 'Application Seven.cvt'
DA = 'Desk accessory with a long name.cvt'
DOC1 = 'Holiday photos from the lake 2026.txt'
DOC2 = 'Notes from a longer trip to the lake in 2026.txt'
TEXT1 = 'A week of photos by the lake.'
TEXT2 = 'Notes kept on the way.'


def want():
    out = ['SHELL STARTED', 'APP 2 RAN', 'SHELL STARTED', 'APP 1 RAN']
    out += ['APP 1 DOC %s IN /' % short(DOC1), 'APP 1 LONG ' + DOC1, 'APP 1 READ ' + TEXT1]
    out += ['SHELL STARTED', 'APP 1 RAN', 'APP 1 DOC %s IN /Docs' % short(DOC2), 'APP 1 LONG ' + DOC2,
            'APP 1 READ ' + TEXT2]
    out += ['SHELL STARTED', 'DA RAN', 'SHELL PINNED ' + APP, 'APP 2 RAN', 'SHELL STARTED', 'SHELL DONE']
    return out


def main():
    if sys.argv[1] == '--want':
        print('\n'.join(want()))
        return
    d = sys.argv[1]
    dirs = [n for n in os.listdir(d) if os.path.isdir(os.path.join(d, n))]
    files = sorted(set([n for n in os.listdir(d) if not os.path.isdir(os.path.join(d, n))]
                       + ['SHELL.TST', 'SHELL.STP'] + sys.argv[2:]))
    root = S.listing(dirs, files)
    parts = []
    p = S.Part()
    p.wait(20)
    p.dbl(*S.cell(root.index(APP)))
    p.end(S.END_STOP)
    parts.append(p)
    p = S.Part()
    p.wait(20)
    p.dbl(*S.cell(root.index(DOC1)))
    p.end(S.END_STOP)
    parts.append(p)
    p = S.Part()
    p.wait(20)
    p.dbl(*S.cell(root.index('Docs')))
    p.wait(30)
    p.dbl(*S.cell(1))                           # (after "..")
    p.end(S.END_STOP)
    parts.append(p)
    p = S.Part()
    p.wait(20)
    p.dbl(*S.cell(0))                           # ".." in Docs
    p.wait(30)
    p.dbl(*S.cell(root.index(DA)))              # over the shell, which stays
    p.wait(40)
    p.click(*S.cell(root.index(APP)))
    p.menu('options', 'pin')
    p.wait(40)
    p.dbl(*S.desk_pin(0))
    p.end(S.END_STOP)
    parts.append(p)
    p = S.Part()
    p.wait(30)
    p.end(S.END_DONE)
    parts.append(p)
    S.write(os.path.join(d, 'SHELL.TST'), parts)


if __name__ == '__main__':
    main()
