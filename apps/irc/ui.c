/* Veranda Chat: the interface (overlay 1, appBank: mapped for good;
   DECISIONS V111).

   The window (Veranda Look 3 "Sunroom", sdk vrwin.h; V149): the menu
   bar (the kernel's), the title band (card rows 2-3: the server), the
   toolbar (4-5: the windows as tabs, the one shown in the theme's
   highlight, '*' after one with new lines, '!' after one that named us
   or a new private message), the topic line (6-7), the text (rows of 12
   pixels: the X16 ROM's 8 x 8 ISO font with 4 pixels between lines,
   from y 64 to 447: 32 lines; cards 1-76, or 1-58 beside the nick list)
   and its scroll bar (Sunroom's, vr_scroll in overlay 5: cards 78-79,
   or 60-61), the nick list at its right (cards 63-77, a channel's, with
   its own scroll bar at cards 78-79; Window > Nick list hides it), the
   input line (card rows 56-57: the nick, then the text, in a frame),
   the status bar (58-59: what happened at its left; the connection,
   the people in the channel at its right).

   A line is kept whole (store.c) and wrapped when it is drawn, at the
   last space (continuation rows indented), so the nick list can come and
   go. New lines at the bottom: the text moved up (ScrollRect) and only
   they drawn; scrolled back (PgUp, the wheel), the view stays where it
   is ("Scrolled back" in the status bar; End or Esc: the newest).

   Keys: typing goes to the input line (Left, Right, Home, End, Backspace,
   Delete; Up and Down its history; Tab completes a nick of the channel,
   again for the next one; Return sends; Esc clears it); PgUp and PgDn
   scroll; F1-F7 a window, Ctrl+N and Ctrl+P the next and previous,
   Ctrl+W closes it; Ctrl+V pastes the clipboard's first line; Ctrl+Q
   quits. A click on a tab shows it; on a nick puts it in the input line;
   on a scroll bar's arrow scrolls a row, on its track a page.

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <vr.h>
#include <string.h>
#include <theme.h>
#include <vrnet.h>
#include <vrser.h>
#include <vrwin.h>
#include "chat.h"
#pragma code-name ("OVERLAY1")

#define TOOLY   32
#define TABW    11              /* a tab's cards */
#define TOPY    48
#define BODYY   64
#define RH      12              /* a text row's pixels */
#define ROWS    32
#define BODYB   (BODYY + ROWS * RH - 1)
#define PANEX   63              /* the nick list's first card */
#define PANEW   15
#define SBY     (BODYY >> 3)    /* the scroll bars' first card row, their length */
#define SBL     (ROWS * RH / 8)
#define SBN     78              /* the nick list's bar (and the text's without it) */
#define SBT     60              /* the text's beside the nick list */
#define INY     448
#define NR      24              /* rows of one line at most */

/* (overlay 1's own bank: what only this file reads) */
#pragma bss-name (push, "OVL1BSS")
static char dl[LNMAX + 8];              /* a line as shown */
static unsigned int rs[NR];             /* its rows' starts */
static unsigned char rl[NR];            /* their lengths */
static unsigned int sbstart[8];
#pragma bss-name (pop)

char msg[96];
char right[64];
unsigned char hl;
static unsigned char nrows;
static unsigned char pane = 1, stamps = 1;
static unsigned int drawn_seq, np_top;
static unsigned char drawn_w = 0xFF, last_state = 0xFF, pg_closed;
static unsigned int off;                /* the input's first cell shown */
#define cur in_cur
#define inlen in_len
static unsigned char hback;             /* the history: lines back (0: the line typed) */
static unsigned char last_net;
static unsigned int lshown, lfirst;     /* (V149) the text's lines shown, the first of them */

#define PANE()  (pane && W[cw].kind == W_CHAN)
#define WIDTH() (PANE() ? SBT - 2 : SBN - 2)
#define IND()   (stamps ? 8 : 2)

/*---------------------------------------------------------------- the status bar */

/* (V149: the status bar's right, the tabs, the topic: bar.c, overlay 5) */
static void where(void) { ov5(ui_where); }
static void tabs(void) { ov5(ui_tabs); }
static void topic_line(void) { ov5(ui_topic); }

static void status2(void)
{
    win_status(msg, right);
}

void __fastcall__ ui_status(const char *s)
{
    strncpy(msg, s, sizeof msg - 1);
    status2();
#ifdef CHAT_TEST
    strcpy(line, "IR STATUS ");
    strcat(line, msg);
    gt_log(line);
#endif
}

/*---------------------------------------------------------------- the tabs, the topic */

static void title(void)
{
    strcpy(line, "Veranda Chat");
    if (S.name[0] && cstate != C_OFF) {
        strcat(line, ": ");
        strcat(line, S.name);
    }
    win_title(line);
}

/*---------------------------------------------------------------- the text */

/* ln (sb_prev's) as shown into dl, wrapped to the width: rs, rl, nrows */
static void wrap(void)
{
    unsigned int n, s, b, i;
    unsigned char w = WIDTH(), ind = IND(), k;
    char *p = dl;
    if (stamps) {
        p[0] = '0' + ln_hh / 10;
        p[1] = '0' + ln_hh % 10;
        p[2] = ':';
        p[3] = '0' + ln_mm / 10;
        p[4] = '0' + ln_mm % 10;
        p[5] = ' ';
        p += 6;
    }
    strcpy(p, ln);
    n = strlen(dl);
    s = 0;
    nrows = 0;
    k = w;
    while (nrows < NR) {
        rs[nrows] = s;
        if (n - s <= k) {
            rl[nrows++] = n - s;
            break;
        }
        b = 0;
        for (i = s + k; i > s; --i)
            if (dl[i] == ' ') {
                b = i;
                break;
            }
        if (b > s + k / 3) {
            rl[nrows++] = b - s;
            s = b + 1;
        } else {
            rl[nrows++] = k;
            s += k;
        }
        k = w - ind;
    }
}

/* row k of the line (wrap's) at screen row r */
/* (the rows are drawn opaque, the whole width: the 4 pixels between
   them stay empty, so nothing is cleared but when the width changes) */
static unsigned char bw = 0xFF;         /* the width the text was drawn at */

static void __fastcall__ draw_row(unsigned char k, unsigned char r)
{
    unsigned char x = 1, n = rl[k], fl = 0;
    unsigned int y = BODYY + r * RH + 2;
    char *s = dl + rs[k], keep = s[n];
    if (ln_attr == A_MENTION)
        fl = 1;                         /* (a mention: reversed, a bar across) */
    else if (ln_attr == A_ERR)
        fl = 2;
    s[n] = 0;
    if (k) {
        x += IND();
        put(1, y, "", IND(), fl);
    }
    put(x, y, s, bw + 1 - x, fl);
    s[n] = keep;
}

/*---------------------------------------------------------------- the scroll bars (V149) */

/* sbar set and drawn by overlay 5 (b: 0 the text's, 1 the nick list's;
   +SB_FORCE: drawn even if its thumb has not moved) */
#define SB_FORCE 0x80
static void __fastcall__ bar_set(unsigned char cx, unsigned int first, unsigned int shown, unsigned int total)
{
    sbar.cx = cx;
    sbar.cy = SBY;
    sbar.len = SBL;
    sbar.vert = 1;
    sbar.first = first;
    sbar.shown = shown;
    sbar.total = total;
}

static void __fastcall__ tbar(unsigned char force)
{
    bar_set(PANE() ? SBT : SBN, lfirst, lshown, W[cw].lines);
    sb_r = force;
    ov5(sb_draw);
}

/* (V178) the nick list's rows: the nicks kept, and "and N more" when the
   channel has more people than store.c keeps */
static unsigned int nrows_all(void)
{
    unsigned int n = W[cw].nicks;
    return W[cw].people > n ? n + 1 : n;
}

static void __fastcall__ nbar(unsigned char force)
{
    bar_set(SBN, np_top, ROWS, nrows_all());
    sb_r = force | 1;
    ov5(sb_draw);
}

static void __fastcall__ body_clear(void)
{
    unsigned char w = WIDTH();
    if (w == bw)
        return;
    bw = w;
    dispBufferOn = ST_WR_FORE;
    SetPattern(0);
    WRectangle(0, BODYY, 639, BODYB);
    theme_rect(0, 80, SBY, SBL, 0);     /* (a bar's track where text goes now) */
    if (PANE())
        dirty |= D_NICKS;
}

/* the whole text; the rows left empty at the top (lines ran out) */
static unsigned char body(void)
{
    unsigned int end = W[cw].used, skip = W[cw].scroll, lskip = 0;
    signed char r = ROWS - 1;
    signed char k;
    unsigned char on;
    body_clear();
    lshown = 0;
    while (end && r >= 0) {
        end = sb_prev(cw, end);
        wrap();
        on = 0;
        for (k = nrows - 1; k >= 0 && r >= 0; --k) {
            if (skip) {
                --skip;
                continue;
            }
            draw_row(k, r--);
            on = 1;
        }
        if (on)
            ++lshown;
        else
            ++lskip;
    }
    lfirst = W[cw].lines - lskip - lshown;
    drawn_seq = W[cw].seq;
    drawn_w = cw;
    k = r + 1;
    for (; r >= 0; --r)
        put(1, BODYY + r * RH + 2, "", bw, 0);
    tbar(SB_FORCE);
    return k;
}

static void body_all(void)
{
    unsigned char left = body();
    unsigned int s = W[cw].scroll;
    if (left && s) {                    /* (scrolled past the oldest: back to it) */
        W[cw].scroll = s > left ? s - left : 0;
        body();
    }
}

/* lines added since drawn: the text moved up, they drawn (or all of it
   again); scrolled back: the view kept */
static void body_new(void)
{
    unsigned int d = W[cw].seq - drawn_seq, end = W[cw].used, total = 0;
    unsigned char i, n;
    signed char k;
    if (d > 6 || d > W[cw].lines) {
        if (W[cw].scroll)
            W[cw].scroll += ROWS / 2;   /* (roughly where it was) */
        body_all();
        return;
    }
    for (i = 0; i < d; ++i) {
        end = sb_prev(cw, end);
        sbstart[i] = end;
        wrap();
        total += nrows;
    }
    drawn_seq = W[cw].seq;
    if (W[cw].scroll) {
        W[cw].scroll += total;
        if (lfirst + lshown > W[cw].lines)      /* (the view kept; the oldest dropped: about) */
            lfirst = W[cw].lines > lshown ? W[cw].lines - lshown : 0;
        tbar(0);
        return;
    }
    if (total >= ROWS) {
        body_all();
        return;
    }
    body_clear();
    ScrollRect(1, bw, BODYY, BODYB, -(int)(total * RH), 0);
    n = ROWS - total;
    i = d;
    while (d--) {
        sb_prev(cw, d ? sbstart[d - 1] : W[cw].used);
        wrap();
        for (k = 0; k < nrows; ++k)
            draw_row(k, n++);
    }
    if (lshown < ROWS)                  /* (lines that scrolled away at the top: not known; about) */
        lshown += i;
    lfirst = W[cw].lines > lshown ? W[cw].lines - lshown : 0;
    tbar(0);
}

#ifdef CHAT_TEST
void t_body(void) { body_all(); }       /* (the test times them) */
void t_stat(void) { where(); status2(); }
void t_wrap(void) { sb_prev(cw, W[cw].used); wrap(); }
#endif

/* the rows of the newest lines, counted until there are lim (or all) */
static unsigned int __fastcall__ rows_upto(unsigned int lim)
{
    unsigned int end = W[cw].used, n = 0;
    while (end && n < lim) {
        end = sb_prev(cw, end);
        wrap();
        n += nrows;
    }
    return n;
}

static void __fastcall__ scroll_by(int by)
{
    long s = (long)W[cw].scroll + by;
    unsigned int old = W[cw].scroll, n;
    if (s < 0)
        s = 0;
    if (by > 0) {                       /* (not past the oldest line) */
        n = rows_upto(s + ROWS);
        if (s + ROWS > n)
            s = n > ROWS ? n - ROWS : 0;
    }
    if ((unsigned int)s == old)
        return;
    W[cw].scroll = s;
    body_all();
    if (!old != !s) {                   /* ("Scrolled back" comes or goes) */
        where();
        status2();
    }
}

/*---------------------------------------------------------------- the nick list */

static void nicks(void)
{
    unsigned char r;
    unsigned int i, n = nrows_all();
    if (!pane || W[cw].kind != W_CHAN)
        return;
    if (np_top + ROWS > n)
        np_top = n > ROWS ? n - ROWS : 0;
    dispBufferOn = ST_WR_FORE;
    SetPattern(0);
    WRectangle((PANEX - 1) * 8, BODYY, SBN * 8 - 1, BODYB);
    for (r = 0; r < ROWS; ++r) {
        i = np_top + r;
        if (i >= n)
            break;
        if (i >= W[cw].nicks) {         /* (V178) */
            strcpy(line, " and ");
            strcat(unum(line + 5, W[cw].people - W[cw].nicks), " more");
            put(PANEX, BODYY + r * RH + 2, line, PANEW, 0);
            break;
        }
        nk_get(cw, i);
        put(PANEX, BODYY + r * RH + 2, nk, PANEW, 0);
    }
    nbar(SB_FORCE);
}

#ifdef CHAT_TEST
void t_nend(void) { np_top = 60000; nicks(); }     /* (V178: the list's end, "and N more") */
#endif

/*---------------------------------------------------------------- the input line */

static void input(void)
{
    unsigned char pl, iw;
    strcpy(line, "[");
    strcat(line, me[0] ? me : S.nick);
    strcat(line, "]");
    pl = strlen(line) + 1;
    if (pl > 20)
        pl = 20;
    iw = 78 - pl - 1;
    if (cur < off)
        off = cur;
    if (cur - off >= iw)
        off = cur - iw + 1;
    put(1, INY + 4, line, pl, 0);
    put(1 + pl, INY + 4, inbuf + off, iw, 0);
    put(1 + pl + (unsigned char)(cur - off), INY + 4, cur < inlen ? inbuf + cur : " ", 1, 1);
    WFrameRectangle(0xFF, 3, INY + 1, 636, INY + 14);     /* (V149: a field's frame) */
}

static void __fastcall__ set_input(const char *s)
{
    strncpy(inbuf, s, INMAX);
    inbuf[INMAX] = 0;
    inlen = cur = strlen(inbuf);
    off = 0;
    input();
}

static void __fastcall__ insert(unsigned char c)
{
    if (inlen >= INMAX)
        return;
    memmove(inbuf + cur + 1, inbuf + cur, inlen - cur + 1);
    inbuf[cur++] = c;
    ++inlen;
}

static void __fastcall__ insert_s(const char *s)
{
    while (*s)
        insert(*s++);
}

static void send_input(void)
{
    if (!inlen)
        return;
    hist_add(inbuf);
    hback = 0;
    if (W[cw].scroll) {
        W[cw].scroll = 0;
        dirty |= D_BODY | D_STAT;
    }
    ov4(irc_input);
    set_input("");
}

/*---------------------------------------------------------------- windows */

void __fastcall__ ui_show(unsigned char w)
{
    if (w >= WMAX || W[w].kind == W_FREE)
        return;
    cw = w;
    W[w].unread = 0;
    np_top = 0;
    comp_on = 0;
    dirty |= D_ALL;
}

static void __fastcall__ next_win(signed char by)
{
    unsigned char i, w = cw;
    for (i = 0; i < WMAX; ++i) {
        w = (w + WMAX + by) % WMAX;
        if (W[w].kind != W_FREE) {
            ui_show(w);
            return;
        }
    }
}

static void close_win(void)
{
    strcpy(inbuf, "/close");
    ov4(irc_input);
    set_input("");
}

static void redraw(void)
{
    unsigned char d = dirty;
    dirty = 0;
    if (d & D_TITLE)
        title();
    if (d & D_TABS)
        tabs();
    if (d & D_TOPIC)
        topic_line();
    if (d & D_BODY)
        body_all();
    if (d & D_NICKS)
        nicks();
    if (d & D_INPUT)
        input();
    if (d & (D_STAT | D_BODY | D_NICKS)) {     /* (V178: the people count follows the list) */
        where();
        status2();
    }
}

/*---------------------------------------------------------------- the end of a connection */

/* (V179) what the link saw, in the server's window, for a report from the
   X16: "-- (link e n p b x o l)": why (CE_*), vrnet's error (256 - it),
   packets, bad checksums, XONs sent again, the UART's overruns, bytes the
   ring had no room for */
#pragma rodata-name (push, "OVL1RO")
static const char t_link[] = "-- (link";
#pragma rodata-name (pop)

static char *__fastcall__ num(char *p, unsigned int v)
{
    *p++ = ' ';
    return unum(p, v);
}

static void __fastcall__ link_note(unsigned char e)
{
    char *p = tbuf + 8;
    strcpy(tbuf, t_link);
    p = num(p, e);
    p = num(p, (unsigned char)cnet);
    p = num(p, net_stats.packets);
    p = num(p, net_stats.badcrc);
    p = num(p, net_stats.xon_retries);
    p = num(p, ser_oe);
    p = num(p, ser_lost);
    p[0] = ')';
    p[1] = 0;
    sb_add(0, A_ERR, tbuf);
}

static void ended(void)
{
    unsigned char e = cerr;
    cerr = CE_NONE;
    dirty |= D_ALL;
    redraw();
    if (e == CE_QUIT) {
        ui_status("Disconnected.");
        sb_add(0, A_INFO, "-- Disconnected.");
        return;
    }
    cbox = e;
    cbox_st = last_state;
    ov3(sv_box);
    ui_status("Disconnected: Server > Servers... connects again.");
    sb_add(0, A_ERR, "-- Disconnected.");
    link_note(e);
}

/*---------------------------------------------------------------- the servers page */

static void page_closed(void)
{
    unsigned char i;
    dispBufferOn = ST_WR_FORE;
    SetPattern(0);
    WRectangle(0, TOPY, 639, 463);
    theme_rect(0, 80, TOPY >> 3, 52, 0);
    if (sv_go) {
        sv_go = 0;
        conn_drop();
        cerr = CE_NONE;
        for (i = 1; i < WMAX; ++i)
            W[i].kind = W_FREE;
        cw = 0;
        sb_clear(0);
        conn_start();
        strcpy(msg, "Connecting to ");
        strcat(msg, S.host);
        strcat(msg, " ...");
        ui_status(msg);
    }
    dirty |= D_ALL;
}

static void servers(void)
{
    ov3(sv_show);
}

/*---------------------------------------------------------------- every pass */

void ui_tick(void)
{
    signed char w;
    unsigned char s;
    if (sv_page)                        /* (a connection that ends behind the page: its box after it) */
        return;
    if (sv_go || pg_closed) {         /* (the page just closed) */
        pg_closed = 0;
        page_closed();
    }
    asm("sei");
    w = (signed char)mouseWheel;
    mouseWheel = 0;
    asm("cli");
    if (w && !menuNumber) {
        if (pane && W[cw].kind == W_CHAN && mouseXPos >= (PANEX - 1) * 8) {
            if (w < 0 && np_top < -w * 3)
                np_top = 0;
            else
                np_top += 3 * w;
            nicks();
        } else
            scroll_by(3 * w);
    }
    if (cw_req >= 0) {
        w = cw_req;
        cw_req = -1;
        ui_show(w);
    }
    if (cerr)
        ended();
    if (ding) {
        ding = 0;
        PlaySound(SND_WARNING);
#ifdef CHAT_TEST
        ++t_ding;
        gt_log("IR DING");
#endif
    }
    if (W[cw].unread) {
        W[cw].unread = 0;
        dirty |= D_TABS;
    }
    if (dirty)
        redraw();
    if (drawn_w != cw)
        body_all();
    else if (drawn_seq != W[cw].seq) {
        body_new();
        if (W[cw].scroll) {
            where();
            status2();
        }
    }
    s = net_on ? net_state() : NET_OFF;
    if (cstate != last_state || s != last_net) {
        if (cstate == C_UP && last_state != C_UP) {
            strcpy(msg, "Connected to ");
            strcat(msg, S.name);
            strcat(msg, ".");
            ui_status(msg);
        }
        last_state = cstate;
        last_net = s;
        title();
        where();
        status2();
    }
}

/*---------------------------------------------------------------- the menus */

void m_about(void)
{
    GotoFirstMenu();
    message("Veranda Chat 1.0, MIT licence.", "An IRC client through the Wi-Fi modem.");
}

void m_quit(void)
{
    GotoFirstMenu();
    if (cstate == C_UP && !yesno("You are connected.", "Quit Veranda Chat anyway?"))
        return;
    conn_quit(0);
    while (cstate != C_OFF)             /* (the QUIT out: 3 s at most) */
        conn_poll();
    net_stop();
    EnterDeskTop();
}

void m_servers(void) { GotoFirstMenu(); servers(); }

void m_disc(void)
{
    GotoFirstMenu();
    if (cstate == C_OFF) {
        ui_status("Not connected.");
        return;
    }
    conn_quit(0);
}

void m_next(void) { GotoFirstMenu(); next_win(1); }
void m_prev(void) { GotoFirstMenu(); next_win(-1); }
void m_close(void) { GotoFirstMenu(); close_win(); }
void m_pane(void) { GotoFirstMenu(); pane = !pane; dirty |= D_ALL; }
void m_stamps(void) { GotoFirstMenu(); stamps = !stamps; dirty |= D_BODY; }
void m_clear(void) { GotoFirstMenu(); sb_clear(cw); dirty |= D_BODY; }

/*---------------------------------------------------------------- input */

static void press(void)
{
    unsigned int x = mouseXPos, y = mouseYPosW, i;
    unsigned char c = x >> 3;
    if (mouseData & 0x80)
        return;
    if (sv_page) {
        ov3(sv_press);
        pg_closed = !sv_page;         /* (closed: drawn again at the next pass) */
        return;
    }
    if (y >= TOOLY && y < TOOLY + 16) {
        if (c >= 1 && (c - 1) % TABW < TABW - 1)
            ui_show((c - 1) / TABW);
        return;
    }
    if (y >= BODYY && y <= BODYB && (c == SBN || c == SBN + 1 || (PANE() && (c == SBT || c == SBT + 1)))) {
        if (c < SBN || !PANE()) {           /* (the text's bar: rows up from the newest) */
            tbar(0);
            ov5(sb_hit);
            i = sb_r == VS_BACK ? 1 : sb_r == VS_FWD ? -1 : sb_r == VS_PGBACK ? ROWS - 2 : sb_r == VS_PGFWD ? -(ROWS - 2) : 0;
            if (i)
                scroll_by(i);
        } else {                            /* (the nick list's) */
            nbar(0);
            ov5(sb_hit);
            i = sb_r == VS_BACK ? -1 : sb_r == VS_FWD ? 1 : sb_r == VS_PGBACK ? -(ROWS - 1) : sb_r == VS_PGFWD ? ROWS - 1 : 0;
            if (i) {
                np_top = (int)i < 0 && np_top < -(int)i ? 0 : np_top + i;
                nicks();
            }
        }
        return;
    }
    if (PANE() && y >= BODYY && y <= BODYB && c >= PANEX) {
        i = np_top + (y - BODYY) / RH;
        if (i < W[cw].nicks) {
            nk_get(cw, i);
            insert_s(nk + 1);
            insert_s(cur == strlen(nk + 1) ? ": " : " ");
            input();
        }
    }
}

static void key(void)
{
    unsigned char k = keyData, m = keyDataMods;
    if (sv_page) {
        ov3(sv_key);
        pg_closed = !sv_page;
        return;
    }
    if (k != KEY_TAB)
        comp_on = 0;
    if (m & 2) {                        /* Ctrl */
        switch (k) {
        case 14: next_win(1); return;               /* N */
        case 16: next_win(-1); return;              /* P */
        case 23: close_win(); return;               /* W */
        case 12: dirty |= D_ALL; return;            /* L */
        case 17:                                    /* Q (not Ctrl+Down: KEY_DOWN is 17) */
            if (!(m & KEYM_ARROW))
                m_quit();
            return;
        case 22:                                    /* V */
            ov3(sv_paste);
            for (k = 0; line[k] && line[k] != '\r' && line[k] != '\n'; ++k)
                insert(line[k]);
            input();
            return;
        }
        return;
    }
    if (m & KEYM_ARROW) {
        switch (k) {
        case KEY_LEFT: if (cur) --cur; break;
        case KEY_RIGHT: if (cur < inlen) ++cur; break;
        case KEY_UP:
            if (hist_get(hback + 1, tbuf)) {
                ++hback;
                set_input(tbuf);
            }
            return;
        case KEY_DOWN:
            if (hback > 1 && hist_get(hback - 1, tbuf)) {
                --hback;
                set_input(tbuf);
            } else if (hback) {
                hback = 0;
                set_input("");
            }
            return;
        }
        input();
        return;
    }
    switch (k) {
    case 13: send_input(); return;
    case KEY_TAB: ov4(in_complete); break;
    case 8:
        if (!cur)
            return;
        --cur;
        /* (on: Delete's) */
    case KEY_DELETE:
        if (cur >= inlen)
            return;
        memmove(inbuf + cur, inbuf + cur + 1, inlen - cur);
        --inlen;
        break;
    case KEY_HOME: cur = 0; break;
    case KEY_END:
        cur = inlen;
        if (W[cw].scroll)
            scroll_by(-30000);
        break;
    case KEY_PGUP: scroll_by(ROWS - 2); return;
    case KEY_PGDN: scroll_by(-(ROWS - 2)); return;
    case KEY_ESC:
        if (W[cw].scroll)
            scroll_by(-30000);
        set_input("");
        return;
    case KEY_F1: case KEY_F2: case KEY_F3: case KEY_F4: case KEY_F5: case KEY_F6:
        ui_show(k - 1);
        return;
    case KEY_F7: ui_show(6); return;
    default:
        if ((k >= 32 && k < 127) || k >= 160)
            insert(k);
        else
            return;
    }
    input();
}

void ui_start(void)
{
    dispBufferOn = ST_WR_FORE;
    SetPattern(0);
    WRectangle(0, 0, 639, 15);
    theme_load();
    theme_palette();
    win_all("Veranda Chat");
    theme_menus();
    ov5(sv_menus);
    hl = theme_none() ? 0 : theme.hilite ? theme.hilite : SELECT;
    DoMenu((void *)&mbar, 0);
    cw_req = -1;
    ov3(sv_load);
    sb_add(0, A_INFO, "-- Veranda Chat 1.0: an IRC client. Server > Servers... connects; /help lists the commands.");
    dirty = D_ALL;
    redraw();
    otherPressVec = VR_FN(press);
    keyVector = VR_FN(key);
    servers();
}
