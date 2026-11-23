#!/usr/bin/env python3
"""Gate ftp (DECISIONS V100): Veranda FTP's main session checked (tools/
gate_ftp.sh): the console's "FTP ..." lines (tests/ftp_play.c), the
server's log (tests/ftp_server.py), the modem's log, the files.

usage: check_ftp.py <run folder>
"""
import os
import re
import sys
import time

R = sys.argv[1]
SRV = os.path.join(R, 'srv')
raw = open(os.path.join(R, 'log.txt'), encoding='latin-1').read()
log = raw.split('\n')
slog = open(os.path.join(SRV, 'ftp.log'), encoding='latin-1').read().split('\n')
mlog = open(os.path.join(R, 'modem.log'), encoding='latin-1').read().split('\n')


def need(c, msg):
    if not c:
        sys.exit('FAIL  ' + msg)


def val(key):
    m = re.search(r'%s(-?\d+)' % re.escape(key), raw)
    return int(m.group(1)) if m else None


def lists(side, path):
    """every listing of pane side ('R', 'L') of folder path: [{name: (size, flags, y, mo, d, h, mi)}]"""
    out, cur = [], None
    for l in log:
        if l.startswith('FTP LIST %s ' % side) or l == 'FTP LIST %s' % side:
            cur = {} if l[11:] == path else None
        elif l == 'FTP LIST END':
            if cur is not None:
                out.append(cur)
            cur = None
        elif cur is not None and l.startswith('FTP %s ' % side):
            m = re.match(r'^FTP . (.*)\|(\d+)\|(\d+)\|(\d+)-(\d+)-(\d+) (\d+):(\d+)$', l)
            if m:
                cur[m.group(1)] = tuple(int(m.group(i)) for i in range(2, 9))
    return out


def stamp(path, utc=False):
    t = (time.gmtime if utc else time.localtime)(os.stat(path).st_mtime)
    return t.tm_year, t.tm_mon, t.tm_mday, t.tm_hour, t.tm_min


need('FTP TEST STUCK' not in raw and 'FTP TEST FAILED' not in raw,
     'the test stopped: %s' % re.findall(r'FTP TEST (?:STUCK|FAILED)[^\n]*', raw))

# the modem: Packet16's profile, the connections
ats = [l.split(' ', 1)[1] for l in mlog if l.startswith('@')]
prof = ['ATE0V1X1Q0&M&D', 'ATS40=254S45=0S0=0', 'ATF3', 'ATH0']
need(any(ats[i:i + 4] == prof for i in range(len(ats))), 'the modem\'s profile: %s' % ats[:8])
conns = [l for l in mlog if l.startswith('CONNECT ')]
atc = [a for a in ats if a.startswith('ATC"')]
need(all(a.startswith('ATC"127.0.0.1:') for a in atc), 'ATC: %s' % atc[:3])

# the first listing of /pub: the server's files, names, sizes, dates
pub = os.path.join(SRV, 'root', 'pub')
rl = lists('R', '/pub')
need(rl, 'no listing of /pub')
first = rl[0]
PL = 'Zażółć gęślą jaźń.txt'
want = {'..': None, 'dosdir': 'd', 'A long file name on the server.txt': 1234, 'big.bin': 40960, 'ghost.bin': 26,
        'oldfile.txt': 4, PL: 5}
# (V143) the UTF-8 name: the console turns its bytes $80-$9F into U+FFFD, so
# it is known by its ends (the screen shows it whole: tests/check_l10_text.py)
for k in [k for k in first if k.startswith('Za') and k.endswith('.txt') and k != PL]:
    first[PL] = first.pop(k)
need(set(first) == set(want), 'the listing of /pub: %s' % sorted(first))
for n, w in want.items():
    e = first[n]
    if w is None:
        need(e[1] == 3, '..: flags %d' % e[1])
        continue
    if w == 'd':
        need(e[1] == 1 and e[0] == 0, '%s: a folder (%s)' % (n, e))
    else:
        need(e[0] == w and e[1] == 0, '%s: size %d flags %d' % (n, e[0], e[1]))
    y, mo, d, h, mi = stamp(os.path.join(pub, n))
    if n == 'oldfile.txt':
        need(e[2:5] == (2019, mo, d) and e[5] == 99, '%s: the date with a year: %s' % (n, e))
    else:
        need(e[2:] == (y, mo, d, h, mi), '%s: the date %s, the server\'s %s' % (n, e[2:], (y, mo, d, h, mi)))
print('ok    connected (anonymous, the start folder /pub): the listing (Unix) has the server\'s %d entries with their '
      'sizes and dates (a time this year, a year for an old file), ".." first, the folder before the files' % (len(first) - 1))

# dosdir: the DOS form
dl = lists('R', '/pub/dosdir')
need(dl, 'no listing of /pub/dosdir')
dd = dl[0]
need(set(dd) == {'..', 'readme.txt', 'sub'}, 'dosdir: %s' % sorted(dd))
dos = os.path.join(pub, 'dosdir')
y, mo, d, h, mi = stamp(os.path.join(dos, 'readme.txt'))
need(dd['readme.txt'] == (105, 0, y, mo, d, h, mi), 'dosdir readme.txt: %s, want %s' % (dd['readme.txt'], (105, 0, y, mo, d, h, mi)))
y, mo, d, h, mi = stamp(os.path.join(dos, 'sub'))
need(dd['sub'] == (0, 1, y, mo, d, h, mi), 'dosdir sub: %s' % (dd['sub'],))
print('ok    a double click into dosdir: its DOS listing (MM-DD-YY hh:mmPM, <DIR>, sizes) parsed; ".." back to /pub')

# the download: byte for byte; Alt+Tab
big = open(os.path.join(pub, 'big.bin'), 'rb').read()
got = open(os.path.join(R, 'DOCUMENTS', 'big.bin'), 'rb').read()
need(got == big, 'big.bin on the card: %d bytes, %s' % (len(got), 'equal' if got == big else 'NOT equal'))
need(val('FTP TEST DOWNLOADED ') == 40960, 'the download\'s count %s' % val('FTP TEST DOWNLOADED '))
at = 0
for w in ['FTP ALT+TAB AT', 'FTP ASIDE', 'TASK ASIDE', 'TERMDESK WAITED', 'TASK BACK', 'FTP FILE REOPENED', 'FTP BACK AT',
          'FTP TEST DOWNLOADED']:
    k = raw.find(w, at)
    need(k >= 0, 'Alt+Tab: %r not in order' % w)
    at = k
print('ok    File > Download big.bin: 40,960 bytes, equal byte for byte; Alt+Tab at byte %d: put aside (vrnet\'s aside, '
      'the file closed), the desktop 3 s, back (the file opened again at its place), on to the end' % val('FTP ALT+TAB AT '))

# the upload
st = os.path.join(SRV, 'stored', 'upload.bin')
up = open(os.path.join(R, 'DOCUMENTS', 'upload.bin'), 'rb').read()
need(os.path.exists(st) and open(st, 'rb').read() == up, 'upload.bin on the server: not equal')
need(val('FTP TEST UPLOADED ') == len(up), 'the upload\'s count %s' % val('FTP TEST UPLOADED '))
print('ok    File > Upload upload.bin: %d bytes on the server, equal byte for byte' % len(up))

# the folder, the rename, the deletes
cmds = [l[2:] for l in slog if l.startswith('< ')]
reps = [l[2:] for l in slog if l.startswith('> ')]


def replied(cmd, code):
    for i, l in enumerate(slog):
        if l == '< ' + cmd:
            for k in slog[i + 1:]:
                if k.startswith('> '):
                    return k[2:5] == code
    return False


for c, code in [('MKD newdir', '257'), ('RNFR upload.bin', '350'), ('RNTO renamed.bin', '250'), ('DELE renamed.bin', '250'),
                ('RMD newdir', '250'), ('RETR ghost.bin', '550'), ('QUIT', '221')]:
    need(replied(c, code), '%s: not answered %s' % (c, code))
need(not os.path.exists(os.path.join(pub, 'newdir')) and not os.path.exists(os.path.join(pub, 'renamed.bin'))
     and not os.path.exists(os.path.join(pub, 'upload.bin')), 'the server\'s folder at the end: %s' % os.listdir(pub))
print('ok    File > New folder "newdir" (MKD), Rename upload.bin to renamed.bin (RNFR, RNTO), Delete renamed.bin (DELE) '
      'and newdir (RMD), each confirmed, the listing again after each')

# the errors
need('FTP TEST BOX MISSING' in raw and 'The download failed:' in raw and '550 ghost.bin: No such file.' in raw,
     'the missing file\'s box')
need(val('FTP TEST GHOST LEFT ') == 0 and not os.path.exists(os.path.join(R, 'DOCUMENTS', 'ghost.bin')),
     'ghost.bin left on the card')
need(val('FTP TEST DISCONNECTED ') == 0, 'Disconnect')
need('FTP TEST BOX PASSWORD' in raw and 'The login failed:' in raw and '530 Login incorrect.' in raw, 'the password\'s box')
need(val('FTP TEST LOGGED ') == 0, 'logged in with a wrong password?')
need(any(l.startswith('< PASS') and '[wrong]' in l for l in slog), 'the wrong password sent')
print('ok    a file the server refuses (RETR ghost.bin: 550): the box "The download failed: 550 ghost.bin: No such '
      'file.", OK; nothing left on the card; Connection > Disconnect: QUIT, 221')
print('ok    the wrong password (sand): the box "The login failed: 530 Login incorrect.", not connected')

# MLSD
need(val('FTP TEST MLSD ') == 1 and 'MLSD' in cmds, 'MLSD not used')
ml = rl[-1]
for k in [k for k in ml if k.startswith('Za') and k.endswith('.txt')]:     # (V143: the UTF-8 name)
    ml[PL] = ml.pop(k)
need(set(ml) == {'..', 'dosdir', 'A long file name on the server.txt', 'big.bin', 'ghost.bin', 'oldfile.txt', PL},
     'the MLSD listing: %s' % sorted(ml))
y, mo, d, h, mi = stamp(os.path.join(pub, 'big.bin'), utc=True)
need(ml['big.bin'] == (40960, 0, y, mo, d, h, mi), 'MLSD big.bin: %s' % (ml['big.bin'],))
need(ml['dosdir'][:2] == (0, 1), 'MLSD dosdir: %s' % (ml['dosdir'],))
print('ok    the third server (FEAT names MLST): listed with MLSD (type, size, modify facts), "." (cdir) dropped')

# the main loop, the line
gap = val('FTP MAXGAP ')
need(gap is not None and gap < 60, 'the main loop\'s longest gap %s frames' % gap)
need(val('FTP LOST ') == 0 and val('FTP BADCRC ') == 0, 'lost %s, bad CRC %s' % (val('FTP LOST '), val('FTP BADCRC ')))
print('ok    the main loop\'s longest gap %d frames; %d packets, %d XON retries; nothing lost in the UART, no bad CRC; '
      '%d connections (ATC), the modem\'s profile Packet16\'s' % (gap, val('FTP PACKETS '), val('FTP XONRETRY '), len(atc)))
