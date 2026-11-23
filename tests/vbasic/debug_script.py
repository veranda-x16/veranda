#!/usr/bin/env python3
"""gate vb_debug: VeraBASIC's debugger (DECISIONS V97) in scripted sessions
(tools/gate_vb_debug.sh); tests/vbasic/check_debug.py checks what they
logged.

usage: debug_script.py SESSION CARD [--stop NAME]

Writes the session's program (tests/vbasic/debug/*.bas) into the card's
folder and IDE.PLY (tests/edit_play.s plays it). The sessions:

  debug     debug.bas: breakpoints (F9) in a SUB and in a FUNCTION; Run;
            the break: the call stack, the variables (locals first), three
            watches (Ctrl+W); Step (F7); a local changed (Tab, Down,
            Return, a value); an array's elements (Return) and a 2-D
            array's; Step out (F11); the FUNCTION's breakpoint four deep;
            its breakpoint off (F9), Step over (F10); STOP; Continue (F6)
            to the end. --stop brk: at the break after the change (the
            variables window); --stop stack: four calls deep
  screen_a  screen.bas run as it is: its screen (the dump) at the end
  screen_b  screen.bas with a breakpoint, a watch, two steps over, a
            variable changed through a dialog box, Continue: its screen at
            the end must be screen_a's; its timer goes on after the break
  trace     trace.bas (TRON): run to its end, then the trace pane (F12)
  error     error.bas: the error's message in the pane (the statement)
  kerror    kerror.bas: a kernel's error (its code)

MIT licence (LICENSE)."""
import os
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from ide_play import Play, TAB, RET, DOWN, ESC, F6, F7, CTRL  # noqa: E402

F9, F10, F11, F12 = 0x10, 0x15, 0x16, 0x17     # (the ROM's codes: kernel/x/input.s)


def opened(p, first):
    """Ctrl+O, the program's first letter, Return: the only .bas there"""
    p.W(150)
    p.ctrl('o')
    p.W(30)
    p.K(ord(first))
    p.W(10)
    p.K(RET)
    p.W(40)


def goto(p, line):
    p.ctrl('l')
    p.W(20)
    p.T('%d\r' % line)
    p.W(20)


def bp(p, line):
    goto(p, line)
    p.K(F9)
    p.W(20)


def back(p):
    """a console program's end: its output stays until a key or a click
    (a key typed while it still ran is not one: the click is the sure way
    back; on the editor's status bar it does nothing)"""
    p.W(200)
    p.click(320, 474)
    p.W(80)


def watch(p, text):
    p.ctrl('w')
    p.W(20)
    p.T(text + '\r')
    p.W(80)


def main(argv):
    sess, card = argv[0], argv[1]
    stop = argv[argv.index('--stop') + 1] if '--stop' in argv else None
    p = Play()

    def S(name):
        if name == stop:
            p.W(40)
            p.stop()

    prog = {'debug': 'debug', 'screen_a': 'screen', 'screen_b': 'screen', 'trace': 'trace',
            'error': 'error', 'kerror': 'kerror'}[sess]
    shutil.copy(os.path.join(HERE, 'debug', prog + '.bas'), os.path.join(card, prog + '.bas'))
    opened(p, prog[0].upper())
    if sess == 'debug':
        bp(p, 15)                       # k = n * 2 (SUB Twice)
        bp(p, 19)                       # IF n <= 1 ... (FUNCTION Fact)
        p.ctrl('r')
        p.W(200)
        watch(p, 'total * 2')
        watch(p, 'squares(3) + 1')
        watch(p, 'LEFT$(name$, 4) + "!"')
        p.K(F7)                         # Step: line 16
        p.W(150)
        p.K(TAB)
        p.W(10)
        p.K(DOWN)                       # k
        p.W(10)
        p.K(RET)
        p.W(30)
        p.T('99\r')
        p.W(150)
        S('brk')
        p.K(DOWN)                       # squares(): its elements
        p.W(10)
        p.K(RET)
        p.W(150)
        p.K(ESC)
        p.W(150)
        p.K(DOWN)                       # grid(): 2-D
        p.W(10)
        p.K(RET)
        p.W(150)
        p.K(ESC)
        p.W(150)
        p.K(ESC)                        # the keys back to the text
        p.W(20)
        p.K(F11)                        # Step out: main, line 23
        p.W(150)
        for _ in range(4):              # Fact(4) .. Fact(1): its breakpoint
            p.K(F6)
            p.W(150)
        S('stack')
        p.K(F9)                         # (the cursor on line 19: off)
        p.W(20)
        p.K(F10)                        # Step over: out of the calls, line 24
        p.W(150)
        p.K(F6)                         # STOP
        p.W(150)
        p.K(F6)                         # to the end
        back(p)
    elif sess == 'screen_a':
        p.ctrl('r')
        p.W(400)
    elif sess == 'screen_b':
        bp(p, 40)                       # total = 0
        p.ctrl('r')
        p.W(200)
        S('sbrk')
        watch(p, 'ticks')
        p.K(F10)
        p.W(150)
        p.K(F10)
        p.W(150)
        p.K(TAB)                        # ticks (the second global after d$)
        p.W(10)
        for _ in range(3):
            p.K(DOWN)
            p.W(10)
        p.K(RET)
        p.W(30)
        p.T('1\r')
        p.W(150)
        p.K(F6)
        p.W(400)
    elif sess == 'trace':
        p.ctrl('r')
        back(p)
        p.K(F12)
        p.W(100)
        S('trace')
    elif sess in ('error', 'kerror'):
        p.ctrl('r')
        p.W(200)
        S(sess)
    p.W(30)
    p.stop()
    open(os.path.join(card, 'IDE.PLY'), 'wb').write(p.data())
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
