#!/usr/bin/env python3
"""gate vb_ide: VeraBASIC's editor in a scripted session, and what it must
leave (tools/gate_vb_ide.sh).

usage: ide_script.py CARD [--stop NAME]

Writes into the card's folder the long-named program the session opens,
IDE.PLY (tests/edit_play.s plays it: keys into the ROM's queue, the
pointer) and expect.json: the states its 'L' records must log (the
editor's "IDE STATE n line col bytes lines modified err stop name"), the
files it must leave, the programs it runs (their console lines come from
tools/vbasic.py run, the reference). With --stop the session ends there
with a VRAM dump (a screenshot, a golden).

The session, as a user would: Ctrl+O, 'C', Return: "Counting the birds at
the feeder in 2026.bas" (a long name) through the Open dialog; the program
typed at its end with Return's indentation, a NEXT that does not match its
FOR planted; Check (Ctrl+K): the error's line red, the cursor there; the
error fixed (End, two Backspaces); Check: none; Run (Ctrl+R): its console,
a key back; a loop added, Run, Ctrl+C: stopped, its line marked; Save
(Ctrl+S); F1 on PRINT: the help page; Esc; a line typed carelessly, Format
(Ctrl+Shift+F): the canonical form; Save as "Birds formatted by VeraBASIC.bas" through
the dialog. MIT licence (LICENSE).
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ide_play import Play, F1, ESC, END, BS, RET, RIGHT, CTRL_HOME, CTRL_END, CTRL  # noqa: E402

NAME = 'Counting the birds at the feeder in 2026.bas'
NAME2 = 'Birds formatted by VeraBASIC.bas'
START = 'REM Bird count, the feeder by the kitchen window\n'

# the lines typed (Return's indentation makes the blanks: ide_play.line)
TYPED = ['OPTION INTEGER', 'DIM birds(3)', 'DATA 4, 7, 2', 'total = 0', 'FOR i = 1 TO 3',
         'READ birds(i)', 'total = total + birds(i)', 'PRINT "Feeder"; i; ":"; birds(i)',
         'NEXT j', 'PRINT "Total:"; total']
# as the editor makes them
SHOWN = ['OPTION INTEGER', 'DIM birds(3)', 'DATA 4, 7, 2', 'total = 0', 'FOR i = 1 TO 3',
         '  READ birds(i)', '  total = total + birds(i)', '  PRINT "Feeder"; i; ":"; birds(i)',
         'NEXT j', 'PRINT "Total:"; total']
ERR_LINE = 10                           # NEXT j (line 1 is START's)
LOOP = ['DO', 'n = n + 1', 'LOOP']
LOOP_SHOWN = ['DO', '  n = n + 1', 'LOOP']
MESSY = 'print   "the end"  ;total:n=0'


def main(argv):
    card = argv[0]
    stop = argv[argv.index('--stop') + 1] if '--stop' in argv else None
    open(os.path.join(card, NAME), 'w', encoding='latin-1', newline='\n').write(START)
    p = Play()
    states = {}

    def L(n, line, col, text, mod, err=0, stopl=0, name=NAME):
        p.L(n)
        states[n] = [line, col, None if text is None else len(text),
                     None if text is None else text.count('\n') + 1, mod, err, stopl, name]

    def S(name):
        if name == stop:
            p.W(30)
            p.stop()

    p.W(150)
    text = ''
    L(1, 1, 1, text, 0, name='')
    p.B(0)                      # the cursor's blink, fast and slowed (tests/check_blink.py)
    p.B(40)
    p.B(200)
    # Open: the dialog, 'C' (the only .bas), Return
    p.ctrl('o')
    p.W(30)
    S('open')
    p.K(ord('C'))
    p.W(10)
    p.K(RET)
    p.W(40)
    text = START
    L(2, 1, 1, text, 0)
    # the program typed at the end
    p.K(CTRL_END, CTRL)
    for t in TYPED[:-1]:
        p.line(t)
    p.T(TYPED[-1])
    shown = SHOWN[:]
    text = START + '\n'.join(shown)
    L(3, len(shown) + 1, len(shown[-1]) + 1, text, 1)
    S('colour')
    # (pictures only, no gate session: a menu open on its title, V149)
    for nm, x in (('menufile', 117), ('menuedit', 150), ('menusearch', 190), ('menurun', 230),
                  ('menuhelp', 262)):
        if stop == nm:
            p.click(x, 6)
            p.W(30)
            p.stop()
    # Check: the error's line, the cursor at its start
    p.ctrl('k')
    p.W(40)
    L(4, ERR_LINE, 1, text, 1, err=ERR_LINE)
    S('error')
    # the fix: End, two Backspaces (NEXT j: NEXT)
    p.K(END)
    p.K(BS)
    p.K(BS)
    shown[ERR_LINE - 2] = 'NEXT'
    text = START + '\n'.join(shown)
    p.ctrl('k')
    p.W(40)
    L(5, ERR_LINE, 5, text, 1)
    # Run: its console, then a key: back
    p.ctrl('r')
    p.W(80)
    S('console')
    p.K(ord(' '))
    p.W(60)
    L(6, ERR_LINE, 5, text, 1)
    run1 = text
    # a loop at the end; Run; Ctrl+C
    p.K(CTRL_END, CTRL)
    p.K(RET)
    for t in LOOP[:-1]:
        p.line(t)
    p.T(LOOP[-1])
    p.K(RET)                            # (LOOP goes back to the left)
    text = text + '\n' + '\n'.join(LOOP_SHOWN) + '\n'
    p.ctrl('r')
    p.W(80)
    p.ctrl('c')
    p.W(60)
    loop_at = text.count('\n', 0, text.index('  n = n + 1')) + 1
    states_stop = loop_at
    L(7, 0, 0, text, 1)                 # (stopped at DO, the line in it or LOOP: stop_lines)
    S('stopped')
    # Save
    p.ctrl('s')
    p.W(40)
    L(8, 0, 0, text, 0)
    saved = text
    # F1 on PRINT (line 9: "  PRINT ..."): Ctrl+L 9, two Rights
    p.ctrl('l')
    p.W(20)
    p.T('9\r')
    p.W(20)
    p.K(RIGHT)
    p.K(RIGHT)
    p.K(RIGHT)
    p.K(F1)
    p.W(40)
    S('help')
    p.K(ESC)
    p.W(30)
    # a careless line, Format, Save as
    p.K(CTRL_END, CTRL)
    p.T(MESSY)
    messy = text + MESSY
    p.ctrl('f', shift=True)
    p.W(60)
    S('format')
    L(9, 0, 0, None, 1)
    p.ctrl('s', shift=True)
    p.W(40)
    S('saveas')
    for _ in range(len(NAME)):
        p.K(BS)
    p.T(NAME2)
    p.W(10)
    p.K(RET)
    p.W(60)
    L(10, 0, 0, None, 0, name=NAME2)
    p.W(30)
    p.stop()
    open(os.path.join(card, 'IDE.PLY'), 'wb').write(p.data())
    exp = {'states': states, 'run1': run1, 'saved': {NAME: saved}, 'messy': messy, 'name2': NAME2,
           'stop_lines': [states_stop - 1, states_stop, states_stop + 1], 'err_line': ERR_LINE}
    json.dump(exp, open(os.path.join(card, 'expect.json'), 'w'), indent=1)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
