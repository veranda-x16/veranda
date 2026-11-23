/* Veranda Gemini: the interface (overlay 1, appBank: mapped for good;
   DECISIONS V118).

   Veranda Gopher's window (V109, V110): the menu bar (the kernel's), the
   title band (the page's name), the toolbar (Back and Forward, Home, the
   address line, Go, which is Stop while something comes), the page (card
   rows 7-57), the scroll bar at cards 78-79 (V149: the SDK's), the status bar.

   A gemtext page is rows of 16 pixels (2 card rows: each has its own
   colours), 25 shown, in the X16's CP437 font (cs_draw): text at cards
   4-76; a link's badge at cards 1-2 (its kind's glyph on its kind's
   colour: an arrow cyan a Gemini link, a globe the web, a folder yellow
   Gopher, an envelope purple mail, a picture orange, chrome anything
   else), the selected link in the theme's highlight (reversed with
   Classic); headings underlined (a first one also on the title bars'
   colour, a second on the sidebar's), a list item's bullet and a quote's
   bar at card 2; preformatted rows at cards 1-76. A plain text is rows
   of 12 pixels (34 shown), cards 1-76.

   A click follows a link (Shift+click only selects it); the keys: Tab
   and Shift+Tab (the next and the previous link), Return (follow it),
   Up, Down, PgUp, PgDn, Home, End, Left or Backspace (Back), Right
   (Forward), Esc (Stop), Ctrl+L (the address line), Ctrl+R (Reload),
   Ctrl+F (Find), Ctrl+G (Find again); the wheel and the scroll bar
   scroll. Typing a character starts a new address. In the address line:
   Return goes, Esc leaves it, Ctrl+V pastes the clipboard's text.

   What a reply asks for: 1x a question in a box, sent back as the URL's
   query (11's answer shows as it is typed: the box has no stars); 3x a
   redirect followed (5 at most; another host asked about first; another
   scheme said where it leads); 20 a page, or a file: "Download?"; the
   rest a box (url.c).

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <vr.h>
#include <string.h>
#include <theme.h>
#include <vrnet.h>
#include <vrser.h>
#include <vrpath.h>
#include <vrwin.h>
#include "gemini.h"
#pragma code-name ("OVERLAY1")
#pragma rodata-name ("OVL1RO")
/* (its texts in this bank: what the kernel reads is copied below $A000
   first (message, ask, ui_status, line), the menus' texts are in main
   RAM, below) */

#define NONE    0xFFFF

#define N_NEW    0
#define N_BACK   1
#define N_FWD    2
#define N_RELOAD 3

char cur[URLMAX], go[URLMAX], rel[URLMAX];
char title[TITLEMAX], gtitle[TITLEMAX];
char msg[96];
unsigned int v_top, v_sel = NONE;       /* the first row shown, the selected link's first row */
unsigned int v_find = NONE;             /* the row Find found */
unsigned char v_edit, hpos, hn, fresh;
static unsigned char nav, navto, local, kcol, kgo;
unsigned char redirs;
char right[40];
char fq[42];
static unsigned char hl;
static unsigned int upto, tshow;
unsigned char lastnet = 0xFF;
static unsigned char dragging, sbf;     /* (V149) the scroll bar: held (1 the thumb, 2 3 an arrow); drawn again */
static unsigned int grab;               /* (the thumb's: where it was taken) */
unsigned char rows = MROWS, rowh = MROWH;

#define LINES() (doc_lines + (doc_full && doc_done ? 2 : 0))

/* a link's badge: its glyph, its colour (K_SUB) */
static const unsigned char lglyph[] = { G_LINK, G_WEB, G_FOLDER, G_MAIL, G_PIC, G_BIN };
static const unsigned char lcol[] = { CYAN, SKY2, YELLOW, PURPLE, ORANGE, CHROME };

/*---------------------------------------------------------------- drawing */

static void status2(void)
{
    win_status(msg, right);
}

void __fastcall__ ui_status(const char *s)
{
    if (s != msg)
        strncpy(msg, s, sizeof msg - 1);
    status2();
#ifdef GEMINI_TEST
    strcpy(line, "GE STATUS ");
    strcat(line, msg);
    gt_log(line);
#endif
}

static void set_title(void)
{
    strcpy(line, appname);
    if (title[0]) {
        strcat(line, ": ");
        strcat(line, title);
    }
    win_title(line);
}

static void __fastcall__ draw_row(unsigned char r)
{
    unsigned int i = v_top + r, y = BODYY + r * rowh;
    unsigned char k, t, s, c, p, n, g = G_NONE, cr = BROW + (r << 1);
    if (i >= LINES()) {
        SetPattern(0);
        WRectangle(8, y, SBX * 8 - 1, y + rowh - 1);
        if (hl && doc_mode == M_GEM)
            theme_rect(0, SBX, cr, 2, 0);
        return;
    }
    k = render(i);
    if (doc_mode == M_PLAIN) {
        cells(1, y, ROWW, TROWH, 0);
        return;
    }
    t = k == 0xFF ? K_TEXT : k & K_TYPE;
    s = i == v_find;
    kcol = 0;
    if (t == K_LINK) {
        if (link_head(i) == v_sel)
            s = 1;
        if (!(k & K_CONT)) {
            g = lglyph[K_SUB(k)];
            kcol = lcol[K_SUB(k)];
        }
        memmove(row, row + 3, GEMW);
        cells(4, y, GEMW, MROWH, s && !hl);
        glyph(8 + 3, y, g, MROWH, s && !hl ? GL_REV : 0);
    } else {
        cells(1, y, ROWW, MROWH, s && !hl);
        if (t >= K_H1 && t <= K_H3) {
            for (n = ROWW; n > 3 && row[n - 1] == ' '; --n)
                ;
            if (n > 3) {
                WHorizontalLine(t == K_H3 ? 0xAA : 0xFF, 32, n * 8 + 7, y + 13);
                if (t == K_H1)
                    WHorizontalLine(0xFF, 32, n * 8 + 7, y + 14);
            }
        }
    }
    if (hl) {
        c = s ? hl : 0;
        p = t == K_H1 ? TITLE : t == K_H2 ? SIDEBAR : 0;
        if (c)
            p = c;
        theme_rect(0, 1, cr, 2, c ? c : p);
        theme_rect(1, 2, cr, 2, kcol ? kcol : p);
        theme_rect(3, SBX - 3, cr, 2, p);
    }
}

/* (V149, Sunroom) the SDK's scroll bar, when what it shows changed */
static void scrollbar(void)
{
    unsigned int all = LINES();
    if (!sbf && sbar.first == v_top && sbar.shown == rows && sbar.total == all)
        return;
    sbf = 0;
    sbar.first = v_top;
    sbar.shown = rows;
    sbar.total = all;
    sb_draw();
}

void page(void)                         /* (the test's timing calls it) */
{
    unsigned char r;
    for (r = 0; r < rows; ++r)
        draw_row(r);
    sbf = 1;
    scrollbar();
}

#define where() ov2(u_lines)

/*---------------------------------------------------------------- moving */

static void __fastcall__ scroll_to(long t)
{
    unsigned int all = LINES();
    if (t > (long)all - rows)
        t = (long)all - rows;
    if (t < 0)
        t = 0;
    if ((unsigned int)t == v_top)
        return;
    v_top = t;
    page();
    where();
    status2();
}

static void __fastcall__ scroll_by(long by)
{
    scroll_to((long)v_top + by);
}

/* the rows of the line whose first row is h drawn (those shown) */
static void __fastcall__ draw_line(unsigned int h)
{
    if (h == NONE)
        return;
    do {
        if (h >= v_top && h < v_top + rows)
            draw_row(h - v_top);
        ++h;
    } while (h < doc_lines && (doc_kind(h) & K_CONT));
}

/* link h selected, scrolled to */
static void __fastcall__ select(unsigned int h)
{
    unsigned int old = v_sel;
    v_sel = h;
    if (h != NONE && h < v_top)
        scroll_to(h);
    else if (h != NONE && h >= v_top + rows)
        scroll_to((long)h - rows + 2);
    draw_line(old);
    draw_line(h);
}

static unsigned char __fastcall__ is_link(unsigned int i)
{
    return i < doc_lines && doc_kind(i) == (doc_kind(i) & ~K_CONT) && (doc_kind(i) & K_TYPE) == K_LINK;
}

/* Tab, Shift+Tab: the next link (by 1, -1), from the selected one or
   the page shown; round to the other end */
static void __fastcall__ tab(signed char by)
{
    unsigned int i, n;
    if (doc_mode != M_GEM || !doc_lines)
        return;
    if (v_sel != NONE)
        i = v_sel;
    else
        i = by > 0 ? (v_top ? v_top - 1 : doc_lines - 1) : (v_top + rows < doc_lines ? v_top + rows : 0);
    for (n = 0; n < doc_lines; ++n) {
        i = by > 0 ? (i + 1 < doc_lines ? i + 1 : 0) : (i ? i - 1 : doc_lines - 1);
        if (is_link(i)) {
            select(i);
            return;
        }
    }
    ui_status("This page has no links.");
}

/*---------------------------------------------------------------- going places */

static unsigned char busy(void)
{
    if (!gbusy)
        return 0;
    ui_status("Busy: wait for this to end, or Stop (Esc).");
    Beep();
    return 1;
}

static void here_saved(void)
{
    if (!hn)
        return;
    hist_get(hpos, &H);
    H.top = v_top;
    H.sel = v_sel;
    hist_put(hpos, &H);
}

/* the fetch's page is the page now (its header came, or the bookmarks,
   or the cache's copy): the history moved */
void g_first(void)
{
    ov4(i_off);                         /* (a picture shown: gone) */
    here_saved();
    if (nav == N_NEW) {
        if (hn)
            ++hpos;
        if (hpos == HISTMAX) {
            hist_shift();
            --hpos;
        }
        hn = hpos + 1;
        strcpy(H.url, go);
        memcpy(H.title, gtitle, TITLEMAX);
        H.top = 0;
        H.sel = NONE;
        hist_put(hpos, &H);
    } else {
        if (nav != N_RELOAD)
            hpos = navto;
        hist_get(hpos, &H);
        strcpy(H.url, go);              /* (after a redirect, a question: where it is) */
        hist_put(hpos, &H);
    }
    strcpy(cur, go);
    memcpy(title, gtitle, TITLEMAX);
    v_top = H.top;
    v_sel = H.sel;
    v_find = NONE;
    doc_clear(gtext, gdec);
    rowh = gtext == M_PLAIN ? TROWH : MROWH;
    rows = gtext == M_PLAIN ? TROWS : MROWS;
    upto = v_top;
    set_title();
    dispBufferOn = ST_WR_FORE;
    SetPattern(0);
    WRectangle(0, BODYY, SBX * 8 - 1, BODYY + TRACK * 8 - 1);
    theme_rect(0, SBX, BROW, TRACK, 0);
    scrollbar();
}

static void __fastcall__ connect(unsigned char download)
{
    rtry = 0;
    ov3(u_host);
    if (!u_ret) {
        message("Veranda Gemini cannot reach that host", "(letters, digits, dots and dashes only).");
        return;
    }
    if (!net_on || net_state() == NET_FAULT)
        net_restart();
    strcpy(msg, "Connecting to ");
    strcat(msg, ghost);
    strcat(msg, " ...");
    ui_status(msg);
    g_start(download);
    toolbar();
}

static void __fastcall__ fetch(unsigned char kind)
{
    rtry = 0;
    nav = kind;
    local = 0;
    if (!go[0]) {                       /* the bookmarks page */
        local = 1;
        gtext = M_GEM;
        gdec = D_RAW;
        gdl = 0;
        gfirst = 1;
        gerr = GE_OK;
        g_first();
        ov2(marks_page);
        ui_done();
        return;
    }
    if ((kind == N_BACK || kind == N_FWD) && cache_has()) {
        local = 2;                      /* (Back, Forward: the page kept) */
        ov3(u_host);
        gdec = D_RAW;
        gdl = 0;
        gfirst = 1;
        gerr = GE_OK;
        g_first();
        cache_fill();
        ui_done();
        return;
    }
    connect(0);
}

static void __fastcall__ go_hist(unsigned char i, unsigned char kind)
{
    if (busy())
        return;
    hist_get(i, &H);
    strcpy(go, H.url);
    memcpy(gtitle, H.title, TITLEMAX);
    navto = i;
    redirs = 0;
    fetch(kind);
}

static void back(void)
{
    if (!hpos) {
        Beep();
        return;
    }
    go_hist(hpos - 1, N_BACK);
}

static void forward(void)
{
    if (hpos + 1 >= hn) {
        Beep();
        return;
    }
    go_hist(hpos + 1, N_FWD);
}

static void reload(void)
{
    if (hn)
        go_hist(hpos, N_RELOAD);
}

static void home(void)
{
    if (busy())
        return;
    go[0] = 0;
    strcpy(gtitle, "Bookmarks");
    redirs = 0;
    fetch(N_NEW);
}

static void __fastcall__ follow(unsigned int i)
{
    unsigned char n;
    if (busy())
        return;
    i = link_head(i);
    if (!doc_url(i)) {
        Beep();
        return;
    }
    render(i);                          /* (its label: the page's name until it has a heading) */
    for (n = 0; n < TITLEMAX - 1 && row[3 + n]; ++n)
        gtitle[n] = row[3 + n];
    while (n && gtitle[n - 1] == ' ')
        --n;
    gtitle[n] = 0;
    ov3(u_resolve);
    if (u_ret != U_GEM) {
        ov3(u_where);
        return;
    }
    redirs = 0;
    if (K_SUB(doc_kind(i)) == LK_PIC) { /* (a picture: shown or saved, V125) */
        ov4(i_link);
        if (u_ret)
            connect(u_ret);
        return;
    }
    fetch(N_NEW);
}

/*---------------------------------------------------------------- the address line */

static void __fastcall__ edit(unsigned char on)
{
    v_edit = on;
    if (on) {
        strcpy(abuf, cur);
        alen = strlen(abuf);
        fresh = 1;
    }
    field();
}

static void go_on(void);

static void go_addr(void)
{
    if (busy())
        return;
    if (!alen) {
        ui_status("Type an address: gemini://host/path");
        return;
    }
    ov4(k_typed);                       /* ("wp <text>": Wikipedia, V128) */
    if (u_ret == 0xFF)
        ov3(u_typed);
    go_on();
}

/* go (u_ret U_GEM) fetched as a new page; else where it leads, or nothing */
static void go_on(void)
{
    if (u_ret != U_GEM) {
        ov3(u_where);
        return;
    }
    v_edit = 0;
    field();
    gtitle[0] = 0;
    redirs = 0;
    fetch(N_NEW);
}

static void __fastcall__ field_key(unsigned char k)
{
    if (fresh && k >= 32) {
        alen = 0;
        abuf[0] = 0;
    }
    fresh = 0;
    if (k == 13) {
        go_addr();
        return;
    }
    if (k == KEY_ESC) {
        edit(0);
        return;
    }
    if (k == 8 && !(keyDataMods & KEYM_ARROW)) {
        if (alen)
            abuf[--alen] = 0;
    } else if (k == 22 && (keyDataMods & 2)) {     /* Ctrl+V */
        ov2(marks_paste);
        for (k = 0; line[k] && line[k] != '\r' && line[k] != '\n' && alen < URLMAX - 1; ++k)
            abuf[alen++] = line[k];
        abuf[alen] = 0;
    } else if (k >= 32 && k < 127 && alen < URLMAX - 1) {
        abuf[alen++] = k;
        abuf[alen] = 0;
    }
    field();
}

/*---------------------------------------------------------------- find */

static void find_next(void)
{
    unsigned int i, n, old = v_find;
    if (!fq[0] || !doc_lines)
        return;
    i = v_find != NONE ? v_find : (v_top ? v_top - 1 : doc_lines - 1);
    for (n = 0; n < doc_lines; ++n) {
        i = i + 1 < doc_lines ? i + 1 : 0;
        render(i);
        ov2(u_hit);
        if (u_ret) {
            v_find = i;
            if (i < v_top || i >= v_top + rows)
                scroll_to((long)i - 3);
            if (old != NONE && old >= v_top && old < v_top + rows)
                draw_row(old - v_top);
            draw_row(i - v_top);
            strcpy(msg, "Found on line ");
            unum(msg + strlen(msg), i + 1);
            ui_status(msg);
            return;
        }
    }
    ui_status("Not found on this page.");
    Beep();
}

static void find(void)
{
    if (!ask("Find in this page:", fq, 40) || !fq[0])
        return;
    v_find = NONE;
    find_next();
}

/*---------------------------------------------------------------- an end */

void ui_done(void)
{
    unsigned long t;
    unsigned int r;
    unsigned char e = gerr;
    toolbar();
    if (e == GE_NET) {                  /* (V138: tried once more, a second later?) */
        ov3(u_retry);
        if (u_ret)
            return;
    }
    if (gdl == 2) {                     /* (a picture: V125) */
        ov4(i_done);
        if (u_ret)
            connect(1);
        return;
    }
    if (gdl) {
        t = ser_frames - gt0;
        if (e == GE_OK) {
            strcpy(msg, "Downloaded ");
            strcat(msg, xf_name);
            strcat(msg, " to /DOCUMENTS: ");
            unum(msg + strlen(msg), grx);
            strcat(msg, " bytes in ");
            unum(msg + strlen(msg), (t + 30) / 60);
            strcat(msg, " s");
            ui_status(msg);
            where();
            status2();
            return;
        }
    } else if (gfirst) {                /* a page, whole or not */
        r = upto < doc_lines ? upto : doc_lines;
        doc_end();
        if (r > doc_lines)
            r = doc_lines;
        if (r < v_top)
            r = v_top;
        for (; r < v_top + rows; ++r)
            draw_row(r - v_top);
        scrollbar();
        scroll_to(v_top);               /* (a page shorter than where it was) */
        ov2(u_named);
        where();
        strcpy(msg, local == 1 ? "Bookmarks" : ghost);
        strcat(msg, ": ");
        unum(msg + strlen(msg), doc_len);
        strcat(msg, " bytes");
        if (local == 2)
            strcat(msg, " (kept from before)");
        if (doc_full)
            strcat(msg, ", cut (too long)");
        if (e == GE_CANCEL)
            strcat(msg, ", stopped");
        ui_status(msg);
        if (e == GE_OK && !local)
            cache_put();
#ifdef GEMINI_TEST
        t_ovt(page_log);
#endif
        if (e == GE_OK || e == GE_CANCEL)
            return;
    }
    if (e == GE_CANCEL) {
        ui_status("Stopped.");
        return;
    }
    strcpy(msg, "Failed.");
    status2();
    if (e == GE_STATUS && (gstatus / 10 == 1 || gstatus / 10 == 3)) {
        ov3(gstatus / 10 == 1 ? u_input : u_redir);     /* (a question, a redirect) */
        if (u_ret == 2)
            ui_status(msg);
        if (u_ret == 1) {
            ui_status(msg);
            if (gdl)
                connect(1);
            else
                fetch(nav);
        }
        return;
    }
    ov3(u_fail);
    where();
    status2();
}

/* a body that is not a page (or File > Download's): to /DOCUMENTS? */
void ui_save(void)
{
    ov3(u_save);
    if (u_ret)
        ui_status(msg);
}

void ui_tick(void)
{
    unsigned long bps;
    unsigned int lim, f;
    signed char w;
    char *p;
    if (rtry == 1 && ser_frames - rt_t > 60) {
        rtry = 2;
        g_start(gdl);
        toolbar();
    }
    if (kgo && !--kgo) {                /* (the start document's line typed, a few passes on: V128) */
        ov4(k_start);
        if (u_ret)
            go_addr();
    }
    asm("sei");
    w = (signed char)mouseWheel;
    mouseWheel = 0;
    asm("cli");
    if (w && !menuNumber)
        scroll_by(3 * w);
    if (dragging) {                     /* (V149: the thumb dragged, an arrow held) */
        if (mouseData & 0x80)
            dragging = 0;
        else if (dragging > 1)
            scroll_by(dragging == 2 ? -1 : 1);
        else {
            lim = LINES();
            f = mouseYPosW - grab;
            f = (int)f < 16 ? 0 : f - 16;      /* (the thumb's place on the track) */
            if (lim > rows)
                scroll_to((long)f * (lim - rows) / (SBLEN * 8 - 32 - sb_n));
        }
    }
    if (gbusy && !gdl && gfirst) {      /* the rows that have come, drawn */
        lim = doc_lines ? doc_lines - 1 : 0;
        if (lim > upto) {
            if (upto < v_top)
                upto = v_top;
            for (; upto < lim && upto < v_top + rows; ++upto)
                draw_row(upto - v_top);
            upto = lim;
        }
    }
    if (gbusy) {
        if (ser_frames - tshow < 20)
            return;
        tshow = ser_frames;
        if (!gfirst && !gdl)
            return;
        strcpy(msg, gdl ? "Downloading " : "Loading ");
        strcat(msg, gdl ? xf_name : ghost);
        strcat(msg, ": ");
        p = unum(msg + strlen(msg), grx);
        strcpy(p, " bytes");
        f = ser_frames - gt0;
        bps = f ? grx * 60 / f : 0;
        p = unum(right, bps / 1024);
        *p++ = '.';
        p = unum(p, bps * 10 / 1024 % 10);
        strcpy(p, " KB/s");
        if (!gdl)
            scrollbar();
        status2();
        return;
    }
    if ((net_on ? net_state() : NET_OFF) != lastnet) {
        where();
        status2();
    }
}

/*---------------------------------------------------------------- the menus */

static void m_about(void), m_quit(void), m_open(void), m_get(void), m_find(void), m_again(void), m_stop(void), m_web(void);
static void m_back(void), m_fwd(void), m_reload(void), m_home(void), m_wiki(void);
static void m_add(void), m_del(void);

struct item { const char *text; unsigned char type; void *p; };
struct menu2 { unsigned char top, bottom; unsigned int left, right; unsigned char flags; struct item i[2]; };
struct menu3 { unsigned char top, bottom; unsigned int left, right; unsigned char flags; struct item i[3]; };
struct menu4 { unsigned char top, bottom; unsigned int left, right; unsigned char flags; struct item i[4]; };
struct menu5 { unsigned char top, bottom; unsigned int left, right; unsigned char flags; struct item i[5]; };
struct menu6 { unsigned char top, bottom; unsigned int left, right; unsigned char flags; struct item i[6]; };

/* (the menus' texts in main RAM: the kernel draws them; V149, Sunroom:
   "\x1f" a separator above the item, "\t" its key, right-aligned) */
#pragma rodata-name (push, "RODATA")
static const char s_about[] = "About Veranda Gemini", s_quit[] = "\x1f" "Quit", s_open[] = "Open address\tCtrl L",
    s_get[] = "Download", s_find[] = "\x1f" "Find...\tCtrl F", s_again[] = "Find again\tCtrl G",
    s_stop[] = "\x1f" "Stop\tEsc", s_web[] = "\x1f" "Settings...",
    s_back[] = "Back\tLeft", s_fwd[] = "Forward\tRight", s_reload[] = "Reload\tCtrl R",
    s_home[] = "\x1f" "Home (bookmarks)", s_wiki[] = "Wikipedia...\tCtrl W",
    s_show[] = "Show bookmarks", s_add[] = "\x1f" "Add this page", s_del[] = "Remove...",
    s_file[] = "File", s_go[] = "Go", s_marks[] = "Bookmarks";
#pragma rodata-name (pop)

#define IH 14
static struct menu2 mapp = { 14, 14 + 2 * IH, 0, 0, VERTICAL | 2, {
    { s_about, MENU_ACTION, m_about }, { s_quit, MENU_ACTION, m_quit } } };
static struct menu6 mfile = { 14, 14 + 6 * IH, 0, 0, VERTICAL | 6, {
    { s_open, MENU_ACTION, m_open }, { s_get, MENU_ACTION, m_get },
    { s_find, MENU_ACTION, m_find }, { s_again, MENU_ACTION, m_again },
    { s_stop, MENU_ACTION, m_stop }, { s_web, MENU_ACTION, m_web } } };
static struct menu5 mgo = { 14, 14 + 5 * IH, 0, 0, VERTICAL | 5, {
    { s_back, MENU_ACTION, m_back }, { s_fwd, MENU_ACTION, m_fwd },
    { s_reload, MENU_ACTION, m_reload }, { s_home, MENU_ACTION, m_home },
    { s_wiki, MENU_ACTION, m_wiki } } };
static struct menu3 mmarks = { 14, 14 + 3 * IH, 0, 0, VERTICAL | 3, {
    { s_show, MENU_ACTION, m_home }, { s_add, MENU_ACTION, m_add },
    { s_del, MENU_ACTION, m_del } } };
static struct menu4 mbar = { 0, 14, 0, 0, HORIZONTAL | UN_CONSTRAINED | 4, {
    { appname, SUB_MENU, &mapp }, { s_file, SUB_MENU, &mfile },
    { s_go, SUB_MENU, &mgo }, { s_marks, SUB_MENU, &mmarks } } };
static const char *const barnames[4] = { appname, s_file, s_go, s_marks };
unsigned int barx[4], barl[4];          /* the bar's items' middles, the lists' lefts (the test clicks them) */

static void layout(void)
{
    static struct menu6 *const lists[4] = { (struct menu6 *)&mapp, &mfile, (struct menu6 *)&mgo, (struct menu6 *)&mmarks };
    struct menu6 *m;
    unsigned int b, w, wmax;
    unsigned char i, j, c;
    const char *p;
    for (i = 0; i < 4; ++i) {
        b = vr_bar_end(barnames, i);
        barx[i] = (b + vr_bar_end(barnames, i + 1)) >> 1;
        barl[i] = b;
        UseFont(FONT_UI);
        m = lists[i];
        for (wmax = j = 0; j < (m->flags & 31); ++j) {
            for (w = 0, p = m->i[j].text; (c = *p) != 0; ++p)  /* (as the shell's: a key's tab 24 pixels) */
                w += c == 9 ? 24 : c == 0x1F ? 0 : GetCharWidth(c);
            if (w > wmax)
                wmax = w;
        }
        m->left = b;
        m->right = b + wmax + 16;
    }
    mbar.right = vr_bar_end(barnames, 4);
    UseSystemFont();
}

static void m_about(void)
{
    GotoFirstMenu();
    ov2(u_about);
}

static void quit(void)
{
    if (gbusy && !yesno("Something is still coming.", "Quit anyway?"))
        return;
    g_cancel();
    net_stop();
    EnterDeskTop();
}

static void m_quit(void) { GotoFirstMenu(); quit(); }
static void m_open(void) { GotoFirstMenu(); edit(1); }
static void m_find(void) { GotoFirstMenu(); find(); }
static void m_again(void) { GotoFirstMenu(); find_next(); }

/* File > Download: the selected link (else the page shown) to the card,
   whatever it is */
static void m_get(void)
{
    GotoFirstMenu();
    if (busy())
        return;
    if (v_sel != NONE && doc_url(v_sel)) {
        ov3(u_resolve);
        if (u_ret != U_GEM) {
            ov3(u_where);
            return;
        }
    } else if (cur[0])
        strcpy(go, cur);
    else {
        ui_status("Select a link to download (Tab).");
        return;
    }
    redirs = 0;
    connect(1);
}

static void m_stop(void) { GotoFirstMenu(); g_cancel(); }
static void m_web(void) { GotoFirstMenu(); ov4(w_setweb); }
static void m_back(void) { GotoFirstMenu(); back(); }
static void m_fwd(void) { GotoFirstMenu(); forward(); }
static void m_reload(void) { GotoFirstMenu(); reload(); }
static void m_home(void) { GotoFirstMenu(); home(); }

/* Go > Wikipedia... (Ctrl+W): asked, looked up in Gemipedia (wiki.c) */
static void wiki(void)
{
    if (busy())
        return;
    ov4(k_ask);
    go_on();
}

static void m_wiki(void) { GotoFirstMenu(); wiki(); }

static void m_add(void)
{
    GotoFirstMenu();
    if (!cur[0]) {
        ui_status("This is the bookmarks page.");
        return;
    }
    ov2(marks_add);
    ov2(u_marked);
    if (u_ret)
        ui_status(msg);
}

static void m_del(void)
{
    unsigned int i;
    GotoFirstMenu();
    if (busy())
        return;
    if (cur[0] || v_sel == NONE) {
        if (cur[0])
            home();
        ui_status("Select a bookmark (Tab), then Bookmarks > Remove...");
        return;
    }
    render(v_sel);
    for (i = GEMW; i && row[i + 2] == ' '; --i)
        ;
    row[i + 3] = 0;
    strcpy(line, row + 3);
    if (!yesno("Remove the bookmark", line))
        return;
    marks_i = 0;
    for (i = 0; i < v_sel; ++i)
        if (is_link(i))
            ++marks_i;
    ov2(marks_del);
    ov2(u_marked);
    v_sel = NONE;
    home();
}

/*---------------------------------------------------------------- input */

/* (V125) a key or a click while a picture is shown: pic.c's; the page again after it */
static void __fastcall__ viewer(void (*f)(void))
{
    ov4(f);
    if (!viewing) {
        page();
        where();
        status2();
    }
}

static void press(void)
{
    unsigned int x = mouseXPos, y = mouseYPosW, i;
    if (mouseData & 0x80)
        return;
    if (viewing) {
        viewer(i_press);
        return;
    }
    if (y >= TOOLY && y < BODYY) {
        x >>= 3;
        if (x >= FX && x < FX + FW) {
            if (!v_edit)
                edit(1);
            fresh = 0;
            field();
        } else {
            if (v_edit)
                edit(0);
            if (x >= BX && x < BX + 3)
                back();
            else if (x >= BX + 3 && x < BX + 6)
                forward();
            else if (x >= HOMEX && x < HOMEX + 3)
                home();
            else if (x >= GOX && x < GOX + 6) {
                if (gbusy)
                    g_cancel();
                else if (v_edit)
                    go_addr();
                else
                    reload();
            }
        }
        return;
    }
    if (y < TOOLY) {                    /* (V149) the close box: Quit */
        if (y >= 16 && x >= 616)
            quit();
        return;
    }
    if (x >= SBX * 8) {                 /* (V149) the scroll bar: a line, a page, the thumb */
        if (v_edit)
            edit(0);
        switch (sb_hit(x, y)) {
        case VS_BACK: dragging = 2; break;
        case VS_FWD: dragging = 3; break;
        case VS_PGBACK: scroll_by(-(rows - 1)); break;
        case VS_PGFWD: scroll_by(rows - 1); break;
        case VS_THUMB:
            grab = y - sb_at;
            dragging = 1;
        }
        return;
    }
    if (y < BODYY || y >= BODYY + TRACK * 8)
        return;
    if (v_edit)
        edit(0);
    i = (y - BODYY) / rowh;
    if (i >= rows)
        return;
    i += v_top;
    if (doc_mode != M_GEM || i >= doc_lines || (doc_kind(i) & K_TYPE) != K_LINK)
        return;
    i = link_head(i);
    select(i);
    if (!(keyMods & 1))
        follow(i);
}

static void key(void)
{
    unsigned char k = keyData, m = keyDataMods;
    if (viewing) {
        viewer(i_key);
        return;
    }
    if (v_edit) {
        field_key(k);
        return;
    }
    if (m & 2) {                        /* Ctrl */
        if (k == 12)                    /* L */
            edit(1);
        else if (k == 18)               /* R */
            reload();
        else if (k == 6)                /* F */
            find();
        else if (k == 7)                /* G */
            find_next();
        else if (k == 23)               /* W: Wikipedia (V128) */
            wiki();
        else if (k == 22) {             /* V: a new address */
            edit(1);
            field_key(22);
        }
        return;
    }
    if (m & KEYM_ARROW) {
        switch (k) {
        case KEY_LEFT: back(); break;
        case KEY_RIGHT: forward(); break;
        case KEY_UP: scroll_by(-1); break;
        case KEY_DOWN: scroll_by(1); break;
        }
        return;
    }
    switch (k) {
    case KEY_UP: scroll_by(-1); break;
    case KEY_DOWN: scroll_by(1); break;
    case KEY_PGUP: scroll_by(-(rows - 1)); break;
    case KEY_PGDN: scroll_by(rows - 1); break;
    case KEY_HOME: scroll_by(-30000); break;
    case KEY_END: scroll_by(30000); break;
    case KEY_TAB: tab(m & 1 ? -1 : 1); break;
    case 0x18: tab(-1); break;          /* (Shift+Tab's ISO code) */
    case 13:
        if (v_sel != NONE) {
            retkey = 1;                 /* (a picture's: Show, Save, Cancel) */
            follow(v_sel);
            retkey = 0;
        }
        break;
    case 8: back(); break;
    case KEY_ESC: rtry = 0; g_cancel(); break;
    default:
        if (k > 32 && k < 127) {        /* a new address */
            edit(1);
            field_key(k);
        }
    }
}


void ui_start(void)
{
    dispBufferOn = ST_WR_FORE;
    SetPattern(0);
    WRectangle(0, 0, 639, 15);
    theme_load();
    theme_palette();
    win_all(appname);
    theme_menus();
    layout();
    hl = theme_none() ? 0 : theme.hilite ? theme.hilite : SELECT;
    DoMenu((void *)&mbar, 0);
    if (u_err & ST_LD_DATA)             /* (started with a document: its line, V128) */
        ov4(k_doc);
    kgo = 3;
    strcpy((char *)curDirName, vr_cd(VR_DOCS));         /* downloads: /DOCUMENTS */
    ov2(marks_load);
    doc_clear(M_GEM, D_RAW);
    toolbar();
    where();
    home();
    otherPressVec = VR_FN(press);
    keyVector = VR_FN(key);
}
