"""VeraBASIC's reference interpreter: the Veranda statements, part 2 (phase 4,
DECISIONS V90), mixed into tools/vbasic.py's Interp with vbveranda.py's.

Files and folders are real: a program's files are made, read, renamed and
removed in the reference's folder (tools/vbasic.py run --dir DIR, the
current folder by default), which stands for the card's top folder, so a
gate compares the files Run wrote with the reference's byte for byte. The
kernel's errors are given as Run's are (ERRFILE: the kernel's code).

What only the machine knows comes from Run's log (--replay), as in part 1:
the answers of the dialog boxes (ASK, INPUTBOX$, FILEOPEN$, FILESAVE$, a
DIALOG's fields and result: "VB= @nn ..."; the folder the Open and Save
dialog chose: "VB CD path"), the clipboard's text (CLIPBOARD$) and a
folder's listing (DIR$: the DOS's order). Pictures (PICTURE$) are packed
here as Run packs them, byte for byte.

MIT licence (LICENSE)."""

import fnmatch
import os
import re

TK_DATA, TK_TAB, TK_SPC, TK_ON = 0x89, 0xE9, 0xEA, 0x88
T_BLOCK = 0x0B
MAXFILES = 3
# the kernel's error codes (api/veranda.api)
FILE_NOT_FOUND, INCOMPATIBLE, FILE_EXISTS, TOO_MANY_FILES, DOS_ERROR = 5, 14, 15, 16, 20
PSTR, PROWS = 16, 160           # a picture's rows: 16 bytes, 160 of them at most (vbfile.s)
SRAW = 512                      # a sprite's picture unpacked: 512 bytes at most (vbdlg.s)
FOLDERS = {1: '/DOCUMENTS', 2: '/VERANDA/APPS', 3: '/VERANDA/FONTS', 4: '/VERANDA', 5: '/VERANDA/.SYSTEM'}


def escape(b):
    """a string's bytes as Run's test build logs them (vbui.s lg_sc): control
    characters, "\\" and 127 on as "\\" and two hex digits"""
    return ''.join('\\%02X' % c if c < 32 or c == 92 or c >= 127 else chr(c) for c in b)


def unescape(s):
    return re.sub(r'\\([0-9A-F]{2})', lambda m: chr(int(m.group(1), 16)), s).encode('latin-1')


def pack24(v):
    """a whole number of 24 bits as the ROM's packed float (vbui4.s fr_u24)"""
    e = 0x98
    while not v & 0x800000:
        v <<= 1
        e -= 1
    return bytes([e, (v >> 16) & 0x7F, (v >> 8) & 0xFF, v & 0xFF, 0])


def compact(d):
    """GEOS's compacted bitmap, as vbdlg.s pack writes it: repeats of 3-127,
    runs of up to 91 bytes as they are"""
    out = bytearray()
    i, n = 0, len(d)

    def run(j, most):
        r = 1
        while r < most and j + r < n and d[j + r] == d[j]:
            r += 1
        return r
    while i < n:
        r = run(i, 127)
        if r >= 3:
            out += bytes([r, d[i]])
            i += r
            continue
        j = i
        while j < n and j - i < 91 and run(j, 3) < 3:
            j += 1
        out.append(128 + j - i)
        out += d[i:j]
        i = j
    return bytes(out)


def unpack(data, size):
    """the compacted bytes (BitmapUp's) to size bytes; None if they are not"""
    out = bytearray()
    i = 0
    while len(out) < size:
        if i >= len(data):
            return None
        c = data[i]
        i += 1
        if 0 < c < 128:
            if i >= len(data):
                return None
            out += bytes([data[i]]) * c
            i += 1
        elif 128 < c < 220:
            k = c - 128
            if i + k > len(data):
                return None
            out += data[i:i + k]
            i += k
        else:
            return None
    return bytes(out[:size])


class HostFile:
    def __init__(self, f, mode):
        self.f, self.mode, self.col, self.end = f, mode, 0, 0


class Veranda2Mixin:
    def x2_init(self, root=None):
        self.root = os.path.abspath(root or '.')
        self.cwd = '/'
        self.files = {}
        self.dopen = False
        self.dres = 0
        self.dlg = None
        self.icons = set()

    def x2_finish(self):
        for h in list(self.files):
            self.files.pop(h).f.close()

    # --- the host's folder ---
    def host(self, name):
        """a name in the current folder (or from the top, "/...") on the host"""
        if name.startswith('/'):
            return self.root + name
        return os.path.join(self.root + self.cwd, name)

    def kerr(self, k):
        code = {FILE_NOT_FOUND: 50, TOO_MANY_FILES: 51, FILE_EXISTS: 58, INCOMPATIBLE: 59}.get(k, 57)
        return self.Err(code, kernel=k)

    def slot(self, h):
        if not 1 <= h <= 255:
            raise self.Err(52)
        if h not in self.files:
            raise self.Err(53)
        return self.files[h]

    def sel(self, h, write):
        if h == 0:
            raise self.Err(52)
        if h not in self.files:
            raise self.Err(53)
        f = self.files[h]
        if f.mode == ('r' if write else 'w'):
            raise self.Err(55)
        return f

    # --- OPEN, CLOSE, PUT, SEEK ---
    def s_open(self, nn):
        items = []
        self.x_hash(items)
        self.x_cstr(items)
        self.x_cstr(items)
        h, name, mode = self.x_done(items, nn)
        if not 1 <= h <= 255:
            raise self.Err(52)
        if h in self.files:
            raise self.Err(54)
        if len(mode) != 1 or chr(mode[0] | 0x20) not in 'rwm':
            raise self.Err(55)
        m = chr(mode[0] | 0x20)
        if len(self.files) >= MAXFILES:
            raise self.kerr(TOO_MANY_FILES)
        n = name.decode('latin-1')
        if '/' in n:            # (vbfile.s cmdname: CMD's syntax, 64 characters at most)
            d, f = n.rsplit('/', 1)
            if len('/' + d + '/:' + f) > 64:
                raise self.kerr(FILE_NOT_FOUND)
        p = self.host(n)
        if m != 'w' and not os.path.isfile(p):
            raise self.kerr(FILE_NOT_FOUND)
        try:
            f = open(p, {'r': 'rb', 'w': 'wb', 'm': 'r+b'}[m])
        except OSError:
            raise self.kerr(DOS_ERROR)
        self.files[h] = HostFile(f, m)
        if m != 'w':
            self.files[h].end = os.path.getsize(p)

    def s_close(self, nn):
        items = []
        if not self.x_tend():
            while True:
                self.x_hash(items)
                if not self.accept(','):
                    break
        hs = self.x_done(items, nn)
        for h in (hs if hs else list(self.files)):
            if h in self.files:
                self.files.pop(h).f.close()

    def fwrite(self, f, data):
        f.f.write(data)
        for c in data:
            f.col = 0 if c == 10 else min(f.col + 1, 255)
        f.end = max(f.end, f.f.tell())

    def s_put(self, nn):
        items = []
        self.x_hash(items)
        self.x_cstr(items)
        h, s = self.x_done(items, nn)
        if h > 255 or h < 0:
            raise self.Err(52)
        self.fwrite(self.sel(h, True), s)

    def to24(self, v):
        ty, x = v
        if ty == 2:
            raise self.Err(13)
        if ty == 1:
            if x < 0:
                raise self.Err(5)
            return x
        e = x[0]
        if e < 0x81:
            return 0
        if x[1] & 0x80 or e > 0x98:
            raise self.Err(5)
        return ((x[1] | 0x80) << 16 | x[2] << 8 | x[3]) >> (0x98 - e)

    def s_seek(self, nn):
        items = []
        self.x_hash(items)
        self.expect(',')
        pos = self.to24(self.expr())
        self.end_stmt()
        h = self.x_done(items, nn, log=False)[0]
        self.x_out('VB> @%02X %d %d' % (nn, h, pos))
        f = self.slot(h)
        f.f.seek(pos)

    # --- PRINT #, INPUT #, LINE INPUT #, GET # (the core's, '#' first) ---
    def hnum(self):
        self.ip += 1
        h = self.to_int(*self.expr())
        if not 0 <= h <= 255:
            raise self.Err(52)
        return h

    def x_printh(self):
        h = self.hnum()
        newline = True
        if not self.x_tend():
            self.expect(',')
        while not self.x_tend():
            c = self.peek()
            if c == ord(';'):
                self.ip += 1
                newline = False
                continue
            if c == ord(','):
                self.ip += 1
                f = self.sel(h, True)
                t = ((f.col // 10 + 1) * 10) & 0xFF
                while f.col < t:
                    self.fwrite(f, b' ')
                newline = False
                continue
            if c in (TK_TAB, TK_SPC):
                self.ip += 1
                n = self.to_int(*self.args1())
                if not 0 <= n <= 255:
                    raise self.Err(5)
                f = self.sel(h, True)
                if c == TK_TAB:
                    while f.col < n:
                        self.fwrite(f, b' ')
                else:
                    self.fwrite(f, b' ' * n)
                newline = True
                continue
            v = self.expr()
            if v[0] == 2:
                self.fwrite(self.sel(h, True), bytes(v[1]))
            else:
                self.fwrite(self.sel(h, True), (self.num_text(v) + ' ').encode('latin-1'))
            newline = True
        if newline:
            self.fwrite(self.sel(h, True), b'\n')
        self.end_stmt()

    def rline(self, h):
        """the next line (to LF, CR or CR LF; 255 bytes at most), as text"""
        f = self.sel(h, False).f
        out = bytearray()
        c = f.read(1)
        if not c:
            raise self.Err(56)
        while c:
            if c == b'\n':
                break
            if c == b'\r':
                c2 = f.read(1)
                if c2 and c2 != b'\n':
                    f.seek(-1, 1)
                break
            out += c
            if len(out) == 255:
                break
            c = f.read(1)
        return out.decode('latin-1')

    def x_inputh(self, line):
        h = self.hnum()
        self.expect(',')
        if line:
            tgt = self.lvalue()
            if tgt.ty != 2:
                raise self.Err(13)
            tgt.v = self.rline(h).encode('latin-1')
            self.end_stmt()
            return
        fields = self.fields(self.rline(h))
        while True:
            tgt = self.lvalue()
            if not fields:
                fields = self.fields(self.rline(h))
            fl = fields.pop(0)
            if tgt.ty == 2:
                tgt.v = fl.encode('latin-1')
            else:
                r = self.parse_number(fl, True) if fl.strip() else (1, 0)
                if r is None:
                    raise self.Err(13)
                self.store(tgt, r)
            if not self.accept(','):
                break
        self.end_stmt()

    def x_geth(self):
        h = self.hnum()
        self.expect(',')
        tgt = self.lvalue()
        if tgt.ty != 2:
            raise self.Err(13)
        self.expect(',')
        n = self.to_int(*self.expr())
        if not 0 <= n <= 255:
            raise self.Err(5)
        tgt.v = self.sel(h, False).f.read(n)
        self.end_stmt()

    # --- folders ---
    def s_kill(self, nn):
        name = self.x_spec(nn, 's')[0].decode('latin-1')
        p = self.host(name)
        if not os.path.isfile(p):
            raise self.kerr(FILE_NOT_FOUND)
        os.remove(p)

    def s_name(self, nn):
        items = []
        self.x_str(items)
        if not self.x_word('AS'):
            raise self.Err(2)
        self.x_str(items)
        a, b = [x.decode('latin-1') for x in self.x_done(items, nn)]
        pa, pb = self.host(a), self.host(b)
        if not os.path.exists(pa):
            raise self.kerr(FILE_NOT_FOUND)
        if os.path.exists(pb):
            raise self.kerr(FILE_EXISTS)
        os.rename(pa, pb)

    def s_mkdir(self, nn):
        p = self.host(self.x_spec(nn, 's')[0].decode('latin-1'))
        if os.path.exists(p):
            raise self.kerr(FILE_EXISTS)
        os.mkdir(p)

    def s_rmdir(self, nn):
        name = self.x_spec(nn, 's')[0].decode('latin-1')
        p = self.host(name)
        if not os.path.isdir(p):
            raise self.kerr(FILE_NOT_FOUND)
        if os.listdir(p):
            raise self.kerr(DOS_ERROR)
        os.rmdir(p)

    def newpath(self, arg):
        """CHDIR's path (vbfile.s f9_chdir)"""
        parts = [] if arg.startswith('/') else [x for x in self.cwd.split('/') if x]
        for x in arg.split('/'):
            if x in ('', '.'):
                continue
            if x == '..':
                if parts:
                    parts.pop()
                continue
            parts.append(x)
        p = '/' + '/'.join(parts)
        if len(p) > 63:
            raise self.Err(14)
        return p

    def s_chdir(self, nn):
        p = self.newpath(self.x_spec(nn, 's')[0].decode('latin-1'))
        if not os.path.isdir(self.root + p):
            raise self.kerr(FILE_NOT_FOUND)
        self.cwd = p

    # --- dialogs ---
    def x_values(self, nn):
        """Run's VB= lines for nn (consecutive), as they are"""
        out = []
        while True:
            m = re.match(r'VB= @%02X (.*)$' % nn, self.x_peek())
            if not m:
                return out
            self.x_out(self.x_peek())
            out.append(m.group(1))

    def x_replayed(self, nn, string):
        line = self.x_peek()
        m = re.match(r'VB CD (.*)$', line)
        if m:
            self.x_out(line)
            self.cwd = m.group(1) or '/'
            line = self.x_peek()
        m = re.match(r'VB= @%02X (.*)$' % nn, line)
        if string:
            v = unescape(m.group(1)[1:-1]) if m else b''
            self.x_out('VB= @%02X "%s"' % (nn, escape(v)))
            return (2, v)
        v = int(m.group(1)) if m else 0
        self.x_out('VB= @%02X %d' % (nn, v))
        return (1, v)

    def s_msgbox(self, nn):
        self.x_spec(nn, 's[s')

    def s_dialog(self, nn):
        if self.code[self.ip] == T_BLOCK:
            self.ip += 3
        x, y, w, h = self.x_spec(nn, 'n,n,n,n')
        if not (0 <= x and x + w <= 80 and 2 <= y and y + h <= 60 and w >= 16 and h >= 6):
            raise self.Err(5)
        self.dopen = True
        self.dlg = {'w': w, 'h': h, 'labels': 0, 'fields': []}

    def x_inside(self):
        if not self.dopen:
            raise self.Err(60)

    def s_label(self, nn):
        x, y, s = self.x_spec(nn, 'n,n,s')
        self.x_inside()
        if not (0 <= x < 32 and 0 <= y < self.dlg['h']):
            raise self.Err(5)
        if self.dlg['labels'] >= 8:
            raise self.Err(60)
        self.dlg['labels'] += 1

    def s_field(self, nn):
        items = []
        self.x_num(items)
        self.x_cnum(items)
        self.expect(',')
        at = self.ip
        tgt = self.lvalue()
        if tgt.ty != 2:
            raise self.Err(13)
        self.ip = at
        self.x_str(items)
        self.x_cnum(items)
        x, y, s, n = self.x_done(items, nn)
        self.x_inside()
        if len(self.dlg['fields']) >= 4:
            raise self.Err(60)
        if not (0 <= x < self.dlg['w'] and 0 <= y < self.dlg['h'] and 1 <= n <= 63):
            raise self.Err(5)
        self.dlg['fields'].append(tgt)

    def s_button(self, nn):
        items = []
        for w in ('OK', 'CANCEL'):
            if self.x_word(w):
                items.append(('w', self.KW[w] & 0xFF))
                break
        else:
            raise self.Err(2)
        self.x_done(items, nn)
        self.x_inside()

    def s_enddialog(self, nn):
        self.x_spec(nn, '')
        self.x_inside()
        self.dopen = False
        texts = self.x_values(0xAC)
        res = self.x_values(0xA8)
        self.dres = int(res[0]) if res else 0
        if self.dres == 1:
            for tgt, t in zip(self.dlg['fields'], texts):
                tgt.v = unescape(t[1:-1])

    # --- icons, tiles, pictures, sprites, the clipboard ---
    def pcheck(self, s):
        if len(s) < 3 or not 1 <= s[0] <= 80 or s[1] == 0:
            raise self.Err(59)
        return s[0], s[1]

    def s_icon(self, nn):
        items = []
        if self.x_word('OFF'):
            self.x_num(items)
            i = self.x_done(items, nn, self.KW['OFF'] & 0xFF)[0]
            if not 1 <= i <= 8:
                raise self.Err(5)
            self.bind.pop(('ICON', i), None)
            return
        self.x_num(items)
        self.x_cnum(items)
        self.x_cnum(items)
        self.x_cstr(items)
        self.expect(',')
        self.x_proc(items)
        i, x, y, pic, p = self.x_done(items, nn)
        if not 1 <= i <= 8:
            raise self.Err(5)
        self.pcheck(pic)
        self.bind[('ICON', i)] = p
        self.any_bound = True

    def s_icons(self, nn):
        if not self.x_word('CLEAR'):
            raise self.Err(2)
        self.x_done([], nn, self.KW['CLEAR'] & 0xFF)
        for k in [k for k in self.bind if k[0] == 'ICON']:
            del self.bind[k]

    def s_tile(self, nn):
        if self.code[self.ip] == TK_DATA:
            self.skip_stmt()
            return
        a = self.x_spec(nn, 'n,n,s[n')
        if not (0 <= a[0] <= 76 and 0 <= a[1] <= 56) or (len(a) > 3 and not 0 <= a[3] < 16):
            raise self.Err(5)
        name = a[2].decode('latin-1') + '.cvt'
        for d in (self.cwd, '/VERANDA/APPS', '/VERANDA', '/'):
            p = os.path.join(self.root + d, name)
            if os.path.isfile(p):
                break
        else:
            raise self.kerr(FILE_NOT_FOUND)
        d = open(p, 'rb').read(510)
        if len(d) < 510 or d[30:53] != b'PRG formatted GEOS file':
            raise self.kerr(INCOMPATIBLE)

    def s_bitmap(self, nn):
        a = self.x_spec(nn, 'n,n,s')
        self.pcheck(a[2])

    def s_clipboard(self, nn):
        items = []
        if self.x_word('PICTURE'):
            self.x_num(items)
            for _ in range(3):
                self.x_cnum(items)
            self.x_done(items, nn, self.KW['PICTURE'] & 0xFF)
            return
        self.x_str(items)
        self.x_done(items, nn)

    def s_sprite(self, nn):
        items = []
        self.x_num(items)
        if self.accept(','):
            self.x_str(items)
            n, pic = self.x_done(items, nn)
            self.x_sprn(n)
            w, h = self.pcheck(pic)
            if w * h > SRAW or unpack(pic[2:], w * h) is None:
                raise self.Err(59)
            return
        if self.x_word('AT'):
            self.x_num(items)
            self.x_cnum(items)
            self.x_sprn(self.x_done(items, nn, self.KW['AT'] & 0xFF)[0])
            return
        if self.accept_kw('ON'):
            items.append(('w', 0))
        elif self.x_word('OFF'):
            items.append(('w', 1))
        else:
            raise self.Err(2)
        self.x_sprn(self.x_done(items, nn)[0])

    def x_sprn(self, n):
        if not 2 <= n <= 7:
            raise self.Err(5)

    # --- the functions ---
    def f_string_args(self, most):
        """(s [, s [, n]]): the strings and numbers, as Run reads them"""
        items = []
        self.expect('(')
        self.x_str(items)
        if most > 1 and self.accept(','):
            self.x_str(items)
            if most > 2 and self.accept(','):
                self.x_num(items)
        self.expect(')')
        return self.x_done(items, 0, log=False)

    def f_ask(self, nn):
        self.f_string_args(1)
        return self.x_replayed(nn, False)

    def f_inputbox(self, nn):
        a = self.f_string_args(3)
        if len(a) > 2 and not 1 <= a[2] <= 63:
            raise self.Err(5)
        return self.x_replayed(nn, True)

    def f_fileopen(self, nn):
        self.f_string_args(2)
        return self.x_replayed(nn, True)

    def f_filesave(self, nn):
        self.x_spec(nn, '(s,s)', func=True)
        return self.x_replayed(nn, True)

    def f_dresult(self, nn):
        return self.x_value(nn, self.dres)

    def x_value(self, nn, v):
        """a function's value computed here, logged as Run does"""
        if isinstance(v, (bytes, bytearray)):
            self.x_out('VB= @%02X "%s"' % (nn, escape(v)))
            return (2, bytes(v))
        self.x_out('VB= @%02X %d' % (nn, v))
        if v > 32767:
            return (0, pack24(v))
        return (1, v)

    def f_picture(self, nn):
        self.expect('(')
        v = self.expr()
        self.expect(')')
        if v[0] == 2:
            rows = []
            p = self.host(bytes(v[1]).decode('latin-1'))
            if not os.path.isfile(p):
                raise self.kerr(FILE_NOT_FOUND)
            for ln in re.split(rb'\r\n?|\n', open(p, 'rb').read()):
                ln = ln[:128]
                if ln and not ln.strip(b'#.') and len(rows) < PROWS:
                    rows.append(ln)
            if not rows:
                raise self.Err(59)
            w = max(len(r) for r in rows)
        else:
            if self.to_int(*v) != 5:
                raise self.Err(5)
            w = self.ditem_n()
            if not 1 <= w <= 128:
                raise self.Err(59)
            h = self.ditem_n()
            if not 1 <= h <= PROWS:
                raise self.Err(59)
            rows = [self.ditem()[:w] for _ in range(h)]
        wc = (w + 7) // 8
        raw = bytearray()
        for r in rows:
            b = bytearray(wc)
            for i, c in enumerate(r[:w]):
                if c == ord('#'):
                    b[i // 8] |= 0x80 >> (i % 8)
            raw += b
        out = bytes([wc, len(rows)]) + compact(bytes(raw))
        if len(out) > 255:
            raise self.Err(14)
        return self.x_value(nn, out)

    def ditem(self):
        if self.dataptr >= len(self.data_index):
            raise self.Err(4)
        at = self.data_index[self.dataptr]
        self.dataptr += 1
        n = self.code[at + 1]
        text = bytes(self.code[at + 2:at + 2 + n]).strip(b' ')
        if text.startswith(b'"'):
            j = text.find(b'"', 1)
            text = text[1:j] if j > 0 else text[1:]
        return text

    def ditem_n(self):
        t = self.ditem().decode('latin-1')
        if not t:
            return 0
        r = self.parse_number(t, True)
        if r is None:
            raise self.Err(13)
        v = self.to_int(*r)
        if not 0 <= v <= 255:
            raise self.Err(59)
        return v

    def f_clipget(self, nn):
        return self.x_replayed(nn, True)

    def f_lof(self, nn):
        h = self.x_spec(nn, '(n)', func=True)[0]
        return self.x_value(nn, self.slot(h).end)

    def f_loc(self, nn):
        h = self.x_spec(nn, '(n)', func=True)[0]
        return self.x_value(nn, self.slot(h).f.tell())

    def f_eof(self, nn):
        h = self.x_spec(nn, '(n)', func=True)[0]
        f = self.slot(h)
        if f.mode == 'w':
            return self.x_value(nn, -1)
        at = f.f.tell()
        c = f.f.read(1)
        f.f.seek(at)
        return self.x_value(nn, 0 if c else -1)

    def f_curdir(self, nn):
        return self.x_value(nn, self.cwd.encode('latin-1'))

    def f_dir(self, nn):
        items = []
        if self.accept('('):
            if not self.accept(')'):
                self.x_str(items)
                self.expect(')')
        self.x_done(items, nn, log=False)
        if self.replay:
            return self.x_replayed(nn, True)
        if items:
            pat = bytes(items[0][1][1]).decode('latin-1')
            d = self.root + self.cwd
            self.listing = sorted(x + ('/' if os.path.isdir(os.path.join(d, x)) else '')
                                  for x in os.listdir(d) if fnmatch.fnmatch(x.lower(), pat.lower()))
        v = self.listing.pop(0) if getattr(self, 'listing', None) else ''
        return self.x_value(nn, v.encode('latin-1'))

    def f_folder(self, nn):
        n = self.x_spec(nn, '(n)', func=True)[0]
        if n not in FOLDERS:
            raise self.Err(5)
        return self.x_value(nn, FOLDERS[n].encode('latin-1'))

    def f_document(self, nn):
        return self.x_value(nn, b'')

    XSTMT2 = {0x86: s_name, 0x96: s_close, 0xA2: s_msgbox, 0xA7: s_dialog, 0xA8: s_enddialog,
              0xAB: s_label, 0xAC: s_field, 0xAD: s_button, 0xB0: s_icon, 0xB1: s_icons, 0xB4: s_tile,
              0xB5: s_bitmap, 0xDB: s_open, 0xDC: s_put, 0xDD: s_seek, 0xE1: s_kill, 0xE3: s_mkdir,
              0xE4: s_rmdir, 0xE5: s_chdir, 0xEB: s_clipboard, 0xEE: s_sprite}
    XFUN2 = {0xA3: f_ask, 0xA4: f_inputbox, 0xA5: f_fileopen, 0xA6: f_filesave, 0xAA: f_dresult,
             0xB6: f_picture, 0xDE: f_lof, 0xDF: f_loc, 0xE0: f_eof, 0xE6: f_curdir, 0xE7: f_dir,
             0xE8: f_folder, 0xE9: f_document, 0xEA: f_clipget}
