#!/usr/bin/env python3
"""gate archive: SHELL.TST for the shell's part of the gate: a double click
on Test.d64 in the top folder; the shell starts Archive with it as its
document (Archive declares D64 D71 D81: DECISIONS V48).

usage: archive_shell.py <folder> [--name <image>] [<extra name>...]
       (--name: the image clicked, Test.d64 by default; DECISIONS V82)
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import shell_script as ss  # noqa: E402


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    d, extra, img = sys.argv[1], sys.argv[2:], 'Test.d64'
    if extra[:1] == ['--name']:
        img, extra = extra[1], extra[2:]
    names = os.listdir(d) + ['SHELL.TST', 'SHELL.STP'] + extra
    dirs = sorted({n for n in names if os.path.isdir(os.path.join(d, n))})
    files = sorted(set(names) - set(dirs))
    root = ss.listing(dirs, files)
    p = ss.Part()
    p.wait(20)
    p.dbl(*ss.cell(root.index(img)))
    p.end(ss.END_STOP)
    ss.write(os.path.join(d, 'SHELL.TST'), [p])


if __name__ == '__main__':
    main()
