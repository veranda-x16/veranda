/* Veranda Chat: the connection (main RAM; DECISIONS V111).

   IRC is one TCP connection to the server, lines both ways ending with
   CR LF (512 bytes at most). Here a state machine stepped from the main
   loop on vrnet (sdk vrnet.h, docs/NET.md), so nothing waits:
     wait   the modem not ready yet (vrnet looks for it)
     open   net_open'ed; PASS, NICK and USER queued at once (vrnet takes
            them while the modem connects)
     reg    connected: registering (proto.c: nick in use, 001)
     up     registered
     quit   QUIT sent: the server's close awaited (3 s at most)
   Lines in are gathered in rx (a longer one is cut at RXMAX, IRCv3 tags
   left out: V178) and each is
   handed to proto.c (overlay 2); lines out go through a 1 KB queue that
   is written as vrnet takes it. The keep-alive: after 3 minutes with
   nothing from the server a PING, after 5 the connection is given up.

   Alt+Tab: vrnet's own asideVector (a packet that is arriving taken
   whole, the port quiet); the connection stays open in the modem, which
   holds what arrives (TCP slows the server); back, it all comes in. A
   long absence may let the server drop us (its own PING unanswered:
   the close is shown when we come back).

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <vr.h>
#include <string.h>
#include <vrnet.h>
#include <vrser.h>
#include "chat.h"

unsigned char cstate, cerr, net_on;
signed char cnet;
char cwhy[80];
char rx[RXMAX];
char me[NICKLEN];
unsigned int crx_lines, ctx_lines;

static signed char sk = -1;
static unsigned int rxn;
static unsigned char rxtag;             /* (V178) IRCv3 tags being left out (feed) */
static unsigned int tlast, tquit;
static unsigned char pinged;
static unsigned char rbuf[128];         /* (below $A000: net_read) */

#define TXQ 512
static char txq[TXQ];
static unsigned int qh, qn;             /* the queue's head, its bytes */

#define T_PING  (180u * 60)             /* nothing for 3 minutes: PING */
#define T_DEAD  (300u * 60)             /* 5: given up */

static void __fastcall__ end(unsigned char e)
{
    unsigned char i;
    if (sk >= 0)
        net_close(sk);
    sk = -1;
    cstate = C_OFF;
    cerr = e;
    qn = 0;
    for (i = 1; i < WMAX; ++i)
        W[i].joined = 0;
    dirty |= D_ALL;
}

#ifdef CHAT_TEST
static unsigned int net_aside;
static void aside(void)
{
    if (net_aside)
        ((void (*)(void))net_aside)();
    t_aside = 1;
    gt_log("IR ASIDE");
}
#endif

void net_restart(void)
{
    net_stop();
    net_on = net_start(0, 576) == NET_OK;
#ifdef CHAT_TEST
    net_aside = net_on ? asideVector : 0;
    asideVector = VR_FN(aside);
#endif
}

void conn_start(void)
{
    if (!net_on || net_state() == NET_FAULT)
        net_restart();
    cerr = CE_NONE;
    cwhy[0] = 0;
    rxn = qn = qh = 0;
    rxtag = pinged = 0;
    strncpy(me, S.nick, NICKLEN - 1);
    cstate = C_WAIT;
    if (!net_on)
        end(CE_NOCARD);
    dirty |= D_ALL;
}

void conn_drop(void)
{
    if (cstate != C_OFF)
        end(CE_QUIT);
}

void __fastcall__ conn_quit(const char *why)
{
    if (cstate == C_UP || cstate == C_REG) {
        strcpy(obuf, "QUIT :");
        strcat(obuf, why ? why : "Veranda Chat (Commander X16)");
        send_line(obuf);
        cstate = C_QUIT;
        tquit = ser_frames;
    } else
        conn_drop();
}

unsigned char __fastcall__ send_line(const char *s)
{
    unsigned int n = strlen(s), t, i;
    if (sk < 0 || n + 2 > TXQ - qn)
        return 0;
    t = (qh + qn) & (TXQ - 1);
    for (i = 0; i < n; ++i) {
        txq[t] = s[i];
        t = (t + 1) & (TXQ - 1);
    }
    txq[t] = '\r';
    txq[(t + 1) & (TXQ - 1)] = '\n';
    qn += n + 2;
    ++ctx_lines;
    return 1;
}

static void pump(void)
{
    unsigned int c;
    int k;
    while (qn) {
        c = TXQ - qh;
        if (c > qn)
            c = qn;
        k = net_write(sk, txq + qh, c);
        if (k <= 0)
            break;
        qh = (qh + k) & (TXQ - 1);
        qn -= k;
    }
}

/* (V178) the bytes of a line: IRCv3 tags ("@a=b;c=d " first, up to 8 KB
   with the message-tags capability) are left out as they come, so a
   tagged line keeps its 512 bytes of IRC; what is longer than rx is cut
   (the rest dropped, up to the line's end) */

static void __fastcall__ feed(unsigned int n)
{
    unsigned int i;
    unsigned char c;
    for (i = 0; i < n; ++i) {
        c = rbuf[i];
        if (c == '\n') {
            if (rxn && rx[rxn - 1] == '\r')
                --rxn;
            rx[rxn] = 0;
            rxtag = 0;
            if (rxn) {
                ++crx_lines;
                ov2(irc_line);
                if (cstate == C_OFF)    /* (proto.c ended it: the server's ERROR) */
                    return;
            }
            rxn = 0;
        } else if (rxtag) {
            if (c == ' ')
                rxtag = 0;
        } else if (!rxn && c == '@')
            rxtag = 1;
        else if (rxn < RXMAX - 1)
            rx[rxn++] = c;
    }
}

void conn_poll(void)
{
    unsigned char d;
    int n;
    net_poll();
    if (cstate == C_OFF)
        return;
    if (cstate == C_WAIT) {
        d = net_state();
        if (d == NET_FAULT)
            end(CE_MODEM);
        else if (d == NET_READY) {
            sk = net_open(S.host, S.port);
            if (sk < 0) {
                cnet = sk;
                sk = -1;
                end(CE_NET);
                return;
            }
            cstate = C_OPEN;
            tlast = ser_frames;
            nick_try = 0;
            ov4(irc_register);
            dirty |= D_STAT;
        }
        return;
    }
    pump();
    d = net_sock(sk);
    if (d == NET_FAILED || d == NET_FREE) {
        cnet = net_sockerr(sk);
        end(cstate == C_QUIT ? CE_QUIT : CE_NET);
        return;
    }
    if (d == NET_OPENING || d == NET_DIAL) {
        tlast = ser_frames;
        return;
    }
    if (cstate == C_OPEN) {
        cstate = C_REG;
        dirty |= D_STAT;
    }
    n = net_read(sk, rbuf, sizeof rbuf);
    if (n > 0) {
        tlast = ser_frames;
        pinged = 0;
        feed(n);
    } else if (n == NET_ECLOSED) {
        end(cstate == C_QUIT ? CE_QUIT : CE_CLOSED);
    } else if (n < 0) {
        cnet = n;
        end(CE_NET);
    } else if (cstate == C_QUIT) {
        if (ser_frames - tquit > 180)
            end(CE_QUIT);
    } else if (ser_frames - tlast > T_DEAD) {
        end(CE_TIMEOUT);
    } else if (ser_frames - tlast > T_PING && !pinged) {
        pinged = 1;
        send_line("PING :veranda");
    }
}
