#!/usr/bin/env python3
"""Gate sound (tools/gate_sound.sh, DECISIONS V69): the shell's runs.

usage: sound_shell.py keep|resume <folder> [<extra name>...]
       sound_shell.py prefs <folder> <Veranda Prefs.cvt> <kSndAtt address>

Writes <folder>/SHELL.TST (tests/shell_script.py's records) and the BASIC
programs the shell's BASIC items run (^Gn, n the part: tests/basic_gate.py).

keep    the settings as at power-on (no Veranda Prefs: the menu ticks off).
        part 0: double-click AppOne (it returns to the shell); part 1:
        disk > empty trash, YES; options > BASIC (keep Veranda). G1: the
        emulator ends with a dump.
resume  "Veranda Prefs.cvt" with the menu ticks on (written here).
        part 0: geos > desk accessory, OPEN (SndDA: tests/audio/sndda.c);
        options > BASIC (keep Veranda). G0: SYS 35328 (back: the shell
        again); part 1: options > Quit Veranda. G1: the emulator ends with a
        dump.
prefs   (V72) the given "Veranda Prefs.cvt" (the user's card's, saved by
        V65's Preferences: tests/sound_prefs_v65.cvt); part 0: options >
        BASIC (keep Veranda). G1: prints "G PREFS" and the resident
        kSndAtt and kPrefs (PEEK), the emulator ends with a dump.
"""
import shutil
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import shell_script as ss  # noqa: E402
import basic_gate as bg  # noqa: E402

OPEN_ICON = (384, 207)          # the default dialog box's OPEN (DBI_X_2, DBI_Y_0)
# Shell 2's menus (shell/main.c, DECISIONS V70): disk > empty trash, geos >
# desk accessory, options > BASIC (keep Veranda), Quit Veranda
END = ['10 PRINT "G END"', '20 POKE 40884,1:SYS 65535']


def prefs_file(folder, flags):
    """the kernel reads the block from byte 508 (kernel/s/prefs.s SysLoad)"""
    block = bytes([0xFF, 0x0F, 0, 0, 88, 2, flags, 0xFF, 0, 0, 0, 0, 0, 0, 0, 0])
    open(os.path.join(folder, 'Veranda Prefs.cvt'), 'wb').write(bytes(508) + block)


def main():
    if len(sys.argv) < 3 or sys.argv[1] not in ('keep', 'resume', 'prefs'):
        sys.exit(__doc__)
    run, folder = sys.argv[1], sys.argv[2]
    progs = {'G1': END}
    if run == 'prefs':
        shutil.copyfile(sys.argv[3], os.path.join(folder, 'Veranda Prefs.cvt'))
        a = int(sys.argv[4], 0)
        progs['G0'] = ['10 PRINT "G PREFS";PEEK(%d);PEEK(%d)' % (a, a + 1)] + END
        del progs['G1']
        sys.argv[3:] = []
    if run == 'resume':
        progs['G0'] = ['10 PRINT "G0 SYS":SYS 35328', '20 PRINT "G0 STILL IN BASIC"']
        prefs_file(folder, 0x40)
    for name, lines in progs.items():
        open(os.path.join(folder, name), 'wb').write(bg.prg(lines))
    dirs = [n for n in os.listdir(folder) if os.path.isdir(os.path.join(folder, n))]
    files = [n for n in os.listdir(folder) if not os.path.isdir(os.path.join(folder, n))]
    files = sorted(set(files + ['SHELL.TST', 'SHELL.STP'] + sys.argv[3:]))
    root = ss.listing(dirs, files)
    parts = []
    p = ss.Part()
    p.wait(20)
    if run == 'keep':
        p.dbl(*ss.cell(root.index('AppOne.cvt')))
        p.end(ss.END_STOP)
        parts.append(p)
        p = ss.Part()
        p.wait(20)
        p.menu('disk', 'empty')
        p.wait(20)
        p.click(ss.YES_X, ss.YES_Y)
        p.wait(60)
        p.menu('options', 'basic')
        p.end(ss.END_STOP)
        parts.append(p)
    elif run == 'prefs':
        p.wait(60)                      # (the chime: 62 frames)
        p.menu('options', 'basic')
        p.end(ss.END_STOP)
        parts.append(p)
    else:
        p.menu('geos', 'desk accessory')
        p.wait(30)
        p.click(*OPEN_ICON)
        p.wait(60)
        p.menu('options', 'basic')
        p.end(ss.END_STOP)
        parts.append(p)
        p = ss.Part()
        p.wait(20)
        p.menu('options', 'quit')
        p.end(ss.END_STOP)
        parts.append(p)
    ss.write(os.path.join(folder, 'SHELL.TST'), parts)


if __name__ == '__main__':
    main()
