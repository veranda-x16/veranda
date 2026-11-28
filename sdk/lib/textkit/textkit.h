/* Veranda SDK: textkit, the text editing parts of Veranda Edit (DECISIONS
   V57) shared with VeraBASIC (V93): sources compiled into a program, as
   the SDK's src/ files are, so each program puts them where it wants
   (main RAM, an overlay; its own segments):

     buf.s    the text, a gap buffer across RAM banks (the hot paths; it
              maps banks at $A000 itself: it must run below $A000)
     text.c   the text's RAM banks (runs from BankAlloc)
     ops.c    editing and moving: the cursor, the selection, the line count
     undo.c   undo: a log in RAM banks of its own
     view.c   the window: rows of 8 x 8 cells drawn with tk_putrow from the
              lines buf.s renders, the cursor, scrolling, the scroll bar
     putrow.s a row's cards, each its style (main RAM: V215)
     vmove.s  the rows moved by a scroll (with view.c; TK_BANK: its bank)
     find.c   find and replace (its dialog box), go to line
     scrap.c  cut, copy and paste through GEOS's Text Scrap (scrap.h)
     file.c   the document: a plain file read and written, its line ends

   Every source includes "tkapp.h" first: the program's own header (found
   with -I), which may set the configuration below and must include this
   file. The program gives textkit these (its own code):
     void message(const char *a, const char *b);         a box, OK
     unsigned char yesno(const char *a, const char *b);  1: Yes
     unsigned char yesnocancel(const char *a, const char *b);  YES, NO, CANCEL
     unsigned char ask(const char *prompt, char *buf, unsigned char max);
     void view_status_msg(const char *s);   a message in the status bar
     void tk_status(void), tk_title(void);  the status bar, the title (view.c
                                            calls them when B_STATUS, B_TITLE)
     unsigned char __fastcall__ file_dlg(unsigned char mode, const char *title, char *name);
     void doc_dir(void);                    back to the document's folder
     unsigned char edit_idle;               set while the program waits
     unsigned char iobuf[TK_IOBUF];         file and scrap transfers
   and, when TK_ROW_HOOK is defined, void TK_ROW_HOOK(unsigned char r): row
   r is about to be drawn (gb_line rendered, gb_mk... still its; tk_pc,
   tk_px, tk_pn, tk_pf, tk_pa, tk_pb set for tk_putrow, which view.c calls
   after the hook: tk_pn the text's cards drawn, as far as the row's ink
   went or goes; tk_iw[r] the text's ink): the program's own colouring of
   it (its cards' styles, a gutter at the left in the same call: then
   tk_iw[r] counts from column 0, and the colour map of the cards drawn;
   a row whose paper goes further: tk_iw[r] and tk_pn to the end); when
   TK_COLMOVE is
   defined (an expression, 1: the colour map's paper moves with the rows'
   cards), a scroll moves the paper of the cards 0 .. X0 + COLS - 1 too;
   when TK_SCROLL_HOOK(d) is defined, it follows a scroll of the rows by d
   (what else must be drawn again: dirty rows); when
   TK_FRAME_HOOK() is defined, it follows view_frame (the window drawn:
   what the program draws beside the text, again).

   MIT licence (see LICENSE). */
#ifndef TEXTKIT_H
#define TEXTKIT_H

#include <vrwin.h>

/* the window (card rows of 8 pixels; Veranda Look 2, DECISIONS V79): the
   menu bar at rows 0-1 (the kernel's), the title band at rows 2-3
   (vrwin.h), the text at rows TROW .. TROW + ROWS - 1 (COLS columns from
   card column X0; column SBX is the scroll bar), the status bar at rows
   58-59. A program may make COLS and X0 variables (a gutter: then it defines
   TK_GUTTER). */
#ifndef COLS
#define COLS    79
#endif
#ifndef X0
#define X0      0
#endif
#define ROWS    54
#define TROW    4
#define TY      (TROW * 8)
#define TITLEY  16
#define STATY   464
#define SBX     79

#define C_BAR   2               /* the bars' paper (Look 2's CHROME) */
#define C_THUMB 4               /* the scroll bar's thumb (SELECT) */

#ifndef TK_FONT
#define TK_FONT font            /* the 8 x 8 font (2048 bytes, below $A000) */
#endif
#ifndef TK_IOBUF
#define TK_IOBUF 1024           /* iobuf's size */
#endif
#ifndef TK_UNDO_BANKS
#define TK_UNDO_BANKS 6         /* undo's log: 8 KB a bank */
#endif
#ifndef TK_TYPES
#define TK_TYPES "Text:TXT MD INI LOG"  /* the Open and Save dialog's file types */
#endif
#ifndef TK_UNTITLED
#define TK_UNTITLED "Untitled.txt"
#endif
#ifndef TK_TMPNAME
#define TK_TMPNAME "~VEDIT.TMP"
#endif
#ifndef TK_OPEN_TITLE
#define TK_OPEN_TITLE "Open a text file"
#endif
#ifndef TK_SAVE_TITLE
#define TK_SAVE_TITLE "Save the text as"
#endif
#ifndef T_RESET
#define T_RESET()               /* (a test build's clock) */
#define T_LOG(s)
#endif

#define MAPBANK(b) (*(volatile unsigned char *)0 = (b))

/*---------------------------------------------------------------
  buf.s: the gap buffer
 ---------------------------------------------------------------*/
extern unsigned char gb_bk[64], gb_nb, ul_bk[8];
extern unsigned long gb_gs, gb_ge, gb_cap, gb_len;
extern unsigned long gb_a, gb_b, gb_n, gb_r;
extern void *gb_lp;
extern unsigned char gb_mode, gb_crst;
extern unsigned int gb_hs;
extern unsigned char gb_line[80];
extern unsigned long gb_mk[3];
extern unsigned int gb_mkc[3];
extern unsigned char gb_eof;
extern unsigned char gb_tab;            /* (V215) gb_render: not 0, the line has a tab */
extern unsigned int gb_lcols;
extern unsigned char gb_pat[64], gb_plen, gb_ftab[256];

unsigned char gb_get(void);             /* the byte at gb_a (0 past the end) */
void gb_moveto(void);                   /* the gap to gb_a */
void gb_ins(void);                      /* gb_n bytes from gb_lp at the gap */
void gb_del(void);                      /* gb_n bytes after the gap */
void __fastcall__ gb_grow(unsigned char bank);
unsigned int gb_read(void);             /* gb_n bytes from gb_a to gb_lp */
void gb_append(void);                   /* loading: gb_n bytes at the end */
void gb_flush(void);
unsigned int gb_export(void);           /* saving: up to gb_n bytes from gb_a */
void gb_render(void);                   /* the line at gb_a into gb_line */
unsigned int gb_fwd_lines(void);        /* over gb_n LFs from gb_a */
void gb_line_start(void);               /* gb_a to its line's start */
void gb_count(void);                    /* gb_r = the LFs in [gb_a, gb_b) */
void gb_find(void);                     /* gb_pat from gb_a: gb_a or -1 */
unsigned int gb_col(void);              /* the column of gb_b, line at gb_a */
unsigned int gb_at_col(void);           /* gb_a at column gb_n of its line */
void ul_read(void);                     /* the undo log: gb_n bytes, gb_a <-> gb_lp */
void ul_write(void);

#define BANK_SIZE 8192UL
#define NOWHERE 0xFFFFFFFFUL

/*---------------------------------------------------------------
  text.c: the text's banks
 ---------------------------------------------------------------*/
unsigned char tx_new(unsigned long room, unsigned char load);
void tx_free(void);
unsigned char tx_room(unsigned int n);
unsigned char tx_tail(unsigned int n);
unsigned char tx_insert(unsigned long pos, const void *p, unsigned int n);
void tx_delete(unsigned long pos, unsigned long n);
unsigned char tx_get(unsigned long pos);
unsigned char tx_bank(void);
extern unsigned char tx_runs;

/*---------------------------------------------------------------
  the document (ops.c, file.c)
 ---------------------------------------------------------------*/
extern unsigned long cur, anchor;       /* the cursor; the selection's other end */
extern unsigned long cur_line, cur_ls;  /* the cursor's line (from 0), its start */
extern unsigned int goal;               /* the column up and down keep */
extern unsigned long nlines;            /* LFs + 1 */
extern unsigned char modified;
extern unsigned char eol;               /* 0 LF, 1 CR LF, 2 CR (gb_mode when saving) */
extern char docname[64];                /* "" untitled */
#ifdef TK_UTF8
/* u8.c, u8.s (main RAM; a program that defines TK_UTF8 compiles them):
   UTF-8 files (DECISIONS V143). The text is Veranda's set (ISO-8859-16,
   V140): a file that is UTF-8 throughout, whose every character the set
   has, is decoded on loading and encoded again on saving (tk_enc 1); any
   other is read and written byte for byte (tk_enc 0). */
extern unsigned char tk_enc;            /* 1: saved as UTF-8 */
extern unsigned char u8_bad;            /* u8_in: not such a file */
void __fastcall__ u8_start(unsigned char raw);
unsigned int __fastcall__ u8_in(unsigned int n);        /* iobuf[0 .. n) decoded in place */
unsigned char u8_end(void);             /* the file ended: 1 decoded whole (tk_enc set) */
unsigned int u8_gbn(void);              /* gb_export's room for u8_out */
unsigned int __fastcall__ u8_out(unsigned int n);       /* iobuf[0 .. n) encoded in place */
unsigned int __fastcall__ u8_scan(unsigned int n);      /* iobuf's first byte past $7F (n: none) */
#endif
#ifndef iobuf                           /* (a program may make it a pointer) */
extern unsigned char iobuf[];           /* file and scrap transfers (the program's, TK_IOBUF) */
#endif

/*---------------------------------------------------------------
  the view (view.c)
 ---------------------------------------------------------------*/
extern unsigned long top, top_line;     /* the first row's line start, its number */
extern unsigned int hs;                 /* the first column shown */
extern unsigned long rs[ROWS + 1];      /* each row's line start */
extern unsigned char dirty[ROWS];
extern unsigned char bars_dirty;        /* 1 the status line, 2 the title, 4 the scroll bar */
#define B_STATUS 1
#define B_TITLE  2
#define B_SCROLL 4
extern const struct vrwin tk_win;       /* the window (vrwin.h) */
extern char tk_line[81];
                /* the bars' text (tk_status, tk_title) */
void view_init(void);
void view_frame(void);
void view_all(void);
void view_fix(void);                    /* the cursor shown, then everything dirty drawn */
void view_paint(void);
void view_scroll(long lines);           /* the view alone (the wheel) */
void view_cursor(unsigned char on);
void view_blink(void);
unsigned char tk_blink_due(void);    /* (buf.s) 1: half a second since its last 1 */
void view_status_msg(const char *s);    /* (the program's) */
unsigned int view_col(void);
extern unsigned int tk_ccol;            /* (view_col's: other banks read it, V215) */
unsigned char view_hit(unsigned int x, unsigned int y, unsigned long *pos);
char *tk_put_ul(char *p, unsigned long v);      /* (for tk_status, tk_title; TK_PUT_SEG: their code's segment) */
char *tk_put_s(char *p, const char *s);
extern unsigned char cursor_on, thumb_n;
/* (V215) putrow.s, main RAM: tk_pn cards of tk_pc (font tk_pfont) at card
   column tk_px of text row r, each card's style from tk_pf (0: plain; 1
   reversed, 2 bold), the cards [tk_pa, tk_pb) reversed too (the
   selection: view.c sets them for a row's text); vmove.s, with view.c: the rows moved by d (|d| <
   ROWS) as far as their ink, tk_iw (cards from column 0, at most tk_vlim),
   and the colour map's paper with tk_vcol */
void __fastcall__ tk_putrow(unsigned char r);
extern const unsigned char *tk_pc, *tk_pf, *tk_pfont;
extern unsigned char tk_px, tk_pn, tk_pa, tk_pb;
unsigned char tk_jiffy(void);           /* (putrow.s) the jiffies' low byte */
unsigned char tk_keys(void);            /* (putrow.s) keys still in the ROM's queue */
/* (V215) tk_hold set: view_paint leaves the status bar and the title
   (bars_dirty's B_STATUS, B_TITLE) for later: the program sets it while
   input comes and draws them (view_paint again) when it pauses */
extern unsigned char tk_hold;
void __fastcall__ tk_vmove(signed char d);
void tk_vmove_x(void);                  /* (d from tk_vd) */
extern signed char tk_vd;
extern unsigned char tk_iw[ROWS], tk_vlim, tk_vcol;
#ifndef TK_VMOVE
#define TK_VMOVE() tk_vmove_x()         /* (the program's: vmove.s in another bank) */
#endif
void tk_status(void);                   /* (the program's) */
void tk_title(void);

/*---------------------------------------------------------------
  editing (ops.c)
 ---------------------------------------------------------------*/
unsigned long sel_lo(void);
unsigned long sel_hi(void);
#define HAS_SEL() (anchor != cur)
void set_cur(unsigned long p);          /* the cursor to p: its line counted */
void move_to(unsigned long p, unsigned char extend);
void move_line(long n, unsigned char extend);
void move_word(signed char dir, unsigned char extend);
void move_home(unsigned char extend);
void move_end(unsigned char extend);
void move_page(signed char dir, unsigned char extend);
unsigned char ed_insert(const void *p, unsigned int n);   /* at the cursor, over the selection */
void ed_delete_sel(void);
void ed_backspace(void);
void ed_delete(void);
unsigned char raw_insert(unsigned long pos, const void *p, unsigned int n);
void raw_delete(unsigned long pos, unsigned long n);
void ed_changed_all(void);
unsigned char ed_text(unsigned long pos, unsigned int n, char *out);
void select_all(void);
void select_word(void);
void sel_clear(void);
void ed_recount(void);
void doc_reset(void);

/*---------------------------------------------------------------
  undo (undo.c)
 ---------------------------------------------------------------*/
#define U_INS 1
#define U_DEL 2
#define U_REP 3                 /* a replacement (find.c): len = old | new << 16 */
void undo_init(void);
void undo_clear(void);
void undo_step(void);                   /* the next change starts an undo step */
void undo_push(unsigned char type, unsigned long pos, unsigned long len);
unsigned char undo_run(unsigned char type);     /* typing continues the step */
void undo_saved(void);
void undo_join(unsigned char type);       /* this step goes on as a run */
unsigned char undo(void);
unsigned char undo_can(void);

/*---------------------------------------------------------------
  files (file.c)
 ---------------------------------------------------------------*/
unsigned char doc_load(const char *name);
unsigned char doc_save(void);
void doc_new(void);
void m_new(void), m_open(void), m_save(void), m_saveas(void), m_quit(void), m_startdoc(void);
unsigned char ask_discard(void);
unsigned char __fastcall__ file_dlg(unsigned char mode, const char *title, char *name);  /* (the program's) */
void doc_dir(void);                     /* (the program's) back to the document's folder (curDirName) */

/*---------------------------------------------------------------
  find (find.c)
 ---------------------------------------------------------------*/
void m_find(void), m_findnext(void), m_replnext(void), m_goto(void);

/*---------------------------------------------------------------
  the clipboard (scrap.c): GEOS's Text Scrap
 ---------------------------------------------------------------*/
typedef void (*scrap_src)(unsigned char *buf, unsigned int n);
typedef void (*scrap_dst)(const unsigned char *buf, unsigned int n);
unsigned char edit_scrap_put(unsigned long len, scrap_src src, void (*rewind)(void));
unsigned long edit_scrap_get(scrap_dst dst);
void m_cut(void), m_copy(void), m_paste(void);

/*---------------------------------------------------------------
  the program's (see above)
 ---------------------------------------------------------------*/
void message(const char *a, const char *b);
unsigned char yesno(const char *a, const char *b);
unsigned char yesnocancel(const char *a, const char *b);
unsigned char ask(const char *prompt, char *buf, unsigned char max);
extern unsigned char edit_idle;

#endif
