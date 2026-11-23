/* Veranda SDK: window chrome for native programs (vrwin.h; DECISIONS
   V79). The shell's title band, toolbar, status bar and shadow (V77,
   shell/chrome.c and bars.c) for a program's own window. MIT licence. */
#include <veranda.h>
#include "vrwin.h"
#include "theme.h"

static unsigned int l, r, t, b;
static unsigned char f, c;              /* c: colours (Look 2's palette) */                 /* 1: framed (the bands inside the frame) */
static char s[64];

static void box(const struct vrwin *w)
{
    c = theme_look2();
    f = (w->flags & VW_FRAME) != 0;
    l = (unsigned int)w->x << 3;
    r = l + ((unsigned int)w->w << 3) - 1;
    t = (unsigned int)w->y << 3;
    b = t + ((unsigned int)w->h << 3) - 1;
}

/* p into s, cut to n pixels in the font now; its width */
static unsigned int fit(const char *p, unsigned int n, unsigned char bold)
{
    unsigned char i = 0;
    unsigned int k = 0, c;
    while (p[i] && i < sizeof s - 1) {
        c = GetCharWidth(p[i]) + bold;
        if (k + c > n)
            break;
        k += c;
        s[i] = p[i];
        ++i;
    }
    s[i] = 0;
    return k;
}

/* s at x, in a 16-line band from y */
static void draw(unsigned int x, unsigned int y, unsigned char bold)
{
    currentMode = bold ? SET_BOLD : 0;
    WPutString(s, x, y + 2 + baselineOffset);
    currentMode = 0;
}

static void band(unsigned int y0, unsigned int y1)
{
    SetPattern(0);
    WRectangle(l + f, y0, r - f, y1);
}

void __fastcall__ vr_win_title(const struct vrwin *w, const char *title)
{
    unsigned char front = !(w->flags & VW_BACK);
    unsigned int n;
    box(w);
    band(t + f, t + 14);
    WHorizontalLine(0xFF, l, r, t + 15);
    if (c)
        theme_rect(w->x, w->w, w->y, 2, front ? (theme.accent ? theme.accent : TITLE) : CHROME);
    if (w->flags & VW_CLOSE) {          /* (V146, Sunroom) a square box, a cross in it
                                           (on the band, cleared above) */
        WFrameRectangle(0xFF, r - 17, t + 3, r - 7, t + 13);
        WDrawLine(DRAW_INK, r - 15, t + 5, r - 9, t + 11);
        WDrawLine(DRAW_INK, r - 9, t + 5, r - 15, t + 11);
    }
    UseFont(FONT_UI);
    n = fit(title, r - l - 48, front);
    draw((l + r - n) >> 1, t, front);
    UseSystemFont();
}

void __fastcall__ vr_win_status(const struct vrwin *w, const char *left, const char *right)
{
    unsigned int y, n = 0;
    box(w);
    y = b - ((unsigned int)w->status << 3) + 1;
    band(y + 1, b - f);
    UseFont(FONT_UI);
    if (right) {
        n = fit(right, r - l - 16, 0);
        draw(r - 8 - n, y, 0);
        n += 16;
    }
    if (left) {
        fit(left, r - l - 12 - n, 0);
        draw(l + 6, y, 0);
    }
    UseSystemFont();
}

void __fastcall__ vr_win(const struct vrwin *w, const char *title)
{
    unsigned int y;
    unsigned char st = w->status;
    theme_load();
    box(w);
    band(t, b);
    if (c)
        theme_rect(w->x, w->w, w->y, w->h, 0);
    if (w->tool) {
        y = t + ((unsigned int)(w->tool + 2) << 3) - 1;
        WHorizontalLine(0xFF, l, r, y);
        if (c)
            theme_rect(w->x, w->w, w->y + 2, w->tool, CHROME);
    }
    if (st) {
        WHorizontalLine(0xFF, l, r, b - ((unsigned int)st << 3) + 1);
        if (c)
            theme_rect(w->x, w->w, w->y + w->h - st, st, CHROME);
    }
    if (w->flags & VW_FRAME)
        WFrameRectangle(0xFF, l, t, r, b);
    if ((w->flags & VW_SHADOW) && !theme.dark) {   /* (V148: none in dark mode: the ink would glow) */
        SetPattern(2);                  /* (V146, Sunroom: 3 pixels) */
        WRectangle(r + 1, t + 3, r + 3, b + 3);
        WRectangle(l + 3, b + 1, r + 3, b + 3);
    }
    vr_win_title(w, title);
}

unsigned char __fastcall__ vr_win_hit(const struct vrwin *w, unsigned int x, unsigned int y)
{
    unsigned char cx, cy;
    box(w);
    if (x < l || x > r || y < t || y > b)
        return VW_OUT;
    cx = (x - l) >> 3;
    cy = (y - t) >> 3;
    if (cy < 2)
        return (w->flags & VW_CLOSE) && cx >= w->w - 3 ? VW_XCLOSE : VW_TITLE;
    if (cy < 2 + w->tool)
        return VW_TOOL;
    if (cy >= w->h - w->status)
        return VW_STATUS;
    return VW_BODY;
}

unsigned int __fastcall__ vr_win_top(const struct vrwin *w)
{
    return ((unsigned int)(w->y + 2 + w->tool) << 3);
}

unsigned int __fastcall__ vr_win_bottom(const struct vrwin *w)
{
    return ((unsigned int)(w->y + w->h - w->status) << 3) - 1;
}
