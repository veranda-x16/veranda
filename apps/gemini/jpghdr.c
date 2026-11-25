/* Veranda Gemini: JPEG pictures, the header (overlay 6; DECISIONS V192).

   A JPEG file on the card (the picture's temporary file) is shown as
   png.c shows a PNG (the same tiles, sizes, 16 colours and dither:
   pngplan.c places it); this reads its header and sets the decoder up,
   jpegcore.s (overlay 7) decodes it an MCU or a row at a time from the
   main loop:

     the header    the quantisation tables (AAN-scaled for the IDCT), the
                   Huffman tables (canonical: the first code past each
                   length), the frame (8-bit baseline or extended
                   Huffman: SOF0, SOF1), the restart interval, the scan;
                   progressive and arithmetic-coded pictures refused
                   (PE_PROG), 12-bit samples, samplings other than Y at
                   1 x 1 to 2 x 2 with Cb and Cr at 1 x 1, and separate
                   scans for the components too (PE_BIG)
     the size      a picture shown at 1/8 of its size or less is decoded
                   at 1/8: each block's DC alone (bs 1)
     the planes    an MCU row in VRAM's back screen from $09600 (37,632
                   bytes to $128FF: the PNG decoder's window and row):
                   Y's rows, then Cb and Cr interleaved

   The tables and the set-up go into overlay 7's jsx (jpeg.h) through
   BankCopy. tests/jpeg_ref.py is the same steps in Python;
   tests/jpeg_bench.c runs this and jpegcore.s on the X16's own (cx16)
   runtime for the gate's timings.

   MIT licence (see LICENSE). */
#include <string.h>
#ifdef JPEG_BENCH
#include "jpeg_bench.h"
#define TO7(d, s, n) memcpy((d), (s), (n))
#else
#include <veranda.h>
#include "gemini.h"
#include "png.h"
#define FREAD(n) FRead(png_h, ln, n)
#define TO7(d, s, n) BankCopy((s), (d), (n), bOv6, bOv7)
#endif
#include "jpeg.h"

/*---------------------------------------------------------------- main RAM */
#ifndef JPEG_BENCH
#pragma code-name ("CODE")
#pragma bss-name ("BSS")
#endif
unsigned char jeof = 0;                 /* (initialised: main RAM's DATA; cc65 puts tentative BSS where the last bss-name says) */
unsigned int jw = 0, jh = 0;            /* the picture's size (the status bar's) */

/* ln refilled (jpegcore.s's fill, and rawb): 256 bytes, a short read's
   moved to its end; at the file's end 0xFF 0xD9 (EOI) over and over */
void jfill(void)
{
    unsigned int n = FREAD(256);
    if (!n) {
        ln[254] = 0xFF;
        ln[255] = 0xD9;
        jidx = 254;
        jeof = 1;
        return;
    }
    if (n < 256)
        memmove(ln + 256 - n, ln, n);
    jidx = (unsigned char)(256 - n);
}

/*---------------------------------------------------------------- overlay 6 */
#ifndef JPEG_BENCH
#pragma code-name ("OVERLAY6")
#pragma rodata-name ("OVL6RO")
#pragma bss-name ("OVL6BSS")
#endif

static struct jcfg jc;
static unsigned char tb[307];           /* a table on its way to overlay 7 */
static unsigned char nc, cid[3], csamp[3], ctq[3];      /* the frame's components: id, sampling (h << 4 | v), table */
static unsigned char ns, sid[3], stab[3];               /* the scan's: id, tables (dc << 4 | ac) */
static unsigned char hseen, qseen;      /* the Huffman, quantisation tables read (bits) */

/* AAN's scales (libjpeg's aanscales, 14 bits) in zigzag order */
static const unsigned int aanz[64] = {
    16384, 22725, 22725, 21407, 31521, 21407, 19266, 29692, 29692, 19266, 16384, 26722, 27969, 26722, 16384,
    12873, 22725, 25172, 25172, 22725, 12873, 8867, 17855, 21407, 22654, 21407, 17855, 8867, 4520, 12299,
    16819, 19266, 19266, 16819, 12299, 4520, 6270, 11585, 15137, 16384, 15137, 11585, 6270, 5906, 10426,
    12873, 12873, 10426, 5906, 5315, 8867, 10114, 8867, 5315, 4520, 6967, 6967, 4520, 3552, 4799, 3552,
    2446, 2446, 1247 };

static unsigned char rawb(void)
{
    unsigned char v = ln[jidx];
    if (!++jidx)
        jfill();
    return v;
}

static unsigned int be16(void)
{
    unsigned int v = (unsigned int)rawb() << 8;
    return v | rawb();
}

static unsigned int n;                  /* the segment's bytes left */

/* a DHT's table: 0 or PE_DATA */
static unsigned char dht(void)
{
    static unsigned char cnt[16];
    unsigned char t, i, k;
    unsigned int code, lim, total, o;
    t = rawb();
    if ((t & 0xEE) || n < 17)           /* (class 0-1, table 0-1) */
        return PE_DATA;
    for (i = 0, total = 0; i < 16; ++i)
        total += cnt[i] = rawb();
    n -= 17 + total;
    if (total > (t & 16 ? 256 : 16) || n > 0xFF00u)
        return PE_DATA;
    code = 0;
    k = 0;
    for (i = 0; i < 16; ++i) {          /* lim[l] (l = i + 1): the first code past length l */
        lim = code + cnt[i];
        if (i < 15 ? lim > (1u << (i + 1)) - 1 : lim < code)
            return PE_DATA;
        tb[i + 1] = (unsigned char)lim;
        tb[i + 18] = lim >> 8;
        tb[i + 35] = (unsigned char)(k - code);
        k += cnt[i];
        code = lim << 1;
    }
    for (code = 0; code < total; ++code)
        tb[51 + code] = rawb();
    o = t & 16 ? HT_AC0 + (t & 1) * 307 : (t & 1) * HT_DC1;
    TO7(jsx.htab + o, tb, 51 + total);
    hseen |= 1 << ((t >> 3) | (t & 1)); /* (bits: DC 0, 1, AC 0, 1) */
    return 0;
}

/* the header up to the scan's data: 0, or PE_* */
unsigned char jpg_open(void)
{
    unsigned char m, i, t;
    unsigned long q;
    jeof = 0;
    jidx = 0;
    perr = 0;
    hseen = qseen = 0;
    jc.dri = 0;
    nc = 0;
    jfill();
    if (rawb() != 0xFF || rawb() != 0xD8)
        return PE_NOTPNG;
    for (;;) {
        do
            m = rawb();
        while (m != 0xFF && !jeof);
        while (m == 0xFF && !jeof)
            m = rawb();
        if (jeof)
            return PE_DATA;
        if (m == 0xD8 || m == 0x01 || (m & 0xF8) == 0xD0)
            continue;
        if (m == 0xD9)
            return PE_DATA;
        n = be16() - 2;
        if (n > 0xFF00u)
            return PE_DATA;
        if (m == 0xDB) {                /* the quantisation tables */
            while (n >= 65) {
                t = rawb();
                if (t & 0xEC)
                    return PE_DATA;
                for (i = 0; i < 64; ++i) {
                    q = t & 16 ? be16() : rawb();
                    q = (q * aanz[i] + 2048) >> 12;
                    tb[i] = (unsigned char)q;
                    tb[64 + i] = (unsigned char)(q >> 8);
                }
                TO7(jsx.qlo + ((t & 3) << 6), tb, 64);
                TO7(jsx.qhi + ((t & 3) << 6), tb + 64, 64);
                qseen |= 1 << (t & 3);
                n -= t & 16 ? 129 : 65;
            }
        } else if (m == 0xC4) {
            while (n >= 17)
                if (dht())
                    return PE_DATA;
        } else if (m == 0xDD) {
            jc.dri = be16();
            n -= 2;
        } else if (m == 0xC0 || m == 0xC1) {
            if (rawb() != 8)
                return PE_BIG;
            jh = be16();
            jw = be16();
            nc = rawb();
            n -= 6;
            if (nc != 1 && nc != 3)
                return PE_BIG;
            for (i = 0; i < nc; ++i) {
                cid[i] = rawb();
                csamp[i] = rawb();
                ctq[i] = rawb() & 3;
                n -= 3;
            }
        } else if (m >= 0xC2 && m <= 0xCF && m != 0xC4 && m != 0xC8 && m != 0xCC)
            return PE_PROG;
        else if (m == 0xDA) {
            ns = rawb();
            if (!nc || ns != nc)
                return nc ? PE_BIG : PE_DATA;
            for (i = 0; i < ns; ++i) {
                sid[i] = rawb();
                stab[i] = rawb();
            }
            rawb();                     /* (Ss, Se, Ah Al) */
            rawb();
            rawb();
            break;
        }
        while (n-- && !jeof)
            rawb();
    }
    if (!jw || !jh)
        return PE_DATA;
    if (nc == 3) {
        t = csamp[0];
        if (csamp[1] != 0x11 || csamp[2] != 0x11 || (unsigned char)((t >> 4) - 1) > 1
            || (unsigned char)((t & 15) - 1) > 1)
            return PE_BIG;
    }
    if (jw > 1568u * 8)
        return PE_BIG;
    pw = jw;
    ph = jh;
    pmode = nc == 1 ? PM_GRAY : PM_COLOUR;
    return 0;
}

/* (after jpg_open and pngplan.c's png_plan) the size decoded, the planes,
   the MCU's blocks: jsx.c */
void jpg_start(void)
{
    unsigned char i, k, c, h, v, bx, by, b, bs, hmax, vmax;
    unsigned int ys;
    bs = (jw + 7) >> 3 >= pow_ && (jh + 7) >> 3 >= poh ? 1 : 8;
    jc.bs = bs;
    pw = bs == 1 ? (jw + 7) >> 3 : jw;
    ph = bs == 1 ? (jh + 7) >> 3 : jh;
    hmax = nc == 1 ? 1 : csamp[0] >> 4;
    vmax = nc == 1 ? 1 : csamp[0] & 15;
    jc.hmax = hmax;
    jc.gray = nc == 1;
    jc.vmask = vmax - 1;
    jc.mcux = (jw + 8 * hmax - 1) / (8 * hmax);
    jc.ystride = ys = jc.mcux * hmax * bs;
    jc.yrows = vmax * bs;
    jc.cbase = ys * jc.yrows;
    jc.cstride = jc.mcux * bs * 2;
    if (pw > 1568 || (unsigned long)ys * jc.yrows + (nc == 3 ? (unsigned long)jc.cstride * bs : 0) > 37632UL)
        perr = PE_BIG;
    b = 0;
    for (i = 0; i < ns; ++i) {          /* the MCU's blocks in the scan's order */
        for (c = 0; c < nc && cid[c] != sid[i]; ++c)
            ;
        k = stab[i];
        if (c == nc || (k & 0xEE) || !(hseen & (1 << (k >> 4))) || !(hseen & (4 << (k & 1)))
            || !(qseen & (1 << ctq[c])))
            perr = PE_DATA;
        h = nc == 1 ? 1 : csamp[c] >> 4;
        v = nc == 1 ? 1 : csamp[c] & 15;
        for (by = 0; by < v; ++by)
            for (bx = 0; bx < h; ++bx, ++b) {
                jc.bt[b] = c;
                jc.bq[b] = ctq[c];
                jc.bdc[b] = (unsigned int)jsx.htab + (k >> 4 & 1) * HT_DC1;
                jc.bac[b] = (unsigned int)jsx.htab + HT_AC0 + (k & 1) * 307;
                if (!c) {
                    jc.bd0[b] = by * bs * ys + bx * bs;
                    jc.bstep[b] = hmax * bs;
                    jc.binc[b] = 0x10;
                    jc.bstr[b] = ys;
                } else {
                    jc.bd0[b] = jc.cbase + (c == 2);
                    jc.bstep[b] = bs * 2;
                    jc.binc[b] = 0x20;
                    jc.bstr[b] = jc.cstride;
                }
            }
    }
    jc.nblk = b;                        /* (at most 4 + 1 + 1: the samplings are checked) */
    TO7(&jsx.c, &jc, sizeof jc);
}

#ifndef JPEG_BENCH
/* (pic.c's calls, through main.c's ov6) */
void jpg_open_v(void)
{
    u_ret = jpg_open();
}
#endif
