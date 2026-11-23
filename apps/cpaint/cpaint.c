/* Colour Paint: a picture of 320 x 240 pixels, each any of the 256
   palette entries, in the kernel's canvas mode (vrcanvas.h; DECISIONS
   V166, V167). The whole screen is the 320 x 240 mode while it runs: the
   kernel's menus and boxes at double-size pixels over the picture.

   The screen (40 x 30 cards): the menu bar at y 0-13; the tools column
   at x 0-39 (two tools a row, the two colour wells, 16 recent colours,
   the status); the view at x 40-319, y 14-239: the picture from (scrx,
   scry), scrolled with the arrow keys (View > Whole picture: all of it,
   until a click or a key). A click on a well opens the colour popup, 16
   x 16 entries.

   The picture lives in 10 RAM banks (cpaint.h); undo keeps the changed
   box's bytes in 10 more, in the same layout, and Undo exchanges them.

   A document: an APPL_DATA VLIR file of class "PaintColour V1.0":
   record 0 the version (1), the width and height (320, 240: words), the
   two current colours, the palette (256 $0RGB words); records 1-10 the
   bands of 24 rows, PackBits (each row packed alone). Paint's black and
   white pictures ("Paint Image V1.0", 592 x 464) open too, at half size
   (a pixel black if any of its four is).

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <vr.h>
#include <string.h>
#include <vrcanvas.h>
#include <vrchoose.h>
#include <vrpath.h>
#include <vrwin.h>
#include "cpaint.h"
#include "defpal.h"
#include "art.h"

unsigned char pbank, ubank;
unsigned char rowbank[PH], rowlo[PH], rowhi[PH];
unsigned char scrx, scry;
unsigned char cola = 1, colb = 0;
unsigned int fill_seeds = 2730;         /* the fill's seeds at most (8192 / 3; draw.c) */

/* the last change's box (draw.c's tools, fill.s, tools4.c) */
int dl, dt, dr, db;

void __fastcall__ d_box(int l, int t, int r, int b)
{
    if (l < dl) dl = l;
    if (t < dt) dt = t;
    if (r > dr) dr = r;
    if (b > db) db = b;
}

/* (V171) for overlay 4, whose code is at $A000 and cannot map another
   bank itself: rowbuf's n bytes to (to = 1) or from the clip's banks from
   bank at byte offset off; mbuf, main RAM for what the kernel reads or
   writes for it (texts, the scrap's stamp, rows) */
unsigned char mbuf[176];

void __fastcall__ clip_move(unsigned char bank, unsigned long off, unsigned int n, unsigned char to)
{
    unsigned char keep = RAMBANK, *p;
    unsigned int i = 0, k;
    while (i < n) {
        RAMBANK = bank + (unsigned char)((off + i) >> 13);
        p = (unsigned char *)(0xA000 + ((unsigned int)(off + i) & 0x1FFF));
        k = 0x2000 - ((unsigned int)(off + i) & 0x1FFF);
        if (k > n - i)
            k = n - i;
        if (to)
            memcpy(p, rowbuf + i, k);
        else
            memcpy(rowbuf + i, p, k);
        i += k;
    }
    RAMBANK = keep;
}


unsigned char sbank;                    /* the files' bank: a record packed */
char expname[64];                       /* (V172) an export's or a print's name */
static unsigned char ovbank;            /* overlay 1: the Open and Save dialog */
static unsigned char tool = T_PENCIL;
static unsigned char recent[16];
unsigned int pal[256];
char docname[64];
static char namebuf[64];
static unsigned char dragging, popup, whole;
unsigned char dirty;
static int x0, y0, lx, ly;              /* the press, the last sample (picture) */
static int ul, ut, ur, ub;              /* undo's box (ul > ur: nothing) */

#ifdef CP_TEST
void cp_test_start(void);
void cp_test_snap(const char *name);
void cp_test_sample(int x, int y);
void cp_test_clock_reset(void);
void cp_test_clock_log(const char *what);
#define SAMPLE(x, y) cp_test_sample(x, y)
#define CLOCK0() cp_test_clock_reset()
#define CLOCK(w) cp_test_clock_log(w)
#else
#define SAMPLE(x, y)
#define CLOCK0()
#define CLOCK(w)
#endif

/*---------------------------------------------------------------
  the view: picture to VRAM
 ---------------------------------------------------------------*/

/* the column (apps/cpaint/mkart.py's art.h: its rows in overlays 2 and
   3, the chosen tool's plate, the wells' and the recent colours' insides
   put in here) */
#define WELLH   16
static unsigned char colbuf[VX];
static unsigned char ov2bank, ov3bank, ov4bank, ov5bank, ov7bank;
#define OV7(call) do { unsigned char _b = RAMBANK; RAMBANK = ov7bank; call; RAMBANK = _b; } while (0)
#define OV4(call) do { unsigned char _b = RAMBANK; RAMBANK = ov4bank; call; RAMBANK = _b; } while (0)
#define OV5(call) do { unsigned char _b = RAMBANK; RAMBANK = ov5bank; call; RAMBANK = _b; } while (0)

static void col_row(unsigned char y)
{
    unsigned char i, k, c, *p, old;
    if (y < 14) {
        memset(colbuf, 0, VX);
        return;
    }
    old = RAMBANK;
    k = y - 14;
    if (k < ART_HALF) {
        RAMBANK = ov2bank;
        memcpy(colbuf, art_col0 + k * VX, VX);
    } else {
        RAMBANK = ov3bank;
        memcpy(colbuf, art_col1 + (k - ART_HALF) * VX, VX);
    }
    RAMBANK = old;
    if (y >= TOOLY + (tool >> 1) * CELLH && y < TOOLY + (tool >> 1) * CELLH + CELLH) {
        p = colbuf + (tool & 1) * CELLW;        /* the chosen tool's plate: sky */
        for (i = 0; i < CELLW; ++i, ++p)
            if (*p == C_PLATE)
                *p = C_SKY;
            else if (*p == C_EDGE)
                *p = C_SKYEDGE;
        return;
    }
    if (y >= WELLY + 1 && y < WELLY + WELLH - 1) {
        memset(colbuf + WAX + 1, cola, 14);
        memset(colbuf + WBX + 1, colb, 14);
        return;
    }
    if (y <= RECY || y >= RECY + 4 * RH)
        return;
    k = y - RECY;
    i = 0;
    while (k >= RH) {
        k -= RH;
        i += 4;
    }
    if (k == 0 || k >= RH - 2)
        return;
    p = colbuf + RECX + 1;
    for (c = 0; c < 4; ++c, p += RW)
        memset(p, recent[i + c], RW - 3);
}

/* the title band's row y (14-27) over the view: its colour, a slate line
   at the bottom */
static unsigned char bandbyte(unsigned char y)
{
    return y == VY - 1 ? C_SLATE : C_BAND;
}

/* screen box l..r, t..b (pixels) to VRAM: the picture in the view, the
   column's colours, 0 elsewhere */
void screen_out(unsigned int l, unsigned char t, unsigned int r, unsigned char b)
{
    unsigned char y, cr;
    unsigned int vl = l < VX ? VX : l;
    unsigned long v0 = VADDR(l, t), v1 = VADDR(vl, t);
    cr = r < VX ? r : VX - 1;
    for (y = t; ; ++y, v0 += 320, v1 += 320) {
        if (r >= VX) {
            pa_n = r - vl + 1;
            pa_v = v1;
            if (y >= VY) {              /* the view's part */
                pa_y = y - VY + scry;
                pa_x = vl - VX + scrx;
                pic_out();
            } else if (y < 14)          /* the menu bar's rows */
                vzero();
            else {                      /* the title band's */
                pa_c = bandbyte(y);
                vfill();
            }
        }
        if (l < VX) {                   /* the column's part */
            pa_v = v0;
            col_row(y);
            pa_n = cr - l + 1;
            vout(colbuf + l);
        }
        if (y == b)
            break;
    }
}

static void view_all(void)
{
    screen_out(VX, VY, 319, 239);
}

/* picture box l..r, t..b to the screen, where the view shows it */
void show(int l, int t, int r, int b)
{
    if (whole || popup)
        return;
    l -= scrx; r -= scrx; t -= scry; b -= scry;
    if (l < 0) l = 0;
    if (t < 0) t = 0;
    if (r > VW - 1) r = VW - 1;
    if (b > VH - 1) b = VH - 1;
    if (l > r || t > b)
        return;
    screen_out(l + VX, t + VY, r + VX, b + VY);
}

/* the kernel's covers (menus, boxes): their cards drawn again */
static void repaint(void)
{
    unsigned int l = vr_canvas_area[0] * 8;
    unsigned char t = vr_canvas_area[2] * 8;
    screen_out(l, t, l + vr_canvas_area[1] * 8 - 1, t + 7);
}

/*---------------------------------------------------------------
  the chrome (1 bpp: the kernel draws it)
 ---------------------------------------------------------------*/
/* a tool's cell drawn again (its plate sky if chosen) */
static void tool_cell(unsigned char t)
{
    unsigned char y = TOOLY + (t >> 1) * CELLH;
    unsigned int x = (t & 1) * CELLW;
    screen_out(x, y, x + CELLW - 1, y + CELLH - 1);
}

static unsigned char tool_ok(unsigned char t)
{
    return t < TOOLS;
}

/* the status (tools4.c's t4_status: main RAM was full) */
static void status(int x, int y)
{
    OV4(t4_status(x, y));
}

/* the column: the 1 bpp screen cleared there (the art is the canvas's
   bytes), the art and the colours */
static void chrome(void)
{
    dispBufferOn = ST_WR_FORE;
    SetPattern(0);
    WRectangle(0, 14, VX - 1, 239);
    screen_out(0, 14, VX - 1, 239);
    OV4(t4_status(-2, 0));             /* (drawn again at the next move) */
}

static void select_tool(unsigned char t)
{
    unsigned char old = tool;
    if (!tool_ok(t))
        return;
    tool = t;
    tool_cell(old);
    tool_cell(t);
}

/* colour A chosen: first among the recent colours */
static void set_cola(unsigned char c)
{
    unsigned char i;
    cola = c;
    for (i = 0; i < 15 && recent[i] != c; ++i)
        ;
    memmove(recent + 1, recent, i);
    recent[0] = c;
    screen_out(0, WELLY, VX - 1, RECY + 4 * RH);
}

/*---------------------------------------------------------------
  the palette
 ---------------------------------------------------------------*/
static void palette_out(void)
{
    SetColors(pal[0], pal[1]);
    vr_canvas_palette(pal + 2, 2, 254);
}

/*---------------------------------------------------------------
  undo: the box about to change, kept; Undo exchanges it
 ---------------------------------------------------------------*/
void keep_box(int l, int t, int r, int b)
{
    unsigned char y;
    if (l < 0) l = 0;
    if (t < 0) t = 0;
    if (r > PW - 1) r = PW - 1;
    if (b > PH - 1) b = PH - 1;
    ul = l; ut = t; ur = r; ub = b;
    if (l > r || t > b)
        return;
    pa_x = l;
    pa_n = r - l + 1;
    for (y = t; ; ++y) {
        pa_y = y;
        urow_save();
        if (y == b)
            break;
    }
}

static void keep_all(void)
{
    keep_box(0, 0, PW - 1, PH - 1);
}

static void menus_off(void);

static void m_undo(void)
{
    unsigned char y;
    menus_off();
    if (ul > ur)
        return;
    pa_x = ul;
    pa_n = ur - ul + 1;
    for (y = ut; ; ++y) {
        pa_y = y;
        urow_swap();
        if (y == ub)
            break;
    }
    show(ul, ut, ur, ub);
    LogText("CPAINT UNDONE");
}

/*---------------------------------------------------------------
  dialog boxes
 ---------------------------------------------------------------*/
struct msgdlg {
    unsigned char pos;
    unsigned char t1, x1, y1, reg1;
    unsigned char t2, x2, y2, reg2;
    unsigned char ok, okx, oky;
    unsigned char end;
};
static const struct msgdlg msgbox = {
    DEF_DB_POS | 1,
    DBVARSTR, TXT_LN_X, TXT_LN_2_Y, 0x0C,
    DBVARSTR, TXT_LN_X, TXT_LN_3_Y, 0x0E,
    OK, DBI_X_0, DBI_Y_2,
    0
};

void message(const char *a, const char *b)
{
    r5 = (unsigned int)a;
    r6 = (unsigned int)b;
    DoDlgBox((void *)&msgbox);
}

static char errtext[] = "Error 00";              /* (logged too) */

void error(unsigned char e)
{
    errtext[6] = '0' + e / 10;
    errtext[7] = '0' + e % 10;
    LogText(errtext);
    message(errtext, docname);
}

/*---------------------------------------------------------------
  documents
 ---------------------------------------------------------------*/
#define hdr rowbuf                      /* (SaveFile reads it first) */
static const char dclass[] = "PaintColour V1.0";
static const char pclass[] = "ColourPaint V1.0";
static const char ddesc[] = "A colour picture from Colour Paint.";
static unsigned char head[7];

/* the info block: kind 0 Colour Paint's picture (docname), 1 a black
   and white picture for Paint (expname: V172) */
static const char oclass[] = "Paint Image V1.0";
static const char opclass[] = "Paint       V1.0";
static const char odesc[] = "A picture for Paint, from Colour Paint.";

void make_hdr(unsigned char kind)
{
    unsigned char i;
    const char *nm = kind ? expname : docname;
    memset(hdr, 0, 256);
    hdr[0] = (unsigned int)nm & 255;
    hdr[1] = (unsigned int)nm >> 8;
    hdr[2] = 3;
    hdr[3] = 21;
    hdr[4] = 0xBF;
    for (i = 0; i < 21; ++i) {          /* the icon: a page with a blot */
        unsigned char *p = hdr + 5 + i * 3;
        if (i == 0 || i == 20) {
            p[0] = 0x7F; p[1] = 0xFF; p[2] = 0xFE;
        } else {
            p[0] = 0x40; p[1] = 0; p[2] = 0x02;
        }
        if (i >= 6 && i <= 14) {
            p[0] |= 0x01; p[1] |= 0xFF; p[2] |= 0x80;
        }
    }
    hdr[68] = 0x83;
    hdr[69] = APPL_DATA;
    hdr[70] = 1;                        /* VLIR */
    memcpy(hdr + O_GH_AUTHOR, "Veranda", 8);
    if (kind) {
        memcpy(hdr + O_GHFNAME, oclass, sizeof oclass);
        memcpy(hdr + O_GHP_FNAME, opclass, sizeof opclass);
        memcpy(hdr + O_GHINFO_TXT, odesc, sizeof odesc);
        return;
    }
    memcpy(hdr + O_GHFNAME, dclass, sizeof dclass);
    memcpy(hdr + O_GHP_FNAME, pclass, sizeof pclass);
    memcpy(hdr + O_GHINFO_TXT, ddesc, sizeof ddesc);
}

/* (V172) WriteRecord of the files' bank's first n bytes (overlay 7's
   export: its code cannot map the bank) */
unsigned char __fastcall__ rec_write(unsigned int n)
{
    unsigned char e, b = RAMBANK;
    RAMBANK = sbank;
    e = WriteRecord((void *)0xA000, n);
    RAMBANK = b;
    return e;
}

/* PackBits (pic.s's pack_row): rowbuf's 320 bytes to *pk, in the bank
   mapped; pk moves past them */
unsigned char *pk;
void pack_row(void);

static unsigned char save_doc(void)
{
    unsigned char e, b, r, y, rr;
    unsigned int n;
    CLOCK0();
    make_hdr(0);
    e = SaveFile(hdr, 0);
    if (e)
        return e;
    e = OpenRecordFile(docname);
    if (e)
        return e;
    /* record 0: the version, 320, 240, the colours, the palette */
    rr = RAMBANK;
    RAMBANK = sbank;
    pk = (unsigned char *)0xA000;
    pk[0] = 1;
    pk[1] = PW & 255; pk[2] = PW >> 8;
    pk[3] = PH; pk[4] = 0;
    pk[5] = cola; pk[6] = colb;
    memcpy(pk + 7, pal, 512);
    RAMBANK = rr;
    if ((e = AppendRecord()) != 0)
        goto out;
    RAMBANK = sbank;
    e = WriteRecord((void *)0xA000, 7 + 512);
    RAMBANK = rr;
    if (e)
        goto out;
    for (b = 0; b < BANDS; ++b) {
        pk = (unsigned char *)0xA000;
        pa_x = 0;
        pa_n = PW;
        for (r = 0; r < BANDH; ++r) {
            y = b * BANDH + r;
            pa_y = y;
            row_get();
            RAMBANK = sbank;
            pack_row();
            RAMBANK = rr;
        }
        n = pk - (unsigned char *)0xA000;
        if ((e = AppendRecord()) != 0)
            break;
        RAMBANK = sbank;
        e = WriteRecord((void *)0xA000, n);
        RAMBANK = rr;
        if (e)
            break;
    }
out:
    r = CloseRecordFile();
    CLOCK("save");
    return e ? e : r;
}

/* PackBits from the bank mapped (p .. end) into rows from row y; the rows
   filled (the bands' rows: 24, Paint's: 74 bytes x 16) */
static unsigned char *up, *uend;
static unsigned int ufill;

static unsigned char ulit, urun, uval;  /* a literal's or a run's bytes left
                                           (a run may go on into the next row) */

static void unpack_start(void)
{
    ulit = urun = 0;
}

static unsigned char unpack(unsigned int want)
{
    signed char h;
    unsigned int n;
    ufill = 0;
    while (ufill < want) {
        if (urun) {
            n = want - ufill < urun ? want - ufill : urun;
            memset(rowbuf + ufill, uval, n);
            urun -= n;
        } else if (ulit) {
            n = want - ufill < ulit ? want - ufill : ulit;
            if (up + n > uend)
                return 0;
            memcpy(rowbuf + ufill, up, n);
            up += n;
            ulit -= n;
        } else {
            if (up >= uend)
                return 0;
            h = (signed char)*up++;
            if (h >= 0)
                ulit = h + 1;
            else if (h != -128) {
                urun = 1 - h;
                uval = *up++;
            }
            continue;
        }
        ufill += n;
    }
    return 1;
}

/* Paint's black and white picture: 29 bands of 16 rows of 74 bytes, at
   half size: (x, y) black if any of (2x, 2y), (2x+1, 2y), (2x, 2y+1),
   (2x+1, 2y+1) is */
unsigned char obuf[74 * 2];            /* (pic.s's old_row reads it) */

static unsigned char open_old(void)
{
    unsigned char e, b, r, rr, y, k;
    rr = RAMBANK;
    cola = 1;
    colb = 0;
    memcpy(pal, defpal, sizeof pal);
    for (y = 0; y < PH; ++y) {          /* white first */
        pa_y = y;
        pa_x = 0;
        pa_n = PW;
        pa_c = 0;
        pic_span();
    }
    for (b = 0; b < 29; ++b) {
        if ((e = PointRecord(b + 1)) != 0)
            return e;
        RAMBANK = sbank;
        e = ReadRecord((void *)0xA000, 8192);
        RAMBANK = rr;
        if (e)
            return e;
        up = (unsigned char *)0xA000;
        uend = (unsigned char *)r7;
        unpack_start();
        for (r = 0; r < 16; r += 2) {
            RAMBANK = sbank;
            k = unpack(148);            /* two rows of 74 bytes */
            if (k)
                memcpy(obuf, rowbuf, 148);
            RAMBANK = rr;
            if (!k)
                return INCOMPATIBLE;
            y = b * 8 + r / 2;
            old_row();                  /* (pic.s: V172, the C loop took 2.7 s) */
            pa_y = y;
            pa_x = 0;
            pa_n = PW;
            row_put();
        }
    }
    return 0;
}

static unsigned char open_doc(void)
{
    unsigned char e, b, r, rr, y;
    CLOCK0();
    if ((e = OpenRecordFile(docname)) != 0)
        return e;
    rr = RAMBANK;
    if ((e = PointRecord(0)) != 0)
        goto out;
    RAMBANK = sbank;
    e = ReadRecord((void *)0xA000, 8192);
    pk = (unsigned char *)0xA000;
    if (!e && r7 - 0xA000 >= 8 && !memcmp(pk, "VPNT", 4) && pk[5] == 74 && pk[6] == 16 && pk[7] == 29) {
        RAMBANK = rr;                   /* Paint's black and white picture */
        e = open_old();
        goto out;
    }
    if (!e && (r7 != 0xA000 + 7 + 512 || pk[0] != 1 || pk[1] != (PW & 255) || pk[2] != PW >> 8 || pk[3] != PH))
        e = INCOMPATIBLE;
    if (!e) {
        cola = pk[5];
        colb = pk[6];
        memcpy(pal, pk + 7, 512);
    }
    RAMBANK = rr;
    if (e)
        goto out;
    for (b = 0; b < BANDS; ++b) {
        if ((e = PointRecord(b + 1)) != 0)
            break;
        RAMBANK = sbank;
        e = ReadRecord((void *)0xA000, 8192);
        RAMBANK = rr;
        if (e)
            break;
        up = (unsigned char *)0xA000;
        uend = (unsigned char *)r7;
        unpack_start();
        for (r = 0; r < BANDH; ++r) {
            RAMBANK = sbank;
            y = unpack(PW);
            RAMBANK = rr;
            if (!y) {
                e = INCOMPATIBLE;
                goto out;
            }
            pa_y = b * BANDH + r;
            pa_x = 0;
            pa_n = PW;
            row_put();
        }
    }
out:
    r = CloseRecordFile();
    CLOCK("open");
    return e ? e : r;
}

/*---------------------------------------------------------------
  the menus
 ---------------------------------------------------------------*/
struct item { const char *text; unsigned char type; void *p; };
struct menu1 { unsigned char top, bottom; unsigned int left, right; unsigned char flags; struct item i[1]; };
struct menu2 { unsigned char top, bottom; unsigned int left, right; unsigned char flags; struct item i[2]; };
struct menu4 { unsigned char top, bottom; unsigned int left, right; unsigned char flags; struct item i[4]; };
struct menu8 { unsigned char top, bottom; unsigned int left, right; unsigned char flags; struct item i[8]; };
struct menu5 { unsigned char top, bottom; unsigned int left, right; unsigned char flags; struct item i[5]; };

static void m_about(void), m_desk(void), m_new(void), m_open(void), m_save(void), m_saveas(void), m_quit(void);
static void m_whole(void);

#define IH 16                   /* (the Veranda look's item height: the menu's box as drawn) */
static struct menu2 mapp = { 14, 14 + 2 * IH, 0, 0, VERTICAL | 2, {
    { "About Colour Paint", MENU_ACTION, m_about }, { "\x1f" "Desk accessory...", MENU_ACTION, m_desk } } };
static void m_expaint(void), m_exbmp(void), m_print(void);
static struct menu8 mfile = { 14, 14 + 8 * IH, 0, 0, VERTICAL | 8, {
    { "New\tCtrl N", MENU_ACTION, m_new }, { "Open...\tCtrl O", MENU_ACTION, m_open },
    { "\x1f" "Save\tCtrl S", MENU_ACTION, m_save }, { "Save as...", MENU_ACTION, m_saveas },
    { "\x1f" "Export for Paint...", MENU_ACTION, m_expaint }, { "Export as BMP...", MENU_ACTION, m_exbmp },
    { "Print...\tCtrl P", MENU_ACTION, m_print }, { "\x1f" "Quit\tCtrl Q", MENU_ACTION, m_quit } } };
static void m_cut(void), m_copy(void), m_paste(void), m_palette(void);
static struct menu4 medit = { 14, 14 + 4 * IH, 0, 0, VERTICAL | 4, {
    { "Undo\tCtrl Z", MENU_ACTION, m_undo }, { "\x1f" "Cut\tCtrl X", MENU_ACTION, m_cut },
    { "Copy\tCtrl C", MENU_ACTION, m_copy }, { "Paste\tCtrl V", MENU_ACTION, m_paste } } };
static struct menu2 mview = { 14, 14 + 2 * IH, 0, 0, VERTICAL | 2, {
    { "Whole picture\tCtrl W", MENU_ACTION, m_whole }, { "Palette...", MENU_ACTION, m_palette } } };
static struct { unsigned char top, bottom; unsigned int left, right; unsigned char flags; struct item i[4]; } mbar = {
    0, 14, 0, 0, HORIZONTAL | UN_CONSTRAINED | 4, {
    { "Colour Paint", SUB_MENU, &mapp }, { "File", SUB_MENU, &mfile }, { "Edit", SUB_MENU, &medit },
    { "View", SUB_MENU, &mview } } };
static const char *const barnames[4] = { "Colour Paint", "File", "Edit", "View" };
static unsigned int barend;

static unsigned int itemw(const char *s)
{
    unsigned int w = 0;
    for (; *s && *s != '\t'; ++s)
        if (*s >= 32)
            w += GetCharWidth(*s);
    return w;
}

static void layout(void)
{
    static unsigned int *const lefts[4] = { &mapp.left, &mfile.left, &medit.left, &mview.left };
    static unsigned int *const rights[4] = { &mapp.right, &mfile.right, &medit.right, &mview.right };
    static struct item *const items[4] = { mapp.i, mfile.i, medit.i, mview.i };
    static const unsigned char nitems[4] = { 2, 8, 4, 2 };
    unsigned int b = 0, w, m;
    unsigned char i, j;
    UseFont(FONT_UI);
    for (i = 0; i < 4; ++i) {
        *lefts[i] = b;
        for (m = 0, j = 0; j < nitems[i]; ++j)
            if ((w = itemw(items[i][j].text)) > m)
                m = w;
        w = b + m + 40;                 /* (room for the shortcut) */
        if (w > 319) {
            *lefts[i] -= w - 319;
            w = 319;
        }
        *rights[i] = w;
        b += itemw(mbar.i[i].text) + 8;
    }
    UseSystemFont();
    barend = vr_bar_end(barnames, 4);
    mbar.right = barend;
}

/* (V170) the window's title (tools4.c's t4_title) */
char ttl[72];

void title(void)
{
    unsigned char b = RAMBANK;
    RAMBANK = ov4bank;
    t4_title();
    RAMBANK = b;
}

/* the menus closed. (In the 320 mode a vertical menu of the Veranda look
   leaves one row of its outline under it, 2 below its bottom, after it
   closes: the kernel's, not the canvas's; those rows of the view's 1 bpp
   screen, all paper there, are cleared, and the column drawn again when
   the program's own menu, over it, was the one) */
static void menus_off(void)
{
    static const unsigned char under[3] = { 16 + 2 * IH, 16 + 8 * IH, 16 + 4 * IH };
    unsigned char i;
    GotoFirstMenu();
    dispBufferOn = ST_WR_FORE;
    SetPattern(0);
    for (i = 0; i < 3; ++i)
        WRectangle(VX, under[i], 319, under[i]);
    title();
}

/*---------------------------------------------------------------
  the commands
 ---------------------------------------------------------------*/
static void clear_pic(void)
{
    unsigned char y;
    pa_x = 0;
    pa_n = PW;
    pa_c = 0;
    for (y = 0; y < PH; ++y) {
        pa_y = y;
        pic_span();
    }
}

static void fresh(void)
{
    palette_out();
    set_cola(cola);
    screen_out(VX, 14, 319, 239);       /* (the title band and the view) */
    title();
}

static void m_new(void)
{
    menus_off();
    clear_pic();
    memcpy(pal, defpal, sizeof pal);
    cola = 1;
    colb = 0;
    ul = 1; ur = 0;
    docname[0] = 0;
    dirty = 0;
    fresh();
    LogText("CPAINT NEW");
}

static void do_save(void)
{
    unsigned char e = save_doc();
    if (e)
        error(e);
    else {
        dirty = 0;
        title();
        LogText("CPAINT SAVED");
#ifdef CP_TEST
        cp_test_snap("SAVED.PIC");
#endif
    }
}

static void nocvt(void)
{
    unsigned char l = strlen(namebuf);
    if (l > 4 && namebuf[l - 4] == '.' && (namebuf[l - 3] | 0x20) == 'c' && (namebuf[l - 2] | 0x20) == 'v'
        && (namebuf[l - 1] | 0x20) == 't')
        namebuf[l - 4] = 0;
}

static const char ptypes[] = "Pictures:CVT";

static unsigned char file_dlg(unsigned char mode, const char *ttl)
{
    unsigned char r, b = RAMBANK;
    vr_file_types = ptypes;
    RAMBANK = ovbank;
    r = vr_file(mode, ttl, namebuf);
    RAMBANK = b;
    if (!r)
        return 0;
    nocvt();
    return namebuf[0] != 0;
}

static void m_saveas(void)
{
    menus_off();
    strcpy(namebuf, docname);
    if (!file_dlg(VRF_SAVE, "Save the picture"))
        return;
    strcpy(docname, namebuf);
    do_save();
}

static void m_save(void)
{
    if (!docname[0]) {
        m_saveas();
        return;
    }
    menus_off();
    do_save();
}

static void opened(void)
{
    unsigned char e = open_doc();
    ul = 1; ur = 0;
    dirty = 0;
    if (e) {
        error(e);
        docname[0] = 0;
    } else {
        LogText("CPAINT OPENED");
        LogText(docname);
#ifdef CP_TEST
        {
            static char on[] = "OPENED0.PIC";
            cp_test_snap(on);
            ++on[6];
        }
#endif
    }
    CLOCK0();
    fresh();
    CLOCK("view");
}

static void m_open(void)
{
    menus_off();
    namebuf[0] = 0;
    if (!file_dlg(VRF_OPEN, "Open a picture"))
        return;
    strcpy(docname, namebuf);
    opened();
}

/* (V172) File > Export for Paint, Export as BMP, Print: the name asked
   (the picture's, with " (BW)", ".bmp" or ".pdf"), then export.c's */
static unsigned char ask_exp(const char *ttl, const char *suffix)
{
    menus_off();
    strcpy(namebuf, docname[0] ? docname : "Untitled");
    strcat(namebuf, suffix);
    if (!file_dlg(VRF_SAVE, ttl))
        return 0;
    strcpy(expname, namebuf);
    if (suffix[0] == '.' && !strchr(expname, '.'))
        strcat(expname, suffix);
    return 1;
}

static void exported(unsigned char e, const char *what)
{
    if (e)
        error(e);
    else {
        LogText(what);
        LogText(expname);
    }
}

static void m_expaint(void)
{
    unsigned char e;
    if (!ask_exp("Export for Paint (black and white)", " BW"))
        return;
    CLOCK0();
    OV7(e = x7_paint());
    CLOCK("expaint");
    exported(e, "CPAINT EXPORTED");
}

static void m_exbmp(void)
{
    unsigned char e;
    if (!ask_exp("Export as BMP", ".bmp"))
        return;
    CLOCK0();
    OV7(e = x7_bmp());
    CLOCK("bmp");
    exported(e, "CPAINT BMP");
}

static void m_print(void)
{
    unsigned char e;
    if (!ask_exp("Print to a PDF file", ".pdf"))
        return;
    CLOCK0();
    OV7(e = x7_print());
    CLOCK("print");
    exported(e, "CPAINT PRINTED");
}

static void m_about(void)
{
    menus_off();
    chrome();
    message("Colour Paint: 320 x 240,", "256 colours. MIT licence.");
}

struct filedlg {
    unsigned char pos;
    unsigned char f, fx, fy;
    unsigned char op, opx, opy;
    unsigned char cn, cnx, cny;
    unsigned char end;
};
static const struct filedlg filebox = {
    DEF_DB_POS | 1,
    DBGETFILES, 4, 4,
    OPEN, DBI_X_2, DBI_Y_0,
    CANCEL, DBI_X_2, DBI_Y_2,
    0
};

static void m_desk(void)
{
    unsigned char r;
    menus_off();
    chrome();
    namebuf[0] = 0;
    r5 = (unsigned int)namebuf;
    r7L = DESK_ACC;
    r10 = 0;
    vr_cd(VR_APPS);
    r = DoDlgBox((void *)&filebox);
    vr_cdback();
    if (r == DBGETFILES) {
        message("There are no desk accessories", "with the applications.");
        return;
    }
    if (r != OPEN || !namebuf[0])
        return;
    vr_cd(VR_APPS);
    r = GetFile(namebuf, 0, 0, 0, 0);
    vr_cdback();
    if (r)
        error(r);
}

static void m_quit(void)
{
    menus_off();
    vr_canvas_off();
    LogText("CPAINT QUIT");
    EnterDeskTop();
}

/* View > Whole picture: the picture on the whole screen until a click or
   a key */
static void m_whole(void)
{
    menus_off();
    whole = 1;
    OV4(t4_whole());
    LogText("CPAINT WHOLE");
}

static void whole_end(void)
{
    whole = 0;
    ReDoMenu();
    chrome();
    screen_out(0, 0, 319, 239);
    title();
    LogText("CPAINT VIEW");
}

/*---------------------------------------------------------------
  the colour popup: 16 x 16 entries of 8 x 8 pixels at (POPX, POPY)
 ---------------------------------------------------------------*/
#define POPX    96
#define POPY    48
static unsigned char popwell;           /* 0 A, 1 B */

static void popup_open(unsigned char w)
{
    popup = 1;
    popwell = w;
    dispBufferOn = ST_WR_FORE;
    SetPattern(0);
    WRectangle(POPX - 2, POPY - 2, POPX + 129, POPY + 129);
    WFrameRectangle(0xFF, POPX - 2, POPY - 2, POPX + 129, POPY + 129);
    OV4(t4_grid(POPX, POPY));
    LogText("CPAINT POPUP");
}

static void popup_close(void)
{
    popup = 0;
    SetPattern(0);
    WRectangle(POPX - 2, POPY - 2, POPX + 129, POPY + 129);
    screen_out(POPX - 2, POPY - 2, POPX + 129, POPY + 129);
}

static void popup_click(unsigned int x, unsigned char y)
{
    unsigned char c;
    if (x >= POPX && x < POPX + 128 && y >= POPY && y < POPY + 128) {
        c = (y - POPY) / 8 * 16 + (x - POPX) / 8;
        popup_close();
        if (popwell)
            colb = c;
        else
            set_cola(c);
        screen_out(0, WELLY, VX - 1, RECY + 4 * RH);
        return;
    }
    popup_close();
}

/*---------------------------------------------------------------
  drawing
 ---------------------------------------------------------------*/
static void order(int *a, int *b)
{
    int t;
    if (*a > *b) {
        t = *a;
        *a = *b;
        *b = t;
    }
}

static int bl, bt, br, bb;              /* the rubber band shown (screen) */
static unsigned char band_on;

static int clampx(int x)
{
    return x < 0 ? 0 : x > PW - 1 ? PW - 1 : x;
}

static int clampy(int y)
{
    return y < 0 ? 0 : y > PH - 1 ? PH - 1 : y;
}

/* the rubber band on the 1 bpp screen (its 0 pixels show the picture):
   ink to show it, 0 to take it away */
static void band_draw(unsigned char ink)
{
    int sx0 = x0 - scrx + VX, sy0 = y0 - scry + VY, sx1 = lx - scrx + VX, sy1 = ly - scry + VY;
    dispBufferOn = ST_WR_FORE;
    if (tool == T_LINE) {
        WDrawLine(ink ? DRAW_INK : DRAW_ERASE, sx0, sy0, sx1, sy1);
        return;
    }
    order(&sx0, &sx1);
    order(&sy0, &sy1);
    WFrameRectangle(ink ? 0xFF : 0x00, sx0, sy0, sx1, sy1);
}

static void band(unsigned char show_it)
{
    if (show_it && !band_on) {
        band_draw(1);
        band_on = 1;
    } else if (!show_it && band_on) {
        band_draw(0);
        band_on = 0;
    }
}

static void change_begin(void)
{
    dl = 32767; dt = 32767; dr = -1; db = -1;
}

static void change_show(void)
{
    if (dr >= 0)
        show(dl, dt, dr, db);
    if (!dirty) {
        dirty = 1;
        title();
    }
}

/* the eraser from the last sample to (x, y) in steps of 4 */
static void erase_to(int x, int y)
{
    int dx = x - lx, dy = y - ly;
    int n = (dx < 0 ? -dx : dx) > (dy < 0 ? -dy : dy) ? (dx < 0 ? -dx : dx) : (dy < 0 ? -dy : dy);
    int i, s = n / 4;
    for (i = 1; i <= s; ++i)
        OV5(d_erase(lx + (long)dx * i / s, ly + (long)dy * i / s));
    OV5(d_erase(x, y));
}

/*---------------------------------------------------------------
  (V171) the text tool: the kernel's GetString types into the 1 bpp
  screen at the click; Return (or a click elsewhere) stamps its ink
  into the picture in colour A (tools4.c's t4_text)
 ---------------------------------------------------------------*/
static char text[42];
static unsigned char texting;
static unsigned int tx;
static unsigned char ty;

static void keys(void);

static void text_done(void)
{
    unsigned int w = 0;
    unsigned char i;
    keyVector = VR_FN(keys);
    texting = 0;
    UseSystemFont();
    for (i = 0; text[i]; ++i)
        w += GetCharWidth(text[i]);
    if (!w)
        return;
    change_begin();
    OV4(t4_text(tx, ty - 8, tx + w, ty + 10));  /* (the system font: above and below its y) */
    change_show();
    LogText("CPAINT TYPED");
}

static void text_end(void)
{
    if (texting) {
        PromptOff();
        text_done();
    }
}

static void text_start(int x, int y)
{
    tx = x - scrx + VX;
    ty = y - scry + VY;
    if (ty < VY + 7)
        ty = VY + 7;
    if (ty > 237)
        ty = 237;
    text[0] = 0;
    texting = 1;
    UseSystemFont();
    dispBufferOn = ST_WR_FORE;
    keyVector = VR_FN(text_done);
    WGetString(text, 40, tx, ty, 0, 0);
}

/*---------------------------------------------------------------
  (V171) the selection and the clipboard (tools4.c's t4_copy, t4_put)
 ---------------------------------------------------------------*/
static unsigned char sel, floating;
static int sl, st, sr, sb;              /* the selection (picture) */
static int fx = -1000, fy;              /* the paste's top left (picture) */

static void sel_hide(void)
{
    if (sel) {
        x0 = sl; y0 = st; lx = sr; ly = sb;
        band_on = 1;
        band(0);
    }
    sel = 0;
}

static void m_copy(void)
{
    unsigned char e;
    menus_off();
    if (!sel) {
        message("Select an area first", "(the dotted box: its tool).");
        return;
    }
    OV4(e = t4_copy(sl, st, sr, sb));
    x0 = sl; y0 = st; lx = sr; ly = sb;
    band_draw(1);                       /* (the menu may have covered it) */
    if (e)
        error(e);
    else
        LogText("CPAINT COPIED");
}

static void m_cut(void)
{
    unsigned char y;
    menus_off();
    if (!sel) {
        message("Select an area first", "(the dotted box: its tool).");
        return;
    }
    m_copy();
    sel_hide();
    keep_box(sl, st, sr, sb);
    pa_x = sl;
    pa_n = sr - sl + 1;
    pa_c = 0;
    for (y = st; ; ++y) {
        pa_y = y;
        pic_span();
        if (y == sb)
            break;
    }
    change_begin();
    d_box(sl, st, sr, sb);
    change_show();
    LogText("CPAINT CUT");
}

static void float_hide(void)
{
    unsigned int w, h;
    if (fx == -1000)
        return;
    OV4((w = t4_cw(), h = t4_ch()));
    show(fx, fy, fx + w - 1, fy + h - 1);
    fx = -1000;
}

static void float_at(int x, int y)
{
    if (x == fx && y == fy)
        return;
    float_hide();
    fx = x;
    fy = y;
    OV4(t4_put(x, y, 0));
}

static void float_drop(void)
{
    unsigned int w, h;
    OV4((w = t4_cw(), h = t4_ch()));
    keep_box(fx, fy, fx + w - 1, fy + h - 1);
    OV4(t4_put(fx, fy, 1));
    change_begin();
    d_box(fx, fy, fx + w - 1, fy + h - 1);
    change_show();
    floating = 0;
    fx = -1000;
    LogText("CPAINT PASTED");
}

static void m_paste(void)
{
    unsigned char e;
    menus_off();
    sel_hide();
    OV4(e = t4_paste_ready());
    if (e) {
        message("There is no picture", "on the clipboard.");
        return;
    }
    floating = 1;
    fx = -1000;
    LogText("CPAINT FLOATING");
}

/*---------------------------------------------------------------
  (V171) the palette editor (tools4.c): a panel over the view
 ---------------------------------------------------------------*/
static unsigned char palmode;

static void m_palette(void)
{
    menus_off();
    palmode = 1;
    OV4(t4_pal_open(cola));
}

static void pal_end(void)
{
    palmode = 0;
    OV4(t4_pal_close());
    screen_out(0, WELLY, VX - 1, RECY + 4 * RH);        /* (the wells' colours may be new) */
}

static void start(int x, int y)
{
    x0 = lx = x;
    y0 = ly = y;
    change_begin();
    switch (tool) {
    case T_PENCIL:
        keep_all();
        SAMPLE(x, y);
        OV5(d_line(x, y, x, y));
        change_show();
        break;
    case T_ERASER:
        keep_all();
        SAMPLE(x, y);
        OV5(d_erase(x, y));
        change_show();
        break;
    case T_FILL:
        keep_all();
#ifdef CP_TEST
        {                               /* (the test build: the first fill with 6
                                           seeds, so that it passes over its box) */
            static unsigned char nf;
            fill_seeds = nf++ ? 2730 : 6;
        }
#endif
        CLOCK0();
        OV5(d_fill(x, y));
        CLOCK("fill");
        change_show();
        LogText("CPAINT FILLED");
#ifdef CP_TEST
        cp_test_snap("FILL.PIC");
#endif
        return;
    case T_PICK:
        set_cola(pget(x, y));
        LogText("CPAINT PICKED");
        return;
    case T_BRUSH:
        keep_all();
        SAMPLE(x, y);
        OV4(t4_brush(x, y, x, y));
        change_show();
        break;
    case T_SPRAY:
        keep_all();
        SAMPLE(x, y);
        OV4(t4_spray(x, y));
        change_show();
        break;
    case T_TEXT:
        text_start(x, y);
        return;
    case T_SELECT:
        sel_hide();
        band(1);
        break;
    default:
        band(1);
        break;
    }
    dragging = 1;
}

static void finish(void)
{
    int l = x0, t = y0, r = lx, b = ly;
    dragging = 0;
    band(0);
    order(&l, &r);
    order(&t, &b);
    change_begin();
    CLOCK0();
    switch (tool) {
    case T_LINE:
        keep_box(l, t, r, b);
        OV5(d_line(x0, y0, lx, ly));
        break;
    case T_RECT:
    case T_BOX:
        keep_box(l, t, r, b);
        OV5(d_rect(l, t, r, b, tool == T_BOX));
        break;
    case T_OVAL:
    case T_DISC:
        keep_box(l, t, r, b);
        OV5(d_oval(l, t, r, b, tool == T_DISC));
        break;
    case T_PENCIL:
    case T_ERASER:
    case T_BRUSH:
    case T_SPRAY:
        LogText("CPAINT STROKE");
        return;
    case T_SELECT:                      /* the band stays: the selection */
        sl = l; st = t; sr = r; sb = b;
        sel = 1;
        band_draw(1);
        LogText("CPAINT SELECTED");
        return;
    }
    change_show();
    CLOCK("shape");
    LogText("CPAINT DRAWN");
}

#ifdef CP_DESK
static unsigned int dn;                 /* (gate cpaint, V177: put aside by
                                           itself, back, then it quits) */
static unsigned char ds;
#endif

static void poll(void)
{
    unsigned int mx, my;
    int x, y;
    do {
        mx = mouseXPos;
        my = mouseYPosW;
    } while (mx != mouseXPos || my != mouseYPosW);
#ifdef CP_DESK
    if (++dn == 300 && ds == 0) {
        ds = 1;
        LogText("CPAINT ASIDE");
        TaskCtl(TASK_ASIDE, 0, 0);
    }
#endif
    if (vr_canvas_back()) {             /* back from the switcher */
        palette_out();
        chrome();
        title();
        view_all();
#ifdef CP_DESK
        LogText("CPAINT BACK");
        ds = 2;
        dn = 0;
#endif
    }
#ifdef CP_DESK
    if (ds == 2 && dn == 100) {
        ds = 3;
        m_quit();
    }
#endif
    if (whole || popup)
        return;
    SetPointer(mx >= VX && my >= VY ? PTR_CROSS : PTR_ARROW);
    x = clampx((int)mx - VX + scrx);
    y = clampy((int)my - VY + scry);
    if (floating) {                     /* a paste follows the pointer */
        float_at(x, y);
        return;
    }
    if (!dragging) {
        if (mx >= VX && my >= VY)
            status(x, y);
        else
            status(-1, -1);
        return;
    }
    if (tool == T_SPRAY) {              /* (while the button is down, moved or not) */
        change_begin();
        SAMPLE(x, y);
        OV4(t4_spray(x, y));
        change_show();
        lx = x;
        ly = y;
        return;
    }
    if (x == lx && y == ly)
        return;
    switch (tool) {
    case T_PENCIL:
        change_begin();
        CLOCK0();
        SAMPLE(x, y);
        OV5(d_line(lx, ly, x, y));
        change_show();
        CLOCK("pencil");
        break;
    case T_ERASER:
        change_begin();
        SAMPLE(x, y);
        erase_to(x, y);
        change_show();
        break;
    case T_BRUSH:
        change_begin();
        SAMPLE(x, y);
        OV4(t4_brush(lx, ly, x, y));
        change_show();
        break;
    default:
        band(0);
        lx = x;
        ly = y;
        band(1);
        status(x, y);
        return;
    }
    lx = x;
    ly = y;
    status(x, y);
}

static void press(void)
{
    unsigned int mx = mouseXPos, my = mouseYPosW;
    unsigned char t;
    if (mouseData & 0x80) {             /* a release */
        if (dragging) {
            poll();
            finish();
        }
        return;
    }
    if (whole) {
        whole_end();
        return;
    }
    if (popup) {
        popup_click(mx, my);
        return;
    }
    if (palmode) {
        OV4(t = t4_pal_click(mx, my));
        if (!t)
            pal_end();
        return;
    }
    if (texting)
        text_end();
    if (floating) {                     /* a paste put down */
        if (mx >= VX && my >= VY)
            float_drop();
        return;
    }
    if (mx >= VX && my >= VY) {
        start(clampx((int)mx - VX + scrx), clampy((int)my - VY + scry));
        return;
    }
    if (my < 14 || mx >= VX)            /* (the column starts at the bar: V170) */
        return;
    if (my >= TOOLY && my < TOOLY + 7 * CELLH) {     /* the tools */
        t = (my - TOOLY) / CELLH * 2 + (mx >= CELLW);
        if (t < TOOLS)
            select_tool(t);
        return;
    }
    if (my >= WELLY && my < WELLY + WELLH) {        /* the wells: the popup */
        popup_open(mx >= WBX);
        return;
    }
    if (my >= RECY && my < RECY + 4 * RH && mx >= RECX && mx < RECX + 4 * RW) {
        t = (my - RECY) / RH * 4 + (mx - RECX) / RW;
        set_cola(recent[t]);
    }
}

static void scroll(int dx, int dy)
{
    int x = (int)scrx + dx, y = (int)scry + dy;
    if (x < 0) x = 0;
    if (x > MAXSX) x = MAXSX;
    if (y < 0) y = 0;
    if (y > MAXSY) y = MAXSY;
    if (x == scrx && y == scry)
        return;
    scrx = x;
    scry = y;
    CLOCK0();
    view_all();
    CLOCK("scroll");
    LogText("CPAINT SCROLLED");
}

static void keys(void)
{
    unsigned char k = keyData;
    if (whole) {
        whole_end();
        return;
    }
    if (popup) {
        popup_close();
        return;
    }
    if (palmode) {
        pal_end();
        return;
    }
    if (floating) {                     /* (a key: the paste dropped) */
        float_hide();
        floating = 0;
        return;
    }
#ifdef CP_TEST
    if (k == KEY_F1) {                  /* (the test build: the picture to STEPn.PIC) */
        static char sn[] = "STEPA.PIC";
        cp_test_snap(sn);
        ++sn[4];
        return;
    }
#endif
    switch (k) {                        /* (left is backspace's code too) */
    case KEY_RIGHT: scroll(8, 0); return;
    case KEY_UP: scroll(0, -8); return;
    case KEY_DOWN: scroll(0, 8); return;
    case KEY_LEFT:
        if (keyDataMods & KEYM_ARROW)
            scroll(-8, 0);
        return;
    }
    if (!(keyDataMods & 2))
        return;
    switch (k & 0x1F) {
    case 'N' & 0x1F: m_new(); break;
    case 'O' & 0x1F: m_open(); break;
    case 'S' & 0x1F: m_save(); break;
    case 'Q' & 0x1F: m_quit(); break;
    case 'P' & 0x1F: m_print(); break;
    case 'Z' & 0x1F: m_undo(); break;
    case 'X' & 0x1F: m_cut(); break;
    case 'C' & 0x1F: m_copy(); break;
    case 'V' & 0x1F: m_paste(); break;
    case 'W' & 0x1F: m_whole(); break;
    }
}

int main(void)
{
    unsigned char opts = r0L, y, e;
    longNames = LONG_NAMES;
    LoadOverlay(1, 0);
    ovbank = r1L;
    LoadOverlay(2, 0);                  /* (V170) the column's art */
    ov2bank = r1L;
    LoadOverlay(3, 0);
    ov3bank = r1L;
    LoadOverlay(4, 0);                  /* (V171) the tools of stage 4 */
    ov4bank = r1L;
    LoadOverlay(5, 0);                  /* (V171) draw.c's tools */
    ov5bank = r1L;
    LoadOverlay(7, 0);                  /* (V172) the exports and the print */
    ov7bank = r1L;
    pbank = BankAlloc(BANDS);
    e = r1L;
    ubank = BankAlloc(BANDS);
    sbank = BankAlloc(1);
    {
        extern unsigned char f_sbank;
        f_sbank = sbank;                /* (the fill's seeds) */
    }
    if (!pbank || !ubank || !sbank) {
        message("Colour Paint needs 21 free", "RAM banks.");
        EnterDeskTop();
    }
    for (y = 0; y < PH; ++y) {
        rowbank[y] = y / BANDH;
        rowlo[y] = (unsigned char)(0xA000 + (y % BANDH) * PW);
        rowhi[y] = (0xA000 + (y % BANDH) * PW) >> 8;
    }
    (void)e;
    vr_home(opts);
    clear_pic();
    ul = 1; ur = 0;
    memcpy(pal, defpal, sizeof pal);
    for (y = 0; y < 16; ++y)
        recent[y] = 15 - y;
    dispBufferOn = ST_WR_FORE;          /* (the back screen is the picture's room) */
    if (vr_canvas_on(repaint)) {
        message("Colour Paint runs in the", "320 x 240 mode only.");
        EnterDeskTop();
    }
    layout();
    uiLook = LOOK_BAR;
    DoMenu((void *)&mbar, 0);
    chrome();
    fresh();
    otherPressVec = VR_FN(press);
    appMain = VR_FN(poll);
    keyVector = VR_FN(keys);
    LogText("CPAINT RUNNING");
    if ((opts & ST_LD_DATA) && dataLongName[0]) {
        strcpy(namebuf, (char *)dataLongName);
        nocvt();
        strcpy(docname, namebuf);
        opened();
    }
#ifdef CP_TEST
    cp_test_start();
#endif
    return 0;
}
