#!/usr/bin/env python3
"""Gate gemini (DECISIONS V118): a small Gemini server on localhost for
Veranda Gemini's test build, with Python's socket module only. Plain TCP:
the emulator's modem makes ATCS (Zimodem's TLS connect) a plain TCP
connection, so no TLS here (and no real server is ever contacted).

usage: gemini_server.py <folder>   writes <folder>/ready (the port, then a
                                   port nothing listens on), <folder>/
                                   gemini.log (every request), the pages
                                   and files it serves (<folder>/files/),
                                   so the checker can compare

The paths (gemini://127.0.0.1:<port>/...):
  /             a gemtext page with every kind of line: headings, a
                paragraph longer than the window, list items, a quote, a
                preformatted block (alt text, CP437 box characters as
                UTF-8, a tab), links (relative, absolute, with no label,
                tabs as spaces, the web, gopher, mail, a picture), UTF-8
                (accents, typographic quotes, a dash, an ellipsis, an
                emoji), a word to find
  /sub/page.gmi a page reached by a relative link (its own links: ../, ?q)
  /input        10 (a question), with a query: a page that answers
  /secret       11 (a sensitive question), with a query: a page
  /redirect     30 to sub/page.gmi (relative)
  /moved        31 to gemini://localhost:<port>/sub/page.gmi (another host)
  /loop         30 to /loop (more than 5)
  /missing      51
  /cert         60
  /plain.txt    20 text/plain; charset=utf-8 (tabs, a long line)
  /latin1.gmi   20 text/gemini; charset=iso-8859-1
  /big.bin      20 application/octet-stream: 40,960 bytes in pieces
  /slow         a page's first lines, then nothing for 120 s
  /cgi-bin/waffle.cgi/view  NewsWaffle's stand-in (V124): 10, with a query a page naming it
  /cgi-bin/wp.cgi/...       Gemipedia's stand-in (V128): view[/<lang>]
                10 without a query, an article it has (WIKI), else 30 to
                search[/<lang>]?<the query, quote_plus'd> as Gemipedia's
                ViewArticle; search: a list; logged "WP route lang query";
                (V138) images?Poland: an image gallery as Gemipedia's
                GalleryRenderer writes it, its links its media route's
                (RouteOptions.MediaProxyUrl: /cgi-bin/wp.cgi/media/media<the
                extension>?<the Wikimedia thumbnail's URL, UrlEncode'd>);
                media...: the picture named by the Wikimedia URL (a PNG of
                tests/png_ref.py's, or image/jpeg), 51 for a host that is not
                wikimedia.org's (IsSafeMediaUrl). Once the gallery has been
                served, the server stops listening until the modem's log
                (<folder>/../modem.log) shows the next connection refused,
                then listens again: the program's one retry
  http(s)://... the private proxy's stand-in (V124): tools/web_proxy.py's
                converter on tests/web/article.html (.../cherry: a small page)
  anything else 51
"""
import importlib.util
import os
import random
import socket
import sys
import threading
import time
import urllib.parse

D = sys.argv[1]
TOP = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_spec = importlib.util.spec_from_file_location('web_proxy', os.path.join(TOP, 'tools', 'web_proxy.py'))
WP = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(WP)
ARTICLE = open(os.path.join(TOP, 'tests', 'web', 'article.html'), encoding='utf-8').read()
LOCK = threading.Lock()
LOG = open(os.path.join(D, 'gemini.log'), 'w')
FILES = os.path.join(D, 'files')
os.makedirs(FILES, exist_ok=True)


def log(s):
    with LOCK:
        LOG.write(s + '\n')
        LOG.flush()


r = random.Random(118)
BIG = bytes(r.randrange(256) for _ in range(40960))
open(os.path.join(FILES, 'big.bin'), 'wb').write(BIG)

ROOT = '''# Veranda Gemini's gate
## A second heading
### A third heading
Polish (V143): Zażółć gęślą jaźń, ZAŻÓŁĆ GĘŚLĄ JAŹŃ.
This paragraph is longer than the window, so the browser wraps it at its spaces: no word is cut in two, and the next row starts with the next word, as far as the end of it.
Averyveryveryveryveryveryveryveryveryveryveryveryveryveryveryveryveryverylongwordwithnospaceatall.

* A list item
* A list item that is long enough to be wrapped onto a second row of the page, indented as the first one is.
*not a list item (no space)
> A quote, long enough to be wrapped: it keeps its bar on every row it takes, as quotes in gemtext do.
>No space after the mark
```An alt text: a box
╔══╗ preformatted\tand a tab
║  ║   spaces    kept
╚══╝ ## not a heading => not a link
```
Accents: café, naïve, Ångström; “quotes” — dashes… and an emoji \U0001F680.
Symbols (V124): \u23E9 next \u23EA back \U0001F3B2 random \u26A0\uFE0F mind \u2022 dot \u2B50 star \U0001F6F8 unknown.
=> sub/page.gmi A relative link
=>/sub/page.gmi\tTabs instead of spaces
=> gemini://127.0.0.1:{port}/sub/page.gmi
=> input Ask my name
=> /secret A secret
=> redirect A redirect
=> moved Another host
=> loop A loop of redirects
=> missing Not found
=> cert A certificate
=> plain.txt Plain text
=> latin1.gmi ISO-8859-1
=> big.bin A binary file
=> slow A stalling page
=> https://example.com/page.html The web
=> gopher://gopher.example/1/ A gopher hole
=> mailto:someone@example.com Mail
=> picture.png A picture
=> pics.gmi Pictures (V125)
=>
# not a link: ## and => only at a line's start
The end of the page, with a needle to find.
'''

SUB = '''# The sub page
=> ../ Up to the root
=> ?q=1 The same page with a query
=> //127.0.0.1:{port}/plain.txt A network-path link
'''

PLAIN = ('Veranda Gemini: a plain text\n'
         'Tabs:\tone\ttwo\tthree\n'
         'A line that is longer than the window: the reader wraps it at its spaces, '
         'so that no word is cut in two, and the next line starts with the next word.\n'
         'UTF-8: café ╔═╗\n')

LATIN1 = '# Latin-1\nCafé crème, à la française.\n'

# (V125) the pictures: tests/png_ref.py's, one over the test's limit; (V192)
# JPEGs: tests/jpeg_ref.py's (Pillow's encoder), a progressive one (refused)
sys.path.insert(0, os.path.join(TOP, 'tests'))
import png_ref  # noqa: E402
import jpeg_ref  # noqa: E402
PICS = ['gray1', 'pal1', 'pal4', 'pal8', 'gray8', 'rgb', 'rgba', 'gray16', 'small', 'comic', 'interlaced', 'corrupt', 'big']
PNGS = {k: png_ref.make(k) for k in PICS}
JPGS = {k: jpeg_ref.make(k) for k in ('photo', 'progressive', 'p422')}
JPEG = JPGS['p422']             # (the gallery's Wawel)
# (V211) the timing session's page and binary
TPAGE = ''.join(('## Part %d\n' % (i // 20) if i % 20 == 0 else '') + ('=> /sub/page.gmi A link, line %d\n' % i if i % 7 == 0 else
                'Line %d of the timing page: some ordinary words that wrap on the screen as a paragraph does.\n' % i)
                for i in range(330)).encode('utf-8')
TBIN = bytes((i * 131 + (i >> 8) * 7) & 255 for i in range(204800))
PICPAGE = ('# Pictures\n' + ''.join('=> pic/%s.png %s.png\n' % (k, k) for k in PICS) + '=> pic/photo.jpg photo.jpg\n'
           '=> pic/progressive.jpg progressive.jpg\n=> /cgi-bin/wp.cgi/images?Poland Gallery: Poland\n')

# (V138) Gemipedia's image gallery (Gemipedia at 00e7863: Gemipedia/Renderer/
# GalleryRenderer.cs, Gemipedia/RouteOptions.cs MediaProxyUrl, Gemipedia/
# CommonUtils.cs GetImageUrl: the img's srcset 2x, else its src, https:)
WM = 'https://upload.wikimedia.org/wikipedia/'
GALLERY_PICS = [   # (the thumbnail's URL, the caption, what is served: a png_ref picture or 'jpeg')
    (WM + 'en/thumb/1/12/Flag_of_Poland.svg/500px-Flag_of_Poland.svg.png', 'Flag of Poland', 'flag'),
    (WM + 'commons/thumb/a/ab/Reconstruction_of_an_8th-century_BCE_Lusatian_culture_settlement_in_Biskupin.svg/'
     '440px-Reconstruction_of_an_8th-century_BCE_Lusatian_culture_settlement_in_Biskupin.svg.png',
     'Biskupin, a reconstruction', 'castle'),
    (WM + 'commons/thumb/4/4e/Wawel_Castle_in_Krak%C3%B3w.jpg/440px-Wawel_Castle_in_Krak%C3%B3w.jpg',
     'Wawel Castle in Kraków', 'jpeg'),
    (WM + 'commons/4/4f/Poland_map_latest', 'Image: a map of Poland', 'map'),
]


def ue(u):
    # (.NET's WebUtility.UrlEncode: unreserved -_.!*() and letters, digits; a space +; %XX upper case)
    return urllib.parse.quote(u, safe='-_.!*()').replace('%20', '+')


def media_url(u, noext=False):
    ext = '' if noext else os.path.splitext(urllib.parse.urlsplit(u).path)[1] or '.jpg'
    return '/cgi-bin/wp.cgi/media/media%s?%s' % (ext, ue(u))


def gallery(closed):
    out = '# Image Gallery: Poland\n=> /cgi-bin/wp.cgi/view?Poland Back to article\n\n'
    for u, cap, kind in GALLERY_PICS:
        out += '=> %s %s\n' % (media_url(u, kind == 'map'), cap)
    out += ('=> gemini://127.0.0.1:%d/cgi-bin/wp.cgi/media/media.png?%s Unreachable\n'
            % (closed, ue(WM + 'en/x.png')))
    return out


REFUSE = threading.Event()      # (the gallery served: the next connection refused once)
CLOSED_PORT = [0]

SLOW = '# A page that stalls\nIts first lines come,\nthen nothing.\n'

# (V128) Gemipedia's articles, in its form (ArticleRenderer: the title, the
# summary, sections as ##, the links to other articles as its view links,
# the gallery and the references): (language, title) -> gemtext
WIKI = {
    ('en', 'Ada Lovelace'): '''# Ada Lovelace
Augusta Ada King, Countess of Lovelace (née Byron; 10 December 1815 – 27 November 1852) was an English mathematician and writer chiefly known for her work on Charles Babbage's proposed mechanical general-purpose computer, the Analytical Engine.
=> /cgi-bin/wp.cgi/images?Ada+Lovelace Gallery: 12 images
## Early life
Lovelace was the only legitimate child of the poet Lord Byron and the reformer Anne Isabella Milbanke.
=> /cgi-bin/wp.cgi/view?Lord+Byron Lord Byron
## Work
Her notes on the engine include what is recognised as the first algorithm intended to be carried out by a machine: a method for calculating Bernoulli numbers.
* Note G: the Bernoulli numbers
* "poetical science"
> That brain of mine is something more than merely mortal; as time will show.
=> /cgi-bin/wp.cgi/view?Charles+Babbage Charles Babbage
=> /cgi-bin/wp.cgi/view?Analytical+Engine Analytical Engine
## References and other languages
=> /cgi-bin/wp.cgi/refs?name=Ada+Lovelace 64 references
=> /cgi-bin/wp.cgi/otherlang?Ada+Lovelace Read in another language
=> https://en.wikipedia.org/wiki/Ada_Lovelace Source on Wikipedia
''',
    ('en', 'Gemini (protocol)'): '''# Gemini (protocol)
Gemini is an application-layer internet communication protocol for accessing remote documents, similar to HTTP and Gopher.
=> /cgi-bin/wp.cgi/view?Gopher+%28protocol%29 Gopher (protocol)
''',
    ('pl', 'Warszawa'): '''# Warszawa
Warszawa – miasto stołeczne Polski i województwa mazowieckiego, największe miasto kraju, położone w jego środkowo-wschodniej części, na Nizinie Środkowomazowieckiej, nad Wisłą.
=> /cgi-bin/wp.cgi/view/pl?Wis%C5%82a Wisła
''',
}


def page(port, path):
    return {'/': ROOT, '/sub/page.gmi': SUB}[path].replace('{port}', str(port))


def serve(c, port):
    try:
        req = b''
        c.settimeout(20)
        while b'\r\n' not in req and len(req) < 2048:
            k = c.recv(1024)
            if not k:
                return
            req += k
        url = req.split(b'\r\n')[0].decode('utf-8', 'replace')
        log('REQ ' + url)
        u = urllib.parse.urlsplit(url)
        path = u.path or '/'

        def send(head, body=b''):
            c.sendall(head.encode('utf-8') + b'\r\n' + body)

        if u.scheme in ('http', 'https'):
            # (the private proxy: tools/web_proxy.py's converter on a sample page)
            if path.endswith('/cherry'):
                body = '# Cherry tomatoes\nSmall and sweet.\n'.encode('utf-8')
            else:
                body = WP.to_gemtext(ARTICLE, url).encode('utf-8')
                open(os.path.join(FILES, 'web.gmi'), 'wb').write(body)
            send('20 text/gemini; charset=utf-8', body)
        elif u.scheme != 'gemini':
            send('59 Not a gemini URL')
        elif path == '/cgi-bin/waffle.cgi/view':
            # (NewsWaffle's stand-in: the page's URL as the query)
            if u.query:
                body = ('# NewsWaffle\nThe page: %s\n' % urllib.parse.unquote(u.query)).encode('utf-8')
                send('20 text/gemini', body)
            else:
                send('10 Enter URL of news site')
        elif path.startswith('/cgi-bin/wp.cgi/media/'):
            # (V138: Gemipedia's ProxyMedia: the query UrlDecode'd is the
            # Wikimedia address; MediaProcessor passes an opaque JPEG as it is)
            q = urllib.parse.unquote_plus(u.query)
            log('WP media %s' % q)
            if urllib.parse.urlsplit(q).hostname not in ('upload.wikimedia.org',):
                send('51 cannot fetch media')
            else:
                kind = [k for w, _, k in GALLERY_PICS if w == q]
                if kind and kind[0] == 'jpeg':
                    send('20 image/jpeg', JPEG)
                elif kind:
                    data = png_ref.make(kind[0])
                    open(os.path.join(FILES, 'media-%s.png' % kind[0]), 'wb').write(data)
                    send('20 image/png', data)
                else:
                    send('51 Not in the stand-in')
        elif path == '/cgi-bin/wp.cgi/images':
            body = gallery(CLOSED_PORT[0]).encode('utf-8')
            open(os.path.join(FILES, 'gallery.gmi'), 'wb').write(body)
            send('20 text/gemini;lang=en', body)
            REFUSE.set()
        elif path.startswith('/cgi-bin/wp.cgi'):
            # (V128: Gemipedia's stand-in, as its RouteHandler answers)
            route = path[len('/cgi-bin/wp.cgi'):].strip('/').split('/')
            lang = route[1] if len(route) == 2 else 'en'
            q = urllib.parse.unquote_plus(u.query)
            log('WP %s %s %s' % (route[0] or 'welcome', lang, q))
            base = '/cgi-bin/wp.cgi/%s' + ('' if lang == 'en' else '/' + lang)
            if route[0] == 'view' and not u.query:
                send("10 Article Name? (doesn't need to be exact)")
            elif route[0] == 'view' and (lang, q) in WIKI:
                body = WIKI[(lang, q)].encode('utf-8')
                open(os.path.join(FILES, 'wiki-%s-%s.gmi' % (lang, q.replace(' ', '_'))), 'wb').write(body)
                send('20 text/gemini;lang=%s' % lang, body)
            elif route[0] == 'view':
                send('30 %s?%s' % (base % 'search', urllib.parse.quote_plus(q)))
            elif route[0] == 'search' and u.query:
                body = ("Articles containing '%s'.\n=> %s?%s 1. Nothing (disambiguation)\n"
                        % (q, base % 'view', urllib.parse.quote_plus('Nothing (disambiguation)'))).encode('utf-8')
                open(os.path.join(FILES, 'wiki-search.gmi'), 'wb').write(body)
                send('20 text/gemini;lang=%s' % lang, body)
            else:
                send('51 Not in the stand-in')
        elif path in ('/', '/sub/page.gmi'):
            body = page(port, path).encode('utf-8')
            open(os.path.join(FILES, 'root.gmi' if path == '/' else 'sub.gmi'), 'wb').write(body)
            send('20 text/gemini; lang=en', body)
        elif path == '/input':
            if u.query:
                body = ('# Hello\nHello, %s!\n' % urllib.parse.unquote(u.query)).encode('utf-8')
                open(os.path.join(FILES, 'hello.gmi'), 'wb').write(body)
                send('20 text/gemini', body)
            else:
                send('10 What is your name?')
        elif path == '/secret':
            if u.query:
                send('20 text/gemini', ('# Secret\nReceived %d characters.\n' % len(urllib.parse.unquote(u.query))).encode())
            else:
                send('11 A password, please')
        elif path == '/redirect':
            send('30 sub/page.gmi')
        elif path == '/moved':
            send('31 gemini://localhost:%d/sub/page.gmi' % port)
        elif path == '/loop':
            send('30 /loop')
        elif path == '/cert':
            send('60 This capsule needs a certificate')
        elif path == '/plain.txt':
            body = PLAIN.encode('utf-8')
            open(os.path.join(FILES, 'plain.txt'), 'wb').write(body)
            send('20 text/plain; charset=utf-8', body)
        elif path == '/latin1.gmi':
            body = LATIN1.encode('latin-1')
            open(os.path.join(FILES, 'latin1.gmi'), 'wb').write(body)
            send('20 text/gemini; charset=ISO-8859-1', body)
        elif path == '/big.bin':
            send('20 application/octet-stream')
            for i in range(0, len(BIG), 1024):
                c.sendall(BIG[i:i + 1024])
                time.sleep(0.01)
        elif path == '/pics.gmi':
            body = PICPAGE.encode('utf-8')
            open(os.path.join(FILES, 'pics.gmi'), 'wb').write(body)
            send('20 text/gemini', body)
        elif path.startswith('/pic/') and path[5:-4] in PNGS:
            send('20 image/png')
            data = PNGS[path[5:-4]]
            for i in range(0, len(data), 2048):
                c.sendall(data[i:i + 2048])
                time.sleep(0.005)
        elif path.startswith('/pic/') and path[5:-4] in JPGS:
            send('20 image/jpeg', JPGS[path[5:-4]])
        elif path == '/t/page.gmi':   # (V211) gate gemini's timing session: a page of 28 KB
            send('20 text/gemini', TPAGE)
        elif path == '/t/big.bin':    # (V211) 200 KB, sent at once
            send('20 application/octet-stream', TBIN)
        elif path == '/t/big.jpg':    # (V211) jpeg_ref's big (3200 x 2000, 192 KB), sent at once
            send('20 image/jpeg', jpeg_ref.make('big'))
        elif path == '/slow':
            send('20 text/gemini', SLOW.encode('utf-8'))
            time.sleep(120)
        else:
            send('51 Not found here')
    except OSError as e:
        log('ERR ' + str(e))
    finally:
        try:
            c.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass
        c.close()
        log('CLOSED')


def listener(port=0):
    s = socket.socket()
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(('127.0.0.1', port))
    s.listen(8)
    s.settimeout(0.01)
    return s


def refusals(port):
    # (the emulator's modem logs "ERROR connect 127.0.0.1:<port>: Connection refused")
    try:
        t = open(os.path.join(os.path.dirname(D), 'modem.log'), encoding='latin-1').read()
    except OSError:
        return 0
    return t.count('ERROR connect 127.0.0.1:%d:' % port)


def main():
    s = listener()
    port = s.getsockname()[1]
    t = socket.socket()
    t.bind(('127.0.0.1', 0))
    closed = t.getsockname()[1]
    t.close()
    CLOSED_PORT[0] = closed
    open(os.path.join(D, 'ready.tmp'), 'w').write('%d %d\n' % (port, closed))
    os.rename(os.path.join(D, 'ready.tmp'), os.path.join(D, 'ready'))
    while True:
        if REFUSE.is_set():
            # (V138: not listening until one connection has been refused, 60 s at most)
            REFUSE.clear()
            n = refusals(port)
            s.close()
            log('REFUSING')
            t0 = time.time()
            while refusals(port) == n and time.time() - t0 < 60:
                time.sleep(0.005)
            s = listener(port)
            log('LISTENING')
        try:
            c, _ = s.accept()
        except socket.timeout:
            continue
        threading.Thread(target=serve, args=(c, port), daemon=True).start()


main()
