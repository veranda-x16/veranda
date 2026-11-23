/* VeraBASIC, the editor (DECISIONS V93): its main RAM part's C (LOW: the
   state the banks share, the dialog boxes' and menus' tables, which the
   kernel reads below $A000, and the calls every bank makes). Veranda
   Edit's misc.c is the model.

   MIT licence (LICENSE). */
#include <string.h>
#include <vrchoose.h>
#include <vrpath.h>
#include <theme.h>
#include "ide.h"

unsigned char need_fix, ide_first, colour_on, gutter_on, help_open, help_file, ide_test;
unsigned char tk_x0, tk_cols = SB_X;
unsigned long sb_first, sb_total;       /* the scroll bar (B_FMT's sbar.c) */
unsigned int sb_at, sb_len, sb_y;
unsigned char sb_part;
unsigned long err_line, stop_line, check_after;
char help_req[40];

/*---------------------------------------------------------------
  dialog boxes (their tables and texts here, below $A000)
 ---------------------------------------------------------------*/
struct askdlg {
    unsigned char pos;
    unsigned char t1, x1, y1, reg1;
    unsigned char t2, x2, y2, reg2, max;
    unsigned char ok, okx, oky;
    unsigned char cn, cnx, cny;
    unsigned char end;
};
static struct askdlg askbox = {
    DEF_DB_POS | 1,
    DBVARSTR, TXT_LN_X, TXT_LN_2_Y, 0x0E,
    DBGETSTRING, TXT_LN_X, TXT_LN_3_Y, 0x0C, 20,
    OK, DBI_X_0, DBI_Y_2,
    CANCEL, DBI_X_2, DBI_Y_2,
    0
};
struct msgdlg {
    unsigned char pos;
    unsigned char t1, x1, y1, reg1;
    unsigned char t2, x2, y2, reg2;
    unsigned char ok, okx, oky;
    unsigned char b2, b2x, b2y;
    unsigned char b3, b3x, b3y;
    unsigned char end;
};
static const struct msgdlg msgbox = {
    DEF_DB_POS | 1,
    DBVARSTR, TXT_LN_X, TXT_LN_2_Y, 0x0C,
    DBVARSTR, TXT_LN_X, TXT_LN_3_Y, 0x0E,
    OK, DBI_X_0, DBI_Y_2,
    0
};
static const struct msgdlg yesnobox = {
    DEF_DB_POS | 1,
    DBVARSTR, TXT_LN_X, TXT_LN_2_Y, 0x0C,
    DBVARSTR, TXT_LN_X, TXT_LN_3_Y, 0x0E,
    YES, DBI_X_0, DBI_Y_2,
    NO, DBI_X_2, DBI_Y_2,
    0
};
static const struct msgdlg yncbox = {
    DEF_DB_POS | 1,
    DBVARSTR, TXT_LN_X, TXT_LN_2_Y, 0x0C,
    DBVARSTR, TXT_LN_X, TXT_LN_3_Y, 0x0E,
    YES, DBI_X_0, DBI_Y_2,
    NO, DBI_X_1, DBI_Y_2,
    CANCEL, DBI_X_2, DBI_Y_2,
    0
};
#define msga ide_msga
#define msgb ide_msgb

static void texts(const char *a, const char *b)
{
    strncpy(msga, a, 47);
    msga[47] = 0;
    strncpy(msgb, b, 63);
    msgb[63] = 0;
    r5 = (unsigned int)msga;
    r6 = (unsigned int)msgb;
}

void message(const char *a, const char *b)
{
    Beep();
    texts(a, b);                        /* (after: Beep changes r5, r6) */
    ide_log("IDE BOX ");
    ide_log(msga);
    ide_log(" / ");
    ide_log(msgb);
    ide_log("\n");
    DoDlgBox((void *)&msgbox);
    need_fix = 1;
}

unsigned char yesno(const char *a, const char *b)
{
    unsigned char r;
    texts(a, b);
    r = DoDlgBox((void *)&yesnobox);
    need_fix = 1;
    return r == YES;
}

unsigned char yesnocancel(const char *a, const char *b)
{
    unsigned char r;
    texts(a, b);
    r = DoDlgBox((void *)&yncbox);
    need_fix = 1;
    return r;
}

unsigned char ask(const char *prompt, char *buf, unsigned char max)
{
    unsigned char r;
    askbox.max = max;
    texts(prompt, "");
    r5 = (unsigned int)buf;
    r = DoDlgBox((void *)&askbox);
    need_fix = 1;
    return r == OK || r == DBGETSTRING;
}

void menus_off(void)
{
    GotoFirstMenu();
    need_fix = 1;
}

void view_status_msg(const char *s)
{
    strncpy(status_msg, s, 63);
    status_msg[63] = 0;
    bars_dirty |= B_STATUS;
    ide_log("IDE MSG ");
    ide_log(s);
    ide_log("\n");
}

char scrap_path[40];                    /* (the scrap library's: B_FILE) */

void sys_dir(void)
{
    vr_cd(VR_APPS);
}

void doc_dir(void)
{
    ChDir((char *)curDirName);
}

static void idle(void)
{
    edit_idle = 1;
}

/* the Open and Save dialog (vrchoose.h) in B_DLG; its variables in main
   RAM's scratch (ide.cfg DYN), cleared first as crt0 clears a BSS */
static const char types[] = TK_TYPES;
const char *file_types;                 /* (B_MK's filter, for one box) */
unsigned char ide_make;
extern unsigned char _B3BSS_RUN__[], _B3BSS_SIZE__[];

unsigned char __fastcall__ file_dlg(unsigned char mode, const char *title, char *name)
{
    unsigned char r, b = *(volatile unsigned char *)0;
    memset(_B3BSS_RUN__, 0, (unsigned int)_B3BSS_SIZE__);
    vr_file_hook = idle;                /* (the test's player: the box waits) */
    vr_file_types = file_types ? file_types : types;
    file_types = 0;
    MAPBANK(ide_banks[B_DLG]);
    r = vr_file(mode, title, name);
    MAPBANK(b);
    return r;
}


/*---------------------------------------------------------------
  the menus (B_VIEW's actions; the texts laid out by B_FILE's cmd_layout)
 ---------------------------------------------------------------*/
struct item { const char *text; unsigned char type; void *p; };
struct menu1 { unsigned char top, bottom; unsigned int left, right; unsigned char flags; struct item i[1]; };
struct menu4 { unsigned char top, bottom; unsigned int left, right; unsigned char flags; struct item i[4]; };
struct menu5 { unsigned char top, bottom; unsigned int left, right; unsigned char flags; struct item i[5]; };
struct menu6 { unsigned char top, bottom; unsigned int left, right; unsigned char flags; struct item i[6]; };
struct menu7 { unsigned char top, bottom; unsigned int left, right; unsigned char flags; struct item i[7]; };
struct menu12 { unsigned char top, bottom; unsigned int left, right; unsigned char flags; struct item i[12]; };
#define IH 14
struct menu1 mi_vb = { 14, 14 + 1 * IH, 0, 0, VERTICAL | 1, {
    { "About VeraBASIC", MENU_ACTION, mn_about } } };
struct menu7 mi_file = { 14, 14 + 7 * IH, 0, 0, VERTICAL | 7, {
    { 0, MENU_ACTION, mn_new }, { 0, MENU_ACTION, mn_open }, { 0, MENU_ACTION, mn_save },
    { 0, MENU_ACTION, mn_saveas }, { 0, MENU_ACTION, mn_saveprog }, { 0, MENU_ACTION, mn_makeapp },
    { 0, MENU_ACTION, mn_quit } } };
struct menu7 mi_edit = { 14, 14 + 7 * IH, 0, 0, VERTICAL | 7, {
    { 0, MENU_ACTION, mn_undo }, { 0, MENU_ACTION, mn_cut }, { 0, MENU_ACTION, mn_copy },
    { 0, MENU_ACTION, mn_paste }, { 0, MENU_ACTION, mn_selall }, { 0, MENU_ACTION, mn_format },
    { 0, MENU_ACTION, mn_gutter } } };
struct menu5 mi_search = { 14, 14 + 5 * IH, 0, 0, VERTICAL | 5, {
    { 0, MENU_ACTION, mn_find }, { 0, MENU_ACTION, mn_findnext }, { 0, MENU_ACTION, mn_replnext },
    { 0, MENU_ACTION, mn_goto }, { 0, MENU_ACTION, mn_nexterr } } };
struct menu12 mi_run = { 14, 14 + 12 * IH, 0, 0, VERTICAL | 12, {
    { 0, MENU_ACTION, mn_run }, { 0, MENU_ACTION, mn_check }, { 0, MENU_ACTION, mn_stop },
    { 0, MENU_ACTION, mn_output }, { 0, MENU_ACTION, mn_cont }, { 0, MENU_ACTION, mn_step },
    { 0, MENU_ACTION, mn_over }, { 0, MENU_ACTION, mn_out }, { 0, MENU_ACTION, mn_bp },
    { 0, MENU_ACTION, mn_watch }, { 0, MENU_ACTION, mn_tron }, { 0, MENU_ACTION, mn_trace } } };
struct menu5 mi_help = { 14, 14 + 5 * IH, 0, 0, VERTICAL | 5, {
    { 0, MENU_ACTION, mn_help }, { 0, MENU_ACTION, mn_contents }, { 0, MENU_ACTION, mn_index },
    { 0, MENU_ACTION, mn_tutorial }, { 0, MENU_ACTION, mn_errors } } };
struct menu6 mi_bar = { 0, 14, 0, 0, HORIZONTAL | UN_CONSTRAINED | 6, {
    { "VeraBASIC", SUB_MENU, &mi_vb }, { "File", SUB_MENU, &mi_file }, { "Edit", SUB_MENU, &mi_edit },
    { "Search", SUB_MENU, &mi_search }, { "Run", SUB_MENU, &mi_run }, { "Help", SUB_MENU, &mi_help } } };
void *const ide_menubar = &mi_bar;
unsigned int barx[6];                   /* the bar's items (the test's script) */
char mi_text[560];                      /* the items' texts, one after the other (cmd_layout: 528 bytes, V149) */

void ide_redraw_menu(void)
{
    theme_menus();
    DoMenu(ide_menubar, 0);
}

/*---------------------------------------------------------------
  the test build's log (the emulator's console)
 ---------------------------------------------------------------*/
#define EMU_OUT (*(volatile unsigned char *)0x9FBB)
void ide_log(const char *s)
{
#ifdef IDE_TEST
    while (*s)
        EMU_OUT = *s++;
#else
    (void)s;
#endif
}

void ide_logn(const char *s, unsigned long n)
{
#ifdef IDE_TEST
    char b[11];
    unsigned char i = 10;
    ide_log(s);
    b[10] = 0;
    do {
        b[--i] = '0' + (unsigned char)(n % 10);
        n /= 10;
    } while (n);
    ide_log(b + i);
#else
    (void)s;
    (void)n;
#endif
}

/* the debugger (DECISIONS V97): its state, the breakpoints (their source
   lines; B9 gives them to the debugger's DI_BP before a run) */
unsigned char dbg_paused, pane, dfocus, bp_n, key_taken, pane_dirty;
unsigned int press_y;
unsigned int bp_line[32];

unsigned int x_sym, x_off, rqn, trace_top;
unsigned char x_proc, x_kind, x_ok, nv, nloc, nreq;

/* DI (overlay 12's bank, dbgshare.h) and main RAM: n bytes (1-255; to
   main RAM only below $A000) */
void __fastcall__ dget(unsigned int at, void *to, unsigned char n)
{
    bg_bank = vx_dbg;
    bg_at = (void *)at;
    bg_to = to;
    bg_n = n;
    ide_bget();
}

void __fastcall__ dput(unsigned int at, const void *from, unsigned char n)
{
    bg_bank = vx_dbg;
    bg_at = (void *)at;
    bg_to = (void *)from;
    bg_n = n;
    ide_bput();
}

unsigned char __fastcall__ bp_has(unsigned int line)
{
    unsigned char i;
    for (i = 0; i < bp_n; ++i)
        if (bp_line[i] == line)
            return 1;
    return 0;
}

/* textkit's row hook (view.c in B_VIEW): the row coloured by B_LEX */
unsigned char lex_row;
void __fastcall__ ide_rowx(unsigned char r)
{
    lex_row = r;
    XCALL(B_LEX, ide_row);
}
