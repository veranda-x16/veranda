/* vrnet: one XON ahead (DECISIONS V210; vrnet.h's net_ahead_on). Its own
   object, so that only a program that asks for it links it (vrnet.c
   calls it through net__ahead).

   When a packet's header has come in, the next XON goes at once, so that
   its packet follows this one on the line with no gap: the modem takes
   it while it still sends this one (Zimodem 4.0.2 queues a packet in its
   4 KB serial buffer: zcommand.ino's sendNextPacket, serout.ino's
   availableForWrite), and the time the modem and this side take to turn
   round is hidden behind the 46 ms this packet takes at 57600. Only while
   nothing else waits (a command, a send, a connection to make or hang
   up: schedule's work goes first), every open socket has room for this
   packet and one more, and never while draining for the switcher or
   just back from it. The emulator's modem drops an XON that comes while
   more than a packet waits to go out: here at most this packet's payload
   does.

   With an XON always out, a pull is always under way: its deadline (0.5
   s for the modem's answer) counts from each header that comes, not from
   the XON, so that this side's own long pass (a card write, a redraw)
   with the packets waiting in the serial ring is never taken for a modem
   that does not answer. (V213) And it is 3 s, not 0.5: with the next XON
   out, the modem reads the next packet from its connection while this
   one is still in its serial buffer, and while its loop is held there (a
   TLS record not all in, the Wi-Fi; tests/zimreal.py's --stall) this
   packet stops half way on the line; 0.5 s cut it short (NET_EIO).

   MIT licence (see LICENSE). */
#include <veranda.h>
#include "vrser.h"
#include "vrnet.h"
#include "vrnetp.h"

#define T_PKT 180               /* (V213) 3 s, as vrnet.c's */

static void ahead(void)
{
    struct sock *s;
    ot = ser_now();
    olen = T_PKT;               /* (V213: this packet's rest, then the next one's answer) */
    if (orphan || hold || draining || !ser_txroom())
        return;
    for (s = sk; s != sk + NET_SOCKS; ++s) {
        if ((s->st >= NET_OPENING && s->st <= NET_DIAL) || s->st == NET_CLOSING || s->txh != s->txt)
            return;
        if (s->st == NET_OPEN && ((s->rxh - s->rxt) & (RXSZ - 1)) > RXSZ - 1 - 2 * PKT)
            return;
    }
    ser_byte(XON);
    nxt = 1;
    ++net_stats.pulls;
}

void net_ahead_on(void)
{
    net__ahead = ahead;
}
