/* textkit (Veranda Edit, VeraBASIC): the window. Rows of 8 x 8 cells drawn with tk_putrow
   (putrow.s, DECISIONS V215: PutCards' cards, a style a card) from
   the lines buf.s renders (tabs, the selection's columns); the cursor a
   thin bar inverted over a cell's left edge; the title bar, the status
   line and the scroll bar in light grey paper (the colour map, a card at
   a time: the thumb is cards of a darker grey; the title bar takes the
   theme's accent, DECISIONS V65, when it has one). Everything is drawn on
   the foreground only, so menus and dialog boxes save what they cover.

   rs[r] is the start of row r's line (rs[0] = top); rs[r + 1] is known
   once row r is drawn. An edit marks rows dirty (ops.c) and shifts the
   starts after it; view_fix scrolls to the cursor and draws what is dirty.
   A scroll moves the rows that stay through VERA's ports (vmove.s, V215:
   only as far as each row's ink goes, tk_iw; the colour map's paper too
   when the program's TK_COLMOVE says so) and draws only the rows it
   uncovers.
   The status bar and the title are the program's (tk_status, tk_title);
   a program with TK_ROW_HOOK styles and colours a row as it is drawn. COLS and X0
   may be variables (a gutter of X0 card columns at the left: the
   program's to draw). (Veranda Edit: overlay 1.)

   MIT licence (see LICENSE). */
#include <string.h>
#include <theme.h>
#include <vrwin.h>
#include "tkapp.h"

unsigned long top, top_line;
unsigned int hs;
unsigned long rs[ROWS + 1];
unsigned char dirty[ROWS];
unsigned char bars_dirty;
unsigned char tk_hold;                 /* (V215) the status bar and the title wait (the program's) */
unsigned char cursor_on;
static unsigned char cur_row;
static unsigned int cur_x;
unsigned int tk_ccol;                   /* the cursor's column (view_col) */
char tk_line[81];                       /* (the bars' texts) */
#define line tk_line
static unsigned char thumb_a;
unsigned char thumb_n;                  /* the scroll bar as drawn (0: not yet) */

static void all_dirty(void)
{
    memset(dirty, 1, ROWS);
}

/* the window: the title band, the status bar (vrwin.h, V79), the scroll
   bar's cards */
const struct vrwin tk_win = { 0, 2, 80, 58, 0, 2, 0 };
#define win tk_win

void view_frame(void)
{
    dispBufferOn = ST_WR_FORE;
    theme_load();                       /* the title band: the theme's accent (V65) */
    if (!theme_none())
        theme_palette();                /* (Look 2's palette first: vrwin's colours need it) */
    vr_win(&win, "");
    ColorRect(SBX, 1, TROW, ROWS, C_BAR);
    memset(tk_iw, 80, ROWS);            /* (what is there: unknown) */
    thumb_n = 0;
    cursor_on = 0;
#ifdef TK_FRAME_HOOK
    TK_FRAME_HOOK();
#endif
}

void view_all(void)
{
    view_frame();
    all_dirty();
    bars_dirty = 7;
    view_paint();
}

/* the cursor bar: 2 pixels at the left of its cell */
void view_cursor(unsigned char on)
{
    unsigned int y;
    unsigned long r;
    if (on == cursor_on)
        return;
    if (on) {
        if (cur_line < top_line || cur_line >= top_line + ROWS || tk_ccol < hs || tk_ccol >= hs + COLS)
            return;
        r = cur_line - top_line;
        cur_row = (unsigned char)r;
        cur_x = (tk_ccol - hs + X0) << 3;
    }
    y = TY + (cur_row << 3);
    dispBufferOn = ST_WR_FORE;
    WInvertRectangle(cur_x, y, cur_x + 1, y + 7);
    cursor_on = on;
}

/* the cursor blinks on the clock, not on main loop passes (DECISIONS
   V160): tk_blink_due (buf.s) */
void view_blink(void)
{
    if (tk_blink_due())
        view_cursor(!cursor_on);
}

/* how many of the text's cards row r draws: as far as its ink went (was)
   or goes (tk_iw[r]); past both they are blank already (tk_pn) */
static void row_width(unsigned char r, unsigned char was)
{
    unsigned char n = tk_iw[r];
    if (was > n)
        n = was;
    n = n > X0 ? n - X0 : 0;
    tk_pn = n < COLS ? n : COLS;
}

/* the row drawn (tk_putrow: one call, each card its style), and how far
   its ink may go (tk_iw: vmove.s moves no further) */
static void row_draw(unsigned char r)
{
    unsigned long lo, hi, end;
    long a, b;
    unsigned int e;
    unsigned char was = tk_iw[r];
    if (cursor_on && cur_row == r)
        view_cursor(0);                 /* (its card may not be drawn) */
    tk_pc = gb_line;
    tk_pfont = TK_FONT;
    tk_px = X0;
    tk_pf = 0;
    tk_pa = tk_pb = 0;
    tk_iw[r] = X0;
    if (top_line + r >= nlines) {
        memset(gb_line, ' ', COLS);
        rs[r + 1] = gb_len;
        row_width(r, was);
#ifdef TK_ROW_HOOK
        gb_lcols = 0xFFFF;              /* (no line here) */
        TK_ROW_HOOK(r);
#endif
        tk_putrow(r);
        return;
    }
    lo = sel_lo();
    hi = sel_hi();
    gb_a = rs[r];
    gb_hs = hs;
    gb_mk[0] = lo;
    gb_mk[1] = hi;
    gb_mk[2] = NOWHERE;
    gb_render();
    rs[r + 1] = gb_a;
    a = b = 0;
    if (lo != hi) {
        end = gb_eof ? gb_a : gb_a - 1;     /* its LF, or the text's end */
        if (lo <= end && hi > rs[r]) {
            a = lo <= rs[r] ? 0 : (long)gb_mkc[0];
            b = hi > end ? (long)gb_lcols + 1 : (long)gb_mkc[1];
            a -= hs;
            b -= hs;
            if (a < 0)
                a = 0;
            if (b > COLS)
                b = COLS;
        }
    }
    e = gb_lcols > hs ? gb_lcols - hs : 0;
    if (e > COLS)
        e = COLS;
    if (b > a && b > (long)e)
        e = (unsigned int)b;
    tk_iw[r] = X0 + (unsigned char)e;
    if (b > a) {
        tk_pa = (unsigned char)a;       /* (the selection: reversed) */
        tk_pb = (unsigned char)b;
    }
    row_width(r, was);
#ifdef TK_ROW_HOOK
    TK_ROW_HOOK(r);
#endif
    tk_putrow(r);
}

#ifdef TK_PUT_SEG
#pragma code-name (push, TK_PUT_SEG)    /* (the program's choice: other parts call them) */
#endif
char *tk_put_ul(char *p, unsigned long v)
{
    char t[11];
    unsigned char n = 0;
    do {
        t[n++] = '0' + (unsigned char)(v % 10);
        v /= 10;
    } while (v);
    while (n)
        *p++ = t[--n];
    return p;
}

char *tk_put_s(char *p, const char *s)
{
    while (*s)
        *p++ = *s++;
    return p;
}
#ifdef TK_PUT_SEG
#pragma code-name (pop)
#endif

/* the thumb: the rows shown, among all the lines */
static void scrollbar(void)
{
    unsigned char a, n;
    if (nlines <= ROWS) {
        a = 0;
        n = ROWS;
    } else {
        n = (unsigned char)((unsigned long)ROWS * ROWS / nlines);
        if (n < 2)
            n = 2;
        a = (unsigned char)((top_line * (ROWS - n) + (nlines - ROWS) / 2) / (nlines - ROWS));
        if (a > ROWS - n)
            a = ROWS - n;
    }
    if (a == thumb_a && n == thumb_n)
        return;
    if (thumb_n)
        ColorRect(SBX, 1, TROW + thumb_a, thumb_n, C_BAR);
    ColorRect(SBX, 1, TROW + a, n, C_THUMB);
    thumb_a = a;
    thumb_n = n;
}

void view_paint(void)
{
    unsigned char r;
    dispBufferOn = ST_WR_FORE;
    for (r = 0; r < ROWS; ++r)
        if (dirty[r]) {
            dirty[r] = 0;
            row_draw(r);
        }
    if (bars_dirty & B_SCROLL)
        scrollbar();
    bars_dirty &= ~B_SCROLL;
    if (!tk_hold) {                     /* (V215: the text first) */
        if (bars_dirty & B_STATUS)
            tk_status();
        if (bars_dirty & B_TITLE)
            tk_title();
        bars_dirty = 0;
    }
    view_cursor(1);
}

static void scroll_rows(signed char d)
{
    /* the text area moved by d rows (d > 0: down): vmove.s, as far as
       each row's ink goes; the rows uncovered dirty */
    unsigned char r;
    view_cursor(0);
    dispBufferOn = ST_WR_FORE;
    tk_vlim = X0 + COLS;
#ifdef TK_COLMOVE
    tk_vcol = TK_COLMOVE;               /* (the program's: the colour map's paper too) */
#endif
    tk_vd = d;
    TK_VMOVE();
    if (d < 0) {
        memmove(rs, rs - d, (ROWS + 1 + d) * sizeof rs[0]);
        memmove(dirty, dirty - d, ROWS + d);
        for (r = ROWS + d; r < ROWS; ++r)
            dirty[r] = 1;
    } else {
        memmove(rs + d, rs, (ROWS + 1 - d) * sizeof rs[0]);
        memmove(dirty + d, dirty, ROWS - d);
        for (r = 0; r < d; ++r)
            dirty[r] = 1;
    }
    rs[0] = top;
#ifdef TK_SCROLL_HOOK
    TK_SCROLL_HOOK(d);                  /* (the program's: what else moved) */
#endif
}

/* top back n lines from where it is */
static void top_back(unsigned long n)
{
    while (n-- && top_line) {
        gb_a = top - 1;
        gb_line_start();
        top = gb_a;
        --top_line;
    }
}

void view_scroll(long n)
{
    unsigned long old = top_line;
    long d;
    if (n < 0) {
        top_back((unsigned long)-n);
    } else if (n > 0) {
        if (top_line + n > nlines - 1)
            n = nlines - 1 - top_line;
        gb_a = top;
        gb_n = n;
        top_line += gb_fwd_lines();
        top = gb_a;
    }
    d = (long)old - (long)top_line;
    if (!d)
        return;
    if (d > -ROWS / 2 && d < ROWS / 2)
        scroll_rows((signed char)d);
    else {
        rs[0] = top;
        all_dirty();
    }
    bars_dirty |= B_SCROLL;
    view_paint();
}

void view_fix(void)
{
    unsigned long d;
    unsigned int c;
    view_cursor(0);
    if (top == NOWHERE) {
        top = cur_ls;
        top_line = cur_line;
        top_back(ROWS / 3);
        rs[0] = top;
        all_dirty();
        bars_dirty |= B_SCROLL;
    }
    if (cur_line < top_line) {
        d = top_line - cur_line;
        if (d < ROWS / 2) {
            top_back(d);
            scroll_rows((signed char)d);
        } else {
            top = cur_ls;
            top_line = cur_line;
            top_back(ROWS / 3);
            rs[0] = top;
            all_dirty();
        }
        bars_dirty |= B_SCROLL;
    } else if (cur_line >= top_line + ROWS) {
        d = cur_line - (top_line + ROWS - 1);
        if (d < ROWS / 2) {
            gb_a = top;
            gb_n = d;
            gb_fwd_lines();
            top = gb_a;
            top_line += d;
            scroll_rows(-(signed char)d);
        } else {
            top = cur_ls;
            top_line = cur_line;
            top_back(ROWS * 2 / 3);
            rs[0] = top;
            all_dirty();
        }
        bars_dirty |= B_SCROLL;
    }
    gb_a = cur_ls;
    gb_b = cur;
    c = gb_col();
    if (c != tk_ccol)
        bars_dirty |= B_STATUS;
    tk_ccol = c;
    if (tk_ccol < hs) {
        hs = tk_ccol > 16 ? (tk_ccol - 16) & ~7 : 0;
        all_dirty();
    } else if (tk_ccol >= hs + COLS) {
        hs = (tk_ccol - COLS + 24) & ~7;
        all_dirty();
    }
    view_paint();
}

/* the text position under the pointer (x, y): 1 if in the text */
unsigned char view_hit(unsigned int x, unsigned int y, unsigned long *pos)
{
    unsigned char r;
    unsigned int c;
    if (y < TY || y >= TY + ROWS * 8 || x >= (X0 + COLS) * 8)
        return 0;
    r = (y - TY) >> 3;
#ifndef TK_GUTTER
    c = ((x + 3) >> 3) + hs;
#else
    x += 3;
    c = x < X0 * 8 ? hs : (x >> 3) - X0 + hs;
#endif
    if (top_line + r >= nlines) {
        if (nlines - 1 < top_line) {
            *pos = gb_len;
            return 1;
        }
        r = (unsigned char)(nlines - 1 - top_line);
    }
    gb_a = rs[r];
    gb_n = c;
    gb_at_col();
    *pos = gb_a;
    return 1;
}

unsigned int view_col(void)
{
    return tk_ccol;
}
