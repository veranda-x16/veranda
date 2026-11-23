# Veranda FTP

An FTP client for Veranda (DECISIONS V100), through the Wi-Fi modem of
TexElec's "Serial & ESP32 Network Card" (Zimodem; the SDK's `vrnet`,
`docs/NET.md`).

Two panes side by side: the card on the left (it starts in `/DOCUMENTS`,
long names), the server on the right. Each shows its folder in the
toolbar (the active pane's bold, on the highlight), the column heads in
bold, the names (16 cells), sizes and dates, and a Sunroom scroll bar
(an arrow a line, the track a page; DECISIONS V149). The status bar
shows what is happening, and during a transfer the bytes, the
percentage, a progress bar and the speed. The panes are drawn by
`pane.c` in overlay 3 (with the SDK's `vrscroll.c`); the test build's
overlay is 4.

## Using it

- **Connection > Sites...** shows the saved servers. Click one, then
  **Connect** (or double-click it, or press Return). **New** adds a
  server; click a field (or Tab, Down, Up) and type. **Delete** forgets
  the selected one. **Close** (or Esc) goes back to the panes. Changes
  are saved when the page closes or connects.
- **Connection > Connect** connects to the selected server again;
  **Disconnect** says goodbye (QUIT).
- **Double-click a folder** to open it; `..` goes up (both panes).
- **File > Download** copies the selected file on the server into the
  local pane's folder. **File > Upload** copies the selected file on the
  card into the server's folder. **New folder...**, **Delete** and
  **Rename...** work on the pane you last clicked in. **Refresh** reads
  the pane again.
- **View** sorts both panes by name, size or date; **Other pane** switches.
- The menus are grouped and show their keys (Sunroom, V146).
- Keys: Tab switches pane; the arrows, PgUp, PgDn, Home, End move;
  Return opens a folder; F5 copies (downloads from the right pane,
  uploads from the left); F6 renames; F7 makes a folder; F8 deletes; Esc
  stops a transfer.

The main loop never waits for the network: menus work during a transfer,
and **Alt+Tab** puts Veranda FTP aside while a file comes; the
connection stays open in the modem, and the transfer goes on when you
come back. Network errors are shown in a box.

Transfers are binary, in passive mode. The data connection goes to the
server's own address on the port the server names (as Packet16 does: a
server behind NAT may name the wrong address).

## FTP.SITES

The saved servers are in `FTP.SITES` in the system's folder,
`/VERANDA/.SYSTEM`, one server a line:

    name,host,port,user,password,start folder

**The password is stored as plain text**, as Packet16 stores it. Anyone
who can read the card can read it. Leave the user empty to log in as
`anonymous`. A field cannot contain a comma. The file can be written on
a PC too (CR LF or LF line ends).

The host is a name or an address: letters, digits, `.` and `-` (the
modem's rule, so that no modem command can be slipped in).

## Limits

- 250 entries a pane; names up to 63 characters (a longer server name
  is cut and marked `~`).
- One transfer at a time; a file at a time.
- A file downloaded after Alt+Tab is written byte by byte from then on
  (CMDR-DOS's read-and-write mode, the only way to go on at a place), a
  little slower.
- No TLS (FTPS), no resume of an interrupted transfer.

## Credits

The FTP protocol, the listing parser and the sites file come from
**Packet16**, Marcin Spoczynski's FTP client for the Commander X16, used
in Veranda under the MIT licence with his permission. Its Zimodem driver
became the SDK's `vrnet` (DECISIONS V98).

MIT licence (see LICENSE).
