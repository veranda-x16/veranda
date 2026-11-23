/* Calculator: a Veranda desk accessory in C.

   A window in the middle of the screen, over the application that opened
   it (GetFile on a DESK_ACC file: docs/APPFORMAT.md). A display and 16
   keys: digits, + - * /, = and C; the close box or Escape ends it with
   RstrAppl, which gives the application back exactly as it was. Keys work
   too: 0-9 + - * / = Return C, Escape.

   Veranda Look 3 "Sunroom" (DECISIONS V148): the SDK's window (vrwin.h:
   the title band, the square close box at the right, the 3-pixel shadow
   in light mode), Veranda's palette light or dark (theme.h), the display
   a white field with the number in bold, the keys card aligned (5 x 4
   cards) as the dialog boxes' buttons: the digits on the paper, the
   operators and C on the chrome, = on the selection colour with a double
   frame.

   Whole numbers (32 bits), as a pocket calculator: an operator applies
   the one before it.

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <vr.h>
#include <stdlib.h>
#include <string.h>
#include <theme.h>
#include <vrwin.h>

#define W       200             /* the window: 25 x 28 cards */
#define H       224
#define BW      40              /* a key: 5 x 4 cards */
#define BH      32
#define GAP     8
#define KX      8               /* the keys' left, top in the window */
#define KY      56
#define DY      24              /* the display: 3 card rows */

static unsigned int x0, y0;     /* the window's top left */
static long acc, cur;
static char op;                 /* the pending operator, 0 none */
static unsigned char fresh;     /* the next digit starts a new number */
static char buf[16];
static char line[24];
static struct vrwin win;

static const char keys[16] = {
    '7', '8', '9', '/',
    '4', '5', '6', '*',
    '1', '2', '3', '-',
    'C', '0', '=', '+' };

#ifdef CALC_TEST
void calc_test_start(void);
void calc_test_clock_reset(void);
void calc_test_clock_log(const char *what);
#endif

static unsigned int strw(const char *s)
{
    unsigned int w = 0;
    while (*s)
        w += GetCharWidth(*s++);
    return w;
}

static void show(void)
{
    unsigned int w;
    ltoa(cur, buf, 10);
    SetPattern(0);
    WRectangle(x0 + KX + 2, y0 + DY + 2, x0 + W - KX - 3, y0 + DY + 21);
    w = strw(buf) + strlen(buf);        /* (bold: a pixel more a character) */
    currentMode = SET_BOLD;
    WPutString(buf, x0 + W - KX - 8 - w, y0 + DY + 15);
    currentMode = 0;
}

/* a frame from x, y, w x h, i pixels in, its corners cut */
static void frame(unsigned int x, unsigned int y, unsigned char i)
{
    unsigned int r = x + BW - 1 - i, b = y + BH - 1 - i;
    x += i;
    y += i;
    WFrameRectangle(0xFF, x, y, r, b);
    WDrawPoint(DRAW_ERASE, x, y);
    WDrawPoint(DRAW_ERASE, r, y);
    WDrawPoint(DRAW_ERASE, x, b);
    WDrawPoint(DRAW_ERASE, r, b);
}

static void draw_key(unsigned char i)
{
    unsigned int x = x0 + KX + (i & 3) * (BW + GAP), y = y0 + KY + (i >> 2) * (BH + GAP);
    unsigned char c = keys[i], d = c >= '0' && c <= '9';
    char s[2];
    s[0] = c;
    s[1] = 0;
    SetPattern(0);
    WRectangle(x, y, x + BW - 1, y + BH - 1);
    theme_rect(x >> 3, BW >> 3, y >> 3, BH >> 3, d ? 0 : c == '=' ? (theme.hilite ? theme.hilite : SELECT) : CHROME);
    frame(x, y, 0);
    if (c == '=')
        frame(x, y, 1);
    WPutString(s, x + (BW - GetCharWidth(c)) / 2, y + BH / 2 + 4);
}

static void draw(void)
{
    unsigned char i;
    dispBufferOn = ST_WR_FORE;          /* the application's screen is put aside whole */
    theme_load();
    theme_palette();
    theme_menus();                      /* (the UI font) */
    win.x = x0 >> 3;
    win.y = y0 >> 3;
    win.w = W >> 3;
    win.h = H >> 3;
    win.flags = VW_CLOSE | VW_FRAME | (theme.dark ? 0 : VW_SHADOW);
    vr_win(&win, "Calculator");
    UseFont(FONT_UI);
    WFrameRectangle(0xFF, x0 + KX, y0 + DY, x0 + W - KX - 1, y0 + DY + 23);
    for (i = 0; i < 16; ++i)
        draw_key(i);
    show();
}

static void calc_close(void)
{
    LogText("CALC CLOSED");
#ifdef CALC_TEST
    calc_test_clock_reset();
#endif
    RstrAppl();
}

static long apply(long a, char o, long b)
{
    switch (o) {
    case '+': return a + b;
    case '-': return a - b;
    case '*': return a * b;
    case '/': return b ? a / b : 0;
    }
    return b;
}

static void key(char c)
{
    if (c >= '0' && c <= '9') {
        if (fresh) {
            cur = 0;
            fresh = 0;
        }
        if (cur < 100000000L && cur > -100000000L)
            cur = cur * 10 + (cur < 0 ? -(c - '0') : c - '0');
    } else if (c == 'C' || c == 'c') {
        acc = cur = 0;
        op = 0;
        fresh = 0;
    } else if (c == '+' || c == '-' || c == '*' || c == '/' || c == '=' || c == 13) {
        acc = op ? apply(acc, op, cur) : cur;
        cur = acc;
        op = (c == '=' || c == 13) ? 0 : c;
        fresh = 1;
        if (!op) {
            strcpy(line, "CALC = ");
            ltoa(cur, line + 7, 10);
            LogText(line);
        }
    } else if (c == 27 || c == 'q')
        calc_close();
    else
        return;
    show();
}

/* otherPressVec: a press on a key or the close box */
static void press(void)
{
    unsigned int x = mouseXPos, y = mouseYPosW, kx, ky;
    unsigned char col, row;
    if (mouseData & 0x80)
        return;
    if (vr_win_hit(&win, x, y) == VW_XCLOSE) {
        calc_close();
        return;
    }
    if (x < x0 + KX || y < y0 + KY)
        return;
    kx = x - x0 - KX;
    ky = y - y0 - KY;
    col = kx / (BW + GAP);
    row = ky / (BH + GAP);
    if (col > 3 || row > 3 || kx % (BW + GAP) >= BW || ky % (BH + GAP) >= BH)
        return;
    key(keys[row * 4 + col]);
}

static void typed(void)
{
    key(keyData);
}

/* appMain: the I-beam over the display (it takes typed digits), the
   arrow elsewhere (DECISIONS V51) */
static void track(void)
{
    unsigned int x, y;
    do {
        x = mouseXPos;
        y = mouseYPosW;
    } while (x != mouseXPos || y != mouseYPosW);
    SetPointer(x >= x0 + KX && x < x0 + W - KX && y >= y0 + DY && y < y0 + DY + 24 ? PTR_IBEAM : PTR_ARROW);
}

int main(void)
{
#ifdef CALC_TEST
    calc_test_clock_log("open");        /* since Paint's GetFile */
#endif
    x0 = ((screenWidth - W) / 2) & ~7;  /* (card aligned: the colours) */
    y0 = ((screenHeight - H) / 2) & ~7;
    draw();
    otherPressVec = VR_FN(press);
    keyVector = VR_FN(typed);
    appMain = VR_FN(track);
    LogText("CALC RUNNING");
#ifdef CALC_TEST
    calc_test_start();
#endif
    return 0;
}
