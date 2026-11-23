/* gate claude (DECISIONS V114): Veranda Claude's test build (apps/claude,
   make test: CLAUDE_TEST; this file in overlay 9, its data in main RAM,
   where the pointer's player reads it from the interrupt;
   tests/term_play.s plays the mouse and the keys through mouseSource, as
   for Veranda Chat and Gopher).

   CLAUDE.TST: the session, then the server's port, then "plain" when the
   emulator's modem has no ATCS (then the connection is plain ATC).
     main     (tools/gate_claude.sh): CLAUDE.CFG without a key: the
              Settings page at the start; the key typed, Return (saved);
              a turn: the thinking pause, the reply streamed (Unicode
              escapes, raw UTF-8); a long reply; a max_tokens stop; a
              refusal; a 529 (its box); an error event mid-stream (its
              box); a 401 (its box); a slow reply stopped with Esc; a
              reply with the program put aside (Alt+Tab); four big
              replies (the oldest turns dropped); Settings > Claude
              Haiku 5.5 and a turn; File > Save (Ctrl+S); New (Ctrl+N)
     nomodem  (no modem on the port) a key in CLAUDE.CFG: a message, the box
     code     (V123) code blocks, files, Remember, compaction: code_steps()
     bridge   (tools/gate_claude_bridge.sh; V115: "bridge <bridge's port>
              <a closed port>") an API key in CLAUDE.CFG: Settings,
              Claude Code on my PC (a click), the address typed, Tab, a
              wrong password, Return; a turn: the 401 box; Settings, the
              password typed again; two turns (the second resumes the
              session); the usage limit, not signed in (their boxes); a
              slow reply stopped with Esc; Settings, the address of a
              closed port: the refused box; Settings, Anthropic API (a
              click), Return: the API's key and host back
   Screens (snap: the foreground's 480 rows of 80 bytes, the cards'
   paper colours, 60 rows of 80, the palette's 16 entries); the log lines
   "CL ..." on the console.

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <string.h>
#include <vrnet.h>
#include <vrser.h>
#include "../apps/claude/claude.h"
#pragma code-name ("OVERLAY9")
#pragma rodata-name ("OVL9RO")
/* (its texts in overlay 9: say() copies them below $A000 for the kernel) */

void __fastcall__ term_play(const unsigned int *script);
void term_dump(void);


#define F_BTN 0x100
#define F_KEY 0x8000

static unsigned int scr[3 * 48];       /* (main RAM: the player reads it from the interrupt) */
static char tl[100];                    /* (main RAM: LogText, FOpen read it) */
#pragma data-name (push, "OVL9DATA")
static unsigned char step = 0, ns = 0;  /* (in the overlay's file: its BSS is not cleared) */
static unsigned char msub = 0;          /* (V149: case 22's: the Settings menu open) */
#pragma data-name (pop)
#pragma bss-name (push, "OVL9BSS")
static unsigned char nbox;
static unsigned int tplay, tlen, plen;
static unsigned char sess, plain, want;
static unsigned int t0, tmax, tlast, tstep_t;
static char port[8], cport[8];
static char tx[64];
#pragma bss-name (pop)
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

static void CK(unsigned int f, unsigned int x, unsigned int y)
{
    Sx(f, x, y, 0);
    Sx(f + 3, x, y, F_BTN);
    Sx(f + 7, x, y, 0);
}

/* menu m of the bar, its item n */
static void M(unsigned int f, unsigned char m, unsigned char n)
{
    Sx(f, barx[m], 7, 0);
    Sx(f + 1, barx[m], 7, F_BTN);
    Sx(f + 2, barl[m] + 12, 24, 0);
    CK(f + 20, barl[m] + 12, 24 + 16 * n);
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

/* the script waits for a box, then clicks its first button */
static void box_ok(unsigned int f)
{
    Sx(f, (unsigned int)&t_box, 0, 0x1000);
    CK(30, 256, 272);
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
        say("CL SNAP FAILED");
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
    logs("CL SNAP ", name);
}

static void the_end(void)
{
    logn("CL MAXGAP ", tmax);
    logn("CL LOST ", ser_lost);
    logn("CL OE ", ser_oe);
    logn("CL PACKETS ", net_stats.packets);
    logn("CL XONRETRY ", net_stats.xon_retries);
    logn("CL BADCRC ", net_stats.badcrc);
    say("CL END");
    term_dump();
}

static unsigned int now(void)
{
    unsigned int t;
    asm("sei");
    t = ser_frames;
    asm("cli");
    return t;
}

/* the conversation: "CL MSG <kind> <length> <text>" (its start; line
   feeds as '|'), one a message */
static void msgs_log(void)
{
    unsigned int a = 0, nx, n;
    unsigned char k, i;
    logn("CL USED ", st_used);
    logn("CL ROWS ", st_rows);
    while (a < st_used) {
        nx = st_msg(a);
        k = st_k;
        n = st_n;
        tl[0] = 0;
        strcpy(tl, "CL MSG ");
        tl[7] = k;
        tl[8] = ' ';
        unum(tl + 9, n);
        strcat(tl, " ");
        i = strlen(tl);
        st_copy(a + 3, tl + i, n > 60 ? 60 : n);
        tl[i + (n > 60 ? 60 : n)] = 0;
        for (; tl[i]; ++i)
            if (tl[i] == '\n')
                tl[i] = '|';
        LogText(tl);
        a = nx;
    }
}

/* rows from..to - 1: "CL ROW <flags> <text>" */
static void __fastcall__ rows_log(unsigned int from, unsigned int to)
{
    unsigned char fl, n;
    for (; from < to && from < st_rows; ++from) {
        fl = row_get(from);
        strcpy(tl, "CL ROW ");
        unum(tl + 7, fl);
        strcat(tl, " ");
        n = strlen(tl);
        memcpy(tl + n, cs_txt, TW);
        tl[n + TW] = 0;
        while (tl[n] && tl[strlen(tl) - 1] == ' ')
            tl[strlen(tl) - 1] = 0;
        LogText(tl);
    }
}

/* (ui.c's, at a turn's end) its bytes, frames; the main loop's costs */
void gt_turn(void)
{
    ++t_turns;
    strcpy(tl, "CL TURN END ");
    unum(tl + strlen(tl), trx);
    strcat(tl, " bytes, ");
    unum(tl + strlen(tl), ser_frames - tt0);
    strcat(tl, " frames, ");
    unum(tl + strlen(tl), t_pages);
    strcat(tl, " pages; parse ");
    unum(tl + strlen(tl), t_fp);
    strcat(tl, ", draw ");
    unum(tl + strlen(tl), t_fb);
    strcat(tl, ", reads ");
    unum(tl + strlen(tl), t_reads);
    LogText(tl);
    t_pages = t_fp = t_fb = t_reads = 0;
}

/* a message typed and sent; box: the box that comes is clicked away */
static void __fastcall__ turn(const char *s, unsigned char box)
{
    strcpy(tx, s);
    strcat(tx, "\r");
    typed(10, tx);
    if (box)
        box_ok(tlen + 10);
    go_();
    ++want;
}

static unsigned char turned(void)
{
    return t_turns == want && tstate == T_IDLE && !tdone && idle();
}

static void clear_in(void)
{
    in_len = in_cur = 0;
    inbuf[0] = 0;
}

#define NEXT() do { ++step; tstep_t = ser_frames; } while (0)
#ifndef CODE_SESSION

static void main_steps(void)
{
    switch (step) {
    case 1:                             /* no key: the Settings page */
        if (!pg_on || net_state() != NET_READY || !idle())
            return;
        logn("CL TEST NET READY ", ser_frames - t0);
        snap("FIRST.RAW");
        typed(10, "sk-ant-gate-0000-dummy-key-for-tests-WXYZ");
        go_();
        break;
    case 2:
        if (!idle())
            return;
        snap("SETTINGS.RAW");
        typed(10, "\r");
        go_();
        break;
    case 3:                             /* saved; the first turn */
        if (pg_on || !idle())
            return;
        logs("CL TEST KEY ", C.key);
        turn("Caf\xe9? Za\xbf\xf3\xb3\xe5 g\xfd\xf7l\xa2 ja\xae\xf1 ZA\xaf\xd3\xa3\xc5 G\xdd\xd7L\xa1 JA\xac\xd1", 0);   /* (V143: Polish, typed as the set) */
        break;
    case 4:                             /* its thinking pause */
        if (tstate != T_RECV || p_status != 200 || p_text)
            return;
        snap("THINKING.RAW");
        break;
    case 5:                             /* its text coming */
        if (tstate != T_RECV || p_text < 120)
            return;
        snap("MIDSTREAM.RAW");
        break;
    case 6:
        if (!turned())
            return;
        snap("HELLO.RAW");                      /* (V143: the Polish turn's glyphs) */
        msgs_log();
        rows_log(st_rows > 16 ? st_rows - 16 : 0, st_rows);
        turn("Please tell me a long story.", 0);
        break;
    case 7:
        if (!turned())
            return;
        snap("LONG.RAW");
        typed(10, "\x82\x82\x82\x82\x82");          /* PgUp x 5 */
        go_();
        break;
    case 8:
        if (!idle())
            return;
        snap("STORY.RAW");
        logn("CL TEST STORY ROWS ", st_rows);
        typed(10, "\x1b");                          /* Esc: the newest again */
        go_();
        break;
    case 9:
        if (!idle())
            return;
        turn("max please", 0);
        break;
    case 10:
        if (!turned())
            return;
        msgs_log();
        turn("refuse please", 0);
        break;
    case 11:
        if (!turned())
            return;
        logs("CL TEST INPUT ", inbuf);
        clear_in();
        turn("overload please", 1);
        break;
    case 12:
        if (!turned())
            return;
        logs("CL TEST INPUT ", inbuf);
        clear_in();
        turn("midstream please", 1);
        break;
    case 13:
        if (!turned())
            return;
        logs("CL TEST INPUT ", inbuf);
        turn("key please", 1);
        break;
    case 14:
        if (!turned())
            return;
        logs("CL TEST INPUT ", inbuf);
        snap("ERROR.RAW");
        clear_in();
        turn("slow please", 0);
        break;
    case 15:                            /* Esc while it comes */
        if (tstate != T_RECV || p_text < 30)
            return;
        typed(10, "\x1b");
        go_();
        break;
    case 16:
        if (!turned())
            return;
        msgs_log();
        turn("aside please", 0);
        break;
    case 17:                            /* Alt+Tab while it comes */
        if (tstate != T_RECV || !p_text)
            return;
        say("CL TEST ASIDE");
        switchReq = SWITCH_ASIDE;
        break;
    case 18:
        if (!t_aside || !turned())
            return;
        say("CL TEST BACK");
        msgs_log();
        turn("big 1 please", 0);
        break;
    case 19: case 20: case 21:
        if (!turned())
            return;
        logn("CL TEST USED ", st_used);
        strcpy(tx, "big 2 please");
        tx[4] = '0' + step - 17;
        turn(tx, 0);
        break;
    case 22:                            /* Settings > Claude Haiku 5.5 (V149: the menu's picture first) */
        if (!msub) {
            if (!turned())
                return;
            logn("CL TEST USED ", st_used);
            msgs_log();
            Sx(10, barx[2], 7, 0);
            Sx(11, barx[2], 7, F_BTN);
            Sx(12, barl[2] + 12, 24, 0);
            go_();
            msub = 1;
            return;
        }
        if (!idle())
            return;
        snap("MENU.RAW");
        CK(10, barl[2] + 12, 24 + 16 * 3);
        go_();
        break;
    case 23:
        if (!idle())
            return;
        logn("CL TEST MODEL ", C.model);
        turn("haiku please", 0);
        break;
    case 24:                            /* File > Save conversation..., the name as it is */
        if (!turned())
            return;
        snap("FINAL.RAW");
        msgs_log();
        M(10, 1, 2);                    /* (V123: File > Export as text...) */
        Sx(tlen + 10, (unsigned int)&t_box, 0, 0x1000);
        typed(30, "\r");
        go_();
        break;
    case 25:                            /* File > New conversation (V123: no box: the chat is kept) */
        if (!idle() || t_nbox == nbox)
            return;
        logs("CL TEST SAVED ", sv_name);
        logn("CL TEST SVERR ", sv_err);
        M(10, 1, 0);
        go_();
        break;
    case 26:
        if (!idle())
            return;
        msgs_log();
        the_end();
        return;
    }
    NEXT();
}

/* Settings > Server, key and model... */
static void settings(void)
{
    M(10, 2, 0);
    go_();
}

static unsigned char __fastcall__ bs(unsigned int f, unsigned char n)
{
    while (n--) {
        Sx(f, 8, 0, F_KEY);
        f += 3;
    }
    return f;
}

static void conf_log(void)
{
    strcpy(tl, "CL TEST CONF ");
    strcat(tl, C.srv ? "bridge " : "api ");
    strcat(tl, C.host);
    strcat(tl, ":");
    unum(tl + strlen(tl), C.port);
    strcat(tl, C.tls ? " tls " : " plain ");
    strcat(tl, C.key);
    LogText(tl);
}

static void bridge_steps(void)
{
    unsigned int f;
    switch (step) {
    case 1:
        if (pg_on || net_state() != NET_READY || !idle())
            return;
        conf_log();
        settings();
        break;
    case 2:                             /* Claude Code on my PC, the address, Tab, a wrong password */
        if (!pg_on || !idle())
            return;
        CK(10, 136, 96);
        strcpy(tx, "127.0.0.1:");
        strcat(tx, port);
        f = typed(tlen + 10, tx);
        f = typed(f, "\t");
        typed(f, "wrong-pass");
        go_();
        break;
    case 3:
        if (!idle())
            return;
        snap("SETBRIDGE.RAW");
        typed(10, "\r");
        go_();
        break;
    case 4:
        if (pg_on || !idle())
            return;
        conf_log();
        turn("hello bridge", 1);
        break;
    case 5:                             /* the password typed again */
        if (!turned())
            return;
        logs("CL TEST INPUT ", inbuf);
        clear_in();
        settings();
        break;
    case 6:
        if (!pg_on || !idle())
            return;
        f = bs(10, 10);
        f = typed(f, "gate-bridge-pass");
        typed(f, "\r");
        go_();
        break;
    case 7:
        if (pg_on || !idle())
            return;
        conf_log();
        turn("hello bridge", 0);
        break;
    case 8:
        if (!turned())
            return;
        turn("second turn please", 0);
        break;
    case 9:
        if (!turned())
            return;
        snap("BRIDGE.RAW");
        msgs_log();
        turn("usage limit please", 1);
        break;
    case 10:
        if (!turned())
            return;
        logs("CL TEST INPUT ", inbuf);
        clear_in();
        turn("not signed in please", 1);
        break;
    case 11:
        if (!turned())
            return;
        logs("CL TEST INPUT ", inbuf);
        clear_in();
        turn("slow please", 0);
        break;
    case 12:                            /* Esc while it comes */
        if (tstate != T_RECV || p_text < 30)
            return;
        typed(10, "\x1b");
        go_();
        break;
    case 13:
        if (!turned())
            return;
        msgs_log();
        settings();
        break;
    case 14:                            /* the address: a closed port */
        if (!pg_on || !idle())
            return;
        f = typed(10, "\t");
        f = bs(f, 16);
        strcpy(tx, "127.0.0.1:");
        strcat(tx, cport);
        strcat(tx, "\r");
        typed(f, tx);
        go_();
        break;
    case 15:
        if (pg_on || !idle())
            return;
        conf_log();
        turn("anyone there", 1);
        break;
    case 16:                            /* back to the API */
        if (!turned())
            return;
        logs("CL TEST INPUT ", inbuf);
        clear_in();
        settings();
        break;
    case 17:
        if (!pg_on || !idle())
            return;
        CK(10, 136, 80);
        typed(tlen + 10, "\r");
        go_();
        break;
    case 18:
        if (pg_on || !idle())
            return;
        conf_log();
        msgs_log();
        the_end();
        return;
    }
    NEXT();
}

#else
#include "code_steps.h"
#endif

void gt_tick(void)
{
    unsigned char h;
    unsigned int f = now();
    if (t_boxed)
        t_boxed = tlast = 0;
    if (tlast && f - tlast > 20) {
        strcpy(tl, "CL GAP AT STEP ");
        unum(tl + strlen(tl), step);
        strcat(tl, ": ");
        unum(tl + strlen(tl), f - tlast);
        LogText(tl);
    }
    if (tlast && f - tlast > tmax)
        tmax = f - tlast;
    tlast = f;
    if (!step) {
        strcpy(tl, VR_ROOTPATH "CLAUDE.TST");
        h = FOpen(tl, 'r');
        if (h < 2 || h > 4) {
            step = 0xFF;
            return;
        }
        tl[FRead(h, tl, 40)] = 0;
        FClose(h);
        sess = tl[0];
        plain = strstr(tl, "plain") != 0;
        t_plain = plain;
        for (h = 0; tl[h] && tl[h] != ' '; ++h)
            ;
        strncpy(port, tl + h + 1, 6);
        for (h = 0; port[h] >= '0' && port[h] <= '9'; ++h)
            ;
        port[h] = 0;
        for (h = 0; tl[h] && tl[h] != ' '; ++h)
            ;
        for (++h; tl[h] && tl[h] != ' '; ++h)
            ;
        strncpy(cport, tl + h + 1, 6);
        for (h = 0; cport[h] >= '0' && cport[h] <= '9'; ++h)
            ;
        cport[h] = 0;
        step = 1;
        want = 0;                       /* (an overlay's BSS is not cleared) */
        tmax = 0;
        t0 = tstep_t = ser_frames;
        say("CL TEST START");
        return;
    }
    if (step == 0xFF)
        return;
    if (ser_frames - tstep_t > 60u * 180) {
        logn("CL TEST STUCK AT STEP ", step);
        snap("FAIL.RAW");
        say("CL TEST FAILED TIMEOUT");
        term_dump();
        return;
    }
    if (sess == 'n') {                  /* nomodem: a message, the box */
        switch (step) {
        case 1:
            if (!idle() || pg_on)
                return;
            turn("hello", 1);
            break;
        case 2:
            if (!turned())
                return;
            logs("CL TEST INPUT ", inbuf);
            msgs_log();
            the_end();
            return;
        }
        NEXT();
        return;
    }
    h = step;
#ifdef CODE_SESSION
    if (sess == 'h' || sess == '2')
        hist_steps();
    else
        code_steps();                       /* (its own test build: the test's overlay has no room for all) */
#else
    if (sess == 'b')
        bridge_steps();
    else
        main_steps();
#endif
    if (step != h)
        tlast = 0;                      /* (the test's own logging: not the main loop's gap) */
}
