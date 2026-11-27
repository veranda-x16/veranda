/* vrnet: TCP sockets through a Zimodem Wi-Fi modem (TexElec's "Serial &
   ESP32 Network Card"), for Veranda applications (lib/veranda.lib;
   DECISIONS V98; docs/NET.md).

   The modem's command mode, as Packet16 (Marcin Spoczynski's X16 FTP
   client, whose Zimodem client this is rewritten from, under the MIT
   licence with his permission) drives it on the real card: up to
   NET_SOCKS connections at once (ATC"host:port", ATT<n>, ATH<id>), each
   packet pulled with an XON (ATF3) and checked with its CRC-8. Nothing
   here waits: net_poll(), called from appMain on every pass of the main
   loop, does the work a step at a time, with deadlines counted in frames,
   so menus, dialog boxes and the switcher (Alt+Tab) go on as usual.

   It uses vrser.h's driver (SerIrq is the program's intFirstVector while
   vrnet runs, ser_aside's work its asideVector) and two RAM banks (the
   receive ring; the sockets' buffers). Buffers passed to net_read and
   net_write must be below $A000. */
#ifndef VRNET_H
#define VRNET_H

#define NET_SOCKS 4             /* sockets at once (FTP: control and data) */

/* errors (negative) */
#define NET_OK          0
#define NET_ERR       (-1)      /* the modem said ERROR (refused, no such host) */
#define NET_ETIMEOUT  (-2)      /* nothing answered in time */
#define NET_ENOSOCK   (-3)      /* no free socket, or not a socket */
#define NET_ECLOSED   (-4)      /* the other side closed (after its data) */
#define NET_EBADCRC   (-5)      /* a packet failed its checksum (data lost) */
#define NET_ENOMODEM  (-6)      /* no modem answers at any rate */
#define NET_ENOCARD   (-7)      /* no UART at the port */
#define NET_ENOBANKS  (-8)      /* no RAM banks */
#define NET_EBADARG   (-9)      /* a bad host name or port */
#define NET_ESTATE    (-10)     /* not started, or failed */
#define NET_EIO       (-11)     /* the modem's reply made no sense */

/* net_state() */
#define NET_OFF     0
#define NET_SYNC    1           /* the modem's rate looked for (vrser.h's ser_sync) */
#define NET_SETUP   2           /* its profile sent */
#define NET_READY   3
#define NET_FAULT   4           /* net_error() says why; net_stop, then net_start again */

/* net_sock() */
#define NET_FREE    0
#define NET_OPENING 1           /* asked for, the ATC not sent yet */
#define NET_DIAL    2           /* the modem is connecting */
#define NET_OPEN    3
#define NET_CLOSING 4           /* net_close'd: its ATH not answered yet */
#define NET_EOF     5           /* the other side closed: read what is left */
#define NET_FAILED  6           /* net_sockerr() says why; net_close it */

/* before net_start: the UART's crystal, Hz / 1600 (vrser.h: SER_X14, the
   TexElec card's 14.7456 MHz, the default) */
extern unsigned int net_xtal;

/* start: the UART at $9F00 + port (0: the first found, vrser.h's
   ser_probe), its banks, its interrupt; then (in net_poll) the modem's
   rate found and moved to baud / 100 (576: 57600, the default when 0;
   Packet16's rate on the real card), the profile sent. Returns NET_OK or
   NET_ENOCARD, NET_ENOBANKS; then watch net_state(). */
signed char __fastcall__ net_start(unsigned char port, unsigned int baud100);
/* every socket hung up (best effort, a few frames), the UART off, the
   banks freed, intFirstVector and asideVector cleared */
void net_stop(void);
/* one step: call it on every pass of the main loop */
void net_poll(void);
unsigned char net_state(void);
signed char net_error(void);    /* why NET_FAULT */

/* a connection to host (letters, digits, '.' and '-', at most 61; V114: 63 before) and
   port: the socket (0 .. NET_SOCKS - 1) at once, NET_OPENING; NET_OPEN
   when the modem has connected, NET_FAILED if it could not. Data written
   before it is open waits. Or an error (< 0). */
signed char __fastcall__ net_open(const char *host, unsigned int port);
/* (V114) net_open while this is 1: the connection is TLS, made by the
   modem (ATCS"host:port": Zimodem's WiFiClientSecure, which does not
   check the server's certificate); the program speaks plain bytes over
   it. 0 (the default): plain TCP */
extern unsigned char net_tls;
/* (V210) from now on, when a packet's header comes in, the next XON is
   sent at once, so that the next packet follows on the line with no gap
   (one XON ahead, while nothing else waits and every open socket has
   room for two packets): a download comes at the line's rate. Without
   it, an XON after each packet, as before (vrahead.c, about 150 bytes,
   is linked only by a program that calls this) */
void net_ahead_on(void);
unsigned char __fastcall__ net_sock(signed char s);
signed char __fastcall__ net_sockerr(signed char s);
/* up to n received bytes into buf: the count (0: none yet), or
   NET_ECLOSED when the other side has closed and everything was read,
   or the socket's error */
int __fastcall__ net_read(signed char s, void *buf, unsigned int n);
/* up to n bytes queued to send: the count taken (0: the socket's buffer
   is full, try again after net_poll), or an error */
int __fastcall__ net_write(signed char s, const void *buf, unsigned int n);
/* bytes waiting to be read; room to write */
unsigned int __fastcall__ net_avail(signed char s);
unsigned int __fastcall__ net_room(signed char s);
/* hang up (after what was written is sent) and free the socket */
void __fastcall__ net_close(signed char s);

/* counters (gates, a diagnostics page) */
struct net_stats {
    unsigned int pulls, packets, empties, xon_retries, badcrc, sends, orphans;
};
extern struct net_stats net_stats;

#endif
