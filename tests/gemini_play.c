/* gate gemini (DECISIONS V118, V124): Veranda Gemini's test build (apps/gemini,
   make test: GEMINI_TEST; this file in overlay 8 (4 until V124, 5 in V124, 6 until V149, 7 until V192), its script in main
   RAM, where the pointer's player reads it from the interrupt;
   tests/term_play.s plays the mouse and the keys through mouseSource, as
   tests/gopher_play.c does for Veranda Gopher).

   GEMINI.TST: the session, then the server's port.
     main     (tools/gate_gemini.sh): the bookmarks page (the defaults);
              the root's address typed; a relative link; Back (from the
              cache), Go > Forward, Back; Tab to a link and Return: a
              question (10) answered; a sensitive one (11); a redirect
              (30); another host's (31: Yes); a loop of redirects; 51; 60;
              the web link: its box (V124), Yes: NewsWaffle's address; No:
              the proxy, a link on its page (no box); Cancel; File > Web
              pages... 2, an https address typed (no box); 3, the box that
              says web pages are off; the mail link's box; a plain text; ISO-8859-1; the
              binary (its box, Yes, Alt+Tab at 20,000 bytes); a page that
              stalls, Esc; Find; Bookmarks > Add this page; Go > Home; a
              bookmark removed (Tab, Bookmarks > Remove..., Yes); dark
              mode; the end
              (V128) Go > Wikipedia... "Ada Lovelace" (Gemipedia's
              stand-in); "wp Gemini (protocol)" and "w no such thing"
              typed (a redirect to its search); File > Settings...
              Wikipedia's language PL; "wp" alone: the box, "Warszawa"
     wiki     (V128; started by the shell with the Wikipedia document,
              tools/gate_gemini.sh's launcher) the box at once: "Ada
              Lovelace", the article, the end
     nomodem  (no modem on the port) the address typed: the box, the end
     qclose, ckey, fmenu  (V196) the pictures' page, small.png shown, then
              the close box, Ctrl+Q, Veranda Gemini > Quit (gemini_pics.c): Gemini
              ends, the test desktop's log follows
   Screens (snap: the foreground's 480 rows of 80 bytes, the cards' paper
   colours, 60 rows of 80, the palette's 16 entries): BOOK.RAW, PAGE.RAW,
   PAGE2.RAW, INPUT.RAW, WEB.RAW, PLAIN.RAW, XFER.RAW, STALL.RAW, FIND.RAW,
   MARKS.RAW, END.RAW, WIKI.RAW, DARK.RAW, LAUNCH.RAW; the log lines "GE ..."
   on the console.

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <string.h>
#include <vrnet.h>
#include <vrser.h>
#include <theme.h>
#include "../apps/gemini/gemini.h"
#include "../apps/gemini/png.h"
#pragma code-name ("OVERLAY8")
#pragma rodata-name ("OVL8RO")
/* (its texts in overlay 4: say() copies them below $A000 for the kernel;
   the script and the log's line in main RAM, below) */

void __fastcall__ term_play(const unsigned int *script);
void term_dump(void);
extern unsigned int barx[4], barl[4];
void t_menu7(void);
extern unsigned char hpos, hn;
void page(void);
void __fastcall__ t_ui(void (*f)(void));
void __fastcall__ t_ov7(void (*f)(void));
void t_pics(void), t_pics_init(void);
extern unsigned char t_pics_done, t_pics_prog;

#define F_BTN 0x100
#define F_KEY 0x8000
#define NONE 0xFFFF

unsigned int scr[3 * 40];               /* (main RAM; gemini_pics.c's too; 48 entries until V125) */
unsigned int stopper[3];
unsigned char ns;
unsigned char t_quit;                   /* (V196: gemini_pics.c reads it) the quit sessions' 'q' 'c' 'f'; 0 */
static unsigned char step;          /* (main RAM: cleared at the start; an overlay's BSS is not) */
#pragma data-name ("OVL8DATA")          /* (the rest in overlay 8, initialised: cc65 puts tentative BSS where
                                           the file ends; kernel calls get rel) */
static unsigned char nbox = 0, sess = 0;
static unsigned int tplay = 0, tlen = 0;
static unsigned int t0 = 0, tmax = 0, tlast = 0, tstep_t = 0;
static char port[8] = { 0 };
static unsigned char seen = 0;          /* (t_pics_prog as last seen) */
#pragma data-name ("DATA")
static char tl[100];                    /* (V149: main RAM, for overlay 8's room) */
extern unsigned int v_find;
extern char _STACKSIZE__[];             /* (the linker's __STACKSIZE__) */

static void say(const char *s)
{
    strncpy(tl, s, sizeof tl - 1);
    gt_log(tl);
}

static void S(unsigned int f, unsigned int x, unsigned int y, unsigned int fl)
{
    if (!ns) {
        stopper[0] = stopper[1] = 0xFFFF;       /* (the player given an empty script first: V110) */
        term_play(stopper);
    }
    scr[ns++] = f;
    scr[ns++] = x;
    scr[ns++] = (y & 255) | (y > 255 ? 0x4000 : 0) | fl;
    if (f > tlen)
        tlen = f;
    if (ns > sizeof scr / 2 - 6)
        say("GE TEST SCRIPT FULL");
}

static void C(unsigned int f, unsigned int x, unsigned int y)
{
    S(f, x, y, 0);
    S(f + 3, x, y, F_BTN);
    S(f + 7, x, y, 0);
}

static void M(unsigned int f, unsigned char m, unsigned char n)
{
    S(f, barx[m], 7, 0);
    S(f + 1, barx[m], 7, F_BTN);
    S(f + 2, barl[m] + 12, 24, 0);
    C(f + 20, barl[m] + 12, 24 + 16 * n);
}

static unsigned int typed(unsigned int f, const char *s)
{
    while (*s) {
        S(f, (unsigned char)*s++, 0, F_KEY);
        f += 3;
    }
    return f;
}

static unsigned int keys(unsigned int f, unsigned char k, unsigned char n, unsigned char gap)
{
    while (n--) {
        S(f, k, 0, F_KEY);
        f += gap;
    }
    return f;
}

static void go_(void)
{
    nbox = t_nbox;
    scr[ns++] = 0xFFFF;
    scr[ns++] = 0xFFFF;
    scr[ns++] = 0;
    term_play(scr);
    ns = 0;
    tplay = ser_frames;
}

static unsigned char played(void)
{
    return ser_frames - tplay > tlen + 40;
}

static unsigned char idle(void)
{
    return played() && !gbusy && !t_box;
}

static void W(void)
{
    S(tlen + 10, (unsigned int)&t_box, 0, 0x1000);
}

static unsigned char idle_box(void)
{
    return idle() && t_nbox != nbox;
}

static void logn(const char *k, unsigned long v)
{
    strcpy(tl, k);
    unum(tl + strlen(tl), v);
    gt_log(tl);
}

static void snap(const char *name)
{
    unsigned char h, keep = dispBufferOn, x, y, i;
    unsigned int r;
    strcpy(tl, VR_ROOTPATH);
    strcat(tl, name);
    strcpy(rel, tl);
    h = FOpen(rel, 'w');
    if (h < 2 || h > 4) {
        say("GE SNAP FAILED");
        return;
    }
    dispBufferOn = ST_WR_FORE;
    for (r = 0; r < 480; ++r) {
        ReadRow((unsigned char *)line, 0, 80, r);
        FWrite(h, line, 80);
    }
    for (y = 0; y < 60; ++y) {
        for (x = 0; x < 80; ++x)
            line[x] = GetCardColor(x, y);
        FWrite(h, line, 80);
    }
    asm("sei");
    *(volatile unsigned char *)0x9F25 &= 0xFE;
    *(volatile unsigned char *)0x9F20 = 0x00;
    *(volatile unsigned char *)0x9F21 = 0xFA;
    *(volatile unsigned char *)0x9F22 = 0x11;
    for (i = 0; i < 32; ++i)
        line[i] = *(volatile unsigned char *)0x9F23;
    asm("cli");
    FWrite(h, line, 32);
    FClose(h);
    dispBufferOn = keep;
    tlast = 0;
    strcpy(tl, "GE SNAP ");
    strcat(tl, name);
    gt_log(tl);
}

static void fail(const char *why)
{
    strcpy(tl, "GE TEST FAILED ");
    strcat(tl, why);
    gt_log(tl);
    term_dump();
}

static unsigned char __fastcall__ head_link(unsigned int i)
{
    unsigned char k = doc_kind(i);
    return k != 0xFF && !(k & K_CONT) && (k & K_TYPE) == K_LINK;
}

/* the link labelled t (its first row); NONE */
static unsigned int find(const char *t)
{
    unsigned int i;
    unsigned char n = strlen(t), k;
    for (i = 0; i < doc_lines; ++i) {
        if (!head_link(i))
            continue;
        render(i);
        for (k = ROWW; k > 3 && row[k - 1] == ' '; --k)
            ;
        row[k] = 0;
        if (k - 3 == n && !memcmp(row + 3, t, n))
            return i;
    }
    return NONE;
}

#define LN() (doc_lines + (doc_full && doc_done ? 2 : 0))

/* a click on the link t (f): PgDn or Home first if it is not shown */
static void click(unsigned int f, const char *t)
{
    unsigned int i = find(t), top = v_top, max = LN() > rows ? LN() - rows : 0;
    if (i == NONE) {
        strcpy(tl, "GE TEST NO ");
        strcat(tl, t);
        gt_log(tl);
        fail("NO LINK");
        return;
    }
    if (i < top) {
        S(f, 0x13, 0, F_KEY);           /* (Home) */
        f += 30;
        top = 0;
    }
    while (i >= top + rows) {
        S(f, 0x02, 0, F_KEY);           /* (PgDn) */
        f += 30;
        top = top + rows - 1 < max ? top + rows - 1 : max;
    }
    C(f, 200, BODYY + (i - top) * rowh + rowh / 2);
}

/* Tabs from the selection (or the page shown) to the link t; the frame after */
static unsigned int tab_to(unsigned int f, const char *t)
{
    unsigned int i = find(t), j;
    unsigned char n = 0;
    if (i == NONE) {
        fail("NO LINK TO TAB TO");
        return f;
    }
    for (j = v_sel != NONE ? v_sel + 1 : v_top; j <= i; ++j)
        if (head_link(j))
            ++n;
    return keys(f, 0x09, n, 20);
}

#define BACKBTN() C(10, 16, 40)
#define OKBTN() C(30, 256, 272)
#define YESX 256                   /* (the web's box: DBI_X_0, _1, _2) */
#define NOX 336
#define CANCELX 400

static unsigned int now(void);
static void type_url(unsigned int f, const char *path);

/* the timings: the page drawn 4 times (ui.c's page, overlay 1), the page
   cache's copy of it read back 4 times; frames ("GE BENCH PAGE n", "GE
   BENCH CACHE n"); here since V125 (overlay 1's room) */
static void t_bench(void)
{
    unsigned int t = now();
    unsigned char i;
    for (i = 0; i < 4; ++i)
        t_ui(page);
    logn("GE BENCH PAGE ", now() - t);
    strcpy(go, cur);
    t = now();
    for (i = 0; i < 4; ++i)
        if (cache_has())
            cache_fill();
    doc_end();
    logn("GE BENCH CACHE ", now() - t);
}

static void the_end(void)
{
    {                                   /* (the C stack's depth: V125) */
        unsigned char *p = (unsigned char *)(0x8800 - (unsigned int)_STACKSIZE__);
        while (*p == 0xA5)
            ++p;
        logn("GE STACK ", 0x8800 - (unsigned int)p);
        logn("GE STACKSIZE ", (unsigned int)_STACKSIZE__);
    }
    logn("GE MAXGAP ", tmax);
    logn("GE LOST ", ser_lost);
    logn("GE OE ", ser_oe);
    logn("GE PACKETS ", net_stats.packets);
    logn("GE XONRETRY ", net_stats.xon_retries);
    logn("GE BADCRC ", net_stats.badcrc);
    say("GE END");
    term_dump();
}

static void type_url(unsigned int f, const char *path)
{
    (void)C;                            /* (typing starts a new address: no click, V125) */
    strcpy(tl, "gemini://127.0.0.1:");
    strcat(tl, port);
    strcat(tl, path);
    strcat(tl, "\r");
    typed(f + 20, tl);
}

static unsigned int now(void)
{
    unsigned int t;
    asm("sei");
    t = ser_frames;
    asm("cli");
    return t;
}

/* (called by ui.c) the page as shown: gemini_pics.c's page_log7 in
   overlay 9 (V128: this overlay's room) */
void page_log7(void);
void page_log(void)
{
    t_ov7(page_log7);
}

void gt_tick(void)
{
    unsigned char h;
    unsigned int f = now();
    if (t_boxed)
        t_boxed = tlast = 0;
    if (tlast && f - tlast > 20) {
        strcpy(tl, "GE GAP AT STEP ");
        unum(tl + strlen(tl), step);
        strcat(tl, ": ");
        unum(tl + strlen(tl), f - tlast);
        gt_log(tl);
    }
    if (tlast && f - tlast > tmax)
        tmax = f - tlast;
    tlast = f;
    if (!step) {
        strcpy(tl, VR_ROOTPATH "GEMINI.TST");
        strcpy(rel, tl);
        h = FOpen(rel, 'r');
        if (h < 2 || h > 4) {
            step = 0xFF;
            return;
        }
        rel[FRead(h, rel, 40)] = 0;
        strcpy(tl, rel);
        tlen = tmax = tlast = 0;
        FClose(h);
        sess = tl[0];
        for (h = 0; tl[h] && tl[h] != ' '; ++h)
            ;
        strncpy(port, tl + h + 1, 6);
        for (h = 0; port[h] >= '0' && port[h] <= '9'; ++h)
            ;
        port[h] = 0;
        step = 1;
        t0 = tstep_t = ser_frames;
        say("GE TEST START");
        {                               /* (the C stack below here marked: its depth at the end) */
            unsigned char probe, *p;
            for (p = (unsigned char *)(0x8800 - (unsigned int)_STACKSIZE__); p < &probe - 48; ++p)
                *p = 0xA5;
        }
        return;
    }
    if (step == 0xFF)
        return;
    if (ser_frames - tstep_t > 60u * 90) {
        logn("GE TEST STUCK AT STEP ", step);
        snap("FAIL.RAW");
        fail("TIMEOUT");
        return;
    }
    if (sess == 'w') {                  /* (V128) wiki: started with the Wikipedia document */
        switch (step) {
        case 1:                         /* (at once: the box comes a few passes after the start) */
            W();
            typed(tlen + 20, "Ada Lovelace\r");
            go_();
            break;
        case 2:
            if (!idle_box() || !doc_done || !cur[0])
                return;
            snap("LAUNCH.RAW");
            say("GE TEST LAUNCHED");
            the_end();
            return;
        }
        ++step;
        tstep_t = ser_frames;
        return;
    }
    if (sess == 'n') {                  /* nomodem */
        switch (step) {
        case 1:
            if (gbusy || !doc_done)
                return;
            type_url(10, "/");
            W();
            OKBTN();
            go_();
            break;
        case 2:
            if (!idle_box())
                return;
            say("GE TEST NOMODEM BOX");
            the_end();
            return;
        }
        ++step;
        tstep_t = ser_frames;
        return;
    }
    switch (step) {
    case 1:                             /* the modem ready, the bookmarks shown: the address */
        if (net_state() != NET_READY || gbusy || !doc_done)
            return;
        logn("GE TEST NET READY ", ser_frames - t0);
        if (sess == 'q' || sess == 'c' || sess == 'f')
            t_quit = sess;              /* (V196: qclose, ckey, fmenu: a picture, then Quit) */
        if (sess == 'p' || t_quit) {       /* (session pics: the pictures alone) */
            step = 45;
            return;
        }
        snap("BOOK.RAW");
        type_url(10, "/");
        go_();
        break;
    case 2:                             /* the root: a relative link */
        if (!idle() || !cur[0])
            return;
        snap("PAGE.RAW");
        say("GE TEST ROOT");
        t_bench();
        tlast = 0;                      /* (the test's own time) */
        click(10, "A relative link");
        go_();
        break;
    case 3:                             /* the sub page: Back (the toolbar) */
        if (!idle())
            return;
        say("GE TEST SUB");
        BACKBTN();
        go_();
        break;
    case 4:                             /* Go > Forward */
        if (!idle())
            return;
        logn("GE TEST BACK SEL ", v_sel);
        M(10, 2, 1);
        go_();
        break;
    case 5:
        if (!idle())
            return;
        say("GE TEST FORWARD");
        BACKBTN();
        go_();
        break;
    case 6:                             /* Tab to "Ask my name", Return: the question */
        if (!idle())
            return;
        logn("GE TEST HPOS ", hpos);
        logn("GE TEST HN ", hn);
        S(tab_to(10, "Ask my name") + 20, 13, 0, F_KEY);
        W();
        typed(tlen + 20, "Ada Lovelace\r");
        go_();
        break;
    case 7:
        if (!idle_box() || !doc_done)
            return;
        snap("INPUT.RAW");
        say("GE TEST ANSWERED");
        BACKBTN();
        go_();
        break;
    case 8:                             /* a sensitive question (11) */
        if (!idle())
            return;
        click(10, "A secret");
        W();
        typed(tlen + 20, "p4ss w0rd&\r");
        go_();
        break;
    case 9:
        if (!idle_box() || !doc_done)
            return;
        say("GE TEST SECRET");
        BACKBTN();
        go_();
        break;
    case 10:                            /* a redirect (30, relative) */
        if (!idle())
            return;
        click(10, "A redirect");
        go_();
        break;
    case 11:
        if (!idle())
            return;
        say("GE TEST REDIRECTED");
        BACKBTN();
        go_();
        break;
    case 12:                            /* another host (31): Yes */
        if (!idle())
            return;
        click(10, "Another host");
        W();
        OKBTN();
        go_();
        break;
    case 13:
        if (!idle_box() || !doc_done)
            return;
        say("GE TEST MOVED");
        snap("PAGE2.RAW");
        BACKBTN();
        go_();
        break;
    case 14:                            /* a loop of redirects: its box */
        if (!idle())
            return;
        click(10, "A loop of redirects");
        W();
        OKBTN();
        go_();
        break;
    case 15:                            /* 51: its box */
        if (!idle_box())
            return;
        click(10, "Not found");
        W();
        OKBTN();
        go_();
        break;
    case 16:                            /* 60: its box */
        if (!idle_box())
            return;
        click(10, "A certificate");
        W();
        OKBTN();
        go_();
        break;
    case 17:                            /* (V124) the web: its box, Yes: NewsWaffle */
        if (!idle_box())
            return;
        click(10, "The web");
        W();
        C(tlen + 30, YESX, 272);
        go_();
        break;
    case 18:
        if (!idle_box() || !doc_done)
            return;
        say("GE TEST WAFFLE");
        BACKBTN();
        go_();
        break;
    case 19:                            /* the box again, No: my proxy */
        if (!idle())
            return;
        click(10, "The web");
        W();
        C(tlen + 30, NOX, 272);
        go_();
        break;
    case 20:                            /* the converted page: a link on it (no box: the proxy's page) */
        if (!idle_box() || !doc_done)
            return;
        snap("WEB.RAW");
        say("GE TEST PROXIED");
        click(10, "[1] cherry variety");
        go_();
        break;
    case 21:
        if (!idle() || !doc_done)
            return;
        logn("GE TEST PROXY LINK BOXES ", t_nbox - nbox);
        BACKBTN();
        go_();
        break;
    case 22:
        if (!idle())
            return;
        BACKBTN();
        go_();
        break;
    case 23:                            /* the box, Cancel */
        if (!idle())
            return;
        click(10, "The web");
        W();
        C(tlen + 30, CANCELX, 272);
        go_();
        break;
    case 24:                            /* File > Settings...: 2 (always my proxy), the proxy and the limit kept */
        if (!idle_box())
            return;
        logn("GE TEST CANCELLED ", hpos);
        M(10, 1, 5);
        W();
        typed(tlen + 20, "2\r");
        W();
        S(tlen + 20, 13, 0, F_KEY);
        W();
        S(tlen + 20, 13, 0, F_KEY);         /* (the pictures' limit kept) */
        W();
        S(tlen + 20, 13, 0, F_KEY);         /* (Wikipedia's language kept: V128) */
        go_();
        break;
    case 25:                            /* a web address typed: through the proxy, no box */
        if (!idle_box())
            return;
        typed(10, "https://example.com/typed\r");     /* (typing starts a new address) */
        go_();
        break;
    case 26:                            /* File > Settings...: 3 (never) */
        if (!idle() || !doc_done)
            return;
        logn("GE TEST TYPED BOXES ", t_nbox - nbox);
        M(10, 1, 5);
        W();
        typed(tlen + 20, "3\r");
        W();
        S(tlen + 20, 13, 0, F_KEY);
        W();
        S(tlen + 20, 13, 0, F_KEY);
        W();
        S(tlen + 20, 13, 0, F_KEY);
        go_();
        break;
    case 27:
        if (!idle_box())
            return;
        BACKBTN();
        go_();
        break;
    case 28:                            /* off: the box that says so */
        if (!idle())
            return;
        click(10, "The web");
        W();
        OKBTN();
        go_();
        break;
    case 29:                            /* mail: its box */
        if (!idle_box())
            return;
        click(10, "Mail");
        W();
        OKBTN();
        go_();
        break;
    case 30:                            /* a plain text */
        if (!idle_box())
            return;
        click(10, "Plain text");
        go_();
        break;
    case 31:
        if (!idle() || !doc_done)
            return;
        snap("PLAIN.RAW");
        BACKBTN();
        go_();
        break;
    case 32:                            /* ISO-8859-1 */
        if (!idle())
            return;
        click(10, "ISO-8859-1");
        go_();
        break;
    case 33:
        if (!idle() || !doc_done)
            return;
        BACKBTN();
        go_();
        break;
    case 34:                            /* the binary: its box, Yes */
        if (!idle())
            return;
        click(10, "A binary file");
        W();
        OKBTN();
        go_();
        break;
    case 35:                            /* 20,000 bytes: the screen, Alt+Tab */
        if (!gbusy && played() && ser_frames - tplay > tlen + 600)
            fail("NO DOWNLOAD");
        if (!gbusy || !gdl || grx < 20000)
            return;
        snap("XFER.RAW");
        logn("GE ALT+TAB AT ", grx);
        switchReq = SWITCH_ASIDE;
        break;
    case 36:                            /* back (asideVector: the file closed, opened again) */
        if (!t_aside || !xf_h)
            return;
        logn("GE BACK AT ", grx);
        break;
    case 37:                            /* the end of it: a page that stalls */
        if (!idle())
            return;
        logn("GE TEST DOWNLOADED ", grx);
        click(10, "A stalling page");
        go_();
        break;
    case 38:                            /* its first rows: Esc */
        if (!played() || !gbusy || !gfirst || doc_lines < 2)
            return;
        say("GE TEST STALLED");
        snap("STALL.RAW");
        keys(10, 0x1B, 1, 4);
        go_();
        break;
    case 39:
        if (!idle())
            return;
        say("GE TEST STOPPED");
        BACKBTN();
        go_();
        break;
    case 40:                            /* File > Find...: "needle" (V149: the File menu open first, MENU.RAW) */
        if (!idle())
            return;
        t_ov7(t_menu7);                 /* (gemini_pics.c) */
        if (!u_ret)
            return;
        C(10, barl[1] + 12, 24 + 16 * 2);
        W();
        typed(tlen + 20, "needle\r");
        go_();
        break;
    case 41:                            /* Bookmarks > Add this page */
        if (!idle_box())
            return;
        logn("GE TEST FOUND ", v_find);
        snap("FIND.RAW");
        M(10, 3, 1);
        go_();
        break;
    case 42:                            /* Go > Home */
        if (!idle())
            return;
        M(10, 2, 3);
        go_();
        break;
    case 43:                            /* Tab to gemi.dev, Bookmarks > Remove..., Yes */
        if (!idle() || cur[0] || !doc_done)
            return;
        snap("MARKS.RAW");
        M(tab_to(10, "gemi.dev") + 20, 3, 2);
        W();
        OKBTN();
        go_();
        break;
    case 44:
        if (!idle_box() || !doc_done)
            return;
        say("GE TEST REMOVED");
        snap("END.RAW");
        type_url(10, "/");
        go_();
        break;
    case 45:                            /* (V125) the pictures: their page, then gemini_pics.c (overlay 9) */
        if (!idle() || (!cur[0] && sess != 'p' && !t_quit))
            return;
        t_ov7(t_pics_init);
        type_url(10, "/pics.gmi");
        go_();
        break;
    case 46:
        if (!idle() || !doc_done)
            return;
        t_ov7(t_pics);
        if (t_pics_prog != seen) {      /* (each picture's own time: the stuck test's) */
            seen = t_pics_prog;
            tstep_t = ser_frames;
        }
        if (!t_pics_done)
            return;
        break;
    case 47:                            /* (V128) Go > Wikipedia...: "Ada Lovelace" */
        if (!idle() || !cur[0])
            return;
        if (sess == 'p') {              /* (V138: session pics ends here: no wiki= in its GEMINI.CFG, so no gemi.dev) */
            the_end();
            return;
        }
        M(10, 2, 4);
        W();
        typed(tlen + 20, "Ada Lovelace\r");
        go_();
        break;
    case 48:                            /* the article; the address line's shortcut "wp <text>" */
        if (!idle_box() || !doc_done)
            return;
        snap("WIKI.RAW");
        say("GE TEST WIKI");
        typed(10, "wp Gemini (protocol)\r");
        go_();
        break;
    case 49:                            /* "w <text>": not an article: Gemipedia's redirect to its search */
        if (!idle() || !doc_done)
            return;
        say("GE TEST WP");
        typed(10, "w no such thing\r");
        go_();
        break;
    case 50:                            /* File > Settings...: all kept, Wikipedia's language pl */
        if (!idle() || !doc_done)
            return;
        say("GE TEST W SEARCH");
        M(10, 1, 5);
        W();
        S(tlen + 20, 13, 0, F_KEY);
        W();
        S(tlen + 20, 13, 0, F_KEY);
        W();
        S(tlen + 20, 13, 0, F_KEY);
        W();
        typed(tlen + 20, "PL\r");
        go_();
        break;
    case 51:                            /* "wp" alone: the box (pl), "Warszawa" */
        if (!idle_box())
            return;
        typed(10, "wp\r");
        W();
        typed(tlen + 20, "Warszawa\r");
        go_();
        break;
    case 52:                            /* dark mode: Look 2's palette swapped */
        if (!idle_box() || !doc_done || !cur[0])
            return;
        say("GE TEST WP PL");
        theme.dark = LOOK_DARK;
        theme_palette();
        snap("DARK.RAW");
        the_end();
        return;
    }
    ++step;
    tstep_t = ser_frames;
}
