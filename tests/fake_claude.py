#!/usr/bin/env -S python3 -I -B
# Gate claude_bridge (DECISIONS V115): a fake Claude Code for tools/claude_bridge.py.
# Copyright (c) 2026 Marcin Spoczynski. MIT licence (see LICENSE).
"""fake_claude.py: plays `claude -p --output-format stream-json --verbose
--include-partial-messages` as Claude Code 2.1.312 prints it (its lines'
shapes as the one real smoke call showed them: a system init line with the
session id and empty tools, a system status line, stream_event lines
wrapping the API's events, the assistant message after the last text
delta, a rate_limit_event, a result line with usage; the error cases'
shapes are from Claude Code's documentation, not seen for real). It never calls anything.

Every run appends {argv, stdin, cwd, pid, env} (env: only whether
ANTHROPIC_API_KEY was there) to $FAKE_CLAUDE_LOG. The answer depends on
the prompt (stdin):
  "usage limit"    the plan's usage limit (an assistant error, is_error)
  "not signed in"  Claude Code not logged in
  "slow"           a delta every 0.25 s for 60 s (the client stops it;
                   $FAKE_CLAUDE_LOG.slowpid gets the pid, .slowend if it
                   ever ends on its own)
  "fail"           exits 1 with only stderr
  anything else    a short answer that says which turn of the session
                   this is (resumed sessions remember their turns in
                   $FAKE_CLAUDE_LOG.sessions)
"""
import json
import os
import sys
import time
import uuid

LOG = os.environ.get('FAKE_CLAUDE_LOG')
argv = sys.argv[1:]
prompt = sys.stdin.read()


def opt(name):
    return argv[argv.index(name) + 1] if name in argv else None


def out(m):
    sys.stdout.write(json.dumps(m, ensure_ascii=False) + '\n')
    sys.stdout.flush()


if LOG:
    with open(LOG, 'a') as f:
        f.write(json.dumps({'argv': argv, 'stdin': prompt, 'cwd': os.getcwd(), 'pid': os.getpid(),
                            'api_key_env': 'ANTHROPIC_API_KEY' in os.environ}) + '\n')

if '--version' in argv:
    print('2.1.312 (Claude Code)')
    sys.exit(0)

sid = opt('--resume') or opt('--session-id') or str(uuid.uuid4())
model = opt('--model') or 'claude-opus-5-5'
low = prompt.lower()

if 'fail please' in low:
    sys.stderr.write('Error: something went wrong on the PC\n')
    sys.exit(1)

# the session's turns (a resumed session goes on counting)
turns = {}
if LOG and os.path.exists(LOG + '.sessions'):
    turns = json.load(open(LOG + '.sessions'))
n = turns.get(sid, 0) + 1 if '--resume' in argv else 1
turns[sid] = n
if LOG:
    json.dump(turns, open(LOG + '.sessions', 'w'))

out({'type': 'system', 'subtype': 'init', 'cwd': os.getcwd(), 'session_id': sid, 'tools': [],
     'mcp_servers': [], 'model': model, 'permissionMode': 'dontAsk', 'slash_commands': [],
     'apiKeySource': 'none', 'claude_code_version': '2.1.312', 'output_style': 'default',
     'agents': [], 'skills': [], 'plugins': [], 'uuid': str(uuid.uuid4())})


out({'type': 'system', 'subtype': 'status', 'status': 'requesting', 'session_id': sid, 'uuid': str(uuid.uuid4())})


def rate_limit(status, resets):
    out({'type': 'rate_limit_event', 'rate_limit_info': {
        'status': status, 'resetsAt': resets, 'rateLimitType': 'five_hour', 'overageStatus': 'rejected',
        'overageDisabledReason': 'org_level_disabled', 'isUsingOverage': False,
        'unifiedWindows': {'five_hour': {'utilization': 1.0 if status == 'rejected' else 0.22, 'resetsAt': resets,
                                         'status': status}}},
        'uuid': str(uuid.uuid4()), 'session_id': sid})


def result(is_error, text, usage=None, subtype='success', dur=900, status=None):
    out({'type': 'result', 'subtype': subtype, 'is_error': is_error, 'duration_ms': dur,
         'duration_api_ms': dur - 100, 'num_turns': 1, 'result': text, 'stop_reason': None if is_error else 'end_turn',
         'api_error_status': status, 'terminal_reason': 'completed',
         'session_id': sid, 'total_cost_usd': 0 if is_error else 0.0021,
         'usage': usage or {'input_tokens': 0, 'output_tokens': 0},
         'modelUsage': {}, 'permission_denials': [], 'uuid': str(uuid.uuid4())})


def synthetic(text, err):
    out({'type': 'assistant', 'message': {'id': str(uuid.uuid4()), 'model': '<synthetic>', 'role': 'assistant',
                                          'stop_reason': 'stop_sequence', 'type': 'message',
                                          'content': [{'type': 'text', 'text': text}],
                                          'usage': {'input_tokens': 0, 'output_tokens': 0}},
         'parent_tool_use_id': None, 'session_id': sid, 'error': err, 'uuid': str(uuid.uuid4())})


if 'usage limit' in low:
    text = "You've hit your session limit · resets 3:45pm"
    rate_limit('rejected', int(time.time()) + 3600)
    synthetic(text, 'rate_limit')
    result(True, text, status=429)
    sys.exit(1)
if 'not signed in' in low:
    text = 'Not logged in · Please run /login'
    synthetic(text, 'authentication_failed')
    result(True, text, status=401)
    sys.exit(1)


def ev(e):
    out({'type': 'stream_event', 'event': e, 'session_id': sid, 'parent_tool_use_id': None,
         'uuid': str(uuid.uuid4()), 'api_message_id': 'msg_fake'})


ev({'type': 'message_start', 'message': {'model': model, 'id': 'msg_fake', 'type': 'message', 'role': 'assistant',
                                         'content': [], 'stop_reason': None, 'stop_sequence': None,
                                         'usage': {'input_tokens': 3, 'cache_creation_input_tokens': 0,
                                                   'cache_read_input_tokens': 15000, 'output_tokens': 1}}})
ev({'type': 'content_block_start', 'index': 0, 'content_block': {'type': 'text', 'text': ''}})
if 'slow' in low:
    if LOG:
        open(LOG + '.slowpid', 'w').write(str(os.getpid()))
    for i in range(240):
        ev({'type': 'content_block_delta', 'index': 0, 'delta': {'type': 'text_delta', 'text': 'slow %d. ' % i}})
        time.sleep(0.25)
    if LOG:
        open(LOG + '.slowend', 'w').write('ended')
    text = 'slow'
else:
    first = prompt.strip().splitlines()[-1][:40] if prompt.strip() else ''
    text = ('Hello from the fake Claude Code — turn %d of session %s. You said: “%s”. '
            'A café, an emoji \U0001F600 and a dash.' % (n, sid[:8], first))
    for i in range(0, len(text), 7):
        ev({'type': 'content_block_delta', 'index': 0, 'delta': {'type': 'text_delta', 'text': text[i:i + 7]}})
        time.sleep(0.02)
ev({'type': 'content_block_stop', 'index': 0})
out({'type': 'assistant', 'message': {'model': model, 'id': 'msg_fake', 'type': 'message', 'role': 'assistant',
                                      'content': [{'type': 'text', 'text': text}], 'stop_reason': None,
                                      'usage': {'input_tokens': 3, 'output_tokens': 1}},
     'parent_tool_use_id': None, 'session_id': sid, 'uuid': str(uuid.uuid4())})
ev({'type': 'message_delta', 'delta': {'stop_reason': 'end_turn', 'stop_sequence': None},
    'usage': {'input_tokens': 3, 'cache_creation_input_tokens': 0, 'cache_read_input_tokens': 15000,
              'output_tokens': 40}})
ev({'type': 'message_stop'})
rate_limit('allowed', int(time.time()) + 3 * 86400)
result(False, text, {'input_tokens': 3, 'cache_creation_input_tokens': 0, 'cache_read_input_tokens': 15000,
                     'output_tokens': 40})
