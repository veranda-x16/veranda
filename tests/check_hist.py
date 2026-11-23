#!/usr/bin/env python3
"""Gates claude and ask (DECISIONS V123): the chats checked (tests/
code_steps.h's hist_steps): run 1 (log1.txt, srv1) two turns, the chat
file written; run 2 (log.txt, srv2) the program started again: the Chats
page, a newer and a damaged chat refused, the first opened, a third turn
(its request has the history), Rename, Delete.

usage: check_hist.py claude|ask <run folder>
"""
import json
import os
import re
import sys

APP, R = sys.argv[1], sys.argv[2]
ASK = APP == 'ask'
NAME = 'Ask' if ASK else 'Claude'
D = os.path.join(R, 'DOCUMENTS', 'Chats', NAME)
MODEL = 'gpt-6.2-sol' if ASK else 'claude-opus-5-5'


def need(c, msg):
    if not c:
        sys.exit('FAIL  ' + msg)


def ok(msg):
    print('ok    ' + msg)


def log(name):
    return open(os.path.join(R, name), encoding='utf-8', errors='replace').read().split('\n')


def reqs(srv):
    r = [json.loads(l) for l in open(os.path.join(R, srv, 'requests.jsonl'))]
    if ASK:
        r = [x for x in r if x.get('path') == '/v1/responses']
    return r


def msgs(r):
    b = r['body']
    return b['input'] if ASK else b['messages']


def parse(path):
    """a chat file (format 1): its header (a dict) and messages [(kind, bytes)]"""
    d = open(path, 'rb').read()
    lines = d.split(b'\r\n')
    need(lines[0] == b'VERANDA CHAT 2', '%s: the magic %r' % (path, lines[0]))
    hdr, i = {}, 1
    while lines[i]:
        k, _, v = lines[i].partition(b'=')
        hdr[k.decode()] = v.decode('cp437')
        i += 1
    p = len(b'\r\n'.join(lines[:i + 1])) + 2
    out = []
    while True:
        e = d.index(b'\r\n', p)
        head = d[p:e].decode()
        if head == 'end':
            need(e + 2 == len(d), '%s: bytes after the end' % path)
            break
        k, n = head.split(' ')
        n = int(n)
        out.append((k, d[e + 2:e + 2 + n]))
        need(d[e + 2 + n:e + 4 + n] == b'\r\n', '%s: a message\'s end' % path)
        p = e + 4 + n
    return hdr, out, d


l1, l2 = log('log1.txt'), log('log.txt')
for lg in (l1, l2):
    need('CL END' in lg and not any('CL TEST STUCK' in x or 'CL TEST FAILED' in x for x in lg), 'a run did not end')

# run 1: the file after two turns
f1 = os.path.join(R, 'chat1.chat')
hdr, m, raw = parse(f1)
need(hdr.get('app') == NAME and hdr.get('title') == 'plain one' and hdr.get('model') == MODEL
     and re.match(r'20\d\d-\d\d-\d\d \d\d:\d\d$', hdr.get('created', '')) and 'updated' in hdr, 'the header: %s' % hdr)
um = [(k, t.decode()) for k, t in m if k in 'ua']
want = [('u', 'plain one'), ('a', 'OK, from %s.' % MODEL), ('u', 'plain two'), ('a', 'OK, from %s.' % MODEL)]
need(um == want, 'the messages: %s' % um)
need(m[0][0] == 'n', 'the welcome note first')
need(b'sk-' not in raw and b'key' not in raw.lower(), 'a key in the chat file')
need(sum(1 for x in l1 if 'CL CHAT SAVED 0001 plain one.chat' in x) >= 2, 'saved after each turn')
ok('two turns: /DOCUMENTS/Chats/%s/0001 plain one.chat written after each (CHAT.TMP, renamed): "VERANDA CHAT 2", '
   'app, title ("plain one"), model, created and updated (the clock), an empty line, each message (kind, length, '
   'its text), "end"; no key in it (%d bytes)' % (NAME, len(raw)))

# run 2: the program started again
need('CL CHAT REFUSED NEWER' in ''.join(l2) and 'CL CHAT REFUSED DAMAGED' in ''.join(l2), 'the refusals')
need(any('CL BOX This chat cannot be opened:|it is from a newer version' in x for x in l2)
     and any('CL BOX This chat cannot be opened:|it is damaged' in x for x in l2), 'the boxes')
need(any('CL CHATS 3 future' in x for x in l2), 'the list: %s' % [x for x in l2 if x.startswith('CL CHATS')])
i = next(k for k, x in enumerate(l2) if 'CL CHAT OPENED' in x)
after = [x for x in l2[i:] if x.startswith('CL MSG ')][:5]
need(after[1:] == ['CL MSG u 9 plain one', 'CL MSG a %d OK, from %s.' % (10 + len(MODEL), MODEL),
                   'CL MSG u 9 plain two', 'CL MSG a %d OK, from %s.' % (10 + len(MODEL), MODEL)], 'opened: %s' % after)
R2 = reqs('srv2')
need(len(R2) == 1 and [(x['role'], x['content']) for x in msgs(R2[0])] ==
     [('user', 'plain one'), ('assistant', 'OK, from %s.' % MODEL), ('user', 'plain two'),
      ('assistant', 'OK, from %s.' % MODEL), ('user', 'plain three')], 'the third turn: %s' % (R2 and msgs(R2[0])))
ok('the program started again: File > Chats... lists them, the newest first (chats.png); a chat of a newer version '
   '("VERANDA CHAT 3") and a damaged one refused with a box, the conversation kept; the first opened: the same '
   'messages; a third turn sends the history from the file')

names = sorted(os.listdir(D))
need(names == ['0001 renamed chat.chat', '0006 future.chat'], 'the folder at the end: %s' % names)
hdr, m, raw = parse(os.path.join(D, '0001 renamed chat.chat'))
need([t.decode() for k, t in m if k == 'u'] == ['plain one', 'plain two', 'plain three'] and hdr['title'] == 'renamed chat',
     'the chat renamed: %s %s' % (hdr, m))
ok('Rename: "0001 renamed chat.chat" (its title too, kept by the next save), three turns in it; Delete (asked, '
   'Yes): the damaged one gone; no CHAT.TMP left')
