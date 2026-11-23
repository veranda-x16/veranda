#!/usr/bin/env python3
# Gate claude_bridge (DECISIONS V115): the bridge session checked.
# Copyright (c) 2026 Marcin Spoczynski. MIT licence (see LICENSE).
"""check_claude_bridge.py: Veranda Claude's bridge session (tools/
gate_claude_bridge.sh): the console's "CL ..." lines (tests/claude_play.c),
the fake Claude Code's record of its runs (tests/fake_claude.py), the
bridge's log, the modem's log, CLAUDE.CFG.

usage: check_claude_bridge.py <run folder> <bridge port> <closed port>
"""
import json
import os
import re
import sys

R, BPORT, CPORT = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
raw = open(os.path.join(R, 'log.txt'), encoding='utf-8', errors='replace').read()
log = raw.split('\n')
KEY = 'sk-ant-gate-0000-dummy-key-for-tests-WXYZ'
PW = 'gate-bridge-pass'


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

# the settings as they were at each step
conf = vals('CL TEST CONF ')
want = ['api 127.0.0.1:9 plain ' + KEY,
        'bridge 127.0.0.1:%d plain wrong-pass' % BPORT,
        'bridge 127.0.0.1:%d plain %s' % (BPORT, PW),
        'bridge 127.0.0.1:%d plain %s' % (CPORT, PW),
        'api 127.0.0.1:9 plain ' + KEY]
need(conf == want, 'the settings: %s\n  want %s' % (conf, want))
need(vals('CL SETTINGS SHOWN') or 'CL SETTINGS SHOWN' in log, 'no Settings page')
cfg = open(os.path.join(R, 'VERANDA', '.SYSTEM', 'CLAUDE.CFG'), 'rb').read()
wcfg = ('server=api\r\nkey=%s\r\nbridge=127.0.0.1:%d\r\nbpass=%s\r\nmodel=claude-opus-5-5\r\nhost=127.0.0.1\r\n'
        'port=9\r\ntls=0\r\nremember=all\r\nanswers=normal\r\noldcode=short\r\ncompact=asked\r\n' % (KEY, CPORT, PW)).encode()
need(cfg == wcfg, 'CLAUDE.CFG: %r\n  want %r' % (cfg, wcfg))
ok('Settings: Claude Code on my PC chosen with a click, the address typed, Tab, the password typed (a wrong one '
   'first, then Backspace x 10 and the right one), Return; C holds the bridge\'s host, port, plain TCP, the '
   'password; later the address of a closed port; then Anthropic API again with a click: the API\'s key and '
   'host back. CLAUDE.CFG keeps both: server=api, key=, bridge=, bpass=, model, host, port, tls')

# the boxes
boxes = vals('CL BOX ')
need(len(boxes) == 4, 'the boxes: %s' % boxes)
need(boxes[0] == 'The bridge password was not accepted (401).|Check the password in Settings.', 'the 401 box: %s' % boxes[0])
need(any(m.startswith('n ') and '(Bridge error 401, authentication_error: the bridge pass' in m for m in vals('CL MSG ')),
     'the 401 note: %s' % [m for m in vals('CL MSG ') if m.startswith('n ')])
need(re.fullmatch(r'Claude Code on the PC:\|usage limit reached \(5-hour\), resets \w{3} \d\d:\d\d', boxes[1]),
     'the usage limit box: %s' % boxes[1])
need(boxes[2] == 'Claude Code on the PC:|not signed in: run claude on the PC, then /login', 'the not signed in box: %s' % boxes[2])
need(boxes[3] == 'Could not connect to 127.0.0.1|Is claude_bridge.py running on the PC?', 'the refused box: %s' % boxes[3])
ins = vals('CL TEST INPUT ')
need(ins == ['hello bridge', 'usage limit please', 'not signed in please', 'anyone there'], 'the texts given back: %s' % ins)
for b in boxes:
    need(len(b.split('|')[1]) <= 51, 'a box line longer than the box: %s' % b)
ok('the boxes: "%s"; "%s"; "%s"; "%s"; each time the turn left out and its text back in the input box'
   % tuple(b.replace('|', ' ') for b in boxes))

# the fake Claude Code's runs
runs = [json.loads(l) for l in open(os.path.join(R, 'br', 'fake.jsonl'))]
need([r['stdin'].strip().splitlines()[-1] for r in runs] ==
     ['hello bridge', 'second turn please', 'usage limit please', 'not signed in please', 'slow please'],
     'the runs: %s' % [r['stdin'] for r in runs])
work = os.path.realpath(os.path.join(R, 'br', 'work'))
for r in runs:
    a = r['argv']
    need(a[:5] == ['-p', '--output-format', 'stream-json', '--verbose', '--include-partial-messages'], 'argv %s' % a)
    need(a[a.index('--tools') + 1] == '' and a[a.index('--disallowedTools') + 1] == '*', 'tools on: %s' % a)
    need('--strict-mcp-config' in a and json.loads(a[a.index('--mcp-config') + 1]) == {'mcpServers': {}}, 'MCP on: %s' % a)
    need(a[a.index('--permission-mode') + 1] == 'dontAsk' and a[a.index('--permission-prompts') + 1] == 'none'
         and '--disable-slash-commands' in a and '--safe-mode' in a and a[a.index('--setting-sources') + 1] == 'user',
         'the permissions: %s' % a)
    need(not any(x in a for x in ('--dangerously-skip-permissions', '--allowedTools', '--add-dir',
                                  '--allow-dangerously-skip-permissions')), 'a dangerous flag: %s' % a)
    need(a[a.index('--model') + 1] == 'claude-opus-5-5', 'the model: %s' % a)
    need('plain ASCII' in a[a.index('--append-system-prompt') + 1], 'the system prompt: %s' % a)
    need(os.path.realpath(r['cwd']) == work and not r['api_key_env'], 'the folder, the environment: %s' % r)
a0, a1, a2, a3 = (r['argv'] for r in runs[:4])
sid = a0[a0.index('--session-id') + 1]
need('--resume' not in a0 and runs[0]['stdin'] == 'hello bridge', 'the first turn: %s' % a0)
need(a1[a1.index('--resume') + 1] == sid and runs[1]['stdin'] == 'second turn please',
     'the second turn does not resume: %s %r' % (a1, runs[1]['stdin']))
need(a2[a2.index('--resume') + 1] == sid, 'the third turn does not resume: %s' % a2)
need('--session-id' in a3 and 'User:\nhello bridge' in runs[3]['stdin'],
     'after the error a new session, the turns so far as a transcript: %s %r' % (a3, runs[3]['stdin']))
ok('Claude Code run %d times, each with no tools (--tools "", --disallowedTools "*"), no MCP (--strict-mcp-config, '
   'an empty --mcp-config), --permission-mode dontAsk, --permission-prompts none, --disable-slash-commands, '
   '--safe-mode, --setting-sources user, --model claude-opus-5-5, Veranda Claude\'s system prompt appended, in the '
   'empty work folder, without ANTHROPIC_API_KEY; the first turn a new session, the second --resume %s... with only '
   'the new message, the third too; after the usage limit a new session with the turns so far' % (len(runs), sid[:8]))

# the conversation
msgs = vals('CL MSG ')
a_msgs = [m for m in msgs if m.startswith('a ')]
need(any('turn 1 of session %s' % sid[:8] in m for m in a_msgs) and any('turn 2 of session %s' % sid[:8] in m for m in a_msgs),
     'the replies: %s' % a_msgs)
need(any(m.startswith('a ') and 'slow 0. slow 1.' in m for m in msgs), 'the slow reply\'s part: %s' % msgs)
ok('two replies streamed through the bridge (the fake\'s text, Unicode folded); the slow one stopped with Esc, '
   'its part kept')

# the slow one killed
pid = int(open(os.path.join(R, 'br', 'fake.jsonl.slowpid')).read())
need(not os.path.exists('/proc/%d' % pid) or open('/proc/%d/stat' % pid).read().split()[2] == 'Z',
     'the slow Claude Code still runs (pid %d)' % pid)
need(not os.path.exists(os.path.join(R, 'br', 'fake.jsonl.slowend')), 'the slow Claude Code ended on its own')

# the bridge's log
blog = open(os.path.join(R, 'br', 'bridge.log')).read()
lines = [l for l in blog.split('\n') if ' prompt ' in l]
need(len(lines) == 6, 'the bridge\'s log: %s' % lines)
need('401' in lines[0] and 'new session' in lines[1] and 'resumed' in lines[2] and 'usage limit' in lines[3]
     and 'not signed in' in lines[4] and 'hung up' in lines[5] and 'Claude Code killed' in lines[5],
     'the bridge\'s log: %s' % lines)
need(PW not in blog and 'wrong-pass' not in blog, 'a password in the bridge\'s log')
ok('the bridge logged one line a request (the client, the model, the prompt\'s length, the outcome: 401, new '
   'session, resumed, the usage limit, not signed in, "stopped: the X16 hung up (Claude Code killed)"); no '
   'password in it')

# the modem: plain ATC to the bridge
mlog = open(os.path.join(R, 'modem.log'), encoding='latin-1').read().split('\n')
atc = [l.split(' ', 1)[1] for l in mlog if l.startswith('@') and ' ATC' in l and '"' in l]
want = ['ATC"127.0.0.1:%d"' % BPORT] * 6 + ['ATC"127.0.0.1:%d"' % CPORT]
need(atc == want, 'the connects: %s' % atc)
ok('each turn a plain connect (ATC, no TLS: net_tls off for the bridge): %s x 6, then %s' % (want[0], want[-1]))
