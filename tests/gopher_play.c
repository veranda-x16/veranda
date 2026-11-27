/* gate gopher (DECISIONS V109): Veranda Gopher's test build (apps/gopher,
   make test: GOPHER_TEST; this file in overlay 3, its data in main RAM,
   where the pointer's player reads it from the interrupt;
   tests/term_play.s plays the mouse and the keys through mouseSource, as
   tests/ftp_play.c does for Veranda FTP).

   GOPHER.TST: the session, then the server's port.
     main     (tools/gate_gopher.sh): the bookmarks page (the defaults);
              the address typed; the root menu; a submenu, the toolbar's
              Back, Go > Forward, an item with no host (back to the root);
              a text; a long text (cut), End; a search (its box, a query);
              a web link (its box); an error line (its box); a refused
              connection (its box); a menu that stalls, Esc; the binary,
              its box, Alt+Tab at 20,000 bytes; the picture selected with
              Down and File > Download; Bookmarks > Add this page; Go >
              Home; a bookmark selected with Down, Bookmarks > Remove...;
              the end
     reread   GOPHER.MARKS read back: the bookmarks page, its gate
              bookmark followed (the root), the end
     nomodem  (no modem on the port) the address typed: the box, the end
   Screens (snap: the foreground's 480 rows of 80 bytes, the cards'
   paper colours, 60 rows of 80, the palette's 16 entries): BOOK.RAW,
   MENU.RAW, TEXT.RAW, LONG.RAW, SEARCH.RAW, XFER.RAW, MARKS.RAW,
   END.RAW; the log lines "GO ..." on the console.

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <string.h>
#include <vrnet.h>
#include <vrser.h>
#include <theme.h>
#include "../apps/gopher/gopher.h"
#pragma code-name ("OVERLAY3")
#pragma rodata-name ("OVL3RO")
/* (its texts in overlay 3: say() copies them below $A000 for the kernel) */

void __fastcall__ term_play(const unsigned int *script);
void term_dump(void);
extern unsigned int barx[4], barl[4];
extern unsigned int v_top, v_sel;
extern unsigned char hpos, hn;
static unsigned char nbox;
void t_bench(void);
void __fastcall__ t_ui(void (*f)(void));

#define F_BTN 0x100
#define F_KEY 0x8000
#define NONE 0xFFFF

static unsigned int scr[3 * 96];
static unsigned char ns;
static unsigned int tplay, tlen;        /* the script's start (ser_frames), its last frame */
static unsigned char step, sess;
static unsigned int t0, tmax, tlast, tstep_t;    /* (tmax: the main loop's longest gap) */
static unsigned int tlong;              /* (V211) the long text's request (GO TIME LONG: frames to its end) */
static char tl[100];
static char port[8];
static unsigned char mshot = 0;         /* (V149, main RAM's DATA) the Go menu's picture: 1 open, 2 taken */
#define wrow ((unsigned char *)line)

static void say(const char *s)
{
    strncpy(tl, s, sizeof tl - 1);
    LogText(tl);
}

/* (V110) a script that ends at once: the player is given it before a new
   script is written over scr (the last one's player, at its end, would
   otherwise play the new entries in an interrupt as they are written:
   seen once as 11 keys lost) */
static unsigned int stopper[3] = { 0xFFFF, 0xFFFF, 0 };

static void S(unsigned int f, unsigned int x, unsigned int y, unsigned int fl)
{
    if (!ns)
        term_play(stopper);
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

static unsigned int keys(unsigned int f, unsigned char k, unsigned char n)
{
    while (n--) {
        S(f, k, 0, F_KEY);
        f += 4;
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
    return ser_frames - tplay > tlen + 40;    /* (a menu item's flash first) */
}

static unsigned char idle(void)
{
    return played() && !gbusy && !t_box;
}

/* the script waits (in the interrupt: no main loop while a box is open)
   until a box is open, then counts its frames from 0 again */
static void W(void)
{
    S(tlen + 10, (unsigned int)&t_box, 0, 0x1000);
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
        say("GO SNAP FAILED");
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
    strcpy(tl, "GO SNAP ");
    strcat(tl, name);
    LogText(tl);
}

static void fail(const char *why)
{
    strcpy(tl, "GO TEST FAILED ");
    strcat(tl, why);
    LogText(tl);
    term_dump();
}

/* the line whose item text is t; NONE */
static unsigned int find(const char *t)
{
    unsigned int i;
    unsigned char n = strlen(t);
    for (i = 0; i < doc_lines; ++i) {
        doc_line(i);
        if (!memcmp(ln + 1, t, n) && (ln[n + 1] == '\t' || !ln[n + 1]))
            return i;
    }
    return NONE;
}

/* a click on the item t (f) */
static void click(unsigned int f, const char *t)
{
    unsigned int i = find(t);
    if (i == NONE || i < v_top || i >= v_top + rows) {
        strcpy(tl, "GO TEST NO ");
        strcat(tl, t);
        LogText(tl);
        fail("NO ITEM");
        return;
    }
    C(f, 200, BODYY + (i - v_top) * rowh + rowh / 2);
}

/* Down until the item t is selected (from f); the frame after */
static unsigned int down_to(unsigned int f, const char *t)
{
    unsigned int i = find(t), j;
    unsigned char n = 0;
    if (i == NONE) {
        fail("NO ITEM TO SELECT");
        return f;
    }
    for (j = v_sel == NONE ? 0 : v_sel + 1; j <= i; ++j)
        if (selectable(j))
            ++n;
    return keys(f, 0x11, n);
}

#define BACKBTN() C(10, 16, 40)

static void the_end(void)
{
    logn("GO MAXGAP ", tmax);
    logn("GO LOST ", ser_lost);
    logn("GO OE ", ser_oe);
    logn("GO PACKETS ", net_stats.packets);
    logn("GO XONRETRY ", net_stats.xon_retries);
    logn("GO BADCRC ", net_stats.badcrc);
    say("GO END");
    term_dump();
}

/* the address of the gate's root, typed in the address line (f) */
static void type_root(unsigned int f)
{
    C(f, 300, 40);
    strcpy(tl, "gopher://127.0.0.1:");
    strcat(tl, port);
    strcat(tl, "/1\r");
    typed(f + 20, tl);
}

/* ser_frames read whole (the interrupt counts it a byte at a time) */
static unsigned int now(void)
{
    unsigned int t;
    asm("sei");
    t = ser_frames;
    asm("cli");
    return t;
}

/* (called by ui.c) the page as shown, on the console: "GO PAGE addr", "GO L text" (the
   first 80 lines), "GO PAGE END lines full" */
void page_log(void)
{
    unsigned int i;
    unsigned char k;
    addr_of(&cur);
    strcpy(line, "GO PAGE ");
    strcat(line, abuf);
    gt_log(line);
    for (i = 0; i < (doc_lines + (doc_full && doc_done ? 2 : 0)) && i < 80; ++i) {
        k = render(i);
        strcpy(line, "GO L ");
        if (doc_menu) {
            line[5] = k ? k : 'i';
            line[6] = 0;
        }
        for (k = strlen(row); k && row[k - 1] == ' '; --k)
            ;
        row[k] = 0;
        strcat(line, row);
        gt_log(line);
    }
    strcpy(line, "GO PAGE END ");
    unum(line + strlen(line), doc_lines);
    strcat(line, " ");
    unum(line + strlen(line), doc_full);
    strcat(line, " ");
    unum(line + strlen(line), doc_len);
    gt_log(line);
}

/* (V110) ui.c's timings (overlay 1, through main RAM) */
static void bench(void)
{
    t_ui(t_bench);
    tlast = 0;                          /* (the test's own time) */
}

void gt_tick(void)
{
    unsigned char h;
    unsigned int f = now();
    if (t_boxed)
        t_boxed = tlast = 0;            /* (no main loop while a box is open) */
    if (tlast && f - tlast > 20) {
        strcpy(tl, "GO GAP AT STEP ");
        unum(tl + strlen(tl), step);
        strcat(tl, ": ");
        unum(tl + strlen(tl), f - tlast);
        LogText(tl);
    }
    if (tlast && f - tlast > tmax)
        tmax = f - tlast;
    tlast = f;
    if (!step) {
        strcpy(tl, VR_ROOTPATH "GOPHER.TST");
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
        say("GO TEST START");
        return;
    }
    if (step == 0xFF)
        return;
    if (ser_frames - tstep_t > 60u * 90) {
        logn("GO TEST STUCK AT STEP ", step);
        snap("FAIL.RAW");
        fail("TIMEOUT");
        return;
    }
    if (sess == 'n') {                  /* nomodem */
        switch (step) {
        case 1:
            if (gbusy || !doc_done)
                return;
            type_root(10);
            W();
            C(30, 256, 272);
            go_();
            break;
        case 2:
            if (!idle_box())
                return;
            say("GO TEST NOMODEM BOX");
            the_end();
            return;
        }
        ++step;
        tstep_t = ser_frames;
        return;
    }
    if (sess == 'r') {                  /* reread: GOPHER.MARKS read back */
        switch (step) {
        case 1:
            if (net_state() != NET_READY || gbusy || !doc_done)
                return;
            snap("MARKS2.RAW");
            click(10, "Gate root");
            go_();
            break;
        case 2:
            if (!idle() || !cur.host[0])
                return;
            say("GO TEST MARK FOLLOWED");
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
        logn("GO TEST NET READY ", ser_frames - t0);
        snap("BOOK.RAW");
        type_root(10);
        go_();
        break;
    case 2:                             /* the root: a submenu */
        if (!idle() || !cur.host[0])
            return;
        snap("MENU.RAW");
        say("GO TEST ROOT");
        click(10, "A submenu");
        go_();
        break;
    case 3:                             /* in it: Back (the toolbar) */
        if (!idle())
            return;
        say("GO TEST SUB");
        BACKBTN();
        go_();
        break;
    case 4:                             /* Go > Forward (V149: the Go menu open first, MENUS.RAW) */
        if (!idle())
            return;
        if (!mshot) {
            logn("GO TEST BACK SEL ", v_sel);
            S(10, barx[2], 7, 0);
            S(11, barx[2], 7, F_BTN);
            S(12, barl[2] + 12, 24, 0);
            go_();
            mshot = 1;
            return;
        }
        if (mshot == 1) {
            snap("MENUS.RAW");
            mshot = 2;
        }
        C(10, barl[2] + 12, 24 + 16 * 1);
        go_();
        break;
    case 5:                             /* an item without a host: the root again */
        if (!idle())
            return;
        say("GO TEST FORWARD");
        click(10, "Back to the top");
        go_();
        break;
    case 6:                             /* a text */
        if (!idle())
            return;
        logn("GO TEST HPOS ", hpos);
        logn("GO TEST HN ", hn);
        click(10, "A text file");
        go_();
        break;
    case 7:
        if (!idle())
            return;
        snap("TEXT.RAW");
        BACKBTN();
        go_();
        break;
    case 8:                             /* a long text */
        if (!idle())
            return;
        click(10, "A long text");
        go_();
        tlong = ser_frames;
        break;
    case 9:                             /* cut: End */
        if (!idle())
            return;
        logn("GO TIME LONG ", ser_frames - tlong);
        snap("LONG.RAW");
        bench();
        logn("GO TEST LONG FULL ", doc_full);
        keys(10, 0x04, 1);
        go_();
        break;
    case 10:
        if (!idle())
            return;
        logn("GO TEST LONG TOP ", v_top);
        snap("LONGEND.RAW");
        BACKBTN();
        go_();
        break;
    case 11:                            /* a search: the box, the query */
        if (!idle())
            return;
        click(10, "Search the gate");
        W();
        typed(20, "veranda\r");
        go_();
        break;
    case 12:
        if (!idle_box())
            return;
        snap("SEARCH.RAW");
        BACKBTN();
        go_();
        break;
    case 13:                            /* a web link: its box */
        if (!idle())
            return;
        click(10, "The web");
        W();
        C(30, 256, 272);
        go_();
        break;
    case 14:                            /* an error line: its box */
        if (!idle_box())
            return;
        click(10, "An error line: this item is gone");
        W();
        C(30, 256, 272);
        go_();
        break;
    case 15:                            /* a refused connection: its box */
        if (!idle_box())
            return;
        click(10, "A closed port");
        W();
        C(30, 256, 272);
        go_();
        break;
    case 16:                            /* a menu that stalls */
        if (!idle_box())
            return;
        say("GO TEST REFUSED");
        click(10, "A menu that stalls");
        go_();
        break;
    case 17:                            /* its first lines: Esc */
        if (!played() || !gbusy || !gfirst || doc_lines < 3)
            return;
        say("GO TEST STALLED");
        keys(10, 0x1B, 1);
        go_();
        break;
    case 18:
        if (!idle())
            return;
        say("GO TEST STOPPED");
        BACKBTN();
        go_();
        break;
    case 19:                            /* the binary: its box, Yes */
        if (!idle())
            return;
        click(10, "A binary file");
        W();
        C(30, 256, 272);
        go_();
        break;
    case 20:                            /* 20,000 bytes: the screen, Alt+Tab */
        if (!gbusy && played() && ser_frames - tplay > tlen + 600)
            fail("NO DOWNLOAD");
        if (!gbusy || !gdl || grx < 20000)
            return;
        snap("XFER.RAW");
        logn("GO ALT+TAB AT ", grx);
        switchReq = SWITCH_ASIDE;       /* (Alt+Tab's request: V83) */
        break;
    case 21:                            /* back (asideVector: the file closed, opened again) */
        if (!t_aside || !xf_h)
            return;
        logn("GO BACK AT ", grx);
        break;
    case 22:                            /* the end of it: the picture, Down, File > Download */
        if (!idle())
            return;
        logn("GO TEST DOWNLOADED ", grx);
        M(down_to(10, "A picture") + 10, 1, 1);
        go_();
        break;
    case 23:                            /* Bookmarks > Add this page */
        if (!idle())
            return;
        logn("GO TEST PICTURE ", grx);
        M(10, 3, 1);
        go_();
        break;
    case 24:                            /* Go > Home */
        if (!idle())
            return;
        M(10, 2, 3);
        go_();
        break;
    case 25:                            /* a bookmark selected, Bookmarks > Remove... */
        if (!idle() || cur.host[0])
            return;
        snap("MARKS.RAW");
        M(down_to(10, "Bitreich") + 10, 3, 2);
        W();
        C(30, 256, 272);
        go_();
        break;
    case 26:
        if (!idle_box() || !doc_done)
            return;
        say("GO TEST REMOVED");
        snap("END.RAW");
        C(10, 300, 40);                 /* (V110) a long menu: its look, its timings */
        strcpy(tl, "gopher://127.0.0.1:");
        strcat(tl, port);
        strcat(tl, "/1/many\r");
        typed(30, tl);
        go_();
        break;
    case 27:
        if (!idle() || !doc_done)
            return;
        snap("MANY.RAW");
        bench();
        theme.dark = LOOK_DARK;         /* (dark mode: Look 2's palette swapped, nothing drawn again) */
        theme_palette();
        snap("DARK.RAW");
        the_end();
        return;
    }
    ++step;
    tstep_t = ser_frames;
}
