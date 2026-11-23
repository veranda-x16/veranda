/* Veranda SDK: the menu bar as a title band (vrwin.h; DECISIONS V79),
   apart from vrwin.c so that a program that needs only these (Paint)
   links only these. MIT licence. */
#include <veranda.h>
#include "vrwin.h"

static char s[48];

unsigned int __fastcall__ vr_bar_end(const char *const *names, unsigned char n)
{
    unsigned char i;
    unsigned int e = 0;
    const char *p;
    UseFont(FONT_UI);
    for (i = 0; i < n; ++i) {
        p = names[i];
        e += i ? 6 + 6 : 24 + 6;        /* (the mark; 6 pixels each side) */
        while (*p)
            e += GetCharWidth(*p++) + !i;
        e = (e + 7) & ~7;
    }
    UseSystemFont();
    return e;
}

void __fastcall__ vr_bar_title(const char *p, unsigned int x0)
{
    unsigned int x1 = screenWidth - 144, n, c;
    unsigned char i, keep = dispBufferOn;
    dispBufferOn = ST_WR_FORE | ST_WR_BACK;
    SetPattern(0);
    WRectangle(x0, 1, x1, 14);
    UseFont(FONT_UI);
    for (n = 0, i = 0; p[i] && i < sizeof s - 1; ++i) {
        c = GetCharWidth(p[i]) + 1;
        if (n + c > x1 - x0 - 16)
            break;
        n += c;
        s[i] = p[i];
    }
    s[i] = 0;
    currentMode = SET_BOLD;
    /* (V164) the capitals in the middle of the bar's 15 rows, as the
       kernel's titles: 3 above, 3 below in the UI font */
    WPutString(s, (x0 + x1 - n) >> 1, 3 + baselineOffset);
    currentMode = 0;
    UseSystemFont();
    dispBufferOn = keep;
}

