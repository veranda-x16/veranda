/* Veranda SDK: an alert in Veranda Look 3 "Sunroom" (vralert.h;
   DECISIONS V148). A DoDlgBox table made here: the position (38 cards
   wide, 13 card rows high, card aligned, centred), a DB_USR_ROUT that
   draws the icon and the texts and takes Return and Esc, the kernel's
   system icons for the buttons. MIT licence (see LICENSE). */
#include <veranda.h>
#include "vralert.h"
#include "vr.h"
#include "theme.h"

const unsigned char *vr_alert_icon;

#define BW      38              /* the box: cards */
#define BH      13              /* card rows */
#define TX      64              /* the texts' left with an icon */
#define TW      (BW * 8 - 16)   /* their right */

static const char *hd, *tx;
static unsigned char dflt, esc;
static unsigned int L, T;
static char ln[72];
static struct {
    unsigned char pos;
    unsigned int top, bot, left, right;
    unsigned char usr;
    void *rout;
    unsigned char b[3][3];      /* the buttons: icon, card, row (0 ends) */
    unsigned char end;
} tab;

/* the kinds' buttons, left to right: the last is the default */
static const unsigned char btn[4][3] = {
    { OK, 0, 0 }, { NO, YES, 0 }, { NO, CANCEL, YES }, { CANCEL, OK, 0 }
};

static void put(const char *s, unsigned char n, unsigned int x, unsigned int y)
{
    unsigned char i;
    for (i = 0; i < n && i < sizeof ln - 1; ++i)
        ln[i] = s[i];
    ln[i] = 0;
    WPutString(ln, x, y);
}

/* p's first n lines at x, baseline y, b: bold; wrapped at spaces to
   the box's right (the last line cut); the next line's baseline */
static unsigned int lines(const char *p, unsigned char n, unsigned int x, unsigned int y, unsigned char b)
{
    unsigned char i, sp;
    unsigned int w;
    currentMode = b ? SET_BOLD : 0;
    while (p && *p && n--) {
        i = sp = 0;
        w = 0;
        while (p[i] && (w += GetCharWidth(p[i]) + b) <= L + TW - x) {
            if (p[i] == ' ')
                sp = i;
            ++i;
        }
        if (p[i] && sp)
            i = sp;
        put(p, i, x, y);
        p += i;
        while (*p == ' ')
            ++p;
        y += 13;
    }
    currentMode = 0;
    return y;
}

static void draw(void)
{
    unsigned int x = L + 16;
    UseFont(FONT_UI);
    if (vr_alert_icon) {
        WBitmapUp((void *)vr_alert_icon, (L >> 3) + 2, 4, T + 14, 0x8000 | 32);
        x = L + TX;
    }
    /* the headline (two lines at most; alone: beside the icon's middle),
       then the explanation */
    lines(tx, 2, x, lines(hd, 2, x, T + (tx && *tx ? 25 : 33), 1) + 4, 0);
}

static void key(void)
{
    unsigned char r = 0;
    if (keyData == CR)
        r = dflt;
    else if (keyData == KEY_ESC)
        r = esc;
    if (r) {
        sysDBData = r;
        RstrFrmDialogue();
    }
}

static void rout(void)
{
    draw();
    keyVector = (unsigned int)vr_tramp(1, key);
}

unsigned char __fastcall__ vr_alert(unsigned char kind, const char *head, const char *text)
{
    const unsigned char *b = btn[kind & 3];
    unsigned char i, c = BW - 8, k = 0;
    hd = head;
    tx = text;
    L = ((screenWidth >> 3) - BW) >> 1 << 3;
    T = ((screenHeight >> 3) - BH) >> 1 << 3;
    tab.pos = SET_DB_POS | WIDE_DB | (theme.dark ? 0 : 1);  /* a solid shadow, as the system's boxes;
                                           none in dark mode (theme_load done: it would glow) */
    tab.top = T;
    tab.bot = T + BH * 8 - 1;
    tab.left = L;
    tab.right = L + BW * 8 - 1;
    tab.usr = DB_USR_ROUT;
    tab.rout = vr_tramp(0, rout);
    for (i = 3; i--;)                   /* right to left: the default first */
        if (b[i]) {
            tab.b[k][0] = b[i];
            tab.b[k][1] = b[i] == NO && kind == VA_YNC ? 2 : c;
            tab.b[k][2] = BH * 8 - 26;
            c -= 7;
            ++k;
        }
    if (k < 3)
        tab.b[k][0] = 0;
    dflt = b[kind == VA_YNC ? 2 : kind == VA_OK ? 0 : 1];
    esc = kind == VA_YNC || kind == VA_OKCANCEL ? CANCEL : kind == VA_YESNO ? NO : OK;
    return vr_dlgbox(&tab);
}
