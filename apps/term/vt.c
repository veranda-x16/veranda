/* Veranda Term: the screen model, the ANSI/VT100 parser, the renderer and
   the scrollback (MIT licence, see LICENSE).

   The model: ROWS rows of COLS characters and COLS attributes (160 bytes
   a row) in two RAM banks; rowmap[] gives each screen row's slot, so a
   scroll moves no bytes. A cell's attribute is what Veranda shows (term.h:
   the card's paper colour, reverse, bold), worked out when the cell is
   written:

     ANSI on a black background (40; or the default one, scheme "dark"):
       the cell is reversed, so its glyph is drawn in the paper colour and
       the card's paper is the foreground colour: coloured text on the
       black ink, as on a PC. Bold or bright: the bright colour.
     ANSI on a coloured background (41-47, 100-107): the card's paper is
       a light shade of the background, the glyph in the ink (black);
       bold is bold. The foreground colour is not shown (one ink).
     The default background, scheme "light": the normal paper, black text.
     Reverse (7) turns any of these over.

   The renderer draws only the rows that changed (dirty[]), with PutCards
   (runs of cells with the same flags) and ColorRect (runs of the same
   colour), into the foreground only (menus and dialog boxes recover
   through the kernel's save-under stack). Scrolls of the whole region
   wait and are done with one ScrollRect for all the lines that came in
   meanwhile (jump scroll), the cursor taken off and put back with
   WInvertRectangle. The colour map does not move with ScrollRect: a row
   that had colours or has them is drawn again.

   Lines scrolled off the top go to the scrollback in RAM banks (51 lines
   a bank, characters and attributes). */
#include <string.h>
#include "term.h"

#define SLOTB   51              /* slots a bank */

static unsigned char mbank;     /* the model's first bank */
static unsigned char rowmap[ROWS];
static unsigned char hascol[ROWS];      /* by slot: a cell has a colour */
static unsigned char mapc[ROWS];        /* by screen row: the map has colours */
static unsigned char dirty[ROWS];
static unsigned char *slotp[ROWS];
static unsigned char slotb[ROWS];

static unsigned char hb0, hbn;  /* the scrollback banks */
static unsigned int hcap, hhead;
unsigned int vt_hist, vt_back;
unsigned char vt_hold;

unsigned char vt_cx, vt_cy;
static unsigned char wrapnext, autowrap = 1, curshow = 1;
static unsigned char top, bot = ROWS - 1;
static unsigned char fg, bg, sgr;       /* ANSI: fg/bg 0 default, 1-8 colours 0-7; sgr bits */
#define S_BOLD  1
#define S_REV   2
static unsigned char cattr;             /* the display attribute of new cells */
static unsigned char eattr;             /* of erased cells (the background) */
static unsigned char sx, sy, sfg, sbg, ssgr; /* saved cursor */
static unsigned char g0, g1, gl;        /* charsets: 1 DEC graphics */

static unsigned char state, priv, np, inter;
static unsigned int par[8];

/* scrolling waiting for the renderer */
static int pend;
static unsigned char ptop, pbot;
static unsigned char cur_r = 255, cur_c;        /* the cursor as drawn */

static unsigned char rowbuf[COLS], attrbuf[COLS];

/* ANSI colour (1-8: black .. white) -> a VERA palette entry */
static const unsigned char fgdark[9]  = { 0, 1, 2, 5, 9, 6, 4, 3, 15 };   /* text on black */
static const unsigned char fgbright[9] = { 0, 11, 10, 13, 7, 14, 4, 3, 0 };
static const unsigned char bglight[9] = { 0, 1, 10, 13, 7, 14, 4, 3, 15 };  /* paper under black text */

/* VT100 special graphics ($5F-$7E) in CP437 */
static const unsigned char decgfx[32] = {
    ' ', 0x04, 0xB1, 0x09, 0x0C, 0x0D, 0x0A, 0xF8, 0xF1, 0x0A, 0x0B, 0xD9, 0xBF, 0xDA,
    0xC0, 0xC5, 0xC4, 0xC4, 0xC4, 0xC4, 0x5F, 0xC3, 0xB4, 0xC1, 0xC2, 0xB3, 0xF3, 0xF2,
    0xE3, 0xD8, 0x9C, 0xFA };

static void mkattr(void)
{
    unsigned char a, dark = bg == 1 || (bg == 0 && cfg.scheme);
    if (dark)
        a = A_REV | ((sgr & S_BOLD) ? fgbright[fg ? fg : 8] : fgdark[fg ? fg : 8]);
    else if (bg)
        a = bglight[bg];
    else
        a = 0;
    if (sgr & S_BOLD)
        a |= A_BOLD;
    if (sgr & S_REV)
        a ^= A_REV;
    if (!cfg.colour)
        a &= ~A_COL;
    cattr = a;
    /* the background of erased cells: as a space in the current colours,
       without bold */
    if (dark)
        a = A_REV | fgdark[fg ? fg : 8];
    else
        a = bglight[bg];
    if (sgr & S_REV)
        a ^= A_REV;
    if (!cfg.colour)
        a &= ~A_COL;
    eattr = a;
}

static unsigned char *row(unsigned char r)
{
    unsigned char s = rowmap[r];
    MAPBANK(slotb[s]);
    return slotp[s];
}

static void clear_cells(unsigned char r, unsigned char from, unsigned char to)
{
    unsigned char *p = row(r);
    memset(p + from, ' ', to - from + 1);
    memset(p + COLS + from, eattr, to - from + 1);
    if (eattr & A_COL)
        hascol[rowmap[r]] = 1;
    else if (from == 0 && to == COLS - 1)
        hascol[rowmap[r]] = 0;
    dirty[r] = 1;
}

static unsigned char histbuf[2 * COLS];

static void hist_push(unsigned char r)
{
    unsigned char *p;
    if (!hbn)
        return;
    memcpy(histbuf, row(r), 2 * COLS);
    MAPBANK(hb0 + hhead / SLOTB);
    p = (unsigned char *)0xA000 + (hhead % SLOTB) * (2 * COLS);
    memcpy(p, histbuf, 2 * COLS);
    if (++hhead == hcap)
        hhead = 0;
    if (vt_hist < hcap)
        ++vt_hist;
    if (vt_back && vt_back < vt_hist)
        ++vt_back;      /* the view stays on the same lines */
}

static unsigned char flush(void);

/* the region top..bottom moves up (n > 0) or down by n lines */
static void scroll(unsigned char t, unsigned char b, int n)
{
    unsigned char s, h = b - t + 1;
    if (pend && (t != ptop || b != pbot || (pend > 0) != (n > 0)))
        if (!flush()) {
            memset(dirty + ptop, 1, pbot - ptop + 1);
            pend = 0;
        }
    if (n > 0) {
        while (n--) {
            if (t == 0)
                hist_push(0);
            s = rowmap[t];
            memmove(rowmap + t, rowmap + t + 1, h - 1);
            memmove(dirty + t, dirty + t + 1, h - 1);
            rowmap[b] = s;
            clear_cells(b, 0, COLS - 1);
            ptop = t;
            pbot = b;
            ++pend;
        }
    } else {
        while (n++) {
            s = rowmap[b];
            memmove(rowmap + t + 1, rowmap + t, h - 1);
            memmove(dirty + t + 1, dirty + t, h - 1);
            rowmap[t] = s;
            clear_cells(t, 0, COLS - 1);
            ptop = t;
            pbot = b;
            --pend;
        }
    }
    if (pend >= h || -pend >= h) {
        memset(dirty + t, 1, h);
        pend = 0;
    }
}

static void lf(void)
{
    if (vt_cy == bot)
        scroll(top, bot, 1);
    else if (vt_cy < ROWS - 1)
        ++vt_cy;
}

static void ri(void)
{
    if (vt_cy == top)
        scroll(top, bot, -1);
    else if (vt_cy)
        --vt_cy;
}

void vt_reset(void)
{
    unsigned char i;
    fg = bg = sgr = 0;
    g0 = g1 = gl = 0;
    top = 0;
    bot = ROWS - 1;
    autowrap = curshow = 1;
    state = 0;
    wrapnext = 0;
    mkattr();
    for (i = 0; i < ROWS; ++i)
        clear_cells(i, 0, COLS - 1);
    vt_cx = vt_cy = 0;
    pend = 0;
}

void vt_init(unsigned char bank0, unsigned char hbank, unsigned char hbanks)
{
    unsigned char i;
    mbank = bank0;
    for (i = 0; i < ROWS; ++i) {
        rowmap[i] = i;
        slotb[i] = mbank + i / SLOTB;
        slotp[i] = (unsigned char *)0xA000 + (i % SLOTB) * (2 * COLS);
    }
    hb0 = hbank;
    hbn = hbanks;
    hcap = (unsigned int)hbanks * SLOTB;
    vt_reset();
}

static void putglyph(unsigned char c)
{
    unsigned char *p;
    if (wrapnext) {
        wrapnext = 0;
        vt_cx = 0;
        lf();
    }
    p = row(vt_cy);
    p[vt_cx] = c ? c : ' ';
    p[COLS + vt_cx] = cattr;
    if (cattr & A_COL)
        hascol[rowmap[vt_cy]] = 1;
    dirty[vt_cy] = 1;
    if (vt_cx == COLS - 1)
        wrapnext = autowrap;
    else
        ++vt_cx;
}

static unsigned char p1(unsigned char i)
{
    unsigned int v = (i < np && par[i]) ? par[i] : 1;
    return v > 255 ? 255 : v;
}

static void sgr_set(void)
{
    unsigned char i;
    unsigned int v;
    if (!np)
        par[np++] = 0;
    for (i = 0; i < np; ++i) {
        v = par[i];
        if (v == 0)
            fg = bg = sgr = 0;
        else if (v == 1)
            sgr |= S_BOLD;
        else if (v == 22)
            sgr &= ~S_BOLD;
        else if (v == 7)
            sgr |= S_REV;
        else if (v == 27)
            sgr &= ~S_REV;
        else if (v >= 30 && v <= 37)
            fg = v - 29;
        else if (v == 39)
            fg = 0;
        else if (v >= 40 && v <= 47)
            bg = v - 39;
        else if (v == 49)
            bg = 0;
        else if (v >= 90 && v <= 97) {
            fg = v - 89;
            sgr |= S_BOLD;
        } else if (v >= 100 && v <= 107)
            bg = v - 99;
        else if (v == 38 || v == 48)
            i = np;             /* 256 colours and RGB: not here */
    }
    mkattr();
}

static void clamp(void)
{
    if (vt_cx >= COLS)
        vt_cx = COLS - 1;
    if (vt_cy >= ROWS)
        vt_cy = ROWS - 1;
    wrapnext = 0;
}

static char reply[24];

static void report(void)
{
    /* ESC [ row ; col R */
    unsigned char r = vt_cy + 1, c = vt_cx + 1, i = 2;
    reply[0] = 27;
    reply[1] = '[';
    if (r >= 10)
        reply[i++] = '0' + r / 10;
    reply[i++] = '0' + r % 10;
    reply[i++] = ';';
    if (c >= 10)
        reply[i++] = '0' + c / 10;
    reply[i++] = '0' + c % 10;
    reply[i++] = 'R';
    reply[i] = 0;
    term_reply(reply);
}

static void csi(unsigned char f)
{
    unsigned char i, n, r;
    unsigned char *p;
    switch (f) {
    case 'A': n = p1(0); vt_cy = vt_cy >= top && vt_cy - n < top ? top : (vt_cy < n ? 0 : vt_cy - n); clamp(); break;
    case 'B': case 'e': n = p1(0); vt_cy = vt_cy <= bot && vt_cy + n > bot ? bot : (vt_cy + n >= ROWS ? ROWS - 1 : vt_cy + n); clamp(); break;
    case 'C': case 'a': n = p1(0); vt_cx = vt_cx + n >= COLS ? COLS - 1 : vt_cx + n; clamp(); break;
    case 'D': n = p1(0); vt_cx = vt_cx < n ? 0 : vt_cx - n; clamp(); break;
    case 'E': n = p1(0); vt_cy = vt_cy + n >= ROWS ? ROWS - 1 : vt_cy + n; vt_cx = 0; clamp(); break;
    case 'F': n = p1(0); vt_cy = vt_cy < n ? 0 : vt_cy - n; vt_cx = 0; clamp(); break;
    case 'G': case '`': vt_cx = p1(0) - 1; clamp(); break;
    case 'd': vt_cy = p1(0) - 1; clamp(); break;
    case 'H': case 'f': vt_cy = p1(0) - 1; vt_cx = p1(1) - 1; clamp(); break;
    case 'J':
        n = np ? par[0] : 0;
        if (n == 0) {
            clear_cells(vt_cy, vt_cx, COLS - 1);
            for (r = vt_cy + 1; r < ROWS; ++r)
                clear_cells(r, 0, COLS - 1);
        } else if (n == 1) {
            for (r = 0; r < vt_cy; ++r)
                clear_cells(r, 0, COLS - 1);
            clear_cells(vt_cy, 0, vt_cx);
        } else {
            for (r = 0; r < ROWS; ++r)
                clear_cells(r, 0, COLS - 1);
            vt_cx = vt_cy = 0;  /* as ANSI.SYS: BBSes expect it */
        }
        wrapnext = 0;
        break;
    case 'K':
        n = np ? par[0] : 0;
        if (n == 0)
            clear_cells(vt_cy, vt_cx, COLS - 1);
        else if (n == 1)
            clear_cells(vt_cy, 0, vt_cx);
        else
            clear_cells(vt_cy, 0, COLS - 1);
        wrapnext = 0;
        break;
    case 'X':
        n = p1(0);
        if (vt_cx + n > COLS)
            n = COLS - vt_cx;
        clear_cells(vt_cy, vt_cx, vt_cx + n - 1);
        break;
    case 'L': case 'M':
        if (vt_cy < top || vt_cy > bot)
            break;
        n = p1(0);
        if (n > bot - vt_cy + 1)
            n = bot - vt_cy + 1;
        scroll(vt_cy, bot, f == 'L' ? -(int)n : n);
        vt_cx = 0;
        break;
    case 'S': scroll(top, bot, p1(0)); break;
    case 'T': scroll(top, bot, -(int)p1(0)); break;
    case 'P': case '@':
        n = p1(0);
        if (n > COLS - vt_cx)
            n = COLS - vt_cx;
        p = row(vt_cy);
        i = COLS - vt_cx - n;
        if (f == 'P') {
            memmove(p + vt_cx, p + vt_cx + n, i);
            memmove(p + COLS + vt_cx, p + COLS + vt_cx + n, i);
            clear_cells(vt_cy, COLS - n, COLS - 1);
        } else {
            memmove(p + vt_cx + n, p + vt_cx, i);
            memmove(p + COLS + vt_cx + n, p + COLS + vt_cx, i);
            clear_cells(vt_cy, vt_cx, vt_cx + n - 1);
        }
        dirty[vt_cy] = 1;
        break;
    case 'm': sgr_set(); break;
    case 'r':
        r = p1(0) - 1;
        n = (np > 1 && par[1]) ? par[1] - 1 : ROWS - 1;
        if (n >= ROWS)
            n = ROWS - 1;
        if (r < n) {
            if (pend && !flush()) {
                memset(dirty + ptop, 1, pbot - ptop + 1);
                pend = 0;
            }
            top = r;
            bot = n;
        }
        vt_cx = vt_cy = 0;
        wrapnext = 0;
        break;
    case 's': sx = vt_cx; sy = vt_cy; break;
    case 'u': vt_cx = sx; vt_cy = sy; clamp(); break;
    case 'n':
        if (np && par[0] == 6)
            report();
        else if (np && par[0] == 5)
            term_reply("\033[0n");
        break;
    case 'c':
        if (!priv)
            term_reply("\033[?1;0c");   /* a VT100 */
        break;
    case 'h': case 'l':
        if (priv)
            for (i = 0; i < np; ++i) {
                if (par[i] == 7)
                    autowrap = f == 'h';
                else if (par[i] == 25)
                    curshow = f == 'h';
            }
        break;
    }
}

static void esc(unsigned char c)
{
    state = 0;
    switch (c) {
    case '[': state = 2; np = 0; priv = 0; par[0] = 0; inter = 0; break;
    case '(': state = 3; break;
    case ')': state = 4; break;
    case ']': case 'P': case '_': case '^': state = 5; break;
    case '#': case '%': state = 6; break;
    case '7': sx = vt_cx; sy = vt_cy; sfg = fg; sbg = bg; ssgr = sgr; break;
    case '8': vt_cx = sx; vt_cy = sy; fg = sfg; bg = sbg; sgr = ssgr; mkattr(); clamp(); break;
    case 'D': lf(); break;
    case 'E': vt_cx = 0; lf(); break;
    case 'M': ri(); break;
    case 'c': vt_reset(); break;
    }
}

void vt_put(unsigned char c)
{
    if (state == 0) {
        if (c >= 32) {
            if (c == 127)
                return;
            if (c >= 0x5F && c < 0x7F && (gl ? g1 : g0))
                c = decgfx[c - 0x5F];
            putglyph(c);
            return;
        }
    } else if (state == 2) {
        if (c >= '0' && c <= '9') {
            if (!np)
                np = 1;
            par[np - 1] = par[np - 1] * 10 + (c - '0');
            return;
        }
        if (c == ';') {
            if (!np)
                np = 1;
            if (np < 8)
                par[np++] = 0;
            return;
        }
        if (c >= '<' && c <= '?') {
            priv = c;
            return;
        }
        if (c >= ' ' && c <= '/') {
            inter = c;
            return;
        }
        if (c >= '@' && c <= '~') {
            state = 0;
            if (!inter)
                csi(c);
            return;
        }
    } else if (state == 1) {
        if (c >= ' ') {
            esc(c);
            return;
        }
    } else if (state == 3 || state == 4) {
        if (c >= ' ') {
            if (state == 3)
                g0 = c == '0';
            else
                g1 = c == '0';
            state = 0;
            return;
        }
    } else if (state == 5) {    /* a string: up to BEL or ST */
        if (c == 7 || c == 0x9C)
            state = 0;
        else if (c == 27)
            state = 1;
        return;
    } else if (state == 6) {
        state = 0;
        return;
    }
    /* C0 controls (also in the middle of a sequence, as VT100) */
    switch (c) {
    case 27: state = 1; break;
    case 24: case 26: state = 0; break;
    case 13: vt_cx = 0; wrapnext = 0; if (cfg.crin) lf(); break;
    case 10: case 11: case 12: lf(); break;
    case 8: if (vt_cx) --vt_cx; wrapnext = 0; break;
    case 9:
        vt_cx = (vt_cx | 7) + 1;
        if (vt_cx >= COLS)
            vt_cx = COLS - 1;
        break;
    case 14: gl = 1; break;
    case 15: gl = 0; break;
    }
}

void vt_write(const unsigned char *p, unsigned int n)
{
    while (n--)
        vt_put(*p++);
}

void vt_puts(const char *s)
{
    while (*s) {
        if (*s == '\n')
            vt_put(13);
        vt_put(*s++);
    }
}

/*---------------------------------------------------------------
  drawing
 ---------------------------------------------------------------*/
static unsigned char can_draw(void)
{
    return !vt_hold && !vt_back && menuNumber == 0;
}

static void draw_line(unsigned char r, const unsigned char *src, unsigned char has)
{
    unsigned char i, j, f, y8 = TROW + r;
    unsigned int y = TY + (r << 3);
    memcpy(rowbuf, src, COLS);
    memcpy(attrbuf, src + COLS, COLS);
    for (i = 0; i < COLS; i = j) {
        f = attrbuf[i] & (A_REV | A_BOLD);
        for (j = i + 1; j < COLS && (attrbuf[j] & (A_REV | A_BOLD)) == f; ++j)
            ;
        PutCards(rowbuf + i, font, i, j - i, y, f >> 4);
    }
    if (has || mapc[r]) {
        for (i = 0; i < COLS; i = j) {
            f = attrbuf[i] & A_COL;
            for (j = i + 1; j < COLS && (attrbuf[j] & A_COL) == f; ++j)
                ;
            ColorRect(i, j - i, y8, 1, f);
        }
    }
    mapc[r] = has;
}

static void draw_row(unsigned char r)
{
    unsigned char s = rowmap[r];
    unsigned char *p = row(r);
    draw_line(r, p, hascol[s]);
    dirty[r] = 0;
}

static void cursor(void)
{
    unsigned int x = cur_c << 3, y = TY + (cur_r << 3);
    WInvertRectangle(x, y, x + 7, y + 7);
}

/* everything waiting; 0 if drawing is not possible now */
static unsigned char flush(void)
{
    unsigned char r;
    if (!can_draw())
        return 0;
    dispBufferOn = ST_WR_FORE;
    if (cur_r != 255) {
        cursor();
        cur_r = 255;
    }
    if (pend) {
        ScrollRect(0, COLS, TY + (ptop << 3), TY + (pbot << 3) + 7, -(pend << 3), 0);
        for (r = ptop; r <= pbot; ++r)
            if (mapc[r] || hascol[rowmap[r]])
                dirty[r] = 1;
        pend = 0;
    }
    for (r = 0; r < ROWS; ++r)
        if (dirty[r])
            draw_row(r);
    if (curshow) {
        cur_r = vt_cy;
        cur_c = vt_cx;
        cursor();
    }
    return 1;
}

void vt_render(void)
{
    flush();
}

/* the window's colours back to the normal paper (a page over it) */
void vt_mapclear(void)
{
    unsigned char r;
    for (r = 0; r < ROWS && !mapc[r]; ++r)
        ;
    if (r < ROWS)
        ColorRect(0, COLS, TROW, ROWS, 0);
    memset(mapc, 0, ROWS);
}

void vt_redraw(void)
{
    memset(dirty, 1, ROWS);
    pend = 0;
    cur_r = 255;
    flush();
}

/* the scrollback: the window shows the lines vt_back lines before the
   live screen */
void vt_view(int delta)
{
    int b = (int)vt_back + delta;
    unsigned char r;
    unsigned int i, idx;
    if (b < 0)
        b = 0;
    if (b > (int)vt_hist)
        b = vt_hist;
    vt_back = b;
    if (!vt_back) {
        vt_redraw();
        status();
        return;
    }
    if (menuNumber)
        return;
    dispBufferOn = ST_WR_FORE;
    cur_r = 255;
    for (r = 0; r < ROWS; ++r) {
        i = vt_hist - vt_back + r;     /* 0: the oldest line kept */
        if (i < vt_hist) {
            idx = (hhead + hcap - vt_hist + i) % hcap;
            MAPBANK(hb0 + idx / SLOTB);
            memcpy(histbuf, (unsigned char *)0xA000 + (idx % SLOTB) * (2 * COLS), 2 * COLS);
        } else
            memcpy(histbuf, row(i - vt_hist), 2 * COLS);
        for (idx = COLS; idx < 2 * COLS && !(histbuf[idx] & A_COL); ++idx)
            ;
        draw_line(r, histbuf, idx < 2 * COLS);
    }
    memset(dirty, 1, ROWS);     /* the live screen, when it comes back */
    pend = 0;
    status();
}

void vt_cell_text(unsigned char r, unsigned char *out)
{
    memcpy(out, row(r), COLS);
}

void vt_cell_attr(unsigned char r, unsigned char *out)
{
    memcpy(out, row(r) + COLS, COLS);
}
