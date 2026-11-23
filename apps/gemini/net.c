/* Veranda Gemini: a request (main RAM; DECISIONS V118).

   Gemini (geminiprotocol.net's specification) is one TLS connection a
   request, to port 1965 by default: the absolute URL sent with CR LF
   (1,024 bytes at most), then the reply: a header "<two digits> <meta>"
   with CR LF, and after a 2x header the body, until the server closes.
   The TLS is the modem's (vrnet's net_tls: Zimodem's ATCS "host:port",
   which does not check the server's certificate); the X16 speaks plain
   bytes over it. A state machine stepped from the main loop (g_poll), so
   nothing waits:
     wait   the modem not ready yet
     open   net_open'ed: the request written as soon as vrnet takes it;
            the header read
     body   to the document (doc_feed) or to the download's file
     hold   a body that is not a page came: the program asks (EV_SAVE)
            and goes on with g_save, or g_cancel's
   The header's meta is kept (gmeta); a 2x's MIME type says what the body
   is (text/gemini, the default, and text/plain pages; any other text type
   shown as plain text; anything else a file) and its charset how it is
   decoded (UTF-8, the default; ISO-8859-1). Errors: the modem's, the
   connection's (vrnet's), nothing for 30 s, a connection closed without a
   byte, a header that is not Gemini's.
   (V138) A connection is not asked for while the one before is still
   being hung up (vrnet's ATH, which frees the modem's TLS client);
   greply says whether any byte of the reply came (ui.c tries a
   connection that failed before once more, a second later).

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <string.h>
#include <vrnet.h>
#include <vrser.h>
#include "gemini.h"

#define S_IDLE 0
#define S_WAIT 1
#define S_OPEN 2
#define S_BODY 3
#define S_HOLD 4

#define T_IDLE 1800             /* frames with nothing coming (30 s) */
#define HDRMAX 1100             /* a header longer than this is not Gemini's */

unsigned char gbusy, gerr, gdl, gfirst, gstatus, gtext, gdec, greply;
signed char gnet;
unsigned long grx;
unsigned char rtry;                     /* (V138: ui.c's, url.c's u_retry) */
unsigned int rt_t;
unsigned int gt0;
char gmeta[METAMAX];

static unsigned char st, ended;
static signed char sk = -1, psk = -1;  /* (psk: the one before, being hung up) */
static unsigned int tlast, hn_, req_n, req_p;
static unsigned char mn;
static unsigned char buf[384];          /* (below $A000: net_read; the request, 257 bytes at most; 512 until V125) */
static unsigned int bp, bn;             /* the body's bytes in buf not used yet */

static void __fastcall__ end(unsigned char e)
{
    if (sk >= 0)
        net_close(psk = sk);
    sk = -1;
    if (st == S_BODY && gdl)
        xf_close(e == GE_OK);
    st = S_IDLE;
    gerr = e;
    gbusy = 0;
    ended = EV_END;
}

void __fastcall__ g_start(unsigned char download)
{
    gdl = download;
    gerr = GE_OK;
    greply = 0;
    gnet = 0;
    grx = 0;
    gfirst = 0;
    gstatus = 0;
    gbusy = 1;
    gt0 = ser_frames;
    hn_ = mn = 0;
    gmeta[0] = 0;
    strcpy((char *)buf, go);
    req_n = strlen(go);
    tl_d = (char *)buf + req_n;         /* (V138: a long link's rest) */
    doc_tail(sizeof buf - 3 - req_n);
    strcat((char *)buf, "\r\n");
    req_n = strlen((char *)buf);
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

static unsigned char __fastcall__ lower(unsigned char c)
{
    return c >= 'A' && c <= 'Z' ? c + 32 : c;
}

/* a 2x's MIME type: what the body is */
static void mime(void)
{
    unsigned char i, c;
    const char *p;
    for (i = 0; (line[i] = lower(gmeta[i])) != 0; ++i)
        ;                               /* (gmeta: METAMAX, line's size) */
    gtext = 0xFF;
    if (!line[0] || !memcmp(line, "text/gemini", 11))
        gtext = M_GEM;
    else if (!memcmp(line, "text/", 5))
        gtext = M_PLAIN;
    gdec = D_UTF8;
    p = strstr(line, "charset=");      /* (V138: iso-8859-1, latin1, us-ascii told apart cheaply: main RAM's room) */
    if (p && ((c = p[8]) == 'l' || (c == 'i' && p[17] == '1') || (c == 'u' && p[9] == 's')))
        gdec = D_LATIN1;
}

/* the header's byte c: 1 when it ended */
static unsigned char __fastcall__ hbyte(unsigned char c)
{
    if (++hn_ > HDRMAX) {
        end(GE_BADHDR);
        return 1;
    }
    if (c == '\n') {
        while (mn && (gmeta[mn - 1] == '\r' || gmeta[mn - 1] == ' '))
            --mn;
        gmeta[mn] = 0;
        return 1;
    }
    if (hn_ <= 2) {
        if (c < '0' || c > '9') {
            end(GE_BADHDR);
            return 1;
        }
        gstatus = gstatus * 10 + c - '0';
    } else if (hn_ == 3 && c == ' ') {
        /* (the space before the meta) */
    } else if (mn < METAMAX - 1 && (mn || c != ' '))
        gmeta[mn++] = c;
    return 0;
}

/* the header has come: the body's way */
static void header(void)
{
    if (hn_ < 3) {
        end(GE_BADHDR);
        return;
    }
    if (gstatus < 20 || gstatus > 29) {
        end(GE_STATUS);                 /* (the program reads gstatus, gmeta) */
        return;
    }
    mime();
    if (gtext != 0xFF && gdl != 1) {   /* (a page: also when a picture was asked for, V125) */
        gdl = 0;
        gfirst = 1;
        g_first();                      /* (doc_clear: the page is new) */
        st = S_BODY;
        return;
    }
    st = S_HOLD;                        /* a file: the program asks */
    ended = EV_SAVE;
}

/* the body's bytes, to the page or the file */
static void __fastcall__ body(const unsigned char *b, unsigned int n)
{
    if (!n)
        return;
    grx += n;
    if (gdl) {
        if (!xf_write(b, n))
            end(GE_LOCAL);
    } else if (!doc_feed(b, n))
        end(GE_OK);                     /* (the page is full: cut) */
}

unsigned char g_save(void)
{
    if (st != S_HOLD)
        return 0;
    if (!xf_open()) {
        end(GE_LOCAL);
        return 0;
    }
    st = S_BODY;
    tlast = ser_frames;
    body(buf + bp, bn);
    bn = 0;
    return 1;
}

static void push(void)
{
    int k;
    if (req_p < req_n) {
        k = net_write(sk, buf + req_p, req_n - req_p);
        if (k > 0)
            req_p += k;
    }
}

unsigned char g_poll(void)
{
    int n;
    unsigned char d;
    unsigned int i;
    net_poll();
    if (st == S_WAIT) {
        d = net_state();
        if (d == NET_FAULT)
            end(GE_MODEM);
        else if (net_sock(psk) == NET_CLOSING)
            ;                           /* (V138: the one before not hung up yet: vrnet's ATH frees the modem's TLS client) */
        else if (d == NET_READY) {
            net_tls = 1;
            sk = net_open(ghost, gport);
            net_tls = 0;
            if (sk < 0) {
                gnet = sk;
                sk = -1;
                end(GE_NET);
            } else {
                st = S_OPEN;
                tlast = ser_frames;
            }
        }
    } else if (st == S_OPEN || st == S_BODY) {
        if (req_p < req_n)
            push();
        d = net_sock(sk);
        if (d == NET_FAILED || d == NET_FREE) {
            gnet = net_sockerr(sk);
            end(GE_NET);
        } else if (d == NET_OPENING || d == NET_DIAL) {
            tlast = ser_frames;
        } else if (req_p >= req_n) {    /* (buf is the request's until it is sent) */
            n = net_read(sk, buf, sizeof buf);
            if (n > 0) {
                greply = 1;
                tlast = ser_frames;
                if (st == S_OPEN) {
                    for (i = 0; i < (unsigned int)n; )
                        if (hbyte(buf[i++]))
                            break;
                    if (st == S_OPEN) {
                        if (i == (unsigned int)n && buf[n - 1] != '\n')
                            goto out;   /* (more header to come) */
                        bp = i;
                        bn = n - i;
                        header();
                        if (st == S_BODY) {
                            body(buf + bp, bn);
                            bn = 0;
                        }
                    }
                } else
                    body(buf, n);
            } else if (n == NET_ECLOSED) {
                if (st == S_OPEN)
                    end(hn_ ? GE_BADHDR : GE_EMPTY);
                else
                    end(GE_OK);
            } else if (n < 0) {
                gnet = n;
                end(GE_NET);
            } else if (ser_frames - tlast > T_IDLE)
                end(GE_TIMEOUT);
        } else if (ser_frames - tlast > T_IDLE)
            end(GE_TIMEOUT);
    }
out:
    d = ended;
    ended = 0;
    return d;
}
