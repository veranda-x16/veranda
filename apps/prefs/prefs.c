/* Preferences: Veranda's control panel, a desk accessory in C.

   A row a setting, each changed with its < and > buttons (or a click on
   a switch): the screen's blanking delay (blankDelay), the paper and the
   ink (palette entries 0 and 1 at every program's start: SetColors; shown
   at once in the window), the sounds (on or off, their volume 0-63, the
   menu ticks: DECISIONS V69), the pointer's speed (x1, x2,
   x4), the video mode Veranda starts in and gives programs that keep the
   mode (the shell's), the desktop (Veranda's shell, or TopDesk: its
   TopDesk.cvt, from the applications' folder, copied as DESKTOP.cvt in
   the system folder /VERANDA (DECISIONS V71), or DESKTOP.cvt
   deleted: DECISIONS V46), the time zone (kept for programs that take the
   time from a network), and the date and time (SetClock, the X16's
   battery-backed clock).

   The date and time (V127): they tick with the clock while they are not
   edited (appMain: each new minute); a change (< >, a digit typed, Up
   and Down) leaves them pending, their values in the highlight colour,
   until Save (or Return) sets the clock with the rest and says what the
   clock read back under the rows ("Clock set to 21 Nov 2026 09:45", or
   "The clock did not take the time"); Now puts the clock's time back
   into them. A click on a value, or Tab, picks it for typing (its value
   on yellow): digits fill it and go on to the next (0945 in the hour:
   09:45; a year as 26 or 2026), Up and Down step it, Backspace starts it
   again. A clock that reads 2000 (never set) opens the window with the
   rows marked and "The clock is not set: set the date and time, then
   Save"; from the bar's clock (DN_CLOCK) the day is picked for typing.

   Theme (the button by Save) shows the colour theme instead (DECISIONS
   V65, V74, sdk theme.h): a preset (Sunroom, Classic, Graphite, Mint, Veranda, or
   Custom once a colour is changed), the accent (title bars), the
   desktop (the area behind windows: the shell's icons) and the
   highlight (selections, an open menu), each one of Veranda Look 2's
   light colours (dark ones would hide the one ink), with a swatch, the
   mode (light or dark: Look 2's palette swapped, at once on the whole
   screen), and a preview: a small shell in those colours; the window's
   own title bar takes the accent at once. Saved in the settings block's
   bytes 10-14 (14: LOOK_V2 and LOOK_DARK); the shell takes it when the
   accessory closes, and at every start.

   Desktop (the button by Theme) shows the desktop's background (Veranda
   Look 2, step C: DECISIONS V78, sdk wallcfg.h): a picture (a wallpaper
   file, tools/mkwall.py, chosen from /VERANDA/WALLPAPERS with Choose;
   Dusk, the default), the theme's plain desktop colour, or one of the
   shell's eight patterns on it (the classic look); dark mode takes the
   picture's dark variant by itself. Saved in WALLPAPER.CFG (the system's
   data folder) with the rest; the shell takes it when the accessory
   closes.

   Save writes "Veranda Prefs" in the system's data folder (/VERANDA/.SYSTEM;
   a GEOS file of type
   SYSTEM, its data the kernel's settings block: SysPrefs, DECISIONS V56),
   which the kernel reads when Veranda starts, and gives the block to the
   running system (blankDelay, the sounds and the speed at once; the colours
   and the mode from the next program's start). Closing without Save
   leaves everything as it was (the window's colours go with it).

   Opened by the kernel from the menu bar (DECISIONS V120: deskNote, in any
   native program with its bar up): a click on the clock opens the window
   with the Date and Time rows marked in the highlight colour; a click on
   the sound opens only a small pop-up under the bar at the sound instead
   of the window: the volume as a slider (0-63: a click or a drag on it,
   the wheel, the arrow keys) and Mute (the sounds off: PREFS_NOSOUND),
   each change given to the running system at once (PREFS_SET) with a
   short sound; a click outside it, Esc or Return closes it, and the
   settings are saved as Save saves them when they changed (the block as
   the kernel has it). The screen under it comes back with the
   application (RstrAppl), and the kernel draws the bar's sound again
   (crossed out when muted).

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <vr.h>
#include <string.h>
#include <theme.h>
#include <vrpath.h>
#include <wallcfg.h>
#include <vrcs.h>
#include "daui.h"

#define W       480
#define LX      16              /* the labels (in the window) */
#define CX      184             /* the controls */
#define VW      128             /* a setting's value */
#define NROW    10

static unsigned char p[PREFS_SIZE];
static unsigned char rh, ry;            /* the rows' height, the first row */
static unsigned char iblank, ipaper, iink, ispeed, imode, idesk, topdesk;
static signed char tz;
static unsigned char dd, dm, dy, th, tmi;       /* the clock being edited */
static unsigned char cdirty;            /* (V127) the date or time changed, not saved */
static unsigned char cfoc = 0xFF;       /* the part picked for typing (0-4: day, month,
                                           year, hour, minute), $FF none */
static unsigned char ctn;               /* digits typed into it */
static unsigned int ctb;                /* their number */
static char line[64];
static unsigned char page;              /* 0 the settings, 1 the theme, 2 the desktop, 3 the dock (V163) */
static unsigned char wcfg[WALL_CFGLEN]; /* the desktop's background (wallcfg.h) */
static struct theme tt;                 /* the theme being edited */

/* the colours offered: none and Look 2's light ones (V74) */
#define NCOL 14
static const unsigned char cols[NCOL] = { 0, TITLE, SELECT, SKY2, CYAN, GREEN, YELLOW,
    ORANGE, RED, PURPLE, DUSK, CHROME, SIDEBAR, SAGE };
static const char *const colt[NCOL] = { "None", "Sky", "Blue", "Azure", "Cyan", "Green", "Yellow",
    "Orange", "Rose", "Lilac", "Dusk", "Chrome", "Mist", "Sage" };
static const char *const presett[THEME_NPRESET] = { "Veranda", "Classic", "Graphite", "Mint",
    "Custom", "Sunroom" };
/* the presets in the order offered (V132: Sunroom, Look 3's default, where
   Veranda was, Look 2's Veranda after Mint) */
#define NPRE 5
static const unsigned char preo[NPRE] = { THEME_SUNROOM, THEME_CLASSIC, THEME_GRAPHITE, THEME_MINT, THEME_VERANDA };
#define TROWS 5
static const char *const tlabels[TROWS] = { "Theme", "Accent (title bars)", "Desktop", "Highlight", "Mode" };
#define DROWS 4
static const char *const dlabels[DROWS] = { "Background", "Picture", "Pattern", "Colour" };
static const char *const kindt[3] = { "Picture", "Plain colour", "Pattern" };
static const unsigned char pats[8] = { 2, 3, 5, 31, 23, 19, 0, 33 };   /* (the shell's) */

static const unsigned int blanks[8] = { 0, 60, 120, 300, 600, 900, 1800, 3600 };
static const char *const blankt[8] = { "never", "1 minute", "2 minutes", "5 minutes",
    "10 minutes", "15 minutes", "30 minutes", "1 hour" };
static const unsigned int papers[6] = { 0x0FFF, 0x0FFD, 0x0DFE, 0x0DEF, 0x0DDD, 0x0EDB };
static const char *const papert[6] = { "White", "Cream", "Mint", "Sky", "Silver", "Sand" };
static const unsigned int inks[6] = { 0x0223, 0x0000, 0x0026, 0x0420, 0x0030, 0x0303 };
static const char *const inkt[6] = { "Slate", "Black", "Navy", "Brown", "Forest", "Plum" };
static const char *const speedt[3] = { "Normal", "Fast", "Faster" };
static const char *const modet[4] = { "640 x 480", "640 x 240", "320 x 240", "as it is" };
static const char *const deskt[2] = { "Veranda's shell", "TopDesk" };
static const char *const labels[NROW] = { "Blank the screen after", "Paper", "Ink", "Sounds",
    "Pointer, keyboard", "Video mode, switching", "Desktop", "Time zone", "Date", "Time" };
static const char *const mon[12] = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug",
    "Sep", "Oct", "Nov", "Dec" };

#ifdef PREFS_TEST
void da_test_start(void);
#endif

static char logl[80];
static void say(const char *s)
{
    *ui_put(ui_put(logl, "PREFS "), s) = 0;
    LogText(logl);
}

static unsigned int ry_of(unsigned char r)
{
    return ui_y0 + ry + r * rh;
}

/* a spinner: < at x, the value in w (its cards in vcol), > after it */
static unsigned char vcol;
static void spin(unsigned int x, unsigned int y, unsigned int w, const char *v)
{
    ui_button(x, y, 16, "<", C_BTN);
    ui_clear(x + 16, y, w, UI_BH);
    ui_color(x + 16, y, w, UI_BH, vcol);
    vcol = C_NONE;
    ui_textc(v, x + 16, w, y + 11);
    ui_button(x + 16 + w, y, 16, ">", C_BTN);
}

/* the sounds' volume, 0-63: PREFS_VOLSET + 63 - it; without PREFS_VOLSET
   (a file saved before DECISIONS V72) full, as the kernel reads it */
static unsigned char volume(void)
{
    return p[PREFS_VOLUME] & PREFS_VOLSET ? 63 - (p[PREFS_VOLUME] & 63) : 63;
}

static unsigned char mdays(unsigned char y, unsigned char m)
{
    static const unsigned char n[12] = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    return m == 2 && !(y & 3) ? 29 : n[m - 1];
}

/* the date's and time's part k: its value's colour (V127: picked for
   typing yellow, pending the highlight) for the next spin */
static void part(unsigned char k)
{
    vcol = cfoc == k ? C_YELLOW : cdirty ? C_SEL : C_NONE;
}

/* (V145) the switcher Roomy (programs aside onto the card when RAM is
   short) or Fast (in RAM only); PREFS_SWITCH 0: by the machine, the
   kernel's rule: Roomy below 2 MB */
static unsigned char roomy(void)
{
    static unsigned char sum[TASK_SUM];
    unsigned char m = p[6] & PREFS_SWITCH;
    if (m)
        return m == PREFS_ROOMY;
    TaskCtl(TASK_INFO, 0xFF, sum);
    return sum[TS_BANKS] < 128;
}

static void draw_row(unsigned char r)
{
    unsigned int x = ui_x0 + CX, y = ry_of(r);
    char *q;
    switch (r) {
    case 0: spin(x, y, VW, blankt[iblank]); break;
    case 1: spin(x, y, VW, papert[ipaper]); break;
    case 2: spin(x, y, VW, inkt[iink]); break;
    case 3:                             /* on/off, < volume >, the menu ticks */
        ui_button(x, y, 48, p[6] & PREFS_NOSOUND ? "Off" : "On", p[6] & PREFS_NOSOUND ? C_BTN : C_GREEN);
        ui_num(line, volume(), 0);
        spin(x + 56, y, 32, line);
        ui_button(x + 128, y, 104, p[6] & PREFS_MENUTICK ? "Menu ticks" : "No menu ticks",
                  p[6] & PREFS_MENUTICK ? C_GREEN : C_BTN);
        break;
    case 4:                             /* the speed; the keyboard (V142) */
        spin(x, y, VW, speedt[ispeed]);
        ui_button(x + 168, y, 120, p[6] & PREFS_POLISH ? "Polish (programmers)" : "Keyboard: US",
                  p[6] & PREFS_POLISH ? C_GREEN : C_BTN);
        break;
    case 5:                             /* the mode; the switcher's (V145) */
        spin(x, y, VW, modet[imode]);
        ui_button(x + 168, y, 120, roomy() ? "Programs aside: card" : "Programs aside: RAM",
                  roomy() ? C_GREEN : C_BTN);
        break;
    case 6: spin(x, y, VW, deskt[topdesk ? idesk : 0]); break;
    case 7:
        q = ui_put(line, "UTC");
        if (tz) {
            unsigned char a = tz < 0 ? -tz : tz;
            *q++ = tz < 0 ? '-' : '+';
            q = ui_num(q, a / 4, 0);
            *q++ = ':';
            ui_num(q, a % 4 * 15, 2);
        }
        spin(x, y, VW, line);
        break;
    case 8:
        ui_num(line, dd, 0);
        part(0);
        spin(x, y, 32, line);
        part(1);
        spin(x + 72, y, 32, mon[dm - 1]);
        ui_num(line, 2000 + dy, 0);
        part(2);
        spin(x + 144, y, 40, line);
        break;
    case 9:
        ui_num(line, th, 2);
        part(3);
        spin(x, y, 32, line);
        ui_num(line, tmi, 2);
        part(4);
        spin(x + 72, y, 32, line);
        ui_button(x + 144, y, 48, "Now", C_BTN);
        break;
    }
}

static unsigned int bx(unsigned char i)
{
    return ui_x0 + W - 8 - (2 - i) * 88;
}

static unsigned char *colp(unsigned char r)
{
    return r == 1 ? &tt.accent : r == 2 ? &tt.desk : &tt.hilite;
}

static unsigned char coli(unsigned char c)
{
    unsigned char i;
    for (i = 0; i < NCOL; ++i)
        if (cols[i] == c)
            return i;
    return 0;
}

/* a preview: a small shell in the theme's colours (card aligned): the
   menu bar on the chrome (with a highlight: V74), a title bar on the
   accent, the desktop, three icons, one selected */
static void preview_theme(void)
{
    unsigned int x = ui_x0 + LX, y = ry_of(TROWS), w = W - 2 * LX, h = ry_of(NROW - 1) + UI_BH - y;
    unsigned int cy = y + 32, ch = h - 40;
    unsigned char i;
    static const char *const names[3] = { "Docs", "Paint", "Notes" };
    ui_clear(x, y, w, h);
    ui_color(x, y, w, h, tt.desk);
    ui_color(x, y, w, 16, tt.hilite ? CHROME : 0);
    ui_color(x, y + 16, w, 16, tt.accent);
    ui_frame(x, y, w, h);
    ui_text("Veranda   File   View", x + 8, y + 11);
    WHorizontalLine(0xFF, x, x + w - 1, y + 15);
    ui_text("/VERANDA", x + 8, y + 27);
    WHorizontalLine(0xFF, x, x + w - 1, y + 31);
    if (ch > 40)
        ch = 40;
    for (i = 0; i < 3; ++i) {
        unsigned int cx = x + 8 + i * 96;
        ui_frame(cx + 32, cy + 4, 16, 18);
        ui_textc(names[i], cx, 80, cy + 33);
        if (i == 1) {
            if (tt.hilite)
                ui_color(cx, cy, 80, ch, tt.hilite);
            else
                WInvertRectangle(cx + 2, cy, cx + 77, cy + ch - 1);
        }
    }
    /* the window's own title bar: the accent at once */
    ui_color(ui_x0, ui_y0, W, UI_BAR, tt.accent ? tt.accent : C_BLUE);
}

static void draw_trow(unsigned char r)
{
    unsigned int x = ui_x0 + CX, y = ry_of(r);
    if (r == 0) {
        spin(x, y, VW, presett[tt.preset]);
        return;
    }
    if (r == TROWS - 1) {
        spin(x, y, VW, tt.dark ? "Dark" : "Light");
        return;
    }
    spin(x, y, VW, colt[coli(*colp(r))]);
    ui_frame(x + VW + 40, y, 32, UI_BH);
    ui_color(x + VW + 40, y, 32, UI_BH, *colp(r));
}

#define DBX 120                 /* the Desktop button */

/* the desktop page's row r (V78) */
static void draw_drow(unsigned char r)
{
    unsigned int x = ui_x0 + CX, y = ry_of(r);
    unsigned char k = wcfg[WALL_KIND];
    switch (r) {
    case 0:
        spin(x, y, VW, kindt[k < 3 ? k : 0]);
        break;
    case 1:
        ui_button(x, y, 64, "Choose", k == WALL_PICTURE ? C_GREEN : C_BTN);
        ui_clear(x + 72, y, 176, UI_BH);
        ui_color(x + 72, y, 176, UI_BH, C_NONE);
        ui_text((char *)wcfg + WALL_NAME, x + 72, y + 11);
        break;
    case 2:
        *ui_num(ui_put(line, "Pattern "), wcfg[WALL_PAT] + 1, 0) = 0;
        spin(x, y, VW, line);
        ui_frame(x + VW + 40, y, 32, UI_BH);
        SetPattern(pats[wcfg[WALL_PAT] & 7]);
        WRectangle(x + VW + 41, y + 1, x + VW + 70, y + UI_BH - 2);
        break;
    case 3:
        spin(x, y, VW, colt[coli(tt.desk)]);
        ui_frame(x + VW + 40, y, 32, UI_BH);
        ui_color(x + VW + 40, y, 32, UI_BH, tt.desk);
        break;
    }
}

static void draw_dock(void);

/* the rows' area: the page's labels and controls */
static void draw_page(void)
{
    unsigned char r;
    unsigned int y = ry_of(0);
    ui_clear(ui_x0 + 8, y, W - 16, ry_of(NROW) + UI_BH - y);     /* (V127: the clock's line too) */
    ui_color(ui_x0 + 8, y, W - 16, ry_of(NROW) + UI_BH - y, C_NONE);
    if (page == 3)
        draw_dock();
    else if (page == 2) {
        for (r = 0; r < DROWS; ++r) {
            ui_text(dlabels[r], ui_x0 + LX, ry_of(r) + 11);
            draw_drow(r);
        }
        ui_text("Dark mode shows the picture's dark variant.", ui_x0 + LX, ry_of(DROWS) + 11);
        ui_text("Pictures: " VR_WALLDIR " (tools/mkwall.py).", ui_x0 + LX, ry_of(DROWS + 1) + 11);
    } else if (page) {
        for (r = 0; r < TROWS; ++r) {
            ui_text(tlabels[r], ui_x0 + LX, ry_of(r) + 11);
            draw_trow(r);
        }
        preview_theme();
    } else {
        for (r = 0; r < NROW; ++r) {
            ui_text(labels[r], ui_x0 + LX, ry_of(r) + 11);
            draw_row(r);
        }
    }
    ui_button(ui_x0 + 208, ui_y0 + ui_h - 24, 80, page ? "Settings" : "Theme", C_BTN);
    ui_button(ui_x0 + DBX, ui_y0 + ui_h - 24, 80, "Desktop", page == 2 ? C_SEL : C_BTN);
    ui_button(ui_x0 + LX, ui_y0 + ui_h - 24, 56, "Dock", page == 3 ? C_SEL : C_BTN);   /* (V163) */
}

static void tchange(unsigned char r, signed char d)
{
    unsigned char *c;
    if (r == 0) {
        for (c = (unsigned char *)preo; *c != tt.preset && c < preo + NPRE; ++c)
            ;
        tt.preset = c == preo + NPRE ? preo[d > 0 ? 0 : NPRE - 1]
            : preo[(c - preo + NPRE + d) % NPRE];
        theme_preset(&tt);
        say(presett[tt.preset]);
        draw_page();
        return;
    }
    if (r == TROWS - 1) {               /* light, dark: the palette at once */
        tt.dark ^= LOOK_DARK;
        theme.dark = tt.dark;
        theme.paper = papers[ipaper];
        theme.ink = inks[iink];
        theme_palette();
        say(tt.dark ? "DARK" : "LIGHT");
        draw_trow(r);
        return;
    }
    c = colp(r);
    *c = cols[(coli(*c) + NCOL + d) % NCOL];
    tt.preset = THEME_CUSTOM;
    draw_trow(0);
    draw_trow(r);
    preview_theme();
}

static void draw(void)
{
    ui_window("Preferences", W, ui_h);
    draw_page();
    WHorizontalLine(0xFF, ui_x0 + 8, ui_x0 + W - 9, ui_y0 + ui_h - 32);
    ui_button(bx(0), ui_y0 + ui_h - 24, 80, "Save", C_GREEN);
    ui_button(bx(1), ui_y0 + ui_h - 24, 80, "Close", C_BTN);
}

static unsigned char find(const unsigned int *t, unsigned char n, unsigned int v)
{
    unsigned char i;
    for (i = 0; i < n; ++i)
        if (t[i] == v)
            return i;
    return 0;
}

static void preview(void)
{
    if (!tt.dark)               /* (dark mode has its own paper and ink) */
        SetColors(papers[ipaper], inks[iink]);
}

/* the settings into p */
static void collect(void)
{
    p[0] = papers[ipaper] & 255;
    p[1] = papers[ipaper] >> 8;
    p[2] = inks[iink] & 255;
    p[3] = inks[iink] >> 8;
    p[4] = blanks[iblank] & 255;
    p[5] = blanks[iblank] >> 8;
    p[6] = (p[6] & (PREFS_NOSOUND | PREFS_MENUTICK | PREFS_POLISH | PREFS_SWITCH)) | ispeed;
    p[7] = imode < 3 ? imode : 0xFF;
    p[8] = tz;
    p[9] = idesk;
    p[PREFS_ACCENT] = tt.accent;
    p[PREFS_DESK] = tt.desk;
    p[PREFS_HILITE] = tt.hilite;
    p[PREFS_THEME] = THEME_SET | tt.preset;
    p[PREFS_LOOK] = LOOK_V2 | tt.dark;  /* (V74: Look 2's colours) */
}

/* from (in the applications' folder) copied to "to" in the system folder
   (an open stream keeps its folder) */
static unsigned char copy_file(const char *from, const char *to)
{
    static unsigned char buf[512];
    unsigned char a, b, e = 0;
    unsigned int n;
    vr_cd(VR_APPS);
    a = FOpen((void *)from, 'r');
    if (a < 2 || a > 9 || dosStatus >= 20)
        return FILE_NOT_FOUND;
    vr_cd(VR_SYS);
    b = FOpen((void *)to, 'w');
    if (b < 2 || b > 9 || dosStatus >= 20) {
        FClose(a);
        return DOS_ERROR;
    }
    while ((n = FRead(a, buf, sizeof buf)) != 0 && !e)
        e = FWrite(b, buf, n);
    FClose(a);
    if (FClose(b) && !e)
        e = DOS_ERROR;
    return e;
}

static void desktop(void)
{
    unsigned char e = 0;
    if (idesk) {
        e = copy_file("TopDesk.cvt", "DESKTOP.cvt");
        say(e ? "DESKTOP NOT COPIED" : "DESKTOP TOPDESK");
    } else if ((vr_cd(VR_SYS), FindFile("DESKTOP")) == 0) {
        e = FDelete("DESKTOP.cvt");
        say("DESKTOP SHELL");
    }
    sys_leave();
    if (e)
        ui_msg("The desktop could not be changed", "in the system folder.");
}

/* WALLPAPER.CFG (V78) into wcfg; without one: the plain colour (V132),
   Dusk the picture offered */
static void wall_read(void)
{
    unsigned char h;
    memset(wcfg, 0, sizeof wcfg);
    wcfg[0] = 'W';
    wcfg[1] = 'P';
    wcfg[2] = 1;
    wcfg[WALL_KIND] = WALL_DEFKIND;
    strcpy((char *)wcfg + WALL_NAME, WALL_DEFAULT);
    strcpy((char *)wcfg + WALL_DIR, VR_WALLDIR);
    sys_enter();
    h = FOpen(WALL_CFG, 'r');
    if (h >= 2 && h <= 9) {
        if (FRead(h, line, WALL_CFGLEN) == WALL_CFGLEN && line[0] == 'W' && line[1] == 'P' && line[2] == 1)
            memcpy(wcfg, line, WALL_CFGLEN);
        FClose(h);
    }
    wcfg[WALL_NAME + WALL_NAMELEN - 1] = 0;
    wcfg[WALL_DIR + WALL_DIRLEN - 1] = 0;
    if (wcfg[WALL_KIND] > WALL_PATTERN)
        wcfg[WALL_KIND] = WALL_PICTURE;
    wcfg[WALL_PAT] &= 7;
    sys_leave();
}

static unsigned char wall_save(void)
{
    unsigned char h, e = DOS_ERROR;
    char *q;
    sys_enter();
    h = FOpen(WALL_CFG, 'w');
    if (h >= 2 && h <= 9) {
        e = FWrite(h, wcfg, WALL_CFGLEN);
        if (FClose(h) && !e)
            e = DOS_ERROR;
    }
    sys_leave();
    q = ui_put(line, "DESKTOP ");
    q = ui_put(q, kindt[wcfg[WALL_KIND]]);
    *q++ = ' ';
    q = ui_put(q, (char *)wcfg + WALL_NAME);
    *q++ = ' ';
    *ui_num(q, wcfg[WALL_PAT], 0) = 0;
    say(line);
    return e;
}

/* Choose: a wallpaper of /VERANDA/WALLPAPERS (DBGETFILES: the GEOS
   documents of class Wallpaper) */
struct box4 {
    unsigned char pos;
    unsigned char t1, x1, y1;
    unsigned char t2, x2, y2;
    unsigned char t3, x3, y3;
    unsigned char end;
};
static const struct box4 wallBox = {
    DEF_DB_POS | 1,
    DBGETFILES, 4, 4,
    OPEN, DBI_X_2, DBI_Y_0,
    CANCEL, DBI_X_2, DBI_Y_2,
    0
};

static void choose(void)
{
    static char name[20];
    unsigned char r;
    if (ChDir(VR_WALLDIR)) {
        ui_msg("There is no folder", VR_WALLDIR ".");
        return;
    }
    name[0] = 0;
    r5 = (unsigned int)name;
    r7L = APPL_DATA;
    r10 = (unsigned int)WALL_CLASS;
    r = DoDlgBox((void *)&wallBox);
    sys_leave();
    if (r == DBGETFILES) {
        ui_msg("There are no pictures in", VR_WALLDIR ".");
        return;
    }
    if (r != OPEN || !name[0])
        return;
    strcpy((char *)wcfg + WALL_NAME, name);
    strcpy((char *)wcfg + WALL_DIR, VR_WALLDIR);
    wcfg[WALL_KIND] = WALL_PICTURE;
    *ui_put(ui_put(line, "PICTURE "), name) = 0;
    say(line);
    draw_page();
}

/* (V163) Dock: the shell's pinned programs, in their order, from and to
   its desk file (SHELL.DSK in the system's data folder: shell/dir.c's
   format, version 4; versions 1-3 read too); Add... (the Open box, in
   /VERANDA/APPS: an application), Remove, Move up, Move down; written by
   Save; the shell reads the pins again when the accessory closes */
#define DSKHDR  79              /* the windows' part, its last byte the pins' number */
#define PINDIR  62
#define PSZ     130             /* a pin: its folder (62), its file's name (68) */
#define DMAX    10              /* the shell's MAXPINS */
static unsigned char dsk[DSKHDR + DMAX * PSZ];
static unsigned char dn, dsel, ddirty;
static const char dskName[] = "SHELL.DSK";

static void dock_read(void)
{
    unsigned char h, i, v = 0;
    unsigned int n = 0;
    memset(dsk, 0, sizeof dsk);
    sys_enter();
    h = FOpen(dskName, 'r');
    if (h >= 2 && h <= 9) {
        n = FRead(h, dsk, sizeof dsk);
        FClose(h);
    }
    sys_leave();
    if (n >= DSKHDR && dsk[0] == 'V' && dsk[1] == 'S' && dsk[2] == 'D' && dsk[3] >= 1 && dsk[3] <= 4)
        v = dsk[3];
    dn = v ? dsk[DSKHDR - 1] : 0;
    if (dn > (v < 4 ? 4 : DMAX))
        dn = 0;
    if (v == 1)                         /* (names of 22 bytes) */
        for (i = dn; i-- > 0;) {
            memmove(dsk + DSKHDR + i * PSZ, dsk + DSKHDR + i * (PINDIR + 22), PINDIR + 22);
            memset(dsk + DSKHDR + i * PSZ + PINDIR + 21, 0, PSZ - PINDIR - 21);
        }
    if (!v) {                           /* (none yet: the shell's defaults
                                           for the rest) */
        memset(dsk, 0, DSKHDR);
        dsk[0] = 'V';
        dsk[1] = 'S';
        dsk[2] = 'D';
        dsk[16] = '/';
    }
    dsel = 0;
}

static unsigned char dock_write(void)
{
    unsigned char h, e = DOS_ERROR;
    dsk[3] = 4;
    dsk[DSKHDR - 1] = dn;
    sys_enter();
    h = FOpen(dskName, 'w');
    if (h >= 2 && h <= 9) {
        e = FWrite(h, dsk, DSKHDR + dn * PSZ);
        if (FClose(h) && !e)
            e = DOS_ERROR;
    }
    sys_leave();
    say(e ? "DOCK NOT SAVED" : "DOCK SAVED");
    return e;
}

static char *pin(unsigned char i)
{
    return (char *)dsk + DSKHDR + i * PSZ;
}

/* pin i's name, without ".cvt", into line */
static void pname(unsigned char i)
{
    unsigned char l;
    strcpy(line, pin(i) + PINDIR);
    l = strlen(line);
    if (l > 4 && line[l - 4] == '.')
        line[l - 4] = 0;
}

/* the gates: "PREFS DOCK a, b, ..." */
static void dock_say(void)
{
    static char t[80];
    unsigned char i;
    char *q = ui_put(t, "DOCK");
    for (i = 0; i < dn; ++i) {
        pname(i);
        if (q + strlen(line) + 3 >= t + sizeof t)
            break;
        q = ui_put(ui_put(q, i ? ", " : " "), line);
    }
    *q = 0;
    say(t);
}

#define DLW     288             /* the list's width */
#define DBX2    320             /* its buttons */
static unsigned char lh(void)
{
    return ui_h >= 400 ? 24 : 16;
}

static const char *const dbt[4] = { "Add...", "Remove", "Move up", "Move down" };


#define NAPPS   40              /* the picker's names (FindFTypes: GEOS names, 17 bytes) */
#define PCW     112             /* a name's column */
static char apps[NAPPS][17];
static unsigned char napps, picking;

/* the picker's first row (its line above) */
static unsigned int py0(void)
{
    return ry_of(0) + 20;
}

static void draw_dock(void)
{
    unsigned char i, h = lh();
    unsigned int x = ui_x0 + LX, y = ry_of(0);
    if (picking) {                      /* Add...: the applications of /VERANDA/APPS */
        ui_text("Click a program to add it (anywhere else: back).", x, y + 11);
        for (i = 0; i < napps; ++i)
            ui_text(apps[i], x + (i & 3) * PCW, py0() + (i >> 2) * (h - 2) + h / 2 + 2);
        return;
    }
    ui_frame(x, y, DLW, DMAX * h + 4);
    for (i = 0; i < dn; ++i) {
        if (i == dsel)
            ui_color(x + 2, y + 2 + i * h, DLW - 4, h, C_SEL);
        pname(i);
        ui_text(line, x + 8, y + 2 + i * h + h / 2 + 4);
    }
    for (i = 0; i < 4; ++i)
        ui_button(ui_x0 + DBX2, y + i * 24, 136, dbt[i], C_BTN);
    ui_text("In the dock's order.", ui_x0 + DBX2, y + 4 * 24 + 11);
    ui_text("Saved with Save.", ui_x0 + DBX2, y + 4 * 24 + 27);
}

/* Add...: the applications of /VERANDA/APPS listed to pick from */
static void dock_add(void)
{
    if (dn >= DMAX) {
        ui_msg("The dock is full:", "remove a program first.");
        return;
    }
    if (ChDir(VR_APPSDIR)) {
        ui_msg("There is no folder", VR_APPSDIR ".");
        return;
    }
    napps = NAPPS - FindFTypes(apps, APPLICATION, NAPPS, 0);
    sys_leave();
    picking = 1;
    say("DOCK PICK");
    draw_page();
}

/* program i of the picker added at the end */
static void dock_pick(unsigned char i)
{
    unsigned char j, e;
    picking = 0;
    if (i < napps) {
        *ui_put(ui_put(line, apps[i]), ".cvt") = 0;
        for (j = 0; j < dn; ++j)
            if (!strcmp(pin(j), VR_APPSDIR) && !strcmp(pin(j) + PINDIR, line)) {
                ui_msg("It is in the dock already.", "");
                i = 0xFF;
                break;
            }
        if (i != 0xFF) {
            ChDir(VR_APPSDIR);          /* (its file, by its long name) */
            longNames = LONG_NAMES;
            e = FindFile(apps[i]);
            longNames = 0;
            sys_leave();
            if (e)
                ui_msg("It is not in", VR_APPSDIR ".");
            else {
                memset(pin(dn), 0, PSZ);
                strcpy(pin(dn), VR_APPSDIR);
                strcpy(pin(dn) + PINDIR, line);
                dsel = dn++;
                ddirty = 1;
            }
        }
    }
    dock_say();
    draw_page();
}

/* pins i and i + 1 swapped */
static void dswap(unsigned char i)
{
    static unsigned char t[PSZ];
    memcpy(t, pin(i), PSZ);
    memcpy(pin(i), pin(i + 1), PSZ);
    memcpy(pin(i + 1), t, PSZ);
}

static void dock_press(void)
{
    unsigned char i, h = lh();
    unsigned int x = ui_x0 + LX, y = ry_of(0);
    if (picking) {
        i = 0xFF;
        if (ui_px >= x && ui_px < x + 4 * PCW && ui_py >= py0())
            i = (ui_py - py0()) / (h - 2) * 4 + (ui_px - x) / PCW;
        dock_pick(i);
        return;
    }
    if (ui_in(x, y + 2, DLW, dn * h)) {
        dsel = (ui_py - y - 2) / h;
        draw_page();
        return;
    }
    for (i = 0; i < 4; ++i)
        if (ui_in(ui_x0 + DBX2, y + i * 24, 136, UI_BH))
            break;
    if (i == 0) {
        dock_add();
        return;
    }
    if (i == 4 || dsel >= dn)
        return;
    if (i == 1) {
        memmove(pin(dsel), pin(dsel + 1), (dn - dsel - 1) * PSZ);
        if (--dn && dsel >= dn)
            dsel = dn - 1;
    } else if (i == 2) {
        if (!dsel)
            return;
        dswap(--dsel);
    } else {
        if (dsel + 1 >= dn)
            return;
        dswap(dsel++);
    }
    ddirty = 1;
    dock_say();
    draw_page();
}

static void set_clock(void);

static void save(void)
{
    unsigned char e, i;
    char *q;
    collect();
    e = sys_write("Veranda Prefs", "Veranda Prefs V1.0", "Veranda's settings (Preferences).", p, PREFS_SIZE);
    SysPrefs(PREFS_SET, p);
    vr_kbd();                           /* (V142: the ROM's key map, PL-PL) */
    desktop();
    e |= wall_save();
    if (ddirty && !(e |= dock_write()))     /* (V163) the Dock page */
        ddirty = 0;
    if (e) {
        ui_msg("The settings could not be written", "in the system folder.");
        return;
    }
    q = ui_put(line, "SAVED");
    for (i = 0; i < PREFS_SIZE; ++i) {
        *q++ = ' ';
        q = ui_num(q, p[i], 0);
    }
    say(line);
    ui_clear(ui_x0 + 76, ui_y0 + ui_h - 24, DBX - 76 - 4, 16);   /* (V163: right of Dock) */
    ui_text("Saved.", ui_x0 + 76, ui_y0 + ui_h - 13);
    if (cdirty)                         /* (V127: Save sets the clock too) */
        set_clock();
}

/* the clock's line, under the Time row (V127) */
static void clock_line(const char *s)
{
    unsigned int y = ry_of(NROW);
    ui_clear(ui_x0 + LX, y, W - 2 * LX, UI_BH);
    ui_text(s, ui_x0 + LX, y + 11);
}

/* the date and time from the clock (not pending, none picked) */
static void clock_read(void)
{
    dd = day;
    dm = month;
    dy = year;
    th = hour;
    tmi = minutes;
    if (!dm || dm > 12)
        dm = 1;
    if (!dd || dd > mdays(dy, dm))
        dd = 1;
    cdirty = 0;
    cfoc = 0xFF;
    ctn = 0;
}

static void clock_rows(void)
{
    if (page)
        return;
    draw_row(8);
    draw_row(9);
}

/* appMain (V127): the rows tick with the clock while not pending */
static void clock_tick(void)
{
    char *q;
    unsigned char k = cfoc;
    if (cdirty || (tmi == minutes && th == hour && dd == day))
        return;
    clock_read();
    cfoc = k;                           /* (a part picked stays picked) */
    clock_rows();
    q = ui_num(ui_put(line, "CLOCK TICK "), th, 2);
    *q++ = ':';
    ui_num(q, tmi, 2);
    say(line);
}

static void set_clock(void)
{
    unsigned int Y = 2000 + dy - (dm < 3);
    static const unsigned char t[12] = { 0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4 };
    unsigned char w = (Y + Y / 4 - Y / 100 + Y / 400 + t[dm - 1] + dd) % 7;   /* 0 Sunday */
    char *q;
    SetClock(100 + dy, dm, dd, th, tmi, 0, w + 1);
    q = ui_num(ui_put(line, "CLOCK SET "), th, 2);  /* (the gates: the time set) */
    *q++ = ':';
    ui_num(q, tmi, 2);
    say(line);
    /* what the clock reads back (SetClock reads it again), said under
       the rows (a click on Set clock showed nothing: hardware report) */
    if (day == dd && month == dm && year == dy && hour == th && minutes == tmi) {
        q = ui_put(line, "Clock set to ");
        q = ui_num(q, dd, 0);
        *q++ = ' ';
        q = ui_put(q, mon[dm - 1]);
        *q++ = ' ';
        q = ui_num(q, 2000 + dy, 0);
        *q++ = ' ';
        q = ui_num(q, th, 2);
        *q++ = ':';
        ui_num(q, tmi, 2);
        clock_line(line);
        say("CLOCK TOOK IT");
    } else {
        clock_line("The clock did not take the time");
        say("CLOCK NOT TAKEN");
    }
    cdirty = 0;
    cfoc = 0xFF;
    clock_rows();
}

/* row r's < (d = -1) or > (d = 1); for the date and time k: the part */
static void change(unsigned char r, unsigned char k, signed char d)
{
    if (r >= 8) {                       /* (V127: pending until Save) */
        cdirty = 1;
        ctn = 0;
    }
    switch (r) {
    case 0: iblank = (iblank + 8 + d) % 8; break;
    case 1: ipaper = (ipaper + 6 + d) % 6; preview(); break;
    case 2: iink = (iink + 6 + d) % 6; preview(); break;
    case 3:
        if (k == 0)
            p[6] ^= PREFS_NOSOUND;
        else if (k == 2)
            p[6] ^= PREFS_MENUTICK;
        else {                          /* the volume in steps of 9 */
            k = volume();
            k = d > 0 ? (k > 54 ? 63 : k + 9) : (k < 9 ? 0 : k - 9);
            p[PREFS_VOLUME] = PREFS_VOLSET | (63 - k);
        }
        break;
    case 4:
        if (k == 2)
            p[6] ^= PREFS_POLISH;       /* Keyboard: Polish (programmers), V142 */
        else
            ispeed = (ispeed + 3 + d) % 3;
        break;
    case 5:
        if (k == 2)
            p[6] = (p[6] & ~PREFS_SWITCH) | (roomy() ? PREFS_FAST : PREFS_ROOMY);
        else
            imode = (imode + 4 + d) % 4;
        break;
    case 6: if (topdesk || idesk) idesk ^= 1; break;
    case 7:
        if ((d > 0 && tz < 56) || (d < 0 && tz > -48))
            tz += d;
        break;
    case 8:
        if (k == 0)
            dd = dd + d < 1 ? mdays(dy, dm) : dd + d > mdays(dy, dm) ? 1 : dd + d;
        else if (k == 1)
            dm = (dm + 11 + d) % 12 + 1;
        else if ((d > 0 && dy < 99) || (d < 0 && dy))
            dy += d;
        if (dd > mdays(dy, dm))
            dd = mdays(dy, dm);
        break;
    case 9:
        if (k == 0)
            th = (th + 24 + d) % 24;
        else
            tmi = (tmi + 60 + d) % 60;
        break;
    }
    if (r >= 8)
        clock_rows();
    else
        draw_row(r);
}

/* part k (0-4) typed into: digit c; the value as far as it is valid,
   on to the next part when full */
static void digit(unsigned char c)
{
    unsigned char k = cfoc, v;
    ctb = ctn ? ctb * 10 + c : c;
    ++ctn;
    v = ctb % 100;
    switch (k) {
    case 0:
        if (v && v <= mdays(dy, dm))
            dd = v;
        break;
    case 1:
        if (v && v <= 12)
            dm = v;
        if (dd > mdays(dy, dm))
            dd = mdays(dy, dm);
        break;
    case 2:
        dy = v;
        if (dd > mdays(dy, dm))
            dd = mdays(dy, dm);
        break;
    case 3:
        if (v < 24)
            th = v;
        break;
    default:
        if (v < 60)
            tmi = v;
    }
    cdirty = 1;
    if (ctn >= (k == 2 ? 4 : 2) && k < 4) {
        ++cfoc;
        ctn = 0;
    }
    clock_rows();
}

static void pick(unsigned char k)
{
    cfoc = k;
    ctn = 0;
    clock_rows();
}

static void close_box(void)
{
    say("CLOSED");
    RstrAppl();
}

/*---------------------------------------------------------------
  the volume pop-up (deskNote DN_VOLUME: the bar's sound, V120)
 ---------------------------------------------------------------*/
#define PW      240             /* its size (whole cards) */
#define PH      48
#define PY      16              /* under the bar */
#define SLX     8               /* the slider: 64 steps of 2 pixels and the knob's 8 */
#define SLY     24
#define SLW     136
#define MX      152             /* Mute */
#define MW      80

static unsigned char drag, changed;
static unsigned int px0;

static void vol_value(void)
{
    unsigned int x = px0 + SLX, k = x + volume() * 2;
    ui_clear(px0 + PW - 48, PY + 4, 40, 16);
    ui_num(line, volume(), 0);
    ui_textc(line, px0 + PW - 48, 40, PY + 15);
    ui_clear(x, PY + SLY, SLW, 16);
    WHorizontalLine(0xFF, x, x + SLW - 1, PY + SLY + 7);
    WHorizontalLine(0xFF, x, x + SLW - 1, PY + SLY + 8);
    WVerticalLine(0xFF, x, PY + SLY + 4, PY + SLY + 11);
    WVerticalLine(0xFF, x + SLW - 1, PY + SLY + 4, PY + SLY + 11);
    SetPattern(1);
    WRectangle(k, PY + SLY, k + 7, PY + SLY + 15);
}

static void vol_mute(void)
{
    ui_button(px0 + MX, PY + SLY, MW, "Mute", p[6] & PREFS_NOSOUND ? C_SEL : C_BTN);
}

static void vol_say(void)
{
    *ui_num(ui_put(line, p[6] & PREFS_NOSOUND ? "VOLUME MUTED " : "VOLUME "), volume(), 0) = 0;
    say(line);
}

/* the volume v (0-63) given to the system at once */
static void vol_set(unsigned char v)
{
    if (v > 63)
        v = 63;
    if (v == volume())
        return;
    p[PREFS_VOLUME] = PREFS_VOLSET | (63 - v);
    SysPrefs(PREFS_SET, p);
    changed = 1;
    vol_value();
}

/* the short sound of a change (none when muted), and the console's line */
static void vol_tick(void)
{
    vol_say();
    PlaySound(SND_OPEN);
}

static void vol_x(void)
{
    int v = ((int)mouseXPos - (int)(px0 + SLX) - 4) / 2;
    vol_set(v < 0 ? 0 : v);
}

static void vol_mutes(void)
{
    p[6] ^= PREFS_NOSOUND;
    SysPrefs(PREFS_SET, p);
    changed = 1;
    vol_mute();
    vol_tick();
}

static void vol_close(void)
{
    if (changed) {
        if (sys_write("Veranda Prefs", "Veranda Prefs V1.0", "Veranda's settings (Preferences).", p,
                      PREFS_SIZE))
            say("NOT SAVED");
        else
            say("SAVED VOLUME");
    }
    close_box();
}

/* appMain: the drag, the wheel */
static void vol_main(void)
{
    signed char w = mouseWheel;
    unsigned char v = volume();
    if (drag && !(mouseData & 0x80))
        vol_x();
    if (w) {
        mouseWheel = 0;
        vol_set(w > 0 ? (v > w ? v - w : 0) : v - w);
        vol_tick();
    }
}

/* otherPressVec: presses and releases */
static void vol_press(void)
{
    if (!ui_press()) {
        if (drag) {
            drag = 0;
            vol_tick();
        }
        return;
    }
    if (!ui_in(px0, PY, PW, PH))
        vol_close();
    else if (ui_in(px0 + MX, PY + SLY, MW, UI_BH))
        vol_mutes();
    else if (ui_in(px0 + SLX - 4, PY + SLY - 4, SLW + 8, 24)) {
        drag = 1;
        vol_x();
    }
}

static void vol_key(void)
{
    unsigned char k = keyData, v = volume();
    if (k == 27 || k == 13)
        vol_close();
    else if (k == KEY_RIGHT || k == KEY_UP) {
        vol_set(v + 1);
        vol_tick();
    } else if ((k == KEY_LEFT && (keyDataMods & KEYM_ARROW)) || k == KEY_DOWN) {
        vol_set(v ? v - 1 : 0);
        vol_tick();
    } else if (k == ' ' || k == 'm')
        vol_mutes();
}

/* the pop-up at the sound (the pointer's card), inside the screen */
static void vol_open(void)
{
    px0 = mouseXPos & ~7;
    if (px0 > screenWidth - PW - 8)
        px0 = screenWidth - PW - 8;
    ui_theme();
    theme_menus();
    dispBufferOn = ST_WR_FORE;
    UseFont(FONT_UI);
    ui_clear(px0, PY, PW, PH);
    ui_color(px0, PY, PW, PH, C_NONE);
    ui_frame(px0, PY, PW, PH);
    WVerticalLine(0xFF, px0 + PW, PY + 1, PY + PH);        /* a lower right edge */
    WHorizontalLine(0xFF, px0 + 1, px0 + PW, PY + PH);
    ui_bold("Volume", px0 + SLX, PY + 15);
    vol_value();
    vol_mute();
    *ui_num(ui_put(line, "POPUP "), px0, 0) = 0;
    say(line);
    vol_say();
    otherPressVec = VR_FN(vol_press);
    keyVector = VR_FN(vol_key);
    appMain = VR_FN(vol_main);
}

/* otherPressVec */
static void press(void)
{
    unsigned char r, k;
    unsigned int x, y, w;
    if (!ui_press())
        return;
    if (ui_closebox()) {
        close_box();
        return;
    }
    if (ui_in(bx(0), ui_y0 + ui_h - 24, 80, UI_BH)) {
        save();
        return;
    }
    if (ui_in(bx(1), ui_y0 + ui_h - 24, 80, UI_BH)) {
        close_box();
        return;
    }
    if (ui_in(ui_x0 + 208, ui_y0 + ui_h - 24, 80, UI_BH)) {
        page = page ? 0 : 1;
        say(page ? "THEME PAGE" : "SETTINGS PAGE");
        draw_page();
        return;
    }
    if (ui_in(ui_x0 + DBX, ui_y0 + ui_h - 24, 80, UI_BH)) {
        page = 2;
        say("DESKTOP PAGE");
        draw_page();
        return;
    }
    if (ui_in(ui_x0 + LX, ui_y0 + ui_h - 24, 56, UI_BH)) {     /* (V163) */
        page = 3;
        say("DOCK PAGE");
        dock_say();
        draw_page();
        return;
    }
    if (page == 3) {
        dock_press();
        return;
    }
    if (page == 2) {
        for (r = 0; r < DROWS; ++r) {
            y = ry_of(r);
            x = ui_x0 + CX;
            if (ui_py < y || ui_py >= y + UI_BH)
                continue;
            if (r == 1) {
                if (ui_in(x, y, 64, UI_BH))
                    choose();
                return;
            }
            k = ui_in(x, y, 16, UI_BH) ? 0xFF : ui_in(x + 16 + VW, y, 16, UI_BH) ? 1 : 0;
            if (!k)
                return;
            if (r == 0)
                wcfg[WALL_KIND] = (wcfg[WALL_KIND] + 3 + (signed char)k) % 3;
            else if (r == 2) {
                wcfg[WALL_PAT] = (wcfg[WALL_PAT] + 8 + (signed char)k) & 7;
                wcfg[WALL_KIND] = WALL_PATTERN;
            } else {
                tt.desk = cols[(coli(tt.desk) + NCOL + (signed char)k) % NCOL];
                tt.preset = THEME_CUSTOM;
            }
            say(kindt[wcfg[WALL_KIND]]);
            draw_page();
            return;
        }
        return;
    }
    if (page) {
        for (r = 0; r < TROWS; ++r) {
            y = ry_of(r);
            x = ui_x0 + CX;
            if (ui_py < y || ui_py >= y + UI_BH)
                continue;
            if (ui_in(x, y, 16, UI_BH))
                tchange(r, -1);
            else if (ui_in(x + 16 + VW, y, 16, UI_BH))
                tchange(r, 1);
            return;
        }
        return;
    }
    for (r = 0; r < NROW; ++r) {
        y = ry_of(r);
        if (ui_py < y || ui_py >= y + UI_BH)
            continue;
        x = ui_x0 + CX;
        if (r == 3) {
            if (ui_in(x, y, 48, UI_BH))
                change(r, 0, 1);
            else if (ui_in(x + 56, y, 16, UI_BH))
                change(r, 1, -1);
            else if (ui_in(x + 104, y, 16, UI_BH))
                change(r, 1, 1);
            else if (ui_in(x + 128, y, 104, UI_BH))
                change(r, 2, 1);
            return;
        }
        if ((r == 4 || r == 5) && ui_in(x + 168, y, 120, UI_BH)) {
            change(r, 2, 1);
            return;
        }
        if (r == 9 && ui_in(x + 144, y, 48, UI_BH)) {
            clock_read();               /* Now (V127): the clock's time again */
            clock_rows();
            clock_line("");
            say("CLOCK NOW");
            return;
        }
        for (k = 0; k < (r >= 8 ? (r == 8 ? 3 : 2) : 1); ++k) {
            w = r < 8 ? VW : k == 2 ? 40 : 32;
            if (ui_in(x, y, 16, UI_BH)) {
                change(r, k, -1);
                return;
            }
            if (ui_in(x + 16 + w, y, 16, UI_BH)) {
                change(r, k, 1);
                return;
            }
            if (r >= 8 && ui_in(x + 16, y, w, UI_BH)) {
                pick(k + (r == 9 ? 3 : 0));     /* (V127: typed into) */
                return;
            }
            x += 72;
        }
        return;
    }
}

static void typed(void)
{
    unsigned char c = keyData, k = cfoc;
    if (c == 27)
        close_box();
    else if (c == 13)
        save();
    else if (page)
        return;
    else if (c == KEY_TAB)
        pick(k >= 4 ? 0 : k + 1);
    else if (k > 4)
        return;
    else if (c >= '0' && c <= '9')
        digit(c - '0');
    else if (c == KEY_UP || c == KEY_DOWN)
        change(k < 3 ? 8 : 9, k < 3 ? k : k - 3, c == KEY_UP ? 1 : -1);
    else if (c == KEY_LEFT) {           /* (Backspace: the part again) */
        ctn = 0;
        clock_rows();
    }
}

int main(void)
{
    unsigned char note = deskNote;      /* (V120: opened from the menu bar) */
    if (note == DN_VOLUME) {
        SysPrefs(PREFS_GET, p);
        vol_open();
#ifdef PREFS_TEST
        da_test_start();
#endif
        return 0;
    }
    if (screenWidth < 640) {
        ui_msg("Preferences needs a screen", "640 wide.");
        RstrAppl();
    }
    ui_h = screenHeight >= 400 ? 400 : 232;
    rh = ui_h >= 400 ? 32 : 16;
    ry = ui_h >= 400 ? 32 : 24;
    ui_x0 = ((screenWidth - W) / 2) & ~7;
    ui_y0 = ((screenHeight - ui_h) / 2) & ~7;
    SysPrefs(PREFS_GET, p);
    iblank = find(blanks, 8, p[4] | p[5] << 8);
    ipaper = find(papers, 6, p[0] | p[1] << 8);
    iink = find(inks, 6, p[2] | p[3] << 8);
    ispeed = p[6] & 3;
    imode = p[7] < 3 ? p[7] : 3;
    tz = p[8];
    theme_load();
    tt.accent = theme.accent;
    tt.desk = theme.desk;
    tt.hilite = theme.hilite;
    tt.preset = theme.preset > THEME_SUNROOM ? THEME_CUSTOM : theme.preset;
    tt.dark = theme.dark;
    vr_cd(VR_APPS);                     /* TopDesk with the applications, */
    topdesk = FindFile("TopDesk") == 0;
    vr_cd(VR_SYS);                      /* DESKTOP.cvt by the shell (V46, V71) */
    idesk = FindFile("DESKTOP") == 0;
    sys_leave();
    wall_read();
    dock_read();                        /* (V163) */
    clock_read();
    if (note == DN_CLOCK)               /* (V127: the day ready to type) */
        cfoc = 0;
    draw();
    if (note == DN_CLOCK || !year) {    /* (V120: the bar's clock; V127: never set)
                                           the Date and Time rows marked */
        ui_color(ui_x0 + 8, ry_of(8), CX - 16, rh + UI_BH, C_SEL);
        say("CLOCK ROWS");
    }
    if (!year) {
        clock_line("The clock is not set: set the date and time, then Save");
        say("CLOCK UNSET");
    }
    otherPressVec = VR_FN(press);
    keyVector = VR_FN(typed);
    appMain = VR_FN(clock_tick);
    say("RUNNING");
#ifdef PREFS_TEST
    da_test_start();
#endif
    return 0;
}
