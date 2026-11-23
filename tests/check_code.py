#!/usr/bin/env python3
"""Gates claude and ask (DECISIONS V123): the code session checked (tests/
claude_play.c's and tests/ask_play.c's code_steps): the requests the fake
server got (their bodies: the prefixes kept turn after turn, Remember,
old code shortened, the file attached, the compaction, the cheap model,
short answers), the files saved, the clipboard's copies, the rows.

usage: check_code.py claude|ask <run folder>
"""
import json
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'tools'))
import x16basic                         # noqa: E402

APP, R = sys.argv[1], sys.argv[2]
ASK = APP == 'ask'
raw = open(os.path.join(R, 'log.txt'), encoding='utf-8', errors='replace').read()
log = raw.split('\n')
srv = os.path.join(R, 'srv', 'requests.jsonl')
REQ = [json.loads(l) for l in open(srv)]
if ASK:
    REQ = [r for r in REQ if r.get('path') == '/v1/responses']
D = os.path.join(R, 'DOCUMENTS')


def need(c, msg):
    if not c:
        sys.exit('FAIL  ' + msg)


def ok(msg):
    print('ok    ' + msg)


def vals(key):
    return [l[len(key):] for l in log if l.startswith(key)]


need('CL TEST STUCK' not in raw and 'CL TEST FAILED' not in raw,
     'the test stopped: %s' % re.findall(r'CL TEST (?:STUCK|FAILED)[^\n]*', raw))
need('CL END' in log, 'no end')

BAS = '10 PRINT "HELLO FROM CLAUDE"\n20 FOR I=1 TO 3:PRINT I*I;:NEXT I\n30 PRINT\n40 PRINT "DONE"'
PY = 'for i in range(1, 4):\n    print(i * i, end=" ")\nprint("done")'
CODE = ('Here is a small program for the X16.\n\n```basic\n' + BAS + '\n```\n\nAnd the same in Python:\n\n'
        '```python\n' + PY + '\n```\n\nCopy or save either.')
ORIG = '5 PRINT "{93}"\n10 PRINT "GAME"\n20 X=5\n30 PRINT "SCORE";X+\n40 END\n'
FIXED = '5 PRINT "{93}"\n10 PRINT "GAME"\n20 X=5\n30 PRINT "SCORE";X*2\n40 END'
SUMMARY = ('We wrote a BASIC program that prints squares, saved as PROGRAM.PRG, and fixed line 30 of GAME.PRG '
           '(PRINT "SCORE";X*2).')
SHORT_S = ' Keep every answer short: a few sentences, or only the code asked for.'
CINST = 'Summarise our conversation so far in at most 150 words'
ACK = 'Thank you: I have the summary and will go on from it.'


def msgs(r):
    b = r['body']
    if ASK:
        return [{'role': m['role'], 'content': m['content']} for m in b['input']]
    return b['messages']


def last(r):
    return msgs(r)[-1]['content']


def model(r):
    return r['body']['model']


KINDS = ['plain', 'plain', 'plain', 'code', 'plain', 'plain', 'fix', 'plain', 'summarise', 'plain', 'cheap',
         'short', 'big', 'plain', 'summarise', 'plain']
kinds = ['summarise' if last(r).startswith(CINST) else last(r).split()[0].lower().strip(',!?.:') for r in REQ]
need(kinds == KINDS, 'the requests: %s' % kinds)
for r in REQ:
    need(not r['bad'], 'request %s: %s' % (last(r)[:20], r['bad']))
CHEAP = 'claude-haiku-5-5' if not ASK else 'gpt-6.2-sol'     # (Ask with an API key: its one model)
MAIN = 'claude-opus-5-5' if not ASK else 'gpt-6.2-sol'

# ---------------------------------------------------------------- the prefix: the cache's
def prefix(r):
    t = r['raw']
    i = t.rfind('],"store"') if ASK else len(t) - 2
    need(t[i:i + 2] in (']}', '],'), 'the body\'s end: %r' % t[-40:])
    return t[:i]


for i in range(3):
    a, b = prefix(REQ[i]), REQ[i + 1]['raw']
    if not b.startswith(a):
        need(False, 'turn %d\'s body is not the start of turn %d\'s: first difference at %d: %r / %r'
             % (i + 1, i + 2, next((k for k in range(min(len(a), len(b))) if a[k] != b[k]), -1),
                a[max(0, len(a) - 60):][:80], b[max(0, len(a) - 60):][:80]))
sysk = 'instructions' if ASK else 'system'
need(len({r['body'][sysk] for r in REQ if not r['body'][sysk].endswith(SHORT_S)}) == 1,
     'the system prompt changed between turns')
ok('the prefix kept: each of turns 1-3\'s body (up to its messages\' end, %d, %d, %d bytes) is byte for byte the '
   'start of the next turn\'s; the system prompt the same in every turn of one setting (%s)'
   % (len(prefix(REQ[0])), len(prefix(REQ[1])), len(prefix(REQ[2])),
      'OpenAI\'s automatic prefix cache' if ASK else 'Anthropic\'s top-level cache_control: the breakpoint on the last block'))

# ---------------------------------------------------------------- the blocks' rows
rows = [l[7:] for l in log if l.startswith('CL ROW ')]
fl = {}
for r in rows:
    f, _, t = r.partition(' ')
    fl.setdefault(t, int(f))
need(fl.get('```basic', 0) & 0x60 == 0x60 and fl.get('```python', 0) & 0x60 == 0x60, 'the fences\' rows: %s' % rows[-24:])
need(fl.get('30 PRINT', 0) & 0x70 == 0x40 and fl.get('print("done")', 0) & 0x70 == 0x40, 'the code\'s rows: %s' % rows[-24:])
need(fl.get('```', 0) & 0x50 == 0x50, 'the closing fence\'s row')
need(fl.get('Copy or save either.', 0) & 0x70 == 0 and fl.get('And the same in Python:', 0) & 0x70 == 0, 'the text\'s rows')
ok('the reply\'s two fenced blocks found: their rows marked (R_CODE: shaded; the opening fence R_FENCE: its labels '
   '[Copy] [Save...] [Save .PRG]; the closing one R_CEND), the text around them not')

# ---------------------------------------------------------------- the clipboard
def scrap(name):
    p = os.path.join(R, name) if name != '-' else os.path.join(R, 'VERANDA', '.SYSTEM', 'Text  Scrap.cvt')
    if name == '-' and not os.path.exists(p):
        p = os.path.join(R, 'Text  Scrap.cvt')      # (the library's other folder, the root)
    d = open(p, 'rb').read()
    need(d[254 + 75:254 + 91] == b'Text  Scrap V2.0', '%s: not a Text Scrap' % name)
    size = d[508] | d[509] << 8
    body = d[510:510 + size]
    need(body[:4] == bytes([23, 9, 0, 0]), '%s: its NEWCARDSET' % name)
    return body[4:]


need(scrap('SCRAP1.CVT') == PY.replace('\n', '\r').encode(), 'Code > Copy last code block: %r' % scrap('SCRAP1.CVT'))
need(scrap('SCRAP2.CVT') == BAS.replace('\n', '\r').encode(), '[Copy]: %r' % scrap('SCRAP2.CVT'))
need(scrap('SCRAP3.CVT') == CODE.replace('\n', '\r').encode(), 'Code > Copy last reply: %r' % scrap('SCRAP3.CVT'))
need(scrap('-') == scrap('SCRAP3.CVT'), 'the scrap at the end')
ok('the clipboard (the Text Scrap, NEWCARDSET then the text, CR line ends): Code > Copy last code block the '
   'Python block exactly, [Copy] the BASIC block exactly, Code > Copy last reply the reply exactly')

# ---------------------------------------------------------------- the files
prg = open(os.path.join(D, 'PROGRAM.PRG'), 'rb').read()
need(prg == x16basic.tokenize(BAS.encode()), 'PROGRAM.PRG: %s\n  want %s' % (prg.hex(), x16basic.tokenize(BAS.encode()).hex()))
bas = open(os.path.join(D, 'PROGRAM.BAS'), 'rb').read()
need(bas == (BAS + '\n').replace('\n', '\r\n').encode(), 'PROGRAM.BAS: %r' % bas)
ok('[Save .PRG]: /DOCUMENTS/PROGRAM.PRG (%d bytes) byte for byte the host\'s tokenizer\'s (tools/x16basic.py, '
   'the ROM\'s crunch); [Save...]: /DOCUMENTS/PROGRAM.BAS the text, CR LF' % len(prg))

# ---------------------------------------------------------------- Remember the last 4
need(vals('CL TEST REMEMBER ')[:2] == ['2', '0'], 'the Conversation page\'s Remember: %s' % vals('CL TEST REMEMBER '))
m4, m5 = msgs(REQ[4]), msgs(REQ[5])
need([m['content'] for m in m4][0] == 'plain three' and len(m4) == 5, 'Remember 4 (plain four): %s' % [m['content'][:12] for m in m4])
need(m5[0]['content'] == 'code please' and len(m5) == 5 and m5[-1]['content'] == 'plain five',
     'Remember 4 (plain five): %s' % [m['content'][:12] for m in m5])
need(all(m['role'] == ('user' if i % 2 == 0 else 'assistant') for i, m in enumerate(m5)), 'the alternation')
ok('Remember the last 4 messages (the Conversation page, CLAUDE.CFG remember=4): each request the 4 messages '
   'before the question and the question (5, from a user\'s message, alternating); %d bytes against %d with '
   'Remember all just before' % (REQ[5]['raw_len'], REQ[3]['raw_len']))

# ---------------------------------------------------------------- old code shortened
short = ('Here is a small program for the X16.\n\n[code block: 4 lines, saved as PROGRAM.BAS]\n\nAnd the same in '
         'Python:\n\n[code block: 3 lines]\n\nCopy or save either.')
need(m4[3]['content'] == CODE, 'the last reply\'s blocks sent whole: %r' % m4[3]['content'][:80])
need(m5[1]['content'] == short, 'the blocks saved and copied, shortened: %r' % m5[1]['content'])
ok('old code shortened (on by default): the reply\'s blocks sent whole while it is the last reply, then (saved, '
   'copied) as "[code block: 4 lines, saved as PROGRAM.BAS]" and "[code block: 3 lines]"; the screen keeps them')

# ---------------------------------------------------------------- the file attached, saved back
game0 = x16basic.tokenize(ORIG.encode())
need(x16basic.detokenize(game0).decode() == ORIG and x16basic.tokenize(x16basic.detokenize(game0)) == game0,
     'the host\'s round trip')
fixq = last(REQ[6])
want = 'fix please: line 30 says X+\n\nAttached file GAME.PRG:\n```basic\n' + ORIG + '```'
need(fixq == want, 'the question with the file: %r\n  want %r' % (fixq, want))
need(vals('CL TEST ATTLBL ') == ['Attached: GAME.PRG (5 lines) [Remove]'], 'the label: %s' % vals('CL TEST ATTLBL '))
game1 = open(os.path.join(D, 'GAME.PRG'), 'rb').read()
need(game1 == x16basic.tokenize(FIXED.encode()), 'GAME.PRG saved back: %s' % game1.hex())
need(any('CL BOX Replace GAME.PRG?' in l for l in log), 'the Replace box')
m7 = msgs(REQ[7])
need(m7[-3]['content'] == 'fix please: line 30 says X+\n\nAttached file GAME.PRG:\n[GAME.PRG, older version, 5 lines]\n',
     'the older version: %r' % m7[-3]['content'])
need('```basic\n' + FIXED + '\n```' in m7[-2]['content'], 'the newest version sent whole')
ok('Code > Attach a file... GAME.PRG (tokenized, from /DOCUMENTS): the toolbar "Attached: GAME.PRG (5 lines) '
   '[Remove]"; the question sent with "Attached file GAME.PRG:" and the program as text exactly ({93} for its '
   'CLR code; the host\'s detokenizer\'s, and its tokenizer gives the PRG back byte for byte); the reply\'s '
   'new version [Save...]: GAME.PRG offered, "Replace GAME.PRG?" Yes: tokenized again, byte for byte; the next '
   'request sends the old version as "[GAME.PRG, older version, 5 lines]", the newest whole')

# ---------------------------------------------------------------- compaction
c = REQ[8]
need(model(c) == CHEAP and last(c).startswith(CINST) and msgs(c)[-2]['role'] == 'assistant', 'the compaction request')
if not ASK:
    need(c['body']['max_tokens'] == 500, 'its max_tokens')
a = msgs(REQ[9])
need(len(a) == 3 and a[0]['content'] == 'Summary of our conversation so far: ' + SUMMARY and a[1]['content'] == ACK
     and a[2]['content'] == 'plain after', 'after the compaction: %s' % a)
mk = [l[7] for l in vals('CL MSG ')]
need('c' in raw and any(l.startswith('CL MSG s ') for l in log) and any(l.startswith('CL MSG h ') for l in log),
     'the kinds kept: %s' % mk[-30:])
ok('Settings > Compact conversation: one request to %s (%d bytes; max_tokens 500 for Claude), the conversation and the '
   'request to summarise it; then the turns before are dimmed and not sent: the next request is the summary '
   '(as the user\'s), the acknowledgement and the question: %d bytes against %d before'
   % (CHEAP, c['raw_len'], REQ[9]['raw_len'], REQ[7]['raw_len']))

# ---------------------------------------------------------------- the cheap model, short answers
need(model(REQ[10]) == CHEAP and model(REQ[11]) == MAIN, 'Ctrl+Return\'s model: %s' % model(REQ[10]))
s11 = REQ[11]['body']
if ASK:
    need(s11['instructions'].endswith(SHORT_S) and 'max_output_tokens' not in s11, 'short answers')
else:
    need(s11['system'].endswith(SHORT_S) and s11['max_tokens'] == 1024 and REQ[9]['body']['max_tokens'] == 4096, 'short answers')
ok('one question to the cheap model (Ctrl+Return): %s, the next one %s again; short answers: the fixed '
   'sentence after the system prompt%s' % (CHEAP, MAIN, '' if ASK else ', max_tokens 1024'))

# ---------------------------------------------------------------- compact when long; the long hint
st = vals('CL STATUS ')
need(any('Long conversation: each question resends it. New starts fresh.' in s for s in st), 'the hint: %s' % st[-12:])
need(model(REQ[14]) == CHEAP and last(REQ[14]).startswith(CINST) and last(REQ[15]) == 'plain auto'
     and msgs(REQ[15])[0]['content'].startswith('Summary of our conversation so far: '), 'compact when long')
ok('the hint "Long conversation: each question resends it. New starts fresh." after a turn of %d bytes; compact '
   'when long (the Conversation page): the question waited for the compaction, then went with the summary '
   '(%d bytes against %d)' % (REQ[13]['raw_len'], REQ[15]['raw_len'], REQ[13]['raw_len']))

# ---------------------------------------------------------------- the usage
if ASK:
    u = [s for s in st if ' in ' in s and ' out ' in s]
    need(u and all('$' not in s for s in u), 'the plan shows no money: %s' % u[-3:])
    ok('the usage after each turn: "%s" (tokens only: no money with the ChatGPT plan)' % u[0][u[0].find('in '):])
else:
    want = 'in 1,484 (cached 34) out 42, $0.0069'
    need(any(want in s for s in st), 'the usage: %s' % [s for s in st if ' out ' in s][:3])
    ok('the usage after each turn: "%s" (input 1,200 + cache write 250 + cache read 34 tokens; Opus 5.5\'s list '
       'prices: $4, $20, $5, $0.20 a million)' % want)

print('      the bodies (bytes): ' + ', '.join('%s %d' % (k, r['raw_len']) for k, r in zip(KINDS, REQ)))
