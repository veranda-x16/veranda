/* Veranda Gopher: a Gopher reader for Veranda (C, MIT; DECISIONS V109).

   An address line (gopher://host[:port]/Tselector), menus a line an item
   with a small mark for the kind, text pages wrapped to the window, a
   search's query asked in a box, other files downloaded to /DOCUMENTS;
   Back, Forward, Reload, Home; bookmarks in GOPHER.MARKS in the system's
   data folder (/VERANDA/.SYSTEM). Through vrnet (sdk vrnet.h): the Wi-Fi
   modem of TexElec's network card. Nothing waits: the main loop runs on
   while a page or a file comes, so menus, Stop and Alt+Tab work.

   This file, in main RAM: the start, the main loop's pass (tick), the
   helpers both overlays use, the card's side of a download, and the
   switcher's aside routine (vrnet's, then the file closed: a program
   with a stream open is not put aside; it is opened again, at its
   position, when the program comes back: Veranda FTP's way, V100).

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <vr.h>
#include <string.h>
#include <vrnet.h>
#include <vrser.h>
#include <theme.h>
#include "gopher.h"

char line[200];
unsigned char bOv2, bOv3, net_on;
unsigned char marks_n, marks_i, marks_err;      /* (marks.c's, in main RAM: ui.c reads them) */

/*---------------------------------------------------------------
  the font: the X16's CP437 set from ROM bank 6 (as Archive finds it),
  laid out for cs_draw (copy.s; V110) in the history's bank at $B000:
  10 tables of 256 bytes, one a glyph row (row r of character c at
  $B000 + 256 r + c; control characters as '?'), then a box character's
  top row and bottom row (0 for the others): they fill the taller cells'
  rows above and below the glyph. (V143, copy.s's cs_font) $A0-$FF are
  Veranda's set, ISO-8859-16, the ROM's own glyphs of it; $80-$9F private
  glyphs: CP437's pi, square, root, shades, blocks and box lines
 ---------------------------------------------------------------*/
static void load_font(void)
{
    cs_fbank = doc_bank + DOCBANKS + 1;
    cs_font(0x80);                        /* (copy.s, V143) */
}

/* cs_txt's first n characters at card x, pixel row y, in cells of 8 x h
   (8, 12 or 16; fl 1: reversed) */
void __fastcall__ cells(unsigned char x, unsigned int y, unsigned char n, unsigned char h, unsigned char fl)
{
    cs_x = x;
    cs_y = y;
    cs_n = n;
    cs_h = h;
    cs_fl = fl;
    cs_draw();
}

/* w cells at card x, pixel row y: s padded with spaces or cut (s may be
   in an overlay's bank: copied first); control characters as '?' */
void __fastcall__ put(unsigned char x, unsigned int y, const char *s, unsigned char w, unsigned char flags)
{
    unsigned char n = 0;
    unsigned char c;
    while (n < w && (c = s[n]) != 0)
        cs_txt[n++] = c >= 32 ? c : '?';
    while (n < w)
        cs_txt[n++] = ' ';
    if (w)
        cells(x, y, w, 8, flags);
}

/* the glyphs (11 x 11, as the shell's minis; bit 15 the left pixel) */
static const unsigned int glyphs[G_N][11] = {
    { 0x0000, 0xF000, 0x8FE0, 0x8020, 0x8020, 0x8020, 0x8020, 0x8020, 0x8020, 0xFFE0, 0x0000 },     /* folder */
    { 0x7F80, 0x4080, 0x4080, 0x5E80, 0x4080, 0x5E80, 0x4080, 0x5E80, 0x4080, 0x4080, 0x7F80 },     /* text */
    { 0x1E00, 0x2100, 0x4080, 0x4080, 0x4080, 0x4080, 0x2100, 0x1E80, 0x0040, 0x0020, 0x0000 },     /* search */
    { 0x4300, 0xC480, 0x4480, 0x4480, 0xE300, 0x0000, 0x3080, 0x4980, 0x4880, 0x4880, 0x31C0 },     /* binary */
    { 0x0000, 0xFFE0, 0x8020, 0x81A0, 0x81A0, 0x8820, 0x9C20, 0xBEA0, 0xFFE0, 0x0000, 0x0000 },     /* picture */
    { 0x0F80, 0x0F80, 0x0800, 0x0800, 0x0800, 0x0800, 0x7800, 0xF800, 0xF800, 0xF800, 0x7000 },     /* sound */
    { 0x1F00, 0x2480, 0x4A40, 0x8A20, 0xFFE0, 0x8A20, 0xFFE0, 0x8A20, 0x4A40, 0x2480, 0x1F00 },     /* web */
    { 0xFFE0, 0x8020, 0xA020, 0x9020, 0x8820, 0x9020, 0xA720, 0x8020, 0xFFE0, 0x0000, 0x3F80 },     /* telnet */
    { 0x0400, 0x0A00, 0x0A00, 0x1100, 0x1500, 0x2480, 0x2480, 0x4040, 0x4440, 0x8020, 0xFFE0 },     /* error */
    { 0x0000, 0x0C00, 0x1800, 0x3000, 0x6000, 0xFFE0, 0x6000, 0x3000, 0x1800, 0x0C00, 0x0000 },     /* back */
    { 0x0000, 0x0600, 0x0300, 0x0180, 0x00C0, 0xFFE0, 0x00C0, 0x0180, 0x0300, 0x0600, 0x0000 },     /* forward */
    { 0x0400, 0x0A00, 0x1100, 0x2080, 0x4040, 0xFFE0, 0x2080, 0x2E80, 0x2A80, 0x2A80, 0x3B80 },     /* home */
};

static unsigned char gbuf[3 * 16];

/* glyph m (G_NONE: nothing) with its left at pixel x, rows 2-12 of h
   rows from y, 3 cards drawn (opaque); fl: GL_DIM dotted (a button that
   does nothing now), GL_REV reversed */
void __fastcall__ glyph(unsigned int x, unsigned int y, unsigned char m, unsigned char h, unsigned char fl)
{
    unsigned char r, s = x & 7, *d = gbuf, e = fl & GL_REV ? 0xFF : 0;
    unsigned int v;
    for (r = 0; r < h; ++r, d += 3) {
        v = m < G_N && r >= 2 && r < 13 ? glyphs[m][r - 2] : 0;
        if (fl & GL_DIM)
            v &= r & 1 ? 0xAAAA : 0x5555;
        d[0] = (v >> (8 + s)) ^ e;
        d[1] = (v >> s) ^ e;
        d[2] = (unsigned char)(v << (8 - s)) ^ e;
    }
    WBitmapUp(gbuf, x >> 3, 3, y, 0x8000 | h);
}

/* a menu item's kind (its type; 'i' or 0 none): its glyph, its badge's
   colour (kcol; ui.c's) */
static const char ktype[] = "10h7238Tg;IpPs<d";
static const unsigned char kglyph[] = { G_FOLDER, G_TEXT, G_WEB, G_SEARCH, G_SEARCH, G_ERR, G_TEL, G_TEL,
    G_PIC, G_PIC, G_PIC, G_PIC, G_PIC, G_SOUND, G_SOUND, G_TEXT };
static const unsigned char kcolour[] = { YELLOW, CYAN, SKY2, GREEN, GREEN, RED, DUSK, DUSK,
    ORANGE, ORANGE, ORANGE, ORANGE, ORANGE, PURPLE, PURPLE, CHROME };
unsigned char kcol;

unsigned char __fastcall__ kind(unsigned char t)
{
    const char *p;
    kcol = 0;
    if (!t || t == 'i')
        return G_NONE;
    p = strchr(ktype, t);
    if (!p) {
        kcol = CHROME;
        return G_BIN;
    }
    kcol = kcolour[p - ktype];
    return kglyph[p - ktype];
}

/* a control's frame (Sunroom, V149: square, its corners' pixels cut) */
void __fastcall__ rframe(unsigned int l, unsigned int t, unsigned int r, unsigned int b)
{
    WHorizontalLine(0xFF, l + 1, r - 1, t);
    WHorizontalLine(0xFF, l + 1, r - 1, b);
    WVerticalLine(0xFF, l, t + 1, b - 1);
    WVerticalLine(0xFF, r, t + 1, b - 1);
}

/* the window's chrome and the scroll bar (vrwin.h): the SDK's sources
   compiled into overlay 2 (main RAM's room; vrscroll since V149), called
   from here */
#include <vrwin.h>
static const struct vrwin win = { 0, 2, 80, 58, 2, 2, VW_CLOSE };
struct vrscroll sbar = { SBX, SBY, SBLEN, 1, 0, 0, 0 };
unsigned int sb_at, sb_n;
#define OV2(x) RAMBANK = bOv2; x; RAMBANK = appBank

void __fastcall__ win_all(const char *t)
{
    OV2(vr_win(&win, t));
}

void __fastcall__ win_title(const char *t)
{
    OV2(vr_win_title(&win, t));
}

void __fastcall__ win_status(const char *left, const char *right)
{
    OV2(vr_win_status(&win, left, right));
}

/* (V149) the scroll bar (sbar) drawn; where x, y is on it (VS_*), its
   thumb's place and length (sb_at, sb_n) */
void sb_draw(void)
{
    OV2(vr_scroll(&sbar));
}

unsigned char __fastcall__ sb_hit(unsigned int x, unsigned int y)
{
    unsigned char h;
    OV2(h = vr_scroll_hit(&sbar, x, y); sb_n = vr_scroll_len(&sbar, &sb_at));
    return h;
}

void __fastcall__ ov2(void (*f)(void))
{
    RAMBANK = bOv2;
    f();
    RAMBANK = appBank;
}

char *__fastcall__ unum(char *p, unsigned long v)
{
    char t[10];
    unsigned char n = 0;
    do {
        t[n++] = '0' + (unsigned char)(v % 10);
        v /= 10;
    } while (v);
    while (n)
        *p++ = t[--n];
    *p = 0;
    return p;
}

/*---------------------------------------------------------------
  the toolbar (V110: here in main RAM, the interface's overlay's room)
 ---------------------------------------------------------------*/
/* the address line: a rounded frame on the toolbar, the address in the
   8 x 8 font */
void field(void)
{
    unsigned char o = 0;
    if (!v_edit)
        addr_of(gbusy && !gdl ? &go : &cur);
    if (alen > FW - 2)
        o = v_edit ? alen - (FW - 2) : 0;
    put(FX + 1, TOOLY + 4, abuf + o, FW - 2, 0);
    if (v_edit)                         /* the cursor: a reversed cell at the end */
        put(FX + 1 + alen - o, TOOLY + 4, fresh ? "" : " ", fresh ? 0 : 1, 1);
    if (v_edit && fresh)
        put(FX + 1, TOOLY + 4, abuf, alen > FW - 2 ? FW - 2 : alen, 1);
}

/* the toolbar: Back and Forward (one frame, dotted glyphs when there is
   nowhere to go), Home, the address line, Go (Stop while something
   comes; its name in the UI font, bold) */
void toolbar(void)
{
    unsigned int x;
    const char *t = gbusy ? "Stop" : "Go";
    SetPattern(0);
    WRectangle(0, TOOLY, 639, TOOLY + 14);
    glyph(BX * 8 + 6, TOOLY, G_BACK, 15, hpos ? 0 : GL_DIM);
    glyph(BX * 8 + 30, TOOLY, G_FWD, 15, hpos + 1 < hn ? 0 : GL_DIM);
    glyph(HOMEX * 8 + 6, TOOLY, G_HOME, 15, 0);
    rframe(BX * 8, TOOLY + 1, BX * 8 + 47, TOOLY + 13);
    WVerticalLine(0xFF, BX * 8 + 24, TOOLY + 1, TOOLY + 13);
    rframe(HOMEX * 8, TOOLY + 1, HOMEX * 8 + 23, TOOLY + 13);
    rframe(FX * 8, TOOLY + 1, (FX + FW) * 8 - 1, TOOLY + 13);
    rframe(GOX * 8, TOOLY + 1, GOX * 8 + 47, TOOLY + 13);
    field();
    UseFont(FONT_UI);
    currentMode = SET_BOLD;
    strcpy(line, t);
    for (x = 0; *t; ++t)
        x += GetCharWidth(*t) + 1;
    WPutString(line, GOX * 8 + 24 - (x >> 1), TOOLY + 3 + baselineOffset);
    currentMode = 0;
    UseSystemFont();
}

/*---------------------------------------------------------------
  dialog boxes (their texts copied below $A000)
 ---------------------------------------------------------------*/
struct askdlg {
    unsigned char pos;
    unsigned char t1, x1, y1, reg1;     /* DBVARSTR: the prompt (r6) */
    unsigned char t2, x2, y2, reg2, max;  /* DBGETSTRING (r5) */
    unsigned char ok, okx, oky;
    unsigned char cn, cnx, cny;
    unsigned char end;
};
static struct askdlg askbox = {
    DEF_DB_POS | 1,
    DBVARSTR, TXT_LN_X, TXT_LN_2_Y, 0x0E,
    DBGETSTRING, TXT_LN_X, TXT_LN_3_Y, 0x0C, 40,
    OK, DBI_X_0, DBI_Y_2,
    CANCEL, DBI_X_2, DBI_Y_2,
    0
};

struct msgdlg {
    unsigned char pos;
    unsigned char t1, x1, y1, reg1;
    unsigned char t2, x2, y2, reg2;
    unsigned char ok, okx, oky;
    unsigned char b2, b2x, b2y;
    unsigned char end;
};
static const struct msgdlg msgbox = {
    DEF_DB_POS | 1,
    DBVARSTR, TXT_LN_X, TXT_LN_2_Y, 0x0C,
    DBVARSTR, TXT_LN_X, TXT_LN_3_Y, 0x0E,
    OK, DBI_X_0, DBI_Y_2,
    0
};
static const struct msgdlg yesnobox = {
    DEF_DB_POS | 1,
    DBVARSTR, TXT_LN_X, TXT_LN_2_Y, 0x0C,
    DBVARSTR, TXT_LN_X, TXT_LN_3_Y, 0x0E,
    YES, DBI_X_0, DBI_Y_2,
    NO, DBI_X_2, DBI_Y_2,
    0
};

static char msga[52], msgb[52];

/* (the boxes' font is the system's: characters 32-126 only) */
static void __fastcall__ copy7(char *d, const char *s)
{
    unsigned char n = 0, c;
    while (n < 51 && (c = s[n]) != 0) {
        d[n++] = c >= 32 && c < 127 ? c : '?';
    }
    d[n] = 0;
}

static void texts(const char *a, const char *b)
{
    copy7(msga, a);
    copy7(msgb, b);
    r5 = (unsigned int)msga;
    r6 = (unsigned int)msgb;
}

#ifdef GOPHER_TEST
unsigned char t_box;                    /* a box is open (the test's player waits for it) */
unsigned char t_aside;                  /* the switcher put it aside */
unsigned char t_nbox;                   /* boxes opened */
unsigned char t_boxed;                  /* a box was open (the main loop's gap not counted) */
static char tlog[120];

void __fastcall__ gt_log(const char *s)
{
    strncpy(tlog, s, sizeof tlog - 1);
    LogText(tlog);
}

/* (V110) f in overlay 3, from overlay 1 */
void __fastcall__ t_ov3(void (*f)(void))
{
    RAMBANK = bOv3;
    f();
    RAMBANK = appBank;
}

/* (V110) f in overlay 1, from overlay 3 */
void __fastcall__ t_ui(void (*f)(void))
{
    RAMBANK = appBank;
    f();
    RAMBANK = bOv3;
}

static void box_log(void)
{
    t_box = 1;
    ++t_nbox;
    strcpy(tlog, "GO BOX ");
    strcat(tlog, msga);
    strcat(tlog, "|");
    strcat(tlog, msgb);
    LogText(tlog);
}
#define BOXED() (t_box = 0, t_boxed = 1)
#else
#define box_log()
#define BOXED()
#endif

void __fastcall__ message(const char *a, const char *b)
{
    texts(a, b);
    box_log();
    DoDlgBox((void *)&msgbox);
    BOXED();
}

unsigned char __fastcall__ yesno(const char *a, const char *b)
{
    unsigned char r;
    texts(a, b);
    box_log();
    r = DoDlgBox((void *)&yesnobox) == YES;
    BOXED();
    return r;
}

/* buf (below $A000, its text the default) edited; 0: cancelled */
unsigned char __fastcall__ ask(const char *prompt, char *buf, unsigned char max)
{
    unsigned char r;
    askbox.max = max;
    texts(prompt, "");
    r5 = (unsigned int)buf;
    box_log();
    r = DoDlgBox((void *)&askbox);
    BOXED();
    return r == OK || r == DBGETSTRING;
}

/*---------------------------------------------------------------
  a download's file on the card (Veranda FTP's, V100)
 ---------------------------------------------------------------*/
unsigned char xf_h;
char xf_name[64];
static unsigned long xf_fpos;           /* the file's position */
static unsigned char xf_slept;          /* closed for the switcher */

static unsigned char __fastcall__ fopen_(const char *name, unsigned char mode)
{
    unsigned char h;
    ChDir((char *)curDirName);
    h = FOpen((char *)name, mode);
    return h < 2 || h > 4 ? 0 : h;
}

/* (CMDR-DOS opens a file that is not there: its status says so) */
unsigned char __fastcall__ xf_exists(const char *name)
{
    unsigned char h = fopen_(name, 'r'), there;
    if (!h)
        return 0;
    there = dosStatus < 20;
    FClose(h);
    return there;
}

unsigned char xf_open(void)
{
    xf_fpos = 0;
    xf_slept = 0;
    xf_h = fopen_(xf_name, 'w');
    return xf_h != 0;
}

void __fastcall__ xf_close(unsigned char ok)
{
    if (xf_h)
        FClose(xf_h);
    xf_h = 0;
    if (!ok) {
        ChDir((char *)curDirName);
        FDelete(xf_name);               /* (a download that failed: no part of it kept) */
    }
    xf_slept = 0;
}

unsigned char __fastcall__ xf_write(const unsigned char *b, unsigned int n)
{
    if (!xf_h || FWrite(xf_h, (void *)b, n))
        return 0;
    xf_fpos += n;
    return 1;
}

/* back from the switcher: the file opened again where it was */
void xf_wake(void)
{
    if (!xf_slept)
        return;
    xf_slept = 0;
    xf_h = fopen_(xf_name, 'm');
    if (!xf_h)
        return;                         /* (xf_h 0: the download fails) */
    FSeek(xf_h, (unsigned int)xf_fpos, (unsigned int)(xf_fpos >> 16));
#ifdef GOPHER_TEST
    gt_log("GO FILE REOPENED");
#endif
}

/* asideVector: vrnet's first (the packet arriving taken whole, the
   port's interrupt off), then the file closed */
static unsigned int net_aside;

static void aside(void)
{
    if (net_aside)
        ((void (*)(void))net_aside)();
    if (xf_h) {
        FClose(xf_h);
        xf_h = 0;
        xf_slept = 1;
    }
#ifdef GOPHER_TEST
    t_aside = 1;
    gt_log("GO ASIDE");
#endif
}

void net_restart(void)
{
    net_stop();
    net_on = net_start(0, 576) == NET_OK;
    /* (V213: no net_ahead_on() since: one XON ahead, V211, broke this
       program on the user's card; DECISIONS V213) */
    net_aside = net_on ? asideVector : 0;
    asideVector = VR_FN(aside);
}

/*---------------------------------------------------------------
  the main loop's pass
 ---------------------------------------------------------------*/
static void tick(void)
{
    xf_wake();
    if (g_poll())
        ui_done();
    ui_tick();
#ifdef GOPHER_TEST
    RAMBANK = bOv3;
    gt_tick();
    RAMBANK = appBank;
#endif
}

int main(void)
{
    LoadOverlay(1, 0);                  /* (overlay 1: the interface, mapped for good, as appBank) */
    appBank = r1L;
    LoadOverlay(2, 0);                  /* (overlay 2: the bookmarks, the chrome) */
    bOv2 = r1L;
#ifdef GOPHER_TEST
    LoadOverlay(3, 0);
    bOv3 = r1L;
#endif
    RAMBANK = appBank;
    doc_bank = BankAlloc(DOCBANKS + 2);
    if (!doc_bank) {
        message("Veranda Gopher needs more memory", "(8 RAM banks).");
        EnterDeskTop();
    }
    load_font();
    net_restart();
    ui_start();
    appMain = VR_FN(tick);
    return 0;
}
