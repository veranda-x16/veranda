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
| an XON's packet | 0.5 s | XON again (the firmware drops an XON when its buffer is full), 4 tries |
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
7.3 KB) and 0.7 KB of data (the 256-byte transmit ring among it); two RAM
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
