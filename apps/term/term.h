/* Veranda Term: shared declarations (MIT licence, see LICENSE) */
#ifndef TERM_H
#define TERM_H

#include <veranda.h>

/* the window (Sunroom, V149): the title in the menu bar (vr_bar_title),
   card row 2 a margin, the text at card rows 3-57 (COLS x ROWS cells of
   8 x 8), the status bar at rows 58-59 (vr_win_status: the UI font) */
#define COLS    80
#define ROWS    55
#define TROW    3               /* the first text row, in cards */
#define TY      (TROW * 8)      /* its top pixel row */
#define TITLEY  16
#define STATY   464

#define MAPBANK(b) (*(volatile unsigned char *)0 = (b))

/* a cell's display attribute (the model keeps one a cell): what ANSI's
   colours and styles become on Veranda's screen (vt.c, README) */
#define A_COL   0x0F            /* the card's paper colour (0 the normal paper) */
#define A_REV   0x10            /* reverse: ink background, glyph in the paper colour */
#define A_BOLD  0x20

/* the settings (TERM.CFG) */
struct settings {
    unsigned char magic, version;
    unsigned char port;         /* the UART's address low byte ($9Fxx) */
    unsigned char baud;         /* index into bauds[] */
    unsigned char xtal;         /* index into xtals[] */
    unsigned char echo;         /* local echo */
    unsigned char crin;         /* received CR: 0 CR, 1 CR LF */
    unsigned char ret;          /* Return sends: 0 CR, 1 CR LF, 2 LF */
    unsigned char telnet;       /* 0 auto (on after a host:port dial), 1 on, 2 off */
    unsigned char colour;       /* ANSI colours through the colour map */
    unsigned char scheme;       /* 0 light (default paper white), 1 dark */
    unsigned char uirq;         /* use the UART's own interrupt too */
    unsigned char backend;      /* 0 the 16C550, 1 the script (gates) */
    signed char tz;             /* the time zone, in quarter hours from UTC */
    unsigned char autoclock;    /* set the clock without asking */
    unsigned char bs;           /* Backspace sends: 0 BS (8), 1 DEL (127) */
    char init[33];              /* the modem's init string */
    char info[33];              /* status commands, ';' between them */
    char timehost[41];          /* the daytime service (RFC 867) */
};
extern struct settings cfg;
extern const unsigned int bauds[];       /* hundreds of baud */
extern const unsigned int xtals[];       /* the crystal in Hz / 1600 */
#define NBAUDS 9
#define NXTALS 6

extern unsigned char font[2048];

/* vt.c: the screen model, the ANSI/VT100 parser, the renderer, scrollback */
void vt_init(unsigned char bank0, unsigned char hbank, unsigned char hbanks);
void vt_reset(void);
void vt_put(unsigned char c);
void vt_write(const unsigned char *p, unsigned int n);
void vt_puts(const char *s);
void vt_render(void);
void vt_redraw(void);           /* everything dirty */
void vt_mapclear(void);         /* the window's colours off (before a page) */
void vt_view(int delta);        /* scrollback: lines back (0: live) */
extern unsigned int vt_back;    /* lines back now */
extern unsigned int vt_hist;    /* lines kept */
extern unsigned char vt_hold;   /* 1: draw nothing (a page is shown) */
void vt_cell_text(unsigned char row, unsigned char *out); /* a row's characters (80) */
void vt_cell_attr(unsigned char row, unsigned char *out);
extern unsigned char vt_cx, vt_cy;

/* term.c, also for ui.c */
extern unsigned char rxbuf[256];
extern unsigned char restart;
extern const char hexd[];
char *put_num(char *p, unsigned int v);
char *put_str(char *p, const char *s);
char *put2(char *p, unsigned char v);
void row_text(unsigned char r, const char *s, unsigned char flags);
void ui_text(const char *s, unsigned int x, unsigned int y, unsigned char bold);  /* the UI font */
void page_head(const char *title, const char *help);        /* a page's heading */
void list_row(unsigned int y, const char *s, unsigned char sel);    /* a row of 16 lines */
#define LISTTOP (TY + 64)       /* a page's list (16 lines a row) */
/* (V195) a list page's buttons: 5 framed, 12 cards wide, at cards 1, 14,
   27, 40, 53, rows BTNY to BTNY + 15; the first the default (Return) */
#define BTNY    352
#define BTNW    12
void page_press(void);          /* term.c: otherPressVec */
void o_btns(unsigned char hosts);       /* sync.c (overlay 2): the buttons */
unsigned char btn_at(void);             /* the button under the pointer, else 255 */
unsigned char row_at(unsigned char n);  /* the list's row under it (n rows), else 255 */
extern unsigned char capfh, sendfh;     /* capture, sending a file (the status) */
extern unsigned char nouart;
void message(const char *a, const char *b);
unsigned char fopen_any(const char *name, unsigned char mode);
unsigned char fopen_sys(const char *name, unsigned char mode);  /* in .SYSTEM (V71) */
extern unsigned char crow[];
extern char scrap_path[40];     /* (also fopen_sys's path) */
unsigned char crow_len(unsigned char r);
unsigned char ask(const char *prompt, char *buf, unsigned char max);

/* ui.c (the overlay) */
void o_page_draw(unsigned char page);
unsigned char o_settings_key(unsigned char k);   /* 1: close */
unsigned char o_book_key(unsigned char k);       /* 1: close, 2: dial the entry */
unsigned char o_book_click(void);        /* (V195) a click on the page: as o_book_key */
void o_book_entry(char *name, char *addr);
void o_save_settings(void);
void o_load_settings(void);
void o_book_load(void);
unsigned char o_doc(char *name, char *addr);  /* the .TEL document (V56) */
void o_copy_screen(void);       /* options/copy screen (the scrap library is here) */
unsigned char yesno(const char *a, const char *b);   /* term.c: YES 1 */

/* term.c */
void term_reply(const char *s);         /* to the host (terminal reports) */
void put_text(const char *s, unsigned char x, unsigned int y, unsigned char flags);
void status(void);              /* (hosts.c's o_status, overlay 3) */
extern unsigned char st_full;   /* (V194) 1: the whole bar drawn at the next status() */
extern char stbuf[40];          /* (its changed characters, below $A000) */
#ifdef TERM_TEST
extern unsigned int st_draws, st_parts, vt_curdraws;    /* (gate term_tcp's idle) */
#endif
void o_status(void);
void title(const char *s);

#endif
