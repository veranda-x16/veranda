/* Colour Paint, stage 5 (overlay 7; DECISIONS V172): the picture out of
   Colour Paint: a black and white picture for Paint (its format, "Paint
   Image V1.0", version 1), a BMP file (8 bits a pixel, the palette) and a
   print (the kernel's PDF writer). tests/check_cpaint.py has the dither:
   change them together.

   The dither: a pixel becomes 2 x 2 dots, as many of them ink as its
   colour is dark: L = ((45 - (R + G + B)) * 4 + 22) / 45 of 4, in the
   order top left, bottom right, top right, bottom left. For Paint the
   picture's 296 x 232 at the top left (592 x 464 dots, Paint's drawing
   area); for a print all of it (640 x 480 dots).

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <vr.h>
#include <string.h>
#include <vrcanvas.h>
#include "cpaint.h"
#pragma code-name ("OVERLAY7")
#pragma rodata-name ("OVL7RO")
#pragma data-name ("OVL7DATA")
#pragma bss-name ("OVL7BSS")

static unsigned char lvl[256];          /* each entry's ink dots of 4 */

static void levels(void)
{
    unsigned int i, v, s;
    for (i = 0; i < 256; ++i) {
        v = pal[i];
        s = (v >> 8 & 15) + (v >> 4 & 15) + (v & 15);
        lvl[i] = ((45 - s) * 4 + 22) / 45;
    }
}

/* picture row y's first n pixels as two rows of dots: mbuf (row A, the
   top) and mbuf + 80 (row B) */
static void dither(unsigned char y, unsigned int n)
{
    unsigned int x, d;
    unsigned char l, m, *a = mbuf, *b = mbuf + 80;
    pa_y = y;
    pa_x = 0;
    pa_n = n;
    row_get();
    memset(mbuf, 0, 160);
    for (x = 0; x < n; ++x) {
        l = lvl[rowbuf[x]];
        if (!l)
            continue;
        d = x >> 2;                     /* 2 dots a pixel: 4 pixels a byte */
        m = 0x80 >> ((x & 3) * 2);
        a[d] |= m;                      /* top left */
        if (l >= 2)
            b[d] |= m >> 1;             /* bottom right */
        if (l >= 3)
            a[d] |= m >> 1;             /* top right */
        if (l >= 4)
            b[d] |= m;                  /* bottom left */
    }
}

/* PackBits of n bytes at s into rowbuf: the length */
static unsigned int pack(const unsigned char *s, unsigned char n)
{
    unsigned char i = 0, j, k, *o = rowbuf;
    while (i < n) {
        for (j = i + 1; j < n && j - i < 128 && s[j] == s[i]; ++j)
            ;
        if (j - i >= 3) {
            *o++ = 257 - (j - i);
            *o++ = s[i];
            i = j;
            continue;
        }
        for (j = i; j < n && j - i < 128; ++j)
            if (j + 2 < n && s[j] == s[j + 1] && s[j] == s[j + 2])
                break;
        k = j - i;
        *o++ = k - 1;
        memcpy(o, s + i, k);
        o += k;
        i = j;
    }
    return o - rowbuf;
}

/* the black and white picture for Paint, named expname: 0, or an error */
unsigned char x7_paint(void)
{
    unsigned char e, r, b, k;
    unsigned int off, n;
    levels();
    make_hdr(1);
    if ((e = SaveFile(rowbuf, 0)) != 0)
        return e;
    if ((e = OpenRecordFile(expname)) != 0)
        return e;
    mbuf[0] = 'V', mbuf[1] = 'P', mbuf[2] = 'N', mbuf[3] = 'T';
    mbuf[4] = 1;                        /* version 1: no colours */
    mbuf[5] = 74, mbuf[6] = 16, mbuf[7] = 29;
    if ((e = AppendRecord()) || (e = WriteRecord(mbuf, 8)))
        goto out;
    for (b = 0; b < 29; ++b) {
        off = 0;
        for (r = 0; r < 8; ++r) {
            dither(b * 8 + r, 296);
            for (k = 0; k < 2; ++k) {
                n = pack(mbuf + k * 80, 74);
                clip_move(sbank, off, n, 1);
                off += n;
            }
        }
        if ((e = AppendRecord()) || (e = rec_write(off)))
            break;
    }
out:
    r = CloseRecordFile();
    return e ? e : r;
}

/* a BMP file named expname: 0, or an error */
unsigned char x7_bmp(void)
{
    unsigned char h, i, k;
    unsigned int v;
    static const unsigned char head[54] = {
        'B', 'M', 0x36, 0x30, 0x01, 0, 0, 0, 0, 0, 0x36, 4, 0, 0,     /* 77,878 bytes; the pixels at 1078 */
        40, 0, 0, 0, 0x40, 1, 0, 0, 240, 0, 0, 0, 1, 0, 8, 0,         /* 320 x 240, 8 bits */
        0, 0, 0, 0, 0, 0x2C, 1, 0, 0x13, 0x0B, 0, 0, 0x13, 0x0B, 0, 0, /* 76,800 bytes, 72 dpi */
        0, 1, 0, 0, 0, 0, 0, 0                                         /* 256 colours */
    };
    h = vr_fopen(expname, 'w');
    if (!h)
        return vr_ferr;
    memcpy(mbuf, head, 54);
    FWrite(h, mbuf, 54);
    for (i = 0; i < 16; ++i) {          /* the palette: B, G, R, 0 */
        for (k = 0; k < 16; ++k) {
            v = pal[i * 16 + k];
            mbuf[k * 4] = (v & 15) * 17;
            mbuf[k * 4 + 1] = (v >> 4 & 15) * 17;
            mbuf[k * 4 + 2] = (v >> 8 & 15) * 17;
            mbuf[k * 4 + 3] = 0;
        }
        FWrite(h, mbuf, 64);
    }
    pa_x = 0;
    pa_n = PW;
    for (i = PH; i--; ) {               /* the rows bottom up */
        pa_y = i;
        row_get();
        FWrite(h, rowbuf, PW);
    }
    FClose(h);
    return 0;
}

/* a print (a PDF named expname, A4 at 150 dpi): the picture dithered to
   640 x 480 dots at the page's top left (4.3 x 3.2 inches) */
unsigned char x7_print(void)
{
    unsigned char e, y, r, k;
    unsigned int rb;
    levels();
    if ((e = PrintOpen(expname, 0)) != 0)
        return e;
    rb = r1;                            /* the page's bytes a row (A4, 150 dpi: 155) */
    for (y = 0; y < PH && !e; ++y) {
        dither(y, PW);
        for (k = 0; k < 2 && !e; ++k) { /* a row of dots, the rest of the page's paper */
            memcpy(rowbuf, mbuf + k * 80, 80);
            memset(rowbuf + 80, 0, rb - 80);
            e = PrintBand(rowbuf, 1);
        }
    }
    r = PrintClose();
    return e ? e : r;
}
