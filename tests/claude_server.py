#!/usr/bin/env python3
"""Gate claude (DECISIONS V114): a fake Anthropic Messages API on localhost,
in plain TCP (the emulator's modem connects ATCS as plain TCP), with
Python's socket module only. It never calls the real API.

usage: claude_server.py <folder>   writes <folder>/ready (the port, then a
                                   port nothing listens on) and
                                   <folder>/requests.jsonl: every request
                                   (its line, headers, body, what was
                                   wrong with it, what was sent back)

Each request is checked as the real API would take it (and as Veranda
Claude must send it): POST /v1/messages HTTP/1.1, Host, x-api-key (the
gate's dummy key), anthropic-version 2026-10-21, anthropic-beta
server-side-fallback-2026-07-01 (not for Haiku), content-type JSON, a
Content-Length equal to the body's; the body JSON with model, max_tokens,
stream true, fallbacks "default" (not for Haiku), output_config.effort
"low", a top-level cache_control, a system prompt, no temperature, top_p,
top_k or thinking; messages that start with a user turn and alternate,
the last a user turn, none empty. What is wrong goes into the log
("bad"), and the check fails on it.

The reply depends on the last user message (one connection a request,
Connection: close; SSE in chunked transfer, its chunks cut anywhere):
  hello     message_start, an empty thinking block (its signature), a
            ping, 1.5 s of thinking, then text with Unicode escapes,
            raw UTF-8, an emoji (a surrogate pair), bullets; a pause in
            the middle; end_turn
  long      about 6 KB of paragraphs in many small deltas
  max       text, then stop_reason max_tokens
  refuse    a little text, then stop_reason refusal (stop_details)
  overload  HTTP 529 with the API's error JSON (not chunked)
  midstream text, then an "error" event (overloaded_error), the close
  key       HTTP 401 (authentication_error)
  slow      a delta every 0.25 s for 15 s (the client stops it: its
            close is noted)
  aside     a delta every 0.2 s for 3 s (the client is put aside)
  big       about 14 KB of text (the client's store fills: old turns go)
  anything else: a short answer
"""
import json
import os
import random
import socket
import sys
import threading
import time

D = sys.argv[1]
KEY = 'sk-ant-gate-0000-dummy-key-for-tests-WXYZ'
LOCK = threading.Lock()
LOG = open(os.path.join(D, 'requests.jsonl'), 'w')
RND = random.Random(114)

HELLO_A = ('Hello! “Quoted” words — a dash, an ellipsis… café, naïve, '
           'an emoji \U0001F600 here. Polish: Zażółć gęślą jaźń.\n\nA list:\n• one\n• two\n\n')
HELLO_B = ('Raw UTF-8: łódź, ZAŻÓŁĆ GĘŚLĄ JAŹŃ, ‘single’, 5°C, ½, → next. '
           'A tab\there, a backslash \\ and "plain quotes".')
PARA = ('Once upon a time a small 8-bit computer named Commander X16 sat on a desk by a window. '
        'Every evening its owner typed to it, and every evening it answered as well as it could, '
        'one character at a time, through a little Wi-Fi modem that hummed quietly.')
LONG = '\n\n'.join('%d. %s' % (i + 1, PARA) for i in range(22))
BIG = '\n\n'.join('Block %02d: %s' % (i, PARA) for i in range(52))
# (V123) replies with fenced code blocks, a file's next version, a summary
BAS = '10 PRINT "HELLO FROM CLAUDE"\n20 FOR I=1 TO 3:PRINT I*I;:NEXT I\n30 PRINT\n40 PRINT "DONE"'
PY = 'for i in range(1, 4):\n    print(i * i, end=" ")\nprint("done")'
CODE = ('Here is a small program for the X16.\n\n```basic\n' + BAS + '\n```\n\nAnd the same in Python:\n\n'
        '```python\n' + PY + '\n```\n\nCopy or save either.')
FIXED = '5 PRINT "{93}"\n10 PRINT "GAME"\n20 X=5\n30 PRINT "SCORE";X*2\n40 END'
FIX = 'Here is GAME.PRG with line 30 fixed.\n\n```basic\n' + FIXED + '\n```\n\nSave it over the old one.'
SUMMARY = ('We wrote a BASIC program that prints squares, saved as PROGRAM.PRG, and fixed line 30 of GAME.PRG '
           '(PRINT "SCORE";X*2).')


def log(rec):
    with LOCK:
        LOG.write(json.dumps(rec) + '\n')
        LOG.flush()


def sse(ev, data, ascii=False):
    """an event; ascii: non-ASCII as \\uXXXX escapes (an emoji as a surrogate pair), else raw UTF-8"""
    return ('event: %s\ndata: %s\n\n' % (ev, json.dumps(data, ensure_ascii=ascii))).encode('utf-8')



class Conn:
    def __init__(self, c):
        self.c = c
        self.closed = False

    def raw(self, b):
        try:
            self.c.sendall(b)
        except OSError:
            self.closed = True

    def chunk(self, b):
        """b sent as chunks of random sizes (the SSE lines cut anywhere)"""
        while b and not self.closed:
            n = RND.randint(1, 90)
            p, b = b[:n], b[n:]
            self.raw(b'%x\r\n' % len(p) + p + b'\r\n')

    def head(self, status, reason, ctype, chunked=True, length=None):
        h = 'HTTP/1.1 %d %s\r\nContent-Type: %s\r\nrequest-id: req_gate\r\n' % (status, reason, ctype)
        h += 'Transfer-Encoding: chunked\r\n' if chunked else 'Content-Length: %d\r\n' % length
        h += 'Connection: close\r\n\r\n'
        self.raw(h.encode())

    def end(self):
        self.raw(b'0\r\n\r\n')


def start_msg(model):
    return {'type': 'message_start', 'message': {
        'id': 'msg_gate', 'type': 'message', 'role': 'assistant', 'model': model, 'content': [],
        'stop_reason': None, 'stop_sequence': None,
        'usage': {'input_tokens': 1200, 'cache_creation_input_tokens': 250, 'cache_read_input_tokens': 34,
                  'output_tokens': 1}}}


def deltas(c, text, size=12, pause=0.0, index=1, ascii=False):
    i = 0
    while i < len(text) and not c.closed:
        n = RND.randint(1, size)
        c.chunk(sse('content_block_delta', {'type': 'content_block_delta', 'index': index,
                                            'delta': {'type': 'text_delta', 'text': text[i:i + n]}}, ascii))
        i += n
        if pause:
            time.sleep(pause)


def stream(c, model, parts, stop='end_turn', out_tokens=42, error=None, extra=None):
    """parts: [(text, delta size, pause after each delta, pause after the part)]; the first part's non-ASCII as \\u escapes"""
    c.head(200, 'OK', 'text/event-stream; charset=utf-8')
    c.chunk(sse('message_start', start_msg(model)))
    c.chunk(sse('content_block_start', {'type': 'content_block_start', 'index': 0,
                                        'content_block': {'type': 'thinking', 'thinking': '', 'signature': ''}}))
    c.chunk(sse('content_block_delta', {'type': 'content_block_delta', 'index': 0,
                                        'delta': {'type': 'thinking_delta', 'thinking': ''}}))
    c.chunk(sse('content_block_delta', {'type': 'content_block_delta', 'index': 0,
                                        'delta': {'type': 'signature_delta', 'signature': 'EqQBCgIYAhIM' * 8}}))
    c.chunk(sse('content_block_stop', {'type': 'content_block_stop', 'index': 0}))
    c.chunk(sse('ping', {'type': 'ping'}))
    c.chunk(sse('content_block_start', {'type': 'content_block_start', 'index': 1,
                                        'content_block': {'type': 'text', 'text': ''}}))
    for k, (text, size, pd, pa) in enumerate(parts):
        deltas(c, text, size, pd, ascii=k < 2)
        time.sleep(pa)
    if error:
        c.chunk(sse('error', {'type': 'error', 'error': error}))
        c.end()
        return
    c.chunk(sse('content_block_stop', {'type': 'content_block_stop', 'index': 1}))
    md = {'type': 'message_delta', 'delta': {'stop_reason': stop, 'stop_sequence': None},
          'usage': {'output_tokens': out_tokens}}
    if extra:
        md.update(extra)
    c.chunk(sse('message_delta', md))
    c.chunk(sse('message_stop', {'type': 'message_stop'}))
    c.end()


def error_reply(c, status, reason, etype, emsg):
    body = json.dumps({'type': 'error', 'error': {'type': etype, 'message': emsg},
                       'request_id': 'req_gate'}).encode()
    c.head(status, reason, 'application/json', chunked=False, length=len(body))
    c.raw(body)


def check(line, hdr, body, raw_len):
    bad = []
    if line != 'POST /v1/messages HTTP/1.1':
        bad.append('request line %r' % line)
    if hdr.get('x-api-key') != KEY:
        bad.append('x-api-key %r' % hdr.get('x-api-key'))
    if hdr.get('anthropic-version') != '2026-10-21':
        bad.append('anthropic-version %r' % hdr.get('anthropic-version'))
    if hdr.get('content-type') != 'application/json':
        bad.append('content-type %r' % hdr.get('content-type'))
    if 'host' not in hdr:
        bad.append('no Host')
    if int(hdr.get('content-length', '-1')) != raw_len:
        bad.append('content-length %r, body %d' % (hdr.get('content-length'), raw_len))
    if body is None:
        bad.append('the body is not JSON')
        return bad
    haiku = body.get('model') == 'claude-haiku-5-5'
    if body.get('model') not in ('claude-opus-5-5', 'claude-sonnet-5-5', 'claude-haiku-5-5'):
        bad.append('model %r' % body.get('model'))
    if haiku:
        if 'fallbacks' in body or 'anthropic-beta' in hdr:
            bad.append('fallbacks for Haiku')
    else:
        if body.get('fallbacks') != 'default':
            bad.append('fallbacks %r' % body.get('fallbacks'))
        if hdr.get('anthropic-beta') != 'server-side-fallback-2026-07-01':
            bad.append('anthropic-beta %r' % hdr.get('anthropic-beta'))
    if body.get('stream') is not True:
        bad.append('stream %r' % body.get('stream'))
    if not isinstance(body.get('max_tokens'), int) or not 1 <= body['max_tokens'] <= 128000:
        bad.append('max_tokens %r' % body.get('max_tokens'))
    if body.get('output_config') != {'effort': 'low'}:
        bad.append('output_config %r' % body.get('output_config'))
    if body.get('cache_control') != {'type': 'ephemeral'}:
        bad.append('cache_control %r' % body.get('cache_control'))
    if not isinstance(body.get('system'), str) or 'plain ASCII' not in body['system']:
        bad.append('system %r' % body.get('system'))
    for k in ('temperature', 'top_p', 'top_k', 'thinking'):
        if k in body:
            bad.append('%s sent' % k)
    msgs = body.get('messages')
    if not isinstance(msgs, list) or not msgs:
        bad.append('no messages')
        return bad
    for i, m in enumerate(msgs):
        if m.get('role') != ('user' if i % 2 == 0 else 'assistant'):
            bad.append('messages[%d].role %r' % (i, m.get('role')))
        if not isinstance(m.get('content'), str) or not m['content']:
            bad.append('messages[%d].content %r' % (i, m.get('content')))
        if set(m) != {'role', 'content'}:
            bad.append('messages[%d] keys %r' % (i, sorted(m)))
    if msgs[-1].get('role') != 'user':
        bad.append('the last message is not the user\'s')
    return bad


def serve(c):
    conn = Conn(c)
    buf = b''
    c.settimeout(60)
    try:
        while b'\r\n\r\n' not in buf:
            d = c.recv(4096)
            if not d:
                return
            buf += d
        head, rest = buf.split(b'\r\n\r\n', 1)
        lines = head.decode('latin-1').split('\r\n')
        hdr = {}
        for l in lines[1:]:
            k, _, v = l.partition(':')
            hdr[k.strip().lower()] = v.strip()
        n = int(hdr.get('content-length', '0'))
        while len(rest) < n:
            d = c.recv(4096)
            if not d:
                break
            rest += d
        raw = rest[:n]
        try:
            body = json.loads(raw.decode('utf-8'))
        except ValueError:
            body = None
        bad = check(lines[0], hdr, body, len(rest))
        last = body['messages'][-1]['content'] if body and body.get('messages') else ''
        model = body.get('model', '?') if body else '?'
        rec = {'line': lines[0], 'headers': hdr, 'body': body, 'bad': bad, 'raw_len': len(raw),
               'raw': raw.decode('utf-8', 'replace')}
        word = last.split()[0].lower().strip(',!?.') if last.split() else ''
        if last.startswith('Hello') or last.startswith('Caf'):     # (V143: the Polish first turn)
            word = 'hello'
        elif last.startswith('Summarise our conversation'):
            word = 'summarise'
        elif 'long story' in last:
            word = 'long'
        rec['kind'] = word
        if word == 'hello':
            rec['reply'] = HELLO_A + HELLO_B
            stream(conn, model, [('', 1, 0, 1.5), (HELLO_A, 6, 0.02, 2.0), (HELLO_B, 8, 0.02, 0)])
        elif word == 'long':
            rec['reply'] = LONG
            stream(conn, model, [(LONG, 30, 0, 0)], out_tokens=1500)
        elif word == 'max':
            rec['reply'] = 'This answer goes on and on, until the limit cuts it'
            stream(conn, model, [(rec['reply'], 10, 0, 0)], stop='max_tokens', out_tokens=4096)
        elif word == 'refuse':
            rec['reply'] = 'I can start on that, but'
            stream(conn, model, [(rec['reply'], 5, 0, 0)], stop='refusal',
                   extra={'stop_details': {'type': 'refusal', 'category': None, 'explanation': None}})
        elif word == 'overload':
            error_reply(conn, 529, 'Overloaded', 'overloaded_error', 'Overloaded')
        elif word == 'midstream':
            rec['reply'] = 'Here is the start of an answer that'
            stream(conn, model, [(rec['reply'], 6, 0, 0.2)],
                   error={'type': 'overloaded_error', 'message': 'Overloaded'})
        elif word == 'key':
            error_reply(conn, 401, 'Unauthorized', 'authentication_error', 'invalid x-api-key')
        elif word == 'slow':
            rec['reply'] = ' '.join('word%02d' % i for i in range(60))
            stream(conn, model, [(rec['reply'], 7, 0.25, 0)])
        elif word == 'aside':
            rec['reply'] = ' '.join('aside%02d' % i for i in range(15))
            stream(conn, model, [(rec['reply'], 8, 0.2, 0)])
        elif word == 'code':
            rec['reply'] = CODE
            stream(conn, model, [(CODE, 9, 0, 0)])
        elif word == 'fix':
            rec['reply'] = FIX
            stream(conn, model, [(FIX, 9, 0, 0)])
        elif word == 'summarise':
            rec['reply'] = SUMMARY
            stream(conn, model, [(SUMMARY, 9, 0, 0)])
        elif word == 'big':
            rec['reply'] = BIG
            stream(conn, model, [(BIG, 60, 0, 0)], out_tokens=3500)
        else:
            rec['reply'] = 'OK, from %s.' % model
            stream(conn, model, [(rec['reply'], 5, 0, 0)])
        rec['client_closed'] = conn.closed
        time.sleep(0.2)
        log(rec)
    except OSError as e:
        log({'error': str(e)})
    finally:
        try:
            c.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass
        c.close()


def main():
    s = socket.socket()
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(('127.0.0.1', 0))
    s.listen(4)
    t = socket.socket()
    t.bind(('127.0.0.1', 0))
    closed = t.getsockname()[1]
    t.close()
    with open(os.path.join(D, 'ready.tmp'), 'w') as f:
        f.write('%d %d\n' % (s.getsockname()[1], closed))
    os.rename(os.path.join(D, 'ready.tmp'), os.path.join(D, 'ready'))
    while True:
        c, _ = s.accept()
        threading.Thread(target=serve, args=(c,), daemon=True).start()


main()
