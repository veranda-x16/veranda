/* Veranda SDK: a scroll bar in Veranda Look 3 "Sunroom" (vrwin.h;
   DECISIONS V146): arrow boxes at both ends, the track between them in
   the chrome's colour, a framed thumb with a grip, its size and place
   from the part shown. Its own object, so a program without scroll bars
   links none of it. MIT licence. */
#include <veranda.h>
#include "vrwin.h"
#include "theme.h"

static unsigned int sAlg, sAcr;             /* the bar's first pixel along and across */
static unsigned char vt;

/* a rectangle from along a..b, across c..d (the bar's own axes) */
static void rect(unsigned char frame, unsigned int a, unsigned int b, unsigned char c, unsigned char d)
{
    a += sAlg;
    b += sAlg;
    if (vt) {
        if (frame)
            WFrameRectangle(0xFF, sAcr + c, a, sAcr + d, b);
        else
            WRectangle(sAcr + c, a, sAcr + d, b);
    } else if (frame)
        WFrameRectangle(0xFF, a, sAcr + c, b, sAcr + d);
    else
        WRectangle(a, sAcr + c, b, sAcr + d);
}

/* a line across, from c to d, at along a */
static void across(unsigned int a, unsigned char c, unsigned char d)
{
    a += sAlg;
    if (vt)
        WHorizontalLine(0xFF, sAcr + c, sAcr + d, a);
    else
        WVerticalLine(0xFF, a, sAcr + c, sAcr + d);
}

/* an arrow box at along a (16 pixels): pointing to the start (dir 0) or the end */
static void arrow(unsigned int a, unsigned char dir)
{
    unsigned char i;
    rect(0, a, a + 15, 0, 15);
    rect(1, a, a + 15, 0, 15);
    for (i = 0; i < 4; ++i)
        across(a + (dir ? 9 - i : 6 + i), 7 - i, 8 + i);
}

unsigned int vr_scroll_len(const struct vrscroll *s, unsigned int *at)
{
    unsigned int l = ((unsigned int)s->len << 3) - 32, n, p = 0;
    unsigned long k;
    if (s->total <= s->shown || !s->total)
        n = l;
    else {
        k = (unsigned long)l * s->shown / s->total;
        n = k < 16 ? 16 : (unsigned int)k;
        k = (unsigned long)(l - n) * s->first / (s->total - s->shown);
        p = s->first >= s->total - s->shown ? l - n : (unsigned int)k;
    }
    *at = p + 16;
    return n;
}

void __fastcall__ vr_scroll(const struct vrscroll *s)
{
    unsigned int l = (unsigned int)s->len << 3, at, n;
    vt = s->vert;
    sAlg = vt ? (unsigned int)s->cy << 3 : (unsigned int)s->cx << 3;
    sAcr = vt ? (unsigned int)s->cx << 3 : (unsigned int)s->cy << 3;
    SetPattern(5);                      /* (V148) the track dotted, so the thumb stands out */
    rect(0, 16, l - 17, 0, 15);
    if (!theme_look2())                 /* (V148: a program in its pictures' palette: no colours) */
        ;
    else if (vt)
        theme_rect(s->cx, 2, s->cy + 2, s->len - 4, CHROME);
    else
        theme_rect(s->cx + 2, s->len - 4, s->cy, 2, CHROME);
    SetPattern(0);
    rect(1, 0, l - 1, 0, 15);
    arrow(0, 0);
    arrow(l - 16, 1);
    if (s->total > s->shown) {
        n = vr_scroll_len(s, &at);
        rect(0, at, at + n - 1, 1, 14);
        rect(1, at, at + n - 1, 0, 15);
        at += n >> 1;                   /* the grip: three lines across its middle */
        across(at - 2, 5, 10);
        across(at, 5, 10);
        across(at + 2, 5, 10);
    }
}

unsigned char __fastcall__ vr_scroll_hit(const struct vrscroll *s, unsigned int x, unsigned int y)
{
    unsigned int a, b, l = (unsigned int)s->len << 3, at, n;
    a = s->vert ? y - ((unsigned int)s->cy << 3) : x - ((unsigned int)s->cx << 3);
    b = s->vert ? x - ((unsigned int)s->cx << 3) : y - ((unsigned int)s->cy << 3);
    if (a >= l || b >= 16)
        return VS_OUT;
    if (a < 16)
        return VS_BACK;
    if (a >= l - 16)
        return VS_FWD;
    if (s->total <= s->shown)
        return VS_OUT;
    n = vr_scroll_len(s, &at);
    return a < at ? VS_PGBACK : a < at + n ? VS_THUMB : VS_PGFWD;
}
