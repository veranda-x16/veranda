#!/usr/bin/env python3
"""Gate basic (tools/gate_basic.sh, DECISIONS V64): the files of a run.

usage: basic_gate.py <run> <folder> [<extra name>...]

Writes into <folder> the shell's script SHELL.TST (tests/shell_script.py's
records) and the BASIC programs G0, G1, ... of run <run> (tokenized here;
plain .PRG files without an extension, as BASIC's ^G0 loads them). The
shell, while a script plays, quits to BASIC with "?6*7" and "^Gn" typed
(n: the part being played), so BASIC answers 42 and then runs Gn.

Runs:
  mem    part 0: open the folder Docs; geos > BASIC (keep Veranda). G0:
         MEMTOP (banks and address), FRE, an integer array filling the
         memory up to MEMTOP, written and checked; the first and last
         byte of every RAM bank BASIC may use (1 .. MEMTOP's count - 1),
         written and checked; RUN STOP/RESTORE's warm start (the ROM's
         NMI routine) with SYS 35328 in the keyboard queue.
         part 1 (back, in Docs): double-click AppOne there; part 2 (the
         shell again, in Docs): the end, a dump of the banked RAM
  core   part 0: BASIC (keep). G0: the resident core overwritten but
         ReEntry ($8A00-$8A5F), SYS 35328: back from the
         copy. part 1: BASIC (keep). G1: VERANDA.SYS and VERANDA.PRG
         renamed away (nothing on the card to load), all of $8800-$9EFF
         overwritten (ReEntry too), LOAD"RBOOT": RBOOT puts it back from
         the copy in RAM. part 2: the end, a dump
  card   part 0: BASIC (keep). G0: the copy in bank RB damaged (a byte of
         RCore); SYS 35328 refuses (its message); LOAD"RBOOT": no intact
         copy, VERANDA.PRG from the card, a fresh start. part 1: geos >
         Quit Veranda. G1: MEMTOP as at power-on, SYS 35328 refuses (the
         descriptor made invalid); the emulator ends
  tkeep  (DECISIONS V67: the text screen, the hard case) "Veranda
         Prefs.cvt" with dark paper and light ink and a blank after 2 s;
         part 0: idle until the screen blanks, a move wakes it, BASIC
         (keep). G0: a line, the emulator ends (a dump of the text screen)
  tquit  the same with geos > Quit Veranda
  blank  the same settings; part 0: idle, the emulator ends while the
         screen is blanked (the dump shows the blank happened)
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import shell_script as ss  # noqa: E402

# CBM BASIC V2's keywords, tokens $80-$CB, in the order the ROM's crunch
# tries them (x16-rom basic/tokens.s, token2.s)
KEYWORDS = ('END FOR NEXT DATA INPUT# INPUT DIM READ LET GOTO RUN IF RESTORE GOSUB RETURN REM STOP ON '
            'WAIT LOAD SAVE VERIFY DEF POKE PRINT# PRINT CONT LIST CLR CMD SYS OPEN CLOSE GET NEW TAB( '
            'TO FN SPC( THEN NOT STEP + - * / ^ AND OR > = < SGN INT ABS USR FRE POS SQR RND LOG EXP '
            'COS SIN TAN ATN PEEK LEN STR$ VAL ASC CHR$ LEFT$ RIGHT$ MID$ GO').split()
EXTRA = {'BANK': b'\xce\x98'}       # X16: escape $CE, statement 24 (token2.s reslst2)


def crunch(text):
    out, i, quote = bytearray(), 0, False
    while i < len(text):
        c = text[i]
        if c == '"':
            quote = not quote
        if not quote:
            hit = None
            for k, v in EXTRA.items():
                if text.startswith(k, i):
                    hit = (k, v)
                    break
            if not hit:
                for n, k in enumerate(KEYWORDS):
                    if text.startswith(k, i):
                        hit = (k, bytes([0x80 + n]))
                        break
            if hit:
                out += hit[1]
                i += len(hit[0])
                if hit[0] == 'REM':
                    out += text[i:].encode('latin-1')
                    break
                continue
            if c == ' ':
                i += 1
                continue
        out.append(ord(c))
        i += 1
    return bytes(out)


def prg(lines):
    """numbered lines "10 PRINT ..." -> a .PRG at $0801"""
    data, addr = bytearray(b'\x01\x08'), 0x0801
    for ln in lines:
        num, text = ln.split(' ', 1)
        body = crunch(text)
        nxt = addr + 4 + len(body) + 1
        data += nxt.to_bytes(2, 'little') + int(num).to_bytes(2, 'little') + body + b'\x00'
        addr = nxt
    return bytes(data + b'\x00\x00')


def memtop():
    # MEMTOP with c set: a banks, x/y the address ($030C-$030E after SYS)
    return '20 I=0:K=0:E=0:POKE 783,1:SYS 65433:B=PEEK(780):T=PEEK(781)+256*PEEK(782)'


def keys(s, line):
    """lines putting s into the ROM's keyboard queue (kbdbuf_put, $FEC3)"""
    codes = ','.join(str(ord(c)) for c in s)
    return ['%d FOR K=1 TO %d:READ C:POKE 780,C:SYS 65219:NEXT' % (line, len(s)),
            '%d DATA %s' % (line + 1, codes)]


PROGS = {
    'mem': {
        'G0': ['10 PRINT "G0 START"', memtop(),
               '30 PRINT "MEMTOP";B;T',
               '40 F=FRE(0):PRINT "FREE";F',
               '50 N=INT(F/2)-80:DIM A%(N)',
               '60 FOR I=0 TO N:A%(I)=I:NEXT',
               '70 FOR I=0 TO N:IF A%(I)<>I THEN E=E+1',
               '80 NEXT:PRINT "ARRAY";N;"ERRORS";E;"FREE";FRE(0)',
               '90 E=0:FOR K=1 TO B-1:BANK K:POKE 40960,K:POKE 49151,255-K:NEXT',
               '100 FOR K=1 TO B-1:BANK K:IF PEEK(40960)<>K OR PEEK(49151)<>255-K THEN E=E+1',
               '110 NEXT:BANK 1:PRINT "BANKS";B-1;"ERRORS";E'] +
              keys('SYS35328\r', 120) +
              ['130 PRINT "G0 RESTORE":BANK 1,0:SYS PEEK(792)+256*PEEK(793)'],
    },
    'core': {
        'G0': ['10 PRINT "G0 START"',
               '20 FOR A=34816 TO 35327:POKE A,0:NEXT:FOR A=35424 TO 40703:POKE A,0:NEXT',
               '30 PRINT "G0 SYS":SYS 35328',
               '40 PRINT "G0 STILL IN BASIC"'],
        'G1': ['10 PRINT "G1 START"',
               '20 OPEN 15,8,15,"R:VSYS.OFF=VERANDA.SYS":CLOSE 15',
               '30 OPEN 15,8,15,"R:VPRG.OFF=VERANDA.PRG":CLOSE 15',
               '40 FOR A=34816 TO 40703:POKE A,234:NEXT',
               '50 PRINT "G1 RBOOT":LOAD "RBOOT",8'],
    },
    'card': {
        'G0': ['10 PRINT "G0 START"', memtop(),
               '30 BANK B:POKE 41024,255-PEEK(41024):BANK 1',
               '40 PRINT "G0 SYS":SYS 35328',
               '50 PRINT "G0 REFUSED":LOAD "RBOOT",8'],
        'G1': ['10 PRINT "G1 START"', memtop(),
               '30 PRINT "MEMTOP";B;T',
               '40 SYS 35328',
               '50 PRINT "G1 REFUSED":POKE 40884,1:SYS 65535'],
    },
}
TEXT = ['10 PRINT "G0 TEXT"', '20 POKE 40884,1:SYS 65535']
for r in ('tkeep', 'tquit', 'blank'):
    PROGS[r] = {'G0': TEXT}

# the settings block (kernel/s/prefs.s): paper $0RGB, ink, blankDelay (s),
# the flags, the video mode ($FF: none), the rest the control panel's
PAPER, INK, BLANK = 0x0113, 0x0FE8, 2
PREFS = (bytes(508) + PAPER.to_bytes(2, 'little') + INK.to_bytes(2, 'little') +
         BLANK.to_bytes(2, 'little') + bytes([0, 0xFF]) + bytes(8))


def script(run, folder, extra):
    dirs = [n for n in os.listdir(folder) if os.path.isdir(os.path.join(folder, n))]
    files = [n for n in os.listdir(folder) if not os.path.isdir(os.path.join(folder, n))]
    files = sorted(set(files + ['SHELL.TST', 'SHELL.STP'] + extra))
    root = ss.listing(dirs, files)
    parts = []
    basic = lambda p: p.menu('options', 'basic')   # noqa: E731
    quit_ = lambda p: p.menu('options', 'quit')    # noqa: E731
    p = ss.Part()
    if run == 'mem':
        p.dbl(*ss.cell(root.index('Docs')))
        p.wait(30)
    p.wait(20)
    if run in ('tkeep', 'tquit', 'blank'):
        p.wait(60 * (BLANK + 3))                 # idle: the screen blanks
        if run == 'blank':
            p.end(ss.END_DONE)
            ss.write(os.path.join(folder, 'SHELL.TST'), [p])
            return
        p.at(300, 300, 0, 30)                    # a move wakes it
        (basic if run == 'tkeep' else quit_)(p)
        p.end(ss.END_STOP)
        ss.write(os.path.join(folder, 'SHELL.TST'), [p])
        return
    basic(p)
    p.end(ss.END_STOP)
    parts.append(p)
    p = ss.Part()
    p.wait(20)
    if run == 'mem':
        p.dbl(*ss.cell(1))                       # AppOne, after ".." in Docs
        p.end(ss.END_STOP)
        parts.append(p)
        p = ss.Part()
        p.wait(20)
        p.end(ss.END_DONE)
    elif run == 'core':
        basic(p)
        p.end(ss.END_STOP)
        parts.append(p)
        p = ss.Part()
        p.wait(20)
        p.end(ss.END_DONE)
    else:
        quit_(p)
        p.end(ss.END_STOP)
    parts.append(p)
    ss.write(os.path.join(folder, 'SHELL.TST'), parts)


def main():
    if len(sys.argv) < 3 or sys.argv[1] not in PROGS:
        sys.exit(__doc__)
    run, folder = sys.argv[1], sys.argv[2]
    for name, lines in PROGS[run].items():
        open(os.path.join(folder, name), 'wb').write(prg(lines))
    names = list(PROGS[run])
    if run in ('tkeep', 'tquit', 'blank'):
        open(os.path.join(folder, 'Veranda Prefs.cvt'), 'wb').write(PREFS)
        names.append('Veranda Prefs.cvt')
    script(run, folder, sys.argv[3:] + names)


if __name__ == '__main__':
    main()
