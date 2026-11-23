/* Veranda shell: Veranda Look 3's icons, part two (overlay 16; DECISIONS
   V132, V165): the icons' labels, the plain desktop's tiles, the colour
   icons kept in RAM, a GEOS file's listing in one open, a page's icons
   loaded before it is drawn (moved out of look3.c, overlay 12, for its
   room).

   - The icons' labels in Gate Sans 9 (fontSmall: look.c loads it), on
     one line or two: a name too wide for the 70 pixels of a cell breaks
     at its last space that lets the first line fit ("Veranda Write"
     is "Commander" over "Write"); a line still too wide is cut with
     "...". The lines 11 pixels apart from the cell's line 34; the
     selected one bold, its cards (2 card rows for one line, 3 for two)
     in the selection colour.

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <string.h>
#include <theme.h>
#include "shell.h"
#include "tiles.h"
#pragma code-name ("OVERLAY16")
#pragma rodata-name ("OVL16RO")
#pragma data-name ("OVL16DATA")
#pragma bss-name ("OVL16BSS")

#define PLAIN_T 16              /* the plain desktop's tile (wall.c), in row 2 */
typedef void (*FBBB)(unsigned char, unsigned char, unsigned char);
extern char k3buf[13];          /* (main.c) */

#define LW 70                   /* a label's width (a cell is 72) */

static unsigned int w1, w2, wm;
static unsigned char n, c0, cn;

static unsigned int width(const char *s)
{
    unsigned int w = 0;
    while (*s)
        w += GetCharWidth(*s++);
    return w;
}

/* s cut to fit in LW pixels, "..." where cut; its width */
static unsigned int fit(char *s)
{
    unsigned char l, c;
    unsigned int x = 0;
    for (l = 0; (c = s[l]) != 0; ++l) {
        c = GetCharWidth(c);
        if (x + c > LW)
            break;
        x += c;
    }
    if (!s[l])
        return x;
    while (l && x + 3 * GetCharWidth('.') > LW)
        x -= GetCharWidth(s[--l]);
    strcpy(s + l, "...");
    return x + 3 * GetCharWidth('.');
}

/* E's name into str (line 1) and tmp (line 2: n 2), in the small font
   (the kernel reads strings below $A000: str and tmp are the resident
   part's); the label's card columns c0, cn for the cell at x */
static void lines(unsigned int x, unsigned char bold)
{
    char *sp, *best = 0;
    unsigned int tx;
    UseFont(fontSmall);
    currentMode = bold ? SET_BOLD : 0;
    shown(&E, str);
    n = 1;
    if (width(str) > LW) {
        for (sp = str; (sp = strchr(sp, ' ')) != 0; ++sp) {
            *sp = 0;
            if (width(str) <= LW)
                best = sp;
            *sp = ' ';
        }
        if (best) {
            *best = 0;
            strcpy(tmp, best + 1);
            n = 2;
            w2 = fit(tmp);
        }
    }
    w1 = fit(str);
    wm = n == 2 && w2 > w1 ? w2 : w1;
    tx = x + (72 - wm) / 2;
    c0 = tx >> 3;
    cn = ((tx + wm) >> 3) - c0 + 1;
}

/* the label of E under the icon of the cell at x, y (from line y + 34),
   drawn (on: selected, bold); the font then FONT_UI again */
void lbl_draw(unsigned int x, unsigned int y, unsigned char on)
{
    lines(x, on);
    WPutString(str, x + (72 - w1) / 2, y + 34 + baselineOffset);
    if (n == 2)
        WPutString(tmp, x + (72 - w2) / 2, y + 45 + baselineOffset);
    if (on && lookNone)
        WInvertRectangle(c0 * 8, y + 32, (c0 + cn) * 8 - 1, y + 39 + n * 8);
    currentMode = 0;
    UseFont(FONT_UI);
}

/* the label's cards in colour c (the selection); c 0: the three card
   rows a label may use, the cell's width, back to the paper */
void lbl_colour(unsigned int x, unsigned int y, unsigned char c)
{
    if (!c) {
        look_rect(x >> 3, 9, (y >> 3) + 4, 3, 0);
        return;
    }
    lines(x, 1);
    look_rect(c0, cn, (y >> 3) + 4, n + 1, c);
    currentMode = 0;
    UseFont(FONT_UI);
}

/* the plain desktop's tiles and map into the picture's banks b .. b + 3
   (wall.c: tiles 0-15 solid, 16 entry 1, every card tile 16 in row 2) */
void ic3_plain(unsigned char b)
{
    unsigned int i;
    for (i = 0; i < 17 * 32 / 2; ++i)
        ((unsigned int *)buf)[i] = (i >> 4) < 16 ? (i >> 4) * 0x1111u : 0x1111u;
    bput(b, 0, buf, 17 * 32);
    for (i = 0; i < 80; ++i) {
        buf[2 * i] = PLAIN_T;
        buf[2 * i + 1] = 0x20;
    }
    for (i = 0; i < 60; ++i)
        bput(b + 2 + (i >= 51), (i % 51) * 160, buf, 160);
}

/*---------------------------------------------------------------- the icons kept in RAM
   (V165) The colour icons (I3 blocks, 658 bytes) of the windows' files
   that carry their own, by class (k3buf), in NST records of three RAM
   banks (12 a bank), read in the listing's one open of the file
   (dir_info), while a folder is opened alone: its page is loaded from
   them, and its next page (ic3_ahead's work, at dir_rest's end); then the
   banks are given back (ic3_stfree), as banks are short at 512 KB (V168:
   the kernel's own start of Preferences, the bar's clock, and the
   switcher's find none else, and they cannot ask the shell). A ring: the
   oldest record goes when they are all used. */

#define NST     36
#define IC_LEN  658

static unsigned char stB = 0, stN = 0, stNext = 0;     /* (DATA: an overlay's BSS is not cleared) */
static char stKey[NST][12];

static unsigned char stFind(void)
{
    unsigned char i;
    for (i = 0; i < stN; ++i)
        if (!memcmp(stKey[i], k3buf, 12))
            return i;
    return 0xFF;
}

/* k3buf's record into buf: 1, or 0 none */
unsigned char ic3_stget(void)
{
    unsigned char i = stFind();
    if (i == 0xFF)
        return 0;
    bget(stB + i / 12, (i % 12) * IC_LEN, buf, IC_LEN);
    return 1;
}

/* their banks given back (dir_rest: the folder opened, its pages loaded) */
void ic3_stfree(void)
{
    if (stB)
        BankFree(stB);
    stB = stN = stNext = 0;
}

/* buf kept as k3buf's record */
void ic3_stput(void)
{
    unsigned char i;
    if (!stB)                           /* (no folder being opened) */
        return;
    if ((i = stFind()) == 0xFF) {
        i = stNext;
        if (++stNext == NST)
            stNext = 0;
        if (stN < NST)
            ++stN;
        memcpy(stKey[i], k3buf, 12);
    }
    bput(stB + i / 12, (i % 12) * IC_LEN, buf, IC_LEN);
}

/* (V165) window w's GEOS file E (the listing's entry; its folder the
   current one) as its n-th icon: its info block (fileHeader), its GEOS
   icon, its Look 2 tile (tile nt of the window's tiles when it has one)
   and, on the tile desktop, its own colour icon, all from one open of the
   file and its first 508 bytes (the directory entry, the signature with
   the tile block and the I3 offset, the info block: docs/APPFORMAT.md);
   FindFile, GetFHdrInfo, the tile block's read and the colour icon's
   each opened it (four opens, about 110 ms a program at 8 MHz). 0: not a
   GEOS file; 1 done, 3 its own tile used */
typedef unsigned char (*FIC3R)(unsigned char, unsigned char, const char *);

unsigned char dir_info(unsigned char w, unsigned char n, unsigned char nt)
{
    unsigned char h, r = 0, t;
    unsigned long o;
    h = FOpen((void *)E.name, 'r');
    if (h < 2 || h > 9)
        return 0;
    if (FRead(h, buf, 508) != 508)
        goto done;
    r = 1;
    fileHeader[0] = 0;                  /* (as GetFHdrInfo: CvtHeader) */
    fileHeader[1] = 0xFF;
    memcpy((void *)(fileHeader + 2), buf + 254, 254);
    E.geos = fileHeader[69];
    memcpy(pic, (void *)(fileHeader + 4), 64);
    pic[0] = 0xBF;
    icon_put(w, n, pic, (void *)(fileHeader + 144));
    E.icon = I_OWN + n;
    t = !memcmp(fileHeader + 137, "VRND", 4);
    if (t && nt < MAXTILE && (fileHeader[143] & 2)) {      /* (dir.c's tileFor) */
        bput(bTiles, (w ? 4096 : 0) + nt * TILELEN, buf + 96, TILELEN);
        E.tile = TL_OWN + nt;
        r = 3;
    } else {
        t = XCALL(bTile, tile_class, unsigned char (*)(const unsigned char *))(fileHeader + 77);
        E.tile = t ? t : TL_ICON;
    }
    o = buf[225] == 'I' && buf[226] == '3' ? buf[227] | (unsigned long)buf[228] << 8 | (unsigned long)buf[229] << 16 : 0;
    if (XCALL(bLook3, ic3_file, FIC3R)(w, n, E.name) && o) {      /* (it reads buf: the offset first) */
        memcpy(k3buf, (void *)(fileHeader + 77), 12);
        if (stB && stFind() == 0xFF) {
            if (!FSeek(h, (unsigned int)o, (unsigned int)(o >> 16)) && FRead(h, buf, IC_LEN) == IC_LEN)
                ic3_stput();
        }
    }
done:
    FClose(h);
    return r;
}

void ic3_clock(unsigned char what);
void ic3_ahead(void);

/* (V165) window w's entry i (dir.c's dir_read: the listing's entries,
   the folder the current one): dir_info, once (rDone) */
static unsigned char rNi, rNt, rW = 0xFF, rDone[(MAXE + 7) / 8];

static void info(unsigned char w, unsigned char i)
{
    unsigned char t, m = 1 << (i & 7);
    if (rDone[i >> 3] & m)
        return;
    rDone[i >> 3] |= m;
    ent_get(w, i);
    if (E.type != 'F' || rNi >= MAXICON || !shell_is_cvt(E.name) || !(t = dir_info(w, rNi, rNt)))
        return;
    ++rNi;
    if (t & 2)
        ++rNt;
    ent_put(w, i);
}

/* the info blocks of all of window w's entries; lazy (sorted by the
   listing already): those of the page it will show (as view_draw computes
   it), dir_rest the others once it is drawn (a folder's first screen
   waits for its files on the screen alone: an open each, about 35 ms at
   8 MHz) */
void dir_infos(unsigned char w, unsigned char lazy)
{
    struct win *p = &wins[w];
    unsigned char i, f, per, n = p->n;
    rW = 0xFF;
    rNi = rNt = 0;
    memset(rDone, 0, sizeof rDone);
    ic3_stfree();
    if (lazy && ic3On)                  /* (a folder shown: its icons kept while it opens) */
        stB = BankAlloc(NST / 12);
    if (lazy) {
        per = XCALL(bView, view_per, RB)(w);
        f = p->first;
        if (f >= n)
            f = n > per ? n - per : 0;
        f -= f % vCols;
        for (i = f; i < n && i < f + per; ++i)
            info(w, p->order[i]);
        rW = w;
    } else
        for (i = 0; i < n; ++i)
            info(w, i);
    p->nicons = rNi;
}

void dir_rest(unsigned char w)
{
    struct win *p = &wins[w];
    unsigned char i;
    ic3_clock(1);
    if (rW != w)
        goto done;
    rW = 0xFF;
    play_busy = 1;
    if (ChDir(p->path) == 0)
        for (i = 0; i < p->n; ++i)
            info(w, i);
    p->nicons = rNi;
    if (front != 0xFF)
        ChDir(wins[front].path);
    if (ic3Next == w + 1)               /* (the next page from them, into spare tiles) */
        ic3_ahead();
    play_busy = 0;
done:
    ic3_stfree();
    ic3_clock(2);
}

/* each cell of window w's page (next: the page after it) given to
   look3.c's f (overlay 12) as (w, its tile, its GEOS file's icon) */
static void cells(unsigned char w, unsigned char next, void *f)
{
    struct win *p = &wins[w];
    unsigned char per, s, i, g;
    per = XCALL(bView, view_per, RB)(w);
    g = p->first;                       /* (as view_draw will) */
    if (g >= p->n)
        g = p->n > per ? p->n - per : 0;
    g -= g % vCols;
    if (next)
        g += per;
    for (s = 0; s < per; ++s) {
        if ((i = g + s) >= p->n)
            break;
        ent_get(w, p->order[i]);
        XCALL(bLook3, f, FBBB)(w, E.tile ? E.tile : TL_BUILT + (E.type == 'D' ? T_FOLDER : E.type == 'U' ? T_UP : T_DOCUMENT),
                               E.icon - I_OWN);
    }
}

/* (V165) window w, in front, drawn whole (win.c's content): its page's
   colour icons loaded first (from RAM: the library, the records above; a
   file read only for an icon not kept), what it showed before given up
   (look3.c's ic3_mark), its cells' colours the paper; then view.c draws
   each cell once, its ink and its colours together (ic3Now); 0 not the
   icons' view (nothing done but the marks), or not drawn whole on the
   screen (nothing done) */
unsigned char ic3_page(unsigned char w)
{
    struct win *p = &wins[w];
    unsigned char i, side;
    if (clipOn || colClip || !ic3On || !(dispBufferOn & ST_WR_FORE))
        return 0;                       /* (not drawn whole on the screen) */
    XCALL(bLook3, ic3_mark, FB)(w);
    if (p->view != V_ICON)
        return 0;
    cells(w, 0, (void *)ic3_want);
    side = p->w >= 40 ? 12 : 0;
    i = (p->y + 40) >> 3;
    look_rect(p->x + side, p->w - side - 2, i, ((p->y + p->h - 17) >> 3) - i + 1, 0);
    ic3Next = w + 1;
    return 1;
}

/* (V165, main.c's idle after ic3_page) the front window's next page's
   icons loaded into spare tiles (look3.c's ic3_spare: nothing on the
   screen given up), so Page > Next, Page Down and the scroll bar's track
   find them in VRAM */
void ic3_ahead(void)
{
    unsigned char w = ic3Next - 1;
    ic3Next = 0;
    if (w == front && wins[w].open && wins[w].view == V_ICON && ic3On)
        cells(w, 1, (void *)ic3_spare);
}

/*---------------------------------------------------------------- look3.c's rows and shadow
   (moved here for overlay 12's room, V165) */
#define IROW    12
#define DROW    11
#define VREG(a) (*(volatile unsigned char *)(a))

static const unsigned int pal3[15] = {
    0xFFF, 0xDDE, 0x99A, 0x556, 0x9DF, 0x48D, 0x237, 0xFE5, 0xFA3, 0xA52, 0xE44, 0x9E6, 0x3A5, 0xC9F, 0x73C };

/* palette rows IROW and DROW (after gui_pal: it writes 11-15 of 2-12);
   the shadow's two shades, entries 2 and 3 of row 2 (the plain desktop
   uses its entry 1): half and three quarters of the desktop's colour */
void ic3_rows(unsigned char plain)
{
    unsigned char r, i;
    unsigned int c;
    if (plain) {                    /* (V151's soft shadow: entries 34, 35 of the plain
                                       desktop's row 2; a picture's row 2 is its own) */
        c = theme.desk ? theme_colour(theme.desk, theme.dark) : theme.dark ? 0x334 : theme.paper;
        VREG(0x9F25) = 0;
        VREG(0x9F20) = 0x44;
        VREG(0x9F21) = 0xFA;
        VREG(0x9F22) = 0x11;
        r = (c >> 1) & 0x77;
        VREG(0x9F23) = r;
        VREG(0x9F23) = (c >> 9) & 7;
        c -= (c >> 2) & 0x333;
        VREG(0x9F23) = c;
        VREG(0x9F23) = c >> 8;
    }
    for (r = DROW; r <= IROW; ++r) {
        c = 0xFA02 + (r << 5);
        VREG(0x9F25) = 0;
        VREG(0x9F20) = c;
        VREG(0x9F21) = c >> 8;
        VREG(0x9F22) = 0x11;
        for (i = 0; i < 15; ++i) {
            c = pal3[i];
            if (r == DROW && i == 13)
                c = theme_colour(theme.desk, theme.dark);
            else if (theme.dark)
                c = (c >> 1) & 0x777;
            VREG(0x9F23) = c;
            VREG(0x9F23) = c >> 8;
        }
    }
}

/*---------------------------------------------------------------- the soft shadow
   (Look 3, V151) its five tiles at tile t (look3.c gives them out) */
/* the five tiles: 2 bits a pixel (1 the desktop, 2 the shadow, 3 its
   outer edge), a row 2 bytes */
static const unsigned char shData[80] = {
    0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0xFD, 0x55, 0xAD, 0x55, 0xAD, 0x55, 0xAD, 0x55, 0xAD, 0x55,
    0xAD, 0x55, 0xAD, 0x55, 0xAD, 0x55, 0xAD, 0x55, 0xAD, 0x55, 0xAD, 0x55, 0xAD, 0x55, 0xAD, 0x55,
    0xAD, 0x55, 0xAD, 0x55, 0xFD, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55,
    0xAA, 0xAA, 0xAA, 0xAA, 0xFF, 0xFF, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55,
    0x57, 0xAA, 0x57, 0xAA, 0x57, 0xFF, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55 };

#pragma static-locals (push, on)

void ic3_shadow5(unsigned int t)
{
    unsigned char i, v;
    unsigned long a = 0x13000UL + ((unsigned long)t << 5);
    VREG(0x9F25) = 0;
    VREG(0x9F20) = a;
    VREG(0x9F21) = a >> 8;
    VREG(0x9F22) = 0x10 | (unsigned char)(a >> 16);
    for (i = 0; i < 80; ++i) {
        v = shData[i];
        VREG(0x9F23) = (v >> 2 & 0x30) | (v >> 4 & 3);
        VREG(0x9F23) = (v << 2 & 0x30) | (v & 3);
    }
}

#pragma static-locals (pop)


/*---------------------------------------------------------------- the gates' times
   (V165) a folder opened (wops.c's win_open): 0 dir_read's start, 1 the window drawn ("SHELL FOLDER
   SHOWN IN <cycles>": when it shows), 2 the folder's other files read
   ("SHELL FOLDER READ IN"); the emulator's cycle counter (the gates only:
   real hardware's expansion cards answer at $9FB0-$9FBF) */
static unsigned long clk0;

void ic3_clock(unsigned char what)
{
    unsigned long c;
    unsigned char *q = (unsigned char *)&c;
    if (!testing)
        return;
    q[0] = VREG(0x9FB8);
    q[1] = VREG(0x9FB9);
    q[2] = VREG(0x9FBA);
    q[3] = VREG(0x9FBB);
    if (!what) {
        clk0 = c;
        return;
    }
    strcpy(msg, what == 1 ? "SHELL FOLDER SHOWN IN " : "SHELL FOLDER READ IN ");
    num(c - clk0, msg + strlen(msg));
    LogText(msg);
}

/*---------------------------------------------------------------- look3.c's tiles
   (V165) the colour icons' tiles (17-479, then 774-990; on a picture from
   its end), a bit each in tb: the first run of free ones that fits (the
   holes evicted icons left too; whole bytes in use skipped); 0 none */
#define T_HI    480
#define P_LO    774             /* (gui.s: DBOX + 4) */
#define P_HI    991             /* (991: the scroll bar's track, chrome.c: V151) */

static unsigned char tb[124];
static unsigned int tLo;
static const unsigned char bit[8] = { 1, 2, 4, 8, 16, 32, 64, 128 };

#pragma static-locals (push, on)

void ic3_tset(unsigned int t, unsigned int n, unsigned char v)
{
    unsigned char *q;
    for (; n; --n, ++t) {
        q = tb + (t >> 3);
        if (v)
            *q |= bit[t & 7];
        else
            *q &= ~bit[t & 7];
    }
}

static unsigned int tfind(unsigned char n)
{
    unsigned int t;
    unsigned char r = 0, b;
    for (t = tLo; t < P_HI; ++t) {
        b = tb[t >> 3];
        if (!(t & 7) && b == 0xFF) {
            t += 7;
            r = 0;
        } else if (b & bit[t & 7])
            r = 0;
        else if (++r == n)
            return t + 1 - n;
    }
    return 0;
}

#pragma static-locals (pop)

void ic3_tinit(unsigned int lo)
{
    tLo = lo;
    memset(tb, 0xFF, sizeof tb);
    ic3_tset(lo, T_HI - lo, 0);
    ic3_tset(P_LO, P_HI - P_LO, 0);
}

unsigned int ic3_tget(unsigned char n)
{
    unsigned int t = tfind(n);
    if (t)
        ic3_tset(t, n, 1);
    return t;
}

/* (V165) win.c's win_content: window w's body's colours alone (right of
   the sidebar, from the toolbar to the status bar: a page, a scroll), its
   frame's as they were (the whole window's took 790,000 cycles a page) */
void colours_in(unsigned int l, unsigned int t, unsigned int r, unsigned int b);   /* (win.c) */

void ic3_body(unsigned char w)
{
    struct win *p = &wins[w];
    XCALL(bWin, colours_in, void (*)(unsigned int, unsigned int, unsigned int, unsigned int))
        ((p->x + (p->w >= 40 ? 12 : 0)) * 8, p->y + 40, (p->x + p->w) * 8 - 1, p->y + p->h - 17);
}
