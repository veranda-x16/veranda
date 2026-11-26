#!/usr/bin/env python3
"""Gate update (DECISIONS V130): GitHub played on localhost, for Veranda
Update's test build. No real server is contacted.

    update_fake.py <dir>

<dir>/fake.json says what to serve:
    {"repo": "owner/repo", "release": "<a folder from mkrelease.py>",
     "missing": [asset, ...],   GitHub answers 404 for these
     "corrupt": [asset, ...],   one byte changed (the CRC must refuse it)
     "drop": [asset, ...],      the connection closed half way, once each
     "latest": true,            (false: no release, 404 for UPDATE.LST)
     "repos": {"owner/repo": "<folder>", ...}}
                                (V198) more repositories, each with one
                                release (its tag its list's: UPDATE.LST's
                                or DICT.LST's, Veranda Write's
                                dictionaries); missing, corrupt and drop
                                name their assets too

The release is served as GitHub serves a published one (V140): its tag
is the one its UPDATE.LST names (mkrelease.py's --tag v<version>, the
release workflow's; "test" for the Test channel's pre-release), and only
that tag has its assets; a pre-release (the tag "test") is never the
latest, so releases/latest/download/... is 404 for it.

Two listeners (written to <dir>/ready as "<github port> <assets port>"):
  github    127.0.0.1, GitHub's stand-in: /<repo>/releases/latest/download/
            <name> answers 302 to /<repo>/releases/download/<tag>/<name>
            on github.com (here: this listener, an absolute https://
            address, as GitHub's), and that one 302 with a Location on
            the other host (https://localhost:<assets
            port>/github-production-release-asset-2e65be/...?X-Amz-...),
            about 950 bytes long as GitHub's signed addresses are, and a
            short body of their own; anything else 404 (another tag too)
  assets    the bodies: with Content-Length for even requests, chunked
            (chunks of 700 bytes and less, one with an extension, then a
            trailer) for odd ones
Each request is checked (GET, HTTP/1.1, Host, User-Agent VerandaUpdate,
Accept-Encoding: identity, Connection: close) and logged to
<dir>/requests.log as JSON lines (host, path's start, the length of the
whole request line, how the body went).

MIT licence (see LICENSE)."""
import hashlib
import json
import os
import re
import socket
import sys
import threading

D = sys.argv[1]
CFG = json.load(open(os.path.join(D, 'fake.json')))
LOCK = threading.Lock()
DROPPED = set()
COUNT = [0]
TOKENS = {}


def log(**k):
    with LOCK:
        with open(os.path.join(D, 'requests.log'), 'a') as f:
            f.write(json.dumps(k) + '\n')


def read_request(c):
    data = b''
    while b'\r\n\r\n' not in data:
        b = c.recv(4096)
        if not b:
            return None, None
        data += b
        if len(data) > 8192:
            return None, None
    head = data.split(b'\r\n\r\n', 1)[0].decode('latin-1')
    lines = head.split('\r\n')
    hdr = {}
    for l in lines[1:]:
        k, _, v = l.partition(':')
        hdr[k.strip().lower()] = v.strip()
    return lines[0], hdr


def check(line, hdr, who):
    bad = []
    m = re.match(r'^GET (\S+) HTTP/1\.1$', line)
    if not m:
        bad.append('request line %r' % line[:60])
    if 'VerandaUpdate' not in hdr.get('user-agent', ''):
        bad.append('no User-Agent')
    if hdr.get('accept-encoding') != 'identity':
        bad.append('Accept-Encoding %r' % hdr.get('accept-encoding'))
    if hdr.get('connection', '').lower() != 'close':
        bad.append('Connection %r' % hdr.get('connection'))
    if not hdr.get('host'):
        bad.append('no Host')
    return (m.group(1) if m else ''), bad


def send(c, code, reason, body=b'', extra=()):
    h = ['HTTP/1.1 %d %s' % (code, reason), 'Server: GitHub.com', 'Content-Type: text/html; charset=utf-8']
    h += list(extra)
    h += ['Content-Length: %d' % len(body), 'Connection: close', '', '']
    c.sendall('\r\n'.join(h).encode() + body)


def release_tag(rel):
    """the release's tag: its UPDATE.LST's (or DICT.LST's) "tag" line"""
    for n in ('UPDATE.LST', 'DICT.LST'):
        if os.path.isfile(os.path.join(rel, n)):
            for l in open(os.path.join(rel, n), encoding='latin-1'):
                if l.startswith('tag '):
                    return l[4:].strip()
    return None


RELS = {}      # an asset's token: its release's folder


def which(path):
    """the repository a path asks for and its release's folder"""
    repos = {CFG['repo']: CFG['release']}
    repos.update(CFG.get('repos', {}))
    for r, rel in repos.items():
        if path.startswith('/%s/' % r):
            return r, rel
    return CFG['repo'], CFG['release']


def github(c, aport):
    line, hdr = read_request(c)
    if line is None:
        return
    path, bad = check(line, hdr, 'github')
    repo, rel = which(path)
    m = re.match(r'^/%s/releases/(?:latest/download|download/([^/]+))/([^/?]+)$' % re.escape(repo), path)
    if not m or (path.endswith('/latest/download/UPDATE.LST') and not CFG.get('latest', True)):
        log(host='github', path=path[:120], status=404, bad=bad, hosthdr=hdr.get('host'))
        send(c, 404, 'Not Found', b'Not Found')
        return
    tag, name = m.group(1), m.group(2)
    rtag = release_tag(rel)
    if tag is None and rtag == 'test':
        log(host='github', path=path[:120], status=404, name=name, tag=tag, why='a pre-release is never latest',
            bad=bad, hosthdr=hdr.get('host'))
        send(c, 404, 'Not Found', b'Not Found')
        return
    if tag is None:
        # (GitHub: the latest release's download, on github.com itself, then the asset's host)
        url = 'https://%s/%s/releases/download/%s/%s' % (hdr.get('host'), repo, rtag, name)
        log(host='github', path=path[:120], status=302, name=name, tag=tag, location=url, bad=bad,
            hosthdr=hdr.get('host'))
        send(c, 302, 'Found', b'<html><body>You are being redirected.</body></html>', ['Location: ' + url])
        return
    if tag != rtag:
        log(host='github', path=path[:120], status=404, name=name, tag=tag, why='no release tagged %s' % tag,
            bad=bad, hosthdr=hdr.get('host'))
        send(c, 404, 'Not Found', b'Not Found')
        return
    if not os.path.isfile(os.path.join(rel, name)) or name in CFG.get('missing', []):
        log(host='github', path=path[:120], status=404, name=name, tag=tag, bad=bad, hosthdr=hdr.get('host'))
        send(c, 404, 'Not Found', b'Not Found')
        return
    tok = hashlib.sha256(('%s %d' % (name, len(TOKENS))).encode()).hexdigest()
    TOKENS[tok] = name
    RELS[tok] = rel
    q = ('X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=releaseassetproduction%2F20261121%2Fus-east-1%2Fs3%2Faws4_request'
         '&X-Amz-Date=20261121T120000Z&X-Amz-Expires=300&X-Amz-Signature=' + tok + '&X-Amz-SignedHeaders=host'
         '&actor_id=0&key_id=0&repo_id=123456789&response-content-disposition=attachment%3B%20filename%3D' + name +
         '&response-content-type=application%2Foctet-stream&jwt=')
    url = 'https://localhost:%d/github-production-release-asset-2e65be/123456789/%s?%s' % (aport, tok[:36], q)
    url += ('eyJ' + hashlib.sha512(tok.encode()).hexdigest() * 3)[:950 - len(url)]
    log(host='github', path=path[:120], status=302, name=name, tag=tag, location_len=len(url), bad=bad,
        hosthdr=hdr.get('host'))
    send(c, 302, 'Found', b'<html><body>You are being redirected.</body></html>', ['Location: ' + url])


def assets(c):
    line, hdr = read_request(c)
    if line is None:
        return
    path, bad = check(line, hdr, 'assets')
    m = re.match(r'^/github-production-release-asset-2e65be/\d+/[0-9a-f]+\?.*X-Amz-Signature=([0-9a-f]{64})&', path)
    name = TOKENS.get(m.group(1)) if m else None
    rel = RELS.get(m.group(1)) if m else None
    if not name:
        log(host='assets', path=path[:80], status=403, line_len=len(line), bad=bad)
        send(c, 403, 'Forbidden', b'<Error>AccessDenied</Error>')
        return
    body = open(os.path.join(rel, name), 'rb').read()
    how = []
    if name in CFG.get('corrupt', []):
        body = bytearray(body)
        body[len(body) // 2] ^= 0x5A
        body = bytes(body)
        how.append('corrupt')
    with LOCK:
        COUNT[0] += 1
        n = COUNT[0]
        drop = name in CFG.get('drop', []) and name not in DROPPED
        if drop:
            DROPPED.add(name)
    chunked = n % 2 == 1
    h = ['HTTP/1.1 200 OK', 'Content-Type: application/octet-stream', 'Accept-Ranges: bytes',
         'x-ms-request-id: 0', 'Connection: close']
    if chunked:
        h.append('Transfer-Encoding: chunked')
        how.append('chunked')
    else:
        h.append('Content-Length: %d' % len(body))
        how.append('content-length')
    c.sendall('\r\n'.join(h + ['', '']).encode())
    if drop:
        how.append('dropped')
        cut = len(body) // 2
        if chunked:
            c.sendall(b'%x\r\n' % cut + body[:cut])
        else:
            c.sendall(body[:cut])
        log(host='assets', name=name, status=200, line_len=len(line), how=how, bad=bad, hosthdr=hdr.get('host'))
        return
    if chunked:
        i, k = 0, 0
        while i < len(body):
            step = [700, 1, 333, 512, 699][k % 5]
            part = body[i:i + step]
            ext = ';name=value' if k == 2 else ''
            c.sendall(b'%X%s\r\n' % (len(part), ext.encode()) + part + b'\r\n')
            i += step
            k += 1
        c.sendall(b'0\r\nX-Trailer: done\r\n\r\n')
    else:
        c.sendall(body)
    log(host='assets', name=name, status=200, line_len=len(line), how=how, bad=bad, hosthdr=hdr.get('host'))


def serve(sock, fn, *a):
    while True:
        c, _ = sock.accept()

        def run(c=c):
            try:
                c.settimeout(60)
                fn(c, *a)
            except OSError:
                pass
            finally:
                try:
                    c.shutdown(socket.SHUT_RDWR)
                except OSError:
                    pass
                c.close()
        threading.Thread(target=run, daemon=True).start()


def listener(addr):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind((addr, 0))
    s.listen(8)
    return s


def main():
    g, a = listener('127.0.0.1'), listener('127.0.0.1')
    aport = a.getsockname()[1]
    threading.Thread(target=serve, args=(a, assets), daemon=True).start()
    with open(os.path.join(D, 'ready'), 'w') as f:
        f.write('%d %d\n' % (g.getsockname()[1], aport))
    serve(g, github, aport)


if __name__ == '__main__':
    main()
