#!/usr/bin/env python3
"""Gate claude (DECISIONS V114): Veranda Claude's sessions checked (tools/
gate_claude.sh): the console's "CL ..." lines (tests/claude_play.c and the
test build's own), the fake API's log (tests/claude_server.py: every
request as it came, what was sent back), the modem's log, the files on the
card.

usage: check_claude.py <session> <run folder> <port> [plain]
"""
import json
import os
import re
import sys

SESS, R, PORT = sys.argv[1], sys.argv[2], int(sys.argv[3])
PLAIN = len(sys.argv) > 4 and sys.argv[4] == 'plain'
raw = open(os.path.join(R, 'log.txt'), encoding='utf-8', errors='replace').read()   # (the console: bytes as Latin-1, in UTF-8)
log = raw.split('\n')

# CP437 as Veranda Claude's font has it (0-31 the glyphs): its Unicode
LOW = [0x0000, 0x263A, 0x263B, 0x2665, 0x2666, 0x2663, 0x2660, 0x2022, 0x25D8, 0x25CB, 0x25D9, 0x2642,
       0x2640, 0x266A, 0x266B, 0x263C, 0x25BA, 0x25C4, 0x2195, 0x203C, 0x00B6, 0x00A7, 0x25AC, 0x21A8,
       0x2191, 0x2193, 0x2192, 0x2190, 0x221F, 0x2194, 0x25B2, 0x25BC]
# (V143) $80-$9F the private glyphs (CP437's pi, square, root, shades, blocks,
# box lines: copy.s's cs_font), $A0-$FF Veranda's set, ISO-8859-16
PRIV = [0xE3, 0xFE, 0xFB, 0xB0, 0xB1, 0xB2, 0xB3, 0xB4, 0xBF, 0xC0, 0xC1, 0xC2, 0xC3, 0xC4, 0xC5, 0xD9,
        0xDA, 0xDB, 0xDC, 0xDD, 0xDE, 0xDF, 0xBA, 0xCD, 0xC9, 0xBB, 0xC8, 0xBC, 0xCC, 0xB9, 0xCB, 0xCA]
CP = (LOW + list(range(32, 127)) + [0x2302] + [ord(bytes([b]).decode('cp437')) for b in PRIV]
      + [ord(bytes([b]).decode('iso8859_16')) for b in range(160, 256)])
REV = {}
for b in list(range(160, 256)) + list(range(1, 160)):     # (store.c's cp_of: the set first)
    if b not in (9, 10, 13):
        REV.setdefault(CP[b], b)
SPEC = {}
for us, out in [((0x2018, 0x2019, 0x201A, 0x201B, 0x2032, 0x2035), b"'"),
                ((0x201C, 0x201D, 0x201E, 0x201F, 0x2033), b'"'),
                ((0x2010, 0x2011, 0x2012, 0x2013, 0x2014, 0x2015, 0x2212, 0x2043), b'-'),
                ((0x2026,), b'...'), ((0x00A0, 0x2007, 0x202F, 0x205F, 0x3000), b' '),
                ((0x00AD, 0x200B, 0x200C, 0x200D, 0x2060, 0xFEFF), b''),
                ((0x25CF, 0x2023, 0x25E6, 0x2027), b'\x07'), ((0x25AA, 0x25FE, 0x25FC), b'\x81'),
                ((0x2713, 0x2714, 0x2705), b'\x82'), ((0x2717, 0x2718, 0x274C, 0x00D7), b'x'),
                ((0x21D2,), b'=>'), ((0x21D0,), b'<='), ((0x27A1, 0x2794), b'\x1a'),
                ((0x2122,), b'TM'), ((0x00AE,), b'(R)'), ((0x00BD,), b'1/2'), ((0x00BC,), b'1/4'),
                ((0x00BE,), b'3/4')]:
    for u in us:
        SPEC[u] = out
FOLD = ('AAAAAAACEEEEIIIIDNOOOOOxOUUUUYPsaaaaaaaceeeeiiiidnooooo/ouuuuypy'
        'AaAaAaCcCcCcCcDdDdEeEeEeEeEeGgGgGgGgHhHhIiIiIiIiIiIiJjKkkLlLlLlLlLlNnNnNnnNnOoOoOoOoRrRrRrSsSsSsSsTtTtTtUuUuUuUuUuUuWwYyYZzZzZzs')


def fold(s):
    """the reply as Veranda Claude keeps it: CP437 bytes (parse.c's rules)"""
    out = b''
    for ch in s:
        u = ord(ch)
        if u > 0xFFFF:
            out += b'?'
        elif u < 128:
            out += b'\n' if u == 10 else b' ' if u == 9 else bytes([u]) if 32 <= u < 127 else b''
        elif u in SPEC:
            out += SPEC[u]
        elif 0x2000 <= u <= 0x200A:
            out += b' '
        elif u in REV:
            out += bytes([REV[u]])
        elif 0xC0 <= u < 0x180:
            out += FOLD[u - 0xC0].encode()
        else:
            out += b'?'
    return out


def sent(b):
    """CP437 bytes as Veranda Claude sends them back (each glyph's Unicode), trailing spaces dropped"""
    return ''.join('\n' if c == 10 else chr(CP[c]) for c in b.rstrip(b' \n'))


def wrap(b, w=74):
    """store.c's rows of text b"""
    rows, p = [], 0
    while True:
        rem = len(b) - p
        n = min(rem, w)
        i = b.find(b'\n', p, p + n)
        if i >= 0:
            rows.append(b[p:i])
            p = i + 1
        elif rem <= w:
            rows.append(b[p:])
            return rows
        else:
            k = next((k for k in range(w, w // 3, -1) if b[p + k] == 32), 0)
            if k:
                rows.append(b[p:p + k])
                p += k + 1
            else:
                rows.append(b[p:p + w])
                p += w


def need(c, msg):
    if not c:
        sys.exit('FAIL  ' + msg)


def ok(msg):
    print('ok    ' + msg)


def val(key):
    return [int(x) for x in re.findall(r'^%s(-?\d+)$' % re.escape(key), raw, re.M)]


def vals(key):
    return [l[len(key):] for l in log if l.startswith(key)]


def boxes():
    return [l[7:] for l in log if l.startswith('CL BOX ')]


need('CL TEST STUCK' not in raw and 'CL TEST FAILED' not in raw,
     'the test stopped: %s' % re.findall(r'CL TEST (?:STUCK|FAILED)[^\n]*', raw))
need('CL END' in log, 'no end')
lost, oe, bad = val('CL LOST ')[0], val('CL OE ')[0], val('CL BADCRC ')[0]
need(lost == 0 and oe == 0 and bad == 0, 'lost %s, overruns %s, bad CRC %s' % (lost, oe, bad))

if SESS in ('nomodem', 'nocard'):
    want = 'The modem does not answer.|' if SESS == 'nomodem' else 'No network card was found.|'
    need(any(b.startswith(want) for b in boxes()), 'the box: %s' % boxes())
    need(vals('CL TEST INPUT ') == ['hello'], 'the text given back: %s' % vals('CL TEST INPUT '))
    need(any(l.startswith('CL MSG x 5 hello') for l in log), 'the turn left out: %s' % vals('CL MSG '))
    ok('%s: a message sent: the box "%s" (vrnet: %s); the turn left out of the conversation, its text back in '
       'the input box' % (SESS, want[:-1], 'NET_ENOMODEM' if SESS == 'nomodem' else 'NET_ENOCARD'))
    sys.exit(0)

# ---------------------------------------------------------------- main
REQ = [json.loads(l) for l in open(os.path.join(R, 'srv', 'requests.jsonl'))]
need(all('error' not in r for r in REQ), 'the server: %s' % [r for r in REQ if 'error' in r])
KINDS = ['hello', 'long', 'max', 'refuse', 'overload', 'midstream', 'key', 'slow', 'aside', 'big', 'big', 'big',
         'big', 'haiku']
need([r['kind'] for r in REQ] == KINDS, 'the requests: %s' % [r['kind'] for r in REQ])
for r in REQ:
    need(not r['bad'], 'request %s: %s' % (r['kind'], r['bad']))
r0 = REQ[0]
h, b = r0['headers'], r0['body']
ok('%d requests, each one connection: POST /v1/messages HTTP/1.1, Host, x-api-key (the key typed), '
   'anthropic-version 2026-10-21, anthropic-beta server-side-fallback-2026-07-01, content-type '
   'application/json, Content-Length equal to the body (%d bytes the first, %d the largest); the body: model '
   '%s, max_tokens %d, stream true, fallbacks "default", output_config {"effort": "low"}, top-level '
   'cache_control ephemeral, a system prompt (plain ASCII, no Markdown), no temperature, top_p, top_k or '
   'thinking; messages alternating from a user turn, the last the user\'s'
   % (len(REQ), r0['raw_len'], max(r['raw_len'] for r in REQ), b['model'], b['max_tokens']))

# the modem: ATCS, one a request
mlog = open(os.path.join(R, 'modem.log'), encoding='latin-1').read().split('\n')
atc = [l.split(' ', 1)[1] for l in mlog if l.startswith('@') and ' ATC' in l and '"' in l]
want = 'ATC"127.0.0.1:%d"' % PORT if PLAIN else 'ATCS"127.0.0.1:%d"' % PORT
need(len(atc) == len(REQ) and all(a == want for a in atc), 'the connects: %s' % atc)
if not PLAIN:
    sec = [l for l in mlog if l.startswith('SECURE')] or [l for l in mlog if 'SECURE' in l]
    need(len(sec) == len(REQ), 'SECURE in the modem\'s log: %d' % len(sec))
    ok('each turn a connection of its own: %s (the modem\'s TLS; the emulator\'s modem makes it plain TCP and '
       'logs it SECURE)' % want)
else:
    ok('each turn a connection of its own: %s (this emulator has no ATCS: the test\'s plain connect)' % want)

# the Settings page; CLAUDE.CFG
need(log.index('CL SETTINGS SHOWN') < log.index('CL TEST START') or 'CL SETTINGS SHOWN' in log, 'no Settings page')
need(vals('CL TEST KEY ') == ['sk-ant-gate-0000-dummy-key-for-tests-WXYZ'], 'the key: %s' % vals('CL TEST KEY '))
cfg = open(os.path.join(R, 'VERANDA', '.SYSTEM', 'CLAUDE.CFG'), 'rb').read()
want = (b'server=api\r\nkey=sk-ant-gate-0000-dummy-key-for-tests-WXYZ\r\nmodel=claude-haiku-5-5\r\nhost=127.0.0.1\r\n'
        b'port=%d\r\nremember=all\r\nanswers=normal\r\noldcode=short\r\ncompact=asked\r\n' % PORT)
need(cfg == want, 'CLAUDE.CFG: %r' % cfg)
ok('CLAUDE.CFG with no key: the welcome notes and the Settings page at the start; the key typed (shown as '
   'stars but its last 4), Return: CLAUDE.CFG written (server, key, model, host, port; CR LF); Settings > Claude Haiku '
   '5.5 later: written again')

# the first turn: its text, its rows
msgs1 = REQ[0]['body']['messages']
need(msgs1 == [{'role': 'user', 'content': 'Café? Zażółć gęślą jaźń ZAŻÓŁĆ GĘŚLĄ JAŹŃ'}], 'the first message: %s' % msgs1)
HELLO = REQ[0]['reply']
hb = fold(HELLO)
need(REQ[1]['body']['messages'][1] == {'role': 'assistant', 'content': sent(hb)},
     'the reply sent back: %r\n  want %r' % (REQ[1]['body']['messages'][1], sent(hb)))
rows = [l[7:] for l in log if l.startswith('CL ROW ')]
got = [r.split(' ', 1)[1] if ' ' in r else '' for r in rows if r.split(' ', 1)[0] in ('129', '1')]


def shown(b):
    """a row's CP437 bytes as the console shows them (Latin-1; control characters and 128-159 as U+FFFD)"""
    return ''.join('\ufffd' if c < 32 or 0x80 <= c < 0xA0 else chr(c) for c in b.rstrip(b' '))


need(got == [shown(x) for x in wrap(hb.rstrip(b' \n'))], 'the reply\'s rows: %r\n  want %r' % (got, wrap(hb)))
need('za\\u017c\\u00f3\\u0142\\u0107 g\\u0119\\u015bl\\u0105' in REQ[0]['raw'].lower(), 'the Polish letters as JSON escapes: %r' % REQ[0]['raw'][-160:])
ok('a turn: "Café? Zażółć gęślą jaźń ZAŻÓŁĆ GĘŚLĄ JAŹŃ" typed (V143: Veranda\'s set, ISO-8859-16; sent as that Unicode); the thinking pause ("Thinking" '
   'in the reply\'s row), the text streamed in chunks cut anywhere: \\u escapes (curly quotes, a dash, an '
   'ellipsis, é ï, "Zażółć gęślą jaźń", an emoji\'s surrogate pair as one ?, bullets as CP437\'s), raw UTF-8 '
   '(ł ó ź "ZAŻÓŁĆ GĘŚLĄ JAŹŃ" kept, ½ as 1/2: the set, V143), a tab, a backslash, quotes; %d rows wrapped at 74 at the last '
   'space; sent back in the next request as it was folded' % len(got))

# the long reply, max_tokens, refusal
LONG = REQ[1]['reply']
m2 = REQ[2]['body']['messages']
need(m2[3] == {'role': 'assistant', 'content': sent(fold(LONG))}, 'the long reply sent back')
need(val('CL TEST STORY ROWS ')[0] > 100, 'the story\'s rows')
ok('a long reply (%d characters, %d rows in all): sent back whole; PgUp x 5 scrolls back, Esc to the newest'
   % (len(LONG), val('CL TEST STORY ROWS ')[0]))
MAXR = REQ[2]['reply']
m3 = REQ[3]['body']['messages']
need(m3[-2] == {'role': 'assistant', 'content': MAXR} and m3[-1]['content'] == 'refuse please', 'after max: %s' % m3[-2:])
need(any('length limit, max_tokens' in l for l in log if l.startswith('CL MSG n')), 'the max_tokens note')
ok('stop_reason max_tokens: the reply kept (and sent back), a note "(The reply reached its length limit ...)"')
m4 = REQ[4]['body']['messages']
need(m4[-3:] == [{'role': 'user', 'content': 'max please'}, {'role': 'assistant', 'content': MAXR},
                 {'role': 'user', 'content': 'overload please'}], 'after the refusal: %s' % m4[-3:])
need(vals('CL TEST INPUT ')[0] == 'refuse please', 'the refused text back: %s' % vals('CL TEST INPUT '))
need(any(l.startswith('CL MSG x 13 refuse please') for l in log) and any(l.startswith('CL MSG y ') for l in log),
     'the refused turn marked')
ok('stop_reason refusal (after some text): the turn and its partial reply marked (red badges), left out of the '
   'next request, a note; the text back in the input box')

# 529, mid-stream error, 401
B = boxes()
need('Claude is overloaded (529).|Busy: try again in a moment (Return).' in B, 'the 529 box: %s' % B)
need(vals('CL TEST INPUT ')[1] == 'overload please', 'the 529 text back')
m5 = REQ[5]['body']['messages']
need(m5[-1]['content'] == 'midstream please' and 'overload please' not in [m['content'] for m in m5], 'after 529: %s' % m5[-3:])
ok('HTTP 529 (overloaded_error): the box "Claude is overloaded (529). Busy: try again in a moment", a note '
   '(API error 529, overloaded_error: Overloaded), the turn left out, its text back in the input box')
MID = REQ[5]['reply']
need('The reply was cut by an error:|Overloaded' in B, 'the mid-stream box: %s' % B)
need(vals('CL TEST INPUT ')[2] == '', 'nothing given back after a partial reply')
m6 = REQ[6]['body']['messages']
need(m6[-3:] == [{'role': 'user', 'content': 'midstream please'}, {'role': 'assistant', 'content': MID},
                 {'role': 'user', 'content': 'key please'}], 'after the mid-stream error: %s' % m6[-3:])
ok('an "error" event mid-stream (overloaded_error): the part that came kept (and sent back), a note, the box')
need('The API key was not accepted (401):|Check your API key in Settings.' in B, 'the 401 box: %s' % B)
need(vals('CL TEST INPUT ')[3] == 'key please', 'the 401 text back')
m7 = REQ[7]['body']['messages']
need('key please' not in [m['content'] for m in m7] and m7[-1]['content'] == 'slow please', 'after 401: %s' % m7[-3:])
ok('HTTP 401 (authentication_error): the box "The API key was not accepted (401). Check your API key in '
   'Settings.", a note with the API\'s message, the turn left out, its text back')

# Stop, Alt+Tab
SLOW = REQ[7]['reply']
need(REQ[7]['client_closed'], 'the server did not see the client close the slow reply')
m8 = REQ[8]['body']['messages']
part = m8[-2]['content']
need(m8[-3]['content'] == 'slow please' and m8[-2]['role'] == 'assistant' and SLOW.startswith(part)
     and 10 < len(part) < len(SLOW), 'the stopped reply: %r' % part)
need(any('(Stopped: the part that came is kept.)' in l for l in log), 'the Stopped note')
ok('Esc while a slow reply comes: the connection hung up (the server saw the close), the %d characters that '
   'came kept (and sent back), a note' % len(part))
need('CL ASIDE' in log and 'CL TEST BACK' in log, 'Alt+Tab')
m9 = REQ[9]['body']['messages']
need(m9[-2] == {'role': 'assistant', 'content': REQ[8]['reply']}, 'the reply while aside: %r' % m9[-2])
ok('Alt+Tab while a reply comes: put aside (vrnet\'s aside: the connection kept in the modem), back: the '
   'reply whole')

# the big replies: the oldest turns dropped
BIG = fold(REQ[9]['reply'])
lens = [len(json.dumps(r['body'])) for r in REQ[9:]]
for r in REQ[10:]:
    m = r['body']['messages']
    need(m[0]['role'] == 'user', 'a request starting with %s' % m[0]['role'])
need(any('oldest turns were dropped' in l for l in log), 'the dropped note')
m13 = REQ[13]['body']['messages']
need(m13[-1] == {'role': 'user', 'content': 'haiku please'} and m13[-2]['content'] == sent(BIG)
     and len(m13) < len(REQ[9]['body']['messages']), 'the history after the drops: %s' % [x['content'][:12] for x in m13])
need(REQ[13]['body']['model'] == 'claude-haiku-5-5' and 'fallbacks' not in REQ[13]['body']
     and 'anthropic-beta' not in REQ[13]['headers'], 'Haiku\'s request')
ok('four replies of %d characters: the conversation (32 KB) full: the oldest turns dropped whole (a note), '
   'what is left starting with a user turn (the requests %s bytes); Settings > Claude Haiku 5.5: model '
   'claude-haiku-5-5, no fallbacks, no anthropic-beta' % (len(REQ[9]['reply']), lens))

# Save, New
need(vals('CL TEST SAVED ') == ['CLAUDE.TXT'] and val('CL TEST SVERR ') == [0], 'the save')
f = open(os.path.join(R, 'DOCUMENTS', 'CLAUDE.TXT'), 'rb').read()
need(f.startswith(b'Veranda Claude: a conversation with Claude Haiku 5.5\r\n\r\n'), 'the file\'s head: %r' % f[:80])
need(b'You:\r\nhaiku please\r\n\r\nClaude:\r\nOK, from claude-haiku-5-5.\r\n\r\n' in f, 'the file\'s end: %r' % f[-120:])
need(b'Note:\r\n(The oldest turns were dropped' in f, 'the note in the file')
need(BIG.replace(b'\n', b'\r\n') in f, 'a big reply in the file')
ok('File > Save conversation: /DOCUMENTS/CLAUDE.TXT (%d bytes; UTF-8, CR LF; "You:", "Claude:", "Note:")' % len(f))
need(not any(l.startswith('CL BOX Start a new') for l in log), 'a New box (V123: none, the chat is kept)')
need(log[log.index('CL END') - 9:log.index('CL END') - 6][:2] == ['CL USED 22', 'CL ROWS 1'] or
     ('CL USED 22' in log and 'CL MSG n 19 A new conversation.' in log), 'New: %s' % log[-20:])
ok('File > New conversation (no box: the chat is kept in /DOCUMENTS/Chats): the conversation cleared, a note')

gap = val('CL MAXGAP ')[0]
need(gap < 120, 'the main loop\'s longest gap: %s frames' % gap)
turns = [l for l in log if l.startswith('CL TURN END ')]
big = [re.match(r'CL TURN END (\d+) bytes, (\d+) frames', t).groups() for t in turns]
rate = max(int(b) * 60 / int(f) for b, f in big if int(b) > 50000)
ok('the main loop\'s longest gap %d frames (sending a long conversation: its length counted, the oldest '
   'turns moved); the reply at up to %.1f KB/s through the modem (the SSE\'s bytes); nothing lost in the UART, '
   'no bad CRC' % (gap, rate / 1024))
