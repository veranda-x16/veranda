/* gate ask (DECISIONS V116): Veranda Ask's test build (apps/ask, make test:
   CLAUDE_TEST and ASK; this file in overlay 11 (V149: its own; was 10 with log.c, V129), its data in main RAM, where
   the pointer's player reads it from the interrupt; tests/term_play.s
   plays the mouse and the keys through mouseSource, as for Veranda Claude).

   ASK.TST: the session, the fake OpenAI's port, the sign-in helper's port,
   then "plain" when the emulator's modem has no ATCS.
     main     (tools/gate_ask.sh) ASK.CFG with the fake's hosts and no
              credentials: the Settings page at the start; the helper's
              address, a wrong code: its box; the right code: the sign-in
              (the helper, the fake's OAuth, a scripted browser), the
              plan's notice, Got it; two turns streamed; a 401 (the access
              token expired): the renewal, the turn again; the usage limit
              and not eligible boxes; Esc mid-reply; Alt+Tab mid-reply; a
              failed reply; an interrupted one; a refresh token that is
              dead: sign in again; Settings, OpenAI API key, the key typed:
              a turn with it
     nomodem  (no modem on the port) an API key in ASK.CFG: a turn, the box
     renew    (V129) ASK.CFG signed in (the fake's seed pair), the X16's
              clock set to the PC's (UTC, from ASK.TST: utc=YYMMDDHHMMSS):
              a renewal's reply in each of the fake's styles (FAKE_TOKSTYLE:
              Content-Length, keep-alive, tiny chunks, a big one, escapes,
              not rotated, an access token too long: its box, then the next
              turn renews first), a token due by its exp (renewed before the
              turn), the clock set to 1 January 2000 (not trusted: the turn
              goes, the 401 renews); ASK.LOG shown ("CL LOG ...")
     code     (V123; its own build, -DCODE_SESSION) tests/code_steps.h
   The log lines "CL ..." on the console; screens as in claude_play.c.

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <string.h>
#include <vrnet.h>
#include <vrser.h>
#include <vrpath.h>
#include "../apps/claude/claude.h"
#pragma code-name ("OVERLAY11")
#pragma rodata-name ("OVL11RO")

void __fastcall__ term_play(const unsigned int *script);
void __fastcall__ t_ui(void (*f)(void));        /* (main.c: f in overlay 1) */
void t_status(void);                            /* (ui.c: msg in the status bar) */
void term_dump(void);

#define F_BTN 0x100
#define F_KEY 0x8000

static unsigned int scr[3 * 64];       /* (main RAM: the player reads it from the interrupt) */
static char tl[100];                    /* (main RAM: LogText, FOpen read it) */
#pragma data-name (push, "OVL11DATA")
static unsigned char step = 0, ns = 0;  /* (in the overlay's file: its BSS is not cleared) */
#pragma data-name (pop)
#pragma bss-name (push, "OVL11BSS")
static unsigned char nbox;
static unsigned int tplay, tlen, plen;
static unsigned char sess, plain, want;
static unsigned int t0, tmax, tlast, tstep_t;
static char port[8], hlport[8];
static char tx[64];
static char rtail[12];
static unsigned char utc[6];            /* (renew) the PC's clock: YY MM DD HH MM SS */
static unsigned int rwait;
static unsigned char rph;
static unsigned char rmatch, rin, rcount;
#pragma bss-name (pop)
#define wrow ((unsigned char *)line)

static void say(const char *s)
{
    strncpy(tl, s, sizeof tl - 1);
    LogText(tl);
}

/* (V149) a new script's first entry: the player stopped first. It may
   still be reading the last script (its pointer at that script's end,
   its frame counter long past): the entries written over that end would
   be played at once, half written (keys of an older script: "fé", "00",
   "3fix" in requests). So scr's first entry becomes an end and the player
   starts on it (frame 0); the entry is written over before it is due. */
static void Sx(unsigned int f, unsigned int x, unsigned int y, unsigned int fl)
{
    if (!ns) {
        scr[0] = scr[1] = 0xFFFF;
        term_play(scr);
    }
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

static void msgs_log(void)
{
    unsigned int a = 0, nx, n;
    unsigned char k, i;
    logn("CL USED ", st_used);
    while (a < st_used) {
        nx = st_msg(a);
        k = st_k;
        n = st_n;
        strcpy(tl, "CL MSG ");
        tl[7] = k;
        tl[8] = ' ';
        unum(tl + 9, n);
        strcat(tl, " ");
        i = strlen(tl);
        st_copy(a + 3, tl + i, n > 70 ? 70 : n);
        tl[i + (n > 70 ? 70 : n)] = 0;
        for (; tl[i]; ++i)
            if (tl[i] == '\n')
                tl[i] = '|';
        LogText(tl);
        a = nx;
    }
}

void gt_turn(void)
{
    ++t_turns;
    strcpy(tl, "CL TURN END rq ");
    unum(tl + strlen(tl), rq);
    strcat(tl, " status ");
    unum(tl + strlen(tl), p_status);
    strcat(tl, " end ");
    unum(tl + strlen(tl), tend);
    strcat(tl, " bytes ");
    unum(tl + strlen(tl), trx);
    LogText(tl);
}

/* the live slot, as main RAM has it */
static void slot_log(void)
{
    strcpy(tl, "CL TEST SLOT ");
    unum(tl + strlen(tl), tlive);
    strcat(tl, " acc ");
    unum(tl + strlen(tl), sl.acc);
    strcat(tl, " ref ");
    unum(tl + strlen(tl), sl.ref);
    strcat(tl, " cid ");
    unum(tl + strlen(tl), sl.cid);
    strcat(tl, " hid ");
    unum(tl + strlen(tl), sl.hid);
    strcat(tl, " models ");
    unum(tl + strlen(tl), sl.nmod);
    strcat(tl, " key ");
    tl[strlen(tl) + 1] = 0;
    tl[strlen(tl)] = '0' + C.key[0];
    strcat(tl, " srv ");
    unum(tl + strlen(tl), C.srv);
    strcat(tl, " model ");
    strcat(tl, C.mslug);
    LogText(tl);
}

/* ASK.CFG as the card has it now: its refresh= value's last 8 characters */
static void cfg_refresh(void)
{
    static const char want_[] = "\nrefresh=";
    unsigned char h, i, k;
    char c;
    vr_cd(VR_DATA);
    strcpy(tl, "ASK.CFG");
    h = FOpen(tl, 'r');
    rmatch = rin = rcount = 0;
    memset(rtail, 0, sizeof rtail);
    if (h >= 2 && h <= 4) {
        do {
            k = FRead(h, tl, 64);
            for (i = 0; i < k; ++i) {
                c = tl[i];
                if (rin) {
                    if (c == '\r' || c == '\n')
                        rin = 0;
                    else {
                        memmove(rtail, rtail + 1, 7);
                        rtail[7] = c;
                        ++rcount;
                    }
                } else if (c == want_[rmatch]) {
                    if (++rmatch == 9) {
                        rin = 1;
                        rmatch = 0;
                    }
                } else
                    rmatch = c == '\n';
            }
        } while (k == 64);
        FClose(h);
    }
    rtail[8] = 0;
    logs("CL TEST CFGREF ", rtail);
}

static void __fastcall__ turn(const char *s, unsigned char box)
{
    strcpy(tx, s);
    strcat(tx, "\r");
    typed(10, tx);
    if (box)
        box_ok(tlen + 10);
    go_();
    want = t_turns + 1;
}

static unsigned char turned(void)
{
    return t_turns >= want && tstate == T_IDLE && !tdone && idle();
}

static void clear_in(void)
{
    in_len = in_cur = 0;
    inbuf[0] = 0;
}

#define NEXT() do { ++step; tstep_t = ser_frames; } while (0)

#ifndef CODE_SESSION
/* (V129) ASK.LOG on the console, a line at a time (cut at 90) */
static void log_dump(void)
{
    unsigned char h, i, k, n = 0;
    vr_cd(VR_DATA);
    strcpy(tl, "ASK.LOG");
    h = FOpen(tl, 'r');
    if (h < 2 || h > 4) {
        say("CL LOG NONE");
        return;
    }
    strcpy(tx, "CL LOG ");
    n = 7;
    do {
        k = FRead(h, wrow, 64);
        for (i = 0; i < k; ++i) {
            if (wrow[i] == '\n') {
                tx[n] = 0;
                say(tx);
                strcpy(tx, "CL LOG ");
                n = 7;
            } else {
                if (n == sizeof tx - 1) {   /* (a long line: on in "CL LOG+") */
                    tx[n] = 0;
                    say(tx);
                    strcpy(tx, "CL LOG+");
                    n = 7;
                }
                tx[n++] = wrow[i] >= 32 && wrow[i] < 127 ? wrow[i] : '?';
            }
        }
    } while (k == 64);
    FClose(h);
    say("CL LOG END");
}

static const char *const rturns[] = { "expire1 clen", "expire2 keepalive", "expire3 chunkka", "expire4 big",
    "expire5 escaped", "expire6 norefresh", "expire7 toolong", "expire8 after", "expire9 soon", "due10 please",
    "refuse please", "expire11 stale", "word12 please", 0 };

/* a turn typed, checked in the input box (typed again when a key went
   astray: the ROM's keyboard buffer is 10 keys), then sent; rph 1: typed */
static void __fastcall__ rtype(const char *s)
{
    clear_in();
    strcpy(tx, s);
    typed(10, tx);
    go_();
    rph = 1;
}

static void renew_steps(void)
{
    unsigned char i = step - 2;
    if (step == 1) {
        if (pg_on || net_state() != NET_READY || !idle())
            return;
        SetClock(100 + utc[0], utc[1], utc[2], utc[3], utc[4], utc[5], 1);
        rwait = 0;
        slot_log();
        rtype(rturns[0]);
        NEXT();
        return;
    }
    if (rph == 1) {                     /* (the text in the box as typed: Return) */
        if (!idle())
            return;
        if (in_len != strlen(rturns[i]) || memcmp(inbuf, rturns[i], in_len)) {
            logs("CL TEST RETYPED, the box had: ", inbuf);
            rtype(rturns[i]);
            return;
        }
        typed(10, "\r");
        if (i == 6 || i == 10)          /* (V131: 10, a fresh token refused: its box, not renewed) */
            box_ok(tlen + 10);
        go_();
        want = t_turns + 1;
        rph = 2;
        return;
    }
    if (!turned())
        return;
    if (!rwait) {                       /* (a second for the turn's end to settle before the next is typed) */
        rwait = ser_frames | 1;
        return;
    }
    if (ser_frames - rwait < 60)
        return;
    rwait = 0;
    slot_log();
    cfg_refresh();
    if (i == 6 || i == 10) {            /* (the access token too long: its box, the text back) */
        logs("CL TEST INPUT ", inbuf);
        if (i == 6)
            log_dump();
        clear_in();
    }
    if (i == 10) {                      /* the clock as if never set (V131: after the refused turn) */
        SetClock(100, 1, 1, 0, 0, 0, 7);
        ov4(ask_right);
        logs("CL TEST RIGHT ", right);
        t_ui(t_status);                 /* (V149: ui.c's, overlay 1: mapped first) */
        snap("CLOCK.RAW");
    }
    if (!rturns[i + 1]) {
        log_dump();
        snap("FINAL.RAW");
        msgs_log();
        the_end();
        return;
    }
    rtype(rturns[i + 1]);
    NEXT();
}

static void main_steps(void)
{
    unsigned int f;
    switch (step) {
    case 1:                             /* not signed in: the Settings page; the address, a wrong code */
        if (!pg_on || net_state() != NET_READY || !idle())
            return;
        logn("CL TEST NET READY ", ser_frames - t0);
        slot_log();
        snap("FIRST.RAW");
        strcpy(tx, "127.0.0.1:");
        strcat(tx, hlport);
        f = typed(10, tx);
        f = typed(f, "\t000000\r");
        box_ok(f + 10);
        go_();
        want = t_turns + 1;
        break;
    case 2:                             /* its box came; Settings again, the right code */
        if (!turned())
            return;
        M(10, 2, 0);
        f = typed(tlen + 30, "\t271828");
        go_();
        break;
    case 3:
        if (!pg_on || !idle())
            return;
        snap("SETTINGS.RAW");
        typed(10, "\r");
        go_();
        want = t_turns + 1;
        break;
    case 4:                             /* signed in: the plan's notice */
        if (!turned() || !pg_on)
            return;
        slot_log();
        snap("NOTICE.RAW");
        typed(10, "\r");
        go_();
        break;
    case 5:
        if (pg_on || !idle())
            return;
        logn("CL TEST NOTICE ", notice);
        turn("Hello there! Caf\xe9?", 0);
        break;
    case 6:
        if (tstate != T_RECV || p_text < 120)
            return;
        snap("MIDSTREAM.RAW");
        break;
    case 7:
        if (!turned())
            return;
        turn("second please", 0);
        break;
    case 8:
        if (!turned())
            return;
        snap("CHAT.RAW");
        msgs_log();
        turn("expire please", 0);
        break;
    case 9:                             /* renewed and sent again */
        if (!turned())
            return;
        slot_log();
        cfg_refresh();
        msgs_log();
        turn("limit please", 1);
        break;
    case 10:
        if (!turned())
            return;
        snap("LIMIT.RAW");
        logs("CL TEST INPUT ", inbuf);
        clear_in();
        turn("eligible please", 1);
        break;
    case 11:
        if (!turned())
            return;
        logs("CL TEST INPUT ", inbuf);
        clear_in();
        turn("slow please", 0);
        break;
    case 12:
        if (tstate != T_RECV || p_text < 30)
            return;
        typed(10, "\x1b");
        go_();
        break;
    case 13:
        if (!turned())
            return;
        turn("aside please", 0);
        break;
    case 14:
        if (tstate != T_RECV || !p_text)
            return;
        say("CL TEST ASIDE");
        switchReq = SWITCH_ASIDE;
        break;
    case 15:
        if (!t_aside || !turned())
            return;
        say("CL TEST BACK");
        turn("failed please", 1);
        break;
    case 16:
        if (!turned())
            return;
        turn("interrupt please", 0);
        break;
    case 17:
        if (!turned())
            return;
        msgs_log();
        turn("revoke please", 1);
        break;
    case 18:                            /* signed out; Settings, OpenAI API key, the key */
        if (!turned())
            return;
        snap("SIGNEDOUT.RAW");
        logs("CL TEST INPUT ", inbuf);
        clear_in();
        slot_log();
        M(10, 2, 0);
        CK(tlen + 30, 136, 88);
        typed(tlen + 20, "sk-gate-0000-openai-dummy-key-for-tests-ABCD");
        go_();
        break;
    case 19:
        if (!pg_on || !idle())
            return;
        snap("APIKEY.RAW");
        typed(10, "\r");
        go_();
        break;
    case 20:
        if (pg_on || !idle())
            return;
        slot_log();
        turn("api please Za\xbf\xf3\xb3\xe5 g\xfd\xf7l\xa2 ja\xae\xf1 ZA\xaf\xd3\xa3\xc5 G\xdd\xd7L\xa1 JA\xac\xd1", 0);       /* (V143: Polish typed; after the aside,
                                                   which a longer conversation would not fit at 512 KB) */
        break;
    case 21:
        if (!turned())
            return;
        snap("FINAL.RAW");
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
    if (tlast && f - tlast > tmax)
        tmax = f - tlast;
    tlast = f;
    if (!step) {
        strcpy(tl, VR_ROOTPATH "ASK.TST");
        h = FOpen(tl, 'r');
        if (h < 2 || h > 4) {
            step = 0xFF;
            return;
        }
        tl[FRead(h, tl, 60)] = 0;
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
        strncpy(hlport, tl + h + 1, 6);
        for (h = 0; hlport[h] >= '0' && hlport[h] <= '9'; ++h)
            ;
        hlport[h] = 0;
        if (strstr(tl, "utc="))
            for (h = 0; h < 6; ++h)
                utc[h] = (strstr(tl, "utc=")[4 + 2 * h] - '0') * 10 + strstr(tl, "utc=")[5 + 2 * h] - '0';
        step = 1;
        want = 0;                       /* (an overlay's BSS is not cleared) */
        tplay = tlen = plen = 0;         /* (V129: the bank is log.c's too) */
        nbox = rph = 0;
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
        step = 0xFF;
        return;
    }
    if (sess == 'n' || sess == 't') {
        switch (step) {
        case 1:
            if (!idle() || pg_on)
                return;
            turn("hello", sess == 'n');  /* (V131: t, signed in: the turn goes) */
            break;
        case 2:
            if (!turned())
                return;
#ifndef CODE_SESSION
            if (sess == 't')
                log_dump();
#endif
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
        code_steps();
#else
    if (sess == 'r')
        renew_steps();
    else
        main_steps();
#endif
    if (step != h)
        tlast = 0;
}
