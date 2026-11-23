/* Veranda SDK: the standard Open and Save dialog (vrchoose.h; Veranda
   Look 2, DECISIONS V79; the mockup list-save.png).

   A dialog box (DoDlgBox) of its own drawing: no system icons, its
   DB_USR_ROUT draws it and sets the key, press and main loop vectors.
   Its place: the card column and card row vr_file_x, vr_file_y (or
   centred), 38 cards wide, 13 + 2 x nr card rows high (nr = 7 list rows
   at 400 lines or more, else 3); every part is a band of 2 card rows:
     rows 0-1     the title band (the theme's accent): a press there
                  drags the box's outline; let go, the box closes and
                  opens again at the new place
     rows 3-4     the name field (cards 9-35, a frame with its corners cut)
     rows 6-7     "In:", the folder pop-up (chrome cards): the path's
                  folders, deepest first, then Documents, Apps and the
                  card (vr_cd, V71), shown over the list
     rows 9-      the list: nr rows (the selection's cards in the
                  highlight colour; a kind badge of 2 x 2 cards in its
                  kind's colour, as the shell's list, V77), the scroll bar
                  in card 35
     2 rows       New folder (cards 2-10; its name typed into the field),
                  the type filter's button (12-19), Cancel (21-27), the
                  default button (29-35: on the highlight colour, a double
                  frame, bold)
   Colours go straight into the colour map's attributes of the cards the
   box covers (theme_cover_rect), so they leave with the box; the
   Classic theme, or a program without the map, gets none (the selection
   inverted). Text in the UI font.

   The entries are kept in a RAM bank of their own (64 bytes each: the
   kind 'D' or 'F' and the name), read and written with BankCopy, sorted
   as they are read (a binary insertion); nothing here maps a bank, and
   the kernel calls the routines through vr_tramp, so this file may be
   compiled into a banked overlay (its BSS in main RAM: every string the
   kernel sees is copied to row first). Changing folder lists the new one
   in the box; only a move closes and opens it again.

   The console (LogText, the gates): "VRF SHOW n path" for each listing,
   "VRF NEW name" for a folder made, "VRF MOVED x y", "VRF OK path",
   "VRF NAME name", "VRF CANCEL".

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <string.h>
#include "vrchoose.h"
#include "vrpath.h"
#include "theme.h"
#include "vr.h"

void (*vr_file_hook)(void);
unsigned char (*vr_file_filter)(const char *name);
const char *vr_file_types;
unsigned char vr_file_max = VRF_NAME;
unsigned char vr_file_x = 0xFF, vr_file_y;

#define BW      38              /* the box's width in cards */
#define MAXE    127
#define NRMAX   7
#define MOVED   0x40            /* (the box closed to open again) */
#define B_BOLD  1
#define B_MID   2

enum { G_FOLDER, G_DOC, G_NOTE, G_APPS };

static unsigned char bank, n, top, sel, mode, focus, nr, bh, br, ftype, nf, pop, npop, psel;
static unsigned char drag, outlined, colours, hi, acc, gl, bx, by, ac, aw, ar, ah, ol, ot;
static unsigned int L, T, X0, X1, Y0, dx, dy;
static unsigned char idx[MAXE];
static unsigned char pk[NRMAX];
static char path[62], opath[62];
static char field[VRF_NAME + 1], fkeep[VRF_NAME + 1];
static const char *ttl;
static unsigned char ent[3 + 64];
static char e[64];
static char row[72];
static unsigned char glyph[34];
static struct {
    unsigned char pos;
    unsigned int top, bot, left, right;
    unsigned char usr;
    void *rout;
    unsigned char end;
} tab;

static const unsigned int glyphs[4][11] = {
    { 0x7F00, 0x5580, 0x5540, 0x5540, 0x4040, 0x4040, 0x4040, 0x4040, 0x4040, 0x4040, 0x7FC0 },  /* folder */
    { 0x7F80, 0x4080, 0x4080, 0x5E80, 0x4080, 0x5E80, 0x4080, 0x5E80, 0x4080, 0x4080, 0x7F80 },  /* doc */
    { 0x0F80, 0x0F80, 0x0800, 0x0800, 0x0800, 0x0800, 0x7800, 0xF800, 0xF800, 0xF800, 0x7000 },  /* note */
    { 0xF3C0, 0xF3C0, 0xF3C0, 0xF3C0, 0x0000, 0x0000, 0xF3C0, 0xF3C0, 0xF3C0, 0xF3C0, 0x0000 },  /* apps */
};
static const char *const pname[4] = { "SD card", "Veranda", "Apps", "Documents" };
static const char *const ppath[4] = { "/", VR_SYSDIR, VR_APPSDIR, VR_DOCSDIR };
/* the kinds: extensions, the badge's colour, its glyph (the last: any) */
static const char *const kext[7] = { "TXT MD INI LOG ASC", "PNT BMP PCX PNG", "MOD XM S3M", "SID", "CSV XLS",
                                     "CVT", "" };
static const unsigned char kcol[7] = { CYAN, ORANGE, PURPLE, RED, GREEN, TITLE, CHROME };
static const unsigned char kgl[7] = { G_DOC, G_DOC, G_NOTE, G_NOTE, G_APPS, G_APPS, G_DOC };

#define EA(i) ((void *)(0xA000 + ((unsigned int)(i) << 6)))

static unsigned char low(unsigned char c)
{
    return c >= 'A' && c <= 'Z' ? c + 32 : c;
}

/* the band at card c, w cards wide, at card row r (2 rows): X0, X1, Y0 */
static void at(unsigned char c, unsigned char w, unsigned char r)
{
    ac = c;
    aw = w;
    ar = r;
    ah = 2;
    X0 = L + ((unsigned int)c << 3);
    X1 = X0 + ((unsigned int)w << 3) - 1;
    Y0 = T + ((unsigned int)r << 3);
}

/* the band's cards (ah card rows: 2 after at) in colour col (theme_cover_rect) */
static void paint(unsigned char col)
{
    if (colours)
        theme_cover_rect(bx + ac, aw, by + ar, ah, col);
}

/* the band cleared, its cards in colour col */
static void blank(unsigned char col)
{
    SetPattern(0);
    WRectangle(X0, Y0, X1, Y0 + 15);
    paint(col);
}

/* a frame i pixels inside the band (its bottom 1 more), corners cut */
static void rf(unsigned char i)
{
    unsigned int a = X0 + i, b = X1 - i, c = Y0 + i, d = Y0 + 14 - i;
    WFrameRectangle(0xFF, a, c, b, d);
    WDrawPoint(DRAW_ERASE, a, c);
    WDrawPoint(DRAW_ERASE, b, c);
    WDrawPoint(DRAW_ERASE, a, d);
    WDrawPoint(DRAW_ERASE, b, d);
}

/* s at x in the band (cut with "..." to the band's right - 2), B_MID:
   centred; r11 is its end. Text is opaque in its box: frames come after. */
static void text(const char *s, unsigned int x, unsigned char f)
{
    unsigned char l = 0, b = f & B_BOLD, c;
    unsigned int t = 0, w = X1 - 2 - x, d = 3 * (GetCharWidth('.') + b);
    while ((c = s[l]) != 0 && l < 64) {
        c = GetCharWidth(c) + b;
        if (t + c > w)
            break;
        t += c;
        row[l] = s[l];
        ++l;
    }
    if (s[l]) {
        while (l && t + d > w)
            t -= GetCharWidth(row[--l]) + b;
        memcpy(row + l, "...", 3);
        l += 3;
        t += d;
    }
    row[l] = 0;
    if (f & B_MID)
        x += (w - t) >> 1;
    currentMode = b ? SET_BOLD : 0;
    WPutString(row, x, Y0 + 3 + baselineOffset);   /* (centred in the band: V126) */
    currentMode = 0;
}

static void say(const char *a, const char *b)
{
    strcpy(row, a);
    strncat(row, b, 62);
    LogText(row);
}

static char *dec(char *p, unsigned char v)
{
    if (v >= 100)
        *p++ = '0' + v / 100;
    if (v >= 10)
        *p++ = '0' + v / 10 % 10;
    *p++ = '0' + v % 10;
    *p++ = ' ';
    *p = 0;
    return p;
}

/* glyph g (11 x 11) at the band's x + 3, top + 3 */
static void mini(unsigned int x, unsigned char g)
{
    unsigned char r, s = (x += 3) & 7, *d = glyph + 1;
    unsigned long v;
    for (r = 0; r < 11; ++r, d += 3) {
        v = (unsigned long)glyphs[g][r] << (8 - s);
        d[0] = v >> 16;
        d[1] = v >> 8;
        d[2] = v;
    }
    glyph[0] = 0x80 + 33;
    WBitmapUp(glyph, x >> 3, 3, Y0 + 3, 11);
}

/*---------------------------------------------------------------- the list */

/* name's extension in list (extensions apart by spaces, case ignored) */
static unsigned char extin(const char *nm, const char *list)
{
    const char *d = strrchr(nm, '.');
    unsigned char k;
    if (!d)
        return 0;
    ++d;
    while (*list) {
        for (k = 0; list[k] > ' ' && low(list[k]) == low(d[k]); ++k)
            ;
        if (list[k] <= ' ' && !d[k])
            return 1;
        while (*list > ' ')
            ++list;
        while (*list == ' ')
            ++list;
    }
    return 0;
}

/* entry e's badge: its colour, its glyph in gl */
static unsigned char kind(void)
{
    unsigned char k = 0;
    gl = G_FOLDER;
    if (e[0] == 'D')
        return YELLOW;
    while (k < 6 && !extin(e + 1, kext[k]))
        ++k;
    gl = kgl[k];
    return kcol[k];
}

/* entry i (in the order shown) into e: its kind */
static unsigned char get(unsigned char i)
{
    BankCopy(EA(idx[i]), e, 64, bank, 0);
    return e[0];
}

/* e against entry j: folders first, then by name, case ignored */
static signed char cmp(unsigned char j)
{
    unsigned char k = 0, a, b;
    BankCopy(EA(j), row, 64, bank, 0);
    if (e[0] != row[0])
        return e[0] == 'D' ? -1 : 1;
    do {
        a = low(e[++k]);
        b = low(row[k]);
    } while (a && a == b);
    return a < b ? -1 : a > b;
}

static void scan(void)
{
    unsigned char a, z, m, first;
    const char *nm = (const char *)ent + 3, *t = vr_file_types;
    n = 0;
    if (path[1]) {
        strcpy(e, "D..");
        BankCopy(e, EA(0), 64, 0, bank);
        idx[0] = 0;
        n = 1;
    }
    first = n;
    row[0] = '*';
    row[1] = 0;
    if (DirOpen(row) == 0)
        while (n < MAXE && DirNext(ent) == 0) {
            if (nm[0] == '.')
                continue;
            if (ent[0] != 'D' && ((vr_file_filter && !vr_file_filter(nm)) ||
                                  (ftype && !extin(nm, strchr(t, ':') + 1))))
                continue;
            e[0] = ent[0];
            strncpy(e + 1, nm, 62);
            e[63] = 0;
            for (a = first, z = n; a < z;) {
                m = (a + z) >> 1;
                if (cmp(idx[m]) < 0)
                    z = m;
                else
                    a = m + 1;
            }
            memmove(idx + a + 1, idx + a, n - a);
            idx[a] = n;
            BankCopy(e, EA(n), 64, 0, bank);
            ++n;
        }
    top = sel = 0;
    strcpy(e, "VRF SHOW ");
    strcpy(dec(e + 9, n), path);
    LogText(e);
}

/* the display name of path's first k characters: a place's, the card's,
   or its last folder's (into e) */
static void fname(unsigned char k)
{
    unsigned char i, j;
    const char *q;
    for (i = 0; i < 4; ++i) {
        q = ppath[i];
        for (j = 0; j < k && low(q[j]) == low(path[j]); ++j)
            ;
        if (j == k && !q[j]) {
            strcpy(e, pname[i]);
            return;
        }
    }
    for (j = k; path[j - 1] != '/'; --j)
        ;
    memcpy(e, path + j, k - j);
    e[k - j] = 0;
}

/* list row r: an entry, or the pop-up's item r */
static void draw_row(unsigned char r)
{
    unsigned char i = top + r, c = YELLOW, s;
    at(2, BW - 5, 9 + (r << 1));
    blank(0);
    if (pop) {
        if (r >= npop)
            return;
        s = r == psel;
        i = pk[r];
        if (i & 0x80)
            strcpy(e, pname[i & 3]);
        else
            fname(i);
        gl = G_FOLDER;
    } else {
        if (i >= n)
            return;
        s = i == sel;
        get(i);
        c = kind();
    }
    if (s)
        paint(hi);
    at(3, 2, ar);
    paint(c);
    mini(X0, gl);
    at(2, BW - 5, ar);
    text(e + !pop, X0 + 28, 0);
    if (s && !colours)
        WInvertRectangle(X0, Y0, X1, Y0 + 15);
}

static void draw_bar(void)
{
    unsigned char h = (nr << 4) - 4, a, b;
    unsigned int x;
    at(BW - 3, 1, 9);
    x = X0 + 1;
    SetPattern(5);                      /* (V148, Sunroom) a dotted track on the chrome, */
    WRectangle(x, Y0, x + 6, Y0 + h + 3);
    ah = nr << 1;
    paint(CHROME);
    if (pop || n <= nr)
        return;
    a = (unsigned int)top * h / n;
    b = (unsigned int)nr * h / n + a;
    SetPattern(1);                      /* a slim thumb in the ink */
    WRectangle(x + 1, Y0 + 2 + a, x + 5, Y0 + 2 + b);
}

static void draw_list(void)
{
    unsigned char r;
    for (r = 0; r < nr; ++r)
        draw_row(r);
    draw_bar();
}

/* a label at the band row r's left; the band is then the field's place */
static void label(const char *s, unsigned char r)
{
    at(1, BW - 2, r);
    blank(0);
    text(s, X0 + 4, 0);
    at(9, BW - 11, r);
}

/* the name field: the text typed, or (opening) the selected name */
static void draw_field(void)
{
    const char *s = field;
    unsigned char ed = nf || mode == VRF_SAVE;
    unsigned int xe;
    label(nf ? "Folder:" : ed ? "Save as:" : "Name:", 3);
    if (!ed) {
        s = "";
        if (sel < n) {
            get(sel);
            s = e + 1;
        }
    }
    text(s, X0 + 6, 0);
    xe = r11 + 1;                       /* (the text's end: rf changes r11) */
    rf(0);
    if (ed && !focus)
        WVerticalLine(0xFF, xe, Y0 + 3, Y0 + 12);
}

/* "In:" and the folder pop-up's button */
static void draw_in(void)
{
    unsigned int x;
    label("In:", 6);
    paint(CHROME);
    mini(X0 + 3, G_FOLDER);
    fname(strlen(path));
    text(e, X0 + 20, 0);
    rf(0);
    x = X1 - 12;
    WDrawLine(DRAW_INK, x, Y0 + 6, x + 3, Y0 + 9);
    WDrawLine(DRAW_INK, x + 6, Y0 + 6, x + 3, Y0 + 9);
}

static void button(unsigned char c, unsigned char w, const char *s, unsigned char dflt)
{
    at(c, w, br);
    blank(dflt ? hi : 0);
    text(s, X0 + 3, dflt | B_MID);
    rf(1);
    if (dflt)
        rf(2);
}

static void draw_types(void)
{
    const char *t = vr_file_types;
    unsigned char l;
    if (!t)
        return;
    l = strchr(t, ':') - t;
    if (!ftype) {
        t = "All files";
        l = 9;
    }
    memcpy(e, t, l);
    e[l] = 0;
    button(12, 8, e, 0);
}

/*---------------------------------------------------------------- moving in it */

/* select i, scrolling only as far as it takes to show it */
static void go(int i)
{
    unsigned char old = sel, otop = top;
    if (!n)
        return;
    if (i < 0)
        i = 0;
    if (i >= n)
        i = n - 1;
    sel = i;
    if (sel < top)
        top = sel;
    else if (sel >= top + nr)
        top = sel - nr + 1;
    if (top != otop)
        draw_list();
    else if (old != sel) {
        draw_row(old - top);
        draw_row(sel - top);
    }
    if (mode != VRF_SAVE && !nf)
        draw_field();
}

/* path made the current directory and listed (else back to opath) */
static void cd(void)
{
    pop = 0;
    if (ChDir(path)) {
        strcpy(path, opath);
        ChDir(path);
        Beep();
    }
    scan();
    draw_list();
    draw_in();
    draw_field();
}

/* path + "/" + s (opath: path before): 0 if too long */
static unsigned char append(const char *s)
{
    unsigned char l = strlen(path);
    strcpy(opath, path);
    if (l + 1 + strlen(s) > sizeof path - 1) {
        Beep();
        return 0;
    }
    if (l > 1)
        path[l++] = '/';
    strcpy(path + l, s);
    return 1;
}

/* into entry sel (a folder) */
static void enter(void)
{
    unsigned char l = strlen(path);
    get(sel);
    if (e[1] == '.' && e[2] == '.' && !e[3]) {
        strcpy(opath, path);
        while (l > 1 && path[--l] != '/')
            ;
        path[l ? l : 1] = 0;
    } else if (!append(e + 1))
        return;
    if (mode == VRF_SAVE)
        focus = 0;
    cd();
}

/* the folder pop-up opened, or closed */
static void pop_open(void)
{
    unsigned char l = strlen(path), m = 0;
    pop ^= 1;
    if (pop) {
        while (l > 1 && m < nr - 3) {
            pk[m++] = l;
            do
                --l;
            while (l && path[l] != '/');
        }
        pk[m++] = 0x80 + VR_DOCS;
        pk[m++] = 0x80 + VR_APPS;
        pk[m++] = 0x80;
        npop = m;
        psel = 0;
    }
    draw_list();
}

static void pop_choose(unsigned char i)
{
    unsigned char c = pk[i];
    strcpy(opath, path);
    if (c == 0x80)
        strcpy(path, "/");
    else if (c & 0x80)
        strcpy(path, vr_cd(c & 3));
    else
        path[c] = 0;
    cd();
}

static void fd_close(unsigned char r)
{
    sysDBData = r;
    RstrFrmDialogue();
}

static void newfolder(void)
{
    if (nf)
        return;
    nf = 1;
    strcpy(fkeep, field);
    field[0] = 0;
    focus = 0;
    draw_field();
}

static void nf_done(unsigned char ok)
{
    if (ok) {
        if (!field[0] || MkDir(field)) {
            Beep();
            return;
        }
        say("VRF NEW ", field);
        append(field);
    }
    nf = 0;
    strcpy(field, fkeep);
    if (ok)
        cd();
    else
        draw_field();
}

/* the default button (Return, a double click) */
static void ok(void)
{
    if (pop)
        pop_choose(psel);
    else if (nf)
        nf_done(1);
    else if (sel < n && get(sel) == 'D' && (mode == VRF_OPEN || focus || !field[0]))
        enter();
    else if (mode == VRF_OPEN) {
        if (sel < n) {
            strcpy(field, e + 1);
            fd_close(OK);
        }
    } else if (!field[0])
        Beep();
    else
        fd_close(OK);
}

static void move(int d)
{
    if (pop) {
        d += psel;
        if (d >= 0 && d < npop) {
            psel = d;
            draw_list();
        }
        return;
    }
    focus = 1;
    go((int)sel + d);
}

static void fd_key(void)
{
    unsigned char k = keyData, i, j, l = strlen(field);
    UseFont(FONT_UI);
    if (keyDataMods & KEYM_ARROW) {
        if (k == KEY_UP)
            move(-1);
        else if (k == KEY_DOWN)
            move(1);
        return;
    }
    switch (k) {
    case KEY_PGUP: move(-nr); return;
    case KEY_PGDN: move(nr); return;
    case KEY_HOME: move(-255); return;
    case KEY_END: move(255); return;
    case CR: ok(); return;
    case KEY_ESC:
        if (pop)
            pop_open();
        else if (nf)
            nf_done(0);
        else
            fd_close(CANCEL);
        return;
    }
    if (nf || mode == VRF_SAVE) {
        if (k == 8) {
            if (!l)
                return;
            field[l - 1] = 0;
        } else if (k >= 32 && (k < 127 || k >= 160) && l < (nf ? VRF_NAME : vr_file_max) &&
                   !strchr("/\\:*?\"<>|,=", k)) {
            field[l] = k;
            field[l + 1] = 0;
        } else {
            Beep();
            return;
        }
        focus = 0;
        draw_field();
        return;
    }
    if (k == 8) {
        if (path[1]) {
            sel = 0;                    /* ".." */
            enter();
        }
        return;
    }
    for (j = 1; j <= n; ++j) {          /* the next name starting with k */
        i = (sel + j) % n;
        get(i);
        if (low(e[1]) == low(k)) {
            go(i);
            return;
        }
    }
}

static void fd_press(void)
{
    unsigned int x, y;
    unsigned char cx, cy, i;
    if (mouseData & 0x80)
        return;
    do {
        x = mouseXPos;
        y = mouseYPosW;
    } while (x != mouseXPos || y != mouseYPosW);
    if (x < L || y < T)
        return;
    x -= L;
    y -= T;
    cx = x >> 3;
    cy = y >> 3;
    i = (cy - 9) >> 1;
    UseFont(FONT_UI);
    if (cy < 2) {                       /* the title band: a move */
        drag = 1;
        dx = x;
        dy = y;
    } else if (pop) {
        if (cy >= 9 && i < npop && cx >= 2 && cx < BW - 2)
            pop_choose(i);
        else
            pop_open();
    } else if (cx >= 9 && cx < BW - 2 && cy >= 3 && cy < 8) {
        if (cy < 5) {
            focus = 0;
            draw_field();
        } else if (cy > 5)
            pop_open();
    } else if (cy >= 9 && i < nr) {
        if (cx == BW - 3) {             /* the bar: a page */
            if (n > nr)
                move(y - 72 < (unsigned int)top * (nr << 4) / n ? -nr : nr);
            return;
        }
        i += top;
        if (cx < 2 || cx > BW - 4 || i >= n)
            return;
        focus = 1;
        if (i == sel && dblClickCount) {
            dblClickCount = 0;
            ok();
            return;
        }
        go(i);
        dblClickCount = 30;
        if (mode == VRF_SAVE && !nf && get(i) == 'F') {
            strncpy(field, e + 1, vr_file_max);
            field[vr_file_max] = 0;
            focus = 0;
            draw_field();
        }
    } else if (cy == br || cy == br + 1) {
        if (cx >= 2 && cx < 11)
            newfolder();
        else if (vr_file_types && cx >= 12 && cx < 20) {
            ftype ^= 1;
            scan();
            draw_list();
            draw_field();
            draw_types();
        } else if (cx >= 21 && cx < 28)
            fd_close(CANCEL);
        else if (cx >= 29 && cx < 36)
            ok();
    }
}

/* the move's outline at card ol, card row ot (inverted, on the foreground) */
static void xframe(void)
{
    unsigned int l = (unsigned int)ol << 3, t = (unsigned int)ot << 3, r = l + BW * 8 - 1, b = t + (bh << 3) - 1;
    WInvertRectangle(l, t, r, t);
    WInvertRectangle(l, b, r, b);
    ++t;
    --b;
    WInvertRectangle(l, t, l, b);
    WInvertRectangle(r, t, r, b);
}

static void fd_main(void)
{
    signed char w;
    unsigned char x, y, m;
    asm("sei");
    w = (signed char)mouseWheel;
    mouseWheel = 0;
    asm("cli");
    if (w && !drag) {
        UseFont(FONT_UI);
        move(3 * w);
    }
    if (drag) {
        /* the box's card and card row under the pointer */
        x = mouseXPos + 4 > dx ? (mouseXPos + 4 - dx) >> 3 : 0;
        y = mouseYPosW + 4 > dy ? (mouseYPosW + 4 - dy) >> 3 : 0;
        m = (screenWidth >> 3) - BW;
        if (x > m)
            x = m;
        m = (screenHeight >> 3) - bh;
        if (y > m)
            y = m;
        if (y < 2)
            y = 2;
        if (outlined && (x != ol || y != ot)) {
            xframe();
            outlined = 0;
        }
        if (mouseData & 0x80) {
            drag = 0;
            if (outlined)
                xframe();
            outlined = 0;
            if (x != bx || y != by) {
                vr_file_x = x;
                vr_file_y = y;
                fd_close(MOVED);
            }
            return;
        }
        if (!outlined && (x != bx || y != by)) {
            ol = x;
            ot = y;
            xframe();
            outlined = 1;
        }
    }
    if (vr_file_hook)
        vr_file_hook();
}

/* the box's routine: all of it, its vectors */
static void fd_draw(void)
{
    unsigned int y = T + ((unsigned int)nr << 4) + 72;
    UseFont(FONT_UI);
    at(0, BW, 0);
    WFrameRectangle(0xFF, X0 + 1, Y0 + 1, X1 - 1, T + (bh << 3) - 2);
    paint(acc);
    WHorizontalLine(0xFF, X0, X1, Y0 + 15);
    text(ttl, X0 + 8, B_BOLD | B_MID);
    at(2, BW - 4, 9);
    WFrameRectangle(0xFF, X0 - 1, Y0 - 1, X1 + 1, y);
    WVerticalLine(0xFF, X1 - 7, Y0, y - 1);
    draw_field();
    draw_in();
    draw_list();
    button(2, 9, "New folder", 0);
    draw_types();
    button(21, 7, "Cancel", 0);
    button(29, 7, mode == VRF_SAVE ? "Save" : "Open", B_BOLD);
    keyVector = (unsigned int)vr_tramp(1, fd_key);
    otherPressVec = (unsigned int)vr_tramp(2, fd_press);
    appMain = (unsigned int)vr_tramp(3, fd_main);
}

unsigned char __fastcall__ vr_file(unsigned char md, const char *title, char *name)
{
    unsigned char r, sw = screenWidth >> 3, sh = screenHeight >> 3;
    mode = md;
    ttl = title;
    bank = BankAlloc(1);
    if (!bank)
        return 0;
    theme_load();
    colours = theme_map_on() && !theme_none() && theme_look2();
    hi = theme.hilite ? theme.hilite : SELECT;
    acc = theme.accent ? theme.accent : TITLE;
    nr = sh >= 50 ? NRMAX : 3;
    bh = 13 + (nr << 1);
    br = 10 + (nr << 1);
    strncpy(path, (char *)curDirName, sizeof path - 1);
    path[sizeof path - 1] = 0;
    if (path[0] != '/' || ChDir(path)) {
        strcpy(path, "/");
        ChDir(path);
    }
    if (vr_file_max > VRF_NAME)
        vr_file_max = VRF_NAME;
    field[0] = 0;
    if (md == VRF_SAVE) {
        strncpy(field, name, vr_file_max);
        field[vr_file_max] = 0;
    }
    ftype = vr_file_types != 0;
    focus = nf = pop = drag = outlined = 0;
    scan();
    do {
        bx = vr_file_x;
        by = vr_file_y;
        if (bx == 0xFF) {
            bx = (sw - BW) >> 1;
            by = (sh - bh) >> 1;
        }
        if (bx > sw - BW)
            bx = sw - BW;
        if (by > sh - bh)
            by = sh - bh;
        if (by < 2)
            by = 2;
        tab.left = L = (unsigned int)bx << 3;
        tab.top = T = (unsigned int)by << 3;
        tab.bot = T + (bh << 3) - 1;
        tab.right = L + BW * 8 - 1;
        tab.pos = SET_DB_POS | WIDE_DB | (theme.dark ? 0 : 2);   /* (V148: no shadow in dark mode: the ink would glow) */
        tab.usr = DB_USR_ROUT;
        tab.rout = vr_tramp(0, fd_draw);
        dblClickCount = 0;
        r = vr_dlgbox(&tab);
        if (r == MOVED) {
            strcpy(e, "VRF MOVED ");
            dec(dec(e + 10, vr_file_x), vr_file_y);
            LogText(e);
        }
    } while (r == MOVED);
    BankFree(bank);
    if (r == OK) {
        strcpy(name, field);
        strcpy((char *)curDirName, path);
        say("VRF OK ", path);
        say("VRF NAME ", name);
        return 1;
    }
    ChDir((char *)curDirName);
    say("VRF CANCEL", "");
    return 0;
}
