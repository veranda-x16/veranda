#!/usr/bin/env python3
"""gate vb_ide: the player's records (tests/edit_play.s reads them: IDE.PLY)
as a small library for tests/vbasic/ide_script.py.

Keys go into the ROM's key queue with the ROM's codes (the kernel turns
them into Veranda's: kernel/x/input.s IsoToGeos), the modifiers into the
ROM's shflag; the pointer is absolute. A record waits until the program is
idle (edit_idle) and both key queues are empty, then 6 idle frames.

MIT licence (LICENSE).
"""

# the ROM's key codes (ISO mode)
RET, BS, DEL, TAB, ESC = 0x0D, 0x14, 0x19, 0x09, 0x1B
UP, DOWN, RIGHT, LEFT = 0x91, 0x11, 0x1D, 0x9D
HOME, END, PGUP, PGDN = 0x13, 0x04, 0x82, 0x02
F1, F3, F5, F7, F2, F4, F6, F8 = 0x85, 0x86, 0x87, 0x88, 0x89, 0x8A, 0x8B, 0x8C
CTRL_HOME, CTRL_END = 0x82, 0x84
SHIFT, ALT, CTRL = 1, 2, 4


class Play:
    def __init__(self):
        self.b = bytearray()
        self.marks = []

    def P(self, x, y):
        self.b += bytes([ord('P'), x & 255, x >> 8, y & 255, y >> 8])

    def click(self, x, y, n=1):
        self.P(x, y)
        for _ in range(n):
            self.b += b'D'
            self.W(4)
            self.b += b'U'

    def K(self, k, mods=0):
        if mods & CTRL and 0x40 <= k < 0x80:
            k &= 0x1F                   # Ctrl + a letter: the ROM gives its control code
        if mods:
            self.b += bytes([ord('M'), mods])
        self.b += bytes([ord('K'), k])
        if mods:
            self.b += bytes([ord('M'), 0])

    def ctrl(self, c, shift=False):
        self.K(ord(c), CTRL | (SHIFT if shift else 0))

    def T(self, s):
        """text typed (LF: Return); in pieces of 8 keys"""
        s = s.replace('\n', '\r').encode('latin-1') if isinstance(s, str) else s
        for i in range(0, len(s), 8):
            c = s[i:i + 8]
            self.b += bytes([ord('T'), len(c)]) + c

    def line(self, s):
        """a line typed and Return (the editor's auto-indent adds the
        indentation: s is typed without its own)"""
        self.T(s.lstrip(' ') + '\n')

    def W(self, n):
        while n > 0:
            self.b += bytes([ord('W'), min(n, 250)])
            n -= 250

    def L(self, n):
        self.b += bytes([ord('L'), n])
        self.marks.append(n)

    def B(self, m, n=7):
        """the blink probe: n changes of the cursor, the main loop slowed
        by m (tests/edit_play.s, tests/check_blink.py)"""
        self.b += bytes([ord('B'), m, n])

    def stop(self):
        self.b += b'S'

    def data(self):
        return bytes(self.b) + b'E'
