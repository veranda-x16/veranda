/* Paint's newer tools (overlay 4; DECISIONS V147): the brush, the spray,
   the oval and the filled oval, the fill.

   The brush paints the current pattern in a small round tip along the
   pointer's way; the spray scatters ink dots around it while the button
   is down; the ovals are the box dragged out (a rubber band on the
   foreground only, as the rectangles'); the fill paints the current
   pattern over the area of paper around the point pressed (its pixels
   not set, four neighbours; on the back screen first, then the area is
   the difference of the two screens). Each gives the cards it touches the
   current colour, as the other tools do.

   MIT licence (see LICENSE). */
#include <veranda.h>
#include "paint.h"

/* the kernel's patterns 0-23 (kernel/g/draw.s), for the fill */
static const unsigned char pats[PATS][8] = {
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 },
    { 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF },
    { 0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55 },
    { 0x88, 0x22, 0x88, 0x22, 0x88, 0x22, 0x88, 0x22 },
    { 0x77, 0xDD, 0x77, 0xDD, 0x77, 0xDD, 0x77, 0xDD },
    { 0x88, 0x00, 0x22, 0x00, 0x88, 0x00, 0x22, 0x00 },
    { 0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00 },
    { 0xAA, 0xAA, 0xAA, 0xAA, 0xAA, 0xAA, 0xAA, 0xAA },
    { 0xFF, 0x00, 0x00, 0x00, 0xFF, 0x00, 0x00, 0x00 },
    { 0x88, 0x88, 0x88, 0x88, 0x88, 0x88, 0x88, 0x88 },
    { 0xFF, 0x88, 0x88, 0x88, 0xFF, 0x88, 0x88, 0x88 },
    { 0xFF, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80 },
    { 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80 },
    { 0x80, 0x40, 0x20, 0x10, 0x08, 0x04, 0x02, 0x01 },
    { 0x11, 0x22, 0x44, 0x88, 0x11, 0x22, 0x44, 0x88 },
    { 0x88, 0x44, 0x22, 0x11, 0x88, 0x44, 0x22, 0x11 },
    { 0x81, 0x42, 0x24, 0x18, 0x18, 0x24, 0x42, 0x81 },
    { 0x18, 0x18, 0x18, 0xFF, 0xFF, 0x18, 0x18, 0x18 },
    { 0x00, 0x66, 0x66, 0x00, 0x00, 0x66, 0x66, 0x00 },
    { 0xCC, 0xCC, 0x33, 0x33, 0xCC, 0xCC, 0x33, 0x33 },
    { 0xF0, 0xF0, 0xF0, 0xF0, 0x0F, 0x0F, 0x0F, 0x0F },
    { 0xFF, 0xFF, 0x00, 0x00, 0xFF, 0xFF, 0x00, 0x00 },
    { 0xCC, 0xCC, 0xCC, 0xCC, 0xCC, 0xCC, 0xCC, 0xCC },
    { 0x80, 0x00, 0x08, 0x00, 0x80, 0x00, 0x08, 0x00 },
};

/* a rectangle in the current pattern, clipped to the drawing area */
static void __fastcall__ box(int l, int t, int r, int b)
{
    if (l < CX)
        l = CX;
    if (t < CY)
        t = CY;
    if (r > CR_)
        r = CR_;
    if (b > CB)
        b = CB;
    if (l <= r && t <= b)
        WRectangle(l, t, r, b);
}

/*---------------------------------------------------------------
  the brush: a round tip of 7 pixels, every 2 pixels along the way
 ---------------------------------------------------------------*/
static void __fastcall__ tip(int x, int y)
{
    box(x - 1, y - 3, x + 1, y + 3);
    box(x - 2, y - 2, x + 2, y + 2);
    box(x - 3, y - 1, x + 3, y + 1);
}

void __fastcall__ brush_to(unsigned int x, unsigned int y)
{
    int dx = (int)x - (int)lx, dy = (int)y - (int)ly;
    int n = (dx < 0 ? -dx : dx) > (dy < 0 ? -dy : dy) ? (dx < 0 ? -dx : dx) : (dy < 0 ? -dy : dy);
    int i, s = n / 2;
    SetPattern(pat);
    for (i = 1; i <= s; ++i)
        tip(lx + (long)dx * i / s, ly + (long)dy * i / s);
    tip(x, y);
    colour(lx < x ? lx - 3 : x - 3, ly < y ? ly - 3 : y - 3, lx < x ? x + 3 : lx + 3, ly < y ? y + 3 : ly + 3);
}

/*---------------------------------------------------------------
  the spray: 8 dots a frame in a circle of radius 9
 ---------------------------------------------------------------*/
static unsigned int seed = 0x6A3B;

static unsigned char rnd(void)
{
    seed ^= seed << 7;
    seed ^= seed >> 9;
    seed ^= seed << 8;
    return seed;
}

void __fastcall__ spray_at(unsigned int x, unsigned int y)
{
    unsigned char i;
    int u, v;
    seed ^= random;
    for (i = 0; i < 8; ) {
        u = (rnd() % 19) - 9;
        v = (rnd() % 19) - 9;
        if (u * u + v * v > 81)
            continue;
        ++i;
        u += x;
        v += y;
        if (u >= CX && u <= CR_ && v >= CY && v <= CB)
            WDrawPoint(DRAW_INK, u, v);
    }
    colour(x < CX + 9 ? CX : x - 9, y < CY + 9 ? CY : y - 9, x + 9, y + 9);
}

/*---------------------------------------------------------------
  the ovals: in the box rl, rt, rr, rb; hw[d] the half width d rows from
  the middle row (x^2 b^2 + y^2 a^2 <= a^2 b^2, in steps)
 ---------------------------------------------------------------*/
#define STK 600                         /* the fill's seeds (fill.s: 4 bytes each; the ovals share the room) */
unsigned int twork[2 * STK];
#define work twork

#define hw work
static unsigned int ocx, ocy, ob;

static void rows(void)
{
    unsigned int a = (rr - rl) >> 1, b = (rb - rt) >> 1, x, d;
    unsigned char half = 0;
    unsigned long A, B, X2B, TX, Y2A, TY, AB;
    ocx = rl + a;
    ocy = rt + b;
    ob = b;
    if (a > 255) {                      /* (a^2 b^2 in 32 bits) */
        a >>= 1;
        half = 1;
    }
    A = (unsigned long)a * a;
    B = (unsigned long)b * b;
    AB = A * B;
    x = a;
    X2B = A * B;                        /* x^2 b^2 */
    TX = (2UL * x - 1) * B;             /* what one less x takes off */
    Y2A = 0;
    TY = A;                             /* (2y + 1) a^2 */
    for (d = 0; d <= b; ++d) {
        while (x && X2B + Y2A > AB) {
            X2B -= TX;
            TX -= 2 * B;
            --x;
        }
        hw[d] = half ? x << 1 : x;
        Y2A += TY;
        TY += 2 * A;
    }
}

/* the outline's spans of each row (both halves, above and below), and
   their cards the colour */
static void spans(void)
{
    unsigned int d, in, out, y;
    unsigned char k;
    for (d = 0; d <= ob; ++d) {
        out = hw[d];
        in = d < ob ? hw[d + 1] + 1 : 0;
        if (in > out)
            in = out;
        for (k = 0; k < 2; ++k) {
            if (k && !d)
                break;
            y = k ? ocy + d : ocy - d;
            colour(ocx - out, y, ocx - in, y);
            colour(ocx + in, y, ocx + out, y);
            WHorizontalLine(0xFF, ocx - out, ocx - in, y);
            WHorizontalLine(0xFF, ocx + in, ocx + out, y);
        }
    }
}

/* the rubber band: a polygon of 32 sides through the oval (one call a
   side: drawn and taken away fast at any size; the oval itself is drawn
   exactly at the release) */
static const unsigned char cosq[9] = { 128, 126, 118, 106, 91, 71, 49, 25, 0 };   /* cos, 128ths, 11.25 degrees apart */
#define bx ((int *)work + 300)          /* (the band's corners: work's room too) */
#define by ((int *)work + 340)

/* a * cos(k * 11.25 degrees) */
static int __fastcall__ cosk(unsigned int a, unsigned char k)
{
    unsigned char q = k & 31, i;
    int v;
    i = q <= 8 ? q : q <= 16 ? 16 - q : q <= 24 ? q - 16 : 32 - q;
    v = (int)((a * cosq[i]) >> 7);
    return q > 8 && q < 24 ? -v : v;
}

void __fastcall__ oval_band(unsigned char show)
{
    unsigned char k;
    if (show) {
        unsigned int a = (rr - rl) >> 1, b = (rb - rt) >> 1;
        ocx = rl + a;
        ocy = rt + b;
        for (k = 0; k <= 32; ++k) {
            bx[k] = ocx + cosk(a, k);
            by[k] = ocy + cosk(b, k + 24);
        }
    }
    dispBufferOn = ST_WR_FORE;
    for (k = 0; k < 32; ++k)
        WDrawLine(show ? DRAW_INK : DRAW_RECOVER, bx[k], by[k], bx[k + 1], by[k + 1]);
    dispBufferOn = BOTH;
}

void oval_draw(void)
{
    unsigned int d, y, w;
    unsigned char k;
    dispBufferOn = BOTH;
    rows();
    if (tool == T_OVAL) {
        spans();
        return;
    }
    SetPattern(pat);
    for (d = 0; d <= ob; ++d) {
        w = hw[d];
        for (k = 0; k < 2; ++k) {
            if (k && !d)
                break;
            y = k ? ocy + d : ocy - d;
            WRectangle(ocx - w, y, ocx + w, y);
            if (((y - CY) & 7) == 0 || d == ob)
                colour(ocx - w, y, ocx + w, y);
        }
    }
    colour(ocx - hw[0], ocy, ocx + hw[0], ocy);
}

/*---------------------------------------------------------------
  the fill: a scanline flood fill on the back screen's bytes through
  VERA's data port (fill.s: the spans; a kernel row call for each of
  thousands of short spans, in a patterned area, took seconds): the
  foreground at $00000, the back screen at $09600, 80 bytes a row (640 x
  480); then the pattern where the back screen has more ink than the
  foreground, on both screens
 ---------------------------------------------------------------*/
#define VERA_ADDR_L (*(volatile unsigned char *)0x9F20)
#define VERA_ADDR_M (*(volatile unsigned char *)0x9F21)
#define VERA_ADDR_H (*(volatile unsigned char *)0x9F22)
#define VERA_DATA0  (*(volatile unsigned char *)0x9F23)
#define VERA_CTRL   (*(volatile unsigned char *)0x9F25)
#define AH      (CB - CY)               /* the area's last row: 463 */

/* fill.s's tables in main RAM's spare room (the documents' buffers, free
   meanwhile): each area row's back-screen address; each row's first and
   last byte set; a card row's cards the area touches */
#define rowl    (band + 256)
#define rowh    (band + 720)
#define lo      packed
#define hi      (packed + AH + 1)
#define cards   (band + 160)
extern unsigned char fx_k, fx_j;
extern unsigned int fy;
void fill_scan(void);

/* port 0 (stepping 1) at byte k of the area's row y; back: the back screen */
static void __fastcall__ at(unsigned char back, unsigned int y, unsigned char k)
{
    unsigned int b = rowl[y] | rowh[y] << 8, a = b + k;
    unsigned char h = 0;
    if (back)
        h = (y >= 324) + (a < b);       /* (rows 324 on start in VRAM bank 1; 323 crosses it) */
    else
        a += 0x6A00;                    /* (- 0x9600: the foreground is in bank 0) */
    VERA_CTRL = 0;
    VERA_ADDR_L = a;
    VERA_ADDR_M = a >> 8;
    VERA_ADDR_H = 0x10 | h;
}

void __fastcall__ fill_at(unsigned int x, unsigned int y)
{
    unsigned int i, a, py;
    unsigned char m, p, k, n, j, any;
    x -= CX;
    y -= CY;
    for (i = 0, a = 0x9600 + CY * 80 + CCARD; i <= AH; ++i, a += 80) {
        rowl[i] = a;
        rowh[i] = a >> 8;
        lo[i] = 255;
        hi[i] = 0;
    }
    at(1, y, x >> 3);
    if (VERA_DATA0 & (0x80 >> (x & 7)))
        return;                         /* (ink pressed: nothing to fill) */
    SetPointer(PTR_BUSY);
    fx_k = x >> 3;
    fx_j = x & 7;
    fy = y;
    fill_scan();
    for (i = 0; i <= AH; i += 8) {
        any = 0;
        for (k = 0; k < MW; ++k)
            cards[k] = 0;
        for (j = 0; j < 8; ++j) {
            py = i + j;
            if (lo[py] > hi[py])
                continue;
            n = hi[py] - lo[py] + 1;
            at(0, py, lo[py]);
            for (k = 0; k < n; ++k)
                band[k] = VERA_DATA0;
            at(1, py, lo[py]);
            for (k = 0; k < n; ++k)
                band[80 + k] = VERA_DATA0;
            p = pats[pat][(CY + py) & 7];
            for (k = 0; k < n; ++k) {
                m = band[k] ^ band[80 + k];
                if (m) {
                    band[k] |= m & p;
                    cards[lo[py] + k] = any = 1;
                }
            }
            at(0, py, lo[py]);
            for (k = 0; k < n; ++k)
                VERA_DATA0 = band[k];
            at(1, py, lo[py]);
            for (k = 0; k < n; ++k)
                VERA_DATA0 = band[k];
        }
        for (k = 0; any && k < MW; ) {
            if (!cards[k]) {
                ++k;
                continue;
            }
            for (n = 1; k + n < MW && cards[k + n]; ++n)
                ;
            ColorRect(MCARD + k, n, MROW + (i >> 3), 1, col);
            k += n;
        }
    }
    SetPointer(PTR_CROSS);
}
