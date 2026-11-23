/* Veranda Claude: what the parts share (DECISIONS V114).

   main.c   main RAM: the start, the main loop's pass (tick), the font
            (the X16's CP437 set, laid out for copy.s), text in cells,
            the badges' glyphs, rounded frames, boxes, the window's
            chrome (vrwin in overlay 2), the overlays' wrappers, the
            switcher's aside routine
   copy.s   main RAM: text in cells of 8 x 8, 12 or 16 lines straight
            into VERA (Veranda Gopher's, V110)
   store.c  main RAM: the conversation in RAM banks (its messages one
            after another), the rows it is shown in (wrapped), the
            oldest turns dropped when it is full
   net.c    main RAM: one turn on vrnet: the modem's TLS connection to
            the API (ATCS), the request (HTTP/1.1 headers, the JSON
            body made from the store as it is sent), the reply handed
            to parse.c
   ui.c     overlay 1 (appBank, mapped for good): the window, the
            toolbar, the conversation, the scroll bar, the input box,
            the menus' actions, the mouse, the keys, a turn's end
   prefs.c  overlay 2: a conversation saved as text, the clipboard's
            paste, vrwin
   sbar.c   overlay 3 (V149): the scroll bar (vrscroll), the menus
            (Ask: overlay 10)
   parse.c  overlay 3: the reply: the status line, the headers, chunked
            transfer, server-sent events, JSON (a scanner, byte by
            byte: no line is ever held whole), its strings' escapes,
            UTF-8 and Unicode folded to CP437

   turn.c   overlay 2: a turn's end (its notes, its boxes)
   page.c   overlay 4: CLAUDE.CFG (both servers' settings), the Settings
            page (the server: the API or Claude Code on my PC, V115)

   MIT licence (see LICENSE). */
#ifndef CLAUDE_H
#define CLAUDE_H

#define RAMBANK (*(volatile unsigned char *)0)

/*--------------------------------------------------------------- the settings (CLAUDE.CFG) */
#define KEYMAX   160
#define HOSTMAX  64
#define SYSMAX   600
/* the conversation's options (V123; both programs' config files: remember=,
   answers=, oldcode=, compact=) */
#define CFG_OPTS \
    unsigned char rem;          /* RM_*: the messages sent */ \
    unsigned char shorta;       /* 1: short answers (a sentence more in the system prompt, max_tokens 1024) */ \
    unsigned char fullold;      /* 1: old code blocks sent whole (0: shortened, the default) */ \
    unsigned char autoc;        /* 1: compacted when the conversation sent is longer than 6 KB */
#define RM_ALL  0
#define RM_10   1
#define RM_4    2
#define RM_ONE  3
#ifdef ASK
/* Veranda Ask (apps/ask, DECISIONS V116) builds from these files with -DASK:
   its settings are its own (ask.h; its secrets in RAM banks) */
#define SLUGMAX  40
struct cfg {
    char key[2];                /* key[0]: 1 when there is a credential (the plan's tokens or an API key) */
    unsigned char model;        /* the plan's model chosen (its row) */
    char host[HOSTMAX];         /* the request's host (api.openai.com, auth.openai.com, the PC) */
    unsigned int port;
    unsigned char tls;
    unsigned char srv;          /* 0 the ChatGPT plan, 1 an OpenAI API key */
    char mslug[SLUGMAX];        /* the model sent (its slug) */
    char mname[SLUGMAX];        /* its name, shown */
    CFG_OPTS
};
#else
#define M_OPUS   0
#define M_SONNET 1
#define M_HAIKU  2
#define MODELS   3
struct cfg {
    char key[KEYMAX + 1];       /* the API key or the bridge's password ("": none yet) */
    unsigned char model;        /* M_* */
    char host[HOSTMAX];         /* api.anthropic.com */
    unsigned int port;          /* 443 */
    unsigned char tls;          /* 1 (ATCS); "tls=0" in the file: plain TCP; 0 for the bridge */
    unsigned char srv;          /* 0 the Anthropic API, 1 Claude Code on my PC (the bridge, V115) */
    char sys[SYSMAX + 1];       /* the system prompt ("": the built-in one) */
    CFG_OPTS
};
#endif
extern struct cfg C;
#ifndef ASK
extern const char *const model_id[MODELS];      /* claude-opus-5-5 ... */
extern const char *const model_name[MODELS];    /* Claude Opus 5.5 ... */
extern const char sys_default[];
#endif

/*--------------------------------------------------------------- the conversation (store.c) */
/* a message's kind (its first byte in the store) */
#define K_USER    'u'           /* sent to the API */
#define K_CLAUDE  'a'           /* sent to the API */
#define K_NOTE    'n'           /* the program's own: shown, never sent */
#define K_UNSENT  'x'           /* a user turn left out (not answered, declined) */
#define K_DECLINED 'y'          /* a reply declined (refusal): shown, not sent */
#define K_SUM     's'           /* (V123) a compaction's summary: sent as the user's */
#define K_CINST   'i'           /* (V123) the compaction's request: sent as the user's, not shown */
#define K_HIDDEN  'h'           /* (V123) a compaction's request, done: not sent, not shown */
#define K_CUSER   'c'           /* (V123) a user turn compacted: shown, not sent */
#define K_CASST   'd'           /* (V123) a reply compacted: shown, not sent */
#define SENT(k) ((k) == K_USER || (k) == K_CLAUDE || (k) == K_SUM || (k) == K_CINST)
#define USERK(k) ((k) == K_USER || (k) == K_SUM || (k) == K_CINST)
#ifdef ASK
#define STBANKS  3              /* 24 KB of conversation (V123: Ask's banks for code blocks and chats, Alt+Tab at 512 KB) */
#else
#define STBANKS  4              /* 32 KB of conversation (V123: was 40; the banks for code blocks and chats) */
#endif
#define STSIZE   ((unsigned int)STBANKS * 8192u)
#define ROWMAX   1024           /* rows shown (4 bytes each, a bank's first half) */
#define NOMSG    0xFFFF
/* a row's flags (row_get's): the kind's code, the message's first row */
#define R_USER   0
#define R_CLAUDE 1
#define R_NOTE   2
#define R_UNSENT 3
#define R_DECL   4
#define R_GAP    5              /* the empty row between two messages */
#define R_CUSER  6              /* (V123) compacted: the user's, a reply */
#define R_CASST  7
#define R_KIND   7
#define R_CODE   0x40           /* (V123, code.c) a row of a code block */
#define R_FENCE  0x20           /* its opening fence (the labels) */
#define R_CEND   0x10           /* its closing fence */
#define R_FIRST  0x80
#define TW       73             /* a row's characters (cards 4-76; V149: was 74, the scroll bar 2 cards) */

extern unsigned char sbank;     /* the first of STBANKS + 1 (the rows, the font) */
extern unsigned int st_used, st_rows;
extern unsigned int st_cur;     /* the open message (a reply coming), NOMSG none */
extern unsigned int st_prot;    /* from here on nothing is dropped (the turn's) */
extern unsigned int st_dirty;   /* the first row changed since ui.c drew */
extern unsigned char st_gen;    /* bumped when the rows were made again (all drawn again) */
extern unsigned char st_cutn;   /* turns dropped (the last time room was made) */
extern unsigned char st_k;      /* st_msg's */
extern unsigned int st_n;
unsigned char store_start(void);
void st_clear(void);
unsigned char __fastcall__ st_rd(unsigned int a);
unsigned int __fastcall__ st_msg(unsigned int a);       /* the message at a: st_k, st_n; the next's address */
unsigned int __fastcall__ st_add(unsigned char kind, const char *t, unsigned int n);    /* its address, NOMSG: no room */
unsigned char __fastcall__ st_open(unsigned char kind);  /* an empty message to append to (st_cur) */
unsigned char __fastcall__ st_append(const char *t, unsigned int n);   /* 0: no room */
void st_close(void);            /* the open message ended (trailing spaces dropped) */
void __fastcall__ st_kind(unsigned int a, unsigned char kind);
void __fastcall__ st_drop_last(void);   /* the open message removed */
unsigned char __fastcall__ st_room(unsigned int need);  /* need bytes free (the oldest turns dropped); 0: no */
unsigned int __fastcall__ st_copy(unsigned int a, char *buf, unsigned int n);  /* (main RAM buf) */
/* V123 (code.c's) */
extern unsigned int st_cutb;    /* bytes dropped from the start, in all */
extern unsigned char row_fl;
unsigned int __fastcall__ row_at(unsigned int i);       /* row i's text address; row_fl */
void __fastcall__ row_set(unsigned int i, unsigned char fl);
void __fastcall__ st_mark(unsigned int a, unsigned char kind);  /* no rows changed */
void st_relayout(void);         /* the rows made again (st_gen) */
void __fastcall__ rb_put(unsigned int off, const void *buf, unsigned char n);
unsigned int __fastcall__ cp_u(unsigned char c);        /* CP437 to Unicode */
#define CP437U ((unsigned int *)0xBA00) /* (the rows' bank: rows $A000, the font $B000-$B9FF) */
unsigned char __fastcall__ row_get(unsigned int i);     /* row i into cs_txt (TW, padded); its flags */
extern unsigned int row_msg;    /* row_get's message (its address) */

/*--------------------------------------------------------------- a turn (net.c) */
#define T_IDLE   0
#define T_WAIT   1              /* the modem not ready yet */
#define T_OPEN   2              /* the modem connecting (TLS) */
#define T_SEND   3              /* the request going out */
#define T_RECV   4              /* the reply coming */
extern unsigned char tstate;
#define TE_OK      0
#define TE_NET     1            /* vrnet's error: tnet */
#define TE_CONNECT 2            /* could not connect: tnet */
#define TE_TIMEOUT 3            /* nothing for 2 minutes */
#define TE_MODEM   4
#define TE_NOCARD  5
#define TE_STOP    6            /* stopped (Esc, Stop) */
#define TE_CLOSED  7            /* closed before the reply's end */
#define TE_FULL    8            /* no room for more of the reply */
extern unsigned char tend;      /* why the last turn ended */
extern unsigned char tdone;     /* a turn ended: ui.c's to show */
extern signed char tnet;
extern unsigned char net_on;
extern unsigned long ttx, trx;  /* bytes out, in */
extern unsigned int tbody;      /* the request's body */
extern unsigned int tt0, tfirst;        /* its start, the first text's frame (0: none yet) */
void net_restart(void);
unsigned char turn_start(void); /* the last user message to the API; 0: not started (tend) */
void turn_poll(void);           /* every pass */
void turn_stop(void);
#ifdef CLAUDE_TEST
extern unsigned char t_plain;   /* the emulator has no ATCS: plain ATC */
#endif

/*--------------------------------------------------------------- the reply (parse.c, overlay 3) */
extern unsigned char rbuf[256]; /* what came (main RAM) */
extern unsigned int rn;
#ifdef ASK
extern char dtext[272];         /* its text, CP437 (main RAM; V129: room for a key's "access=" too) */
#else
extern char dtext[256];         /* its text, CP437 (main RAM) */
#endif
extern unsigned int dn;
extern unsigned int p_status;   /* the HTTP status (0: not yet) */
extern unsigned char p_end;     /* the reply ended (message_stop, the last chunk) */
extern unsigned char p_fb;      /* a fallback block came (another model went on) */
extern unsigned char p_errev;   /* an "error" event came */
#ifdef ASK
extern char p_stop[20];         /* incomplete_details.reason */
extern char p_etype[48];        /* error.code (or error.type) */
#else
extern char p_stop[16];         /* stop_reason */
extern char p_etype[32];        /* error.type */
#endif
extern char p_emsg[160];        /* error.message */
extern char p_model[40];        /* message.model */
extern unsigned long p_in, p_out, p_cache;      /* usage */
extern unsigned long p_cw;      /* (V123) cache_creation_input_tokens */
extern unsigned int p_text;     /* text bytes made (the reply's) */
void p_begin(void);
void p_feed(void);              /* rbuf[0 .. rn) in; dtext[0 .. dn) out */
unsigned char __fastcall__ cp_of(unsigned int u);       /* Unicode to CP437, 0: none (main.c) */

/*--------------------------------------------------------------- the screen */
#define TOOLY   32
#define BODYY   56              /* the conversation: card rows 7-50 */
#define BROW    7
#define RH      16              /* a row: 2 card rows (its colours) */
#define BROWS   22
#define TRACK   44              /* the scroll bar's cards (card rows 7-50) */
#define TX      4
#define SBX     78              /* (V149) the scroll bar: cards 78-79, Sunroom's (sbar.c) */
#define INY     408             /* the input box: card rows 51-57 */
#define INTX    2
#define INTW    66
#define INL     3               /* its lines shown, 12 pixels each */
#define INTY    418
#define SENDX   71              /* Send / Stop: cards 71-77 */

/* (V149) the scroll bar (sbar.c: Claude's overlay 3, Ask's 10) */
struct vrscroll;
extern struct vrscroll sbar;    /* (main.c) the bar sb_draw draws, sb_hit tests */
extern unsigned char sb_r;      /* sb_draw's SB_FORCE (drawn even when its thumb has not moved); sb_hit's VS_* */
#define SB_FORCE 0x80
void sb_draw(void), sb_hit(void);
#ifdef ASK
#define ovsb ovl
#else
#define ovsb ov3
#endif

/* text in cells (copy.s) */
extern char cs_txt[80];
extern unsigned char cs_x, cs_n, cs_h, cs_fl, cs_fbank;
void __fastcall__ cs_font(unsigned char ctl);     /* (copy.s, V143) the font into cs_fbank */
extern unsigned int cs_y;
void cs_draw(void);
void __fastcall__ cells(unsigned char x, unsigned int y, unsigned char n, unsigned char h, unsigned char fl);
void __fastcall__ put(unsigned char x, unsigned int y, const char *s, unsigned char w, unsigned char flags);
#define G_YOU    0
#define G_CLAUDE 1
#define G_NOTE   2
#define G_WARN   3
#define G_N      4
#define G_NONE   0xFF
#define GL_DIM   1
#define GL_REV   2
void __fastcall__ glyph(unsigned int x, unsigned int y, unsigned char m, unsigned char h, unsigned char fl);
void __fastcall__ rframe(unsigned int l, unsigned int t, unsigned int r, unsigned int b);
void __fastcall__ button(unsigned char x, unsigned char w, unsigned int y, const char *label, unsigned char dim);
void __fastcall__ heading(const char *t, const char *what);     /* (V149) a page's */
void __fastcall__ win_all(const char *title);
void __fastcall__ win_title(const char *title);
void __fastcall__ win_status(const char *left, const char *right);
extern char line[200];
extern unsigned char bOv2, bOv3, bOv4, bOv5;
void __fastcall__ message(const char *a, const char *b);
unsigned char __fastcall__ yesno(const char *a, const char *b);
unsigned char __fastcall__ ask(const char *prompt, char *buf, unsigned char max);
void __fastcall__ ov2(void (*f)(void));
void __fastcall__ ov3(void (*f)(void));
void __fastcall__ ov4(void (*f)(void));
/* V123: three banks of their own: code.c (the code blocks, the clipboard),
   file.c (files: saved, tokenized, attached), conv.c (a turn's plan,
   compaction, the usage, the Conversation page) */
extern unsigned char bCode, bFiles, bConv;
void __fastcall__ ovc(void (*f)(void));         /* code.c's bank */
void __fastcall__ ovs(void (*f)(void));         /* file.c's */
void __fastcall__ ovb(unsigned char b, void (*f)(void));
extern unsigned char c_blk, c_prg;      /* a block for file.c (code.c's click, c_last) */
void c_last(void), c_saveblk(void), c_about(void), at_store1(void), thinking(void);
/* (V123) hist.c: the chats (/DOCUMENTS/Chats/<the program's>), its own bank */
extern unsigned char bHist;
void __fastcall__ ovh(void (*f)(void));
extern unsigned int h_seq;      /* the chat shown: its number (0: not saved yet) */
extern char h_title[41], h_created[17];
void h_save(void);              /* after a turn: the chat written (CHAT.TMP, renamed) */
void h_page(void), h_key(void), h_press(void);  /* the Chats page (pg_on 3) */
extern char scrap_path[40];     /* (the scrap library in code.c's bank: its file name below $A000) */
char *__fastcall__ unum(char *p, unsigned long v);

/*--------------------------------------------------------------- the input (ui.c's, main RAM) */
#define INMAX 1000
extern char inbuf[INMAX + 1];
extern unsigned int in_len, in_cur;

/*--------------------------------------------------------------- ui.c (overlay 1) */
void ui_start(void);
void ui_tick(void);
void __fastcall__ ui_status(const char *s);
extern char msg[100];
extern unsigned char hl;        /* the selection's colour (0: Classic) */
void page_all(void);            /* (prefs.c: the page closed) */
void m_quit(void), m_new(void), m_save(void), m_settings(void), m_about(void);
void m_opus(void), m_sonnet(void), m_haiku(void);
void m_chats(void), m_conv(void), m_compact(void), m_ccopy(void), m_csave(void), m_cgo(void), m_crep(void), m_catt(void);

/*--------------------------------------------------------------- turn.c (overlay 2; turn_hello page.c, overlay 4) */
extern unsigned int t_umsg, t_rmsg;     /* the turn's user message, its reply (main.c) */
void turn_end(void);            /* a turn's end: notes, boxes, msg */
void turn_hello(void);          /* the first notes */

/*--------------------------------------------------------------- page.c (overlay 4) */
void cfg_load(void);
void cfg_save(void);            /* (cfg_err: 1 failed) */
extern unsigned char cfg_err;
void pg_show(void);             /* the Settings page */
void pg_key(void);
void pg_press(void);
extern unsigned char pg_on;     /* the page is up */
extern unsigned char pg_saved;  /* it closed with Save */

/*--------------------------------------------------------------- prefs.c (overlay 2; menus, model_marks: sbar.c) */
void conv_save(void);           /* the conversation to /DOCUMENTS (sv_name) */
extern char sv_name[40];
extern unsigned char sv_err;    /* 1: the file failed */
void paste(void);               /* the clipboard's text into line */
void menus(void);               /* the bar laid out (DoMenu's) */
void model_marks(void);         /* the Settings menu's marks: the model chosen */
struct menu4;
extern struct menu4 mbar;
extern unsigned int barx[4], barl[4];

/*--------------------------------------------------------------- V123: code.c, the plan of a turn */
/* what gen sends (net.c), laid out by code.c's plan before each turn */
extern unsigned int g_from;     /* the first message sent (the Remember setting) */
extern char g_max[6];           /* max_tokens ("4096", "1024" short, "500" a compaction) */
extern unsigned char g_model;   /* (Claude) the model sent: C.model, Haiku for a compaction or Ctrl+Return */
extern unsigned char t_cheap;   /* this question to the cheap model (Ctrl+Return) */
extern unsigned char t_comp;    /* the turn is a compaction (1 asked, 2 automatic: the question after) */
#define NSUB 12
extern unsigned char nsub, ph_i;        /* old code blocks sent shortened: their text */
extern unsigned int sub_a[NSUB], sub_e[NSUB];
extern char gph[64];            /* the placeholder of block ph_i (code.c's ph_make) */
#ifdef ASK
extern char g_slug[40];         /* (Ask) the model sent */
#endif
extern const char short_s[];    /* the short answers' sentence */
extern unsigned int c_row;      /* code_click's row, c_col its column */
extern unsigned char c_col;
extern unsigned int v_top;      /* (ui.c) the first row shown */
extern unsigned char att_on;    /* a file attached to the next question */
extern char att_lbl[48];        /* the toolbar's "Attached: NAME (n lines)  [Remove]" */
void c_presend(void);           /* send's: an automatic compaction first (c_go 2) */
void toolbar(void);
extern unsigned char c_ui;      /* what ui.c draws after a code.c command: */
#define CU_STATUS 1             /* msg in the status bar */
#define CU_ALL    2             /* everything (a page closed) */
#define CU_TOOL   4             /* the toolbar (the file attached) */
#define CU_GOTO   8             /* row c_row shown */
#define CU_NEW    16            /* a new conversation (the Chats page's New) */
extern unsigned long u_in, u_cached, u_out, u_cost;     /* the conversation's usage (u_cost: millionths of a dollar) */
extern unsigned int u_turns;
/* the code blocks (code.c finds them; conv.c reads them) */
#define B_USER   1              /* in a user's message (a file attached) */
#define B_FILE   2              /* a version of the file attached (name) */
#define B_SAVED  4
#define B_COPIED 8
#define NB 16
struct blk {
    unsigned int msg;           /* its message */
    unsigned int a, ca, ce, e;  /* the opening fence's line, the code, the closing fence's line, after it */
    unsigned int lines;
    unsigned char lang, fl;
    char tag[10];
    char name[18];              /* the file's, or the name it was saved as */
};
extern struct blk B[NB];
extern unsigned char nblk;
#define L_TXT 0
#define L_BAS 1
#define L_ASM 2
#define L_C   3
#define L_PY  4
/* the file attached last (the blocks' name: its first 17 characters) */
extern char af_name[64];
extern unsigned char af_prg, af_lang, af_kind;
#define AK_TEXT 0
#define AK_CWR  1
#define AK_PRG  2
#define ATTMAX  ((unsigned int)STBANKS * 4096u - 4096u)    /* (12 KB in Claude, 8 in Ask: a reply's room left) */
void __fastcall__ ovv(void (*f)(void));         /* conv.c's bank */
void code_scan(void);           /* the blocks found, their rows marked */
void code_reset(void);
void code_label(void);          /* a fence row's text (cs_txt, row_fl) */
void code_click(void);          /* a click on row c_row, column c_col */
void c_copy(void), c_save(void), c_reply(void), c_choose(void), c_compact(void), c_attach(void);
void c_unattach(void), c_conv(void), c_newconv(void);
void cp_init(void);
void paste(void);               /* the clipboard's text into line (was prefs.c's) */
void plan(void);                /* before a turn: g_*, the shortened blocks; t_umsg made with the file attached */
void ph_make(void);
void c_ask_user(void);          /* send's: the user message (with the attached file): t_umsg */
void c_after(void);             /* after a turn: the usage, the blocks, the hint; a compaction's end */
void cv_key(void), cv_press(void);      /* the Conversation page (pg_on == 2) */
extern unsigned char c_go;      /* c_after's: 1 the question is to be sent now (after an automatic compaction) */

#ifdef ASK
#include "ask.h"
#endif

#ifdef CLAUDE_TEST
void gt_tick(void), gt_turn(void);
void __fastcall__ t_ov5(void (*f)(void));
void __fastcall__ gt_log(const char *s);
extern unsigned char t_box, t_nbox, t_boxed, t_aside, t_turns;
extern unsigned int t_pages, t_fp, t_fb, t_reads;
#endif

#endif
