#!/usr/bin/env python3
"""Gate ui, session 640: two VRAM dumps (-dump BV) of a 640x480 session have
the same foreground: what menus and dialog boxes covered came back.

usage: check_same.py [--differ] <before dump.bin> <after dump.bin> <what>
  --differ: they must differ (a box was open; V84)
"""
import sys

VDUMP = 132878                  # x16emu's VRAM section (see check_ui.py)
N = 80 * 480


def fg(path):
    d = open(path, 'rb').read()
    return d[len(d) - VDUMP:][:N]


def main():
    args = sys.argv[1:]
    differ = args[:1] == ['--differ']
    if differ:
        args = args[1:]
    if len(args) != 3:
        sys.exit(__doc__)
    a, b = fg(args[0]), fg(args[1])
    bad = [i for i in range(N) if a[i] != b[i]]
    if differ:
        print(('ok    ' if bad else 'FAIL  ') + args[2] + ' (%d bytes differ)' % len(bad))
        sys.exit(0 if bad else 1)
    where = '' if not bad else ' (%d bytes differ; first at row %d, card %d)' % (len(bad), bad[0] // 80, bad[0] % 80)
    print(('FAIL  ' if bad else 'ok    ') + args[2] + where)
    sys.exit(1 if bad else 0)


if __name__ == '__main__':
    main()
