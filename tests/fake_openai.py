#!/usr/bin/env python3
# Gate ask (DECISIONS V116): a fake of OpenAI's sign-in and API.
# Copyright (c) 2026 Marcin Spoczynski. MIT licence (see LICENSE).
"""fake_openai.py: OpenAI's "Sign in with ChatGPT" endpoints and the
Responses API, faked on localhost in plain HTTP for the tests (written
from the protocol's description; the real servers are never called).

    fake_openai.py <folder>    serves until killed; writes <folder>/ready
                               (the port) and <folder>/requests.jsonl
                               (every request: what was wrong with it,
                               what was sent back)

As a module (tests/test_chatgpt_signin.py): World, serve(world) -> server.

The endpoints, on one port:
  GET  /api/accounts/authorize   the browser's sign-in: every parameter
                                 checked, then a 302 to the redirect_uri
                                 with code, state and (a first
                                 registration) the client_id issued
  POST /api/accounts/oauth/token authorization_code (PKCE S256, the same
                                 redirect_uri, the issued client_id, no
                                 secret) and refresh_token (rotated: an old
                                 one again is refresh_token_reused); its
                                 reply chunked, cut anywhere; (V129) a
                                 renewal's reply in the style the
                                 environment's FAKE_TOKSTYLE lists, one a
                                 renewal (see STYLES)
  POST /api/accounts/oauth/revoke
  GET  /.well-known/jwks.json    the test key (RS256)
  GET  /v1/models                the plan's models (a bearer)
  POST /v1/responses             SSE as the Responses API streams it; the
                                 request checked as the plan wants it
                                 (model, instructions, input, store false,
                                 stream true, nothing else); the reply by
                                 the last user message's first word (see
                                 respond())

The access tokens are JWTs (V129: as the real ones; their exp read by the
X16), about 2 KB. FAKE_SEED=1: a pair issued at the start, in
<folder>/seed.json (gate ask's renew session starts signed in with it).

THE KEY BELOW IS A TEST KEY, MADE FOR THESE TESTS ONLY (openssl genrsa
2048): it signs the fake id_tokens and nothing else.
"""
import base64
import hashlib
import http.server
import json
import os
import random
import re
import secrets
import socket
import sys
import threading
import time
import urllib.parse

# ---- TEST-ONLY RSA KEY (never use it for anything else) ----
N = int(
    'a4cd8b0d99932020013f13534931fb73b676861e85bc4ea12626bb1757345d3a57ccf8bd'
    '9ca967f39736d3d0ccf26beeaeccf879c2eb143ab715b51eb5cd6aec2047f10f2d07b408'
    'bd5968dbb7522f6fc05864d625eda5741b814125aa754e509033eefc316e10e33835bdf7'
    '54ae3524707f691e47e9e92bce3a2a3bd56ba451e6d3b2e61f832f6eed1172174e101991'
    '893fc884434e648738208a475549a09be4ccaaefd4fd0d3f0839de489f93f2c5e6d2ba23'
    'd062d3a4032fac008794c4c64e0c820980dd6310b1015f7f67f1afe8693417b643a7edf6'
    'f127a3ee06ae2d0272734dd4db3b03f43417149f7e4228a91e515995095426df9b98c017'
    '67a140b5', 16)
E = 65537
D = int(
    '2dfced80ae0a503c9e1c6bd821e4c0b659845988cae8f14826cd48080b5da1665679ec2f'
    '7d3808ba00c85bf3383dadc0bd26956fe4e494908de690d43107517ef2c320918b8f4abd'
    'e598bd9a125decbed27dd825aa0fd6cbbfa121fcd0c44b464ff72e095201d4d4932aec07'
    'c8a9944ac6d9c70b9c25b9db6f80eba826b612f4148b04fc06a487461243a323e58df974'
    '3483b765de387d951d703cb175619047f2d439a914f44a1392b4d27d16ac1a11f826e423'
    'f8a64b709f04ff34200098a79b22e51625133d5d6e9d9b8f3deeba254ac23bb59eed0e9d'
    'f7dbd6a215f411826861314c44235bc73606c9b07cd28c17f76fe5c4de645135419835e9'
    '6453ac1', 16)
KID = 'veranda-gate-test-key'

SCOPE = 'openid profile email offline_access resource.invoke chatgpt.tokens.use.direct'
RESOURCE = 'https://api.openai.com/v1'
API_KEY = 'sk-gate-0000-openai-dummy-key-for-tests-ABCD'
EMAIL = 'gate@example.com'
MODELS = [{'slug': 'gpt-6.2-sol', 'display_name': 'GPT-6.2 Sol', 'visibility': 'list'},
          {'slug': 'gpt-hidden', 'display_name': 'Hidden', 'visibility': 'hide'},
          {'slug': 'gpt-6.1-sol', 'display_name': 'GPT-6.1 Sol', 'visibility': 'list'}]
FORBIDDEN = ('background', 'conversation', 'max_output_tokens', 'max_tool_calls', 'metadata', 'moderation',
             'prompt', 'prompt_cache_retention', 'safety_identifier', 'temperature', 'top_p', 'top_logprobs',
             'truncation', 'user', 'previous_response_id')
# (V129) a renewal's reply as real servers may send it (RFC 6749 5.1, behind
# Cloudflare): '' chunked (random chunks, Connection: close); clen
# Content-Length and close, Cloudflare's headers (cookies too); keepalive
# Content-Length, Connection: keep-alive, the server waiting for the next
# request; chunkka chunks of 1-3 bytes, keep-alive; big a 4,200-character
# access token, a 6 KB id_token, keys in another order, unknown ones (a
# nested object, an array), odd spacing, newlines, no final newline;
# escaped \/ and \u002d in the refresh token, expires_in a string; norefresh
# no refresh_token (not rotated: the old one stays good); toolong a 6,000-
# character access token (more than the X16 keeps: it must say so, keep
# the new refresh token); soon exp in 60 s; stale good for one turn, then
# token_expired
STYLES = ('', 'clen', 'keepalive', 'chunkka', 'big', 'escaped', 'norefresh', 'toolong', 'soon', 'stale')
CF_HEADERS = (('Date', 'Sat, 21 Nov 2026 10:00:00 GMT'), ('CF-RAY', '8e2f1a3b4c5d6e7f-AMS'),
              ('CF-Cache-Status', 'DYNAMIC'), ('Set-Cookie', '__cf_bm=GATECOOKIEsecretXYZ123; path=/; HttpOnly'),
              ('Set-Cookie', '_cfuvid=GATECOOKIE2secretABC789; path=/; Secure'),
              ('Strict-Transport-Security', 'max-age=31536000; includeSubDomains; preload'),
              ('X-Content-Type-Options', 'nosniff'), ('X-Request-Id', 'req_0123456789abcdef0123456789abcdef'),
              ('Vary', 'Origin'), ('Server', 'cloudflare'), ('Alt-Svc', 'h3=":443"; ma=86400'))
HOST_ID_RE = re.compile(r'urn:uuid:[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}')

# (V123) the code session's replies
_BAS = '10 PRINT "HELLO FROM CLAUDE"\n20 FOR I=1 TO 3:PRINT I*I;:NEXT I\n30 PRINT\n40 PRINT "DONE"'
_PY = 'for i in range(1, 4):\n    print(i * i, end=" ")\nprint("done")'
V123 = {
    'code': ('Here is a small program for the X16.\n\n```basic\n' + _BAS + '\n```\n\nAnd the same in Python:\n\n'
             '```python\n' + _PY + '\n```\n\nCopy or save either.'),
    'fix': ('Here is GAME.PRG with line 30 fixed.\n\n```basic\n5 PRINT "{93}"\n10 PRINT "GAME"\n20 X=5\n'
            '30 PRINT "SCORE";X*2\n40 END\n```\n\nSave it over the old one.'),
    'summarise': ('We wrote a BASIC program that prints squares, saved as PROGRAM.PRG, and fixed line 30 of '
                  'GAME.PRG (PRINT "SCORE";X*2).'),
}

HELLO_A = ('Hello! “Quoted” words — a dash, an ellipsis… café, naïve, '
           'an emoji \U0001F600 here.\n\nA list:\n• one\n• two\n\n')
HELLO_B = ('Raw UTF-8: łódź, ‘single’, 5°C, ½, → next. '
           'A tab\there, a backslash \\ and "plain quotes".')


def b64u(b):
    return base64.urlsafe_b64encode(b).rstrip(b'=').decode('ascii')


def sign_rs256(data):
    t = bytes.fromhex('3031300d060960864801650304020105000420') + hashlib.sha256(data).digest()
    k = (N.bit_length() + 7) // 8
    em = b'\x00\x01' + b'\xff' * (k - len(t) - 3) + b'\x00' + t
    return pow(int.from_bytes(em, 'big'), D, N).to_bytes(k, 'big')


def jwt(claims, kid=KID, bad_sig=False):
    h = b64u(json.dumps({'alg': 'RS256', 'typ': 'JWT', 'kid': kid}).encode())
    p = b64u(json.dumps(claims).encode())
    s = sign_rs256((h + '.' + p).encode())
    if bad_sig:
        s = bytes([s[0] ^ 1]) + s[1:]
    return h + '.' + p + '.' + b64u(s)


def jwks():
    n = N.to_bytes((N.bit_length() + 7) // 8, 'big')
    return {'keys': [{'kty': 'RSA', 'kid': KID, 'use': 'sig', 'alg': 'RS256', 'n': b64u(n), 'e': 'AQAB'}]}


class World:
    """what the fake remembers; mode: '' normal, or one fault for the helper's tests:
    deny (access_denied), noclient (no client_id at a first registration), otherclient
    (another client_id at a sign-in again), noscope (no plan scope), badsig, badnonce,
    badaud, badstate, slow (the browser's reply after 3 s)"""

    def __init__(self, folder=None):
        self.lock = threading.Lock()
        self.mode = ''
        self.issuer = None              # (the server's own URL, set by serve)
        self.codes = {}                 # code -> the authorize request's
        self.clients = {}               # host_id -> client_id issued
        self.access = {}                # access token -> client_id
        self.dead_access = set()        # (expired or revoked)
        self.refresh = {}               # refresh token -> [client_id, state: live, used, dead]
        self.issued = []                # [(client_id, access, refresh)] in order
        self.expired_once = set()       # access tokens "expire" has refused
        self.gen = {}                   # (V129) access token -> the renewal that issued it (0: a sign-in)
        self.stale = {}                 # access token -> its turns ('stale': one, then expired)
        self.styles = [x.strip() for x in os.environ.get('FAKE_TOKSTYLE', '').split(',') if x.strip()]
        self.nref = 0                   # renewals so far
        self.reused = 0
        self.rnd = random.Random(116)
        self.early = int(os.environ.get('FAKE_EARLY', '60'))   # (V131) earliest_refresh_at: this long after a token
        self.log = open(os.path.join(folder, 'requests.jsonl'), 'w') if folder else None
        self.records = []

    def note(self, rec):
        with self.lock:
            self.records.append(rec)
            if self.log:
                self.log.write(json.dumps(rec) + '\n')
                self.log.flush()

    def tokens(self, client_id, nonce=None, style='', gen=0, size=None):
        now = int(time.time())
        life = 60 if style == 'soon' else 3600
        exact, size = size, size or {'big': 4200, 'toolong': 6000}.get(style, 2000)
        claims = {'iss': 'https://auth.openai.com', 'aud': [RESOURCE], 'sub': 'user-gate', 'iat': now,
                  'nbf': now, 'exp': now + life, 'scp': SCOPE.split(), 'session_id': secrets.token_hex(16),
                  'https://api.openai.com/auth': {'chatgpt_plan_type': 'plus', 'user_id': 'user-gate'}}
        acc = jwt(claims)                                       # (about 2 KB, as the real ones: padded)
        claims['pad'] = 'x' * max(0, (size - len(acc)) * 3 // 4)
        acc = jwt(claims)
        if exact:                       # (V131: this length exactly, its signature's end cut to it)
            claims['pad'] += 'x' * ((exact - len(acc)) * 3 // 4 + 4)
            acc = jwt(claims)[:exact]
        ref = 'rt_' + b64u(secrets.token_bytes(180))
        if style == 'escaped':
            ref = 'rt_' + base64.b64encode(secrets.token_bytes(96)).decode() + '/a-b/'
        with self.lock:
            self.access[acc] = client_id
            self.refresh[ref] = [client_id, 'live']
            self.issued.append((client_id, acc, ref))
            self.gen[acc] = gen
            if style == 'stale':
                self.stale[acc] = 0
        r = {'access_token': acc, 'refresh_token': ref, 'token_type': 'Bearer', 'expires_in': life,
             'scope': SCOPE if self.mode != 'noscope' else 'openid profile email offline_access',
             'earliest_refresh_at': int(time.time()) + self.early}
        if nonce is not None:
            now = int(time.time())
            r['id_token'] = jwt({'iss': self.issuer if self.mode != 'badiss' else 'https://evil.example',
                                 'aud': client_id if self.mode != 'badaud' else 'oaiapp_other',
                                 'sub': 'user-gate', 'email': EMAIL, 'iat': now, 'exp': now + 3600,
                                 'nonce': nonce if self.mode != 'badnonce' else 'other-nonce'},
                                bad_sig=self.mode == 'badsig')
        return r


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'
    timeout = 60

    def log_message(self, *a):
        pass

    @property
    def W(self):
        return self.server.world

    def send(self, status, body, ctype='application/json', chunked=False, extra=(), keep=False, tiny=False):
        if isinstance(body, (dict, list)):
            body = json.dumps(body).encode()
        self.send_response(status)
        self.send_header('Content-Type', ctype)
        for k, v in extra:
            self.send_header(k, v)
        if chunked:
            self.send_header('Transfer-Encoding', 'chunked')
        else:
            self.send_header('Content-Length', str(len(body)))
        self.send_header('Connection', 'keep-alive' if keep else 'close')
        if keep:
            self.close_connection = False   # (the client's to close)
        self.end_headers()
        if chunked:
            self.chunks(body, tiny)
            self.raw(b'0\r\n\r\n')
        else:
            self.raw(body)

    def raw(self, b):
        try:
            self.wfile.write(b)
            self.wfile.flush()
            return True
        except OSError:
            self.closed = True
            return False

    def chunks(self, b, tiny=False):
        """b as chunks of random sizes (lines and JSON cut anywhere)"""
        while b and not getattr(self, 'closed', False):
            n = self.W.rnd.randint(1, 3 if tiny else 90)
            p, b = b[:n], b[n:]
            self.raw(b'%x\r\n' % len(p) + p + b'\r\n')

    def body(self):
        try:
            n = int(self.headers.get('content-length', '0'))
        except ValueError:
            n = 0
        return self.rfile.read(n) if n > 0 else b''

    # ------------------------------------------------------------ GET
    def do_GET(self):
        self.close_connection = True
        u = urllib.parse.urlsplit(self.path)
        if u.path == '/.well-known/jwks.json':
            return self.send(200, jwks())
        if u.path == '/api/accounts/authorize':
            return self.authorize(urllib.parse.parse_qs(u.query, keep_blank_values=True))
        if u.path == '/v1/models':
            acc = self.bearer()
            ok = acc in self.W.access and acc not in self.W.dead_access
            self.W.note({'path': '/v1/models', 'ok': ok})
            if not ok:
                return self.send(401, {'error': {'code': 'invalid_token', 'message': 'bad token'}})
            return self.send(200, {'models': MODELS})
        self.send(404, {'detail': 'Not Found'})

    def head_lines(self):
        """(V131) the request line and its headers as they came, in order; the Authorization's
        value as its length and SHA-256 (the gate compares them with the X16's shape)"""
        out = [self.requestline]
        for k, v in self.headers.items():
            if k.lower() == 'authorization':
                t = v[7:] if v.startswith('Bearer ') else v
                v = 'Bearer <%d %s>' % (len(t), hashlib.sha256(t.encode('latin-1')).hexdigest()[:16])
            out.append('%s: %s' % (k, v))
        return out

    def bearer(self):
        a = self.headers.get('authorization', '')
        return a[7:] if a.startswith('Bearer ') else None

    def authorize(self, q):
        W, bad = self.W, []
        one = {k: v[0] for k, v in q.items() if len(v) == 1}
        if len(one) != len(q):
            bad.append('a parameter twice')
        cid = one.get('client_id', '')
        hid = one.get('ext_agent_host_id', '')
        first = cid == 'dynamic_agent_client'
        if one.get('response_type') != 'code':
            bad.append('response_type')
        ru = one.get('redirect_uri', '')
        if not re.fullmatch(r'http://127\.0\.0\.1:\d+/auth/callback', ru):
            bad.append('redirect_uri %r' % ru)
        if one.get('scope') != SCOPE:
            bad.append('scope %r' % one.get('scope'))
        if one.get('resource') != RESOURCE:
            bad.append('resource')
        if one.get('code_challenge_method') != 'S256' or not re.fullmatch(r'[A-Za-z0-9_-]{43}', one.get('code_challenge', '')):
            bad.append('PKCE')
        if len(one.get('state', '')) < 16 or len(one.get('nonce', '')) < 16:
            bad.append('state, nonce')
        if not HOST_ID_RE.fullmatch(hid):
            bad.append('ext_agent_host_id %r' % hid)
        if first:
            if one.get('agent_name_hint') != 'Veranda Ask':
                bad.append('agent_name_hint %r' % one.get('agent_name_hint'))
            if 'login_hint' in one:
                bad.append('login_hint at a first registration')
        else:
            if 'agent_name_hint' in one:
                bad.append('agent_name_hint at a sign-in again')
            if cid not in W.clients.values():
                bad.append('an unknown client_id %r' % cid)
        rec = {'path': '/api/accounts/authorize', 'first': first, 'host_id': hid, 'client_id': cid,
               'login_hint': one.get('login_hint'), 'bad': bad}
        W.note(rec)
        if W.mode == 'slow':
            time.sleep(3)
        if bad:
            return self.send(400, {'error': 'invalid_request', 'error_description': '; '.join(bad)})
        back = {'state': one['state'] if W.mode != 'badstate' else 'not-the-state'}
        if W.mode == 'deny':
            back.update(error='access_denied', error_description='The user declined.')
        else:
            code = secrets.token_urlsafe(24)
            with W.lock:
                issued = W.clients.setdefault(hid, 'oaiapp_' + hashlib.sha256(hid.encode()).hexdigest()[:20]) \
                    if first else cid
                W.codes[code] = {'client_id': issued, 'challenge': one['code_challenge'], 'redirect_uri': ru,
                                 'nonce': one['nonce']}
            back['code'] = code
            if first and W.mode != 'noclient':
                back['client_id'] = issued
            if not first and W.mode == 'otherclient':
                back['client_id'] = 'oaiapp_other'
        self.send(302, b'', ctype='text/plain', extra=[('Location', ru + '?' + urllib.parse.urlencode(back))])

    # ------------------------------------------------------------ POST
    def do_POST(self):
        self.close_connection = True
        u = urllib.parse.urlsplit(self.path)
        raw = self.body()
        if u.path == '/api/accounts/oauth/token':
            return self.token(raw)
        if u.path == '/api/accounts/oauth/revoke':
            f = {k: v[0] for k, v in urllib.parse.parse_qs(raw.decode()).items()}
            with self.W.lock:
                if f.get('token') in self.W.refresh:
                    self.W.refresh[f['token']][1] = 'dead'
            self.W.note({'path': '/api/accounts/oauth/revoke', 'known': f.get('token') in self.W.refresh})
            return self.send(200, {})
        if u.path == '/v1/responses':
            return self.api_responses(raw)
        self.send(404, {'detail': 'Not Found'})

    def token(self, raw):
        W, bad = self.W, []
        ct = self.headers.get('content-type', '')
        if ct != 'application/x-www-form-urlencoded':
            bad.append('content-type %r' % ct)
        if self.headers.get('content-length') != str(len(raw)):
            bad.append('content-length')
        try:
            q = urllib.parse.parse_qs(raw.decode('ascii'), keep_blank_values=True, strict_parsing=True)
        except (ValueError, UnicodeDecodeError):
            q = {}
            bad.append('not a form')
        f = {k: v[0] for k, v in q.items()}
        g = f.get('grant_type')
        rec = {'path': '/api/accounts/oauth/token', 'grant': g, 'keys': sorted(f), 'bad': bad,
               'host': self.headers.get('host'), 'head': self.head_lines(),
               'raw_sha': hashlib.sha256(raw).hexdigest()}
        if 'client_secret' in f:
            bad.append('a client secret')
        if f.get('resource') != RESOURCE:
            bad.append('resource %r' % f.get('resource'))
        if g == 'authorization_code':
            c = W.codes.pop(f.get('code', ''), None)
            if not c:
                bad.append('an unknown or used code')
            else:
                if f.get('client_id') != c['client_id']:
                    bad.append('client_id %r, issued %r' % (f.get('client_id'), c['client_id']))
                if b64u(hashlib.sha256(f.get('code_verifier', '').encode()).digest()) != c['challenge']:
                    bad.append('code_verifier')
                if f.get('redirect_uri') != c['redirect_uri']:
                    bad.append('redirect_uri')
            if set(f) != {'grant_type', 'client_id', 'code', 'code_verifier', 'redirect_uri', 'resource'}:
                bad.append('fields %r' % sorted(f))
            W.note(rec)
            if bad:
                return self.send(400, {'error': 'invalid_grant', 'error_description': '; '.join(bad)})
            return self.send(200, json.dumps(W.tokens(c['client_id'], c['nonce'])).encode(), chunked=True)
        if g == 'refresh_token':
            if 'scope' in f:
                bad.append('scope sent at a refresh')
            if set(f) != {'grant_type', 'client_id', 'refresh_token', 'resource'}:
                bad.append('fields %r' % sorted(f))
            r = W.refresh.get(f.get('refresh_token', ''))
            rec['refresh_tail'] = f.get('refresh_token', '')[-8:]
            if r and r[0] != f.get('client_id'):
                bad.append('client_id %r' % f.get('client_id'))
            if self.headers.get('accept-encoding') != 'identity' and not os.environ.get('FAKE_LAX'):
                bad.append('accept-encoding %r' % self.headers.get('accept-encoding'))
            if bad:
                W.note(rec)
                return self.send(400, {'error': 'invalid_request', 'error_description': '; '.join(bad)})
            if not r:
                rec['outcome'] = 'invalid_refresh_token'
                W.note(rec)
                return self.send(400, {'error': 'invalid_refresh_token', 'error_description': 'Unknown refresh token.'})
            if r[1] == 'used':
                W.reused += 1
                rec['outcome'] = 'refresh_token_reused'
                W.note(rec)
                return self.send(400, {'error': 'refresh_token_reused',
                                       'error_description': 'This refresh token was already used.'})
            if r[1] == 'dead':
                rec['outcome'] = 'refresh_token_invalidated'
                W.note(rec)
                return self.send(401, {'error': 'refresh_token_invalidated',
                                       'error_description': 'The sign-in has ended.'})
            style = W.styles[W.nref] if W.nref < len(W.styles) else ''
            W.nref += 1
            t = W.tokens(r[0], style=style, gen=W.nref)
            rec['style'] = style
            if style == 'norefresh':        # (not rotated: the old one stays good)
                W.refresh.pop(t.pop('refresh_token'))
                rec['outcome'] = 'kept'
            else:
                r[1] = 'used'
                rec['outcome'] = 'rotated'
                rec['new_refresh_tail'] = t['refresh_token'][-8:]
            W.note(rec)
            return self.token_reply(t, style)
        rec['bad'].append('grant_type %r' % g)
        W.note(rec)
        self.send(400, {'error': 'unsupported_grant_type'})

    def token_reply(self, t, style):
        """(V129) a renewal's 200 in its style (STYLES)"""
        if style in ('', 'chunked', 'soon', 'stale'):
            return self.send(200, json.dumps(t).encode(), chunked=True)
        if style == 'chunkka':
            return self.send(200, json.dumps(t).encode(), chunked=True, keep=True, tiny=True, extra=CF_HEADERS)
        if style == 'big':
            t['id_token'] = jwt({'iss': 'https://auth.openai.com', 'aud': 'oaiapp_gate', 'sub': 'user-gate',
                                 'email': EMAIL, 'pad': 'y' * 4300})
            t = {'id_token': t['id_token'], 'scope': t['scope'], 'token_type': t['token_type'],
                 'refresh_token': t['refresh_token'], 'earliest_refresh_at': t['earliest_refresh_at'],
                 'nested': {'a': [1, 2.5, {'b': 'c \" d'}], 'e': None, 'f': True, 'g': 'h'},
                 'expires_in': t['expires_in'], 'access_token': t['access_token'], 'unknown_key_of_some_length': ''}
            body = json.dumps(t, indent=3, separators=(' ,  ', ' :\t')).replace('\n', '\r\n').encode()
            return self.send(200, body, extra=CF_HEADERS)
        if style == 'escaped':
            t['expires_in'] = str(t['expires_in'])
            s = json.dumps(t, separators=(',', ':'))
            ref = t['refresh_token']
            s = s.replace(json.dumps(ref), json.dumps(ref).replace('/', '\\/').replace('-', '\\u002d', 1))
            return self.send(200, s.encode(), extra=CF_HEADERS)
        if style == 'keepalive':
            return self.send(200, json.dumps(t).encode() + b'\n', keep=True, extra=CF_HEADERS)
        return self.send(200, json.dumps(t).encode(), extra=CF_HEADERS)     # (clen, norefresh, toolong)

    # ------------------------------------------------------------ the Responses API
    def check(self, body, raw, plan):
        bad, h = [], self.headers
        if h.get('content-type') != 'application/json':
            bad.append('content-type %r' % h.get('content-type'))
        if h.get('accept') != 'text/event-stream':
            bad.append('accept %r' % h.get('accept'))
        if h.get('content-length') != str(len(raw)):
            bad.append('content-length %r, body %d' % (h.get('content-length'), len(raw)))
        if h.get('accept-encoding') != 'identity' and not os.environ.get('FAKE_LAX'):
            bad.append('accept-encoding %r' % h.get('accept-encoding'))
        if not h.get('host'):
            bad.append('no Host')
        if body is None:
            return bad + ['not JSON']
        extra = set(body) - {'model', 'instructions', 'input', 'store', 'stream'}
        if extra:
            bad.append('fields %r' % sorted(extra))
        for k in FORBIDDEN:
            if k in body:
                bad.append('%s sent' % k)
        if body.get('store') is not False:
            bad.append('store %r' % body.get('store'))
        if body.get('stream') is not True:
            bad.append('stream %r' % body.get('stream'))
        if plan and body.get('model') not in [m['slug'] for m in MODELS if m['visibility'] == 'list']:
            bad.append('model %r' % body.get('model'))
        if not isinstance(body.get('instructions'), str) or 'plain ASCII' not in body['instructions']:
            bad.append('instructions %r' % str(body.get('instructions'))[:40])
        inp = body.get('input')
        if not isinstance(inp, list) or not inp:
            return bad + ['no input']
        for i, m in enumerate(inp):
            if not isinstance(m, dict) or set(m) != {'role', 'content'}:
                bad.append('input[%d] %r' % (i, m))
                continue
            if m['role'] != ('user' if i % 2 == 0 else 'assistant'):
                bad.append('input[%d].role %r' % (i, m['role']))
            if not isinstance(m['content'], str) or not m['content']:
                bad.append('input[%d].content' % i)
        if inp[-1].get('role') != 'user':
            bad.append('the last input is not the user\'s')
        return bad

    def ev(self, data):
        return ('event: %s\ndata: %s\n\n' % (data['type'], json.dumps(data, ensure_ascii=False))).encode('utf-8')

    def stream(self, model, text, size=8, pause=0.0, end='completed', first_pause=0.0):
        W = self.W
        self.send_response(200)
        self.send_header('Content-Type', 'text/event-stream; charset=utf-8')
        self.send_header('Transfer-Encoding', 'chunked')
        self.send_header('Connection', 'close')
        self.end_headers()
        rid = 'resp_gate_' + secrets.token_hex(6)
        resp = {'id': rid, 'object': 'response', 'status': 'in_progress', 'model': model + '-2026-10-01',
                'instructions': 'You are talking with someone ...', 'error': None, 'incomplete_details': None,
                'output': [], 'usage': None}
        seq = [0]

        def out(d):
            d['sequence_number'] = seq[0]
            seq[0] += 1
            self.chunks(self.ev(d))
        out({'type': 'response.created', 'response': resp})
        out({'type': 'response.in_progress', 'response': resp})
        time.sleep(first_pause)
        out({'type': 'response.output_item.added', 'output_index': 0,
             'item': {'id': 'msg_1', 'type': 'message', 'status': 'in_progress', 'role': 'assistant', 'content': []}})
        out({'type': 'response.content_part.added', 'item_id': 'msg_1', 'output_index': 0, 'content_index': 0,
             'part': {'type': 'output_text', 'text': '', 'annotations': []}})
        i = 0
        while i < len(text) and not getattr(self, 'closed', False):
            n = W.rnd.randint(1, size)
            out({'type': 'response.output_text.delta', 'item_id': 'msg_1', 'output_index': 0, 'content_index': 0,
                 'delta': text[i:i + n]})
            i += n
            if pause:
                time.sleep(pause)
        if end == 'cut':
            self.raw(b'0\r\n\r\n')
            return
        done = dict(resp, output=[{'id': 'msg_1', 'type': 'message', 'role': 'assistant',
                                   'content': [{'type': 'output_text', 'text': text, 'annotations': []}]}])
        out({'type': 'response.output_text.done', 'item_id': 'msg_1', 'output_index': 0, 'content_index': 0,
             'text': text})
        if end == 'failed':
            out({'type': 'response.failed', 'response': dict(done, status='failed', error={
                'code': 'server_error', 'message': 'The model stopped with an error.'})})
        elif end == 'incomplete':
            out({'type': 'response.incomplete', 'response': dict(done, status='incomplete', incomplete_details={
                'reason': 'max_output_tokens'})})
        else:
            out({'type': 'response.completed', 'response': dict(done, status='completed', usage={
                'input_tokens': 321, 'input_tokens_details': {'cached_tokens': 100}, 'output_tokens': 45,
                'total_tokens': 366})})
        self.raw(b'0\r\n\r\n')

    def api_responses(self, raw):
        W = self.W
        try:
            body = json.loads(raw.decode('utf-8'))
        except (ValueError, UnicodeDecodeError):
            body = None
        tok = self.bearer()
        plan = tok != API_KEY
        bad = self.check(body, raw, plan)
        last = body['input'][-1]['content'] if body and isinstance(body.get('input'), list) and body['input'] \
            and isinstance(body['input'][-1], dict) else ''
        word = last.split()[0].lower().strip(',!?.') if isinstance(last, str) and last.split() else ''
        model = body.get('model', '?') if isinstance(body, dict) else '?'
        rec = {'path': '/v1/responses', 'plan': plan, 'token_tail': (tok or '')[-8:], 'body': body, 'bad': bad,
               'kind': word, 'host': self.headers.get('host'), 'raw': raw.decode('utf-8', 'replace'),
               'raw_len': len(raw), 'auth_len': len(tok or ''),
               'auth_sha': hashlib.sha256((tok or '').encode('latin-1')).hexdigest(), 'head': self.head_lines(),
               'raw_sha': hashlib.sha256(raw).hexdigest()}
        known = tok == API_KEY or (tok in W.access and tok not in W.dead_access)
        if not known:
            rec['reply'] = 401
            W.note(rec)
            return self.send(401, {'error': {'message': 'Invalid or expired token.', 'type': 'invalid_request_error',
                                             'code': 'invalid_token', 'param': None}})
        m = re.fullmatch(r'expire(\d*)', word)
        if tok in W.stale:                  # (V129: 'stale': one turn, then expired)
            W.stale[tok] += 1
        if (m and tok != API_KEY and W.gen.get(tok, 0) < int(m.group(1) or 1)) or W.stale.get(tok, 0) > 1:
            W.expired_once.add(tok)         # ("expireN": a token from before the N-th renewal has expired)
            W.dead_access.add(tok)
            rec['reply'] = 401
            W.note(rec)
            return self.send(401, {'error': {'message': 'Your authentication token has expired.',
                                             'type': 'invalid_request_error', 'code': 'token_expired', 'param': None,
                                             'token_hint': tok[:40], 'request_id': 'req_' + secrets.token_hex(16)}})
        if word == 'refuse' or W.mode == 'refuse':     # (V131: a good token refused, not for its age)
            rec['reply'] = 401
            W.note(rec)
            return self.send(401, {'error': {'message': 'Your authentication token is not valid for this route.',
                                             'type': 'invalid_request_error', 'param': None, 'code': 'invalid_token',
                                             'token_hint': tok[:24]}},
                             extra=CF_HEADERS + (('WWW-Authenticate', 'Bearer realm="OpenAI API"'),))
        if word == 'revoke':
            with W.lock:
                W.dead_access.add(tok)
                for r in W.refresh.values():
                    if r[0] == W.access.get(tok):
                        r[1] = 'dead'
            rec['reply'] = 401
            W.note(rec)
            return self.send(401, {'error': {'message': 'The sign-in has ended.', 'type': 'invalid_request_error',
                                             'code': 'subscription_sharing_invalid_user', 'param': None}})
        codes = {'limit': (429, 'subscription_sharing_usage_limit_exceeded', 'You have reached the usage limit.'),
                 'eligible': (403, 'subscription_sharing_user_not_eligible', 'This account cannot use its plan here.'),
                 'unavailable': (503, 'subscription_sharing_usage_unavailable', 'Usage is unavailable.')}
        if word in codes:
            st, code, msg = codes[word]
            rec['reply'] = st
            W.note(rec)
            return self.send(st, {'error': {'message': msg, 'type': 'invalid_request_error', 'code': code,
                                            'param': None}})
        if word == 'detail':
            rec['reply'] = 400
            W.note(rec)
            return self.send(400, {'detail': 'Unsupported parameter.'})
        rec['reply'] = 200
        if word == 'hello':
            rec['text'] = HELLO_A + HELLO_B
            self.stream(model, HELLO_A + HELLO_B, 6, 0.02, first_pause=1.0)
        elif word == 'slow':
            rec['text'] = ' '.join('word%02d' % i for i in range(60))
            self.stream(model, rec['text'], 7, 0.25)
        elif word == 'aside':
            rec['text'] = ' '.join('aside%02d' % i for i in range(15))
            self.stream(model, rec['text'], 8, 0.2)
        elif word == 'failed':
            rec['text'] = 'Here is the start of an answer that'
            self.stream(model, rec['text'], 6, end='failed')
        elif word == 'interrupt':
            rec['text'] = 'A reply that never ends because'
            self.stream(model, rec['text'], 6, end='cut')
        elif word in V123:              # (the code session's replies: tests/claude_server.py's)
            rec['text'] = V123[word]
            self.stream(model, rec['text'], 9)
        elif last.startswith('Summarise our conversation'):
            rec['text'] = V123['summarise']
            self.stream(model, rec['text'], 9)
        elif word == 'big':
            rec['text'] = '\n\n'.join('Block %02d: %s' % (i, 'Once upon a time a small 8-bit computer sat on a desk by a '
                                                             'window and answered one character at a time.') for i in range(80))
            self.stream(model, rec['text'], 60)
        elif word == 'incomplete':
            rec['text'] = 'This answer goes on and on, until the limit cuts it'
            self.stream(model, rec['text'], 10, end='incomplete')
        elif word == 'api' and 'ZA' in last:      # (V143: Polish back, raw UTF-8)
            rec['text'] = 'OK, from %s. Zażółć gęślą jaźń, ZAŻÓŁĆ GĘŚLĄ JAŹŃ.' % model
            self.stream(model, rec['text'], 5)
        else:
            rec['text'] = 'OK, from %s.' % model
            self.stream(model, rec['text'], 5)
        rec['client_closed'] = bool(getattr(self, 'closed', False))
        W.note(rec)


class Server(http.server.ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True


def serve(world, port=0):
    s = Server(('127.0.0.1', port), Handler)
    s.world = world
    world.issuer = 'http://127.0.0.1:%d' % s.server_address[1]
    threading.Thread(target=s.serve_forever, daemon=True).start()
    return s


def main():
    d = sys.argv[1]
    w = World(d)
    if len(sys.argv) > 2:
        w.mode = sys.argv[2]
    s = serve(w)
    t = socket.socket()
    t.bind(('127.0.0.1', 0))
    closed = t.getsockname()[1]
    t.close()
    if os.environ.get('FAKE_SEED'):
        t = w.tokens('oaiapp_gateseed0123456789', size=int(os.environ.get('FAKE_SEEDSIZE', '0')) or None)
        with open(os.path.join(d, 'seed.json'), 'w') as f:
            json.dump({'client_id': 'oaiapp_gateseed0123456789', 'access': t['access_token'],
                       'refresh': t['refresh_token']}, f)
    with open(os.path.join(d, 'ready.tmp'), 'w') as f:
        f.write('%d %d\n' % (s.server_address[1], closed))
    os.rename(os.path.join(d, 'ready.tmp'), os.path.join(d, 'ready'))
    n = 0
    with open(os.path.join(d, 'issued.jsonl'), 'w') as f:
        while True:
            time.sleep(0.2)
            with w.lock:
                new = w.issued[n:]
                n = len(w.issued)
            for cid, acc, ref in new:
                f.write(json.dumps({'client_id': cid, 'access': acc, 'refresh': ref}) + '\n')
                f.flush()


if __name__ == '__main__':
    main()
