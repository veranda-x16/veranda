/* Veranda Claude: a chat with Claude for Veranda (C, MIT; DECISIONS V114).

   Claude through the Anthropic Messages API (POST /v1/messages,
   streamed as server-sent events), from the Commander X16 through the
   Wi-Fi modem of TexElec's network card (sdk vrnet.h). The X16 cannot do
   TLS: the modem does (Zimodem's ATCS"host:port", the ESP32's
   WiFiClientSecure, which does not check the server's certificate), and
   the X16 speaks plain HTTP/1.1 over that connection. The API keeps
   nothing between requests, so every turn sends the whole conversation
   (kept in RAM banks; the oldest turns dropped when it is full). The
   settings (the API key, the model) are in CLAUDE.CFG in the system's
   data folder. Nothing waits: the main loop runs on while a reply comes,
   so menus, Stop and Alt+Tab work.

   This file, in main RAM: the start, the main loop's pass (tick), the
   helpers every overlay uses (text in cells, the glyphs, frames,
   buttons, boxes, the window's chrome), the font laid out for copy.s,
   CP437's Unicode, the switcher's aside routine.

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <vr.h>
#include <string.h>
#include <vrnet.h>
#include <vrser.h>
#include <theme.h>
#include "claude.h"

char line[200];
unsigned char bOv2, bOv3, bOv4, bOv5;
unsigned int t_umsg, t_rmsg;
struct cfg C;
char inbuf[INMAX + 1];
unsigned int in_len, in_cur;
char sv_name[40];
unsigned char sv_err, cfg_err, pg_on, pg_saved;
unsigned int barx[4], barl[4];

#ifndef ASK
const char *const model_id[MODELS] = { "claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5" };
const char *const model_name[MODELS] = { "Claude Opus 5.5", "Claude Sonnet 5.5", "Claude Haiku 5.5" };
const char sys_default[] =
    "You are Claude, talking with someone on a Commander X16, an 8-bit computer, through "
    "Veranda Claude. Its screen shows 74 columns of plain text and cannot show Markdown, "
    "emoji or most Unicode. Write plain ASCII text only: no Markdown headings, no * or ** "
    "for emphasis, no tables, no emoji. Keep paragraphs short, with a blank line between "
    "them; use simple dashes for lists. Put code in a fenced block: a line ``` with the "
    "language (```basic, ```asm, ```c), the code, then a line ```; the user can copy it or "
    "save it. Number every line of the X16's BASIC. Be concise unless asked for detail.";
#endif

/* (CP437's Unicode, the table: code.c's cp_init puts it in the rows' bank,
   CP437U; cp_of and cp_u are store.c's, V123) */

/*---------------------------------------------------------------
  V123: a turn's plan (code.c lays it out, net.c sends it), the code
  blocks' clicks, the options, the usage
 ---------------------------------------------------------------*/
unsigned char bCode, bFiles, bConv, bHist, c_blk, c_prg;
unsigned int h_seq;
char h_title[41], h_created[17];
struct blk B[NB];
unsigned char nblk, af_prg, af_lang, af_kind;
char af_name[64];
char scrap_path[40];
unsigned int g_from;
char g_max[6];
unsigned char c_ui, g_model, t_cheap, t_comp, nsub, ph_i, c_col, att_on, c_go;
unsigned int sub_a[NSUB], sub_e[NSUB], c_row, u_turns;
char gph[64], att_lbl[48];
#ifdef ASK
char g_slug[40];
#endif
unsigned long u_in, u_cached, u_out, u_cost;
const char short_s[] = " Keep every answer short: a few sentences, or only the code asked for.";

void __fastcall__ ovc(void (*f)(void))
{
    unsigned char keep = RAMBANK;
    RAMBANK = bCode;
    f();
    RAMBANK = keep;
}

void __fastcall__ ovv(void (*f)(void))
{
    unsigned char keep = RAMBANK;
    RAMBANK = bConv;
    f();
    RAMBANK = keep;
}

void __fastcall__ ovh(void (*f)(void))
{
    unsigned char keep = RAMBANK;
    RAMBANK = bHist;
    f();
    RAMBANK = keep;
}

void __fastcall__ ovs(void (*f)(void))
{
    unsigned char keep = RAMBANK;
    RAMBANK = bFiles;
    f();
    RAMBANK = keep;
}

/*---------------------------------------------------------------
  the font: the X16's CP437 set from ROM bank 6 (as Veranda Gopher
  finds it), laid out for cs_draw (copy.s) in the rows' bank at $B000:
  10 tables of 256 bytes, one a glyph row, then a box character's top
  row and bottom row (the box lines and blocks; 0 for the others).
  Characters 0-31 keep their glyphs (the conversation has no control
  characters in its rows: a bullet is CP437's 7). (V143, copy.s's
  cs_font) $A0-$FF are Veranda's set, ISO-8859-16: the ROM's own glyphs
  of it; $80-$9F private glyphs, CP437's: pi, the square, the root, then
  the shades, blocks and box lines
 ---------------------------------------------------------------*/
static void load_font(void)
{
    cs_fbank = sbank + STBANKS;
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

/* w cells at card x, pixel row y (8 lines): s padded with spaces or cut
   (s may be in an overlay's bank: copied first) */
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

/* the badges' glyphs (11 x 11, as the shell's minis; bit 15 the left pixel) */
static const unsigned int glyphs[G_N][11] = {
    { 0x0E00, 0x1F00, 0x1F00, 0x1F00, 0x0E00, 0x0000, 0x3F80, 0x7FC0, 0x7FC0, 0x7FC0, 0x0000 },     /* you */
#ifdef ASK
    { 0x0000, 0x7FC0, 0x8020, 0x8020, 0xA4A0, 0x8020, 0x8020, 0x77C0, 0x1400, 0x1800, 0x1000 },     /* the reply (Ask: a speech bubble) */
#else
    { 0x0400, 0x4440, 0x2480, 0x1500, 0x0E00, 0xFFE0, 0x0E00, 0x1500, 0x2480, 0x4440, 0x0400 },     /* Claude */
#endif
    { 0x1F00, 0x2080, 0x4440, 0x8020, 0x8C20, 0x8420, 0x8420, 0x4E40, 0x2080, 0x1F00, 0x0000 },     /* a note */
    { 0x0400, 0x0A00, 0x0A00, 0x1100, 0x1500, 0x2480, 0x2480, 0x4040, 0x4440, 0x8020, 0xFFE0 },     /* a warning */
};

static unsigned char gbuf[3 * 16];

/* glyph m (G_NONE: nothing) with its left at pixel x, rows 2-12 of h
   rows from y, 3 cards drawn (opaque); fl: GL_DIM dotted, GL_REV reversed */
void __fastcall__ glyph(unsigned int x, unsigned int y, unsigned char m, unsigned char h, unsigned char fl)
{
    unsigned char r, s = x & 7, *d = gbuf, e = fl & GL_REV ? 0xFF : 0, o = (h - 11) >> 1;
    unsigned int v;
    for (r = 0; r < h; ++r, d += 3) {
        v = m < G_N && r >= o && r < o + 11 ? glyphs[m][r - o] : 0;
        if (fl & GL_DIM)
            v &= r & 1 ? 0xAAAA : 0x5555;
        d[0] = (v >> (8 + s)) ^ e;
        d[1] = (v >> s) ^ e;
        d[2] = (unsigned char)(v << (8 - s)) ^ e;
    }
    WBitmapUp(gbuf, x >> 3, 3, y, 0x8000 | h);
}

/* a rounded frame (the shell's look, radius 3) */
void __fastcall__ rframe(unsigned int l, unsigned int t, unsigned int r, unsigned int b)
{
    WHorizontalLine(0xFF, l + 2, r - 2, t);
    WHorizontalLine(0xFF, l + 2, r - 2, b);
    WVerticalLine(0xFF, l, t + 2, b - 2);
    WVerticalLine(0xFF, r, t + 2, b - 2);
    WHorizontalLine(0xFF, l + 1, l + 1, t + 1);
    WHorizontalLine(0xFF, r - 1, r - 1, t + 1);
    WHorizontalLine(0xFF, l + 1, l + 1, b - 1);
    WHorizontalLine(0xFF, r - 1, r - 1, b - 1);
}

/* a button: a rounded frame over cards x .. x + w - 1, pixel rows y ..
   y + 13, its label centred, bold, in the UI font, centred in the
   frame (V155) (dim: plain, a button that does nothing now); w 0: no button, a
   heading (V149, Sunroom: bold in the UI font at card x, the same row) */
void __fastcall__ button(unsigned char x, unsigned char w, unsigned int y, const char *label, unsigned char dim)
{
    unsigned int l = x * 8, r = (x + w) * 8 - 1, px;
    const char *t;
    SetPattern(0);
    if (w) {
        WRectangle(l, y, r, y + 13);
        rframe(l, y, r, y + 13);
    }
    UseFont(FONT_UI);
    currentMode = dim ? 0 : SET_BOLD;
    strcpy(line, label);
    for (px = 0, t = line; *t; ++t)
        px += GetCharWidth(*t) + 1;
    WPutString(line, w ? ((l + r) >> 1) - (px >> 1) : l, y + 2 + baselineOffset);
    currentMode = 0;
    UseSystemFont();
}

/* (V149, Sunroom) a page's heading: its title bold in the UI font (card 2,
   card row 6), what it shows at card 15 (the cells' font) */
void __fastcall__ heading(const char *t, const char *what)
{
    button(2, 0, 49, t, 0);
    put(15, 52, what, 63, 0);
}

/* the window's chrome (vrwin.h): the SDK's source compiled into overlay 2 */
#include <vrwin.h>
static const struct vrwin win = { 0, 2, 80, 58, 2, 2, 0 };
struct vrscroll sbar;                   /* (V149: sbar.c's, read with its bank mapped) */
unsigned char sb_r;

#ifdef ASK
#define bWin bOv3                       /* (Ask: vrwin in overlay 3, beside the parser) */
#else
#define bWin bOv2
#endif

void __fastcall__ win_all(const char *t)
{
    unsigned char keep = RAMBANK;
    RAMBANK = bWin;
    vr_win(&win, t);
    RAMBANK = keep;
}

void __fastcall__ win_title(const char *t)
{
    unsigned char keep = RAMBANK;
    RAMBANK = bWin;
    vr_win_title(&win, t);
    RAMBANK = keep;
}

void __fastcall__ win_status(const char *left, const char *right)
{
    unsigned char keep = RAMBANK;
    RAMBANK = bWin;
    vr_win_status(&win, left, right);
    RAMBANK = keep;
}

void __fastcall__ ovb(unsigned char b, void (*f)(void))
{
    unsigned char keep = RAMBANK;
    RAMBANK = b;
    f();
    RAMBANK = keep;
}

void __fastcall__ ov2(void (*f)(void)) { ovb(bOv2, f); }
void __fastcall__ ov3(void (*f)(void)) { ovb(bOv3, f); }
void __fastcall__ ov4(void (*f)(void)) { ovb(bOv4, f); }
#ifdef ASK
void __fastcall__ ov5(void (*f)(void)) { ovb(bOv5, f); }
unsigned char bLog, bRq;
void __fastcall__ ovl(void (*f)(void)) { ovb(bLog, f); }
void __fastcall__ ovq(void (*f)(void)) { ovb(bRq, f); }
#endif
#ifdef CLAUDE_TEST
static unsigned char bTest;     /* (the test's overlay: after code.c's and vrchoose's) */
#endif

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
  dialog boxes (their texts copied below $A000)
 ---------------------------------------------------------------*/
struct askdlg {
    unsigned char pos;
    unsigned char t1, x1, y1, reg1;
    unsigned char t2, x2, y2, reg2, max;
    unsigned char ok, okx, oky;
    unsigned char cn, cnx, cny;
    unsigned char end;
};
static struct askdlg askbox = {
    DEF_DB_POS | 1,
    DBVARSTR, TXT_LN_X, TXT_LN_2_Y, 0x0E,
    DBGETSTRING, TXT_LN_X, TXT_LN_3_Y, 0x0C, 38,
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

#ifdef ASK
char msga[52], msgb[52];                /* (Ask's test player logs them: tests/ask_play.c's gt_box) */
#else
static char msga[52], msgb[52];
#endif

/* (the boxes' font is the system's: characters 32-126 only) */
static void __fastcall__ copy7(char *d, const char *s)
{
    unsigned char n = 0, c;
    while (n < 51 && (c = s[n]) != 0)
        d[n++] = c >= 32 && c < 127 ? c : '?';
    d[n] = 0;
}

static void texts(const char *a, const char *b)
{
    copy7(msga, a);
    copy7(msgb, b);
    r5 = (unsigned int)msga;
    r6 = (unsigned int)msgb;
}

#ifdef CLAUDE_TEST
unsigned char t_box, t_aside, t_nbox, t_boxed, t_turns;
unsigned int t_pages, t_fp, t_fb, t_reads;
char tlog[120];                         /* (Ask's test player's buffer too: tests/ask_play.c) */

void __fastcall__ gt_log(const char *s)
{
    strncpy(tlog, s, sizeof tlog - 1);
    LogText(tlog);
}

void __fastcall__ t_ov5(void (*f)(void)) { ovb(bTest, f); }

/* f in overlay 1, from the test's overlay */
void __fastcall__ t_ui(void (*f)(void))
{
    RAMBANK = appBank;
    f();
    RAMBANK = bTest;
}

#ifdef ASK
void gt_box(void);                      /* (V199: in the test player's overlay, for main RAM's room) */
#define box_log() t_ov5(gt_box)
#else
static void box_log(void)
{
    t_box = 1;
    ++t_nbox;
    strcpy(tlog, "CL BOX ");
    strcat(tlog, msga);
    strcat(tlog, "|");
    strcat(tlog, msgb);
    LogText(tlog);
}
#endif
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
  the switcher: vrnet's aside routine (the packet arriving taken whole,
  the port quiet); the connection stays open in the modem, which holds
  what arrives meanwhile
 ---------------------------------------------------------------*/
static unsigned int net_aside;

static void aside(void)
{
    if (net_aside)
        ((void (*)(void))net_aside)();
#ifdef CLAUDE_TEST
    t_aside = 1;
    gt_log("CL ASIDE");
#endif
}

void net_restart(void)
{
    net_stop();
    net_on = net_start(0, 576) == NET_OK;
    net_aside = net_on ? asideVector : 0;
    asideVector = VR_FN(aside);
}

/*---------------------------------------------------------------
  the main loop's pass
 ---------------------------------------------------------------*/
static void tick(void)
{
    turn_poll();
    ui_tick();
#ifdef CLAUDE_TEST
    RAMBANK = bTest;
    gt_tick();
    RAMBANK = appBank;
#endif
}

int main(void)
{
    LoadOverlay(1, 0);                  /* (overlay 1: the interface, mapped for good, as appBank) */
    appBank = r1L;
    LoadOverlay(2, 0);                  /* (overlay 2: the settings, files, the menus, the chrome) */
    bOv2 = r1L;
    LoadOverlay(3, 0);                  /* (overlay 3: the reply's parser) */
    bOv3 = r1L;
    LoadOverlay(4, 0);                  /* (overlay 4: a turn's end) */
    bOv4 = r1L;
#ifdef ASK
    LoadOverlay(5, 0);                  /* (Ask: overlay 5, its settings and sign-in: apps/ask/auth.c) */
    bOv5 = r1L;
#define OVC 6
#else
#define OVC 5
#endif
    LoadOverlay(OVC, 0);                /* (V123: the code blocks, the options, a turn's plan: code.c) */
    bCode = r1L;
    LoadOverlay(OVC + 1, 0);            /* (V123: files saved, tokenized, attached: file.c) */
    bFiles = r1L;
    LoadOverlay(OVC + 2, 0);            /* (V123: a turn's plan, compaction, the usage: conv.c) */
    bConv = r1L;
    LoadOverlay(OVC + 3, 0);            /* (V123: the chats: hist.c) */
    bHist = r1L;
#ifdef ASK
    LoadOverlay(OVC + 4, 0);            /* (V129: ASK.LOG written, log.c; V149: the scroll bar, sbar.c) */
    bLog = r1L;
    LoadOverlay(OVC + 5, 0);            /* (V199: another program's request, rq.c) */
    bRq = r1L;
#ifdef CLAUDE_TEST
    LoadOverlay(OVC + 6, 0);            /* (V149: the test build's player, its own) */
    bTest = r1L;
#endif
#elif defined(CLAUDE_TEST)
    LoadOverlay(OVC + 4, 0);
    bTest = r1L;
#endif
    RAMBANK = appBank;
#ifdef ASK
    if (!store_start() || !tok_start()) {
        message("Veranda Ask needs more memory", "(6 RAM banks).");
        EnterDeskTop();
    }
#else
    if (!store_start()) {
        message("Veranda Claude needs more memory", "(5 RAM banks).");
        EnterDeskTop();
    }
#endif
    load_font();
    ov3(cp_init);
    ovv(c_newconv);                     /* (the overlays' BSS is not cleared: code.c's and conv.c's state) */
    net_restart();
    ui_start();
    appMain = VR_FN(tick);
    return 0;
}
