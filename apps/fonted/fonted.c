/* Font Editor: GEOS fonts on Veranda, in C (DECISIONS V62).

   A GEOS font file is a record file of type FONT, record n the font at n
   points (tools/fontcvt.py has the format). The editor works in the fonts
   folder /VERANDA/FONTS (it changes to it at its start): Open picks a font
   and a size with the font picker (fontpick.h), and the record is read
   into memory as a GEOS font whose rows are 16 bytes longer than they need
   to be (room for wider glyphs; LoadCharSet draws the preview from it).

   The screen (Veranda Look 3 "Sunroom", DECISIONS V148: the SDK's window
   chrome, vrwin.h, over the whole screen, Veranda's palette light or
   dark): the title band (the font, its size, a * when changed; the close
   box quits), a toolbar with the buttons (Open, Save, New size, Quit;
   Width - +, Base - +), the glyph in a zoomed grid on the left (a press
   on a cell toggles it, a drag paints with the value the first cell got;
   the baseline row is marked), the 96 characters on the right (a press
   picks one: on the selection colour), a preview in the font being
   edited, and the status bar (the hint; the character's figures).
   Width - and + take a column from the glyph's right or give it one;
   Base - and + move the baseline. New size asks for a point size and
   scales the current size to it (nearest pixel), which then is edited.

   Save writes a new file through 'w' (Name.tmp: the CVT, its records in
   order, the size edited put in or replaced, the info block's size list
   made again; then Name.cvt is deleted and Name.tmp renamed: a valid font
   file at every moment) and tells the font service to forget its copies
   (FontFlush). It never patches a file in place (V55).

   An extended record (DECISIONS V141: the glyphs of $A0-$FF after the 96
   of ASCII, an index of 193 words) keeps them: they are not shown or
   edited here, but Width and New size move and scale them with the rest
   and Save writes them back.

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <vr.h>
#include <string.h>
#include <stdlib.h>
#include <fontpick.h>
#include <theme.h>
#include <vrwin.h>
#include <vralert.h>

#define RAM_BANK (*(volatile unsigned char *)0x00)

#define FBUF    10240           /* the font: header, index, rows of WS bytes */
#define BO      bmo             /* the bitmap's offset: 8 + 2 * (nc + 1) */
#define PAD     16              /* bytes a row more than needed */

/* the screen: the window 80 x 60 cards, the toolbar card rows 2-5, the
   status bar rows 58-59 */
#define BY      24              /* the buttons (card rows 3-4) */
#define BH      16
#define GX      16              /* the grid */
#define GY      56
#define GW      320
#define GH      384
#define CX      344             /* the characters: 12 x 8 cells of 24 */
#define CY      56
#define CS      24
#define PX      344             /* the preview */
#define PY      264
#define PR      631
#define PB      455

static unsigned char font[FBUF];
static unsigned char head[762];         /* the file's entry, signature, info block, record table */
static unsigned char loaded;            /* a font is in memory */
static unsigned char dirty;
static unsigned char size, ch = 'A' - 32;
static unsigned int ws;                 /* bytes a row */
static unsigned char nc = 96;           /* glyphs: 96, or 192 in an extended record
                                           (DECISIONS V141: $A0-$FF after them, kept) */
static unsigned int bmo = 202;
static char fname[FONT_NAME_LEN];
static struct fontpick pick = { "", 12, 0 };
static char path[48];
static char line[64];
static unsigned char z;                 /* the zoom: a cell's size */
static unsigned char painting, pval, lastx, lasty;
static unsigned char buf[254];
static const struct vrwin win = { 0, 0, 80, 60, 4, 2, VW_CLOSE };
extern const unsigned char vr_icon[128];        /* (alerticon.c: the editor's icon) */
static const char hint[] = "A press on a cell toggles it; a drag paints.";

#ifdef FONTED_TEST
void fonted_test_start(void);
#endif

/*---------------------------------------------------------------
  the font in memory
 ---------------------------------------------------------------*/
#define HT      (font[3])
#define BASE    (font[0])

static unsigned int idx(unsigned char c)
{
    return font[8 + 2 * c] | font[9 + 2 * c] << 8;
}

static void set_idx(unsigned char c, unsigned int v)
{
    font[8 + 2 * c] = v;
    font[9 + 2 * c] = v >> 8;
}

static unsigned char gw(unsigned char c)
{
    return idx(c + 1) - idx(c);
}

static unsigned char *rowp(unsigned char r)
{
    return font + BO + r * ws;
}

static unsigned char px(unsigned int x, unsigned char r)
{
    return (rowp(r)[x >> 3] >> (7 - (x & 7))) & 1;
}

static void set_px(unsigned int x, unsigned char r, unsigned char v)
{
    unsigned char *p = rowp(r) + (x >> 3), m = 0x80 >> (x & 7);
    if (v)
        *p |= m;
    else
        *p &= ~m;
}

/* a 0 column put in at bit p of every row; or bit p taken out */
static void col_ins(unsigned int p)
{
    unsigned char r, *row, m, b;
    unsigned int i;
    for (r = 0; r < HT; ++r) {
        row = rowp(r);
        b = p >> 3;
        for (i = ws - 1; i > b; --i)
            row[i] = (row[i] >> 1) | (row[i - 1] << 7);
        m = 0xFF >> (p & 7);
        row[b] = (row[b] & ~m) | ((row[b] & m) >> 1);
    }
}

static void col_del(unsigned int p)
{
    unsigned char r, *row, m, b;
    unsigned int i;
    for (r = 0; r < HT; ++r) {
        row = rowp(r);
        b = p >> 3;
        m = 0xFF >> (p & 7);
        row[b] = (row[b] & ~m) | ((row[b] << 1) & m) | (row[b + 1] >> 7);
        for (i = b + 1; i < ws - 1; ++i)
            row[i] = (row[i] << 1) | (row[i + 1] >> 7);
        row[ws - 1] <<= 1;
    }
}

/*---------------------------------------------------------------
  drawing
 ---------------------------------------------------------------*/
static void text(const char *s, unsigned int x, unsigned int y)
{
    WPutString((char *)s, x, y);
}

static unsigned int strw(const char *s)
{
    unsigned int w = 0;
    while (*s)
        w += GetCharWidth(*s++);
    return w;
}

static void box(unsigned int l, unsigned int t, unsigned int r, unsigned int b, unsigned char pat)
{
    SetPattern(pat);
    WRectangle(l, t, r, b);
}

static const char *const blabel[8] = { "Open...", "Save", "New size...", "Quit", "Width -", "Width +", "Base -", "Base +" };
static const unsigned int bx[8] = { 8, 80, 152, 248, 344, 416, 488, 560 };
static const unsigned char bw[8] = { 64, 64, 88, 56, 64, 64, 64, 64 };

/* (V148, Sunroom) a button as the dialog boxes': white on the toolbar's
   chrome (card aligned), a frame with its corners cut */
static void button(unsigned char i)
{
    unsigned int x = bx[i], r = x + bw[i] - 1, b = BY + BH - 1;
    box(x, BY, r, b, 0);
    theme_rect(x >> 3, bw[i] >> 3, BY >> 3, BH >> 3, 0);
    WFrameRectangle(0xFF, x, BY, r, b);
    WDrawPoint(DRAW_ERASE, x, BY);
    WDrawPoint(DRAW_ERASE, r, BY);
    WDrawPoint(DRAW_ERASE, x, b);
    WDrawPoint(DRAW_ERASE, r, b);
    text(blabel[i], x + (bw[i] - strw(blabel[i])) / 2, BY + 3 + baselineOffset);
}

static void title(void)
{
    strcpy(line, "Font Editor");
    if (loaded) {
        strcat(line, ": ");
        strcat(line, fname);
        strcat(line, " ");
        utoa(size, line + strlen(line), 10);
        if (dirty)
            strcat(line, " *");
    }
    vr_win_title(&win, line);
    UseFont(FONT_UI);                   /* (vrwin ends with the system font) */
}

/* the grid's cell for the glyph's column x, row r */
static void cell(unsigned char x, unsigned char r)
{
    unsigned int l = GX + x * z, t = GY + r * z;
    box(l + 1, t + 1, l + z - 1, t + z - 1, px(idx(ch) + x, r) ? 1 : 0);
}

static void grid(void)
{
    unsigned char w, x, r;
    unsigned int y;
    box(0, GY - 4, GX + GW + 4, GY + GH + 4, 0);
    if (!loaded)
        return;
    w = gw(ch);
    z = GH / HT;
    if (w && GW / w < z)
        z = GW / w;
    if (z > 16)
        z = 16;
    for (x = 0; x <= w; ++x)
        WVerticalLine(0xAA, GX + x * z, GY, GY + HT * z);
    for (r = 0; r <= HT; ++r)
        WHorizontalLine(r == BASE + 1 ? 0xFF : 0xAA, GX, GX + w * z, GY + r * z);
    for (r = 0; r < HT; ++r)
        for (x = 0; x < w; ++x)
            if (px(idx(ch) + x, r))
                cell(x, r);
    y = GY + BASE * z;                      /* the baseline row: a mark */
    box(GX - 10, y + 1, GX - 4, y + z - 1, 1);
}

static void chars(void)
{
    unsigned char c;
    char s[2];
    s[1] = 0;
    box(CX, CY, CX + 12 * CS, CY + 8 * CS, 0);
    for (c = 0; c < 96; ++c) {
        unsigned int x = CX + (c % 12) * CS, y = CY + (c / 12) * CS;
        WFrameRectangle(0xFF, x, y, x + CS, y + CS);
        s[0] = c + 32;
        text(s, x + (CS - GetCharWidth(s[0])) / 2, y + 8 + baselineOffset);
        /* (V148) the one chosen on the selection colour */
        theme_rect(x >> 3, CS >> 3, y >> 3, CS >> 3, c == ch ? (theme.hilite ? theme.hilite : SELECT) : 0);
    }
}

/* the status bar: the hint, the character's figures (V148) */
static void figures(void)
{
    char *p;
    line[0] = 0;
    if (!loaded)
        goto out;
    strcpy(line, "'");
    p = line + 1;
    *p++ = ch + 32;
    strcpy(p, "' width ");
    utoa(gw(ch), line + strlen(line), 10);
    strcat(line, "  height ");
    utoa(HT, line + strlen(line), 10);
    strcat(line, "  baseline ");
    utoa(BASE, line + strlen(line), 10);
out:
    vr_win_status(&win, hint, line);
    UseFont(FONT_UI);
}

static const char *const sample[3] = { "The quick brown fox", "jumps over the lazy dog.", "ABC abc 0123 {gjpqy}" };

static void preview(void)
{
    unsigned char i;
    unsigned int y;
    box(PX, PY, PR, PB, 0);
    WFrameRectangle(0xFF, PX, PY, PR, PB);
    if (!loaded)
        return;
    LoadCharSet(font);
    WSetWindow(PY + 1, PB - 1);
    rightMargin = PR - 2;
    y = PY + 4 + BASE;
    for (i = 0; i < 3 && y < PB; ++i) {
        text(sample[i], PX + 4, y);
        y += HT + 2;
    }
    rightMargin = 639;
    WSetWindow(0, 479);
    UseFont(FONT_UI);
}

static void draw_all(void)
{
    unsigned char i;
    vr_win(&win, "Font Editor");
    title();
    for (i = 0; i < 8; ++i)
        button(i);
    grid();
    chars();
    figures();
    preview();
}

/*---------------------------------------------------------------
  messages
 ---------------------------------------------------------------*/
/* (V148) Sunroom's alert: the editor's icon, a headline, an explanation */
static void message(const char *s, const char *t)
{
    vr_alert(VA_OK, s, t);
}

struct askdlg {
    unsigned char pos;
    unsigned char t1, x1, y1, reg1;
    unsigned char t2, x2, y2, reg2, max;
    unsigned char ok, okx, oky;
    unsigned char cn, cnx, cny;
    unsigned char end;
};
static const struct askdlg askbox = {
    DEF_DB_POS | 1,
    DBVARSTR, TXT_LN_X, TXT_LN_2_Y, 0x0E,
    DBGETSTRING, TXT_LN_X, TXT_LN_3_Y, 0x0C, 3,
    OK, DBI_X_0, DBI_Y_2,
    CANCEL, DBI_X_2, DBI_Y_2,
    0
};

/*---------------------------------------------------------------
  files: the font folder's Name.cvt
 ---------------------------------------------------------------*/
static void make_path(const char *ext)
{
    strcpy(path, fname);
    strcat(path, ext);
}

/* n bytes from the open file h into p; 0 if all came */
static unsigned char rd(unsigned char h, void *p, unsigned int n)
{
    unsigned int k;
    while (n) {
        k = FRead(h, p, n);
        if (!k)
            return 1;
        p = (unsigned char *)p + k;
        n -= k;
    }
    return 0;
}

/* the offset of record n in the CVT (head's table); its length in *len */
static unsigned long rec_off(unsigned char n, unsigned int *len)
{
    unsigned long off = 762;
    unsigned char i, *t = head + 508;
    for (i = 0; i < n; ++i)
        off += (unsigned long)t[2 * i] * 254;
    *len = t[2 * n] ? (t[2 * n] - 1) * 254 + t[2 * n + 1] - 1 : 0;
    return off;
}

static unsigned char load(void)
{
    unsigned char h, e = 0, r;
    unsigned int len, io, bo, sw, base;
    unsigned long off;
    make_path(".cvt");
    h = FOpen(path, 'r');
    if (dosStatus >= 20 || h < 2 || h > 9)
        return FILE_NOT_FOUND;
    if (rd(h, head, 762) || head[21] != 1 || head[254 + 67] != FONT) {
        e = INCOMPATIBLE;
        goto out;
    }
    off = rec_off(pick.size, &len);
    if (!len || len > FBUF) {
        e = FILE_NOT_FOUND;
        goto out;
    }
    base = FBUF - len;                      /* the record at the end */
    FSeek(h, off, off >> 16);
    if (rd(h, font + base, len)) {
        e = STRUCT_MISMAT;
        goto out;
    }
    sw = font[base + 1] | font[base + 2] << 8;
    io = font[base + 4] | font[base + 5] << 8;
    bo = font[base + 6] | font[base + 7] << 8;
    nc = bo - io == 2 * 193 ? 192 : 96;    /* (V141: an extended record) */
    bmo = 8 + 2 * (nc + 1);
    if (font[base + 3] == 0 || font[base + 3] > 32 || io + 2 * (nc + 1) > len || bo + sw * font[base + 3] > len
        || BO + (sw + PAD) * font[base + 3] > base + bo) {
        e = STRUCT_MISMAT;
        goto out;
    }
    memmove(font, font + base, 8);
    memmove(font + 8, font + base + io, 2 * (nc + 1));
    ws = sw + PAD;
    for (r = 0; r < font[3]; ++r) {
        memmove(font + BO + r * ws, font + base + bo + r * sw, sw);
        memset(font + BO + r * ws + sw, 0, PAD);
    }
    font[1] = ws;
    font[2] = ws >> 8;
    font[4] = 8;
    font[5] = 0;
    font[6] = BO;
    font[7] = BO >> 8;
    size = pick.size;
out:
    FClose(h);
    return e;
}

static void put16(unsigned char *p, unsigned int v)
{
    p[0] = v;
    p[1] = v >> 8;
}

static unsigned char wr(unsigned char h, const void *p, unsigned int n)
{
    return FWrite(h, (void *)p, n);
}

/* the size edited, as a record: its length; written to h if h */
static unsigned int rec_len(void)
{
    return BO + ((idx(nc) + 7) >> 3) * HT;
}

static unsigned char write_rec(unsigned char h)
{
    unsigned char hd[8], r, e;
    unsigned int sw = (idx(nc) + 7) >> 3, n = rec_len();
    memcpy(hd, font, 8);
    put16(hd + 1, sw);
    if ((e = wr(h, hd, 8)) != 0 || (e = wr(h, font + 8, 2 * (nc + 1))) != 0)
        return e;
    for (r = 0; r < HT; ++r)
        if ((e = wr(h, rowp(r), sw)) != 0)
            return e;
    memset(buf, 0, sizeof buf);             /* its last block's padding */
    n %= 254;
    return n ? wr(h, buf, 254 - n) : 0;
}

static unsigned char save(void)
{
    unsigned char in, out, e = 0, n, last, *t;
    static unsigned char nt[254];
    unsigned int len, k, blocks = 1;
    unsigned long off;
    static char tmp[48];
    make_path(".cvt");
    in = FOpen(path, 'r');
    if (dosStatus >= 20 || in < 2 || in > 9)
        return FILE_NOT_FOUND;
    if (rd(in, head, 762)) {
        FClose(in);
        return STRUCT_MISMAT;
    }
    /* the new table: the old one, the size edited put in */
    t = head + 508;
    memcpy(nt, t, 254);
    last = 0;
    for (n = 0; n < 127 && (t[2 * n] || t[2 * n + 1]); ++n)
        last = n;
    if (size > last) {
        for (n = last + 1; n < size; ++n) {
            nt[2 * n] = 0;
            nt[2 * n + 1] = 0xFF;
        }
        last = size;
    }
    len = rec_len();
    nt[2 * size] = (len + 253) / 254;
    nt[2 * size + 1] = (len - 1) % 254 + 2;
    /* the info block's size list (ID << 6 | size), the entry's size */
    k = head[254 + 0x80 - 2] | head[254 + 0x81 - 2] << 8;
    memset(head + 254 + 0x82 - 2, 0, 30);
    for (n = 1, e = 0; n <= last && e < 15; ++n)
        if (nt[2 * n]) {
            put16(head + 254 + 0x82 - 2 + 2 * e++, k << 6 | n);
            blocks += nt[2 * n];
        }
    put16(head + 28, blocks + 2);
    e = 0;
    make_path(".tmp");
    strcpy(tmp, path);
    out = FOpen(tmp, 'w');
    if (dosStatus >= 20 || out < 2 || out > 9) {
        FClose(in);
        return DOS_ERROR;
    }
    if ((e = wr(out, head, 508)) != 0 || (e = wr(out, nt, 254)) != 0)
        goto done;
    for (n = 0; n <= last; ++n) {
        if (!nt[2 * n])
            continue;
        if (n == size) {
            if ((e = write_rec(out)) != 0)
                goto done;
            continue;
        }
        off = rec_off(n, &len);             /* (the old table) */
        FSeek(in, off, off >> 16);
        k = t[2 * n] * 254;
        while (k) {
            len = k > sizeof buf ? sizeof buf : k;
            if (rd(in, buf, len)) {
                e = STRUCT_MISMAT;
                goto done;
            }
            if ((e = wr(out, buf, len)) != 0)
                goto done;
            k -= len;
        }
    }
done:
    FClose(in);
    FClose(out);
    if (e) {
        FDelete(tmp);
        return e;
    }
    make_path(".cvt");
    FDelete(path);
    FRename(tmp, path);
    memcpy(head + 508, nt, 254);
    FontFlush(fname);
    dirty = 0;
    LogText("FONTED SAVED");
    return 0;
}

/*---------------------------------------------------------------
  a new size: the current one scaled (nearest pixel); the old rows from
  a copy in RAM banks, one at a time; each glyph's source columns
  stepped (x * w / nw without a division; V141: no table of columns, so
  an extended record's 192 glyphs fit)
 ---------------------------------------------------------------*/
static unsigned int oidx[193];
#define MAXROW  420
static unsigned char srow[MAXROW];

static unsigned char new_size(unsigned char ns)
{
    unsigned char oh = HT, nh, nb, c, r, w, nw, sbank;
    unsigned int sws = ws, total = 0, x, X, sx, num;
    nh = (unsigned int)oh * ns / size;
    if (nh < 1 || nh > 32 || sws > MAXROW)
        return BFR_OVERFLOW;
    for (c = 0; c <= nc; ++c)
        oidx[c] = idx(c);
    for (c = 0; c < nc; ++c) {          /* the new widths, the columns' sources */
        w = oidx[c + 1] - oidx[c];
        nw = (unsigned int)w * ns / size;
        if (w && !nw)
            nw = 1;
        total += nw;
    }
    if (BO + ((total + 7) / 8 + PAD) * nh > FBUF)
        return BFR_OVERFLOW;
    sbank = BankAlloc(2);
    if (!sbank)
        return NO_BANKS;
    BankCopy(font + BO, (void *)0xA000, sws * oh, 0, sbank);
    nb = (unsigned int)(BASE + 1) * nh / oh;
    font[0] = nb ? nb - 1 : 0;
    font[3] = nh;
    ws = (total + 7) / 8 + PAD;
    font[1] = ws;
    font[2] = ws >> 8;
    x = 0;
    for (c = 0; c < nc; ++c) {
        set_idx(c, x);
        w = oidx[c + 1] - oidx[c];
        nw = (unsigned int)w * ns / size;
        if (w && !nw)
            nw = 1;
        x += nw;
    }
    set_idx(nc, x);
    memset(font + BO, 0, ws * nh);
    for (r = 0; r < nh; ++r) {
        x = (unsigned int)r * oh / nh * sws;    /* the old row: from the banks */
        BankCopy((void *)(0xA000 + (x & 0x1FFF)), srow, sws, sbank + (x >> 13), 0);
        X = 0;
        for (c = 0; c < nc; ++c) {
            w = oidx[c + 1] - oidx[c];
            nw = (unsigned int)w * ns / size;
            if (w && !nw)
                nw = 1;
            sx = oidx[c];               /* oidx[c] + x * w / nw, stepped */
            num = 0;
            for (x = 0; x < nw; ++x, ++X) {
                if ((srow[sx >> 3] << (sx & 7)) & 0x80)
                    set_px(X, r, 1);
                num += w;
                while (num >= nw) {
                    num -= nw;
                    ++sx;
                }
            }
        }
    }
    BankFree(sbank);
    size = ns;
    return 0;
}

/*---------------------------------------------------------------
  commands
 ---------------------------------------------------------------*/
static void redraw(void)
{
    title();
    grid();
    chars();
    figures();
    preview();
}

static void cmd_open(void)
{
    unsigned char e;
    if (FontPick(&pick) != OK)
        return;
    UseFont(FONT_UI);
    if (!strcmp(pick.name, "System") || !strcmp(pick.name, "Veranda UI")) {
        message("This font is built in.", "Only a font file in the fonts folder can be edited.");
        return;
    }
    strcpy(fname, pick.name);
    e = load();
    loaded = e == 0;
    dirty = 0;
    if (e)
        message("The font could not be read.", "Its file is not a GEOS font, or this size is too large.");
    else
        LogText("FONTED OPENED");
    redraw();
}

static void cmd_save(void)
{
    if (!loaded)
        return;
    if (save())
        message("The font could not be saved.", "The file in the fonts folder is as it was.");
    title();
}

static void cmd_size(void)
{
    char num[4];
    unsigned char n = 0, i, e;
    if (!loaded)
        return;
    num[0] = 0;
    r5 = (unsigned int)num;
    r6 = (unsigned int)"New point size (1-63):";
    i = DoDlgBox((void *)&askbox);
    if (i != OK && i != DBGETSTRING)
        return;
    for (i = 0; num[i] >= '0' && num[i] <= '9'; ++i)
        n = n * 10 + num[i] - '0';
    if (n < 1 || n > 63 || n == size)
        return;
    e = new_size(n);
    if (e) {
        message("That size does not fit.", "Choose a smaller point size.");
        return;
    }
    dirty = 1;
    LogText("FONTED NEW SIZE");
    redraw();
}

static void cmd_width(signed char d)
{
    unsigned char c;
    unsigned int p = idx(ch + 1);
    if (!loaded)
        return;
    if (d > 0) {
        if (idx(nc) + 1 > (ws - 1) * 8)
            return;
        col_ins(p);
        for (c = ch + 1; c <= nc; ++c)
            set_idx(c, idx(c) + 1);
    } else {
        if (!gw(ch))
            return;
        col_del(p - 1);
        for (c = ch + 1; c <= nc; ++c)
            set_idx(c, idx(c) - 1);
    }
    dirty = 1;
    title();
    grid();
    figures();
    preview();
}

static void cmd_base(signed char d)
{
    if (!loaded || (d < 0 && !BASE) || (d > 0 && BASE + 1 >= HT))
        return;
    BASE += d;
    dirty = 1;
    title();
    grid();
    figures();
    preview();
}

/*---------------------------------------------------------------
  the mouse
 ---------------------------------------------------------------*/
/* the grid cell under (x, y): 0 if none */
static unsigned char at_cell(unsigned int x, unsigned int y, unsigned char *cx, unsigned char *cy)
{
    if (!loaded || x < GX || y < GY)
        return 0;
    *cx = (x - GX) / z;
    *cy = (y - GY) / z;
    return *cx < gw(ch) && *cy < HT;
}

static void paint_at(unsigned int x, unsigned int y)
{
    unsigned char cx, cy;
    if (!at_cell(x, y, &cx, &cy) || (cx == lastx && cy == lasty))
        return;
    lastx = cx;
    lasty = cy;
    if (px(idx(ch) + cx, cy) != pval) {
        set_px(idx(ch) + cx, cy, pval);
        cell(cx, cy);
        dirty = 1;
    }
}

static void press(void)
{
    unsigned int x = mouseXPos, y = mouseYPosW;
    unsigned char i, cx, cy;
    if (mouseData & 0x80) {                 /* a release: the painting ends */
        if (painting) {
            painting = 0;
            title();
            preview();
        }
        return;
    }
    if (vr_win_hit(&win, x, y) == VW_XCLOSE) {
        EnterDeskTop();
        return;
    }
    if (y >= BY && y < BY + BH) {
        for (i = 0; i < 8; ++i)
            if (x >= bx[i] && x < bx[i] + bw[i]) {
                WInvertRectangle(bx[i] + 1, BY + 1, bx[i] + bw[i] - 2, BY + BH - 2);
                WInvertRectangle(bx[i] + 1, BY + 1, bx[i] + bw[i] - 2, BY + BH - 2);
                switch (i) {
                case 0: cmd_open(); break;
                case 1: cmd_save(); break;
                case 2: cmd_size(); break;
                case 3: EnterDeskTop(); break;
                case 4: cmd_width(-1); break;
                case 5: cmd_width(1); break;
                case 6: cmd_base(-1); break;
                case 7: cmd_base(1); break;
                }
                return;
            }
        return;
    }
    if (x >= CX && x < CX + 12 * CS && y >= CY && y < CY + 8 * CS) {
        ch = (x - CX) / CS + (y - CY) / CS * 12;
        grid();
        chars();
        figures();
        return;
    }
    if (at_cell(x, y, &cx, &cy)) {
        pval = !px(idx(ch) + cx, cy);
        painting = 1;
        lastx = lasty = 255;
        paint_at(x, y);
    }
}

/* appMain: the drag */
static void poll(void)
{
    unsigned int x, y;
    if (!painting)
        return;
    do {
        x = mouseXPos;
        y = mouseYPosW;
    } while (x != mouseXPos || y != mouseYPosW);
    paint_at(x, y);
}

int main(void)
{
    ChDir(VR_FONTSDIR);                 /* (its documents are the fonts) */
    theme_load();                       /* (V148: Veranda's palette, light or dark) */
    theme_palette();
    theme_menus();                      /* (V79: no menus here; its boxes in the UI font) */
    vr_alert_icon = vr_icon;
    UseFont(FONT_UI);
    dispBufferOn = ST_WR_FORE;
    draw_all();
    otherPressVec = VR_FN(press);
    appMain = VR_FN(poll);
    LogText("FONTED RUNNING");
#ifdef FONTED_TEST
    fonted_test_start();
#endif
    return 0;
}
