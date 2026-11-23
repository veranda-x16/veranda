/* daui: the small toolkit Veranda's native desk accessories share
   (apps/dex, apps/calendar, apps/prefs; compiled into each of them).

   A window in the middle of the screen, card aligned (8 x 8 pixels, so
   the colour map can tint it: DECISIONS V30, V33), drawn on the
   foreground only (an accessory's start puts the application's screens
   aside, RstrAppl gives them back). The look: a white window with a
   one-pixel frame and a shadow, the SDK's title band (vrwin.h, V79: the
   title bold in the UI font, the close glyph at its right), buttons on
   chrome cards, fields in a frame with the caret
   at the end, selections in blue: Veranda Look 2's palette (sdk theme.h,
   DECISIONS V74; light or dark, as the settings have it). The title bar
   and the selections take the theme's accent and highlight (V65) when it
   has them; the Classic theme keeps the blue.

   Veranda Look 3 "Sunroom" (V148): the window's 3-pixel shadow (none in
   dark mode), buttons framed with their corners cut as the dialog boxes'.

   Also: message and question boxes (the SDK's vr_alert: the accessory's
   icon, which it sets in vr_alert_icon, a bold headline, an explanation),
   the system folder
   (/VERANDA, or the root without one) and small GEOS files written there
   whole (FOpen 'w' by a path: DECISIONS V54, V55).

   MIT licence (see LICENSE). */
#ifndef DAUI_H
#define DAUI_H
#include <vrpath.h>              /* the folders (DECISIONS V71) */

/* palette entries for the cards' paper (Look 2's: sdk theme.h) */
#define C_NONE   0              /* the normal paper */
#define C_YELLOW 6              /* YELLOW */
#define C_GREEN  8              /* GREEN */
#define C_BLUE   5              /* TITLE: light blue */
#define C_GREY   2              /* CHROME: light grey */
#define C_TITLE  ui_accent      /* the theme's accent (DECISIONS V65), else blue */
#define C_BTN    C_GREY
#define C_SEL    ui_sel         /* the theme's highlight, else SELECT */

extern unsigned char ui_accent, ui_sel;
/* the theme from the settings into ui_accent, ui_sel (ui_window does it) */
void ui_theme(void);

#define UI_BAR   16             /* the title bar's height */
#define UI_BH    16             /* a button's and a field's height */

extern unsigned int ui_x0, ui_y0, ui_w, ui_h;   /* the window */
extern unsigned char ui_tall;                   /* the screen has 400 lines or more */

unsigned int __fastcall__ ui_strw(const char *s);
/* the window, w x h (multiples of 8), in the middle of the screen */
void ui_window(const char *title, unsigned int w, unsigned int h);
/* x, y, w, h in pixels; colours by whole cards (x, y, w, h multiples of 8) */
void ui_clear(unsigned int x, unsigned int y, unsigned int w, unsigned int h);
void ui_color(unsigned int x, unsigned int y, unsigned int w, unsigned int h, unsigned char c);
void ui_frame(unsigned int x, unsigned int y, unsigned int w, unsigned int h);
/* text at its baseline; ui_textc centred in x .. x + w, clipped to w */
void ui_text(const char *s, unsigned int x, unsigned int y);
void ui_textc(const char *s, unsigned int x, unsigned int w, unsigned int y);
void ui_textw(const char *s, unsigned int x, unsigned int y, unsigned int w);
void ui_bold(const char *s, unsigned int x, unsigned int y);
/* a button (UI_BH high) on cards of colour c */
void ui_button(unsigned int x, unsigned int y, unsigned int w, const char *label, unsigned char c);
/* the pointer (when pressed: ui_px, ui_py) in a rectangle */
extern unsigned int ui_px, ui_py;
unsigned char ui_press(void);           /* a press (not a release): 1, ui_px/ui_py set */
unsigned char ui_in(unsigned int x, unsigned int y, unsigned int w, unsigned int h);
unsigned char ui_closebox(void);

/* a text field */
struct field {
    unsigned int x, y, w;
    char *buf;
    unsigned char max;
};
void ui_field(const struct field *f, unsigned char focus);
/* a key for the field: 1 if it changed (characters, Backspace) */
unsigned char ui_field_key(const struct field *f, unsigned char c);

/* boxes (vr_alert, V148): a headline a, an explanation b; a message (OK);
   a question: 1 for YES */
void ui_msg(const char *a, const char *b);
unsigned char ui_ask(const char *a, const char *b);

/* numbers: n as text (at least digits digits, 0 padded), the end */
char *ui_num(char *p, unsigned int n, unsigned char digits);
char *ui_put(char *p, const char *s);

/* the system's data folder (/VERANDA/.SYSTEM): into it (record files there), and back to the
   application's folder (curDirName, the shell's path that applications
   keep; the root without one) */
void sys_enter(void);
void sys_leave(void);
/* name (a GEOS name) as a sequential GEOS file of type SYSTEM in the
   system folder, written whole: 0 or an error */
unsigned char sys_write(const char *name, const char *cls, const char *desc,
                        const void *data, unsigned int len);
/* a record file in the current folder (opened; created empty first if
   there is none): 0 or an error; the application must have none open
   (ui_rec_busy: 1 if it has) */
unsigned char ui_rec_open(const char *name, const char *cls, const char *desc);
unsigned char ui_rec_busy(void);

#endif
