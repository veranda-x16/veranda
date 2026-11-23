/* Veranda shell: its colours, from the theme (sdk theme.h, DECISIONS V65).

   Veranda Look 2 (DECISIONS V74): the palette (light or dark) and the
   menu bar in the Veranda look (uiLook: the kernel draws it full width
   on the chrome, the mark, the clock; an open menu in the highlight
   colour). The windows' title bars on the accent, the desktop on the
   desktop colour, the windows' insides on the normal paper, the selected
   icon's cards on the highlight colour (without one: inverted). All
   through the colour map's paper (ColorRect); the ink stays the one ink.
   A Classic theme turns no colour map on: the shell in black and white.

   The bar's cards are not covered by the main menu (the kernel, V74);
   its sub menus and the dialog boxes cover theirs, and the kernel gives
   them back when they close (V33).

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <theme.h>
#include "shell.h"

static char line[24];
unsigned char lookNone;          /* Classic: no colours at all (Look 2: DECISIONS V77) */
unsigned char fontSmall = FONT_UI;  /* (Look 3, V132) Gate Sans 9: labels, the status bar */
static const char smallName[] = "Gate Sans";

static char *dec(char *p, unsigned char n)
{
    if (n >= 10)
        *p++ = '1';
    *p++ = '0' + n % 10;
    return p;
}

/* the theme from the settings; 1 if it is not the one shown */
unsigned char look_load(void)
{
    unsigned char a = theme.accent, d = theme.desk, h = theme.hilite, k = theme.dark;
    const char *s = "\nSHELL THEME ";
    char *p = line;
    theme_load();
    lookNone = theme_none();
    fontSmall = LoadFont((void *)smallName, 9);    /* (once: then kept by the font service, V62) */
    if (fontSmall == FONT_NONE)
        fontSmall = FONT_UI;
    theme_palette();
    theme_menus();
    while (*s)
        *p++ = *s++;
    p = dec(p, theme.accent);
    *p++ = ' ';
    p = dec(p, theme.desk);
    *p++ = ' ';
    p = dec(p, theme.hilite);
    if (theme.dark) {
        s = " DARK";
        while (*s)
            *p++ = *s++;
    }
    *p = 0;
    LogText(line);
    return a != theme.accent || d != theme.desk || h != theme.hilite || k != theme.dark;
}

/* before the screen is drawn: a theme without colours (Classic) shows
   no colour map (one shown before, by another theme, hidden) */
void look_off(void)
{
    if (theme_none() && theme_map_on())
        ColorRect(0, 0, 0, 0, 0xFF);
}

/* look_rect: clip.s (the colour clip, V81) */

/* a rounded frame (Look 2, DECISIONS V77): the corners' rows inset as
   PIL's rounded rectangles of radius 3, 4 and 6 are (the mockups') */
static const unsigned char in3[] = { 2, 1, 0 };
static const unsigned char in4[] = { 3, 1, 1, 0 };
static const unsigned char in6[] = { 4, 3, 2, 1, 0 };

void shell_rframe(unsigned int l, unsigned int t, unsigned int r, unsigned int b, unsigned char rad)
{
    const unsigned char *a = rad <= 3 ? in3 : rad == 4 ? in4 : in6;
    unsigned char n = rad <= 3 ? 3 : rad == 4 ? 4 : 5, j, x0, x1;
    WHorizontalLine(0xFF, l + a[0], r - a[0], t);
    WHorizontalLine(0xFF, l + a[0], r - a[0], b);
    WVerticalLine(0xFF, l, t + n - 1, b - n + 1);
    WVerticalLine(0xFF, r, t + n - 1, b - n + 1);
    for (j = 1; j < n - 1; ++j) {
        x0 = a[j];
        x1 = a[j - 1] > a[j] + 1 ? a[j - 1] - 1 : a[j];
        WHorizontalLine(0xFF, l + x0, l + x1, t + j);
        WHorizontalLine(0xFF, r - x1, r - x0, t + j);
        WHorizontalLine(0xFF, l + x0, l + x1, b - j);
        WHorizontalLine(0xFF, r - x1, r - x0, b - j);
    }
}
