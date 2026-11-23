/* Veranda Gopher: a fetch (main RAM; DECISIONS V109).

   Gopher (RFC 1436) is one connection a page: to the item's host and
   port, the selector sent with CR LF (a search's: the selector, a tab,
   the query), then everything the server sends until it closes. Here a
   state machine stepped from the main loop (g_poll) on vrnet (sdk
   vrnet.h, docs/NET.md), so nothing waits:
     wait   the modem not ready yet (vrnet looks for it)
     open   net_open'ed: the request written as soon as vrnet takes it
            (it may be queued while the modem connects)
     recv   the reply read on every pass, to the document (doc_feed) or
            to the download's file (xf_write); its end the server's close
   Errors: the modem's (none, or it stopped answering), the connection's
   (refused, no such host, no answer: vrnet's), nothing for 30 s, a
   connection closed without a byte. g_cancel (Stop, Esc) hangs up at
   once. A page longer than the document's room is cut: the connection
   is closed and the page says so.

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <string.h>
#include <vrnet.h>
#include <vrser.h>
#include <vrcs.h>
#include "gopher.h"

#define S_IDLE 0
#define S_WAIT 1
#define S_OPEN 2

#define T_IDLE 1800             /* frames with nothing coming (30 s) */

unsigned char gbusy, gerr, gdl, gfirst;
signed char gnet;
unsigned long grx;
unsigned int gt0;

static unsigned char st, ended;
static signed char sk = -1;
static unsigned int tlast;
static char req[SELMAX + 2];
static unsigned char req_n, req_p;
static unsigned char buf[512];          /* (below $A000: net_read) */

static void __fastcall__ end(unsigned char e)
{
    if (sk >= 0)
        net_close(sk);
    sk = -1;
    st = S_IDLE;
    if (gdl)
        xf_close(e == GE_OK);
    gerr = e;
    gbusy = 0;
    ended = 1;
}

void __fastcall__ g_start(unsigned char download)
{
    unsigned char n = 0;
    const char *s = go.sel;
    gdl = download;
    gerr = GE_OK;
    gnet = 0;
    grx = 0;
    gfirst = 0;
    gbusy = 1;
    gt0 = ser_frames;
    while (*s && n < SELMAX - 3) {      /* (V143: the set's letters as UTF-8) */
        if ((unsigned char)*s >= 0xA0)
            n += cs_utf8(*s++, req + n);
        else
            req[n++] = *s++;
    }
    req[n++] = '\r';
    req[n++] = '\n';
    req_n = n;
    req_p = 0;
    st = S_WAIT;
    if (!net_on)
        end(GE_NOCARD);
}

void g_cancel(void)
{
    if (gbusy)
        end(GE_CANCEL);
}

static void push(void)
{
    int k;
    if (req_p < req_n) {
        k = net_write(sk, req + req_p, req_n - req_p);
        if (k > 0)
            req_p += k;
    }
}

unsigned char g_poll(void)
{
    int n;
    unsigned char d;
    net_poll();
    if (st == S_WAIT) {
        d = net_state();
        if (d == NET_FAULT)
            end(GE_MODEM);
        else if (d == NET_READY) {
            sk = net_open(go.host, go.port);
            if (sk < 0) {
                gnet = sk;
                sk = -1;
                end(GE_NET);
            } else {
                st = S_OPEN;
                tlast = ser_frames;
            }
        }
    } else if (st == S_OPEN) {
        push();
        d = net_sock(sk);
        if (d == NET_FAILED || d == NET_FREE) {
            gnet = net_sockerr(sk);
            end(GE_NET);
        } else if (d == NET_OPENING || d == NET_DIAL) {
            tlast = ser_frames;         /* (vrnet's own deadline: 15 s) */
        } else {
            n = net_read(sk, buf, sizeof buf);
            if (n > 0) {
                tlast = ser_frames;
                if (!gfirst) {
                    gfirst = 1;
                    g_first();
                }
                grx += n;
                if (gdl) {
                    if (!xf_write(buf, n))
                        end(GE_LOCAL);
                } else if (!doc_text(buf, n))     /* (V143: into Veranda's set) */
                    end(GE_OK);         /* (the page is full: cut) */
            } else if (n == NET_ECLOSED) {
                if (!grx)
                    end(GE_EMPTY);
                else
                    end(GE_OK);
            } else if (n < 0) {
                gnet = n;
                end(GE_NET);
            } else if (ser_frames - tlast > T_IDLE)
                end(GE_TIMEOUT);
        }
    }
    d = ended;
    ended = 0;
    return d;
}
