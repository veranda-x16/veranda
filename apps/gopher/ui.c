/* Veranda Gopher: the interface (overlay 1, appBank: mapped for good;
   DECISIONS V109; its look V110).

   The window (Veranda Look 2, sdk vrwin.h): the menu bar (the kernel's),
   the title band (card rows 2-3: the page's name), the toolbar (4-5:
   Back and Forward (dotted when there is nowhere to go), Home, the
   address line, Go, which is Stop while something comes: square
   frames, Sunroom), the page (card rows 7-57, row 6 left empty;
   drawn on the foreground only), the scroll bar at cards 78-79 (V149: the SDK's), the status
   bar (58-59: what is happening at its left; the lines shown, the speed
   or the modem's state at its right).

   The page is the X16's CP437 font, 8 x 8 glyphs in taller cells
   (cs_draw: a box character carried into the rows above and below,
   so that lines and blocks meet): a text's lines are 12 pixels (34
   shown, cards 1-76); a menu's are 16, 2 card rows (25 shown), so that
   each has its own colours: a badge (cards 1-2: the kind's glyph on the
   kind's colour, the shell list's) before an item's text (cards 4-76),
   none before an "i" line; the selected item in the theme's highlight
   (reversed with Classic). A click
   follows an item (Shift+click only selects it; a click on an error
   line shows its text in a box); the keys: Up, Down
   (the items), PgUp, PgDn, Home, End, Return (follow), Left or
   Backspace (Back), Right (Forward), Esc (Stop), Ctrl+L or Tab (the
   address line), Ctrl+R (Reload); the wheel and the scroll bar scroll.
   Typing a character starts a new address. In the address line:
   Return goes, Esc leaves it, Ctrl+V pastes the clipboard's text.

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <vr.h>
#include <string.h>
#include <theme.h>
#include <vrnet.h>
#include <vrser.h>
#include <vrpath.h>
#include <vrwin.h>
#include "gopher.h"
#pragma code-name ("OVERLAY1")

#define MTX     4               /* a menu line's text: cards MTX .. MTX + MTW - 1 */
#define NONE    0xFFFF

#define N_NEW    0
#define N_BACK   1
#define N_FWD    2
#define N_RELOAD 3

struct loc cur, go;
char title[TITLEMAX], gtitle[TITLEMAX];
char msg[96];
unsigned int v_top, v_sel = NONE;      /* the first line shown, the selected item */
unsigned char v_edit;                   /* the address line has the keys */
unsigned char hpos, hn;                 /* the history: the page shown, the entries */
static unsigned char nav, navto;        /* the fetch's kind (N_*), Back's or Forward's entry */
unsigned char fresh;                    /* the address line's text goes at the first key */
static char right[40];
static unsigned char hl;                /* the selection's colour, 0: reversed */
static unsigned int upto;               /* the lines drawn while a page comes */
static unsigned int tshow;
static unsigned char lastnet = 0xFF, dragging, sbf;   /* (V149) the scroll bar: held (1 the thumb, 2 3 an arrow); drawn again */
static unsigned int grab;               /* (the thumb's: where it was taken) */
static unsigned char wasbusy;
unsigned char rows = MROWS, rowh = MROWH;

#define LINES() (doc_lines + (doc_full && doc_done ? 2 : 0))

/*---------------------------------------------------------------- drawing */

static void status2(void)
{
    win_status(msg, right);
}

void __fastcall__ ui_status(const char *s)
{
    strncpy(msg, s, sizeof msg - 1);
    status2();
#ifdef GOPHER_TEST
    strcpy(line, "GO STATUS ");
    strcat(line, msg);
    gt_log(line);
#endif
}

static void set_title(void)
{
    strcpy(line, "Veranda Gopher");
    if (title[0]) {
        strcat(line, ": ");
        strcat(line, title);
    }
    win_title(line);
}

static void __fastcall__ draw_row(unsigned char r)
{
    unsigned int i = v_top + r, y = BODYY + r * rowh;
    unsigned char s = i == v_sel, t, g, c;
    if (i >= LINES()) {                 /* (past the end: cleared, quicker) */
        SetPattern(0);
        WRectangle(8, y, SBX * 8 - 1, y + rowh - 1);
        if (hl && doc_menu)
            theme_rect(0, SBX, BROW + (r << 1), 2, 0);
        return;
    }
    t = render(i);
    if (!doc_menu) {
        cells(1, y, WRAPW, TROWH, 0);
        return;
    }
    g = kind(t);
    cells(MTX, y, MTW, MROWH, s && !hl);
    glyph(8 + 3, y, g, MROWH, s && !hl ? GL_REV : 0);
    if (hl) {
        r = BROW + (r << 1);
        c = s ? hl : 0;
        theme_rect(0, 1, r, 2, c);
        theme_rect(1, 2, r, 2, kcol ? kcol : c);
        theme_rect(3, SBX - 3, r, 2, c);
    }
}

/* the scroll bar (V149, Sunroom: the SDK's): the lines shown, among
   all; drawn when that changed */
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

static void page(void)
{
    unsigned char r;
    for (r = 0; r < rows; ++r)
        draw_row(r);
    sbf = 1;
    scrollbar();
}

/* the right of the status bar: the modem, or the lines shown */
static void where(void)
{
    unsigned char s = net_on ? net_state() : NET_OFF;
    unsigned int all = LINES(), b;
    lastnet = s;
    if (!net_on)
        strcpy(right, "No network card");
    else if (s == NET_FAULT)
        strcpy(right, "The modem does not answer");
    else if (s != NET_READY)
        strcpy(right, "Looking for the modem ...");
    else if (!all)
        right[0] = 0;
    else {
        b = v_top + rows < all ? v_top + rows : all;
        strcpy(right, "Lines ");
        unum(right + strlen(right), v_top + 1);
        strcat(right, "-");
        unum(right + strlen(right), b);
        strcat(right, " of ");
        unum(right + strlen(right), all);
    }
}


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

/* the selection shown (scrolled to it) */
static void __fastcall__ select(unsigned int i)
{
    unsigned int old = v_sel;
    v_sel = i;
    if (i != NONE && i < v_top)
        scroll_to(i);
    else if (i != NONE && i >= v_top + rows)
        scroll_to((long)i - rows + 1);
    if (old != NONE && old >= v_top && old < v_top + rows)
        draw_row(old - v_top);
    if (i != NONE && i >= v_top && i < v_top + rows)
        draw_row(i - v_top);
}

/* the next item from i on (by -1 or 1); NONE */
static unsigned int __fastcall__ next_item(unsigned int i, signed char by)
{
    while (i < doc_lines) {
        if (selectable(i))
            return i;
        if (!i && by < 0)
            break;
        i += by;
    }
    return NONE;
}

static void __fastcall__ step(signed char by)
{
    unsigned int i;
    if (!doc_menu) {
        scroll_to((long)v_top + by);
        return;
    }
    if (v_sel == NONE)
        i = next_item(v_top, 1);
    else if (by < 0 && !v_sel)
        return;
    else
        i = next_item(v_sel + by, by);
    if (i != NONE)
        select(i);
    else if (by > 0)
        scroll_to((long)v_top + rows);  /* (the info lines after the last item) */
    else
        scroll_to(0);
}

/* PgUp, PgDn ...: the page scrolled, the selection kept in it */
static void __fastcall__ scroll_by(long by)
{
    scroll_to((long)v_top + by);
    if (doc_menu && (v_sel == NONE || v_sel < v_top || v_sel >= v_top + rows))
        select(next_item(v_top, 1) < v_top + rows ? next_item(v_top, 1) : NONE);
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

/* the fetch's page is the page now (its first bytes came, or the
   bookmarks): the history moved */
void g_first(void)
{
    if (gdl)
        return;
    here_saved();
    if (nav == N_NEW) {
        if (hn)
            ++hpos;
        if (hpos == HISTMAX) {
            hist_shift();
            --hpos;
        }
        hn = hpos + 1;
        memcpy(&H.l, &go, sizeof go);
        memcpy(H.title, gtitle, TITLEMAX);
        H.top = 0;
        H.sel = NONE;
        hist_put(hpos, &H);
    } else if (nav != N_RELOAD) {
        hpos = navto;
    }
    hist_get(hpos, &H);
    memcpy(&cur, &go, sizeof go);
    memcpy(title, gtitle, TITLEMAX);
    v_top = H.top;
    v_sel = H.sel;
    doc_clear(go.type == '1' || go.type == '7');
    rowh = doc_menu ? MROWH : TROWH;
    rows = doc_menu ? MROWS : TROWS;
    upto = v_top;
    set_title();
    dispBufferOn = ST_WR_FORE;         /* (the page cleared: its lines drawn as they come) */
    SetPattern(0);
    WRectangle(0, BODYY, SBX * 8 - 1, BODYY + TRACK * 8 - 1);
    theme_rect(0, SBX, BROW, TRACK, 0);
    scrollbar();
}

static void __fastcall__ fetch(unsigned char kind)
{
    nav = kind;
    if (!go.host[0]) {                  /* the bookmarks page */
        gdl = gfirst = 0;           /* (no fetch: the page from the table) */
        gerr = GE_OK;
        g_first();
        ov2(marks_page);
        doc_end();
        ui_done();
        return;
    }
    if (!net_on || net_state() == NET_FAULT)
        net_restart();
    strcpy(msg, "Connecting to ");
    strcat(msg, go.host);
    strcat(msg, " ...");
    ui_status(msg);
    g_start(0);
    toolbar();
}

static void __fastcall__ go_hist(unsigned char i, unsigned char kind)
{
    if (busy())
        return;
    hist_get(i, &H);
    memcpy(&go, &H.l, sizeof go);
    memcpy(gtitle, H.title, TITLEMAX);
    navto = i;
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
    go.host[0] = 0;
    go.type = '1';
    strcpy(gtitle, "Bookmarks");
    fetch(N_NEW);
}

static void download(void)
{
    card_name();
    if (xf_exists(xf_name)) {
        strcpy(line, xf_name);
        strcat(line, " is in /DOCUMENTS already.");
        if (!yesno(line, "Replace it?"))
            return;
    }
    if (!xf_open()) {
        message("The file cannot be made on the card:", xf_name);
        return;
    }
    if (!net_on || net_state() == NET_FAULT)
        net_restart();
    strcpy(msg, "Downloading ");
    strcat(msg, xf_name);
    strcat(msg, " ...");
    ui_status(msg);
    g_start(1);
    toolbar();
}

/* the search's query asked, put after a tab; 0: cancelled */
static unsigned char query(void)
{
    static char q[48];
    unsigned char n;
    q[0] = 0;
    strcpy(line, "Search ");
    strncat(line, gtitle[0] ? gtitle : go.host, 40);
    strcat(line, ":");
    if (!ask(line, q, 40) || !q[0])
        return 0;
    n = strlen(go.sel);
    if (n + strlen(q) + 2 > SELMAX)
        return 0;
    go.sel[n] = '\t';
    strcpy(go.sel + n + 1, q);
    return 1;
}

/* go's item opened as its kind wants */
static void open_go(void)
{
    char *p;
    switch (go.type) {
    case '0': case '1':
        break;
    case '7':
        if (!strchr(go.sel, '\t') && !query())
            return;
        break;
    case 'h':
        if (ishttp()) {
            p = go.sel + 4;
            if (strlen(p) <= 51)
                message("A web page (Veranda Gopher shows no web pages):", p);
            else {
                strncpy(line, p, 51);
                line[51] = 0;
                message(line, p + 51);
            }
            return;
        }
        go.type = '0';                  /* (an HTML file from the server: shown as text) */
        break;
    case '8': case 'T':
        strcpy(line, go.host);
        strcat(line, " port ");
        unum(line + strlen(line), go.port);
        message("A telnet session (Veranda Term can open it):", line);
        return;
    case '2':
        message("Veranda Gopher cannot open a CSO phone book.", "");
        return;
    default:
        card_name();
        strcpy(line, "Download ");
        strcat(line, xf_name);
        if (yesno(line, "to /DOCUMENTS?"))
            download();
        return;
    }
    fetch(N_NEW);
}

static void __fastcall__ follow(unsigned int i)
{
    char *p;
    if (busy())
        return;
    if (!doc_menu || i >= doc_lines)
        return;
    if (doc_type(i) == '3') {           /* an error line: its text in a box */
        doc_line(i);
        p = strchr(ln, '\t');
        if (p)
            *p = 0;
        message("The server says:", ln + 1);
        return;
    }
    if (!item(i)) {
        Beep();
        return;
    }
    open_go();
}

/*---------------------------------------------------------------- the address line */

static void __fastcall__ edit(unsigned char on)
{
    v_edit = on;
    if (on) {
        addr_of(&cur);
        fresh = 1;
    }
    field();
}

static void go_addr(void)
{
    if (busy())
        return;
    if (!parse()) {
        ui_status("Type an address: gopher://host[:port]/Tselector");
        return;
    }
    v_edit = 0;
    field();
    open_go();
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
        for (k = 0; line[k] && line[k] != '\r' && line[k] != '\n' && alen < sizeof abuf - 1; ++k)
            abuf[alen++] = line[k];
        abuf[alen] = 0;
    } else if (k >= 32 && k < 127 && alen < sizeof abuf - 1) {
        abuf[alen++] = k;
        abuf[alen] = 0;
    }
    field();
}

/*---------------------------------------------------------------- an end */

static const char *net_why(void)
{
    switch (gnet) {
    case NET_ERR: return "(refused, or no such host)";
    case NET_ETIMEOUT: return "(no answer)";
    case NET_EBADARG: return "(a bad host name)";
    case NET_ENOSOCK: return "(no free connection)";
    }
    return "(the modem's connection failed)";
}

void ui_done(void)
{
    unsigned long t;
    unsigned int r;
    unsigned char e = gerr;
    toolbar();
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
    } else if (gfirst || !go.host[0]) {         /* (a page, whole or not) */
        r = upto < doc_lines ? upto : doc_lines;
        doc_end();                      /* (the rows not drawn yet, and a "." line dropped) */
        if (r > doc_lines)
            r = doc_lines;
        if (r < v_top)
            r = v_top;
        for (; r < v_top + rows; ++r)
            draw_row(r - v_top);
        scrollbar();
        if (doc_menu && v_sel == NONE) {
            t = next_item(0, 1);
            if (t < rows)
                select(t);
        }
        where();
        strcpy(msg, cur.host[0] ? cur.host : "Bookmarks");
        strcat(msg, ": ");
        unum(msg + strlen(msg), doc_len);
        strcat(msg, " bytes");
        if (doc_full)
            strcat(msg, ", cut (too long)");
        if (e == GE_CANCEL)
            strcat(msg, ", stopped");
        ui_status(msg);
#ifdef GOPHER_TEST
        t_ov3(page_log);                /* (the test's overlay: room) */
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
    switch (e) {
    case GE_NET:
        strcpy(line, gfirst ? "The connection to " : "Could not connect to ");
        strncat(line, go.host, 30);
        if (gfirst)
            strcat(line, " failed");
        message(line, net_why());
        break;
    case GE_TIMEOUT:
        message("The server stopped sending.", "(nothing for 30 seconds: the connection was closed)");
        break;
    case GE_EMPTY:
        message("The server closed the connection", "without sending anything.");
        break;
    case GE_LOCAL:
        message("The file on the card failed:", xf_name);
        break;
    case GE_MODEM:
        message("The modem does not answer.", "(TexElec's Serial & ESP32 Network Card)");
        break;
    case GE_NOCARD:
        message("No network card was found.", "(TexElec's Serial & ESP32 Network Card)");
        break;
    }
    where();
    status2();
}

/* every pass: a page as it comes, the progress, the wheel, the scroll
   bar's drag, the modem's state */
void ui_tick(void)
{
    unsigned long bps;
    unsigned int lim, f;
    signed char w;
    unsigned char r;
    char *p;
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
    if (gbusy && !gdl && gfirst) {      /* the lines that have come, drawn */
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
        wasbusy = 1;
        if (ser_frames - tshow < 60)   /* (V211: once a second, the UI font's text some 60 ms) */
            return;
        tshow = ser_frames;
        if (!gfirst && !gdl)
            return;
        strcpy(msg, gdl ? "Downloading " : "Loading ");
        strcat(msg, gdl ? xf_name : go.host);
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
    r = net_on ? net_state() : NET_OFF;
    if (r != lastnet) {
        where();
        status2();
    }
}

#ifdef GOPHER_TEST
/* (V110) the timings: the page drawn 8 times, then scrolled a page down
   and up 4 times; their frames ("GO BENCH TEXT PAGE n", "... SCROLL n") */
static unsigned int t_now(void)
{
    unsigned int t;
    asm("sei");
    t = ser_frames;
    asm("cli");
    return t;
}

static void __fastcall__ t_log(const char *k, unsigned int t)
{
    strcpy(line, doc_menu ? "GO BENCH MENU " : "GO BENCH TEXT ");
    strcat(line, k);
    unum(line + strlen(line), t_now() - t);
    gt_log(line);
}

void t_bench(void)
{
    unsigned int t = t_now();
    unsigned char i;
    for (i = 0; i < 8; ++i)
        page();
    t_log("PAGE ", t);
    t = t_now();
    for (i = 0; i < 4; ++i) {
        scroll_by(rows - 1);
        scroll_by(-(rows - 1));
    }
    t_log("SCROLL ", t);
}
#endif

/*---------------------------------------------------------------- the menus */

static void m_about(void), m_quit(void), m_open(void), m_get(void), m_stop(void);
static void m_back(void), m_fwd(void), m_reload(void), m_home(void);
static void m_add(void), m_del(void);

struct item { const char *text; unsigned char type; void *p; };
struct menu2 { unsigned char top, bottom; unsigned int left, right; unsigned char flags; struct item i[2]; };
struct menu3 { unsigned char top, bottom; unsigned int left, right; unsigned char flags; struct item i[3]; };
struct menu4 { unsigned char top, bottom; unsigned int left, right; unsigned char flags; struct item i[4]; };

#define IH 14
/* (V149, Sunroom: "\x1f" a separator above the item, "\t" its key,
   right-aligned) */
static struct menu2 mapp = { 14, 14 + 2 * IH, 0, 0, VERTICAL | 2, {
    { "About Veranda Gopher", MENU_ACTION, m_about }, { "\x1f" "Quit", MENU_ACTION, m_quit } } };
static struct menu3 mfile = { 14, 14 + 3 * IH, 0, 0, VERTICAL | 3, {
    { "Open address\tCtrl L", MENU_ACTION, m_open }, { "Download", MENU_ACTION, m_get },
    { "\x1f" "Stop\tEsc", MENU_ACTION, m_stop } } };
static struct menu4 mgo = { 14, 14 + 4 * IH, 0, 0, VERTICAL | 4, {
    { "Back\tLeft", MENU_ACTION, m_back }, { "Forward\tRight", MENU_ACTION, m_fwd },
    { "Reload\tCtrl R", MENU_ACTION, m_reload }, { "\x1f" "Home (bookmarks)", MENU_ACTION, m_home } } };
static struct menu3 mmarks = { 14, 14 + 3 * IH, 0, 0, VERTICAL | 3, {
    { "Show bookmarks", MENU_ACTION, m_home }, { "\x1f" "Add this page", MENU_ACTION, m_add },
    { "Remove...", MENU_ACTION, m_del } } };
static struct menu4 mbar = { 0, 14, 0, 0, HORIZONTAL | UN_CONSTRAINED | 4, {
    { "Veranda Gopher", SUB_MENU, &mapp }, { "File", SUB_MENU, &mfile },
    { "Go", SUB_MENU, &mgo }, { "Bookmarks", SUB_MENU, &mmarks } } };
static const char *const barnames[4] = { "Veranda Gopher", "File", "Go", "Bookmarks" };
unsigned int barx[4], barl[4];          /* the bar's items' middles, the lists' lefts (the test clicks them) */

/* the lists' widths in the UI font; the kernel puts each under its bar
   item (vr_bar_end; Veranda FTP's layout) */
static void layout(void)
{
    static struct menu4 *const lists[4] = { (struct menu4 *)&mapp, (struct menu4 *)&mfile, &mgo, (struct menu4 *)&mmarks };
    struct menu4 *m;
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
    message("Veranda Gopher 1.0, MIT licence.", "A Gopher reader through the Wi-Fi modem.");
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

static void m_get(void)
{
    GotoFirstMenu();
    if (busy())
        return;
    if (v_sel != NONE && item(v_sel)) {
        if (go.type == 'h' && ishttp()) {
            open_go();
            return;
        }
        if (go.type == '7' || go.type == '8' || go.type == 'T' || go.type == '2') {
            ui_status("That item is not a file.");
            return;
        }
    } else if (cur.host[0]) {
        memcpy(&go, &cur, sizeof go);   /* (the page itself) */
    } else {
        ui_status("Select an item to download.");
        return;
    }
    download();
}

static void m_stop(void) { GotoFirstMenu(); g_cancel(); }
static void m_back(void) { GotoFirstMenu(); back(); }
static void m_fwd(void) { GotoFirstMenu(); forward(); }
static void m_reload(void) { GotoFirstMenu(); reload(); }
static void m_home(void) { GotoFirstMenu(); home(); }


static void m_add(void)
{
    GotoFirstMenu();
    if (!cur.host[0]) {
        ui_status("This is the bookmarks page.");
        return;
    }
    ov2(marks_add);
    if (marks_err == 2)
        message("There are 16 bookmarks already:", "remove one first (Bookmarks > Remove...).");
    else if (marks_err)
        message("GOPHER.MARKS cannot be written.", "(the bookmarks are in /VERANDA/.SYSTEM)");
    else {
        strcpy(msg, "Bookmark added: ");
        strcat(msg, title);
        ui_status(msg);
    }
}

static void m_del(void)
{
    GotoFirstMenu();
    if (busy())
        return;
    if (cur.host[0]) {
        home();
        ui_status("Select a bookmark (Up, Down), then Bookmarks > Remove...");
        return;
    }
    if (v_sel == NONE || v_sel < MARKS_HEAD || !item(v_sel)) {
        ui_status("Select a bookmark (Up, Down), then Bookmarks > Remove...");
        return;
    }
    if (!yesno("Remove the bookmark", gtitle))
        return;
    marks_i = v_sel - MARKS_HEAD;
    ov2(marks_del);
    if (marks_err)
        message("GOPHER.MARKS cannot be written.", "(the bookmarks are in /VERANDA/.SYSTEM)");
    reload();
}

/*---------------------------------------------------------------- input */

static void press(void)
{
    unsigned int x = mouseXPos, y = mouseYPosW, i;
    if (mouseData & 0x80)
        return;
#ifdef GOPHER_TEST
    strcpy(line, "GO PRESS ");
    unum(line + 9, x);
    strcat(line, " ");
    unum(line + strlen(line), y);
    gt_log(line);
#endif
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
    if (doc_menu && doc_type(i) == '3') {       /* an error line: its box */
        follow(i);
        return;
    }
    if (!selectable(i))
        return;
    select(i);
    if (!(keyMods & 1))
        follow(i);
}

static void key(void)
{
    unsigned char k = keyData, m = keyDataMods;
    if (v_edit) {
        field_key(k);
        return;
    }
    if (m & 2) {                        /* Ctrl */
        if (k == 12)                    /* L */
            edit(1);
        else if (k == 18)               /* R */
            reload();
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
        case KEY_UP: step(-1); break;
        case KEY_DOWN: step(1); break;
        }
        return;
    }
    switch (k) {
    case KEY_UP: step(-1); break;
    case KEY_DOWN: step(1); break;
    case KEY_PGUP: scroll_by(-(rows - 1)); break;
    case KEY_PGDN: scroll_by(rows - 1); break;
    case KEY_HOME: scroll_by(-30000); break;
    case KEY_END: scroll_by(30000); break;
    case 13: if (v_sel != NONE) follow(v_sel); break;
    case 8: back(); break;
    case KEY_ESC: g_cancel(); break;
    case KEY_TAB: edit(1); break;
    default:
        if (k > 32 && k < 127) {        /* a new address */
            edit(1);
            field_key(k);
        }
    }
}

void ui_start(void)
{
    dispBufferOn = ST_WR_FORE;          /* (the foreground only, as Veranda Edit: menus and boxes save what they cover) */
    SetPattern(0);
    WRectangle(0, 0, 639, 15);
    theme_load();
    theme_palette();                    /* (Look 2's palette: the chrome's and the selection's colours) */
    win_all("Veranda Gopher");
    theme_menus();
    layout();
    hl = theme_none() ? 0 : theme.hilite ? theme.hilite : SELECT;
    DoMenu((void *)&mbar, 0);
    strcpy((char *)curDirName, vr_cd(VR_DOCS));         /* downloads: /DOCUMENTS */
    ov2(marks_load);
    doc_clear(1);
    toolbar();
    where();
    home();
    otherPressVec = VR_FN(press);
    keyVector = VR_FN(key);
}
