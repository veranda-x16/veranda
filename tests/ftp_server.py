#!/usr/bin/env python3
"""Gate ftp (DECISIONS V100): a small FTP server on localhost for Veranda
FTP's test build, with Python's socket module only (no pyftpdlib).

usage: ftp_server.py <folder>      the folder's root/ is the server's /;
                                   writes <folder>/ready (the port),
                                   <folder>/ftp.log (every command) and
                                   <folder>/stored/ (a copy of each file
                                   stored)

What it does, as real servers do (RFC 959, 3659):
  - USER/PASS: "anonymous" (any password) and "sand" / "secret"; anything
    else 530 (after PASS); user "mlsd" (any password) is "sand" too but
    its FEAT names MLSD (the client then lists with MLSD);
  - SYST, FEAT, TYPE (A, I), PWD, CWD, CDUP, PASV (227 with 127,0,0,1),
    LIST (Unix "ls -l"; a folder whose name starts with "dos": DOS/IIS
    lines), MLSD, RETR, STOR, MKD, RMD, DELE, RNFR, RNTO, NOOP, QUIT;
  - a 150 before the data, 226 after it; the banner 220 is multi-line
    ("220-" lines then "220 "), the FEAT reply too;
  - replies sent in one piece (Packet16's D38: CR and LF together).
"""
import os
import socket
import sys
import threading
import time

ROOT = None
LOG = None
LOCK = threading.Lock()
MONTHS = 'Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec'.split()


def log(s):
    with LOCK:
        LOG.write(s + '\n')
        LOG.flush()


def real(cwd, name):
    """the host path of a name relative to cwd ("/a/b"), kept inside ROOT"""
    p = name if name.startswith('/') else cwd.rstrip('/') + '/' + name
    parts = []
    for c in p.split('/'):
        if c in ('', '.'):
            continue
        if c == '..':
            if parts:
                parts.pop()
            continue
        parts.append(c)
    return '/' + '/'.join(parts), os.path.join(ROOT, *parts)


def unix_line(path, name):
    st = os.stat(path)
    d = os.path.isdir(path)
    t = time.localtime(st.st_mtime)
    when = '%s %2d %02d:%02d' % (MONTHS[t.tm_mon - 1], t.tm_mday, t.tm_hour, t.tm_min)
    if name.startswith('old'):
        when = '%s %2d  %4d' % (MONTHS[t.tm_mon - 1], t.tm_mday, 2019)
    return '%s 1 ftp ftp %12d %s %s' % ('drwxr-xr-x' if d else '-rw-r--r--', 0 if d else st.st_size, when, name)


def dos_line(path, name):
    st = os.stat(path)
    t = time.localtime(st.st_mtime)
    h = t.tm_hour % 12 or 12
    stamp = '%02d-%02d-%02d  %02d:%02d%s' % (t.tm_mon, t.tm_mday, t.tm_year % 100, h, t.tm_min, 'PM' if t.tm_hour >= 12 else 'AM')
    if os.path.isdir(path):
        return '%s       <DIR>          %s' % (stamp, name)
    return '%s %20d %s' % (stamp, st.st_size, name)


def mlsd_line(path, name):
    st = os.stat(path)
    t = time.gmtime(st.st_mtime)
    facts = 'type=%s;' % ('dir' if os.path.isdir(path) else 'file')
    if not os.path.isdir(path):
        facts += 'size=%d;' % st.st_size
    facts += 'modify=%04d%02d%02d%02d%02d%02d;perm=adfrw;unix.mode=0644;unique=fd01g%x;' % (
        t.tm_year, t.tm_mon, t.tm_mday, t.tm_hour, t.tm_min, t.tm_sec, st.st_ino)
    return facts + ' ' + name


class Session(threading.Thread):
    def __init__(self, conn):
        super().__init__(daemon=True)
        self.c = conn
        self.cwd = '/'
        self.user = None
        self.ok = False
        self.mlsd = False
        self.pasv = None
        self.rnfr = None

    def send(self, s):
        log('> ' + s.replace('\r\n', ' | '))
        self.c.sendall(s.encode('latin-1') + b'\r\n')

    def data(self):
        if not self.pasv:
            return None
        self.pasv.settimeout(20)
        try:
            d, _ = self.pasv.accept()
        except OSError:
            d = None
        self.pasv.close()
        self.pasv = None
        return d

    def run(self):
        self.send('220-Veranda gate FTP server\r\n220-(tests/ftp_server.py)\r\n220 Ready.')
        buf = b''
        while True:
            try:
                b = self.c.recv(4096)
            except OSError:
                break
            if not b:
                break
            buf += b
            while b'\n' in buf:
                ln, buf = buf.split(b'\n', 1)
                line = ln.rstrip(b'\r').decode('latin-1')
                if not self.command(line):
                    self.c.close()
                    return
        self.c.close()
        log('CLOSED')

    def command(self, line):
        verb, _, arg = line.partition(' ')
        verb = verb.upper()
        log('< ' + (line if verb != 'PASS' else 'PASS ' + '*' * len(arg)) + ('  [%s]' % arg if verb == 'PASS' else ''))
        if verb == 'USER':
            self.user = arg
            self.ok = False
            self.send('331 Password, please.')
        elif verb == 'PASS':
            if self.user == 'anonymous' or (self.user == 'sand' and arg == 'secret') or self.user == 'mlsd':
                self.ok = True
                self.mlsd = self.user == 'mlsd'
                self.send('230 Logged in.')
            else:
                self.send('530 Login incorrect.')
        elif verb == 'QUIT':
            self.send('221 Goodbye.')
            return False
        elif not self.ok:
            self.send('530 Please log in first.')
        elif verb == 'SYST':
            self.send('215 UNIX Type: L8')
        elif verb == 'FEAT':
            self.send('211-Features:\r\n SIZE\r\n UTF8\r\n' + (' MLST type*;size*;modify*;\r\n' if self.mlsd else '') + '211 End')
        elif verb == 'TYPE':
            self.send('200 Type set to %s.' % arg)
        elif verb == 'NOOP':
            self.send('200 NOOP ok.')
        elif verb == 'PWD':
            self.send('257 "%s" is the current directory.' % self.cwd)
        elif verb in ('CWD', 'CDUP'):
            v, p = real(self.cwd, '..' if verb == 'CDUP' else arg)
            if os.path.isdir(p):
                self.cwd = v
                self.send('250 Directory changed to %s.' % v)
            else:
                self.send('550 %s: No such directory.' % arg)
        elif verb == 'PASV':
            if self.pasv:
                self.pasv.close()
            s = socket.socket()
            s.bind(('127.0.0.1', 0))
            s.listen(1)
            self.pasv = s
            port = s.getsockname()[1]
            self.send('227 Entering Passive Mode (127,0,0,1,%d,%d).' % (port >> 8, port & 255))
        elif verb in ('LIST', 'NLST', 'MLSD'):
            v, p = real(self.cwd, arg if arg and not arg.startswith('-') else '.')
            if not os.path.isdir(p):
                self.send('550 No such directory.')
                return True
            dos = os.path.basename(v).startswith('dos')
            names = sorted(os.listdir(p))
            if verb == 'MLSD':
                lines = [mlsd_line(p, '.').replace('type=dir', 'type=cdir', 1)] + [mlsd_line(os.path.join(p, n), n) for n in names]
            elif dos:
                lines = [dos_line(os.path.join(p, n), n) for n in names]
            else:
                lines = ['total %d' % len(names)] + [unix_line(os.path.join(p, n), n) for n in names]
            self.send('150 Here comes the listing.')
            d = self.data()
            if not d:
                self.send('425 No data connection.')
                return True
            d.sendall(''.join(l + '\r\n' for l in lines).encode('utf-8'))     # (V143: names in UTF-8)
            d.close()
            self.send('226 Listing sent.')
        elif verb == 'RETR':
            v, p = real(self.cwd, arg)
            if not os.path.isfile(p) or os.path.basename(p).startswith('ghost'):
                if self.pasv:
                    self.pasv.close()
                    self.pasv = None
                self.send('550 %s: No such file.' % arg)
                return True
            self.send('150 Opening BINARY mode data connection for %s (%d bytes).' % (arg, os.path.getsize(p)))
            d = self.data()
            if not d:
                self.send('425 No data connection.')
                return True
            with open(p, 'rb') as f:
                d.sendall(f.read())
            d.close()
            self.send('226 Transfer complete.')
        elif verb == 'STOR':
            v, p = real(self.cwd, arg)
            self.send('150 Ok to send data.')
            d = self.data()
            if not d:
                self.send('425 No data connection.')
                return True
            got = b''
            d.settimeout(60)
            while True:
                try:
                    b = d.recv(65536)
                except OSError:
                    break
                if not b:
                    break
                got += b
            d.close()
            with open(p, 'wb') as f:
                f.write(got)
            os.makedirs(os.path.join(os.path.dirname(ROOT), 'stored'), exist_ok=True)
            with open(os.path.join(os.path.dirname(ROOT), 'stored', os.path.basename(p)), 'wb') as f:
                f.write(got)              # (a copy the gate compares: the file is renamed and deleted later)
            log('STORED %s %d' % (v, len(got)))
            self.send('226 Transfer complete (%d bytes).' % len(got))
        elif verb == 'MKD':
            v, p = real(self.cwd, arg)
            try:
                os.mkdir(p)
                self.send('257 "%s" created.' % v)
            except OSError:
                self.send('550 Cannot make %s.' % arg)
        elif verb == 'RMD':
            v, p = real(self.cwd, arg)
            try:
                os.rmdir(p)
                self.send('250 Removed %s.' % v)
            except OSError:
                self.send('550 Cannot remove %s.' % arg)
        elif verb == 'DELE':
            v, p = real(self.cwd, arg)
            if os.path.isfile(p):
                os.remove(p)
                self.send('250 Deleted %s.' % v)
            else:
                self.send('550 %s: No such file.' % arg)
        elif verb == 'RNFR':
            v, p = real(self.cwd, arg)
            if os.path.exists(p):
                self.rnfr = p
                self.send('350 Ready for RNTO.')
            else:
                self.send('550 %s: No such file.' % arg)
        elif verb == 'RNTO':
            v, p = real(self.cwd, arg)
            if self.rnfr:
                os.rename(self.rnfr, p)
                self.rnfr = None
                self.send('250 Renamed.')
            else:
                self.send('503 RNFR first.')
        elif verb == 'SIZE':
            v, p = real(self.cwd, arg)
            self.send('213 %d' % os.path.getsize(p) if os.path.isfile(p) else '550 No such file.')
        else:
            self.send('502 %s not implemented.' % verb)
        return True


def main():
    global ROOT, LOG
    d = sys.argv[1]
    ROOT = os.path.join(d, 'root')
    LOG = open(os.path.join(d, 'ftp.log'), 'w')
    s = socket.socket()
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(('127.0.0.1', 0))
    s.listen(4)
    with open(os.path.join(d, 'ready.tmp'), 'w') as f:
        f.write('%d\n' % s.getsockname()[1])
    os.rename(os.path.join(d, 'ready.tmp'), os.path.join(d, 'ready'))
    while True:
        c, a = s.accept()
        log('CONNECT %s:%d' % a)
        Session(c).start()


if __name__ == '__main__':
    main()
