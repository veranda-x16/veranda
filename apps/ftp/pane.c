/* Veranda FTP: the panes drawn, their scroll bars (overlay 3; Sunroom,
   DECISIONS V149). Moved here from ui.c (overlay 1) and main.c (the
   sizes and dates) for room; ui.c calls these through main.c's ov3, the
   pane and the row in pa and pb.

   A pane (cards 0-39, the remote 40-79): its folder in the toolbar (card
   rows 4-5, the UI font; the active pane's bold, its half in the
   highlight); the column heads (rows 6-7, bold, the size's right-
   aligned over its column, a rule under them); 25 rows of 16 lines in
   cells 1-36 (the X16's CP437 set and Veranda's: names, main.c's put):
   the name in 16 cells, the size in 6, the date in 12 (cell 37 empty);
   a Sunroom scroll bar in cards 38-39 (the SDK's vrscroll.c, compiled into this overlay:
   an arrow a line, the track a page).

   Rules (sdk/docs/GUIDE.md, overlays): what goes to the kernel is below
   $A000 (the texts through main.c's line).

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <string.h>
#include <theme.h>
#include <vrwin.h>
#include "ftp.h"
#pragma code-name ("OVERLAY3")
#pragma rodata-name ("OVL3RO")
#pragma data-name ("OVL3DATA")
#pragma bss-name ("OVL3BSS")

/* 6 characters: "<DIR>", bytes, K, M */
static void __fastcall__ fmt_size(char *p, const struct ent *e)
{
    char t[12];
    unsigned char n;
    unsigned long s = e->size;
    if (e->flags & E_DIR)
        strcpy(t, "<DIR>");
    else if (s < 1000000UL)
        unum(t, s);
    else if (s < 100000000UL) {
        strcpy(unum(t, s >> 10), "K");
    } else
        strcpy(unum(t, s >> 20), "M");
    n = strlen(t);
    memset(p, ' ', 6);
    memcpy(p + 6 - n, t, n);
}

static const char mname[] = "JanFebMarAprMayJunJulAugSepOctNovDec";

static void two(char *p, unsigned char v, char pad)
{
    p[0] = v >= 10 ? '0' + v / 10 : pad;
    p[1] = '0' + v % 10;
}

/* 12 characters: "Nov 16 10:42" this year, "Nov 16  2025" another */
static void __fastcall__ fmt_date(char *p, const struct ent *e)
{
    memset(p, ' ', 12);
    if (!e->y || !e->mo || e->mo > 12)
        return;
    memcpy(p, mname + (e->mo - 1) * 3, 3);
    two(p + 4, e->d, ' ');
    if (e->y == year + 100 && e->h != 0xFF) {
        two(p + 7, e->h, '0');
        p[9] = ':';
        two(p + 10, e->mi, '0');
    } else
        unum(p + 8, 1900u + e->y);
}

/* line (main RAM) in the UI font at x, its top at y */
static void __fastcall__ text(unsigned int x, unsigned char y, unsigned char bold)
{
    currentMode = bold ? SET_BOLD : 0;
    WPutString(line, x, y + baselineOffset);
    currentMode = 0;
}

/* s (bold) into line; its width */
static unsigned int __fastcall__ bold(const char *s)
{
    unsigned int w = 0;
    unsigned char i;
    strcpy(line, s);
    for (i = 0; line[i]; ++i)
        w += GetCharWidth(line[i]) + 1;
    return w;
}

/* the toolbar: each pane's folder */
void p_heads(void)
{
    unsigned char p, on, i;
    unsigned int x, w;
    dispBufferOn = ST_WR_FORE | ST_WR_BACK;
    UseFont(FONT_UI);
    for (p = 0; p < 2; ++p) {
        on = active == p;
        x = p ? 320 : 0;
        SetPattern(0);
        WRectangle(x, 32, x + 319, 46);
        theme_rect(p ? 40 : 0, 40, 4, 2, on && hl ? hl : CHROME);
        if (p) {
            strcpy(line, "Remote: ");
            strncat(line, logged ? (rpath[0] ? rpath : "/") : "not connected", 70);
        } else {
            strcpy(line, "Local: ");
            strncat(line, (char *)curDirName, 70);
        }
        for (i = 0, w = 0; line[i]; ++i) {     /* (cut to the half) */
            w += GetCharWidth(line[i]) + on;
            if (w > 300) {
                strcpy(line + i - 3, "...");
                break;
            }
        }
        text(x + 8, 34, on);
    }
    UseSystemFont();
}

/* the body: cleared, the column heads */
void p_body(void)
{
    unsigned char p;
    unsigned int x;
    dispBufferOn = ST_WR_FORE | ST_WR_BACK;
    SetPattern(0);
    WRectangle(0, 48, 639, LISTEND - 1);
    theme_rect(0, 80, 6, 52, 0);
    UseFont(FONT_UI);
    for (p = 0; p < 2; ++p) {
        x = p ? 320 : 0;
        bold("Name");
        text(x + 8, 50, 1);
        text(x + 24 * 8 - 1 - bold("Size"), 50, 1);   /* (over the sizes' right edge) */
        bold("Date");
        text(x + 25 * 8, 50, 1);
        WVerticalLine(0xFF, x + 17 * 8 + 3, 50, 60);
        WVerticalLine(0xFF, x + 24 * 8 + 3, 50, 60);
    }
    UseSystemFont();
    WHorizontalLine(0xFF, 0, 639, 63);
    WVerticalLine(0xFF, 320, 48, 63);
}

/* pane pa's row pb */
void p_row(void)
{
    unsigned char p = pa, r = pb;
    struct pane *q = &panes[p];
    unsigned char i = q->top + r, ox = p ? 40 : 0, sel, n, k, c, w, ch;
    unsigned int y = LISTY + r * ROWH;
    char *o;
    sel = i == q->sel && i < q->n;
    theme_rect(ox, 38, y >> 3, 2, sel && hl ? (active == p ? hl : CHROME) : 0);
    line[0] = 0;
    if (i >= q->n) {
        if (p == REMOTE && !logged && i == 0)
            strcpy(line, "Not connected: Connection > Sites...");
        put(ox + 1, y + 4, line, 36, 0);
        return;
    }
    ent_get(p, i);
    n = strlen(E.name);
    for (k = w = 0; k < n; ++k)         /* (V143) its cells: UTF-8's characters */
        if ((E.name[k] & 0xC0) != 0x80)
            ++w;
    for (k = c = 0, o = line; k < n; ++k) {
        ch = E.name[k];
        if ((ch & 0xC0) != 0x80 && c++ == (w > 16 ? 15 : 16))
            break;
        *o++ = ch;
    }
    if (w > 16) {
        *o++ = '~';
        c = 16;
    }
    memset(o, ' ', 36);
    o -= c;                             /* (the columns after the name: cells) */
    fmt_size(o + 17, &E);
    if (E.flags & E_LINK)
        memcpy(o + 17, "<LINK>", 6);
    fmt_date(o + 24, &E);
    o[36] = 0;
    put(ox + 1, y + 4, line, 36, sel && !hl && active == p);
}

/* pane pa's scroll bar */
static struct vrscroll sb = { 0, LISTY / 8, ROWS * ROWH / 8, 1, 0, ROWS, 0 };

static void bar(void)
{
    sb.cx = pa ? 78 : 38;
    sb.first = panes[pa].top;
    sb.total = panes[pa].n;
}

/* pane pa: its rows and its scroll bar */
void p_pane(void)
{
    for (pb = 0; pb < ROWS; ++pb)
        p_row();
    bar();
    dispBufferOn = ST_WR_FORE | ST_WR_BACK;
    vr_scroll(&sb);
#ifdef FTP_TEST
    tlist(pa);
#endif
}

/* a click on pane pa's scroll bar: an arrow a line, the track a page */
void p_scroll(void)
{
    struct pane *q = &panes[pa];
    int t = q->top, m = q->n > ROWS ? q->n - ROWS : 0;
    bar();
    switch (vr_scroll_hit(&sb, mouseXPos, mouseYPosW)) {
    case VS_BACK: --t; break;
    case VS_FWD: ++t; break;
    case VS_PGBACK: t -= ROWS - 1; break;
    case VS_PGFWD: t += ROWS - 1; break;
    default: return;
    }
    if (t > m)
        t = m;
    if (t < 0)
        t = 0;
    if (t != q->top) {
        q->top = t;
        p_pane();
    }
}

/* (V149) a transfer's progress: a bar in the status bar, between its
   texts (pa: the percentage) */
void p_progress(void)
{
    unsigned int w = (unsigned int)116 * (pa > 100 ? 100 : pa) / 100;
    dispBufferOn = ST_WR_FORE | ST_WR_BACK;
    SetPattern(0);
    WRectangle(448, 467, 567, 476);
    WFrameRectangle(0xFF, 448, 467, 567, 476);
    if (w) {
        SetPattern(2);
        WRectangle(450, 469, 449 + w, 474);
    }
}
