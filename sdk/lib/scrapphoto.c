/* Veranda's clipboard: the Photo Scrap (scrap.h). MIT licence (see LICENSE).

   GEOS's compacted bitmap (as BitmapUp reads it): a count byte, then
     $01-$7F    the next byte, count times
     $80-$DB    count - $80 bytes as they are
     $DC-$FF    a pattern of count - $DC bytes (itself compacted) after
                the next byte, its repeat count
   The writer uses the first two over the whole stream (a run may go
   past the end of a row); the reader takes all three. */
#include <veranda.h>
#include <string.h>
#include "scrap.h"

static unsigned char row[80];

/*---------------------------------------------------------------
  the writer: runs of 3 or more repeated, the rest as literals
 ---------------------------------------------------------------*/
static unsigned char out[96];           /* the output buffer */
static unsigned char on;
static unsigned int total;              /* the bytes written (or counted) */
static unsigned char writing, werr;
static unsigned char lit[91], nlit;
static unsigned char last, cnt;

static void emit(const unsigned char *p, unsigned char n)
{
    total += n;
    if (!writing)
        return;
    if (on + n > sizeof out) {
        if (!werr)
            werr = scrap_write(out, on);
        on = 0;
    }
    memcpy(out + on, p, n);
    on += n;
}

static void flush_lit(void)
{
    unsigned char c;
    if (!nlit)
        return;
    c = 0x80 + nlit;
    emit(&c, 1);
    emit(lit, nlit);
    nlit = 0;
}

static void flush_run(void)
{
    unsigned char b[2];
    if (cnt >= 3) {
        flush_lit();
        b[0] = cnt;
        b[1] = last;
        emit(b, 2);
    } else
        while (cnt) {
            lit[nlit++] = last;
            if (nlit == sizeof lit)
                flush_lit();
            --cnt;
        }
    cnt = 0;
}

static void put(unsigned char b)
{
    if (cnt && (b != last || cnt == 127))
        flush_run();
    last = b;
    ++cnt;
}

static void put_end(void)
{
    flush_run();
    flush_lit();
}

/* the whole picture through put(): rows, then the colours */
static void stream(unsigned char w, unsigned int h,
                   void (*get)(unsigned int y, unsigned char *row),
                   unsigned char (*colour)(unsigned char cx, unsigned char cy))
{
    unsigned int y;
    unsigned char x, cy;
    total = 0;
    on = nlit = cnt = 0;
    for (y = 0; y < h; ++y) {
        get(y, row);
        for (x = 0; x < w; ++x)
            put(row[x]);
    }
    put_end();
    if (colour) {
        for (cy = 0; cy < (h + 7) >> 3; ++cy)
            for (x = 0; x < w; ++x)
                put(colour(x, cy));
        put_end();
    }
}

unsigned char scrap_put_photo(unsigned char w, unsigned int h,
                              void (*get)(unsigned int y, unsigned char *row),
                              unsigned char (*colour)(unsigned char cx, unsigned char cy))
{
    unsigned char e, head[3];
    if (!w || w > 80 || !h)
        return INCOMPATIBLE;
    writing = 0;                        /* the size first */
    stream(w, h, get, colour);
    if ((e = scrap_create(SCRAP_PHOTO, total + 3)) != 0)
        return e;
    head[0] = w;
    head[1] = h;
    head[2] = h >> 8;
    werr = scrap_write(head, 3);
    writing = 1;
    stream(w, h, get, colour);
    if (on && !werr)
        werr = scrap_write(out, on);
    writing = 0;
    e = scrap_close();
    return werr ? werr : e;
}

/*---------------------------------------------------------------
  the reader
 ---------------------------------------------------------------*/
static unsigned char in[64], ii, ik;
static unsigned char pat[36], plen, ppos, prep;
static unsigned char mode, n, val;      /* mode 1 repeat, 2 literals */
static unsigned char bad;

/* the next byte of the file */
static unsigned char raw_file(void)
{
    if (ii == ik) {
        ik = scrap_read(in, sizeof in);
        ii = 0;
        if (!ik) {
            bad = 1;
            return 0;
        }
    }
    return in[ii++];
}

/* the next compacted byte: the pattern's while it repeats */
static unsigned char raw(void)
{
    unsigned char c;
    if (!prep)
        return raw_file();
    c = pat[ppos++];
    if (ppos == plen) {
        ppos = 0;
        --prep;
    }
    return c;
}

static unsigned char decode(void)
{
    unsigned char c;
    while (!n) {
        if (bad)
            return 0;
        c = raw();
        if (c >= 0xDC) {
            if (prep) {                 /* (a pattern in a pattern) */
                bad = 1;
                return 0;
            }
            plen = c - 0xDC;
            c = raw_file();
            for (ppos = 0; ppos < plen; ++ppos)
                pat[ppos] = raw_file();
            ppos = 0;
            prep = plen ? c : 0;
        } else if (c >= 0x80) {
            n = c - 0x80;
            mode = 2;
        } else {
            n = c;
            mode = 1;
            val = raw();
        }
    }
    --n;
    return mode == 1 ? val : raw();
}

static unsigned char sw;
static unsigned int sh;

unsigned char __fastcall__ scrap_photo_size(unsigned char *w, unsigned int *h)
{
    unsigned char head[3];
    if (!scrap_open(SCRAP_PHOTO))
        return FILE_NOT_FOUND;
    if (scrap_read(head, 3) != 3) {
        scrap_close();
        return INCOMPATIBLE;
    }
    sw = *w = head[0];
    sh = *h = head[1] | head[2] << 8;
    if (!sw || sw > 80 || !sh) {
        scrap_close();
        return INCOMPATIBLE;
    }
    return 0;
}

unsigned char scrap_get_photo(void (*put)(unsigned int y, const unsigned char *row),
                              void (*colour)(unsigned char cx, unsigned char cy, unsigned char c))
{
    unsigned char w, x, cy, e;
    unsigned int h, y;
    if ((e = scrap_photo_size(&w, &h)) != 0)
        return e;
    ii = ik = 0;
    n = prep = bad = 0;
    for (y = 0; y < h && !bad; ++y) {
        for (x = 0; x < w; ++x)
            row[x] = decode();
        if (!bad)
            put(y, row);
    }
    if (bad) {
        scrap_close();
        return INCOMPATIBLE;
    }
    /* colours, if there is more */
    if (colour && !n && ii == ik) {
        ik = scrap_read(in, sizeof in);
        ii = 0;
    }
    if (colour && (ii < ik || n)) {
        for (cy = 0; cy < (h + 7) >> 3 && !bad; ++cy)
            for (x = 0; x < w; ++x) {
                e = decode();
                if (bad)
                    break;
                colour(x, cy, e);
            }
    }
    scrap_close();
    return 0;
}
