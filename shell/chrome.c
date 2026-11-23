/* Veranda shell: a window's chrome (overlay 8; Veranda Look 2, DECISIONS
   V77).

   A window, from its top (its cards: x and width in cards, y and height
   in multiples of 8, so every band is whole cards and takes one colour):
   - the title band (16 rows, the theme's accent; chrome for the window
     behind): the folder's name centred, bold in front; minimise, zoom
     and close at the right, as glyphs;
   - the toolbar (24 rows, chrome): back and forward, the path as a
     breadcrumb (each crumb a folder to go to), the icons and list
     toggle (the view shown on the selection colour), the search field
     (2 card rows of the paper; the windows at least 44 cards wide);
   - the body: the sidebar (12 cards of the sidebar colour, in a window
     at least SIDEMIN cards wide): the places (Veranda, Apps, Documents,
     Mods; the card and the trash under "devices"), the one shown on the
     selection colour; the contents (view.c);
   - the status bar (16 rows, chrome): the page (when there are several:
     the arrows at the left go to the one before and after), the items
     and the selection, the card's free space, the resize grip;
   - the shadow: an ink dither 4 pixels wide, right and below.
   The colours are cards of the colour map (ColorRect); the ink is the
   one ink. The Classic theme has no colours: the toggle shown inverted,
   the place in bold. */
#include <veranda.h>
#include <string.h>
#include <theme.h>
#include "shell.h"
#include "winp.h"
#include "tiles.h"
#pragma code-name ("OVERLAY8")
#pragma bss-name ("OVL8BSS")

#define NCRUMB 8
static unsigned int crumbX[NWIN][NCRUMB];       /* each crumb's right end */
static unsigned char crumbLen[NWIN][NCRUMB];    /* the path's characters up to it */
static unsigned char ncrumb[NWIN];

#pragma bss-name ("BSS")

const char *const placeName[NPLACES] = {
    "Veranda", "Apps", "Documents", "Mods", "SD card", "Trash", "Printer"
};
/* the Mods place's folder (V84: File > Set as Mods folder; dir.c reads
   and writes MODS.CFG) */
char modsDir[PATHMAX + 1] = "/MODS";
const char *const placePath[NPLACES] = {
    VR_SYSDIR, VR_APPSDIR, VR_DOCSDIR, modsDir, "/", VR_TRASHDIR, ""
};
const unsigned char placeMini[NPLACES] = { M_HOME, M_APPS, M_DOC, M_NOTE, M_CARD, M_TRASH, M_DOC };
const char sPlaces[] = "Places";
const char sDevices[] = "Devices";
static const char sSearch[] = "Search";

const char *chrome_place(unsigned char i)
{
    return i == 5 && trash[0] ? trash : placePath[i];
}

#pragma rodata-name (push, "OVL8RO")
static const char noMods[] = "There is no Mods folder.";
static const char noOpen[] = "Cannot open the folder.";
static const char sPrint[] = "Drop a picture on the printer to print it to a PDF.";
static const unsigned char navs[96] = {      /* back and forward: rounded boxes, chevrons */
    0x3F, 0xFF, 0xC0, 0x3F, 0xFF, 0xC0,
    0x40, 0x00, 0x20, 0x40, 0x00, 0x20,
    0x80, 0x0C, 0x10, 0x81, 0x80, 0x10,
    0x80, 0x18, 0x10, 0x80, 0xC0, 0x10,
    0x80, 0x30, 0x10, 0x80, 0x60, 0x10,
    0x80, 0x60, 0x10, 0x80, 0x30, 0x10,
    0x80, 0xC0, 0x10, 0x80, 0x18, 0x10,
    0x81, 0x80, 0x10, 0x80, 0x0C, 0x10,
    0x80, 0xC0, 0x10, 0x80, 0x18, 0x10,
    0x80, 0x60, 0x10, 0x80, 0x30, 0x10,
    0x80, 0x30, 0x10, 0x80, 0x60, 0x10,
    0x80, 0x18, 0x10, 0x80, 0xC0, 0x10,
    0x80, 0x0C, 0x10, 0x81, 0x80, 0x10,
    0x80, 0x00, 0x10, 0x80, 0x00, 0x10,
    0x40, 0x00, 0x20, 0x40, 0x00, 0x20,
    0x3F, 0xFF, 0xC0, 0x3F, 0xFF, 0xC0 };
static const unsigned char boxes[66] = {      /* minimise, zoom, close; the frame */
    0xFF, 0xE1, 0xFF, 0xC3, 0xFF, 0x81,
    0x80, 0x21, 0x00, 0x42, 0x00, 0x81,
    0x80, 0x21, 0x00, 0x42, 0x00, 0x81,
    0x80, 0x21, 0x3E, 0x42, 0x44, 0x81,
    0x80, 0x21, 0x22, 0x42, 0x28, 0x81,
    0x80, 0x21, 0x22, 0x42, 0x10, 0x81,
    0x80, 0x21, 0x22, 0x42, 0x28, 0x81,
    0x9F, 0x21, 0x3E, 0x42, 0x44, 0x81,
    0x80, 0x21, 0x00, 0x42, 0x00, 0x81,
    0x80, 0x21, 0x00, 0x42, 0x00, 0x81,
    0xFF, 0xE1, 0xFF, 0xC3, 0xFF, 0x81 };
#pragma rodata-name (pop)

/* a place of the sidebar: Veranda, Apps, Documents, Mods, the card, the
   trash (made when missing); in window w (moved here from main.c, V84) */
void chrome_goplace(unsigned char w, unsigned char i)
{
    const char *p;
    if (i == 6) {                       /* the printer (V151) */
        strcpy(msg, sPrint);
        shell_say(msg);
        return;
    }
    if (i == 5) {
        XCALL(bFiles, trash_path, FV)();
        ChDir("/");
        MkDir(trash + 1);
    }
    p = i < 3 ? vr_cd(i == 0 ? VR_SYS : i == 1 ? VR_APPS : VR_DOCS) : chrome_place(i);
    ChDir(curDirName);
    if (strcmp(p, wins[w].path) && !shell_goto(w, p)) {
        strcpy(msg, i == 3 ? noMods : noOpen);
        shell_warn(msg);                /* (below $A000 for the kernel) */
    }
}

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
        q = chrome_place(i);
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

static unsigned char hasSearch(unsigned char w)
{
    return wins[w].w >= 44;
}

/* the toggles' first card */
static unsigned char toggles(unsigned char w)
{
    return wins[w].x + wins[w].w - (hasSearch(w) ? 22 : 7);
}

static unsigned int width(const char *s)
{
    unsigned int w = 0;
    while (*s)
        w += GetCharWidth(*s++);
    return w;
}

/* s cut to fit in w pixels (with "..." when cut); its width */
static unsigned int fit(char *s, unsigned int w)
{
    unsigned char l, c;
    unsigned int x = 0;
    for (l = 0; (c = s[l]) != 0; ++l) {
        c = GetCharWidth(c);
        if (x + c > w)
            break;
        x += c;
    }
    if (!s[l])
        return x;
    while (l && x + 3 * GetCharWidth('.') > w)
        x -= GetCharWidth(s[--l]);
    strcpy(s + l, "...");
    return x + 3 * GetCharWidth('.');
}

static void put(const char *s, unsigned int x, unsigned int y)
{
    WPutString((void *)s, x, y + baselineOffset);
}

static void bold(const char *s, unsigned int x, unsigned int y)
{
    currentMode = SET_BOLD;
    put(s, x, y);
    currentMode = 0;
}

static unsigned int boldW(const char *s)
{
    return width(s) + strlen(s);
}

/* the name of the folder p's first n characters: a place's, or its own */
static void nameOf(const char *p, unsigned char n, char *out)
{
    unsigned char i = placeOf(p, n), k;
    if (i != 0xFF) {
        strcpy(out, placeName[i]);
        return;
    }
    for (k = n; k && p[k - 1] != '/'; --k)
        ;
    memcpy(out, p + k, n - k);
    out[n - k] = 0;
}

/*---------------------------------------------------------------- the title band */

void chrome_title(unsigned char w)
{
    unsigned int l = L(w), r = R(w), t = T(w), bx, tw, mx;
    struct win *p = &wins[w];
    SetPattern(0);
    WRectangle(l + 1, t + 1, r - 1, t + TITLEH - 2);
    WHorizontalLine(0xFF, l, r, t + TITLEH - 1);
    /* minimise, zoom, close: three square boxes of 11, 15 apart (Look 3,
       V151): one bitmap, the window's frame its last column */
    memcpy(tileBuf, boxes, sizeof boxes);
    WBitmapUp(tileBuf, wins[w].x + wins[w].w - 6, 6, t + 2, 0x8000 | 11);
    /* the name */
    UseFont(FONT_UI);
    nameOf(p->path, strlen(p->path), str);
    mx = r - l > 120 ? r - l - 120 : 8;
    tw = fit(str, mx);
    if (w == front)
        bold(str, (l + r - tw - strlen(str)) / 2, t + 2);
    else
        put(str, (l + r - tw) / 2, t + 2);
    UseSystemFont();
    if (guiOn)
        XCALL(bWall, gui_ink, FBB)(w, 1);   /* its corners (V102) */
}

/*---------------------------------------------------------------- the toolbar */

static void crumbs(unsigned char w, unsigned int y0, unsigned int xmax)
{
    struct win *p = &wins[w];
    unsigned int x = L(w) + 62, tw;
    unsigned char n = 0, i = 0, l = strlen(p->path), last;
    UseFont(FONT_UI);
    for (;;) {
        /* the crumb up to i (the root: 1) */
        if (i == 0)
            i = 1;
        else {
            while (i < l && p->path[i] != '/')
                ++i;
        }
        last = i >= l;
        nameOf(p->path, i, str);
        if (!str[0])
            strcpy(str, placeName[4]);
        tw = (last ? boldW(str) : width(str));
        if (x + tw > xmax) {
            tw = fit(str, xmax > x + 8 ? xmax - x - 8 : 0);
            last = 1;
        }
        if (last)
            bold(str, x, y0 + 6);
        else
            put(str, x, y0 + 6);
        x += tw;
        crumbX[w][n] = x + 6;
        crumbLen[w][n++] = i;
        if (last || n >= NCRUMB)
            break;
        WDrawLine(DRAW_INK, x + 5, y0 + 9, x + 8, y0 + 12);
        WDrawLine(DRAW_INK, x + 8, y0 + 12, x + 5, y0 + 15);
        x += 14;
        ++i;
    }
    ncrumb[w] = n;
    UseSystemFont();
}

/* the icons and list toggles (V156: also alone, when the view changes:
   win.c's win_view) */
void chrome_toggles(unsigned char w)
{
    struct win *p = &wins[w];
    unsigned int y0 = T(w) + TITLEH, bx, by;
    unsigned char vx = toggles(w), i, a, b;
    SetPattern(0);
    WRectangle(vx * 8, y0 + 3, (vx + 6) * 8 - 1, y0 + 20);
    SetPattern(1);
    for (i = 0; i < 2; ++i) {
        bx = (vx + i * 3) * 8 + 6;
        by = y0 + 6;
        if (!i) {
            for (a = 0; a < 8; a += 7)
                for (b = 0; b < 8; b += 7)
                    WRectangle(bx + a, by + b, bx + a + 4, by + b + 4);
        } else
            for (b = 0; b < 9; b += 4) {
                WRectangle(bx, by + b + 1, bx + 1, by + b + 2);
                WRectangle(bx + 3, by + b + 1, bx + 11, by + b + 2);
            }
    }
    WFrameRectangle(0xFF, vx * 8, y0 + 3, (vx + 6) * 8 - 1, y0 + 20);
    WVerticalLine(0xFF, (vx + 3) * 8, y0 + 3, y0 + 20);
    /* the view shown: inverted inside its frame (V156: the selection's
       colour was whole cards, the toolbar's 3 card rows, so it spilled
       above and below the frame, which is not on the cards' grid) */
    if (p->view == V_ICON || p->view == V_LIST) {
        bx = (vx + (p->view == V_LIST ? 3 : 0)) * 8;
        WInvertRectangle(bx + 1, y0 + 4, bx + 23, y0 + 19);
    }
}

static void toolbar(unsigned char w)
{
    struct win *p = &wins[w];
    unsigned int l = L(w), r = R(w), y0 = T(w) + TITLEH, x0;
    SetPattern(0);
    WRectangle(l + 1, y0, r - 1, y0 + TOOLH - 2);
    WHorizontalLine(0xFF, l, r, y0 + TOOLH - 1);
    memcpy(tileBuf, navs, sizeof navs);         /* (Look 3: framed, one bitmap: V151) */
    WBitmapUp(tileBuf, p->x + 1, 6, y0 + 4, 0x8000 | 16);
    crumbs(w, y0, toggles(w) * 8 - 8);
    chrome_toggles(w);
    /* the search field: on the chrome, as high as the toggles (V156: its
       paper was 2 whole card rows round a rounded frame, showing outside
       it at the corners, above and below) */
    if (hasSearch(w)) {
        x0 = (p->x + p->w - 15) * 8;
        shell_rframe(x0, y0 + 3, x0 + 103, y0 + 20, 6);
        shell_rframe(x0 + 6, y0 + 7, x0 + 12, y0 + 13, 3);
        WDrawLine(DRAW_INK, x0 + 11, y0 + 13, x0 + 14, y0 + 16);
        if (p->find[0]) {
            UseFont(FONT_UI);
            strcpy(str, p->find);
            fit(str, 80);
            put(str, x0 + 19, y0 + 5);
            UseSystemFont();
        } else
            put(sSearch, x0 + 19, y0 + 7);
    }
}

/*---------------------------------------------------------------- the window */

/* (the scene: with the kernel's clip on, only the bands that meet it,
   DECISIONS V81) */
void chrome_draw(unsigned char w)
{
    unsigned int l = L(w), t = T(w), r = R(w), b = B(w);
    WFrameRectangle(0xFF, l, t, r, b);
    if (shell_seen(l, t, r, t + TITLEH - 1))
        chrome_title(w);
    if (shell_seen(l, t + TITLEH, r, t + CTOP - 1))
        toolbar(w);
    if (side(w) && shell_seen(l, t + CTOP, l + SIDEW * 8 - 1, b - STATH))
        XCALL(bBars, bars_sidebar, FB)(w);
}

/*---------------------------------------------------------------- the scroll bar */

/* (Look 3, V151) the body's right 2 cards, from the toolbar to the status
   bar: an arrow box at each end (2 card rows: a row of cells up, down),
   the track (dotted: a page up, down) and the thumb (whole cards of the
   paper, framed, a grip of three lines: where the shown rows are among
   all, as tall as their share; none when all show). Its lines: the
   cells' rows (the list: entries; view.c's vCols, vRows) */
#define TRACKP  31              /* the track's pattern: light dots */

#pragma bss-name (push, "OVL8BSS")
static unsigned int sx, sr, st, sb;             /* its left line, right, top, bottom (pixels) */
static unsigned char sbT, sbN, thY, thN;        /* the track's first card row, its cards; the thumb's (thN 0: none) */
static unsigned char sbL, sbV, sbC, sbF;        /* the lines, those shown, cells a line, the first shown */
#pragma bss-name (pop)

#pragma static-locals (push, on)

static void sbGeom(unsigned char w)
{
    struct win *p = &wins[w];
    XCALL(bView, view_per, RB)(w);
    sbC = vCols;
    sbV = vRows;
    sbL = (p->n + sbC - 1) / sbC;
    sbF = p->first / sbC;
    sr = (p->x + p->w) * 8 - 2;
    sx = sr - 14;
    st = p->y + CTOP;
    sb = st + p->h - CTOP - STATH - 1;
    sbT = (st >> 3) + 2;
    sbN = (sb >> 3) - 1 - sbT;
    thN = 0;
    if (sbL > sbV && sbN >= 2) {
        thN = (unsigned int)sbN * sbV / sbL;
        if (thN < 2)
            thN = 2;
        if (sbF > sbL - sbV)
            sbF = sbL - sbV;
        thY = sbT + (unsigned int)(sbN - thN) * sbF / (sbL - sbV);
    }
}

static void hline(unsigned int x0, unsigned int x1, unsigned int y)
{
    WHorizontalLine(0xFF, x0, x1, y);
}

/* its ink (the contents' clear took the inside: view.c, the scene; w +
   $80: the thumb erased, + $40: the thumb alone: a row scrolled); on the
   tile desktop the track is tiles (chrome_sbcol), else dots of the ink */
void chrome_sbar(unsigned char w)
{
    unsigned int y;
    unsigned char k;
    sbGeom(w & 0x3F);
    if (w & 0x80) {
        if (thN) {
            y = thY * 8;
            SetPattern(guiOn ? 0 : TRACKP);
            WRectangle(sx + 1, y, sr, y + thN * 8 - 1);
        }
        return;
    }
    if (w & 0x40)
        goto thumb;
    WVerticalLine(0xFF, sx, st, sb);
    hline(sx, sr, st + 15);
    hline(sx, sr, sb - 15);
    for (k = 0; k < 4; ++k) {
        hline(sx + 8 - k, sx + 8 + k, st + 6 + k);
        hline(sx + 8 - k, sx + 8 + k, sb - 6 - k);
    }
    if (!guiOn) {
        SetPattern(TRACKP);
        WRectangle(sx + 1, st + 16, sr, sb - 16);
    }
thumb:
    if (thN) {
        y = thY * 8;
        if (!guiOn) {
            SetPattern(0);
            WRectangle(sx + 1, y, sr, y + thN * 8 - 1);
        }
        hline(sx, sr, y);
        hline(sx, sr, y + thN * 8 - 1);
        y += thN * 4 - 3;
        for (k = 0; k < 9; k += 3)
            hline(sx + 4, sx + 11, y + k);
    }
}

#define VREG(a) (*(volatile unsigned char *)(a))
#define TRACKT  991             /* (the chrome pool's last tile: look3.c gives out to 990) */

/* its colours: the arrow boxes the chrome, the thumb the paper, the track
   on the tile desktop tile TRACKT (the paper and the chrome, a pixel
   each: dots; look3.c's ic3_reset writes it), else the chrome */
#pragma bss-name (push, "OVL8BSS")
static unsigned char x0, x1, y0, y1;
#pragma bss-name (pop)

void chrome_sbcol(unsigned char w)
{
    unsigned char x, y, k, a, t, h;
    sbGeom(w);
    x = sx >> 3;
    if (!guiOn) {
        look_rect(x, 2, st >> 3, (sb >> 3) - (st >> 3) + 1, CHROME);
        if (thN)
            look_rect(x, 2, thY, thN, 0);
        return;
    }
    y0 = st >> 3;                       /* (tile mode: the map entries, ColorRect's */
    y1 = (sb >> 3) + 1;                 /* solid tile c in row 0 or the track's) */
    x0 = x;
    x1 = x + 2;
    if (colClip) {
        if (y0 < colY0)
            y0 = colY0;
        if (y1 > colY1 + 1)
            y1 = colY1 + 1;
        if (x0 < colX0)
            x0 = colX0;
        if (x1 > colX1 + 1)
            x1 = colX1 + 1;
    }
    VREG(0x9F25) = 0;
    VREG(0x9F20) = 0;                   /* (the covers in place: VRAM_TILECOV $1EB00) */
    VREG(0x9F21) = 0xEB;
    VREG(0x9F22) = 1;
    a = VREG(0x9F23);
    for (y = y0; y < y1; ++y) {
        t = CHROME;
        h = 0;
        if (y >= sbT && y < sbT + sbN) {
            t = TRACKT & 0xFF;
            h = TRACKT >> 8;
            if (y >= thY && y < thY + thN)
                t = h = 0;
        }
        if (!a) {                       /* (none: the row's entries at once) */
            VREG(0x9F20) = x0 << 1;
            VREG(0x9F21) = 0xAC + y;
            VREG(0x9F22) = 0x11;
            for (k = x0; k < x1; ++k) {
                VREG(0x9F23) = t;
                VREG(0x9F23) = h;
            }
            continue;
        }
        for (k = x0; k < x1; ++k) {
            VREG(0x9F20) = (k << 1) + 1;
            VREG(0x9F21) = 0xAC + y;
            VREG(0x9F22) = 1;
            if (VREG(0x9F23) >= 0xE0)       /* (covered: kept) */
                continue;
            VREG(0x9F20) = k << 1;
            VREG(0x9F22) = 0x11;
            VREG(0x9F23) = t;
            VREG(0x9F23) = h;
        }
    }
}

#pragma static-locals (pop)

/* what a press at x, y is on window w's scroll bar */
unsigned char chrome_sbhit(unsigned char w, unsigned int x, unsigned int y)
{
    sbGeom(w);
    if (x < sx || y < st || y > sb)
        return 0xFF;
    if (y < st + 16)
        return 0xFD;
    if (y > sb - 16)
        return 0xFC;
    if (!thN)
        return 0xF8;
    vx = thY * 8;                       /* (the thumb: mouse.c drags it) */
    vy = thN * 8;
    y >>= 3;
    return y < thY ? 0xFB : y >= thY + thN ? 0xFA : 0xF9;
}

/* the thumb let go with its top at y: the rows that place shows */
void chrome_sbto(unsigned char w, unsigned int y)
{
    unsigned int r;
    sbGeom(w);
    if (!thN)
        return;
    r = (sbN - thN) * 8;
    y -= sbT * 8;
    vx = (unsigned int)(((unsigned long)y * (sbL - sbV) + r / 2) / r) * sbC;
    XCALL(bView, view_page, FBB)(w, 0);
}

/*---------------------------------------------------------------- presses */

/* place i's card row in window w's sidebar, 0 if it does not fit (as
   bars.c draws it) */
static unsigned char placeRow(unsigned char w, unsigned char i)
{
    unsigned char y;
    if (i >= 5)                         /* (the card, the printer, the trash: V151) */
        i ^= 3;
    y = (T(w) + CTOP) / 8 + 2 + 2 * i + (i >= 4 ? 3 : 0);
    return (y + 2) * 8 <= B(w) - STATH + 1 ? y : 0;
}

unsigned char chrome_hit(unsigned char w, unsigned int x, unsigned int y)
{
    unsigned int l = L(w), r = R(w), t = T(w), b = B(w), vx;
    unsigned char i, pg;
    if (y < t + TITLEH)
        return x >= r - 18 ? H_CLOSE : x >= r - 33 ? H_ZOOM : x >= r - 48 ? H_MIN : H_TITLE;
    if (y < t + CTOP) {
        vx = toggles(w) * 8;
        if (x >= l + 6 && x <= l + 29)
            return H_BACK;
        if (x >= l + 30 && x <= l + 53)
            return H_FWD;
        if (x >= vx && x < vx + 48 && y >= t + TITLEH + 3 && y <= t + TITLEH + 20)
            return x < vx + 24 ? H_ICONS : H_LIST;
        if (hasSearch(w) && x >= (wins[w].x + wins[w].w - 15) * 8 && x < (wins[w].x + wins[w].w - 2) * 8)
            return H_SEARCH;
        if (x >= l + 62)
            for (i = 0; i < ncrumb[w]; ++i)
                if (x < crumbX[w][i])
                    return H_CRUMB + i;
        return H_NONE;
    }
    if (y > b - STATH) {
        return x >= r - 15 ? H_SIZE : H_NONE;
    }
    if (side(w) && x < l + SIDEW * 8) {
        for (i = 0; i < NPLACES; ++i)
            if ((pg = placeRow(w, i)) != 0 && y >= pg * 8 && y < pg * 8 + 16)
                return H_PLACE + i;
        return H_NONE;
    }
    return H_BODY;
}

/* the crumb's path length (mouse.c, through the press) */
unsigned char chrome_crumb(unsigned char w, unsigned char i)
{
    return crumbLen[w][i];
}
