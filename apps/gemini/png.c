/* Veranda Gemini: PNG pictures (overlay 5; DECISIONS V125).

   A PNG file on the card (the picture's temporary file) decoded a slice at
   a time from the main loop and shown in VERA's 4 bpp tiles (the kernel's
   tile mode, as the SDK's vr_pic sets it up, V105) under the window:

     the file      read through main RAM's ln (256 bytes); the chunks
                   walked (IHDR, PLTE, tRNS; IDAT's bytes to inflate; the
                   others and the CRCs skipped)
     inflate       RFC 1951, after Commander Calc's inflate.c (Marcin
                   Spoczynski, MIT: src/import/inflate.c, reused with its
                   canonical Huffman decoder and tables), its 32 KB window
                   in VRAM's back screen ($09600-$115FF: tile mode does not
                   use it) through VERA's two data ports: a literal is one
                   store, a match a run of loads and stores
     unfilter      the five filters, a row at a time, the row in VRAM
                   ($11600-$128FF: 4,864 bytes, up to 1,216 pixels of RGBA)
                   rewritten in place (the row above read, this one written)
     pixels        1-16 bits (16-bit samples by their high byte), every
                   colour type; alpha (and a palette's tRNS) over white
     scaling       to fit the page (624 x 408 pixels, 912 tiles at most),
                   never more than twice; across, a box filter (the mean of
                   the pixels of each column of the picture); down, the
                   nearest row (rows not shown are only unfiltered)
     colours       16, per picture: a palette of up to 16 colours as it is
                   (no dither); a grey picture (or a palette of greys) 16
                   greys; any other 2 reds x 4 greens x 2 blues; with a 4 x 4
                   ordered dither
     the tiles     a row of 8 output rows at a time: tile row r of each
                   tile, 4 bytes, from outrow; the map's entries (palette
                   row 2) set at the start

   Interlaced (Adam7) pictures are refused (PE_INTERLACE). Compiled for the
   host too (PNG_HOST: tests/png_host.c) against Python's reference.

   MIT licence (see LICENSE). */
#include <string.h>
#ifdef PNG_HOST
#include "png_host.h"
#else
#include <veranda.h>
#include "gemini.h"
#include "png.h"
#include <vrser.h>
#define PNG_NOW() ser_frames
#pragma code-name ("OVERLAY5")
#pragma rodata-name ("OVL5RO")
#pragma bss-name ("OVL5BSS")
#define VCTRL  (*(volatile unsigned char *)0x9F25)
#define VAL    (*(volatile unsigned char *)0x9F20)
#define VAM    (*(volatile unsigned char *)0x9F21)
#define VAH    (*(volatile unsigned char *)0x9F22)
#define VD0    (*(volatile unsigned char *)0x9F23)
#define VD1    (*(volatile unsigned char *)0x9F24)
#endif

#define WINV   0x09600UL        /* the window (32 KB) */
#define ROWV   0x11600UL        /* the row (ROWMAX; the code lengths after it, at $12900) */
#define ROWMAX 4864u
#define TILEV  0x13000UL
#define MAPV   0x1AC00UL


unsigned char pch, bpp, psb;              /* channels, filter bytes a pixel, bytes a sample (pngcore.s reads them) */
unsigned int rowb;                      /* bytes a row */
unsigned char pr[256], pg[256], pb[256];        /* the palette over white */
static unsigned char npal;

/*---------------------------------------------------------------- the file */
unsigned int ip, il;                    /* ln: the next byte, the bytes in it */
unsigned long clen;                     /* the chunk's bytes left (IDAT) */

/* clen - 1 (no 32-bit sums: cc65's helpers for them are in main RAM) */
static void cdec(void)
{
    unsigned char *p = (unsigned char *)&clen;
    if (!p[0]--)
        if (!p[1]--)
            if (!p[2]--)
                --p[3];
}
static unsigned char eof;

#ifndef PNG_HOST

#define FREAD(n) FRead(png_h, ln, n)
#endif

static unsigned char rawb(void)
{
    if (ip == il) {
        il = FREAD(256);
        ip = 0;
        if (!il) {
            eof = 1;
            return 0;
        }
    }
    return ln[ip++];
}

static unsigned long be32(void)
{
    static unsigned long v;              /* (no shifts of 32 bits: cc65's helpers are in main RAM) */
    unsigned char i;
    for (i = 4; i--; )
        ((unsigned char *)&v)[i] = rawb();
    return v;
}

static char ctype[5];

/* the next chunk's length and type (ctype) */
static void next_chunk(void)
{
    unsigned char i;
    clen = be32();
    for (i = 0; i < 4; ++i)
        ctype[i] = rawb();
}

static void __fastcall__ skip(unsigned char n)
{
    while (n-- && !eof)
        rawb();
}

/* x / 255 for x < 65535 */
#define DIV255(x) ((unsigned char)(((x) + 1 + ((x) >> 8)) >> 8))

/* c with alpha a over white */
static unsigned char __fastcall__ over(unsigned char c, unsigned char a)
{
    unsigned int x = (unsigned int)c * a + 255u * (unsigned char)(255 - a);
    return DIV255(x);
}

/*---------------------------------------------------------------- VERA's ports */
#ifndef PNG_HOST
static void __fastcall__ vset(unsigned char port, unsigned long a)
{
    VCTRL = port;
    VAL = (unsigned char)a;
    VAM = (unsigned char)(a >> 8);
    VAH = 0x10 | (unsigned char)(a >> 16);
}
#define VW(b) (VD0 = (b))
#define VR() VD1
static unsigned char keepa[6];
static void keep_ports(void)
{
    VCTRL = 0;
    keepa[0] = VAL; keepa[1] = VAM; keepa[2] = VAH;
    VCTRL = 1;
    keepa[3] = VAL; keepa[4] = VAM; keepa[5] = VAH;
}
static void back_ports(void)
{
    VCTRL = 0;
    VAL = keepa[0]; VAM = keepa[1]; VAH = keepa[2];
    VCTRL = 1;
    VAL = keepa[3]; VAM = keepa[4]; VAH = keepa[5];
}
#endif

/* IDAT's next byte (the chunks crossed; the ports kept over a read) */
unsigned char inb(void)
{
    if (!clen || ip == il) {
        keep_ports();
        while (!clen) {
            skip(4);                    /* (the CRC) */
            next_chunk();
            if (eof || memcmp(ctype, "IDAT", 4)) {
                perr = PE_DATA;
                clen = 1;
                ip = il = 0;
                ln[0] = 0;
                break;
            }
        }
        if (ip == il) {
            rawb();
            --ip;
        }
        back_ports();
    }
    cdec();
    return ln[ip++];
}

#ifdef PNG_HOST                 /* (the host's; on the X16 pngcore.s does these) */
/*---------------------------------------------------------------- inflate (Commander Calc's) */
#define ST_HEADER 0
#define ST_STORED 1
#define ST_CODES  2
#define ST_DONE   3

static unsigned int bb;                 /* bits, least significant first */
static unsigned char bc;
static unsigned char state, last;
static unsigned int left, copy_len, copy_dist, wpos;
static unsigned char wrapped;
static unsigned int lcount[16], lsym[288], dcount[16], dsym[30];
static unsigned char cl[320];

static const unsigned char bmask[9] = { 0, 1, 3, 7, 15, 31, 63, 127, 255 };

/* n bits (at most 8) */
static unsigned char __fastcall__ bits(unsigned char n)
{
    unsigned char v;
    if (bc < n) {
        bb |= (unsigned int)inb() << bc;
        bc += 8;
    }
    v = (unsigned char)bb & bmask[n];
    bb >>= n;
    bc -= n;
    return v;
}

static unsigned int __fastcall__ bits16(unsigned char n)
{
    unsigned int v;
    if (n <= 8)
        return bits(n);
    v = bits(8);
    return v | ((unsigned int)bits(n - 8) << 8);
}

static void __fastcall__ build(unsigned int *count, unsigned int *symbol, unsigned int base, unsigned int n)
{
    static unsigned int offs[16];
    unsigned int s;
    unsigned char len;
    memset(count, 0, 16 * sizeof count[0]);
    for (s = 0; s < n; ++s)
        ++count[cl[base + s]];
    count[0] = 0;
    offs[1] = 0;
    for (len = 1; len < 15; ++len)
        offs[len + 1] = offs[len] + count[len];
    for (s = 0; s < n; ++s)
        if ((len = cl[base + s]) != 0)
            symbol[offs[len]++] = s;
}

static int __fastcall__ decode(const unsigned int *count, const unsigned int *symbol)
{
    int code = 0, first = 0, index = 0, n;
    unsigned char len;
    for (len = 1; len < 16; ++len) {
        if (!bc) {
            bb = inb();
            bc = 8;
        }
        code |= bb & 1;
        bb >>= 1;
        --bc;
        n = count[len];
        if (code - first < n)
            return symbol[index + (code - first)];
        index += n;
        first = (first + n) << 1;
        code <<= 1;
    }
    perr = PE_DATA;
    return -1;
}

static void fixed(void)
{
    unsigned int i;
    memset(cl, 8, 144);
    memset(cl + 144, 9, 112);
    memset(cl + 256, 7, 24);
    memset(cl + 280, 8, 8);
    build(lcount, lsym, 0, 288);
    memset(cl, 5, 30);
    build(dcount, dsym, 0, 30);
    (void)i;
}

static const unsigned char order[19] = { 16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15 };

static void dynamic(void)
{
    unsigned int nlen, ndist, ncode, i, rep;
    int s;
    unsigned char v;
    nlen = bits(5) + 257;
    ndist = bits(5) + 1;
    ncode = bits(4) + 4;
    if (nlen > 286 || ndist > 30) {
        perr = PE_DATA;
        return;
    }
    for (i = 0; i < 19; ++i)
        cl[order[i]] = i < ncode ? bits(3) : 0;
    build(dcount, dsym, 0, 19);
    for (i = 0; i < nlen + ndist && !perr; ) {
        s = decode(dcount, dsym);
        if (s < 0)
            return;
        if (s < 16) {
            cl[i++] = s;
            continue;
        }
        v = 0;
        if (s == 16) {
            if (!i) {
                perr = PE_DATA;
                return;
            }
            v = cl[i - 1];
            rep = 3 + bits(2);
        } else if (s == 17)
            rep = 3 + bits(3);
        else
            rep = 11 + bits(7);
        if (i + rep > nlen + ndist) {
            perr = PE_DATA;
            return;
        }
        while (rep--)
            cl[i++] = v;
    }
    build(lcount, lsym, 0, nlen);
    build(dcount, dsym, nlen, ndist);
}

static const unsigned int lbase[29] = { 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43,
    51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258 };
static const unsigned char lextra[29] = { 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3,
    4, 4, 4, 4, 5, 5, 5, 5, 0 };
static const unsigned int dbase[30] = { 1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385,
    513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577 };
static const unsigned char dextra[30] = { 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9,
    10, 10, 11, 11, 12, 12, 13, 13 };

static unsigned char obuf[256];

/* a byte into the window (port 0 at wpos) and obuf */
#define PUT(b) do { VW(b); obuf[n++] = (b); if (++wpos == 0x8000u) { wpos = 0; wrapped = 1; vset(0, WINV); } } while (0)

/* up to 256 bytes into obuf: their count (0: the end, or perr) */
static unsigned int inflate(void)
{
    unsigned int n = 0, src;
    unsigned char b, t;
    int s;
    vset(0, WINV + wpos);
    while (n < 256 && !perr && state != ST_DONE) {
        if (copy_len) {
            src = (wpos - copy_dist) & 0x7FFF;
            if (copy_dist == 1) {       /* (a run: port 1's prefetch would be stale) */
                vset(1, WINV + src);
                b = VR();
                vset(0, WINV + wpos);
                while (copy_len && n < 256) {
                    PUT(b);
                    --copy_len;
                }
                continue;
            }
            vset(1, WINV + src);
            vset(0, WINV + wpos);
            while (copy_len && n < 256) {
                b = VR();
                if (++src == 0x8000u) {
                    src = 0;
                    vset(1, WINV);
                }
                PUT(b);
                --copy_len;
            }
            continue;
        }
        switch (state) {
        case ST_HEADER:
            last = bits(1);
            t = bits(2);
            if (t == 0) {
                bc = 0;
                bb = 0;
                left = inb();
                left |= (unsigned int)inb() << 8;
                s = inb();
                s |= inb() << 8;
                if (((left ^ (unsigned int)s) & 0xFFFF) != 0xFFFF)
                    perr = PE_DATA;
                state = ST_STORED;
            } else if (t == 1) {
                fixed();
                state = ST_CODES;
            } else if (t == 2) {
                dynamic();
                state = ST_CODES;
            } else
                perr = PE_DATA;
            vset(0, WINV + wpos);       /* (inb may have read the card) */
            break;
        case ST_STORED:
            if (!left) {
                state = last ? ST_DONE : ST_HEADER;
                break;
            }
            b = inb();
            PUT(b);
            --left;
            break;
        case ST_CODES:
            s = decode(lcount, lsym);
            if (s < 0)
                break;
            if (s < 256) {
                PUT((unsigned char)s);
            } else if (s == 256)
                state = last ? ST_DONE : ST_HEADER;
            else {
                s -= 257;
                if (s >= 29) {
                    perr = PE_DATA;
                    break;
                }
                copy_len = lbase[s] + bits(lextra[s]);
                s = decode(dcount, dsym);
                if (s < 0 || s >= 30) {
                    perr = PE_DATA;
                    break;
                }
                copy_dist = dbase[s] + bits16(dextra[s]);
                if (!wrapped && copy_dist > wpos) {
                    perr = PE_DATA;
                    copy_len = 0;
                }
            }
            break;
        }
    }
    return n;
}

/*---------------------------------------------------------------- pixels to tiles */
static unsigned int rpos;               /* the byte in the row (0: its filter type) */
static unsigned char ftype, la[8], lc[8], li;   /* the last bpp bytes of this row, of the row above */
static unsigned int iy, oy, accy, accx, ox;
static unsigned char show;              /* this row is shown (emitted show times) */
static unsigned char outrow[320];       /* the output row's pixels, 4 bpp */
static unsigned int sr, sg, sbl;        /* the sums across */
static unsigned char nsum, cr, cg, cbl, ci, ki;
static unsigned int smp;
static unsigned char px[4];             /* a pixel's samples */

/* the ordered dither's thresholds: a 4 x 4 Bayer matrix b, ((2b + 1) * 255) / 32 */
static const unsigned char thr[16] = { 7, 135, 39, 167, 199, 71, 231, 103, 55, 183, 23, 151, 247, 119, 215, 87 };

/* an output pixel (cr, cg, cbl, or ci) at ox */
static void emit(void)
{
    unsigned char t, v;
    unsigned int o = ox;
    unsigned int x;
    if (nsum) {
        if (pmode != PM_DIRECT) {
            cr = (sr + (nsum >> 1)) / nsum;
            if (pmode == PM_COLOUR) {
                cg = (sg + (nsum >> 1)) / nsum;
                cbl = (sbl + (nsum >> 1)) / nsum;
            }
        }
        nsum = 0;
        sr = sg = sbl = 0;
    }
    t = thr[((oy & 3) << 2) | (o & 3)];
    if (pmode == PM_DIRECT)
        v = ci;
    else if (pmode == PM_GRAY) {
        x = (unsigned int)cr * 15 + t;
        v = DIV255(x);
    } else {
        x = cr + t;
        v = DIV255(x) << 3;
        x = (unsigned int)cg * 3 + t;
        v |= DIV255(x) << 1;
        x = cbl + t;
        v |= DIV255(x);
    }
    if (o & 1)
        outrow[o >> 1] = (outrow[o >> 1] & 0xF0) | v;
    else
        outrow[o >> 1] = (outrow[o >> 1] & 0x0F) | (v << 4);
    ++ox;
}

/* a picture's pixel (cr, cg, cbl; ci the palette's index): across */
static void pixel(void)
{
#ifdef PNG_TEST_PIXEL
    PNG_TEST_PIXEL();             /* (the test: every row's pixels summed) */
    if (!show)
        return;
#endif
    if (pmode == PM_DIRECT)
        nsum = 0;
    else {
        sr += cr;
        sg += cg;
        sbl += cbl;
        ++nsum;
    }
    accx += pow_;
    while (accx >= pw) {
        accx -= pw;
        emit();
    }
}

static void __fastcall__ index_px(unsigned char i)
{
    ci = i;
    cr = pr[i];
    cg = pg[i];
    cbl = pb[i];
    pixel();
}

static void __fastcall__ gray_px(unsigned char v)
{
    cr = cg = cbl = v;
    pixel();
}

/* row byte v (unfiltered) of a shown row */
static void __fastcall__ sample(unsigned char v)
{
    unsigned char k, d;
    if (pdepth < 8) {
        d = pdepth;
        for (k = 8 / d; k && smp < pw; --k, ++smp) {
            v = (v << d) | (v >> (8 - d));      /* (rotate: the top sample to the bottom) */
            if (pctype == 3)
                index_px(v & bmask[d]);
            else
                gray_px((v & bmask[d]) * (255 / bmask[d]));
        }
        return;
    }
    if (psb == 2 && (rpos & 1) == 0)
        return;                         /* (a 16-bit sample's low byte) */
    px[li++] = v;
    if (li < pch)
        return;
    li = 0;
    switch (pctype) {
    case 0: gray_px(px[0]); break;
    case 3: index_px(px[0]); break;
    case 4: gray_px(over(px[0], px[1])); break;
    case 2:
        cr = px[0]; cg = px[1]; cbl = px[2];
        pixel();
        break;
    default:
        cr = over(px[0], px[3]); cg = over(px[1], px[3]); cbl = over(px[2], px[3]);
        pixel();
    }
}

/* the output row oy to the tiles (tile row oy & 7) */
static void out_row(void)
{
    unsigned char tx, k;
    unsigned int t = (oy >> 3) * ptw;
    unsigned char *p = outrow;
    for (tx = 0; tx < ptw; ++tx, ++t) {
        vset(0, TILEV + (unsigned long)(t < 464 ? 16 + t : 80 + t) * 32 + ((oy & 7) << 2));
        for (k = 0; k < 4; ++k)
            VW(*p++);
    }
#ifdef PNG_TEST_ROW
    PNG_TEST_ROW();
#endif
    ++oy;
}

/* the start of a row: shown? */
static void row_start(void)
{
    show = 0;
    accy += poh;
    while (accy >= ph) {
        accy -= ph;
        ++show;
    }
    smp = li = 0;
    accx = ox = 0;
    nsum = 0;
    sr = sg = sbl = 0;
}

/* the end of a row */
static void row_end(void)
{
    if (show) {
        while (ox < ptw * 8) {          /* (the tiles' columns past the picture: white) */
            ci = 15;
            cr = cg = cbl = 255;
            emit();
        }
        while (show--)
            out_row();
    }
#ifdef PNG_TEST_IROW
    PNG_TEST_IROW();
#endif
    ++iy;
    rpos = 0;
    vset(1, ROWV);
    vset(0, ROWV);
}

static unsigned char __fastcall__ paeth(unsigned char a, unsigned char b, unsigned char c)
{
    int p = (int)a + b - c, pa = p - a, pb = p - b, pc = p - c;
    if (pa < 0) pa = -pa;
    if (pb < 0) pb = -pb;
    if (pc < 0) pc = -pc;
    if (pa <= pb && pa <= pc)
        return a;
    return pb <= pc ? b : c;
}

/* obuf's n bytes: unfiltered, the shown rows' pixels */
static void __fastcall__ unfilter(unsigned int n)
{
    unsigned char *p = obuf, x, a, b, c, k;
    vset(1, ROWV + (rpos ? rpos - 1 : 0));
    vset(0, ROWV + (rpos ? rpos - 1 : 0));
    while (n--) {
        x = *p++;
        if (!rpos) {
            ftype = x;
            if (x > 4)
                perr = PE_DATA;
            memset(la, 0, 8);
            memset(lc, 0, 8);
            ki = 0;
            row_start();
            ++rpos;
            continue;
        }
        k = ki;
        if (++ki == bpp)
            ki = 0;
        a = la[k];
        c = lc[k];
        b = VR();
        switch (ftype) {
        case 1: x += a; break;
        case 2: x += b; break;
        case 3: x += (unsigned char)(((unsigned int)a + b) >> 1); break;
        case 4: x += paeth(a, b, c); break;
        }
        VW(x);
        la[k] = x;
        lc[k] = b;
#ifdef PNG_TEST_PIXEL
        if (show || png_sums)
#else
        if (show)
#endif
            sample(x);
        if (rpos++ == rowb) {
            row_end();
            if (iy == ph)
                return;
        }
    }
}

#endif
#ifndef PNG_HOST
extern unsigned int iy, oy;              /* (pngcore.s: the rows done, the rows shown) */
unsigned int inflate(void);
void __fastcall__ unfilter(unsigned char n);
void core_init(void);
#ifdef GEMINI_TEST
extern unsigned char png_sums;          /* (main.c's, the test's: every row's pixels summed, "GE IROW y sum") */
extern unsigned int rowsum;
void png_test_row(void)
{
    if (!png_sums)
        return;
    strcpy(line, "GE IROW ");
    unum(line + 8, iy);
    strcat(line, " ");
    unum(line + strlen(line), rowsum);
    gt_log(line);
}
#endif
#endif

/*---------------------------------------------------------------- the start */

/* the header's chunks up to the first IDAT: 0, or PE_* */
unsigned char png_open(void)
{
    static const unsigned char sig[8] = { 137, 'P', 'N', 'G', 13, 10, 26, 10 };
    unsigned char i, inter = 0, a, t[13];
    ip = il = 0;
    eof = perr = 0;
    npal = 0;
    for (i = 0; i < 8; ++i)
        if (rawb() != sig[i])
            return PE_NOTPNG;
    for (;;) {
        next_chunk();
        if (eof)
            return PE_DATA;
        if (!memcmp(ctype, "IHDR", 4) && clen == 13) {
            for (i = 0; i < 13; ++i)
                t[i] = rawb();
            if (t[0] || t[1] || t[4] || t[5])
                return PE_BIG;
            pw = (t[2] << 8) | t[3];
            ph = (t[6] << 8) | t[7];
            pdepth = t[8];
            pctype = t[9];
            inter = t[12];
            clen = 0;
        } else if (!memcmp(ctype, "PLTE", 4)) {
            for (i = 0; clen >= 3; ++i, cdec(), cdec(), cdec()) {
                pr[i] = rawb();
                pg[i] = rawb();
                pb[i] = rawb();
                npal = i + 1;
            }
        } else if (!memcmp(ctype, "tRNS", 4) && pctype == 3) {
            for (i = 0; clen; ++i, cdec()) {
                a = rawb();
                pr[i] = over(pr[i], a);
                pg[i] = over(pg[i], a);
                pb[i] = over(pb[i], a);
            }
        } else if (!memcmp(ctype, "IDAT", 4))
            break;
        else if (!memcmp(ctype, "IEND", 4))
            return PE_DATA;
        while (clen && !eof) {
            rawb();
            cdec();
        }
        skip(4);
    }
    if (inter)
        return PE_INTERLACE;
    switch (pctype) {
    case 0: pch = 1; break;
    case 2: pch = 3; break;
    case 3: pch = 1; break;
    case 4: pch = 2; break;
    case 6: pch = 4; break;
    default: return PE_DATA;
    }
    if (pdepth == 16)
        psb = 2;
    else if (pdepth == 8 || ((pctype == 0 || pctype == 3) && (pdepth == 1 || pdepth == 2 || pdepth == 4)))
        psb = 1;
    else
        return PE_DATA;
    if (pctype == 3 && !npal)
        return PE_DATA;
    bpp = pdepth < 8 ? 1 : pch * psb;
    a = pch * pdepth;                   /* (bits a pixel; 16-bit sums: see be32) */
    if (pw > ROWMAX)
        return PE_BIG;
    rowb = a >= 8 ? pw * (a >> 3) : (pw >> 3) * a + (((pw & 7) * a + 7) >> 3);
    if (!pw || !ph || rowb > ROWMAX)
        return PE_BIG;
    /* the colours: grey pictures (and palettes of greys) 16 greys; a
       palette of up to 16 its own (ppal); others the fixed 16 */
    pmode = pctype == 0 || pctype == 4 ? PM_GRAY : PM_COLOUR;
    if (pctype == 3) {
        for (i = 0; i < npal && pr[i] == pg[i] && pg[i] == pb[i]; ++i)
            ;
        pmode = npal <= 16 ? PM_DIRECT : i == npal ? PM_GRAY : PM_COLOUR;
        for (i = 0; i < 16; ++i)
            ppal[i] = i < npal ? ((pr[i] + 8) / 17 << 8) + ((pg[i] + 8) / 17 << 4) + (pb[i] + 8) / 17 : 0xFFF;
    }
    return 0;
}

/* (after png_open and pngplan.c's png_plan) the decoder's start: the row
   above the first zeros, zlib's header */
void png_start(void)
{
    unsigned int i;
#ifndef PNG_HOST
    if (pjpeg) {                        /* (V192: a JPEG, overlays 6 and 7) */
        ov6(jpg_start);
        ov7(jinit);
        return;
    }
#endif
#ifdef PNG_HOST
    bb = bc = 0;
    state = ST_HEADER;
    wpos = copy_len = 0;
    wrapped = 0;
    rpos = iy = oy = accy = 0;
#else
    core_init();
#endif
    vset(0, ROWV);
    for (i = 0; i < rowb; ++i)
        VW(0);
    if ((inb() & 15) != 8)              /* (CMF: deflate; FLG) */
        perr = PE_DATA;
    inb();
}

/* about frames' worth of decoding: 0 more to come, 1 done, PE_* */
unsigned char __fastcall__ png_step(unsigned char frames)
{
    unsigned int n, t0 = PNG_NOW();
    do {
        n = inflate();
        if (n)
            unfilter(n);
        if (perr)
            return perr;
        if (iy >= ph)
            return 1;
        if (!n)
            return PE_DATA;             /* (the data ended before the picture) */
    } while ((unsigned int)(PNG_NOW() - t0) < frames);
    return 0;
}

#ifndef PNG_HOST
/* (pic.c's calls, through main.c's ov5) */
void png_open_v(void)
{
    if (pjpeg)                          /* (V192: a JPEG, overlay 6) */
        ov6(jpg_open_v);
    else
        u_ret = png_open();
}

void png_step_v(void)
{
    if (pjpeg) {                        /* (overlay 7) */
        ov7(jpg_step_v);
        return;
    }
    u_ret = png_step(png_frames);
    oy_done = oy;
}
#endif
