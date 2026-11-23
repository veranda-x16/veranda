/* Veranda FTP: an FTP client for Veranda (C, MIT; DECISIONS V100).

   Two panes: the card (from /DOCUMENTS, long names) and the server (its
   listing, Unix, DOS or MLSD), each with names, sizes and dates; the
   window's chrome (vrwin.h); a status bar with the transfer's progress
   and speed. Saved servers in FTP.SITES in the system's data folder
   (/VERANDA/.SYSTEM). Passive mode, binary; downloads go to the local
   pane's folder, uploads come from it. Through vrnet (sdk vrnet.h): the
   Wi-Fi modem of TexElec's network card. Nothing waits: the main loop
   runs on through every transfer, so menus and Alt+Tab work while a file
   comes.

   This file, in main RAM: the start, the main loop's pass (tick), the
   helpers both overlays use, the card's side of a transfer, and the
   switcher's aside routine (vrnet's, then the file closed: a program
   with a stream open is not put aside; it is opened again, at its
   position, when the program comes back).

   The FTP protocol and the listing parser come from Packet16, Marcin
   Spoczynski's FTP client for the X16, used under the MIT licence with
   his permission (proto.c, list.c, sites.c).

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <vr.h>
#include <string.h>
#include <vrnet.h>
#include <vrser.h>
#include "ftp.h"

unsigned char font[168 * 8];            /* (characters 32-127, then the set's $C0-$FF as
                                           $80-$BF and its Polish letters of $A0-$BF,
                                           font_pl, as $C0-$C7: PutCards from font - 256;
                                           V143, u8.c's u8_cells) */
const unsigned char font_pl[8] = { 0xA1, 0xA2, 0xA3, 0xAC, 0xAE, 0xAF, 0xB3, 0xBF };
char line[128];
unsigned char bOv2, bOv3, net_on;
unsigned char pa, pb;                   /* (ov3's arguments) */
#ifdef FTP_TEST
static unsigned char bOv4;              /* (the test's overlay) */
#endif
unsigned char sites_n, sites_go;        /* (sites.c's, in main RAM: ui.c reads them) */

/*---------------------------------------------------------------
  the font: the X16's CP437 set from ROM bank 6 (as Archive finds it),
  and glyphs of the ROM's ISO-8859-16 upper half for names in Veranda's
  set (V143: found by its A ogonek; font's comment)
 ---------------------------------------------------------------*/
static const unsigned char smiley[8] = { 0x7E, 0x81, 0xA5, 0x81, 0xBD, 0x99, 0x81, 0x7E };
static const unsigned char sigL10[8] = { 0x18, 0x3C, 0x24, 0x66, 0x7E, 0x66, 0x0C, 0x06 };

static void load_font(void)
{
    unsigned char keep, ok = 0;
    unsigned int a;
    asm("sei");
    keep = *(unsigned char *)1;
    *(unsigned char *)1 = 6;
    for (a = 0xC000; a; a += 0x800)
        if (!memcmp((void *)(a + 8), smiley, 8)) {
            memcpy(font, (void *)(a + 256), 96 * 8);
            ok = 1;
            break;
        }
    if (!ok)
        memcpy(font, (void *)0xC900, 96 * 8);
    for (a = 0xC008; a; a += 8)
        if (!memcmp((void *)a, sigL10, 8)) {
            memcpy(font + 96 * 8, (void *)(a + 0x1F * 8), 64 * 8);
            for (ok = 0; ok < 8; ++ok)
                memcpy(font + (160 + ok) * 8, (void *)(a - 8 + (font_pl[ok] - 0xA0) * 8), 8);
            break;
        }
    *(unsigned char *)1 = keep;
    asm("cli");
}

/* w cells at card x, pixel row y: s padded with spaces or cut (s may be
   in an overlay's bank: copied first). V143: names are shown as UTF-8
   (the servers' and the card's) decoded into Veranda's set: u8.c's
   u8_cells, overlay 1 (with the SDK's vrcs), mapped for it; the bytes are
   left as they are (the commands send them so) */
unsigned char cell[81];

void __fastcall__ put(unsigned char x, unsigned int y, const char *s, unsigned char w, unsigned char flags)
{
    unsigned char n = 0, k;
    while (n < 80 && (cell[n] = s[n]) != 0)
        ++n;
    cell[80] = 0;
    k = RAMBANK;
    RAMBANK = appBank;
    u8_cells(w);
    RAMBANK = k;
    if (w)
        PutCards(cell, font - 256, x, w, y, flags);
}

/* the window's chrome (vrwin.h): the SDK's source compiled into overlay 2
   (main RAM's room), called from here */
#include <vrwin.h>
static const struct vrwin win = { 0, 2, 80, 58, 2, 2, 0 };

void __fastcall__ win_all(const char *title)
{
    RAMBANK = bOv2;
    vr_win(&win, title);
    RAMBANK = appBank;
}

void __fastcall__ win_title(const char *title)
{
    RAMBANK = bOv2;
    vr_win_title(&win, title);
    RAMBANK = appBank;
}

void __fastcall__ win_status(const char *left, const char *right)
{
    RAMBANK = bOv2;
    vr_win_status(&win, left, right);
    RAMBANK = appBank;
}

void __fastcall__ ov2(void (*f)(void))
{
    RAMBANK = bOv2;
    f();
    RAMBANK = appBank;
}

void __fastcall__ ov3(void (*f)(void))
{
    RAMBANK = bOv3;
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

static void texts(const char *a, const char *b)
{
    strncpy(msga, a, sizeof msga - 1);
    strncpy(msgb, b, sizeof msgb - 1);
    r5 = (unsigned int)msga;
    r6 = (unsigned int)msgb;
}

#ifdef FTP_TEST
unsigned char t_box;                    /* a box is open (the test's player waits for it) */
unsigned char t_aside;                  /* the switcher put it aside */
unsigned char t_nbox;                   /* boxes opened */
unsigned char t_boxed;                  /* a box was open (the main loop's gap not counted) */
static char tlog[100];

void ftp_test_log(const char *s)
{
    strncpy(tlog, s, sizeof tlog - 1);
    LogText(tlog);
}

void ftp_test_list(unsigned char p);

void __fastcall__ tlist(unsigned char p)
{
    unsigned char b = RAMBANK;
    RAMBANK = bOv4;
    ftp_test_list(p);
    RAMBANK = b;
}
#endif

void __fastcall__ message(const char *a, const char *b)
{
    texts(a, b);
#ifdef FTP_TEST
    t_box = 1;
    ++t_nbox;
    ftp_test_log(msga);
    ftp_test_log(msgb);
#endif
    DoDlgBox((void *)&msgbox);
#ifdef FTP_TEST
    t_box = 0;
    t_boxed = 1;
#endif
}

unsigned char __fastcall__ yesno(const char *a, const char *b)
{
    unsigned char r;
    texts(a, b);
#ifdef FTP_TEST
    t_box = 2;
    ++t_nbox;
#endif
    r = DoDlgBox((void *)&yesnobox) == YES;
#ifdef FTP_TEST
    t_box = 0;
    t_boxed = 1;
#endif
    return r;
}

/* buf (below $A000, its text the default) edited; 0: cancelled */
unsigned char __fastcall__ ask(const char *prompt, char *buf, unsigned char max)
{
    unsigned char r;
    askbox.max = max;
    texts(prompt, "");
    r5 = (unsigned int)buf;
#ifdef FTP_TEST
    t_box = 3;
    ++t_nbox;
#endif
    r = DoDlgBox((void *)&askbox);
#ifdef FTP_TEST
    t_box = 0;
    t_boxed = 1;
#endif
    return r == OK || r == DBGETSTRING;
}

/*---------------------------------------------------------------
  a transfer's file on the card
 ---------------------------------------------------------------*/
unsigned char xf_h, xf_up;
unsigned long xf_pos, xf_size;
unsigned int xf_t0;
char xf_name[NAMEMAX];
static unsigned long xf_fpos;           /* the file's position */
static unsigned char xf_slept;          /* closed for the switcher */

unsigned char xf_open(unsigned char up)
{
    unsigned char h;
    xf_up = up;
    xf_pos = xf_fpos = 0;
    xf_slept = 0;
    ChDir((char *)curDirName);
    h = FOpen(xf_name, up ? 'r' : 'w');
    if (h < 2 || h > 4)
        return 0;
    xf_h = h;
    xf_t0 = ser_frames;
    if (up) {
        FSize(h);
        xf_size = r0 | (unsigned long)r1 << 16;
    }
    return 1;
}

void xf_close(unsigned char ok)
{
    if (xf_h)
        FClose(xf_h);
    xf_h = 0;
    xf_slept = 0;
    if (!ok && !xf_up) {
        ChDir((char *)curDirName);
        FDelete(xf_name);               /* (a download that failed: no part of it kept) */
    }
}

unsigned char __fastcall__ xf_write(const unsigned char *b, unsigned int n)
{
    if (!xf_h || FWrite(xf_h, (void *)b, n))
        return 0;
    xf_fpos += n;
    return 1;
}

unsigned int __fastcall__ xf_read(unsigned char *b, unsigned int n)
{
    if (!xf_h)
        return 0;
    n = FRead(xf_h, b, n);
    xf_fpos += n;
    return n;
}

/* back from the switcher: the file opened again where it was */
void xf_wake(void)
{
    unsigned char h;
    if (!xf_slept)
        return;
    xf_slept = 0;
    ChDir((char *)curDirName);
    h = FOpen(xf_name, xf_up ? 'r' : 'm');
    if (h < 2 || h > 4)
        return;                         /* (xf_h 0: the transfer fails) */
    xf_h = h;
    FSeek(h, (unsigned int)xf_fpos, (unsigned int)(xf_fpos >> 16));
#ifdef FTP_TEST
    ftp_test_log("FTP FILE REOPENED");
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
#ifdef FTP_TEST
    t_aside = 1;
    ftp_test_log("FTP ASIDE");
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
    unsigned char op;
    xf_wake();
    op = ftp_poll();
    if (op)
        ui_done(op);
    ui_tick();
#ifdef FTP_TEST
    RAMBANK = bOv4;
    ftp_test_tick();
    RAMBANK = appBank;
#endif
}

int main(void)
{
    unsigned char b;
    LoadOverlay(1, 0);                  /* (overlay 1: the interface, mapped for good, as appBank) */
    appBank = r1L;
    LoadOverlay(2, 0);                  /* (overlay 2: the Sites page) */
    bOv2 = r1L;
    LoadOverlay(3, 0);                  /* (overlay 3: the panes drawn, V149) */
    bOv3 = r1L;
#ifdef FTP_TEST
    LoadOverlay(4, 0);
    bOv4 = r1L;
#endif
    RAMBANK = appBank;
    load_font();
    b = BankAlloc(2 * PBANKS);
    if (!b) {
        message("Veranda FTP needs more memory", "(RAM banks).");
        EnterDeskTop();
    }
    panes[LOCAL].bank = b;
    panes[REMOTE].bank = b + PBANKS;
    net_restart();
    ui_start();
    appMain = VR_FN(tick);
    return 0;
}
