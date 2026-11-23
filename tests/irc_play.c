/* gate irc (DECISIONS V111): Veranda Chat's test build (apps/irc, make
   test: CHAT_TEST; this file in overlay 5, its data in main RAM, where
   the pointer's player reads it from the interrupt; tests/term_play.s
   plays the mouse and the keys through mouseSource, as for Veranda FTP
   and Veranda Gopher).

   CHAT.TST: the session, then the server's port.
     main     (tools/gate_irc.sh): the Servers page (the defaults), New,
              the fields typed, Connect; nick in use, the alternative;
              two channels joined; PING; messages in (formatting, UTF-8,
              Latin-1); messages out, /me; a private message (its window
              opened); JOIN, PART, NICK, QUIT, MODE in the nick list; a
              mention (the line, the sound, the tab's mark); Tab's
              completion; a long line (split); CTCP VERSION; /topic, /msg,
              /raw; the history (Up); /nick, /join, /part, /query, /close;
              400 lines (the scrollback's cap), PgUp; Alt+Tab with lines
              coming; the server's ERROR and close: the box
     reread   CHAT.SERVERS read back: PgDn to the gate's server, Return:
              registered, the channels joined
     nomodem  (no modem on the port) Return: the box
     closedport  a server on a port nothing listens on: Return, the box
     welcome  (V179) a big network's welcome (NOTICEs, 001-005, 250-266, a
              MOTD of 120 lines) in one write, at 115200 baud, then #retro
     big      (V178) channels of 2,400 and 600 people (NAMES in many
              lines, topics of 460 bytes) joined while the hands click
              the tabs and the list; the people counted (PART, QUIT,
              KICK, JOIN of nicks kept and not); lines past 512 bytes
              (tags, a long PRIVMSG, NOTICE, TOPIC, KICK, CTCP PING,
              MODE); more windows than there is room for; the list's end
              ("and N more"); 600 lines of a busy channel
   Screens (snap: the foreground's 480 rows of 80 bytes, the cards'
   paper colours, 60 rows of 80, the palette's 16 entries); the log
   lines "IR ..." on the console.

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <string.h>
#include <vrnet.h>
#include <vrser.h>
#include "../apps/irc/chat.h"
#pragma code-name ("OVERLAY6")
#pragma rodata-name ("OVL6RO")
/* (its texts in overlay 6: say() copies them below $A000 for the kernel) */

void __fastcall__ term_play(const unsigned int *script);
void term_dump(void);
void __fastcall__ gt_ov1(void (*f)(void));
void t_body(void), t_stat(void), t_wrap(void), t_nend(void);
static unsigned char nbox, ndone;

#define F_BTN 0x100
#define F_KEY 0x8000

static unsigned int scr[3 * 84];
static unsigned char ns;
static unsigned int tplay, tlen, plen;  /* (plen: the script playing's last frame) */
static unsigned char step, sess, chunk;
static unsigned int t0, tmax, tlast, tstep_t;
#define tl tlog                         /* (main.c's 128 bytes: below $A000 for the kernel; a buffer of its own no longer fits, V138) */
static char port[8];
static char tx[80];                     /* (main RAM: send_line, the typed text) */
#define wrow ((unsigned char *)line)

static void say(const char *s)
{
    strncpy(tl, s, sizeof tl - 1);
    LogText(tl);
}

static void Sx(unsigned int f, unsigned int x, unsigned int y, unsigned int fl)
{
    scr[ns++] = f;
    scr[ns++] = x;
    scr[ns++] = (y & 255) | (y > 255 ? 0x4000 : 0) | fl;
    if (f > tlen)
        tlen = f;
}

static void C(unsigned int f, unsigned int x, unsigned int y)
{
    Sx(f, x, y, 0);
    Sx(f + 3, x, y, F_BTN);
    Sx(f + 7, x, y, 0);
}

static unsigned int typed(unsigned int f, const char *s)
{
    while (*s) {
        Sx(f, (unsigned char)*s++, 0, F_KEY);
        f += 3;
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
    plen = tlen;
    tlen = 0;
    tplay = ser_frames;
}

static unsigned char played(void)
{
    return ser_frames - tplay > plen + 40;
}

static unsigned char idle(void)
{
    return played() && !t_box;
}

static void W_(void)
{
    Sx(tlen + 10, (unsigned int)&t_box, 0, 0x1000);
}

static unsigned char idle_box(void)
{
    return idle() && t_nbox != nbox;
}

static void logn(const char *k, unsigned long v)
{
    strcpy(tl, k);
    unum(tl + strlen(tl), v);
    LogText(tl);
}

static void logs(const char *k, const char *v)
{
    strcpy(tl, k);
    strncat(tl, v, sizeof tl - 1 - strlen(tl));
    LogText(tl);
}

static void snap(const char *name)
{
    unsigned char h, keep = dispBufferOn, x, y, i;
    unsigned int r;
    strcpy(tl, VR_ROOTPATH);
    strcat(tl, name);
    h = FOpen(tl, 'w');
    if (h < 2 || h > 4) {
        say("IR SNAP FAILED");
        return;
    }
    dispBufferOn = ST_WR_FORE;
    for (r = 0; r < 480; ++r) {
        ReadRow(wrow, 0, 80, r);
        FWrite(h, wrow, 80);
    }
    for (y = 0; y < 60; ++y) {
        for (x = 0; x < 80; ++x)
            wrow[x] = GetCardColor(x, y);
        FWrite(h, wrow, 80);
    }
    asm("sei");
    *(volatile unsigned char *)0x9F25 &= 0xFE;
    *(volatile unsigned char *)0x9F20 = 0x00;
    *(volatile unsigned char *)0x9F21 = 0xFA;
    *(volatile unsigned char *)0x9F22 = 0x11;
    for (i = 0; i < 32; ++i)
        wrow[i] = *(volatile unsigned char *)0x9F23;
    asm("cli");
    FWrite(h, wrow, 32);
    FClose(h);
    dispBufferOn = keep;
    tlast = 0;
    logs("IR SNAP ", name);
}

static void fail(const char *why)
{
    logs("IR TEST FAILED ", why);
    term_dump();
}

static void the_end(void)
{
    logn("IR MAXGAP ", tmax);
    logn("IR LOST ", ser_lost);
    logn("IR OE ", ser_oe);
    logn("IR PACKETS ", net_stats.packets);
    logn("IR XONRETRY ", net_stats.xon_retries);
    logn("IR BADCRC ", net_stats.badcrc);
    logn("IR DINGS ", t_ding);
    say("IR END");
    term_dump();
}

/* a "GATE what" line to the server (not IRC: the test server's cue) */
static void gate(const char *what)
{
    ndone = t_done;
    strcpy(tx, "GATE ");
    strcat(tx, what);
    send_line(tx);
}

static unsigned char done(void)
{
    return t_done != ndone && idle();
}

static unsigned char __fastcall__ wi(const char *name)
{
    strcpy(tx, name);
    return (unsigned char)win_find(tx);
}

/* a tab clicked (window i) */
static void tab(unsigned int f, unsigned char i)
{
    C(f, (1 + i * 11) * 8 + 20, 38);
}

static void tabs_log(void)
{
    unsigned char i;
    strcpy(tl, "IR TABS");
    for (i = 0; i < WMAX; ++i) {
        if (W[i].kind == W_FREE)
            continue;
        strcat(tl, " ");
        strcat(tl, i ? W[i].name : "*");
        strcat(tl, W[i].unread == U_MENTION ? "!" : W[i].unread ? "+" : "");
        if (i == cw)
            strcat(tl, "<");
    }
    LogText(tl);
}

static void __fastcall__ nicks_log(unsigned char w)
{
    unsigned int i;
    logs("IR NICKS ", W[w].name);
    for (i = 0; i < W[w].nicks; ++i) {
        nk_get(w, i);
        logs("IR NICK ", nk);
    }
    say("IR NICKS END");
}

/* the scrollback of w: lines kept, bytes, the oldest and newest lines */
static void __fastcall__ sb_log(unsigned char w)
{
    unsigned int e = W[w].used, n = 0;
    logn("IR SB LINES ", W[w].lines);
    logn("IR SB USED ", W[w].used);
    if (!e)
        return;
    sb_prev(w, e);
    logs("IR SB LAST ", ln);
    while (e) {
        e = sb_prev(w, e);
        ++n;
    }
    logs("IR SB FIRST ", ln);
    logn("IR SB COUNTED ", n);
}

static unsigned int now(void)
{
    unsigned int t;
    asm("sei");
    t = ser_frames;
    asm("cli");
    return t;
}

/* the long line: 48 words of 8 characters and a space ("w01-abcd "), 431 characters and Return */
static void long_chunk(unsigned char c)
{
    unsigned char i, k;
    char *p = tx;
    for (i = 0; i < 8; ++i) {
        k = c * 8 + i + 1;
        *p++ = 'w';
        *p++ = '0' + k / 10;
        *p++ = '0' + k % 10;
        memcpy(p, "-abcd ", 6);
        p += 6;
    }
    if (c == 5)
        p[-1] = '\r';                   /* (the last: Return for its space) */
    *p = 0;
    typed(10, tx);
}

/* the drawing's costs, in frames (the gate's figures) */
static void measure(void)
{
    unsigned int t;
    unsigned char r;
    dispBufferOn = ST_WR_FORE;
    SetPattern(0);
    t = now();
    for (r = 0; r < 10; ++r)
        WRectangle(0, 64, 503, 447);
    logn("IR TIME WRECT10 ", now() - t);
    t = now();
    for (r = 0; r < 32; ++r)
        put(1, 66 + r * 12, "The quick brown fox jumps over the lazy dog, again and again and", 62, 0);
    logn("IR TIME PUT32 ", now() - t);
    t = now();
    for (r = 0; r < 10; ++r)
        ScrollRect(0, 63, 64, 447, -12, 0);
    logn("IR TIME SCROLL10 ", now() - t);
    t = now();
    for (r = 0; r < 32; ++r)
        sb_prev(0, W[0].used);
    logn("IR TIME SBPREV32 ", now() - t);
    t = now();
    for (r = 0; r < 10; ++r)
        gt_ov1(t_body);
    logn("IR TIME BODY10 ", now() - t);
    t = now();
    for (r = 0; r < 10; ++r)
        gt_ov1(t_stat);
    logn("IR TIME STATUS10 ", now() - t);
    t = now();
    for (r = 0; r < 32; ++r)
        gt_ov1(t_wrap);
    logn("IR TIME WRAP32 ", now() - t);
}

#define NEXT() do { ++step; tstep_t = ser_frames; } while (0)

static void main_steps(void)
{
    unsigned char r, x;
    switch (step) {
    case 1:                             /* the Servers page: New, the fields, Connect */
        if (!sv_page || net_state() != NET_READY)
            return;
        logn("IR TEST NET READY ", ser_frames - t0);
        snap("SERVERS.RAW");
        C(10, 140, 356);
        strcpy(tx, "Gate\t127.0.0.1\t\x14\x14\x14\x14");
        strcat(tx, port);
        strcat(tx, "\tveranda\tverandax\tGate tester\t\t#retro #x16");
        typed(30, tx);
        C(tlen + 20, 36, 356);
        go_();
        break;
    case 2:                             /* registered, both channels joined */
        r = wi("#x16");
        if (cstate != C_UP || r == 0xFF || !W[r].joined || W[r].names || !W[r].nicks || !idle())
            return;
        logs("IR TEST ME ", me);
        tabs_log();
        nicks_log(wi("#retro"));
        nicks_log(r);
        snap("JOINED.RAW");
        gate("ping");
        break;
    case 3:                             /* #retro shown; messages in */
        if (!done())
            return;
        tab(10, wi("#retro"));
        go_();
        gate("msgs");
        break;
    case 4:                             /* messages out, /me */
        if (!done())
            return;
        logn("IR TEST CW ", cw);
        typed(typed(typed(10, "Hello everyone, caf\xe9!\r") + 10, "/me waves\r") + 10,
              "Za\xbf\xf3\xb3\xe5 g\xfd\xf7l\xa2 ja\xae\xf1\r");     /* (V143: the set's bytes) */
        go_();
        break;
    case 5:                             /* (V149) then the Window menu open: its picture */
        if (!idle())
            return;
        if (!chunk) {
            snap("MSGS.RAW");
            Sx(10, barx[2], 7, 0);
            Sx(11, barx[2], 7, F_BTN);
            Sx(12, barl[2] + 12, 24, 0);
            go_();
            chunk = 1;
            return;
        }
        if (chunk == 1) {
            snap("MENU.RAW");
            C(10, 300, 300);            /* (closed by a click on the text) */
            go_();
            chunk = 2;
            return;
        }
        chunk = 0;
        gate("query");
        break;
    case 6:                             /* a private message: its window */
        if (!done())
            return;
        tabs_log();
        logn("IR TEST DINGS ", t_ding);
        gate("nicks");
        break;
    case 7:
        if (!done())
            return;
        nicks_log(wi("#retro"));
        tabs_log();
        gate("mention");
        break;
    case 8:                             /* a mention: the line, the sound, the tab */
        if (!done())
            return;
        tabs_log();
        logn("IR TEST DINGS ", t_ding);
        snap("MENTION.RAW");
        typed(typed(10, "car\t") + 10, "hi\r");
        go_();
        chunk = 0;
        break;
    case 9:                             /* the long line, typed in pieces */
        if (!idle())
            return;
        if (chunk < 6) {
            long_chunk(chunk++);
            go_();
            return;
        }
        gate("version");
        break;
    case 10:                            /* /topic, /msg, /raw */
        if (!done())
            return;
        typed(typed(typed(10, "/topic A new topic\r") + 10, "/msg carol private hello\r") + 10, "/raw WHOIS carol\r");
        go_();
        break;
    case 11:                            /* the history: Up */
        if (!idle())
            return;
        typed(10, "\x91");
        go_();
        break;
    case 12:
        if (!idle())
            return;
        logs("IR TEST UP1 ", inbuf);
        typed(10, "\x91");
        go_();
        break;
    case 13:
        if (!idle())
            return;
        logs("IR TEST UP2 ", inbuf);
        typed(typed(10, "\x1b/nick verandaz\r") + 10, "/join #new\r");
        go_();
        break;
    case 14:                            /* #new joined (shown): /part */
        r = wi("#new");
        if (!idle() || r == 0xFF || !W[r].joined || W[r].names || cw != r)
            return;
        logs("IR TEST ME ", me);
        tabs_log();
        typed(10, "/part\r");
        go_();
        break;
    case 15:
        if (!idle() || wi("#new") != 0xFF)
            return;
        tabs_log();
        typed(10, "/query dave\r");
        go_();
        break;
    case 16:
        if (!idle())
            return;
        tabs_log();
        typed(10, "/close\r");
        go_();
        break;
    case 17:                            /* 400 lines to #x16 */
        if (!idle())
            return;
        tabs_log();
        tab(10, wi("#x16"));
        go_();
        gate("flood");
        break;
    case 18:
        if (!done())
            return;
        sb_log(wi("#x16"));
        snap("FLOOD.RAW");
        for (x = 0; x < 12; ++x)
            Sx(10 + x * 30, 0x82, 0, F_KEY);          /* PgUp (a page drawn: about 10 frames) */
        go_();
        break;
    case 19:
        if (!idle())
            return;
        logn("IR TEST SCROLL ", W[cw].scroll);
        snap("SCROLL.RAW");
        typed(10, "\x04");                         /* End */
        go_();
        break;
    case 20:                            /* #retro; Alt+Tab while lines come */
        if (!idle())
            return;
        logn("IR TEST SCROLL END ", W[cw].scroll);
        tab(10, wi("#retro"));
        go_();
        break;
    case 21:
        if (!idle())
            return;
        gate("aside");
        switchReq = SWITCH_ASIDE;
        break;
    case 22:
        if (!t_aside || !done())
            return;
        say("IR TEST BACK");
        snap("ASIDE.RAW");
        gate("close");
        W_();
        C(30, 256, 272);
        go_();
        break;
    case 23:                            /* the server closed: the box */
        if (!idle_box() || cstate != C_OFF)
            return;
        snap("CLOSED.RAW");
        measure();
        the_end();
        return;
    }
    NEXT();
}

extern char right[64];
#pragma bss-name (push, "OVL6BSS")
static unsigned int tjoin, tnames;      /* (overlay 6's: main RAM is full in the test build) */
#pragma bss-name (pop)

/* a channel's counts: "IR TEST PEOPLE <name> <people> <nicks kept>" */
static void __fastcall__ people_log(const char *name)
{
    unsigned char w = wi(name);
    strcpy(tl, "IR TEST PEOPLE ");
    strcat(tl, name);
    strcat(tl, " ");
    unum(tl + strlen(tl), W[w].people);
    strcat(tl, " ");
    unum(tl + strlen(tl), W[w].nicks);
    LogText(tl);
}

/* the status bar's right (as drawn) and the window it is for */
static void status_log(void)
{
    logs("IR TEST STATUS ", right);
    logs("IR TEST SHOWN ", W[cw].name);
}

/* big (V178): channels as Libera's #linux and EFnet's #freebsd (the
   user's X16 stopped after joining them): 2,400 and 600 people, topics of
   460 bytes; the counts; lines past 512 bytes; more windows than there
   is room for; a busy channel's traffic */
static void big_steps(void)
{
    unsigned char r, x;
    unsigned int e, mx;
    switch (step) {
    case 1:                             /* the gate's server (the only one): Return */
        if (!sv_page || net_state() != NET_READY)
            return;
        typed(10, "\r");
        for (x = 0; x < 12; ++x) {      /* (the user's hands while the names come: the nick list, the tabs) */
            Sx(300 + x * 300, 560, 100 + x * 12, 0);
            C(340 + x * 300, 560, 70 + x * 14);
            if (x & 1)
                tab(400 + x * 300, 1 + (x & 2) / 2);
        }
        go_();
        tjoin = ser_frames;
        break;
    case 2:                             /* both joined, their names in */
        r = wi("#huge");
        x = wi("#big");
        if (cstate != C_UP || r == 0xFF || x == 0xFF || !W[r].joined || W[r].names || W[x].names || !W[r].nicks)
            return;
        if (!tnames)                    /* (from Return to #huge's 366: the NAMES of 3,000 people) */
            tnames = ser_frames - tjoin;
        if (!idle())
            return;
        logn("IR TEST JOIN FRAMES ", tnames);
        tabs_log();
        people_log("#big");
        people_log("#huge");
        status_log();
        topic_get(x, tbuf, TOPICMAX);
        logn("IR TEST TOPIC LEN ", strlen(tbuf));
        logs("IR TEST TOPICTEXT ", tbuf);
        snap("BIG.RAW");
        gate("count");
        break;
    case 3:                             /* #big's people counted */
        if (!done())
            return;
        people_log("#big");
        nicks_log(wi("#big"));
        gate("long");
        break;
    case 4:                             /* lines past 512 bytes */
        if (!done())
            return;
        topic_get(wi("#huge"), tbuf, TOPICMAX);
        logn("IR TEST TOPIC2 LEN ", strlen(tbuf));
        r = wi("#big");                 /* (the longest line #big keeps) */
        for (e = W[r].used, mx = 0; e; )
            if ((e = sb_prev(r, e)) != 0 && ln_len > mx)
                mx = ln_len;
        logn("IR TEST SB MAXLEN ", mx);
        tab(10, wi("#big"));
        go_();
        break;
    case 5:
        if (!idle())
            return;
        snap("LONG.RAW");
        gate("tabs");
        break;
    case 6:                             /* more windows than there is room for */
        if (!done())
            return;
        tabs_log();
        tab(10, wi("#big"));
        go_();
        break;
    case 7:
        if (!idle())
            return;
        gt_ov1(t_nend);                 /* (#big's list at its end: "and N more") */
        status_log();
        snap("NICKEND.RAW");
        gate("storm1");
        break;
    case 8:                             /* a busy channel's traffic */
        if (!done())
            return;
        people_log("#big");
        people_log("#huge");
        status_log();
        snap("STORM.RAW");
        the_end();
        return;
    }
    NEXT();
}

void gt_tick(void)
{
    unsigned char h, r;
    unsigned int f = now();
    if (t_boxed)
        t_boxed = tlast = 0;
    if (tlast && f - tlast > 20) {
        strcpy(tl, "IR GAP AT STEP ");
        unum(tl + strlen(tl), step);
        strcat(tl, ": ");
        unum(tl + strlen(tl), f - tlast);
        LogText(tl);
    }
    if (tlast && f - tlast > tmax)
        tmax = f - tlast;
    tlast = f;
    if (!step) {
        strcpy(tl, VR_ROOTPATH "CHAT.TST");
        h = FOpen(tl, 'r');
        if (h < 2 || h > 4) {
            step = 0xFF;
            return;
        }
        tl[FRead(h, tl, 40)] = 0;
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
        say("IR TEST START");
        return;
    }
    if (step == 0xFF)
        return;
    if (ser_frames - tstep_t > 60u * 120) {
        logn("IR TEST STUCK AT STEP ", step);
        snap("FAIL.RAW");
        fail("TIMEOUT");
        return;
    }
    if (sess == 'n' || sess == 'c') {   /* nomodem, closedport: Return, the box */
        switch (step) {
        case 1:
            if (!sv_page)
                return;
            typed(10, "\r");
            W_();
            C(30, 256, 272);
            go_();
            break;
        case 2:
            if (!idle_box())
                return;
            say("IR TEST NOMODEM BOX");
            the_end();
            return;
        }
        NEXT();
        return;
    }
    if (sess == 'w') {                  /* (V179) welcome: a big network's welcome at once, then #retro */
        switch (step) {
        case 1:
            if (!sv_page || net_state() != NET_READY)
                return;
            typed(10, "\r");
            go_();
            break;
        case 2:
            r = wi("#retro");
            if (cstate != C_UP || r == 0xFF || !W[r].joined || W[r].names || !idle())
                return;
            logn("IR TEST RX LINES ", crx_lines);
            tabs_log();
            the_end();
            return;
        }
        NEXT();
        return;
    }
    if (sess == 'b') {                  /* big: channels of hundreds of people, long lines */
        big_steps();
        return;
    }
    if (sess == 'r') {                  /* reread: CHAT.SERVERS read back */
        switch (step) {
        case 1:
            if (!sv_page || net_state() != NET_READY)
                return;
            snap("SERVERS2.RAW");
            typed(10, "\x02\x02\x02\r");            /* PgDn x 3, Return */
            go_();
            break;
        case 2:
            r = wi("#x16");
            if (cstate != C_UP || r == 0xFF || !W[r].joined || W[r].names || !idle())
                return;
            logs("IR TEST ME ", me);
            tabs_log();
            the_end();
            return;
        }
        NEXT();
        return;
    }
    main_steps();
}
