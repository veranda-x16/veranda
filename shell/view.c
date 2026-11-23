/* Veranda shell: a window's contents (overlay 2; DECISIONS V70; Veranda
   Look 2, V77).

   The contents are the window's body right of the sidebar, in cards
   (the colour map's), each view its own (the toolbar's toggle, the view
   menu):
   - icons: cells of 9 x 9 cards: the tile (4 x 4 cards, 2 in) and the
     name under it, centred on the 9 cards (cut with "..."); as many
     columns and rows as the window holds; pages of them. The selection:
     the name's cards in the selection colour and a rounded ring round
     the tile;
   - small icons: cells of 20 x 2 cards, a small glyph and the name;
   - the list: a header (name, size, modified, kind: a click sorts by
     that column, the sorted one underlined), then a row of 2 cards an
     entry, every other row striped (the sidebar colour), the selected
     one in the selection colour, its name bold; a kind badge (2 cards
     of the entry's colour, a small glyph) before the name; a scroll bar
     at the right when there are more rows than fit (its arrows a row,
     the track a page).
   Without colours (the Classic theme) the selection is inverted. */
#include <veranda.h>
#include <string.h>
#include <theme.h>
#include "shell.h"
#include "tiles.h"
#pragma code-name ("OVERLAY2")


#define CTOP    40
#define STATH   16
#define SIDEW   12
#define SIDEMIN 40
#define SBW     16              /* the scroll bar (bars.c: Look 3, V151) */

unsigned int vx, vy;

static unsigned int l0, t0, r0_, b0;    /* the content area */
static unsigned char vcAll;             /* (view_colours: the paper's rows too) */
static unsigned char cols, rows, ccx, ccw, brow;

/* the geometry of window w's contents */
static void geom(unsigned char w)
{
    struct win *p = &wins[w];
    unsigned char s = p->w >= SIDEMIN ? SIDEW : 0, br;
    ccx = p->x + s;
    ccw = p->w - s - SBW / 8;          /* (the scroll bar's 2 cards not the contents': V151) */
    l0 = ccx * 8 + (s ? 0 : 1);
    r0_ = (p->x + p->w) * 8 - 1 - SBW;
    t0 = p->y + CTOP;
    b0 = p->y + p->h - 1 - STATH;
    brow = t0 >> 3;
    br = (p->h - CTOP - STATH) >> 3;
    switch (p->view) {
    case V_ICON:
        cols = (ccw - 1) / 9;
        rows = br >= 8 ? (br - 8) / 9 + 1 : 1;    /* (a label's second line: V132) */
        break;
    case V_SMALL:
        cols = (ccw - 1) / 20;
        rows = (br - 1) / 2;
        break;
    default:
        cols = 1;
        rows = (br - 2) / 2;
    }
    if (!cols)
        cols = 1;
    vCols = cols;
    vRows = rows;
}

unsigned char view_per(unsigned char w)
{
    geom(w);
    return cols * rows;
}

/* slot s (on the page) -> vx, vy: its cell's corner (card aligned) */
static void slot(unsigned char w, unsigned char s)
{
    switch (wins[w].view) {
    case V_ICON:
        vx = (ccx + 1 + (s % cols) * 9) * 8;
        vy = (brow + 1 + (s / cols) * 9) * 8;
        break;
    case V_SMALL:
        vx = (ccx + 1 + (s % cols) * 20) * 8;
        vy = (brow + 1 + (s / cols) * 2) * 8;
        break;
    default:
        vx = ccx * 8;
        vy = (brow + 2 + s * 2) * 8;
    }
}

/* selection s (an order index) of window w: its cell's corner, or vx $FFFF */
void view_cell(unsigned char w, unsigned char s)
{
    struct win *p = &wins[w];
    geom(w);
    vx = 0xFFFF;
    if (s == 0xFF || s < p->first || s >= p->first + cols * rows)
        return;
    slot(w, s - p->first);
}

static unsigned int width(const char *s)
{
    unsigned int w = 0;
    while (*s)
        w += GetCharWidth(*s++);
    return w;
}

/* s cut to fit in w pixels, "..." where cut; its width */
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

static unsigned char tileOf(void)
{
    if (E.tile)
        return E.tile;
    return TL_BUILT + (E.type == 'D' ? T_FOLDER : E.type == 'U' ? T_UP : T_DOCUMENT);
}

static unsigned char upper(unsigned char c)
{
    return c >= 'a' && c <= 'z' ? c - 32 : c;
}

/* the entry's kind: its badge's colour and glyph (badgeM) */
static unsigned char badgeM;

static unsigned char badge(unsigned char w)
{
    const char *d;
    unsigned char a, b;
    badgeM = M_DOC;
    if (E.type != 'F') {
        badgeM = M_CARD;
        return YELLOW;
    }
    if (E.geos == APPLICATION || E.geos == DESK_ACC) {
        badgeM = M_APPS;
        return XCALL(bTile, tile_colour, unsigned char (*)(unsigned char, unsigned char))(w, tileOf());
    }
    if (E.geos)
        return CHROME;
    d = strrchr(E.name, '.');
    if (!d)
        return CHROME;
    a = upper(d[1]);
    b = upper(d[2]);
    if ((a == 'M' && b == 'O') || (a == 'X' && b == 'M') || (a == 'S' && b == '3')) {
        badgeM = M_NOTE;
        return PURPLE;
    }
    if (a == 'S' && b == 'I') {
        badgeM = M_NOTE;
        return RED;
    }
    if ((a == 'P' && b == 'N') || (a == 'B' && b == 'M') || (a == 'P' && b == 'C'))
        return ORANGE;
    if ((a == 'C' && b == 'S') || (a == 'X' && b == 'L')) {
        badgeM = M_APPS;
        return GREEN;
    }
    if ((a == 'T' && b == 'X') || (a == 'M' && b == 'D'))
        return CYAN;
    return CHROME;
}

/* the size: "12 KB", "800 B", "--" (a folder) */
static void sizeStr(char *out)
{
    if (E.type != 'F') {
        strcpy(out, "--");
        return;
    }
    if (E.size < 1024) {
        num(E.size, out);
        strcat(out, " B");
        return;
    }
    num((E.size + 1023) >> 10, out);
    strcat(out, " KB");
}

/* the date shown: "16 Nov 2026", "--" */
static void dateShown(char *out)
{
    static const char mon[] = "JanFebMarAprMayJunJulAugSepOctNovDec";
    unsigned char m = E.date[1];
    if (!m || m > 12) {
        strcpy(out, "--");
        return;
    }
    num(E.date[2], out);
    out += strlen(out);
    *out++ = ' ';
    memcpy(out, mon + (m - 1) * 3, 3);
    out[3] = ' ';
    num(1900u + E.date[0], out + 4);
}

/* the list's columns, from the contents' left */
#define C_BADGE 8
#define C_NAME  28              /* (V151: right of the small icon) */
#define C_SIZE  212             /* (its right end) */
#define C_DATE  224
#define C_TYPE  300

/* the icon's label: look3.c (overlay 12, Gate Sans 9 on one or two
   lines: Look 3, V132) */
typedef void (*FLBL)(unsigned int, unsigned int, unsigned char);

/* E's small icon (16 x 16, look3.c: V151) at card cx, line y: its ink
   (ink 1) or its colours; 0: none (Look 2's badge then) */
static unsigned char small(unsigned char w, unsigned char cx, unsigned int y, unsigned char ink)
{
    return XCALL(bLook3, ic3_small, FSMALL)(cx, y, w, tileOf(), ink);
}

static void cell(unsigned char w, unsigned char s, unsigned char idx, unsigned char on)
{
    unsigned int x, y, tw;
    slot(w, s);
    x = vx;
    y = vy;
    ent_get(w, idx);
    switch (wins[w].view) {
    case V_ICON:
        XCALL(bLook3, ic3_draw, unsigned char (*)(unsigned char, unsigned int, unsigned char, unsigned char, unsigned char))
            ((x >> 3) + 2, y, w, tileOf(), E.icon - I_OWN);     /* (a colour icon: V133) */
        if (on)
            shell_rframe(x + 14, y - 2, x + 49, y + 33, 6);
        XCALL(bIc2, lbl_draw, FLBL)(x, y, on);
        break;
    case V_SMALL:
        if (!ic3On || !small(w, x >> 3, y, 1)) {
            badge(w);
            XCALL(bTile, mini_draw, void (*)(unsigned int, unsigned int, unsigned char))(x + 2, y + 3, badgeM);
        }
        shown(&E, str);
        fit(str, 138);
        put(str, x + 20, y + 3);
        if (on && lookNone)
            WInvertRectangle(x, y, x + 159, y + 15);
        break;
    default:
        if (!ic3On || !small(w, (x >> 3) + 1, y, 1)) {
            badge(w);
            XCALL(bTile, mini_draw, void (*)(unsigned int, unsigned int, unsigned char))(x + C_BADGE + 3, y + 3, badgeM);
        }
        tw = r0_;
        shown(&E, str);
        fit(str, (x + C_SIZE - 50 < tw ? C_SIZE - 50 : tw - x) - C_NAME);
        if (on)
            currentMode = SET_BOLD;
        put(str, x + C_NAME, y + 3);
        currentMode = 0;
        UseFont(fontSmall);             /* (the columns in Gate Sans 9: V151) */
        y += fontSmall == FONT_UI ? 3 : 5;
        if (x + C_SIZE < tw) {
            sizeStr(str);
            put(str, x + C_SIZE - width(str), y);
        }
        if (x + C_DATE + 50 < tw) {
            dateShown(str);
            put(str, x + C_DATE, y);
        }
        if (x + C_TYPE + 30 < tw) {
            type_str(&E, str);
            str[0] = upper(str[0]);
            fit(str, tw - x - C_TYPE);
            put(str, x + C_TYPE, y);
        }
        UseFont(FONT_UI);
        y = vy;
        if (on && lookNone)
            WInvertRectangle(l0, y, tw - 1, y + 15);
    }
}

/* the colours of E's row (the list: from card cx, cw cards) or small
   icons' cell at line y: c from its icon's right (the icon's cards its
   own: V151), else c and Look 2's badge (the list's) */
static void rowCol(unsigned char w, unsigned char cx, unsigned int y, unsigned char cw, unsigned char c)
{
    unsigned char l = wins[w].view == V_LIST, k = l ? 3 : 2;
    if (ic3On && small(w, cx + l, y, 0)) {
        look_rect(cx, k, y >> 3, 2, 0);
        look_rect(cx + k, cw - k, y >> 3, 2, c);
        small(w, cx + l, y, 0);
        return;
    }
    look_rect(cx, cw, y >> 3, 2, c);
    if (l)
        look_rect(cx + 1, 2, y >> 3, 2, badge(w));
}

/* cell s (an order index) of window w drawn again, selected or not, and
   its colours */
static void mark(unsigned char w, unsigned char s, unsigned char on)
{
    struct win *p = &wins[w];
    unsigned int x, y;
    unsigned char c;
    view_cell(w, s);
    if (vx == 0xFFFF)
        return;
    x = vx;
    y = vy;
    SetPattern(0);
    switch (p->view) {
    case V_ICON:
        WRectangle(x, y - 2, x + 71, y + 55);
        break;
    case V_SMALL:
        WRectangle(x, y, x + 159, y + 15);
        break;
    default:
        WRectangle(l0, y, r0_, y + 15);
    }
    UseFont(FONT_UI);
    cell(w, s - p->first, p->order[s], on);
    UseSystemFont();
    /* its colours (the window is in front) */
    c = on ? (theme.hilite ? theme.hilite : SELECT) : 0;
    switch (p->view) {
    case V_ICON:
        XCALL(bIc2, lbl_colour, FLBL)(x, y, 0);
        if (on)
            XCALL(bIc2, lbl_colour, FLBL)(x, y, c);
        break;
    case V_SMALL:
        rowCol(w, x >> 3, y, 20, c);
        break;
    default:
        rowCol(w, ccx, y, ccw, on ? c : ((s - p->first) & 1) ? SIDEBAR : 0);
    }
}

static const char *const heads[4] = { "Name", "Size", "Modified", "Kind" };

/* the list's header (Look 3, V151): on the chrome (view_colours), in the
   UI font, the sorted column bold with a small triangle, a line between
   the columns */
static void header(unsigned char w)
{
    struct win *p = &wins[w];
    unsigned int x = ccx * 8, hx, tw = r0_;
    unsigned char i, k;
    UseFont(FONT_UI);
    for (i = 0; i < 4; ++i) {
        currentMode = i == p->sort ? SET_BOLD : 0;
        hx = x + (i == 0 ? C_NAME : i == 1 ? C_SIZE - width(heads[1]) - currentMode / SET_BOLD * 4 : i == 2 ? C_DATE : C_TYPE);
        if (i && hx + 30 > tw)
            break;
        put(heads[i], hx, t0 + 3);
        if (i)
            WVerticalLine(0xFF, i == 1 ? x + C_SIZE - 44 : hx - 6, t0 + 3, t0 + 12);
        if (currentMode) {
            hx = i == 1 ? hx - 11 : hx + width(heads[i]) + strlen(heads[i]) + 4;
            for (k = 0; k < 4; ++k)
                WHorizontalLine(0xFF, hx + k, hx + 6 - k, t0 + 6 + k);
        }
    }
    currentMode = 0;
    UseSystemFont();
    WHorizontalLine(0xFF, l0, r0_, t0 + 15);
}

void view_draw(unsigned char w)
{
    struct win *p = &wins[w];
    unsigned char s, i, per;
    geom(w);
    per = cols * rows;
    if (p->first >= p->n)
        p->first = p->n > per ? p->n - per : 0;
    p->first -= p->first % cols;
    SetPattern(0);
    WRectangle(l0, t0, r0_ + SBW - 1, b0);    /* (the scroll bar's inside too) */
    if (p->view == V_LIST && shell_seen(l0, t0, r0_, t0 + 15))
        header(w);
    if (shell_seen(r0_ + 1, t0, r0_ + SBW, b0))
        XCALL(bChrome, chrome_sbar, FB)(w);
    UseFont(FONT_UI);
    for (s = 0; s < per; ++s) {
        i = p->first + s;
        if (i >= p->n)
            break;
        slot(w, s);             /* (the scene: the cells that meet the clip, V81) */
        if (p->view == V_ICON ? shell_seen(vx, vy - 2, vx + 71, vy + 55)
            : shell_seen(p->view == V_LIST ? l0 : vx, vy, p->view == V_LIST ? r0_ : vx + 159, vy + 15))
            cell(w, s, p->order[i], i == p->sel);
    }
    UseSystemFont();
}

/* window w's contents' colours: the tiles, the selection, the list's
   stripes and badges (win_colours, after the window's chrome) */
void view_colours(unsigned char w)
{
    struct win *p = &wins[w];
    unsigned char s, i, per, sc = theme.hilite ? theme.hilite : SELECT, c;
    geom(w);
    per = cols * rows;
    if (p->view == V_LIST)              /* the header on the chrome (V151) */
        look_rect(ccx, ccw, brow, 2, CHROME);
    if (p->view == V_ICON)
        UseFont(FONT_UI);
    for (s = 0; s < per; ++s) {
        i = p->first + s;
        if (i >= p->n)
            break;
        slot(w, s);
        if (colClip) {          /* (the colour clip, V81: the cells in it alone) */
            c = p->view == V_ICON ? 9 : 2;
            if ((vy >> 3) > colY1 || (vy >> 3) + c <= colY0)
                continue;
            if (c == 9 && ((vx >> 3) > colX1 || (vx >> 3) + 9 <= colX0))
                continue;
        }
        ent_get(w, p->order[i]);
        switch (p->view) {
        case V_ICON:
            XCALL(bLook3, ic3_colour, FICON)((vx >> 3) + 2, vy >> 3, w, tileOf(), 0xFF);    /* (V102) */
            if (i == p->sel)
                XCALL(bIc2, lbl_colour, FLBL)(vx, vy, sc);
            break;
        case V_SMALL:
            if (i == p->sel || ic3On)
                rowCol(w, vx >> 3, vy, 20, i == p->sel ? sc : 0);
            break;
        default:                        /* (the paper's rows: chrome_colours' already) */
            if (i == p->sel || (s & 1) || ic3On || vcAll)
                rowCol(w, ccx, vy, ccw, i == p->sel ? sc : (s & 1) ? SIDEBAR : 0);
            else
                look_rect(ccx + 1, 2, vy >> 3, 2, badge(w));
        }
    }
    if (p->view == V_ICON)
        UseSystemFont();
}

/* the order index at x, y; $FF nothing, $FE the list's header (the
   scroll bar: bars.c's bars_sbhit) */
unsigned char view_hit(unsigned char w, unsigned int x, unsigned int y)
{
    struct win *p = &wins[w];
    unsigned char c, r, s, cx = x >> 3, cy = y >> 3;
    geom(w);
    if (x < l0 || x > r0_ || y < t0 || y > b0)
        return 0xFF;
    if (p->view == V_LIST) {
        if (cy < brow + 2)
            return 0xFE;
        r = (cy - brow - 2) / 2;
        if (r >= rows)
            return 0xFF;
        s = p->first + r;
        return s < p->n ? s : 0xFF;
    }
    if (cx < ccx + 1 || cy < brow + 1)
        return 0xFF;
    c = (cx - ccx - 1) / (p->view == V_ICON ? 9 : 20);
    r = (cy - brow - 1) / (p->view == V_ICON ? 9 : 2);
    if (c >= cols || r >= rows)
        return 0xFF;
    s = p->first + r * cols + c;
    return s < p->n ? s : 0xFF;
}

/* the status bar's count of selected entries with s selected */
static unsigned char counted(struct win *p, unsigned char s)
{
    return s != 0xFF && !(s == 0 && p->path[1]);
}

/* the selection of window w (in front) is s now */
void view_select(unsigned char w, unsigned char s)
{
    struct win *p = &wins[w];
    unsigned char o = p->sel, f;
    if (s == o) {
        if (s != 0xFF)
            mark(w, s, 1);
        return;
    }
    p->sel = s;
    if (o != 0xFF)
        mark(w, o, 0);
    if (s != 0xFF) {
        geom(w);
        if (s < p->first || s >= p->first + cols * rows) {
            f = s - s % cols;           /* (its row at the top, or the bottom: V151) */
            if (s > p->first)
                f -= (rows - 1) * cols;
            p->first = f;
            XCALL(bWin, win_content, FB)(w);
        } else
            mark(w, s, 1);
    }
    if (counted(p, o) != counted(p, s))         /* (its "selected": V81) */
        XCALL(bWin, win_status, FB)(w);
}

/* the list scrolled by a row (a page full before and after; the window in
   front): the rows moved with CopyRect, the new one drawn, the scroll
   bar drawn again, the colours (the stripes) again (DECISIONS V81) */
static void scroll1(unsigned char w, unsigned char f)
{
    struct win *p = &wins[w];
    unsigned int y0 = (brow + 2) * 8, y, h = (rows - 1) * 16;
    unsigned char s = 0;
    dispBufferOn = ST_WR_FORE | ST_WR_BACK;
    XCALL(bChrome, chrome_sbar, FB)(w | 0x80);      /* (its thumb erased: V151) */
    if (f > p->first) {
        CopyRect(ccx, ccw, y0 + 16, h, ccx, y0);
        s = rows - 1;
    } else
        CopyRect(ccx, ccw, y0, h, ccx, y0 + 16);
    p->first = f;
    y = y0 + s * 16;
    SetPattern(0);
    WRectangle(l0, y, r0_, y + 15);
    UseFont(FONT_UI);
    cell(w, s, p->order[f + s], f + s == p->sel);
    UseSystemFont();
    XCALL(bChrome, chrome_sbar, FB)(w | 0x40);      /* (the thumb again) */
    colX0 = ccx;                        /* the colours of the rows, the scroll bar, the */
    colX1 = (r0_ + SBW) >> 3;           /* dock over them (in front: nothing else, V151) */
    colY0 = brow;
    colY1 = b0 >> 3;
    colClip = vcAll = 1;
    view_colours(w);
    vcAll = 0;
    XCALL(bChrome, chrome_sbcol, FB)(w);
    XCALL(bDock, dock_colours, FV)();
    colClip = 0;
}

/* +1, -1 a page; +2, -2 a row (of cells: V151); 0 the row of entry vx
   (the scroll bar's thumb let go: V151) */
void view_page(unsigned char w, signed char d)
{
    struct win *p = &wins[w];
    unsigned char per = view_per(w), f = p->first, last;
    unsigned char step = d == 2 || d == -2 ? cols : per;
    last = p->n > per ? p->n - per + cols - 1 : 0;
    last -= last % cols;                /* (the last row's screen) */
    if (!d)
        f = vx < last ? vx - vx % cols : last;
    else if (d > 0) {                   /* (a page may show the last rows alone, as */
        if (f + step >= p->n || (step == cols && f >= last))     /* before; a row: a screen full) */
            return;
        f += step;
        if (step == cols || p->view == V_LIST)
            if (f > last)
                f = last;
    } else {
        if (!f)
            return;
        f = f > step ? f - step : 0;
    }
    if (f == p->first)
        return;
    geom(w);                    /* (a row: from the scroll bar, the list in front) */
    if (step == 1 && p->n >= (f > p->first ? f : p->first) + rows)
        scroll1(w, f);
    else {
        p->first = f;
        XCALL(bWin, win_content, FB)(w);
    }
    strcpy(msg, "SHELL PAGE ");
    num(w, msg + 11);
    strcat(msg, " FIRST ");
    num(f, msg + strlen(msg));
    LogText(msg);
}

