/* Veranda Gemini: a Gemini browser for Veranda (C, MIT; DECISIONS V118).

   An address line (gemini://host[:port]/path), gemtext pages (links,
   headings, lists, quotes, preformatted text) wrapped to the window, a
   capsule's questions asked in a box, redirects followed, plain texts
   shown, other files saved to /DOCUMENTS; Back, Forward (from a cache of
   pages in RAM banks), Reload, Home; bookmarks in GEMINI.MARKS in the
   system's data folder (/VERANDA/.SYSTEM). Through vrnet (sdk vrnet.h):
   the Wi-Fi modem of TexElec's network card, which makes the TLS
   connection (Zimodem's ATCS: it does not check certificates). Nothing
   waits: the main loop runs on while a page or a file comes, so menus,
   Stop and Alt+Tab work.

   This file, in main RAM: the start, the main loop's pass (tick), the
   helpers the overlays use, the card's side of a download, and the
   switcher's aside routine (Veranda Gopher's, V109).

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <vr.h>
#include <string.h>
#include <vrnet.h>
#include <vrser.h>
#include <theme.h>
#include <vrpath.h>
#include "gemini.h"
#include "png.h"

char line[200];
unsigned char bOv2, bOv3, bOv4, bOv5, bOv6, bOv7, net_on;
#ifdef GEMINI_TEST
static unsigned char bOvT, bOvT2;       /* (the test's overlays, 8 and 9) */
#endif
unsigned char marks_n, marks_i, marks_err;
const char appname[] = "Veranda Gemini";
unsigned char u_ret, u_err, u_moved;    /* (url.c's results, here in main RAM) */
unsigned char png_h;                    /* (png.c's: the picture's file; aside closes it; V125) */
unsigned int pic_kb;                    /* (web.c's setting: the largest picture shown without asking, KB; V124) */
char ghost[HOSTMAX];
unsigned int gport;

/*---------------------------------------------------------------
  the font: the X16's CP437 set from ROM bank 6, laid out for cs_draw
  (copy.s) in the history's bank at $B000: 10 tables of 256 bytes, one a
  glyph row, then a box character's top row and bottom row (0 for the
  others). Characters 0-31 keep their glyphs (rows hold no control
  characters: a list's bullet is CP437's 7). (V143, copy.s's cs_font)
  $A0-$FF are Veranda's set, ISO-8859-16, the ROM's own glyphs of it;
  $80-$9F private glyphs: CP437's pi, square, root, shades, blocks and
  box lines
 ---------------------------------------------------------------*/
static void load_font(void)
{
    cs_fbank = doc_bank + DOCBANKS + 1;
    cs_font(0);                        /* (copy.s, V143) */
}

void __fastcall__ cells(unsigned char x, unsigned int y, unsigned char n, unsigned char h, unsigned char fl)
{
    cs_x = x;
    cs_y = y;
    cs_n = n;
    cs_h = h;
    cs_fl = fl;
    cs_draw();
}

/* w cells at card x, pixel row y: s padded with spaces or cut */
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

static unsigned char gbuf[3 * 16];

/* glyph m (G_NONE: nothing) with its left at pixel x, rows 2-12 of h
   rows from y, 3 cards drawn (opaque); fl: GL_DIM dotted, GL_REV reversed.
   The glyphs (11 x 11, as the shell's minis; bit 15 the left pixel) are
   in the font's bank at $BE00 (web.c's w_load copies them there: V128) */
void __fastcall__ glyph(unsigned int x, unsigned int y, unsigned char m, unsigned char h, unsigned char fl)
{
    unsigned char r, s = x & 7, *d = gbuf, e = fl & GL_REV ? 0xFF : 0, kb = RAMBANK;
    unsigned int v;
    const unsigned int *g = (const unsigned int *)0xBE00 + m * 11 - 2;
    RAMBANK = cs_fbank;
    for (r = 0; r < h; ++r, d += 3) {
        v = m < G_N && r >= 2 && r < 13 ? g[r] : 0;
        if (fl & GL_DIM)
            v &= r & 1 ? 0xAAAA : 0x5555;
        d[0] = (v >> (8 + s)) ^ e;
        d[1] = (v >> s) ^ e;
        d[2] = (unsigned char)(v << (8 - s)) ^ e;
    }
    RAMBANK = kb;
    WBitmapUp(gbuf, x >> 3, 3, y, 0x8000 | h);
}

/* the window's chrome and the scroll bar (vrwin.h): the SDK's sources
   compiled into overlay 6 (V149; overlay 2 before) */
#include <vrwin.h>
static const struct vrwin win = { 0, 2, 80, 58, 2, 2, VW_CLOSE };
struct vrscroll sbar = { SBX, SBY, SBLEN, 1, 0, 0, 0 };
unsigned int sb_at, sb_n;

/* (these map the bank that was mapped again after: overlay 3 calls them too) */
static unsigned char keep;
#define OV6(x) keep = RAMBANK; RAMBANK = bOv6; x; RAMBANK = keep

void __fastcall__ win_all(const char *t)
{
    OV6(vr_win(&win, t));
}

void __fastcall__ win_title(const char *t)
{
    OV6(vr_win_title(&win, t));
}

void __fastcall__ win_status(const char *left, const char *right)
{
    OV6(vr_win_status(&win, left, right));
}

/* the scroll bar (sbar) drawn; where x, y is on it (VS_*), its thumb's
   place and length (sb_at, sb_n) */
void sb_draw(void)
{
    OV6(vr_scroll(&sbar));
}

unsigned char __fastcall__ sb_hit(unsigned int x, unsigned int y)
{
    unsigned char h;
    OV6(h = vr_scroll_hit(&sbar, x, y); sb_n = vr_scroll_len(&sbar, &sb_at));
    return h;
}

void __fastcall__ ov2(void (*f)(void))
{
    unsigned char keep = RAMBANK;
    RAMBANK = bOv2;
    f();
    RAMBANK = keep;
}

void __fastcall__ ov3(void (*f)(void))
{
    unsigned char keep = RAMBANK;
    RAMBANK = bOv3;
    f();
    RAMBANK = keep;
}

void __fastcall__ ov5(void (*f)(void))
{
    unsigned char keep = RAMBANK;
    RAMBANK = bOv5;
    f();
    RAMBANK = keep;
}

void __fastcall__ ov4(void (*f)(void))
{
    unsigned char keep = RAMBANK;
    RAMBANK = bOv4;
    f();
    RAMBANK = keep;
}

void __fastcall__ ov6(void (*f)(void))
{
    unsigned char keep = RAMBANK;
    RAMBANK = bOv6;
    f();
    RAMBANK = keep;
}

void __fastcall__ ov7(void (*f)(void))
{
    unsigned char keep = RAMBANK;
    RAMBANK = bOv7;
    f();
    RAMBANK = keep;
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
  the toolbar (tool.c, overlay 6 since V149: main RAM's room)
 ---------------------------------------------------------------*/
char abuf[URLMAX];
unsigned char alen;

void field(void)
{
    OV6(field6());
}

void toolbar(void)
{
    OV6(toolbar6());
}

/*---------------------------------------------------------------
  dialog boxes (their texts copied below $A000)
 ---------------------------------------------------------------*/
struct askdlg {
    unsigned char pos;
    unsigned char t0, x0, y0, reg0;     /* DBVARSTR: the prompt's first line (r7) */
    unsigned char t1, x1, y1, reg1;     /* DBVARSTR: its second (r6) */
    unsigned char t2, x2, y2, reg2, max;  /* DBGETSTRING (r5) */
    unsigned char ok, okx, oky;
    unsigned char cn, cnx, cny;
    unsigned char end;
};
static struct askdlg askbox = {
    DEF_DB_POS | 1,
    DBVARSTR, TXT_LN_X, TXT_LN_1_Y, 0x10,
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

#ifdef GEMINI_TEST
unsigned char t_box, t_aside, t_nbox, t_boxed, png_sums, t_pics_done, t_pics_prog;

/* (an overlay's text copied below $A000 first: into the row's cells, 79
   characters at most; V125: no buffer of its own, for main RAM's room) */
void __fastcall__ gt_log(const char *s)
{
    if ((unsigned int)s >= 0xA000) {
        strncpy(cs_txt, s, 79);
        cs_txt[79] = 0;
        s = cs_txt;
    }
    LogText((char *)s);
}

void __fastcall__ t_ovt(void (*f)(void))
{
    RAMBANK = bOvT;
    f();
    RAMBANK = appBank;
}

void __fastcall__ t_ui(void (*f)(void))
{
    RAMBANK = appBank;
    f();
    RAMBANK = bOvT;
}

void __fastcall__ t_ov7(void (*f)(void))
{
    RAMBANK = bOvT2;
    f();
    RAMBANK = bOvT;
}

static void box_log(void)
{
    t_box = 1;
    ++t_nbox;
    strcpy(line, "GE BOX ");            /* (line: its texts are in msga, msgb now) */
    strcat(line, msga);
    strcat(line, "|");
    strcat(line, msgb);
    LogText(line);
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

/* buf (below $A000, its text the default) edited under a prompt of up to
   two lines (cut at 51 characters, or at the last space before); 0:
   cancelled */
unsigned char __fastcall__ ask(const char *prompt, char *buf, unsigned char max)
{
    unsigned char r, n = strlen(prompt), c = n;
    askbox.max = max;
    if (n > 51) {
        for (c = 51; c > 30 && prompt[c] != ' '; --c)
            ;
        if (prompt[c] != ' ')
            c = 51;
    }
    texts(prompt, prompt + c + (prompt[c] == ' '));
    msga[c] = 0;
    r7 = (unsigned int)msga;
    r6 = (unsigned int)msgb;
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
char xf_name[56];
static unsigned long xf_fpos;
static unsigned char xf_slept;

static unsigned char __fastcall__ fopen_(const char *name, unsigned char mode)
{
    unsigned char h;
    ChDir((char *)curDirName);
    h = FOpen((char *)name, mode);
    return h < 2 || h > 4 ? 0 : h;
}

/* (V125) a picture's fetch (gdl 2) goes to GEMINI.TMP in the system's
   folder (pic.c shows it from there): its first 24 bytes kept (IHDR's
   size), the limit (pic_kb) a write that fails (pic_big) */
unsigned char viewing, retkey, pic_redo, pic_big, png_frames, pic_head[24];
static unsigned char pic_n;             /* (pic_head's bytes) */
unsigned int oy_done;
static const char pic_tmp[] = "GEMINI.TMP";

static unsigned char __fastcall__ xf_fopen(unsigned char mode)
{
    unsigned char h;
    if (gdl != 2)
        return fopen_(xf_name, mode);
    vr_cd(VR_DATA);
    h = FOpen((char *)pic_tmp, mode);
    ChDir((char *)curDirName);
    return h < 2 || h > 4 ? 0 : h;
}

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
    pic_n = 0;
    xf_slept = 0;
    xf_h = xf_fopen('w');
    return xf_h != 0;
}

void __fastcall__ xf_close(unsigned char ok)
{
    if (xf_h)
        FClose(xf_h);
    xf_h = 0;
    if (!ok && gdl != 2) {
        ChDir((char *)curDirName);
        FDelete(xf_name);
    }
    xf_slept = 0;
}

unsigned char __fastcall__ xf_write(const unsigned char *b, unsigned int n)
{
    unsigned int k;
    if (gdl == 2) {
        for (k = 0; pic_n < 24 && k < n; )
            pic_head[pic_n++] = b[k++];
        if (*(unsigned int *)((unsigned char *)&grx + 1) >= pic_kb << 2) {     /* (grx >> 8 against KB * 4) */
            pic_big = 1;
            return 0;
        }
    }
    if (!xf_h || FWrite(xf_h, (void *)b, n))
        return 0;
    xf_fpos += n;
    return 1;
}

void xf_wake(void)
{
    if (!xf_slept)
        return;
    xf_slept = 0;
    xf_h = xf_fopen('m');
    if (!xf_h)
        return;
    FSeek(xf_h, (unsigned int)xf_fpos, (unsigned int)(xf_fpos >> 16));
#ifdef GEMINI_TEST
    gt_log("GE FILE REOPENED");
#endif
}

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
    if (png_h) {                        /* (a picture being drawn: again when back) */
        FClose(png_h);
        png_h = 0;
    }
    pic_redo = 1;
#ifdef GEMINI_TEST
    t_aside = 1;
    gt_log("GE ASIDE");
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
  (V196) the way out of a picture (here for overlay 1's room)
 ---------------------------------------------------------------*/
unsigned char pic_pv;                   /* viewing as the last pass saw it */
void page(void);                        /* (ui.c's: overlay 1, mapped here) */

/* the page again after a picture: its rows, the scroll bar, the lines'
   count, the status bar's left cleared ("Esc: the page" no more) */
static void shown(void)
{
    page();
    ov2(u_lines);
    msg[0] = 0;
    win_status(msg, right);
}

/* every way out (a key, a click, the wheel, a menu's item, Quit; ui.c's):
   pic.c's i_off (tile mode off, the file closed and deleted, the menus
   on, the chrome), the page drawn again; nothing if no picture is shown */
void pic_leave(void)
{
    if (!viewing)
        return;
    ov4(i_off);
    pic_pv = 0;
    shown();
}

/* (ui.c's press and key while a picture is shown) pic.c's i_press or
   i_key says what it was (u_ret): 1 Save (done), 2 just the page (Esc,
   Backspace, Left; on the picture, the toolbar's Back), 0 anything else
   (then the page's: the toolbar, the close box, a key); the picture left
   unless 1; u_ret */
unsigned char __fastcall__ pic_in(void (*f)(void))
{
    ov4(f);
    if (u_ret != 1)
        pic_leave();
    return u_ret;
}

/* File > Quit, Ctrl+Q, the close box: a picture's view left first (tile
   mode off, GEMINI.TMP deleted), the connection ended, the desktop */
void g_quit(void)
{
    if (gbusy && !yesno("Something is still coming.", "Quit anyway?"))
        return;
    g_cancel();
    ov4(i_off);
    net_stop();
    EnterDeskTop();
}

/* (ui.c's menus) an item chosen: the menu closed, a picture left */
void pic_menu(void)
{
    GotoFirstMenu();
    pic_leave();
}

/*---------------------------------------------------------------
  the main loop's pass
 ---------------------------------------------------------------*/
static void tick(void)
{
    unsigned char e;
    xf_wake();
    e = g_poll();
    if (e == EV_END)
        ui_done();
    else if (e == EV_SAVE)
        ui_save();
    ui_tick();
    if (viewing || gdl == 2)
        ov4(i_tick);                    /* (pictures: V125) */
    if (pic_pv && !viewing)             /* (V196: gone by itself: a failed picture's box) */
        shown();
    pic_pv = viewing;
#ifdef GEMINI_TEST
    RAMBANK = bOvT;
    gt_tick();
    RAMBANK = appBank;
#endif
}

int main(void)
{
    u_err = r0L;                        /* (GetFile's options: ST_LD_DATA, a document; ui_start reads them, V128) */
    LoadOverlay(1, 0);                 /* (overlay 1: the interface, mapped for good, as appBank) */
    appBank = r1L;
    LoadOverlay(2, 0);
    bOv2 = r1L;
    LoadOverlay(3, 0);
    bOv3 = r1L;
    LoadOverlay(4, 0);
    bOv4 = r1L;
    LoadOverlay(5, 0);
    bOv5 = r1L;
    LoadOverlay(6, 0);                  /* (the window's chrome, the scroll bar: V149; the JPEG header, V192) */
    bOv6 = r1L;
    LoadOverlay(7, 0);                  /* (the JPEG decoder: V192) */
    bOv7 = r1L;
#ifdef GEMINI_TEST
    LoadOverlay(8, 0);
    bOvT = r1L;
    LoadOverlay(9, 0);                  /* (the test's pictures: tests/gemini_pics.c) */
    bOvT2 = r1L;
#endif
    /* the page cache: a bank of its own, and the two the loader gives
       banked overlays besides theirs and keeps nothing in after the start
       (record 0's padding before the first, the last one's after it:
       kernel/f/load.s, DECISIONS V37, V125) */
    cbank[1] = appBank - 1;
    cbank[2] = r1L + 1;
    RAMBANK = appBank;
    doc_bank = BankAlloc(BANKS);
    if (!doc_bank) {
        message("Veranda Gemini needs more memory", "(7 RAM banks).");
        EnterDeskTop();
    }
    cbank[0] = doc_bank + DOCBANKS + 2;
    load_font();
    ov3(u_load);
    net_restart();
    ui_start();
    appMain = VR_FN(tick);
    return 0;
}
