/* Veranda Chat: what the parts share (DECISIONS V111).

   main.c   main RAM: the start, the main loop's pass (tick), the font
            (read by input.c's load_font: V178), text in cells, boxes,
            the window's chrome (vrwin in overlay 3), the overlays'
            wrappers
   conn.c   main RAM: the connection on vrnet (a state machine stepped
            from tick): the modem, the socket, lines in (each handed to
            proto.c), the queue of lines out, the keep-alive
   store.c  main RAM: the windows (server, channels, queries), each one's
            scrollback in a RAM bank, each channel's nicks and topic in
            another, the input's history in one more
   proto.c  overlay 2: IRC (RFC 1459/2812): a line from the server
            handled (registration, numerics, JOIN ... PRIVMSG, CTCP), the
            text cleaned (formatting codes, UTF-8); the input line's
            commands (/join ...) and messages
   ui.c     overlay 1 (appBank, mapped for good): the window, the tabs,
            the topic, the text, the nick list, the input line, the
            menus, the mouse, the keys
   servers.c overlay 3: the servers (CHAT.SERVERS), their page, the
            connection's end's box; the clipboard's paste
   input.c  overlay 4: the input line's commands; vrwin, vrcs
   bar.c    overlay 5 (V149): the Sunroom scroll bars (vrscroll), the menus

   MIT licence (see LICENSE). */
#ifndef CHAT_H
#define CHAT_H

#define RAMBANK (*(volatile unsigned char *)0)

/*--------------------------------------------------------------- a server */
struct srv {
    char name[24];
    char host[64];
    unsigned int port;
    char nick[17];
    char alt[17];
    char real[40];
    char pass[32];
    char chans[64];             /* channels joined at the start, by spaces */
};
extern struct srv S;            /* the one connected to (or last chosen) */

/*--------------------------------------------------------------- windows */
#define WMAX    7               /* the server's and 6 channels or queries */
#define W_FREE  0
#define W_SERV  1
#define W_CHAN  2
#define W_QUERY 3
#define NAMEMAX 32

struct win {
    char name[NAMEMAX];         /* a channel's or a nick's; "" the server's */
    unsigned char kind;
    unsigned char joined;       /* a channel: we are in it */
    unsigned char unread;       /* 0, U_NEW, U_MENTION */
    unsigned char names;        /* a NAMES list coming (353 until 366) */
    unsigned int used;          /* its scrollback's bytes */
    unsigned int lines;         /* lines kept */
    unsigned int seq;           /* lines ever added (the screen follows it) */
    unsigned int nicks;         /* a channel's nicks kept (NMAX at most) */
    unsigned int people;        /* (V178) a channel's people, all of them (NAMES, JOIN, PART ...) */
    unsigned int scroll;        /* the view: rows up from the newest */
};
#define U_NEW     1
#define U_MENTION 2
extern struct win W[WMAX];
extern unsigned char cw;        /* the window shown */

/* a line's kinds (its attribute) */
#define A_MSG     0             /* <nick> text */
#define A_OWN     1             /* our own */
#define A_INFO    2             /* joins, parts, the server's notes */
#define A_MENTION 3             /* our nick in it */
#define A_ERR     4             /* an error */
#define A_ACTION  5             /* * nick text */
#define A_NOTICE  6

/* store.c */
#define SBSIZE  4096u           /* a window's scrollback (half a bank); the oldest dropped */
#define LNMAX   520
extern char ln[LNMAX];          /* sb_prev's line */
extern unsigned char ln_attr, ln_hh, ln_mm;
extern unsigned int ln_len;
unsigned char store_start(void);        /* the banks; 0: not enough */
signed char __fastcall__ win_find(const char *name);   /* -1: none */
signed char __fastcall__ win_new(unsigned char kind, const char *name);  /* -1: no room */
void __fastcall__ win_close(unsigned char w);
void __fastcall__ sb_add(unsigned char w, unsigned char attr, const char *text);
unsigned int __fastcall__ sb_prev(unsigned char w, unsigned int end);   /* the line ending at end into ln; its start */
void __fastcall__ sb_clear(unsigned char w);
/* nicks: a channel's, sorted (ops, voices, the rest; by name) */
#define NICKLEN 17              /* a mode character, 16 of the nick (0-padded) */
#define NMAX    190             /* a channel's nicks kept (more: counted in W[].people, "and N more") */
extern char nk[NICKLEN + 1];    /* nk_get's: the mode character (' ' none), the nick */
void __fastcall__ nk_clear(unsigned char w);
unsigned char __fastcall__ nk_add(unsigned char w, const char *nick, unsigned char mode); /* 0: not there, full; 1: there (V178); 2: added */
unsigned char __fastcall__ nk_del(unsigned char w, const char *nick);    /* 1: it was there */
int __fastcall__ nk_find(unsigned char w, const char *nick);    /* its place (nk filled), -1 */
void __fastcall__ nk_get(unsigned char w, unsigned int i);
unsigned char __fastcall__ nk_mode(unsigned char w, const char *nick, unsigned char mode, unsigned char on);
void __fastcall__ nk_join(unsigned char w, const char *nick, unsigned char mode);          /* (V178) counted */
unsigned char __fastcall__ nk_gone(unsigned char w, const char *nick, unsigned char part); /* (V178) 1: counted out */
#define TOPICMAX 400
void __fastcall__ topic_set(unsigned char w, const char *t);
void __fastcall__ topic_get(unsigned char w, char *buf, unsigned int max);
/* the input's history */
#define HISTN 8
void __fastcall__ hist_add(const char *s);
unsigned char __fastcall__ hist_get(unsigned char back, char *buf);     /* back 1 the newest; 0: none */
extern unsigned char hist_n;
/* IRC's case (RFC 1459: {}|^ are []\~'s lower case) */
unsigned char __fastcall__ ilower(unsigned char c);
unsigned char __fastcall__ ieq(const char *a, const char *b);
unsigned char __fastcall__ ieqn(const char *a, const char *b, unsigned char n);

/*--------------------------------------------------------------- the connection (conn.c) */
#define C_OFF    0
#define C_WAIT   1              /* the modem not ready yet */
#define C_OPEN   2              /* connecting */
#define C_REG    3              /* connected, registering (NICK, USER) */
#define C_UP     4              /* registered (001) */
#define C_QUIT   5              /* QUIT sent: waiting for the close */
extern unsigned char cstate;
extern unsigned char cerr;      /* why it ended (CE_*), shown by ui.c */
#define CE_NONE    0
#define CE_NET     1            /* vrnet's error: cnet */
#define CE_CLOSED  2            /* the server closed it (cwhy: its ERROR line) */
#define CE_TIMEOUT 3            /* nothing for 5 minutes */
#define CE_MODEM   4
#define CE_NOCARD  5
#define CE_QUIT    6            /* we quit */
extern signed char cnet;
extern char cwhy[80];
extern unsigned char net_on;
#define RXMAX 520
extern char rx[RXMAX];          /* the line being handled (proto.c) */
extern char me[NICKLEN];        /* our nick */
void conn_start(void);          /* to S */
void conn_poll(void);           /* every pass */
void __fastcall__ conn_quit(const char *why);  /* QUIT sent (if up; why 0: ours), then closed */
void conn_drop(void);           /* hung up at once */
unsigned char __fastcall__ send_line(const char *s);    /* s with CR LF queued; 0: no room */
void net_restart(void);
extern unsigned int crx_lines, ctx_lines;

/*--------------------------------------------------------------- proto.c (overlay 2), input.c (overlay 4) */
void irc_line(void);            /* rx handled (overlay 2) */
void irc_input(void);           /* inbuf (a command or a message to cw; overlay 4) */
void irc_welcome(void);         /* registered: the channels joined (overlay 4) */
void irc_register(void);        /* PASS, NICK, USER (overlay 4) */
extern char tbuf[LNMAX];        /* a line made for sb_add */
extern char obuf[LNMAX];        /* a line made to send */
#define INMAX 480
extern char inbuf[INMAX + 1];
extern unsigned int in_cur, in_len;     /* the input line's cursor, its length (ui.c) */
extern unsigned char comp_on;           /* Tab pressed last: the next nick (ui.c clears it) */
void in_complete(void);                 /* Tab (overlay 4) */
void load_font(void);                   /* (V178) the font into font[] (overlay 4, once) */
extern unsigned char nick_try;  /* registration: 0 the nick, 1 the alt, 2.. with "_" */

/*--------------------------------------------------------------- what to draw again (ui.c reads it) */
extern unsigned char dirty;
#define D_TABS  1
#define D_TOPIC 2
#define D_NICKS 4
#define D_BODY  8               /* the whole text again */
#define D_TITLE 16
#define D_STAT  32
#define D_INPUT 64
#define D_ALL   127
extern unsigned char ding;      /* a mention or a new query: the sound */

/*--------------------------------------------------------------- main.c */
extern unsigned char font[224 * 8];     /* ISO-8859-1 32-255 */
extern char line[200];
extern unsigned char bOv2, bOv3;
void __fastcall__ win_all(const char *title);
void __fastcall__ win_title(const char *title);
void __fastcall__ win_status(const char *left, const char *right);
void __fastcall__ put(unsigned char x, unsigned int y, const char *s, unsigned char w, unsigned char flags);
void __fastcall__ message(const char *a, const char *b);
unsigned char __fastcall__ yesno(const char *a, const char *b);
unsigned char __fastcall__ l10_byte(unsigned int u);   /* (V143) cs_byte, vrcs in overlay 4 */
void __fastcall__ ov2(void (*f)(void));
void __fastcall__ ov3(void (*f)(void));
void __fastcall__ ov4(void (*f)(void));
void __fastcall__ ov5(void (*f)(void));
char *__fastcall__ unum(char *p, unsigned long v);
unsigned char now_hh(void), now_mm(void);

/*--------------------------------------------------------------- ui.c (overlay 1) */
void ui_start(void);
void ui_tick(void);
void __fastcall__ ui_status(const char *s);
void __fastcall__ ui_show(unsigned char w);     /* (proto.c asks through cw_req) */
extern signed char cw_req;      /* proto.c: show this window next (-1 none) */

/*--------------------------------------------------------------- servers.c (overlay 3) */
void sv_load(void);
void sv_show(void);             /* the page */
void sv_key(void);
void sv_press(void);
void sv_paste(void);            /* the clipboard's text into line */
void sv_box(void);              /* the box for cbox (CE_*), cbox_st the state it ended in */
extern unsigned char cbox, cbox_st;
extern unsigned char sv_page;   /* the page is up */
extern unsigned char sv_go;     /* Connect pressed: S is the server */
extern unsigned char sv_err;    /* the last save failed */

/*--------------------------------------------------------------- bar.c (overlay 5, V149) */
struct vrscroll;
extern struct vrscroll sbar;    /* (main.c) the bar sb_draw draws, sb_hit tests */
extern unsigned char sb_r;      /* sb_hit's: VS_* */
void sb_draw(void);
void sb_hit(void);              /* mouseXPos, mouseYPosW on sbar */
void ui_where(void), ui_tabs(void), ui_topic(void);     /* (ui.c's: right; the tabs, the topic line drawn) */
void sv_menus(void);            /* the menus laid out (ui.c's, DoMenu) */
extern unsigned int barx[3], barl[3];   /* (main.c: the menu bar's items; the test clicks them) */
struct menu3;
extern struct menu3 mbar;

#ifdef CHAT_TEST
void gt_tick(void);
void __fastcall__ gt_log(const char *s);
void __fastcall__ gt_line(unsigned char w, unsigned char attr, const char *t);
extern unsigned char t_box, t_nbox, t_boxed, t_aside, t_ding, t_done;
extern char tlog[128];                  /* (main.c's log line, the test's too) */
#endif

#endif
