/* Veranda Gemini: what the parts share (DECISIONS V118).

   main.c   main RAM: the start, the main loop's pass (tick), the helpers
            the overlays use (text in cells, the glyphs, boxes, the
            window's chrome, the toolbar, the menus' texts), the font laid
            out for copy.s, a download's file, the switcher's aside routine
   copy.s   main RAM: a line's bytes out of the banks; text in cells of
            8 x 8, 12 or 16 lines straight into VERA (Veranda Gopher's)
   net.c    main RAM: a Gemini request, a state machine stepped from tick
            on vrnet (the modem's TLS: net_tls): the URL sent, the reply's
            header, its body to the document or to the download's file
   doc.c    main RAM: the document in RAM banks (its text folded to
            CP437, the rows shown: gemtext's lines by kind, wrapped to the
            window), the history, the page cache
   ui.c     overlay 1 (appBank, mapped for good): the window, the address
            line, the page, the scroll bar, the menus, the mouse, the keys
   tool.c   overlay 6 (V149): the toolbar; with the SDK's vrwin and
            vrscroll (the window's chrome, the scroll bar)
   marks.c  overlay 2: the bookmarks (GEMINI.MARKS), the page that shows
            them; the clipboard's paste
   box.c    overlay 2: small things for the interface (the status bar's
            right, the page's name, Find's match, About, the bookmarks'
            boxes)
   url.c    overlay 3: URLs (typed, resolved against the page's, a query
            percent-encoded), the card's name for a download, the boxes
            for a reply that is not a page
   web.c    overlay 4: web pages (NewsWaffle, the proxy), the settings
   wiki.c   overlay 4: Wikipedia through Gemipedia (V128)

   MIT licence (see LICENSE). */
#ifndef GEMINI_H
#define GEMINI_H

#define RAMBANK (*(volatile unsigned char *)0)

/*--------------------------------------------------------------- places */
#define URLMAX   256            /* a URL with its 0 (Gemini allows 1024: longer ones are refused) */
#define HOSTMAX  64
#define TITLEMAX 25

extern char cur[URLMAX];        /* the page shown ("": the bookmarks page) */
extern char go[URLMAX];         /* the one being fetched */
extern char rel[URLMAX];        /* a link's URL, a redirect's, as written (url.c resolves it) */
extern char title[TITLEMAX];    /* the page's name */
extern char gtitle[TITLEMAX];   /* the one being fetched */
extern char ghost[HOSTMAX];     /* go's host and port (url.c's u_host) */
extern unsigned int gport;

/* the history (a RAM bank, 14 entries) */
#define HISTMAX 14
struct hent {
    char url[URLMAX];
    unsigned int top, sel;      /* where the page was */
    char title[TITLEMAX];
};
void __fastcall__ hist_get(unsigned char i, struct hent *e);
void __fastcall__ hist_put(unsigned char i, const struct hent *e);
void hist_shift(void);
extern struct hent H;

/*--------------------------------------------------------------- the page on the screen */
#define BODYY   56              /* its first line's top (card row 6 left empty) */
#define BROW    7
#define TRACK   51              /* its card rows (7-57) */
#define SBX     78              /* (V149, Sunroom) the scroll bar: cards 78-79, */
#define SBY     6               /* card rows 6-57 (vr_scroll, overlay 6) */
#define SBLEN   52
#define MROWH   16              /* gemtext's rows: 2 card rows (their colours) */
#define MROWS   25
#define TROWH   12              /* a plain text's */
#define TROWS   34
extern unsigned char rows, rowh;

/*--------------------------------------------------------------- the document (doc.c) */
#define DOCBANKS 4              /* 32 KB of text: more is cut */
#define DOCMAX   ((unsigned int)DOCBANKS * 8192u)
#define LINEMAX  2730           /* rows (a bank: 2 bytes of start and a kind each) */
#define CACHES   3              /* pages kept for Back and Forward (a bank each: V125, cbank) */
#define CACHEMAX 7920u          /* the longest kept */
#define GEMW     73             /* gemtext's columns (cards 4-76; V149: card 77 the margin, 78-79 the scroll bar) */
#define PLAINW   76             /* a plain text's, a preformatted line's (cards 1-76) */
#define ROWW     76             /* a row's cells (cards 1-76) */
#define BANKS    (DOCBANKS + 3)  /* (the page, its rows, the history and the font, a cache bank) */
extern unsigned char cbank[CACHES];

/* a row's kind */
#define K_TEXT   0
#define K_LINK   1
#define K_H1     2
#define K_H2     3
#define K_H3     4
#define K_LIST   5
#define K_QUOTE  6
#define K_PRE    7
#define K_PLAIN  8
#define K_TYPE   0x0F
#define K_CONT   0x80           /* a row after a line's first (wrapped) */
#define K_SUB(k) (((k) >> 4) & 7)       /* a link's: */
#define LK_GEM    0
#define LK_WEB    1
#define LK_GOPHER 2
#define LK_MAIL   3
#define LK_PIC    4
#define LK_OTHER  5

/* doc_clear's modes and decodings */
#define M_GEM    0
#define M_PLAIN  1
#define D_UTF8   0
#define D_LATIN1 1
#define D_RAW    2              /* CP437 as it is (the cache, the bookmarks) */

extern unsigned char doc_bank;  /* the first of BANKS */
extern unsigned int doc_len, doc_lines;
extern unsigned char doc_mode;
extern unsigned char doc_full, doc_done;
void __fastcall__ doc_clear(unsigned char mode, unsigned char dec);
unsigned char __fastcall__ doc_feed(const unsigned char *b, unsigned int n);   /* 0: full */
void doc_end(void);
#define LNMAX 256
extern char ln[LNMAX];
unsigned char __fastcall__ doc_line(unsigned int i);    /* row i's bytes into ln */
unsigned char __fastcall__ doc_kind(unsigned int i);
unsigned int __fastcall__ link_head(unsigned int i);    /* the first row of row i's line */
unsigned char __fastcall__ doc_url(unsigned int i);     /* link row i's URL into rel; 0: none (or too long) */
#define ULCUT    128            /* (V138) a long link's URL cut here in rel; the rest sent from the page */
extern unsigned int ulo;                /* (its rest's place on the page; 0 none) */
extern char *tl_d;
void __fastcall__ doc_tail(unsigned char max);  /* (copy.s; g_start) the rest of a long link's URL at tl_d, max characters at most, if go is still that link's */
void cache_put(void);                   /* the page (cur) kept */
unsigned char cache_has(void);          /* go's page kept? (gtext its kind) */
void cache_fill(void);                  /* (after cache_has) its text into the document */
void cache_drop(void);                  /* go's page forgotten */

#define row cs_txt
unsigned char __fastcall__ render(unsigned int i);      /* row i as shown (cards 1-76) into row: its kind; 0xFF none */

/*--------------------------------------------------------------- the fetch (net.c) */
#define GE_OK      0
#define GE_NET     1            /* the connection failed: gnet */
#define GE_TIMEOUT 2
#define GE_EMPTY   3            /* closed without a byte */
#define GE_MODEM   4
#define GE_CANCEL  5
#define GE_LOCAL   6            /* the card's file */
#define GE_NOCARD  7
#define GE_STATUS  8            /* a reply that is not a body: gstatus, gmeta */
#define GE_BADHDR  9            /* not a Gemini reply */

#define EV_END   1              /* g_poll: it ended (gerr) */
#define EV_SAVE  2              /* a body that is not a page: g_save or g_cancel */

extern unsigned char gbusy, gerr, gdl, gfirst, gstatus, greply;  /* (greply: a byte of the reply came, V138) */
extern signed char gnet;
extern unsigned long grx;       /* body bytes received */
extern unsigned int gt0;
#define METAMAX 200
extern char gmeta[METAMAX];     /* the header's meta (cut) */
extern unsigned char gtext;     /* the body is a page: M_GEM, M_PLAIN; 0xFF a file */
extern unsigned char gdec;      /* its decoding */
void __fastcall__ g_start(unsigned char download);      /* go (ghost, gport) */
unsigned char g_poll(void);     /* every pass: EV_* or 0 */
void g_cancel(void);
unsigned char g_save(void);     /* (after EV_SAVE) on to the file xf_name; 0: it cannot be made */
void g_first(void);             /* ui.c: a page's header came: the page is new */
extern unsigned char rtry;      /* (V138) a connection that failed before any reply: 1 tried again at rt_t, 2 was */
extern unsigned int rt_t;

/*--------------------------------------------------------------- downloads (main.c) */
extern unsigned char xf_h;
extern char xf_name[56];
unsigned char xf_open(void);
void __fastcall__ xf_close(unsigned char ok);
unsigned char __fastcall__ xf_write(const unsigned char *b, unsigned int n);
unsigned char __fastcall__ xf_exists(const char *name);
void xf_wake(void);

/*--------------------------------------------------------------- shared helpers (main.c) */
extern char cs_txt[80];
extern unsigned char cs_x, cs_n, cs_h, cs_fl, cs_fbank;
void __fastcall__ cs_font(unsigned char ctl);     /* (copy.s, V143) the font into cs_fbank */
extern unsigned int cs_y;
void cs_draw(void);
void __fastcall__ cells(unsigned char x, unsigned int y, unsigned char n, unsigned char h, unsigned char fl);
#define G_FOLDER 0
#define G_TEXT   1
#define G_SEARCH 2
#define G_BIN    3
#define G_PIC    4
#define G_MAIL   5
#define G_WEB    6
#define G_LINK   7
#define G_BACK   8
#define G_FWD    9
#define G_HOME   10
#define G_N      11
#define G_NONE   0xFF
#define GL_DIM   1
#define GL_REV   2
void __fastcall__ glyph(unsigned int x, unsigned int y, unsigned char m, unsigned char h, unsigned char fl);
void __fastcall__ win_all(const char *title);
void __fastcall__ win_title(const char *title);
void __fastcall__ win_status(const char *left, const char *right);
void sb_draw(void);                     /* (V149) the scroll bar (sbar) */
unsigned char __fastcall__ sb_hit(unsigned int x, unsigned int y);     /* VS_*; sb_at, sb_n its thumb */
extern struct vrscroll sbar;
extern unsigned int sb_at, sb_n;
extern char line[200];
extern unsigned char bOv2, bOv3, bOv4, bOv5, bOv6, bOv7;
extern unsigned char net_on;
void net_restart(void);
void __fastcall__ put(unsigned char x, unsigned int y, const char *s, unsigned char w, unsigned char flags);
void __fastcall__ message(const char *a, const char *b);
unsigned char __fastcall__ yesno(const char *a, const char *b);
unsigned char __fastcall__ ask(const char *prompt, char *buf, unsigned char max);
void __fastcall__ ov2(void (*f)(void));
void __fastcall__ ov3(void (*f)(void));
void __fastcall__ ov4(void (*f)(void));
char *__fastcall__ unum(char *p, unsigned long v);
extern const char appname[];            /* "Veranda Gemini" (main RAM: the kernel's and vrwin's) */

/*--------------------------------------------------------------- the toolbar (tool.c) */
#define TOOLY   32
#define BX      1
#define HOMEX   8
#define FX      12
#define FW      60
#define GOX     73
extern char abuf[URLMAX];               /* the address line's text */
extern unsigned char alen;
void field(void);                       /* (main.c: overlay 6's field6, toolbar6, tool.c; V149) */
void toolbar(void);
void field6(void);
void toolbar6(void);
extern unsigned char v_edit, fresh, hpos, hn;

/*--------------------------------------------------------------- ui.c (overlay 1) */
void ui_start(void);
void ui_done(void);
void ui_save(void);                     /* EV_SAVE */
void ui_tick(void);
void __fastcall__ ui_status(const char *s);
extern char msg[96];

/*--------------------------------------------------------------- marks.c (overlay 2) */
void marks_load(void);
void marks_page(void);                  /* the bookmarks as gemtext, into the document */
void marks_add(void);                   /* cur (title) added, saved */
void marks_del(void);                   /* marks_i removed, saved */
void marks_paste(void);                 /* the clipboard's text into line */
void cfg_read(void);                    /* GEMINI.CFG into line (0-terminated; "" none) */
void cfg_write(void);                   /* line into GEMINI.CFG */
extern unsigned char marks_i, marks_n, marks_err;

/*--------------------------------------------------------------- url.c (overlay 3) */
#define U_GEM    0
#define U_WEB    1
#define U_GOPHER 2
#define U_MAIL   3
#define U_OTHER  4
#define U_BAD    5              /* not an address (u_err: 1 not one, 2 too long) */
#define U_NONE   6              /* (web pages) cancelled: no box */
extern unsigned char u_ret, u_err;      /* the functions' result (main RAM) */
extern unsigned int pic_kb;             /* (web.c) pictures: the largest shown without asking, KB */
extern unsigned char u_moved;           /* u_redirect: the host changed */
void u_typed(void);                     /* abuf into go (gemini:// put before a bare host) */
void u_resolve(void);                   /* rel against cur into go: u_ret U_* */
void u_redirect(void);                  /* gmeta against go into go: u_ret U_*, u_moved */
void u_host(void);                      /* go's host and port into ghost, gport: u_ret 0 bad */
void u_query(void);                     /* line (the answer) percent-encoded as go's query: u_ret 0 too long */
void u_name(void);                      /* go's file name on the card into xf_name */
void u_fail(void);                      /* the box for a fetch that failed (gerr; a reply's: gstatus, gmeta) */
void u_load(void);                      /* (the start) the CP437 table into the font's bank; GEMINI.CFG read */
void u_ghost(void);                     /* ghost (host[:port]) parsed in place: u_ret 0 bad */

/*--------------------------------------------------------------- web.c (overlay 4; V124) */
void w_load(void);                      /* (the start, from u_load) GEMINI.CFG */
void w_setweb(void);                    /* File > Web pages...: the setting, the proxy */
void w_web(void);                       /* (u_resolve, u_typed) a web address its way: u_ret */
void w_proxy(void);                     /* (u_host) the proxy into ghost */
unsigned char __fastcall__ box3(const char *s);    /* a box: line's start and s, line + 52, + 100; Yes, No, Cancel */

/*--------------------------------------------------------------- Wikipedia (wiki.c, overlay 4; V128) */
#define WIKI_DEF  "gemini://gemi.dev/cgi-bin/wp.cgi"       /* Gemipedia (its routes after it) */
#define WIKIMAX   60
#define WLANGMAX  12
extern char wlang[WLANGMAX + 1], wbase[WIKIMAX + 1];
void k_init(void);                      /* (w_load) the defaults */
void k_ask(void);                       /* Go > Wikipedia...: asked; u_ret U_GEM (go), U_NONE, U_BAD */
void k_typed(void);                     /* abuf "wp <text>", "w <text>": u_ret as k_ask's, 0xFF not one */
void k_doc(void);                       /* (ui_start) the start document's line kept */
void k_start(void);                     /* it into abuf: u_ret its length */
void k_setlang(void);                   /* (File > Settings...) the language */

/*--------------------------------------------------------------- pictures (V125): pic.c, pngplan.c (overlay 4), png.c, pngcore.s (overlay 5) */
extern unsigned char viewing;           /* the viewer: 0 off, 1 drawing, 2 shown */
extern unsigned char retkey;            /* (ui.c) follow: from Return */
extern unsigned char pic_redo, pic_big, png_frames;     /* (main.c) aside came; over the limit; png_step_v's */
extern unsigned char pic_head[24];      /* the picture's first bytes (IHDR's size) */
extern unsigned int oy_done;            /* the rows drawn */
void __fastcall__ ov5(void (*f)(void));
void __fastcall__ ov6(void (*f)(void));
void __fastcall__ ov7(void (*f)(void));
void i_link(void);                      /* (follow) go a picture: u_ret 2 show, 1 save, 0 */
void i_done(void);                      /* (ui_done) its fetch ended: the viewer; u_ret 1 save instead */
void i_tick(void);                      /* (tick) */
void i_key(void);                       /* (V196: pic_in's) u_ret 1 saved, 2 the page, 0 the page's key */
void i_press(void);                     /* (V196: pic_in's) the same for a click */
void i_off(void);                       /* (g_first) the viewer gone */
void pic_leave(void);                   /* (V196, main.c) the way out of a picture: the page again */
void pic_menu(void);                    /* (V196) a menu's item: GotoFirstMenu, pic_leave */
unsigned char __fastcall__ pic_in(void (*f)(void));     /* (V196) i_press, i_key: not 0 taken */
void g_quit(void);                      /* (V196) Quit: the picture left, the connection ended, the desktop */
extern unsigned char pic_pv;            /* (V196) viewing as the main loop's last pass saw it */
void png_open_v(void);                  /* (overlay 5) u_ret = png_open() */
void png_step_v(void);                  /* (overlay 5) u_ret = png_step(png_frames) */
void jpg_open_v(void);                  /* (overlay 6, V192) u_ret = jpg_open() */
void jpg_start(void);                   /* (overlay 6) after png_plan */
void jinit(void);                       /* (overlay 7) */
void jpg_step_v(void);                  /* (overlay 7) u_ret = jstep(png_frames) */
extern unsigned int jw, jh;             /* (jpghdr.c, main RAM) the JPEG's size */
void png_start(void);
/* (ui.c's boxes, here for overlay 1's room) */
void u_where(void);                     /* go not Gemini (u_ret): where it leads */
void u_input(void);                     /* a 1x: asked, go's query; u_ret 1 fetch, 2 msg */
void u_redir(void);                     /* a 3x: u_ret 1 fetch, 2 msg */
void u_save(void);                      /* EV_SAVE: u_ret 1 msg */
void u_retry(void);                     /* (V138) GE_NET: u_ret 1 tried again a second later (rtry), the status bar says so */

/*--------------------------------------------------------------- box.c (overlay 2) */
void u_lines(void);                     /* the status bar's right (right, lastnet: ui.c's) */
extern char right[40];
extern unsigned char lastnet;
void u_named(void);                     /* the page's name (its first heading) */
void u_hit(void);                       /* fq in row: u_ret */
void u_about(void);
void u_marked(void);                    /* marks_add's, marks_del's boxes: u_ret 1 msg */
extern unsigned char redirs;            /* (ui.c's) */
extern char fq[42];
extern unsigned int v_top, v_sel;

#ifdef GEMINI_TEST
void gt_tick(void);
void __fastcall__ gt_log(const char *s);
extern unsigned char t_box, t_nbox, t_boxed, t_aside, png_sums;
void __fastcall__ t_ovt(void (*f)(void));
void page_log(void);
#endif

#endif
