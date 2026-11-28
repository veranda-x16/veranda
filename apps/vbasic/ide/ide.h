/* VeraBASIC, the editor (DECISIONS V93): its declarations.

   The editor is C with the SDK's textkit (Veranda Edit's gap buffer, view,
   editing, undo, find, clipboard and files), linked by a link of its own
   (ide/ide.cfg) after VeraBASIC's main one, whose symbols below $A000 it
   takes as equates (tools/vbceq.py, as Run's C overlays do):
     LOW    its main RAM part, at the interpreter's code's place
            (vb.s _ide_s0 .. _ide_s1; ideshare.h): buf.s, text.c, ops.c,
            undo.c (the text's code: every bank calls it), the dialog boxes'
            and menus' tables, the state the banks share (low.c), the calls
            between banks and the kernel's entries (low.s)
     B_VIEW the bank the kernel calls (appBank while the editor shows): the
            window (textkit's view.c, its rows' cards: putrow.s), keys, the
            pointer
     B_FILE files (textkit's file.c), the clipboard (scrap.c), the menus'
            layout, the text given to the runtime's side, a scroll's rows
            moved (textkit's vmove.s, V215)
     B_DLG  the SDK's Open and Save dialog (vrchoose.c: a bank alone)
     B_HELP the help viewer, F1, the status bar's syntax lines
     B_FMT  find and replace (textkit's find.c), Format, the answers of a
            Check or a run (the error jumps), the scroll bar (sbar.c, V149),
            the status bar and the title (bars.c, V215)
     B_DBG  the debugger (DECISIONS V97: dbg.c; its names in B_HELP's
            names.c, an expression's tokens in B_LEX's tok.c, an error's
            statement in B_FMT's fmt_quote, the trace pane in B_FILE's
            trace.c; the runtime's side is overlay 12, vbdbg.s)
     B_MK   File > Save program and Make application... (DECISIONS V99:
            mk.c; record 5, V149)
   A bank calls LOW and its own code; another bank's only through xcall
   (a void function; arguments in LOW's variables), which maps it and makes
   it appBank meanwhile (its dialog boxes' routines).

   MIT licence (LICENSE). */
#ifndef IDE_H
#define IDE_H

#include <veranda.h>
#include <vr.h>
#include "ideshare.h"

/* textkit's configuration (textkit.h) */
#define docname ide_doc         /* (main.c has a docname: the run's title) */
#define COLS    tk_cols
#define X0      tk_x0
#define TK_GUTTER
#define TK_PUT_SEG "CODE"              /* (tk_put_s, tk_put_ul in LOW: every bank uses them) */
#define TK_ROW_HOOK ide_rowx
/* (V215) a scroll moves the colour map's paper with the rows (vmove.s);
   not while a menu is down (the cards it covers keep their colours aside:
   every row drawn again, as before) */
#define TK_COLMOVE (colour_on && !menuNumber)
#define TK_VMOVE() XCALL(B_FILE, tk_vmove_x)   /* (vmove.s: B_FILE's) */
#define TK_SCROLL_HOOK(d) if (menuNumber) memset(dirty, 1, ROWS)
#define TK_FRAME_HOOK() ide_frame()   /* (the window drawn: the scroll bar, the debugger's pane again: keys.c) */
extern unsigned char pane_dirty;
void ide_frame(void);
#define TK_FONT vb_font
#define TK_IOBUF 512
#define TK_UNDO_BANKS 2
#define TK_TYPES "VeraBASIC:BAS"
#define TK_UNTITLED "Untitled.bas"
#define TK_TMPNAME "~VBASIC.TMP"
#define TK_OPEN_TITLE "Open a VeraBASIC program"
#define TK_SAVE_TITLE "Save the program as"
extern unsigned char tk_x0, tk_cols;
/* main RAM's room for a program's names (from the main link's BSS end,
   IDEDYN, to the C stack: 2,555 bytes; 1,859 in the test build, which has
   the player there) is free while the editor shows: its scratch, where
   nothing lasts across a run (ide_resume clears what must start empty).
   IDEDYN is the linker's (tools/vbceq.py --ide). */
extern unsigned char IDEDYN[];
#define iobuf      (IDEDYN + 0)         /* 512: files, undo, the scrap, the text given to Run */
#define IDE_REC    (IDEDYN + 512)       /* 256: Format's line record */
#define IDE_OUT    ((char *)IDEDYN + 768)   /* 256: its text */
#define IDE_OUTN   256
/* (512 .. 1199: the Open and Save dialog's variables, ide.cfg B3BSS) */
#define lexbuf     (IDEDYN + 1200)      /* 256: a line's bytes (the colouring, the syntax, Return) */
#define ide_msga   ((char *)IDEDYN + 1200)  /* 48, 64: a dialog box's two lines (over lexbuf: */
#define ide_msgb   ((char *)IDEDYN + 1248)  /* no line is read while a box is up) */
#define lexcls     (IDEDYN + 1456)      /* 80: the cards' classes (B_LEX; the help viewer's styles) */
#define ide_paper  (IDEDYN + 1536)      /* 80: a row's colours (ColorRect COLOR_BUF) */
#define status_msg ((char *)IDEDYN + 1616)  /* 64: a message in the status bar (until the next key) */
#define syn_line   ((char *)IDEDYN + 1680)  /* 64: the status bar's syntax line (B_SYN) */
#define IDE_DYNEND 1840                 /* (XNAME, XSRC: the debugger's, ide.h below) */
extern unsigned char vb_font[2048];
void __fastcall__ ide_rowx(unsigned char r);   /* (LOW: B_LEX's ide_row) */
extern unsigned char lex_row;

#include <textkit.h>
/* (Sunroom, V149: textkit's scroll bar column, SBX, only in the chrome's
   colour, the track's; the bar and its thumb are B_FMT's sbar.c, drawn) */
#undef C_THUMB
#define C_THUMB C_BAR

/* the banks (ide_banks[]) */
#define B_VIEW 0
#define B_FILE 1
#define B_DLG  2
#define B_HELP 3
#define B_FMT  4
#define B_SYN  5
#define B_CMD  6
#define B_LEX  7
#define B_DBG  8                /* the debugger (dbg.c, DECISIONS V97) */
#define B_MK   9                /* Save program, Make application (mk.c, DECISIONS V99) */
extern unsigned char vx_dbg;    /* (its runtime's side, overlay 12: what the two share, dbgshare.h) */
/* the scroll bar (Sunroom, V149; B_FMT's sbar.c): card columns SB_X,
   SB_X + 1 beside the text's rows (textkit's own, column SBX, is drawn
   over); its arguments and answers in LOW */
#define SB_X 78
extern unsigned long sb_first, sb_total;
extern unsigned int sb_at, sb_len, sb_y;
extern unsigned char sb_part;
void sb_draw(void), sb_hit(void), sb_move(void);
void ide_status(void), ide_title(void);  /* (B_FMT's bars.c: tk_status, tk_title's, V215) */
/* the debugger's pane at the right of the text while a program is stopped */
#define PANE_W 33
#define PANE_X (SB_X - PANE_W)
void __fastcall__ xcall(unsigned char bank, void (*f)(void));
#define XCALL(b, f) xcall(ide_banks[b], f)

/* main RAM's (main.c, vb.s, vbtok.s) */
extern char vb_docname[70];             /* main.c's docname: the run's title */
extern unsigned char vt_inmem, vt_src, vt_err, vt_recb[4];
extern unsigned int vt_srclen, vt_after, vt_erl, vt_size[4];
extern char vt_msg[80];
extern unsigned char vb_errno, vb_state;
extern unsigned int vb_esrc;

/* LOW (low.c, low.s) */
extern unsigned char need_fix, ide_first;
extern unsigned long err_line;          /* a line shown RED (Check, an error), from 1; 0 none */
extern unsigned long stop_line;         /* the line a program stopped at, SELECT; 0 none */
extern unsigned char colour_on;         /* the colouring (not in the Classic theme) */
extern unsigned char gutter_on;
extern unsigned char help_open;         /* the help viewer is up (B_HELP's keys) */
extern char help_req[40];               /* the page asked for */
extern unsigned char help_file;         /* its file (HF_*) */
extern unsigned char ide_test;
extern unsigned long check_after;       /* F8: the next error after this line */
void menus_off(void);
void message(const char *a, const char *b);
unsigned char yesno(const char *a, const char *b);
unsigned char yesnocancel(const char *a, const char *b);
unsigned char ask(const char *prompt, char *buf, unsigned char max);
void sys_dir(void);
extern unsigned char fr_bank;           /* ide_fread: the bank, the address, the bytes at most */
extern void *fr_at;
extern unsigned int fr_n;
unsigned int __fastcall__ ide_fread(unsigned char h);
extern unsigned char bg_bank, bg_n;     /* ide_bget: bg_n bytes from bg_at in bg_bank to bg_to */
extern void *bg_at, *bg_to;
void ide_bget(void);
void help_free(void);
void ide_redraw_menu(void);
extern void *const ide_menubar;
extern unsigned int barx[6];
void ide_log(const char *s);            /* (the test build: a line to the emulator's console) */
void ide_logn(const char *s, unsigned long n);

/* B_VIEW (keys.c, textkit's view.c) */
void ide_tick(void), ide_key(void), ide_press(void), view_off(void);
/* B_LEX (colour.c, lex.s: the colouring) */
void ide_row(void);
/* B_CMD (cmd2.c, textkit's find.c): the actions (LOW's mn_* stubs call
   do_*), the start, the answers */
void ide_resume(void), do_newline(void), fmt_answer(void);
void ide_relayout(void);                /* the gutter on or off: COLS, X0 */
extern unsigned char ide_lastreq;
void mn_about(void), mn_new(void), mn_open(void), mn_save(void), mn_saveas(void), mn_quit(void);
void mn_undo(void), mn_cut(void), mn_copy(void), mn_paste(void), mn_selall(void), mn_format(void), mn_gutter(void);
void mn_find(void), mn_findnext(void), mn_replnext(void), mn_goto(void), mn_nexterr(void);
void mn_run(void), mn_check(void), mn_stop(void), mn_output(void), mn_newline(void);
void mn_help(void), mn_contents(void), mn_index(void), mn_tutorial(void), mn_errors(void);

/* B_FILE (cmd.c) */
void cmd_layout(void), cmd_new(void), cmd_open(void), cmd_save(void), cmd_saveas(void);
void cmd_quit(void), cmd_startdoc(void), cmd_export(void), cmd_cut(void), cmd_copy(void), cmd_paste(void);
extern unsigned char export_ok;

/* B_HELP (help.c), B_SYN (syn.c) */
void help_show(void), help_key(void);
void help_word(void), help_syntax(void);
#define HF_KEYWORDS 0
#define HF_TUTORIAL 1
#define HF_ERRORS   2
#define HF_EDITOR   3
#define HF_MANUAL   4               /* (the manual, DECISIONS V99) */
#define HF_N        5

/* B_FMT (fmt.c) */
void fmt_format(void);

/* B_MK (mk.c, DECISIONS V99): after IR_FORMAT, when ide_make (LOW) is
   MK_PROG or MK_APP; file_types (LOW): the Save dialog's filter, once */
#define MK_PROG 1
#define MK_APP  2
extern unsigned char ide_make;
extern const char *file_types;
void mk_answer(void);
void mn_saveprog(void), mn_makeapp(void);

/* B_DBG (dbg.c), LOW's state of it (low.c) */
extern unsigned char dbg_paused;        /* a program is stopped at a break */
extern unsigned char pane;              /* 0 none, 1 the break's, 2 the trace, 3 an error */
extern unsigned char dfocus;            /* the pane has the keys */
extern unsigned char key_taken;         /* (dbg_key: the key was the pane's) */
extern unsigned int press_y;            /* (dbg_press: the pointer) */
extern unsigned char bp_n;
extern unsigned int bp_line[32];
unsigned char __fastcall__ bp_has(unsigned int line);
void ide_bput(void);
extern unsigned int cellbase;           /* (vb.s: the globals' cells) */
void dbg_draw(void), dbg_break(void), dbg_answer(void), dbg_after(void), dbg_ended(void), dbg_error(void);
void dbg_prep(void), dbg_init(void), dbg_key(void), dbg_focus(void), dbg_press(void);
void dbg_cont(void), dbg_step(void), dbg_over(void), dbg_out(void), dbg_bp(void), dbg_watch(void);
void dbg_tron(void), dbg_trace(void);
void mn_cont(void), mn_step(void), mn_over(void), mn_out(void), mn_bp(void), mn_watch(void);
void mn_tron(void), mn_trace(void);
void fmt_quote(void);                   /* (B_FMT: DI_QUOTE's statement to IDE_OUT) */
/* the debugger's calls between its banks (B_HELP's names, B_LEX's
   tokenizer): their arguments and answers in LOW (low.c) and main RAM's
   scratch */
#define XNAME ((char *)IDEDYN + 1744)   /* 48: a name, a word */
#define XSRC  ((char *)IDEDYN + 1792)   /* 48: an expression's text */
#define RQBUF ((unsigned char *)IDEDYN + 0)    /* 512 (iobuf): the requests being made */
extern unsigned int x_sym, x_off, rqn;
extern unsigned char x_proc, x_kind, x_ok, nv, nloc, nreq;
void fmt_names(void), fmt_vars(void), fmt_symname(void), fmt_procname(void), fmt_findsym(void);   /* (B_HELP: names.c) */
void tk_expr(void);                     /* (B_LEX: XSRC onto RQBUF at rqn; x_ok, or 0 and x_kind the error) */
void __fastcall__ dget(unsigned int at, void *to, unsigned char n);   /* DI (dbgshare.h) <-> main RAM */
void __fastcall__ dput(unsigned int at, const void *from, unsigned char n);

/* the requests (keys.c): the text to the runtime's side */
void __fastcall__ ide_request(unsigned char r);
extern unsigned char req_arg;           /* B_CMD's ide_request_x: ide_request(req_arg) */
void ide_request_x(void);
extern unsigned long jump_line;         /* B_CMD's ide_toline: the cursor to that line */
void ide_toline(void);
void ide_banks_log(void);               /* (B_CMD; the test build's log) */
void test_redraw_a(void), test_redraw_b(void);  /* (the test build's B_FILE: tests/vbasic/ide_redraw.c, V215) */
void test_idle(void);                   /* (its tests/tk_hash.s: a timed record's end) */
extern unsigned int trace_top;          /* B_FILE's trace.c: the trace pane, its first line shown */
void trace_draw(void), trace_log(void);

#endif
