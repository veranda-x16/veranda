/* Veranda FTP: what the parts share (DECISIONS V100).

   main.c   main RAM: the start, the main loop's pass (tick), the helpers
            both overlays use (text in cards, boxes), the transfers' file
            side, the switcher's aside routine
   proto.c  main RAM: the FTP client, a state machine stepped from tick
            on vrnet (Packet16's ftp.c rewritten so that nothing waits)
   list.c   main RAM: the two panes' listings in RAM banks, sorted; the
            card's folder ("$=L"); the server's (Unix, DOS, MLSD;
            Packet16's vfs.c and dirlist.c)
   ui.c     overlay 1 (appBank, mapped for good): the window, the panes,
            the menus, the mouse and the keys, the actions
   sites.c  overlay 2: FTP.SITES (Packet16's sites.c) and the Sites page
   pane.c   overlay 3 (V149): the panes drawn, their scroll bars (the
            test build's own overlay is 4)

   The protocol and listing code comes from Packet16, Marcin Spoczynski's
   FTP client for the X16, used here under the MIT licence with his
   permission.

   MIT licence (see LICENSE). */
#ifndef FTP_H
#define FTP_H

#define RAMBANK (*(volatile unsigned char *)0)

/*--------------------------------------------------------------- the panes */
#define NAMEMAX  64             /* a name with its 0 (FAT: 63 characters) */
#define MAXE     250            /* entries a pane */
#define ENTSZ    80
#define EPB      102            /* entries a bank (8192 / 80) */
#define PBANKS   3              /* banks a pane */

#define E_DIR    1
#define E_UP     2              /* ".." */
#define E_LINK   4              /* a symbolic link (the server's): tried as a folder */

struct ent {
    char name[NAMEMAX];
    unsigned long size;
    unsigned char y, mo, d, h, mi;      /* y: years since 1900 (0: no date); h $FF: no time */
    unsigned char flags;
    unsigned char pad[ENTSZ - NAMEMAX - 4 - 6];
};

struct pane {
    unsigned char bank;         /* the first of PBANKS */
    unsigned char n;            /* entries */
    unsigned char top, sel;     /* the first row shown, the selected (in the order) */
    unsigned char ord[MAXE];    /* the order shown: entry numbers */
};
#define LOCAL  0
#define REMOTE 1
extern struct pane panes[2];
extern struct ent E, E2;        /* an entry's copy */
extern unsigned char sortby;    /* SORT_* */
#define SORT_NAME 0
#define SORT_SIZE 1
#define SORT_DATE 2

void pane_clear(unsigned char p);
void pane_add(unsigned char p);                 /* E added, in order */
void __fastcall__ ent_get(unsigned char p, unsigned char i);      /* row i of the order -> E */
void pane_sort(unsigned char p);                /* the order again (sortby changed) */
unsigned char local_read(void);                 /* curDirName's folder into pane 0; 0: failed */
void rlist_begin(unsigned char mlsd);           /* the server's listing into pane 1 */
void __fastcall__ rlist_feed(const unsigned char *b, unsigned int n);
void rlist_end(void);
extern unsigned int rl_unparsed;

/*--------------------------------------------------------------- the FTP client */
/* ops (ftp_start) */
#define OP_NONE    0
#define OP_CONNECT 1            /* log in, the start folder, PWD, then the listing */
#define OP_LIST    2            /* PASV, LIST (or MLSD) */
#define OP_CWD     3            /* CWD fa (".." CDUP), PWD, the listing */
#define OP_RETR    4            /* fa into the open file xf_h */
#define OP_STOR    5            /* the open file xf_h as fa */
#define OP_MKD     6
#define OP_DELE    7
#define OP_RMD     8
#define OP_RENAME  9            /* fa to fb */
#define OP_QUIT    10
#define OP_SYNC    11           /* NOOP until its 200 (after a cancel) */

/* errors (ferr) */
#define FE_OK      0
#define FE_REPLY   1            /* the server refused: fcode, ftext */
#define FE_TIMEOUT 2
#define FE_NET     3            /* a connection failed: fnet (vrnet's error) */
#define FE_CLOSED  4            /* the server closed the connection */
#define FE_PROTO   5            /* a reply made no sense (PASV) */
#define FE_LOCAL   6            /* the card's file */
#define FE_CANCEL  7
#define FE_MODEM   8            /* no modem (net_error() says why) */
#define FE_BUSY    9

#define FTP_LINE 80
extern unsigned char fop;               /* the op under way, OP_NONE: idle */
extern unsigned char ferr;
extern signed char fnet;
extern unsigned int fcode;
extern char ftext[FTP_LINE];            /* the last reply's first line */
extern unsigned char logged;            /* logged in */
extern char rpath[NAMEMAX + 16];        /* the server's folder (PWD) */
extern char fa[NAMEMAX], fb[NAMEMAX];   /* the op's names */
extern unsigned char use_mlsd;
extern unsigned char xfer_data;         /* a transfer's data are flowing */

/* the site connected to (a copy of the Sites page's) */
struct site {
    char name[24];
    char host[64];
    char user[32];
    char pass[32];
    char dir[64];
    unsigned int port;
};
extern struct site cur;

unsigned char __fastcall__ ftp_start(unsigned char op);   /* 0: busy */
unsigned char ftp_poll(void);           /* every pass: the op that ended, else 0 */
void ftp_cancel(void);
void ftp_drop(void);                    /* the connection dropped at once */

/*--------------------------------------------------------------- transfers (main.c) */
extern unsigned char xf_h;              /* the card's file (a stream), 0 none */
extern unsigned long xf_pos, xf_size;   /* bytes done; the size if known (0 not) */
extern unsigned int xf_t0;              /* its start (ser_frames) */
extern unsigned char xf_up;             /* 1 upload */
extern char xf_name[NAMEMAX];           /* the card's name */
unsigned char xf_open(unsigned char up);   /* xf_name in curDirName; 0 failed */
void xf_close(unsigned char ok);        /* (a download that failed is deleted) */
unsigned char __fastcall__ xf_write(const unsigned char *b, unsigned int n);   /* 0 failed */
unsigned int __fastcall__ xf_read(unsigned char *b, unsigned int n);
void xf_wake(void);                     /* back from the switcher: the file again */

/*--------------------------------------------------------------- shared helpers (main.c) */
extern unsigned char font[168 * 8];
extern const unsigned char font_pl[8];
extern unsigned char cell[81];
void __fastcall__ u8_cells(unsigned char w);    /* u8.c (overlay 1): cell's UTF-8 to the set (V143) */
void __fastcall__ win_all(const char *title);
void __fastcall__ win_title(const char *title);
void __fastcall__ win_status(const char *left, const char *right);
extern char line[128];
extern unsigned char bOv2;
extern unsigned char net_on;            /* net_start succeeded */
void __fastcall__ put(unsigned char x, unsigned int y, const char *s, unsigned char w, unsigned char flags);
void __fastcall__ message(const char *a, const char *b);
unsigned char __fastcall__ yesno(const char *a, const char *b);
unsigned char __fastcall__ ask(const char *prompt, char *buf, unsigned char max);
void __fastcall__ ov2(void (*f)(void));         /* f in overlay 2 */
void __fastcall__ ov3(void (*f)(void));         /* f in overlay 3 (pane.c, V149) */
extern unsigned char pa, pb;                    /* (its arguments: the pane, the row) */
char *__fastcall__ unum(char *p, unsigned long v);   /* v in decimal at p; the end */
unsigned char __fastcall__ lower(unsigned char c);

/*--------------------------------------------------------------- ui.c (overlay 1) */
void ui_start(void);
void ui_done(unsigned char op);         /* an op ended (ftp_poll) */
void ui_tick(void);                     /* every pass: the status */
void ui_status(const char *s);
void ui_redraw(void);
void ui_pane(unsigned char p);
extern unsigned char page;              /* 0 the panes, 1 the Sites page */
extern unsigned char active;            /* the pane with the focus */
extern unsigned char hl;                /* the selection's colour, 0: reversed */
/* the panes (V149: card rows 4-5 the folders, 6-7 the column heads, the
   rows from LISTY, a pane's scroll bar in its cards 38-39) */
#define LISTY   64
#define ROWH    16
#define ROWS    25
#define LISTEND (LISTY + ROWS * ROWH)

/*--------------------------------------------------------------- pane.c (overlay 3) */
void p_heads(void);                     /* the toolbar: the folders */
void p_body(void);                      /* cleared, the column heads */
void p_row(void);                       /* pane pa's row pb */
void p_pane(void);                      /* pane pa: its rows, its scroll bar */
void p_scroll(void);                    /* a click on pane pa's scroll bar */
void p_progress(void);                  /* a transfer's bar in the status bar (pa: %) */
extern char msg[96];

/*--------------------------------------------------------------- sites.c (overlay 2) */
void sites_load(void);
void sites_pick(void);                  /* the selected site into cur */
void sites_show(void);                  /* the page drawn */
void sites_key(void);                   /* keyData */
void sites_press(void);                 /* mouseXPos, mouseYPosW */
extern unsigned char sites_go;          /* the page asked for a connection (cur) */
extern unsigned char sites_n;

#ifdef FTP_TEST
void __fastcall__ tlist(unsigned char p);
void ftp_test_tick(void);
void ftp_test_log(const char *s);
void ftp_test_list(unsigned char p);
extern unsigned char t_idle;
#endif

#endif
