#!/usr/bin/env python3
"""Gate gemini (DECISIONS V124): tools/web_proxy.py on the host, against the
sample pages in tests/web/ (written for these tests, not downloaded): the
HTML converter, DuckDuckGo's results, the requests (a fake fetcher: no
website is contacted), the private-address filter, the size cap; then the
proxy itself over TLS on localhost (a certificate made with openssl, when
there is one) in front of a local http.server serving tests/web/.

usage: test_web_proxy.py <work folder>
"""
import functools
import http.server
import importlib.util
import os
import socket
import ssl
import subprocess
import sys
import threading
import time
import urllib.error

TOP = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
spec = importlib.util.spec_from_file_location('web_proxy', os.path.join(TOP, 'tools', 'web_proxy.py'))
wp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(wp)
WORK = sys.argv[1]
WEB = os.path.join(TOP, 'tests', 'web')


def need(c, msg):
    if not c:
        sys.exit('FAIL  web_proxy: ' + msg)


def ok(msg):
    print('ok    web_proxy: ' + msg)


def sample(name):
    return open(os.path.join(WEB, name), encoding='utf-8').read()


BASE = 'https://gazette.example/2026/tomatoes.html'

# ---------------------------------------------------------------- the converter
g = wp.to_gemtext(sample('article.html'), BASE)
L = g.split('\n')
for bad in ('do not show this', 'Sidebar text', 'Subscribe', 'Popular', '/news', '/shop', 'Copyright', '/privacy',
            'document.write', 'font-family'):
    need(bad not in g, 'dropped text is shown: %r' % bad)
need(L[0] == '# Tomatoes on a Balcony', 'the first line: %r' % L[0])
for want in ('## What you need', '### A watering table', '* A pot of at least 20 litres', '* Compost & a little grit',
             '> “The best fertiliser is the gardener’s shadow.”',
             '```', 'Month   Litres/day', 'June    1.5',
             '=> https://gazette.example/varieties/cherry [1] cherry variety',
             '=> https://example.org/seeds?id=42&lang=en [2] seed library',
             '=> https://gazette.example/2026/images/balcony.jpg Picture: A balcony full of tomatoes',
             '=> %s The original page' % BASE):
    need(want in L, 'no line %r in:\n%s' % (want, g))
p = [l for l in L if l.startswith('Choose a cherry variety [1]')]
need(p and p[0].endswith('seed library [2].'), 'the paragraph with its link numbers: %s' % p)
need(L.index(p[0]) + 1 == L.index('=> https://gazette.example/varieties/cherry [1] cherry variety'),
     'the links do not follow their paragraph')
need('Water at the base, never the leaves, and pick the fruit as soon as it colours. Enjoy them warm from the sun.' in L,
     'a <br> and the whitespace')
need(L.count('```') == 2, 'the preformatted block\'s fences')
items = [i for i, l in enumerate(L) if l.startswith('* ')]
need(items == list(range(items[0], items[0] + 3)), 'list items apart')
ok('the article (tests/web/article.html): script, style, header, nav, aside, form and footer dropped; the <main> '
   '<article> taken (it has the paragraph text); h1-h3, paragraphs, a list, a quote, pre kept; links numbered after '
   'their paragraph, absolute (%d lines)' % len(L))

# no article: everything kept; markup that looks like gemtext escaped
g2 = wp.to_gemtext('<html><head><title>Short</title></head><body><p>=> not a link</p><p># not a heading</p>'
                   '<a href="x.png">pic</a></body></html>', 'http://h.example/a/')
need(g2.split('\n')[:5] == ['# Short', '', ' => not a link', '', ' # not a heading'], 'a short page: %r' % g2)
need('=> http://h.example/a/x.png pic' in g2, 'a picture link: %r' % g2)
ok('a page without an article: all of it; "=>", "#" at a paragraph\'s start escaped; a link to a picture')

s = wp.search_gemtext(sample('ddg.html'), 'commander x16')
S = s.split('\n')
need(S[0] == '# Search: commander x16', 'the search title')
need('=> https://www.commanderx16.com/ Commander X16 - the official site' in S and
     '=> https://github.com/X16Community/x16-docs x16-docs: the documentation' in S, 'the results: %r' % s)
need('Buy one now' not in s and 'The Commander X16 is a modern 8-bit computer.' in S and
     ' # The manual & the reference.' in S, 'the snippets, the advert: %r' % s)
ok('DuckDuckGo\'s results (tests/web/ddg.html): 2 results (the uddg addresses decoded), their snippets, the advert '
   'dropped')

# ---------------------------------------------------------------- requests (a fake fetcher)
calls = []


def fake(url):
    calls.append(url)
    if 'html.duckduckgo.com' in url:
        return url, 'text/html; charset=utf-8', sample('ddg.html').encode()
    if url.endswith('.txt'):
        return url, 'text/plain; charset=iso-8859-1', 'caf\xe9\n'.encode('latin-1')
    if url.endswith('.png'):
        return url, 'image/png', b'\x89PNG\r\n\x1a\nrest'
    if url.endswith('/big.html'):
        return url, 'text/html', ('<p>' + 'word ' * 30000 + '</p>').encode()
    if url.endswith('/gone'):
        raise urllib.error.HTTPError(url, 404, 'Not Found', {}, None)
    if 'unreachable' in url:
        raise urllib.error.URLError('no such host')
    return BASE, 'text/html', sample('article.html').encode()


h, b = wp.respond('https://gazette.example/t', fake)
need(h == '20 text/gemini; charset=utf-8' and b.decode().startswith('# Tomatoes on a Balcony'), 'a page: %s' % h)
need(wp.respond('https://x.example/a.txt', fake) == ('20 text/plain; charset=utf-8', 'caf\xe9\n'.encode()), 'text/plain')
need(wp.respond('http://x.example/p.png', fake) == ('20 image/png', b'\x89PNG\r\n\x1a\nrest'), 'a picture')
h, b = wp.respond('https://x.example/big.html', fake)
need(len(b) <= wp.MAX_OUT and b.endswith(b'longer than the proxy sends.)\n'), 'the cap: %d' % len(b))
need(wp.respond('https://x.example/gone', fake)[0] == '51 The web server says 404 Not Found', '404')
need(wp.respond('https://unreachable.example/', fake)[0].startswith('43 '), 'unreachable')
need(wp.respond('gopher://x.example/', fake)[0].startswith('53 '), 'gopher')
need(wp.respond('gemini://192.168.1.20/search', fake) == ('10 Search the web (DuckDuckGo):', b''), 'the search box')
h, b = wp.respond('gemini://192.168.1.20/search?commander%20x16', fake)
need(calls[-1] == 'https://html.duckduckgo.com/html/?q=commander+x16' and b.decode() == s, 'the search: %s' % calls[-1])
need(wp.respond('gemini://192.168.1.20/go', fake)[0] == '10 A web address (https://...):', '/go')
wp.respond('gemini://192.168.1.20/go?gazette.example%2Fx', fake)
need(calls[-1] == 'https://gazette.example/x', '/go: %s' % calls[-1])
need(wp.respond('gemini://192.168.1.20/', fake)[1].decode() == wp.HOME, 'the start page')
ok('requests: an http(s) URL converted, text/plain re-encoded as UTF-8, a picture passed through, the 64 KB cap '
   '(cut at a line), 404 (51), unreachable (43), gopher (53); its own pages: /, /search (10, then '
   'html.duckduckgo.com/html/?q=...), /go (10, https:// added)')

# (V125) a JPEG through the proxy: a PNG with Pillow (scaled to the page), as it is without
try:
    import io
    from PIL import Image
    im = Image.new('RGB', (1600, 900), (200, 60, 30))
    jb = io.BytesIO()
    im.save(jb, 'JPEG')
    jpeg = jb.getvalue()
except ImportError:
    Image, jpeg = None, b'\xff\xd8\xff\xe0' + bytes(100)
h, b = wp.respond('https://x.example/p.jpg', lambda u: (u, 'image/jpeg', jpeg))
if Image:
    need(h == '20 image/png' and b[:8] == b'\x89PNG\r\n\x1a\n', 'a JPEG with Pillow: %s' % h)
    got = Image.open(io.BytesIO(b))
    need(got.size == (624, 351) and not got.info.get('interlace'), 'the JPEG as PNG: %s' % (got.size,))
    ok('a JPEG (1600 x 900) through the proxy with Pillow: a PNG of 624 x 351 (the page\'s size), not interlaced')
else:
    need(h == '20 image/jpeg' and b == jpeg, 'a JPEG without Pillow: %s' % h)
    ok('a JPEG through the proxy without Pillow: passed as it is (Veranda Gemini offers to save it)')

for a, want in (('127.0.0.1', 1), ('192.168.1.5', 1), ('10.1.2.3', 1), ('172.20.0.9', 1), ('::1', 1),
                ('::ffff:192.168.0.7', 1), ('8.8.8.8', 0), ('100.64.0.1', 0), ('172.32.0.1', 0), ('2001:db8::1', 0)):
    need(wp.allowed_client(a) == bool(want), 'allowed_client(%s)' % a)
ok('only private addresses: loopback, 10/8, 172.16/12, 192.168/16 (and IPv6 loopback, unique-local) accepted')

# ---------------------------------------------------------------- the proxy over TLS
if not wp.shutil.which('openssl'):
    ok('no openssl here: the TLS run skipped')
    sys.exit(0)


class Quiet(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *a):
        pass


hs = http.server.ThreadingHTTPServer(('127.0.0.1', 0), functools.partial(Quiet, directory=WEB))
threading.Thread(target=hs.serve_forever, daemon=True).start()
hport = hs.server_address[1]
t = socket.socket()
t.bind(('127.0.0.1', 0))
pport = t.getsockname()[1]
t.close()
log = open(os.path.join(WORK, 'proxy.log'), 'w')
proc = subprocess.Popen([sys.executable, '-I', '-B', os.path.join(TOP, 'tools', 'web_proxy.py'), '--host', '127.0.0.1',
                         '--port', str(pport), '--cert', os.path.join(WORK, 'p.crt'), '--key', os.path.join(WORK, 'p.key')],
                        stdout=log, stderr=subprocess.STDOUT)


def ask(line):
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE        # (as the modem: no check)
    with socket.create_connection(('127.0.0.1', pport), timeout=20) as raw:
        with ctx.wrap_socket(raw) as c:
            c.sendall(line.encode() + b'\r\n')
            data = b''
            while True:
                k = c.recv(65536)
                if not k:
                    break
                data += k
    head, _, body = data.partition(b'\r\n')
    return head.decode(), body


try:
    for _ in range(100):
        try:
            socket.create_connection(('127.0.0.1', pport), timeout=1).close()
            break
        except OSError:
            time.sleep(0.1)
    url = 'http://127.0.0.1:%d/article.html' % hport
    head, body = ask(url)
    need(head == '20 text/gemini; charset=utf-8', 'over TLS: %s' % head)
    need(body.decode() == wp.to_gemtext(sample('article.html'), url), 'over TLS: the page is not the converter\'s')
    head, body = ask('gemini://127.0.0.1:%d/search' % pport)
    need(head == '10 Search the web (DuckDuckGo):', 'over TLS: the search %s' % head)
finally:
    proc.terminate()
    proc.wait()
    hs.shutdown()
plog = open(os.path.join(WORK, 'proxy.log')).read()
need('made a self-signed certificate' in plog and plog.count(' -> ') == 2, 'the proxy\'s log: %s' % plog)
ok('the proxy over TLS on localhost (a self-signed certificate made by openssl): %s converted as the converter does; '
   'its search box; one log line a request' % url)
