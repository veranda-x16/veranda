#!/usr/bin/env python3
# Gate ask, session request (DECISIONS V199): another program's request
# through Veranda Ask (apps/ask/rq.c, docs/AIREQ.md), prepared and checked.
# Copyright (c) 2026 Marcin Spoczynski. MIT licence (see LICENSE).
"""check_aireq.py: a request's run (tools/gate_ask.sh, ONLY=request).

    check_aireq.py prep <run> <folder>    AI.REQ and AI.IN on the card (the
                                          folder's VERANDA/.SYSTEM), as
                                          Veranda Write writes them
    check_aireq.py check <run> <folder>   the console's "CL ..." lines, the
                                          fake OpenAI's requests
                                          (srv/requests.jsonl), AI.OUT,
                                          AI.RES, what is left on the card
    check_aireq.py handoff <folder> <kind>  the stand-in's run (tests/ai_standin.c);
                                          the kinds: HANDOFF (V201)

The tasks, the system prompt and the actions' words are read from
apps/ask/rq.c itself; the answers from tests/fake_openai.py's
request_answer, made the way rq.c's out_write writes them.
"""
import importlib.util
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = open(os.path.join(HERE, '..', 'apps', 'ask', 'rq.c'), encoding='utf-8').read()
spec = importlib.util.spec_from_file_location('fake_openai', os.path.join(HERE, 'fake_openai.py'))
fake = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fake)


def c_strings(name):
    """the string literals of rq.c's array or string `name`, in order"""
    i = re.search(r'\b%s\[[A-Z_]*\]\s*=' % re.escape(name), SRC).end()
    out = []
    while True:
        m = re.compile(r'\s*([{},]|"((?:[^"\\]|\\.)*)")', re.S).match(SRC, i)
        if not m:
            break
        if m.group(2) is not None:
            out.append(bytes(m.group(2), 'latin-1').decode('unicode_escape'))
        i = m.end()
    return out


WORDS = c_strings('a_word')
TASKS = c_strings('a_task')
SYS = ''.join(c_strings('rq_sys'))
POLISH = 'Zażółć gęślą jaźń.\rDrugi akapit: ŻÓŁTA ĆMA, ąćęłńóśźż.\r\nTrzeci, z tabem:\tkoniec.'
ENGLISH = 'The quick brown fox jumps over the lazy dog.\n\nIt was a dark and stormy night; the rain fell in torrents.'

# run: (action, question, text (str: ISO-8859-16, or bytes), mode, the result expected, requests expected)
RUNS = {
    'rewrite':   ('rewrite', None, POLISH, 's', 'ok', 1),
    'shorten':   ('shorten', None, ENGLISH, 'k', 'ok', 1),
    'grammar':   ('grammar', None, 'Ths sentense has erors.\rAnd this one to.', 's', 'ok', 1),
    'trans_en':  ('translate-en', None, POLISH, 'r', 'ok', 2),
    'trans_pl':  ('translate-pl', None, ENGLISH, 's', 'ok', 1),
    'summarise': ('summarise', None, ENGLISH, 's', 'ok', 1),
    'ask':       ('ask', 'Czy to zdanie jest poprawne? Odpowiedz krótko.', POLISH, 's', 'ok', 1),
    'cancel':    ('rewrite', None, ENGLISH, 'c', 'cancelled', 1),
    'esc':       ('rewrite', None, POLISH, 'e', 'cancelled', 0),
    'notsetup':  ('rewrite', None, POLISH, 'n', 'error not-set-up', 0),
    'nomodem':   ('grammar', None, POLISH, 's', 'error network', 0),    # (no modem on the port: at Send; V201: network)
    'toolong':   ('rewrite', None, ('Lorem ipsum dolor sit amet. ' * 330), 'n', 'error too-long', 0),
    'badreq':    ('improve', None, ENGLISH, 'n', 'error bad-request', 0),
}


def fail(msg):
    print('FAIL  ' + msg)
    sys.exit(1)


def ok(msg):
    print('ok    ' + msg)


def need(c, msg):
    if not c:
        fail(msg)


def text_in(b):
    """rq.c's text_in: AI.IN's bytes as the store has them"""
    out, cr = [], False
    for c in b:
        if c == 10 and cr:
            cr = False
            continue
        cr = c == 13
        if cr:
            c = 10
        elif c == 9:
            c = 32
        elif (c < 32 and c != 10) or 0x7F <= c < 0xA0:
            continue
        out.append(c)
    return bytes(out).decode('iso8859_16')


def content(action, q, text):
    """the request's message, as rq.c makes it"""
    t = TASKS[WORDS.index(action)]
    if q:
        t += '\nQuestion: ' + q
    return t + '\n\n<<<TEXT\n' + text_in(text) + '\nTEXT>>>'


def out_bytes(answer):
    """rq.c's out_write: the answer as AI.OUT holds it"""
    a = answer
    if len(a) >= 8:
        if a.startswith('<<<TEXT\n'):
            a = a[8:]
        if a.endswith('TEXT>>>'):
            a = a[:-7]
    a = a.strip('\n ')
    return a.replace('\n', '\r').encode('iso8859_16')


def raw_text(t):
    return t if isinstance(t, bytes) else t.encode('iso8859_16')


def prep(run, folder):
    action, q, t, mode, _, _ = RUNS[run]
    d = os.path.join(folder, 'VERANDA', '.SYSTEM')
    os.makedirs(d, exist_ok=True)
    lines = ['AIREQ 1', 'action ' + action]
    if q:
        lines.append('question ' + q)
    lines.append('back Veranda Write')
    open(os.path.join(d, 'AI.REQ'), 'wb').write(('\r\n'.join(lines) + '\r\n').encode('iso8859_16'))
    open(os.path.join(d, 'AI.IN'), 'wb').write(raw_text(t))
    print(mode)


def res_lines(folder):
    p = os.path.join(folder, 'VERANDA', '.SYSTEM', 'AI.RES')
    need(os.path.exists(p), 'no AI.RES')
    b = open(p, 'rb').read()
    need(b.endswith(b'\r\n'), 'AI.RES does not end with CR LF')
    return b.decode('latin-1').split('\r\n')[:-1]


def check(run, folder):
    action, q, t, mode, want, nreq = RUNS[run]
    log = open(os.path.join(folder, 'log.txt'), encoding='utf-8', errors='replace').read()   # (the emulator's echo: UTF-8 of the bytes)
    log = re.sub(r'(?<!\n)CL (?=[A-Z]{2,})', '\nCL ', log).split('\n')
    sysd = os.path.join(folder, 'VERANDA', '.SYSTEM')
    for f in ('AI.REQ', 'AI.IN'):
        need(not os.path.exists(os.path.join(sysd, f)), '%s: %s left on the card' % (run, f))
    need(any(l.startswith('CL RQ REQUEST ' + (action if action in WORDS else '?') + ' back Veranda Write')
             for l in log), '%s: no CL RQ REQUEST' % run)
    need('CL RQ DONE' in [l.strip() for l in log], '%s: Veranda Ask did not end the request (CL RQ DONE)' % run)
    need(any(l.startswith('TERMDESK') for l in log), '%s: the desktop did not come after it' % run)
    # what the fake received
    recs = [json.loads(l) for l in open(os.path.join(folder, 'srv', 'requests.jsonl'))] \
        if os.path.exists(os.path.join(folder, 'srv', 'requests.jsonl')) else []
    turns = [r for r in recs if r.get('path') == '/v1/responses']
    need(len(turns) == nreq, '%s: %d requests to the API, %d expected' % (run, len(turns), nreq))
    exp = content(action, q, raw_text(t)) if nreq else None
    for r in turns:
        need(not r['bad'], '%s: the request: %s' % (run, r['bad']))
        b = r['body']
        need(b['instructions'] == SYS, '%s: the instructions are not rq.c\'s rq_sys: %r' % (run, b['instructions'][:80]))
        need(b['input'] == [{'role': 'user', 'content': exp}],
             '%s: the input %r, expected %r' % (run, b['input'], exp))
        need(b['store'] is False and b['stream'] is True, '%s: store/stream' % run)
        need(r['reply'] == 200, '%s: the fake replied %s' % (run, r['reply']))
    if nreq:
        ok('%s: %d request%s: the system prompt rq_sys (%d characters, no "plain ASCII", no short-answers '
           'sentence), one message: "%s" and the text between its markers (%d characters%s), store false'
           % (run, nreq, 's' if nreq > 1 else '', len(SYS), TASKS[WORDS.index(action)][:40] + '...',
              len(text_in(raw_text(t))), ', the question' if q else ''))
    else:
        ok('%s: nothing sent to the API' % run)
    shown = [l for l in log if l.startswith('CL RQ SHOWN ')]
    rl = res_lines(folder)
    need(rl[0] == 'AIRES 1', '%s: AI.RES %r' % (run, rl))
    need(rl[1] == want, '%s: AI.RES says %r, %r expected' % (run, rl[1], want))
    outp = os.path.join(sysd, 'AI.OUT')
    if want == 'ok':
        need(shown and int(shown[0].split()[-1]) == len(text_in(raw_text(t)).encode('iso8859_16')),
             '%s: CL RQ SHOWN %r' % (run, shown))
        ans = fake.Handler.request_answer(exp)
        ob = out_bytes(ans)
        got = open(outp, 'rb').read() if os.path.exists(outp) else None
        need(got == ob, '%s: AI.OUT %r, expected %r' % (run, got, ob))
        kv = dict(l.split(' ', 1) for l in rl[2:])
        need(kv.get('action') == action and kv.get('bytes') == str(len(ob)) and kv.get('model')
             and kv.get('service') in ('api', 'plan'), '%s: AI.RES %r' % (run, rl))
        pre = [l for l in log if l.startswith('CL MSG a ')]
        need(pre and ans.lstrip('\n')[:20].replace('\n', '|').encode('iso8859_16').decode('latin-1') in pre[-1],
             '%s: the answer previewed: %r' % (run, pre))
        need(any(l.startswith('CL TEST RQ ANSWER 2') for l in log), '%s: no answer to use (rqm 2)' % run)
        ok('%s: the answer streamed into the preview, Use this: AI.OUT (%d bytes, ISO-8859-16, CR) as expected%s; '
           'AI.RES: %s' % (run, len(ob), ' (Polish letters both ways)' if any(c > 127 for c in ob) else '',
                           ', '.join(rl[1:])))
    else:
        need(not os.path.exists(outp), '%s: AI.OUT written' % run)
        if want.startswith('error'):
            need(len(rl) > 2 and rl[2].startswith('message '), '%s: AI.RES has no message: %r' % (run, rl))
            need(any(l.startswith('CL BOX ') for l in log), '%s: no box' % run)
        ok('%s: AI.RES %s; no AI.OUT' % (run, ' | '.join(rl[1:])))
    need(not os.path.exists(os.path.join(folder, 'DOCUMENTS', 'Chats')), '%s: a chat saved' % run)
    return rl


# (V201) the hand-off's runs: how Veranda Ask is set up on the card, and
# what the stand-in reads back
HANDOFF = {
    'api':      'an API key',
    'plan':     'the ChatGPT plan, signed in (a token good for an hour)',
    'renew':    'the ChatGPT plan, its access token expired an hour ago, the clock not set: '
                'refused (401 token_expired), renewed, sent again',
    'renewclk': 'the ChatGPT plan, its access token expired an hour ago, the clock set: renewed before the turn',
    'mem':      'an API key, the switcher in Fast mode, the stand-in holding all but 24 RAM banks: '
                'Veranda Ask starts, vrnet has no two banks',
}


def handoff(folder, kind='api'):
    log = open(os.path.join(folder, 'log.txt'), encoding='utf-8', errors='replace').read()   # (the emulator's echo: UTF-8 of the bytes)
    log = re.sub(r'(?<!\n)CL (?=[A-Z]{2,})', '\nCL ', log).split('\n')
    h = 'handoff %s' % kind
    recs = [json.loads(l) for l in open(os.path.join(folder, 'srv', 'requests.jsonl'))] \
        if os.path.exists(os.path.join(folder, 'srv', 'requests.jsonl')) else []
    seq = [(r['path'], r.get('reply'), r.get('outcome')) for r in recs]
    i = 0
    order = ['STANDIN STARTED', 'STANDIN ASIDE', 'S:START.REQ',    # (the desktop deletes START.REQ, then starts it)
             'CL RQ REQUEST translate-pl back Veranda Write']
    if kind == 'mem':
        order += ['CL BOX Not enough memory for the network card', 'CL RQ DONE', 'CL RQ BACK',
                  'TASK BACK Veranda Write', 'STANDIN BACK']
    else:
        order += ['CL RQ SHOWN', 'CL TEST RQ READY', 'CL RQ ANSWER', 'CL RQ DONE', 'CL RQ BACK',
                  'TASK BACK Veranda Write', 'STANDIN BACK']
    for want in order:
        while i < len(log) and want not in log[i]:
            i += 1
        need(i < len(log), '%s: no %r in the log (in this order)' % (h, want))
    need(not any(l.startswith('CL BOX Veranda Ask is not signed in') or l.startswith('CL BOX Veranda Ask has no')
                 for l in log), '%s: Veranda Ask said it is not set up' % h)
    res = [l.split('STANDIN RES ', 1)[1].strip() for l in log if 'STANDIN RES ' in l]
    sysd = os.path.join(folder, 'VERANDA', '.SYSTEM')
    for f in ('START.REQ', 'AI.REQ', 'AI.IN'):
        need(not os.path.exists(os.path.join(sysd, f)), '%s: %s left' % (h, f))
    need(any(l.startswith('STANDIN FREE ') for l in log) == (kind == 'mem'), '%s: the stand-in\'s banks' % h)
    if kind == 'mem':
        need(res[:2] == ['AIRES 1', 'error network'] and len(res) > 2 and
             res[2].startswith('message Not enough memory for the network card'),
             '%s: AI.RES as the stand-in read it: %r' % (h, res))
        need(not any('STANDIN OUT ' in l for l in log), '%s: an AI.OUT' % h)
        need(not [s for s in seq if s[0] == '/v1/responses'], '%s: sent: %r' % (h, seq))
        ok('%s (%s): the request refused at once, its box; AI.RES %s; not "not-set-up"; nothing sent; Veranda Write '
           'back' % (h, HANDOFF[kind], ' | '.join(res[1:])))
        return
    need(res[:2] == ['AIRES 1', 'ok'], '%s: AI.RES as the stand-in read it: %r' % (h, res))
    need('service ' + ('api' if kind == 'api' else 'plan') in res, '%s: AI.RES %r' % (h, res))
    tok = ('/api/accounts/oauth/token', None, 'rotated')
    exp = {'api': [('/v1/responses', 200, None)], 'plan': [('/v1/responses', 200, None)],
           'renew': [('/v1/responses', 401, None), tok, ('/v1/responses', 200, None)],
           'renewclk': [tok, ('/v1/responses', 200, None)]}[kind]
    need(seq == exp, '%s: the fake received %r, expected %r' % (h, seq, exp))
    if kind.startswith('renew'):
        cfg = open(os.path.join(sysd, 'ASK.CFG'), 'rb').read().decode('latin-1')
        iss = [json.loads(l) for l in open(os.path.join(folder, 'srv', 'issued.jsonl'))]
        need(len(iss) >= 2 and 'access=' + iss[-1]['access'] + '\r\n' in cfg and
             'refresh=' + iss[-1]['refresh'] + '\r\n' in cfg, '%s: the renewed sign-in not in ASK.CFG' % h)
    outl = [l.split('STANDIN OUT ', 1)[1].strip() for l in log if 'STANDIN OUT ' in l]
    text = 'Zażółć gęślą jaźń.\rDrugi akapit: ŻÓŁTA ĆMA.\r'
    exp = content('translate-pl', None, text.encode('iso8859_16'))
    ob = out_bytes(fake.Handler.request_answer(exp))
    need(outl and outl[0] == ob[:50].hex().upper(), '%s: AI.OUT as the stand-in read it %r, expected %s'
         % (h, outl, ob[:50].hex().upper()))
    ok('%s (%s): the desktop started the stand-in as Veranda Write (START.REQ); it wrote AI.IN, AI.REQ, START.REQ '
       'and went aside; the desktop started Veranda Ask; the request shown, Send, Use this; Veranda Write back '
       '(CL RQ BACK, STANDIN BACK): AI.RES %s, AI.OUT the Polish answer byte for byte; the requests deleted; '
       'the fake received %s%s' % (h, HANDOFF[kind], ' | '.join(res[1:4]), ', '.join('%s %s' % (s[0], s[1] or s[2])
                                                                                for s in seq),
                                   '; the renewed sign-in kept in ASK.CFG' if kind.startswith('renew') else ''))

if __name__ == '__main__':
    if sys.argv[1] == 'prep':
        prep(sys.argv[2], sys.argv[3])
    elif sys.argv[1] == 'check':
        check(sys.argv[2], sys.argv[3])
    elif sys.argv[1] == 'handoff':
        handoff(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else 'api')
    elif sys.argv[1] == 'runs':
        print(' '.join(RUNS))
    elif sys.argv[1] == 'handoffs':
        print(' '.join(HANDOFF))
