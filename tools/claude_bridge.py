#!/usr/bin/env python3
# Veranda Claude's bridge to Claude Code (DECISIONS V115).
# Copyright (c) 2026 Marcin Spoczynski. MIT licence (see LICENSE).
"""claude_bridge.py: Veranda Claude on the Commander X16 talks to your own
Claude Code on this PC.

Run it on a PC where Claude Code (`claude`) is installed and signed in
(with your claude.ai plan):

    python3 claude_bridge.py --password something-long

then, in Veranda Claude's Settings, choose "Claude Code on my PC" and type
this PC's IP address (port 8642) and the same password. Without
--password (or CLAUDE_BRIDGE_PASSWORD) a password is made up and printed.

Each turn runs `claude -p` (print mode) once, with every tool off, no MCP
servers, no slash commands, and in an empty folder of its own
(~/.cache/veranda-claude-bridge/work): the X16 can only talk; it cannot
make this PC run anything or read a file. The bridge never reads Claude
Code's credentials: it only runs the program. It speaks the Anthropic
Messages API's HTTP and server-sent events, so Veranda Claude needs no
second dialect. Plain HTTP: the password and the conversation cross the
home network unencrypted, so only private addresses may connect.
"""
import argparse
import collections
import difflib
import hashlib
import hmac
import http.server
import ipaddress
import json
import os
import re
import secrets
import selectors
import signal
import socket
import subprocess
import sys
import threading
import time
import uuid

DEFAULT_PORT = 8642
DEFAULT_SYSTEM = (
    "You are Claude, talking with someone on a Commander X16, an 8-bit computer, through "
    "Veranda Claude. Its screen shows 74 columns of plain text and cannot show Markdown, "
    "emoji or most Unicode. Write plain ASCII text only: no Markdown (no #, no * or ** "
    "for emphasis, no backticks, no tables), no emoji. Keep paragraphs short, with a blank "
    "line between them; use simple dashes for lists. Be concise unless asked for detail.")
MAX_BODY = 1 << 20
MAX_SYSTEM = 4000

# Every one of these goes on every run (a resumed one too: Claude Code does
# not keep them in the session). Built-in tools: none (--tools ""), and every
# tool denied besides (--disallowedTools "*"); MCP: only the empty config;
# nothing may ask for or be given permission; no skills or slash commands;
# no hooks, plugins, CLAUDE.md or MCP from the user's set-up (--safe-mode:
# its documentation keeps the login working); only the user's own settings
# file, never a project's (the folder is empty anyway).
SAFE_ARGS = [
    '-p', '--output-format', 'stream-json', '--verbose', '--include-partial-messages',
    '--tools', '',
    '--disallowedTools', '*',
    '--strict-mcp-config', '--mcp-config', '{"mcpServers":{}}',
    '--permission-mode', 'dontAsk', '--permission-prompts', 'none',
    '--disable-slash-commands', '--safe-mode',
    '--setting-sources', 'user',
]


def log(msg):
    sys.stderr.write(time.strftime('%H:%M:%S ') + msg + '\n')
    sys.stderr.flush()


# ------------------------------------------------------------------ who may connect

_PRIVATE4 = [ipaddress.ip_network(n) for n in ('127.0.0.0/8', '10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16')]
_PRIVATE6 = [ipaddress.ip_network(n) for n in ('::1/128', 'fc00::/7', 'fe80::/10')]


def allowed_client(addr):
    """the X16 must be on this PC's own network: loopback, 10/8, 172.16/12,
    192.168/16; IPv6 loopback, unique-local and link-local"""
    try:
        ip = ipaddress.ip_address(addr.split('%')[0])
    except ValueError:
        return False
    if ip.version == 6 and ip.ipv4_mapped:
        ip = ip.ipv4_mapped
    nets = _PRIVATE4 if ip.version == 4 else _PRIVATE6
    return any(ip in n for n in nets)


def password_ok(given, password):
    return isinstance(given, str) and hmac.compare_digest(given.encode('utf-8', 'replace'),
                                                          password.encode('utf-8'))


# ------------------------------------------------------------------ the request

def text_of(content):
    """a message's content (a string, or a list of text blocks) as text"""
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return '\n'.join(b.get('text', '') for b in content
                         if isinstance(b, dict) and b.get('type') == 'text' and isinstance(b.get('text'), str))
    return None


def conversation(body):
    """[(role, text)] from the request, the last a user's; ValueError if not"""
    msgs = body.get('messages')
    if not isinstance(msgs, list) or not msgs:
        raise ValueError('no messages')
    out = []
    for m in msgs:
        if not isinstance(m, dict) or m.get('role') not in ('user', 'assistant'):
            raise ValueError('a message without a role')
        t = text_of(m.get('content'))
        if t is None:
            raise ValueError('a message without text')
        out.append((m['role'], t))
    if out[-1][0] != 'user' or not out[-1][1].strip():
        raise ValueError('the last message is not the user\'s')
    return out


def system_of(body):
    s = body.get('system')
    t = text_of(s) if s is not None else None
    t = (t or '').strip() or DEFAULT_SYSTEM
    return t[:MAX_SYSTEM]


def model_of(body):
    """the X16's model (claude-opus-5-5 ...) for --model: a full name as it
    is (Claude Code takes them), anything else Claude Code's default"""
    m = body.get('model')
    if isinstance(m, str) and re.fullmatch(r'claude-[a-z0-9.-]{1,60}', m):
        return m
    return None


def transcript(conv):
    """a new session's prompt: the earlier turns, then the new message"""
    *old, (_, new) = conv
    if not old:
        return new
    parts = ['(This conversation began earlier; here it is so far.)', '']
    for role, t in old:
        parts += ['User:' if role == 'user' else 'You (Claude):', t, '']
    parts += ['(Now the user says:)', new]
    return '\n'.join(parts)


def guard_slash(prompt):
    """a prompt that starts with / is never a command (they are off too)"""
    return ' ' + prompt if prompt.lstrip().startswith('/') else prompt


# ------------------------------------------------------------------ the sessions

def _loose(t):
    """a reply as it may come back: the X16 folds Unicode to its font (and
    drops what it cannot show), so only ASCII letters and digits are compared"""
    return re.sub(r'[^a-z0-9]', '', t.lower())


class Sessions:
    """the conversation so far -> Claude Code's session: its user turns
    exactly, its replies loosely (the X16 sends them back folded)"""

    def __init__(self, size=64, max_age=24 * 3600):
        self.size, self.max_age = size, max_age
        self.map = collections.OrderedDict()   # key -> (session id, [replies], when)
        self.lock = threading.Lock()

    @staticmethod
    def key(conv):
        h = hashlib.sha256()
        for role, t in conv:
            h.update(b'u' if role == 'user' else b'a')
            if role == 'user':
                h.update(' '.join(t.split()).encode('utf-8', 'replace'))
            h.update(b'\0')
        return h.hexdigest()

    @staticmethod
    def _replies(conv):
        return [_loose(t) for role, t in conv if role == 'assistant']

    def find(self, prior):
        """the session holding exactly the turns before the new message, or None"""
        if not prior:
            return None
        with self.lock:
            self._expire()
            e = self.map.get(self.key(prior))
            if not e:
                return None
            sid, reps, _ = e
            now = self._replies(prior)
            if len(now) != len(reps):
                return None
            for a, b in zip(now, reps):
                if a != b and difflib.SequenceMatcher(None, a, b, autojunk=False).ratio() < 0.9:
                    return None
            return sid

    def drop(self, sid):
        """a session that ran a turn: its old entries are stale"""
        with self.lock:
            for k in [k for k, e in self.map.items() if e[0] == sid]:
                del self.map[k]

    def add(self, conv, sid):
        """conv (ending with Claude's reply) is now session sid"""
        with self.lock:
            k = self.key(conv)
            self.map[k] = (sid, self._replies(conv), time.time())
            self.map.move_to_end(k)
            self._expire()
            while len(self.map) > self.size:
                self.map.popitem(last=False)

    def _expire(self):
        old = time.time() - self.max_age
        for k in [k for k, e in self.map.items() if e[2] < old]:
            del self.map[k]


# ------------------------------------------------------------------ Claude Code

def command(claude, model, system, session, resume):
    """the argv of one turn"""
    argv = [claude] + SAFE_ARGS
    if model:
        argv += ['--model', model]
    argv += ['--append-system-prompt', system]
    argv += ['--resume', session] if resume else ['--session-id', session]
    return argv


def child_env():
    """this environment, but an API key in it would bill the API instead of
    the claude.ai plan: it is left out"""
    env = dict(os.environ)
    for k in ('ANTHROPIC_API_KEY', 'ANTHROPIC_AUTH_TOKEN'):
        env.pop(k, None)
    return env


_WINDOWS = {'five_hour': '5-hour', 'seven_day': 'weekly', 'seven_day_opus': 'weekly Opus',
            'seven_day_sonnet': 'weekly Sonnet'}


def limit_of(info):
    """a rate_limit_event's rate_limit_info that says no -> a short message, else None"""
    if not isinstance(info, dict) or info.get('status') in (None, 'allowed', 'allowed_warning'):
        return None
    w = _WINDOWS.get(info.get('rateLimitType'), '')
    m = 'usage limit reached' + (' (%s)' % w if w else '')
    r = info.get('resetsAt')
    if isinstance(r, (int, float)) and r > 0:
        m += ', resets ' + time.strftime('%a %H:%M', time.localtime(r))
    return m


def classify(text, status=None):
    """Claude Code's error text -> (the API's error type, a short message for
    the X16's 80 columns)"""
    t = ' '.join((text or '').split())
    low = t.lower()
    if status == 401:
        return 'authentication_error', 'not signed in: run claude on the PC, then /login'
    if status == 429 and 'limit' not in low:
        return 'rate_limit_error', 'too many requests: try again in a moment'
    if 'limit' in low and ('reset' in low or 'hit your' in low or 'usage' in low):
        m = re.search(r'resets?\s+(?:at\s+)?([^.()\n]{1,30})', t, re.I)
        return 'rate_limit_error', 'usage limit reached' + (', resets ' + m.group(1).strip() if m else '')
    if 'not logged in' in low or '/login' in low or 'authenticat' in low or 'oauth' in low or 'sign in' in low:
        return 'authentication_error', 'not signed in: run claude on the PC, then /login'
    if 'overloaded' in low or '529' in low:
        return 'overloaded_error', 'Claude is overloaded: try again in a moment'
    if 'rate limit' in low or '429' in low:
        return 'rate_limit_error', 'too many requests: try again in a moment'
    if not t:
        return 'api_error', 'Claude Code ended without an answer'
    return 'api_error', t[:100]


def sse(event, data):
    return ('event: %s\ndata: %s\n\n' % (event, json.dumps(data, ensure_ascii=False))).encode('utf-8')


def error_json(etype, message):
    return json.dumps({'type': 'error', 'error': {'type': etype, 'message': message},
                       'request_id': 'req_bridge'}).encode()


class Turn:
    """one turn: Claude Code's stream-json read as it comes, the API's
    events written to the X16 as they are made"""

    def __init__(self, handler, conv, argv, prompt, model, timeout, idle):
        self.h, self.conv, self.argv, self.prompt = handler, conv, argv, prompt
        self.model = model or 'claude-code'
        self.timeout, self.idle = timeout, idle
        self.text = []
        self.session = None
        self.stop_reason = 'end_turn'
        self.usage = {}
        self.result = None
        self.fallback = []              # an assistant message's text (no partials came)
        self.deltas = False
        self.limit = None               # a rate_limit_event that said no
        self.sep = False
        self.outcome = ''

    # (the X16's end)
    def send(self, b):
        self.h.wfile.write(b'%x\r\n' % len(b) + b + b'\r\n')
        self.h.wfile.flush()

    def event(self, ev, data):
        self.send(sse(ev, data))

    def text_out(self, t):
        if not t:
            return
        if not self.text:
            self.event('content_block_start', {'type': 'content_block_start', 'index': 0,
                                               'content_block': {'type': 'text', 'text': ''}})
        if self.sep and self.text:
            t = '\n\n' + t
        self.sep = False
        self.text.append(t)
        self.event('content_block_delta', {'type': 'content_block_delta', 'index': 0,
                                           'delta': {'type': 'text_delta', 'text': t}})

    # (Claude Code's end)
    def line(self, ln):
        try:
            m = json.loads(ln)
        except ValueError:
            return
        if not isinstance(m, dict):
            return
        typ = m.get('type')
        if m.get('session_id') and not self.session:
            self.session = m['session_id']
        if m.get('parent_tool_use_id'):
            return
        if typ == 'stream_event':
            e = m.get('event') or {}
            et = e.get('type')
            if et == 'message_start' and self.text:
                self.sep = True
            elif et == 'content_block_delta':
                d = e.get('delta') or {}
                if d.get('type') == 'text_delta' and isinstance(d.get('text'), str):
                    self.deltas = True
                    self.text_out(d['text'])
            elif et == 'message_delta':
                sr = (e.get('delta') or {}).get('stop_reason')
                if sr:
                    self.stop_reason = sr
        elif typ == 'assistant':
            msg = m.get('message') or {}
            if m.get('error') or msg.get('model') == '<synthetic>':
                return                  # (Claude Code's own error text: the result says it)
            if not self.deltas:
                self.fallback.append(text_of(msg.get('content')) or '')
        elif typ == 'rate_limit_event':
            self.limit = limit_of(m.get('rate_limit_info')) or self.limit
        elif typ == 'result':
            self.result = m
            if m.get('session_id'):
                self.session = m['session_id']

    def run(self):
        """True: a whole reply"""
        try:
            p = subprocess.Popen(self.argv, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                 stderr=subprocess.PIPE, cwd=self.h.server.workdir, env=child_env(),
                                 start_new_session=True)
        except OSError as e:
            self.h.error(503, 'api_error', 'claude not found on the PC (%s)' % type(e).__name__)
            self.outcome = 'claude not found: %s' % e
            return False
        self.proc = p
        err = collections.deque(maxlen=20)
        threading.Thread(target=lambda: [err.append(x) for x in iter(p.stderr.readline, b'')],
                         daemon=True).start()
        try:
            p.stdin.write(self.prompt.encode('utf-8'))
            p.stdin.close()
        except OSError:
            pass
        h = self.h
        h.send_response(200)
        h.send_header('Content-Type', 'text/event-stream; charset=utf-8')
        h.send_header('Transfer-Encoding', 'chunked')
        h.send_header('Connection', 'close')
        h.end_headers()
        try:
            self.event('message_start', {'type': 'message_start', 'message': {
                'id': 'msg_bridge_' + uuid.uuid4().hex[:12], 'type': 'message', 'role': 'assistant',
                'model': self.model, 'content': [], 'stop_reason': None, 'stop_sequence': None,
                'usage': {'input_tokens': 0, 'output_tokens': 0}}})
            ok = self.pump(p, err)
        except OSError:
            self.outcome = 'stopped: the X16 hung up'
            ok = False
        finally:
            self.kill(p)
        return ok

    def kill(self, p):
        if p.poll() is None:
            try:
                os.killpg(p.pid, signal.SIGTERM)
            except OSError:
                pass
            try:
                p.wait(3)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(p.pid, signal.SIGKILL)
                except OSError:
                    pass
                p.wait()
            if not self.outcome:
                self.outcome = 'stopped'
            self.outcome += ' (Claude Code killed)'

    def pump(self, p, err):
        sel = selectors.DefaultSelector()
        fd = p.stdout.fileno()
        os.set_blocking(fd, False)
        sel.register(fd, selectors.EVENT_READ, 'claude')
        sel.register(self.h.connection, selectors.EVENT_READ, 'x16')
        buf = b''
        t0 = last = ping = time.monotonic()
        eof = False
        while not eof:
            for k, _ in sel.select(1.0):
                if k.data == 'x16':
                    try:
                        b = self.h.connection.recv(512, socket.MSG_DONTWAIT)
                    except BlockingIOError:
                        continue
                    except OSError:
                        b = b''
                    if not b:
                        self.outcome = 'stopped: the X16 hung up'
                        return False
                    continue
                try:
                    b = os.read(fd, 65536)
                except BlockingIOError:
                    continue
                if not b:
                    eof = True
                    break
                last = time.monotonic()
                buf += b
                while b'\n' in buf:
                    ln, buf = buf.split(b'\n', 1)
                    self.trace(ln)
                    self.line(ln.decode('utf-8', 'replace'))
            now = time.monotonic()
            if now - t0 > self.timeout or now - last > self.idle:
                self.fail('timeout_error', 'no answer from Claude Code for %d s: stopped'
                          % int(now - (t0 if now - t0 > self.timeout else last)))
                self.outcome = 'timed out'
                return False
            if now - ping > 10:
                ping = now
                self.event('ping', {'type': 'ping'})
        if buf.strip():
            self.line(buf.decode('utf-8', 'replace'))
        try:
            p.wait(5)
        except subprocess.TimeoutExpired:
            pass
        r = self.result
        if r is None or r.get('is_error') or r.get('subtype', 'success') != 'success':
            why = ''
            if r is not None:
                why = r.get('result') if isinstance(r.get('result'), str) else ''
                if not why and isinstance(r.get('errors'), list):
                    why = ' '.join(str(x) for x in r['errors'])
            if not why:
                why = b' '.join(err).decode('utf-8', 'replace')
            et, msg = classify(why, r.get('api_error_status') if r else None)
            if et == 'rate_limit_error' and self.limit:
                msg = self.limit
            self.fail(et, msg)
            self.outcome = 'error: %s (%s)' % (msg, ' '.join(why.split())[:80])
            return False
        if not self.deltas:
            self.text_out('\n\n'.join(t for t in self.fallback if t) or (r.get('result') or ''))
        if self.text:
            self.event('content_block_stop', {'type': 'content_block_stop', 'index': 0})
        u = r.get('usage') or {}
        usage = {'output_tokens': int(u.get('output_tokens') or 0)}
        for k in ('input_tokens', 'cache_read_input_tokens', 'cache_creation_input_tokens'):
            if isinstance(u.get(k), int):
                usage[k] = u[k]
        self.event('message_delta', {'type': 'message_delta',
                                     'delta': {'stop_reason': self.stop_reason, 'stop_sequence': None},
                                     'usage': usage})
        self.event('message_stop', {'type': 'message_stop'})
        self.send(b'')
        n = len(''.join(self.text))
        self.outcome = 'ok: %d characters in %.1f s' % (n, time.monotonic() - t0)
        return bool(self.text)

    def trace(self, ln):
        t = self.h.server.trace
        if t:
            with open(t, 'ab') as f:
                f.write(ln + b'\n')

    def fail(self, etype, msg):
        self.event('error', {'type': 'error', 'error': {'type': etype, 'message': msg}})
        self.send(b'')


# ------------------------------------------------------------------ HTTP

class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'
    timeout = 60                        # (a client that stops sending its request)
    server_version = 'VerandaClaudeBridge/1.0'

    def log_message(self, fmt, *args):
        pass                            # (one line a request, below; never the headers)

    def error(self, status, etype, message):
        b = error_json(etype, message)
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(b)))
        self.send_header('Connection', 'close')
        self.end_headers()
        self.wfile.write(b)
        self.wfile.flush()

    def note(self, model, n, outcome):
        log('%s  %s  prompt %d chars  %s' % (self.client_address[0], model or '-', n, outcome))

    def do_GET(self):
        self.close_connection = True
        self.error(404, 'not_found_error', 'this is Veranda Claude\'s bridge: POST /v1/messages')

    def do_POST(self):
        self.close_connection = True
        S = self.server
        try:
            n = int(self.headers.get('content-length', ''))
        except ValueError:
            n = -1
        # (the body read first, whatever comes of it: a reply sent over unread
        # bytes makes the close a reset, and the X16 loses the reply)
        raw = self.rfile.read(n) if 0 <= n <= MAX_BODY else b''
        if self.path.split('?')[0] != '/v1/messages':
            self.error(404, 'not_found_error', 'POST /v1/messages only')
            return self.note(None, 0, '404 %s' % self.path[:40])
        if not password_ok(self.headers.get('x-api-key'), S.password):
            self.error(401, 'authentication_error', 'the bridge password was not accepted')
            return self.note(None, 0, '401: wrong or no password')
        if n < 0 or n > MAX_BODY:
            self.error(413 if n > MAX_BODY else 411, 'invalid_request_error', 'a body of up to 1 MB, with its length')
            return self.note(None, 0, 'bad length')
        try:
            body = json.loads(raw.decode('utf-8'))
            if not isinstance(body, dict):
                raise ValueError('not an object')
            conv = conversation(body)
        except (ValueError, UnicodeDecodeError) as e:
            self.error(400, 'invalid_request_error', 'a bad request: %s' % str(e)[:60])
            return self.note(None, 0, '400 %s' % str(e)[:60])
        model = model_of(body)
        if not S.turn_lock.acquire(blocking=False):
            self.error(529, 'overloaded_error', 'the bridge is busy with another turn')
            return self.note(model, len(conv[-1][1]), '529: busy')
        try:
            self.turn(body, conv, model)
        finally:
            S.turn_lock.release()

    def turn(self, body, conv, model):
        S = self.server
        prior = conv[:-1]
        sid = S.sessions.find(prior)
        if sid:
            prompt, how = conv[-1][1], 'resumed'
        else:
            sid, prompt, how = str(uuid.uuid4()), transcript(conv), 'new session' + (
                ' (%d earlier turns)' % len(prior) if prior else '')
        prompt = guard_slash(prompt)
        argv = command(S.claude, model, system_of(body), sid, bool(how == 'resumed'))
        t = Turn(self, conv, argv, prompt, model, S.timeout, S.idle)
        ok = t.run()
        S.sessions.drop(sid)
        if t.session and t.session != sid:
            S.sessions.drop(t.session)
        if ok:
            S.sessions.add(conv + [('assistant', ''.join(t.text))], t.session or sid)
        self.note(model, len(prompt), '%s, %s' % (t.outcome, how))


class Server(http.server.ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True

    def verify_request(self, request, client_address):
        if allowed_client(client_address[0]):
            return True
        log('%s  refused: not a private address' % client_address[0])
        return False


def make_server(bind, port, password, claude, workdir, timeout=600, idle=180, trace=None):
    cls = Server
    if ':' in bind:
        cls = type('Server6', (Server,), {'address_family': socket.AF_INET6})
    s = cls((bind, port), Handler)
    s.password, s.claude, s.workdir = password, claude, workdir
    s.timeout, s.idle, s.trace = timeout, idle, trace
    s.sessions = Sessions()
    s.turn_lock = threading.Lock()
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


def main(argv=None):
    ap = argparse.ArgumentParser(
        prog='claude_bridge.py',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        description='Veranda Claude (Commander X16) to your own Claude Code on this PC.',
        epilog='Start it on a PC where `claude` is signed in with your claude.ai plan:\n'
               '  python3 claude_bridge.py --password something-long\n'
               'In Veranda Claude: Settings, Server "Claude Code on my PC", this PC\'s IP\n'
               'address and port (e.g. 192.168.1.20:8642), and the same password.\n'
               'Claude Code runs with every tool, MCP server and slash command off, in\n'
               'an empty folder: the X16 can only talk. The connection is plain HTTP:\n'
               'the password and the conversation cross your network unencrypted.')
    ap.add_argument('--port', type=int, default=DEFAULT_PORT, help='the TCP port (default %(default)s)')
    ap.add_argument('--bind', default='0.0.0.0', help='the address to listen on (default %(default)s: every one)')
    ap.add_argument('--password', default=os.environ.get('CLAUDE_BRIDGE_PASSWORD'),
                    help='the password the X16 sends (default: $CLAUDE_BRIDGE_PASSWORD, else one is made up)')
    ap.add_argument('--claude', default='claude', help='the Claude Code program (default: claude on the PATH)')
    ap.add_argument('--workdir', default=os.path.join(os.path.expanduser('~'), '.cache', 'veranda-claude-bridge', 'work'),
                    help='the empty folder Claude Code runs in (default %(default)s)')
    ap.add_argument('--timeout', type=int, default=600, help='seconds a turn may take (default %(default)s)')
    ap.add_argument('--idle', type=int, default=180, help='seconds Claude Code may be silent (default %(default)s)')
    ap.add_argument('--trace', metavar='FILE', help='append Claude Code\'s stream-json lines to FILE (for debugging)')
    a = ap.parse_args(argv)
    made = not a.password
    password = a.password or secrets.token_urlsafe(9)
    os.makedirs(a.workdir, mode=0o700, exist_ok=True)
    try:
        s = make_server(a.bind, a.port, password, a.claude, a.workdir, a.timeout, a.idle, a.trace)
    except OSError as e:
        sys.exit('claude_bridge.py: cannot listen on %s:%d: %s' % (a.bind, a.port, e))
    port = s.server_address[1]
    log('Veranda Claude bridge on %s port %d; Claude Code: %s; its folder: %s'
        % (a.bind, port, a.claude, a.workdir))
    for ip in local_ips():
        log('  in Veranda Claude\'s Settings: Claude Code on my PC, address %s:%d' % (ip, port))
    if made:
        print('The password (type it in Settings): %s' % password, flush=True)
    if os.environ.get('ANTHROPIC_API_KEY') or os.environ.get('ANTHROPIC_AUTH_TOKEN'):
        log('  (ANTHROPIC_API_KEY is set here: it is left out of Claude Code\'s environment, so your plan is used)')
    if os.environ.get('CLAUDE_BRIDGE_READY'):
        with open(os.environ['CLAUDE_BRIDGE_READY'], 'w') as f:
            f.write('%d\n' % port)
    try:
        s.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        s.server_close()


if __name__ == '__main__':
    main()
