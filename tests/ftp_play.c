/* gate ftp (DECISIONS V100): Veranda FTP's test build (apps/ftp, make
   test: FTP_TEST; this file in overlay 4 (V149), its data in main RAM, where the
   pointer's player reads it from the interrupt; tests/term_play.s plays
   the mouse and the keys through mouseSource, as on a real X16's mouse
   path above the PS/2 driver).

   FTP.TST, one word: the session.
     main    (tools/gate_ftp.sh): Connection > Sites..., the first server
             (anonymous, start folder /pub), Connect; a double click into
             dosdir (a DOS listing), ".." back; big.bin selected, File >
             Download, at 20,000 bytes the screen (XFER.RAW) and Alt+Tab
             (switchReq: the test desktop tests/term_desk.s 3 s, then
             back); upload.bin on the card, File > Upload; File > New
             folder "newdir"; upload.bin renamed renamed.bin; renamed.bin
             and newdir deleted; ghost.bin downloaded: the server says 550
             (the box's OK clicked); Connection > Disconnect; the second
             server (a wrong password): the box; the third (MLSD); the end
     probe   the screen once the modem is ready, then the end
     timing  (V211) the first server; t300.bin (307,200 bytes) downloaded,
             then t300up.bin from the card uploaded: each one's frames
             from File > Download (Upload) to its end and from its first
             data byte to its last, its bytes, vrnet's XONs, packets,
             empty packets and sends (FTP TIME ...)
   Screens: SITES.RAW, CONN.RAW, XFER.RAW, END.RAW (ftp_snap: the
   foreground's 480 rows of 80 bytes, the cards' paper colours, 60 rows of
   80, the palette's 16 entries); the log lines "FTP ..." on the console.

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <string.h>
#include <vrnet.h>
#include <vrser.h>
#include "../apps/ftp/ftp.h"
#pragma code-name ("OVERLAY4")
#pragma rodata-name ("OVL4RO")
/* (its texts in overlay 4, V149: say() copies them below $A000 for the kernel) */

void __fastcall__ term_play(const unsigned int *script);
void term_dump(void);
extern unsigned char t_box, t_aside, t_boxed, t_nbox;
static unsigned char nbox;
extern unsigned int barx[4], barl[4];
void ftp_test_log(const char *s);

#define F_BTN 0x100
#define F_KEY 0x8000

static unsigned int scr[3 * 64];
static unsigned char ns;
static unsigned int tplay, tlen;        /* the script's start (ser_frames), its last frame */
static unsigned char step, sess;
static unsigned int t0, tmax, tlast, tstep_t;    /* (tmax: the main loop's longest gap) */
static char tl[100];
#define wrow ((unsigned char *)line)

static void say(const char *s)
{
    strncpy(tl, s, sizeof tl - 1);
    LogText(tl);
}

static void S(unsigned int f, unsigned int x, unsigned int y, unsigned int fl)
{
    scr[ns++] = f;
    scr[ns++] = x;
    scr[ns++] = (y & 255) | (y > 255 ? 0x4000 : 0) | fl;
    if (f > tlen)
        tlen = f;
}

/* a click (down, up 4 frames later) */
static void C(unsigned int f, unsigned int x, unsigned int y)
{
    S(f, x, y, 0);
    S(f + 3, x, y, F_BTN);
    S(f + 7, x, y, 0);
}

/* a double click */
static void D(unsigned int f, unsigned int x, unsigned int y)
{
    C(f, x, y);
    C(f + 9, x, y);
}

/* menu m of the bar, its item n */
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
        S(f, *s++, 0, F_KEY);
        f += 3;
    }
    return f;
}

static void go(void)
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
    return ser_frames - tplay > tlen + 40;    /* (a menu item's flash first) */
}

static unsigned char idle(void)
{
    return played() && fop == OP_NONE && !t_box;
}

/* the script waits (in the interrupt: no main loop while a box is open)
   until a box is open, then counts its frames from 0 again */

static void W(void)
{
    S(tlen + 10, (unsigned int)&t_box, 0, 0x1000);
    nbox = t_nbox;
}

/* idle, and the box the script waited for has been opened (and closed) */
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

/* the screen as the gate reads it */
static void snap(const char *name)
{
    unsigned char h, keep = dispBufferOn, x, y, i;
    unsigned int r;
    strcpy(tl, VR_ROOTPATH);
    strcat(tl, name);
    h = FOpen(tl, 'w');
    if (h < 2 || h > 4) {
        say("FTP SNAP FAILED");
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
    *(volatile unsigned char *)0x9F25 &= 0xFE;      /* ADDRSEL 0 */
    *(volatile unsigned char *)0x9F20 = 0x00;       /* $1FA00, step 1 */
    *(volatile unsigned char *)0x9F21 = 0xFA;
    *(volatile unsigned char *)0x9F22 = 0x11;
    for (i = 0; i < 32; ++i)
        wrow[i] = *(volatile unsigned char *)0x9F23;
    asm("cli");
    FWrite(h, wrow, 32);
    FClose(h);
    dispBufferOn = keep;
    tlast = 0;                          /* (the test's own time) */
    strcpy(tl, "FTP SNAP ");
    strcat(tl, name);
    LogText(tl);
}

/* a pane's entries on the console: "FTP R name|size|flags|date" */
void ftp_test_list(unsigned char p)
{
    unsigned char i, n = panes[p].n;
    char *q;
    strcpy(tl, p ? "FTP LIST R " : "FTP LIST L ");
    strncat(tl, p ? rpath : (char *)curDirName, 60);
    LogText(tl);
    for (i = 0; i < n; ++i) {
        ent_get(p, i);
        strcpy(tl, p ? "FTP R " : "FTP L ");
        strcat(tl, E.name);
        q = tl + strlen(tl);
        *q++ = '|';
        q = unum(q, E.size);
        *q++ = '|';
        q = unum(q, E.flags);
        *q++ = '|';
        q = unum(q, E.y ? 1900u + E.y : 0);
        *q++ = '-';
        q = unum(q, E.mo);
        *q++ = '-';
        q = unum(q, E.d);
        *q++ = ' ';
        q = unum(q, E.h == 0xFF ? 99 : E.h);
        *q++ = ':';
        unum(q, E.mi);
        LogText(tl);
    }
    say("FTP LIST END");
}

/* the row of name in pane p (its order), $FF none */
static unsigned char row_of(unsigned char p, const char *name)
{
    unsigned char i;
    for (i = 0; i < panes[p].n; ++i) {
        ent_get(p, i);
        if (!strcmp(E.name, name))
            return i;
    }
    return 0xFF;
}

static unsigned int rowy(unsigned char p, unsigned char i)
{
    return 64 + (i - panes[p].top) * 16 + 8;
}

/* a click on name in pane p (f), 0 if it is not there */
static unsigned char pick(unsigned int f, unsigned char p, const char *name)
{
    unsigned char i = row_of(p, name);
    if (i == 0xFF) {
        strcpy(tl, "FTP TEST NO ");
        strcat(tl, name);
        LogText(tl);
        return 0;
    }
    C(f, p ? 400 : 80, rowy(p, i));
    return 1;
}

static void fail(const char *why)
{
    strcpy(tl, "FTP TEST FAILED ");
    strcat(tl, why);
    LogText(tl);
    term_dump();
}

static void the_end(void)
{
    logn("FTP LOST ", ser_lost);
    logn("FTP OE ", ser_oe);
    logn("FTP PULLS ", net_stats.pulls);
    logn("FTP PACKETS ", net_stats.packets);
    logn("FTP XONRETRY ", net_stats.xon_retries);
    logn("FTP BADCRC ", net_stats.badcrc);
    say("FTP END");
    term_dump();
}


/* "main YY MM DD hh mm" (the host's date): the X16's clock set, so the
   listings' dates without a year are this year's */
static unsigned char num2(const char *p)
{
    return (p[0] - '0') * 10 + p[1] - '0';
}

static void clock(void)
{
    const char *p = strchr(tl, ' ');
    if (!p || strlen(p) < 15)
        return;
    SetClock(100 + num2(p + 1), num2(p + 4), num2(p + 7), num2(p + 10), num2(p + 13), 0, 1);
}    /* (the main loop's longest gap) */

/* (V211) the timing session: a transfer's frames, from its start (fop)
   and from its data's first byte, and vrnet's counters over it */
static unsigned int tt_op, tt_data, tt_end, tt_dend, tt_passes;
static struct net_stats tt_ns;
extern unsigned int t_ui, t_file;
static unsigned char tt_was;

static void tt_watch(void)
{
    if (fop == OP_RETR || fop == OP_STOR) {
        if (!tt_op) {
            tt_op = ser_frames;
            tt_ns = net_stats;
            t_ui = t_file = 0;
        }
        if (!tt_data && xf_pos)
            tt_data = ser_frames;
        if (xfer_data)
            tt_dend = ser_frames, ++tt_passes;
        tt_was = 1;
    } else if (tt_was && !tt_end)
        tt_end = ser_frames;
}

static void __fastcall__ tt_one(const char *a, const char *k, unsigned int v)
{
    strcpy(tl, a);
    strcat(tl, k);
    strcat(tl, " ");
    logn(tl, v);
}

static void __fastcall__ tt_report(const char *k)
{
    tt_one("FTP TIME ", k, tt_end - tt_op);
    tt_one("FTP TDATA ", k, tt_dend - tt_data);
    logn(k[0] == 'D' ? "FTP TBYTES DOWN " : "FTP TBYTES UP ", xf_pos);
    tt_one("FTP TPULLS ", k, net_stats.pulls - tt_ns.pulls);
    tt_one("FTP TPACKETS ", k, net_stats.packets - tt_ns.packets);
    tt_one("FTP TEMPTIES ", k, net_stats.empties - tt_ns.empties);
    tt_one("FTP TSENDS ", k, net_stats.sends - tt_ns.sends);
    tt_one("FTP TRETRIES ", k, net_stats.xon_retries - tt_ns.xon_retries);
    tt_one("FTP TPASSES ", k, tt_passes);
    tt_one("FTP TUI ", k, t_ui);
    tt_one("FTP TFILE ", k, t_file);
    tt_op = tt_data = tt_end = tt_dend = tt_passes = 0;
    tt_was = 0;
}

void ftp_test_tick(void)
{
    unsigned char h;
    if (sess == 't')
        tt_watch();
    if (t_boxed)
        t_boxed = tlast = 0;            /* (no main loop while a box is open) */
    if (tlast && ser_frames - tlast > tmax)
        tmax = ser_frames - tlast;
    tlast = ser_frames;
    if (!step) {
        strcpy(tl, VR_ROOTPATH "FTP.TST");
        h = FOpen(tl, 'r');
        if (h < 2 || h > 4) {
            step = 0xFF;
            return;
        }
        tl[FRead(h, tl, 40)] = 0;
        FClose(h);
        sess = tl[0];
        clock();
        step = 1;
        t0 = tstep_t = ser_frames;
        say("FTP TEST START");
        return;
    }
    if (step == 0xFF)
        return;
    if (ser_frames - tstep_t > (sess == 't' ? 60u * 600 : 60u * 90)) {
        logn("FTP TEST STUCK AT STEP ", step);
        snap("FAIL.RAW");
        fail("TIMEOUT");
        return;
    }
    switch (step) {
    case 1:                             /* the modem ready: Connection > Sites... */
        if (net_state() != NET_READY)
            return;
        logn("FTP TEST NET READY ", ser_frames - t0);
        if (sess == 'p') {
            snap("PROBE.RAW");
            the_end();
            return;
        }
        M(10, 1, 0);
        go();
        break;
    case 2:                             /* the page: the first server, Connect */
        if (!played())
            return;
        if (!page) {
            if (ser_frames - tplay < tlen + 200)
                return;
            fail("NO SITES PAGE");
        }
        snap("SITES.RAW");
        C(10, 300, 80 + 8);
        C(30, 2 * 8 + 30, 344 + 8);
        go();
        break;
    case 3:                             /* connected: into dosdir */
        if (!idle())
            return;
        if (!logged)
            fail("NOT CONNECTED");
        if (sess == 't') {              /* (V211) the timing session */
            if (!pick(10, REMOTE, "t300.bin"))
                fail("NO t300.bin");
            M(30, 2, 0);
            go();
            step = 30;
            tstep_t = ser_frames;
            return;
        }
        snap("CONN.RAW");
        say("FTP TEST CONNECTED");
        h = row_of(REMOTE, "dosdir");
        if (h == 0xFF)
            fail("NO dosdir");
        D(10, 400, rowy(REMOTE, h));
        go();
        break;
    case 4:                             /* the DOS listing: ".." back */
        if (!idle())
            return;
        say("FTP TEST IN DOSDIR");
        D(10, 400, rowy(REMOTE, 0));
        go();
        break;
    case 5:                             /* big.bin, File > Download */
        if (!idle())
            return;
        say("FTP TEST BACK");
        if (!pick(10, REMOTE, "big.bin"))
            fail("NO big.bin");
        M(30, 2, 0);
        go();
        break;
    case 6:                             /* 20,000 bytes: the screen, Alt+Tab */
        if (fop == OP_NONE && ser_frames - tplay > tlen + 300)
            fail("NO DOWNLOAD");
        if (!xfer_data || xf_pos < 20000)
            return;
        snap("XFER.RAW");
        logn("FTP ALT+TAB AT ", xf_pos);
        switchReq = SWITCH_ASIDE;       /* (Alt+Tab's request: V83) */
        break;
    case 7:                             /* back (asideVector: the file closed, opened again) */
        if (!t_aside || !xf_h)
            return;
        logn("FTP BACK AT ", xf_pos);
        break;
    case 8:                             /* the download's end: upload.bin from the card */
        if (!idle())
            return;
        logn("FTP TEST DOWNLOADED ", xf_pos);
        if (!pick(10, LOCAL, "upload.bin"))
            fail("NO upload.bin");
        M(30, 2, 1);
        go();
        break;
    case 9:                             /* uploaded (and listed again): a new folder on the server */
        if (!idle())
            return;
        logn("FTP TEST UPLOADED ", xf_pos);
        C(10, 400, 52);                 /* (the remote pane's heads: it is active) */
        M(20, 2, 2);
        W();
        typed(typed(20, "newdir"), "\r");
        go();
        break;
    case 10:                            /* made: upload.bin renamed */
        if (!idle_box())
            return;
        say("FTP TEST MADE");
        if (!pick(10, REMOTE, "upload.bin"))
            fail("NO upload.bin THERE");
        M(30, 2, 4);
        W();
        for (h = 0; h < 10; ++h)        /* ("upload.bin" erased) */
            S(20 + 3 * h, 8, 0, F_KEY);
        typed(typed(60, "renamed.bin"), "\r");
        go();
        break;
    case 11:                            /* renamed: deleted */
        if (!idle_box())
            return;
        say("FTP TEST RENAMED");
        if (!pick(10, REMOTE, "renamed.bin"))
            fail("NO renamed.bin");
        M(30, 2, 3);
        W();
        C(20, 256, 272);                /* YES */
        go();
        break;
    case 12:                            /* deleted: newdir deleted */
        if (!idle_box())
            return;
        say("FTP TEST DELETED FILE");
        if (!pick(10, REMOTE, "newdir"))
            fail("NO newdir");
        M(30, 2, 3);
        W();
        C(20, 256, 272);
        go();
        break;
    case 13:                            /* a file the server refuses: the box, OK */
        if (!idle_box())
            return;
        say("FTP TEST DELETED FOLDER");
        if (!pick(10, REMOTE, "ghost.bin"))
            fail("NO ghost.bin");
        M(30, 2, 0);
        W();
        C(30, 256, 272);                /* OK */
        go();
        break;
    case 14:                            /* Disconnect */
        if (!idle_box())
            return;
        say("FTP TEST BOX MISSING");
        logn("FTP TEST GHOST LEFT ", row_of(LOCAL, "ghost.bin") != 0xFF);
        M(10, 1, 2);
        go();
        break;
    case 15:                            /* the wrong password: the box, OK */
        if (!idle() || logged)
            return;
        logn("FTP TEST DISCONNECTED ", logged);
        M(10, 1, 0);
        C(80, 300, 80 + 16 + 8);
        C(100, 2 * 8 + 30, 344 + 8);
        W();
        C(30, 256, 272);
        go();
        break;
    case 16:                            /* the MLSD server */
        if (!idle_box())
            return;
        say("FTP TEST BOX PASSWORD");
        logn("FTP TEST LOGGED ", logged);
        M(10, 1, 0);
        C(80, 300, 80 + 32 + 8);
        C(100, 2 * 8 + 30, 344 + 8);
        go();
        break;
    case 30:                            /* (timing) downloaded: t300up.bin from the card */
        if (!idle() || !tt_end)
            return;
        tt_report("DOWN");
        if (!pick(10, LOCAL, "t300up.bin"))
            fail("NO t300up.bin");
        M(30, 2, 1);
        go();
        break;
    case 31:                            /* (timing) uploaded */
        if (!idle() || !tt_end)
            return;
        tt_report("UP");
        logn("FTP MAXGAP ", tmax);
        the_end();
        return;
    case 17:
        if (!idle() || !logged)
            return;
        logn("FTP TEST MLSD ", use_mlsd);
        logn("FTP MAXGAP ", tmax);
        snap("END.RAW");
        the_end();
        return;
    }
    ++step;
    tstep_t = ser_frames;
}
