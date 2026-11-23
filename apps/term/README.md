# Veranda Term

A terminal for Veranda: a serial card with a 16C550 UART on the X16's
expansion bus, a Wi-Fi modem behind it (Zimodem or another ESP firmware:
AT commands, then Telnet BBSes). MIT licence, Veranda's own code (no
geoTerm source exists; GEOS-W128's BBS client was read for its features
only).

## The window

Veranda's menu bar with the window's title in it (the BBS or the host:
Sunroom, DECISIONS V149); under it a card row of margin, 80 x 55 cells of
8 x 8 (`PutCards`, the X16 ROM's own CP437 font from ROM bank 6), a
status bar at the bottom in the UI font (`vr_win_status`): at its left
Offline/Dialling/Online and the online time (in a TCP session `TCP
host:port` first, with ", connecting" or ", closing"), Telnet or Raw TCP,
Local echo, Capture, Sending a file, the XMODEM block, "Back n of m" in
the scrollback, Lost and the bytes lost, fields apart by a gap; at its
right the UART's address (or Script) and the line. Its code is in
overlay 3 (`hosts.c`'s `o_status`, with the SDK's `vrwin.c` compiled
there). The 80 columns fill the screen's 640 pixels, so the scrollback
has no scroll bar (a 2-card bar would cost 2 columns, and NAWS reports
80). Menus, dialog boxes and desk accessories open over it and give it
back with its colours (the kernel's colour map polish, V33). Telnet's
NAWS reports 80 x 55.

The menus (Sunroom's lists, V146: groups, keys at the right):

| Menu | Items |
|---|---|
| Term | About Term; Desk accessory... (the port's interrupts are off and RTS down while it runs); Quit (Alt Q) |
| File | Capture on/off, Send text file... (raw); XMODEM download... (Alt X) |
| Connection | Connect... (a host over TCP, Telnet or raw: the Hosts page, below), Dial... (Alt D: host:port, or an AT command as it is), Address book; Disconnect / hang up (Alt H: a TCP session's ATH; else +++, ATH0); Modem status (the status commands), Clock from network |
| Options | Settings...; Clear screen, Copy screen (the window's text on the clipboard, the Text Scrap: a row a line, trailing spaces dropped, non-ASCII as `?`; DECISIONS V54) |

The pages (settings, the address book, the hosts) have a heading in the
UI font (bold), a line of help and a rule; the lists' column heads in
bold, their rows 16 lines high in the window's cells, the chosen one
inverted; the settings in three groups.

Keys: everything goes to the host (arrows, Home, End, Insert, Delete and
F1-F4 as VT100/xterm sequences; Ctrl + a letter its control code; STOP
Ctrl-C; Backspace BS or DEL, a setting). PgUp and PgDn move through the
scrollback (816 lines in 16 RAM banks), any other key comes back. F7 is
the session menu (D hang up, X download, C capture, Q quit), Alt+D dial,
Alt+H hang up, Alt+X download, Alt+Q quit.

## Connect to a host (TCP, DECISIONS V112)

Connection > Connect... opens the Hosts page in the window: up to 11
hosts, each with a name, `host:port` and a mode, **Telnet** or **raw**
TCP. 1-9, A, B or Up/Down choose one, Return connects; **C** connects to
another host (three boxes: the host, letters, digits, `.` and `-`; the
port, 23 by default; T or R), **N** adds one (a name first; the list is
written at once), **X** removes the chosen one, Esc goes back. The list
is `TERM.HOSTS` in /VERANDA/.SYSTEM (as FTP.SITES and GOPHER.MARKS), a
line `name|host:port|telnet` or `...|raw` each, CR LF (LF read too);
missing, it starts with five well known hosts, written from memory and
**not checked from here**: Vertrauen (vert.synchro.net:23, Synchronet's
home BBS), Level 29 (bbs.fozztexx.com:23), Black Flag
(blackflag.acid.org:23), Telehack (telehack.com:23) and NIST's daytime
service (time.nist.gov:13, raw).

**Telnet:** Term answers the options itself: DO ECHO and SGA when the
host offers them (character at a time, the host echoing), WILL
TERMINAL-TYPE (IS `ANSI`), WILL NAWS (80 x 55), BINARY both ways when
asked, anything else refused (DONT, WONT); a request for what is already
so is not answered (no loops). IAC sequences never reach the screen, a
received IAC IAC is one 0xFF, and every 0xFF sent is doubled; NVT's CR
NUL is taken as CR unless BINARY is on. **Raw:** the bytes as they are,
both ways.

**How:** not with `ATDT`: Zimodem reads the letters after `ATD` as
modifiers, and `T` is its own Telnet translation (it answers the options
itself and changes 0xFF bytes); its stream mode also ends on `+++`. The
session runs in the modem's command mode instead, as vrnet does
(docs/NET.md; after Packet16): Packet16's profile (`ATE0V1X1Q0&M&D`,
`ATS40=254S45=0S0=0`, `ATF3`, `ATH0`), `ATC"host:port"`, each packet
pulled with an XON and checked with its CRC-8, what Term sends in `ATT<n>`
packets; every byte arrives as it was sent. It is the one-connection
subset of vrnet in Term's overlay 2 (`tcp.c`), on Term's own serial
set-up: the port, the ring, the rate (found as before) and the interrupt
are not touched, so the serial terminal (Dial..., AT commands typed in
the window) works exactly as before. vrnet itself would cost 6 KB of
main RAM, which Term does not have. When the session ends (Disconnect,
the host closed it, it failed) Term sends `ATZ`: the modem gets its own
saved profile back (echo, flow control) for typing AT commands again.

**Boxes:** "Could not connect (refused, or no such host)" (the modem's
`ERROR` or `NO ANSWER`), "The modem does not answer" (no modem, or not a
Zimodem: the rates are tried again first), "No answer in 15 seconds",
"The host closed the connection" (Zimodem's `NO CARRIER` after the last
data), "The modem stopped answering"; no serial card: "There is no
serial card". Capture, Send text file and XMODEM download work over the
connection (in Telnet with 0xFF doubled both ways).

## ANSI on one ink

Veranda's screen has one ink colour and a paper colour per 8 x 8 card
(DECISIONS V30-V33), and a cell is exactly a card. So:

- **A black background** (40, or the default one in the "dark" scheme):
  the cell is drawn reversed, so the glyph shows in the paper colour and
  the card's paper is the foreground colour. Coloured text on black, as on
  a PC; bold or 90-97 give the bright colours (VERA's palette: red 2/10,
  green 5/13, yellow 9 (brown)/7, blue 6/14, magenta 4, cyan 3, white 15
  (light grey)/0 (white); black on black stays black, bold black is dark
  grey 11).
- **A coloured background** (41-47, 100-107): the card's paper is a light
  shade of it (10, 13, 7, 14, 4, 3, 15), the glyph in the ink (black); the
  foreground colour cannot be shown, bold is bold.
- **The default background** in the "light" scheme (the default): the
  normal paper, black text, the foreground colour not shown.
- **Reverse** (7) turns any of these over; underline and blink are not
  shown; 256 colours and RGB (38;5, 48;5 ...) are skipped.

Settings: ANSI colours off (black and white, reverse kept), scheme light or
dark.

Supported: the C0 controls, VT100 special graphics (`ESC ( 0`, SO/SI),
CP437 bytes 128-255 as they are, CUU/CUD/CUF/CUB/CNL/CPL/CHA/VPA/CUP,
ED and EL (`ESC[2J` homes the cursor, as ANSI.SYS), ECH, IL/DL, ICH/DCH,
SU/SD, DECSTBM, SGR, DSR (5, 6), DA, `?7` and `?25`, save and restore
(`ESC[s`, `ESC 7`), IND/RI/NEL/RIS; OSC and DCS strings are skipped.
Deferred: PETSCII mode (40 columns, PETSCII graphics: a second font and a
second parser), UTF-8, XMODEM upload, ZMODEM.

## The serial port

The driver is the SDK's (`vrser.h`: `vrser.s` and `vrserc.c` in
`veranda.lib`, the modem's rate `vrsync.c` compiled into overlay 2;
DECISIONS V98: Term's own `ser.s` and `ser_*` functions moved there, and
vrnet shares them). Its `SerIrq` is Veranda's `intFirstVector` (DECISIONS V41): every interrupt
reaches it first. It reads the UART's FIFO into an 8 KB ring in a RAM bank
and refills the transmit FIFO from a 256-byte ring, on VERA's line
interrupt (lines 60, 120 ... 420: with the frame's own, eight times a
frame). The UART itself never interrupts by default (IER 0: polled only,
as Packet16 runs on TexElec's card; DECISIONS V94); with settings/I on,
its own interrupt (received data at 8 bytes, timeout, THR empty; through
MCR OUT2, as on PC cards) brings it there too. RTS drops at 6 KB in the
ring and comes back below 2 KB.
The main loop takes the bytes, Telnet answers its options (ECHO, SGA,
BINARY, TERMINAL-TYPE "ANSI", NAWS), the capture file and XMODEM take
theirs, the screen the rest, and the screen is drawn when nothing else is
waiting (whole-window scrolls are joined into one `ScrollRect`).

Measured in the emulator (tools/gate_term.sh): 9,602 bytes at 9600 baud
in 10.08 s, none lost, 952 bytes/s (99 % of the line).

**The modem's rate** (V94, after Packet16): at start, and when the
settings change the port, Term sends `AT` at 115200, 57600, 38400, 19200
and 9600 until the modem answers (the status bar says Finding the
modem; what comes meanwhile is not shown); found at another rate than
settings/B, `ATB<rate>` moves the modem to B and the UART follows.
Zimodem keeps its rate until it is powered off (115200 on TexElec's
card), so Term and the modem agree without typing `ATB` by hand. Nothing
answers (no modem, or it is online): the UART stays at B. A dial waits
for it.

A "script" back-end plays `TERM.IN` at the baud rate instead of a port
(the gates without a serial line).

## Settings (TERM.CFG) and the address book (TERM.BOOK)

options/settings is a page in the window: a letter changes a line, W
writes TERM.CFG, Esc goes back (the port is opened again if its address,
the baud rate, the crystal or the interrupt changed).

| Key | Setting | Default |
|---|---|---|
| A, P | the UART's address ($9F60, $9F68 ... $9FF8); P probes $9F60-$9FF0 by $10 (the scratch register; a card's second port is 8 above) | $9FE0, else the first that answers at start |
| B | baud rate 300-115200, 8N1 | 9600 |
| C | the UART's crystal: 1.8432, 3.6864, 7.3728, 8.0, 14.7456, 16.0 MHz | 14.7456 (TexElec's card) |
| I | the UART's own interrupt (V94: off, polled only, as Packet16) | off |
| E, R, T, K | local echo; a received CR as CR or CR LF; Return sends CR, CR LF or LF (CR NUL in Telnet); Backspace BS or DEL | off, CR, CR, BS |
| N | Telnet: auto (after a host:port dial), always, never | auto |
| O, S | ANSI colours; the scheme | on, light |
| M | the modem's init string, sent before every dial | ATV1 |
| Q | status commands, `;` between them | ATI;ATI2 |
| H, Z, U | the time service (RFC 867 daytime) host:port; the time zone (quarter hours, + and -); set the clock without asking | time.nist.gov:13, UTC, off |

The address book has eight well known Telnet BBSes (from memory: check
them) and eight of your own (N new, E edit, X delete; TERM.BOOK, a line
`name|host:port` each).

**Documents.** Veranda Term opens `.TEL` files (`documents = TEL` in
`app.hdr`: the shell starts it on a double click, DECISIONS V48): a
plain file holding one address book line, `name|host:port` (or
`host:port` alone). Started with one (`GetFile` with `ST_LD_DATA`), it
dials it once its window is up. Dex's Connect writes `DEX.TEL` next to
Veranda Term and starts it so (DECISIONS V56); the file is looked for in
the current folder, then in `curDirName`'s. The parsing is in the
overlay (`o_doc`, `ui.c`); the test build's TERM.TST session `dex` ends
once online.

## The clock

connect/clock from network dials the time service through the modem; its
line (`YY-MM-DD HH:MM:SS`, NIST's daytime format, or an ISO date) is taken
as UTC, the time zone added, and after the box (the time now and the new
one; YES) `SetClock` (DECISIONS V42) writes the X16's RTC and Veranda's
clock together: it holds after a reboot (the RTC is battery-backed).
A modem status line with a date in it (a firmware's own time command, set
as a status command) offers the same.

## On the real card: what to check

- **The address.** TexElec's Serial & ESP32 Network Card: its DIP switches
  put the ESP32's UART in one of ten 16-byte ranges $9F60-$9FF0 (the
  factory's $9FE0), the DE9 port's 8 above it. Settings/P finds the first
  whose scratch register answers (DECISIONS V91).
- **The crystal and the baud rate.** The divisor is crystal / 16 / baud:
  set C to the card's oscillator (TexElec's card: 14.7456 MHz, the default:
  divisor 921600 / baud; PC-style cards often 1.8432). The modem's own
  rate must match: Term finds a Zimodem's rate itself and moves it to B
  with `ATB` (V94); other ESP firmwares `AT$SB=<rate>`, typed by hand.
- **The interrupt.** Off by default (V94): the UART is polled eight times
  a frame (~2.1 ms apart; the FIFO's 16 bytes last 4.2 ms at 38400), the
  set-up Packet16 has run on TexElec's card; the card's INT on the bus
  was never tried on hardware. If the card wires it (a jumper on some
  cards), I on lets bytes in between the polls, for 57600 and above.
  Some cards need MCR OUT2 for it (Veranda Term sets MCR $0B: DTR, RTS,
  OUT2; never AFE, which holds every byte sent while CTS is low, as it
  stays on TexElec's card). Put aside by the switcher (Alt+Tab), Term
  turns the UART's and VERA's line interrupts off first (`asideVector`,
  DECISIONS V91: with the kernel no longer calling its routine, the
  UART would hold the IRQ line and the machine would hang) and on again
  when it comes back; bytes that come meanwhile are lost.
- **Flow control.** RTS drops when the ring fills (a dialog box held open
  a long time): with Zimodem `AT&K3` (RTS/CTS), the modem waits instead
  of losing bytes, if the card carries RTS to it. TexElec's card has no
  CTS (it stays low), and whether its RTS reaches the ESP32 is not known:
  there the throttle may do nothing (it needs no CTS: RTS is the X16's
  output; it is kept, harmless).
- **The init string.** Zimodem: `ATV1` (verbal results; `CONNECT` and `NO
  CARRIER` are how the terminal knows the line state; DCD is shown but not
  relied on), `ATE0` if its echo is unwanted. Telnet: Zimodem's `ATD`
  passes the Telnet bytes through (Veranda Term answers them); with a
  firmware that answers them itself, set Telnet to never.
- **Status commands.** Zimodem: `ATI` (the firmware), `ATI2` (the IP
  address), `AT+CONFIG` (Wi-Fi setup, typed by hand offline). If the
  firmware has a time command whose answer contains the date, add it to
  the status commands: Veranda Term offers to set the clock from it.
