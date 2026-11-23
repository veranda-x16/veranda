/* Paint: a Veranda application in C, 640x480, one bit a pixel.

   The screen: the menu bar at the top, the Sunroom column on the left (x
   0-47: the tools, the patterns, the current pattern on the current
   colour, the colours, the status; chrome.c, overlay 2, DECISIONS V147),
   the drawing area for the rest (x 48-639, y 16-479).
   Everything is drawn to both screens; the back screen holds the picture,
   so menus and dialog boxes recover from it and the rubber band (line,
   rectangles) is drawn to the foreground only and taken away again with
   the back screen's copy.

   Colour: a paper colour for each 8 x 8 card of the drawing area (the
   kernel's colour map, ColorRect), and one ink colour for the whole
   picture (palette entry 1, SetColors: black at first; options/ink colour
   makes it the current colour). The drawing tools give the cards they
   touch the current colour (colour 0: the normal paper; colour 1 is the
   ink's colour). Paint runs in the kernel's tile mode (V101, V105): the
   drawing area's cards are the solid tiles of palette row 0, the column
   is tiles of its own in rows 2-11 (chrome.c).

   The tools (2 a row in the column): the selection, the fill, the
   pencil, the brush, the spray, the eraser, the line, the text, the
   rectangle, the filled rectangle, the oval, the filled oval (the brush,
   the spray, the ovals and the fill: tools.c, overlay 4).

   A document is a record file of type APPL_DATA: record 0 a small header,
   records 1-29 a band of 16 rows each (74 bytes a row), PackBits
   compressed; version 2: records 30 and 31 the colour map's two halves
   (29 card rows of 74 cards, two cards a byte, the left one in the high
   nibble); version 3: the header has the ink colour too (a colour cell,
   1-15). A version 1 picture opens in black and white, version 1 and 2
   in black ink.

   The clipboard (DECISIONS V54): edit/select makes the selection tool
   current (an area dragged out, snapped to whole cards, shown by a frame
   on the foreground); edit/cut and edit/copy write it to the Photo Scrap
   (from the back screen, with the cards' colours when any is set; cut
   then clears it); edit/paste reads the Photo Scrap into RAM banks and
   shows it floating on the foreground under the pointer (its top left
   on a card), and a press puts it down: the picture on both screens and
   its colours, if it has any, on its cards.

   Documents by their long names (DECISIONS V82): longNames on, so the
   GEOS file calls take names of up to LONG_MAX characters; File/Open and
   Save as are the SDK's dialog (vrchoose.h, V79), compiled into overlay 1
   (a banked overlay: file_dlg maps it), which lists the folder's .cvt
   files by their FAT names (the class is checked when the picture opens).

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <vr.h>
#include <string.h>
#include <scrap.h>
#include <fontpick.h>
#include <vrpath.h>
#include <theme.h>
#include <vrwin.h>
#include <vrchoose.h>
#include <vrpic.h>
#include "paint.h"

#define BANDSZ_ BANDSZ
#define MHALF   29              /* card rows a map record */
#define MRECSZ  (MHALF * MW / 2)

unsigned char tool = T_PENCIL;
unsigned char pat = 1;
unsigned char col;                      /* the current colour, 0 none */
unsigned char ink = 1;                  /* the ink colour (a colour cell) */
unsigned char dragging;
unsigned int x0, y0, lx, ly;            /* the press, the last position */
unsigned char texting;
static char text[41];
/* the text tool's font (options/text font: the font picker, fontpick.h;
   DECISIONS V62): the system font at first */
static struct fontpick tfont = { "System", 9, 0 };


static char docname[LONG_MAX + 1];
static char namebuf[LONG_MAX + 1];
static unsigned char ovbank;            /* overlay 1: the Open and Save dialog */
unsigned char ov2bank, ov3bank, ov4bank;        /* 2 the column, 3 its art, 4 the newer tools */
unsigned char band[BANDSZ];
char stbuf[12];                         /* the status's text (chrome.c) */

/* the selection (cards, inclusive pixels) and the floating paste */
static unsigned char sel;                       /* a selection is shown */
static unsigned int sl, st, sr, sb;
static unsigned char floating, fw, fbank, fcol; /* fcol: it has colours */
static unsigned int fh, fx, fy, frpb;           /* rows a bank */
#define FBANKS  6                               /* 5 for 74 x 464, 1 the colours */
unsigned char packed[BANDSZ + 16];

#ifdef PAINT_TEST
void paint_test_start(void);
void paint_test_snap(const char *name);
void paint_test_snapmap(const char *name);
void paint_test_snapall(const char *name);
void paint_test_clock_reset(void);
void paint_test_clock_log(const char *what);
void paint_test_stamp(unsigned char kind);
static unsigned char test_saves, test_opens, test_drafts_done;
#endif

/*---------------------------------------------------------------
  small helpers
 ---------------------------------------------------------------*/
unsigned int __fastcall__ clampx(unsigned int x)
{
    return x < CX ? CX : x > CR_ ? CR_ : x;
}

unsigned int __fastcall__ clampy(unsigned int y)
{
    return y < CY ? CY : y > CB ? CB : y;
}

static void order(unsigned int *a, unsigned int *b)
{
    unsigned int t;
    if (*a > *b) {
        t = *a;
        *a = *b;
        *b = t;
    }
}

/* a menu item's width: its text, and a shortcut after a tab 24 pixels on
   (the Veranda look's lists draw it right-aligned); $1F, a separator
   above it, is not drawn */
static unsigned int itemw(const char *s)
{
    unsigned int w = 0, t = 0;
    if (*s == 0x1F)
        ++s;
    for (; *s; ++s)
        if (*s == '\t') {
            t = w + 24;
            w = 0;
        } else
            w += GetCharWidth(*s);
    return t + w;
}

/*---------------------------------------------------------------
  colour: the cards from x0, y0 to x1, y1 (pixels; the drawing area's)
  get the current colour
 ---------------------------------------------------------------*/
void __fastcall__ colour(unsigned int x0, unsigned int y0, unsigned int x1, unsigned int y1)
{
    unsigned char a, b, c, d;
    if (x0 > x1) { unsigned int t = x0; x0 = x1; x1 = t; }
    if (y0 > y1) { unsigned int t = y0; y0 = y1; y1 = t; }
    a = clampx(x0) >> 3;
    b = clampx(x1) >> 3;
    c = clampy(y0) >> 3;
    d = clampy(y1) >> 3;
    ColorRect(a, b - a + 1, c, d - c + 1, col);
}

/* the cards a line passes through: a point every 8 pixels or less along
   it (16ths of a pixel: no long arithmetic) */
static void colour_line(unsigned int xa, unsigned int ya, unsigned int xb, unsigned int yb)
{
    int dx = (int)xb - (int)xa, dy = (int)yb - (int)ya;
    int n = (dx < 0 ? -dx : dx) > (dy < 0 ? -dy : dy) ? (dx < 0 ? -dx : dx) : (dy < 0 ? -dy : dy);
    int i, s = n / 8 + 1, sx = (dx << 4) / s, sy = (dy << 4) / s;
    unsigned int x = xa << 4, y = ya << 4;
    for (i = 0; i <= s; ++i) {
        colour(x >> 4, y >> 4, x >> 4, y >> 4);
        x += sx;
        y += sy;
    }
    colour(xb, yb, xb, yb);
}

/* the cards of a frame's four sides */
static void colour_frame(unsigned int l, unsigned int t, unsigned int r, unsigned int b)
{
    colour(l, t, r, t);
    colour(l, b, r, b);
    colour(l, t, l, b);
    colour(r, t, r, b);
}

static void clear_colours(void)
{
    ColorRect(MCARD, MW, MROW, MH, 0);
}

/* the colour cells' colours ($0RGB): VERA's palette entries 0-15 as the
   X16 starts, with Veranda's paper (white) and ink (black) for 0 and 1 */
static const unsigned int rgb[COLS] = {
    0xFFF, 0x000, 0x800, 0xAFE, 0xC4C, 0x0C5, 0x00A, 0xEE7,
    0xD85, 0x640, 0xF77, 0x333, 0x777, 0xAF6, 0x08F, 0xBBB
};

/* the ink: colour cell i (0 or 1: black), palette entry 1, the paper
   left alone */
static void set_ink(unsigned char i)
{
    ink = i < 2 || i >= COLS ? 1 : i;
    SetColors(0xFFFF, rgb[ink]);
    OV2(chrome_ink());                  /* (colour 1's swatch is the ink) */
}

static void clear_area(void)
{
    dispBufferOn = BOTH;
    SetPattern(0);
    WRectangle(CX, CY, CR_, CB);
    clear_colours();
}

/*---------------------------------------------------------------
  dialog boxes
 ---------------------------------------------------------------*/
struct namedlg {
    unsigned char pos;
    unsigned char t1, x1, y1, reg1;     /* DBVARSTR: the prompt (r6) */
    unsigned char t2, x2, y2, reg2, max;  /* DBGETSTRING: the name (r5) */
    unsigned char ok, okx, oky;
    unsigned char cn, cnx, cny;
    unsigned char end;
};
static const struct namedlg namebox = {
    DEF_DB_POS | 1,
    DBVARSTR, TXT_LN_X, TXT_LN_2_Y, 0x0E,
    DBGETSTRING, TXT_LN_X, TXT_LN_3_Y, 0x0C, 16,
    OK, DBI_X_0, DBI_Y_2,
    CANCEL, DBI_X_2, DBI_Y_2,
    0
};

struct msgdlg {
    unsigned char pos;
    unsigned char t1, x1, y1, reg1;     /* DBVARSTR (r5) */
    unsigned char t2, x2, y2, reg2;     /* DBVARSTR (r6) */
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

/* file/open: the pictures in the current directory (r5 the name chosen,
   r7L the type, r10 the class) */
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

static void message(const char *a, const char *b)
{
    r5 = (unsigned int)a;
    r6 = (unsigned int)b;
    DoDlgBox((void *)&msgbox);
}

static char errtext[] = "Error 00";

static void error(unsigned char e)
{
    errtext[6] = '0' + e / 10;
    errtext[7] = '0' + e % 10;
    message(errtext, docname);
}

/* ask for a name (into namebuf); 0: cancelled or empty */
static unsigned char ask(const char *prompt)
{
    unsigned char r;
    namebuf[16] = 0;                    /* (the box's field: 16 characters) */
    r5 = (unsigned int)namebuf;
    r6 = (unsigned int)prompt;
    r = DoDlgBox((void *)&namebox);
    if ((r != OK && r != DBGETSTRING) || namebuf[0] == 0)
        return 0;
    return 1;
}

/*---------------------------------------------------------------
  documents
 ---------------------------------------------------------------*/
/* the file's header block (SaveFile reads it before any band is packed:
   it shares packed's room) */
#define hdr packed
static const char dclass[] = "Paint Image V1.0";
static const char pclass[] = "Paint       V1.0";
static const char ddesc[] = "A picture from Paint.";
static unsigned char head[9] = { 'V', 'P', 'N', 'T', 3, CBYTES, BANDH, BANDS, 1 };

static void make_hdr(void)
{
    unsigned char i;
    memset(hdr, 0, 256);
    hdr[0] = (unsigned int)docname & 255;
    hdr[1] = (unsigned int)docname >> 8;
    hdr[2] = 3;
    hdr[3] = 21;
    hdr[4] = 0xBF;
    for (i = 0; i < 21; ++i) {          /* the icon: a page with a stroke */
        unsigned char *p = hdr + 5 + i * 3;
        if (i == 0 || i == 20) {
            p[0] = 0x7F; p[1] = 0xFF; p[2] = 0xFE;
        } else {
            p[0] = 0x40; p[1] = 0; p[2] = 0x02;
        }
    }
    for (i = 4; i < 17; ++i)
        hdr[5 + i * 3 + (i + 2) / 8] |= 0x80 >> ((i + 2) & 7);
    hdr[68] = 0x83;                     /* USR */
    hdr[69] = APPL_DATA;
    hdr[70] = 1;                        /* VLIR */
    memcpy(hdr + O_GHFNAME, dclass, sizeof dclass);
    memcpy(hdr + O_GH_AUTHOR, "Veranda", 8);
    memcpy(hdr + O_GHP_FNAME, pclass, sizeof pclass);
    memcpy(hdr + O_GHINFO_TXT, ddesc, sizeof ddesc);
}

static unsigned char save_doc(void)
{
    unsigned char e, b, r;
    unsigned int n;
    unsigned int y;
#ifdef PAINT_TEST
    paint_test_snapmap(test_saves == 0 ? "SAVED.MAP" : test_saves == 1 ? "SAVED2.MAP" : "SAVED3.MAP");
    paint_test_snap(test_saves == 0 ? "SAVED.RAW" : test_saves == 1 ? "SAVED2.RAW" : "SAVED3.RAW");
    ++test_saves;
#endif
    make_hdr();
    e = SaveFile(hdr, 0);
    if (e)
        return e;
    e = OpenRecordFile(docname);
    if (e)
        return e;
    head[8] = ink;                      /* (version 3: 9 bytes) */
    if ((e = AppendRecord()) || (e = WriteRecord((void *)head, head[4] == 3 ? 9 : 8)))
        goto out;
    dispBufferOn = ST_WR_FORE;          /* rows from the foreground */
    for (b = 0; b < BANDS; ++b) {
        y = CY + b * BANDH;
        for (r = 0; r < BANDH; ++r)
            ReadRow(band + r * CBYTES, CCARD, CBYTES, y + r);
        OV2(n = pack());                /* (PackBits: chrome.c's overlay has the room) */
        if ((e = AppendRecord()) || (e = WriteRecord(packed, n)))
            break;
    }
    /* version 2: the colour map, two records */
    for (b = 0; !e && head[4] >= 2 && b < 2; ++b) {
        unsigned char *q = band, cx;
        for (r = 0; r < MHALF; ++r)
            for (cx = 0; cx < MW; cx += 2)
                *q++ = GetCardColor(MCARD + cx, MROW + b * MHALF + r) << 4
                       | GetCardColor(MCARD + cx + 1, MROW + b * MHALF + r);
        if ((e = AppendRecord()) == 0)
            e = WriteRecord(band, MRECSZ);
    }
    dispBufferOn = BOTH;
out:
    r = CloseRecordFile();
    return e ? e : r;
}

static unsigned char open_doc(void)
{
    unsigned char e, b, r, ver;
    unsigned int n;
    unsigned int y;
    e = OpenRecordFile(docname);
    if (e)
        return e;
    if ((e = PointRecord(0)) || (e = ReadRecord(packed, sizeof packed)))
        goto out;
    ver = packed[4];
    if (r7 - (unsigned int)packed != (ver == 3 ? 9 : 8) || memcmp(packed, head, 4) || memcmp(packed + 5, head + 5, 3)
        || ver < 1 || ver > 3) {
        e = INCOMPATIBLE;
        goto out;
    }
    set_ink(ver == 3 ? packed[8] : 1);
    dispBufferOn = BOTH;
    for (b = 0; b < BANDS; ++b) {
        if ((e = PointRecord(b + 1)) || (e = ReadRecord(packed, sizeof packed)))
            break;
        n = r7 - (unsigned int)packed;
        OV2(n = unpack(n));
        if (!n) {
            e = INCOMPATIBLE;
            break;
        }
        y = CY + b * BANDH;
        for (r = 0; r < BANDH; ++r)
            WriteRow(band + r * CBYTES, CCARD, CBYTES, y + r);
    }
    /* the colours: version 2's map, version 1 black and white */
    clear_colours();
    for (b = 0; !e && ver >= 2 && b < 2; ++b) {
        unsigned char *q = band, cx, c, n, k, x;
        if ((e = PointRecord(BANDS + 1 + b)) || (e = ReadRecord(band, MRECSZ)))
            break;
        if (r7 - (unsigned int)band != MRECSZ) {
            e = INCOMPATIBLE;
            break;
        }
        for (r = 0; r < MHALF; ++r) {
            for (cx = 0; cx < MW; ) {           /* runs of a colour */
                k = cx & 1 ? q[cx >> 1] & 15 : q[cx >> 1] >> 4;
                for (n = 1, x = cx + 1; x < MW; ++x, ++n) {
                    c = x & 1 ? q[x >> 1] & 15 : q[x >> 1] >> 4;
                    if (c != k)
                        break;
                }
                if (k)
                    ColorRect(MCARD + cx, n, MROW + b * MHALF + r, 1, k);
                cx += n;
            }
            q += MW / 2;
        }
    }
out:
    r = CloseRecordFile();
    return e ? e : r;
}

/*---------------------------------------------------------------
  the menus
 ---------------------------------------------------------------*/
struct item { const char *text; unsigned char type; void *p; };
struct menu7 { unsigned char top, bottom; unsigned int left, right; unsigned char flags; struct item i[7]; };
struct menu3 { unsigned char top, bottom; unsigned int left, right; unsigned char flags; struct item i[3]; };
struct menu2 { unsigned char top, bottom; unsigned int left, right; unsigned char flags; struct item i[2]; };
struct menu4 { unsigned char top, bottom; unsigned int left, right; unsigned char flags; struct item i[4]; };
struct menu6 { unsigned char top, bottom; unsigned int left, right; unsigned char flags; struct item i[6]; };

static void m_new(void), m_open(void), m_save(void), m_saveas(void), m_export(void), m_print(void), m_quit(void);
static void m_clear(void), m_invert(void), m_about(void), m_desk(void), m_ink(void), m_font(void);
static void m_select(void), m_cut(void), m_copy(void), m_paste(void);

/* the menus in the Veranda look (DECISIONS V74, V79): the first one is
   Paint's own (about, the desk accessories). Sunroom's lists (V147): an
   item starting with $1F has a dotted line above it (a group starts), a
   shortcut after a tab is drawn right-aligned; the keys are keys() */
#define IH 14                   /* a vertical item's height (GEOS's look) */
static struct menu2 mpaint = { 14, 14 + 2 * IH, 0, 0, VERTICAL | 2, {
    { "About Paint", MENU_ACTION, m_about }, { "\x1f" "Desk accessory...", MENU_ACTION, m_desk } } };
static struct menu7 mfile = { 14, 14 + 7 * IH, 0, 0, VERTICAL | 7, {
    { "New\tCtrl N", MENU_ACTION, m_new }, { "Open...\tCtrl O", MENU_ACTION, m_open },
    { "\x1f" "Save\tCtrl S", MENU_ACTION, m_save }, { "Save as...", MENU_ACTION, m_saveas },
    { "\x1f" "Export...", MENU_ACTION, m_export }, { "Print...\tCtrl P", MENU_ACTION, m_print },
    { "\x1f" "Quit\tCtrl Q", MENU_ACTION, m_quit } } };
static struct menu6 medit = { 14, 14 + 6 * IH, 0, 0, VERTICAL | 6, {
    { "Clear", MENU_ACTION, m_clear }, { "Invert", MENU_ACTION, m_invert },
    { "\x1f" "Select", MENU_ACTION, m_select }, { "\x1f" "Cut\tCtrl X", MENU_ACTION, m_cut },
    { "Copy\tCtrl C", MENU_ACTION, m_copy }, { "Paste\tCtrl V", MENU_ACTION, m_paste } } };
static struct menu2 mopts = { 14, 14 + 2 * IH, 0, 0, VERTICAL | 2, {
    { "Ink colour", MENU_ACTION, m_ink }, { "Text font...", MENU_ACTION, m_font } } };
static struct menu4 mbar = { 0, 14, 0, 0, HORIZONTAL | UN_CONSTRAINED | 4, {
    { "Paint", SUB_MENU, &mpaint }, { "File", SUB_MENU, &mfile }, { "Edit", SUB_MENU, &medit },
    { "Options", SUB_MENU, &mopts } } };
static const char *const barnames[4] = { "Paint", "File", "Edit", "Options" };
static unsigned int barend;             /* where the bar's items end (the title after them) */

/* the menus' widths from the UI font (theme_menus: their font) */
static struct item *const items[4] = { mpaint.i, mfile.i, medit.i, mopts.i };
static const unsigned char nitems[4] = { 2, 7, 6, 2 };

static void layout(void)
{
    static unsigned int *const lefts[4] = { &mpaint.left, &mfile.left, &medit.left, &mopts.left };
    static unsigned int *const rights[4] = { &mpaint.right, &mfile.right, &medit.right, &mopts.right };
    unsigned int b = 0, w, m;
    unsigned char i, j;
    UseFont(FONT_UI);
    for (i = 0; i < 4; ++i) {
        *lefts[i] = b;
        for (m = 0, j = 0; j < nitems[i]; ++j)
            if ((w = itemw(items[i][j].text)) > m)
                m = w;
        *rights[i] = b + m + 16;
        b += itemw(mbar.i[i].text) + 8;
    }
    UseSystemFont();
    barend = vr_bar_end(barnames, 4);
    mbar.right = barend;                /* (the kernel's bar: its items' end) */
}

/* the window's title: the picture's name in the menu bar (the picture
   fills the screen under it: vrwin.h, V79) */
static void title(void)
{
    vr_bar_title(docname[0] ? docname : "Untitled", barend);
}

static void menus_off(void)
{
    GotoFirstMenu();
    title();                            /* (GotoFirstMenu draws the bar again) */
}

static void m_new(void)
{
    menus_off();
    clear_area();
    set_ink(1);
    docname[0] = 0;
    namebuf[0] = 0;
#ifdef PAINT_TEST
    paint_test_snap("CLEAR.RAW");
    paint_test_snapmap("CLEAR.MAP");
#endif
    title();
    LogText("PAINT NEW");
}

static void do_save(void)
{
    unsigned char e = save_doc();
    if (e)
        error(e);
    else
        title();
        LogText("PAINT SAVED");
}

/* namebuf without ".cvt" (a GEOS name, long or not: longNames) */
static void nocvt(void)
{
    unsigned char l = strlen(namebuf);
    if (l > 4 && namebuf[l - 4] == '.' && (namebuf[l - 3] | 0x20) == 'c' && (namebuf[l - 2] | 0x20) == 'v'
        && (namebuf[l - 1] | 0x20) == 't')
        namebuf[l - 4] = 0;
}

/* the Open and Save dialog (vrchoose.h), in overlay 1: the name into
   namebuf; 0: cancelled or empty */
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

#ifdef PAINT_TEST
/* after "no pictures": five empty documents for the list to scroll */
static void test_drafts(void)
{
    unsigned char i;
    strcpy(docname, "Draft 1");
    for (i = 0; i < 5; ++i) {
        docname[6] = '1' + i;
        make_hdr();
        SaveFile(hdr, 0);
    }
    /* and "Zebra", an empty picture in version 1's format (no colours) */
    strcpy(docname, "Zebra");
    head[4] = 1;
    save_doc();
    head[4] = 3;
    --test_saves;
    docname[0] = 0;
}
#endif

static void opened(void);

static void m_open(void)
{
    menus_off();
    namebuf[0] = 0;
    if (!file_dlg(VRF_OPEN, "Open a picture")) {
#ifdef PAINT_TEST
        if (!test_drafts_done) {        /* (the first open, cancelled: the
                                           documents for the next ones) */
            test_drafts_done = 1;
            LogText("PAINT NO PICTURES");
            test_drafts();
        }
#endif
        return;
    }
    strcpy(docname, namebuf);
    opened();
}

/* docname opened (a message if it is not a picture) */
static void opened(void)
{
    unsigned char e;
    e = open_doc();
    if (e) {
        error(e);
        docname[0] = 0;
    } else {
        title();
        LogText("PAINT OPENED");
        LogText(docname);
#ifdef PAINT_TEST
        paint_test_snapmap(test_opens == 0 ? "OPENED.MAP" : test_opens == 1 ? "OLD.MAP" :
                           test_opens == 2 ? "OPENED2.MAP" : "OPENED3.MAP");
        paint_test_snap(test_opens == 0 ? "OPENED.RAW" : test_opens == 1 ? "OLD.RAW" :
                        test_opens == 2 ? "OPENED2.RAW" : "OPENED3.RAW");
        ++test_opens;
#endif
    }
}

/* file/export: the picture (from the back screen, which holds it without
   the rubber band) as a BMP file for a PC, 4 bits a pixel with the
   colours: the name typed, ".bmp" added if it has no dot */
static char expname[22];

static void m_export(void)
{
    unsigned char e;
    menus_off();
    strcpy(namebuf, docname);
    if (!ask("Export the picture (BMP) as:"))
        return;
    strcpy(expname, namebuf);
    if (!strchr(expname, '.'))
        strcat(expname, ".bmp");
    OV2(chrome_classic(1));             /* (the kernel exports the classic map's colours) */
    e = ExportRect(expname, CX, CY, CR_, CB, 0x81);    /* the back screen, 4 bpp */
    OV2(chrome_classic(0));
    if (e)
        error(e);
    else {
        LogText("PAINT EXPORTED");
        LogText(expname);
    }
}

/* file/print: the picture to a PDF file (the kernel's print service,
   DECISIONS V38), after a page setup box: the paper (A4 or US Letter)
   and the size (fit to the page, or GEOS's 80 pixels an inch), at 150
   dots an inch, in the ink's colour and the cards' colours; the name
   typed, ".pdf" added if it has no dot */
#define PBX 224                 /* the default box at 640x480 */
#define PBY 192
static unsigned char paper;     /* 0 A4, 1 Letter */
static unsigned char fitpage = 1;
static char setup[32];

static void setup_text(void)
{
    strcpy(setup, paper ? "Letter" : "A4");
    strcat(setup, fitpage ? ", fit to the page" : ", 80 pixels an inch");
}

static void setup_draw(void)
{
    unsigned char keep = dispBufferOn;
    dispBufferOn = ST_WR_FORE;
    SetPattern(0);
    WRectangle(PBX + 8, PBY + TXT_LN_2_Y - 9, PBX + 184, PBY + TXT_LN_2_Y + 3);
    WPutString(setup, PBX + TXT_LN_X, PBY + TXT_LN_2_Y);
    dispBufferOn = keep;
}

static void t_paper(void)
{
    paper ^= 1;
    setup_text();
    setup_draw();
}

static void t_fit(void)
{
    fitpage ^= 1;
    setup_text();
    setup_draw();
}

/* the two buttons' labels, right of them (the icons are drawn last) */
static void labels(void)
{
    unsigned char keep = dispBufferOn;
    dispBufferOn = ST_WR_FORE;
    WPutString("paper", PBX + 8 + 22, PBY + 44 + 9);
    WPutString("size", PBX + 72 + 22, PBY + 44 + 9);
    dispBufferOn = keep;
}

/* a button: a frame of 2 cards by 12 rows (a compacted bitmap) */
#define FRAME_ROW 0x81, 0x80, 0x81, 0x01
static const unsigned char framepic[] = {
    2, 0xFF,
    FRAME_ROW, FRAME_ROW, FRAME_ROW, FRAME_ROW, FRAME_ROW,
    FRAME_ROW, FRAME_ROW, FRAME_ROW, FRAME_ROW, FRAME_ROW,
    2, 0xFF
};
struct uicon { const void *pic; unsigned char x, y, w, h; void (*fn)(void); };
static const struct uicon ipaper = { framepic, 0, 0, 2, 12, t_paper };
static const struct uicon ifit = { framepic, 0, 0, 2, 12, t_fit };

struct printdlg {
    unsigned char pos;
    unsigned char t1, x1, y1; const char *title;        /* DBTXTSTR */
    unsigned char t2, x2, y2, reg2;                     /* DBVARSTR: the setup (r5) */
    unsigned char u1, u1x, u1y; const struct uicon *i1; /* DBUSRICON */
    unsigned char u2, u2x, u2y; const struct uicon *i2;
    unsigned char r; void (*rout)(void);                /* DB_USR_ROUT */
    unsigned char ok, okx, oky;
    unsigned char cn, cnx, cny;
    unsigned char end;
};
static const struct printdlg printbox = {
    DEF_DB_POS | 1,
    DBTXTSTR, TXT_LN_X, TXT_LN_1_Y, "Print the picture to a PDF file:",
    DBVARSTR, TXT_LN_X, TXT_LN_2_Y, 0x0C,
    DBUSRICON, 1, 44, &ipaper,
    DBUSRICON, 9, 44, &ifit,
    DB_USR_ROUT, labels,
    OK, DBI_X_0, DBI_Y_2,
    CANCEL, DBI_X_2, DBI_Y_2,
    0
};

static void m_print(void)
{
    unsigned char e, r;
    menus_off();
    setup_text();
    r5 = (unsigned int)setup;
    if (DoDlgBox((void *)&printbox) != OK)
        return;
    strcpy(namebuf, docname);
    if (!ask("Print the picture (PDF) as:"))
        return;
    strcpy(expname, namebuf);
    if (!strchr(expname, '.'))
        strcat(expname, ".pdf");
    LogText("PAINT PRINTING");
    e = PrintOpen(expname, paper ? PRINT_LETTER : 0);
    if (!e) {
        /* the back screen (the picture without a rubber band), the
           colours from the classic map (the kernel's) */
        OV2(chrome_classic(1));
        e = PrintRect(CX, CY, CR_, CB, PRINT_BACK | PRINT_COLOR | (fitpage ? PRINT_FIT : 0));
        OV2(chrome_classic(0));
        r = PrintClose();
        if (!e)
            e = r;
    }
    if (e)
        error(e);
    else {
        LogText("PAINT PRINTED");
        LogText(expname);
    }
}

static void m_quit(void)
{
    menus_off();
    EnterDeskTop();
}

static void m_clear(void)
{
    menus_off();
    clear_area();
}

static void m_invert(void)
{
    menus_off();
    dispBufferOn = BOTH;
    WInvertRectangle(CX, CY, CR_, CB);
    LogText("PAINT INVERTED");
}

/* options/ink colour: the ink becomes the current colour (none, or
   colour 1: black again) */
static void m_ink(void)
{
    menus_off();
    set_ink(col);
    LogText("PAINT INK");
}

static void m_font(void)
{
    menus_off();
    if (FontPick(&tfont) == OK && tfont.handle != FONT_NONE)
        LogText("PAINT FONT");
}

static void m_about(void)
{
    menus_off();
    message("Paint 1.0 for Veranda", "640x480, one bit a pixel. MIT licence");
    LogText("PAINT ABOUT");
}

/* Paint/desk accessory: a desk accessory from the list (DBGETFILES, type
   DESK_ACC), started with GetFile; it comes back here when the accessory
   ends (RstrAppl), with Paint's memory, state and screens as they were */
static void m_desk(void)
{
    unsigned char r;
    menus_off();
    namebuf[0] = 0;
    r5 = (unsigned int)namebuf;
    r7L = DESK_ACC;
    r10 = 0;
    vr_cd(VR_APPS);                     /* (with the applications: V71) */
    r = DoDlgBox((void *)&filebox);
    vr_cdback();
    if (r == DBGETFILES) {
        message("There are no desk accessories", "with the applications.");
        return;
    }
    if (r != OPEN || !namebuf[0])
        return;
#ifdef PAINT_TEST
    paint_test_snapall("PRE.RAW");
    paint_test_snapmap("PRE.MAP");
    paint_test_clock_reset();
#endif
    vr_cd(VR_APPS);
    r = GetFile(namebuf, 0, 0, 0, 0);
#ifdef PAINT_TEST
    paint_test_clock_log("back");       /* from RstrAppl (calc_test_clock_reset) */
#endif
    vr_cdback();
    OV2(chrome_again());                /* (palette rows 2-11: the accessory may have used them) */
    if (r) {
        error(r);
        return;
    }
    LogText("PAINT DESK BACK");
#ifdef PAINT_TEST
    paint_test_snapall("POST.RAW");
    paint_test_snapmap("POST.MAP");
#endif
}

/*---------------------------------------------------------------
  drawing
 ---------------------------------------------------------------*/
static void eraser(unsigned int x, unsigned int y)
{
    unsigned int r = x + 7, b = y + 7;
    SetPattern(0);
    WRectangle(x, y, r > CR_ ? CR_ : r, b > CB ? CB : b);
}

/* the eraser from the last position to x, y in steps of 4 */
static void erase_to(unsigned int x, unsigned int y)
{
    int dx = (int)x - (int)lx, dy = (int)y - (int)ly;
    int n = (dx < 0 ? -dx : dx) > (dy < 0 ? -dy : dy) ? (dx < 0 ? -dx : dx) : (dy < 0 ? -dy : dy);
    int i, s = n / 4;
    for (i = 1; i <= s; ++i)
        eraser(lx + (long)dx * i / s, ly + (long)dy * i / s);
    eraser(x, y);
}

unsigned int rl, rt, rr, rb;            /* the rubber band shown */
static void sel_frame(unsigned char show), sel_hide(void), float_at(unsigned int x, unsigned int y), float_drop(void);

static void band_box(unsigned int x, unsigned int y)
{
    rl = x0; rr = x; rt = y0; rb = y;
    order(&rl, &rr);
    order(&rt, &rb);
    if (tool == T_SELECT) {             /* whole cards */
        rl &= ~7;
        rt &= ~7;
        rr |= 7;
        rb |= 7;
    }
}

/* the rubber band: shown (foreground only) or taken away */
static void band_show(void)
{
    if (tool >= T_OVAL) {
        OV4(oval_band(1));
        return;
    }
    dispBufferOn = ST_WR_FORE;
    if (tool == T_LINE)
        WDrawLine(DRAW_INK, x0, y0, lx, ly);
    else
        WFrameRectangle(0xFF, rl, rt, rr, rb);
    dispBufferOn = BOTH;
}

static void band_hide(void)
{
    if (tool >= T_OVAL) {
        OV4(oval_band(0));
        return;
    }
    dispBufferOn = ST_WR_FORE;
    if (tool == T_LINE)
        WDrawLine(DRAW_RECOVER, x0, y0, lx, ly);
    else {
        WRecoverRectangle(rl, rt, rr, rt);
        WRecoverRectangle(rl, rb, rr, rb);
        WRecoverRectangle(rl, rt, rl, rb);
        WRecoverRectangle(rr, rt, rr, rb);
    }
    dispBufferOn = BOTH;
}

static void keys(void);

static void text_done(void)
{
    keyVector = VR_FN(keys);
    texting = 0;
    if (text[0]) {
        if (tfont.handle)               /* (GetString's y: the text's top) */
            colour(x0, y0, x0 + itemw(text), y0 + curHeight - 1);
        else
            colour(x0, y0 - 7, x0 + itemw(text), y0 + 2);
    }
    UseSystemFont();
}

static void text_end(void)
{
    if (texting) {
        PromptOff();
        text_done();
    }
}

static void start(unsigned int x, unsigned int y)
{
    x0 = lx = x;
    y0 = ly = y;
    dispBufferOn = BOTH;
    switch (tool) {
    case T_PENCIL:
        WDrawPoint(DRAW_INK, x, y);
        colour(x, y, x, y);
        break;
    case T_ERASER:
        eraser(x, y);
        break;
    case T_BRUSH:
        OV4(brush_to(x, y));
        break;
    case T_SPRAY:
        OV4(spray_at(x, y));
        break;
    case T_FILL:
#ifdef PAINT_TEST
        paint_test_clock_reset();
#endif
        OV4(fill_at(x, y));
#ifdef PAINT_TEST
        paint_test_clock_log("fill");
#endif
        LogText("PAINT FILLED");
        return;
    case T_TEXT:
        UseFont(tfont.handle);
        if (y > CB - 10)
            y = CB - 10;
        if (tfont.handle && y > CB + 1 - curHeight)
            y = CB + 1 - curHeight;
        x0 = x;
        y0 = y;
        text[0] = 0;
        texting = 1;
        keyVector = VR_FN(text_done);
        WGetString(text, 40, x, y, 0, 0);
        return;
    default:
        band_box(x, y);
        band_show();
        break;
    }
    dragging = 1;
}

static void finish(void)
{
    dragging = 0;
    dispBufferOn = BOTH;
    switch (tool) {
    case T_LINE:
        band_hide();
        WDrawLine(DRAW_INK, x0, y0, lx, ly);
        colour_line(x0, y0, lx, ly);
        break;
    case T_RECT:
        band_hide();
        WFrameRectangle(0xFF, rl, rt, rr, rb);
        colour_frame(rl, rt, rr, rb);
        break;
    case T_BOX:
        band_hide();
        SetPattern(pat);
        WRectangle(rl, rt, rr, rb);
        colour(rl, rt, rr, rb);
        break;
    case T_OVAL:
    case T_DISC:
        band_hide();
        OV4(oval_draw());
        break;
    case T_SELECT:                      /* the band stays: the selection */
        sel = 1;
        sl = rl; st = rt; sr = rr; sb = rb;
        LogText("PAINT SELECTED");
        break;
    }
}

/* appMain: follow the pointer while the button is down; the status */
#ifdef PAINT_TEST
static void poll2(void);
static char tname[] = "drag a";

/* (the test build: each frame's work while a tool is dragged, in cycles
   on the console: "TIME drag" and the tool's letter, a the selection) */
static void poll(void)
{
    unsigned char d = dragging;
    paint_test_clock_reset();
    poll2();
    if (d) {
        tname[5] = 'a' + tool;
        paint_test_clock_log(tname);
    }
}

static void poll2(void)
#else
static void poll(void)
#endif
{
    unsigned int x, y;
    /* the interrupt moves the pointer: read until x and y agree */
    do {
        x = mouseXPos;
        y = mouseYPosW;
    } while (x != mouseXPos || y != mouseYPosW);
    /* the pointer's shape (DECISIONS V51): over the drawing area the
       crosshair, the I-beam for the text tool; the arrow elsewhere (the
       kernel shows the arrow itself over a menu or a dialog box) */
    SetPointer(x >= CX && y >= CY ? (tool == T_TEXT ? PTR_IBEAM : PTR_CROSS) : PTR_ARROW);
    if (vr_pic_back())                  /* (back from the switcher: the column's rows again) */
        OV2(chrome_again());
    if (floating) {
        float_at(x, y);
        OV2(chrome_status(x, y));
        return;
    }
    if (!dragging) {
        OV2(chrome_status(x, y));
        return;
    }
    x = clampx(x);
    y = clampy(y);
    if (tool == T_SPRAY)                /* (while the button is down, moved or not) */
        OV4(spray_at(x, y));
    if (x == lx && y == ly)
        return;
    dispBufferOn = BOTH;
    switch (tool) {
    case T_PENCIL:
        WDrawLine(DRAW_INK, lx, ly, x, y);
        colour(lx, ly, x, y);           /* (a short segment: its box) */
        break;
    case T_ERASER:
        erase_to(x, y);
        break;
    case T_BRUSH:
        OV4(brush_to(x, y));
        break;
    case T_SPRAY:
        break;
    default:
        band_hide();
        lx = x;
        ly = y;
        band_box(x, y);
        band_show();
        OV2(chrome_status(x, y));
        return;
    }
    lx = x;
    ly = y;
    OV2(chrome_status(x, y));
}

static void select_tool(unsigned char t)
{
    unsigned char old = tool;
    sel_hide();
    tool = t;
    OV2(chrome_tool(old));
}

static void select_col(unsigned char c)
{
    unsigned char old = col;
    col = c;
    OV2(chrome_col(old));
}

static void select_pat(unsigned char p)
{
    unsigned char old = pat;
    pat = p;
    OV2(chrome_pat(old));
}

/*---------------------------------------------------------------
  the clipboard: the selection, cut, copy and paste through the Photo
  Scrap (lib/veranda.lib's scrap.h)
 ---------------------------------------------------------------*/

/* the selection's frame on the foreground, or taken away */
static void sel_frame(unsigned char show)
{
    dispBufferOn = ST_WR_FORE;
    if (show)
        WFrameRectangle(0xFF, sl, st, sr, sb);
    else {
        WRecoverRectangle(sl, st, sr, st);
        WRecoverRectangle(sl, sb, sr, sb);
        WRecoverRectangle(sl, st, sl, sb);
        WRecoverRectangle(sr, st, sr, sb);
    }
    dispBufferOn = BOTH;
}

static void sel_hide(void)
{
    if (sel)
        sel_frame(0);
    sel = 0;
}

static void float_hide(void);

static void m_select(void)
{
    menus_off();
    text_end();
    sel_hide();
    if (floating) {
        float_hide();
        floating = 0;
    }
    select_tool(T_SELECT);
}

/* the selection's rows from the back screen (no frame there) and its
   cards' colours */
static void get_row(unsigned int y, unsigned char *row)
{
    dispBufferOn = ST_WR_BACK;
    ReadRow(row, sl >> 3, (sr - sl + 1) >> 3, st + y);
}

static unsigned char get_col(unsigned char cx, unsigned char cy)
{
    return ink << 4 | GetCardColor((sl >> 3) + cx, (st >> 3) + cy);
}

static unsigned char copy_sel(void)
{
    unsigned char x, y, any = 0, e;
    if (!sel) {
        message("Select an area first", "(edit/select).");
        return 1;
    }
    for (y = st >> 3; y <= sb >> 3; ++y)
        for (x = sl >> 3; x <= sr >> 3; ++x)
            any |= GetCardColor(x, y);
    e = scrap_put_photo((sr - sl + 1) >> 3, sb - st + 1, get_row, any ? get_col : 0);
    dispBufferOn = BOTH;
    if (e)
        error(e);
#ifdef PAINT_TEST
    paint_test_snapmap("COPY.MAP");
    paint_test_stamp(SCRAP_PHOTO);
#endif
    return e;
}

static void m_copy(void)
{
    menus_off();
    if (copy_sel() == 0) {
        sel_frame(1);                   /* (the menu took a part of it) */
        LogText("PAINT COPIED");
    }
}

static void m_cut(void)
{
    menus_off();
    if (copy_sel())
        return;
    sel_frame(0);
#ifdef PAINT_TEST
    paint_test_snap("PRECUT.RAW");
#endif
    SetPattern(0);
    WRectangle(sl, st, sr, sb);
    ColorRect(sl >> 3, (sr - sl + 1) >> 3, st >> 3, (sb - st + 1) >> 3, 0);
    sel = 0;
    LogText("PAINT CUT");
#ifdef PAINT_TEST
    paint_test_snapmap("CUT.MAP");
#endif
}

/* the paste: fw x fh in banks from fbank, frpb rows a bank; the
   colours, fw a card row, in the last bank */
static unsigned char *frow(unsigned int y)
{
    RAMBANK = fbank + y / frpb;
    return (unsigned char *)(0xA000 + (y % frpb) * fw);
}

static void put_row(unsigned int y, const unsigned char *row)
{
    unsigned char old = RAMBANK;
    if (y < fh)
        memcpy(frow(y), row, fw);
    RAMBANK = old;
}

static void put_col(unsigned char cx, unsigned char cy, unsigned char c)
{
    unsigned char old = RAMBANK;
    if (cx < fw && cy < MH) {
        RAMBANK = fbank + FBANKS - 1;
        *(unsigned char *)(0xA000 + cy * fw + cx) = c;
        fcol = 1;
    }
    RAMBANK = old;
}

/* the picture at fx, fy on the screens given (clipped to the screen) */
static void float_draw(unsigned char screens)
{
    unsigned int y;
    unsigned char w = fw, old = RAMBANK;
    if ((fx >> 3) + w > 80)
        w = 80 - (fx >> 3);
    dispBufferOn = screens;
    for (y = 0; y < fh && fy + y <= CB; ++y) {
        memcpy(band, frow(y), w);
        RAMBANK = old;
        WriteRow(band, fx >> 3, w, fy + y);
    }
    dispBufferOn = BOTH;
}

static void float_hide(void)
{
    unsigned int r = fx + fw * 8 - 1, b = fy + fh - 1;
    dispBufferOn = ST_WR_FORE;
    WRecoverRectangle(fx, fy, r > CR_ ? CR_ : r, b > CB ? CB : b);
    dispBufferOn = BOTH;
}

/* the floating picture's top left to the card at x, y */
static void float_at(unsigned int x, unsigned int y)
{
    x = clampx(x) & ~7;
    y = clampy(y) & ~7;
    if (x == fx && y == fy)
        return;
    if (fx != 0xFFFF)
        float_hide();
    fx = x;
    fy = y;
    float_draw(ST_WR_FORE);
}

/* put it down: both screens, and its colours */
static void float_drop(void)
{
    unsigned char cx, cy, c, old = RAMBANK;
    float_draw(BOTH);
    for (cy = 0; fcol && cy < (fh + 7) >> 3 && (fy >> 3) + cy < MROW + MH; ++cy)
        for (cx = 0; cx < fw && (fx >> 3) + cx < 80; ++cx) {
            RAMBANK = fbank + FBANKS - 1;
            c = *(unsigned char *)(0xA000 + cy * fw + cx);
            RAMBANK = old;
            ColorRect((fx >> 3) + cx, 1, (fy >> 3) + cy, 1, c & 15);
        }
    floating = 0;
    LogText("PAINT PASTED");
#ifdef PAINT_TEST
    paint_test_snapmap("PASTE.MAP");
#endif
}

static void m_paste(void)
{
    unsigned char w, e;
    unsigned int h, x, y;
    menus_off();
    sel_hide();
    if (floating) {
        float_hide();
        floating = 0;
    }
    e = scrap_photo_size(&w, &h);
    scrap_close();
    if (e) {
        message("There is no picture", "on the clipboard.");
        return;
    }
    if (!fbank && (fbank = BankAlloc(FBANKS)) == 0) {
        error(NO_BANKS);
        return;
    }
    fw = w > MW ? MW : w;
    fh = h > CB - CY + 1 ? CB - CY + 1 : h;
    frpb = 8192 / fw;
    fcol = 0;
    if ((e = scrap_get_photo(put_row, put_col)) != 0) {
        error(e);
        return;
    }
    floating = 1;
    fx = fy = 0xFFFF;
    do {
        x = mouseXPos;
        y = mouseYPosW;
    } while (x != mouseXPos || y != mouseYPosW);
    float_at(x, y);
    LogText("PAINT FLOATING");
}

/* otherPressVec: presses and releases off the menus */
static void press(void)
{
    unsigned int x = mouseXPos, y = mouseYPosW;
    unsigned char k;
    if (mouseData & 0x80) {             /* a release */
        if (dragging) {
            poll();
            finish();
        }
        return;
    }
    text_end();
    if (floating) {                     /* a paste put down */
        if (x >= CX && y >= CY) {
            float_at(x, y);
            float_drop();
        }
        return;
    }
    if (sel) {
        sel_frame(0);
        sel = 0;
    }
    if (x >= CX && y >= CY) {
        start(x, y);
        return;
    }
    if (x >= CX || y < CY)
        return;
    OV2(k = chrome_hit(x, y));          /* the column: a tool, a pattern, a colour */
    switch (k >> 5) {
    case 1:
        select_tool(k & 31);
        break;
    case 2:
        select_pat(k & 31);
        break;
    case 3:
        select_col(k & 31);
        break;
    }
}

/* keyVector (but while the text tool types): the menus' shortcuts */
static void keys(void)
{
    unsigned char k = keyData;
    if (!(keyDataMods & 2))
        return;
    k &= 0x1F;                          /* (Ctrl + a letter: 1-26, either case) */
    switch (k) {
    case 'N' & 0x1F: m_new(); break;
    case 'O' & 0x1F: m_open(); break;
    case 'S' & 0x1F: m_save(); break;
    case 'P' & 0x1F: m_print(); break;
    case 'Q' & 0x1F: m_quit(); break;
    case 'X' & 0x1F: m_cut(); break;
    case 'C' & 0x1F: m_copy(); break;
    case 'V' & 0x1F: m_paste(); break;
    }
}

int main(void)
{
    unsigned char opts = r0L;
    longNames = LONG_NAMES;             /* documents by their long names (V82) */
    LoadOverlay(1, 0);
    ovbank = r1L;
    LoadOverlay(2, 0);
    ov2bank = r1L;
    LoadOverlay(3, 0);
    ov3bank = r1L;
    LoadOverlay(4, 0);
    ov4bank = r1L;
    vr_home(opts);                      /* Open and Save: /DOCUMENTS first (V71) */
    OV2(chrome_init());                 /* tile mode, the screen, the column */
    layout();
    theme_load();
    theme_menus();                      /* the menu bar (V74; black and white: Paint's palette is its pictures') */
    DoMenu((void *)&mbar, 0);
    title();
    otherPressVec = VR_FN(press);
    appMain = VR_FN(poll);
    keyVector = VR_FN(keys);
    LogText("PAINT RUNNING");
    if ((opts & ST_LD_DATA) && dataLongName[0]) {     /* (a document: its whole name, V82) */
        strcpy(namebuf, (char *)dataLongName);
        nocvt();
        strcpy(docname, namebuf);
        opened();
    }
#ifdef PAINT_TEST
    paint_test_start();
#endif
    return 0;
}
