/* View: a viewer for Veranda (C, MIT; DECISIONS V60).

   It shows a file without the application that made it:
     - text: wrapped at 80 columns (words kept whole when they fit), tabs
       to every 8th column, CR, LF or CR LF ending a line; scrolled with
       the keys; file/find and find again (case ignored), the match shown
       reversed;
     - BMP pictures, uncompressed, 1, 4, 8 or 24 bpp (Veranda's ExportRect
       writes 1 and 4: DECISIONS V28, V32): 1 bpp in the darker entry as
       the ink, 4 bpp with entry 1 the ink and the other pixels as each
       card's paper (the colour map, V30); 8 and 24 bpp as dark = ink;
     - Paint documents (versions 1-3: the picture, its cards' colours, the
       ink);
     - GEOS Photo Scraps and photo albums (a page a record), their colours;
     - any other GEOS file (CVT) as its info block: the icon, the type, the
       class, the author, the date, the description, as GEOS's info box.
   A picture larger than the screen's area is fitted (shrunk to fit, the
   nearest pixel), a smaller one zoomed by a whole factor; view/zoom
   switches to the actual size, panned with the keys a card at a time.
   File/open as text shows any file as text. Edit/copy puts the picture
   (all of it) on the
   Photo Scrap, or the page of text shown on the Text Scrap (scrap.h,
   V54).

   The shell starts it with a document (DECISIONS V48: it declares BMP;
   its whole name, dataLongName: V82); started alone, and with file/open
   or Esc, it shows the SDK's Open dialog (vrchoose.h, V79), compiled into
   overlay 2 (file_dlg maps it): names of up to 63 characters.

   The window (Veranda Look 2, DECISIONS V79; sdk vrwin.h): the menu bar
   (the kernel's, in the Veranda look), the title band (the file's name)
   at card rows 2-3, the view at rows 4-57, the status bar at rows 58-59.
   The text area is 8 x 8 cells in the X16's CP437 font (PutCards), 78
   columns, with a scroll bar in cards 78-79 (vr_scroll, Look 3
   "Sunroom": DECISIONS V148); the status bar and the info page are in
   the UI font (the info page's labels in a column, the name bold);
   tests/check_view.py draws the same screens on a PC. A file's
   bytes are kept in RAM banks (the pool). The info page's code is a
   banked overlay (overlay 1, mapped for good as appBank: the code that
   maps the pool's banks maps appBank back).

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <vr.h>
#include <string.h>
#include <stdlib.h>
#include <scrap.h>
#include <theme.h>
#include <vrwin.h>
#include <vrchoose.h>

#define RAMBANK (*(volatile unsigned char *)0)
#define BANKMEM ((unsigned char *)0xA000)

#define AREAY   32              /* the view: y 32-463, cards rows 4-57 */
#define AREAH   432
#define AREAW   640
#define ROWS    54              /* text rows */
#define COLS    80              /* the area's cards */
#define TCOLS   78              /* (V148) the text's columns: cards 78-79 its scroll bar */
#define STATX   1               /* the status: cards 1-78 of the status bar */
#define STATW   78
#define STATY   468
#define MAXW    640             /* the widest picture kept (wider: pre-scaled) */

enum { K_NONE, K_TEXT, K_PIC, K_INFO };
enum { P_BMP, P_PAINT, P_SCRAP, P_ALBUM };

/* fast.s */
void cv4(void);
extern unsigned char *cv_src, cv_n, *cv_out, cv_om, *cv_hist, cv_cmap[16];
void sc_row(void);
extern unsigned char *sc_src, *sc_dst;
extern unsigned int sc_dw;
extern unsigned char sc_bank;

#ifdef VIEW_TEST
void view_test_snap(const char *name);
void view_test_end(void);
void view_test_keys(const char *keys);
static void test_run(void);
#endif

static unsigned char font[2048];
static char line[100];
static unsigned char row[128];          /* a row: the screen's, a picture's */
static unsigned char work[1280];        /* a band, a colour record, histograms */
static unsigned char head[284];         /* a file's bytes 0-29 and 254-507: a CVT's entry, info block */
static unsigned int headn;

static unsigned char kind, isCvt, asText;
static char docname[VRF_NAME + 1];      /* the file shown (in the current folder) */
static unsigned char bDlg, bPool, nPool; /* bDlg: overlay 2, the Open dialog */
static unsigned long poolSize;

static const unsigned int vpal[16] = {  /* VERA's first 16 entries ($0RGB) */
    0xFFF, 0x000, 0x800, 0xAFE, 0xC4C, 0x0C5, 0x00A, 0xEE7,
    0xD85, 0x640, 0xF77, 0x333, 0x777, 0xAF6, 0x08F, 0xBBB
};

/*---------------------------------------------------------------
  small things
 ---------------------------------------------------------------*/
static const unsigned char smiley[8] = { 0x7E, 0x81, 0xA5, 0x81, 0xBD, 0x99, 0x81, 0x7E };

static void load_font(void)
{
    unsigned char keep, ok = 0;
    unsigned int a;
    asm("sei");
    keep = *(unsigned char *)1;
    *(unsigned char *)1 = 6;
    for (a = 0xC000; a; a += 0x800)
        if (!memcmp((void *)(a + 8), smiley, 8)) {
            memcpy(font, (void *)a, 2048);
            ok = 1;
            break;
        }
    if (!ok)
        memcpy(font, (void *)0xC800, 2048);
    *(unsigned char *)1 = keep;
    asm("cli");
}

static unsigned char lower(unsigned char c)
{
    return c >= 'A' && c <= 'Z' ? c + 32 : c;
}

/* a byte as a cell: control characters (and DEL) as '.' */
static unsigned char glyph(unsigned char c)
{
    return c < 32 || c == 127 ? '.' : c;
}

/* the window: its chrome (vrwin.h), its title the file shown */
static const struct vrwin win = { 0, 2, 80, 58, 0, 2, 0 };

/* (V148) the status bar's text in the UI font (vrwin.h) */
static void status(const char *s)
{
    vr_win_status(&win, s, 0);
}

static void num(unsigned long v)        /* appended to line */
{
    ultoa(v, line + strlen(line), 10);
}

#pragma code-name (push, "OVERLAY1")        /* (V148: room in main RAM) */
static unsigned char ciprefix(const unsigned char *s, const char *p)
{
    while (*p)
        if (lower(*s++) != *p++)
            return 0;
    return 1;
}
#pragma code-name (pop)

/*---------------------------------------------------------------
  the pool: the RAM banks from bPool on, as one memory
 ---------------------------------------------------------------*/
static unsigned char *pp(unsigned long off)
{
    unsigned char *b = (unsigned char *)&off;
    RAMBANK = bPool + (b[1] >> 5 | b[2] << 3);
    return BANKMEM + (*(unsigned int *)b & 0x1FFF);
}

static void pget(unsigned long off, unsigned char *d, unsigned int n)
{
    unsigned int k;
    while (n) {
        k = 0x2000 - ((unsigned int)off & 0x1FFF);
        if (k > n)
            k = n;
        memcpy(d, pp(off), k);
        d += k;
        off += k;
        n -= k;
    }
    RAMBANK = appBank;
}

static void pput(unsigned long off, const unsigned char *s, unsigned int n)
{
    unsigned int k;
    while (n) {
        k = 0x2000 - ((unsigned int)off & 0x1FFF);
        if (k > n)
            k = n;
        memcpy(pp(off), s, k);
        s += k;
        off += k;
        n -= k;
    }
    RAMBANK = appBank;
}

static unsigned char pbyte(unsigned long off)
{
    unsigned char b = *pp(off);
    RAMBANK = appBank;
    return b;
}

/*---------------------------------------------------------------
  the file: a buffered reader
 ---------------------------------------------------------------*/
static unsigned char fh;
static unsigned char rbuf[256];
static unsigned int rpos, rlen;
static unsigned long rat;               /* rbuf[0]'s offset */

static unsigned char ropen(const char *name)
{
    fh = vr_fopen(name, 'r');
    rpos = rlen = 0;
    rat = 0;
    return fh;
}

static void rclose(void)
{
    if (fh)
        FClose(fh);
    fh = 0;
}

static int rbyte(void);
#define RB() (rpos < rlen ? rbuf[rpos++] : (unsigned char)rbyte())

static int rbyte(void)
{
    if (rpos >= rlen) {
        rat += rlen;
        rpos = 0;
        rlen = FRead(fh, rbuf, sizeof rbuf);
        if (!rlen)
            return -1;
    }
    return rbuf[rpos++];
}

static unsigned int rread(unsigned char *d, unsigned int n)
{
    unsigned int i;
    int c;
    for (i = 0; i < n && (c = rbyte()) >= 0; ++i)
        d[i] = c;
    return i;
}

static void rseek(unsigned long o)
{
    if (o >= rat && o <= rat + rlen) {  /* in the buffer */
        rpos = o - rat;
        return;
    }
    FSeek(fh, (unsigned int)o, (unsigned int)(o >> 16));
    rat = o;
    rpos = rlen = 0;
}

static unsigned long u32(const unsigned char *p)
{
    return p[0] | (unsigned int)p[1] << 8 | (unsigned long)p[2] << 16 | (unsigned long)p[3] << 24;
}

/* GEOS header byte k of a CVT file (fileHeader's offsets) */
#define INFO(k) (head[28 + (k)])

/*---------------------------------------------------------------
  text
 ---------------------------------------------------------------*/
static unsigned long tlen, ltab;        /* the text's length; the line table */
static unsigned int nlines, maxlines, top;
static unsigned long mat;               /* the match shown */
static unsigned char mlen;
static char pat[32];

static unsigned char tb(unsigned long i)
{
    unsigned char b = *pp(i);
    return b;
}

static void setline(unsigned int k, unsigned long s)
{
    unsigned char *p = pp(ltab + 3 * (unsigned long)k);
    unsigned int o = (unsigned int)(ltab + 3 * (unsigned long)k) & 0x1FFF;
    if (o <= 0x1FFD) {
        p[0] = s;
        p[1] = s >> 8;
        p[2] = s >> 16;
    } else {
        unsigned char b[3];
        b[0] = s;
        b[1] = s >> 8;
        b[2] = s >> 16;
        pput(ltab + 3 * (unsigned long)k, b, 3);
    }
}

static unsigned long getline_(unsigned int k)
{
    unsigned char b[3];
    if (k >= nlines)
        return tlen;
    pget(ltab + 3 * (unsigned long)k, b, 3);
    return b[0] | (unsigned int)b[1] << 8 | (unsigned long)b[2] << 16;
}

static void addline(unsigned long s)
{
    if (nlines < maxlines)
        setline(nlines++, s);
}

/* the columns of the bytes s..e-1 from column 0 */
static unsigned char cols(unsigned long s, unsigned long e)
{
    unsigned char c = 0;
    while (s < e)
        c += tb(s++) == 9 ? 8 - (c & 7) : 1;
    return c;
}

/* a cursor over the text: the byte at ci with its bank mapped (cleft = 0
   after anything else maps a bank) */
static unsigned long ci;
static unsigned char *cptr;
static unsigned int cleft;

static unsigned char cget(void)
{
    if (!cleft) {
        cptr = pp(ci);
        cleft = 0x2000 - ((unsigned int)ci & 0x1FFF);
    }
    return *cptr;
}

static void cnext(void)
{
    ++ci;
    ++cptr;
    --cleft;
}

/* the line table: where each line on the screen starts (tests/check_view.py
   wrap() is the same) */
static void wrap(void)
{
    unsigned long s = 0, brk = 0;
    unsigned char col = 0, c, w;
    nlines = 0;
    addline(0);
    ci = 0;
    cleft = 0;
    while (ci < tlen) {
        c = cget();
        if (c == 13 || c == 10) {
            cnext();
            if (c == 13 && ci < tlen && cget() == 10)
                cnext();
            s = ci;
            col = 0;
            brk = 0;
            if (s < tlen) {
                addline(s);
                cleft = 0;
            }
            continue;
        }
        w = c == 9 ? 8 - (col & 7) : 1;
        if (col + w > TCOLS) {
            if (c == ' ') {             /* the space at the end goes */
                cnext();
                s = ci;
                col = 0;
                if (s < tlen)
                    addline(s);
            } else if (brk > s) {       /* after the last space */
                s = brk;
                col = cols(s, ci);
                addline(s);
            } else {
                s = ci;
                col = 0;
                addline(s);
            }
            cleft = 0;
            brk = 0;
            continue;
        }
        col += w;
        cnext();
        if (c == ' ')
            brk = ci;
    }
    RAMBANK = appBank;
}

static unsigned int maxtop(void)
{
    return nlines > ROWS ? nlines - ROWS : 0;
}

static void draw_line(unsigned char r)
{
    unsigned int k = top + r;
    unsigned long s, e;
    unsigned char col = 0, c, n, h0 = 0xFF, h1 = 0;
    if (k < nlines) {
        s = getline_(k);
        e = getline_(k + 1);
        while (s < e && col < TCOLS) {
            c = tb(s);
            if (c == 13 || c == 10)
                break;
            n = c == 9 ? 8 - (col & 7) : 1;
            if (mlen && s >= mat && s < mat + mlen) {
                if (h0 == 0xFF)
                    h0 = col;
                h1 = col + n;
            }
            while (n-- && col < TCOLS)
                row[col++] = c == 9 ? ' ' : glyph(c);
            ++s;
        }
        RAMBANK = appBank;
    }
    memset(row + col, ' ', TCOLS - col);
    PutCards(row, font, 0, TCOLS, AREAY + 8 * r, 0);
    if (h0 != 0xFF) {
        if (h1 > TCOLS)
            h1 = TCOLS;
        PutCards(row + h0, font, h0, h1 - h0, AREAY + 8 * r, 1);
    }
}

#pragma code-name (push, "OVERLAY1")
static void text_status(void)
{
    strcpy(line, docname);
    strcat(line, "  ");
    num(nlines);
    strcat(line, " lines  line ");
    num(top + 1);
    status(line);
}
#pragma code-name (pop)

/* (V148) the text's scroll bar: cards 78-79, rows 4-57 */
static struct vrscroll sbar = { 78, 4, 54, 1 };

static void draw_text(void)
{
    unsigned char r;
    for (r = 0; r < ROWS; ++r)
        draw_line(r);
    sbar.first = top;
    sbar.shown = ROWS;
    sbar.total = nlines;
    vr_scroll(&sbar);
    ColorRect(78, 2, 6, 50, 0);         /* (its track's cards: the paper, the palette being the pictures') */
    text_status();
}

#pragma code-name (push, "OVERLAY1")
static void text_go(long t)
{
    if (t < 0)
        t = 0;
    if (t > (long)maxtop())
        t = maxtop();
    top = t;
    draw_text();
}
#pragma code-name (pop)

/* the next match of pat after the one shown (or from the top line),
   round to the start once */
static unsigned char find_next(void)
{
    unsigned char n = strlen(pat), i, pass, f;
    unsigned long from, to;
    unsigned int lo, hi, mid;
    if (!n || tlen < n)
        return 0;
    f = lower(pat[0]);
    from = mlen ? mat + 1 : getline_(top);
    for (pass = 0; pass < 2; ++pass) {
        to = pass ? from : tlen - n + 1;
        ci = pass ? 0 : from;
        cleft = 0;
        for (; ci < to && ci + n <= tlen; cnext()) {
            if (lower(cget()) != f)
                continue;
            for (i = 1; i < n && lower(tb(ci + i)) == lower(pat[i]); ++i)
                ;
            cleft = 0;
            if (i == n) {
                RAMBANK = appBank;
                mat = ci;
                mlen = n;
                lo = 0;                 /* the line holding it */
                hi = nlines - 1;
                while (lo < hi) {
                    mid = (lo + hi + 1) >> 1;
                    if (getline_(mid) <= mat)
                        lo = mid;
                    else
                        hi = mid - 1;
                }
                if (lo < top || lo >= top + ROWS)
                    top = lo > maxtop() ? maxtop() : lo;
                return 1;
            }
        }
    }
    RAMBANK = appBank;
    return 0;
}

#pragma code-name (push, "OVERLAY1")
static void do_find(void)
{
    if (find_next()) {
        draw_text();
        strcpy(line, docname);
        strcat(line, "  \"");
        strcat(line, pat);
        strcat(line, "\" at line ");
        num(top + 1);
        status(line);
    } else {
        Beep();
        strcpy(line, "\"");
        strcat(line, pat);
        strcat(line, "\" is not there.");
        status(line);
    }
}
#pragma code-name (pop)

static unsigned char load_text(void)
{
    unsigned int n;
    unsigned char b, last = 0;
    unsigned long cap = poolSize / 4 * 3;
    FSeek(fh, 0, 0);
    rpos = rlen = 0;
    rat = 0;
    tlen = 0;
    for (b = 0; (unsigned long)b * 8192 < cap; ++b) {
        RAMBANK = bPool + b;
        n = FRead(fh, BANKMEM, 8192);
        RAMBANK = appBank;
        tlen += n;
        if (n < 8192) {
            last = 1;
            break;
        }
    }
    ltab = (tlen + 0x1FFF) & ~0x1FFFUL;
    maxlines = (poolSize - ltab) / 3 > 60000U ? 60000U : (poolSize - ltab) / 3;
    mlen = 0;
    top = 0;
    wrap();
    kind = K_TEXT;
    ColorRect(0, 0, 0, 0, 0xFF);
    SetColors(0xFFFF, 0x000);
    draw_text();
    if (!last) {
        strcpy(line, "Only the first ");
        num(tlen >> 10);
        strcat(line, " KB are shown.");
        status(line);
    }
    return 0;
}

/*---------------------------------------------------------------
  pictures: a 1 bpp bitmap in the pool (iw x ih, stride bytes a row,
  bits past iw 0) and a paper colour per card after it
 ---------------------------------------------------------------*/
static unsigned char psrc, stride, cw, hascol, inkcell, fit, deep;
static unsigned int iw, ih, ch, px, py;
static unsigned long mapoff, taboff;
static unsigned int inkrgb;
static unsigned char page, pages;
#define MAXREC  96              /* records read (Paint has 32; an album: its first 96 pages) */
static unsigned int recblk[MAXREC];     /* a record's first block after the table */
static unsigned int reclen[MAXREC];
#define RECOFF(i) (762 + 254UL * recblk[i])

static unsigned char pic_alloc(unsigned int w, unsigned int h)
{
    if (!w || !h || w > MAXW)
        return 0;
    iw = w;
    ih = h;
    stride = (w + 7) >> 3;
    cw = stride;
    ch = (h + 7) >> 3;
    mapoff = ((unsigned long)stride * h + 0x1FFF) & ~0x1FFFUL;
    taboff = (mapoff + (unsigned long)cw * ch + 0x1FFF) & ~0x1FFFUL;
    if (taboff + 0x2000 > poolSize)     /* (a bank for fast.s's tables) */
        return 0;
    hascol = 0;
    inkcell = 1;
    inkrgb = 0x000;
    return 1;
}

static void pic_clear(void)
{
    unsigned long o, end = mapoff + (unsigned long)cw * ch;
    for (o = 0; o < end; o += 0x2000) {
        memset(pp(o), 0, 0x2000);
    }
    RAMBANK = appBank;
}

static void put_row(unsigned int y, const unsigned char *r)
{
    pput((unsigned long)y * stride, r, stride);
}

static void set_card(unsigned char cx, unsigned int cy, unsigned char c)
{
    if (cx < cw && cy < ch) {
        *pp(mapoff + (unsigned long)cy * cw + cx) = c;
        RAMBANK = appBank;
        if (c)
            hascol = 1;
    }
}

/* the view: dw x dh pixels shown; src x = x * iw / dw (fit) or x + px */
static unsigned int dw, dh;

#pragma code-name (push, "OVERLAY1")
static void geometry(void)
{
    unsigned int z;
    if (!fit) {
        dw = iw - px < AREAW ? iw - px : AREAW;
        dh = ih - py < AREAH ? ih - py : AREAH;
        return;
    }
    if (iw <= AREAW && ih <= AREAH) {
        z = AREAW / iw;
        if (AREAH / ih < z)
            z = AREAH / ih;
        dw = iw * z;
        dh = ih * z;
    } else if ((unsigned long)iw * AREAH > (unsigned long)ih * AREAW) {
        dw = AREAW;
        dh = (unsigned long)ih * AREAW / iw;
    } else {
        dh = AREAH;
        dw = (unsigned long)iw * AREAH / ih;
    }
    if (!dw)
        dw = 1;
    if (!dh)
        dh = 1;
}
#pragma code-name (pop)

#pragma code-name (push, "OVERLAY1")
static void pic_status(void)
{
    static const char *const pname[] = { "BMP", "Paint", "Photo Scrap", "album" };
    strcpy(line, docname);
    strcat(line, "  ");
    strcat(line, pname[psrc]);
    if (psrc == P_BMP) {
        strcat(line, " ");
        num(deep);
        strcat(line, " bpp");
    }
    if (psrc == P_ALBUM) {
        strcat(line, " ");
        num(page + 1);
        strcat(line, "/");
        num(pages);
    }
    strcat(line, "  ");
    num(iw);
    strcat(line, " x ");
    num(ih);
    if (fit)
        strcat(line, "  fit");
    else {
        strcat(line, "  1:1 at ");
        num(px);
        strcat(line, ",");
        num(py);
    }
    status(line);
}
#pragma code-name (pop)

static void draw_pic(void)
{
    static unsigned int csx[COLS], csy[AREAH / 8];      /* each card's source pixel */
    unsigned int x, y, sy, last = 0xFFFF, acc, ax, sb;
    unsigned char cx, cy, k, n, *tb_;
    geometry();
    dispBufferOn = ST_WR_FORE | ST_WR_BACK;
    /* the cards' source columns: x * iw / dw (fit) or x + px */
    tb_ = pp(taboff);                   /* fast.s's tables: a pixel's source byte, its mask */
    sc_bank = RAMBANK;
    for (x = ax = sb = 0; x < AREAW; ++x) {
        if (!(x & 7))
            csx[x >> 3] = fit ? sb : x + px;
        tb_[x] = sb >> 3;
        tb_[x + 0x280] = 0x80 >> (sb & 7);
        ax += iw;
        while (ax >= dw) {
            ax -= dw;
            ++sb;
        }
    }
    acc = 0;
    sy = fit ? 0 : py;
    for (y = 0; y < AREAH; ++y) {
        if (!(y & 7))
            csy[y >> 3] = sy;
        RAMBANK = appBank;
        if (y >= dh) {
            if (last != 0xFFFE) {
                memset(work, 0, COLS);
                last = 0xFFFE;
            }
        } else if (sy != last) {
            last = sy;
            pget((unsigned long)sy * stride, row, stride);
            memset(work, 0, COLS);
            if (!fit) {
                n = stride - (px >> 3);
                memcpy(work, row + (px >> 3), n > COLS ? COLS : n);
            } else {
                sc_src = row;           /* the source bit x * iw / dw */
                sc_dst = work;
                sc_dw = dw;
                sc_row();
            }
        }
        WriteRow(work, 0, COLS, AREAY + y);
        if (fit) {                      /* the next source row */
            acc += ih;
            while (acc >= dh) {
                acc -= dh;
                ++sy;
            }
        } else
            ++sy;
    }
    /* the colours: a card's from the source pixel at its top left */
    if (!hascol) {
        ColorRect(0, 0, 0, 0, 0xFF);
    } else {
        for (cy = 0; cy < AREAH / 8; ++cy) {
            memset(work, 0, COLS);
            if (cy * 8 < dh) {
                pget(mapoff + (unsigned long)(csy[cy] >> 3) * cw, row, cw);
                for (cx = 0; cx < COLS && cx * 8 < dw; ++cx)
                    work[cx] = row[csx[cx] >> 3];
            }
            for (cx = 0; cx < COLS; cx += k) {   /* runs */
                for (k = 1; cx + k < COLS && work[cx + k] == work[cx]; ++k)
                    ;
                ColorRect(cx, k, cy + AREAY / 8, 1, work[cx]);
            }
        }
    }
    SetColors(0xFFFF, inkrgb);
    pic_status();
}

/* (V148: show_pic
   and the GEOS pictures' loaders, which map no bank themselves, moved to
   overlay 1 for room in main RAM) */
#pragma code-name ("OVERLAY1")
static void show_pic(void)
{
    kind = K_PIC;
    px = py = 0;
    fit = iw > AREAW || ih > AREAH;
    draw_pic();
}

#pragma code-name ("CODE")

/* the nearest of VERA's entries 2-15 to an RGB colour (8 bits each) */
static unsigned char nearest(unsigned char r, unsigned char g, unsigned char b)
{
    unsigned char i, best = 2;
    unsigned int d, bd = 0xFFFF;
    int dr, dg, db;
    for (i = 2; i < 16; ++i) {
        dr = (r >> 4) - (vpal[i] >> 8);
        dg = (g >> 4) - (vpal[i] >> 4 & 15);
        db = (b >> 4) - (vpal[i] & 15);
        d = dr * dr + dg * dg + db * db;
        if (d < bd) {
            bd = d;
            best = i;
        }
    }
    return best;
}

static unsigned int rgb12(const unsigned char *bgr)
{
    return (bgr[2] >> 4) << 8 | (bgr[1] >> 4) << 4 | bgr[0] >> 4;
}

static unsigned char lum(const unsigned char *bgr)
{
    return (bgr[2] * 77U + bgr[1] * 150U + bgr[0] * 29U) >> 8;
}

static unsigned char inkof(unsigned int rgb)
{
    unsigned char i;
    for (i = 1; i < 16; ++i)
        if (vpal[i] == rgb)
            return i;
    return 1;
}

/* the papers of card row cr from the counts in work (16 a card): the most
   common value, the lower one on a tie */
static void flush_hist(unsigned int cr)
{
    unsigned char cx, i, best, bn, *h;
    for (cx = 0; cx < cw; ++cx) {
        h = work + cx * 16;
        best = 0;
        bn = 0;
        for (i = 0; i < 16; ++i)
            if (h[i] > bn) {
                bn = h[i];
                best = i;
            }
        line[cx] = best;
        if (best)
            hascol = 1;
    }
    pput(mapoff + (unsigned long)cr * cw, (unsigned char *)line, cw);
    memset(work, 0, (unsigned int)cw * 16);
}

/* a BMP (BITMAPINFOHEADER or later, BI_RGB); tests/check_view.py bmp() */
static unsigned char load_bmp(void)
{
    static unsigned char pal[16][4], hd[54], ink[256 / 8], px3[3];
#define cmap cv_cmap
    unsigned long off, fstride;
    long hh;
    unsigned int w, h, k, ow, oh, x, y, fy, cr, sx;
    unsigned char bpp, inkbit, v, i, *o, om, *hp, im, cv = 0;
    unsigned int npal, kc;
    rseek(0);
    if (rread(hd, 54) != 54 || hd[0] != 'B' || hd[1] != 'M' || u32(hd + 14) < 40)
        return 1;
    off = u32(hd + 10);
    w = u32(hd + 18);
    hh = (long)u32(hd + 22);
    bpp = hd[28];
    if (u32(hd + 30) != 0 || (bpp != 1 && bpp != 4 && bpp != 8 && bpp != 24) || !w || !hh || u32(hd + 18) > 32767)
        return 2;
    h = hh < 0 ? -hh : hh;
    npal = u32(hd + 46);
    if (!npal || npal > 256)
        npal = bpp <= 8 ? 1 << bpp : 0;
    /* the palette: entries 0-15 kept; 8 bpp: which are dark */
    memset(ink, 0, sizeof ink);
    memset(pal, 0, sizeof pal);
    rseek(14 + u32(hd + 14));
    for (k = 0; k < npal; ++k) {
        rread(row, 4);
        if (k < 16)
            memcpy(pal[k], row, 4);
        if (lum(row) < 128)
            ink[k >> 3] |= 1 << (k & 7);
    }
    /* the size kept: pre-scaled by k so that it fits */
    for (k = 1;; ++k) {
        ow = (w + k - 1) / k;
        oh = (h + k - 1) / k;
        if (ow <= MAXW && pic_alloc(ow, oh))
            break;
        if (k > 64)
            return 3;
    }
    pic_clear();
    psrc = P_BMP;
    deep = bpp;
    inkbit = 1;
    if (bpp == 1) {
        inkbit = lum(pal[0]) < lum(pal[1]) ? 0 : 1;
        inkrgb = rgb12(pal[inkbit]);
    } else if (bpp == 4) {
        inkrgb = rgb12(pal[1]);
        cmap[0] = 0;
        cmap[1] = 1;
        for (i = 2; i < 16; ++i)
            cmap[i] = nearest(pal[i][2], pal[i][1], pal[i][0]);
    }
    inkcell = inkof(inkrgb);
    fstride = (((unsigned long)w * bpp + 31) >> 5) << 2;
    memset(work, 0, (unsigned int)cw * 16);
    cr = 0xFFFF;
    for (fy = 0; fy < h; ++fy) {
        y = hh > 0 ? h - 1 - fy : fy;
        if (y % k)
            continue;
        y /= k;
        if (bpp == 4 && (y >> 3) != cr) {
            if (cr != 0xFFFF)
                flush_hist(cr);
            cr = y >> 3;
        }
        rseek(off + fy * fstride);
        memset(row, 0, stride);
        if (bpp == 1 && k == 1) {               /* the bytes as they are */
            rread(row, stride);
            if (!inkbit)
                for (x = 0; x < stride; ++x)
                    row[x] = ~row[x];
            if (w & 7)
                row[stride - 1] &= 0xFF << (8 - (w & 7));
        } else if (bpp == 4 && k == 1) {       /* fast.s, as the buffer holds them */
            cv_out = row;
            cv_om = 0x80;
            cv_hist = work;
            for (x = w >> 1; x; x -= kc) {
                if (rpos >= rlen) {
                    if (rbyte() < 0)
                        break;
                    --rpos;
                }
                kc = rlen - rpos;
                if (kc > x)
                    kc = x;
                if (kc > 255)
                    kc = 255;
                cv_src = rbuf + rpos;
                cv_n = kc;
                cv4();
                rpos += kc;
            }
            if (w & 1) {
                v = RB() >> 4;
                if (v == 1)
                    *cv_out |= cv_om;
                else
                    ++cv_hist[cv_cmap[v]];
            }
        } else {
            o = row;
            om = 0x80;
            hp = work;
            im = 0;
            kc = 0;
            for (sx = 0; sx < w; ++sx) {
                if (bpp == 1) {
                    if (!im) {
                        cv = RB();
                        im = 0x80;
                    }
                    v = !(cv & im) == !inkbit;
                    im >>= 1;
                } else if (bpp == 4) {
                    if (sx & 1)
                        v = cv & 15;
                    else {
                        cv = RB();
                        v = cv >> 4;
                    }
                } else if (bpp == 8) {
                    cv = RB();
                    v = (ink[cv >> 3] >> (cv & 7)) & 1;
                } else {
                    px3[0] = RB();
                    px3[1] = RB();
                    px3[2] = RB();
                    v = lum(px3) < 128;
                }
                if (!kc) {                      /* every k-th pixel kept */
                    if (bpp == 4 && v != 1)     /* (4 bpp: v the entry; else 1 = ink) */
                        ++hp[cmap[v]];
                    else if (v)
                        *o |= om;
                    if (!(om >>= 1)) {
                        om = 0x80;
                        ++o;
                        hp += 16;
                    }
                }
                if (++kc == k)
                    kc = 0;
            }
        }
        put_row(y, row);
    }
    if (bpp == 4 && cr != 0xFFFF)
        flush_hist(cr);
    return 0;
}

/* PackBits (Paint's bands) from the file into work, n bytes */
#pragma code-name ("OVERLAY1")
static unsigned char unpackbits(unsigned int n)
{
    unsigned int o = 0;
    int c;
    unsigned char k;
    while (o < n) {
        c = RB();
        if (c < 128) {
            if (o + c + 1 > n)
                return 0;
            for (k = c + 1; k; --k)
                work[o++] = RB();
        } else if (c > 128) {
            if (o + 257 - c > n)
                return 0;
            memset(work + o, RB(), 257 - c);
            o += 257 - c;
        }
    }
    return 1;
}

/* a VLIR CVT's records: offsets and lengths (0xFFFF: empty) */
static unsigned char nrecs;

static void records(void)
{
    static unsigned char t[254];
    unsigned int at = 0;
    unsigned char i;
    rseek(508);
    rread(t, 254);
    nrecs = 0;
    for (i = 0; i < MAXREC; ++i) {
        if (!t[2 * i] && !t[2 * i + 1])
            break;
        if (!t[2 * i]) {
            recblk[i] = 0;
            reclen[i] = 0xFFFF;
        } else {
            recblk[i] = at;
            reclen[i] = (t[2 * i] - 1) * 254 + t[2 * i + 1] - 1;
            at += t[2 * i];
        }
        ++nrecs;
    }
}

static unsigned char load_paint(void)
{
    unsigned char b, r, ver, cx, v;
    records();
    if (nrecs < 30 || reclen[0] < 8 || reclen[0] > 9)
        return 1;
    rseek(RECOFF(0));
    rread(row, reclen[0]);
    ver = row[4];
    if (memcmp(row, "VPNT", 4) || row[5] != 74 || row[6] != 16 || row[7] != 29 || ver < 1 || ver > 3)
        return 1;
    if (!pic_alloc(592, 464))
        return 3;
    pic_clear();
    psrc = P_PAINT;
    inkcell = ver == 3 && row[8] >= 2 && row[8] < 16 ? row[8] : 1;
    inkrgb = vpal[inkcell];
    for (b = 0; b < 29; ++b) {
        if (reclen[b + 1] == 0xFFFF)
            continue;
        rseek(RECOFF(b + 1));
        if (!unpackbits(74 * 16))
            return 4;
        for (r = 0; r < 16; ++r)
            put_row(b * 16 + r, work + r * 74);
    }
    for (b = 0; ver >= 2 && b < 2 && nrecs > 31; ++b) {
        if (reclen[30 + b] != 1073)
            continue;
        rseek(RECOFF(30 + b));
        rread(work, 1073);
        for (r = 0; r < 29; ++r) {
            for (cx = 0; cx < 74; ++cx) {
                v = work[r * 37 + (cx >> 1)];
                if ((row[cx] = cx & 1 ? v & 15 : v >> 4) != 0)
                    hascol = 1;
            }
            pput(mapoff + (unsigned long)(b * 29 + r) * cw, row, 74);
        }
    }
    return 0;
}

/* GEOS's compacted bitmap (BitmapUp's) from the file, dleft bytes of it */
static unsigned long dleft;
static unsigned char cnt, lit, val, inpat, prep, plen, ppos, bad;
static unsigned char patb[40];

static int gb(void)
{
    int c;
    if (!dleft || (c = rbyte()) < 0) {
        bad = 1;
        return 0;
    }
    --dleft;
    return c;
}

static unsigned char fromPat(void)
{
    return ppos < plen ? patb[ppos++] : 0;
}

static unsigned char bm_next(void)
{
    unsigned char c, i;
    for (;;) {
        if (bad)
            return 0;
        if (cnt) {
            --cnt;
            if (lit)
                return inpat ? fromPat() : gb();
            return val;
        }
        if (inpat) {
            if (ppos >= plen) {
                if (--prep) {
                    ppos = 0;
                } else {
                    inpat = 0;
                    continue;
                }
            }
            c = patb[ppos++];
            if (c < 0x80) {
                cnt = c;
                lit = 0;
                val = fromPat();
            } else {
                cnt = c - 0x80;
                lit = 1;
            }
            continue;
        }
        c = gb();
        if (bad)
            return 0;
        if (c >= 0xDC) {
            plen = c - 0xDC;
            prep = gb();
            for (i = 0; i < plen; ++i)
                patb[i] = gb();
            if (prep && plen) {
                inpat = 1;
                ppos = 0;
            }
            continue;
        }
        if (c < 0x80) {
            cnt = c;
            lit = 0;
            val = gb();
        } else {
            cnt = c - 0x80;
            lit = 1;
        }
    }
}

/* a Photo Scrap's data at the file's position, n bytes */
static unsigned char load_scrap(unsigned long n)
{
    unsigned char w, x, cx;
    unsigned int h, y, cy;
    dleft = n;
    bad = cnt = inpat = 0;
    w = gb();
    h = gb();
    h |= gb() << 8;
    if (bad || !w || w > 80 || !h)
        return 1;
    if (!pic_alloc(w * 8, h))
        return 3;
    pic_clear();
    for (y = 0; y < h; ++y) {
        for (x = 0; x < w; ++x)
            row[x] = bm_next();
        if (bad)
            return 4;
        put_row(y, row);
    }
    if (dleft && !inpat && !cnt)        /* the colours, if any */
        for (cy = 0; cy < ch && !bad; ++cy)
            for (cx = 0; cx < w; ++cx) {
                x = bm_next();
                if (bad)
                    break;
                set_card(cx, cy, x & 15);
            }
    bad = 0;
    return 0;
}

static unsigned char load_page(void)
{
    unsigned char i, k = 0;
    for (i = 0; i < nrecs; ++i)
        if (reclen[i] != 0xFFFF && k++ == page)
            break;
    rseek(RECOFF(i));
    if (load_scrap(reclen[i]))
        return 1;
    psrc = P_ALBUM;
    return 0;
}

/*---------------------------------------------------------------
  the info block (GEOS's info box, as a page)
 ---------------------------------------------------------------*/
static const char *const tname[] = {
    "not GEOS", "BASIC", "assembly", "data", "system", "desk accessory", "application",
    "document", "font", "printer driver", "input driver", "disk driver", "boot",
    "temporary", "auto-exec", "input 128"
};

/* the info page: overlay 1 (it maps no bank) */
#pragma code-name ("OVERLAY1")

/* (V148, Look 3 "Sunroom") the info page in the UI font: the icon, the
   name bold and the kind beside it, a line, the labels in a column and
   their values, the description wrapped at spaces (tests/check_view.py's
   info_screen draws the same) */
#define IX      16              /* the labels */
#define VX      120             /* the values */
#define IR      624             /* the right margin */

/* s's first n bytes (to a 0 or a $A0), outside $20-$7E as '?', at x, baseline y */
static void ut(const unsigned char *s, unsigned char n, unsigned int x, unsigned int y)
{
    unsigned char l = 0, c;
    while (l < n && (c = s[l]) != 0 && c != 0xA0) {
        line[l++] = c < 32 || c > 126 ? '?' : c;
    }
    line[l] = 0;
    WPutString(line, x, y);
}

static unsigned int iy;                 /* the next row's baseline */

static void row_(const char *label, const unsigned char *s, unsigned char n)
{
    ut((const unsigned char *)label, 20, IX, iy);
    ut(s, n, VX, iy);
    iy += 14;
}

static char ival[48];

static void two(unsigned char v)
{
    unsigned char l = strlen(ival);
    ival[l] = '0' + v / 10 % 10;
    ival[l + 1] = '0' + v % 10;
    ival[l + 2] = 0;
}

static void show_info(void)
{
    static unsigned char ico[64];
    unsigned char t = INFO(69), i, l, b;
    unsigned int w;
    kind = K_INFO;
    ColorRect(0, 0, 0, 0, 0xFF);
    SetColors(0xFFFF, 0x000);
    SetPattern(0);
    WRectangle(0, AREAY, 639, AREAY + AREAH - 1);
    UseFont(FONT_UI);
    memcpy(ico, &INFO(4), 64);
    ico[0] = 0xBF;
    WBitmapUp(ico, 2, 3, 44, 21);
    currentMode = SET_BOLD;
    ut(head + 3, 16, 56, 54);
    currentMode = 0;
    strcpy(ival, t < 16 ? tname[t] : "other");
    strcat(ival, head[21] == 1 ? ", VLIR" : ", sequential");
    ut((unsigned char *)ival, 48, 56, 68);
    WHorizontalLine(0xFF, IX, IR - 1, 78);
    iy = 98;
    row_("Class", &INFO(77), 20);
    row_("Author", &INFO(97), 20);
    row_("Application", &INFO(117), 20);
    ival[0] = 0;
    utoa(1900 + head[23], ival, 10);
    strcat(ival, "-");
    two(head[24]);
    strcat(ival, "-");
    two(head[25]);
    strcat(ival, "  ");
    two(head[26]);
    strcat(ival, ":");
    two(head[27]);
    row_("Date", (unsigned char *)ival, 48);
    utoa(head[28] | head[29] << 8, ival, 10);
    strcat(ival, " blocks");
    row_("Size", (unsigned char *)ival, 48);
    row_("File", (unsigned char *)docname, 47);
    if (!memcmp(&INFO(137), "VRND", 4)) {
        strcpy(ival, "API ");
        utoa(INFO(141), ival + 4, 10);
        l = strlen(ival);
        t = 0;
        for (i = 0; i < 16; i += 4) {
            if (!INFO(144 + i))
                continue;
            strcpy(ival + l, t++ ? " " : ", opens ");
            l = strlen(ival);
            memcpy(ival + l, &INFO(144 + i), 4);
            l += 4;
            while (ival[l - 1] == ' ')
                --l;
            ival[l] = 0;
        }
        row_("Veranda", (unsigned char *)ival, 48);
    }
    /* the description (96 bytes at most): lines to the right margin,
       broken after the last space that fits */
    ut((const unsigned char *)"Description", 20, IX, iy);
    for (i = 0; i < 96 && INFO(160 + i);) {
        w = 0;
        b = 0;
        for (l = 0; i + l < 96 && INFO(160 + i + l); ++l) {
            if ((w += GetCharWidth(INFO(160 + i + l))) > IR - VX)
                break;
            if (INFO(160 + i + l) == ' ')
                b = l + 1;
        }
        if (i + l < 96 && INFO(160 + i + l) && b)
            l = b;
        ut(&INFO(160 + i), l, VX, iy);
        i += l;
        iy += 14;
    }
    UseSystemFont();
    strcpy(line, docname);
    strcat(line, "  info");
    status(line);
}

#pragma code-name ("CODE")

/*---------------------------------------------------------------
  opening a file
 ---------------------------------------------------------------*/
static void blank(void)
{
    dispBufferOn = ST_WR_FORE | ST_WR_BACK;
    ColorRect(0, 0, 0, 0, 0xFF);
    SetPattern(0);
    WRectangle(0, AREAY, 639, AREAY + AREAH - 1);
}


/* (title, say_err, open_doc in overlay 1: called with appBank mapped
   only; the loaders they call map it back, V82: room for the dialog) */
#pragma code-name (push, "OVERLAY1")
static void title(void)
{
    vr_win_title(&win, docname[0] ? docname : "View");
}

static void say_err(const char *what)
{
    Beep();
    strcpy(line, docname);
    strcat(line, ": ");
    strcat(line, what);
    status(line);
}

static void open_doc(const char *name, unsigned char text)
{
    unsigned char e = 0;
    rclose();
    if (name != docname)
        strcpy(docname, name);
    title();
    asText = text;
    kind = K_NONE;
    page = pages = 0;
    if (!ropen(name)) {
        blank();
        say_err("cannot be opened.");
        return;
    }
    headn = rread(head, 30);
    isCvt = headn == 30 && rread(row, 128) == 128 && !memcmp(row + 3, " formatted GEOS file", 20)
            && rread(row, 96) == 96 && rread(head + 30, 254) == 254;
    if (text) {
        load_text();
        return;
    }
    if (headn >= 2 && head[0] == 'B' && head[1] == 'M') {
        blank();
        status("Reading the picture ...");
        if ((e = load_bmp()) == 0) {
            show_pic();
            return;
        }
        say_err(e == 2 ? "this kind of BMP is not shown." : e == 3 ? "the picture is too large." :
                "the picture cannot be read.");
        return;
    }
    if (!isCvt) {
        load_text();
        return;
    }
    if (head[21] == 1 && ciprefix(&INFO(77), "paint image")) {
        blank();
        status("Reading the picture ...");
        if ((e = load_paint()) == 0) {
            show_pic();
            return;
        }
    } else if (head[21] == 0 && ciprefix(&INFO(77), "photo scrap")) {
        blank();
        rseek(508);
        if ((e = load_scrap(0xFFFFFFUL)) == 0) {
            psrc = P_SCRAP;
            show_pic();
            return;
        }
    } else if (head[21] == 1 && ciprefix(&INFO(77), "photo album")) {
        unsigned char i;
        blank();
        records();
        for (i = 0; i < nrecs; ++i)
            if (reclen[i] != 0xFFFF)
                ++pages;
        if (pages && (e = load_page()) == 0) {
            show_pic();
            return;
        }
    }
    show_info();                        /* any other GEOS file, or a picture that failed */
    if (e)
        say_err("the picture cannot be read.");
}
#pragma code-name (pop)

#pragma code-name (push, "OVERLAY1")
static void album_go(int d)
{
    if (kind != K_PIC || psrc != P_ALBUM || (int)page + d < 0 || page + d >= pages)
        return;
    page += d;
    if (load_page())
        say_err("the page cannot be read.");
    else
        show_pic();
}
#pragma code-name (pop)

/*---------------------------------------------------------------
  the Open dialog (vrchoose.h, DECISIONS V79, V82): the SDK's, compiled
  into overlay 2; overlay 1 stays appBank (the dialog's routines map
  their own bank through vr_tramp)
 ---------------------------------------------------------------*/
static const char vtypes[] = "Viewable:BMP CVT TXT MD INI LOG";
static char pick[VRF_NAME + 1];

static unsigned char file_dlg(void)
{
    unsigned char r, b = RAMBANK;
    vr_file_types = vtypes;
    RAMBANK = bDlg;
    r = vr_file(VRF_OPEN, "Open", pick);
    RAMBANK = b;
    return r;
}

/* the dialog; a file chosen is shown (its folder current: curDirName) */
#pragma code-name (push, "OVERLAY1")
static void choose(void)
{
    if (file_dlg())
        open_doc(pick, 0);
    else if (kind == K_NONE)
        status("File > Open shows a file.");
}
#pragma code-name (pop)

/*---------------------------------------------------------------
  the clipboard
 ---------------------------------------------------------------*/
static void get_pic_row(unsigned int y, unsigned char *r)
{
    pget((unsigned long)y * stride, r, stride);
}

static unsigned char get_pic_col(unsigned char cx, unsigned char cy)
{
    return inkcell << 4 | pbyte(mapoff + (unsigned long)cy * cw + cx);
}

/* the lines shown as GEOS text (scrap.h): characters 32-126, TAB, CR (a
   CR LF, or a LF, as CR); counted, then written */
static const unsigned char cardset[4] = { SCRAP_NEWCARDSET, 9, 0, 0 };

static unsigned int text_out(unsigned char write)
{
    unsigned long s = getline_(top), t = getline_(top + ROWS);
    unsigned int n = 0;
    unsigned char c, prev = 0, k = 0;
    for (; s < t; ++s) {
        c = tb(s);
        if (c == 10 && prev == 13) {
            prev = 0;
            continue;
        }
        prev = c;
        if (c == 10)
            c = 13;
        if (!(c >= 32 && c < 127) && c != 9 && c != 13)
            continue;
        ++n;
        if (write) {
            row[k++] = c;
            if (k == sizeof row) {
                RAMBANK = appBank;
                scrap_write(row, k);
                k = 0;
            }
        }
    }
    RAMBANK = appBank;
    if (write && k)
        scrap_write(row, k);
    return n;
}

static unsigned char copy_text(void)
{
    unsigned char e = scrap_text_begin(text_out(0) + 4);
    if (!e)
        e = scrap_write(cardset, 4);
    if (!e)
        text_out(1);
    return scrap_close() | e;
}

static void copy(void)
{
    unsigned char e;
    if (kind == K_PIC) {
        status("Copying the picture ...");
        e = scrap_put_photo(stride, ih, get_pic_row, hascol || inkcell != 1 ? get_pic_col : 0);
        strcpy(line, e ? "The picture was not copied." : "The picture is on the clipboard.");
    } else if (kind == K_TEXT) {
        e = copy_text();
        strcpy(line, e ? "The text was not copied." : "The page's text is on the clipboard.");
    } else
        return;
    if (e)
        Beep();
    status(line);
}

/*---------------------------------------------------------------
  the menus and the input
 ---------------------------------------------------------------*/
struct box3 {                   /* text, an input through r5, OK, CANCEL */
    unsigned char pos;
    unsigned char t1, x1, y1; const char *s1;
    unsigned char t2, x2, y2, reg2, max2;
    unsigned char ok, okx, oky;
    unsigned char cn, cnx, cny;
    unsigned char end;
};
static const struct box3 findBox = {
    DEF_DB_POS | 1,
    DBTXTSTR, TXT_LN_X, TXT_LN_1_Y, "Find:",
    DBGETSTRING, TXT_LN_X, TXT_LN_2_Y, 0x0C, 24,
    OK, DBI_X_0, DBI_Y_2,
    CANCEL, DBI_X_2, DBI_Y_2,
    0
};

struct item { const char *text; unsigned char type; void *p; };
struct menu5 { unsigned char top, bottom; unsigned int left, right; unsigned char flags; struct item i[5]; };
struct menu6 { unsigned char top, bottom; unsigned int left, right; unsigned char flags; struct item i[6]; };
struct menu2 { unsigned char top, bottom; unsigned int left, right; unsigned char flags; struct item i[2]; };
struct menu3 { unsigned char top, bottom; unsigned int left, right; unsigned char flags; struct item i[3]; };
struct menu4 { unsigned char top, bottom; unsigned int left, right; unsigned char flags; struct item i[4]; };

static void m_open(void), m_text(void), m_info(void), m_quit(void), m_copy(void);
static void m_zoom(void), m_find(void), m_again(void), m_next(void), m_prev(void), m_about(void);

/* the menus in the Veranda look (DECISIONS V74, V79): the first is
   View's own. Look 3 "Sunroom" (V148): an item starting with $1F has a
   dotted line above it (a group starts), its key after a tab is drawn
   at the list's right; the lists' widths from the texts (menu_widths) */
static struct menu2 mview = { 15, 15 + 2 * 14, 0, 0, VERTICAL | 2, {
    { "About View", MENU_ACTION, m_about }, { "\x1f" "Quit", MENU_ACTION, m_quit } } };
static struct menu4 mfile = { 15, 15 + 4 * 14, 0, 0, VERTICAL | 4, {
    { "Open...\tEsc", MENU_ACTION, m_open }, { "Open as text", MENU_ACTION, m_text },
    { "\x1f" "Info", MENU_ACTION, m_info }, { "\x1f" "Copy", MENU_ACTION, m_copy } } };
static struct menu5 mshow = { 15, 15 + 5 * 14, 0, 0, VERTICAL | 5, {
    { "Zoom: fit / 1:1", MENU_ACTION, m_zoom }, { "\x1f" "Find...", MENU_ACTION, m_find },
    { "Find again", MENU_ACTION, m_again }, { "\x1f" "Next page\tPgDn", MENU_ACTION, m_next },
    { "Previous page\tPgUp", MENU_ACTION, m_prev } } };
static struct menu3 mbar = { 0, 14, 0, 160, HORIZONTAL | UN_CONSTRAINED | 3, {
    { "View", SUB_MENU, &mview }, { "File", SUB_MENU, &mfile }, { "Show", SUB_MENU, &mshow } } };

#pragma code-name (push, "OVERLAY1")
static void m_about(void)
{
    GotoFirstMenu();
    status("View 1.0: text, BMP, Paint, Photo Scraps and albums, file info. MIT licence");
}
#pragma code-name (pop)

#pragma code-name (push, "OVERLAY1")
static void m_open(void)
{
    GotoFirstMenu();
    choose();
}
#pragma code-name (pop)

#pragma code-name (push, "OVERLAY1")
static void m_text(void)
{
    GotoFirstMenu();
    if (docname[0])
        open_doc(docname, 1);
}
#pragma code-name (pop)

#pragma code-name (push, "OVERLAY1")
static void m_info(void)
{
    GotoFirstMenu();
    if (!docname[0])
        return;
    if (!isCvt) {
        strcpy(line, docname);
        strcat(line, ": a plain file, no info block.");
        status(line);
        return;
    }
    open_doc(docname, 0);
    if (kind != K_INFO)
        show_info();
}
#pragma code-name (pop)

#pragma code-name (push, "OVERLAY1")
static void m_copy(void)
{
    GotoFirstMenu();
    copy();
}
#pragma code-name (pop)

#pragma code-name (push, "OVERLAY1")
static void m_quit(void)
{
    GotoFirstMenu();
    rclose();
    EnterDeskTop();
}
#pragma code-name (pop)

#pragma code-name (push, "OVERLAY1")
static void m_zoom(void)
{
    GotoFirstMenu();
    if (kind != K_PIC)
        return;
    fit = !fit;
    px = py = 0;
    draw_pic();
}
#pragma code-name (pop)

#pragma code-name (push, "OVERLAY1")
static void m_find(void)
{
    GotoFirstMenu();
    if (kind != K_TEXT)
        return;
    r5 = (unsigned int)pat;
    if (DoDlgBox((void *)&findBox) != OK || !pat[0])
        return;
    mlen = 0;
    do_find();
}
#pragma code-name (pop)

#pragma code-name (push, "OVERLAY1")
static void m_again(void)
{
    GotoFirstMenu();
    if (kind == K_TEXT && pat[0])
        do_find();
}
#pragma code-name (pop)

#pragma code-name (push, "OVERLAY1")
static void m_next(void)
{
    GotoFirstMenu();
    album_go(1);
}
#pragma code-name (pop)

#pragma code-name (push, "OVERLAY1")
static void m_prev(void)
{
    GotoFirstMenu();
    album_go(-1);
}
#pragma code-name (pop)

/* the picture panned (1:1) by whole cards */
#pragma code-name (push, "OVERLAY1")
static void pan(int dx, int dy)
{
    long x = (long)px + dx, y = (long)py + dy;
    long mx = iw > AREAW ? ((long)iw - AREAW + 7) & ~7L : 0, my = ih > AREAH ? ((long)ih - AREAH + 7) & ~7L : 0;
    if (fit)
        return;
    if (x > mx) x = mx;
    if (y > my) y = my;
    if (x < 0) x = 0;
    if (y < 0) y = 0;
    if ((unsigned int)x == px && (unsigned int)y == py)
        return;
    px = x;
    py = y;
    draw_pic();
}
#pragma code-name (pop)

/* (V148) a press on the text's scroll bar: its arrows a line, its track
   a page */
#pragma code-name (push, "OVERLAY1")
static void press(void)
{
    unsigned char h;
    if ((mouseData & 0x80) || kind != K_TEXT)
        return;
    h = vr_scroll_hit(&sbar, mouseXPos, mouseYPosW);
    if (h == VS_BACK) text_go((long)top - 1);
    else if (h == VS_FWD) text_go((long)top + 1);
    else if (h == VS_PGBACK) text_go((long)top - (ROWS - 1));
    else if (h == VS_PGFWD) text_go((long)top + ROWS - 1);
}
#pragma code-name (pop)

#pragma code-name (push, "OVERLAY1")
static void key(void)
{
    unsigned char k = keyData;
    if (kind == K_TEXT) {
        if (k == KEY_DOWN) text_go((long)top + 1);
        else if (k == KEY_UP) text_go((long)top - 1);
        else if (k == KEY_PGDN || k == ' ') text_go((long)top + ROWS - 1);
        else if (k == KEY_PGUP) text_go((long)top - (ROWS - 1));
        else if (k == KEY_HOME) text_go(0);
        else if (k == KEY_END) text_go(maxtop());
    } else if (kind == K_PIC) {
        if (k == KEY_DOWN) pan(0, 64);
        else if (k == KEY_UP) pan(0, -64);
        else if (k == KEY_RIGHT) pan(64, 0);
        else if (k == KEY_LEFT && (keyDataMods & KEYM_ARROW)) pan(-64, 0);
        else if (k == KEY_PGDN) { if (psrc == P_ALBUM) album_go(1); else pan(0, AREAH); }
        else if (k == KEY_PGUP) { if (psrc == P_ALBUM) album_go(-1); else pan(0, -AREAH); }
    }
    if (k == KEY_ESC)
        choose();
}
#pragma code-name (pop)

/* each list's width: its widest item (a key 24 pixels after its text) + 16 */
#pragma code-name (push, "CODE")
static void menu_widths(void)
{
    static struct item *const its[3] = { mview.i, mfile.i, mshow.i };
    static unsigned int *const rights[3] = { &mview.right, &mfile.right, &mshow.right };
    static const unsigned char ns[3] = { 2, 4, 5 };
    unsigned char i, j;
    unsigned int w, t, m;
    const char *s;
    UseFont(FONT_UI);
    for (i = 0; i < 3; ++i) {
        for (m = 0, j = 0; j < ns[i]; ++j) {
            s = its[i][j].text;
            w = t = 0;
            if (*s == 0x1F)
                ++s;
            for (; *s; ++s)
                if (*s == '\t') {
                    t = w + 24;
                    w = 0;
                } else
                    w += GetCharWidth(*s);
            if (t + w > m)
                m = t + w;
        }
        *rights[i] = m + 16;
    }
    UseSystemFont();
}

#pragma code-name (pop)
#pragma code-name (push, "OVERLAY1")
static void frame(void)
{
    dispBufferOn = ST_WR_FORE | ST_WR_BACK;
    SetPattern(0);
    WRectangle(0, 0, 639, 15);
    vr_win(&win, "View");               /* (theme_load) */
    menu_widths();
    theme_menus();                      /* the menu bar (V74; black and white: the pictures' palette) */
    DoMenu((void *)&mbar, 0);
}
#pragma code-name (pop)

int main(void)
{
    unsigned char opts = r0L, b, n, d;
    LoadOverlay(1, 0);                  /* (overlay 1: mapped for good, as appBank) */
    appBank = r1L;
    RAMBANK = appBank;
    load_font();
    frame();
    keyVector = VR_FN(key);
    otherPressVec = VR_FN(press);
    LoadOverlay(2, 0);                  /* (overlay 2: the Open dialog, mapped by file_dlg) */
    bDlg = r1L;
    RAMBANK = appBank;
    d = BankAlloc(1);                   /* (a bank kept for the dialog's list) */
    for (n = 48; n >= 8; n -= 8)        /* the pool: as many banks as there are, up to 48 */
        if ((b = BankAlloc(n)) != 0)
            break;
    if (d)
        BankFree(d);
    if (!b) {
        status("Not enough memory (RAM banks).");
        return 0;
    }
    bPool = b;
    nPool = n;
    poolSize = (unsigned long)nPool * 8192;
    if (curDirName[0] != '/') {
        strcpy((char *)curDirName, "/");
        ChDir("/");
    } else
        ChDir((char *)curDirName);
    LogText("VIEW RUNNING");
#ifdef VIEW_TEST
    if (!(opts & ST_LD_DATA)) {
        test_run();
        return 0;
    }
#endif
    if (opts & ST_LD_DATA) {            /* the shell's document */
        strcpy(docname, (char *)dataLongName);         /* (its whole name: V82) */
#ifdef VIEW_TEST
        strcpy(line, "VIEW DOC ");
        strcat(line, docname);
        strcat(line, " IN ");
        strcat(line, (char *)curDirName);
        LogText(line);
#endif
        open_doc(docname, 0);
#ifdef VIEW_TEST
        view_test_snap("DOC.RAW");
        view_test_end();
#endif
        return 0;
    }
    choose();
    return 0;
}

#ifdef VIEW_TEST
/*---------------------------------------------------------------
  the test build (tools/gate_view.sh; tests/view_scene.c made the BMPs
  with ExportRect and started it): each kind of file opened and its screen written to a file
  (tests/view_play.c), checked by tests/check_view.py
 ---------------------------------------------------------------*/
/* "VIEW STEP what": the step's cycles since the last one (the emulator's
   counter: a read of $9FB8 latches it) in TIME, a separate line */
#pragma code-name (push, "OVERLAY1")  /* (the test's room: overlay 1) */
static void step(const char *what, const char *snap)
{
    unsigned char c[4], i, n;
    c[0] = *(volatile unsigned char *)0x9FB8;
    c[1] = *(volatile unsigned char *)0x9FB9;
    c[2] = *(volatile unsigned char *)0x9FBA;
    c[3] = *(volatile unsigned char *)0x9FBB;
    strcpy(line, "VIEW STEP ");
    strcat(line, what);
    LogText(line);
    strcpy(line, "TIME ");
    for (i = 4, n = 5; i-- > 0;) {
        line[n++] = "0123456789ABCDEF"[c[i] >> 4];
        line[n++] = "0123456789ABCDEF"[c[i] & 15];
    }
    line[n] = 0;
    LogText(line);
    view_test_snap(snap);
    *(volatile unsigned char *)0x9FB8 = 0;
}

/* (V148) VIEW_STOP=n: the run ends after screen n (1 text, 2 picture,
   3 info) with a VRAM dump: the screenshots' builds */
#ifndef VIEW_STOP
#define VIEW_STOP 0
#endif
#define STOP(n) if (VIEW_STOP == (n)) view_test_end()

static void test_run(void)
{
    *(volatile unsigned char *)0x9FB8 = 0;
    open_doc("Readme.txt", 0);
    step("text", "TEXT1.RAW");
    STOP(1);
    strcpy(pat, "NEEDLE");
    do_find();
    step("find", "TEXT2.RAW");
    do_find();
    step("find again", "TEXT3.RAW");
    copy();
    LogText("VIEW COPIED TEXT");
    open_doc("Line.bmp", 0);
    step("bmp1", "BMP1.RAW");
    open_doc("Color.bmp", 0);
    step("bmp4 fit", "BMP4F.RAW");
    fit = 0;
    draw_pic();
    pan(0, 8);
    pan(0, 8);
    pan(0, 8);
    pan(0, 8);                          /* (to 0,32: the view's top, V79) */
    step("bmp4 1:1", "BMP4A.RAW");
    copy();
    LogText("VIEW COPIED PICTURE");
    open_doc("Picture.cvt", 0);
    step("paint", "PAINT.RAW");
    STOP(2);
    open_doc("Sunset.cvt", 0);
    step("scrap", "SCRAP.RAW");
    open_doc("Album.cvt", 0);
    step("album 1", "ALBUM1.RAW");
    album_go(1);
    step("album 2", "ALBUM2.RAW");
    open_doc("View.cvt", 0);
    step("info", "INFO.RAW");
    STOP(3);
    open_doc("Line.bmp", 1);
    step("as text", "ASTEXT.RAW");
    /* the Open dialog (V82): 'h' selects the long-named picture, Return
       opens it; with VIEW.SHT in the folder the run ends in the dialog
       (its screenshot: key 1 ends it) */
    {
        unsigned char h = FOpen("VIEW.SHT", 'r');
        if (h >= 2 && h <= 9) {
            FClose(h);
            view_test_keys("h\1");
        } else
            view_test_keys("h\r");
    }
    choose();
    step("long name", "LONG.RAW");
    LogText("VIEW DONE");
    view_test_end();
}
#pragma code-name (pop)
#endif
