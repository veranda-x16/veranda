/* Veranda FTP: the interface (overlay 1, appBank: mapped for good;
   DECISIONS V100).

   The window (Veranda Look 3 "Sunroom", sdk vrwin.h; V149): the menu
   bar (the kernel's), the title band (card rows 2-3: the site), the
   toolbar (4-5: the panes' folders in the UI font, the active one bold
   in the highlight), the body (6-57): the column heads (bold), then 25
   rows of 16 lines a pane and its scroll bar, the local pane at cards
   0-39, the remote at 40-79, the row selected in the theme's highlight
   (chrome in the other pane; reversed with the Classic theme); the
   status bar (58-59): what is happening at its left (a transfer's bytes
   and percentage), the connection or the speed at its right. The rows
   are 8 x 8 cells in the X16's CP437 font (PutCards), as View and
   Archive draw theirs. The panes are drawn by pane.c (overlay 3).

   Input: a click selects, a double click on a folder enters it (".."
   goes up), a click on a scroll bar scrolls; Tab the other pane; the arrows, PgUp, PgDn, Home, End;
   Return enters; F5 copies (a download from the remote pane, an upload
   from the local), F6 renames, F7 a new folder, F8 deletes, Esc stops a
   transfer.

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <vr.h>
#include <string.h>
#include <theme.h>
#include <vrnet.h>
#include <vrser.h>
#include <vrpath.h>
#include <vrwin.h>
#include "ftp.h"
#pragma code-name ("OVERLAY1")


unsigned char page, active;
char msg[96];
static char right[48];
static char title[40];
unsigned char hl;                       /* the selection's colour, 0: reversed */
static unsigned char lastnet = 0xFF;
static unsigned int tshow;

void net_restart(void);

/*---------------------------------------------------------------- drawing */

static void status2(void)
{
    win_status(msg, right);
}

void ui_status(const char *s)
{
    strncpy(msg, s, sizeof msg - 1);
    status2();
#ifdef FTP_TEST
    strcpy(line, "FTP STATUS ");
    strcat(line, msg);
    LogText(line);
#endif
}

static void conn_text(void)
{
    unsigned char s = net_on ? net_state() : NET_OFF;
    if (logged) {
        strcpy(right, "Connected: ");
        strncat(right, cur.host, 30);
    } else if (!net_on)
        strcpy(right, "No network card");
    else if (s == NET_READY)
        strcpy(right, "Not connected (modem ready)");
    else if (s == NET_FAULT)
        strcpy(right, "The modem does not answer");
    else
        strcpy(right, "Looking for the modem ...");
    lastnet = s;
}

static void heads(void)
{
    ov3(p_heads);                       /* (pane.c, V149) */
}

static void set_title(void)
{
    strcpy(title, "Veranda FTP");
    if (logged) {
        strcat(title, ": ");
        strncat(title, cur.name[0] ? cur.name : cur.host, 24);
    }
    win_title(title);
}

static void __fastcall__ draw_row(unsigned char p, unsigned char r)
{
    pa = p;
    pb = r;
    ov3(p_row);
}

void ui_pane(unsigned char p)
{
    pa = p;
    ov3(p_pane);
}

static void body(void)
{
    ov3(p_body);
}

void ui_redraw(void)
{
    body();
    heads();
    ui_pane(LOCAL);
    ui_pane(REMOTE);
}

/* the selection shown (scrolled to it if need be) */
static void show_sel(unsigned char p, unsigned char old)
{
    struct pane *q = &panes[p];
    if (q->sel < q->top) {
        q->top = q->sel;
    } else if (q->sel >= q->top + ROWS) {
        q->top = q->sel - ROWS + 1;
    } else {
        if (old >= q->top && old < q->top + ROWS)
            draw_row(p, old - q->top);
        draw_row(p, q->sel - q->top);
        return;
    }
    ui_pane(p);
}

static void __fastcall__ move(int by)
{
    struct pane *q = &panes[active];
    int s = (int)q->sel + by;
    unsigned char old = q->sel;
    if (!q->n)
        return;
    if (s < 0)
        s = 0;
    if (s >= q->n)
        s = q->n - 1;
    q->sel = s;
    show_sel(active, old);
}

static void __fastcall__ set_active(unsigned char p)
{
    unsigned char o = active;
    if (p == active)
        return;
    active = p;
    heads();
    if (panes[o].sel >= panes[o].top && panes[o].sel < panes[o].top + ROWS)
        draw_row(o, panes[o].sel - panes[o].top);
    if (panes[p].sel >= panes[p].top && panes[p].sel < panes[p].top + ROWS)
        draw_row(p, panes[p].sel - panes[p].top);
}

/*---------------------------------------------------------------- the operations */

static unsigned char busy(void)
{
    if (fop == OP_NONE)
        return 0;
    ui_status("Busy: wait for this to end (Esc stops a transfer).");
    Beep();
    return 1;
}

/* the selected entry of pane p into E; 0: none (or "..") */
static unsigned char __fastcall__ selected(unsigned char p)
{
    if (panes[p].sel >= panes[p].n)
        return 0;
    ent_get(p, panes[p].sel);
    return !(E.flags & E_UP);
}

static void local_list(void)
{
    ChDir((char *)curDirName);
    if (!local_read())
        ui_status("The card's folder cannot be read.");
    panes[LOCAL].top = panes[LOCAL].sel = 0;
    heads();
    ui_pane(LOCAL);
}

static void clear_remote(void)
{
    pane_clear(REMOTE);
    heads();
    ui_pane(REMOTE);
    set_title();
    conn_text();
    status2();
}

static void __fastcall__ start(unsigned char op, const char *what)
{
    strcpy(msg, what);
    strncat(msg, fa, 60);
    strcat(msg, " ...");
    status2();
    ftp_start(op);
}

static void connect(void)
{
    if (busy())
        return;
    if (!cur.host[0]) {
        page = 1;
        ov2(sites_show);
        return;
    }
    if (!net_on || net_state() == NET_FAULT)
        net_restart();
    if (!net_on) {
        message("No network card was found.", "(TexElec's Serial & ESP32 Network Card)");
        conn_text();
        status2();
        return;
    }
    strcpy(fa, cur.host);
    start(OP_CONNECT, "Connecting to ");
}

/* the card's name for a server's file (FAT and CMDR-DOS: no , : = * ? " < > | \ /) */
static void card_name(const char *s)
{
    unsigned char i;
    char c;
    for (i = 0; s[i] && i < NAMEMAX - 1; ++i) {
        c = s[i];
        xf_name[i] = strchr(",:=*?\"<>|\\/", c) ? '_' : c;
    }
    xf_name[i] = 0;
}

static unsigned char local_has(const char *name)
{
    unsigned char i, j;
    for (i = 0; i < panes[LOCAL].n; ++i) {
        ent_get(LOCAL, i);
        for (j = 0; E.name[j] && lower(E.name[j]) == lower(name[j]); ++j)
            ;
        if (!E.name[j] && !name[j])
            return 1;
    }
    return 0;
}

static void download(void)
{
    if (busy())
        return;
    if (!logged || !selected(REMOTE) || (E.flags & E_DIR)) {
        ui_status("Select a file on the server (the right pane) to download.");
        return;
    }
    strcpy(fa, E.name);
    xf_size = E.size;
    card_name(fa);
    if (local_has(xf_name)) {
        strcpy(line, xf_name);
        strcat(line, " is here already.");
        if (!yesno(line, "Replace it?"))
            return;
    }
    if (!xf_open(0)) {
        message("The file cannot be made on the card:", xf_name);
        return;
    }
    start(OP_RETR, "Downloading ");
}

static void upload(void)
{
    if (busy())
        return;
    if (!logged) {
        ui_status("Connect to a server first (Connection > Sites...).");
        return;
    }
    if (!selected(LOCAL) || (E.flags & E_DIR)) {
        ui_status("Select a file on the card (the left pane) to upload.");
        return;
    }
    strcpy(xf_name, E.name);
    strcpy(fa, E.name);
    if (!xf_open(1)) {
        message("The file cannot be read:", xf_name);
        return;
    }
    start(OP_STOR, "Uploading ");
}

static char name[NAMEMAX];

static void new_folder(void)
{
    if (busy())
        return;
    name[0] = 0;
    if (!ask(active == REMOTE ? "A new folder on the server:" : "A new folder on the card:", name, 40) || !name[0])
        return;
    if (active == REMOTE) {
        if (!logged)
            return;
        strcpy(fa, name);
        start(OP_MKD, "Making ");
        return;
    }
    ChDir((char *)curDirName);
    if (MkDir(name))
        message("The folder could not be made:", name);
    local_list();
}

static void delete(void)
{
    unsigned char dir, e;
    if (busy())
        return;
    if (!selected(active)) {
        ui_status("Select what to delete.");
        return;
    }
    dir = E.flags & E_DIR;
    strcpy(name, E.name);
    strcpy(line, dir ? "Delete the folder " : "Delete ");
    strncat(line, name, 30);
    if (!yesno(line, active == REMOTE ? "on the server?" : "on the card?"))
        return;
    if (active == REMOTE) {
        strcpy(fa, name);
        start(dir ? OP_RMD : OP_DELE, "Deleting ");
        return;
    }
    ChDir((char *)curDirName);
    e = dir ? RmDir(name) : FDelete(name);
    if (e)
        message(dir ? "The folder could not be deleted" : "The file could not be deleted:",
                dir ? "(is it empty?)" : name);
    local_list();
}

static void rename_(void)
{
    if (busy())
        return;
    if (!selected(active)) {
        ui_status("Select what to rename.");
        return;
    }
    strcpy(fa, E.name);
    strcpy(name, E.name);
    if (!ask("The new name:", name, 40) || !name[0] || !strcmp(name, fa))
        return;
    if (active == REMOTE) {
        strcpy(fb, name);
        start(OP_RENAME, "Renaming ");
        return;
    }
    ChDir((char *)curDirName);
    if (FRename(fa, name))
        message("It could not be renamed:", fa);
    local_list();
}

static void refresh(void)
{
    if (busy())
        return;
    if (active == LOCAL)
        local_list();
    else if (logged) {
        fa[0] = 0;
        start(OP_LIST, "Listing");
    }
}

/* a double click or Return: into a folder */
static void open_sel(void)
{
    char *p;
    unsigned char n;
    struct pane *q = &panes[active];
    if (q->sel >= q->n)
        return;
    ent_get(active, q->sel);
    if (!(E.flags & (E_DIR | E_LINK)))
        return;
    if (active == REMOTE) {
        if (busy())
            return;
        strcpy(fa, E.name);
        start(OP_CWD, "Opening ");
        return;
    }
    strcpy(line, (char *)curDirName);
    if (E.flags & E_UP) {
        p = strrchr(line, '/');
        if (!p)
            return;
        p[p == line] = 0;               /* ("/A" -> "/") */
    } else {
        n = strlen(line);
        if (n + strlen(E.name) + 2 > 63) {
            ui_status("That folder's path is too long.");
            return;
        }
        if (n > 1)
            line[n++] = '/';
        strcpy(line + n, E.name);
    }
    if (ChDir(line)) {
        ChDir((char *)curDirName);
        ui_status("That folder cannot be opened.");
        return;
    }
    strcpy((char *)curDirName, line);
    local_list();
}

/*---------------------------------------------------------------- an op's end */

static const char *net_why(void)
{
    switch (fnet) {
    case NET_ERR: return "(refused, or no such host)";
    case NET_ETIMEOUT: return "(no answer)";
    case NET_EBADARG: return "(a bad host name)";
    case NET_ENOSOCK: return "(no free connection)";
    }
    return "(the modem's connection failed)";
}

void ui_done(unsigned char op)
{
    unsigned long t;
    unsigned char e = ferr;
    if (e == FE_OK) {
        switch (op) {
        case OP_CONNECT:
            set_title();
            conn_text();
            /* (fall through) */
        case OP_LIST:
        case OP_CWD:
            heads();
            ui_pane(REMOTE);
            if (op == OP_CONNECT)
                set_active(REMOTE);
            strcpy(msg, cur.host);
            strcat(msg, " ");
            strncat(msg, rpath, 40);
            strcat(msg, ": ");
            unum(msg + strlen(msg), panes[REMOTE].n - 1);
            strcat(msg, " entries");
            if (rl_unparsed) {
                strcat(msg, ", ");
                unum(msg + strlen(msg), rl_unparsed);
                strcat(msg, " lines not understood");
            }
            ui_status(msg);
            return;
        case OP_RETR:
        case OP_STOR:
            t = ser_frames - xf_t0;
            strcpy(msg, op == OP_RETR ? "Downloaded " : "Uploaded ");
            strncat(msg, fa, 40);
            strcat(msg, ": ");
            unum(msg + strlen(msg), xf_pos);
            strcat(msg, " bytes in ");
            unum(msg + strlen(msg), (t + 30) / 60);
            strcat(msg, " s");
            conn_text();
            ui_status(msg);
            if (op == OP_RETR)
                local_list();
            else
                ftp_start(OP_LIST);
            return;
        case OP_QUIT:
            clear_remote();
            ui_status("Disconnected.");
            return;
        }
        ui_status("Done.");
        ftp_start(OP_LIST);             /* (MKD, DELE, RMD, RENAME: the listing again) */
        return;
    }
    if (e == FE_CANCEL)
        ui_status("Stopped.");
    else {
        strcpy(msg, "Failed.");
        status2();
    }
    switch (e) {
    case FE_REPLY:
        message(op == OP_CONNECT ? (logged ? "The server refused:" : "The login failed:") :
                op == OP_RETR ? "The download failed:" : op == OP_STOR ? "The upload failed:" :
                "The server refused:", ftext);
        break;
    case FE_TIMEOUT:
        message("The server did not answer in time.", "(the connection was closed)");
        break;
    case FE_NET:
        strcpy(line, "Could not connect to ");
        strncat(line, cur.host, 30);
        message(op == OP_CONNECT ? line : "The data connection failed", net_why());
        break;
    case FE_CLOSED:
        message("The server closed the connection.", "");
        break;
    case FE_PROTO:
        message("The server's reply made no sense:", ftext);
        break;
    case FE_LOCAL:
        message("The file on the card failed:", xf_name);
        break;
    case FE_MODEM:
        message(net_on ? "The modem does not answer." : "No network card was found.",
                "(TexElec's Serial & ESP32 Network Card)");
        break;
    }
    if (op == OP_RETR)
        local_list();
    if (!logged)
        clear_remote();
}

/* every pass: the transfer's progress, the modem's state */
void ui_tick(void)
{
    unsigned long f, bps;
    char *p;
    if (xfer_data) {
        if (ser_frames - tshow < 20)
            return;
        tshow = ser_frames;
        strcpy(msg, xf_up ? "Uploading " : "Downloading ");
        strncat(msg, fa, 20);
        strcat(msg, ": ");
        p = unum(msg + strlen(msg), xf_pos);
        if (xf_size) {
            strcpy(p, " of ");
            p = unum(p + 4, xf_size);
            strcpy(p, " bytes (");
            p = unum(p + 8, pa = xf_pos * 100 / xf_size);
            strcpy(p, "%)");
        } else
            strcpy(p, " bytes");
        f = ser_frames - xf_t0;
        bps = f ? xf_pos * 60 / f : 0;
        p = unum(right, bps / 1024);
        *p++ = '.';
        p = unum(p, bps * 10 / 1024 % 10);
        strcpy(p, " KB/s");
        status2();
        if (xf_size)
            ov3(p_progress);            /* (V149: a bar in the status bar, pa) */
        return;
    }
    if (!logged && fop == OP_NONE && (net_on ? net_state() : NET_OFF) != lastnet) {
        conn_text();
        status2();
    }
}

/*---------------------------------------------------------------- the menus */

static void m_about(void), m_quit(void), m_sites(void), m_connect(void), m_disconnect(void);
static void m_get(void), m_put(void), m_mkdir(void), m_del(void), m_ren(void), m_refresh(void);
static void m_name(void), m_size(void), m_date(void), m_other(void);

struct item { const char *text; unsigned char type; void *p; };
struct menu2 { unsigned char top, bottom; unsigned int left, right; unsigned char flags; struct item i[2]; };
struct menu3 { unsigned char top, bottom; unsigned int left, right; unsigned char flags; struct item i[3]; };
struct menu4 { unsigned char top, bottom; unsigned int left, right; unsigned char flags; struct item i[4]; };
struct menu6 { unsigned char top, bottom; unsigned int left, right; unsigned char flags; struct item i[6]; };

/* Sunroom's lists (V146, V149): $1F in front of an item starts a group
   (a dotted line above it), a key after a tab is shown at the right: the
   keys key() takes (F5 copies from the active pane: a download from the
   server's, an upload from the card's) */
#define IH 14
static struct menu2 mftp = { 14, 14 + 2 * IH, 0, 0, VERTICAL | 2, {
    { "About Veranda FTP", MENU_ACTION, m_about }, { "\x1f" "Quit", MENU_ACTION, m_quit } } };
static struct menu3 mconn = { 14, 14 + 3 * IH, 0, 0, VERTICAL | 3, {
    { "Sites...", MENU_ACTION, m_sites }, { "\x1f" "Connect", MENU_ACTION, m_connect },
    { "Disconnect", MENU_ACTION, m_disconnect } } };
static struct menu6 mfile = { 14, 14 + 6 * IH, 0, 0, VERTICAL | 6, {
    { "Download\tF5", MENU_ACTION, m_get }, { "Upload\tF5", MENU_ACTION, m_put },
    { "\x1f" "New folder...\tF7", MENU_ACTION, m_mkdir }, { "Delete\tF8", MENU_ACTION, m_del },
    { "Rename...\tF6", MENU_ACTION, m_ren }, { "\x1f" "Refresh", MENU_ACTION, m_refresh } } };
static struct menu4 mview = { 14, 14 + 4 * IH, 0, 0, VERTICAL | 4, {
    { "By name", MENU_ACTION, m_name }, { "By size", MENU_ACTION, m_size },
    { "By date", MENU_ACTION, m_date }, { "\x1f" "Other pane\tTab", MENU_ACTION, m_other } } };
static struct menu4 mbar = { 0, 14, 0, 0, HORIZONTAL | UN_CONSTRAINED | 4, {
    { "Veranda FTP", SUB_MENU, &mftp }, { "Connection", SUB_MENU, &mconn },
    { "File", SUB_MENU, &mfile }, { "View", SUB_MENU, &mview } } };
static const char *const barnames[4] = { "Veranda FTP", "Connection", "File", "View" };
unsigned int barx[4], barl[4];          /* the bar's items' middles, the lists' lefts (the test clicks them) */

/* the lists' widths in the UI font (the menus' font, theme_menus); the
   kernel puts each under its bar item (vr_bar_end: where the items are;
   Term's layout) */
static void layout(void)
{
    static unsigned int *const lefts[4] = { &mftp.left, &mconn.left, &mfile.left, &mview.left };
    static unsigned int *const rights[4] = { &mftp.right, &mconn.right, &mfile.right, &mview.right };
    static struct item *const items[4] = { mftp.i, mconn.i, mfile.i, mview.i };
    static const unsigned char nitems[4] = { 2, 3, 6, 4 };
    unsigned int b, w, m;
    unsigned char i, j, c;
    const char *p;
    for (i = 0; i < 4; ++i) {
        b = vr_bar_end(barnames, i);
        barx[i] = (b + vr_bar_end(barnames, i + 1)) >> 1;
        barl[i] = b;
        UseFont(FONT_UI);
        for (m = 0, j = 0; j < nitems[i]; ++j) {
            for (w = 0, p = items[i][j].text; (c = *p) != 0; ++p)   /* (a tab 24, $1F nothing: */
                w += c == 9 ? 24 : c == 0x1F ? 0 : GetCharWidth(c);  /* shell/look3.c's mwidth) */
            if (w > m)
                m = w;
        }
        *lefts[i] = b;
        *rights[i] = b + m + 16;
    }
    mbar.right = vr_bar_end(barnames, 4);
    UseSystemFont();
}

static void panes_page(void)
{
    if (page) {
        page = 0;
        ui_redraw();
    }
}

static void m_about(void)
{
    GotoFirstMenu();
    message("Veranda FTP 1.0, MIT licence. Its FTP code:", "Packet16, by Marcin Spoczynski.");
}

static void m_quit(void)
{
    GotoFirstMenu();
    if (fop != OP_NONE && !yesno("Something is still under way.", "Quit anyway?"))
        return;
    ftp_drop();
    net_stop();
    EnterDeskTop();
}

static void m_sites(void)
{
    GotoFirstMenu();
    page = 1;
    ov2(sites_show);
}

static void m_connect(void)
{
    GotoFirstMenu();
    panes_page();
    connect();
}

static void m_disconnect(void)
{
    GotoFirstMenu();
    if (fop != OP_NONE) {
        ftp_drop();
        clear_remote();
        ui_status("Disconnected.");
    } else if (logged) {
        fa[0] = 0;
        start(OP_QUIT, "Disconnecting");
    }
}

static void m_get(void) { GotoFirstMenu(); panes_page(); download(); }
static void m_put(void) { GotoFirstMenu(); panes_page(); upload(); }
static void m_mkdir(void) { GotoFirstMenu(); panes_page(); new_folder(); }
static void m_del(void) { GotoFirstMenu(); panes_page(); delete(); }
static void m_ren(void) { GotoFirstMenu(); panes_page(); rename_(); }
static void m_refresh(void) { GotoFirstMenu(); panes_page(); refresh(); }

static void __fastcall__ sort(unsigned char by)
{
    GotoFirstMenu();
    sortby = by;
    pane_sort(LOCAL);
    pane_sort(REMOTE);
    panes[LOCAL].sel = panes[LOCAL].top = panes[REMOTE].sel = panes[REMOTE].top = 0;
    page = 1;
    panes_page();
}

static void m_name(void) { sort(SORT_NAME); }
static void m_size(void) { sort(SORT_SIZE); }
static void m_date(void) { sort(SORT_DATE); }
static void m_other(void) { GotoFirstMenu(); panes_page(); set_active(!active); }

/*---------------------------------------------------------------- input */

static void after_sites(void)
{
    if (!page) {                        /* (the page closed) */
        ui_redraw();
        if (sites_go) {
            sites_go = 0;
            connect();
        }
    }
}

static void press(void)
{
    unsigned int x = mouseXPos, y = mouseYPosW;
    unsigned char p, i, old;
    if (mouseData & 0x80)
        return;
#ifdef FTP_TEST
    strcpy(line, "FTP PRESS ");
    unum(line + 10, x);
    strcat(line, " ");
    unum(line + strlen(line), y);
    LogText(line);
#endif
    if (page) {
        ov2(sites_press);
        after_sites();
        return;
    }
    p = x >= 320;
    if (y >= 32 && y < LISTY) {
        set_active(p);
        return;
    }
    if (y < LISTY || y >= LISTEND)
        return;
    if ((x >> 3) - (p ? 40 : 0) >= 38) {        /* (V149) the scroll bar */
        set_active(p);
        pa = p;
        ov3(p_scroll);
        return;
    }
    i = panes[p].top + (y - LISTY) / ROWH;
    set_active(p);
    if (i >= panes[p].n)
        return;
    if (i == panes[p].sel && dblClickCount) {
        dblClickCount = 0;
        open_sel();
        return;
    }
    dblClickCount = CLICK_COUNT;
    old = panes[p].sel;
    panes[p].sel = i;
    show_sel(p, old);
}

static void key(void)
{
    unsigned char k = keyData;
    if (page) {
        ov2(sites_key);
        after_sites();
        return;
    }
    switch (k) {
    case KEY_TAB: set_active(!active); break;
    case KEY_UP: move(-1); break;
    case KEY_DOWN: move(1); break;
    case KEY_PGUP: move(-(ROWS - 1)); break;
    case KEY_PGDN: move(ROWS - 1); break;
    case KEY_HOME: move(-MAXE); break;
    case KEY_END: move(MAXE); break;
    case 13: open_sel(); break;
    case KEY_F5: if (active == REMOTE) download(); else upload(); break;
    case KEY_F6: rename_(); break;
    case KEY_F7: new_folder(); break;
    case KEY_F8: delete(); break;
    case KEY_ESC: ftp_cancel(); break;
    }
}

void ui_start(void)
{
    dispBufferOn = ST_WR_FORE | ST_WR_BACK;
    SetPattern(0);
    WRectangle(0, 0, 639, 15);
    theme_load();
    theme_palette();                    /* (Look 2's palette: the chrome's and the selection's colours) */
    win_all("Veranda FTP");
    theme_menus();
    layout();
    hl = theme_none() ? 0 : theme.hilite ? theme.hilite : SELECT;
    DoMenu((void *)&mbar, 0);
    strcpy((char *)curDirName, vr_cd(VR_DOCS));         /* the local pane: /DOCUMENTS */
    ov2(sites_load);
    if (sites_n)
        ov2(sites_pick);
    conn_text();
    ChDir((char *)curDirName);
    local_read();
    ui_redraw();
    ui_status("Connection > Sites... chooses a server.");
    otherPressVec = VR_FN(press);
    keyVector = VR_FN(key);
}
