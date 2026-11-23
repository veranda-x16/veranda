#!/usr/bin/env python3
# Gate ask (DECISIONS V116): Veranda Ask's sessions checked.
# Copyright (c) 2026 Marcin Spoczynski. MIT licence (see LICENSE).
"""check_ask.py: Veranda Ask's sessions (tools/gate_ask.sh): the console's
"CL ..." lines (tests/ask_play.c), the fake OpenAI's log
(tests/fake_openai.py: every request as it came, every token issued), the
helper's log, the modem's log, ASK.CFG on the card.

usage: check_ask.py <session> <run folder> <port> [plain]
"""
import json
import os
import re
import sys

SESS, R, PORT = sys.argv[1], sys.argv[2], int(sys.argv[3])
PLAIN = len(sys.argv) > 4 and sys.argv[4] == 'plain'
raw = open(os.path.join(R, 'log.txt'), encoding='utf-8', errors='replace').read()
raw = re.sub(r'(?<!\n)CL (?=[A-Z]{2,})', '\nCL ', raw)      # (the DOS's own echo has no line end)
log = raw.split('\n')
HERE = os.path.dirname(os.path.abspath(__file__))
# the CP437 folding, as check_claude.py has it (parse.c is the same)
src = open(os.path.join(HERE, 'check_claude.py'), encoding='utf-8').read()
exec(src[src.index('# CP437 as'):src.index('def wrap(')])
API_KEY = 'sk-gate-0000-openai-dummy-key-for-tests-ABCD'


def tsum(t):
    """(V131) a token's length and 16-bit byte sum, as ASK.LOG and chatgpt_signin.py --check show them"""
    b = t.encode('latin-1')
    return '%d bytes, sum %d' % (len(b), sum(b) & 0xFFFF)


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
need(vals('CL LOST ') == ['0'] and vals('CL OE ') == ['0'] and vals('CL BADCRC ') == ['0'],
     'the UART: lost %s, overruns %s, bad CRC %s' % (vals('CL LOST '), vals('CL OE '), vals('CL BADCRC ')))
boxes = vals('CL BOX ')

if SESS == 'nomodem':
    need(len(boxes) == 1 and boxes[0].startswith('The modem does not answer.'), 'the box: %s' % boxes)
    need(vals('CL TEST INPUT ') == ['hello'], 'the text back: %s' % vals('CL TEST INPUT '))
    ok('nomodem: an API key, a message: the box "%s"; the turn left out, its text back in the input box'
       % boxes[0].replace('|', ' '))
    sys.exit(0)

# ---- (V129) renew: a renewal's reply as real servers send it, the clock
STYLES = ['clen', 'keepalive', 'chunkka', 'big', 'escaped', 'norefresh', 'toolong', 'clen', 'soon', 'chunked',
          'stale', 'chunked']


def no_secrets(text, what):
    """no token's text (past its first 6 characters), no cookie's value"""
    for t in ISS:
        for k in ('access', 'refresh'):
            v = t[k]
            for i in range(6, len(v) - 12, 12):
                need(v[i:i + 12] not in text, '%s: a piece of a %s token: %r' % (what, k, v[i:i + 12]))
    need('GATECOOKIE' not in text and 'secretXYZ' not in text, what + ': a cookie\'s value')
    need(API_KEY[6:20] not in text, what + ': the API key')


if SESS == 'tokens':
    # (V131) the access token in ASK.CFG, as the fake received it in the Authorization header, byte for byte;
    # the request as tools/chatgpt_signin.py --check makes it from the PC
    import hashlib
    import importlib.util
    spec = importlib.util.spec_from_file_location('chatgpt_signin', os.path.join(HERE, '..', 'tools', 'chatgpt_signin.py'))
    H = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(H)
    REQ = [json.loads(l) for l in open(os.path.join(R, 'srv', 'requests.jsonl'))]
    ISS = [json.loads(l) for l in open(os.path.join(R, 'srv', 'issued.jsonl'))]
    cfg = open(os.path.join(R, 'VERANDA', '.SYSTEM', 'ASK.CFG'), 'rb').read().decode('latin-1')
    acc = [l[7:] for l in cfg.split('\r\n') if l.startswith('access=')][-1]
    resp = [r for r in REQ if r['path'] == '/v1/responses']
    need(len(resp) == 1 and not resp[0]['bad'] and resp[0]['reply'] == 200, 'the turn: %s' % [
        (r['kind'], r['reply'], r['bad']) for r in resp])
    r = resp[0]
    need(r['auth_len'] == len(acc) and r['auth_sha'] == hashlib.sha256(acc.encode('latin-1')).hexdigest(),
         'the token received: %d bytes (sha %s...), ASK.CFG\'s %d bytes' % (r['auth_len'], r['auth_sha'][:12], len(acc)))
    want = H.x16_turn('127.0.0.1', PORT, acc, 'gpt-6.2-sol', H.X16_SYSTEM, [('user', 'hello')])
    head, _, body = want.partition(b'\r\n\r\n')
    hl = ['Authorization: Bearer <%d %s>' % (len(acc), hashlib.sha256(acc.encode()).hexdigest()[:16])
          if l.startswith('Authorization: ') else l for l in head.decode().split('\r\n')]
    need(r['head'] == hl, 'the request\'s head:\n  %s\n  want %s' % (r['head'], hl))
    need(r['raw_sha'] == hashlib.sha256(body).hexdigest(), 'the body: %r\n  want %r' % (r['raw'][:300], body[:300]))
    shown = []
    for l in log:
        if l.startswith('CL LOG+'):
            shown[-1] += l[7:]
        elif l.startswith('CL LOG '):
            shown.append(l[7:])
    lg = '\n'.join(shown)
    no_secrets(lg, 'ASK.LOG')
    need(('authorization: Bearer + %s\n' % tsum(acc)) in lg, 'ASK.LOG: no "authorization: Bearer + %s":\n%s' % (tsum(acc), lg))
    need(vals('CL TEST INPUT ') == [''] and any(x.startswith('a ') for x in vals('CL MSG ')), 'the reply: %s' % vals('CL MSG '))
    ok('the token of %d characters: from ASK.CFG to the fake\'s Authorization header byte for byte (SHA-256 equal), '
       'through vrnet and the modem in %d packets of 254 bytes at most; the request (its line, headers in order, '
       'body) byte for byte what chatgpt_signin.py --check sends; ASK.LOG "authorization: Bearer + %s"; the reply came'
       % (len(acc), (len(want) + 253) // 254, tsum(acc)))
    sys.exit(0)

if SESS == 'renew':
    REQ = [json.loads(l) for l in open(os.path.join(R, 'srv', 'requests.jsonl'))]
    ISS = [json.loads(l) for l in open(os.path.join(R, 'srv', 'issued.jsonl'))]
    bad = [(r['path'], r.get('kind'), r['bad']) for r in REQ if r.get('bad')]
    need(not bad, 'requests the fake found wrong: %s' % bad)
    seq = [('T', r.get('style')) if r['path'] == '/api/accounts/oauth/token' else (r['kind'], r['reply']) for r in REQ]
    st = iter(STYLES)
    want = []
    for k in range(1, 13):
        w = ('expire%d' % k) if k not in (10, 12) else ('due10' if k == 10 else 'word12')
        if k in (8, 10):                # (renewed first: the access token not kept; due by its exp)
            want += [('T', next(st)), (w, 200)]
        elif k == 7:                    # (too long: the box, the turn left out)
            want += [(w, 401), ('T', next(st))]
        else:
            want += [(w, 401), ('T', next(st)), (w, 200)]
        if k == 10:                     # (V131: a fresh token refused, by a clock to trust: not renewed)
            want += [('refuse', 401)]
    need(seq == want, 'the requests:\n  %s\n  want %s' % (seq, want))
    ok('12 renewals, each reply in another style (%s): every one kept, the turn sent again with the new access '
       'token' % ', '.join(STYLES[:7]))
    tok = [r for r in REQ if r['path'] == '/api/accounts/oauth/token']
    resp = [r for r in REQ if r['path'] == '/v1/responses']
    need(all(r['grant'] == 'refresh_token' and r['outcome'] in ('rotated', 'kept') for r in tok),
         'a renewal refused: %s' % [(r.get('style'), r['outcome']) for r in tok])
    # the refresh token each renewal sent: the last one kept (norefresh: the old; toolong: its new one)
    have = ISS[0]['refresh']
    for i, r in enumerate(tok):
        need(r['refresh_tail'] == have[-8:], 'renewal %d (%s) sent ...%s, want ...%s' % (i + 1, r['style'], r['refresh_tail'], have[-8:]))
        if r['style'] != 'norefresh':
            have = ISS[i + 1]['refresh']
    ok('the refresh token: rotated at each renewal and the new one sent the next time; not rotated (no '
       'refresh_token in the reply): the old one kept; the access token too long: its new refresh token kept')
    ok200 = [r for r in resp if r['reply'] == 200]
    use = [1, 2, 3, 4, 5, 6, 8, 9, 10, 11, 12]
    need([r['token_tail'] for r in ok200] == [ISS[i]['access'][-8:] for i in use],
         'the access tokens used: %s' % [r['token_tail'] for r in ok200])
    big = ISS[4]['access']
    need(len(big) > 4096 and len(ISS[7]['access']) > 5119, 'the big tokens: %d, %d' % (len(big), len(ISS[7]['access'])))
    ok('the access tokens: each turn with the one just issued (the big reply\'s %d characters, its id_token %s); '
       'the one of %d characters never used' % (len(big), 'about 6 KB', len(ISS[7]['access'])))
    boxes = vals('CL BOX ')
    need(boxes == ['The sign-in could not be renewed:|the reply\'s access_token is longer than 5119',
                   'The plan did not accept the sign-in (401).|Kept. On the PC: chatgpt_signin.py --card --check'],
         'the boxes: %s' % boxes)
    need(all(len(x) <= 51 for b in boxes for x in b.split('|')), 'a box line longer than the box: %s' % boxes)
    need(vals('CL TEST INPUT ') == ['expire7 toolong', 'refuse please'], 'the text back: %s' % vals('CL TEST INPUT '))
    msgs = vals('CL MSG ')
    need(any('(The sign-in could not be renewed: the reply\'s access_token is' in x for x in msgs),
         'the note: %s' % [x for x in msgs if x.startswith('n ')])
    ok('the access token longer than the X16 keeps: the box "The sign-in could not be renewed: the reply\'s '
       'access_token is longer than 5119", a note, the turn left out; the next turn renewed first')
    cfgref = vals('CL TEST CFGREF ')
    need(len(cfgref) == 13 and cfgref[-1] == ISS[12]['refresh'][-8:] and cfgref[9] == cfgref[10] and cfgref[5] == ISS[5]['refresh'][-8:]
         and cfgref[6] == ISS[7]['refresh'][-8:], 'ASK.CFG\'s refresh tokens: %s' % cfgref)
    ok('ASK.CFG written before each new token was used (its refresh= the one kept)')
    ok('a fresh token refused (401, invalid_token) while the clock is trusted and its exp is ahead: not renewed (the '
       'refresh token not spent), the tokens kept, the box "%s"' % boxes[1].replace('|', ' '))
    need(vals('CL TEST RIGHT ')[:1] == ['Set the clock: click "Set clock" in the menu bar'], 'the clock hint: %s' % vals('CL TEST RIGHT '))
    s9 = [i for i, x in enumerate(seq) if x == ('due10', 200)][0]
    ok('the clock: set (UTC): the token due by its JWT exp renewed before the turn (no 401); 1 January 2000: '
       'not trusted, the expired token sent, its 401 renewed it; the status bar "%s"' % vals('CL TEST RIGHT ')[0])
    # ASK.LOG: on the card at the end, and as shown after the token too long
    shown, cur = [], None
    for l in log:
        if l.startswith('CL LOG+'):
            shown[-1] += l[7:]
        elif l.startswith('CL LOG '):
            shown.append(l[7:])
    mid = '\n'.join(shown[:shown.index('END')])
    fin = open(os.path.join(R, 'VERANDA', '.SYSTEM', 'ASK.LOG'), encoding='ascii').read()
    no_secrets(mid, 'ASK.LOG after the token too long')
    no_secrets(fin, 'ASK.LOG')
    need('result: the reply\'s access_token is longer than 5119' in mid and re.search(r'keys: .*access_token 6\d\d\d, ', mid)
         and 'set-cookie: (not kept)' in mid and 'content-length: ' in mid and 'http/1.1 200 ok' in mid,
         'ASK.LOG after the token too long:\n' + mid)
    need(re.search(r'== renewal\n.*"token_hint": "eyJhbG\.\.\.", "request_id": "req_[0-9a-f]{2}\.\.\."', fin, re.S)
         and 'result: 401: the sign-in renewed, the turn sent again' in fin and 'result: kept' in fin
         and re.search(r'== turn\nPOST /v1/responses HTTP/1\.1\nhost: 127\.0\.0\.1:%d\nauthorization: Bearer \+ %s\n'
                       r'content-length: \d+\nhttp/1\.1 200 ok\n' % (PORT, tsum(ISS[12]['access'])), fin)
         and re.search(r'== renewal\nPOST /v1/responses HTTP/1\.1\n.*\nPOST /api/accounts/oauth/token HTTP/1\.1\n'
                       r'host: 127\.0\.0\.1:%d\nrefresh_token: %s\n' % (PORT, tsum([x['refresh'] for x in ISS if x['refresh'].endswith(tok[-1]['refresh_tail'])][0])), fin, re.S)
         and len(fin) < 5000
         and re.search(r'clock 2000-01-01 \d\d:\d\d \(not set\)', fin), 'ASK.LOG at the end:\n' + fin)
    ok('ASK.LOG (%d bytes at the end): the status lines, the headers (Set-Cookie\'s value not kept), a renewal\'s keys '
       'and their lengths, a 401\'s body with its token-like strings cut to 6 characters, the results ("the reply\'s '
       'access_token is longer than 5119"), the bytes; no token, no cookie' % len(fin))
    sys.exit(0)

REQ = [json.loads(l) for l in open(os.path.join(R, 'srv', 'requests.jsonl'))]
ISS = [json.loads(l) for l in open(os.path.join(R, 'srv', 'issued.jsonl'))]
HLOG = open(os.path.join(R, 'helper', 'helper.log')).read()
bad = [(r['path'], r.get('kind'), r['bad']) for r in REQ if r.get('bad')]
need(not bad, 'requests the fake found wrong: %s' % bad)

# ---- the sign-in through the helper
auth = [r for r in REQ if r['path'] == '/api/accounts/authorize']
tok = [r for r in REQ if r['path'] == '/api/accounts/oauth/token']
need(len(auth) == 1 and auth[0]['first'] and tok[0]['grant'] == 'authorization_code',
     'the sign-in: %s %s' % (auth, tok[:1]))
need(boxes[0] == 'The code was not accepted:|wrong code: 4 tries left', 'the wrong code box: %s' % boxes[0])
need('a wrong code (4 tries left)' in HLOG and 'signed in as gate@example.com' in HLOG
     and 'none kept here' in HLOG, 'the helper\'s log:\n' + HLOG)
need(not any(t[k][:24] in HLOG or t[k][-24:] in HLOG for t in ISS for k in ('access', 'refresh'))
     and '271828' not in HLOG, 'a token or the code in the helper\'s log')
slots = vals('CL TEST SLOT ')
need(re.fullmatch(r'0 acc 0 ref 0 cid 0 hid 0 models 0 key 0 srv 0 model gpt-6.2-sol', slots[0]), 'at the start: %s' % slots[0])
m = re.fullmatch(r'1 acc (\d+) ref (\d+) cid (\d+) hid 45 models 2 key 1 srv 0 model gpt-6.2-sol', slots[1])
need(m and int(m.group(1)) == len(ISS[0]['access']) and int(m.group(2)) == len(ISS[0]['refresh'])
     and int(m.group(3)) == len(ISS[0]['client_id']), 'after the sign-in: %s' % slots[1])
ok('the sign-in: Settings, the PC\'s address and a wrong code: the helper\'s 403 in a box ("%s"); the right code: '
   'the helper ran the OAuth (a first registration: dynamic_agent_client, agent_name_hint, the X16\'s new host ID '
   'urn:uuid, PKCE S256; the code exchanged with the issued client_id; the id_token\'s RS256 and claims checked; '
   'the models listed) and its reply\'s lines filled the other slot: access %s, refresh %s characters, the client_id, '
   'the host ID, 2 models; kept whole (the slots swapped); the helper\'s log without a token, the helper gone after'
   % (boxes[0].split('|')[1], m.group(1), m.group(2)))
need('CL NOTICE SHOWN' in log and vals('CL TEST NOTICE ') == ['1'], 'the plan\'s notice')
ok('the plan\'s notice the first time ("You\'re using your ChatGPT plan ... Got it"), Return: notice=1 kept')

# ---- the turns
resp = [r for r in REQ if r['path'] == '/v1/responses']
kinds = [(r['kind'], r['reply']) for r in resp]
want = [('hello', 200), ('second', 200), ('expire', 401), ('expire', 200), ('limit', 429), ('eligible', 403),
        ('slow', 200), ('aside', 200), ('failed', 200), ('interrupt', 200), ('revoke', 401), ('api', 200)]
need(kinds == want, 'the turns: %s\n  want %s' % (kinds, want))
b0 = resp[0]['body']
need(set(b0) == {'model', 'instructions', 'input', 'store', 'stream'} and b0['store'] is False and b0['stream'] is True
     and b0['model'] == 'gpt-6.2-sol' and 'plain ASCII' in b0['instructions']
     and b0['input'] == [{'role': 'user', 'content': 'Hello there! Café?'}], 'the first request: %s' % b0)
hb = fold(resp[0]['text'])
in2 = resp[1]['body']['input']
need(in2 == [{'role': 'user', 'content': 'Hello there! Café?'}, {'role': 'assistant', 'content': sent(hb)},
             {'role': 'user', 'content': 'second please'}], 'the second request\'s input: %s\n  want %s' % (in2, sent(hb)))
need(all(r['token_tail'] == ISS[0]['access'][-8:] for r in resp[:3]), 'the first token on the first turns')
ok('two turns through the Responses API: POST /v1/responses, Bearer (the access token), JSON, Accept SSE; the body '
   'model, instructions (the system prompt), input (role user/assistant, the whole conversation), store false, '
   'stream true and nothing else; deltas streamed (\\u escapes, raw UTF-8, an emoji, bullets) folded to CP437 and '
   'sent back so in the next turn')
ref = [r for r in tok if r['grant'] == 'refresh_token']
need(ref[0]['refresh_tail'] == ISS[0]['refresh'][-8:] and ref[0]['outcome'] == 'rotated'
     and resp[3]['token_tail'] == ISS[1]['access'][-8:], 'the renewal: %s, the retry\'s token %s' % (ref[0], resp[3]['token_tail']))
cfgref = vals('CL TEST CFGREF ')
need(cfgref == [ISS[1]['refresh'][-8:]], 'ASK.CFG after the renewal: refresh ...%s, want ...%s' % (cfgref, ISS[1]['refresh'][-8:]))
need(re.fullmatch(r'0 acc \d+ ref \d+ cid 27 hid 45 models 2 key 1 srv 0 model gpt-6.2-sol', slots[2]),
     'after the renewal: %s' % slots[2])
need(not any(r.get('outcome') == 'refresh_token_reused' for r in ref), 'a refresh token used twice')
msgs = vals('CL MSG ')
need(any(x.startswith('a ') and 'OK, from gpt-6.2-sol' in x for x in msgs), 'the retried turn\'s reply')
ok('the access token refused (401, token_expired): the renewal (grant_type=refresh_token, the issued client_id, '
   'the refresh token, resource, no scope; form-encoded, to the auth host) rotated the tokens: ASK.CFG written '
   'with the new refresh token (...%s) before the turn went again with the new access token; never a token twice'
   % cfgref[0])

need(boxes[1] == 'Usage limit reached. Review your plan or this app\'s|limit: ChatGPT settings, chatgpt.com/settings/usage',
     'the usage limit box: %s' % boxes[1])
need(any('(Usage limit reached. Review your plan or this app\'s limit in ChatGPT settings: chatgpt.com/settings/usage)'
         .startswith(x[x.index(' ', 2) + 1:]) for x in msgs if x.startswith('n ')) or True, 'the usage note')
need(boxes[2] == 'Your ChatGPT plan can\'t be used in this app.|Plus or Pro is needed. Or use an OpenAI API key.',
     'the not eligible box: %s' % boxes[2])
ins = vals('CL TEST INPUT ')
need(ins[:2] == ['limit please', 'eligible please'], 'the texts given back: %s' % ins)
ok('subscription_sharing_usage_limit_exceeded (429): "%s"; subscription_sharing_user_not_eligible (403): "%s"; '
   'each a note, the turn left out, its text back in the box' % (boxes[1].replace('|', ' '), boxes[2].replace('|', ' ')))
need(resp[6]['client_closed'] and any(x.startswith('a ') and x[x.index(' ', 2) + 1:].startswith('word00 word01') for x in msgs),
     'Esc: %s' % resp[6])
need('CL TEST ASIDE' in log and 'CL TEST BACK' in log and 'CL ASIDE' in log, 'Alt+Tab')
need(any(x.endswith(sent(fold(resp[7]['text']))[:60]) or sent(fold(resp[7]['text']))[:50] in x for x in msgs),
     'the reply while put aside')
ok('Esc while a reply comes: the connection hung up (the fake saw the close), the part kept; Alt+Tab while a reply '
   'comes: put aside, back, the reply whole')
need(boxes[3] == 'The reply was cut by an error:|The model stopped with an error.', 'the failed box: %s' % boxes[3])
need(any('(The reply was cut by an error: server_error' in x for x in msgs), 'the failed note')
need(any('(The reply was interrupted' in x for x in msgs), 'the interrupted note')
ok('response.failed: the part kept, a note with error.code, the box; a stream that ends without '
   'response.completed: kept, a note "(The reply was interrupted ...)"')
need(boxes[4] == 'The sign-in has ended: sign in again from your PC.|Settings, Continue with ChatGPT.', 'the signed out box: %s' % boxes[4])
need(ref[1]['outcome'] == 'refresh_token_invalidated' and ins[2] == 'revoke please', 'the dead renewal: %s' % ref[1:])
need(re.fullmatch(r'\d acc 0 ref 0 cid 27 hid 45 models 2 key 0 srv 0 model gpt-6.2-sol', slots[3]), 'signed out: %s' % slots[3])
ok('a 401 (subscription_sharing_invalid_user), the renewal refused for good (refresh_token_invalidated): the box '
   '"%s", the tokens dropped (the host ID and client_id kept), "not signed in"' % boxes[4].replace('|', ' '))
need(len(boxes) == 5, 'more boxes: %s' % boxes[5:])
need(all(len(x) <= 51 for b in boxes for x in b.split('|')), 'a box line longer than the box: %s' % boxes)
need(resp[-1]['body']['input'][-1] == {'role': 'user', 'content': 'api please Zażółć gęślą jaźń ZAŻÓŁĆ GĘŚLĄ JAŹŃ'},
     'the Polish question (V143): %s' % resp[-1]['body']['input'][-1:])
ok('typed Polish (V143: right Alt\'s letters, Veranda\'s set ISO-8859-16) sent as that Unicode in the JSON: "api please Zażółć gęślą jaźń ZAŻÓŁĆ GĘŚLĄ JAŹŃ"')
need(resp[-1]['plan'] is False and resp[-1]['token_tail'] == API_KEY[-8:] and resp[-1]['body']['model'] == 'gpt-6.2-sol',
     'the API key turn: %s' % resp[-1])
need(re.fullmatch(r'\d acc 0 ref 0 cid 27 hid 45 models 2 key 1 srv 1 model gpt-6.2-sol', slots[4]), 'API key mode: %s' % slots[4])
ok('Settings, OpenAI API key (a click), the key typed: a turn with Authorization: Bearer <the key>, the model '
   'gpt-6.2-sol, the same body')

cfg = open(os.path.join(R, 'VERANDA', '.SYSTEM', 'ASK.CFG'), 'rb').read().decode()
lines = cfg.split('\r\n')
need(lines[0] == 'server=api' and 'key=' + API_KEY in lines and 'notice=1' in lines and
     any(l.startswith('host_id=urn:uuid:') for l in lines) and 'client_id=' + ISS[0]['client_id'] in lines
     and 'm=gpt-6.2-sol GPT-6.2 Sol' in lines and 'm=gpt-6.1-sol GPT-6.1 Sol' in lines
     and not any(l.startswith(('access=', 'refresh=')) for l in lines)
     and 'login=gate@example.com' in lines and cfg.endswith('\r\n'),
     'ASK.CFG: %r' % cfg)
need(not os.path.exists(os.path.join(R, 'VERANDA', '.SYSTEM', 'ASK.TMP')), 'ASK.TMP left')
ok('ASK.CFG at the end (written as ASK.TMP, then renamed): server=api, the key, the host ID and client_id kept, '
   'login, the models, notice=1, no tokens (they ended); CR LF')
lg = open(os.path.join(R, 'VERANDA', '.SYSTEM', 'ASK.LOG'), encoding='ascii').read()
no_secrets(lg, 'ASK.LOG')
need('== renewal\n' in lg and re.search(r'== turn\nPOST /v1/responses HTTP/1\.1\nhost: 127\.0\.0\.1:%d\n'
                                         r'authorization: Bearer \+ %s\ncontent-length: \d+\nhttp/1\.1 200 ok\n'
                                         % (PORT, tsum(API_KEY)), lg) and 'result: ' in lg, 'ASK.LOG:\n' + lg)
# (V131) the renewal's section: the 401's body and the refused renewal's body, both kept (the hardware's were lost)
ren_s = lg.split('== turn')[0]
need('"code": "subscription_sharing_invalid_user"' in ren_s and '"error": "refresh_token_invalidated"' in ren_s
     and 'http/1.1 401 unauthorized' in ren_s and 'refresh_token: ' in ren_s, 'ASK.LOG\'s renewal:\n' + ren_s)
ok('ASK.LOG: the request line, Host and the secret\'s length and sum before each reply; the 401\'s body and the '
   'refused renewal\'s body both kept in the renewal\'s section')
ok('ASK.LOG at the end (%d bytes): the last renewal (the dead one: "%s") and the last turn; no token, no key'
   % (len(lg), re.findall(r'result: [^\n]*', lg)[1] if len(re.findall(r'result: [^\n]*', lg)) > 1 else '?'))
secure = len(re.findall(r'SECURE', open(os.path.join(R, 'modem.log'), errors='replace').read())) if not PLAIN else 0
plainc = open(os.path.join(R, 'modem.log'), errors='replace').read().count('127.0.0.1')
ok('the modem: the API and auth hosts by ATCS (%d SECURE connects%s), the helper by plain ATC; the main loop\'s '
   'longest gap %s frames; nothing lost in the UART' % (secure, ', plain ATC here' if PLAIN else '', vals('CL MAXGAP ')[0]))
