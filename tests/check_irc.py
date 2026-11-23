#!/usr/bin/env python3
"""Gate irc (DECISIONS V111): Veranda Chat's sessions checked (tools/
gate_irc.sh): the console's "IR ..." lines (tests/irc_play.c and the test
build's own: every line a window got, "IR LINE <window> <kind> <text>"),
the server's log (tests/irc_server.py: every line the client sent, exact),
the files on the card.

usage: check_irc.py <session> <run folder> <port>
"""
import ast
import os
import re
import sys

SESS, R, PORT = sys.argv[1], sys.argv[2], int(sys.argv[3])
raw = open(os.path.join(R, 'log.txt'), encoding='utf-8', errors='replace').read()   # (the console: bytes as Latin-1, in UTF-8)
log = raw.split('\n')


def need(c, msg):
    if not c:
        sys.exit('FAIL  ' + msg)


def ok(msg):
    print('ok    ' + msg)


def val(key):
    m = re.findall(r'^%s(-?\d+)$' % re.escape(key), raw, re.M)
    return [int(x) for x in m]


def vals(key):
    return [l[l.index(key) + len(key):] for l in log if key in l and not l.endswith('IR SERVERS SHOWN')]   # (DOS's output may come first)


def boxes():
    return [l[7:] for l in log if l.startswith('IR BOX ')]


LINES = []
for l in log:
    m = re.match(r'^IR LINE (\S+) (\d) (.*)$', l)
    if m:
        LINES.append((m.group(1), int(m.group(2)), m.group(3)))

need('IR TEST STUCK' not in raw and 'IR TEST FAILED' not in raw,
     'the test stopped: %s' % re.findall(r'IR TEST (?:STUCK|FAILED)[^\n]*', raw))
need('IR END' in log, 'no end')

if SESS == 'nomodem':
    need(any(b.startswith('The modem does not answer.|') for b in boxes()), 'no modem: the boxes %s' % boxes())
    ok('no modem on the port: Connect, the box "The modem does not answer." (vrnet: NET_ENOMODEM)')
    sys.exit(0)

if SESS == 'closedport':
    need('Could not connect to 127.0.0.1|(refused, or no such host)' in boxes(), 'the refused box: %s' % boxes())
    ok('a server on a port nothing listens on: Connect, the box "Could not connect to 127.0.0.1 (refused, or no '
       'such host)"')
    sys.exit(0)

RX = [ast.literal_eval(l[3:]) for l in open(os.path.join(R, 'srv', 'irc.log'), encoding='latin-1').read().split('\n')
      if l.startswith('RX ')]
IRC = [x for x in RX if not x.startswith(b'GATE ')]
mlog = open(os.path.join(R, 'modem.log'), encoding='latin-1').read().split('\n')
atc = [l.split(' ', 1)[1] for l in mlog if l.startswith('@') and ' ATC"' in l]
need(atc and all(a == 'ATC"127.0.0.1:%d"' % PORT for a in atc), 'ATC: %s' % atc)


def tabs():
    return [l[8:].split() for l in log if l.startswith('IR TABS ')]


if SESS == 'welcome':                   # (V179: the link dropped in a big welcome on the user's X16)
    need(IRC[:3] == [b'NICK veranda', b'USER veranda 0 * :Gate burst', b'NICK verandax'] and IRC[3] == b'JOIN #retro',
         'the registration: %s' % IRC[:5])
    star = [t for w, a, t in LINES if w == '*']
    motd = [t for t in star if t.startswith('Line ') and 'of the message of the day' in t]
    need(len(motd) == 120 - 120 // 10 * 5 and motd[-1].startswith('Line 119 '), 'the MOTD: %d lines' % len(motd))
    for want in ('Welcome to the Burst Internet Relay Chat Network verandax', '2395 2560 Current local users 2395, max 2560',
                 'Highest connection count: 2561 (2560 clients) (98731 connections received)', 'End of /MOTD command.',
                 '-- Your modes: +iw '):
        need(want in star, 'missing %r' % want)
    need(not boxes() and not any('Disconnected' in t for t in star), 'the link dropped: %s' % boxes())
    T = tabs()
    need(T and T[-1] == ['*', '#retro<'], 'the tabs: %s' % T)
    lost, oe, bad, xr = val('IR LOST ')[0], val('IR OE ')[0], val('IR BADCRC ')[0], val('IR XONRETRY ')[0]
    need(lost == 0 and oe == 0 and bad == 0, 'lost %s, overruns %s, bad CRC %s' % (lost, oe, bad))
    ok('a welcome of 140 lines (13.7 KB: NOTICEs, 001-005, 250-266, a MOTD of 120 lines) written at once, the modem '
       'at 115200: every line shown (%d lines in), #retro joined after it; %d packets, %d XON retries, nothing lost '
       'in the UART, no bad CRC' % (val('IR TEST RX LINES ')[0], val('IR PACKETS ')[0], xr))
    sys.exit(0)

if SESS == 'big':                       # (V178: the user's X16 stopped after joining Libera's #linux, EFnet's #freebsd)
    def people(name):
        return [tuple(int(x) for x in l.split()[4:6]) for l in log if l.startswith('IR TEST PEOPLE %s ' % name)]

    def status():
        return list(zip(vals('IR TEST STATUS '), vals('IR TEST SHOWN ')))

    need(IRC[:3] == [b'NICK veranda', b'USER veranda 0 * :Gate tester', b'NICK verandax']
         and IRC[3] == b'JOIN #big,#huge', 'the registration: %s' % IRC[:5])
    pb, ph = people('#big'), people('#huge')
    need(pb[0] == (2401, 190) and ph[0] == (601, 190), 'the people after NAMES: %s %s' % (pb, ph))
    need(('#big', 2, '-- 2401 people here (the list shows 190)') in LINES
         and ('#huge', 2, '-- 601 people here (the list shows 190)') in LINES, 'the 366 lines')
    st = status()
    need(st[0][0] == '%d people, as verandax' % {'#big': 2401, '#huge': 601}[st[0][1]], 'the status bar: %s' % st)
    jf = val('IR TEST JOIN FRAMES ')[0]
    need(jf < 2400, 'the NAMES of 3,000 people took %d frames' % jf)
    ok('#big (2,400 people and us) and #huge (600 and us; nicks of 17 characters kept as 16) joined, their NAMES '
       'in 353 lines of up to 512 bytes, while the hands clicked the tabs and the list: 190 nicks kept each, 2401 '
       'and 601 people counted, "-- 2401 people here (the list shows 190)"; the status bar "%s" for %s (was "0 '
       'people": not drawn again after the names came); from Return to the last 366 %d frames (%.1f s)'
       % (st[0][0], st[0][1], jf, jf / 60.0))
    tl = val('IR TEST TOPIC LEN ')[0]
    tt = vals('IR TEST TOPICTEXT ')[0]
    need(tl == 399 and tt.startswith('Welcome to #big | Rules: https://example.org/rules/'), 'the topic: %d %r' % (tl, tt))
    tp = [t for w, a, t in LINES if w == '#big' and t.startswith('-- Topic: Welcome to #big')]
    need(len(tp) == 1, 'the topic line: %s' % tp)       # (the console's lines stop at 128 bytes)
    ok('the topic of 453 bytes (URLs, bold, a colour): kept cut to 399 bytes (TOPICMAX 400), shown in the text')

    need(pb[1] == (2400, 190), 'the people after PART, QUIT, KICK, JOIN: %s' % (pb,))
    nb = [l[8:] for l in log if l.startswith('IR NICK ')]
    nb = ('#big' if 'IR NICKS #big' in log else '', nb)
    need(nb[0] == '#big' and len(nb[1]) == 190 and ' gatejoin1' in nb[1] and ' gatejoin2' in nb[1]
         and ' gatejoin3' not in nb[1] and not any(x[1:].startswith(('n0yzq', 'n1{}')) for x in nb[1]),
         'the list after them: %s' % (nb,))
    ok('#big counted: PART and QUIT of 2 nicks in the list (2399, 188 kept), PART and KICK of 2 not in it (2397), '
       'QUIT of one not in it (not known to be in #big: 2397), JOIN of 3 new (gatejoin1 and 2 kept, 3 counted: '
       '2400), gatejoin1 again (in the list: not counted): 2400 people, 190 kept')

    cut = [t for w, a, t in LINES if w == '#big' and t.startswith('<alice> long700')]
    need(len(cut) == 1 and len(cut[0]) <= 519, 'the 700-byte line: %s' % [len(x) for x in cut])
    need(('#big', 0, '<bob> after the tags') in LINES, 'the tagged line')
    w3 = [t for w, a, t in LINES if w == '#big' and t.startswith('<carol> w3000')]
    need(len(w3) == 1 and len(w3[0]) <= 519, 'the 3000-byte line: %s' % [len(x) for x in w3])
    need(('#big', 0, '<dave> the next line is whole') in LINES, 'the line after it')
    need(val('IR TEST TOPIC2 LEN ')[0] == 399, 'the long topic: %s' % val('IR TEST TOPIC2 LEN '))
    kk = [t for w, a, t in LINES if w == '#big' and t.startswith('<-- VVVV')]
    need(len(kk) == 1 and ' was kicked by KKKK' in kk[0], 'the KICK: %s' % kk)
    pg = [x for x in IRC if x.startswith(b'NOTICE gail :\x01PING ')]
    need(len(pg) == 1 and len(pg[0]) + 2 <= 512 and pg[0].endswith(b'\x01'), 'the PING answer: %s' % [len(x) for x in pg])
    need(any(w == '#big' and t.startswith('-- ChanServ sets mode +ooooovvvvvbbbbbeeeee m0 m1') for w, a, t in LINES),
         'the MODE of 20 parameters')
    mx = val('IR TEST SB MAXLEN ')[0]
    need(480 <= mx <= 519, 'the longest line kept: %d' % mx)
    ok('lines past 512 bytes: a PRIVMSG of 700 and one of 3,000 cut where rx (520) ends (the longest line kept %d characters), the next line whole; '
       '1,000 bytes of IRCv3 tags before a PRIVMSG left out as they came (the line whole); a TOPIC of 600 kept as '
       '399; a NOTICE of 1,200; a KICK with nicks of 40 (its line cut to 80: was 5 bytes past it); a CTCP PING of '
       '600 answered in %d bytes (was 552 into obuf\'s 520); a MODE of 20 parameters'
       % (mx, len(pg[0]) + 2))

    T = tabs()
    need(T[-1][:7] == ['*+', '#big', '#huge', '#t1', '#t2', '#t3', '#t4<'] or T[-1][:7] == ['*', '#big', '#huge', '#t1', '#t2', '#t3', '#t4<'],
         'the tabs: %s' % T)
    need(b'PART #t5' in IRC and ('*', 4, '-- No room for another window: leaving #t5') in LINES, 'no room: PART #t5')
    need(('*', 0, '<q1> first private, no room') in LINES and ('*', 0, '<q2> second private, no room') in LINES,
         'the private messages without a window: %s' % [x for x in LINES if 'private' in x[2]])
    ok('more windows than there is room for: #t1-#t4 joined (7 tabs), #t5 parted ("No room for another '
       'window"), private messages from q1 and q2 in the server\'s window')

    need(st[1] == ('2399 people, as verandax', '#big'), 'the status at the list\'s end: %s' % st)
    ok('#big\'s list scrolled to its end: the last row "and 2209 more" (NICKEND.png), the status "2399 people" '
       '(the KICK of a nick of 40 not in the list counted out)')

    need(people('#big')[-1][1] <= 190 and people('#big')[-1][0] >= people('#big')[-1][1]
         and people('#huge')[-1][1] <= 190 and people('#huge')[-1][0] >= people('#huge')[-1][1],
         'after the storm: %s %s' % (people('#big'), people('#huge')))
    need(st[-1] == ('%d people, as verandax' % people('#big')[-1][0], '#big'), 'the status after the storm: %s' % st)
    gap, lost, bad = val('IR MAXGAP ')[0], val('IR LOST ')[0], val('IR BADCRC ')[0]
    need(lost == 0 and bad == 0, 'lost %s, bad CRC %s' % (lost, bad))
    need(gap < 120, 'the main loop\'s longest gap: %s frames' % gap)
    ok('600 lines of a busy channel (JOIN, PART, QUIT, NICK, MODE, KICK, TOPIC, PRIVMSG, NOTICE, tagged lines, up '
       'to 1,200 bytes): no stop; #big %d people (%d kept), #huge %d (%d); the main loop\'s longest gap %d frames'
       % (people('#big')[-1] + people('#huge')[-1] + (gap,)))
    sys.exit(0)

if SESS == 'reread':
    need(vals('IR SERVERS ') == ['Libera.Chat;SDF;EFnet;Gate;'], 'CHAT.SERVERS read back: %s' % vals('IR SERVERS '))
    need(IRC[:4] == [b'NICK veranda', b'USER veranda 0 * :Gate tester', b'NICK verandax', b'JOIN #retro,#x16'],
         'the registration: %s' % IRC[:5])
    need(vals('IR TEST ME ') == ['verandax'], 'the nick: %s' % vals('IR TEST ME '))
    ok('CHAT.SERVERS (written by the main session) read back: the 3 defaults and the gate\'s server; PgDn x 3, '
       'Return: NICK veranda (in use), NICK verandax, USER, JOIN #retro,#x16: registered, both channels joined')
    sys.exit(0)

# ---------------------------------------------------------------- main
need(vals('IR SERVERS ') == ['Libera.Chat;SDF;EFnet;'], 'the defaults: %s' % vals('IR SERVERS '))
mk = open(os.path.join(R, 'VERANDA', '.SYSTEM', 'CHAT.SERVERS'), 'rb').read()
want = (b'Libera.Chat,irc.libera.chat,6667,X16user,X16user_,Veranda Chat user,,\r\n'
        b'SDF,irc.sdf.org,6667,X16user,X16user_,Veranda Chat user,,\r\n'
        b'EFnet,irc.efnet.org,6667,X16user,X16user_,Veranda Chat user,,\r\n'
        b'Gate,127.0.0.1,%d,veranda,verandax,Gate tester,,#retro #x16\r\n' % PORT)
need(mk == want, 'CHAT.SERVERS: %r' % mk)
ok('no CHAT.SERVERS: the Servers page lists the defaults (Libera.Chat, SDF, EFnet; port 6667); New, the fields '
   'typed, Connect: CHAT.SERVERS written with the 3 defaults and the new server (CR LF)')

need(IRC[:4] == [b'NICK veranda', b'USER veranda 0 * :Gate tester', b'NICK verandax', b'JOIN #retro,#x16'],
     'the registration: %s' % IRC[:5])
need(vals('IR TEST ME ')[:1] == ['verandax'], 'the nick: %s' % vals('IR TEST ME '))
need(not any(x.startswith(b'PASS') for x in IRC), 'PASS sent without a password')
mo = [t for w, a, t in LINES if w == '*' and 'Message of the Day' in t or 'Be kind' in t]
need(len(mo) == 2, 'the MOTD in the server window: %s' % mo)
ok('registration: NICK veranda, USER veranda 0 * :Gate tester; 433 (in use): NICK verandax (the alternative); '
   '001: one JOIN #retro,#x16; the welcome and the MOTD in the server\'s window')


def nicks_at(k):
    """the k-th nick dump: (channel, [entries])"""
    out, cur = [], None
    for l in log:
        if l.startswith('IR NICKS END'):
            out.append(cur)
            cur = None
        elif l.startswith('IR NICKS '):
            cur = (l[9:], [])
        elif l.startswith('IR NICK ') and cur:
            cur[1].append(l[8:])
    return out[k]


EXTRA = [' user%02d' % i for i in range(1, 31)]
n0 = nicks_at(0)
need(n0 == ('#retro', ['@alice', '+dave', ' bob'] + EXTRA + [' verandax']), 'the names of #retro: %s' % (n0,))
n1 = nicks_at(1)
need(n1 == ('#x16', ['@erin', ' frank', ' verandax']), 'the names of #x16: %s' % (n1,))
need(('#retro', 2, '-- Topic: Retro computing: the X16 and friends') in LINES, 'the topic (332, bold stripped)')
ok('both channels joined: the names (353 in two pieces, 366) sorted: ops, voices, the rest by name (34 and 3); '
   'the topics (332, formatting stripped)')

need(b'PONG :gate-ping-1' in IRC, 'no PONG')
ok('PING :gate-ping-1 answered: PONG :gate-ping-1')

need(('#retro', 0, '<alice> Hello bold red and italic done') in LINES, 'formatting: %s' % [x for x in LINES if 'alice' in x[2]])
L10 = lambda s: s.encode('iso8859_16').decode('latin-1')     # (V143: the lines are the set's bytes)
need(('#retro', 0, L10('<alice> café łódź "quoted” ? naïve e')) in LINES, 'UTF-8: %s' % [x for x in LINES if 'alice' in x[2]])
need(('#retro', 0, '<alice> Latin-1: \xe9t\xe9') in LINES, 'Latin-1')
need(('#retro', 0, L10('<alice> Zażółć gęślą jaźń')) in LINES and ('#retro', 0, L10('<alice> ZAŻÓŁĆ GĘŚLĄ JAŹŃ')) in LINES,
     'Polish in: %s' % [x for x in LINES if 'alice' in x[2]])
ok('messages in: bold, a colour (^C04,01), italics, reset stripped; UTF-8 decoded into the set (ISO-8859-16, V143): '
   'é ó ï ł ź ” (the set has it), "Zażółć gęślą jaźń" in both cases; “ to ", an emoji to ?, a combining accent '
   'dropped; a Latin-1 line (not UTF-8) kept')

need(b'PRIVMSG #retro :Hello everyone, caf\xc3\xa9!' in IRC, 'the message out: %s' % IRC)
need(b'PRIVMSG #retro :\x01ACTION waves\x01' in IRC, '/me')
need('PRIVMSG #retro :Zażółć gęślą jaźń'.encode('utf-8') in IRC, 'the Polish message out: %s' % IRC)
need(('#retro', 1, L10('<verandax> Zażółć gęślą jaźń')) in LINES, 'the Polish echo')
ok('(V143) "Zażółć gęślą jaźń" typed in the set\'s bytes: sent as UTF-8, shown')
need(('#retro', 1, '<verandax> Hello everyone, caf\xe9!') in LINES and ('#retro', 1, '* verandax waves') in LINES, 'the echoes')
ok('messages out: "Hello everyone, caf\xe9!" typed: PRIVMSG #retro :Hello everyone, caf\\xc3\\xa9! (Latin-1 sent as '
   'UTF-8); /me waves: PRIVMSG #retro :\\x01ACTION waves\\x01; both shown')

T = tabs()
need(('bob', 0, '<bob> Hi there, privately') in LINES, 'the query line')
need(T[1] == ['*+', '#retro<', '#x16', 'bob!'], 'the tabs after the query: %s' % T[1])
d = val('IR TEST DINGS ')
need(d[0] >= 1, 'no sound for the query')
ok('a private message from bob: its window opened as a tab, marked "!" (not shown), the sound played')

n2 = nicks_at(2)
need(n2 == ('#retro', ['@carol', '+bobby'] + EXTRA + [' verandax']), 'the nicks after JOIN, PART, NICK, QUIT, MODE: %s' % (n2,))
need(T[2] == ['*+', '#retro<', '#x16', 'bobby!'], 'the query renamed: %s' % T[2])
for want in ['--> carol joined', '<-- alice left bye', '-- bob is now bobby', '<-- dave quit gone', '-- alice sets mode +ov carol bobby']:
    need(('#retro', 2, want) in LINES, 'the line %r' % want)
ok('the nick list after carol JOIN, alice PART, bob NICK bobby, dave QUIT, MODE +ov carol bobby: @carol +bobby, '
   'user01-30, verandax; the query window renamed bobby; each change noted in #retro')

need(('#retro', 3, '<carol> verandax: are you there?') in LINES, 'the mention')
need(('#x16', 3, '<erin> ping verandax, the X16 is here') in LINES, 'the mention in #x16')
need(T[3] == ['*+', '#retro<', '#x16!', 'bobby!'], 'the tabs after the mentions: %s' % T[3])
need(d[1] > d[0], 'no sound for the mention (%s)' % d)
ok('mentions: carol\'s line in #retro marked (shown reversed), erin\'s in #x16 too and its tab "!"; the sound')

need(b'PRIVMSG #retro :carol: hi' in IRC, 'Tab completion: %s' % IRC)
ok('"car" Tab "hi": PRIVMSG #retro :carol: hi (the nick completed from the list, ": " at the line\'s start)')

words = ' '.join('w%02d-abcd' % k for k in range(1, 49))
i = IRC.index(b'PRIVMSG #retro :carol: hi')
parts = [x for x in IRC[i + 1:] if x.startswith(b'PRIVMSG #retro :w')]
need(len(parts) == 2, 'the long line: %s' % parts)
txt = b' '.join(p[len(b'PRIVMSG #retro :'):] for p in parts).decode()
need(txt == words, 'the long line\'s text: %r' % txt)
rel = max(len(b':verandax!verandax@' + b'h' * 63 + b' ') + len(p) + 2 for p in parts)
need(rel <= 512, 'a piece too long: %d' % rel)
ok('a line of %d characters: split at a space into 2 PRIVMSGs (%d and %d bytes; with the prefix the server '
   'adds, a 63-character host: %d of 512 at most), joined equal to what was typed'
   % (len(words), len(parts[0]) + 2, len(parts[1]) + 2, rel))

need(b'NOTICE carol :\x01VERSION Veranda Chat 1.0 (Commander X16)\x01' in IRC, 'VERSION: %s' % IRC)
need(not any(w == 'carol' for w, a, t in LINES), 'a window opened for the CTCP')
ok('CTCP VERSION from carol: NOTICE carol :\\x01VERSION Veranda Chat 1.0 (Commander X16)\\x01; no window opened for it')

for x in [b'TOPIC #retro :A new topic', b'PRIVMSG carol :private hello', b'WHOIS carol']:
    need(x in IRC, 'missing %r' % x)
need(('#retro', 2, '-- verandax set the topic: A new topic') in LINES, 'the topic echoed')
need(vals('IR TEST UP1 ') == ['/raw WHOIS carol'] and vals('IR TEST UP2 ') == ['/msg carol private hello'],
     'the history: %s %s' % (vals('IR TEST UP1 '), vals('IR TEST UP2 ')))
ok('/topic, /msg, /raw: TOPIC #retro :A new topic (the topic changed), PRIVMSG carol :private hello, WHOIS carol; '
   'Up, Up: the last two lines typed again')

for x in [b'NICK verandaz', b'JOIN #new', b'PART #new']:
    need(x in IRC, 'missing %r' % x)
need(vals('IR TEST ME ')[1:] == ['verandaz'], 'the new nick: %s' % vals('IR TEST ME '))
need(T[4][-1] == '#new<' and '#new<' not in T[5] and '#new' not in T[5], 'join, part: %s %s' % (T[4], T[5]))
need(T[6][-1] == 'dave<' and not any(x.startswith('dave') for x in T[7]), 'query, close: %s %s' % (T[6], T[7]))
ok('/nick verandaz (the server\'s NICK: our nick changed), /join #new (its tab, shown), /part (closed), /query dave '
   '(a tab), /close (gone)')

fl = [t for w, a, t in LINES if w == '#x16' and t.startswith('<frank> Flood line ')]
need(fl == ['<frank> Flood line %03d: the quick brown fox jumps over the lazy dog' % i for i in range(1, 401)], 'the flood: %d' % len(fl))
nl, used, cnt = val('IR SB LINES ')[0], val('IR SB USED ')[0], val('IR SB COUNTED ')[0]
first = vals('IR SB FIRST ')[0]
need(vals('IR SB LAST ')[0].startswith('<frank> Flood line 400'), 'the newest kept')
k = int(first[19:22])
need(nl == cnt and nl < 400 and used <= 4096 and first.startswith('<frank> Flood line ') and nl == 401 - k,
     'the cap: %d lines, %d bytes, first %r' % (nl, used, first))
sc = val('IR TEST SCROLL ')
need(sc[0] > 0 and val('IR TEST SCROLL END ')[0] == 0, 'scrolling: %s' % sc)
ok('400 lines to #x16: all came; the scrollback keeps the newest %d (%d bytes of 4 KB; "Flood line %03d" the '
   'oldest, the rest dropped); PgUp x 12: scrolled back %d rows (to the oldest); End: the newest again'
   % (nl, used, k, sc[0]))

need('IR ASIDE' in log and 'IR TEST BACK' in log, 'Alt+Tab')
for i in range(1, 4):
    need(('#retro', 0, '<alice> While you were away %d' % i) in LINES, 'the lines while aside')
ok('Alt+Tab with lines coming: put aside (vrnet\'s aside: the connection kept in the modem), the test desktop 3 s, '
   'back: the 3 lines sent meanwhile shown')

B = boxes()
need('The server Gate closed the connection.|Closing Link: verandaz (Gate is closing)' in B, 'the close box: %s' % B)
ok('the server\'s ERROR and close: the box "The server Gate closed the connection." with its reason')

gap, lost, oe, bad, pk, xr = (val('IR MAXGAP ')[0], val('IR LOST ')[0], val('IR OE ')[0], val('IR BADCRC ')[0],
                              val('IR PACKETS ')[0], val('IR XONRETRY ')[0])
need(lost == 0 and oe == 0 and bad == 0, 'lost %s, overruns %s, bad CRC %s' % (lost, oe, bad))
need(gap < 30, 'the main loop\'s longest gap: %s frames' % gap)
ok('the server got %d IRC lines; the main loop\'s longest gap %d frames (boxes and screenshots excluded); %d '
   'packets, %d XON retries; nothing lost in the UART, no bad CRC' % (len(IRC), gap, pk, xr))
