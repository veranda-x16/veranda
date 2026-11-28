/* Veranda Gopher: what the parts share (DECISIONS V109; its look V110).

   main.c   main RAM: the start, the main loop's pass (tick), the helpers
            both overlays use (text in cells, the glyphs, boxes, the
            window's chrome, the toolbar), the font laid out for copy.s,
            a download's file, the switcher's aside routine
   copy.s   main RAM: a line's bytes out of the banks; text in cells of
            8 x 8, 12 or 16 lines straight into VERA
   net.c    main RAM: a Gopher fetch (RFC 1436), a state machine stepped
            from tick on vrnet: the selector sent, the reply read to the
            document store or to the download's file
   doc.c    main RAM: the document in RAM banks (its bytes, the start of
            each line shown: a text wrapped to the window, a menu a line
            an item), the history's entries
   ui.c     overlay 1 (appBank, mapped for good): the window, the address
            line, the page, the scroll bar, the menus, the mouse, the keys
   marks.c  overlay 2: the bookmarks (GOPHER.MARKS), the page that shows
            them; the clipboard's paste (the address line)

   MIT licence (see LICENSE). */
#ifndef GOPHER_H
#define GOPHER_H

#define RAMBANK (*(volatile unsigned char *)0)

/*--------------------------------------------------------------- places */
#define HOSTMAX 64              /* a host with its 0 */
#define SELMAX  160             /* a selector (with a search's tab and query) with its 0 */
#define TITLEMAX 25

/* a place: an item's type, where it is */
struct loc {
    unsigned char type;         /* '0' text, '1' menu, '7' search ... */
    unsigned int port;
    char host[HOSTMAX];         /* "": the bookmarks page */
    char sel[SELMAX];
};
extern struct loc cur;          /* the page shown */
extern struct loc go;           /* the one being fetched */
extern char title[TITLEMAX];    /* the page's name (the item's text that led to it) */
extern char gtitle[TITLEMAX];   /* the one being fetched */

/* the history (a RAM bank): entries of 256 bytes */
#define HISTMAX 16
struct hent {
    struct loc l;
    unsigned int top, sel;      /* where the page was */
    char title[TITLEMAX];
};
void __fastcall__ hist_get(unsigned char i, struct hent *e);
void __fastcall__ hist_put(unsigned char i, const struct hent *e);
void hist_shift(void);          /* entry 0 dropped, the rest moved down one */
extern struct hent H;           /* (an entry's copy) */

/*--------------------------------------------------------------- the page on the screen */
#define BODYY   56              /* its first line's top (card row 6 left empty) */
#define BROW    7               /* its first card row */
#define TRACK   51              /* its card rows (7-57) */
#define SBX     78              /* (V149, Sunroom) the scroll bar: cards 78-79, */
#define SBY     6               /* card rows 6-57 (vr_scroll, overlay 2) */
#define SBLEN   52
#define MROWH   16              /* (V110) a menu's lines: 2 card rows (the colours) */
#define MROWS   25
#define TROWH   12              /* a text's: 8 x 8 glyphs in 12 lines */
#define TROWS   34
extern unsigned char rows, rowh;        /* the page's (a menu's or a text's) */

/*--------------------------------------------------------------- the document */
#define DOCBANKS 8              /* (V230; 6 before) 64 KB of text: more is cut ("truncated") */
#define DOCMAX   0xFFFFu        /* (the offsets are 16 bits) */
#define MSEL     1              /* (V230) in a menu's line as kept: the page's own selector */
#define LINEMAX  4000           /* lines shown (a bank of starts) */
#define WRAPW    76             /* a text's columns (cards 1-76; V149: card 77 the margin, 78-79 the scroll bar) */

extern unsigned char doc_bank;  /* the first of DOCBANKS + 2 (the starts, the history) */
extern unsigned int doc_len, doc_lines;
extern unsigned char doc_menu;  /* lines are menu items (not wrapped) */
extern unsigned char doc_full;  /* cut: more came than fits */
extern unsigned char doc_done;  /* all of it came */
void __fastcall__ doc_clear(unsigned char menu);
unsigned char __fastcall__ doc_feed(const unsigned char *b, unsigned int n);   /* 0: full */
unsigned char __fastcall__ doc_text(const unsigned char *b, unsigned int n);   /* (V143) a server's text: UTF-8 or Latin-1 into the set; 0: full */
void doc_end(void);
/* line i's bytes into ln (without its CR LF, at most LNMAX - 1, a 0
   after), its length */
#define LNMAX 256
extern char ln[LNMAX];
unsigned char __fastcall__ doc_line(unsigned int i);
unsigned char __fastcall__ doc_type(unsigned int i);    /* a menu line's first byte */

/*--------------------------------------------------------------- items, addresses (item.c) */
extern char abuf[SELMAX + HOSTMAX + 16];        /* the address line's text */
extern unsigned char alen;
#define row cs_txt                      /* a line as shown (cs_draw's) */
void __fastcall__ addr_of(const struct loc *l); /* l's address into abuf */
unsigned char parse(void);              /* abuf into go, gtitle; 0: no host */
unsigned char __fastcall__ render(unsigned int i);      /* line i as shown into row: a text's WRAPW
                                           characters; a menu's text (MTW), its kind ('i' a line
                                           that is not an item; 0 nothing) */
#define MTW 73                          /* a menu line's characters (cards 4-76) */
unsigned char __fastcall__ selectable(unsigned int i);  /* line i is an item to follow */
unsigned char __fastcall__ item(unsigned int i);        /* item i into go, gtitle; 0: not one */
unsigned char ishttp(void);             /* go is a web address ("URL:...") */
void card_name(void);                   /* go's file name on the card into xf_name */

/*--------------------------------------------------------------- the fetch (net.c) */
#define GE_OK      0
#define GE_NET     1            /* the connection failed: gnet (vrnet's error) */
#define GE_TIMEOUT 2            /* nothing came for 30 s */
#define GE_EMPTY   3            /* closed without a byte */
#define GE_MODEM   4            /* no modem: net_error() */
#define GE_CANCEL  5
#define GE_LOCAL   6            /* the card's file */
#define GE_NOCARD  7

extern unsigned char gbusy;     /* a fetch is under way */
extern unsigned char gerr;
extern signed char gnet;
extern unsigned char gdl;       /* to the download's file (else the document) */
extern unsigned char gfirst;    /* the first bytes came (gfirst_cb ran) */
extern unsigned long grx;       /* bytes received */
extern unsigned int gt0;        /* its start (ser_frames) */
void __fastcall__ g_start(unsigned char download);      /* go, with gtitle */
unsigned char g_poll(void);     /* every pass: 1 when it ended (gerr) */
void g_cancel(void);
void g_first(void);             /* ui.c: the first byte came: the page is new */

/*--------------------------------------------------------------- downloads (main.c) */
extern unsigned char xf_h;              /* the card's file (a stream), 0 none */
extern char xf_name[64];
unsigned char xf_open(void);            /* xf_name in curDirName ('w'); 0 failed */
void __fastcall__ xf_close(unsigned char ok);   /* (a download that failed is deleted) */
unsigned char __fastcall__ xf_write(const unsigned char *b, unsigned int n);   /* 0 failed */
unsigned char __fastcall__ xf_exists(const char *name);
void xf_wake(void);                     /* back from the switcher: the file again */

/*--------------------------------------------------------------- shared helpers (main.c) */
/* (V110) text in cells of 8 x 8, 12 or 16 lines (copy.s, main.c) */
extern char cs_txt[80];
extern unsigned char cs_x, cs_n, cs_h, cs_fl, cs_fbank;
void __fastcall__ cs_font(unsigned char ctl);     /* (copy.s, V143) the font into cs_fbank */
extern unsigned int cs_y;
void cs_draw(void);
void __fastcall__ cells(unsigned char x, unsigned int y, unsigned char n, unsigned char h, unsigned char fl);
/* the glyphs (main.c) */
#define G_FOLDER 0
#define G_TEXT   1
#define G_SEARCH 2
#define G_BIN    3
#define G_PIC    4
#define G_SOUND  5
#define G_WEB    6
#define G_TEL    7
#define G_ERR    8
#define G_BACK   9
#define G_FWD    10
#define G_HOME   11
#define G_N      12
#define G_NONE   0xFF
#define GL_DIM   1
#define GL_REV   2
void __fastcall__ glyph(unsigned int x, unsigned int y, unsigned char m, unsigned char h, unsigned char fl);
unsigned char __fastcall__ kind(unsigned char t);      /* a menu item's glyph, its colour (kcol) */
extern unsigned char kcol;
void __fastcall__ rframe(unsigned int l, unsigned int t, unsigned int r, unsigned int b);
void __fastcall__ win_all(const char *title);
void __fastcall__ win_title(const char *title);
void __fastcall__ win_status(const char *left, const char *right);
void sb_draw(void);                     /* (V149) the scroll bar (sbar) */
unsigned char __fastcall__ sb_hit(unsigned int x, unsigned int y);     /* VS_*; sb_at, sb_n its thumb */
extern struct vrscroll sbar;
extern unsigned int sb_at, sb_n;
extern char line[200];
extern unsigned char bOv2;
extern unsigned char net_on;            /* net_start succeeded */
void net_restart(void);
void __fastcall__ put(unsigned char x, unsigned int y, const char *s, unsigned char w, unsigned char flags);
void __fastcall__ message(const char *a, const char *b);
unsigned char __fastcall__ yesno(const char *a, const char *b);
unsigned char __fastcall__ ask(const char *prompt, char *buf, unsigned char max);
void __fastcall__ ov2(void (*f)(void));         /* f in overlay 2 */
char *__fastcall__ unum(char *p, unsigned long v);   /* v in decimal at p; the end */

/*--------------------------------------------------------------- the toolbar (main.c; V110) */
#define TOOLY   32
#define BX      1               /* Back: cards BX .. BX + 2, Forward the next 3 */
#define HOMEX   8               /* Home: cards HOMEX .. HOMEX + 2 */
#define FX      12              /* the address line: cards FX .. FX + FW - 1 */
#define FW      60
#define GOX     73              /* Go / Stop: cards GOX .. GOX + 5 */
void field(void);
void toolbar(void);
extern unsigned char v_edit, fresh, hpos, hn;   /* (ui.c's) */

/*--------------------------------------------------------------- ui.c (overlay 1) */
void ui_start(void);
void ui_done(void);                     /* a fetch ended */
void ui_tick(void);                     /* every pass */
void __fastcall__ ui_status(const char *s);
extern char msg[96];

/*--------------------------------------------------------------- marks.c (overlay 2) */
void marks_load(void);                  /* GOPHER.MARKS (or the defaults) */
void marks_page(void);                  /* the bookmarks as a menu, into the document */
void marks_add(void);                   /* cur (title) added, saved */
void marks_del(void);                   /* marks_i removed, saved */
void marks_paste(void);                 /* the clipboard's text into line (0: none) */
extern unsigned char marks_i;           /* marks_del's */
extern unsigned char marks_n;
extern unsigned char marks_err;         /* the last save failed */
#define MARKS_HEAD 2                    /* the page's lines before the first bookmark */

#ifdef GOPHER_TEST
void gt_tick(void);
void __fastcall__ gt_log(const char *s);
extern unsigned char t_box, t_nbox, t_boxed, t_aside;
void __fastcall__ t_ov3(void (*f)(void));
void page_log(void);
#endif

#endif
