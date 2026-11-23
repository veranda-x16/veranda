/* Veranda SDK: window chrome for native programs (lib/veranda.lib;
   Veranda Look 2, DECISIONS V79), the shell's windows' parts (V77)
   for a program's own window:
     - the title band (2 card rows, the theme's accent; chrome when the
       window is not in front): the title centred, bold, in the UI font;
       a square close box at the right (VW_CLOSE; Sunroom, V146);
     - a toolbar (tool card rows of chrome under the title band, a line
       under it; the program draws its tools on it);
     - the body (the program's);
     - a status bar (status card rows of chrome at the bottom, a line
       over it): a text at its left and one at its right, in the UI font;
     - a frame round it (VW_FRAME) and a shadow right and below
       (VW_SHADOW: a 4-pixel ink dither, outside the window).
   Every band is whole cards, so it takes one colour of the colour map
   (ColorRect; the Classic theme gets none). It calls theme_load. The
   drawing goes where dispBufferOn says; it ends with the system font. */
#ifndef VRWIN_H
#define VRWIN_H

struct vrwin {
    unsigned char x, y;         /* the left card, the top card row */
    unsigned char w, h;         /* cards, card rows */
    unsigned char tool;         /* the toolbar's card rows (0: none) */
    unsigned char status;       /* the status bar's card rows (0: none; 2) */
    unsigned char flags;
};
#define VW_CLOSE  1             /* a close glyph in the title band */
#define VW_FRAME  2             /* a frame round the window */
#define VW_SHADOW 4             /* a shadow right and below */
#define VW_BACK   8             /* the window is not in front: its title
                                   band chrome, its title plain */

/* the whole window: the bands cleared, their colours, the lines, the
   title (the body is cleared to the paper) */
void __fastcall__ vr_win(const struct vrwin *w, const char *title);
/* the title band again (a new title) */
void __fastcall__ vr_win_title(const struct vrwin *w, const char *title);
/* the status bar's texts again (left, right: either may be 0) */
void __fastcall__ vr_win_status(const struct vrwin *w, const char *left, const char *right);

/* where x, y is in the window: */
#define VW_OUT    0
#define VW_TITLE  1             /* the title band (to drag a window by) */
#define VW_XCLOSE 2             /* the close glyph */
#define VW_TOOL   3
#define VW_BODY   4
#define VW_STATUS 5
unsigned char __fastcall__ vr_win_hit(const struct vrwin *w, unsigned int x, unsigned int y);

/* the menu bar (the kernel's, DECISIONS V74) as a title band, for a
   program whose body fills the screen under it (Paint: its picture,
   592 x 464): vr_bar_end is where the kernel ends the bar's items (their
   texts, bold item 0, in the menus' font: the UI font); vr_bar_title
   draws s centred, bold, between x0 and the bar's clock (on both
   screens; draw it again after DoMenu) */
unsigned int __fastcall__ vr_bar_end(const char *const *names, unsigned char n);
void __fastcall__ vr_bar_title(const char *s, unsigned int x0);

/* the body's top and bottom lines */
unsigned int __fastcall__ vr_win_top(const struct vrwin *w);
unsigned int __fastcall__ vr_win_bottom(const struct vrwin *w);

/* (V146, Sunroom) a scroll bar, 2 cards across (lib/veranda.lib: its own
   object, vrscroll.c): a 16 x 16 arrow box at each end, the track in the
   chrome's colour, a framed thumb with a grip; its size and place show
   first .. first + shown of total (no thumb when all is shown) */
struct vrscroll {
    unsigned char cx, cy;       /* its first card, card row */
    unsigned char len;          /* its length in cards (at least 6) */
    unsigned char vert;         /* 1: vertical (down from cy), 0: across from cx */
    unsigned int first, shown, total;
};
void __fastcall__ vr_scroll(const struct vrscroll *s);
/* where x, y is on it: */
#define VS_OUT    0
#define VS_BACK   1             /* the arrow at the start (up, left) */
#define VS_PGBACK 2             /* the track before the thumb */
#define VS_THUMB  3
#define VS_PGFWD  4             /* the track after it */
#define VS_FWD    5             /* the arrow at the end */
unsigned char __fastcall__ vr_scroll_hit(const struct vrscroll *s, unsigned int x, unsigned int y);
/* the thumb's length in pixels; *at its place from the bar's start */
unsigned int vr_scroll_len(const struct vrscroll *s, unsigned int *at);

#endif
