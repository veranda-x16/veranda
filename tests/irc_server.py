#!/usr/bin/env python3
"""Gate irc (DECISIONS V111): a small IRC server (RFC 1459/2812, as much
as Veranda Chat's test needs) on localhost, with Python's socket module
only.

usage: irc_server.py <folder>   writes <folder>/ready (the port, then a
                                port nothing listens on) and
                                <folder>/irc.log: every line the client
                                sent, as Python's repr of its bytes
                                ("RX b'...'"), and the server's notes

Registration: NICK "veranda" is taken (433); any other nick is welcome
(001-005, LUSERS, a MOTD of three lines). JOIN (several by commas):
the JOIN echoed, the topic (332, 333), the names (353 in two pieces,
366). PART, TOPIC, NICK echoed; WHOIS answered; QUIT: ERROR and the
close. The test drives the rest with lines "GATE <what>" (not IRC):

  ping     PING :gate-ping-1 (the client's PONG is in the log)
  msgs     two messages to #retro from alice: formatting codes (bold,
           colours, italics, reset), UTF-8 (Latin-1 letters, Polish
           letters, curly quotes, an emoji, a combining accent), and a
           Latin-1 line that is not UTF-8
  query    bob writes to us privately
  nicks    in #retro: carol joins, alice parts, bob becomes bobby, dave
           quits, carol gets +o, bobby +v
  mention  carol names us in #retro, erin in #x16
  version  carol sends us a CTCP VERSION (the NOTICE back is in the log)
  flood    400 lines to #x16 from frank
  aside    after 0.3 s, three lines to #retro (the client is put aside)
  close    ERROR :Closing Link ..., then the connection closed
The big session (V178: the user's X16 stopped on Libera's #linux and
EFnet's #freebsd): #big has 2,400 people besides us (Libera's #linux had
2,418: NAMES in 45 lines), #huge 600, each NAMES in 353 lines of up to
512 bytes as a real server sends them, topics of 460 bytes with URLs:
  count    in #big: PART and QUIT of two listed nicks (the client keeps
           the first 190 names: us and the first 189 of NAMES[#big]),
           PART, KICK and QUIT of three it does not keep, JOIN of three
           new ones, then the first of them again
  long     lines past 512 bytes: a PRIVMSG of 700, one with 1,000 bytes
           of IRCv3 tags first, one of 3,000, a TOPIC of 600, a NOTICE
           of 1,200 with formatting, a KICK with nicks of 40, a CTCP PING
           of 600 (the NOTICE back), a MODE of 20 parameters, a 332 of 500
  tabs     JOINs for us to #t1 .. #t5 (the client has room for 4 more
           windows: #t5 is parted), private messages from q1 and q2 (no
           room for their windows)
  storm<n> 600 lines of a busy channel's traffic in #big and #huge
           (random, seeded by n: JOIN, PART, QUIT, NICK, MODE, KICK,
           TOPIC, PRIVMSG, NOTICE, tagged lines, up to 1,200 bytes)
Each ends with a NOTICE from the server "GATE done <what>".
"""
import os
import socket
import sys
import threading
import time

D = sys.argv[1]
LOCK = threading.Lock()
LOG = open(os.path.join(D, 'irc.log'), 'w')
SRV = 'gate.server'


def log(s):
    with LOCK:
        LOG.write(s + '\n')
        LOG.flush()


TOPICS = {'#retro': 'Retro computing: \x02the X16\x02 and friends', '#x16': 'The Commander X16', '#new': ''}
EXTRA = ['user%02d' % i for i in range(1, 31)]
NAMES = {'#retro': ['@alice', 'bob', '+dave'] + EXTRA, '#x16': ['@erin', 'frank'], '#new': []}
BURST = 120                     # (V179) the burst's MOTD lines
# (the big session, V178)
BIGN = {'#big': 2400, '#huge': 600}
TOPICS['#big'] = ('Welcome to #big | Rules: https://example.org/rules/channel-guidelines-for-everyone.html | '
                  'Paste: https://paste.example.net/?lang=c&expire=1d | FAQ https://wiki.example.com/wiki/FAQ#Before_asking '
                  '| No meta-questions, just ask | Be patient: answers can take a while | Logs: '
                  'https://logs.example.org/%23big/2026-11-22/ | Mirror https://mirror.example.net/pub/big/ | '
                  'Off-topic: #big-offtopic | Bots: \x02helper\x02, \x0304quotes\x03 | Have fun and be kind to each other')
TOPICS['#huge'] = TOPICS['#big'].replace('#big', '#huge')


def big_names(n):
    """n nicks of 3 to 16 characters, IRC's odd ones among them ([]\\`^{}|-_),
    every 37th an operator, every 23rd a voice (an LCG: the same each run)"""
    r, out = 7, []
    for i in range(n):
        r = (r * 1103515245 + 12345) & 0x7FFFFFFF
        k = max(3 + r % 14, len('n%d' % i) + 1)       # (each different, IRC's case too)
        nick = ('n%d' % i + 'abc[]\\`^{}|-_xyzqrstuvw'[(r >> 8) % 17:] * 2)[:k]
        out.append(('@' if i % 37 == 0 else '+' if i % 23 == 0 else '') + nick)
    return out


def bare(x):
    return x.lstrip('@+')


for _c, _n in BIGN.items():
    NAMES[_c] = [(x[:len(x) - len(bare(x))] + 'h' + bare(x) if _c == '#huge' else x) for x in big_names(_n)]


class Client:
    def __init__(self, c):
        self.c = c
        self.nick = None
        self.user = None
        self.reg = False
        self.real = ''
        self.buf = b''

    def send(self, s):
        if isinstance(s, str):
            s = s.encode('utf-8')
        self.c.sendall(s + b'\r\n')

    def num(self, n, rest):
        self.send(':%s %03d %s %s' % (SRV, n, self.nick or '*', rest))

    def me(self):
        return '%s!%s@127.0.0.1' % (self.nick, self.user or 'x')

    def done(self, what):
        self.send(':%s NOTICE %s :GATE done %s' % (SRV, self.nick, what))

    def burst(self):
        """(V179) a welcome as Libera's and SDF's send it, in one write: the
        NOTICEs, 001-005 (three 005 lines of 200-260 bytes), 250-266, a
        MOTD of BURST lines (ASCII art with backslashes and backquotes,
        empty lines, URLs), 376, our MODE; the user's X16 lost the link in
        the middle of such a burst (V178's build)"""
        n, h = self.nick, 'burst.example.net'
        out = [':%s NOTICE * :*** Checking Ident' % h, ':%s NOTICE * :*** No Ident response' % h]
        out.append(':%s 001 %s :Welcome to the Burst Internet Relay Chat Network %s' % (h, n, n))
        out.append(':%s 002 %s :Your host is %s[192.0.2.10/6667], running version solanum-1.0-dev' % (h, n, h))
        out.append(':%s 003 %s :This server was created Sat Nov 21 2026 at 20:11:30 UTC' % (h, n))
        out.append(':%s 004 %s %s solanum-1.0-dev BDGIMQRSZaghiopsuwz BCFILMPQRSTbcefgijklmnopqrstuvz bkloveqjfI' % (h, n, h))
        for k in range(3):
            out.append((':%s 005 %s ' % (h, n) + ' '.join('TOKEN%d%d=%s' % (k, i, 'v' * (i % 7)) for i in range(26)))[:250]
                       + ' :are supported by this server')
        for num, t in ((251, ':There are 55 users and 29747 invisible on 30 servers'), (252, '30 :IRC Operators online'),
                       (253, '65 :unknown connection(s)'), (254, '22171 :channels formed'),
                       (255, ':I have 2395 clients and 1 servers'), (265, '2395 2560 :Current local users 2395, max 2560'),
                       (266, '30158 32146 :Current global users 30158, max 32146'),
                       (250, ':Highest connection count: 2561 (2560 clients) (98731 connections received)')):
            out.append(':%s %03d %s %s' % (h, num, n, t))
        out.append(':%s 375 %s :- %s Message of the Day - ' % (h, n, h))
        art = ['                 _                  _____              ',
               '                (_)_______  ___ ___/ / _/___  _______ _',
               "               / / __/ __/ (_-</ _  / _// _ \\/ __/ _ `/",
               '              /_/_/  \\__(_)___/\\_,_/_/(_)___/_/  \\_, / ']
        for i in range(BURST):
            t = art[i % 4] if i % 10 < 4 else ' ' if i % 10 == 4 else \
                'Line %03d of the message of the day: https://example.org/policies/%03d -- be kind' % (i, i)
            out.append(':%s 372 %s :%s' % (h, n, t))
        out.append(':%s 376 %s :End of /MOTD command.' % (h, n))
        out.append(':%s MODE %s :+iw' % (n, n))
        return out

    def welcome(self):
        self.reg = True
        if 'burst' in self.real:        # (V179: a big network's welcome, all at once)
            self.c.sendall(b''.join(x.encode('latin-1') + b'\r\n' for x in self.burst()))
            return
        self.num(1, ':Welcome to the Gate IRC network %s' % self.me())
        self.num(2, ':Your host is %s, running gate-1.0' % SRV)
        self.num(3, ':This server was created today')
        self.num(4, '%s gate-1.0 iow ovbkl' % SRV)
        self.num(5, 'PREFIX=(ov)@+ CHANTYPES=# NICKLEN=16 :are supported by this server')
        self.num(251, ':There are 9 users on 1 server')
        self.num(375, ':- %s Message of the Day -' % SRV)
        self.num(372, ':- Welcome to the gate\'s server.')
        self.num(372, ':- Be kind; this is only a test.')
        self.num(376, ':End of /MOTD command.')

    def join(self, ch):
        self.send(':%s JOIN %s' % (self.me(), ch))
        if TOPICS.get(ch):
            self.num(332, '%s :%s' % (ch, TOPICS[ch]))
            self.num(333, '%s alice 1700000000' % ch)
        names = [self.nick] + NAMES.get(ch, [])
        if ch in BIGN:                  # (lines of 512 bytes at most, as a real server's)
            head = ':%s 353 %s = %s :' % (SRV, self.nick, ch)
            l = ''
            for x in names:
                if len(head) + len(l) + len(x) + 3 > 512:
                    self.send(head + l)
                    l = ''
                l += (' ' if l else '') + x
            if l:
                self.send(head + l)
        else:
            half = len(names) // 2 or 1
            self.num(353, '= %s :%s' % (ch, ' '.join(names[:half])))
            if names[half:]:
                self.num(353, '= %s :%s' % (ch, ' '.join(names[half:])))
        self.num(366, '%s :End of /NAMES list.' % ch)

    def gate(self, what):
        n = self.nick
        if what == 'ping':
            self.send('PING :gate-ping-1')
        elif what == 'msgs':
            self.send(b':alice!a@host PRIVMSG #retro :Hello \x02bold\x02 \x0304,01red\x03 and \x1ditalic\x1d \x0fdone')
            self.send(b':alice!a@host PRIVMSG #retro :caf\xc3\xa9 \xc5\x82\xc3\xb3d\xc5\xba \xe2\x80\x9cquoted\xe2\x80\x9d '
                      b'\xf0\x9f\x98\x80 na\xc3\xafve e\xcc\x81')
            self.send(b':alice!a@host PRIVMSG #retro :Latin-1: \xe9t\xe9')
            self.send(':alice!a@host PRIVMSG #retro :Zażółć gęślą jaźń')      # (V143: Polish)
            self.send(':alice!a@host PRIVMSG #retro :ZAŻÓŁĆ GĘŚLĄ JAŹŃ')
        elif what == 'query':
            self.send(':bob!b@host PRIVMSG %s :Hi there, privately' % n)
        elif what == 'nicks':
            self.send(':carol!c@host JOIN #retro')
            self.send(':alice!a@host PART #retro :bye')
            self.send(':bob!b@host NICK :bobby')
            self.send(':dave!d@host QUIT :gone')
            self.send(':alice!a@host MODE #retro +ov carol bobby')
        elif what == 'mention':
            self.send(':carol!c@host PRIVMSG #retro :%s: are you there?' % n)
            self.send(':erin!e@host PRIVMSG #x16 :ping %s, the X16 is here' % n)
        elif what == 'version':
            self.send(':carol!c@host PRIVMSG %s :\x01VERSION\x01' % n)
        elif what == 'flood':
            for i in range(1, 401):
                self.send(':frank!f@host PRIVMSG #x16 :Flood line %03d: the quick brown fox jumps over the lazy dog' % i)
        elif what == 'aside':
            time.sleep(0.3)
            for i in range(1, 4):
                self.send(':alice!a@host PRIVMSG #retro :While you were away %d' % i)
        elif what == 'count':           # (the big session: #big's people counted)
            b = [bare(x) for x in NAMES['#big']]
            self.send(':%s!u@h PART #big :listed' % b[0])
            self.send(':%s!u@h QUIT :listed' % b[1])
            self.send(':%s!u@h PART #big :not listed' % b[-1])
            self.send(':ChanServ!u@h KICK #big %s :not listed' % b[-2])
            self.send(':%s!u@h QUIT :not listed' % b[-3])
            for x in ('gatejoin1', 'gatejoin2', 'gatejoin3', 'gatejoin1'):
                self.send(':%s!u@h JOIN #big' % x)
        elif what == 'long':            # (lines past 512 bytes, cut by the client)
            self.send(':alice!a@host PRIVMSG #big :%s' % ('long700 ' * 88)[:700])
            self.send('@time=2026-11-22T10:00:00.000Z;msgid=%s;+draft/x=y :bob!b@host PRIVMSG #big :after the tags'
                      % ('t' * 1000))
            self.send(':carol!c@host PRIVMSG #big :%s' % ('w3000 ' * 500))
            self.send(':dave!d@host PRIVMSG #big :the next line is whole')
            self.send(':erin!e@host TOPIC #huge :%s' % ('https://example.org/topic/%03d ' % 1 * 40)[:600])
            self.send(':frank!f@host NOTICE #big :\x02\x0304,01%s\x0f' % ('n' * 1200))
            self.send(':%s!k@host KICK #big %s :%s' % ('K' * 40, 'V' * 40, 'r' * 300))
            self.send(':gail!g@host PRIVMSG %s :\x01PING %s\x01' % (n, 'p' * 600))
            self.send(':ChanServ!c@host MODE #big +ooooovvvvvbbbbbeeeee %s' % ' '.join('m%d' % i for i in range(20)))
            self.num(332, '#huge :%s' % ('Topic 500 ' * 50))
        elif what == 'tabs':            # (more windows than the client has)
            for i in range(1, 6):
                self.send(':%s JOIN #t%d' % (self.me(), i))
                self.num(366, '#t%d :End of /NAMES list.' % i)
            self.send(':q1!q@host PRIVMSG %s :first private, no room' % n)
            self.send(':q2!q@host PRIVMSG %s :second private, no room' % n)
        elif what.startswith('storm'):  # (a busy channel's traffic, random but the same each run)
            import random
            rnd = random.Random(int(what[5:] or 1))
            pool = [bare(x) for x in NAMES['#big']]
            for i in range(600):
                ch = rnd.choice(['#big', '#huge'])
                a = rnd.choice(pool)
                k = rnd.randrange(10)
                if k == 0:
                    b = 'new%d%s' % (i, 'x' * rnd.randrange(30))
                    self.send(':%s!u@h JOIN %s' % (b, ch))
                    pool.append(b)
                elif k == 1:
                    self.send(':%s!u@h PART %s :%s' % (a, ch, 'bye ' * rnd.randrange(150)))
                elif k == 2:
                    self.send(':%s!u@h QUIT :%s' % (a, 'Quit: ' + 'z' * rnd.randrange(600)))
                elif k == 3:
                    b = 'nn%d%s' % (i, 'y' * rnd.randrange(25))
                    self.send(':%s!u@h NICK :%s' % (a, b))
                    pool.append(b)
                elif k == 4:
                    self.send(':ChanServ!u@h MODE %s %s %s %s %s' % (ch, rnd.choice(['+o', '-o', '+v', '-v', '+ov', '-ov+o']),
                                                                    a, rnd.choice(pool), rnd.choice(pool)))
                elif k == 5:
                    self.send(':%s!u@h PRIVMSG %s :%s' % (a, ch, ('word%d ' % i) * rnd.randrange(1, 200)))
                elif k == 6:
                    self.send('@time=2026-11-22T10:00:00.000Z;msgid=%s :%s!u@h PRIVMSG %s :tagged %d' % ('m' * rnd.randrange(900), a, ch, i))
                elif k == 7:
                    self.send(':%s!u@h KICK %s %s :%s' % (a, ch, rnd.choice(pool), 'k' * rnd.randrange(400)))
                elif k == 8:
                    self.send(':%s!u@h TOPIC %s :%s' % (a, ch, 'https://example.org/%d/' % i * rnd.randrange(1, 40)))
                else:
                    self.send(':%s!u@h NOTICE %s :%s' % (a, ch, '\x02\x0304,01' + 'n' * rnd.randrange(1200)))
        elif what == 'close':
            self.send('ERROR :Closing Link: %s (Gate is closing)' % n)
            time.sleep(0.2)
            raise EOFError
        self.done(what)

    def line(self, raw):
        log('RX ' + repr(raw))
        s = raw.decode('utf-8', 'replace')
        if s.startswith('GATE '):
            self.gate(s[5:])
            return
        w = s.split(' ')
        cmd = w[0].upper()
        if cmd == 'NICK':
            new = w[1].lstrip(':')
            if new == 'veranda':
                self.send(':%s 433 %s %s :Nickname is already in use' % (SRV, self.nick or '*', new))
                return
            if self.reg:
                self.send(':%s NICK :%s' % (self.me(), new))
                self.nick = new
                return
            self.nick = new
            if self.user:
                self.welcome()
        elif cmd == 'USER':
            self.user = w[1]
            self.real = s.split(' :', 1)[1] if ' :' in s else ''
            if self.nick and not self.reg:
                self.welcome()
        elif cmd == 'JOIN':
            for ch in w[1].split(','):
                self.join(ch)
        elif cmd == 'PART' and w[1].startswith('#t'):
            pass                        # (the tabs: the client parts the one it has no room for)
        elif cmd == 'PART':
            self.send(':%s %s' % (self.me(), s))
        elif cmd == 'TOPIC' and ' :' in s:
            self.send(':%s %s' % (self.me(), s))
        elif cmd == 'WHOIS':
            self.num(311, '%s c host * :Carol' % w[1])
            self.num(318, '%s :End of /WHOIS list.' % w[1])
        elif cmd == 'QUIT':
            self.send('ERROR :Closing Link: %s (Quit)' % self.nick)
            raise EOFError

    def run(self):
        try:
            self.c.settimeout(600)
            while True:
                k = self.c.recv(4096)
                if not k:
                    break
                self.buf += k
                while b'\n' in self.buf:
                    l, self.buf = self.buf.split(b'\n', 1)
                    self.line(l.rstrip(b'\r'))
        except (OSError, EOFError) as e:
            log('END ' + type(e).__name__)
        finally:
            try:
                self.c.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            self.c.close()
            log('CLOSED')


def main():
    s = socket.socket()
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(('127.0.0.1', 0))
    s.listen(4)
    port = s.getsockname()[1]
    t = socket.socket()
    t.bind(('127.0.0.1', 0))
    closed = t.getsockname()[1]
    t.close()
    open(os.path.join(D, 'ready.tmp'), 'w').write('%d %d\n' % (port, closed))
    os.rename(os.path.join(D, 'ready.tmp'), os.path.join(D, 'ready'))
    while True:
        c, _ = s.accept()
        log('CONNECT')
        threading.Thread(target=Client(c).run, daemon=True).start()


main()
