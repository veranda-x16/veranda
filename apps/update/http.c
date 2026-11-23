/* Veranda Update: one HTTP/1.1 GET on vrnet, redirects followed (main
   RAM; DECISIONS V130).

   hurl is an absolute address, https:// (the modem's TLS: vrnet's net_tls,
   Zimodem's ATCS, which does not check the certificate) or http://, up
   to URLMAX - 1 bytes. A state machine stepped from the main loop
   (http_poll), so nothing waits:
     wait    the modem not ready yet
     send    the request, written as vrnet takes it:
               GET <path> HTTP/1.1, Host, User-Agent, Accept,
               Accept-Encoding: identity (no gzip), Connection: close
     head    the status line and the headers: Content-Length,
             Transfer-Encoding: chunked, Location (up to URLMAX - 1 bytes,
             read straight into hurl: the request has gone)
     body    to hsink: Content-Length's bytes (then done, without waiting
             for the close), chunks (their sizes in hex, the last 0), or
             everything until the server closes
   301, 302, 303, 307 and 308 with a Location: the connection closed and a
   new one opened to the new address, another host or the same (GitHub's
   release download answers 302 with a signed address on
   release-assets.githubusercontent.com or objects.githubusercontent.com),
   at most 6 times. A relative Location keeps the host. 200: the body;
   404: H_E404 (a file the release does not have); anything else
   H_ESTATUS. A connection that ends before its Content-Length or its
   last chunk: H_EDROP. Nothing for 30 s: H_ETIMEOUT.

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <string.h>
#include <vrnet.h>
#include <vrser.h>
#include "up.h"

/* (hurl: overlay 1's, job.c: http_poll runs with it mapped) */
unsigned int hstatus;
unsigned long hgot, hlen;
unsigned char hredir, hchunked;
signed char hnet;
unsigned char __fastcall__ (*hsink)(const unsigned char *b, unsigned int n);

#define T_IDLE 1800             /* frames with nothing coming (30 s) */
#define REDIR_MAX 6

enum { HS_IDLE, HS_WAIT, HS_SEND, HS_HEAD, HS_BODY, HS_CSIZE, HS_CDATA, HS_CEND, HS_DONE };
static unsigned char hs, hres;
static signed char sk = -1;
static unsigned int tlast;
static unsigned char tls;
static char host[64];
static unsigned int port;
static char portstr[7];
static unsigned int pathat;     /* the path's start in hurl */

/* the request's parts */
static const char *pp;
static unsigned char pi;
static const char r_get[] = "GET ";
static const char r_ver[] = " HTTP/1.1\r\nHost: ";
static const char r_tail[] = "\r\nUser-Agent: VerandaUpdate/1.0 (Commander X16)\r\nAccept: */*\r\n"
                             "Accept-Encoding: identity\r\nConnection: close\r\n\r\n";

/* the reply */
static char hl[64];             /* a header line, lower case (what does not fit is dropped) */
static unsigned char hln, firstline, loc, locsp;
static unsigned int locn;
static unsigned char hasloc;
static unsigned long left;      /* a body's or a chunk's bytes still to come */
static unsigned char cdig;      /* a chunk size's digits; 0xFF: past them (an extension) */
static unsigned char rb[256];

static void __fastcall__ fin(unsigned char e)
{
    if (sk >= 0)
        net_close(sk);
    sk = -1;
    hs = HS_DONE;
    hres = e;
}

static unsigned char __fastcall__ lower(unsigned char c)
{
    return c >= 'A' && c <= 'Z' ? c + 32 : c;
}

/* hurl's scheme, host and port (a relative one: those kept): 0 if bad */
static unsigned char parse(void)
{
    char *p = hurl, *h;
    unsigned char n;
    unsigned int v;
    if (hurl[0] == '/') {
        pathat = 0;
        return 1;
    }
    if (!memcmp(p, "https://", 8)) {
        tls = 1;
        port = 443;
        p += 8;
    } else if (!memcmp(p, "http://", 7)) {
        tls = 0;
        port = 80;
        p += 7;
    } else
        return 0;
    h = host;
    for (n = 0; *p && *p != '/' && *p != ':' && *p != '?'; ++p) {
        if (n == 61)
            return 0;
        *h++ = *p;
        ++n;
    }
    *h = 0;
    if (!n)
        return 0;
    if (*p == ':') {
        for (v = 0, ++p; *p >= '0' && *p <= '9'; ++p)
            v = v * 10 + (*p - '0');
        if (!v)
            return 0;
        port = v;
    }
    pathat = p - hurl;
    portstr[0] = 0;
    if (port != (tls ? 443 : 80)) {
        portstr[0] = ':';
        ui_num(portstr + 1, port);
    }
    return 1;
}

static void open_(void)
{
    hs = HS_WAIT;
    hstatus = 0;
    hlen = 0xFFFFFFFFUL;
    hchunked = 0;
    hln = 0;
    firstline = 1;
    loc = hasloc = 0;
    tlast = ser_frames;
    if (!net_on || net_state() == NET_FAULT)
        net_restart();
    if (!net_on)
        fin(H_ENOCARD);
}

void http_get(void)
{
    hredir = 0;
    hgot = 0;
    hnet = 0;
    if (!parse()) {
        hs = HS_DONE;
        hres = H_EURL;
        return;
    }
    open_();
}

void http_cancel(void)
{
    if (hs != HS_IDLE && hs != HS_DONE)
        fin(H_ECANCEL);
    hs = HS_IDLE;
}

/* the next part of the request; 0 at its end */
static const char *part(void)
{
    switch (pi++) {
    case 0: return r_get;
    case 1: return hurl[pathat] ? hurl + pathat : "/";
    case 2: return r_ver;
    case 3: return host;
    case 4: return portstr;
    case 5: return r_tail;
    }
    return 0;
}

/* the request written as vrnet takes it (through wb: vrnet maps its own
   bank at $A000 while it copies, and hurl is overlay 1's) */
static void push(void)
{
    static char wb[64];
    int k;
    unsigned int n;
    while (hs == HS_SEND) {
        if (!*pp) {
            pp = part();
            if (!pp) {
                hs = HS_HEAD;
                return;
            }
            continue;
        }
        n = strlen(pp);
        if (n > sizeof wb)
            n = sizeof wb;
        memcpy(wb, pp, n);
        k = net_write(sk, wb, n);
        if (k <= 0)
            return;
        pp += k;
    }
}

/* a header line has ended (in hl, lower case to its ':') */
static void header(void)
{
    char *p;
    hl[hln] = 0;
    if (firstline) {
        firstline = 0;
        if (memcmp(hl, "http/1.", 7) || hln < 12) {
            fin(H_EHDR);
            return;
        }
        hstatus = (hl[9] - '0') * 100 + (hl[10] - '0') * 10 + (hl[11] - '0');
        return;
    }
    if (!memcmp(hl, "content-length:", 15)) {
        for (p = hl + 15; *p == ' '; ++p)
            ;
        for (hlen = 0; *p >= '0' && *p <= '9'; ++p)
            hlen = hlen * 10 + (*p - '0');
    } else if (!memcmp(hl, "transfer-encoding:", 18) && strstr(hl + 18, "chunked"))
        hchunked = 1;
}

/* the headers have ended */
static void headers_end(void)
{
    if ((hstatus == 301 || hstatus == 302 || hstatus == 303 || hstatus == 307 || hstatus == 308) && hasloc) {
        if (sk >= 0)
            net_close(sk);
        sk = -1;
        if (++hredir > REDIR_MAX) {
            fin(H_EREDIR);
            return;
        }
        if (!parse()) {
            fin(H_EURL);
            return;
        }
        open_();
        return;
    }
    if (hstatus == 404) {
        fin(H_E404);
        return;
    }
    if (hstatus != 200) {
        fin(H_ESTATUS);
        return;
    }
    if (hchunked) {
        hs = HS_CSIZE;
        left = 0;
        cdig = 0;
        return;
    }
    hs = HS_BODY;
    left = hlen;
    if (!left)
        fin(H_OK);
}

/* body bytes to the sink */
static unsigned char __fastcall__ give(const unsigned char *b, unsigned int n)
{
    if (!n)
        return 1;
    hgot += n;
    if (!hsink(b, n)) {
        fin(H_ELOCAL);
        return 0;
    }
    return 1;
}

static unsigned char __fastcall__ hexv(unsigned char c)
{
    if (c >= '0' && c <= '9')
        return c - '0';
    c = lower(c);
    if (c >= 'a' && c <= 'f')
        return c - 'a' + 10;
    return 0xFF;
}

/* n received bytes in rb */
static void feed(unsigned int n)
{
    unsigned int i = 0, k;
    unsigned char c, v;
    while (i < n && hs != HS_DONE && hs != HS_WAIT) {
        switch (hs) {
        case HS_HEAD:
            c = rb[i++];
            if (c == '\n') {
                if (loc) {
                    while (locn && hurl[locn - 1] == ' ')
                        --locn;
                    hurl[locn] = 0;
                    loc = 0;
                    hasloc = locn > 0;
                    hln = 0;
                    break;
                }
                if (!hln) {
                    headers_end();
                    break;
                }
                header();
                hln = 0;
                break;
            }
            if (c == '\r')
                break;
            if (loc) {
                if (locsp && c == ' ')
                    break;
                locsp = 0;
                if (locn >= URLMAX - 1) {
                    fin(H_EURL);
                    break;
                }
                hurl[locn++] = c;
                break;
            }
            if (hln < sizeof hl - 1)
                hl[hln++] = lower(c);
            if (hln == 9 && !firstline && !memcmp(hl, "location:", 9)) {
                loc = locsp = 1;
                locn = 0;
            }
            break;
        case HS_BODY:
            k = n - i;
            if (hlen != 0xFFFFFFFFUL && k > left)
                k = (unsigned int)left;
            if (!give(rb + i, k))
                return;
            i += k;
            if (hlen != 0xFFFFFFFFUL) {
                left -= k;
                if (!left)
                    fin(H_OK);
            }
            break;
        case HS_CSIZE:
            c = rb[i++];
            if (c == '\n') {
                if (!cdig)
                    break;              /* (a blank line: tolerated) */
                if (!left) {
                    fin(H_OK);          /* the last chunk (its trailer not waited for) */
                    break;
                }
                hs = HS_CDATA;
                break;
            }
            if (cdig == 0xFF || c == '\r')
                break;
            v = hexv(c);
            if (v == 0xFF) {
                if (cdig)
                    cdig = 0xFF;        /* (";extension") */
                else if (c != ' ') {
                    fin(H_EHDR);
                    return;
                }
                break;
            }
            if (left >= 0x08000000UL) {
                fin(H_EHDR);
                return;
            }
            left = left << 4 | v;
            ++cdig;
            break;
        case HS_CDATA:
            k = n - i;
            if (k > left)
                k = (unsigned int)left;
            if (!give(rb + i, k))
                return;
            i += k;
            left -= k;
            if (!left) {
                hs = HS_CEND;
                cdig = 0;
            }
            break;
        case HS_CEND:                   /* the CR LF after a chunk's data */
            c = rb[i++];
            if (c == '\n') {
                hs = HS_CSIZE;
                left = 0;
                cdig = 0;
            }
            break;
        }
    }
}

unsigned char http_poll(void)
{
    unsigned char d;
    int n;
    net_poll();
    switch (hs) {
    case HS_IDLE:
        return H_RUN;
    case HS_DONE:
        hs = HS_IDLE;
        return hres;
    case HS_WAIT:
        d = net_state();
        if (d == NET_FAULT)
            fin(H_EMODEM);
        else if (d == NET_READY) {
            net_tls = tls;
            sk = net_open(host, port);
            net_tls = 0;
            if (sk < 0) {
                hnet = sk;
                sk = -1;
                fin(H_ECONN);
            } else {
                hs = HS_SEND;
                pi = 0;
                pp = "";
                tlast = ser_frames;
            }
        } else if (ser_frames - tlast > T_IDLE)
            fin(H_EMODEM);
        return H_RUN;
    }
    d = net_sock(sk);
    if (d == NET_FAILED || d == NET_FREE) {
        hnet = net_sockerr(sk);
        fin(hs == HS_SEND ? H_ECONN : H_EDROP);
        return H_RUN;
    }
    if (hs == HS_SEND)
        push();
    if (d == NET_OPENING || d == NET_DIAL) {
        tlast = ser_frames;
        return H_RUN;
    }
    if (hs == HS_SEND) {
        if (ser_frames - tlast > T_IDLE)
            fin(H_ETIMEOUT);
        return H_RUN;
    }
    n = net_read(sk, rb, sizeof rb);
    if (n > 0) {
        tlast = ser_frames;
        feed(n);
    } else if (n == NET_ECLOSED) {
        if (hs == HS_BODY && hlen == 0xFFFFFFFFUL)
            fin(H_OK);                  /* (no length: the close ends it) */
        else
            fin(hs == HS_HEAD && firstline ? H_ECONN : H_EDROP);
    } else if (n < 0) {
        hnet = n;
        fin(H_EDROP);
    } else if (ser_frames - tlast > T_IDLE)
        fin(H_ETIMEOUT);
    return H_RUN;
}
