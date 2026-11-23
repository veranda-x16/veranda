/* Note Pad: a Veranda desk accessory in C, GEOS's note pad again.

   A window of notes over the application that opened it: pages of up to
   640 characters (36 columns, 18 rows, wrapped at the window's edge; the
   X16 ROM's ISO font through PutCards, its $A0-$FF the ROM's ISO-8859-16
   glyphs: the text is Veranda's set, DECISIONS V140, V143). The pages are the records of the
   record file "Note File" in /VERANDA/.SYSTEM (DECISIONS V71; the root
   without it): one page a record, up to 127. Its window (V148, Look 3
   "Sunroom": the SDK's vrwin.h chrome, Look 2's palette light or dark):
   the title band with the close box; the text; a bar at the bottom with
   Prev, Next, "Page n of m", New and Delete. Keys: typing, Return, Backspace, Delete, the arrows; PgUp
   and PgDn turn the pages (PgDn on the last page makes a new one unless
   it is empty); Ctrl+N a new page after this one, Ctrl+D deletes this
   page; Escape closes it. A page is written back when it is turned or the
   pad closed, if it changed; the file is closed before RstrAppl.

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <vr.h>
#include <vrpath.h>
#include <string.h>
#include <theme.h>
#include <vrwin.h>

#define X0      160             /* the window: card aligned */
#define Y0      136
#define W       320
#define H       208
#define TX      (X0 / 8 + 2)    /* the text: card column, top row */
#define TY      (Y0 + 24)
#define COLS    36
#define ROWS    18
#define MAXP    640
#define BY      (Y0 + H - 24)   /* the buttons: in the bar (V148: card rows 40-41) */
#define BH      15

static const char fname[] = "Note File";
static unsigned char font[2048];
static char page[MAXP + 1];
static unsigned int len, cur;
static unsigned char pg, npages, dirty;
static unsigned int rowst[ROWS + 2];    /* each row's first character */
static unsigned char nrows;
static char line[48];

/* (V148, Sunroom) the window: the SDK's chrome (vrwin.h), a title band
   with its close box, a frame, a shadow; the text; a bar of 4 card rows
   (the chrome) with the buttons on paper cards and the page between them */
static struct vrwin win = { X0 / 8, Y0 / 8, W / 8, H / 8, 0, 4, VW_CLOSE | VW_FRAME | VW_SHADOW };

struct button { unsigned int l, r; const char *t; };
static const struct button buttons[4] = {
    { X0 + 16, X0 + 63, "Prev" },
    { X0 + 72, X0 + 119, "Next" },
    { X0 + 208, X0 + 247, "New" },
    { X0 + 256, X0 + 303, "Delete" },
};

#ifdef NOTE_TEST
void note_test_start(void);
#endif

static char *put(char *p, const char *s)
{
    while (*s)
        *p++ = *s++;
    *p = 0;
    return p;
}

static char *num(char *p, unsigned char v)
{
    if (v >= 100)
        *p++ = '0' + v / 100;
    if (v >= 10)
        *p++ = '0' + v / 10 % 10;
    *p++ = '0' + v % 10;
    *p = 0;
    return p;
}

static void log2(const char *a, unsigned char x, unsigned char y)
{
    num(put(num(put(put(line, a), " "), x), " "), y);
    LogText(line);
}

/*---------------------------------------------------------------
  the font: the ROM's ISO set (bank 6), as Veranda Edit finds it, its
  $A0-$FF the ROM's ISO-8859-16 set (V143: found by its A ogonek)
 ---------------------------------------------------------------*/
static const unsigned char sigA[8] = { 0x18, 0x3C, 0x24, 0x66, 0x7E, 0x66, 0x66, 0x00 };
static const unsigned char sigL10[8] = { 0x18, 0x3C, 0x24, 0x66, 0x7E, 0x66, 0x0C, 0x06 };

static void font_load(void)
{
    unsigned char keep;
    unsigned int a;
    asm("sei");
    keep = *(unsigned char *)1;
    *(unsigned char *)1 = 6;
    for (a = 0xC000; a; a += 0x800)
        if (!memcmp((void *)(a + 0x41 * 8), sigA, 8) && *(unsigned char *)a == 0xC3)
            break;
    memcpy(font, (void *)(a ? a : 0xC800), 2048);
    for (a = 0xC008; a; a += 8)
        if (*(unsigned char *)a == 0x18 && !memcmp((void *)a, sigL10, 8)) {
            memcpy(font + 0xA0 * 8, (void *)(a - 8), 96 * 8);
            break;
        }
    *(unsigned char *)1 = keep;
    asm("cli");
}

/*---------------------------------------------------------------
  the file
 ---------------------------------------------------------------*/
/* back to the application's folder: curDirName, the path applications
   keep (DECISIONS V48); empty, the root */
static void app_dir(void)
{
    ChDir(curDirName[0] == '/' ? (char *)curDirName : "/");
}

static void sys_dir(void)
{
    vr_cd(VR_DATA);                     /* /VERANDA/.SYSTEM (DECISIONS V71) */
}

/* a new, empty Note File (a record file of type APPL_DATA) */
static unsigned char create(void)
{
    static unsigned char hdr[256];
    static const unsigned char icon[63] = {
        0x15, 0x55, 0x40, 0x3F, 0xFF, 0xF0, 0x20, 0x00, 0x10, 0x2F, 0xFF, 0xD0,
        0x20, 0x00, 0x10, 0x2F, 0xFF, 0xD0, 0x20, 0x00, 0x10, 0x2F, 0xFF, 0xD0,
        0x20, 0x00, 0x10, 0x2F, 0xFF, 0xD0, 0x20, 0x00, 0x10, 0x2F, 0xFC, 0x10,
        0x20, 0x00, 0x10, 0x20, 0x00, 0xF0, 0x20, 0x00, 0xA0, 0x20, 0x00, 0xC0,
        0x3F, 0xFF, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00
    };
    memset(hdr, 0, sizeof hdr);
    hdr[0] = (unsigned int)fname & 255;
    hdr[1] = (unsigned int)fname >> 8;
    hdr[2] = 3;
    hdr[3] = 21;
    hdr[4] = 0xBF;
    memcpy(hdr + 5, icon, 63);
    hdr[68] = 0x83;
    hdr[69] = APPL_DATA;
    hdr[70] = 1;
    memcpy(hdr + O_GHFNAME, "Note File   V1.0", 16);
    memcpy(hdr + O_GH_AUTHOR, "Veranda", 7);
    memcpy(hdr + O_GHP_FNAME, "Note Pad    V1.0", 16);
    memcpy(hdr + O_GHINFO_TXT, "The pages of the Note Pad.", 26);
    return SaveFile(hdr, 0);
}

static void load(void)
{
    len = 0;
    if (!PointRecord(pg) && !ReadRecord(page, MAXP))
        len = r7 - (unsigned int)page;
    if (len > MAXP)
        len = MAXP;
    page[len] = 0;
    cur = len;
    dirty = 0;
}

static void save(void)
{
    if (!dirty)
        return;
    PointRecord(pg);
    WriteRecord(page, len);
    dirty = 0;
}

/*---------------------------------------------------------------
  drawing
 ---------------------------------------------------------------*/
/* the rows: wrapped at COLS, a LF ends one; 0 if the text does not fit */
static unsigned char layout(void)
{
    unsigned int i = 0, c = 0;
    nrows = 0;
    rowst[0] = 0;
    for (i = 0; i < len; ++i) {
        if (page[i] == 10 || c == COLS) {
            if (++nrows >= ROWS)
                return 0;
            rowst[nrows] = page[i] == 10 ? i + 1 : i;
            c = page[i] == 10 ? 0 : 1;
        } else
            ++c;
    }
    rowst[nrows + 1] = len + 1;
    return 1;
}

static unsigned char row_of(unsigned int p, unsigned char *col);

static void draw_text(void)
{
    unsigned char r, k, cx, cy;
    unsigned int s, e;
    for (r = 0; r < ROWS; ++r) {
        memset(line, ' ', COLS);
        if (r <= nrows) {
            s = rowst[r];
            e = r < nrows ? rowst[r + 1] : len;
            for (k = 0; s + k < e && k < COLS && page[s + k] != 10; ++k)
                line[k] = page[s + k] ? page[s + k] : ' ';
        }
        PutCards(line, font, TX, COLS, TY + r * 8, 0);
    }
    /* the cursor: a bar at the left of its cell */
    cy = row_of(cur, &cx);
    WInvertRectangle(TX * 8 + cx * 8, TY + cy * 8, TX * 8 + cx * 8 + 1, TY + cy * 8 + 7);
}

/* s centred in l .. r, in the bar's button row (the UI font) */
static void label(const char *s, unsigned int l, unsigned int r)
{
    unsigned int w = 0;
    const char *p = s;
    while (*p)
        w += GetCharWidth(*p++);
    WPutString((char *)s, (l + r + 1 - w) >> 1, BY + 3 + baselineOffset);
}

/* "Page n of m" between Next and New */
static void draw_title(void)
{
    char *p = line;
    UseFont(FONT_UI);
    SetPattern(0);
    WRectangle(X0 + 120, BY, X0 + 207, BY + BH);
    p = num(put(p, "Page "), pg + 1);
    p = num(put(p, " of "), npages);
    label(line, X0 + 120, X0 + 207);
    UseSystemFont();
}

static void draw_page(void)
{
    layout();
    draw_text();
    draw_title();
}

static void frame(void)
{
    unsigned char i;
    unsigned int l, r;
    theme_palette();                    /* (an accessory's palette goes back with RstrAppl) */
    if (theme.dark)
        win.flags = VW_CLOSE | VW_FRAME;        /* (a shadow in the ink would glow) */
    vr_win(&win, "Note Pad");
    UseFont(FONT_UI);
    for (i = 0; i < 4; ++i) {           /* white buttons, their corners cut */
        l = buttons[i].l;
        r = buttons[i].r;
        theme_rect(l >> 3, (r - l + 1) >> 3, BY >> 3, 2, PAPER);
        SetPattern(0);
        WRectangle(l, BY, r, BY + BH);
        WFrameRectangle(0xFF, l, BY, r, BY + BH);
        WDrawPoint(DRAW_ERASE, l, BY);
        WDrawPoint(DRAW_ERASE, r, BY);
        WDrawPoint(DRAW_ERASE, l, BY + BH);
        WDrawPoint(DRAW_ERASE, r, BY + BH);
        label(buttons[i].t, l, r);
    }
    UseSystemFont();
}

/*---------------------------------------------------------------
  pages
 ---------------------------------------------------------------*/
static void turn(unsigned char to)
{
    save();
    pg = to;
    load();
    draw_page();
    log2("NOTE PAGE", pg + 1, npages);
}

static void next(void)
{
    if (pg + 1 < npages) {
        turn(pg + 1);
        return;
    }
    if (!len || npages >= 127) {
        Beep();
        return;
    }
    save();
    PointRecord(pg);
    AppendRecord();
    ++npages;
    turn(pg + 1);
}

static void prev(void)
{
    if (pg)
        turn(pg - 1);
    else
        Beep();
}

static void newpage(void)
{
    if (npages >= 127) {
        Beep();
        return;
    }
    save();
    PointRecord(pg);
    AppendRecord();
    ++npages;
    turn(pg + 1);
}

static void delpage(void)
{
    dirty = 0;
    PointRecord(pg);
    DeleteRecord();
    if (!--npages) {
        AppendRecord();
        npages = 1;
    }
    if (pg >= npages)
        pg = npages - 1;
    turn(pg);
}

static void quit(void)
{
    save();
    CloseRecordFile();
    app_dir();
    LogText("NOTE CLOSED");
    RstrAppl();
}

/*---------------------------------------------------------------
  editing
 ---------------------------------------------------------------*/
static void insert(char c)
{
    if (len >= MAXP)
        goto full;
    memmove(page + cur + 1, page + cur, len - cur + 1);
    page[cur] = c;
    ++len;
    if (!layout()) {
        memmove(page + cur, page + cur + 1, len - cur);
        --len;
        layout();
        goto full;
    }
    ++cur;
    dirty = 1;
    draw_text();
    return;
full:
    Beep();
}

static void erase(unsigned int at)
{
    if (at >= len)
        return;
    memmove(page + at, page + at + 1, len - at);
    --len;
    cur = at;
    dirty = 1;
    layout();
    draw_text();
}

/* the row of position p, and its column */
static unsigned char row_of(unsigned int p, unsigned char *col)
{
    unsigned char r = 0;
    while (r < nrows && rowst[r + 1] <= p)
        ++r;
    *col = p - rowst[r];
    return r;
}

static void vmove(signed char d)
{
    unsigned char col, r = row_of(cur, &col);
    unsigned int e;
    if ((d < 0 && !r) || (d > 0 && r >= nrows))
        return;
    r += d;
    e = r < nrows ? rowst[r + 1] - 1 : len;
    cur = rowst[r] + col;
    if (cur > e)
        cur = e;
    draw_text();
}

static void key(void)
{
    unsigned char k = keyData, m = keyDataMods;
    if (m & KEYM_ARROW) {
        if (k == KEY_LEFT && cur)
            --cur;
        else if (k == KEY_RIGHT && cur < len)
            ++cur;
        else if (k == KEY_UP)
            vmove(-1);
        else if (k == KEY_DOWN)
            vmove(1);
        draw_text();
        return;
    }
    if (m & 2) {                        /* Ctrl + a letter */
        if (k == 14)
            newpage();
        else if (k == 4)
            delpage();
        return;
    }
    switch (k) {
    case KEY_ESC: quit(); return;
    case KEY_PGDN: next(); return;
    case KEY_PGUP: prev(); return;
    case 8: if (cur) erase(cur - 1); return;
    case KEY_DELETE: erase(cur); return;
    case CR: insert(10); return;
    }
    if ((k >= 32 && k < 127) || (k >= 160 && !(m & 4)))   /* (not Alt's shortcuts) */
        insert(k);
}

static void press(void)
{
    unsigned int x, y;
    unsigned char i, r, c;
    if (mouseData & 0x80)
        return;
    do {
        x = mouseXPos;
        y = mouseYPosW;
    } while (x != mouseXPos || y != mouseYPosW);
    if (vr_win_hit(&win, x, y) == VW_XCLOSE) {
        quit();
        return;
    }
    if (y >= BY && y <= BY + BH) {
        for (i = 0; i < 4; ++i)
            if (x >= buttons[i].l && x <= buttons[i].r)
                switch (i) {
                case 0: prev(); return;
                case 1: next(); return;
                case 2: newpage(); return;
                case 3: delpage(); return;
                }
        return;
    }
    if (x >= TX * 8 && x < (TX + COLS) * 8 && y >= TY && y < TY + ROWS * 8) {
        r = (y - TY) >> 3;
        c = (x - TX * 8 + 3) >> 3;
        if (r > nrows)
            r = nrows;
        cur = rowst[r] + c;
        if (r < nrows && cur >= rowst[r + 1])
            cur = rowst[r + 1] - 1;
        if (cur > len)
            cur = len;
        draw_text();
    }
}

static void tick(void)
{
    unsigned int x = mouseXPos, y = mouseYPosW;
    SetPointer(x >= TX * 8 && x < (TX + COLS) * 8 && y >= TY && y < TY + ROWS * 8 ? PTR_IBEAM : PTR_ARROW);
}

int main(void)
{
    theme_load();
    font_load();
    dispBufferOn = ST_WR_FORE;
    frame();
    sys_dir();
    if ((npages = OpenRecordFile((char *)fname)) != 0) {
        if ((pg = create()) != 0 || OpenRecordFile((char *)fname)) {
            log2("NOTE NO FILE", npages, pg);         /* (the errors: opening, making it) */
            app_dir();
            RstrAppl();
        }
    }
    npages = usedRecords;
    if (!npages) {
        AppendRecord();
        npages = 1;
    }
    pg = 0;
    load();
    draw_page();
    keyVector = VR_FN(key);
    otherPressVec = VR_FN(press);
    appMain = VR_FN(tick);
    log2("NOTE RUNNING", pg + 1, npages);
#ifdef NOTE_TEST
    note_test_start();
#endif
    return 0;
}
