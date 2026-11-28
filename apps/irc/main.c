/* Veranda Chat: an IRC client for Veranda (C, MIT; DECISIONS V111).

   One server at a time (chosen on the Servers page: CHAT.SERVERS in the
   system's data folder), its windows as tabs (the server's, channels,
   private conversations), each with its scrollback in a RAM bank; the
   nick list of a channel; an input line with a history and Tab's nick
   completion. Through vrnet (sdk vrnet.h): the Wi-Fi modem of TexElec's
   network card. Nothing waits: the main loop runs on while lines come
   and go, so menus, boxes and Alt+Tab work (put aside, the connection
   stays open in the modem, which holds what arrives).

   This file, in main RAM: the start, the main loop's pass (tick), the
   font, text in cells, the boxes, the window's chrome, the overlays'
   wrappers.

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <vr.h>
#include <string.h>
#include <vrnet.h>
#include <vrser.h>
#include <vrwin.h>
#include "chat.h"

unsigned char font[224 * 8];            /* (characters 32-255: PutCards from font - 256) */
char line[200];
unsigned char bOv2, bOv3, bOv4, bOv5;
#ifdef CHAT_TEST
static unsigned char bOv6;
#endif
struct vrscroll sbar;                   /* (V149) bar.c's scroll bar to draw, test (main RAM: vrscroll reads it) */
unsigned char sb_r;
struct srv S;
char tbuf[LNMAX], obuf[LNMAX];
char inbuf[INMAX + 1];
unsigned int in_cur, in_len;
unsigned char comp_on;
unsigned char nick_try, dirty, ding;
signed char cw_req = -1;
unsigned char sv_page, sv_go, sv_err, cbox, cbox_st;
unsigned int barx[3], barl[3];          /* (ui.c's menu bar: the test clicks them) */

/* w cells at card x, pixel row y: s padded with spaces or cut; control
   characters (and 127-159) as '?' */
static char cell[81];

void __fastcall__ put(unsigned char x, unsigned int y, const char *s, unsigned char w, unsigned char flags)
{
    unsigned char n = 0;
    unsigned char c;
    while (n < w && (c = s[n]) != 0)
        cell[n++] = c >= 32 && (c < 127 || c >= 160) ? c : '?';
    while (n < w)
        cell[n++] = ' ';
    if (w)
        PutCards(cell, font - 256, x, w, y, flags);
}

/* the window's chrome (vrwin.h): the SDK's source compiled into overlay 4 */
#include <vrwin.h>
#include <vrcs.h>
static const struct vrwin win = { 0, 2, 80, 58, 2, 2, 0 };

/* (their texts in main RAM: vrwin reads them with overlay 4 mapped) */
void __fastcall__ win_all(const char *t)
{
    unsigned char keep = RAMBANK;
    RAMBANK = bOv4;
    vr_win(&win, t);
    RAMBANK = keep;
}

void __fastcall__ win_title(const char *t)
{
    unsigned char keep = RAMBANK;
    RAMBANK = bOv4;
    vr_win_title(&win, t);
    RAMBANK = keep;
}

void __fastcall__ win_status(const char *left, const char *right)
{
    unsigned char keep = RAMBANK;
    RAMBANK = bOv4;
    vr_win_status(&win, left, right);
    RAMBANK = keep;
}

/* f in overlay 2, 3, 4 (from main RAM or another overlay: its bank mapped again after) */
static void __fastcall__ ovl(unsigned char b, void (*f)(void))
{
    unsigned char keep = RAMBANK;
    RAMBANK = b;
    f();
    RAMBANK = keep;
}

/* (V143) the SDK's vrcs is in overlay 4 (input.c's): proto.c's decoding
   (overlay 2) asks for a code point's byte in the set here */
unsigned char __fastcall__ l10_byte(unsigned int u)
{
    unsigned char keep = RAMBANK, c;
    RAMBANK = bOv4;
    c = cs_byte(u);
    RAMBANK = keep;
    return c;
}

void __fastcall__ ov2(void (*f)(void)) { ovl(bOv2, f); }
void __fastcall__ ov3(void (*f)(void)) { ovl(bOv3, f); }
void __fastcall__ ov4(void (*f)(void)) { ovl(bOv4, f); }
void __fastcall__ ov5(void (*f)(void)) { ovl(bOv5, f); }

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

unsigned char now_hh(void) { return hour; }
unsigned char now_mm(void) { return minutes; }

/*---------------------------------------------------------------
  dialog boxes (their texts copied below $A000)
 ---------------------------------------------------------------*/
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

#ifdef CHAT_TEST
unsigned char t_box, t_aside, t_nbox, t_boxed, t_ding, t_done;
char tlog[128];                         /* (tests/irc_play.c's line too: main RAM, V138's room) */

/* f in overlay 1 (from the test's overlay) */
void __fastcall__ gt_ov1(void (*f)(void))
{
    unsigned char keep = RAMBANK;
    RAMBANK = appBank;
    f();
    RAMBANK = keep;
}

/* every line a window gets, on the console: "IR LINE <window> <kind> <text>" */
void __fastcall__ gt_line(unsigned char w, unsigned char attr, const char *t)
{
    char *p;
    strcpy(tlog, "IR LINE ");
    strcat(tlog, w ? W[w].name : "*");
    p = tlog + strlen(tlog);
    *p++ = ' ';
    *p++ = '0' + attr;
    *p++ = ' ';
    *p = 0;
    strncat(tlog, t, sizeof tlog - 1 - strlen(tlog));
    LogText(tlog);
    if (strstr(t, "GATE done "))
        ++t_done;                       /* (V213: its <what> was kept, never read: 16 bytes and the copy, for vrnet's room) */
}

void __fastcall__ gt_log(const char *s)
{
    strncpy(tlog, s, sizeof tlog - 1);
    LogText(tlog);
}

static void box_log(void)
{
    t_box = 1;
    ++t_nbox;
    strcpy(tlog, "IR BOX ");
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

/*---------------------------------------------------------------
  the main loop's pass
 ---------------------------------------------------------------*/
static void tick(void)
{
    conn_poll();
    ui_tick();
#ifdef CHAT_TEST
    RAMBANK = bOv6;
    gt_tick();
    RAMBANK = appBank;
#endif
}

int main(void)
{
    LoadOverlay(1, 0);                  /* (overlay 1: the interface, mapped for good, as appBank) */
    appBank = r1L;
    LoadOverlay(2, 0);                  /* (overlay 2: IRC) */
    bOv2 = r1L;
    LoadOverlay(3, 0);                  /* (overlay 3: the servers, the chrome) */
    bOv3 = r1L;
    LoadOverlay(4, 0);                  /* (overlay 4: the input line's commands) */
    bOv4 = r1L;
    LoadOverlay(5, 0);                  /* (overlay 5: the scroll bars, the menus: V149) */
    bOv5 = r1L;
#ifdef CHAT_TEST
    LoadOverlay(6, 0);
    bOv6 = r1L;
#endif
    RAMBANK = appBank;
    ov4(load_font);                     /* (V178: input.c's, overlay 4) */
    if (!store_start()) {
        message("Veranda Chat needs more memory", "(7 RAM banks).");
        EnterDeskTop();
    }
    net_restart();
    ui_start();
    appMain = VR_FN(tick);
    return 0;
}
