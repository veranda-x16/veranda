#!/usr/bin/env python3
"""gate desk: writes tests/calc_script.h, the session the Calculator's
test build plays (tests/calc_play.c), from the accessory's start; CASES
(the keys and what the display must then show) is read by
tests/check_calc.py.

usage: calc_script.py [out.h]      (default tests/calc_script.h)

The window (apps/calc/calc.c) at 640x480: 296 x 304 at (168, 88); a key
is 40 x 24, 48 and 32 apart, from (176, 168), 6 across and 7 down (=
two rows tall at the right); the close box at the title band's right
(the SDK's vr_win, V148): 446-456, 91-101. Each case is typed (the
keyboard queue) or clicked; it ends with a "CALC = <display>" line on
the console (at = or at an error). "/* shot NAME FRAME */" lines name
frames for screenshots (CALC_STOP): calc (a trigonometric sum, light;
also built dark and at 320x240), press (= pressed), error.
"""
import os
import sys

X0, Y0 = 168, 88
KEYS = [['2nd', 'DRG', 'MC', 'MR', 'M+', 'M-'],
        ['sin', 'cos', 'tan', 'C', 'BS', '/'],
        ['ln', 'log', '(', ')', '%', '*'],
        ['x2', 'rt', '7', '8', '9', '-'],
        ['^', 'inv', '4', '5', '6', '+'],
        ['!', 'pi', '1', '2', '3', '='],
        ['EE', 'Ans', 'neg', '0', '.', '=']]

# (how, keys, expected): how 't' typed (a string of characters: \r Return,
# \b Backspace), 'k' clicked (a list of the keys' names above). Expected:
# a number (the display within one unit of its 9th significant digit) or
# a string the display must equal. The mode carries from case to case
# (degrees at the start); each typed case starts with c (clear).
SHOWCASE = ('t', '7m30s+2*3^2\r', 18.5)
CASES = [
    SHOWCASE,
    ('k', ['C', '1', '2', '+', '3', '0', '='], '42'),
    ('t', '*2\r', '84'),                        # (gate desk's check: 42 then 84)
    # the arithmetic and the precedence
    ('t', 'c0.1+0.2\r', '0.3'),
    ('t', 'c1/3*3\r', '1'),
    ('t', 'c2^10\r', '1024'),
    ('t', 'c2+3*4\r', '14'),
    ('t', 'c2*3+4\r', '10'),
    ('t', 'c10-2-3\r', '5'),
    ('t', 'c100/10/5\r', '2'),
    ('t', 'c2^3^2\r', '512'),
    ('t', 'c(2+3)*4\r', '20'),
    ('t', 'c2*(3+4)*5\r', '70'),
    ('t', 'c((1+2)*(3+4))^2\r', '441'),
    ('t', 'c2(3+4\r', '14'),                    # (2 x (3 + 4: = closes the bracket)
    ('t', 'c1+2*(3-(4-5)*2)/4^2\r', 1 + 2 * (3 - (4 - 5) * 2) / 4 ** 2),
    ('t', 'c5n+3\r', '-2'),
    ('t', 'c6x7\r', '42'),
    ('t', 'c2+*3\r', '6'),                      # (the second operator instead of the first)
    ('t', 'c123\b\r', '12'),
    ('t', 'c5+39\b\r', '8'),
    ('t', 'c7\b\b4\r', '4'),
    ('t', 'c3*4\r', '12'),
    ('t', 'a+1\r', '13'),                       # Ans
    ('t', 'c-5*2\r', '-10'),                    # (- first: 0 - 5 x 2)
    # number forms
    ('t', 'c1e20\r', '1E+20'),
    ('t', 'c1e20*1e5\r', '1E+25'),
    ('t', 'c2e7n\r', '2E-07'),
    ('t', 'c1.5e7n\r', '1.5E-07'),
    ('t', 'c123456789*1000\r', '1.23456789E+11'),
    ('t', 'c0.00001\r', '0.00001'),
    ('t', 'c1/7\r', 1 / 7),
    ('t', 'c2/3\r', 2 / 3),
    ('t', 'c1e10n\r', '1E-10'),
    ('t', 'c9999999999\r', '999999999'),       # (9 digits at most)
    ('t', 'c33!\r', 8683317618811886495518194401280000000),
    ('t', 'c10!\r', '3628800'),
    ('t', 'c0!\r', '1'),
    # functions
    ('t', 'c2r\r', 2 ** 0.5),
    ('t', 'c16r\r', '4'),
    ('t', 'c5q\r', '25'),
    ('t', 'c4i\r', '0.25'),
    ('t', 'c2^0.5\r', 2 ** 0.5),
    ('t', 'c7^2\r', '49'),
    ('t', 'c2^1n\r', '0.5'),
    ('t', 'c2n^3\r', '-8'),
    ('t', 'c1Ll\r', '1'),                       # ln(e) = 1
    ('t', 'c1L\r', 2.718281828459045),
    ('t', 'c2l\r', 0.6931471805599453),
    ('t', 'c100g\r', '2'),
    ('t', 'c1000g\r', '3'),
    ('t', 'c2g\r', 0.3010299956639812),
    ('t', 'c3G\r', '1000'),
    ('t', 'c0.5G\r', 10 ** 0.5),
    ('t', 'cp\r', 3.141592653589793),
    ('t', 'c200+10%\r', '220'),
    ('t', 'c200*10%\r', '20'),
    ('t', 'c50%\r', '0.5'),
    # degrees
    ('t', 'c30s\r', '0.5'),
    ('t', 'c60o\r', '0.5'),
    ('t', 'c45t\r', '1'),
    ('t', 'c180s\r', '0'),
    ('t', 'c90o\r', '0'),
    ('t', 'c90ns\r', '-1'),
    ('t', 'c0.5S\r', '30'),
    ('t', 'c0.5O\r', '60'),
    ('t', 'c1T\r', '45'),
    ('t', 'c1nS\r', '-90'),
    ('t', 'c20s\r', 0.3420201433256687),
    # radians
    ('t', 'cd(p/2)s\r', '1'),
    ('t', 'cpo\r', '-1'),
    ('t', 'cps\r', '0'),
    ('t', 'c1T\r', 0.7853981633974483),
    ('t', 'c1s\r', 0.8414709848078965),
    ('t', 'c0.5S\r', 0.5235987755982989),
    ('t', 'cd\r', '0'),                         # (back to degrees)
    # the memory
    ('t', 'cKm5m3mk\r', '8'),
    ('t', 'c2Mk\r', '6'),
    ('t', 'cKk\r', '0'),
    # errors
    ('t', 'c1/0\r', 'Error'),
    ('t', 'c1nr', 'Error'),
    ('t', 'c0l', 'Error'),
    ('t', 'c0g', 'Error'),
    ('t', 'c1n^0.5\r', 'Error'),
    ('t', 'c1e30*1e30\r', 'Error'),
    ('t', 'c34!', 'Error'),
    ('t', 'c2.5!', 'Error'),
    ('t', 'c2S', 'Error'),
    ('t', 'c90t', 'Error'),
    ('t', 'c0i', 'Error'),
    ('t', 'c' + '1^' * 26, 'Error'),            # (the 26th pending operator: past the stack)
    ('t', '3\r', '3'),                          # (a key after an error starts afresh)
    # every key clicked
    ('k', ['C', '(', '7', '-', '4', ')', '*', '9', '/', '3', '='], '9'),
    ('k', ['C', '5', 'x2', 'rt', '='], '5'),
    ('k', ['C', '2', '^', '8', '='], '256'),
    ('k', ['C', '4', 'inv', '='], '0.25'),
    ('k', ['C', '6', '!', '='], '720'),
    ('k', ['C', 'pi', '='], 3.141592653589793),
    ('k', ['C', '1', 'EE', '3', 'neg', '='], '0.001'),
    ('k', ['Ans', '+', '.', '5', '='], '0.501'),
    ('k', ['C', '8', '9', 'BS', '='], '8'),
    ('k', ['C', '5', '0', '%', '='], '0.5'),
    ('k', ['C', '0', 'cos', '+', '0', 'sin', '+', '4', '5', 'tan', '='], '2'),
    ('k', ['C', '1', 'ln', '+', '1', '0', '0', 'log', '='], '2'),
    ('k', ['C', '0', '.', '5', '2nd', 'sin', '='], '30'),
    ('k', ['C', '0', '.', '5', '2nd', 'cos', '='], '60'),
    ('k', ['C', '1', '2nd', 'tan', '='], '45'),
    ('k', ['C', '1', '2nd', 'ln', '='], 2.718281828459045),
    ('k', ['C', '2', '2nd', 'log', '='], '100'),
    ('k', ['C', '2nd', '2nd', '3', '0', 'sin', '='], '0.5'),     # (2nd twice: off)
    ('k', ['C', 'MC', '3', 'M+', '4', 'M+', 'MR', '='], '7'),
    ('k', ['C', '2', 'M-', 'MR', '='], '5'),
    ('k', ['MC', 'MR', '='], '0'),
    ('k', ['DRG', 'C', 'pi', 'cos', '=', 'DRG'], '-1'),
    ('k', ['C', '1', '+', '2', '='], '3'),
]
PRESS_CASE = ('t', 'c1/0', None)                 # then = clicked: Error (the press and error shots)


def key_at(name):
    for r, row in enumerate(KEYS):
        if name in row:
            c = row.index(name)
            return X0 + 8 + c * 48 + 20, Y0 + 80 + r * 32 + 12
    raise KeyError(name)


L = []
shots = []


def P(f, x, y, b, c=None):
    L.append('P(%d, %d, %d, %d),%s' % (f, x, y, b, '  /* %s */' % c if c else ''))


def K(f, ch, c=None):
    code = {'\r': '13', '\b': '8'}.get(ch, "'%s'" % ch)
    L.append('K(%d, %s),%s' % (f, code, '  /* %s */' % c if c else ''))


def click(f, x, y, c=None):
    P(f, x, y, 0, c)
    P(f + 1, x, y, 1)
    P(f + 3, x, y, 0)
    return f + 12


def play(f, case):
    how, keys, want = case
    note = 'case: %s -> %s' % (keys if how == 't' else ' '.join(keys), want)
    note = note.replace('*/', '* /').replace('\r', '=').replace('\b', '<BS>')
    if how == 't':
        for i, k in enumerate(keys):
            K(f, k, note if i == 0 else None)
            f += 6
    else:
        for i, k in enumerate(keys):
            f = click(f, *key_at(k), c=note if i == 0 else None)
    return f + 6


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), 'calc_script.h')
    f = 30
    f = play(f, CASES[0])
    shots.append(('calc', f + 20))
    f += 40
    for case in CASES[1:]:
        f = play(f, case)
    f = play(f, PRESS_CASE)
    x, y = key_at('=')
    f = click(f, x, y, c='= clicked: Error, the key shown pressed')
    shots.append(('press', f - 12 + 6))     # (the press at + 1, shown 6 frames)
    shots.append(('error', f + 20))
    f = click(f + 30, X0 + 296 - 12, Y0 + 8, c='the close box: RstrAppl')
    L.append('END(60000)')
    with open(out, 'w') as o:
        o.write('/* gate desk: the Calculator\'s session, written by tests/calc_script.py */\n')
        for name, fr in shots:
            o.write('/* shot %s %d */\n' % (name, fr))
        o.write('\n'.join(L) + '\n')


if __name__ == '__main__':
    main()
