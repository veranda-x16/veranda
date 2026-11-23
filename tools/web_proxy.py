#!/usr/bin/env python3
# Veranda Gemini's private web proxy (DECISIONS V124).
# Copyright (c) 2026 Marcin Spoczynski. MIT licence (see LICENSE).
"""web_proxy.py: ordinary web pages for Veranda Gemini on the Commander X16,
turned into gemtext on your own PC.

Run it on a PC on the same network as the X16 (Python 3, nothing else):

    python3 web_proxy.py

then, in Veranda Gemini, File > Settings..., choose 2 (always my proxy)
or 0 (ask each time), and type this PC's address, e.g. 192.168.1.20 (port
1965 when none is given; --port to change it).

It is a Gemini proxy: Veranda Gemini connects to it with TLS (the Wi-Fi
modem's) and sends the absolute http(s) URL as the request line, as the
Gemini specification's proxy requests are. The proxy fetches the page
with urllib (a desktop browser's User-Agent; redirects followed) and
turns its HTML into gemtext: scripts, styles, navigation, headers,
footers, asides and forms dropped; headings, paragraphs, lists, quotes
and preformatted text kept; the part of the page with the most paragraph
text taken as the article; each paragraph's links numbered and listed as
"=> URL [n] text" lines after it; pictures as links. text/plain is passed
through. Pictures: with Pillow installed (pip install pillow; optional),
JPEG, GIF, WebP, BMP and PNG become PNG scaled to Veranda Gemini's page
(624 x 408), which it shows; without Pillow they pass as they are (the
standard library cannot decode JPEG), as other files do, so Veranda
Gemini can save them. A page is cut at --max bytes (64 KB).

Its own pages (any gemini:// request is for the proxy itself):
    gemini://<this PC>/          a start page
    gemini://<this PC>/search    a search box (1x), DuckDuckGo's HTML
                                 results (html.duckduckgo.com) as links
    gemini://<this PC>/go        a web address asked (1x), then the page

TLS: the certificate is made the first time with the openssl program
(web_proxy.crt and web_proxy.key next to this file, self-signed; the
modem does not check certificates). Without openssl, make them anywhere
with
    openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -subj /CN=veranda \\
        -keyout web_proxy.key -out web_proxy.crt
and pass --cert and --key. Only private (LAN) addresses may connect: the
proxy fetches any page it is asked for. Each request is logged on one line.
Everything you read goes through this PC only (and the sites themselves).
"""
import argparse
import html.parser
import ipaddress
import os
import re
import shutil
import socket
import socketserver
import ssl
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

DEFAULT_PORT = 1965
MAX_OUT = 64 * 1024             # a page sent to the X16, at most
MAX_IN = 4 * 1024 * 1024        # a page read from the web, at most
TIMEOUT = 20
USER_AGENT = 'Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0'
SEARCH = 'https://html.duckduckgo.com/html/?q='

_PRIVATE4 = [ipaddress.ip_network(n) for n in ('127.0.0.0/8', '10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16',
                                              '169.254.0.0/16')]
_PRIVATE6 = [ipaddress.ip_network(n) for n in ('::1/128', 'fc00::/7', 'fe80::/10')]


def allowed_client(addr):
    """the X16 must be on this PC's own network: loopback, 10/8, 172.16/12,
    192.168/16, link-local; IPv6 loopback, unique-local and link-local"""
    try:
        ip = ipaddress.ip_address(addr.split('%')[0])
    except ValueError:
        return False
    if ip.version == 6 and ip.ipv4_mapped:
        ip = ip.ipv4_mapped
    nets = _PRIVATE4 if ip.version == 4 else _PRIVATE6
    return any(ip in n for n in nets)


# ---------------------------------------------------------------- HTML to gemtext

SKIP = {'script', 'style', 'nav', 'header', 'footer', 'aside', 'form', 'noscript', 'svg', 'button', 'select',
        'textarea', 'iframe', 'template', 'object', 'canvas', 'dialog', 'menu'}
VOID = {'area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link', 'meta', 'param', 'source', 'track', 'wbr'}
BLOCK = {'p': 'p', 'h1': 'h1', 'h2': 'h2', 'h3': 'h3', 'h4': 'h3', 'h5': 'h3', 'h6': 'h3', 'li': 'li', 'dt': 'p',
         'dd': 'p', 'blockquote': 'quote', 'pre': 'pre', 'figcaption': 'p', 'caption': 'p', 'td': 'p', 'th': 'p',
         'div': 'p', 'section': 'p', 'article': 'p', 'main': 'p', 'tr': 'p', 'table': 'p', 'ul': 'p', 'ol': 'p',
         'dl': 'p', 'figure': 'p', 'address': 'p', 'center': 'p', 'body': 'p'}
CONTAINERS = {'article', 'main', 'div', 'section', 'td', 'body', 'blockquote', 'ul', 'ol', 'table', 'tbody', 'tr',
              'center', 'figure', 'span', 'font'}
PICTURE = re.compile(r'\.(png|jpe?g|gif|bmp|webp|svg)(\?|$)', re.I)


class Block:
    __slots__ = ('kind', 'text', 'links', 'owners', 'parent')

    def __init__(self, kind, owners, parent):
        self.kind, self.text, self.links, self.owners, self.parent = kind, [], [], owners, parent


class Page(html.parser.HTMLParser):
    """the page's blocks (kind, text, links) and, for each, the containers
    it is in: enough for a crude article extraction"""

    def __init__(self, base):
        super().__init__(convert_charrefs=True)
        self.base = base
        self.stack = []                 # (tag, container id or None)
        self.skip = 0                   # inside a dropped element
        self.blocks = []
        self.cur = None
        self.quote = 0
        self.pre = 0
        self.title = ''
        self.in_title = False
        self.ids = 0
        self.link = None                # the <a> open: [href, text]
        self.ptext = {}                 # container id: paragraph text directly in it
        self.parents = {}               # container id: its parent's
        self.tags = {}                  # container id: its tag
        self.base_set = False

    # the containers open now, innermost last
    def owners(self):
        return tuple(c for _, c in self.stack if c is not None)

    def open_block(self, kind):
        self.close_block()
        own = self.owners()
        self.cur = Block(kind, own, own[-1] if own else None)

    def close_block(self):
        b = self.cur
        self.cur = None
        if b is None:
            return
        if b.kind == 'pre':
            text = ''.join(b.text).strip('\n')
        else:
            text = re.sub(r'\s+', ' ', ''.join(b.text)).strip()
        if not text and not b.links:
            return
        b.text = text
        if b.kind in ('p', 'li', 'quote') and b.parent is not None:
            self.ptext[b.parent] = self.ptext.get(b.parent, 0) + len(text)
        self.blocks.append(b)

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag == 'base' and a.get('href') and not self.base_set:
            self.base = urllib.parse.urljoin(self.base, a['href'])
            self.base_set = True
        if tag == 'title':
            self.in_title = True
        if self.skip or tag in SKIP:
            if tag not in VOID:
                self.skip += 1
                self.stack.append((tag, None))
            return
        if tag in ('head',):
            return
        cid = None
        if tag in CONTAINERS:
            self.ids += 1
            cid = self.ids
            own = self.owners()
            self.parents[cid] = own[-1] if own else None
            self.tags[cid] = tag
        if tag == 'blockquote':
            self.quote += 1
        if tag == 'pre':
            self.pre += 1
        if tag not in VOID:
            self.stack.append((tag, cid))
        if tag == 'br':
            self.data('\n' if self.pre else ' ')
        elif tag == 'hr':
            self.close_block()
        elif tag == 'img':
            src = a.get('src') or a.get('data-src')
            if src and not src.startswith('data:'):
                if self.cur is None:
                    self.open_block('p')
                alt = re.sub(r'\s+', ' ', a.get('alt') or '').strip()
                self.cur.links.append((urllib.parse.urljoin(self.base, src), 'Picture: ' + (alt or 'an image'), True))
        elif tag == 'a':
            href = a.get('href')
            if href and not href.startswith(('javascript:', '#', 'data:')):
                self.link = [urllib.parse.urljoin(self.base, href), []]
        elif tag in BLOCK:
            kind = BLOCK[tag]
            if kind == 'p' and tag not in ('p', 'dt', 'dd', 'figcaption', 'caption', 'td', 'th'):
                self.close_block()      # (a container: the text after it is a block of its own)
                return
            if self.pre and tag != 'pre':
                return
            if self.quote and kind == 'p':
                kind = 'quote'
            self.open_block(kind)

    def handle_endtag(self, tag):
        if tag == 'title':
            self.in_title = False
        if not any(t == tag for t, _ in self.stack):
            return
        while self.stack:
            t, _ = self.stack.pop()
            if self.skip:
                self.skip -= 1
                if t == tag:
                    return
                continue
            if t == 'a' and self.link:
                self.end_link()
            if t == 'blockquote':
                self.quote -= 1
            if t == 'pre':
                self.pre -= 1
            if t in BLOCK:
                self.close_block()
            if t == tag:
                return

    def end_link(self):
        href, words = self.link
        self.link = None
        text = re.sub(r'\s+', ' ', ''.join(words)).strip()
        if self.cur is None:
            self.open_block('p')
        n = len(self.cur.links)
        self.cur.links.append((href, text, bool(PICTURE.search(href))))
        if text:
            self.cur.text.append(' [%d]' % (n + 1))

    def handle_data(self, d):
        if self.in_title:
            self.title += d
            return
        if self.skip:
            return
        self.data(d)

    def data(self, d):
        if self.link is not None:
            self.link[1].append(d)
        if self.cur is None:
            if not d.strip():
                return
            self.open_block('quote' if self.quote else 'pre' if self.pre else 'p')
        self.cur.text.append(d)

    def finish(self):
        if self.link:
            self.end_link()
        self.close()
        self.close_block()


def article(page):
    """the blocks of the container with the most paragraph text directly in
    it (crude readability), with its descendants; all of them when that is
    less than a third of the page's paragraph text"""
    total = sum(page.ptext.values())
    if not page.ptext or total < 200:
        return page.blocks
    best = max(page.ptext, key=lambda c: page.ptext[c])
    # (an article or main element around it is the better choice)
    c = page.parents.get(best)
    while c is not None:
        if page.tags.get(c) in ('article', 'main'):
            best = c
            break
        c = page.parents.get(c)
    inside = [b for b in page.blocks if best in b.owners]
    got = sum(len(b.text) for b in inside if b.kind in ('p', 'li', 'quote'))
    if got * 3 < total:
        return page.blocks
    return inside


def gem_line(s):
    """a text line that cannot be read as gemtext's markup"""
    if s.startswith(('=>', '#', '* ', '>', '```')):
        return ' ' + s
    return s


def to_gemtext(markup, base, keep_all=False):
    """HTML (a str) into gemtext (a str)"""
    page = Page(base)
    page.feed(markup)
    page.finish()
    blocks = page.blocks if keep_all else article(page)
    out = []
    title = re.sub(r'\s+', ' ', page.title).strip()
    if title and not any(b.kind == 'h1' for b in blocks):
        out.append('# ' + title)
    prev = None
    for b in blocks:
        if out and not (b.kind == prev == "li"):
            out.append("")      # (a blank line between blocks, not between list items)
        prev = b.kind
        if b.text:
            if b.kind == 'h1':
                out.append('# ' + b.text)
            elif b.kind == 'h2':
                out.append('## ' + b.text)
            elif b.kind == 'h3':
                out.append('### ' + b.text)
            elif b.kind == 'li':
                out.append('* ' + b.text)
            elif b.kind == 'quote':
                out.append('> ' + b.text)
            elif b.kind == 'pre':
                out.append('```')
                out.extend(l.replace('```', "'''") for l in b.text.split('\n'))
                out.append('```')
            else:
                out.append(gem_line(b.text))
        for i, (href, text, pic) in enumerate(b.links):
            label = text if pic else '[%d] %s' % (i + 1, text or href)
            out.append('=> %s %s' % (href, label))
    out.append('')
    out.append('=> %s The original page' % base)
    return '\n'.join(out) + '\n'


class Results(html.parser.HTMLParser):
    """DuckDuckGo's HTML results: (url, title, snippet)"""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.results, self.cur, self.mode = [], None, None

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        cls = (a.get('class') or '').split()
        if tag == 'a' and 'result__a' in cls:
            href = a.get('href') or ''
            q = urllib.parse.parse_qs(urllib.parse.urlsplit(href).query)
            if 'uddg' in q:
                href = q['uddg'][0]
            elif href.startswith('//'):
                href = 'https:' + href
            self.cur = [href, '', '']
            self.results.append(self.cur)
            self.mode = 1
        elif 'result__snippet' in cls and self.cur is not None:
            self.mode = 2

    def handle_endtag(self, tag):
        if tag in ('a', 'td', 'div'):
            self.mode = None

    def handle_data(self, d):
        if self.mode and self.cur is not None:
            self.cur[self.mode] += d


def search_gemtext(markup, query):
    p = Results()
    p.feed(markup)
    p.close()
    out = ['# Search: ' + query, '']
    n = 0
    for href, title, snippet in p.results:
        if not href.startswith(('http://', 'https://')) or 'duckduckgo.com/y.js' in href:
            continue                    # (adverts)
        n += 1
        out.append('=> %s %s' % (href, re.sub(r'\s+', ' ', title).strip() or href))
        s = re.sub(r'\s+', ' ', snippet).strip()
        if s:
            out.append(gem_line(s))
    if not n:
        out.append('Nothing found.')
    out += ['', '=> /search Search again']
    return '\n'.join(out) + '\n'


def cut(text, limit):
    """gemtext in UTF-8, cut at a line's end before limit bytes"""
    b = text.encode('utf-8')
    if len(b) <= limit:
        return b
    b = b[:limit - 80]
    b = b[:b.rfind(b'\n') + 1]
    return b + b'\n(The page was cut here: it is longer than the proxy sends.)\n'


# ---------------------------------------------------------------- requests

def charset_of(ctype, body):
    m = re.search(r'charset=([\w.:-]+)', ctype or '', re.I)
    if not m:
        m = re.search(rb'<meta[^>]+charset=["\']?([\w.:-]+)', body[:4096], re.I)
        cs = m.group(1).decode('ascii', 'replace') if m else 'utf-8'
    else:
        cs = m.group(1)
    try:
        ''.encode(cs)
    except LookupError:
        cs = 'utf-8'
    return cs


def fetch(url):
    """(final URL, content type, body bytes) of a web page; urllib follows redirects"""
    req = urllib.request.Request(url, headers={'User-Agent': USER_AGENT,
                                               'Accept': 'text/html,application/xhtml+xml,text/plain;q=0.9,*/*;q=0.8',
                                               'Accept-Language': 'en'})
    with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
        return r.geturl(), r.headers.get('Content-Type', ''), r.read(MAX_IN)


HOME = '''# Veranda Gemini's web proxy
This PC turns web pages into gemtext for Veranda Gemini.
=> /search Search the web (DuckDuckGo)
=> /go Open a web address
'''


def to_png(body, limit=(624, 408)):
    """a JPEG, GIF, WebP or BMP picture as a PNG Veranda Gemini can show
    (scaled down to its page: 624 x 408), through Pillow when it is there;
    None without it (the picture passes as it is: Veranda Gemini offers to
    save it). The standard library has no JPEG decoder."""
    try:
        from PIL import Image
    except ImportError:
        return None
    import io
    try:
        im = Image.open(io.BytesIO(body))
        im = im.convert('RGBA' if 'A' in im.getbands() else 'RGB')
        im.thumbnail(limit)
        out = io.BytesIO()
        im.save(out, 'PNG', optimize=True)
        return out.getvalue()
    except (OSError, ValueError):
        return None


def _get(get, url):
    """(error header or None, final URL, content type, body)"""
    try:
        final, ctype, body = get(url)
    except urllib.error.HTTPError as e:
        return '51 The web server says %d %s' % (e.code, e.reason), None, None, None
    except (urllib.error.URLError, OSError, ValueError) as e:
        return '43 The proxy could not fetch the page: %s' % getattr(e, 'reason', e), None, None, None
    return None, final, ctype, body


def web(url, get=fetch, limit=MAX_OUT):
    err, final, ctype, body = _get(get, url)
    if err:
        return err, b''
    mime = (ctype or 'application/octet-stream').split(';')[0].strip().lower()
    if mime in ('text/html', 'application/xhtml+xml') or (not ctype and body.lstrip()[:1] == b'<'):
        text = body.decode(charset_of(ctype, body), 'replace')
        return '20 text/gemini; charset=utf-8', cut(to_gemtext(text, final), limit)
    if mime.startswith('text/'):
        return '20 text/plain; charset=utf-8', cut(body.decode(charset_of(ctype, body), 'replace'), limit)
    if mime.startswith('image/'):
        png = to_png(body)              # (Pillow's, when it is there: a PNG Veranda Gemini shows)
        if png:
            return '20 image/png', png
    return '20 ' + mime, body


def respond(line, get=fetch, limit=MAX_OUT):
    """a request line: (header, body bytes)"""
    try:
        u = urllib.parse.urlsplit(line)
    except ValueError:
        return '59 Not a URL', b''
    if u.scheme in ('http', 'https'):
        return web(line, get, limit)
    if u.scheme != 'gemini':
        return '53 This proxy takes http and https URLs only', b''
    q = urllib.parse.unquote(u.query).strip()
    if u.path in ('', '/'):
        return '20 text/gemini; charset=utf-8', HOME.encode()
    if u.path == '/search':
        if not q:
            return '10 Search the web (DuckDuckGo):', b''
        err, final, ctype, body = _get(get, SEARCH + urllib.parse.quote_plus(q))
        if err:
            return err, b''
        return '20 text/gemini; charset=utf-8', cut(search_gemtext(body.decode(charset_of(ctype, body), 'replace'), q), limit)
    if u.path == '/go':
        if not q:
            return '10 A web address (https://...):', b''
        return web(q if '://' in q else 'https://' + q, get, limit)
    return '51 Not a page of this proxy', b''


class Handler(socketserver.BaseRequestHandler):
    def handle(self):
        ip = self.client_address[0]
        t0 = time.time()
        if not allowed_client(ip):
            log('%s refused (not a private address)' % ip)
            return
        try:
            c = self.server.ctx.wrap_socket(self.request, server_side=True)
        except (ssl.SSLError, OSError) as e:
            log('%s TLS failed: %s' % (ip, e))
            return
        try:
            c.settimeout(30)
            req = b''
            while b'\r\n' not in req and len(req) <= 1026:
                k = c.recv(1100)
                if not k:
                    break
                req += k
            line = req.split(b'\r\n')[0].decode('utf-8', 'replace').strip()
            if b'\r\n' not in req or len(line) > 1024:
                head, body = '59 Bad request', b''
            else:
                head, body = respond(line, limit=self.server.limit)
            c.sendall(head.encode('utf-8') + b'\r\n' + body)
            log('%s %s -> %s, %d bytes, %.1f s' % (ip, line[:200], head[:40], len(body), time.time() - t0))
        except (ssl.SSLError, OSError) as e:
            log('%s failed: %s' % (ip, e))
        finally:
            try:
                c.unwrap()
            except (ssl.SSLError, OSError, ValueError):
                pass
            c.close()


class Server(socketserver.ThreadingMixIn, socketserver.TCPServer):
    allow_reuse_address = True
    daemon_threads = True


def log(s):
    print(time.strftime('%H:%M:%S ') + s, flush=True)


def make_cert(cert, key):
    if os.path.exists(cert) and os.path.exists(key):
        return True
    if not shutil.which('openssl'):
        print('No certificate (%s, %s) and no openssl program to make one. Make them with\n'
              '  openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -subj /CN=veranda '
              '-keyout %s -out %s\n(on any computer) and run this again.' % (cert, key, key, cert))
        return False
    r = subprocess.run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '3650',
                        '-subj', '/CN=veranda-web-proxy', '-keyout', key, '-out', cert],
                       stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    if r.returncode:
        print('openssl failed: ' + r.stderr.decode('utf-8', 'replace'))
        return False
    log('made a self-signed certificate: %s, %s' % (cert, key))
    return True


def main(argv=None):
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser(description='A private web-to-gemtext proxy for Veranda Gemini.')
    ap.add_argument('--host', default='0.0.0.0', help='the address to listen on (default: all)')
    ap.add_argument('--port', type=int, default=DEFAULT_PORT, help='the port (default 1965)')
    ap.add_argument('--cert', default=os.path.join(here, 'web_proxy.crt'))
    ap.add_argument('--key', default=os.path.join(here, 'web_proxy.key'))
    ap.add_argument('--max', type=int, default=MAX_OUT, help='a page sent at most, in bytes (default 65536)')
    a = ap.parse_args(argv)
    if not make_cert(a.cert, a.key):
        return 1
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain(a.cert, a.key)
    srv = Server((a.host, a.port), Handler)
    srv.ctx, srv.limit = ctx, a.max
    names = set()
    try:
        names.add(socket.gethostbyname(socket.gethostname()))
    except OSError:
        pass
    log('Veranda Gemini\'s web proxy on port %d (%s). In Veranda Gemini: File > Settings..., this PC\'s address.'
        % (srv.server_address[1], ', '.join(sorted(names)) or a.host))
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == '__main__':
    sys.exit(main())
