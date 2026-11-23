# Veranda Gemini

A Gemini browser for Veranda (DECISIONS V118, V124, V125, V128), through the Wi-Fi modem of
TexElec's "Serial & ESP32 Network Card" (Zimodem; the SDK's `vrnet`,
`docs/NET.md`).

Gemini is a small protocol for small pages ("capsules"): one TLS
connection a request to port 1965, the page's address sent, a one-line
header back (a status and a MIME type), then the page. Its pages are
*gemtext*: plain lines of text, one link a line, a few headings, lists,
quotes and preformatted blocks. Veranda Gemini shows them in its window,
answers a capsule's questions, follows its redirects and saves other
files to `/DOCUMENTS`.

## Using it

- **The address line** at the top takes an address such as
  `gemini://geminiprotocol.net/docs/`, or just a host name
  (`geminiprotocol.net`). Click it (or press Ctrl+L, or start typing),
  type, press Return or click **Go**. Ctrl+V pastes the clipboard's text;
  Esc leaves it.
- **Pages:** headings are underlined (the first level on the title bars'
  colour, the second on the sidebar's), list items have a bullet, quotes
  a bar, preformatted text keeps its columns (it is not wrapped: a line
  wider than the window is cut), paragraphs are wrapped to the window.
  Unicode is shown in Veranda's set, ISO-8859-16 (DECISIONS V143: the
  ROM's own 8 x 8 glyphs of it; Polish, German, French, Hungarian,
  Romanian ... letters as they are), box lines and blocks as CP437's
  glyphs, typographic quotes and dashes as plain ones, other letters
  without their accents, and anything else (an emoji) as `?`.
- **Links** have a badge before them: an arrow (cyan) for a Gemini link,
  a globe for the web, a folder (yellow) for Gopher, an envelope (purple)
  for mail, a picture (orange) for an image, a grey one for anything else.
  **Click a link** to follow it (Shift+click only selects it), or move
  from link to link with **Tab** (Shift+Tab back) and press **Return**.
  A **web link** (http or https) can be read as gemtext through
  NewsWaffle or your own proxy (see *Web pages* below). A Gopher or mail
  link shows where it leads in a box (Veranda Gopher opens Gopher
  addresses).
- **A capsule's question** (a search, a name ...) is asked in a box; the
  answer is sent as the page's query. A "sensitive" question (a
  password) is asked the same way: the box shows what you type.
- **Redirects** are followed (5 at most); one to another host asks first.
- **Plain text** pages (`text/plain` and other text types) are shown as
  text, wrapped at 76 columns. **Any other file** (a picture, an archive
  ...) asks whether to download it to `/DOCUMENTS`; **File > Download**
  downloads the selected link (or the page shown) without asking. The
  status bar shows the bytes and the speed; **Stop** (the toolbar's
  button, File > Stop or Esc) stops it, and a file that did not arrive
  whole is deleted.
- **Back and Forward** (the toolbar's arrows, the Go menu, Left and Right,
  Backspace) move through the last 14 pages; the last three pages (each
  up to 7.7 KB) are kept in RAM and come back at once, others are fetched
  again; each is shown where you left it. **Reload** (Ctrl+R, or Go when
  nothing is coming) fetches the page again. **Home** (the toolbar's
  house, Go > Home) is the bookmarks page.
- **Find** (File > Find..., Ctrl+F) looks for a word in the page (on one
  row: a word wrapped across two rows is not found); **Find again**
  (Ctrl+G) looks for the next one.
- **Scrolling:** the wheel, the scroll bar (its arrows a row, held down
  to repeat; the track a page; the thumb dragged), Up, Down, PgUp,
  PgDn, Home, End.
- **The look** (Veranda Look 3 "Sunroom", DECISIONS V149): the SDK's
  window with a square close box (it quits), square toolbar buttons,
  the SDK's scroll bar, menus grouped with dotted separators and their
  keys at the right; the page has an 8-pixel margin each side (gemtext
  73 columns, plain and preformatted text 76).
- **Bookmarks:** the bookmarks page is where Veranda Gemini starts.
  **Bookmarks > Add this page** adds the page shown (named by its first
  heading); **Remove...** removes the bookmark selected (Tab) on the
  bookmarks page.

A page is shown as it comes; the main loop never waits for the network,
so menus work while it comes and **Alt+Tab** puts Veranda Gemini aside
during a download (the connection stays open in the modem; the file goes
on when you come back). Network errors (no network card, no modem, a
connection refused, a server that stops sending for 30 seconds) and a
capsule's errors (4x temporary failures, 5x such as 51 "Not found", 6x
"a client certificate is needed") are shown in a box. A connection that
fails before the server has sent anything is tried once more a second
later ("Trying gemi.dev again ..."); if that fails too, the box says why
and which address it was (the modem's own errors by their number, so a
report can say which). Each connection is hung up in the modem (ATH)
before the next one is made: the modem keeps a closed connection's TLS
client until then (DECISIONS V138).

## Web pages

The X16 has no web browser, but Veranda Gemini can show ordinary web
pages turned into gemtext (text, headings, lists and links; no styling,
no scripts, pictures as links). Following an `http://` or `https://`
link (a click, or Return), or typing such an address in the address
line, asks once for that link:

- **Yes: through NewsWaffle** (gemi.dev's free public service);
- **No: through my proxy** (a small program on your own PC);
- **Cancel**: neither.

**File > Settings...** changes this: type **0** to ask each time (the
default), **1** always NewsWaffle, **2** always my proxy, **3** never
(web links then only say where they lead), or nothing to keep it; the
next box takes your proxy's address, `host:port` (port 1965 when you
give none; empty: no proxy), the third the largest picture shown without
asking, in KB, the last Wikipedia's language (see *Wikipedia* below). On
a page that came through your proxy, its links go through it again
without asking. The settings are kept in `GEMINI.CFG` in
`/VERANDA/.SYSTEM` (lines `web=0`, `proxy=192.168.1.20:1965`,
`pictures=256`, `wplang=en`, `waffle=...`: another NewsWaffle's view
address can be named there; `wiki=...`: another Gemipedia's).

**NewsWaffle** (`gemini://gemi.dev/cgi-bin/waffle.cgi`, by Acidus; it is
also among the default bookmarks) fetches the page for you and sends it
back as gemtext; it is best for articles and news sites. Veranda Gemini
asks for `gemini://gemi.dev/cgi-bin/waffle.cgi/view?<the page's URL,
percent-encoded>`, as NewsWaffle's own links do. It is a third-party
service, free and run by one person: **it sees every page you read
through it**, and it may be slow, change or go away.

**Your own proxy**: copy `PC/web_proxy.py` from the card to a PC on the
same network (Python 3, nothing to install) and run

    python3 web_proxy.py

It makes a self-signed certificate the first time (with the `openssl`
program; without it, it says how to make one), listens on port 1965
(`--port` for another) and takes requests only from private (LAN)
addresses. Then File > Settings..., 2 (or 0), and the PC's address.
Veranda Gemini sends it the web page's URL as the request line (a
standard Gemini proxy request); the proxy fetches the page as a desktop
browser would (redirects followed), keeps the part with the most text
(the article), drops scripts, menus, headers, footers, sidebars and
forms, numbers each paragraph's links and lists them after it, and cuts a
page at 64 KB. Text files pass as they are; pictures and other files
come as files (Veranda Gemini offers to save them). Its own pages:
`gemini://<the PC's address>/` a start page, `/search` a search through
DuckDuckGo, `/go` a web address asked. Each request is logged on one
line. Other Gemini proxies take the same requests:
[Duckling](https://github.com/LukeEmmet/duckling-proxy) and
levior work too (give their
host:port; plain-text versions without TLS will not do: the modem always
speaks TLS).

## Security: TLS by the modem

Gemini always uses TLS. The X16 cannot do TLS itself: the modem does it
(Zimodem's `ATCS"host:1965"`: the ESP32's `WiFiClientSecure`, as Veranda
Claude uses it, DECISIONS V114), and **it does not check the capsule's
certificate**. Gemini's usual "trust on first use" (remembering each
capsule's certificate) is not possible either: the X16 never sees the
certificate. So someone on your network or on the way could pose as a
capsule. Do not type anything secret into a capsule's questions. Client
certificates (status 6x) are not supported. Your firmware must have
`ATCS` (Term's `ATI` shows its version); this was gated against the
emulator's modem, not tried on the card.

## GEMINI.MARKS

The bookmarks are in `GEMINI.MARKS` in the system's folder,
`/VERANDA/.SYSTEM`. It is gemtext, one link a line:

    => gemini://geminiprotocol.net/ Project Gemini

and can be written on a PC (CR LF or LF; lines that are not links are
skipped; 16 at most). When it is not there, Veranda Gemini starts with
Project Gemini (`geminiprotocol.net`), the Kennedy search engine
(`kennedy.gemi.dev`), `geminispace.info`'s search, the Antenna feed
(`antenna.flounder.online`), `gemi.dev`, NewsWaffle
(`gemi.dev/cgi-bin/waffle.cgi`), Gemipedia (`gemi.dev/cgi-bin/wp.cgi/`)
and Gemipedia's featured articles; the first four were written from
memory and **not checked against the live capsules**. The package does
not install a GEMINI.MARKS: these are what Veranda Gemini starts with
when there is none, so a file of your own is never replaced. If you have
one already, add the gemi.dev lines yourself:

    => gemini://gemi.dev/ gemi.dev
    => gemini://gemi.dev/cgi-bin/waffle.cgi NewsWaffle: web pages as gemtext
    => gemini://gemi.dev/cgi-bin/wp.cgi/ Gemipedia: Wikipedia
    => gemini://gemi.dev/cgi-bin/wp.cgi/featured Wikipedia: featured articles

(For Polish Wikipedia's front page and featured articles:
`gemini://gemi.dev/cgi-bin/wp.cgi/welcome/pl` and
`gemini://gemi.dev/cgi-bin/wp.cgi/featured/pl`.)

## Wikipedia

Veranda Gemini reads Wikipedia through **Gemipedia**
(`gemini://gemi.dev/cgi-bin/wp.cgi/`), a free public Gemini front end to
Wikipedia by Acidus, NewsWaffle's author: articles as gemtext (sections,
lists, links to other articles, the references on a page of their own).

- **The Wikipedia icon** (a W on a globe, in `/VERANDA/APPS`): a
  double click starts Veranda Gemini at the question **"Look up in
  Wikipedia:"**. Type a title (it need not be exact) and press Return.
- **Go > Wikipedia...** (Ctrl+W) asks the same at any time.
- **In the address line**, `wp Ada Lovelace` or `w Ada Lovelace` looks
  it up; `wp` alone asks.
- **The language:** File > Settings..., the last question: a code such
  as `en` (the default), `pl`, `de`, `fr` or `simple` (Simple English);
  empty keeps it. The question's box then says it: "Look up in Wikipedia
  (pl):". Kept as `wplang=` in `GEMINI.CFG`.

Veranda Gemini asks Gemipedia for its article address with what you
typed as the query, `gemini://gemi.dev/cgi-bin/wp.cgi/view?Ada%20Lovelace`
(another language: `.../wp.cgi/view/pl?Warszawa`); when there is no such
article, Gemipedia sends you on to its search for the words. These are
the forms Gemipedia's own pages use (its source, github.com/acidus99/
Gemipedia at commit 00e7863: `Gemipedia.Cgi/Program.cs` and
`Gemipedia/RouteOptions.cs`); not tried against gemi.dev from the tests.
Gemipedia is a third-party service run by one person: it sees what you
look up, and it may be slow, change or go away.

The icon is a small document (`Wikipedia.cvt`, of Veranda Gemini's: its
parent application's class is Veranda Gemini's), holding the line `wp`:
Veranda Gemini types a document's first line into its address line when
it starts with one.

## Pictures

A link to a picture (its address's path ends `.png`, `.jpg`, `.jpeg`,
`.gif` or `.bmp`, before any `?`: the orange picture badge) has
**[Show image]** after its label. Gemipedia's pictures are such links
(`/cgi-bin/wp.cgi/media/media.jpg?<the Wikimedia address>`), and so are
the pictures in its image galleries. Any other link that turns out to be
a picture (the capsule answers `image/png`, `image/jpeg` ...) is treated
as one too: a PNG is shown, the others offer to be saved.
**Click it** to see the picture; with the keyboard, Tab to it and press
**Return**: a box asks **Yes** show it, **No** save it to `/DOCUMENTS`,
**Cancel**. While it comes the status bar says what it is
(`image/png`), its bytes and, once its header has come, its size
(`PNG 740 x 300`). A picture larger than the limit in File >
Settings... (256 KB at first) stops, and a box offers to save it
instead.

Veranda Gemini shows **PNG** pictures: every colour type and bit depth
(16-bit ones by their high byte), transparency laid over white. It
decodes them itself, a slice at a time (the menus wait while it draws;
Esc stops), and shows them in the window's page area in 16 colours
through VERA's tiles: scaled to fit (624 x 408 pixels, at most 912
tiles of 8 x 8, never more than twice its size; a box filter across, the
nearest row down), with a 4 x 4 ordered dither. The 16 colours are the
picture's own when it has a palette of 16 or fewer; 16 greys for a grey
picture (or a palette of greys); otherwise a fixed set (2 reds x 4
greens x 2 blues), so photographs look posterised. A 740 x 300 grey
picture (40 KB) takes about 29 seconds at 8 MHz, small ones a second or two
(DECISIONS V125).
**Esc**, Backspace or the toolbar's Back go back to the page;
**Save** (the toolbar's button where Go is, or S) copies the picture to
`/DOCUMENTS`. Alt+Tab while it is drawn: it is drawn again when you come
back.

Not shown: interlaced PNGs (they say so; save them), pictures wider
than 4,864 bytes a row (1,216 pixels of RGBA, 4,864 of grey), JPEG
("JPEG can't be shown here: save it, or use the private proxy"), GIF,
BMP and the others (save them). The private proxy (`web_proxy.py`)
turns JPEG, GIF, WebP and BMP into PNG (scaled to the page) when Pillow
is installed on the PC (`pip install pillow`); without it the picture
passes as it is. The picture is kept while shown in
`/VERANDA/.SYSTEM/GEMINI.TMP` (deleted after).

## Limits

- A page is kept up to 32 KB (2,730 rows); a longer one is cut (the
  connection closed) and ends with a "Cut here" note; File > Download
  saves all of it.
- A URL is at most 255 characters (Gemini allows 1,024), except a
  link followed from a page, which may be up to about 360 (its first 128
  characters resolved, the rest sent as it is on the page: Gemipedia's
  links to photographs with long names are 250-300); host names are
  letters, digits, dots and dashes (no IPv6 addresses, no international
  names).
- JPEG pictures are not shown (most of Wikipedia's photographs: Gemipedia
  passes them as they are; its flags, maps and diagrams come as PNG):
  save them, or use the private proxy with Pillow.
- No TOFU, no client certificates; pictures only on their own (PNG);
  Unicode as CP437 (common emoji and symbols as short ASCII: ⏩ `>>`,
  ⏪ `<<`, 🎲 `*`, arrows, bullets, ✓; others `?`).

## How it is built

`main.c`, `net.c`, `doc.c` and `copy.s` (Veranda Gopher's text cells)
are in main RAM with vrnet; `ui.c` is overlay 1 (mapped for good),
`marks.c` and `box.c` overlay 2, `url.c` overlay 3,
`web.c` (web pages, the settings), `wiki.c` (Wikipedia), `pic.c` and
`pngplan.c` (the picture viewer) overlay 4, `png.c` and `pngcore.s` (the PNG decoder: inflate after
Commander Calc's `inflate.c`, in assembly) overlay 5, `tool.c` (the
toolbar) with the SDK's window chrome and scroll bar overlay 6. Seven RAM banks:
the page (4), its rows (1), the history and the font (1), a page cache
bank (1; its other two are the spare banks the loader gives banked
overlays besides theirs); vrnet 2 more and the overlays 6: 15 in all, so
Alt+Tab works on a 512 KB machine. A picture needs no more banks: the
decoder's window is in VRAM's back screen. `make` builds `Gemini.cvt`
and the Wikipedia launcher, `Wikipedia.cvt` (`tools/vpack.py --doc
wiki.hdr`: its icon `wiki.pbm`, its tile `wikitile.txt`), against the
SDK; `tools/gate_gemini.sh` tests it in the emulator against a small
Gemini server (`tests/gemini_server.py`, also NewsWaffle's, Gemipedia's
and the proxy's stand-in and the pictures' server), the launcher
double-clicked in the real shell, `tools/web_proxy.py` on
the host with sample pages (`tests/test_web_proxy.py`, `tests/web/`) and
the decoder on the host (`tests/png_host.c`) against a reference in
Python (`tests/png_ref.py`).

MIT licence (see `LICENSE`).
