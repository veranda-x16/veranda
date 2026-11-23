/* Paint's Sunroom column (overlay 2; DECISIONS V147): the tools, the
   patterns, the current pattern on the current colour, the colours and
   the status, at the screen's left (x 0-47, y 16-479).

   Paint runs in the kernel's tile mode (V101, the SDK's vrpic.h, V105):
   VERA's layer 0 shows 4 bpp tiles under the 1 bpp bitmap. The drawing
   area's cards are the solid tiles 0-15 of palette row 0, so a picture's
   colours (ColorRect, GetCardColor, the documents) are what they were;
   the column is tiles of its own (art.s, mkart.py) in palette rows 2-11,
   which Paint's pictures never use: the chrome has Sunroom's colours
   whatever the picture's palette and ink are. A chosen tool or pattern is
   its cards in palette row 3 (the sky plate) instead of row 2, a chosen
   colour its cards' tiles with the ring.

   The kernel prints and exports the classic colour map's colours only
   (in tile mode PrintRect prints the ink alone, ExportRect writes 8 bpp):
   chrome_classic(1) turns the drawing area's colours into the classic map
   for that time, chrome_classic(0) brings tile mode and the column back.

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <vr.h>
#include <vrpic.h>
#include "paint.h"
#include <string.h>
#include "art.h"

#define VERA_ADDR_L (*(volatile unsigned char *)0x9F20)
#define VERA_ADDR_M (*(volatile unsigned char *)0x9F21)
#define VERA_ADDR_H (*(volatile unsigned char *)0x9F22)
#define VERA_DATA0  (*(volatile unsigned char *)0x9F23)
#define VERA_CTRL   (*(volatile unsigned char *)0x9F25)

/* the drawing area's colours while the map is the classic one: two cards
   a byte (overlay 2's own memory) */
static unsigned char keep[MH * MW / 2];

/* port 0 at VRAM address $1hhll (bank 1), stepping 1 */
static void __fastcall__ at(unsigned int a)
{
    VERA_CTRL = 0;
    VERA_ADDR_L = a;
    VERA_ADDR_M = a >> 8;
    VERA_ADDR_H = 0x11;
}

/* map entries for w x h cards at card x, y (the column's) */
static void put(unsigned char x, unsigned char y, unsigned char w, unsigned char h, const unsigned char *e)
{
    unsigned char i, j;
    for (j = 0; j < h; ++j) {
        at(0xAC00 + (y + j) * 256 + x * 2);
        for (i = 0; i < 2 * w; ++i)
            VERA_DATA0 = *e++;
    }
}

static void tool_cards(unsigned char t, unsigned char on)
{
    put((t & 1) * 3, 2 + (t >> 1) * 3, 3, 3, art_tool[t][on]);
}

static void pat_cards(unsigned char p, unsigned char on)
{
    put((p % 3) * 2, PATY / 8 + (p / 3) * 2, 2, 2, art_pat[p][on]);
}

static void col_cards(unsigned char c, unsigned char on)
{
    put((c % 3) * 2, COLY / 8 + (c / 3) * 2, 2, 2, art_col[c][on]);
}

/* a pattern's sample, in the ink inside its swatch's frame */
static void pat_sample(unsigned char p)
{
    unsigned int x = (p % 3) * 16, y = PATY + (p / 3) * 16;
    SetPattern(p);
    WRectangle(x + 3, y + 3, x + 11, y + 11);
}

/* the current pattern on the current colour (the inside: 4 x 2 cards) */
static void current(void)
{
    ColorRect(1, 4, CURY / 8 + 1, 2, col);
    SetPattern(pat);
    WRectangle(8, CURY + 8, 39, CURY + 23);
}

void chrome_ink(void)
{
    /* palette row 4 (colours 0 and 1), entry 5: palette entry 1's */
    unsigned char g, r;
    VERA_CTRL = 0;
    VERA_ADDR_L = 2;
    VERA_ADDR_M = 0xFA;
    VERA_ADDR_H = 0x11;
    g = VERA_DATA0;
    r = VERA_DATA0;
    VERA_ADDR_L = (ART_ROWC * 16 + 5) * 2;
    VERA_DATA0 = g;
    VERA_DATA0 = r;
}

/* the art (tiles, rows, the column's map) and the chosen ones */
void chrome_again(void)
{
    vr_vram_load(ov3bank);
    tool_cards(tool, 1);
    pat_cards(pat, 1);
    col_cards(col, 1);
    ColorRect(1, 4, CURY / 8 + 1, 2, col);
    chrome_ink();
}

void chrome_init(void)
{
    unsigned char i;
    vr_pic_on();                        /* tile mode (vrpic.h): the back screen cleared */
    chrome_again();
    dispBufferOn = BOTH;
    SetPattern(0);
    WRectangle(0, 0, 639, 479);
    WHorizontalLine(0xFF, 0, 639, 15);
    for (i = 0; i < PATS; ++i)
        pat_sample(i);
    current();
}

void __fastcall__ chrome_tool(unsigned char old)
{
    tool_cards(old, 0);
    tool_cards(tool, 1);
}

void __fastcall__ chrome_pat(unsigned char old)
{
    pat_cards(old, 0);
    pat_cards(pat, 1);
    dispBufferOn = BOTH;
    current();
}

void __fastcall__ chrome_col(unsigned char old)
{
    col_cards(old, 0);
    col_cards(col, 1);
    dispBufferOn = BOTH;
    current();
}

/* a press in the column: 1 << 5 | the tool, 2 << 5 | the pattern, 3 << 5 |
   the colour pressed, 0 nothing */
unsigned char __fastcall__ chrome_hit(unsigned int x, unsigned int y)
{
    unsigned char c = x / 16, r;
    if (x > 46)
        return 0;
    if (y >= TOOLY && y < TOOLY + 6 * 24)
        return 1 << 5 | (y - TOOLY) / 24 * 2 + x / 24;
    if (y >= PATY && y < PATY + 8 * 16)
        return 2 << 5 | (y - PATY) / 16 * 3 + c;
    if (y >= COLY && y < COLY + 6 * 16) {
        r = (y - COLY) / 16 * 3 + c;
        if (r < COLS)
            return 3 << 5 | r;
    }
    return 0;
}

/*---------------------------------------------------------------
  the status: the pointer's place in the picture (its pixels from the
  drawing area's top left) and, while a shape or a selection is dragged
  out, its size. Drawn with digits of its own (7 rows, 4 pixels wide, in
  the manner of Gate Sans) straight into the rows (WriteRow): no font is
  touched, so it may run under a dialog box's text field.
 ---------------------------------------------------------------*/
static const unsigned char digits[13][7] = {
    { 0x6, 0x9, 0x9, 0x9, 0x9, 0x9, 0x6 },     /* 0 */
    { 0x4, 0xC, 0x4, 0x4, 0x4, 0x4, 0xE },     /* 1 */
    { 0x6, 0x9, 0x1, 0x2, 0x4, 0x8, 0xF },     /* 2 */
    { 0xE, 0x1, 0x1, 0x6, 0x1, 0x1, 0xE },     /* 3 */
    { 0x2, 0x6, 0xA, 0xA, 0xF, 0x2, 0x2 },     /* 4 */
    { 0xF, 0x8, 0xE, 0x1, 0x1, 0x9, 0x6 },     /* 5 */
    { 0x6, 0x8, 0x8, 0xE, 0x9, 0x9, 0x6 },     /* 6 */
    { 0xF, 0x1, 0x2, 0x2, 0x4, 0x4, 0x4 },     /* 7 */
    { 0x6, 0x9, 0x9, 0x6, 0x9, 0x9, 0x6 },     /* 8 */
    { 0x6, 0x9, 0x9, 0x7, 0x1, 0x1, 0x6 },     /* 9 */
    { 0x0, 0x0, 0x0, 0x0, 0x0, 0x4, 0x8 },     /* , (2 wide: its bits 3-2) */
    { 0x0, 0x0, 0x0, 0x9, 0x6, 0x6, 0x9 },     /* x */
    { 0, 0, 0, 0, 0, 0, 0 },                   /* space (2 wide) */
};
static const unsigned char dwidth[13] = { 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 3, 5, 3 };
static unsigned int shown_x = 0xFFFF, shown_y, shown_w = 0xFFFF, shown_h;

/* the text in stbuf (digits, ',', 'x', ' ') as 7 rows of the column's 6
   bytes at x 4, row y */
static void line(unsigned int y)
{
    unsigned char *rows = band;         /* (main RAM: WriteRow reads it) */
    unsigned char r, g, k, x = 4;
    const char *p;
    for (k = 0; k < 42; ++k)
        rows[k] = 0;
    for (p = stbuf; *p; ++p) {
        g = *p == ',' ? 10 : *p == 'x' ? 11 : *p == ' ' ? 12 : *p - '0';
        for (r = 0; r < 7; ++r) {
            unsigned int bits = (unsigned int)digits[g][r] << (12 - (x & 7));
            rows[r * 6 + (x >> 3)] |= bits >> 8;
            if ((x >> 3) < 5)
                rows[r * 6 + (x >> 3) + 1] |= bits;
        }
        x += dwidth[g];
    }
    for (r = 0; r < 7; ++r)
        WriteRow(rows + r * 6, 0, 6, y + r);
}

static char *num(char *p, unsigned int n)
{
    char d[5];
    unsigned char k = 0;
    do {
        d[k++] = '0' + n % 10;
        n /= 10;
    } while (n);
    while (k)
        *p++ = d[--k];
    return p;
}

void __fastcall__ chrome_status(unsigned int x, unsigned int y)
{
    unsigned int w = 0xFFFF, h = 0;
    char *p;
    unsigned char keep = dispBufferOn;
    if (dragging && tool != T_PENCIL && tool != T_BRUSH && tool != T_SPRAY && tool != T_ERASER) {
        if (tool == T_LINE) {
            w = lx > x0 ? lx - x0 : x0 - lx;
            h = ly > y0 ? ly - y0 : y0 - ly;
        } else {
            w = rr - rl;
            h = rb - rt;
        }
        ++w;
        ++h;
    }
    if (x < CX || y < CY)
        x = 0xFFFF;
    if (x == shown_x && y == shown_y && w == shown_w && h == shown_h)
        return;
    dispBufferOn = BOTH;
    if (x != shown_x || y != shown_y) {
        shown_x = x;
        shown_y = y;
        p = stbuf;
        if (x != 0xFFFF) {
            p = num(p, x - CX);
            *p++ = ',';
            *p++ = ' ';
            p = num(p, y - CY);
        }
        *p = 0;
        line(STATY + 7);
    }
    if (w != shown_w || h != shown_h) {
        shown_w = w;
        shown_h = h;
        p = stbuf;
        if (w != 0xFFFF) {
            p = num(p, w);
            *p++ = ' ';
            *p++ = 'x';
            *p++ = ' ';
            p = num(p, h);
        }
        *p = 0;
        line(STATY + 19);
    }
    dispBufferOn = keep;
}

/*---------------------------------------------------------------
  the documents' bands: PackBits (paint.c's save_doc and open_doc; here
  for main RAM's room)
 ---------------------------------------------------------------*/
/* PackBits: band -> packed; the length */
unsigned int pack(void)
{
    unsigned int i = 0, o = 0, j, n;
    unsigned char c;
    while (i < BANDSZ) {
        c = band[i];
        for (j = i + 1; j < BANDSZ && j - i < 128 && band[j] == c; ++j)
            ;
        n = j - i;
        if (n >= 3) {
            packed[o++] = 257 - n;
            packed[o++] = c;
            i = j;
            continue;
        }
        /* a literal run: up to the next run of three */
        for (j = i; j < BANDSZ && j - i < 128; ++j)
            if (j + 2 < BANDSZ && band[j] == band[j + 1] && band[j] == band[j + 2])
                break;
        n = j - i;
        packed[o++] = n - 1;
        memcpy(packed + o, band + i, n);
        o += n;
        i = j;
    }
    return o;
}

/* packed (n bytes) -> band; 0 if it does not fill the band exactly */
unsigned char __fastcall__ unpack(unsigned int n)
{
    unsigned int i = 0, o = 0, k;
    unsigned char c;
    while (i < n) {
        c = packed[i++];
        if (c < 128) {
            k = c + 1;
            if (o + k > BANDSZ || i + k > n)
                return 0;
            memcpy(band + o, packed + i, k);
            i += k;
        } else if (c > 128) {
            k = 257 - c;
            if (o + k > BANDSZ || i >= n)
                return 0;
            memset(band + o, packed[i++], k);
        } else
            continue;
        o += k;
    }
    return o == BANDSZ;
}

/*---------------------------------------------------------------
  the classic colour map for printing and exporting (the kernel's
  PrintRect and ExportRect read it), and tile mode back after it
 ---------------------------------------------------------------*/
static void runs(void)
{
    unsigned char x, y, n, c, k;
    unsigned char *q = keep;
    for (y = 0; y < MH; ++y, q += MW / 2) {
        for (x = 0; x < MW; ) {
            k = x & 1 ? q[x >> 1] & 15 : q[x >> 1] >> 4;
            for (n = 1; x + n < MW; ++n) {
                c = (x + n) & 1 ? q[(x + n) >> 1] & 15 : q[(x + n) >> 1] >> 4;
                if (c != k)
                    break;
            }
            if (k)
                ColorRect(MCARD + x, n, MROW + y, 1, k);
            x += n;
        }
    }
}

void __fastcall__ chrome_classic(unsigned char on)
{
    unsigned char x, y;
    unsigned char *q = keep;
    if (on) {
        for (y = 0; y < MH; ++y)
            for (x = 0; x < MW; x += 2)
                *q++ = GetCardColor(MCARD + x, MROW + y) << 4 | GetCardColor(MCARD + x + 1, MROW + y);
        ColorRect(0, 0, 0, 0, 0xFF);    /* tile mode off (rows 2-15 as Paint found them) */
        ColorRect(MCARD, MW, MROW, MH, 0);      /* the classic map, cleared */
        runs();
        return;
    }
    ColorRect(0, 0, 0, 0, COLOR_TILES); /* tile mode again (the map cleared) */
    chrome_again();
    runs();
}
