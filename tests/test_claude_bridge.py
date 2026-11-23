#!/usr/bin/env python3
# Gate claude_bridge (DECISIONS V115): tools/claude_bridge.py on its own, on the host.
# Copyright (c) 2026 Marcin Spoczynski. MIT licence (see LICENSE).
"""test_claude_bridge.py: the bridge with tests/fake_claude.py (never the
real Claude Code): the private-address filter, the password, the session
map, the no-tools flags on every run, the API's SSE out, the errors, busy,
a client that hangs up (Claude Code killed). Run under python3 -I.

usage: test_claude_bridge.py <scratch folder>
"""
import importlib.util
import json
import os
import socket
import sys
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location('claude_bridge', os.path.join(HERE, '..', 'tools', 'claude_bridge.py'))
B = importlib.util.module_from_spec(spec)
spec.loader.exec_module(B)

D = os.path.abspath(sys.argv[1])
os.makedirs(D, exist_ok=True)
FLOG = os.path.join(D, 'fake.jsonl')
for x in (FLOG, FLOG + '.sessions', FLOG + '.slowpid', FLOG + '.slowend'):
    if os.path.exists(x):
        os.remove(x)
os.environ['FAKE_CLAUDE_LOG'] = FLOG
os.environ['ANTHROPIC_API_KEY'] = 'sk-test-must-not-reach-the-child'
FAKE = os.path.join(HERE, 'fake_claude.py')
PW = 'gate-bridge-pass'
fails = 0


def check(c, msg):
    global fails
    if c:
        print('ok    ' + msg)
    else:
        fails += 1
        print('FAIL  ' + msg)


# ------------------------------------------------------------------ the address filter
good = ['127.0.0.1', '127.9.9.9', '10.1.2.3', '172.16.0.1', '172.31.255.254', '192.168.1.20', '::1',
        'fd12:3456::1', 'fe80::1%eth0', '::ffff:192.168.1.5']
bad = ['8.8.8.8', '172.32.0.1', '172.15.255.255', '192.169.0.1', '100.64.0.1', '2001:db8::1',
       '::ffff:8.8.8.8', '11.0.0.1', '', 'nonsense', '0.0.0.0']
check(all(B.allowed_client(a) for a in good) and not any(B.allowed_client(a) for a in bad),
      'the address filter: loopback, 10/8, 172.16/12, 192.168/16, IPv6 loopback, ULA, link-local only (%d allowed, %d refused)'
      % (len(good), len(bad)))
check(B.password_ok(PW, PW) and not B.password_ok('x', PW) and not B.password_ok(None, PW)
      and not B.password_ok('', PW), 'the password: compared in constant time; missing or wrong refused')

# ------------------------------------------------------------------ the session map
S = B.Sessions(size=3)
c1 = [('user', 'Hi there'), ('assistant', 'Hello “friend” — café \U0001F600 ok')]
S.add(c1, 'sid-1')
check(S.find([('user', 'Hi  there'), ('assistant', 'Hello "friend" - caf\x82 ? ok')]) == 'sid-1',
      'the session map: the turns so far found again, the reply as the X16 sends it back (folded)')
check(S.find([('user', 'Hi there'), ('assistant', 'Something else entirely, not this reply')]) is None,
      'the session map: another reply to the same user turns: no session (a new one)')
check(S.find([('user', 'Hi')]) is None and S.find([]) is None, 'the session map: other turns, no turns: none')
S.drop('sid-1')
check(S.find(c1) is None, 'the session map: a session that ran a turn drops its old entries')
for i in range(5):
    S.add([('user', 'q%d' % i), ('assistant', 'a%d' % i)], 'sid-q%d' % i)
check(len(S.map) == 3 and S.find([('user', 'q0'), ('assistant', 'a0')]) is None
      and S.find([('user', 'q4'), ('assistant', 'a4')]) == 'sid-q4', 'the session map: at most its size (the oldest go)')
S2 = B.Sessions(max_age=0)
S2.add(c1, 'sid-old')
time.sleep(0.01)
check(S2.find(c1) is None, 'the session map: old entries expire')
check(B.transcript([('user', 'new')]) == 'new' and 'User:\nfirst' in B.transcript(
    [('user', 'first'), ('assistant', 'reply'), ('user', 'second')]), 'a new session\'s prompt: the earlier turns as a transcript')
check(B.guard_slash('/help me') == ' /help me' and B.guard_slash('help') == 'help', 'a prompt never starts with /')
check(B.classify("You've hit your session limit · resets 3:45pm") == ('rate_limit_error', 'usage limit reached, resets 3:45pm')
      and B.classify('Not logged in · Please run /login')[0] == 'authentication_error',
      'Claude Code\'s errors in a few words: %r' % (B.classify("You've hit your weekly limit · resets Mon 12:00am"),))

# ------------------------------------------------------------------ the server, with the fake
srv = B.make_server('127.0.0.1', 0, PW, FAKE, os.path.join(D, 'work'), timeout=30, idle=10)
os.makedirs(srv.workdir, exist_ok=True)
PORT = srv.server_address[1]
threading.Thread(target=srv.serve_forever, daemon=True).start()


def req(body, key=PW, path='/v1/messages', hang_after=None):
    """(status, events [(name, data)], raw)"""
    b = json.dumps(body).encode()
    s = socket.create_connection(('127.0.0.1', PORT))
    h = 'POST %s HTTP/1.1\r\nHost: 127.0.0.1:%d\r\nContent-Type: application/json\r\n' % (path, PORT)
    if key is not None:
        h += 'x-api-key: %s\r\n' % key
    h += 'Content-Length: %d\r\nConnection: close\r\n\r\n' % len(b)
    s.sendall(h.encode() + b)
    raw = b''
    while True:
        if hang_after and hang_after in raw:
            s.close()
            return None, [], raw
        try:
            k = s.recv(4096)
        except OSError:
            break
        if not k:
            break
        raw += k
    s.close()
    head, _, rest = raw.partition(b'\r\n\r\n')
    status = int(head.split()[1])
    if b'chunked' in head.lower():
        data = b''
        while rest:
            n, _, rest = rest.partition(b'\r\n')
            n = int(n, 16)
            if not n:
                break
            data += rest[:n]
            rest = rest[n + 2:]
    else:
        data = rest
    evs = []
    for block in data.decode('utf-8').split('\n\n'):
        e = dict(l.split(': ', 1) for l in block.split('\n') if ': ' in l)
        if 'event' in e:
            evs.append((e['event'], json.loads(e['data'])))
    if not evs and data:
        evs.append(('body', json.loads(data)))
    return status, evs, raw


def runs():
    return [json.loads(l) for l in open(FLOG)] if os.path.exists(FLOG) else []


def body(*turns, model='claude-opus-5-5'):
    msgs = [{'role': 'user' if i % 2 == 0 else 'assistant', 'content': t} for i, t in enumerate(turns)]
    return {'model': model, 'max_tokens': 4096, 'stream': True, 'system': 'Plain ASCII please.', 'messages': msgs}


def text(evs):
    return ''.join(d['delta']['text'] for e, d in evs if e == 'content_block_delta')


st, evs, _ = req(body('hello'), key='wrong')
check(st == 401 and evs[0][1]['error']['type'] == 'authentication_error' and not runs(),
      'a wrong password: 401, authentication_error (the X16\'s "check the key" box); Claude Code not run')
st, evs, _ = req(body('hello'), key=None)
check(st == 401 and not runs(), 'no password: 401')
st, evs, _ = req(body('hello'), path='/v1/other')
check(st == 404 and not runs(), 'another path: 404')
st, evs, _ = req({'model': 'claude-opus-5-5', 'messages': [{'role': 'assistant', 'content': 'x'}]})
check(st == 400 and not runs(), 'a conversation that does not end with the user\'s turn: 400')

st, evs, _ = req(body('hello bridge'))
r = runs()
names = [e for e, _ in evs]
t1 = text(evs)
check(st == 200 and names[0] == 'message_start' and 'content_block_start' in names and names[-1] == 'message_stop'
      and 'message_delta' in names and 'turn 1 of session' in t1,
      'a turn: 200, message_start, content_block_start, text_delta ..., content_block_stop, message_delta, message_stop')
md = [d for e, d in evs if e == 'message_delta'][0]
check(md['delta']['stop_reason'] == 'end_turn' and md['usage']['output_tokens'] == 40
      and md['usage'].get('cache_read_input_tokens') == 15000, 'message_delta: stop_reason, usage from the result')
a = r[0]['argv']
i = a.index('--tools')
check(a[:5] == ['-p', '--output-format', 'stream-json', '--verbose', '--include-partial-messages']
      and a[i + 1] == '' and a[a.index('--disallowedTools') + 1] == '*'
      and '--strict-mcp-config' in a and json.loads(a[a.index('--mcp-config') + 1]) == {'mcpServers': {}}
      and a[a.index('--permission-mode') + 1] == 'dontAsk' and a[a.index('--permission-prompts') + 1] == 'none'
      and '--disable-slash-commands' in a and '--safe-mode' in a and a[a.index('--setting-sources') + 1] == 'user'
      and '--dangerously-skip-permissions' not in a and '--allowedTools' not in a and '--add-dir' not in a,
      'Claude Code run with no tools (--tools "", --disallowedTools "*"), no MCP (--strict-mcp-config, an empty '
      '--mcp-config), --permission-mode dontAsk, --permission-prompts none, no slash commands, --safe-mode, '
      '--setting-sources user')
check(a[a.index('--model') + 1] == 'claude-opus-5-5' and a[a.index('--append-system-prompt') + 1] == 'Plain ASCII please.'
      and '--session-id' in a and '--resume' not in a and r[0]['stdin'] == 'hello bridge'
      and r[0]['cwd'] == srv.workdir and not r[0]['api_key_env'],
      'the model and the system prompt from the request; a new session (--session-id); the prompt on stdin; '
      'in the empty work folder; ANTHROPIC_API_KEY left out of its environment')
sid = a[a.index('--session-id') + 1]

folded = t1.replace('—', '-').replace('“', '"').replace('”', '"').replace('\U0001F600', '?')
st, evs, _ = req(body('hello bridge', folded, 'second turn'))
r = runs()
a = r[-1]['argv']
check(st == 200 and '--resume' in a and a[a.index('--resume') + 1] == sid and r[-1]['stdin'] == 'second turn'
      and 'turn 2 of session' in text(evs) and '--tools' in a and a[a.index('--tools') + 1] == '',
      'the second turn: --resume <the session> (the reply sent back folded still matches), only the new '
      'message sent; the no-tools flags again')
t2 = text(evs)
st, evs, _ = req(body('second turn', 'whatever', 'third'))
a = runs()[-1]['argv']
check('--session-id' in a and 'User:\nsecond turn' in runs()[-1]['stdin'],
      'the X16 dropped the oldest turns: a new session, the turns so far as a transcript')
st, evs, _ = req(body('/help', model='claude-haiku-5-5'))
r = runs()[-1]
check(r['stdin'] == ' /help' and r['argv'][r['argv'].index('--model') + 1] == 'claude-haiku-5-5',
      'a message starting with / is not a command; Haiku\'s model id passed')

st, evs, _ = req(body('usage limit please'))
e = [d for n, d in evs if n == 'error']
check(st == 200 and e and e[0]['error']['type'] == 'rate_limit_error'
      and e[0]['error']['message'].startswith('usage limit reached (5-hour), resets ')
      and len(e[0]['error']['message']) <= 51 and not text(evs),
      'the plan\'s usage limit: an error event "%s"' % (e[0]['error']['message'] if e else None))
st, evs, _ = req(body('not signed in please'))
e = [d for n, d in evs if n == 'error']
check(e and e[0]['error']['type'] == 'authentication_error' and len(e[0]['error']['message']) <= 51,
      'not signed in: an error event "%s"' % (e[0]['error']['message'] if e else None))
st, evs, _ = req(body('fail please'))
e = [d for n, d in evs if n == 'error']
check(e and 'something went wrong' in e[0]['error']['message'], 'Claude Code fails (stderr only): its words in an error event')

srv2 = B.make_server('127.0.0.1', 0, PW, os.path.join(D, 'no-such-claude'), srv.workdir)
threading.Thread(target=srv2.serve_forever, daemon=True).start()
P1, PORT = PORT, srv2.server_address[1]
st, evs, _ = req(body('hello'))
check(st == 503 and 'claude not found' in evs[0][1]['error']['message'], 'no claude on the PC: 503, "%s"'
      % evs[0][1]['error']['message'])
PORT = P1

# busy: a slow turn, a second request meanwhile; then the slow one's client hangs up
out = {}
th = threading.Thread(target=lambda: out.update(r=req(body('slow please'), hang_after=b'slow 8.')))
th.start()
for _ in range(100):
    if os.path.exists(FLOG + '.slowpid'):
        break
    time.sleep(0.05)
time.sleep(0.3)
st, evs, _ = req(body('hello again'))
check(st == 529 and evs[0][1]['error']['type'] == 'overloaded_error', 'a second turn while one runs: 529, busy')
th.join(10)
pid = int(open(FLOG + '.slowpid').read())
for _ in range(60):
    try:
        os.kill(pid, 0)
        alive = os.path.exists('/proc/%d' % pid) and open('/proc/%d/stat' % pid).read().split()[2] != 'Z'
    except OSError:
        alive = False
    if not alive:
        break
    time.sleep(0.1)
check(not alive and not os.path.exists(FLOG + '.slowend'),
      'the X16 hangs up during a slow reply: Claude Code killed (pid %d gone, it never ended on its own)' % pid)
st, evs, _ = req(body('hello after'))
check(st == 200 and 'turn 1' in text(evs), 'the next turn runs (the lock released)')

srv.shutdown()
srv2.shutdown()
print('test_claude_bridge: %s' % ('PASS' if not fails else 'FAIL (%d)' % fails))
sys.exit(1 if fails else 0)
