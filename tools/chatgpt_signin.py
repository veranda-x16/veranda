#!/usr/bin/env python3
# Veranda Ask's sign-in helper (DECISIONS V116).
# Copyright (c) 2026 Marcin Spoczynski. MIT licence (see LICENSE).
"""chatgpt_signin.py: sign Veranda Ask (on a Commander X16) in with your
ChatGPT plan, from a PC with a web browser.

The X16 has no browser, so the sign-in ("Sign in with ChatGPT", OpenAI's
plan usage for locally run apps) is done here, the way OpenAI describes it
for a self-hosted machine: the OAuth sign-in runs on the machine with the
browser, for the X16's own host ID, and the credentials (the client_id
OpenAI issues, the access and refresh tokens) are handed to the X16, which
keeps them and renews them itself from then on. This PC keeps no copy.

    python3 chatgpt_signin.py

prints a 6-digit code and this PC's address. In Veranda Ask: Settings,
ChatGPT plan, the address (port 8643) and the code, then "Continue with
ChatGPT". The browser here opens OpenAI's sign-in page; when you have
signed in (ChatGPT Plus or Pro), the X16 gets its credentials over your
home network in the reply to its request, and this program exits.

Or, without the network: put the X16's SD card in this PC and

    python3 chatgpt_signin.py --card /path/to/the/card/VERANDA

writes the credentials into VERANDA/.SYSTEM/ASK.CFG on the card, and

    python3 chatgpt_signin.py --card /path/to/the/card/VERANDA --check

then sends from this PC the X16's own turn ("Reply with OK", byte for byte
as Veranda Ask lays it out, with the card's tokens and model) and its
renewal, prints what OpenAI answered (anything token-like cut to 6
characters) and what that says, and writes the renewed tokens to the card.

Plain HTTP on your network: the code and the credentials cross it
unencrypted, so only private addresses may connect, the code works for one
sign-in, and a few wrong codes stop the program. The tokens are never
written to the log.
"""
import argparse
import base64
import hashlib
import hmac
import http.server
import ipaddress
import json
import os
import queue
import re
import secrets
import shlex
import socket
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
import webbrowser

DEFAULT_PORT = 8643
APP_NAME = 'Veranda Ask'
# OpenAI's sign-in, as its discovery document gives it
ISSUER = 'https://auth.openai.com'
AUTHORIZE_URL = 'https://auth.openai.com/api/accounts/authorize'
TOKEN_URL = 'https://auth.openai.com/api/accounts/oauth/token'
REVOKE_URL = 'https://auth.openai.com/api/accounts/oauth/revoke'
JWKS_URL = 'https://auth.openai.com/.well-known/jwks.json'
MODELS_URL = 'https://api.openai.com/v1/models'
RESOURCE = 'https://api.openai.com/v1'
SCOPE = 'openid profile email offline_access resource.invoke chatgpt.tokens.use.direct'
PLAN_SCOPE = 'chatgpt.tokens.use.direct'
FIRST_CLIENT = 'dynamic_agent_client'
CALLBACK_PORT = 1455
MAX_MODELS = 8
MAX_TRIES = 5
HOST_ID_RE = re.compile(r'urn:uuid:[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}')
# what a value may hold on its way to the X16 (one line key=value each)
TOKEN_RE = re.compile(r'[\x21-\x7e]+')
# (V131) what the X16 keeps (apps/ask/ask.h: ACCMAX, REFMAX): a longer one it would cut, and a cut token is refused
ACCMAX, REFMAX = 5119, 1023
DENIED = 'access_denied'


def log(msg):
    sys.stderr.write(time.strftime('%H:%M:%S ') + msg + '\n')
    sys.stderr.flush()


class SignInError(Exception):
    """a sign-in that did not finish: its words for the X16's box (51 characters a line)"""


# ------------------------------------------------------------------ who may connect

_PRIVATE4 = [ipaddress.ip_network(n) for n in ('127.0.0.0/8', '10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16')]
_PRIVATE6 = [ipaddress.ip_network(n) for n in ('::1/128', 'fc00::/7', 'fe80::/10')]


def allowed_client(addr):
    """only this PC's own network: loopback, 10/8, 172.16/12, 192.168/16; IPv6 loopback, unique-local, link-local"""
    try:
        ip = ipaddress.ip_address(addr.split('%')[0])
    except ValueError:
        return False
    if ip.version == 6 and ip.ipv4_mapped:
        ip = ip.ipv4_mapped
    return any(ip in n for n in (_PRIVATE4 if ip.version == 4 else _PRIVATE6))


# ------------------------------------------------------------------ PKCE, base64url, RS256

def b64u(b):
    return base64.urlsafe_b64encode(b).rstrip(b'=').decode('ascii')


def unb64u(s):
    if isinstance(s, str):
        s = s.encode('ascii')
    if not re.fullmatch(rb'[A-Za-z0-9_-]*', s):
        raise ValueError('not base64url')
    return base64.urlsafe_b64decode(s + b'=' * (-len(s) % 4))


def pkce():
    """(verifier, challenge): 32 random bytes, and base64url(SHA-256(verifier)) without padding"""
    v = b64u(secrets.token_bytes(32))
    return v, b64u(hashlib.sha256(v.encode('ascii')).digest())


# DER of the DigestInfo of SHA-256 (RFC 8017, 9.2 note 1), before the hash
SHA256_PREFIX = bytes.fromhex('3031300d060960864801650304020105000420')


def rs256_ok(n, e, signed, sig):
    """RSASSA-PKCS1-v1_5 with SHA-256 (RFC 8017 8.2.2): the signature's
    representative raised to e mod n must be exactly 00 01 FF..FF 00
    DigestInfo(SHA-256(signed))"""
    k = (n.bit_length() + 7) // 8
    if len(sig) != k or k < 256:          # (2048-bit keys at least)
        return False
    s = int.from_bytes(sig, 'big')
    if s >= n:
        return False
    em = pow(s, e, n).to_bytes(k, 'big')
    t = SHA256_PREFIX + hashlib.sha256(signed).digest()
    want = b'\x00\x01' + b'\xff' * (k - len(t) - 3) + b'\x00' + t
    return hmac.compare_digest(em, want)


def verify_id_token(tok, jwks, issuer, client_id, nonce, now=None):
    """the id_token's claims, when its RS256 signature is one of the JWKS's
    keys and it is for this client, from the issuer, not expired, with this
    sign-in's nonce; else SignInError"""
    now = time.time() if now is None else now
    try:
        h64, p64, s64 = tok.split('.')
        head = json.loads(unb64u(h64))
        claims = json.loads(unb64u(p64))
        sig = unb64u(s64)
    except (ValueError, AttributeError):
        raise SignInError('the id_token is not a JWT')
    if not isinstance(head, dict) or head.get('alg') != 'RS256':
        raise SignInError('the id_token is not RS256')
    keys = [k for k in (jwks.get('keys') or []) if isinstance(k, dict) and k.get('kty') == 'RSA'
            and k.get('alg', 'RS256') == 'RS256' and k.get('use', 'sig') == 'sig']
    if head.get('kid') is not None:
        keys = [k for k in keys if k.get('kid') == head['kid']]
    signed = (h64 + '.' + p64).encode('ascii')
    for k in keys:
        try:
            n = int.from_bytes(unb64u(k['n']), 'big')
            e = int.from_bytes(unb64u(k['e']), 'big')
        except (KeyError, ValueError, TypeError):
            continue
        if rs256_ok(n, e, signed, sig):
            break
    else:
        raise SignInError('the id_token\'s signature is wrong')
    if not isinstance(claims, dict):
        raise SignInError('the id_token has no claims')
    if claims.get('iss') != issuer:
        raise SignInError('the id_token is from another issuer')
    aud = claims.get('aud')
    if not (aud == client_id or (isinstance(aud, list) and client_id in aud)):
        raise SignInError('the id_token is for another client')
    exp = claims.get('exp')
    if not isinstance(exp, (int, float)) or exp < now - 60:
        raise SignInError('the id_token has expired')
    if not isinstance(claims.get('nonce'), str) or not hmac.compare_digest(claims['nonce'], nonce):
        raise SignInError('the id_token\'s nonce is wrong')
    return claims


# ------------------------------------------------------------------ the browser's way back (127.0.0.1:1455)

class Callback:
    """the redirect's listener, started before the browser opens"""

    def __init__(self, port):
        self.q = queue.Queue()
        cb = self

        class H(http.server.BaseHTTPRequestHandler):
            def log_message(self, *a):
                pass

            def do_GET(self):
                u = urllib.parse.urlsplit(self.path)
                if u.path != '/auth/callback':
                    self.send_error(404)
                    return
                q = urllib.parse.parse_qs(u.query, keep_blank_values=True)
                cb.q.put({k: v[0] for k, v in q.items() if len(v) == 1})
                body = (b'<!doctype html><meta charset="utf-8"><title>Veranda Ask</title>'
                        b'<p style="font:16px sans-serif">Done: you can close this window and go back to the X16.')
                self.send_response(200)
                self.send_header('Content-Type', 'text/html; charset=utf-8')
                self.send_header('Content-Length', str(len(body)))
                self.send_header('Connection', 'close')
                self.end_headers()
                self.wfile.write(body)

        try:
            self.srv = http.server.HTTPServer(('127.0.0.1', port), H)
        except OSError as e:
            raise SignInError('port %d on this PC is in use (%s)' % (port, e.strerror or e))
        self.port = self.srv.server_address[1]
        threading.Thread(target=self.srv.serve_forever, daemon=True).start()

    def wait(self, timeout, cancel):
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            if cancel.is_set():
                raise SignInError('the sign-in was cancelled')
            try:
                return self.q.get(timeout=0.5)
            except queue.Empty:
                pass
        raise SignInError('no sign-in in the browser in %d minutes' % (timeout // 60))

    def close(self):
        time.sleep(5)       # (a browser that asks again, or late: the page still answers)
        self.srv.shutdown()
        self.srv.server_close()


# ------------------------------------------------------------------ OpenAI's endpoints

class Endpoints:
    def __init__(self, a):
        self.issuer, self.authorize, self.token = a.issuer, a.authorize_url, a.token_url
        self.revoke, self.jwks, self.models = a.revoke_url, a.jwks_url, a.models_url
        self.callback_port, self.browser = a.callback_port, a.browser
        self.redirect = 'http://127.0.0.1:%d/auth/callback' % a.callback_port


def http_json(url, form=None, bearer=None, timeout=30):
    """(status, JSON or None): a form POST or a GET"""
    data = urllib.parse.urlencode(form).encode('ascii') if form is not None else None
    req = urllib.request.Request(url, data=data, method='POST' if form is not None else 'GET')
    req.add_header('Accept', 'application/json')
    req.add_header('User-Agent', 'VerandaAskSignIn/1.0')
    if form is not None:
        req.add_header('Content-Type', 'application/x-www-form-urlencoded')
    if bearer:
        req.add_header('Authorization', 'Bearer ' + bearer)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            status, raw = r.status, r.read(1 << 20)
    except urllib.error.HTTPError as e:
        status, raw = e.code, e.read(1 << 20)
    except (urllib.error.URLError, OSError) as e:
        raise SignInError('cannot reach %s (%s)' % (urllib.parse.urlsplit(url).netloc,
                                                  getattr(e, 'reason', e)))
    try:
        return status, json.loads(raw.decode('utf-8'))
    except (ValueError, UnicodeDecodeError):
        return status, None


def err_words(j):
    """an error reply's code and message"""
    if not isinstance(j, dict):
        return 'no JSON'
    e = j.get('error')
    if isinstance(e, dict):
        return '%s: %s' % (e.get('code') or e.get('type') or 'error', e.get('message') or '')
    if isinstance(e, str):
        return '%s: %s' % (e, j.get('error_description') or '')
    return str(j.get('detail') or 'error')


def clean(s, n):
    """a value for the X16's line: printable ASCII, n characters at most"""
    s = s if isinstance(s, str) else ''
    s = s.encode('ascii', 'replace').decode('ascii')
    return ''.join(c if ' ' <= c <= '~' else '?' for c in s)[:n].strip()


def models_of(ep, access):
    """the plan's models to list (visibility "list"), in the server's order:
    [(slug, name)], MAX_MODELS at most; [] when they cannot be had"""
    try:
        st, j = http_json(ep.models, bearer=access)
    except SignInError as e:
        log('  the models: %s (the X16 uses its default)' % e)
        return []
    if st != 200 or not isinstance(j, dict) or not isinstance(j.get('models'), list):
        log('  the models: HTTP %d %s (the X16 uses its default)' % (st, err_words(j)[:60]))
        return []
    out = []
    for m in j['models']:
        if not isinstance(m, dict) or m.get('visibility') != 'list':
            continue
        slug = m.get('slug')
        if not isinstance(slug, str) or not re.fullmatch(r'[A-Za-z0-9._:-]{1,30}', slug):
            continue
        out.append((slug, clean(m.get('display_name') or slug, 31) or slug))
        if len(out) == MAX_MODELS:
            break
    return out


def revoke(ep, client_id, refresh):
    """best effort: a refresh token that could not be handed over is ended"""
    try:
        st, _ = http_json(ep.revoke, form={'token': refresh, 'token_type_hint': 'refresh_token',
                                           'client_id': client_id})
        log('  the tokens were revoked (HTTP %d)' % st)
    except SignInError as e:
        log('  the tokens could not be revoked: %s' % e)


def open_browser(ep, url):
    print('\nOpen this address in the browser if it does not open by itself:\n  %s\n' % url, flush=True)
    if ep.browser == 'none':
        return
    if ep.browser:
        subprocess.Popen(shlex.split(ep.browser) + [url], stdin=subprocess.DEVNULL)
    else:
        webbrowser.open(url)


def sign_in(ep, host_id, client_id='', login='', cancel=None, timeout=600):
    """Sign in with ChatGPT for host_id (the X16's ext_agent_host_id):
    client_id is the X16's (a sign-in again) or '' (its first). Returns the
    credential set (a dict); SignInError if it did not finish."""
    cancel = cancel or threading.Event()
    first = not client_id
    verifier, challenge = pkce()
    state, nonce = secrets.token_urlsafe(24), secrets.token_urlsafe(24)
    cb = Callback(ep.callback_port)         # (listening before the browser opens)
    try:
        q = {'client_id': FIRST_CLIENT if first else client_id, 'response_type': 'code',
             'redirect_uri': ep.redirect, 'scope': SCOPE, 'resource': RESOURCE, 'state': state,
             'nonce': nonce, 'code_challenge_method': 'S256', 'code_challenge': challenge}
        if first:
            q['agent_name_hint'] = APP_NAME
        q['ext_agent_host_id'] = host_id
        if not first and login:
            q['login_hint'] = login
        open_browser(ep, ep.authorize + '?' + urllib.parse.urlencode(q, quote_via=urllib.parse.quote))
        log('  waiting for the sign-in in the browser')
        r = cb.wait(timeout, cancel)
    finally:
        cb.close()
    if not isinstance(r.get('state'), str) or not hmac.compare_digest(r['state'], state):
        raise SignInError('the browser\'s reply is not this sign-in\'s')
    if r.get('error'):
        if r['error'] == DENIED:
            raise SignInError('you declined the sign-in in the browser')
        raise SignInError(clean('%s %s' % (r['error'], r.get('error_description', '')), 100))
    code = r.get('code')
    if not code:
        raise SignInError('the browser\'s reply has no code')
    issued = r.get('client_id') or ''
    if first:
        if not issued or issued == FIRST_CLIENT:
            raise SignInError('the registration did not finish (no client_id came)')
    elif issued and issued != client_id:
        raise SignInError('the browser\'s reply is for another client_id')
    else:
        issued = client_id
    if not re.fullmatch(r'[\x21-\x7e]{1,127}', issued):
        raise SignInError('a client_id that cannot be kept')
    st, tok = http_json(ep.token, form={'grant_type': 'authorization_code', 'client_id': issued, 'code': code,
                                        'code_verifier': verifier, 'redirect_uri': ep.redirect,
                                        'resource': RESOURCE})
    if st != 200 or not isinstance(tok, dict):
        raise SignInError(clean('the token exchange failed (%d): %s' % (st, err_words(tok)), 100))
    access, refresh, idt = tok.get('access_token'), tok.get('refresh_token'), tok.get('id_token')
    for v in (access, refresh):
        if not isinstance(v, str) or not TOKEN_RE.fullmatch(v):
            raise SignInError('the token reply has no usable tokens')
    if len(access) > ACCMAX or len(refresh) > REFMAX:   # (V131: was 4095 and 2047; the X16 keeps 5119 and 1023)
        if not cancel.is_set():
            revoke(ep, issued, refresh)
        raise SignInError('the %s token is longer than the X16 keeps (%d characters, %d at most)'
                          % (('access', len(access), ACCMAX) if len(access) > ACCMAX else ('refresh', len(refresh), REFMAX)))
    if str(tok.get('token_type', '')).lower() != 'bearer':
        raise SignInError('the token reply is not a bearer token')
    if not isinstance(idt, str):
        raise SignInError('the token reply has no id_token')
    st, jwks = http_json(ep.jwks)
    if st != 200 or not isinstance(jwks, dict):
        raise SignInError('the signing keys could not be had')
    claims = verify_id_token(idt, jwks, ep.issuer, issued, nonce)
    if PLAN_SCOPE not in str(tok.get('scope', '')).split():
        if not cancel.is_set():
            revoke(ep, issued, refresh)
        raise SignInError('plan use was not granted (ChatGPT Plus or Pro)')
    exp = tok.get('expires_in')
    return {'client_id': issued, 'host_id': host_id, 'access': access, 'refresh': refresh,
            'expires': int(exp) if isinstance(exp, (int, float)) and exp > 0 else 3600,
            'login': clean(claims.get('email') or '', 63), 'models': models_of(ep, access),
            'earliest': earliest_of(tok.get('earliest_refresh_at')), 'got_at': time.time()}


def earliest_of(v):
    """(V131) a token reply's earliest_refresh_at as Unix seconds (a number, or an ISO 8601 time); None"""
    if isinstance(v, bool):
        return None
    if isinstance(v, (int, float)):
        return float(v)
    if isinstance(v, str):
        try:
            import datetime
            return datetime.datetime.fromisoformat(v.replace('Z', '+00:00')).timestamp()
        except ValueError:
            return None
    return None


def lines_of(cred):
    """the credential set as the X16's lines key=value"""
    out = ['client_id=' + cred['client_id'], 'host_id=' + cred['host_id']]
    if cred.get('login'):
        out.append('login=' + cred['login'])
    out += ['expires=%d' % cred['expires']]
    out += ['m=%s %s' % m for m in cred['models']]
    out += ['access=' + cred['access'], 'refresh=' + cred['refresh']]
    return out


# ------------------------------------------------------------------ the X16's request (LAN)

class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'
    timeout = 60
    server_version = 'VerandaAskSignIn/1.0'

    def log_message(self, *a):
        pass                                # (one line a request, below: never the code or a token)

    def reply(self, status, lines):
        b = ('\n'.join(lines) + '\n').encode('ascii', 'replace')
        self.send_response(status)
        self.send_header('Content-Type', 'text/plain; charset=us-ascii')
        self.send_header('Content-Length', str(len(b)))
        self.send_header('Connection', 'close')
        self.end_headers()
        self.wfile.write(b)
        self.wfile.flush()

    def chunk(self, s):
        b = s.encode('ascii', 'replace')
        self.wfile.write(b'%x\r\n' % len(b) + b + b'\r\n')
        self.wfile.flush()

    def do_GET(self):
        self.close_connection = True
        self.reply(404, ['error=this is Veranda Ask\'s sign-in helper: POST /x16/signin', 'end=fail'])

    def do_POST(self):
        self.close_connection = True
        S = self.server
        who = self.client_address[0]
        try:
            n = int(self.headers.get('content-length', ''))
        except ValueError:
            n = -1
        raw = self.rfile.read(n) if 0 <= n <= 4096 else b''
        if self.path.split('?')[0] != '/x16/signin':
            log('%s  404 %s' % (who, self.path[:40]))
            return self.reply(404, ['error=POST /x16/signin only', 'end=fail'])
        if n < 0 or n > 4096:
            return self.reply(400, ['error=a bad request', 'end=fail'])
        try:
            f = {k: v[0] for k, v in urllib.parse.parse_qs(raw.decode('ascii'), keep_blank_values=True).items()}
        except (UnicodeDecodeError, ValueError):
            f = {}
        with S.lock:
            if S.done or S.tries >= MAX_TRIES:
                return self.reply(403, ['error=start chatgpt_signin.py on the PC again', 'end=fail'])
            if not hmac.compare_digest(str(f.get('code', '')).encode(), S.code.encode()):
                S.tries += 1
                left = MAX_TRIES - S.tries
                log('%s  a wrong code (%d tries left)' % (who, left))
                if not left:
                    log('too many wrong codes: stopping')
                    threading.Thread(target=S.shutdown, daemon=True).start()
                    return self.reply(403, ['error=too many wrong codes: start the helper again', 'end=fail'])
                return self.reply(403, ['error=wrong code: %d tries left' % left, 'end=fail'])
            if S.busy:
                return self.reply(409, ['error=a sign-in is already running', 'end=fail'])
            S.busy = True
        try:
            self.signin(f, who)
        finally:
            with S.lock:
                S.busy = False

    def signin(self, f, who):
        S = self.server
        host_id, client_id = f.get('host_id', ''), f.get('client_id', '')
        if host_id and not HOST_ID_RE.fullmatch(host_id):
            return self.reply(400, ['error=the X16\'s host ID is not a urn:uuid', 'end=fail'])
        if client_id and not re.fullmatch(r'[\x21-\x7e]{1,127}', client_id):
            return self.reply(400, ['error=the X16\'s client_id is not one', 'end=fail'])
        made = not host_id
        host_id = host_id or 'urn:uuid:' + str(uuid.uuid4())
        log('%s  the code is right: signing in (%s, %s host ID)' % (
            who, 'a first registration' if not client_id else 'again', 'a new' if made else 'its'))
        self.send_response(200)
        self.send_header('Content-Type', 'text/plain; charset=us-ascii')
        self.send_header('Transfer-Encoding', 'chunked')
        self.send_header('Connection', 'close')
        self.end_headers()
        res, cancel = queue.Queue(), threading.Event()

        def work():
            try:
                res.put(sign_in(S.ep, host_id, client_id, f.get('login', ''), cancel, S.wait))
            except SignInError as e:
                res.put(e)
            except Exception as e:          # (any surprise: the X16 still gets an answer)
                res.put(SignInError('the sign-in failed: %s' % type(e).__name__))

        threading.Thread(target=work, daemon=True).start()
        try:
            while True:
                try:
                    r = res.get(timeout=S.keepalive)
                    break
                except queue.Empty:
                    self.chunk('wait=1\n')  # (the X16 gives up after 2 silent minutes)
        except OSError:
            cancel.set()
            log('%s  the X16 hung up: the sign-in is cancelled' % who)
            r = res.get()
            if isinstance(r, dict):
                revoke(S.ep, r['client_id'], r['refresh'])
            return
        if isinstance(r, SignInError):
            log('%s  not signed in: %s' % (who, r))
            msg = str(r)
            try:
                self.chunk('error=%s\nend=fail\n' % clean(msg, 78))
                self.chunk('')
            except OSError:
                pass
            return
        try:
            self.chunk('\n'.join(lines_of(r)) + '\nend=ok\n')
            self.chunk('')
        except OSError:
            log('%s  the X16 hung up before the credentials went: they are revoked, nothing is kept' % who)
            revoke(S.ep, r['client_id'], r['refresh'])
            r.clear()
            return
        log('%s  signed in%s; client_id %s...; %d models: the credentials are on the X16, none kept here' % (
            who, ' as ' + r['login'] if r['login'] else '', r['client_id'][:10], len(r['models'])))
        r.clear()
        S.done = True
        threading.Thread(target=S.shutdown, daemon=True).start()


class Server(http.server.ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True

    def verify_request(self, request, client_address):
        if allowed_client(client_address[0]):
            return True
        log('%s  refused: not a private address' % client_address[0])
        return False


def make_server(bind, port, code, ep, wait=600, keepalive=10):
    cls = Server
    if ':' in bind:
        cls = type('Server6', (Server,), {'address_family': socket.AF_INET6})
    s = cls((bind, port), Handler)
    s.code, s.ep, s.wait, s.keepalive = code, ep, wait, keepalive
    s.lock = threading.Lock()
    s.tries, s.busy, s.done = 0, False, False
    return s


def local_ips():
    ips = set()
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as u:
            u.connect(('192.168.0.1', 9))   # (no packet goes out: only the route is looked up)
            ips.add(u.getsockname()[0])
    except OSError:
        pass
    return sorted(ips)


# ------------------------------------------------------------------ the card (--card)

CARD_KEYS = ('access', 'refresh', 'client_id', 'host_id', 'login', 'expires', 'got', 'm')


def read_cfg(path):
    try:
        with open(path, 'rb') as f:
            return f.read().decode('latin-1').replace('\r\n', '\n').split('\n')
    except FileNotFoundError:
        return []


def minutes_since_2000(t=None):
    lt = time.localtime(t)
    return int((time.mktime(lt) - time.mktime((2000, 1, 1, 0, 0, 0, 0, 0, -1))) // 60)


def card(a, ep):
    folder = os.path.join(a.card, '.SYSTEM')
    if not os.path.isdir(a.card):
        sys.exit('chatgpt_signin.py: %s is not a folder (the card\'s VERANDA folder)' % a.card)
    os.makedirs(folder, exist_ok=True)
    path = os.path.join(folder, 'ASK.CFG')
    old = read_cfg(path) or read_cfg(os.path.join(folder, 'ASK.TMP'))
    kv = {}
    for ln in old:
        k, eq, v = ln.partition('=')
        if eq:
            kv.setdefault(k, v)
    host_id = kv.get('host_id', '')
    if not HOST_ID_RE.fullmatch(host_id):
        host_id = 'urn:uuid:' + str(uuid.uuid4())
    try:
        cred = sign_in(ep, host_id, kv.get('client_id', ''), kv.get('login', ''), timeout=a.wait)
    except SignInError as e:
        sys.exit('chatgpt_signin.py: not signed in: %s' % e)
    keep = [ln for ln in old if ln and ln.partition('=')[0] not in CARD_KEYS + ('server',)]
    out = ['server=plan'] + keep + lines_of(cred)[:-2] + ['got=%d' % minutes_since_2000()] + lines_of(cred)[-2:]
    write_cfg(folder, out)
    log('signed in%s: the credentials are in %s (none kept elsewhere)' % (
        ' as ' + cred['login'] if cred['login'] else '', path))
    r = check(a, ep, folder, cred) if a.check else None
    cred.clear()
    return r


def write_cfg(folder, lines):
    """ASK.CFG written as the X16 does: ASK.TMP first, then renamed"""
    tmp = os.path.join(folder, 'ASK.TMP')
    with open(tmp, 'wb') as f:
        f.write(('\r\n'.join(lines) + '\r\n').encode('latin-1', 'replace'))
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, os.path.join(folder, 'ASK.CFG'))


# ------------------------------------------------------------------ the X16's requests, made here (--check; V131)
#
# Byte for byte what Veranda Ask sends (apps/ask/auth.c's parts, apps/claude/
# net.c's escaping): gate ask compares these with what the X16 sent to its
# fake (tests/check_ask.py, the session tokens).

X16_UA = 'VerandaAsk/1.0 (Commander X16)'
# the built-in system prompt (apps/ask/page.c's sys_default) and Answers: short's (apps/claude/main.c's short_s)
X16_SYSTEM = (
    "You are talking with someone on a Commander X16, an 8-bit computer, through "
    "Veranda Ask. Its screen shows 74 columns of plain text and cannot show Markdown, "
    "emoji or most Unicode. Write plain ASCII text only: no Markdown headings, no * or ** "
    "for emphasis, no tables, no emoji. Keep paragraphs short, with a blank line between "
    "them; use simple dashes for lists. Put code in a fenced block: a line ``` with the "
    "language (```basic, ```asm, ```c), the code, then a line ```; the user can copy it or "
    "save it. Number every line of the X16's BASIC. Be concise unless asked for detail.")
X16_SHORT = ' Keep every answer short: a few sentences, or only the code asked for.'
X16_MODEL = 'gpt-6.2-sol'
RESOURCE_URL = 'https%3A%2F%2Fapi.openai.com%2Fv1'


def x16_json(t):
    """a string as net.c escapes it (esc): quotes, backslashes, \\n \\t \\r; printable ASCII as it is;
    anything else \\u with lower-case hex (the X16's text is ASCII here)"""
    out = []
    for c in t:
        o = ord(c)
        if c in '"\\':
            out.append('\\' + c)
        elif c in '\n\t\r':
            out.append({'\n': '\\n', '\t': '\\t', '\r': '\\r'}[c])
        elif 32 <= o < 127:
            out.append(c)
        else:
            out.append('\\u%04x' % o)
    return ''.join(out)


def x16_url(t):
    """net.c's URL encoding (uesc): letters, digits and -._~ as they are, the rest %xx (lower case)"""
    return ''.join(chr(b) if (48 <= b <= 57 or 65 <= b <= 90 or 97 <= b <= 122 or chr(b) in '-._~') else '%%%02x' % b
                   for b in t.encode('latin-1'))


def x16_host(host, port):
    return host + ('' if port in (443, 80) else ':%d' % port)


def x16_head(line, host, port, ctype, accept, auth, body):
    h = (line + ' HTTP/1.1\r\nHost: ' + x16_host(host, port) + '\r\nUser-Agent: ' + X16_UA
         + '\r\nAccept-Encoding: identity\r\nContent-Type: application/' + ctype + '\r\nAccept: ' + accept)
    if auth is not None:
        h += '\r\nAuthorization: Bearer ' + auth
    return (h + '\r\nContent-Length: %d\r\nConnection: close\r\n\r\n' % len(body)).encode('latin-1') + body


def x16_turn(host, port, token, model, instructions, messages):
    """POST /v1/responses as the X16 sends it (auth.c's chat): messages [(role, text)]"""
    body = ('{"model":"' + x16_json(model) + '","instructions":"' + x16_json(instructions) + '","input":['
            + ','.join('{"role":"%s","content":"%s"}' % (r, x16_json(t)) for r, t in messages)
            + '],"store":false,"stream":true}').encode('latin-1')
    return x16_head('POST /v1/responses', host, port, 'json', 'text/event-stream', token, body)


def x16_renew(host, port, client_id, refresh):
    """POST /api/accounts/oauth/token as the X16 sends it (auth.c's renew)"""
    body = ('grant_type=refresh_token&client_id=' + x16_url(client_id) + '&refresh_token=' + x16_url(refresh)
            + '&resource=' + RESOURCE_URL).encode('latin-1')
    return x16_head('POST /api/accounts/oauth/token', host, port, 'x-www-form-urlencoded', 'application/json',
                    None, body)


def x16_settings(lines):
    """ASK.CFG's lines as the X16 reads them (auth.c's a_load: the last of a key wins): the hosts, the
    model chosen, the instructions, the credentials"""
    kv, models = {}, []
    for ln in lines:
        k, eq, v = ln.partition('=')
        if not eq:
            continue
        if k == 'm':
            models.append(v.lstrip(' ').split(' ')[0][:30])
        else:
            kv[k] = v if k in ('access', 'refresh', 'client_id', 'host_id', 'login', 'key', 'system') else v.lstrip(' ')

    def hp(v, host):
        h, _, p = v.partition(':')
        return (h or host), (int(p) if p.isdigit() and int(p) else 443)
    model = kv.get('model', '')[:31]
    if models:
        model = model if model in models else models[0]
    instr = kv['system'] if 'system' in kv else X16_SYSTEM
    if kv.get('answers', '').startswith('s'):
        instr += X16_SHORT
    return {'api': hp(kv.get('api', ''), 'api.openai.com'), 'auth': hp(kv.get('auth', ''), 'auth.openai.com'),
            'tls': kv.get('tls', '1')[:1] != '0', 'model': model or X16_MODEL, 'instructions': instr,
            'access': kv.get('access', ''), 'refresh': kv.get('refresh', ''), 'client_id': kv.get('client_id', '')}


def x16_send(host, port, tls, data, timeout=90):
    """data sent as it is (TLS with the system's certificates checked; plain for the tests' fakes), the
    reply read to its end: (status, [(name, value)], body); SignInError when it cannot"""
    import ssl
    try:
        sk = socket.create_connection((host, port), timeout=timeout)
        if tls:
            sk = ssl.create_default_context().wrap_socket(sk, server_hostname=host)
        sk.sendall(data)
        raw = b''
        while len(raw) < 1 << 21:
            b = sk.recv(65536)
            if not b:
                break
            raw += b
            if x16_whole(raw):
                break
        sk.close()
    except (OSError, ValueError) as e:
        raise SignInError('cannot reach %s:%d (%s)' % (host, port, e))
    head, _, body = raw.partition(b'\r\n\r\n')
    lines = head.decode('latin-1').split('\r\n')
    try:
        status = int(lines[0].split()[1])
    except (IndexError, ValueError):
        raise SignInError('%s:%d sent no HTTP reply' % (host, port))
    hdrs = [(k.strip().lower(), v.strip()) for k, _, v in (ln.partition(':') for ln in lines[1:])]
    if any(k == 'transfer-encoding' and 'chunked' in v.lower() for k, v in hdrs):
        body = dechunk(body)
    return status, hdrs, body


def x16_whole(raw):
    """the reply has come whole (its Content-Length, or its last chunk)"""
    head, sep, body = raw.partition(b'\r\n\r\n')
    if not sep:
        return False
    h = head.lower()
    m = re.search(rb'\r\ncontent-length:\s*(\d+)', h)
    if m:
        return len(body) >= int(m.group(1))
    if b'chunked' in h:
        return body.startswith(b'0\r\n\r\n') or b'\r\n0\r\n\r\n' in body
    return False


def dechunk(b):
    out = b''
    while b:
        size, _, b = b.partition(b'\r\n')
        try:
            n = int(size.split(b';')[0], 16)
        except ValueError:
            break
        if not n:
            break
        out, b = out + b[:n], b[n + 2:]
    return out


TOKENISH = re.compile(r'(?:eyJ|rt_|sk-)[A-Za-z0-9._~+/=-]*')


def redact(text, toks=()):
    """anything token-like cut to its first 6 characters (eyJ..., rt_..., sk-...), and the tokens themselves"""
    for t in toks:
        if t and len(t) > 6:
            text = text.replace(t, t[:6] + '...')
    return TOKENISH.sub(lambda m: m.group(0)[:6] + '...' if len(m.group(0)) > 6 else m.group(0), text)


def tsum(t):
    """a token's length and 16-bit byte sum, as the X16's ASK.LOG shows them"""
    b = t.encode('latin-1')
    return '%d bytes, sum %d' % (len(b), sum(b) & 0xFFFF)


def sse_text(body):
    """(the deltas' text, response.completed came)"""
    text, done = '', False
    for ln in body.decode('utf-8', 'replace').split('\n'):
        if not ln.startswith('data:'):
            continue
        try:
            e = json.loads(ln[5:].strip())
        except ValueError:
            continue
        if isinstance(e, dict) and e.get('type') == 'response.output_text.delta' and isinstance(e.get('delta'), str):
            text += e['delta']
        elif isinstance(e, dict) and e.get('type') == 'response.completed':
            done = True
    return text, done


SHOWN = ('www-authenticate', 'x-request-id', 'cf-ray', 'content-type', 'openai-processing-ms', 'openai-version')


def show_reply(what, st, hdrs, body, toks):
    print('  %s: HTTP %d' % (what, st))
    for k, v in hdrs:
        if k in SHOWN:
            print('    %s: %s' % (k, redact(clean(v, 120), toks)))
    print('    its body (%d bytes):' % len(body))
    for ln in redact(body.decode('utf-8', 'replace'), toks).splitlines()[:40]:
        print('      ' + ln[:200])


def check(a, ep, folder, cred):
    """--check: from this PC, exactly the X16's turn ("Reply with OK") and its renewal, with what the
    card's ASK.CFG holds now; the rotated tokens written back; what that says. No token is printed."""
    lines = read_cfg(os.path.join(folder, 'ASK.CFG'))
    x = x16_settings(lines)
    toks = [x['access'], x['refresh'], cred.get('access'), cred.get('refresh')]
    print('\nThe check: the X16\'s own requests, sent from this PC (no token is shown)')
    print('  ASK.CFG: the access token %s; the refresh token %s; the client_id %d characters; model %s'
          % (tsum(x['access']), tsum(x['refresh']), len(x['client_id']), x['model']))
    print('  (the X16\'s ASK.LOG says "authorization: Bearer + N bytes, sum S" for the token it sent: the same N '
          'and S say it sent it whole)', flush=True)
    host, port = x['api']
    req = x16_turn(host, port, x['access'], x['model'], x['instructions'], [('user', 'Reply with OK')])
    print('  the turn: POST /v1/responses to %s (%d bytes, as the X16 sends it)' % (x16_host(host, port), len(req)),
          flush=True)
    turn_ok, st = False, 0
    try:
        st, hdrs, body = x16_send(host, port, x['tls'], req)
        if 200 <= st < 300:
            text, turn_ok = sse_text(body)
            print('  the turn: HTTP %d, the reply "%s"%s' % (st, redact(clean(text, 60), toks),
                                                           ' (response.completed)' if turn_ok else ' (not completed)'))
        else:
            show_reply('the turn', st, hdrs, body, toks)
    except SignInError as e:
        print('  the turn: %s' % e)
    # the renewal: not before the server's earliest_refresh_at (one before it may be refused)
    ren, wait = None, 0
    if cred.get('earliest'):
        wait = cred['earliest'] - time.time()
    if wait > a.check_wait:
        print('  the renewal: not tried: OpenAI\'s token reply says not to renew for %d more minutes '
              '(earliest_refresh_at: %d s after the sign-in); one before then may be refused. (Veranda Ask renews '
              'only near the access token\'s end.)' % ((wait + 59) // 60, cred['earliest'] - cred['got_at']))
    else:
        if wait > 0:
            print('  the renewal: waiting %d s (earliest_refresh_at)' % wait, flush=True)
            time.sleep(wait + 1)
        host, port = x['auth']
        req = x16_renew(host, port, x['client_id'], x['refresh'])
        print('  the renewal: POST /api/accounts/oauth/token to %s (%d bytes, as the X16 sends it)'
              % (x16_host(host, port), len(req)), flush=True)
        try:
            ren, rh, rb = x16_send(host, port, x['tls'], req)
        except SignInError as e:
            ren = 0
            print('  the renewal: %s' % e)
        try:
            j = json.loads(rb.decode('utf-8')) if ren else None
        except (ValueError, UnicodeDecodeError):
            j = None
        if ren == 200 and isinstance(j, dict) and isinstance(j.get('access_token'), str):
            acc, ref = j['access_token'], j.get('refresh_token') or x['refresh']
            toks += [acc, ref]
            if TOKEN_RE.fullmatch(acc) and TOKEN_RE.fullmatch(ref) and len(acc) <= ACCMAX and len(ref) <= REFMAX:
                exp = j.get('expires_in')
                exp = int(exp) if isinstance(exp, (int, float)) and exp > 0 else 3600
                out = [ln for ln in lines if ln and ln.partition('=')[0] not in ('access', 'refresh', 'expires', 'got')]
                write_cfg(folder, out + ['expires=%d' % exp, 'got=%d' % minutes_since_2000(), 'access=' + acc,
                                         'refresh=' + ref])
                print('  the renewal: HTTP 200: a new access token (%s)%s; written to ASK.CFG'
                      % (tsum(acc), ', a new refresh token' if j.get('refresh_token') else ', the refresh token kept'))
            else:
                print('  the renewal: HTTP 200, but its tokens are not ones the X16 can keep (%d and %d characters)'
                      % (len(acc), len(ref)))
                ren = -1
        elif ren:
            show_reply('the renewal', ren, rh, rb, toks)
    print('\nWhat it says:')
    if turn_ok:
        print('  PC call OK: OpenAI took this very request from this PC with the token on the card, so the X16\'s '
              'sending is the suspect: compare the next ASK.LOG\'s "authorization: Bearer + N bytes, sum S" with '
              'the access token\'s above.')
    elif st == 401:
        print('  PC call 401: OpenAI refused the same request from this PC too, so the X16\'s transmission is not '
              'the cause. OpenAI\'s reason is the body above.')
    elif st:
        print('  PC call %d: OpenAI refused the same request from this PC too (its body above).' % st)
    else:
        print('  PC call: no reply from OpenAI (this PC\'s network?).')
    if ren == 200:
        print('  The renewal works from this PC; the card has the new tokens.')
    elif ren:
        print('  The renewal was refused (HTTP %d, its body above)%s.' % (
            ren, ': if it says invalid_grant the sign-in has ended; sign in again (without --check)'
            if ren in (400, 401) else ''))
    sys.stdout.flush()
    return 0 if turn_ok and ren in (200, None) else 2


def main(argv=None):
    ap = argparse.ArgumentParser(
        prog='chatgpt_signin.py', formatter_class=argparse.RawDescriptionHelpFormatter,
        description='Sign Veranda Ask (Commander X16) in with your ChatGPT plan, from this PC.',
        epilog='Run it, then in Veranda Ask: Settings, ChatGPT plan, this PC\'s address\n'
               '(e.g. 192.168.1.20:8643) and the code it prints, Continue with ChatGPT.\n'
               'Or --card /media/you/X16CARD/VERANDA writes the credentials onto the card.\n'
               'Plain HTTP on your network: only private addresses may connect.')
    ap.add_argument('--port', type=int, default=DEFAULT_PORT, help='the TCP port (default %(default)s)')
    ap.add_argument('--bind', default='0.0.0.0', help='the address to listen on (default %(default)s: every one)')
    ap.add_argument('--card', metavar='VERANDA', help='write the credentials into VERANDA/.SYSTEM/ASK.CFG on a card instead')
    ap.add_argument('--wait', type=int, default=600, help='seconds the browser\'s sign-in may take (default %(default)s)')
    ap.add_argument('--no-browser', action='store_true', help='do not open a browser: print the address to open')
    ap.add_argument('--check', action='store_true',
                    help='with --card: then, from this PC, the X16\'s own turn and renewal with the card\'s tokens '
                         '(what OpenAI says; no token shown); the renewed tokens written to the card')
    S = argparse.SUPPRESS                       # (the tests' own: fake servers)
    ap.add_argument('--issuer', default=ISSUER, help=S)
    ap.add_argument('--authorize-url', default=AUTHORIZE_URL, help=S)
    ap.add_argument('--token-url', default=TOKEN_URL, help=S)
    ap.add_argument('--revoke-url', default=REVOKE_URL, help=S)
    ap.add_argument('--jwks-url', default=JWKS_URL, help=S)
    ap.add_argument('--models-url', default=MODELS_URL, help=S)
    ap.add_argument('--callback-port', type=int, default=CALLBACK_PORT, help=S)
    ap.add_argument('--browser', default=None, help=S)
    ap.add_argument('--code', default=None, help=S)
    ap.add_argument('--keepalive', type=float, default=10, help=S)
    ap.add_argument('--check-wait', type=float, default=300, help=S)
    a = ap.parse_args(argv)
    if a.no_browser:
        a.browser = 'none'
    ep = Endpoints(a)
    if a.check and not a.card:
        sys.exit('chatgpt_signin.py: --check needs --card (the card\'s VERANDA folder)')
    if a.card:
        return card(a, ep)
    code = a.code or '%06d' % secrets.randbelow(10 ** 6)
    try:
        s = make_server(a.bind, a.port, code, ep, a.wait, a.keepalive)
    except OSError as e:
        sys.exit('chatgpt_signin.py: cannot listen on %s:%d: %s' % (a.bind, a.port, e))
    port = s.server_address[1]
    print('Veranda Ask: Sign in with ChatGPT\n\n  The code: %s\n' % code, flush=True)
    for ip in local_ips():
        print('  In Veranda Ask\'s Settings: ChatGPT plan, PC %s:%d, this code, Continue with ChatGPT' % (ip, port),
              flush=True)
    log('listening on %s port %d (only private addresses; %d tries for the code)' % (a.bind, port, MAX_TRIES))
    if os.environ.get('CHATGPT_SIGNIN_READY'):
        with open(os.environ['CHATGPT_SIGNIN_READY'], 'w') as f:
            f.write('%d\n' % port)
    try:
        s.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        s.server_close()
    return 0 if s.done else 1


if __name__ == '__main__':
    sys.exit(main())
