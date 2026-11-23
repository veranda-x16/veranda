"""VeraBASIC's reference interpreter: the Veranda statements (phase 3,
DECISIONS V89), mixed into tools/vbasic.py's Interp.

The reference does not draw. It parses every Veranda statement as VeraBASIC
Run does, evaluates its arguments in the same order, checks what Run
checks, and logs it as Run's test build does:

    VB> @nn [@ss] args      a statement: its second-page byte (ON: "ON"),
                            its second word, then each argument: a number,
                            "a string", @ww a word, Pn a procedure
    VB= @nn value           a function's value (Run's; replayed here)
    VB EVENT d KIND args    a handler started at the program's d-th event
                            point (WAIT EVENTS, DOEVENTS, SLEEP)

What only the machine knows (the pointer, the keys, the fonts' widths, the
clock, when an event came) is read from Run's own log (--replay): the
values of its functions and its events, each at the event point where Run
took it. Everything else must then come out the same, line for line.

MIT licence (LICENSE)."""

import re

from vbveranda2 import escape, unescape

EV_KINDS = {'MENU', 'CLICK', 'KEY', 'WHEEL', 'CLOSE', 'TIMER', 'QUIT', 'ICON'}
MAXMENU, MAXITEM = 8, 40
TK_CALL, TK_TO, TK_ON, TK_STOP, TK_ELSE = 0xB0, 0x9C, 0x88, 0x8E, 0x92


class Stuck(Exception):
    """waiting for an event that Run's log does not have"""


class VerandaMixin:
    def x_init(self, replay=None):
        self.replay = replay or []
        self.rpos = 0
        self.any_bound = False
        self.bind = {}              # 'CLICK' ... ('CLOSE', w), ('TIMER', n): procedure
        self.menus = []             # [title, first item, count]
        self.items = []             # [name, procedure or None, key, flags]
        self.mcur = None
        self.mshown = False
        self.windows = {}           # w: [x, y, w, h, tool, status, flags]
        self.wopen = set()
        self.dpc = 0
        self.waitf = False
        self.sleeping = False
        self.hact = False
        self.hbase = 0
        # the main lines' end: WAIT EVENTS (Run's wait_stub)
        self.stub = len(self.code)
        self.code = bytes(self.code) + bytes([0xC5, 0xC6, 0, 0])

    # --- Run's log ---
    def x_out(self, line):
        self.out.write(line + '\n')
        if self.rpos < len(self.replay):
            self.rpos += 1

    def x_peek(self):
        return self.replay[self.rpos] if self.rpos < len(self.replay) else ''

    # --- tokens ---
    def x_word(self, name):
        code = self.KW[name]
        if self.code[self.ip] == 0xFF and self.code[self.ip + 1] == code & 0xFF:
            self.ip += 2
            return True
        return False

    def x_tend(self):
        c = self.code[self.ip]
        return c == 0 or c == ord(':') or c == ord("'") or c == TK_ELSE

    # --- arguments: evaluated first, then converted and logged ---
    def x_num(self, items):
        v = self.expr()
        if v[0] == 2:
            raise self.Err(13)
        items.append(('n', v))

    def x_str(self, items):
        v = self.expr()
        if v[0] != 2:
            raise self.Err(13)
        items.append(('s', v))

    def x_cnum(self, items):
        self.expect(',')
        self.x_num(items)

    def x_cstr(self, items):
        self.expect(',')
        self.x_str(items)

    def x_hash(self, items):
        self.accept('#')
        self.x_num(items)

    def x_proc(self, items):
        if self.code[self.ip] != 8:     # TAG_NAMEREF
            raise self.Err(2)
        sym = self.w(self.ip + 1)
        p = self.proc_of_sym.get(sym)
        if p is None:
            raise self.Err(2)
        self.ip += 6
        items.append(('p', p.idx))

    def x_done(self, items, nn, sub=None, log=True):
        """the statement's end, the arguments as Run converts them"""
        if log:
            self.end_stmt()
        out = []
        text = ['ON' if nn == 0 else '@%02X' % nn]
        if sub is not None:
            text.append('@%02X' % sub)
        for kind, v in items:
            if kind == 'n':
                x = self.to_int(*v)
                text.append(str(x))
            elif kind == 's':
                x = bytes(v[1])
                text.append('"%s"' % escape(x))
            elif kind == 'w':
                x = v
                text.append('@%02X' % v)
            else:
                x = v
                text.append('P%d' % v)
            out.append(x)
        if log:
            self.x_out('VB> ' + ' '.join(text))
        return out

    def x_spec(self, nn, spec, func=False):
        items = []
        i = 0
        while i < len(spec):
            c = spec[i]
            if c == 'n':
                self.x_num(items)
            elif c == 's':
                self.x_str(items)
            elif c == '[':
                if not self.accept(','):
                    break
            else:
                self.expect(c)
            i += 1
        return self.x_done(items, nn, log=not func)

    # --- the statements ---
    def x_statement(self):
        nn = self.code[self.ip + 1]
        self.ip += 2
        h = self.XSTMT.get(nn) or self.XSTMT2.get(nn)
        if h is None:
            if nn in self.XSPEC:
                a = self.x_spec(nn, self.XSPEC[nn])
                self.x_check(nn, a)
                return None
            raise self.Err(20)
        return h(self, nn)

    def x_check(self, nn, a):
        """what overlay 7 checks"""
        ill = self.Err(5)
        if nn == 0xB9 and not 0 <= a[0] < 34:
            raise ill
        if nn in (0xBD, 0xBE):
            k = 4 if nn == 0xBD else 2
            if len(a) > k and a[k] not in (0, 1):
                raise ill
        if nn == 0xC2 and not 0 <= a[0] < 4:
            raise ill
        if nn == 0xC9 and not 0 <= a[4] < 16:
            raise ill
        if nn == 0xCC and not 12 <= a[0] < 16:
            raise ill
        if nn == 0xD9:
            if not 0 <= a[0] < 14 or not 0 <= a[2] < 64 or (len(a) > 3 and not 0 <= a[3] < 4):
                raise ill
        if nn == 0xDA and not 0 <= a[0] < 14:
            raise ill

    def x_on(self):
        items = []
        kind = None
        for name in ('CLICK', 'KEY', 'WHEEL', 'QUIT'):
            if self.x_word(name):
                kind = name
                items.append(('w', self.KW[name] & 0xFF))
                break
        else:
            if not self.x_word('CLOSE'):
                raise self.Err(2)
            items.append(('w', self.KW['CLOSE'] & 0xFF))
            self.x_hash(items)
            kind = 'CLOSE'
        if self.code[self.ip] != TK_CALL:
            raise self.Err(2)
        self.ip += 1
        self.x_proc(items)
        a = self.x_done(items, 0)
        if kind == 'CLOSE':
            if not 1 <= a[1] <= 4:
                raise self.Err(5)
            self.bind[('CLOSE', a[1])] = a[2]
        else:
            self.bind[kind] = a[1]
        self.any_bound = True

    def s_timer(self, nn):
        items = []
        self.x_num(items)
        if self.accept(','):
            self.x_num(items)
            if self.code[self.ip] != TK_CALL:
                raise self.Err(2)
            self.ip += 1
            self.x_proc(items)
            a = self.x_done(items, nn)
            n = self.x_timer_n(a[0])
            if a[1] == 0:
                raise self.Err(5)
            self.bind[('TIMER', n)] = a[2]
            self.any_bound = True
            return
        if self.accept_kw('ON'):
            op = 0
        elif self.accept_kw('STOP'):
            op = 2
        elif self.x_word('OFF'):
            op = 1
        else:
            raise self.Err(2)
        items.append(('w', op))
        a = self.x_done(items, nn)
        n = self.x_timer_n(a[0])
        if op == 2:
            self.bind.pop(('TIMER', n), None)

    def x_timer_n(self, n):
        if not 1 <= n <= 8:
            raise self.Err(5)
        return n

    def s_app(self, nn):
        self.skip_stmt()

    def s_window(self, nn):
        items = []
        for sub, strs in (('TITLE', 1), ('STATUS', 2), ('USE', 0), ('BACK', 0), ('FRONT', 0), ('CLOSE', 0)):
            if self.x_word(sub):
                self.x_hash(items)
                for _ in range(strs):
                    self.x_cstr(items)
                a = self.x_done(items, nn, self.KW[sub] & 0xFF)
                w = a[0]
                if sub == 'USE' and w == 0:
                    return
                if not 1 <= w <= 4:
                    raise self.Err(5)
                if sub != 'TITLE' and w not in self.wopen:
                    raise self.Err(25)
                if sub == 'CLOSE':
                    self.wopen.discard(w)
                return
        self.x_hash(items)
        for _ in range(4):
            self.x_cnum(items)
        self.x_cstr(items)
        while self.accept(','):
            for sub, num in (('TOOL', 1), ('STATUS', 1), ('CLOSE', 0), ('FRAME', 0), ('SHADOW', 0)):
                if self.x_word(sub):
                    items.append(('w', self.KW[sub] & 0xFF))
                    if num:
                        self.x_num(items)
                    break
            else:
                raise self.Err(2)
        a = self.x_done(items, nn)
        w = a[0]
        if not 1 <= w <= 4:
            raise self.Err(5)
        x, y, wc, hc = a[1:5]
        if not (0 <= x and 0 <= wc and x + wc <= 80 and 2 <= y and y + hc <= 60 and wc >= 6 and hc >= 4):
            raise self.Err(5)
        self.wopen.add(w)

    def s_screen(self, nn):
        if not self.x_word('FULL'):
            raise self.Err(2)
        items = []
        if not self.x_tend():
            self.x_str(items)
        self.x_done(items, nn, self.KW['FULL'] & 0xFF)

    def s_menu(self, nn):
        items = []
        if self.x_word('SHOW'):
            self.x_done(items, nn, self.KW['SHOW'] & 0xFF)
            if not self.menus:
                raise self.Err(2)
            self.mshown = True
            return
        if self.x_word('ENABLE'):
            self.x_str(items)
            self.x_cstr(items)
            self.x_cnum(items)
            a = self.x_done(items, nn, self.KW['ENABLE'] & 0xFF)
            for m in self.menus:
                if m[0] == a[0]:
                    it = self.x_find(a[1], m[1], m[1] + m[2])
                    if a[2]:
                        it[3] &= ~1
                    else:
                        it[3] |= 1
                    return
            raise self.Err(5)
        self.x_str(items)
        a = self.x_done(items, nn)
        if self.mshown:
            self.mshown = False
            self.menus, self.items = [], []
        if len(self.menus) >= MAXMENU:
            raise self.Err(26)
        self.mcur = len(self.menus)
        self.menus.append([a[0], len(self.items), 0])

    def x_find(self, name, lo, hi):
        for it in self.items[lo:hi]:
            if it[0] == name:
                return it
        raise self.Err(5)

    def s_item(self, nn):
        items = []
        self.x_str(items)
        if self.accept(','):
            self.x_proc(items)
            if self.accept(','):
                self.x_str(items)
        a = self.x_done(items, nn)
        if self.mcur is None:
            raise self.Err(2)
        if a[0] == b'-':
            return
        if len(self.items) >= MAXITEM:
            raise self.Err(26)
        self.items.append([a[0][:31], a[1] if len(a) > 1 else None, None, 0])
        if len(a) > 1:
            self.any_bound = True
        self.menus[self.mcur][2] += 1

    def s_check(self, nn):
        items = []
        self.x_str(items)
        self.x_cnum(items)
        a = self.x_done(items, nn)
        self.x_find(a[0], 0, len(self.items))

    def s_endmenu(self, nn):
        self.mcur = None

    def s_mouse(self, nn):
        if not self.x_word('LIMIT'):
            raise self.Err(2)
        items = []
        self.x_num(items)
        for _ in range(3):
            self.x_cnum(items)
        self.x_done(items, nn, self.KW['LIMIT'] & 0xFF)

    def s_copy(self, nn):
        items = []
        self.x_num(items)
        for _ in range(3):
            self.x_cnum(items)
        if self.code[self.ip] != TK_TO:
            raise self.Err(2)
        self.ip += 1
        self.x_num(items)
        self.x_cnum(items)
        self.x_done(items, nn)

    def s_font(self, nn):
        items = []
        v = self.expr()
        if v[0] == 2:
            items.append(('s', v))
            self.x_cnum(items)
            a = self.x_done(items, nn)
            # the fonts the reference knows: those built into the kernel
            if (a[0], a[1]) not in ((b'System', 9), (b'Veranda UI', 12)):
                raise self.Err(24)
            return
        items.append(('n', v))
        a = self.x_done(items, nn)
        if a[0] not in (4, 6):
            raise self.Err(5)

    def s_sound(self, nn):
        items = []
        if self.x_word('OFF'):
            items.append(('w', self.KW['OFF'] & 0xFF))
        else:
            self.x_num(items)
        self.x_done(items, nn)

    def s_aside(self, nn):
        self.end_stmt()

    XSPEC = {0xB8: '', 0xB9: 'n', 0xBA: 'n,n,n,n', 0xBB: 'n,n,n,n', 0xBC: 'n,n,n,n', 0xBD: 'n,n,n,n[n',
             0xBE: 'n,n[n', 0xC1: 'n,n,n,n,n', 0xC2: 'n', 0xC3: 'n,n,s', 0xC5: 'n', 0xC8: 'n,n,s[n',
             0xC9: 'n,n,n,n,n', 0xCB: 'n', 0xCC: 'n,n', 0xD8: '', 0xD9: 'n,n,n[n[n', 0xDA: 'n,s'}
    XSTMT = {0x84: s_timer, 0x85: s_app, 0x8E: s_window, 0x9A: s_screen, 0x9C: s_menu, 0x9D: s_item,
             0x9E: s_check, 0x9F: s_endmenu, 0xC0: s_copy, 0xC4: s_font, 0xD1: s_mouse, 0xD7: s_sound,
             0xF0: s_aside}

    # --- the functions: Run's values from its log ---
    XFARGS = {0x97: '(n,n,n)', 0x98: '(n)', 0x99: '(n)', 0xBF: '(n,n)', 0xC6: '(s)', 0xCA: '(n,n)',
              0xD0: '(n,n,n,n)', 0xF2: '(n)'}
    XFDEV = {0x82, 0x97, 0x98, 0x99, 0xBF, 0xC6, 0xC7, 0xCA, 0xCD, 0xCE, 0xCF, 0xD0, 0xD4, 0xD5, 0xD6,
             0xEC, 0xED, 0xF1, 0xF2}
    XFSTR = {0xD4, 0xEC, 0xED, 0xF2}

    def x_function(self):
        nn = self.code[self.ip + 1]
        self.ip += 2
        if nn == 0xD3:                  # INKEY$: the keys typed (as phase 1)
            k = self.key()
            return (2, b'' if k is None else bytes([k]))
        if nn in (0xC9, 0xCB, 0x8F):    # PAPER, INK, TITLE: colours
            return (1, {0xC9: 0, 0xCB: 1, 0x8F: 5}[nn])
        if nn in self.XFUN2:            # part 2 (vbveranda2.py)
            return self.XFUN2[nn](self, nn)
        if nn not in self.XFDEV:
            raise self.Err(20)
        spec = self.XFARGS.get(nn)
        if spec:
            if nn in (0x97, 0x98, 0x99):
                self.expect('(')
                items = []
                self.x_hash(items)
                if nn == 0x97:
                    self.x_cnum(items)
                    self.x_cnum(items)
                self.expect(')')
                self.x_done(items, nn, log=False)
            else:
                self.x_spec(nn, spec, func=True)
        line = self.x_peek()
        m = re.match(r'VB= @%02X (.*)$' % nn, line)
        if nn in self.XFSTR:
            v = unescape(m.group(1)[1:-1]) if m else b''
            self.x_out('VB= @%02X "%s"' % (nn, escape(v)))
            return (2, v)
        v = int(m.group(1)) if m else 0
        self.x_out('VB= @%02X %d' % (nn, v))
        return (1, v)

    # --- events ---
    def x_inhandler(self):
        if self.hact and len(self.stack) > self.hbase:
            return True
        self.hact = False
        return False

    def x_dispatch(self, ret):
        """Run's next event if it took one at this event point: its handler
        entered, returning to ret; False if none"""
        m = re.match(r'VB EVENT (\d+) (\w+)(.*)$', self.x_peek())
        if not m or int(m.group(1)) != self.dpc:
            return False
        kind, args = m.group(2), [int(x) for x in m.group(3).split()]
        if kind == 'MENU':
            pi = self.items[args[0]][1] if args[0] < len(self.items) else None
        elif kind in ('CLOSE', 'TIMER', 'ICON'):
            pi = self.bind.get((kind, args[0]))
        else:
            pi = self.bind.get(kind)
        if pi is None:
            raise Stuck()
        self.x_out(self.x_peek())
        p = self.procs[pi]
        if p.nparams:
            raise self.Err(19)
        if p.is_function:
            raise self.Err(2)
        self.waitf = False
        self.hbase = len(self.stack)
        self.hact = True
        frame = [self.Cell(ty) for ty, fl in p.slots]
        self.enter(p, frame, ret)
        return True

    def x_wait(self):
        """WAIT EVENTS (and the main lines' end): Run waits here"""
        if self.x_inhandler():
            raise self.Err(5)
        if not self.waitf:
            self.waitf = True
            self.dpc += 1
        if not self.x_dispatch(self.stmt_ip):
            raise Stuck()

    def x_doevents(self):
        if self.x_inhandler():
            return
        self.dpc += 1
        self.x_dispatch(self.stmt_ip)

    def x_sleep(self):
        """SLEEP: its first run evaluates and counts an event point; Run takes
        events while it sleeps, each handler returning to the SLEEP"""
        first = not self.sleeping
        if first:
            n = self.to_int(*self.expr())
            self.end_stmt()
            if n < 0:
                raise self.Err(5)
        else:
            self.skip_stmt()
        if self.any_bound and not self.x_inhandler():
            if first:
                self.dpc += 1
            if self.x_dispatch(self.stmt_ip):
                self.sleeping = True
                return
        self.sleeping = False
