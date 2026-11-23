/* Colour Paint: the tools on the picture in RAM (cpaint.h; DECISIONS
   V167). Each keeps the box it changed in dl, dt, dr, db (the caller
   shows it and keeps undo's copy). tests/check_cpaint.py has the same
   algorithms in Python: change them together.

   line   Bresenham (all integer: err = dx + dy, e2 = 2 err)
   rect   its four sides; filled: the inside in colour B
   oval   the ellipse in a box, integer midpoint steps (the box's width and
          height odd or even); filled: each row's span inside in colour B
   fill   the 4-connected area of the exact palette entry, in colour A:
          spans, a stack of seeds; when the stack is full, passes over the
          pixels it changed (undo keeps the whole picture before a fill)
          until nothing more changes
   eraser an 8 x 8 square of entry 0

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <string.h>
#include "cpaint.h"
#pragma code-name ("OVERLAY5")
#pragma rodata-name ("OVL5RO")
#pragma data-name ("OVL5DATA")
#pragma bss-name ("OVL5BSS")

static void plot(int x, int y)
{
    if (x < 0 || y < 0 || x >= PW || y >= PH)
        return;
    pset(x, y);
}

static void span(int l, int r, int y, unsigned char c)
{
    if (y < 0 || y >= PH)
        return;
    if (l < 0) l = 0;
    if (r >= PW) r = PW - 1;
    if (l > r)
        return;
    pa_y = y;
    pa_x = l;
    pa_n = r - l + 1;
    pa_c = c;
    pic_span();
}

void __fastcall__ d_line(int x0, int y0, int x1, int y1)
{
    int dx, dy, sx, sy, err, e2;
    dx = x1 - x0;
    sx = 1;
    if (dx < 0) {
        dx = -dx;
        sx = -1;
    }
    dy = y1 - y0;
    sy = 1;
    if (dy < 0) {
        dy = -dy;
        sy = -1;
    }
    dy = -dy;
    err = dx + dy;
    pa_c = cola;
    d_box(x0 < x1 ? x0 : x1, y0 < y1 ? y0 : y1, x0 < x1 ? x1 : x0, y0 < y1 ? y1 : y0);
    for (;;) {
        plot(x0, y0);
        if (x0 == x1 && y0 == y1)
            break;
        e2 = 2 * err;
        if (e2 >= dy) {
            err += dy;
            x0 += sx;
        }
        if (e2 <= dx) {
            err += dx;
            y0 += sy;
        }
    }
}

void __fastcall__ d_rect(int l, int t, int r, int b, unsigned char filled)
{
    int y;
    d_box(l, t, r, b);
    if (filled)
        for (y = t + 1; y < b; ++y)
            span(l + 1, r - 1, y, colb);
    span(l, r, t, cola);
    span(l, r, b, cola);
    for (y = t + 1; y < b; ++y) {
        span(l, l, y, cola);
        span(r, r, y, cola);
    }
}

/* the oval: each row's leftmost and rightmost outline pixel */
static int ominx[PH], omaxx[PH];

static void oplot(int x, int y)
{
    if (y < 0 || y >= PH)
        return;
    if (x < ominx[y]) ominx[y] = x;
    if (x > omaxx[y]) omaxx[y] = x;
    plot(x, y);
}

void __fastcall__ d_oval(int l, int t, int r, int b, unsigned char filled)
{
    long a, bb, b1, dx, dy, err, e2;
    int x0 = l, x1 = r, y0, y1, y;
    d_box(l, t, r, b);
    for (y = 0; y < PH; ++y) {
        ominx[y] = 32767;
        omaxx[y] = -32768;
    }
    a = r - l;
    bb = b - t;
    b1 = bb & 1;
    dx = 4 * (1 - a) * bb * bb;
    dy = 4 * (b1 + 1) * a * a;
    err = dx + dy + b1 * a * a;
    y0 = t + (int)((bb + 1) / 2);
    y1 = y0 - (int)b1;
    a = 8 * a * a;
    b1 = 8 * bb * bb;
    pa_c = cola;
    do {
        oplot(x1, y0);
        oplot(x0, y0);
        oplot(x0, y1);
        oplot(x1, y1);
        e2 = 2 * err;
        if (e2 <= dy) {
            ++y0;
            --y1;
            dy += a;
            err += dy;
        }
        if (e2 >= dx || 2 * err > dy) {
            ++x0;
            --x1;
            dx += b1;
            err += dx;
        }
    } while (x0 <= x1);
    while (y0 - y1 < bb) {              /* a flat oval's ends */
        oplot(x0 - 1, y0);
        oplot(x1 + 1, y0++);
        oplot(x0 - 1, y1);
        oplot(x1 + 1, y1--);
    }
    if (!filled)
        return;
    for (y = t + 1; y < b; ++y)         /* inside the outline, row by row */
        if (ominx[y] < omaxx[y] - 1)
            span(ominx[y] + 1, omaxx[y] - 1, y, colb);
}

void __fastcall__ d_erase(int x, int y)
{
    int k;
    d_box(x, y, x + 7, y + 7);
    for (k = 0; k < 8; ++k)
        span(x, x + 7, y + k, 0);
}

/* the fill: fill.s's f_spans with its seeds in RAM bank f_sbank; when
   they did not fit (f_over), passes over the box changed: each pixel the
   fill changed (now colour A, old in undo's whole copy) with an old one
   above or below gives a seed, until a pass finds none */
extern unsigned char f_old, f_sbank, f_over, f_py;
extern unsigned int f_max, f_ns, f_px;
void f_spans(void);
void f_push(void);
extern unsigned int fill_seeds;         /* (cpaint.c: main RAM) */

static unsigned char seed(unsigned int x, unsigned char y)
{
    if (pget(x, y) != f_old)
        return 0;
    f_px = x;
    f_py = y;
    f_push();
    if (f_over) {                       /* full: the seeds used, then on */
        f_over = 0;
        f_spans();
        f_push();
    }
    return 1;
}

unsigned char __fastcall__ d_fill(int x, int y)
{
    unsigned int px;
    unsigned char py, more, old;
    old = pget(x, y);
    if (old == cola)
        return 0;
    f_old = old;
    f_ns = 0;
    f_over = 0;
    f_max = fill_seeds;
    f_px = x;
    f_py = y;
    f_push();
    f_spans();
    more = f_over;                      /* (V170: passes until one finds no seed;
                                           seed() clears f_over as it goes) */
    while (more) {
        f_over = 0;
        more = 0;
        for (py = dt; py <= db; ++py)
            for (px = dl; px <= dr; ++px) {
                if (pget(px, py) != cola || uget(px, py) != old)
                    continue;
                if (py > 0)
                    more |= seed(px, py - 1);
                if (py < PH - 1)
                    more |= seed(px, py + 1);
            }
        f_spans();
    }
    return 1;
}

