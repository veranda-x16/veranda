/* Dex: an address book, a Veranda desk accessory in C.

   Cards (a name, a phone number or a BBS's host:port, an e-mail address,
   a postal address, a note) kept in a record file in the system folder
   ("Dex Cards", class "Dex Cards V1.0": a record a card, its five fields
   as 0-terminated strings), in name order. The window: a search field
   (search as you type: the cards whose name, phone or e-mail holds the
   text), an alphabet bar (a letter jumps to the first name from it), the
   list, and the card shown in five fields that are edited in place: Save
   keeps it (a new card, or the one selected), New empties the fields,
   Delete takes the card out (asked first). Copy puts the card on the
   clipboard (the Text Scrap, a line a field: scrap.h); Export writes
   DEX.CSV in the application's folder (RFC 4180: a header line, then a
   line a card, CR LF; Veranda Calc opens it), Import reads it back (the
   cards added). Connect, on a card whose phone field is a host (a letter,
   a dot or a colon in it): Veranda Term starts in place of the program
   underneath (asked first), with the document DEX.TEL ("name|host:port",
   Term's address book line) written next to it: GetFile with ST_LD_DATA,
   DECISIONS V48 and V56.

   Keys: Tab moves between the search and the fields, Return saves, the
   up and down arrows move the selection, Escape closes.

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <vr.h>
#include <string.h>
#include <scrap.h>
#include <vrwin.h>
#include <vralert.h>
#include "daui.h"

#define MAXC    100
#define NL      28
#define PL      32
#define EL      32
#define AL      48
#define TL      40
struct card {
    char name[NL + 1], phone[PL + 1], email[EL + 1], addr[AL + 1], note[TL + 1];
};
#define PERBANK (8192 / sizeof(struct card))
#define MAPBANK(b) (*(volatile unsigned char *)0 = (b))

#define W       560
#define LX      8               /* the list (in the window): its rows */
#define LY      56
#define LW      192             /* (then its scroll bar, 16) */
#define RH      16
#define FX      320             /* the fields */
#define FY      72
#define FW      232
#define TB      16              /* (V148) the toolbar (card rows 2-5, chrome): */
#define TBH     32
#define TABX    8               /*   the alphabet bar */
#define TABY    24
#define FINDX   440             /*   "Find", the search field */
#define FILE    "Dex Cards"

static unsigned char bank0;
static unsigned char ncards;
static char names[MAXC][NL + 1];        /* (the names also here: the sort, the list) */
static unsigned char ord[MAXC];         /* the cards in name order */
static unsigned char vis[MAXC], nvis;   /* those the search finds */
static unsigned char top, sel;          /* the list's first row; the selection (in vis), $FF none */
static unsigned char editing;           /* the card in the fields, $FF a new one */
static unsigned char nrows, focus;      /* focus: 0 the search, 1-5 the fields */
static unsigned int fs, by1, by2;       /* the fields' spacing, the button rows */
static struct card cur, tmp;
static char query[24];
static char line[96];
static unsigned char rec[sizeof(struct card)];
static struct vrscroll bar;             /* (V148) the list's scroll bar */
extern const unsigned char vr_icon[128];        /* (alerticon.c: Dex's icon) */

static struct field fields[6];
static const char *const labels[5] = { "Name", "Phone, host", "E-mail", "Address", "Note" };
static char *const bufs[6] = { query, cur.name, cur.phone, cur.email, cur.addr, cur.note };
static const unsigned char maxes[6] = { 20, NL, PL, EL, AL, TL };

#define NBTN 7
static const char *const btext[NBTN] = { "Save", "New", "Delete", "Copy", "Connect", "Export", "Import" };

#ifdef DEX_TEST
void da_test_start(void);
#endif

static char logl[64];
static void say(const char *s)
{
    *ui_put(ui_put(logl, "DEX "), s) = 0;
    LogText(logl);
}

static struct card *cp(unsigned char i)
{
    MAPBANK(bank0 + i / PERBANK);
    return (struct card *)(0xA000 + (i % PERBANK) * sizeof(struct card));
}

static void get(unsigned char i, struct card *c)
{
    memcpy(c, cp(i), sizeof(struct card));
}

static void put(unsigned char i, const struct card *c)
{
    memcpy(cp(i), c, sizeof(struct card));
    strcpy(names[i], c->name);
}

static unsigned char lower(unsigned char c)
{
    return c >= 'A' && c <= 'Z' ? c + 32 : c;
}

static int icmp(const char *a, const char *b)
{
    while (*a && lower(*a) == lower(*b)) {
        ++a;
        ++b;
    }
    return lower(*a) - lower(*b);
}

static unsigned char has(const char *s, const char *q)
{
    unsigned char i;
    for (; *s; ++s) {
        for (i = 0; q[i] && lower(s[i]) == lower(q[i]); ++i)
            ;
        if (!q[i])
            return 1;
    }
    return !*q;
}

/* ord: the cards by name; vis: those the search finds */
static void sort(void)
{
    unsigned char i, j, t;
    for (i = 0; i < ncards; ++i)
        ord[i] = i;
    for (i = 1; i < ncards; ++i) {
        t = ord[i];
        for (j = i; j && icmp(names[ord[j - 1]], names[t]) > 0; --j)
            ord[j] = ord[j - 1];
        ord[j] = t;
    }
}

static void filter(void)
{
    unsigned char i, k;
    struct card *c;
    nvis = 0;
    for (i = 0; i < ncards; ++i) {
        k = ord[i];
        if (query[0]) {
            c = cp(k);
            if (!has(c->name, query) && !has(c->phone, query) && !has(c->email, query))
                continue;
        }
        vis[nvis++] = k;
    }
}

/*---------------------------------------------------------------
  the file
 ---------------------------------------------------------------*/
static unsigned char pack(unsigned char i)
{
    unsigned char *p = rec;
    struct card *c = cp(i);
    p = (unsigned char *)ui_put((char *)p, c->name) + 1;
    p = (unsigned char *)ui_put((char *)p, c->phone) + 1;
    p = (unsigned char *)ui_put((char *)p, c->email) + 1;
    p = (unsigned char *)ui_put((char *)p, c->addr) + 1;
    p = (unsigned char *)ui_put((char *)p, c->note) + 1;
    return p - rec;
}

static void unpack(unsigned int n)
{
    static char *const f[5] = { cur.name, cur.phone, cur.email, cur.addr, cur.note };
    static const unsigned char m[5] = { NL, PL, EL, AL, TL };
    unsigned int i = 0;
    unsigned char k, j;
    memset(&cur, 0, sizeof cur);
    for (k = 0; k < 5; ++k) {
        for (j = 0; i < n && rec[i]; ++i)
            if (j < m[k])
                f[k][j++] = rec[i];
        ++i;
    }
}

static void load(void)
{
    unsigned char i, n;
    ncards = 0;
    if (ui_rec_busy())
        return;
    sys_enter();
    if (OpenRecordFile(FILE) == 0) {
        n = usedRecords;
        for (i = 0; i < n && ncards < MAXC; ++i) {
            if (PointRecord(i) || ReadRecord(rec, sizeof rec))
                continue;
            unpack(r7 - (unsigned int)rec);
            if (cur.name[0])
                put(ncards++, &cur);
        }
        CloseRecordFile();
    }
    sys_leave();
    memset(&cur, 0, sizeof cur);
}

/* the whole book written again (records 0 .. n - 1, in name order) */
static unsigned char save_all(void)
{
    unsigned char e, i;
    if (ui_rec_busy()) {
        ui_msg("Dex cannot write its cards now.", "The program underneath has a document open.");
        return 1;
    }
    sys_enter();
    e = ui_rec_open(FILE, "Dex Cards V1.0", "Dex's address cards.");
    if (!e) {
        while (usedRecords && !e) {
            PointRecord(0);
            e = DeleteRecord();
        }
        for (i = 0; i < ncards && !e; ++i) {
            e = AppendRecord();
            if (!e)
                e = WriteRecord(rec, pack(ord[i]));
        }
        if (CloseRecordFile() && !e)
            e = DOS_ERROR;
    }
    sys_leave();
    if (e)
        ui_msg("The cards could not be written.", "Dex keeps them in the system folder.");
    else {
        ui_num(ui_put(line, "SAVED "), ncards, 0);
        say(line);
    }
    return e;
}

/*---------------------------------------------------------------
  drawing
 ---------------------------------------------------------------*/
static void status(const char *s)
{
    unsigned int x = ui_x0 + LX, y = ui_y0 + LY + nrows * RH + 8;
    ui_clear(x, y, LW + 16, RH);
    ui_textw(s, x + 2, y + 11, LW + 14);
}

static void count(void)
{
    char *p = ui_num(line, nvis, 0);
    p = ui_put(p, nvis == 1 ? " card" : " cards");
    if (query[0])
        ui_put(p, " found");
    status(line);
}

static void draw_row(unsigned char r)
{
    unsigned int x = ui_x0 + LX, y = ui_y0 + LY + r * RH;
    unsigned char i = top + r;
    ui_clear(x + 1, y, LW - 2, RH);
    ui_color(x, y, LW, RH, i == sel && i < nvis ? C_SEL : C_NONE);
    if (i < nvis)
        ui_textw(names[vis[i]], x + 6, y + 11, LW - 12);
}

static void draw_list(void)
{
    unsigned char r;
    for (r = 0; r < nrows; ++r)
        draw_row(r);
    bar.first = top;
    bar.total = nvis;
    vr_scroll(&bar);
    count();
}

static void draw_tabs(void)
{
    unsigned char i, on = 0xFF;
    char s[2];
    unsigned int x;
    if (sel < nvis)
        on = lower(names[vis[sel]][0]) - 'a';
    s[1] = 0;
    for (i = 0; i < 26; ++i) {
        x = ui_x0 + TABX + i * 16;
        ui_clear(x, ui_y0 + TABY, 16, RH);
        ui_color(x, ui_y0 + TABY, 16, RH, i == on ? C_SEL : C_GREY);
        s[0] = 'A' + i;
        ui_textc(s, x, 16, ui_y0 + TABY + 11);
    }
}

static void draw_field(unsigned char k)
{
    ui_field(&fields[k], focus == k);
}

static void draw_fields(void)
{
    unsigned char k;
    for (k = 1; k < 6; ++k)
        draw_field(k);
}

static void draw_card_title(void)
{
    unsigned int x = ui_x0 + 232, y = ui_y0 + 52;
    ui_clear(x, y, W - 240, 14);
    ui_bold(editing == 0xFF ? "New card" : "Card", x, y + 11);
}

static unsigned int bx(unsigned char i)
{
    return ui_x0 + 232 + (i < 4 ? i * 80 : (i - 4) * 104);
}

static unsigned int bw(unsigned char i)
{
    return i < 4 ? 72 : 96;
}

static unsigned int by(unsigned char i)
{
    return ui_y0 + (i < 4 ? by1 : by2);
}

static void draw(void)
{
    unsigned char i;
    ui_window("Dex", W, ui_h);
    /* (V148, Sunroom) the toolbar: the alphabet, the search */
    ui_color(ui_x0, ui_y0 + TB, W, TBH, C_GREY);
    WHorizontalLine(0xFF, ui_x0, ui_x0 + W - 1, ui_y0 + TB + TBH - 1);
    ui_text("Find", ui_x0 + FINDX, ui_y0 + TABY + 11);
    ui_color(fields[0].x, fields[0].y, fields[0].w, UI_BH, C_NONE);
    draw_field(0);
    draw_tabs();
    WFrameRectangle(0xFF, ui_x0 + LX - 1, ui_y0 + LY - 1, ui_x0 + LX + LW, ui_y0 + LY + nrows * RH);
    WVerticalLine(0xFF, ui_x0 + 224, ui_y0 + TB + TBH + 4, ui_y0 + ui_h - 8);
    for (i = 0; i < 5; ++i)
        ui_text(labels[i], ui_x0 + 232, ui_y0 + FY + i * fs + 11);
    draw_card_title();
    draw_fields();
    for (i = 0; i < NBTN; ++i)
        ui_button(bx(i), by(i), bw(i), btext[i], C_BTN);
    draw_list();
}

/*---------------------------------------------------------------
  actions
 ---------------------------------------------------------------*/
static void set_focus(unsigned char k)
{
    unsigned char o = focus;
    focus = k;
    draw_field(o);
    draw_field(k);
}

static void show(void)
{
    if (sel < nvis) {
        editing = vis[sel];
        get(editing, &cur);
    } else {
        editing = 0xFF;
        memset(&cur, 0, sizeof cur);
    }
    draw_card_title();
    draw_fields();
    draw_tabs();
}

/* the list scrolled so that the selection shows */
static void reveal(void)
{
    if (sel != 0xFF && sel < nvis) {
        if (sel < top)
            top = sel;
        else if (sel >= top + nrows)
            top = sel - nrows + 1;
    }
    if (top && top + nrows > nvis)
        top = nvis > nrows ? nvis - nrows : 0;
}

/* after a change: sorted, found, the card k selected if it shows */
static void refresh(unsigned char k)
{
    unsigned char i;
    sort();
    filter();
    sel = 0xFF;
    for (i = 0; i < nvis; ++i)
        if (vis[i] == k)
            sel = i;
    reveal();
    draw_list();
    show();
}

static void search(void)
{
    filter();
    top = 0;
    sel = nvis ? 0 : 0xFF;
    draw_list();
    show();
    *ui_num(ui_put(ui_put(ui_put(line, "FIND "), query), " "), nvis, 0) = 0;
    say(line);
}

static void b_save(void)
{
    unsigned char k = editing;
    if (!cur.name[0]) {
        ui_msg("A card needs a name.", "Type one in the Name field.");
        return;
    }
    if (k == 0xFF) {
        if (ncards >= MAXC) {
            ui_msg("Dex is full.", "It keeps 100 cards at most.");
            return;
        }
        k = ncards++;
    }
    put(k, &cur);
    sort();
    if (save_all() == 0)
        status("Saved.");
    query[0] = 0;
    draw_field(0);
    refresh(k);
}

static void b_new(void)
{
    sel = 0xFF;
    draw_list();
    show();
    set_focus(1);
}

static void b_delete(void)
{
    unsigned char k = editing, i;
    if (k == 0xFF)
        return;
    if (!ui_ask("Delete this card?", names[k]))
        return;
    --ncards;
    if (k != ncards) {                  /* the last card takes its place */
        get(ncards, &cur);
        put(k, &cur);
    }
    for (i = 0; i < ncards; ++i)
        ord[i] = i;
    sort();
    save_all();
    say("DELETED");
    filter();
    if (sel >= nvis)
        sel = nvis ? nvis - 1 : 0xFF;
    reveal();
    draw_list();
    show();
}

static void b_copy(void)
{
    static char t[sizeof(struct card) + 8];
    char *p = t;
    unsigned char k;
    for (k = 1; k < 6; ++k)
        if (bufs[k][0]) {
            p = ui_put(p, bufs[k]);
            *p++ = '\n';
        }
    if (p == t)
        return;
    if (scrap_put_text(t, p - t)) {
        ui_msg("The card could not be copied.", "The clipboard could not be written.");
        return;
    }
    say("COPIED");
    status("Copied to the clipboard.");
}

/* CSV: a field, quoted if it must be */
static unsigned char csvh;
static void csv_field(const char *s, unsigned char last)
{
    unsigned char q = 0;
    const char *p;
    char *o = line;
    for (p = s; *p; ++p)
        if (*p == ',' || *p == '"' || *p == 13 || *p == 10)
            q = 1;
    if (q)
        *o++ = '"';
    for (p = s; *p; ++p) {
        if (*p == '"')
            *o++ = '"';
        *o++ = *p;
    }
    if (q)
        *o++ = '"';
    if (last) {
        *o++ = 13;
        *o++ = 10;
    } else
        *o++ = ',';
    FWrite(csvh, line, o - line);
}

static void b_export(void)
{
    unsigned char i, k;
    struct card *c;
    csvh = FOpen("DEX.CSV", 'w');
    if (csvh < 2 || csvh > 9 || dosStatus >= 20) {
        ui_msg("DEX.CSV could not be written.", "Check the card and the folder.");
        return;
    }
    for (k = 0; k < 5; ++k)
        csv_field(labels[k], k == 4);
    for (i = 0; i < ncards; ++i) {
        get(ord[i], &tmp);
        c = &tmp;
        csv_field(c->name, 0);
        csv_field(c->phone, 0);
        csv_field(c->email, 0);
        csv_field(c->addr, 0);
        csv_field(c->note, 1);
    }
    FClose(csvh);
    ui_num(ui_put(line, "EXPORTED "), ncards, 0);
    say(line);
    status("Written to DEX.CSV.");
}

/* import: DEX.CSV read a byte at a time through a buffer */
static unsigned char ibuf[128], ipos, ilen;
static int inext(void)
{
    if (ipos == ilen) {
        ilen = FRead(csvh, ibuf, sizeof ibuf);
        ipos = 0;
        if (!ilen)
            return -1;
    }
    return ibuf[ipos++];
}

/* a field into f (at most m); the delimiter: ',', '\n' or -1 */
static int ifield(char *f, unsigned char m)
{
    int c = inext();
    unsigned char n = 0, quoted = 0;
    if (c == '"') {
        quoted = 1;
        c = inext();
    }
    for (;;) {
        if (c < 0)
            break;
        if (quoted) {
            if (c == '"') {
                c = inext();
                if (c != '"')
                    break;
            }
        } else if (c == ',' || c == 10 || c == 13)
            break;
        if (n < m)
            f[n++] = c;
        c = inext();
    }
    while (quoted && c >= 0 && c != ',' && c != 10 && c != 13)
        c = inext();
    if (c == 13) {
        c = inext();
        if (c != 10 && c >= 0)
            --ipos;
        c = 10;
    }
    f[n] = 0;
    return c;
}

static void b_import(void)
{
    static char *const f[5] = { cur.name, cur.phone, cur.email, cur.addr, cur.note };
    static const unsigned char m[5] = { NL, PL, EL, AL, TL };
    unsigned char k, added = 0, first = 1;
    int c = 0;
    csvh = FOpen("DEX.CSV", 'r');
    if (csvh < 2 || csvh > 9 || dosStatus >= 20) {
        ui_msg("There is no DEX.CSV.", "Import reads DEX.CSV in this folder.");
        return;
    }
    ipos = ilen = 0;
    while (c >= 0 && ncards < MAXC) {
        memset(&cur, 0, sizeof cur);
        for (k = 0; k < 5; ++k) {
            c = ifield(k < 5 ? f[k] : (char *)rec, m[k]);
            if (c != ',')
                break;
        }
        while (c == ',')                /* more fields: dropped */
            c = ifield((char *)rec, 0);
        if (first && !icmp(cur.name, "name")) {
            first = 0;
            continue;
        }
        first = 0;
        if (cur.name[0]) {
            put(ncards++, &cur);
            ++added;
        }
    }
    FClose(csvh);
    sort();
    save_all();
    ui_num(ui_put(line, "IMPORTED "), added, 0);
    say(line);
    refresh(0xFF);
    status("Read from DEX.CSV.");
}

/* a host: a letter, a dot or a colon in the phone field */
static unsigned char is_host(const char *s)
{
    for (; *s; ++s)
        if (*s == '.' || *s == ':' || (lower(*s) >= 'a' && lower(*s) <= 'z'))
            return 1;
    return 0;
}

static const char *const terms[2] = { "Veranda Term", "Term" };

/* Term in this folder: its name, or 0 */
static const char *find_term(void)
{
    unsigned char i;
    for (i = 0; i < 2; ++i)
        if (FindFile((void *)terms[i]) == 0)
            return terms[i];
    return 0;
}

static void b_connect(void)
{
    const char *t;
    unsigned char h, e;
    char *p;
    if (!cur.phone[0] || !is_host(cur.phone)) {
        ui_msg("This card has no host.", "Put a host:port in its phone field to connect.");
        return;
    }
    if (!ui_ask("Connect with Veranda Term?", "It starts in place of the program underneath."))
        return;
    vr_cd(VR_APPS);                     /* Term: with the applications, else here */
    t = find_term();
    if (!t) {
        sys_leave();
        t = find_term();
    }
    if (!t) {
        sys_leave();
        ui_msg("Veranda Term is not here.", "It is not with the applications or in this folder.");
        return;
    }
    /* the document next to it: Term's address book line */
    p = ui_put(ui_put(ui_put(line, cur.name), "|"), cur.phone);
    *p++ = 13;
    h = FOpen("DEX.TEL", 'w');
    if (h < 2 || h > 9 || dosStatus >= 20) {
        sys_leave();
        ui_msg("DEX.TEL could not be written.", "Term reads the host from it.");
        return;
    }
    FWrite(h, line, p - line);
    FClose(h);
    *ui_put(ui_put((char *)rec, "CONNECT "), cur.phone) = 0;
    say((char *)rec);
    mouseSource = 0;            /* (a pointer source in this RAM, as the test
                                   build's player, is overwritten by the load:
                                   on an SD card the interrupt ran into it) */
    e = GetFile((void *)t, ST_LD_DATA, 0, "DEX.TEL", 0);
    /* (only on an error: Term runs in Dex's place otherwise) */
    sys_leave();
    ui_msg("Veranda Term could not be started.", "");
    (void)e;
}

static void close_box(void)
{
    say("CLOSED");
    RstrAppl();
}

static void act(unsigned char b)
{
    switch (b) {
    case 0: b_save(); break;
    case 1: b_new(); break;
    case 2: b_delete(); break;
    case 3: b_copy(); break;
    case 4: b_connect(); break;
    case 5: b_export(); break;
    case 6: b_import(); break;
    }
}

static void select(unsigned char i)
{
    if (i >= nvis)
        return;
    sel = i;
    reveal();
    draw_list();
    show();
}

static void scroll(signed char d)
{
    int t = (int)top + d;
    if (t + nrows > nvis)
        t = (int)nvis - nrows;
    if (t < 0)
        t = 0;
    if (t == top)
        return;
    top = t;
    draw_list();
}

static void jump(unsigned char letter)
{
    unsigned char i;
    for (i = 0; i < nvis; ++i)
        if (lower(names[vis[i]][0]) >= letter)
            break;
    if (i == nvis)
        i = nvis ? nvis - 1 : 0;
    if (nvis) {
        sel = i;
        top = i;
        reveal();
        draw_list();
        show();
    }
}

/* otherPressVec */
static void press(void)
{
    unsigned char i;
    if (!ui_press())
        return;
    if (ui_closebox()) {
        close_box();
        return;
    }
    for (i = 0; i < 6; ++i)
        if (ui_in(fields[i].x, fields[i].y, fields[i].w, UI_BH)) {
            set_focus(i);
            return;
        }
    for (i = 0; i < NBTN; ++i)
        if (ui_in(bx(i), by(i), bw(i), UI_BH)) {
            act(i);
            return;
        }
    if (ui_in(ui_x0 + TABX, ui_y0 + TABY, 26 * 16, RH)) {
        jump('a' + (ui_px - ui_x0 - TABX) / 16);
        return;
    }
    switch (vr_scroll_hit(&bar, ui_px, ui_py)) {   /* (V148) the scroll bar */
    case VS_BACK: scroll(-1); return;
    case VS_FWD: scroll(1); return;
    case VS_PGBACK: scroll(-(signed char)nrows); return;
    case VS_PGFWD: scroll(nrows); return;
    case VS_THUMB: return;
    }
    if (ui_in(ui_x0 + LX, ui_y0 + LY, LW, nrows * RH))
        select(top + (ui_py - ui_y0 - LY) / RH);
}

static void typed(void)
{
    unsigned char c = keyData;
    if (c == 27) {
        close_box();
        return;
    }
    if (c == KEY_TAB) {
        set_focus(focus == 5 ? 0 : focus + 1);
        return;
    }
    if (c == 13) {
        if (focus)
            b_save();
        return;
    }
    if (c == KEY_UP && sel != 0xFF && sel) {
        select(sel - 1);
        return;
    }
    if (c == KEY_DOWN) {
        select(sel == 0xFF ? 0 : sel + 1);
        return;
    }
    if (ui_field_key(&fields[focus], c)) {
        draw_field(focus);
        if (!focus)
            search();
    }
}

/* appMain: the I-beam over the fields */
static void track(void)
{
    unsigned char i, in = 0;
    ui_px = mouseXPos;
    ui_py = mouseYPosW;
    for (i = 0; i < 6; ++i)
        if (ui_in(fields[i].x, fields[i].y, fields[i].w, UI_BH))
            in = 1;
    SetPointer(in ? PTR_IBEAM : PTR_ARROW);
}

int main(void)
{
    unsigned char i;
    vr_alert_icon = vr_icon;
    if (screenWidth < 640) {
        ui_msg("Dex needs a screen 640 wide.", "");
        RstrAppl();
    }
    bank0 = BankAlloc((MAXC + PERBANK - 1) / PERBANK);
    if (!bank0) {
        ui_msg("Dex cannot start.", "There is not enough memory.");
        RstrAppl();
    }
    ui_h = screenHeight >= 400 ? 400 : 232;
    nrows = (ui_h - LY - 32) / RH;
    fs = ui_h >= 400 ? 24 : 20;
    by1 = FY + 5 * fs + 8;
    by2 = by1 + 24;
    ui_x0 = ((screenWidth - W) / 2) & ~7;
    ui_y0 = ((screenHeight - ui_h) / 2) & ~7;
    fields[0].x = ui_x0 + FINDX + 32;
    fields[0].y = ui_y0 + TABY;
    fields[0].w = W - FINDX - 40;
    for (i = 1; i < 6; ++i) {
        fields[i].x = ui_x0 + FX;
        fields[i].y = ui_y0 + FY + (i - 1) * fs;
        fields[i].w = FW;
    }
    for (i = 0; i < 6; ++i) {
        fields[i].buf = bufs[i];
        fields[i].max = maxes[i];
    }
    bar.cx = (ui_x0 + LX + LW) >> 3;
    bar.cy = (ui_y0 + LY) >> 3;
    bar.len = nrows << 1;
    bar.vert = 1;
    bar.shown = nrows;
    load();
    sort();
    filter();
    sel = nvis ? 0 : 0xFF;
    editing = 0xFF;
    focus = 0;
    draw();
    show();
    otherPressVec = VR_FN(press);
    keyVector = VR_FN(typed);
    appMain = VR_FN(track);
    ui_num(ui_put(line, "RUNNING "), ncards, 0);
    say(line);
#ifdef DEX_TEST
    da_test_start();
#endif
    return 0;
}
