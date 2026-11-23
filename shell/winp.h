/* Veranda shell: what win.c (drawing, overlay 1), mouse.c (the mouse,
   overlay 6), wops.c (window operations, overlay 7) and chrome.c (a
   window's chrome, overlay 8) share */
#ifndef WINP_H
#define WINP_H

#define BOTH    (ST_WR_FORE | ST_WR_BACK)

/* a window (Look 2, DECISIONS V77), from its top: the title band (2 card
   rows: the accent), the toolbar (3: chrome), the body (the sidebar at
   the left, 12 cards of the sidebar colour, when the window is at least
   SIDEMIN cards wide; the contents), the status bar (the last 2 rows:
   chrome); a shadow of SHADOW pixels right and below: one card, its
   ink cleared and its cards in the shadow's colour (V126) */
#define TITLEH  16
#define TOOLH   24
#define CTOP    40              /* the body, from the window's top */
#define STATH   16
#define FOOTH   STATH           /* (the old name: the bottom band) */
#define SIDEW   12
#define SIDEMIN 40
#define SHADOW  8

#define L(w) ((unsigned int)wins[w].x * 8)
#define R(w) (((unsigned int)wins[w].x + wins[w].w) * 8 - 1)
#define T(w) (wins[w].y)
#define B(w) (wins[w].y + wins[w].h - 1)
/* with the shadow, on the screen */
#define RS(w) (R(w) + SHADOW < SW ? R(w) + SHADOW : SW - 1)
#define BS(w) (B(w) + SHADOW < SH ? B(w) + SHADOW : SH - 1)

/* what a press on a window's chrome is (chrome_hit) */
enum { H_NONE, H_TITLE, H_CLOSE, H_ZOOM, H_MIN, H_BACK, H_FWD, H_ICONS, H_LIST, H_SEARCH,
       H_PREV, H_NEXT, H_SIZE, H_BODY };
#define H_CRUMB 0x20            /* + the crumb */
#define H_PLACE 0x40            /* + the place */
#define NPLACES 7               /* (the printer: V151) */

/* the desktop's icons */
enum { K_CARD, K_PIN, K_PRINTER, K_TRASH };
#define MAXDESK 3               /* the card, the printer, the trash (the pins: in the dock since V83; V163) */
extern unsigned char ndesk, deskSel, deskX;
extern unsigned char dkind[MAXDESK], didx[MAXDESK];
extern unsigned int dy[MAXDESK];
extern unsigned int SW, SH;

void win_deskicon(unsigned char i);
void win_clamp(unsigned char w);
void win_colours(void);
void colours_in(unsigned int l, unsigned int t, unsigned int r, unsigned int b);
void win_scene(unsigned int l, unsigned int t, unsigned int r, unsigned int b, unsigned char skip);
void win_repaint(unsigned int l, unsigned int t, unsigned int r, unsigned int b);
void win_front(unsigned char w);
void win_raise(unsigned char w);
extern unsigned char foundWin;
void win_move(unsigned char w, unsigned char nx, unsigned int ny);
void win_resize(unsigned char w, unsigned char nw, unsigned int nh);
void win_zoom(unsigned char w);

/* chrome.c (overlay 8) */
void chrome_draw(unsigned char w);                /* the frame, title band, toolbar, sidebar */
void chrome_title(unsigned char w);               /* the title band (front or not) */
void chrome_toggles(unsigned char w);             /* the toolbar's icons and list toggles (V156) */
void chrome_status(unsigned char w);              /* the status bar */
void chrome_shadow(unsigned char w);
void chrome_colours(unsigned char w);
unsigned char chrome_hit(unsigned char w, unsigned int x, unsigned int y);
unsigned char chrome_crumb(unsigned char w, unsigned char i);  /* crumb i's path length */
extern const char *const placeName[NPLACES];
extern const char *const placePath[NPLACES];
extern const unsigned char placeMini[NPLACES];
extern const char sPlaces[], sDevices[];

/* bars.c (overlay 9, with tiles.c) */
void bars_sidebar(unsigned char w);
unsigned char chrome_sbhit(unsigned char w, unsigned int x, unsigned int y);   /* (V151) $FF not on the scroll bar;
                                                     $FD up, $FC down, $FB the track above the thumb, $FA below,
                                                     $F9 the thumb (vx its top, vy its height), $F8 no thumb */
void chrome_sbto(unsigned char w, unsigned int y);  /* the thumb let go at y */
void win_shcol(unsigned char w);
void sh_rect(unsigned char x0, unsigned char xe, unsigned char y0, unsigned char yb);   /* (V180) */                  /* (V151; win.c, in overlay 7's bank) the soft shadow's colours */
/* chrome_status, chrome_shadow, chrome_colours, win_zoom are there too */

#endif
