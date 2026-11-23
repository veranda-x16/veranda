/* Veranda Gemini: web pages (overlay 4; DECISIONS V124).

   An http(s) address (a link's, or typed) goes one of three ways, as the
   setting says (File > Settings...):
     ask        a box: Yes through NewsWaffle, No through my proxy, Cancel
     NewsWaffle go becomes NewsWaffle's view address with the page's URL
                as its query, percent-encoded (NewsWaffle's CgiPaths.ViewAuto:
                /cgi-bin/waffle.cgi/view?<URL, UrlEncode'd>); a public
                service at gemi.dev that turns web pages into gemtext
     my proxy   go stays the web address: the request line is the absolute
                http(s) URL, sent to the proxy's host (url.c's u_host): a
                Gemini proxy request, which tools/web_proxy.py, Duckling
                and levior take
     never      the box that says web pages are off
   A link on a page that came from the proxy (its host and port the
   proxy's) goes back through it without asking: the proxy's own pages
   (its search) and the pages it converted.

   The setting, the proxy (host:port, 1965 when no port) and NewsWaffle's
   address (another instance can be named) are in GEMINI.CFG in
   /VERANDA/.SYSTEM, lines of key=value:

       web=0            0 ask, 1 NewsWaffle, 2 my proxy, 3 never
       proxy=192.168.1.20:1965
       waffle=gemini://gemi.dev/cgi-bin/waffle.cgi/view
       wplang=pl        Wikipedia's language (wiki.c, V128; en at first)
       wiki=gemini://gemi.dev/cgi-bin/wp.cgi   another Gemipedia (written
                        only when it is not this one)

   (marks.c reads and writes the file through main RAM's line: 185 bytes
   at most are read, so save() leaves out a line that would not fit.)

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <string.h>
#include "gemini.h"
#pragma code-name ("OVERLAY4")
#pragma rodata-name ("OVL4RO")
#pragma bss-name ("OVL4BSS")

#define W_ASK    0
#define W_WAFFLE 1
#define W_PROXY  2
#define W_NEVER  3
#define PROXYMAX 61
#define WAFFLEMAX 80

static unsigned char wmode;
static char proxy[PROXYMAX + 1];        /* host:port ("": none) */
static char waffle[WAFFLEMAX];
static char keep[HOSTMAX];

/* (doc.c's) code points written as short ASCII: the code point, up to 3
   characters; an emoji U+1Fxxx as U+Exxx. Copied to the font's bank at
   $BC00 at the start (main RAM had no room for them). */
#define SP(u, a, b, c) (u) & 255, (u) >> 8, a, b, c
static const char spt[] = {
    SP(0x2018, 39, 0, 0), SP(0x2019, 39, 0, 0), SP(0x201A, 39, 0, 0), SP(0x201B, 39, 0, 0), SP(0x2032, 39, 0, 0),
    SP(0x2035, 39, 0, 0),
    SP(0x201C, '"', 0, 0), SP(0x201D, '"', 0, 0), SP(0x201E, '"', 0, 0), SP(0x201F, '"', 0, 0), SP(0x2033, '"', 0, 0),
    SP(0x2010, '-', 0, 0), SP(0x2011, '-', 0, 0), SP(0x2012, '-', 0, 0), SP(0x2013, '-', 0, 0), SP(0x2014, '-', 0, 0),
    SP(0x2015, '-', 0, 0), SP(0x2212, '-', 0, 0), SP(0x2043, '-', 0, 0),
    SP(0x2026, '.', '.', '.'),
    SP(0x00A0, ' ', 0, 0), SP(0x2007, ' ', 0, 0), SP(0x202F, ' ', 0, 0), SP(0x205F, ' ', 0, 0), SP(0x3000, ' ', 0, 0),
    SP(0x00AD, 0, 0, 0), SP(0x200B, 0, 0, 0), SP(0x200C, 0, 0, 0), SP(0x200D, 0, 0, 0), SP(0x2060, 0, 0, 0),
    SP(0xFEFF, 0, 0, 0), SP(0xFE0F, 0, 0, 0), SP(0xFE0E, 0, 0, 0),
    SP(0x25CF, 7, 0, 0), SP(0x2023, 7, 0, 0), SP(0x25E6, 7, 0, 0), SP(0x2027, 7, 0, 0), SP(0x2022, 7, 0, 0),
    SP(0x2713, 130, 0, 0), SP(0x2714, 130, 0, 0), SP(0x2705, 130, 0, 0),     /* (the root, private: V143) */
    SP(0x2717, 'x', 0, 0), SP(0x2718, 'x', 0, 0), SP(0x274C, 'x', 0, 0), SP(0x00D7, 'x', 0, 0), SP(0x2716, 'x', 0, 0),
    SP(0x21D2, '=', '>', 0), SP(0x21D0, '<', '=', 0), SP(0x27A1, 26, 0, 0), SP(0x2794, 26, 0, 0), SP(0x2192, 26, 0, 0),
    SP(0x2190, 27, 0, 0), SP(0x2B05, 27, 0, 0), SP(0x2191, 24, 0, 0), SP(0x2B06, 24, 0, 0), SP(0x2193, 25, 0, 0),
    SP(0x2B07, 25, 0, 0),
    SP(0x23E9, '>', '>', 0), SP(0x23EA, '<', '<', 0), SP(0x23ED, '>', '>', '|'), SP(0x23EE, '|', '<', '<'), SP(0x25B6, '>', 0, 0),
    SP(0x25C0, '<', 0, 0), SP(0x2B50, '*', 0, 0), SP(0x2605, '*', 0, 0), SP(0x2606, '*', 0, 0), SP(0x2728, '*', 0, 0),
    SP(0x26A0, '!', 0, 0), SP(0x2757, '!', 0, 0), SP(0x2795, '+', 0, 0), SP(0x2796, '-', 0, 0),
    SP(0xE3B2, '*', 0, 0),                /* (U+1F3B2, a die) */
    SP(0xE449, '-', '>', 0), SP(0xE448, '<', '-', 0), SP(0xE519, '<', '-', 0), SP(0xE51D, '^', 0, 0),
    SP(0x2122, 'T', 'M', 0), SP(0x00AE, '(', 'R', ')'),     /* (V143: the euro and (c) the set's own) */
    0, 0
};

/* (main.c's glyph) the glyphs (11 x 11, as the shell's minis; bit 15
   the left pixel), copied to the font's bank at $BE00 at the start (main
   RAM's room: V128) */
static const unsigned int glyphs[G_N][11] = {
    { 0x0000, 0xF000, 0x8FE0, 0x8020, 0x8020, 0x8020, 0x8020, 0x8020, 0x8020, 0xFFE0, 0x0000 },     /* folder */
    { 0x7F80, 0x4080, 0x4080, 0x5E80, 0x4080, 0x5E80, 0x4080, 0x5E80, 0x4080, 0x4080, 0x7F80 },     /* text */
    { 0x1E00, 0x2100, 0x4080, 0x4080, 0x4080, 0x4080, 0x2100, 0x1E80, 0x0040, 0x0020, 0x0000 },     /* search */
    { 0x4300, 0xC480, 0x4480, 0x4480, 0xE300, 0x0000, 0x3080, 0x4980, 0x4880, 0x4880, 0x31C0 },     /* binary */
    { 0x0000, 0xFFE0, 0x8020, 0x81A0, 0x81A0, 0x8820, 0x9C20, 0xBEA0, 0xFFE0, 0x0000, 0x0000 },     /* picture */
    { 0x0000, 0xFFE0, 0xC060, 0xA0A0, 0x9120, 0x8A20, 0x8420, 0x8020, 0xFFE0, 0x0000, 0x0000 },     /* mail */
    { 0x1F00, 0x2480, 0x4A40, 0x8A20, 0xFFE0, 0x8A20, 0xFFE0, 0x8A20, 0x4A40, 0x2480, 0x1F00 },     /* web */
    { 0x0000, 0x0200, 0x0300, 0x0380, 0xFFC0, 0xFFE0, 0xFFC0, 0x0380, 0x0300, 0x0200, 0x0000 },     /* link */
    { 0x0000, 0x0C00, 0x1800, 0x3000, 0x6000, 0xFFE0, 0x6000, 0x3000, 0x1800, 0x0C00, 0x0000 },     /* back */
    { 0x0000, 0x0600, 0x0300, 0x0180, 0x00C0, 0xFFE0, 0x00C0, 0x0180, 0x0300, 0x0600, 0x0000 },     /* forward */
    { 0x0400, 0x0A00, 0x1100, 0x2080, 0x4040, 0xFFE0, 0x2080, 0x2E80, 0x2A80, 0x2A80, 0x3B80 },     /* home */
};

/* a number (KB; 16 at least) */
static unsigned int __fastcall__ katoi(const char *s)
{
    unsigned int v = 0;
    while (*s >= '0' && *s <= '9')
        v = v * 10 + *s++ - '0';
    return v < 16 ? 16 : v;
}

/* the start: GEMINI.CFG (an overlay's BSS is not cleared); the table above */
void w_load(void)
{
    char *p = line, *e;
    char c;
    BankCopy((void *)spt, (void *)0xBC00, sizeof spt, bOv4, doc_bank + DOCBANKS + 1);
    wmode = W_ASK;
    pic_kb = 256;
    memset(proxy, 0, sizeof proxy);
    memset(waffle, 0, sizeof waffle);
    strcpy(waffle, "gemini://gemi.dev/cgi-bin/waffle.cgi/view");
    k_init();                           /* (Wikipedia's: V128) */
    BankCopy((void *)glyphs, (void *)0xBE00, sizeof glyphs, bOv4, doc_bank + DOCBANKS + 1);
    ov2(cfg_read);
    for (;;) {
        for (e = p; *e && *e != '\r' && *e != '\n'; ++e)
            ;
        c = *e;
        *e = 0;
        if (!memcmp(p, "web=", 4))
            wmode = (p[4] - '0') & 3;
        else if (!memcmp(p, "proxy=", 6))
            strncpy(proxy, p + 6, PROXYMAX);
        else if (!memcmp(p, "waffle=", 7))
            strncpy(waffle, p + 7, WAFFLEMAX - 1);
        else if (!memcmp(p, "pictures=", 9))
            pic_kb = katoi(p + 9);
        else if (!memcmp(p, "wplang=", 7))
            strncpy(wlang, p + 7, WLANGMAX);
        else if (!memcmp(p, "wiki=", 5))
            strncpy(wbase, p + 5, WIKIMAX);
        if (!c)
            break;
        p = e + 1;
    }
}

/* a line key=v added to line, if it fits what cfg_read reads (185) */
static void __fastcall__ add(const char *k, const char *v)
{
    if (strlen(line) + strlen(k) + strlen(v) + 2 > 185)
        return;
    strcat(line, k);
    strcat(line, v);
    strcat(line, "\r\n");
}

static void save(void)
{
    strcpy(line, "web=0\r\n");
    line[4] += wmode;
    add("proxy=", proxy);
    unum(keep, pic_kb);
    add("pictures=", keep);
    add("wplang=", wlang);
    add("waffle=", waffle);
    if (strcmp(wbase, WIKI_DEF))        /* (another Gemipedia's: V128) */
        add("wiki=", wbase);
    ov2(cfg_write);
}

/* the proxy asked (in rel, below $A000), saved; 0: none */
static unsigned char set_proxy(void)
{
    strcpy(rel, proxy);
    if (ask("My proxy, host:port (port 1965 if none; empty: none):", rel, PROXYMAX))
        strcpy(proxy, rel);
    save();
    return proxy[0];
}

/* File > Settings...: web pages, the proxy, the pictures' limit (an
   empty answer keeps what there is) */
void w_setweb(void)
{
    strcpy(line, "Web pages (now 0): 0 ask each time, 1 always NewsWaffle, 2 always my proxy, 3 never:");
    line[15] += wmode;
    rel[0] = 0;
    if (!ask(line, rel, 1))
        return;
    if (rel[0] >= '0' && rel[0] <= '3')
        wmode = rel[0] - '0';
    set_proxy();
    strcpy(line, "Pictures: the largest to show without asking, in KB (now ");
    unum(line + strlen(line), pic_kb);
    strcat(line, "):");
    rel[0] = 0;
    if (ask(line, rel, 4) && rel[0])
        pic_kb = katoi(rel);
    k_setlang();                        /* (Wikipedia's language: V128) */
    save();
}

/* (url.c's u_host, for a web address) the proxy into ghost */
void w_proxy(void)
{
    strcpy(ghost, proxy);
}

/* the box for a web page: Yes NewsWaffle, No the proxy, Cancel (its
   texts and its table copied to line, below $A000) */
static const unsigned char wbox[] = {
    DEF_DB_POS | 1,
    DBVARSTR, TXT_LN_X, TXT_LN_1_Y, 0x10,
    DBVARSTR, TXT_LN_X, TXT_LN_2_Y, 0x0C,
    DBVARSTR, TXT_LN_X, TXT_LN_3_Y, 0x0E,
    YES, DBI_X_0, DBI_Y_2,
    NO, DBI_X_1, DBI_Y_2,
    CANCEL, DBI_X_2, DBI_Y_2,
    0
};

/* a box of three lines and Yes, No, Cancel: s (cut at 51) after the
   first line's start (in line), the second and third at line + 52 and
   + 100; DoDlgBox's YES, NO or CANCEL (the texts and the table below
   $A000, in line; pic.c's boxes too) */
unsigned char __fastcall__ box3(const char *s)
{
    unsigned char i = strlen(line), c, r;
    for (; i < 51 && (c = *s++) != 0; ++i)
        line[i] = c >= 32 && c < 127 ? c : '?';
    line[i] = 0;
    memcpy(line + 150, wbox, sizeof wbox);
    r7 = (unsigned int)line;
    r5 = (unsigned int)(line + 52);
    r6 = (unsigned int)(line + 100);
#ifdef GEMINI_TEST
    t_box = 1;
    ++t_nbox;
    strcpy(msg, "GE BOX ");
    strcat(msg, line);
    gt_log(msg);
    msg[0] = 0;
#endif
    r = DoDlgBox(line + 150);
#ifdef GEMINI_TEST
    t_box = 0;
    t_boxed = 1;
#endif
    return r;
}

static unsigned char choose(void)
{
    unsigned char r;
    strcpy(line + 52, "Yes: through NewsWaffle (gemi.dev),");
    strcpy(line + 100, "No: through my proxy, Cancel: neither.");
    strcpy(line, "Open the web page ");
    r = box3(go);
    return r == YES ? W_WAFFLE : r == NO ? W_PROXY : 0xFF;
}

/* go (a web page: u_ret U_WEB) its way: u_ret U_GEM go on (go
   NewsWaffle's address, or the web's for the proxy), U_WEB (off:
   u_where's box), U_NONE (cancelled), U_BAD (too long) */
void w_web(void)
{
    unsigned char w = wmode, from = 0;
    unsigned int p = gport;
    if (cur[0] && proxy[0]) {           /* (the page shown came from the proxy?) */
        strcpy(keep, ghost);
        strcpy(ghost, proxy);
        ov3(u_ghost);
        from = u_ret && !strcmp(keep, ghost) && p == gport;
        strcpy(ghost, keep);
        gport = p;
    }
    if (from)
        w = W_PROXY;
    else if (w == W_ASK)
        w = choose();
    u_ret = U_WEB;
    if (w == W_NEVER)
        return;
    u_ret = U_NONE;
    if (w == W_PROXY) {
        if (proxy[0] || set_proxy())
            u_ret = U_GEM;
    } else if (w == W_WAFFLE) {
        strcpy(line, go);
        strcpy(go, waffle);
        ov3(u_query);
        if (u_ret)
            u_ret = U_GEM;
        else {
            strcpy(rel, line);
            u_err = 2;
            u_ret = U_BAD;
        }
    }
}
