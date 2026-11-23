#!/usr/bin/env python3
# Gate ask (DECISIONS V116): tools/chatgpt_signin.py on its own, on the host.
# Copyright (c) 2026 Marcin Spoczynski. MIT licence (see LICENSE).
"""test_chatgpt_signin.py: Veranda Ask's sign-in helper against a fake of
OpenAI's sign-in (tests/fake_openai.py, its test-only RSA key) and a fake
browser (tests/fake_browser.py): never the real servers. PKCE, the RS256
check of the id_token (and every way it can be wrong), the registration
and the sign-in again, every refusal (declined, no client_id, another
client_id, no plan scope, the state), the X16's request over HTTP (the
code, its tries, the keepalive lines, the credential set, the server gone
after it), --card, the log without a token. Run under python3 -I.

usage: test_chatgpt_signin.py <scratch folder>
"""
import contextlib
import hashlib
import importlib.util
import io
import json
import os
import socket
import sys
import threading
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


H = load('chatgpt_signin', os.path.join(HERE, '..', 'tools', 'chatgpt_signin.py'))
F = load('fake_openai', os.path.join(HERE, 'fake_openai.py'))
D = os.path.abspath(sys.argv[1])
os.makedirs(D, exist_ok=True)
fails = 0
ERR = io.StringIO()                     # (the helper's log: checked for tokens at the end)


def check(c, msg):
    global fails
    print(('ok    ' if c else 'FAIL  ') + msg)
    if not c:
        fails += 1


def free_port():
    s = socket.socket()
    s.bind(('127.0.0.1', 0))
    p = s.getsockname()[1]
    s.close()
    return p


W = F.World(D)
srv = F.serve(W)
BASE = W.issuer


class A:
    issuer = BASE
    authorize_url = BASE + '/api/accounts/authorize'
    token_url = BASE + '/api/accounts/oauth/token'
    revoke_url = BASE + '/api/accounts/oauth/revoke'
    jwks_url = BASE + '/.well-known/jwks.json'
    models_url = BASE + '/v1/models'
    callback_port = free_port()
    browser = '%s -I -B %s' % (sys.executable, os.path.join(HERE, 'fake_browser.py'))


EP = H.Endpoints(A)
HID = 'urn:uuid:12345678-1234-4abc-8def-1234567890ab'

# ------------------------------------------------------------------ the pieces
v, c = H.pkce()
check(len(v) == 43 and len(c) == 43 and '=' not in v + c and H.b64u(hashlib.sha256(v.encode()).digest()) == c,
      'PKCE: a 43-character verifier, its challenge base64url(SHA-256) without padding')
good = ['127.0.0.1', '10.0.0.5', '172.20.1.1', '192.168.1.30', '::1', 'fd00::1', '::ffff:10.1.1.1']
bad = ['8.8.8.8', '172.32.0.1', '100.64.0.1', '2001:db8::1', '::ffff:1.1.1.1', '', 'x']
check(all(H.allowed_client(a) for a in good) and not any(H.allowed_client(a) for a in bad),
      'the address filter: private addresses only (%d allowed, %d refused)' % (len(good), len(bad)))
signed = b'header.payload'
sig = F.sign_rs256(signed)
check(H.rs256_ok(F.N, F.E, signed, sig), 'RS256: a good signature verifies (pow(sig, e, n), PKCS#1 v1.5, the SHA-256 DigestInfo)')
check(not H.rs256_ok(F.N, F.E, b'header.payloaX', sig) and not H.rs256_ok(F.N, F.E, signed, sig[:-1])
      and not H.rs256_ok(F.N, F.E, signed, bytes([sig[0] ^ 1]) + sig[1:])
      and not H.rs256_ok(F.N, 3, signed, sig) and not H.rs256_ok(F.N, F.E, signed, (F.N + 1).to_bytes(256, 'big')),
      'RS256: refused for other data, a short signature, a flipped bit, another exponent, s >= n')
# a signature over an encoding with other padding (no FF bytes): refused
t = bytes.fromhex('3031300d060960864801650304020105000420') + hashlib.sha256(signed).digest()
em = b'\x00\x01' + b'\x00' * (256 - len(t) - 3) + b'\x00' + t
check(not H.rs256_ok(F.N, F.E, signed, pow(int.from_bytes(em, 'big'), F.D, F.N).to_bytes(256, 'big')),
      'RS256: the padding checked exactly (00 01 FF..FF 00, not 00 01 00..00 00)')
now = int(time.time())
cl = {'iss': BASE, 'aud': 'oaiapp_x', 'exp': now + 60, 'nonce': 'n1', 'email': 'a@b.c'}
J = F.jwks()
check(H.verify_id_token(F.jwt(cl), J, BASE, 'oaiapp_x', 'n1')['email'] == 'a@b.c'
      and H.verify_id_token(F.jwt(dict(cl, aud=['oaiapp_x', 'other'])), J, BASE, 'oaiapp_x', 'n1'),
      'the id_token: its signature (the JWKS key by kid), iss, aud (a string or a list), exp, nonce')


def refused(tok, why, **kw):
    try:
        H.verify_id_token(tok, kw.get('jwks', J), BASE, 'oaiapp_x', 'n1')
    except H.SignInError as e:
        return why in str(e)
    return False


check(refused(F.jwt(cl, bad_sig=True), 'signature') and refused(F.jwt(dict(cl, iss='https://x')), 'issuer')
      and refused(F.jwt(dict(cl, aud='oaiapp_y')), 'client') and refused(F.jwt(dict(cl, exp=now - 600)), 'expired')
      and refused(F.jwt(dict(cl, nonce='n2')), 'nonce') and refused(F.jwt(cl, kid='other'), 'signature')
      and refused('a.b', 'JWT') and refused(F.jwt(cl), 'signature', jwks={'keys': []}),
      'the id_token refused: a bad signature, another issuer, another audience, expired, another nonce, '
      'an unknown kid, not a JWT, no keys')
alg_none = H.b64u(json.dumps({'alg': 'none'}).encode()) + '.' + H.b64u(json.dumps(cl).encode()) + '.'
check(refused(alg_none, 'RS256'), 'the id_token refused: alg "none"')

# ------------------------------------------------------------------ the sign-in itself
with contextlib.redirect_stderr(ERR), contextlib.redirect_stdout(io.StringIO()):
    cred = H.sign_in(EP, HID)
auth = [r for r in W.records if r['path'] == '/api/accounts/authorize']
check(cred['client_id'].startswith('oaiapp_') and cred['host_id'] == HID and cred['login'] == F.EMAIL
      and cred['expires'] == 3600 and len(cred['access']) > 2000 and cred['refresh'].startswith('rt_'),
      'a first registration: the client_id issued (%s), the tokens (access %d characters), the account, expires_in'
      % (cred['client_id'], len(cred['access'])))
check(auth[-1]['first'] and not auth[-1]['bad'] and auth[-1]['host_id'] == HID,
      'its authorize request: client_id dynamic_agent_client, agent_name_hint "Veranda Ask", ext_agent_host_id, '
      'the scope, resource, state, nonce, S256 (checked by the fake: %s)' % (auth[-1]['bad'] or 'nothing wrong'))
tokreq = [r for r in W.records if r['path'] == '/api/accounts/oauth/token']
check(tokreq[-1]['grant'] == 'authorization_code' and not tokreq[-1]['bad'],
      'its token exchange: form-encoded, the issued client_id (never dynamic_agent_client), code, code_verifier, '
      'the same redirect_uri, resource, no secret')
check(cred['models'] == [('gpt-6.2-sol', 'GPT-6.2 Sol'), ('gpt-6.1-sol', 'GPT-6.1 Sol')],
      'the models: visibility "list" only, in the server\'s order: %s' % cred['models'])
with contextlib.redirect_stderr(ERR), contextlib.redirect_stdout(io.StringIO()):
    cred2 = H.sign_in(EP, HID, cred['client_id'], cred['login'])
check(cred2['client_id'] == cred['client_id'] and not auth[-1]['bad'] and not W.records[-1].get('bad'),
      'a sign-in again: the saved client_id, login_hint, no agent_name_hint; the callback without client_id taken')
auth = [r for r in W.records if r['path'] == '/api/accounts/authorize']
check(not auth[-1]['first'] and auth[-1]['login_hint'] == F.EMAIL, 'its authorize request: login_hint %s' % auth[-1]['login_hint'])


def fails_with(mode, why, client=''):
    W.mode = mode
    try:
        with contextlib.redirect_stderr(ERR), contextlib.redirect_stdout(io.StringIO()):
            H.sign_in(EP, HID, client)
    except H.SignInError as e:
        W.mode = ''
        return why in str(e), str(e)
    W.mode = ''
    return False, 'signed in'


for mode, why, cid in [('deny', 'declined', ''), ('noclient', 'registration did not finish', ''),
                       ('otherclient', 'another client_id', 'X'), ('noscope', 'plan use was not granted', ''),
                       ('badsig', 'signature', ''), ('badnonce', 'nonce', ''), ('badaud', 'another client', ''),
                       ('badstate', 'not this sign-in', '')]:
    ok, said = fails_with(mode, why, cred['client_id'] if cid else '')
    check(ok, 'refused when the fake does "%s": %s' % (mode, said))
check(any(r['path'] == '/api/accounts/oauth/revoke' and r['known'] for r in W.records),
      'no plan scope: the tokens revoked at once')

# ------------------------------------------------------------------ the X16's request over HTTP
def post(port, body, timeout=30):
    s = socket.create_connection(('127.0.0.1', port), timeout=timeout)
    s.sendall(('POST /x16/signin HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/x-www-form-urlencoded\r\n'
               'Content-Length: %d\r\nConnection: close\r\n\r\n%s' % (len(body), body)).encode())
    out = b''
    while True:
        d = s.recv(4096)
        if not d:
            break
        out += d
    s.close()
    head, _, rest = out.partition(b'\r\n\r\n')
    st = int(head.split()[1])
    if b'chunked' in head.lower():
        txt = b''
        while rest:
            n, _, rest = rest.partition(b'\r\n')
            n = int(n, 16)
            txt += rest[:n]
            rest = rest[n + 2:]
            if not n:
                break
        rest = txt
    return st, rest.decode()


def kv(text):
    return dict(l.split('=', 1) for l in text.splitlines() if '=' in l)


S = H.make_server('127.0.0.1', 0, '271828', EP, wait=60, keepalive=0.3)
port = S.server_address[1]
th = threading.Thread(target=S.serve_forever, daemon=True)
th.start()
with contextlib.redirect_stderr(ERR), contextlib.redirect_stdout(io.StringIO()):
    st, t = post(port, 'code=000000&host_id=&client_id=&login=')
    check(st == 403 and kv(t).get('end') == 'fail' and 'wrong code: 4 tries left' in t,
          'a wrong code: 403, "error=wrong code: 4 tries left", end=fail')
    st, t = post(port, 'code=271828&host_id=nonsense&client_id=&login=')
    check(st == 400 and 'urn:uuid' in t, 'a host ID that is not a urn:uuid: 400')
    W.mode = 'slow'
    st, t = post(port, 'code=271828&host_id=&client_id=&login=')
    W.mode = ''
k = kv(t)
check(st == 200 and k.get('end') == 'ok' and H.HOST_ID_RE.fullmatch(k.get('host_id', '')) and
      k.get('client_id', '').startswith('oaiapp_') and len(k.get('access', '')) > 2000 and k.get('refresh', '').startswith('rt_')
      and k.get('expires') == '3600' and k.get('login') == F.EMAIL,
      'the right code (the X16 without a host ID): 200, chunked lines: a new host_id (%s), client_id, login, '
      'expires, the models, access, refresh, end=ok' % k.get('host_id'))
check(t.count('wait=1') >= 3 and t.index('wait=1') < t.index('client_id='),
      'while the browser signs in: a keepalive line "wait=1" every keepalive (%d of them)' % t.count('wait=1'))
check([l for l in t.splitlines() if l.startswith('m=')] == ['m=gpt-6.2-sol GPT-6.2 Sol', 'm=gpt-6.1-sol GPT-6.1 Sol'],
      'the models as lines m=<slug> <name>')
th.join(5)
check(not th.is_alive() and S.done, 'after the credentials went, the helper stops (it keeps nothing)')
S.server_close()
S = H.make_server('127.0.0.1', 0, '271828', EP, wait=60, keepalive=0.3)
port = S.server_address[1]
th = threading.Thread(target=S.serve_forever, daemon=True)
th.start()
with contextlib.redirect_stderr(ERR), contextlib.redirect_stdout(io.StringIO()):
    for i in range(5):
        st, t = post(port, 'code=11111%d' % i)
check(st == 403 and 'too many' in t, 'five wrong codes: "too many wrong codes"; the helper stops')
th.join(5)
check(not th.is_alive(), 'and it has stopped')
S.server_close()

# ------------------------------------------------------------------ --card
V = os.path.join(D, 'card', 'VERANDA')
os.makedirs(os.path.join(V, '.SYSTEM'), exist_ok=True)
with open(os.path.join(V, '.SYSTEM', 'ASK.CFG'), 'wb') as f:
    f.write(('server=api\r\nkey=%s\r\nnotice=1\r\nhost_id=%s\r\naccess=old\r\nrefresh=old\r\nm=old Old\r\n'
             % (F.API_KEY, HID)).encode())
argv = ['--card', V, '--issuer', BASE, '--authorize-url', A.authorize_url, '--token-url', A.token_url,
        '--revoke-url', A.revoke_url, '--jwks-url', A.jwks_url, '--models-url', A.models_url,
        '--callback-port', str(A.callback_port), '--browser', A.browser]
with contextlib.redirect_stderr(ERR), contextlib.redirect_stdout(io.StringIO()):
    H.main(argv)
raw = open(os.path.join(V, '.SYSTEM', 'ASK.CFG'), 'rb').read().decode()
c = raw.split('\r\n')
k = kv(raw.replace('\r\n', '\n'))
check(c[0] == 'server=plan' and 'key=' + F.API_KEY in c and 'notice=1' in c and k.get('host_id') == HID
      and 'access=old' not in c and 'm=old Old' not in c and len(k.get('access', '')) > 2000
      and c.index('access=' + k['access']) > c.index('expires=3600') and k.get('got', '').isdigit()
      and not os.path.exists(os.path.join(V, '.SYSTEM', 'ASK.TMP')),
      '--card: ASK.CFG written on the card (ASK.TMP renamed): server=plan, the key and notice kept, the card\'s '
      'host_id used, the old tokens and models replaced, got= by this PC\'s clock, CR LF')

# ------------------------------------------------------------------ --check (V131)
PORT = int(BASE.rsplit(':', 1)[1])


def run_check(name, mode='', early=0):
    """--card ... --check against the fake: (exit code, stdout, the card's ASK.CFG as key=value)"""
    v = os.path.join(D, name, 'VERANDA')
    os.makedirs(os.path.join(v, '.SYSTEM'), exist_ok=True)
    with open(os.path.join(v, '.SYSTEM', 'ASK.CFG'), 'wb') as f:
        f.write(('api=127.0.0.1:%d\r\nauth=127.0.0.1:%d\r\ntls=0\r\nanswers=short\r\nhost_id=%s\r\n'
                 % (PORT, PORT, HID)).encode())
    W.early, W.mode = early, mode
    out = io.StringIO()
    with contextlib.redirect_stderr(ERR), contextlib.redirect_stdout(out):
        r = H.main(argv[:1] + [v] + argv[2:] + ['--check'])
    W.early, W.mode = 60, ''
    return r, out.getvalue(), kv(open(os.path.join(v, '.SYSTEM', 'ASK.CFG'), 'rb').read().decode().replace('\r\n', '\n'))


def no_token(out):
    return not any(t[:12] in out for _, a, r in W.issued for t in (a, r)) and F.API_KEY not in out


n0 = len(W.records)
r, out, k1 = run_check('check1')
recs = W.records[n0:]
turns = [x for x in recs if x.get('path') == '/v1/responses']
rens = [x for x in recs if x.get('path') == '/api/accounts/oauth/token' and x.get('grant') == 'refresh_token']
check(r == 0 and 'PC call OK' in out and 'the reply "OK, from gpt-6.2-sol."' in out and len(turns) == 1
      and not turns[0]['bad'] and turns[0]['reply'] == 200 and len(rens) == 1 and not rens[0]['bad']
      and rens[0]['outcome'] == 'rotated' and k1.get('access') == W.issued[-1][1]
      and k1.get('refresh') == W.issued[-1][2] and 'The renewal works from this PC' in out and no_token(out),
      '--check: the X16\'s turn from the PC (200, response.completed: "PC call OK"), its renewal (rotated), the new '
      'tokens on the card; no token in what it prints')
# the turn and the renewal byte for byte as the X16 lays them out (the same shape the gate's X16 sends)
acc0 = [a for _, a, _ in W.issued if hashlib.sha256(a.encode()).hexdigest() == turns[0]['auth_sha']]
want = H.x16_turn('127.0.0.1', PORT, acc0[0] if acc0 else '', 'gpt-6.2-sol', H.X16_SYSTEM + H.X16_SHORT,
                  [('user', 'Reply with OK')])
head, _, body = want.partition(b'\r\n\r\n')
hl = head.decode().split('\r\n')
hl = [l if not l.startswith('Authorization: ') else 'Authorization: Bearer <%d %s>' % (
    len(acc0[0]), hashlib.sha256(acc0[0].encode()).hexdigest()[:16]) for l in hl]
check(acc0 and turns[0]['head'] == hl and turns[0]['raw_sha'] == hashlib.sha256(body).hexdigest()
      and 'the access token %s' % H.tsum(acc0[0]) in out,
      '--check\'s turn: the X16\'s request line, headers in its order (User-Agent, Accept-Encoding identity, '
      'Content-Type, Accept, Authorization, Content-Length, Connection close) and body; the token\'s length and sum '
      'printed as ASK.LOG shows them')
check(rens[0]['head'][0] == 'POST /api/accounts/oauth/token HTTP/1.1' and rens[0]['keys'] == sorted(
      ['grant_type', 'client_id', 'refresh_token', 'resource'])
      and [l.split(':')[0] for l in rens[0]['head'][1:]] == ['Host', 'User-Agent', 'Accept-Encoding', 'Content-Type',
                                                               'Accept', 'Content-Length', 'Connection'],
      '--check\'s renewal: the X16\'s form (grant_type, client_id, refresh_token, resource; no scope) and headers')
r, out, k2 = run_check('check2', mode='refuse')
check(r == 2 and 'PC call 401' in out and 'the turn: HTTP 401' in out and 'invalid_token' in out
      and '"token_hint": "eyJhbG..."' in out and 'www-authenticate: Bearer realm="OpenAI API"' in out
      and 'The renewal works from this PC' in out and no_token(out),
      '--check, the token refused (401): "PC call 401", OpenAI\'s body and WWW-Authenticate (a token in it cut to 6 '
      'characters), the renewal still done')
n0 = len(W.records)
r, out, k3 = run_check('check3', early=3600)
check(r == 0 and 'PC call OK' in out and 'the renewal: not tried' in out and '60 more minutes' in out
      and not [x for x in W.records[n0:] if x.get('grant') == 'refresh_token'] and no_token(out),
      '--check, earliest_refresh_at an hour away: the renewal not tried, said why')
check(H.redact('a eyJhbGciOi.x.y b rt_abcdefgh sk-proj-12345 c') == 'a eyJhbG... b rt_abc... sk-pro... c'
      and H.x16_url('a/b+c d~') == 'a%2fb%2bc%20d~' and H.x16_json('"\\\n\t\x7f') == '\\"\\\\\\n\\t\\u007f',
      'the redaction (eyJ..., rt_..., sk-...: 6 characters), the X16\'s URL and JSON escaping')

# ------------------------------------------------------------------ the log
L = ERR.getvalue()
toks = [x for _, a, r in W.issued for x in (a, r)]
check(L and not any(t in L or t[:40] in L for t in toks) and '271828' not in L,
      'the helper\'s log (%d lines) has no token and no code' % L.count('\n'))
srv.shutdown()
print('test_chatgpt_signin: %s' % ('PASS' if not fails else 'FAIL (%d)' % fails))
sys.exit(1 if fails else 0)
