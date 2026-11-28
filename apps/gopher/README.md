# Veranda Gopher

A Gopher reader for Veranda (DECISIONS V109), through the Wi-Fi modem of
TexElec's "Serial & ESP32 Network Card" (Zimodem; the SDK's `vrnet`,
`docs/NET.md`).

Gopher (RFC 1436) is the internet of menus and plain text from before the
web: a server sends a menu, one item a line, and each item is another
menu, a text, a search or a file. Veranda Gopher shows menus and texts in
its window and saves files to `/DOCUMENTS`.

## Using it

- **The address line** at the top takes an address such as
  `gopher://gopher.floodgap.com/1/world`, or just a host name. Click it
  (or press Tab or Ctrl+L, or start typing), type, press Return or click
  **Go**. Ctrl+V pastes the clipboard's text. Esc leaves it.
  The form is `gopher://host[:port]/Tselector`: T is the kind of item
  (1 a menu, 0 a text, 7 a search ...), the port 70 when it is left out;
  `%09` in a search's address puts the query after it.
- **Menus** show a badge before each item, its kind's picture on its
  kind's colour: a folder (yellow) a menu, a page (blue) a text (grey a
  document), a magnifier (green) a search, `10 01` a binary or an
  archive, a picture (orange) a picture or a film, a note (purple) a
  sound, a globe a web link, a screen a telnet session, a warning sign
  (red) an error from the server; lines without a badge are information. **Click an item**
  to follow it (Shift+click only selects it), or select it with Up and
  Down and press Return.
- **A search** asks for the words in a box.
- **A file** (a binary, a picture, a sound ...) asks whether to download
  it to `/DOCUMENTS`; **File > Download** downloads the selected item (or
  the text shown) without asking. The status bar shows the bytes and the
  speed; **Stop** (the toolbar's button, File > Stop or Esc) stops it, and
  a file that did not arrive whole is deleted.
- **A web link** shows its address in a box (there is no web browser on
  the X16); a telnet item names its host and port (Veranda Term can open
  it).
- **Back and Forward** (the toolbar's arrows, dotted when there is
  nowhere to go; the Go menu, Left and Right, Backspace) move through the
  last 16 pages; each is fetched again and shown where you left it.
  **Reload** (Ctrl+R, or Go when nothing is coming) fetches the page
  again. **Home** (the toolbar's house, Go > Home) is the bookmarks page.
- **Scrolling:** the wheel, the scroll bar (its arrows a line, held down
  to repeat; the track a page; the thumb dragged), PgUp, PgDn, Home,
  End; Up and Down move from item to item in a menu, a line at a
  time in a text.
- **Bookmarks:** the bookmarks page is where Veranda Gopher starts.
  **Bookmarks > Add this page** adds the page shown; **Remove...** removes
  the bookmark selected on the bookmarks page.

The main loop never waits for the network: a page is drawn as it comes,
menus work while it comes, and **Alt+Tab** puts Veranda Gopher aside
during a download (the connection stays open in the modem; the file goes
on when you come back). Network errors (no network card, no modem, a
connection refused, a server that stops sending for 30 seconds) are
shown in a box.

## GOPHER.MARKS

The bookmarks are in `GOPHER.MARKS` in the system's folder,
`/VERANDA/.SYSTEM`. It is a Gopher menu, one item a line, as a server
sends one:

    Tname<TAB>selector<TAB>host<TAB>port

(T the kind of item). It can be written on a PC too (CR LF or LF line
ends); lines that are not items are skipped. When it is not there, the
bookmarks are a few well-known public servers (Floodgap, its Veronica-2
search, Quux.org, SDF, Bitreich); the file is written when you add or
remove one. 16 bookmarks at most.

## The look

Veranda Look 3 "Sunroom" (DECISIONS V149): the SDK's window, its title
band with a square close box (it quits), a toolbar of square buttons, a
status bar, the SDK's scroll bar (arrow boxes, the track, a gripped
thumb), menus grouped with dotted separators and their keys at the
right, the theme's colours, dark mode as Preferences sets it. The page
is the X16's own 8 x 8 CP437 font in taller lines, with an 8-pixel
margin each side: a text's lines are 12 pixels apart (34 a page, 76 columns,
a fixed grid for ASCII art), a menu's 16 (25 a page: each line is two
of the colour map's card rows, so its badge and the selection have
their own colours). CP437's line and block characters are drawn into
the gap between lines, so boxes and pictures made of them stay joined.

## Limits

- A page keeps 64 KB (8 RAM banks) and 4,000 lines; a longer one is cut,
  and says so at its end (File > Download saves all of it).
- Text is UTF-8, or Latin-1 where a byte is not UTF-8, shown in
  Veranda's set, ISO-8859-16 (DECISIONS V143: Polish and the other
  Latin-10 letters as they are; box lines and blocks as CP437's glyphs;
  typographic quotes and dashes plain; what it lacks `?`). A page in
  CP437 itself is no longer shown as CP437.
- Lines are 76 columns: a text is wrapped at its spaces, a menu item's
  text is cut (at 73).
- No Gopher+ (its extra fields are ignored), no TLS, no web pages.
- One thing at a time: a page or a download.

## Memory

Main RAM about 28.7 KB (vrnet and the serial driver 8.3 KB of it),
overlay 1 (the interface) 7.0 KB, overlay 2 (the bookmarks, the window
chrome, the scroll bar) 7.9 KB; 8 RAM banks (the page, its line starts, the history and
the font laid out for drawing) and vrnet's 2. It runs on the 512 KB X16.

## Credits

The modem's driver is the SDK's `vrnet` (DECISIONS V98), whose Zimodem
client comes from Packet16, Marcin Spoczynski's FTP client for the X16
(MIT, with his permission).

MIT licence (see LICENSE).
