/* Veranda's colour theme for native programs (DECISIONS V65, V74), in
   lib/veranda.lib.

   Veranda Look 2 (V74): a palette of 16 entries for Veranda's own
   programs (theme_palette), light or dark (a palette swap: nothing is
   drawn again), and on it a theme: three paper colours of the colour map
   (ColorRect: a palette entry 0-15 per 8 x 8 card; the ink stays one
   colour), chosen in Preferences and kept in the kernel's settings block
   (SysPrefs, bytes 10-14):
     accent   title bars
     desk     the area behind windows (the shell's desktop)
     hilite   selections, and an open menu (the menu bar: theme_menus)
   0 is "none" (the normal paper). Presets: Sunroom (Look 3, V132: the
   default, also for a settings block without a theme: a sage desktop,
   light title bands, blue-grey selections), Veranda (Look 2's default),
   Classic (no colours: no colour map at all, the old look), Graphite,
   Mint.

   The menu bar of a native program is chrome (CHROME) with the
   Veranda mark on cyan (CYAN): the kernel draws it (uiLook,
   theme_menus).

   Only for Veranda's own programs: ports of GEOS programs keep their
   look. */
#ifndef THEME_H
#define THEME_H

/* Look 2's palette entries (theme_palette sets them) */
#define PAPER   0            /* $FFF (the settings' paper)  dark $334 */
#define INK     1            /* $223 (the settings' ink)    dark $EEF */
#define CHROME  2            /* $DDE bars, buttons          dark $223 */
#define SIDEBAR 3            /* $EEF                        dark $223 */
#define SELECT  4            /* $9CF selections             dark $357 */
#define TITLE   5            /* $ACE title bars             dark $346 */
#define YELLOW  6            /* $FD5                        dark $A82 */
#define RED     7            /* $F87                        dark $A44 */
#define GREEN   8            /* $8D9                        dark $385 */
#define PURPLE  9            /* $B9F                        dark $649 */
#define ORANGE 10            /* $FA5                        dark $A62 */
#define CYAN   11            /* $6CE the Veranda mark       dark $278 */
#define SKY    12            /* $36A                        dark $124 */
#define SKY2   13            /* $8BE                        dark $247 */
#define HILL   14            /* $7A8 (Look 3: sage)         dark $343 */
#define SAGE   14            /* (Look 3, Sunroom: the desktop; V132) */
#define DUSK   15            /* $DAC                        dark $535 */

/* the settings block's bytes (SysPrefs PREFS_GET, PREFS_SET) */
#define PREFS_ACCENT  10
#define PREFS_DESK    11
#define PREFS_HILITE  12
#define PREFS_THEME   13        /* $80 + the preset: a theme is stored */
#define THEME_SET     0x80
#define PREFS_LOOK    14        /* (V74) the look: */
#define LOOK_V2       0x80      /*   bytes 10-12 are Look 2's entries (a
                                     block saved before has the old UI
                                     palette's: theme_load converts them) */
#define LOOK_DARK     0x01      /*   dark mode */

/* the presets */
#define THEME_VERANDA  0        /* title bars sky blue, selections blue */
#define THEME_BLUE     0        /* (V65's name of preset 0) */
#define THEME_CLASSIC  1        /* no colours */
#define THEME_GRAPHITE 2        /* chrome bars and selections */
#define THEME_MINT     3        /* green bars and selections */
#define THEME_CUSTOM   4        /* colours chosen one by one */
#define THEME_SUNROOM  5        /* (V132) Look 3: sage desktop, mist title bands, sky selections */
#define THEME_PRESETS  4        /* the presets 0-3 ... */
#define THEME_NPRESET  6        /* ... and Sunroom (5): theme_preset takes 0-3 and 5 */

struct theme {
    unsigned char accent, desk, hilite;
    unsigned char preset;
    unsigned char dark;         /* LOOK_DARK or 0 */
    unsigned int paper, ink;    /* the settings' (bytes 0-3) */
};
extern struct theme theme;

/* the theme from the running system's settings (SysPrefs) into theme */
void theme_load(void);
/* a preset's colours into t (preset < THEME_PRESETS or THEME_SUNROOM) */
void __fastcall__ theme_preset(struct theme *t);
/* palette entries 2-15 Look 2's, light or dark (theme.dark); 0 and 1 the
   settings' paper and ink, or dark mode's */
void theme_palette(void);
/* 1 if the theme has no colours (Classic) */
unsigned char theme_none(void);
/* ColorRect(x, w, y, h, c) in cards, but nothing when c is 0 and the
   colour map is not shown (a Classic theme turns no colour map on) */
void theme_rect(unsigned char x, unsigned char w, unsigned char y, unsigned char h, unsigned char c);
/* 1 if the colour map is shown (VERA's layer 1 is on: the bitmap moved
   up over the map, DECISIONS V30) */
unsigned char theme_map_on(void);
/* the program's menus in the Veranda look (uiLook: the menu bar, open
   menus in the highlight colour; call it before DoMenu; DECISIONS V74).
   A program whose palette is not Look 2's (theme_look2() is 0: Paint's
   colours are its pictures') gets the bar in black and white (V79).
   The menus and the program's dialog boxes are in the UI font (uiFont =
   FONT_UI, V79). */
void theme_menus(void);
/* 1 if palette entries 2-15 are Look 2's (this program called
   theme_palette): the colours a program's chrome and the SDK's dialog
   may use */
unsigned char theme_look2(void);
/* (V79) colours inside a box over the colour map (a dialog box: DoDlgBox
   covers its cards, DECISIONS V33): written straight into the map's
   attributes, as the kernel's menu highlight is, so they go when the box
   goes (RstrFrmDialogue uncovers the cards and gives them their own
   colours back); nothing when the map is not shown. Cards, as ColorRect. */
void theme_cover_rect(unsigned char x, unsigned char w, unsigned char y, unsigned char h, unsigned char c);
/* palette entry i's colour ($0RGB) in Look 2, light (dark 0) or dark */
unsigned int __fastcall__ theme_colour(unsigned char i, unsigned char dark);

#endif
