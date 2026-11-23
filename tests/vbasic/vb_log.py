#!/usr/bin/env python3
"""Run's log lines from an emulator's console (gate vb_files): the lines
that start with "VB". x16emu's -echo shows every character the KERNAL
writes, the DOS commands to the command channel too ("S:name", "MD:dir",
with no line end), so a log line may follow one on the same line: it is
cut off there.

usage: vb_log.py console.txt > x16.log            MIT licence (LICENSE)."""
import re
import sys

LOG = re.compile(r'VB(\| |> |= | EVENT | CD | RUN | END| ERROR| DONE| BANKS| GC| INPUT| LOAD| TEST| ASIDE| CTRL)')


def main(argv):
    out = []
    for ln in open(argv[0], encoding='latin-1'):
        ln = ln.rstrip('\n')
        if ln.startswith('VB'):
            out.append(ln)
            continue
        m = LOG.search(ln)
        if m:
            out.append(ln[m.start():])
    sys.stdout.buffer.write(''.join(x + '\n' for x in out).encode('latin-1'))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
