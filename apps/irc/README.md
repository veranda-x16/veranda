# Veranda Chat

An IRC client for Veranda (DECISIONS V111), through the Wi-Fi modem of
TexElec's "Serial & ESP32 Network Card" (Zimodem; the SDK's `vrnet`,
`docs/NET.md`).

IRC (Internet Relay Chat, RFC 1459 and 2812) is chat in channels
(`#name`) and private conversations, one server at a time. Veranda Chat
shows the server's messages, each channel and each private conversation
as a tab, with the channel's people beside it.

## Using it

- **Servers** (Server > Servers..., shown at the start): the saved
  servers, and the selected one's fields: name, host, port, nick, an
  alternative nick (used when the nick is taken; then the nick with `_`
  added), real name, password (the server's, `PASS`: a bouncer, or a
  registered nick on servers that take it so) and the channels joined
  when connected (`#retro #x16`). Tab, Down and Up move between the
  fields; PgUp and PgDn choose a server; **Connect** (or Return, or a
  double click) connects; **New** and **Delete** add and remove one;
  Esc closes the page. The first time: Libera.Chat, SDF and EFnet.
- **The tabs** at the top: the server's window, then up to six channels
  and private conversations. A click (or F1-F7, Ctrl+N and Ctrl+P) shows
  one; Ctrl+W closes it (Ctrl+Q quits the program). `*` after a name: new lines; `!`: a line that names you, or a new
  private message. A tab in brackets `(` is a channel you are not in
  (kicked).
- **The topic** is the line under the tabs.
- **The text**: lines of 12 pixels, wrapped at a space (the rest
  indented), with the time (Window > Times on/off). A line that names
  you is shown reversed, with the system's sound. PgUp, PgDn, the
  wheel and the scroll bar at its right (Sunroom's: an arrow a row, the
  track a page) scroll back; End or Esc goes back to the newest.
- **The nick list** at the right of a channel: operators (`@`), voices
  (`+`), then the rest by name; the wheel over it and its own scroll
  bar scroll it; a click on a nick puts it in the input line. Window >
  Nick list on/off.
- **The input line** at the bottom: type and press Return. Left, Right,
  Home, End, Backspace and Delete edit it; Up and Down bring back the
  last 8 lines; **Tab** completes a nick of the channel (again for the
  next one; `nick: ` at the start of the line); Ctrl+V pastes the
  clipboard's first line. A long line is sent in pieces that fit IRC's
  512 bytes, cut at a space.
- **Commands:** `/join #channel [key]`, `/part [reason]`, `/msg nick
  text`, `/query nick [text]` (a tab for it), `/me action`, `/nick new`,
  `/topic [text]`, `/notice nick text`, `/raw line` (or `/quote`),
  `/close` (leaves a channel, closes a conversation), `/clear`, `/quit
  [reason]`, `/help`. Any other command is sent as it is (`/whois nick`,
  `/mode`, `/names`, `/away`). `//text` sends a line that starts with `/`.
- Server > Disconnect sends QUIT; Veranda Chat > Quit too.

Lines from the server are cleaned for the X16's font: IRC's bold,
colours, italics and the like are taken out; UTF-8 is decoded: the
Latin-1 letters (é, ü, ñ ...) are shown as they are, the other European
letters as their base letter (ł as l, ś as s), curly quotes and dashes as
`'` `"` `-`, the rest as `?`; a line that is not UTF-8 is read as Latin-1.
What you type (Latin-1 from the X16's keyboard) is sent as UTF-8.
CTCP VERSION and PING are answered; ACTION is shown as `* nick text`.

**The network.** The main loop never waits: lines come and go while you
type, menus and boxes work. **Alt+Tab** puts Veranda Chat aside with the
connection kept open in the modem, which holds what arrives meanwhile;
it comes in when you come back. Away for long, the server may drop you
(its PING unanswered): the box says so when you come back. With nothing
from the server for 3 minutes Veranda Chat sends a PING, after 5 it gives
the connection up. Errors (no network card, no modem, a connection
refused, the server closing it, with its reason) are shown in a box.

## CHAT.SERVERS

The servers are in `CHAT.SERVERS` in the system's folder,
`/VERANDA/.SYSTEM`, one a line:

    name,host,port,nick,alternative nick,real name,password,channels

Plain text, so it can be written on a PC too (CR LF or LF); a field
cannot hold a comma; the channels by spaces. The password is kept as
plain text. 8 servers at most.

## Limits

- One server at a time; the server's window and 6 channels or
  conversations.
- A window keeps the last 4 KB of its lines (about 50 lines; the oldest
  go); a channel lists the first 190 people it hears of, the list's last
  row "and N more" the rest; the status bar counts them all (a QUIT of
  one not listed cannot be told apart from one in another channel, so
  on a big channel the count may stay a little high).
- A line from the server longer than 520 bytes (IRC allows 512; IRCv3
  tags at its start are left out first) is cut.
- Plain connections only (port 6667): there is no TLS on the X16, so a
  server or network that wants TLS (or SASL) cannot be used. No DCC.
- The X16's font is ISO-8859-1: other scripts (Cyrillic, Greek, CJK,
  emoji) show as `?`.
- Lines are not paced: pasting many lines quickly may let the server
  disconnect you for flooding.

## Memory

Main RAM about 29.4 KB (vrnet and the serial driver 8.1 KB of it);
overlay 1 (the interface) 7.7 KB, overlay 2 (IRC) 8.0 KB, overlay 3 (the
servers) 7.7 KB, overlay 4 (the commands, the window chrome, the font's
loading) 7.9 KB, overlay 5 (the scroll bars, the menus, the tabs) 3.9 KB; 7 RAM banks
(the scrollbacks, the nick lists and topics, the history) and vrnet's
2. It runs on the 512 KB X16, and Alt+Tab can put
it aside there.

## Credits

The modem's driver is the SDK's `vrnet` (DECISIONS V98), whose Zimodem
client comes from Packet16, Marcin Spoczynski's FTP client for the X16
(MIT, with his permission).

MIT licence (see LICENSE).
