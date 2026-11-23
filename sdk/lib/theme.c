/* Veranda's colour theme (theme.h, DECISIONS V65, V74). MIT licence. */
#include <veranda.h>
#include "theme.h"

struct theme theme;

/* Veranda Look 2's palette (the proposal's LIGHT and DARK) */
const unsigned int theme_look_[2][16] = {     /* (themedraw.c: theme_palette) */
    { 0x0FFF, 0x0223, 0x0DDE, 0x0EEF, 0x09CF, 0x0ACE, 0x0FD5, 0x0F87,
      0x08D9, 0x0B9F, 0x0FA5, 0x06CE, 0x036A, 0x08BE, 0x07A8, 0x0DAC },
    { 0x0334, 0x0EEF, 0x0223, 0x0223, 0x0357, 0x0346, 0x0A82, 0x0A44,
      0x0385, 0x0649, 0x0A62, 0x0278, 0x0124, 0x0247, 0x0343, 0x0535 },
};

static const unsigned char presets[THEME_NPRESET][3] = {
    { TITLE, SKY2, SELECT },   /* Veranda */
    { 0, 0, 0 },                        /* Classic */
    { CHROME, SIDEBAR, CHROME },       /* Graphite */
    { GREEN, 0, GREEN },          /* Mint */
    { 0, 0, 0 },                        /* (Custom: its own colours) */
    { SIDEBAR, SAGE, TITLE },          /* Sunroom (Look 3, V132): mist title bands, sage desktop, sky selections */
};

/* a custom theme saved before V74: its colours were the old UI palette's
   (the X16's with 7, 13, 14, 15 softened); the nearest of Look 2's */
static const unsigned char old2[16] = {
    0, 0, 0, CYAN, 0, 0, 0, YELLOW, ORANGE, 0, RED, 0, CHROME,
    GREEN, TITLE, CHROME
};

unsigned int __fastcall__ theme_colour(unsigned char i, unsigned char dark)
{
    return theme_look_[dark ? 1 : 0][i & 15];
}

void __fastcall__ theme_preset(struct theme *t)
{
    const unsigned char *c = presets[t->preset];
    t->accent = c[0];
    t->desk = c[1];
    t->hilite = c[2];
}

void theme_load(void)
{
    static unsigned char p[PREFS_SIZE];
    SysPrefs(PREFS_GET, p);
    theme.paper = p[0] | p[1] << 8;
    theme.ink = p[2] | p[3] << 8;
    theme.dark = p[PREFS_LOOK] & LOOK_DARK;
    theme.preset = p[PREFS_THEME] & 7;
    if (!(p[PREFS_THEME] & THEME_SET)) {
        theme.preset = THEME_SUNROOM;   /* no theme saved: Sunroom (Look 3, V132) */
        theme_preset(&theme);
    } else if (p[PREFS_LOOK] & LOOK_V2) {
        theme.accent = p[PREFS_ACCENT] & 15;
        theme.desk = p[PREFS_DESK] & 15;
        theme.hilite = p[PREFS_HILITE] & 15;
    } else if (theme.preset < THEME_CUSTOM) {
        theme_preset(&theme);           /* (V65's presets: Look 2's) */
    } else {
        theme.preset = THEME_CUSTOM;
        theme.accent = old2[p[PREFS_ACCENT] & 15];
        theme.desk = old2[p[PREFS_DESK] & 15];
        theme.hilite = old2[p[PREFS_HILITE] & 15];
    }
}

unsigned char theme_none(void)
{
    return !(theme.accent | theme.desk | theme.hilite);
}

#define VCTRL  (*(volatile unsigned char *)0x9F25)
#define VADDRL (*(volatile unsigned char *)0x9F20)
#define VADDRM (*(volatile unsigned char *)0x9F21)
#define VADDRH (*(volatile unsigned char *)0x9F22)
#define VDATA0 (*(volatile unsigned char *)0x9F23)
#define VVIDEO (*(volatile unsigned char *)0x9F29)

/* set by theme_palette (themedraw.c): the program's palette is Look 2's */
unsigned char theme_lk2;

unsigned char theme_look2(void)
{
    return theme_lk2;
}

void theme_menus(void)
{
    uiLook = LOOK_BAR | (theme_look2() ? theme.hilite : 0);
    uiFont = FONT_UI;                   /* (V79: menus and dialog boxes in the UI font) */
}
