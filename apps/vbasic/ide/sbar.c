/* VeraBASIC, the editor: B_FMT's scroll bar (Sunroom, V149) for the text
   and the help viewer, at card columns SB_X, SB_X + 1 beside the text's
   rows: drawn as the SDK's vr_scroll draws a vertical one (vrscroll.c:
   arrow boxes at both ends, the track in the chrome's colour, a framed
   thumb with a grip), only vertical and only here: vr_scroll with its
   hit test is 1,666 bytes, more than the banks that would call it have
   free. Its arguments in LOW (sb_first, sb_total: lines; ROWS of them
   shown); sb_draw leaves the thumb's place in sb_at, sb_len (pixels from
   the bar's top), sb_hit the part at sb_y (VS_*, vrwin.h) in sb_part.

   MIT licence (LICENSE). */
#include <theme.h>
#include <vrwin.h>
#include "ide.h"

#define XP  (SB_X * 8)
#define L   (ROWS * 8)

/* a line across the bar at y (from its top), from a to b */
static void across(unsigned int y, unsigned char a, unsigned char b)
{
    WHorizontalLine(0xFF, XP + a, XP + b, TY + y);
}

static void box(unsigned int y0, unsigned int y1)
{
    WRectangle(XP, TY + y0, XP + 15, TY + y1);
    WFrameRectangle(0xFF, XP, TY + y0, XP + 15, TY + y1);
}

static void arrow(unsigned int y, unsigned char down)
{
    unsigned char i;
    box(y, y + 15);
    for (i = 0; i < 4; ++i)
        across(y + (down ? 9 - i : 6 + i), 7 - i, 8 + i);
}

void sb_draw(void)
{
    unsigned int l = L - 32, n = l, p = 0;
    dispBufferOn = ST_WR_FORE;
    if (sb_total > ROWS) {
        n = (unsigned int)((unsigned long)l * ROWS / sb_total);
        if (n < 16)
            n = 16;
        p = sb_first >= sb_total - ROWS ? l - n
            : (unsigned int)((unsigned long)(l - n) * sb_first / (sb_total - ROWS));
    }
    sb_at = p + 16;
    sb_len = n;
    theme_rect(SB_X, 2, TROW, ROWS, CHROME);   /* (arrows too: textkit's column 79 is) */
    SetPattern(0);
    box(0, L - 1);
    arrow(0, 0);
    arrow(L - 16, 1);
    if (sb_total > ROWS) {
        box(sb_at, sb_at + n - 1);
        p = sb_at + (n >> 1);           /* the grip: three lines across its middle */
        across(p - 2, 5, 10);
        across(p, 5, 10);
        across(p + 2, 5, 10);
    }
}

void sb_hit(void)
{
    unsigned int y = sb_y - TY;
    sb_part = y < 16 ? VS_BACK : y >= L - 16 ? VS_FWD : sb_total <= ROWS ? VS_OUT
        : y < sb_at ? VS_PGBACK : y < sb_at + sb_len ? VS_THUMB : VS_PGFWD;
}
