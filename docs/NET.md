# vrnet: the network for Veranda applications

`vrnet` gives a Veranda application TCP connections through the Wi-Fi
modem on TexElec's "Serial & ESP32 Network Card" (an ESP32 running
Zimodem, behind a 16C550-class UART at `$9FE0`). TCP/IP and DNS run in
the ESP32; vrnet drives the modem's **command mode**, where several
connections can be open at once and every byte is binary-safe. It is in
`lib/veranda.lib`; its header is `include/vrnet.h`, and it uses the
serial driver `include/vrser.h` (DECISIONS V98).

The way it talks to the modem is Packet16's, the FTP client that works on
the real card (Marcin Spoczynski's; its code is used here under the MIT
licence with his permission, and credited in the sources). What is new is
that **nothing waits**: every step is done a little at a time from your
main loop, so menus, dialog boxes and the switcher keep working while a
connection is made or data flows.

## A first program

```c
#include <veranda.h>
#include <vr.h>
#include <vrnet.h>

static signed char s;
static unsigned char buf[128];

static void tick(void)
{
    int n;
    net_poll();                         /* every pass of the main loop */
    if (net_state() == NET_READY && s < 0) {
        s = net_open("example.org", 80);
        net_write(s, "GET / HTTP/1.0\r\n\r\n", 18);   /* waits until open */
    }
    if (s >= 0) {
        n = net_read(s, buf, sizeof buf);
        if (n > 0)
            ;                           /* n bytes in buf */
        else if (n == NET_ECLOSED || n < 0) {
            net_close(s);
            s = -1;
        }
    }
}

int main(void)
{
    s = -1;
    if (net_start(0, 576) != NET_OK)    /* the UART found, 57600 baud */
        return 0;
    appMain = VR_FN(tick);
    return 0;
}
```

Call `net_stop()` before the program quits (it also hangs up every
connection the modem holds).

## Starting and stopping

| Call | What it does |
|---|---|
| `net_start(port, baud100)` | The UART at `$9F00 + port` (`0`: the first one found, `$9F60-$9FF0` by `$10`), two RAM banks, the interrupt routine. Returns `NET_OK`, `NET_ENOCARD` (no UART) or `NET_ENOBANKS`. The rest happens in `net_poll`: the modem's rate is found and moved to `baud100` x 100 (`0`: 576, 57600 baud), then its profile is sent. |
| `net_state()` | `NET_SYNC` (looking for the modem's rate), `NET_SETUP` (its profile), `NET_READY`, `NET_FAULT` (`net_error()` says why), `NET_OFF`. |
| `net_poll()` | One step. Call it on every pass of `appMain`. |
| `net_ahead_on()` | (V210) From now on, the next XON goes as soon as a packet's header comes in (one XON ahead), so the next packet follows on the line with no gap. Links `vrahead.c` (about 200 bytes); a program that never calls it is as before. See "Speed" below. |
| `net_stop()` | `ATH0` sent, the UART off, the banks freed, `intFirstVector` and `asideVector` cleared. |
| `net_xtal` | Set it before `net_start` for another crystal (Hz / 1600; `SER_X14`, 14.7456 MHz, the TexElec card's, is the default; `SER_X1` 1.8432 MHz). |

**The modem's rate.** Zimodem keeps the rate it was last set to until it
is powered off (115200 when it starts). vrnet sends `AT` at 115200,
57600, 38400, 19200 and 9600 (half a second each) until one answers, then
`ATB<rate>` if that is not the rate asked for; the modem answers at the
new rate. With nothing on the line, after about 2.5 s: `NET_FAULT`,
`NET_ENOMODEM`.

**The profile** (Packet16's, one line at a time): `ATE0V1X1Q0&M&D`
(no echo, verbose results with channel numbers, the global mask and
delimiters cleared, which would delete payload bytes), `ATS40=254S45=0S0=0`
(packets of at most 254 bytes, raw binary), `ATF3` (one packet for each
XON), `ATH0` (connections left by an earlier program hung up).

**Speed** (DECISIONS V210). With an XON after each packet, the line
stands still between packets while the modem turns round and while the
program notices the packet's end: gate update measured 59 ms a packet in
the emulator, against the 47 ms a 254-byte packet and its header take at
57600. `net_ahead_on()` sends the next XON when a header comes in: the
modem queues that packet behind the one it is sending (Zimodem 4.0.2's
4 KB serial buffer: `sendNextPacket` returns without a packet only when
that buffer has less room than a packet), so the turn-round is hidden
and a download comes at the line's rate (49 ms a packet measured). It
sends one ahead only while nothing else waits (a command, a send, a
connection to make or close) and every open socket has room for two
packets; with one always out, a pull's deadline (0.5 s; V213: 3 s)
counts from each header that comes, so a long pass of the program (a card write) is not
taken for a modem that does not answer, and (V211) no deadline is
checked while bytes still wait in the serial ring (after a pass of a
second two packets may wait there, more than one step reads). The emulator's modem drops an
XON that comes while more than a packet waits to go out (the firmware
would keep it): one ahead never meets that. Also since V210 the serial
ring is read in assembly (`ser_get`, some 40 cycles a byte; the C loop
took 120) and the packets' CRC-8 too (`vrnetcrc.s`, 17 cycles a byte;
60). For the most, read the socket on every pass with a buffer of 256
bytes and keep each pass short (Veranda Update calls `net_poll()` again
between the parts of its own work).

**When to call `net_ahead_on()`** (DECISIONS V211, V213). Since V213 no
program calls it (it stays in the SDK, off). Veranda Update called it
from V210, Veranda FTP, Gemini and Gopher in V211, and those three were
reported broken on the user's card (Gemini's search "50", FTP's connection lost in the second
folder) while every gate passed: the emulator's modem answers at once and
its loop is never held, so a gate cannot show what one XON ahead does on
the card, and V213 took it out of them again, and out of Update too
(correctness first: its pack and its one kept connection are most of its
gain). What is known
(tests/zimreal.py, a model of the firmware with a Wi-Fi's latency;
`MODEM=real` in gates ftp, gemini, gopher and update): with one ahead the
modem reads the next packet from its connection while this one is still
in its serial buffer, so any pause of its loop then (a TLS record not all
in, the Wi-Fi) stops this packet half way on the line; before V213 a
pause of more than 0.5 s cut it short (NET_EIO). Since V213 a pull whose
packet has begun has 3 s (from its XON; with one ahead from each header,
vrahead.c), and vrnet reads its clock whole (`ser_now()`: a read of
`ser_frames` torn by the frame's interrupt was 256 frames late, and fired
a 0.5 s deadline at once). Do not call it in
a new program before it has been tried on the card; where it is used,
read every open socket on every pass (with a second socket open it waits
while that socket's ring is fuller than 1 KB - 2 packets). Leave it out
where what comes is slower than the line anyway (Veranda Ask's and
Claude's streamed answers, Chat). Two more rules from V211's measurements:
the status line's text in the UI font takes some 55-65 ms each time it
is drawn, and while it is drawn no packet is pulled and no send's OK is
seen: draw a transfer's progress once a second, not more; and an upload
goes as fast as its ring is full when each `ATT`'s OK comes: since V211 a
packet's bytes leave the 256-byte send ring as they are pushed to the
UART (not when the OK comes), so `net_write` again at once after
`net_poll()`, and while the pulls bring nothing the sends follow one
another (a pull every 10 frames for what the other side says). `ATT`s
are not sent ahead of their OK: while Zimodem 4.0.2 writes one `ATT`'s
bytes to the socket (`doTransmitCommand`: `readBytes`, then the client's
`write`), what comes next waits in the ESP32's serial receive buffer
(the core's default 256 bytes: Zimodem sets no other), and the card has
no CTS (Packet16 D21): a socket slow to take them would lose bytes, and
`readBytes` would then take the next command's as the payload.

**Rates.** 57600 is the default and the one proven on the card. The UART
is read from VERA's line interrupt 16 times a frame (every 1.05 ms: 6
bytes at 57600, inside the 16-byte FIFO with room for the system's own
interrupt work). 115200 overruns the FIFO in the emulator (the ROM's
frame interrupt alone takes longer than 1.4 ms, the FIFO's time at that
rate): do not use it.

## Sockets

| Call | What it does |
|---|---|
| `net_open(host, port)` | A socket number `0 .. NET_SOCKS - 1` (4) at once, in state `NET_OPENING`; `NET_DIAL` while the modem connects; `NET_OPEN`, or `NET_FAILED`. `host`: letters, digits, `.` and `-`, at most 61 characters (63 before V114, whose TLS modifier takes the room; an `AT` command cannot be slipped in); errors `NET_EBADARG`, `NET_ENOSOCK`, `NET_ESTATE`. |
| `net_tls` | (V114) Set to 1 before `net_open`: that connection is TLS, made by the modem (`ATCS"host:port"`: Zimodem's `WiFiClientSecure`, which does **not** check the server's certificate); the program reads and writes plain bytes over it. 0 (the default): plain TCP. Not in Zimodem's README: check the card's firmware (`ATI`). The emulator's modem takes `ATCS` as a plain TCP connection and logs it `SECURE`. |
| `net_sock(s)` | Its state: `NET_FREE`, `NET_OPENING`, `NET_DIAL`, `NET_OPEN`, `NET_CLOSING`, `NET_EOF` (the other side closed: read what is left), `NET_FAILED`. |
| `net_sockerr(s)` | Why it failed: `NET_ERR` (the modem said ERROR: refused, no such host), `NET_ETIMEOUT`, `NET_EBADCRC`, `NET_EIO`. |
| `net_write(s, buf, n)` | Queues up to `n` bytes (a 255-byte buffer a socket); returns how many it took (0: full, try after `net_poll`), or an error. Allowed while the socket is opening. |
| `net_read(s, buf, n)` | Up to `n` received bytes (a 1 KB buffer a socket): the count, `0` if none yet, `NET_ECLOSED` when the other side has closed and all was read, or the socket's error. |
| `net_avail(s)`, `net_room(s)` | Bytes waiting; room to write. |
| `net_close(s)` | What was written goes first, then `ATH<id>`; the socket is free once the modem answers. A failed socket is hung up too, and (V138) so is one the other side closed (`NO CARRIER`): Zimodem keeps a client's connection, with its TLS client, until `ATH<id>` deletes it. |

`buf` must be below `$A000` (vrnet maps its own RAM bank there while it
copies).

**Reading keeps the data flowing.** A packet is pulled from the modem
only when every open socket has room for a whole one (254 bytes): the
modem picks which connection's packet comes next, and a packet with
nowhere to go would be lost. A socket you never read therefore stops the
others. Read every open socket on every pass.

## Timeouts

Deadlines are counted in frames (`ser_frames`), and stand still while the
program is put aside.

| Step | Deadline | Then |
|---|---|---|
| a command's `OK` | 3 s | the socket `NET_FAILED`, `NET_ETIMEOUT` |
| a connection (`ATC`) | 15 s | the socket `NET_FAILED`, `NET_ETIMEOUT` |
| an XON's packet | 0.5 s; (V213) 3 s once its header has come | XON again (the firmware drops an XON when its buffer is full), 4 tries; a packet cut short: NET_EIO |
| after any timeout | 30 s | `AT` until the modem answers `OK` (it may still be busy with what timed out; a late `CONNECT` is hung up); else `NET_FAULT` |

Your program keeps running through all of them.

## The switcher and desk accessories

vrnet sets `asideVector`: before Alt+Tab puts the program aside, it lets
a packet that is arriving finish (the UART is not read while the program
is aside, and its FIFO holds only 16 bytes), then turns the port's
interrupt off. The connections stay open in the modem, which holds what
arrives (TCP then slows the sender). When the program comes back, the
next `net_poll` arms the port again and waits 10 frames before it asks
for more (the system's own work just after a switch can hold the
interrupt off long enough to lose a byte). Around `GetFile` for a desk
accessory, call `ser_pause()` and `ser_resume()` from `vrser.h`.

**A file open across passes.** The switcher does not put aside a program
with a stream open (it asks to quit it instead). A program that writes a
download over many passes (Veranda FTP, DECISIONS V100; Veranda Gopher, V109) keeps vrnet's
`asideVector` after `net_start` and sets its own: vrnet's first, then
`FClose`; when it comes back it opens the file again (`'m'` to write on,
`'r'` to read on) and `FSeek`s to where it was. A program with only connections
open (Veranda Chat, V111) keeps vrnet's `asideVector` as it is: put
aside, its connections stay open in the modem.

## Memory

About 8.1 KB of code in the program (measured, cc65 -O: vrnet 6.0 KB,
the serial driver 1.6 KB, the rate's sync 0.5 KB; Packet16's stack was
7.3 KB; V210: 40 bytes less, and `vrahead.c`'s 200 only with
`net_ahead_on`) and 0.7 KB of data (the 256-byte transmit ring among it); two RAM
banks: the serial ring (8 KB) and
the sockets' buffers (the CRC table, a packet, 4 x 1 KB to read,
4 x 256 bytes to write, the host names). `intFirstVector` is vrnet's
while it runs. Statistics are in `net_stats`.

## The serial driver alone

`vrser.h` is the driver itself (Veranda Term uses it directly): the
UART polled from VERA's line interrupt into a ring in a RAM bank, the
script back-end for tests, `ser_sync` (the modem's rate), the probe. Its
header shows the calls in order.

## Testing without the card

The emulator's `-uart 9FE0 modem` (the user's UART emulator, `modem`
branch, `UART.md`) is an emulated Zimodem in command mode with real TCP
connections from the host; `-uartclock 14.7456` for the card's crystal.
Options: `baud=` the rate it starts at, `cts`, `stall=<port>` (a host
that never answers), `ctimeout=` (the modem's own connect timeout),
`log=<file>` (every command it got). `tools/gate_net.sh` is the gate.

That modem answers at once and its loop is never held. (V213)
`tests/zimreal.py` is a closer one: Zimodem's own `readSerialStream`,
`sendNextPacket` (a `NO CARRIER` leaves the XON standing, so another
answer follows it), `doTransmitCommand` (`ATT` to a connection that is
gone: `ERROR` at once, its bytes read as commands), its 4 KB serial
buffer sent on only from its loop, with a Wi-Fi's latency (`--loop`,
`--write`, `--connect`, `--net`, `--jitter`), pauses of its loop
(`--stallp`, `--stall`, `--stallall`) and a small receive buffer
(`--rxcap`), reached through the emulator's `-uart 9FE0 tcp:` back-end in
real time (no `-warp`). Gates ftp, gemini, gopher and update run on it
with `MODEM=real` (`ZIMREAL="..."` its options; `tools/zimreal.inc.sh`);
gemini's and ftp's `ONLY=` pick sessions.
