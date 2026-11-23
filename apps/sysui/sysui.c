/* sysui: the window, its toolbar, lines and buttons of the body, the
   boxes, numbers as text (sysui.h; DECISIONS V119). MIT licence (see
   LICENSE). */
#include <veranda.h>
#include <vr.h>
#include <vrwin.h>
#include <theme.h>
#include <string.h>
#include "sysui.h"

static const struct vrwin win = { 0, 2, 80, 58, 2, 2, 0 };

void __fastcall__ ui_window(const char *title)
{
    vr_win(&win, title);
}

/* (vrwin may be compiled into the program's overlay 1, its appBank:
   mapped here whatever is mapped now; SYSUI_VRWIN_BANK) */
void __fastcall__ ui_status(const char *left, const char *right)
{
    unsigned char k = RAMBANK;
    RAMBANK = appBank;
    vr_win_status(&win, left, right);
    RAMBANK = k;
}

/*---------------------------------------------------------------- text */
unsigned int __fastcall__ ui_width(const char *s, unsigned char bold)
{
    unsigned int w = 0;
    unsigned char c;
    UseFont(FONT_UI);
    while ((c = *s++) != 0)             /* (a menu's key after a tab, V146: 24 */
        w += c == 9 ? 24 : c == 0x1F ? 0 : GetCharWidth(c) + bold;  /* pixels; a separator: none) */
    return w;
}

static char tbuf[100];                  /* (the text below $A000 for the kernel) */

unsigned int __fastcall__ ui_text(unsigned int x, unsigned int y, const char *s, unsigned char bold)
{
    unsigned int w = ui_width(s, bold);
    strncpy(tbuf, s, sizeof tbuf - 1);
    currentMode = bold ? SET_BOLD : 0;
    WPutString(tbuf, x, y + 2 + baselineOffset);
    currentMode = 0;
    UseSystemFont();
    return w;
}

#define NHOT 24
static unsigned int hl[NHOT], ht[NHOT], hr[NHOT], hb[NHOT];
static unsigned char hid[NHOT], nhot;

void __fastcall__ ui_clear(unsigned int y0, unsigned int y1)
{
    SetPattern(0);
    WRectangle(0, y0, 639, y1);
    if (y0 <= BODY_TOP && y1 >= BODY_BOT)
        nhot = 0;
}

void __fastcall__ ui_pair(unsigned int y, const char *label, const char *value)
{
    SetPattern(0);
    WRectangle(0, y, 639, y + LINE_H - 1);
    ui_text(16, y, label, 0);
    ui_text(VAL_X, y, value, 0);
}

void __fastcall__ ui_hot_add(unsigned int l, unsigned int t, unsigned int r, unsigned int b, unsigned char id)
{
    if (nhot >= NHOT)
        return;
    hl[nhot] = l;
    ht[nhot] = t;
    hr[nhot] = r;
    hb[nhot] = b;
    hid[nhot++] = id;
}

unsigned char __fastcall__ ui_hot(unsigned int x, unsigned int y)
{
    unsigned char i;
    for (i = nhot; i--;)
        if (x >= hl[i] && x <= hr[i] && y >= ht[i] && y <= hb[i])
            return hid[i];
    return 0xFF;
}

/* a rounded frame (the shell's look, radius 3) */
void __fastcall__ ui_rframe(unsigned int l, unsigned int t, unsigned int r, unsigned int b)
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

unsigned int __fastcall__ ui_button(unsigned int x, unsigned int y, const char *t, unsigned char id)
{
    unsigned int w = ui_width(t, 1) + 20, r = x + w - 1;
    SetPattern(0);
    WRectangle(x, y, r, y + 14);
    ui_rframe(x, y, r, y + 14);
    ui_text(x + 10, y - 1, t, 1);
    ui_hot_add(x, y, r, y + 14, id);
    return r;
}

/*---------------------------------------------------------------- the toolbar */
void __fastcall__ ui_toolbar(const struct btn *b, unsigned char n, unsigned char sel)
{
    unsigned char i;
    unsigned int l, r, w;
    SetPattern(0);
    WRectangle(0, TOOL_TOP, 639, TOOL_TOP + 14);
    theme_rect(0, 80, TOOL_TOP >> 3, 2, CHROME);
    for (i = 0; i < n; ++i, ++b) {      /* (Sunroom: a paper button framed on */
        l = (unsigned int)b->x << 3;    /* the chrome, the chosen tab in the */
        r = l + ((unsigned int)b->w << 3) - 1;  /* highlight, its text plain) */
        theme_rect(b->x, b->w, TOOL_TOP >> 3, 2, i == sel ? (theme.hilite ? theme.hilite : SELECT) : PAPER);
        w = ui_width(b->t, i == sel);
        ui_text(l + ((r - l + 1 - w) >> 1), TOOL_TOP + 1, b->t, i == sel);
        ui_rframe(l, TOOL_TOP + 1, r, TOOL_TOP + 14);  /* (after the text, whose band reaches it; */
                                        /* its foot on the bar's line: a shade) */
    }
}

unsigned char __fastcall__ ui_tool_at(const struct btn *b, unsigned char n, unsigned int x)
{
    unsigned char i;
    x >>= 3;
    for (i = 0; i < n; ++i, ++b)
        if (x >= b->x && x < b->x + b->w)
            return i;
    return 0xFF;
}

/*---------------------------------------------------------------- the menus */
void __fastcall__ ui_menus(const char *const *names, unsigned char n, unsigned int **lefts,
                           unsigned int **rights, const char *const *longest, unsigned int *barright,
                           unsigned int *bx, unsigned int *bl)
{
    unsigned int b;
    unsigned char i;
    for (i = 0; i < n; ++i) {
        b = vr_bar_end(names, i);
        bx[i] = (b + vr_bar_end(names, i + 1)) >> 1;
        bl[i] = b;
        *lefts[i] = b;
        *rights[i] = b + ui_width(longest[i], 0) + 16;
    }
    *barright = vr_bar_end(names, n);
    UseSystemFont();
}

/*---------------------------------------------------------------- boxes */
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
static const struct msgdlg okbox = {
    DEF_DB_POS | 1,
    DBVARSTR, TXT_LN_X, TXT_LN_2_Y, 0x0C,
    DBVARSTR, TXT_LN_X, TXT_LN_3_Y, 0x0E,
    OK, DBI_X_0, DBI_Y_2,
    CANCEL, DBI_X_2, DBI_Y_2,
    0
};
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
    DBGETSTRING, TXT_LN_X, TXT_LN_3_Y, 0x0C, 16,
    OK, DBI_X_0, DBI_Y_2,
    CANCEL, DBI_X_2, DBI_Y_2,
    0
};

static char ma[56], mb[56];

/* (a box's font: characters 32-126) */
static void __fastcall__ cp(char *d, const char *s)
{
    unsigned char n = 0, c;
    while (n < 55 && (c = s[n]) != 0)
        d[n++] = c >= 32 && c < 127 ? c : '?';
    d[n] = 0;
}

#ifdef SYSUI_TEST
unsigned char ui_box_open;              /* the test's player waits for it */
unsigned char ui_boxes;
char ui_tl[140];                       /* (the test's log line; About's too) */
#define tl ui_tl
static void logbox(void)
{
    ui_box_open = 1;
    ++ui_boxes;
    strcpy(tl, "BOX ");
    strcat(tl, ma);
    strcat(tl, "|");
    strcat(tl, mb);
    LogText(tl);
}
#define LOGBOX() logbox()
#define BOXED() (ui_box_open = 0)
#else
#define LOGBOX()
#define BOXED()
#endif

static unsigned char __fastcall__ box(const void *t, const char *a, const char *b)
{
    unsigned char r;
    cp(ma, a);
    cp(mb, b);
    r5 = (unsigned int)ma;
    r6 = (unsigned int)mb;
    LOGBOX();
    r = DoDlgBox((void *)t);
    BOXED();
    return r;
}

void __fastcall__ ui_message(const char *a, const char *b)
{
    box(&msgbox, a, b);
}

unsigned char __fastcall__ ui_confirm(const char *a, const char *b)
{
    return box(&okbox, a, b) == OK;
}

unsigned char __fastcall__ ui_ask(const char *prompt, char *buf, unsigned char max)
{
    unsigned char r;
    askbox.max = max;
    cp(mb, prompt);
    ma[0] = 0;
    r6 = (unsigned int)mb;
    r5 = (unsigned int)buf;
    LOGBOX();
    r = DoDlgBox((void *)&askbox);
    BOXED();
    return r == OK || r == DBGETSTRING;
}

/*---------------------------------------------------------------- numbers */
char *__fastcall__ ui_num(char *p, unsigned long v)
{
    char t[11];
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

/* v / 2^sh with one decimal */
static char *__fastcall__ tenths(char *p, unsigned long v, unsigned char sh, const char *unit)
{
    unsigned long w = v >> sh;
    unsigned char d = (unsigned char)(((v - (w << sh)) >> (sh - 4)) * 10 / 16);
    p = ui_num(p, w);
    if (w < 100) {
        *p++ = '.';
        *p++ = '0' + d;
    }
    strcpy(p, unit);
    return p + strlen(p);
}

char *__fastcall__ ui_size(char *p, unsigned long v)
{
    if (v < 1024) {
        p = ui_num(p, v);
        strcpy(p, v == 1 ? " byte" : " bytes");
        return p + strlen(p);
    }
    if (v < 0x100000UL)
        return tenths(p, v, 10, " KB");
    if (v < 0x40000000UL)
        return tenths(p, v, 20, " MB");
    return tenths(p, v, 30, " GB");
}

char *__fastcall__ ui_dd(char *p, unsigned char v)
{
    *p++ = '0' + v / 10;
    *p++ = '0' + v % 10;
    *p = 0;
    return p;
}

char *__fastcall__ ui_hex(char *p, unsigned long v, unsigned char digits)
{
    static const char hx[] = "0123456789ABCDEF";
    unsigned char i;
    *p++ = '$';
    for (i = digits; i--;)
        *p++ = hx[(unsigned char)(v >> (i << 2)) & 15];
    *p = 0;
    return p;
}

void __fastcall__ ui_clock(char *p)
{
    unsigned int y = year;
    if (y < 70)
        y += 100;
    p = ui_num(p, 1900 + y);
    *p++ = '-';
    p = ui_dd(p, month);
    *p++ = '-';
    p = ui_dd(p, day);
    *p++ = ' ';
    p = ui_dd(p, hour);
    *p++ = ':';
    p = ui_dd(p, minutes);
    *p++ = ':';
    ui_dd(p, seconds);
}

unsigned int __fastcall__ le16(const unsigned char *p)
{
    return p[0] | (unsigned int)p[1] << 8;
}

unsigned long __fastcall__ le32(const unsigned char *p)
{
    return le16(p) | (unsigned long)le16(p + 2) << 16;
}
