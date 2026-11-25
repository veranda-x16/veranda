#!/usr/bin/env python3
"""Gate prg (tools/gate_prg.sh, DECISIONS V197): X16 programs (.PRG) run
from the desktop through BASIC, Veranda kept, and the way back.

usage: prg_gate.py <run> <card folder>

Writes into <card folder> (the SD card's files; VERANDA's own are copied
by the gate) the test programs in /DOCUMENTS and the shell's script
SHELL.TST in the top folder (tests/shell_script.py's records; the shell
starts in /DOCUMENTS: DECISIONS V71, in the icons' view: no LIST.DEF).

The programs (in /DOCUMENTS):
  HELLO.PRG    BASIC: prints "PRG HELLO START", writes HELLO.TXT ("HELLO")
               in the current folder, prints "PRG HELLO END", END
  MLSTUB.PRG   machine code behind "10 SYS2061": prints "PRG MLSTUB RAN"
               with CHROUT, RTS (back to BASIC, its program ends)
  BANKS.PRG    machine code: every RAM bank BASIC may use (1 .. MEMTOP's
               count - 1), all 8 KB, filled with $AA and read back;
               prints "PRG BANKS n ERRORS e"
  OVER.PRG     the same over banks 1 .. 46 whatever MEMTOP says (on a
               512 KB X16 that is bank RB, 44, and the copy's first two):
               prints "PRG OVER 46", ENDs (run over only)
  HIGH.PRG     a file that loads at $1000 (not a program BASIC can RUN)
  GAMES/READER.PRG  BASIC: reads LEVEL.DAT (next to it: the current
               folder), prints "PRG READER GOT <its line>", writes
               READER.TXT there
  GAMES/LEVEL.DAT   "LEVEL ONE"
  GAMES/ERR.PRG     BASIC: prints "PRG ERR START", then PRINT 1/0: BASIC's
               ?DIVISION BY ZERO ERROR

Runs:
  ask    part 0: double-click HIGH.PRG: the warning, its OK; double-click
         HELLO.PRG: the question; Cancel: nothing happens (still part 0);
         double-click it again; the end with the question shown (a dump:
         the picture of the box)
  run    part 0: double-click HELLO.PRG, OK. part 1 (back in /DOCUMENTS):
         MLSTUB.PRG, OK. part 2: BANKS.PRG, OK. part 3: open GAMES,
         READER.PRG, OK. part 4 (back in /DOCUMENTS/GAMES): ERR.PRG, OK.
         part 5 (back there after the error): the end
  shot   part 0: SHOT.PRG (BASIC: prints its lines, then ends the
         emulator: a dump of BASIC's screen while the program runs)
  over   part 0: OVER.PRG, OK; what EXEC reads after it is the program's
         $AA (the gate reports what BASIC does)
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import shell_script as ss  # noqa: E402
import basic_gate as bg  # noqa: E402


def ml(code, start=0x080D):
    """a .PRG at $0801: "10 SYS2061" and the machine code after it"""
    stub = bytes([0x0B, 0x08, 0x0A, 0x00, 0x9E]) + b'2061' + bytes([0, 0, 0])
    assert 0x0801 + len(stub) == start
    return b'\x01\x08' + stub + bytes(code)


def text(s):
    """CHROUT each character of s (at the code's end, after an RTS)"""
    return s.encode('latin-1') + b'\x0d\x00'


def mlstub():
    # ldx #0; @l: lda msg,x; beq @d; jsr $FFD2; inx; bra @l; @d: rts; msg
    msg = 0x080D + 13
    code = [0xA2, 0x00, 0xBD, msg & 255, msg >> 8, 0xF0, 0x06, 0x20, 0xD2, 0xFF, 0xE8, 0x80, 0xF5, 0x60]
    msg = 0x080D + len(code)
    code[3], code[4] = msg & 255, msg >> 8
    return ml(code + list(text('PRG MLSTUB RAN')))


# BANKS.PRG and OVER.PRG: banks 1 .. n-1 filled with $AA and read back,
# n = MEMTOP's bank count (sec; jsr $FF99) or 47; then BASIC prints the
# result (a tiny BASIC tail: the machine code returns, line 20 runs)
def banks(over):
    a = []
    if over:
        a += [0xA9, 47]                     # lda #47
    else:
        a += [0x38, 0x20, 0x99, 0xFF]       # sec; jsr MEMTOP: a = banks
    a += [0x8D, 0x00, 0x04,                 # sta $0400 (n)
          0x9C, 0x01, 0x04,                 # stz $0401 (errors)
          0xA9, 0x01, 0x85, 0x00]           # lda #1; sta ram_bank
    # @b: fill $A000-$BFFF with $AA through ($02) (r0), then read it back
    b = len(a)
    a += [0xA9, 0x00, 0x85, 0x02, 0xA9, 0xA0, 0x85, 0x03,   # r0 = $A000
          0xA0, 0x00, 0xA9, 0xAA,                           # ldy #0; lda #$AA
          0x91, 0x02, 0xC8, 0xD0, 0xFB,                     # @f: sta (r0),y; iny; bne @f
          0xE6, 0x03, 0xA6, 0x03, 0xE0, 0xC0, 0xD0, 0xF3,   # inc r0+1; ldx r0+1; cpx #$C0; bne @f
          0xA9, 0xA0, 0x85, 0x03,                           # r0 = $A000 again
          0xB1, 0x02, 0xC9, 0xAA, 0xF0, 0x03,               # @r: lda (r0),y; cmp #$AA; beq @ok
          0xEE, 0x01, 0x04,                                 # inc $0401
          0xC8, 0xD0, 0xF4,                                 # @ok: iny; bne @r
          0xE6, 0x03, 0xA6, 0x03, 0xE0, 0xC0, 0xD0, 0xEC,   # inc r0+1; cpx #$C0; bne @r
          0xE6, 0x00, 0xA5, 0x00, 0xCD, 0x00, 0x04]         # inc ram_bank; lda ram_bank; cmp $0400
    a += [0xD0, (b - (len(a) + 2)) & 255]   # bne @b
    a += [0xA9, 0x01, 0x85, 0x00, 0x60]     # lda #1; sta ram_bank (BASIC's); rts
    # the BASIC: 10 SYS<code>: 20 PRINT ...: the code after the program
    name = 'OVER' if over else 'BANKS'
    lines = ['10 SYS %d' % 9999, '20 PRINT "PRG %s";PEEK(1024)-1;"ERRORS";PEEK(1025)' % name]
    body = bg.prg(lines)
    code_at = 0x0801 + len(body) - 2
    lines[0] = '10 SYS %d' % code_at
    body = bg.prg(lines)
    assert 0x0801 + len(body) - 2 == code_at
    return body + bytes(a)


PROGS = {
    'HELLO.PRG': bg.prg(['10 PRINT "PRG HELLO START"',
                         '20 OPEN 2,8,2,"HELLO.TXT,S,W":PRINT#2,"HELLO":CLOSE 2',
                         '30 PRINT "PRG HELLO END":END']),
    'MLSTUB.PRG': mlstub(),
    'BANKS.PRG': banks(False),
    'OVER.PRG': banks(True),
    'HIGH.PRG': b'\x00\x10' + bytes([0x60]) * 16,
    'SHOT.PRG': bg.prg(['10 PRINT "PRG SHOT: A PROGRAM FROM THE DESKTOP"',
                        '20 PRINT "VERANDA COMES BACK WHEN IT ENDS"',
                        '30 FOR I=1 TO 300:NEXT:POKE 40884,1:SYS 65535']),
}
GAMES = {
    'READER.PRG': bg.prg(['10 OPEN 2,8,2,"LEVEL.DAT,S,R":INPUT#2,A$:CLOSE 2',
                          '20 PRINT "PRG READER GOT ";A$',
                          '30 OPEN 2,8,2,"READER.TXT,S,W":PRINT#2,"READ":CLOSE 2']),
    'LEVEL.DAT': b'LEVEL ONE\r',
    'ERR.PRG': bg.prg(['10 PRINT "PRG ERR START":PRINT 1/0', '20 PRINT "PRG ERR NOT HERE"']),
}


def ok(p):
    p.click(ss.YES_X, ss.YES_Y)             # OK: DBI_X_0, DBI_Y_2 (as YES)


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    run, card = sys.argv[1:]
    docs = os.path.join(card, 'DOCUMENTS')
    os.makedirs(os.path.join(docs, 'GAMES'), exist_ok=True)
    for n, b in PROGS.items():
        open(os.path.join(docs, n), 'wb').write(b)
    for n, b in GAMES.items():
        open(os.path.join(docs, 'GAMES', n), 'wb').write(b)
    top = ['..'] + ss.listing(['GAMES'], list(PROGS))
    games = ['..'] + ss.listing([], list(GAMES))
    parts = []
    p = ss.Part()
    p.wait(30)
    if run == 'ask':
        p.dbl(*ss.cell(top.index('HIGH.PRG')))
        p.wait(30)
        ok(p)                                   # the warning's OK
        p.wait(30)
        p.dbl(*ss.cell(top.index('HELLO.PRG')))
        p.wait(40)
        p.click(ss.NO_X, ss.YES_Y)              # CANCEL: DBI_X_2, DBI_Y_2
        p.wait(40)
        p.dbl(*ss.cell(top.index('HELLO.PRG')))
        p.wait(60)
        p.end(ss.END_DONE)
        parts.append(p)
    elif run == 'run':
        for n in ('HELLO.PRG', 'MLSTUB.PRG', 'BANKS.PRG'):
            if n != 'HELLO.PRG':                # (HELLO.PRG wrote HELLO.TXT)
                top = ['..'] + ss.listing(['GAMES'], list(PROGS) + ['HELLO.TXT'])
            p.dbl(*ss.cell(top.index(n)))
            p.wait(40)
            ok(p)
            p.end(ss.END_STOP)
            parts.append(p)
            p = ss.Part()
            p.wait(30)
        p.dbl(*ss.cell(top.index('GAMES')))
        p.wait(40)
        p.dbl(*ss.cell(games.index('READER.PRG')))
        p.wait(40)
        ok(p)
        p.end(ss.END_STOP)
        parts.append(p)
        p = ss.Part()                           # (back in GAMES, READER.TXT there)
        p.wait(30)
        games = ['..'] + ss.listing([], list(GAMES) + ['READER.TXT'])
        p.dbl(*ss.cell(games.index('ERR.PRG')))
        p.wait(40)
        ok(p)
        p.end(ss.END_STOP)
        parts.append(p)
        p = ss.Part()
        p.wait(60)
        p.end(ss.END_DONE)
        parts.append(p)
    elif run in ('shot', 'over'):
        p.dbl(*ss.cell(top.index('SHOT.PRG' if run == 'shot' else 'OVER.PRG')))
        p.wait(40)
        ok(p)
        p.end(ss.END_STOP)
        parts.append(p)
        p = ss.Part()
        p.wait(30)
        p.end(ss.END_DONE)
        parts.append(p)
    else:
        sys.exit(__doc__)
    ss.write(os.path.join(card, 'SHELL.TST'), parts)


if __name__ == '__main__':
    main()
