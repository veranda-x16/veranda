/* Veranda shell: a window's bars (overlay 9 with tiles.c; Veranda Look 2,
   DECISIONS V77): the sidebar, the status bar, the shadow, the colours of
   a window's chrome, the zoom box (chrome.c has the rest: the title
   band, the toolbar, what a press is). */
#include <veranda.h>
#include <string.h>
#include <theme.h>
#include "shell.h"
#include "winp.h"
#include "tiles.h"
#pragma code-name ("OVERLAY9")

/* the shadow's colour (V126): the ink in light mode (a dialog box's
   shadow is solid ink), the darkest entry in dark mode */
#define SHADE   (theme.dark ? SKY : INK)

static unsigned char lower(unsigned char c)
{
    return c >= 'A' && c <= 'Z' ? c + 32 : c;
}

/* the place whose folder is p's first n characters, $FF none */
static unsigned char placeOf(const char *p, unsigned char n)
{
    unsigned char i, k;
    const char *q;
    for (i = 0; i < NPLACES; ++i) {
        q = i == 5 && trash[0] ? trash : placePath[i];
        for (k = 0; k < n && q[k] && lower(q[k]) == lower(p[k]); ++k)
            ;
        if (k == n && !q[k])
            return i;
    }
    return 0xFF;
}

static unsigned char side(unsigned char w)
{
    return wins[w].w >= SIDEMIN;
}

static unsigned int width(const char *s)
{
    unsigned int w = 0;
    while (*s)
        w += GetCharWidth(*s++);
    return w;
}

static void put(const char *s, unsigned int x, unsigned int y)
{
    WPutString((void *)s, x, y + baselineOffset);
}

/*---------------------------------------------------------------- the sidebar */

/* place i's card row in window w's sidebar, 0 if it does not fit (the
   devices: the card, the printer (6), the trash (5): V151) */
static unsigned char placeRow(unsigned char w, unsigned char i)
{
    unsigned char y;
    if (i >= 5)
        i ^= 3;
    y = (T(w) + CTOP) / 8 + 2 + 2 * i + (i >= 4 ? 3 : 0);
    return (y + 2) * 8 <= B(w) - STATH + 1 ? y : 0;
}

/* place i's tile (its small icon: V151) */
static unsigned char placeTile(unsigned char i)
{
    return TL_BUILT + (i < 4 ? T_FOLDER : i == 4 ? T_CARD : i == 5 ? T_TRASH : T_PRINTER);
}

static unsigned char shownPlace(unsigned char w)
{
    struct win *p = &wins[w];
    return placeOf(p->path, strlen(p->path));
}

/* the sidebar (chrome_draw) */
void bars_sidebar(unsigned char w)
{
    unsigned int l = L(w), y0 = T(w) + CTOP, sx = l + SIDEW * 8 - 1;
    unsigned char i, y, sel = shownPlace(w);
    WVerticalLine(0xFF, sx, y0, B(w) - STATH);
    UseFont(fontSmall);                 /* (the headings in Gate Sans 9 bold: V151) */
    currentMode = SET_BOLD;
    put(sPlaces, l + 8, y0 + 5);
    if ((y = placeRow(w, 4)) != 0)
        put(sDevices, l + 8, y * 8 - 15);
    UseFont(FONT_UI);
    for (i = 0; i < NPLACES; ++i) {
        y = placeRow(w, i);
        if (!y)
            continue;
        if (!ic3On || !XCALL(bLook3, ic3_small, FSMALL)((l >> 3) + 1, y * 8, 2, placeTile(i), 1))
            XCALL(bTile, mini_draw, void (*)(unsigned int, unsigned int, unsigned char))(l + 8, y * 8 + 3, placeMini[i]);
        currentMode = i == sel ? SET_BOLD : 0;
        put(placeName[i], l + 28, y * 8 + 2);
    }
    currentMode = 0;
    UseSystemFont();
}

/*---------------------------------------------------------------- the status bar */

static char *dec(char *o, unsigned long n)
{
    num(n, o);
    return o + strlen(o);
}

void chrome_status(unsigned char w)
{
    struct win *p = &wins[w];
    unsigned int l = L(w), r = R(w), b = B(w), sy = b - STATH + 1, tx, ty;
    char *o;
    SetPattern(0);
    WRectangle(l + 1, sy + 1, r - 1, b - 1);
    WHorizontalLine(0xFF, l, r, sy);
    /* the resize grip */
    WDrawLine(DRAW_INK, r - 10, b - 2, r - 2, b - 10);
    WDrawLine(DRAW_INK, r - 6, b - 2, r - 2, b - 6);
    UseFont(fontSmall);                 /* (Gate Sans 9, its letters in the middle: V132) */
    ty = sy + (fontSmall == FONT_UI ? 2 : 4);
    tx = l + (side(w) ? SIDEW * 8 : 0) + 6;
    o = dec(msg, p->nfiles);
    strcpy(o, p->nfiles == 1 ? " item, " : " items, ");
    o += strlen(o);
    *o++ = p->sel != 0xFF && !(p->sel == 0 && p->path[1]) ? '1' : '0';
    strcpy(o, " selected");
    put(msg, tx, ty);
    tx += width(msg) + 16;
    if (w == front)
        XCALL(bFiles, files_title, void (*)(unsigned int, unsigned int))(tx, ty);
    if (cardFree != 0xFFFFFFFFUL && r - l > 360) {
        if (cardFree >= 10UL << 20) {
            o = dec(str, cardFree >> 20);
            strcpy(o, " MB free");
        } else {
            o = dec(str, cardFree >> 10);
            strcpy(o, " KB free");
        }
        put(str, r - 18 - width(str), ty);
    }
    UseSystemFont();
    if (guiOn)
        XCALL(bWall, gui_ink, FBB)(w, 2);   /* its corners (V102) */
}


/* (V151) the soft shadow's ink in sl, st, sr, sb: cleared; on the window
   behind, in light mode, a 50 % dither (its cards keep their colours) */
#pragma bss-name (push, "OVL9BSS")
static unsigned int sl, st, sr, sb;
#pragma bss-name (pop)

static void rect(unsigned char pat)
{
    if (sl <= sr && st <= sb) {
        SetPattern(pat);
        WRectangle(sl, st, sr, sb);
    }
}

static void soft(unsigned char v)
{
    struct win *q = &wins[v ^ 1];
    unsigned int a;
    if (sr >= SW)
        sr = SW - 1;
    if (sb >= SH)
        sb = SH - 1;
    if (!shell_seen(sl, st, sr, sb))
        return;
    rect(0);
    if (v != front || !q->open || theme.dark)
        return;
    a = q->x * 8;
    if (sl < a)
        sl = a;
    a += q->w * 8 - 1;
    if (sr > a)
        sr = a;
    if (st < q->y)
        st = q->y;
    a = q->y + q->h - 1;
    if (sb > a)
        sb = a;
    rect(2);
}

void chrome_shadow(unsigned char w)
{
    /* (V126) one card right and below, card-aligned: its ink cleared, its
       cards in the shadow's colour (chrome_colours), so no card holds part
       window, part shadow; Classic (no colours): the 4-pixel ink dither */
    unsigned int r = R(w), b = B(w), rs = RS(w), bs = BS(w), t = T(w) + 8, l = L(w) + 8;
    if (ic3On) {                        /* (V151) 3 pixels, soft: on the plain tile desktop */
        sl = r + 1;
        st = t - 5;
        sr = r + 3;
        sb = b + 3;
        soft(w);
        sl = l - 5;
        st = b + 1;
        sr = r;
        sb = b + 3;
        soft(w);
        return;
    }
    if (lookNone) {
        SetPattern(2);
        if (rs > r + 4)
            rs = r + 4;
        if (bs > b + 4)
            bs = b + 4;
        t -= 2;
        l -= 2;
    } else
        SetPattern(0);
    if (rs > r && shell_seen(r + 1, t, rs, bs))
        WRectangle(r + 1, t, rs, bs);
    if (bs > b && shell_seen(l, b + 1, rs, bs))
        WRectangle(l, b + 1, rs, bs);
}

void chrome_colours(unsigned char w)
{
    struct win *p = &wins[w];
    unsigned char x = p->x, cw = p->w, y = p->y >> 3, h = p->h >> 3, i, r;
    unsigned char sel = theme.hilite ? theme.hilite : SELECT;
    if (ic3Now != (0x80 | (w + 1)))     /* (V165: its icons drawn in colour already, win.c) */
        look_rect(x, cw, y, h, 0);
    look_rect(x, cw, y, 2, w == front ? theme.accent : CHROME);
    look_rect(x, cw, y + 2, 3, CHROME);   /* (the toolbar: the view's toggle and the
                                             search field have no colour of their own,
                                             chrome.c: V156) */
    if (side(w)) {                      /* (Look 3: the paper, the small icons, the
                                           selection right of them: V151) */
        look_rect(x, SIDEW, y + 5, h - 7, ic3On ? 0 : SIDEBAR);
        i = shownPlace(w);
        if (i != 0xFF && (i = placeRow(w, i)) != 0)
            look_rect(ic3On ? x + 3 : x, ic3On ? SIDEW - 3 : SIDEW, i, 2, sel);
        for (i = 0; ic3On && i < NPLACES; ++i)
            if ((r = placeRow(w, i)) != 0 && (!colClip || (r <= colY1 && r + 1 >= colY0 && x + 1 <= colX1 && x + 2 >= colX0)))
                XCALL(bLook3, ic3_small, FSMALL)(x + 1, r * 8, 2, placeTile(i), 0);
    }
    look_rect(x, cw, y + h - 2, 2, CHROME);
    if (!(found_on && w == front)       /* the scroll bar (chrome.c: V151) */
        && (!colClip || (colX1 >= x + cw - 2 && colY1 >= y + 5 && colY0 <= y + h - 3)))
        XCALL(bChrome, chrome_sbcol, FB)(w);
    if (ic3On)                          /* the shadow: soft (V151), else a card (V126) */
        XCALL(bOps, win_shcol, FB)(w);
    else {
        look_rect(x + cw, 1, y + 1, h, SHADE);
        look_rect(x + 1, cw, y + h, 1, SHADE);
    }
    if (guiOn)
        XCALL(bWall, gui_win, FB)(w);       /* the gradient, the corners (V102) */
}

/*---------------------------------------------------------------- the zoom box */

/* the window as large as the desktop beside its icons, and
   back to where it was */
static void win_zoom_(unsigned char w)
{
    struct win *p = &wins[w];
    unsigned int l = L(w), t = T(w), r = RS(w), b = BS(w);
    unsigned char zx = p->x, zw = p->w;
    unsigned int zy = p->y, zh = p->h;
    if (p->zw) {
        p->x = p->zx;
        p->w = p->zw;
        p->y = p->zy;
        p->h = p->zh;
        p->zw = 0;
    } else {
        p->x = SW > 320 ? 1 : 0;
        p->w = deskX - p->x - 1;
        p->y = SH > 240 ? 24 : 16;
        p->h = SH - p->y - 8;
        p->zx = zx, p->zw = zw, p->zy = zy, p->zh = zh;
    }
    XCALL(bWin, win_clamp, FB)(w);
    if (L(w) < l)
        l = L(w);
    if (T(w) < t)
        t = T(w);
    if (RS(w) > r)
        r = RS(w);
    if (BS(w) > b)
        b = BS(w);
    if (w)
        deskDirty = 1;
    XCALL(bWin, win_repaint, void (*)(unsigned int, unsigned int, unsigned int, unsigned int))(l, t, r, b);
    strcpy(msg, "SHELL WINDOW ");
    num(w, msg + 13);
    strcat(msg, p->zw ? " ZOOMED " : " UNZOOMED ");
    num(p->w * 8, msg + strlen(msg));
    strcat(msg, " ");
    num(p->h, msg + strlen(msg));
    LogText(msg);
}

void win_zoom(unsigned char w)
{
    unsigned char busy = play_busy;
    play_busy = 1;
    win_zoom_(w);
    play_busy = busy;
}

/* (V161) main.c's idle when look3.c says (ic3Want): bit 0 its talloc
   found no tiles left while drawing: the colour icons' cache started
   again and the whole screen drawn once more, the dock's icons first, so
   what is on the screen is in colour as far as the tiles go (a picture's
   345); bit 2 the cache started again for another desktop (Preferences, a
   video mode): the dock's own icons read again (their files), drawn
   again; bit 1: that drawing itself (not again). (V165) Bit 0 is no
   longer set (look3.c evicts what the screen does not show instead); bit
   3: the window behind gave its page's tiles to the front window's, the
   dock's or the desktop's icons: it is drawn again (its icons from what is
   left, else Look 2's tiles) */
void ic3_idle(void)
{
    unsigned char w = ic3Want;
    ic3Want = 0;
    if ((w & 8) && front < NWIN)        /* (V165) the window behind gave its icons to the */
        XCALL(bWin, win_redraw, FB)(front ^ 1);    /* front's: drawn again */
    if ((w & 2) || !(w & 5))
        return;
    if (w & 1)
        XCALL(bLook3, ic3_flush, FV)();
    ic3Want = 2;
    XCALL(bDir, pins_icons, FV)();
    XCALL(bWin, win_all, FV)();
}
