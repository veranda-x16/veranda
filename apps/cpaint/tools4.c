/* Colour Paint, stage 4 (overlay 4; DECISIONS V171): the brush, the
   spray, the text tool's stamp, the selection's clipboard (Colour Paint's
   own in RAM banks, and a black and white Photo Scrap for the other
   programs) and the palette editor. Called from cpaint.c through OV4()
   (this bank mapped); tests/check_cpaint.py has the brush's and the
   spray's algorithms too: change them together.

   brush  a disc of 5 pixels (rows 3, 5, 5, 5, 3 wide) stamped on every
          point of the Bresenham line from the last sample
   spray  8 dots a call within 8 pixels of the pointer, from a 16-bit
          LCG (s = s * 25173 + 13849): dx = (s >> 8) % 17 - 8, then dy
          from the next; a dot outside the circle (dx^2 + dy^2 > 64)
          drawn again from the next two

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <vr.h>
#include <string.h>
#include <scrap.h>
#include <vrcanvas.h>
#include "cpaint.h"
#pragma code-name ("OVERLAY4")
#pragma rodata-name ("OVL4RO")
#pragma data-name ("OVL4DATA")
#pragma bss-name ("OVL4BSS")

static void dot(int x, int y)
{
    if (x < 0 || y < 0 || x >= PW || y >= PH)
        return;
    pset(x, y);
}

static void hspan(int l, int r, int y)
{
    if (y < 0 || y >= PH)
        return;
    if (l < 0) l = 0;
    if (r > PW - 1) r = PW - 1;
    if (l > r)
        return;
    pa_y = y;
    pa_x = l;
    pa_n = r - l + 1;
    pic_span();
}

/*---------------------------------------------------------------
  the brush
 ---------------------------------------------------------------*/
static void stamp(int x, int y)
{
    hspan(x - 1, x + 1, y - 2);
    hspan(x - 2, x + 2, y - 1);
    hspan(x - 2, x + 2, y);
    hspan(x - 2, x + 2, y + 1);
    hspan(x - 1, x + 1, y + 2);
}

void __fastcall__ t4_brush(int x0, int y0, int x1, int y1)
{
    int dx, dy, sx, sy, err, e2;
    pa_c = cola;
    d_box((x0 < x1 ? x0 : x1) - 2, (y0 < y1 ? y0 : y1) - 2, (x0 < x1 ? x1 : x0) + 2, (y0 < y1 ? y1 : y0) + 2);
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
    for (;;) {
        pa_c = cola;
        stamp(x0, y0);
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

/*---------------------------------------------------------------
  the spray
 ---------------------------------------------------------------*/
static unsigned int seed = 1;

static signed char rnd17(void)
{
    seed = seed * 25173u + 13849u;
    return (signed char)((seed >> 8) % 17) - 8;
}

void __fastcall__ t4_spray(int x, int y)
{
    unsigned char k;
    signed char dx, dy;
    d_box(x - 8, y - 8, x + 8, y + 8);
    for (k = 0; k < 8; ++k) {
        do {
            dx = rnd17();
            dy = rnd17();
        } while (dx * dx + dy * dy > 64);
        pa_c = cola;
        dot(x + dx, y + dy);
    }
}

/*---------------------------------------------------------------
  the text: the kernel typed it into the 1 bpp screen (GetString);
  its ink, screen box l..r, t..b (inside the view), becomes the
  picture's in colour A, and the 1 bpp screen there paper again
 ---------------------------------------------------------------*/
#define trow (rowbuf + 280)              /* (ReadRow writes it: main RAM) */

void __fastcall__ t4_text(unsigned int l, unsigned char t, unsigned int r, unsigned char b)
{
    unsigned char y, cx0, cx1, k, m;
    unsigned int x;
    if (r > 319) r = 319;
    if (b > 239) b = 239;
    if (l < VX) l = VX;
    if (t < VY) t = VY;
    if (l > r || t > b)
        return;
    cx0 = l >> 3;
    cx1 = r >> 3;
#ifdef CP_TEST
    {
        extern void cp_test_textbox(unsigned int l, unsigned char t, unsigned int r, unsigned char b);
        cp_test_textbox(l, t, r, b);
    }
#endif
    keep_box(l - VX + scrx, t - VY + scry, r - VX + scrx, b - VY + scry);
    d_box(l - VX + scrx, t - VY + scry, r - VX + scrx, b - VY + scry);
    dispBufferOn = ST_WR_FORE;
    for (y = t; ; ++y) {
        ReadRow(trow, cx0, cx1 - cx0 + 1, y);
#ifdef CP_TEST
        {
            extern void cp_test_textrow(unsigned char y, unsigned char cx0, unsigned char n, const unsigned char *row);
            cp_test_textrow(y, cx0, cx1 - cx0 + 1, trow);
        }
#endif
        for (k = 0; k <= cx1 - cx0; ++k) {
            m = trow[k];
            if (!m)
                continue;
            for (x = (cx0 + k) * 8; m; m <<= 1, ++x)
                if (m & 0x80 && x >= l && x <= r) {
                    pa_c = cola;
                    pset(x - VX + scrx, y - VY + scry);
                }
        }
        if (y == b)
            break;
    }
    SetPattern(0);
    WRectangle(l, t, r, b);
}

/*---------------------------------------------------------------
  the clipboard: the selection's bytes, row after row, in clip banks
  from cbank (as many as it needs); a black and white Photo Scrap too
  (its stamp kept: a scrap written by another program since is pasted
  instead, its ink in entry 1)
 ---------------------------------------------------------------*/
static unsigned char cbank, cbanks;     /* the clip's banks */
static unsigned int cw, ch;             /* its size */
static unsigned char cstamp[8];
#define stmp (mbuf + 40)                /* (the scrap's stamp: main RAM) */
static int sx0, sy0;                    /* the selection's copy source (picture) */

/* rowbuf's n bytes to (to = 1) or from the clip at row y (draw.c's
   clip_move: this code cannot map another bank) */
static void cmove(unsigned int y, unsigned int n, unsigned char to)
{
    clip_move(cbank, (unsigned long)y * cw, n, to);
}

static unsigned char cfree(void)
{
    if (cbank)
        BankFree(cbank);
    cbank = 0;
    return 0;
}

static unsigned char calloc_(unsigned int w, unsigned int h)
{
    unsigned long n = (unsigned long)w * h;
    cfree();
    cbanks = (unsigned char)((n + 8191) >> 13);
    cbank = BankAlloc(cbanks);
    if (!cbank)
        return NO_BANKS;
    cw = w;
    ch = h;
    return 0;
}

/* the Photo Scrap's row y: the selection's pixels darker than half (the
   palette's R + G + B < 23) ink */
static unsigned char lum[32];           /* a bit an entry: dark */

static void scrap_row(unsigned int y, unsigned char *row)
{
    unsigned int x, w8 = (cw + 7) >> 3;
    unsigned char c;
    pa_y = sy0 + y;
    pa_x = sx0;
    pa_n = cw;
    row_get();
    memset(row, 0, w8);
    for (x = 0; x < cw; ++x) {
        c = rowbuf[x];
        if (lum[c >> 3] & (0x80 >> (c & 7)))
            row[x >> 3] |= 0x80 >> (x & 7);
    }
}

/* copy l..r, t..b (picture): 0, or an error */
unsigned char __fastcall__ t4_copy(int l, int t, int r, int b)
{
    unsigned int y, i, v;
    unsigned char e;
    if ((e = calloc_(r - l + 1, b - t + 1)) != 0)
        return e;
    pa_x = l;
    pa_n = cw;
    for (y = 0; y < ch; ++y) {
        pa_y = t + y;
        row_get();
        cmove(y, cw, 1);
    }
    sx0 = l;
    sy0 = t;
    memset(lum, 0, sizeof lum);
    for (i = 0; i < 256; ++i) {
        v = pal[i];
        if ((v >> 8 & 15) + (v >> 4 & 15) + (v & 15) < 23)
            lum[i >> 3] |= 0x80 >> (i & 7);
    }
    e = scrap_put_photo((cw + 7) >> 3, ch, scrap_row, 0);
    scrap_close();
    scrap_stamp(SCRAP_PHOTO, stmp);
    memcpy(cstamp, stmp, 8);
    return e;
}

/* the Photo Scrap of another program into the clip (ink entry 1) */
static unsigned int py;

static void put_row(unsigned int y, const unsigned char *row)
{
    unsigned int x;
    for (x = 0; x < cw; ++x)
        rowbuf[x] = row[x >> 3] & (0x80 >> (x & 7)) ? 1 : 0;
    cmove(y, cw, 1);
    (void)py;
}

/* the clip ready to paste: 0, or an error (no clip, no scrap) */
unsigned char t4_paste_ready(void)
{
    unsigned char w, e;
    unsigned int h;
#define st stmp
    scrap_stamp(SCRAP_PHOTO, st);
    if (cbank && !memcmp(st, cstamp, 8))
        return 0;
    if (scrap_photo_size(mbuf + 48, (unsigned int *)(mbuf + 50))) {
        scrap_close();
        return cbank ? 0 : FILE_NOT_FOUND;
    }
    scrap_close();
    w = mbuf[48];
    h = *(unsigned int *)(mbuf + 50);
    if ((unsigned int)w * 8 > PW)
        w = PW / 8;
    if (h > PH)
        h = PH;
    if ((e = calloc_(w * 8, h)) != 0)
        return e;
    e = scrap_get_photo(put_row, 0);
    scrap_close();
    memcpy(cstamp, st, 8);
    return e;
}

unsigned int t4_cw(void)
{
    return cw;
}

unsigned int t4_ch(void)
{
    return ch;
}

/* the clip's rows on the view with its top left at (x, y) (picture):
   to VRAM only (show = 1), or into the picture (show = 0) */
void __fastcall__ t4_put(int x, int y, unsigned char into)
{
    unsigned int r, n, sx;
    int py_, l;
    for (r = 0; r < ch; ++r) {
        py_ = y + r;
        if (py_ < 0 || py_ >= PH)
            continue;
        cmove(r, cw, 0);
        l = x;
        sx = 0;
        if (l < 0) {
            sx = -l;
            l = 0;
        }
        if (sx >= cw || l >= PW)
            continue;
        n = cw - sx;
        if (l + n > PW)
            n = PW - l;
        if (into) {
            memmove(rowbuf, rowbuf + sx, n);
            pa_y = py_;
            pa_x = l;
            pa_n = n;
            row_put();
        } else {                        /* the view's part of it */
            int vl = l - scrx, vt = py_ - scry, vr = vl + n - 1;
            unsigned int k = sx;
            if (vt < 0 || vt >= VH)
                continue;
            if (vl < 0) {
                k += -vl;
                vl = 0;
            }
            if (vr > VW - 1)
                vr = VW - 1;
            if (vl > vr)
                continue;
            pa_v = VADDR(VX + vl, VY + vt);
            pa_n = vr - vl + 1;
            vout(rowbuf + k);
        }
    }
}

/*---------------------------------------------------------------
  the palette editor: a panel over the view, the 16 x 16 entries, the
  chosen one's swatch, number and R, G, B as bars of 16 steps (a click
  on a step sets it); entries 0, 1 and 17-20 are fixed
 ---------------------------------------------------------------*/
#define PX0  56
#define PY0  40
#define PX1  303
#define PY1  187
#define GX   (PX0 + 6)
#define GY   (PY0 + 14)
#define BX   (PX0 + 150)
#define BY   (PY0 + 70)
static unsigned char pent;              /* the entry edited */
#define ptxt ((char *)mbuf)             /* (the kernel reads it: main RAM) */

static void say(const char *s, unsigned int x, unsigned char y)
{
    strcpy(ptxt, s);
    WPutString(ptxt, x, y);
}

static unsigned char fixed(unsigned char e)
{
    return e < 2 || (e >= 17 && e <= 20);
}

static void bar(unsigned char k)
{
    unsigned char v = pal[pent] >> (8 - 4 * k) & 15, i;
    unsigned int x;
    unsigned char y = BY + k * 18;
    SetPattern(0);
    WRectangle(BX, y, BX + 16 * 4 + 30, y + 11);
    for (i = 0; i < 16; ++i) {
        x = BX + 14 + i * 4;
        if (i <= v) {
            SetPattern(1);
            WRectangle(x, y + 1, x + 2, y + 10);
        } else
            WFrameRectangle(0xFF, x, y + 8, x + 2, y + 10);
    }
    ptxt[0] = "RGB"[k];
    ptxt[1] = 0;
    WPutString(ptxt, BX, y + 9);
    ptxt[0] = v >= 10 ? '1' : ' ';
    ptxt[1] = '0' + v % 10;
    ptxt[2] = 0;
    WPutString(ptxt, BX + 14 + 16 * 4 + 2, y + 9);
}

static void swatch(void)
{
    unsigned char y;
    for (y = 0; y < 24; ++y) {
        pa_v = VADDR(BX + 30, PY0 + 16 + y);
        pa_n = 50;
        pa_c = pent;
        vfill();
    }
    SetPattern(0);
    WRectangle(BX, PY0 + 44, PX1 - 4, PY0 + 56);
    strcpy(ptxt, "Entry 000");
    ptxt[6] = '0' + pent / 100;
    ptxt[7] = '0' + pent / 10 % 10;
    ptxt[8] = '0' + pent % 10;
    if (fixed(pent))
        strcat(ptxt, " fixed");
    WPutString(ptxt, BX, PY0 + 54);
    for (y = 0; y < 3; ++y)
        bar(y);
}

/* the 256 entries at (x, y), 16 x 16 of 8 x 8 pixels (the popup's and
   the palette editor's) */
void __fastcall__ t4_grid(unsigned int x, unsigned char y)
{
    unsigned char r, k;
    for (r = 0; r < 128; ++r) {
        pa_v = VADDR(x, y + r);
        pa_n = 8;
        for (k = 0; k < 16; ++k) {
            pa_c = (r >> 3) * 16 + k;
            vfill();
            pa_v += 8;
        }
    }
}

/* View > Whole picture: the 1 bpp screen paper, the picture all of it */
void t4_whole(void)
{
    unsigned char y;
    dispBufferOn = ST_WR_FORE;
    SetPattern(0);
    WRectangle(0, 0, 319, 239);
    pa_x = 0;
    pa_n = PW;
    for (y = 0; y < PH; ++y) {
        pa_y = y;
        pa_v = VADDR(0, y);
        pic_out();
    }
}

void __fastcall__ t4_pal_open(unsigned char e)
{
    unsigned char y;
    pent = e;
    dispBufferOn = ST_WR_FORE;
    SetPattern(0);
    WRectangle(PX0, PY0, PX1, PY1);
    WFrameRectangle(0xFF, PX0, PY0, PX1, PY1);
    for (y = PY0 + 1; y < PY1; ++y) {           /* the panel's paper */
        pa_v = VADDR(PX0 + 1, y);
        pa_n = PX1 - PX0 - 1;
        vzero();
    }
    say("Palette: an entry, then R, G, B", PX0 + 4, PY0 + 10);
    t4_grid(GX, GY);
    swatch();
    LogText("CPAINT PALETTE");
}

/* a click at (x, y): 0 when it was outside (the panel closes) */
unsigned char __fastcall__ t4_pal_click(unsigned int x, unsigned char y)
{
    unsigned char k, v;
    if (x < PX0 || x > PX1 || y < PY0 || y > PY1)
        return 0;
    if (x >= GX && x < GX + 128 && y >= GY && y < GY + 128) {
        pent = (y - GY) / 8 * 16 + (x - GX) / 8;
        swatch();
        return 1;
    }
    if (fixed(pent) || x < BX + 14 || x >= BX + 14 + 16 * 4 || y < BY)
        return 1;
    k = (y - BY) / 18;
    if (k > 2)
        return 1;
    v = (x - BX - 14) / 4;
    pal[pent] = (pal[pent] & ~(0x0F00 >> 4 * k)) | ((unsigned int)v << (8 - 4 * k));
    vr_canvas_palette(&pal[pent], pent, 1);
    dirty = 1;
    bar(k);
    return 1;
}

void t4_pal_close(void)
{
    SetPattern(0);
    WRectangle(PX0, PY0, PX1, PY1);
    screen_out(PX0, PY0, PX1, PY1);
    title();
    LogText("CPAINT PALETTE DONE");
}

/*---------------------------------------------------------------
  the status and the title (here: main RAM was full); their texts in
  main RAM (the kernel reads them)
 ---------------------------------------------------------------*/
static unsigned char status_x, status_y, status_c;
#define stl ((char *)mbuf)

static void num3(unsigned char at, unsigned int v)
{
    stl[at] = '0' + v / 100;
    stl[at + 1] = '0' + v / 10 % 10;
    stl[at + 2] = '0' + v % 10;
}

/* the pointer's place in the picture and its entry: x,y on one line,
   the entry under it; x < 0: none (-2: drawn again at the next) */
void __fastcall__ t4_status(int x, int y)
{
    unsigned char c;
    if (x == -2) {
        status_c = 0xFF;
        return;
    }
    if (x < 0 || y < 0) {
        if (status_c == 0xFE)
            return;
        status_c = 0xFE;
        dispBufferOn = ST_WR_FORE;
        SetPattern(0);
        WRectangle(0, STATY, VX - 2, 239);
        return;
    }
    c = pget(x, y);
    if (x == status_x && y == status_y && c == status_c)
        return;
    status_x = x;
    status_y = y;
    status_c = c;
    dispBufferOn = ST_WR_FORE;
    SetPattern(0);
    WRectangle(0, STATY, VX - 2, 239);
    strcpy(stl, "000,000");
    num3(0, x);
    num3(4, y);
    WPutString(stl, 1, STATY + 10);
    strcpy(stl, "c 000");
    num3(2, c);
    WPutString(stl, 1, STATY + 21);
}

/* the picture's name (a * when it changed since it was saved) centred
   in the band over the view, bold, in the UI font, in the 1 bpp screen */
void t4_title(void)
{
    unsigned int w = 0, c;
    unsigned char i;
    if (!docname[0])
        strcpy(ttl, "Untitled");
    else
        strcpy(ttl, docname);
    dispBufferOn = ST_WR_FORE;
    SetPattern(0);
    WRectangle(VX, 14, 319, VY - 2);
    UseFont(FONT_UI);
    for (i = 0; ttl[i] && i < 68; ++i) {
        c = GetCharWidth(ttl[i]) + 1;
        if (w + c > VW - 24)
            break;
        w += c;
    }
    if (dirty) {
        ttl[i++] = ' ';
        ttl[i++] = '*';
        w += GetCharWidth(' ') + GetCharWidth('*') + 2;
    }
    ttl[i] = 0;
    currentMode = SET_BOLD;
    WPutString(ttl, VX + (VW - w) / 2, 14 + 2 + baselineOffset);
    currentMode = 0;
    UseSystemFont();
}
