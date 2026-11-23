/* Veranda Claude: one turn on vrnet (main RAM; DECISIONS V114).

   A turn is one connection (Connection: close): the modem's TLS
   connection to the API (vrnet's net_tls: ATCS"host:port"), the
   request written as vrnet takes it, the reply read and handed to
   parse.c (overlay 3), its text appended to the open reply in the
   store. A state machine stepped from the main loop, so nothing waits:
     wait   the modem not ready yet (vrnet looks for it)
     open   net_open'ed (the request starts going out at once: vrnet
            holds it until the modem has connected)
     send   the headers, then the body, made as it goes
     recv   the reply, until its end (message_stop, the last chunk) or
            the server's close
   The request: POST /v1/messages, HTTP/1.1, the API key, the API's
   version, the fallback beta (not for Haiku, which has none), the body's
   length (counted first: the body is made twice, once to count it).
   The body is JSON made from the store as it is sent: the model,
   max_tokens, "stream": true, "fallbacks": "default", low effort, the
   prompt cache (top-level cache_control), the system prompt and every
   message sent so far (the user's and Claude's; notes and turns left
   out are not), the text escaped: quotes, backslashes, control
   characters, and CP437's other characters as \uXXXX.

   Veranda Ask (-DASK, DECISIONS V116): the request is a list of parts
   (ask.h's struct part) that its overlay 5 lays out for each kind (a
   turn, the sign-in's renewal, the sign-in through the PC): text in main
   RAM, or bytes in a RAM bank (a token, an overlay's text), as they are,
   JSON-escaped or URL-encoded; the messages among them. A reply that is
   not a turn's (rq) goes to overlay 5 as lines key=value (kv_reply).

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <vr.h>
#include <string.h>
#include <vrnet.h>
#include <vrser.h>
#include "claude.h"

unsigned char tstate, tend, tdone, net_on;
signed char tnet;
unsigned long ttx, trx;
unsigned int tbody, tt0, tfirst;
unsigned char rbuf[256];
unsigned int rn;
#ifdef ASK
char dtext[272];                        /* (a read's 256 bytes and a line's "refresh=" made before them) */
#else
char dtext[256];
#endif
unsigned int dn;
unsigned int p_status, p_text;
unsigned char p_end, p_fb, p_errev;
#ifdef ASK
char p_stop[20], p_etype[48], p_emsg[160], p_model[40];   /* (Ask: the plan's codes are up to 43 characters) */
#else
char p_stop[16], p_etype[32], p_emsg[160], p_model[40];
#endif
unsigned long p_in, p_out, p_cache, p_cw;
#ifdef CLAUDE_TEST
unsigned char t_plain;
#endif
#ifdef ASK
unsigned char rq, t_cancel, p_ok, p_inc, p_jok, p_gz;
unsigned long p_body;
char p_param[24];
struct part parts[NPARTS];
unsigned char nparts, pbody;
#endif

static signed char sk = -1;
static unsigned int tlast;
static unsigned int glim;               /* the messages sent end here (the open reply) */

#define T_SILENT (120u * 60)            /* nothing for 2 minutes: given up */

/*---------------------------------------------------------------
  the body, a byte at a time (gen): a list of parts, each a literal,
  a string from main RAM or a message's text from the store, escaped
 ---------------------------------------------------------------*/
#ifndef ASK
static const char b_model[] = "{\"model\":\"";
static const char b_max[] = "\",\"max_tokens\":";
static const char b_stream[] = ",\"stream\":true,";
static const char b_fb[] = "\"fallbacks\":\"default\",";
static const char b_rest[] = "\"output_config\":{\"effort\":\"low\"},\"cache_control\":{\"type\":\"ephemeral\"},\"system\":\"";
static const char b_msgs[] = "\",\"messages\":[";
#endif
static const char b_user[] = "{\"role\":\"user\",\"content\":\"";
static const char b_asst[] = "{\"role\":\"assistant\",\"content\":\"";
static const char b_end[] = "\"}";
#ifndef ASK
static const char b_last[] = "]}";
#endif
#ifdef ASK
static unsigned char gbk, gfl;          /* a part's bank, its escape (P_RAW, P_JSON, P_URL) */
#endif

static unsigned char gst, gnext;        /* the part; the one after a literal or a string */
static unsigned char gi;                /* the head's next part */
static const char *gp;                 /* a literal's or a string's next byte */
static unsigned int ga, ge;             /* a message's text: next, end */
static unsigned int gm;                 /* the next message to look at */
static unsigned char gcomma;
static char gesc[7];
static unsigned char gescn, gescp;

#define G_LIT   0       /* gp until its 0, then gnext */
#define G_STR   1       /* gp escaped, then gnext */
#define G_HEAD  2       /* the head's next part (gi) */
#define G_TEXT  3       /* the store's ga .. ge escaped, then b_end, G_MSG */
#define G_MSG   4       /* the next message sent, or the end */
#define G_DONE  5
#ifdef ASK
#define G_PART  6       /* (Ask) a part's bytes (gbk, ga .. ge), then G_HEAD */
#endif

static const char hex[] = "0123456789abcdef";

/* c escaped into gesc */
static void __fastcall__ esc(unsigned char c)
{
    unsigned int u;
    gescp = 0;
    gescn = 2;
    gesc[0] = '\\';
    switch (c) {
    case '"': gesc[1] = '"'; return;
    case '\\': gesc[1] = '\\'; return;
    case '\n': gesc[1] = 'n'; return;
    case '\t': gesc[1] = 't'; return;
    case '\r': gesc[1] = 'r'; return;
    }
    if (c >= 32 && c < 127) {
        gesc[0] = c;
        gescn = 1;
        return;
    }
    u = cp_u(c);
    gesc[1] = 'u';
    gesc[2] = hex[u >> 12];
    gesc[3] = hex[(u >> 8) & 15];
    gesc[4] = hex[(u >> 4) & 15];
    gesc[5] = hex[u & 15];
    gescn = 6;
}

#ifdef ASK
/* c URL-encoded into gesc (what is not a letter, a digit or -._~) */
static void __fastcall__ uesc(unsigned char c)
{
    gescp = 0;
    gesc[0] = '%';
    gesc[1] = hex[c >> 4];
    gesc[2] = hex[c & 15];
    gescn = 3;
}

static unsigned char __fastcall__ plain_url(unsigned char c)
{
    return (c >= '0' && c <= '9') || ((c | 32) >= 'a' && (c | 32) <= 'z') || c == '-' || c == '.' || c == '_' || c == '~';
}
#endif

static void __fastcall__ lit(const char *s, unsigned char then)
{
    gp = s;
    gnext = then;
    gst = G_LIT;
}

/* the head's parts from part i on (0: the request's line and headers;
   B0: the body) */
#define B0 10
static void __fastcall__ gen_start(unsigned char i)
{
    gst = G_HEAD;
    gi = i;
    gm = g_from;                        /* (the Remember setting: V123) */
    gcomma = 0;
    gescn = gescp = 0;
}

#ifdef ASK
char hport[8], hlen_s[8];               /* (the parts point at them) */
#else
static char hport[8], hlen_s[8];
#endif

static unsigned char gcount;            /* gen counts (out is not written) */

/* the message text ga .. ge's length escaped (256 bytes at a time
   through rbuf: no reply is coming) */
static unsigned int __fastcall__ esc_len(unsigned int e)
{
    unsigned int a = ga, x = 0;
    unsigned char k, i, c;
    while (a < e) {
        k = e - a > 255 ? 255 : e - a;
        st_copy(a, (char *)rbuf, k);
        a += k;
        x += k;
        for (i = 0; i < k; ++i) {
            c = rbuf[i];
            if (c >= 32 && c < 127) {
                if (c == '"' || c == '\\')
                    ++x;
            } else if (c == '\n' || c == '\t' || c == '\r')
                ++x;
            else
                x += 5;                 /* (\uXXXX) */
        }
    }
    return x;
}

/* up to max bytes into out (main RAM); 0: the end */
static unsigned int __fastcall__ gen(unsigned char *out, unsigned int max)
{
    unsigned int n = 0, k, i;
    unsigned char keep = RAMBANK, c;
    static unsigned char tb[64];
    while (n < max) {
        if (gescp < gescn) {
            c = gesc[gescp++];
            if (!gcount)
                out[n] = c;
            ++n;
            continue;
        }
        switch (gst) {
        case G_LIT:
            c = *gp;
            if (c) {
                if (!gcount)
                    out[n] = c;
                ++n;
                ++gp;
            } else
                gst = gnext;
            break;
        case G_STR:
            c = *gp;
            if (c) {
                ++gp;
                esc(c);
            } else
                gst = gnext;
            break;
        case G_HEAD:
#ifdef ASK
            {
                struct part *pp;
                if (gi >= nparts) {
                    gst = G_DONE;
                    break;
                }
                pp = &parts[gi++];
                if (pp->bank == PB_MSGS)
                    gst = G_MSG;
                else if (pp->n == PZ)
                    lit((const char *)pp->a, G_HEAD);
                else {
                    gbk = pp->bank;
                    gfl = pp->fl;
                    ga = pp->a;
                    ge = ga + pp->n;
                    gst = G_PART;
                }
            }
            break;
        case G_PART:                    /* (a part's bytes, a block at a time) */
            if (ga >= ge) {
                gst = G_HEAD;
                break;
            }
            k = ge - ga;
            if (k > sizeof tb)
                k = sizeof tb;
            if (k > max - n)
                k = max - n;
            bk_get(gbk, ga, tb, k);
            for (i = 0; i < k; ++i) {
                c = tb[i];
                if (gfl == P_JSON && (c < 32 || c >= 127 || c == '"' || c == '\\')) {
                    esc(c);
                    ++i;
                    break;
                }
                if (gfl == P_URL && !plain_url(c)) {
                    uesc(c);
                    ++i;
                    break;
                }
                if (!gcount)
                    out[n] = c;
                ++n;
            }
            ga += i;
            break;
#else
            switch (gi++) {
            case 0: lit("POST /v1/messages HTTP/1.1\r\nHost: ", G_HEAD); break;
            case 1: lit(C.host, G_HEAD); break;
            case 2: lit(hport, G_HEAD); break;
            case 3: lit("\r\nUser-Agent: VerandaClaude/1.0 (Commander X16)\r\nContent-Type: application/json\r\n"
                        "Accept: text/event-stream\r\nx-api-key: ", G_HEAD); break;
            case 4: lit(C.key, G_HEAD); break;
            case 5: lit("\r\nanthropic-version: 2026-10-21\r\n", G_HEAD); break;
            case 6: lit(g_model == M_HAIKU ? b_last + 2 : "anthropic-beta: server-side-fallback-2026-07-01\r\n", G_HEAD); break;
            case 7: lit("Content-Length: ", G_HEAD); break;
            case 8: lit(hlen_s, G_HEAD); break;
            case 9: lit("\r\nConnection: close\r\n\r\n", G_HEAD); break;
            case B0: lit(b_model, G_HEAD); break;
            case B0 + 1: lit(model_id[g_model], G_HEAD); gst = G_STR; break;
            case B0 + 2: lit(b_max, G_HEAD); break;
            case B0 + 3: lit(g_max, G_HEAD); break;
            case B0 + 4: lit(b_stream, G_HEAD); break;
            case B0 + 5: lit(g_model == M_HAIKU ? b_last + 2 : b_fb, G_HEAD); break;  /* (Haiku has no fallback) */
            case B0 + 6: lit(b_rest, G_HEAD); break;
            case B0 + 7: lit(C.sys[0] ? C.sys : sys_default, G_HEAD); gst = G_STR; break;
            case B0 + 8: lit(C.shorta ? short_s : b_last + 2, G_HEAD); gst = G_STR; break;
            default: lit(b_msgs, G_MSG); break;
            }
            break;
#endif
        case G_TEXT:                    /* (a block at a time: plain bytes as they are) */
            {
                unsigned int pe = ge;   /* (up to the next block sent shortened: V123) */
                unsigned char j, js = 0xFF;
                for (j = 0; j < nsub; ++j)
                    if (sub_a[j] >= ga && sub_a[j] < pe) {
                        pe = sub_a[j];
                        js = j;
                    }
                if (gcount) {           /* (counted: the escaped length at once) */
                    n += esc_len(pe);
                    ga = pe;
                }
                if (ga >= pe) {
                    if (js == 0xFF) {
                        lit(b_end, G_MSG);
                        break;
                    }
                    ph_i = js;          /* its placeholder (plain ASCII, no quotes) */
                    ovv(ph_make);
                    ga = sub_e[js];
                    lit(gph, G_TEXT);
                    break;
                }
                k = pe - ga;
            }
            if (k > sizeof tb)
                k = sizeof tb;
            if (k > max - n)
                k = max - n;
            st_copy(ga, (char *)tb, k);
            for (i = 0; i < k; ++i) {
                c = tb[i];
                if (c < 32 || c >= 127 || c == '"' || c == '\\') {
                    esc(c);
                    ++i;
                    break;
                }
                out[n++] = c;
            }
            ga += i;
            break;
        case G_MSG:
            while (gm < glim) {
                ga = gm + 3;
                c = st_rd(gm);
                gm = ga + (st_rd(gm + 1) | (st_rd(gm + 2) << 8));
                if (SENT(c)) {
                    ge = gm;
                    lit(USERK(c) ? b_user : b_asst, G_TEXT);
                    if (gcomma) {               /* (the comma goes out first) */
                        gesc[0] = ',';
                        gescp = 0;
                        gescn = 1;
                    }
                    gcomma = 1;
                    goto next;
                }
            }
#ifdef ASK
            lit("]", G_HEAD);
#else
            lit(b_last, G_DONE);
#endif
        next:
            break;
        case G_DONE:
            RAMBANK = keep;
            return n;
        }
    }
    RAMBANK = keep;
    return n;
}

/*---------------------------------------------------------------
  the turn
 ---------------------------------------------------------------*/
static unsigned char obuf[128];
static unsigned char olen, opos;

static void __fastcall__ end(unsigned char e)
{
    if (sk >= 0)
        net_close(sk);
    sk = -1;
    tstate = T_IDLE;
    tend = e;
    tdone = 1;
}

unsigned char turn_start(void)
{
    if (!net_on || net_state() == NET_FAULT)
        net_restart();
    glim = st_cur;                      /* (the open reply: not sent) */
#ifdef ASK
    gen_start(pbody);                   /* the body counted */
#else
    gen_start(B0);                      /* the body counted */
#endif
    gcount = 1;
    tbody = gen(obuf, 0xFFFF);
    gcount = 0;
    hport[0] = 0;
    if (C.port != 443 && C.port != 80) {
        hport[0] = ':';
        unum(hport + 1, C.port);
    }
    unum(hlen_s, tbody);
    gen_start(0);
    olen = opos = 0;
    ttx = trx = 0;
    tfirst = 0;
    tt0 = tlast = ser_frames;
    tdone = 0;
    ov3(p_begin);
    tstate = T_WAIT;
    if (!net_on) {
        end(TE_NOCARD);
        return 0;
    }
    return 1;
}

void turn_stop(void)
{
#ifdef ASK
    if (rq == RQ_REFRESH) {             /* (the new tokens must come and be kept: the turn ends after) */
        t_cancel = 1;
        return;
    }
#endif
    if (tstate != T_IDLE)
        end(TE_STOP);
}

/* what is to go out, written as vrnet takes it */
static void pump(void)
{
    int k;
    while (tstate == T_SEND) {
        if (opos == olen) {
            opos = 0;
            olen = gen(obuf, sizeof obuf);
            if (!olen) {
                tstate = T_RECV;
                return;
            }
        }
        k = net_write(sk, obuf + opos, olen - opos);
        if (k <= 0)
            return;
        opos += k;
        ttx += k;
    }
}

void turn_poll(void)
{
    unsigned char d;
    int n;
    net_poll();
    if (tstate == T_IDLE)
        return;
    if (tstate == T_WAIT) {
        d = net_state();
        if (d == NET_FAULT)
            end(TE_MODEM);
        else if (d == NET_READY) {
            net_tls = C.tls;
#ifdef CLAUDE_TEST
            if (t_plain)
                net_tls = 0;
#endif
            sk = net_open(C.host, C.port);
            net_tls = 0;
            if (sk < 0) {
                tnet = sk;
                sk = -1;
                end(TE_CONNECT);
                return;
            }
            tstate = T_SEND;
            tlast = ser_frames;
        }
        return;
    }
    d = net_sock(sk);
    if (d == NET_FAILED || d == NET_FREE) {
        tnet = net_sockerr(sk);
        end(trx ? TE_NET : TE_CONNECT);
        return;
    }
    pump();
    if (d == NET_OPENING || d == NET_DIAL) {
        tlast = ser_frames;
        return;
    }
    n = net_read(sk, rbuf, sizeof rbuf);
    if (n > 0) {
        tlast = ser_frames;
        trx += n;
        rn = n;
#ifdef CLAUDE_TEST
        t_reads++;
        t_fp -= ser_frames;
#endif
        ov3(p_feed);
#ifdef ASK
        if (dn && rq != RQ_CHAT) {
            ov5(kv_reply);              /* (key=value lines: the tokens, the sign-in's set) */
            dn = 0;
        }
#endif
        if (dn) {
            if (!tfirst)
                tfirst = ser_frames;
            if (!st_append(dtext, dn)) {
                end(TE_FULL);
                return;
            }
        }
#ifdef CLAUDE_TEST
        t_fp += ser_frames;
#endif
        if (p_end)
            end(TE_OK);
    } else if (n == NET_ECLOSED) {
        end(p_end || (p_status && p_status != 200) ? TE_OK : TE_CLOSED);
    } else if (n < 0) {
        tnet = n;
        end(TE_NET);
    } else if (ser_frames - tlast > T_SILENT) {
        end(TE_TIMEOUT);
    }
}
