/* Veranda shell: the desktop's picture (overlay 11; Veranda Look 2,
   step C: DECISIONS V78; in full colour since V101).

   The desktop is a picture (a wallpaper file, tools/mkwall.py), the
   theme's plain desktop colour, or a GEOS pattern on it (the classic
   look), as WALL_CFG says (sdk wallcfg.h: Preferences' Desktop page; V180:
   the shell's Options > Desktop pattern is gone).

   A picture (version 2, V101) is VERA 4 bpp tiles of 8 x 8 pixels under
   the bitmap: the kernel's tile mode (ColorRect COLOR_TILES: layer 0's
   tiles at $13000-$16BFF, its map the colour map's). The shell reads the
   file's tiles (up to 480, 15,360 bytes) and its map (80 x 60 entries of
   2 bytes, 9,600) into four banks of its own (wallBank), its palette rows
   (2-13, light and dark) into this overlay, and puts the tiles into VRAM
   (wallmap.s, resident: it maps the banks) and the rows of the mode into
   the palette (row 15 the paper: a covered card's; row 14 a covered
   card's highlight, the kernel's). Wherever the desktop is drawn again
   (win.c: deskFill, when a window moves or closes, the whole screen) its
   bitmap is cleared (no ink: SetPattern 0, the kernel's rectangle, on the
   screens dispBufferOn selects; so the back screen holds it too and menus
   and dialog boxes recover from it) and its cards marked; win_colours
   (wall_flush) writes the marked cards' map entries before the icons'
   and the windows' colours (theirs are ColorRect's: a solid tile in row
   0). A window's shadow is one card of a solid colour on the picture as
   anywhere (V126: it was a 50% ink dither). Dark mode takes the dark rows (the same tiles and map).

   The file is read again only when the picture changes; the mode (light
   or dark) only writes the other rows. With the Classic theme (no colour
   map): the pattern; (V176) at 640 x 240 and 320 x 240 a picture is the
   plain tile desktop (the picture is 80 x 60 cards; Look 3's colour icons,
   its soft shadow; the colour chrome, gui.s, at 640 x 480 alone). A picture that
   cannot be read (gone, as the Meadow after V162, a version 1 file of
   V78's: re-make it, mkwall.py --from; a bad one) shows the plain desktop
   instead; WALL_CFG is not changed.

   The palette's rows 2-15 (entries 32-255) are a program's (the X16's
   colours unless it set its own): the shell copies them to VRAM_TILEPAL
   ($12C00) before it turns tile mode on, and the kernel puts them back
   when tile mode ends (ColorOff: a program's start, one put aside going
   on, BASIC, the shell's own plain desktop or pattern).

   Before a desk accessory that finds no RAM banks the picture's are lent
   to it (wall_drop) and read again after it, without drawing (the
   tiles in VRAM came back with the accessory's put-aside).

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <string.h>
#include <theme.h>
#include <wallcfg.h>
#include "shell.h"
#include "winp.h"
#pragma code-name ("OVERLAY11")
#pragma rodata-name ("OVL11RO")
#pragma data-name ("OVL11DATA")
#pragma bss-name ("OVL11BSS")

#define NDIRTY 8
#define NBANKS 4
#define VREG(a) (*(volatile unsigned char *)(a))

static unsigned char cfg[WALL_CFGLEN];          /* WALL_CFG as read */
static unsigned char key[WALL_CFGLEN];          /* the picture shown: its name and folder */
static unsigned char isShown = 0;               /* key is the picture shown (DATA: an
                                                   overlay's BSS is not cleared) */
static unsigned char loaded = 0;                /* the banks hold it */
static unsigned char upped = 0;                 /* VRAM holds its tiles */
static unsigned char v3;                        /* it is of version 3: the colour chrome (V102) */
static unsigned char isPlain = 0;               /* (V133) the one shown is the plain desktop */
static unsigned char fell;                      /* (V162) the plain desktop for a picture not read */
typedef char winSize[sizeof (struct win) == 225 ? 1 : -1];     /* (gui.s's WINSZ) */
static unsigned int tileLen;                    /* its tiles' bytes */
unsigned char wRows[2];                         /* its palette rows: the first, how many (look3.c */
#define row0 wRows[0]                           /* reads them from this bank: V153) */
#define rows wRows[1]
static unsigned char wpal[2][WALL_ROWS * 32];   /* its rows, light and dark */
static unsigned char dx0[NDIRTY], dy0[NDIRTY], dx1[NDIRTY], dy1[NDIRTY];
static unsigned char nd = 0;

/* the kernel reads strings and buffers below $A000 only: this overlay's
   own (at $A000) go through the resident part's str, buf and msg */
static char *k(const char *s)
{
    strcpy(str, s);
    return str;
}

/*---------------------------------------------------------------- the file */

static void defaults(void)
{
    memset(cfg, 0, sizeof cfg);
    cfg[0] = 'W';
    cfg[1] = 'P';
    cfg[2] = 1;
    cfg[WALL_KIND] = WALL_DEFKIND;
    cfg[WALL_PAT] = deskPat;
    strcpy((char *)cfg + WALL_NAME, WALL_DEFAULT);
    strcpy((char *)cfg + WALL_DIR, VR_WALLDIR);
}

/* WALL_CFG into cfg (the defaults without one) */
static void readCfg(void)
{
    unsigned char h;
    defaults();
    vr_cd(VR_DATA);
    h = FOpen(k(WALL_CFG), 'r');
    if (h >= 2 && h <= 9) {
        if (FRead(h, buf, WALL_CFGLEN) == WALL_CFGLEN && buf[0] == 'W' && buf[1] == 'P' && buf[2] == 1) {
            memcpy(cfg, buf, WALL_CFGLEN);
            cfg[WALL_NAME + WALL_NAMELEN - 1] = 0;
            cfg[WALL_DIR + WALL_DIRLEN - 1] = 0;
        }
        FClose(h);
    }
    ChDir(curDirName);
}

static void say(const char *what, const char *more)
{
    if (!testing)
        return;
    strcpy(msg, "\nSHELL WALLPAPER ");
    strcat(msg, what);
    if (more) {
        strcat(msg, " ");
        strcat(msg, more);
    }
    LogText(msg);
}

/* the emulator's cycle counter (a read of $9FB8 latches it; only in the
   gates: real hardware's expansion cards answer at $9FB0-$9FBF) */
static unsigned long cycles(void)
{
    unsigned long c = 0;
    unsigned char *p = (unsigned char *)&c;
    if (testing) {
        p[0] = VREG(0x9FB8);
        p[1] = VREG(0x9FB9);
        p[2] = VREG(0x9FBA);
        p[3] = VREG(0x9FBB);
    }
    return c;
}

/* port 0 at palette entry e (VRAM $1FA00 + 2e), increment 1 */
static void palAt(unsigned char e)
{
    VREG(0x9F25) = 0;
    VREG(0x9F20) = e << 1;
    VREG(0x9F21) = 0xFA + (e >> 7);
    VREG(0x9F22) = 0x11;
}

/* the picture's rows of the mode; row 15 (a covered card's) and 14 (its
   highlight, until the kernel makes it the highlight's) the paper */
static void palette(void)
{
    unsigned char a, b;
    unsigned int i;
    const unsigned char *p = wpal[theme.dark ? 1 : 0];
    palAt(0);
    a = VREG(0x9F23);
    VREG(0x9F20) = 1;                   /* (two reads in a row: cc65 may make them one) */
    b = VREG(0x9F23);
    palAt(row0 << 4);
    for (i = 0; i < rows * 32; ++i)
        VREG(0x9F23) = p[i];
    palAt(WALL_HIROW << 4);
    for (i = 0; i < 32; ++i) {
        VREG(0x9F23) = a;
        VREG(0x9F23) = b;
    }
}

static unsigned char tileMode(void)
{
    return VREG(0x9F2F) == WALL_TILEBASE;       /* L0_TILEBASE: the kernel's tile mode */
}

/* the picture of cfg into the banks; 0 if it cannot be read */
static unsigned char load(void)
{
    unsigned char h, ok = 0;
    unsigned int n;
    unsigned long t0 = cycles();
    if (!wallBank) {
        wallBank = BankAlloc(NBANKS);
        if (!wallBank) {
            say("NO BANKS", 0);
            return 0;
        }
    }
    loaded = upped = 0;
    if (ChDir(k((char *)cfg + WALL_DIR)) && ChDir(k(VR_WALLDIR)) && ChDir(k(VR_SYSDIR)))
        ChDir(k("/"));
    strcpy(tmp, (char *)cfg + WALL_NAME);
    strcat(tmp, ".cvt");
    h = FOpen(tmp, 'r');
    if (h < 2 || h > 9) {
        ChDir(curDirName);
        say("MISSING", tmp);
        return 0;
    }
    if (FRead(h, buf, 508 + WALL_HEAD) == 508 + WALL_HEAD && !memcmp(buf + 508, WALL_MAGIC, 4)
        && buf[514] == 80 && buf[515] == 60
        && (buf[512] == WALL_VERSION || buf[512] == 2)) {   /* (version 1: BAD; mkwall.py --from) */
        v3 = buf[512] == WALL_VERSION;          /* (version 2: no colour chrome, V102) */
        tileLen = (buf[516] | buf[517] << 8) << 5;
        row0 = buf[518];
        rows = buf[519];
        if (tileLen >= 16 * 32 && tileLen <= WALL_MAXTILES * 32 && row0 >= 2 && rows
            && rows <= WALL_ROWS && row0 + rows <= (v3 ? WALL_GUIROW : WALL_HIROW)
            && FRead(h, wpal[0], rows * 32) == rows * 32           /* (into this bank: FRead */
            && FRead(h, wpal[1], rows * 32) == rows * 32           /* writes to the bank mapped) */
            && bfread(wallBank + 2, h, 51 * 160) == 51 * 160
            && bfread(wallBank + 3, h, 9 * 160) == 9 * 160) {
            n = tileLen > 8192 ? 8192 : tileLen;
            ok = bfread(wallBank, h, n) == n;
            if (ok && tileLen > 8192)
                ok = bfread(wallBank + 1, h, tileLen - 8192) == tileLen - 8192;
        }
    }
    FClose(h);
    ChDir(curDirName);
    if (!ok) {
        say("BAD", tmp);
        return 0;
    }
    loaded = 1;
    if (testing) {
        t0 = cycles() - t0;
        strcpy(str, "READ IN ");
        num(t0, str + strlen(str));
        say(tmp, str);
    }
    return 1;
}

/* (Look 3, V133) the plain desktop as a picture of one tile: tiles 0-15
   solid, tile 16 entry 1 of palette row 2 (the theme's desktop colour,
   light and dark: plainPal), the map every card tile 16 in row 2; so
   the colour chrome (V102) and the colour icons (look3.c) have tile
   mode, and tiles 17-479 are the icons' */
static void plainPal(void)
{
    unsigned int c;
    unsigned char d;
    memset(wpal, 0, sizeof wpal);
    for (d = 0; d < 2; ++d) {
        c = theme.desk ? theme_colour(theme.desk, d) : (d ? 0x334 : theme.paper);
        wpal[d][2] = c;
        wpal[d][3] = c >> 8;
    }
}

static unsigned char plain(void)
{
    if (!wallBank) {
        wallBank = BankAlloc(NBANKS);
        if (!wallBank) {
            say("NO BANKS", 0);
            return 0;
        }
    }
    upped = 0;
    XCALL(bIc2, ic3_plain, FB)(wallBank);
    tileLen = 17 * 32;
    row0 = 2;
    rows = 1;
    v3 = 1;
    loaded = 1;
    return 1;
}

/* the program's rows (entries 32-255) to VRAM_TILEPAL: the kernel puts
   them back when tile mode ends */
static void keep(void)
{
    unsigned int i;
    palAt(32);
    VREG(0x9F25) = 1;
    VREG(0x9F20) = 0x00;
    VREG(0x9F21) = 0x2C;
    VREG(0x9F22) = 0x11;
    VREG(0x9F25) = 0;
    for (i = 0; i < 448; ++i)
        VREG(0x9F24) = VREG(0x9F23);
}

/*---------------------------------------------------------------- the calls */

/* WALL_CFG read; the desktop's kind set (wallMode), the picture read
   when it changed, tile mode on, its tiles and palette rows set (after
   look_load: the theme set entries 0-15); 1 if the desktop is not as it
   was shown */
unsigned char wall_load(void)
{
    unsigned char m = wallMode, pat = deskPat, same, pl;
    unsigned long t0;
    readCfg();
    /* (V176) at 640 x 240 and 320 x 240 (graphMode not MODE_640x480, 0) a
       picture (80 x 60 cards) is the plain tile desktop: its colour icons */
    pl = cfg[WALL_KIND] == WALL_PLAIN || (graphMode && cfg[WALL_KIND] == WALL_PICTURE);
    if (cfg[WALL_KIND] == WALL_PATTERN && cfg[WALL_PAT] < 8)
        deskPat = cfg[WALL_PAT];
    if ((cfg[WALL_KIND] == WALL_PICTURE || pl) && !lookNone) {
        same = isShown && pl == isPlain && (pl || !memcmp(key + WALL_NAME, cfg + WALL_NAME, WALL_CFGLEN - WALL_NAME));
        if (!(same && loaded)) {        /* (the same one after a desk accessory: read again) */
            isShown = 0;
            fell = !pl && !load();      /* (V162) a picture that cannot be read: the plain desktop */
            if ((pl | fell) && !plain())
                goto pattern;
            memcpy(key, cfg, WALL_CFGLEN);
            isShown = 1;
            isPlain = pl;
            ColorRect(0, 0, 0, 0, 0xFF);        /* (V168) the map made afresh below, all
                                                   drawn again: another picture, or this one
                                                   read again after a desk accessory had its
                                                   banks (its covers' marks were stale) */
        }
        pl |= fell;
        t0 = cycles();
        if (!tileMode()) {
            keep();
            ColorRect(0, 0, 0, 0, COLOR_TILES);         /* (the map cleared: drawn again) */
            m = 0xFF;
            upped = 0;
        }
        if (!upped) {
            wmBank = wallBank;
            wmLen = tileLen;
            wall_up();
            if (v3) {                   /* the chrome's pool (V102) */
                XCALL(bBars, gui_artA, FV)();
                XCALL(bPrint, gui_artB, FV)();
                gui_init();
            }
            XCALL(bLook3, ic3_reset, FB)(pl | 2);   /* (the colour icons: V133; 2 a picture, V153) */
            upped = 1;
        }
        guiOn = v3 && !graphMode;       /* (V176: the colour chrome's art is 640 x 480's) */
        if (pl)
            plainPal();
        palette();
        if (v3)
            gui_pal();
        XCALL(bLook3, ic3_pal, FV)();
        if (testing && m == 0xFF) {
            t0 = cycles() - t0;
            strcpy(str, theme.dark ? "DARK, TILES IN " : "LIGHT, TILES IN ");
            num(t0, str + strlen(str));
            say("ON", str);
        }
        wallMode = W_PICTURE;
    } else {
pattern:
        guiOn = 0;
        XCALL(bLook3, ic3_reset, FB)(0);
        wallMode = cfg[WALL_KIND] == WALL_PLAIN ? W_PLAIN : W_PATTERN;
        if (tileMode()) {               /* (the colour map of before: ColorRect turns it on;
                                           the kernel puts the program's rows back) */
            ColorRect(0, 0, 0, 0, 0xFF);
            m = 0xFF;
        }
    }
    if (m != wallMode)
        say(wallMode == W_PICTURE ? (pl ? "PLAIN TILES" : "SHOWN") : wallMode == W_PLAIN ? "PLAIN" : "PATTERN", 0);
    return m != wallMode || pat != deskPat;
}

/* the picture's banks given back (a desk accessory needs them) */
unsigned char wall_drop(void)
{
    if (!wallBank)
        return 0;
    BankFree(wallBank);
    wallBank = 0;
    loaded = 0;
    say("DROPPED", 0);
    return 1;
}

/* the picture in pixels l-r, rows t-b (in the clip: deskFill), on the
   screens dispBufferOn selects: no ink there (the kernel's fill with the
   clip off: whole rows, through VERA's FX cache where it has it); its
   cards marked for wall_flush */
void wall_fill(unsigned int l, unsigned int t, unsigned int r, unsigned int b)
{
    unsigned char bx = l >> 3, k, c = clipOn;
    clipOn = 0;
    SetPattern(0);
    WRectangle(l, t, r, b);
    clipOn = c;
    /* the cards (merged into the last when there are too many) */
    if (nd < NDIRTY) {
        k = nd++;
        dx0[k] = bx;
        dy0[k] = t >> 3;
        dx1[k] = r >> 3;
        dy1[k] = b >> 3;
        return;
    }
    k = NDIRTY - 1;
    if (bx < dx0[k])
        dx0[k] = bx;
    if (t >> 3 < dy0[k])
        dy0[k] = t >> 3;
    if (r >> 3 > dx1[k])
        dx1[k] = r >> 3;
    if (b >> 3 > dy1[k])
        dy1[k] = b >> 3;
}

/* the map entries of the cards drawn since the last time (win_colours:
   before the icons' and the windows') */
void wall_flush(void)
{
    unsigned char i, x0, x1, y0, y1;
    for (i = 0; i < nd; ++i) {
        x0 = dx0[i];
        x1 = dx1[i];
        y0 = dy0[i] < 2 ? 2 : dy0[i];
        y1 = dy1[i];
        if (x1 > 79)
            x1 = 79;
        if (y1 > 59)
            y1 = 59;
        if (x0 > x1 || y0 > y1)
            continue;
        wmBank = wallBank;
        wmX = x0;
        wmW = x1 - x0 + 1;
        wmY = y0;
        wmH = y1 - y0 + 1;
        wall_map();
    }
    nd = 0;
}

/* the gates (a script's end 2, play.s): the screen to SHOT.BMP in the top
   folder (ExportRect: 8 bpp on the picture), SHELL SHOT and the error,
   then the end (SHELL DONE, the dump) */
void wall_shot(void)
{
    unsigned char e;
    play_shot = 0;
    ChDir(k("/"));
    strcpy(tmp, "SHOT.BMP");
    e = ExportRect(tmp, 0, 0, screenWidth - 1, screenHeight - 1, 0x80);
    strcpy(msg, "\nSHELL SHOT 0");
    msg[13] += e;
    LogText(msg);
    play_done();
}
