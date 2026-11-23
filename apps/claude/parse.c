/* Veranda Claude: the reply (overlay 3; DECISIONS V114).

   What the API sends, a byte at a time, so that nothing has to be held
   whole (a line of text can be as long as the API likes):
     the status line   HTTP/1.1 200 OK: the status kept
     the headers       Transfer-Encoding: chunked noted (the rest
                       skipped)
     the body          chunked: each chunk's size in hex, its bytes,
                       CR LF; a 0 chunk is the end; else as it comes
                       until the server closes
   A 200's body is server-sent events: lines "event: ...", "data: {...}"
   and empty ones; each data line is one JSON object. Another status's
   body is one JSON object (the error). Either goes through the JSON
   scanner: a state machine with a stack of the keys it is in (8 deep),
   which hands on the few values Veranda Claude reads:
     type                       the event's ("content_block_delta" ...)
     delta.text                 a text_delta's text: into dtext as it
                                comes (thinking blocks have no "text":
                                they are skipped, as are signatures)
     delta.stop_reason          end_turn, max_tokens, refusal ...
     error.type, error.message  an error event's, or a status's body
     message.model              the model that answered
     content_block.type         "fallback": another model went on
     usage's input_tokens, output_tokens, cache_read_input_tokens
   A string's escapes (\n \" \\ \/ \t, \uXXXX, a surrogate pair as one
   '?') and its raw UTF-8 make Unicode code points, folded to the font
   (V143: ISO-8859-16 at $A0-$FF, CP437's symbols below $20 and its box
   lines at $80-$9F): ASCII as it is, typographic quotes, dashes, the
   ellipsis, spaces and bullets to their plain forms, what the font has
   to its byte,
   accented letters it lacks to the plain letter, the rest '?'.

   Veranda Ask (-DASK, DECISIONS V116) reads other values (apps/ask/pick.c,
   in place of this file's keys, str_begin, str_end, lit_end and event):
   the Responses API's events, the token endpoint's JSON (its tokens as
   lines key=value in dtext), and the sign-in helper's reply (lines
   key=value already: into dtext as they come).

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <string.h>
#include "claude.h"
#pragma code-name ("OVERLAY3")
#pragma rodata-name ("OVL3RO")
#pragma bss-name ("OVL3BSS")

/* the HTTP layer */
#define H_STATUS 0
#define H_HEAD   1
#define H_BODY   2
static unsigned char hs, hn, chunked;
#ifdef ASK
static char hdl[56];                    /* a header line's start (lower case) */
static unsigned char hlen;              /* (V129) Content-Length came: the body ends at p_clen */
static unsigned long p_clen;
static unsigned int jl;                 /* a string's bytes (the log's lengths) */
#else
static char hdl[40];                     /* a header line's start (lower case) */
#endif
#define C_SIZE  0
#define C_EXT   1
#define C_DATA  2
#define C_CRLF  3
#define C_END   4
static unsigned char cs;
static unsigned long csz;

/* server-sent events: a line's start */
static unsigned char sse, ln_n, ln_data;
static char ln_head[6];

/* JSON */
#define J_VAL   0
#define J_STR   1
#define J_ESC   2
#define J_U     3
#define J_LIT   4
#define J_AFTER 5
#define J_KEY   6
#define J_COLON 7
#define J_DONE  8
#define DEPTH   8
static unsigned char js, jd, uc;
static unsigned char jobj[DEPTH + 1], jk[DEPTH + 1];
static char kb[28];                     /* (cache_creation_input_tokens: 27, V123) */
static unsigned char kn;
static unsigned int ju;
static char nb[12];
static unsigned char nn;
static unsigned char skip_low;          /* a high surrogate's '?' made: its low one dropped */
static unsigned char u8n;               /* UTF-8: continuation bytes to come */
static unsigned long u8;
/* the string being read: where it goes */
#define V_NONE  0
#define V_TEXT  1                       /* dtext */
#define V_CAP   2                       /* cap, up to capn - 1 */
static unsigned char vto;
static char *cap;
static unsigned char capn, capi;
#ifdef ASK
static char evtype[40], cbtype[12];
static unsigned char p_raw, kvs;        /* the sign-in's reply: its bytes as they are; a string made key=value */
#define K_OTHER 0
#else
static char evtype[24], cbtype[12];

/* the keys that matter */
#define K_OTHER   0
#define K_TYPE    1
#define K_DELTA   2
#define K_TEXT    3
#define K_STOP    4
#define K_ERROR   5
#define K_MESSAGE 6
#define K_MODEL   7
#define K_CBLOCK  8
#define K_USAGE   9
#define K_IN      10
#define K_OUT     11
#define K_CACHE   12
#define K_CW      13
static const char *const keys[] = { "", "type", "delta", "text", "stop_reason", "error", "message", "model",
    "content_block", "usage", "input_tokens", "output_tokens", "cache_read_input_tokens",
    "cache_creation_input_tokens" };
#define NKEYS 14
#endif

void p_begin(void)
{
    hs = H_STATUS;
    hn = chunked = 0;
    cs = C_SIZE;
    csz = 0;
    sse = ln_n = ln_data = 0;
    js = J_DONE;
    p_status = p_text = 0;
    p_end = p_fb = p_errev = 0;
    p_stop[0] = p_etype[0] = p_emsg[0] = p_model[0] = 0;
    p_in = p_out = p_cache = p_cw = 0;
    evtype[0] = 0;
#ifdef ASK
    p_ok = p_inc = p_raw = kvs = 0;
    p_param[0] = 0;
    p_jok = p_gz = hlen = lg_tkn = lg_tkx = 0;
    p_body = p_clen = 0;
    ov4(lg_req0);                       /* (V131: the request's lines; a 401's turn kept: logclk.c, logq.c) */
    ovc(lg_req);
#endif
}

static void j_reset(void)
{
    js = J_VAL;
    jd = 0;
    jk[0] = K_OTHER;
    evtype[0] = cbtype[0] = 0;
    skip_low = u8n = 0;
}

/*---------------------------------------------------------------- text out */

static void __fastcall__ out(unsigned char c)
{
    if (vto == V_TEXT) {
        if (dn < sizeof dtext) {
            dtext[dn++] = c;
            ++p_text;
        }
    } else if (vto == V_CAP && capi < capn - 1) {
        cap[capi++] = c;
        cap[capi] = 0;
    }
}

static void __fastcall__ outs(const char *s)
{
    while (*s)
        out(*s++);
}

/* Latin-1 and Latin Extended-A letters without their accents (U+00C0-017F) */
static const char fold[] =
    "AAAAAAACEEEEIIIIDNOOOOOxOUUUUYPsaaaaaaaceeeeiiiidnooooo/ouuuuypy"
    "AaAaAaCcCcCcCcDdDdEeEeEeEeEeGgGgGgGgHhHhIiIiIiIiIiIiJjKkkLlLlLlLlLlNnNnNnnNnOoOoOoOoRrRrRrSsSsSsSsTtTtTtUuUuUuUuUuUuWwYyYZzZzZzs";

/* what is not CP437's own: typographic quotes, dashes, the ellipsis,
   spaces ("" dropped: zero-width ones, the soft hyphen), bullets (CP437's
   7, its small square), ticks and crosses, arrows, a few signs */
static const unsigned int spec[] = {
    0x2018, 0x2019, 0x201A, 0x201B, 0x2032, 0x2035,
    0x201C, 0x201D, 0x201E, 0x201F, 0x2033,
    0x2010, 0x2011, 0x2012, 0x2013, 0x2014, 0x2015, 0x2212, 0x2043,
    0x2026,
    0x00A0, 0x2007, 0x202F, 0x205F, 0x3000,
    0x00AD, 0x200B, 0x200C, 0x200D, 0x2060, 0xFEFF,
    0x25CF, 0x2023, 0x25E6, 0x2027,
    0x25AA, 0x25FE, 0x25FC,
    0x2713, 0x2714, 0x2705,
    0x2717, 0x2718, 0x274C, 0x00D7,
    0x21D2, 0x21D0, 0x27A1, 0x2794,
    0x2122, 0x00AE, 0x00BD, 0x00BC, 0x00BE,
};
static const char *const spec_s[] = {
    "'", "'", "'", "'", "'", "'",
    "\"", "\"", "\"", "\"", "\"",
    "-", "-", "-", "-", "-", "-", "-", "-",
    "...",
    " ", " ", " ", " ", " ",
    "", "", "", "", "", "",
    "\7", "\7", "\7", "\7",
    "\201", "\201", "\201",
    "\202", "\202", "\202",
    "x", "x", "x", "x",
    "=>", "<=", "\32", "\32",
    "TM", "(R)", "1/2", "1/4", "3/4",
};
#define NSPEC (sizeof spec / sizeof spec[0])

/* code point u in the font */
static void __fastcall__ cp(unsigned long u)
{
    unsigned int v;
    unsigned char c;
    if (u > 0xFFFF) {
        out('?');
        return;
    }
    v = u;
    if (v < 128) {
        if (v == '\n')
            out('\n');
        else if (v == '\t')
            out(' ');
        else if (v >= 32 && v < 127)
            out(v);
        return;                         /* (other control characters dropped) */
    }
    for (c = 0; c < NSPEC; ++c)
        if (spec[c] == v) {
            outs(spec_s[c]);
            return;
        }
    if (v >= 0x2000 && v <= 0x200A) {
        out(' ');
        return;
    }
    c = cp_of(v);
    if (c) {
        out(c);
        return;
    }
    if (v >= 0xC0 && v < 0x180) {
        out(fold[v - 0xC0]);
        return;
    }
    out('?');
}

/* a \uXXXX: surrogate pairs (an emoji, mostly) as one '?' */
static void __fastcall__ ucode(unsigned int u)
{
    if (u >= 0xD800 && u < 0xDC00) {
        out('?');
        skip_low = 1;
        return;
    }
    if (u >= 0xDC00 && u < 0xE000) {
        if (!skip_low)
            out('?');
        skip_low = 0;
        return;
    }
    skip_low = 0;
    cp(u);
}

/* a raw byte of a string: UTF-8 */
static void __fastcall__ sbyte(unsigned char c)
{
    skip_low = 0;
    if (u8n) {
        if ((c & 0xC0) == 0x80) {
            u8 = (u8 << 6) | (c & 0x3F);
            if (!--u8n)
                cp(u8);
            return;
        }
        u8n = 0;
        out('?');
    }
    if (c < 0x80)
        cp(c);
    else if ((c & 0xE0) == 0xC0) {
        u8 = c & 0x1F;
        u8n = 1;
    } else if ((c & 0xF0) == 0xE0) {
        u8 = c & 0x0F;
        u8n = 2;
    } else if ((c & 0xF8) == 0xF0) {
        u8 = c & 0x07;
        u8n = 3;
    } else
        out('?');
}

/*---------------------------------------------------------------- JSON */

#ifdef ASK
#include "pick.c"
#else
static unsigned char __fastcall__ key_of(void)
{
    unsigned char i;
    for (i = 1; i < NKEYS; ++i)
        if (!strcmp(kb, keys[i]))
            return i;
    return K_OTHER;
}

/* a string value begins: where it goes */
static void str_begin(void)
{
    unsigned char k = jk[jd], up = jd > 1 ? jk[jd - 1] : K_OTHER;
    vto = V_CAP;
    capi = 0;
    if (jd == 1 && k == K_TYPE) {
        cap = evtype;
        capn = sizeof evtype;
    } else if (jd == 2 && up == K_DELTA && k == K_TEXT && !strcmp(evtype, "content_block_delta")) {
        vto = V_TEXT;
    } else if (jd == 2 && up == K_DELTA && k == K_STOP) {
        cap = p_stop;
        capn = sizeof p_stop;
    } else if (jd == 2 && up == K_ERROR && k == K_MESSAGE) {
        cap = p_emsg;
        capn = sizeof p_emsg;
    } else if (jd == 2 && up == K_ERROR && k == K_TYPE) {
        cap = p_etype;
        capn = sizeof p_etype;
    } else if (jd == 2 && up == K_MESSAGE && k == K_MODEL) {
        cap = p_model;
        capn = sizeof p_model;
    } else if (jd == 2 && up == K_CBLOCK && k == K_TYPE) {
        cap = cbtype;
        capn = sizeof cbtype;
    } else
        vto = V_NONE;
    if (vto == V_CAP)
        cap[0] = 0;
}

static void str_end(void)
{
    if (cap == cbtype && vto == V_CAP && !strcmp(cbtype, "fallback"))
        p_fb = 1;
    vto = V_NONE;
}

/* a number (or true, false, null) ended */
static void lit_end(void)
{
    unsigned long v = 0;
    unsigned char i, k = jk[jd];
    nb[nn] = 0;
    if (jd < 2 || jk[jd - 1] != K_USAGE || (k != K_IN && k != K_OUT && k != K_CACHE && k != K_CW))
        return;
    for (i = 0; nb[i] >= '0' && nb[i] <= '9'; ++i)
        v = v * 10 + nb[i] - '0';
    if (k == K_IN)
        p_in = v;
    else if (k == K_OUT)
        p_out = v;
    else if (k == K_CW)
        p_cw = v;
    else
        p_cache = v;
}

#endif

static void __fastcall__ open_(unsigned char obj)
{
    if (jd < DEPTH)
        ++jd;
    jobj[jd] = obj;
    jk[jd] = K_OTHER;
    js = obj ? J_KEY : J_VAL;
}

static void close_(void)
{
    if (jd)
        --jd;
    js = jd ? J_AFTER : J_DONE;
#ifdef ASK
    p_jok = !jd;
#endif
}

static void __fastcall__ jbyte(unsigned char c)
{
    unsigned char ws = c == ' ' || c == '\t' || c == '\r' || c == '\n';
#ifdef ASK
    if (js >= J_STR && js <= J_U)
        ++jl;                           /* (the closing quote too) */
#endif
    switch (js) {
    case J_DONE:
        return;
    case J_VAL:
        if (ws)
            return;
        if (c == '"') {
            kn = 0;
            uc = 0;
#ifdef ASK
            jl = 0;
#endif
            str_begin();
            js = J_STR;
        } else if (c == '{')
            open_(1);
        else if (c == '[')
            open_(0);
        else if (c == ']' || c == '}')
            close_();
        else {
            nn = 0;
            nb[nn++] = c;
            js = J_LIT;
        }
        return;
    case J_KEY:
        if (c == '"') {
            kn = 0;
            uc = 1;                     /* (a key's string) */
            js = J_STR;
        } else if (c == '}')
            close_();
        return;
    case J_COLON:
        if (c == ':')
            js = J_VAL;
        return;
    case J_STR:
        if (c == '"') {
            if (uc) {
                kb[kn] = 0;
                jk[jd] = key_of();
                js = J_COLON;
            } else {
                str_end();
                js = J_AFTER;
            }
        } else if (c == '\\')
            js = J_ESC;
        else if (uc) {
            if (kn < sizeof kb - 1)
                kb[kn++] = c;
        } else if (vto)
            sbyte(c);
        return;
    case J_ESC:
        js = J_STR;
        if (c == 'u') {
            js = J_U;
            ju = 0;
            nn = 0;
            return;
        }
        switch (c) {
        case 'n': c = '\n'; break;
        case 't': c = '\t'; break;
        case 'r': case 'b': case 'f': return;
        }
        if (uc) {
            if (kn < sizeof kb - 1)
                kb[kn++] = c;
        } else if (vto)
            sbyte(c);
        return;
    case J_U:
        ju <<= 4;
        if (c >= '0' && c <= '9')
            ju |= c - '0';
        else if ((c | 32) >= 'a' && (c | 32) <= 'f')
            ju |= (c | 32) - 'a' + 10;
        if (++nn == 4) {
            js = J_STR;
            if (!uc && vto)
                ucode(ju);
        }
        return;
    case J_LIT:
        if (!ws && c != ',' && c != '}' && c != ']') {
            if (nn < sizeof nb - 1)
                nb[nn++] = c;
            return;
        }
        lit_end();
        js = J_AFTER;
        /* (on: the byte that ended it) */
    case J_AFTER:
        if (c == ',')
            js = jobj[jd] ? J_KEY : J_VAL;
        else if (c == '}' || c == ']')
            close_();
        return;
    }
}

#ifndef ASK
/* a data line ended: its event */
static void event(void)
{
    if (!strcmp(evtype, "message_stop"))
        p_end = 1;
    else if (!strcmp(evtype, "error"))
        p_errev = 1;
}

#endif

/*---------------------------------------------------------------- the body's bytes */

static void __fastcall__ content(unsigned char c)
{
    unsigned char i;
#ifdef ASK
    ++p_body;
    if (p_status != 200 && p_body <= 360) {     /* (V131: room for the facts after it) */
        lg_ch = c;
        ovh(lg_red);
    }
    if (hlen && p_body >= p_clen)
        p_end = 1;                      /* (V129: Content-Length's end; the server may keep the connection) */
    if (p_raw) {                        /* (the sign-in helper's lines) */
        vto = V_TEXT;
        out(c);
        return;
    }
#endif
    if (!sse) {                         /* (not a 200: one JSON object) */
        jbyte(c);
        return;
    }
    if (c == '\n') {
        if (ln_data)
            event();
        ln_n = ln_data = 0;
        return;
    }
    if (ln_data) {
        jbyte(c);
        return;
    }
    if (ln_n < 5) {                     /* "data:" */
        ln_head[ln_n++] = c;
        if (ln_n == 5) {
            for (i = 0; i < 5 && ln_head[i] == "data:"[i]; ++i)
                ;
            if (i == 5) {
                ln_data = 1;
                j_reset();
            } else
                ln_n = 6;               /* (another field: skipped) */
        }
    }
}

static unsigned char __fastcall__ lower(unsigned char c)
{
    return c >= 'A' && c <= 'Z' ? c + 32 : c;
}

static void __fastcall__ hbyte(unsigned char c)
{
    unsigned char i;
    if (c == '\r')
        return;
    if (c != '\n') {
        if (hn < sizeof hdl - 1)
            hdl[hn++] = lower(c);
        return;
    }
    hdl[hn] = 0;
#ifdef ASK
    if (hn)
        lg_hdr(hdl, hn);                /* (V129: the log; a cookie's value never; V131: tok.c's) */
#endif
    if (hs == H_STATUS) {
        if (!hn)
            return;                     /* (the empty line after a 100) */
        for (i = 0; hdl[i] && hdl[i] != ' '; ++i)
            ;
        while (hdl[i] == ' ')
            ++i;
        for (; hdl[i] >= '0' && hdl[i] <= '9'; ++i)
            p_status = p_status * 10 + hdl[i] - '0';
        if (p_status == 100)            /* (100 Continue: another status line comes) */
            p_status = 0;
        else
            hs = H_HEAD;
    } else if (!hn) {
        hs = H_BODY;
#ifdef ASK
        sse = p_status == 200 && rq == RQ_CHAT;
        p_raw = rq == RQ_SIGNIN;
        if (hlen && !p_clen)
            p_end = 1;
        lg_b = lg_n;                    /* (V131: a 401's turn keeps its lines from here) */
        lg_s(p_status == 200 ? (rq == RQ_REFRESH ? "keys: " : "") : "body:\n");
#else
        sse = p_status == 200;
#endif
        if (!sse)
            j_reset();
    } else if (!strncmp(hdl, "transfer-encoding:", 18) && strstr(hdl, "chunked"))
        chunked = 1;
#ifdef ASK
    else if (!strncmp(hdl, "content-length:", 15)) {
        hlen = 1;
        for (i = 15; hdl[i] == ' '; ++i)
            ;
        for (; hdl[i] >= '0' && hdl[i] <= '9'; ++i)
            p_clen = p_clen * 10 + hdl[i] - '0';
    } else if (!strncmp(hdl, "content-encoding:", 17) && !strstr(hdl, "identity"))
        p_gz = 1;
#endif
    hn = 0;
}

static unsigned char __fastcall__ hexv(unsigned char c)
{
    c = lower(c);
    if (c >= '0' && c <= '9')
        return c - '0';
    if (c >= 'a' && c <= 'f')
        return c - 'a' + 10;
    return 0xFF;
}

void p_feed(void)
{
    unsigned int i;
    unsigned char c, v;
    dn = 0;
    for (i = 0; i < rn; ++i) {
        c = rbuf[i];
        if (hs != H_BODY) {
            hbyte(c);
            continue;
        }
        if (!chunked) {
            content(c);
            continue;
        }
        switch (cs) {
        case C_SIZE:
            v = hexv(c);
            if (v != 0xFF)
                csz = (csz << 4) | v;
            else if (c == '\n') {
                cs = csz ? C_DATA : C_END;
                if (!csz)
                    p_end = 1;
            } else if (c == ';')
                cs = C_EXT;
            break;
        case C_EXT:
            if (c == '\n') {
                cs = csz ? C_DATA : C_END;
                if (!csz)
                    p_end = 1;
            }
            break;
        case C_DATA:
            content(c);
            if (!--csz)
                cs = C_CRLF;
            break;
        case C_CRLF:
            if (c == '\n')
                cs = C_SIZE;
            break;
        }
    }
}

/*---------------------------------------------------------------- CP437 to Unicode (to the rows' bank) */

/* the font's Unicode (V143): CP437's for $00-$7F (its symbols at $01-$1F),
   at $80-$9F the private glyphs (main.c: CP437's pi, square, root, shades,
   blocks and box lines), at $A0-$FF Veranda's set, ISO-8859-16 */
static const unsigned int cp437u[256] = {
    0x0000, 0x263A, 0x263B, 0x2665, 0x2666, 0x2663, 0x2660, 0x2022,
    0x25D8, 0x25CB, 0x25D9, 0x2642, 0x2640, 0x266A, 0x266B, 0x263C,
    0x25BA, 0x25C4, 0x2195, 0x203C, 0x00B6, 0x00A7, 0x25AC, 0x21A8,
    0x2191, 0x2193, 0x2192, 0x2190, 0x221F, 0x2194, 0x25B2, 0x25BC,
    0x0020, 0x0021, 0x0022, 0x0023, 0x0024, 0x0025, 0x0026, 0x0027,
    0x0028, 0x0029, 0x002A, 0x002B, 0x002C, 0x002D, 0x002E, 0x002F,
    0x0030, 0x0031, 0x0032, 0x0033, 0x0034, 0x0035, 0x0036, 0x0037,
    0x0038, 0x0039, 0x003A, 0x003B, 0x003C, 0x003D, 0x003E, 0x003F,
    0x0040, 0x0041, 0x0042, 0x0043, 0x0044, 0x0045, 0x0046, 0x0047,
    0x0048, 0x0049, 0x004A, 0x004B, 0x004C, 0x004D, 0x004E, 0x004F,
    0x0050, 0x0051, 0x0052, 0x0053, 0x0054, 0x0055, 0x0056, 0x0057,
    0x0058, 0x0059, 0x005A, 0x005B, 0x005C, 0x005D, 0x005E, 0x005F,
    0x0060, 0x0061, 0x0062, 0x0063, 0x0064, 0x0065, 0x0066, 0x0067,
    0x0068, 0x0069, 0x006A, 0x006B, 0x006C, 0x006D, 0x006E, 0x006F,
    0x0070, 0x0071, 0x0072, 0x0073, 0x0074, 0x0075, 0x0076, 0x0077,
    0x0078, 0x0079, 0x007A, 0x007B, 0x007C, 0x007D, 0x007E, 0x2302,
    0x03C0, 0x25A0, 0x221A, 0x2591, 0x2592, 0x2593, 0x2502, 0x2524,
    0x2510, 0x2514, 0x2534, 0x252C, 0x251C, 0x2500, 0x253C, 0x2518,
    0x250C, 0x2588, 0x2584, 0x258C, 0x2590, 0x2580, 0x2551, 0x2550,
    0x2554, 0x2557, 0x255A, 0x255D, 0x2560, 0x2563, 0x2566, 0x2569,
    0x00A0, 0x0104, 0x0105, 0x0141, 0x20AC, 0x201E, 0x0160, 0x00A7,
    0x0161, 0x00A9, 0x0218, 0x00AB, 0x0179, 0x00AD, 0x017A, 0x017B,
    0x00B0, 0x00B1, 0x010C, 0x0142, 0x017D, 0x201D, 0x00B6, 0x00B7,
    0x017E, 0x010D, 0x0219, 0x00BB, 0x0152, 0x0153, 0x0178, 0x017C,
    0x00C0, 0x00C1, 0x00C2, 0x0102, 0x00C4, 0x0106, 0x00C6, 0x00C7,
    0x00C8, 0x00C9, 0x00CA, 0x00CB, 0x00CC, 0x00CD, 0x00CE, 0x00CF,
    0x0110, 0x0143, 0x00D2, 0x00D3, 0x00D4, 0x0150, 0x00D6, 0x015A,
    0x0170, 0x00D9, 0x00DA, 0x00DB, 0x00DC, 0x0118, 0x021A, 0x00DF,
    0x00E0, 0x00E1, 0x00E2, 0x0103, 0x00E4, 0x0107, 0x00E6, 0x00E7,
    0x00E8, 0x00E9, 0x00EA, 0x00EB, 0x00EC, 0x00ED, 0x00EE, 0x00EF,
    0x0111, 0x0144, 0x00F2, 0x00F3, 0x00F4, 0x0151, 0x00F6, 0x015B,
    0x0171, 0x00F9, 0x00FA, 0x00FB, 0x00FC, 0x0119, 0x021B, 0x00FF
};

/* (V123) the table to the rows' bank, at the start */
void cp_init(void)
{
    unsigned char k;
    for (k = 0; k < 4; ++k) {
        memcpy(line, (const char *)cp437u + k * 128, 128);
        rb_put(0x1A00 + k * 128, line, 128);
    }
}
