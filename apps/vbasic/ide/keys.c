/* VeraBASIC, the editor (DECISIONS V93): B_VIEW, the bank the kernel calls
   while the editor shows (appBank): the keys, the pointer, the main loop's
   pass, the bars; textkit's view.c is in this bank too (it draws; the
   rows' colours are B_LEX's). The menus' actions are B_CMD's (LOW's mn_*
   stubs). Veranda Edit's main.c is the model.

   MIT licence (LICENSE). */
#include <string.h>
#include <theme.h>
#include <vrwin.h>
#include "ide.h"

static unsigned char dragging;
/* the rows a press on the scroll bar's parts scrolls (VS_*: vrwin.h) */
static const signed char sb_steps[6] = { 0, -1, -(ROWS - 1), 0, ROWS - 1, 1 };

/* the scroll bar again when the rows shown or the lines changed */
static void sb_check(void)
{
    if (top_line != sb_first || nlines != sb_total) {
        sb_first = top_line;
        if (nlines == sb_total) {
            XCALL(B_FMT, sb_move);      /* (V215) the thumb alone */
            return;
        }
        sb_total = nlines;
        XCALL(B_FMT, sb_draw);
    }
}

/* the window drawn (textkit's TK_FRAME_HOOK): the scroll bar, the
   debugger's pane on the next pass */
void ide_frame(void)
{
    pane_dirty = 1;
    sb_total = ~0UL;
    sb_check();
}

/* (other banks: the view drawn, the cursor off) */
void view_off(void)
{
    view_cursor(0);
}

/*---------------------------------------------------------------
  the bars (textkit's view.c calls them)
 ---------------------------------------------------------------*/
/* (B_FMT's bars.c: B_VIEW's room, V215) */
void tk_status(void)
{
    XCALL(B_FMT, ide_status);
}

void tk_title(void)
{
    XCALL(B_FMT, ide_title);
}

static void type(unsigned char c)
{
    if (HAS_SEL()) {
        undo_run(0);
        ed_delete_sel();
        undo_join(U_INS);
    } else
        undo_run(U_INS);
    ed_insert(&c, 1);
}

static void letter(unsigned char c, unsigned char sh)
{
    switch (c | 0x20) {
    case 'a': mn_selall(); break;
    case 'c': mn_copy(); break;
    case 'x': mn_cut(); break;
    case 'v': mn_paste(); break;
    case 'z': mn_undo(); break;
    case 'f': if (sh) mn_format(); else mn_find(); break;
    case 'h': mn_replnext(); break;
    case 'l': case 'g': mn_goto(); break;
    case 'n': mn_new(); break;
    case 'o': mn_open(); break;
    case 's': if (sh) mn_saveas(); else mn_save(); break;
    case 'q': mn_quit(); break;
    case 'r': if (dbg_paused) mn_cont(); else mn_run(); break;
    case 'w': mn_watch(); break;
    case 'k': mn_check(); break;
    case 'b': move_to(gb_len, sh); break;      /* Ctrl+PgDn */
    }
}

void ide_key(void)
{
    unsigned char k = keyData, m = keyDataMods, sh = m & 1, ctrl = m & 2;
    if (help_open) {                    /* the help viewer's keys */
        XCALL(B_HELP, help_key);
        return;
    }
    if (pane >= 2 || (dfocus && pane == 1)) {   /* the debugger's pane (DECISIONS V97) */
        XCALL(B_DBG, dbg_key);
        if (key_taken)
            return;
    }
    need_fix = 1;
    if (status_msg[0]) {                /* a message lasts until the next key */
        status_msg[0] = 0;
        bars_dirty |= B_STATUS;
    }
    if (m & KEYM_ARROW) {
        undo_run(0);
        switch (k) {
        case KEY_LEFT:
            if (ctrl)
                move_word(-1, sh);
            else if (HAS_SEL() && !sh)
                move_to(sel_lo(), 0);
            else
                move_to(cur ? cur - 1 : 0, sh);
            goal = 0xFFFF;
            break;
        case KEY_RIGHT:
            if (ctrl)
                move_word(1, sh);
            else if (HAS_SEL() && !sh)
                move_to(sel_hi(), 0);
            else
                move_to(cur < gb_len ? cur + 1 : cur, sh);
            goal = 0xFFFF;
            break;
        case KEY_UP:
            move_line(-1, sh);
            break;
        case KEY_DOWN:
            move_line(1, sh);
            break;
        }
        return;
    }
    if (ctrl && k >= 1 && k <= 26) {
        undo_run(0);
        letter(k + 0x60, sh);
        return;
    }
    if (k >= 0x80 && (m & 4)) {                 /* Alt + a letter (shortcuts) */
        undo_run(0);
        letter(k & 0x7F, sh);
        return;
    }
    switch (k) {
    case KEY_HOME:
        undo_run(0);
        move_home(sh);
        goal = 0;
        return;
    case KEY_CLEAR:
        undo_run(0);
        move_home(1);
        return;
    case KEY_END:
        undo_run(0);
        if (ctrl)
            move_to(gb_len, sh);
        else
            move_end(sh);
        return;
    case KEY_PGUP:
        undo_run(0);
        if (ctrl)
            move_to(0, sh);
        else
            move_page(-1, sh);
        return;
    case KEY_PGDN:
        undo_run(0);
        move_page(1, sh);
        return;
    case 8:
        undo_run(HAS_SEL() ? 0 : 2);
        ed_backspace();
        return;
    case KEY_DELETE:
        undo_run(HAS_SEL() ? 0 : 3);
        ed_delete();
        return;
    case CR:
    case 0x8D:
        mn_newline();
        return;
    case KEY_TAB:                       /* two blanks: VeraBASIC's indentation */
        if (dbg_paused && pane == 1) {  /* (stopped: the keys to the pane) */
            XCALL(B_DBG, dbg_focus);
            return;
        }
        type(' ');
        type(' ');
        return;
    case KEY_ESC:
        undo_run(0);
        sel_clear();
        return;
    case KEY_F1:
        undo_run(0);
        mn_help();
        return;
    case KEY_F3:
        undo_run(0);
        mn_findnext();
        return;
    case KEY_F5:
        undo_run(0);
        mn_output();
        return;
    case KEY_F8:
        undo_run(0);
        mn_nexterr();
        return;
    case KEY_F6:                        /* the debugger (DECISIONS V97) */
        undo_run(0);
        mn_cont();
        return;
    case KEY_F7:
        undo_run(0);
        mn_step();
        return;
    case KEY_F9:
        undo_run(0);
        mn_bp();
        return;
    case KEY_F10:
        undo_run(0);
        mn_over();
        return;
    case KEY_F11:
        undo_run(0);
        mn_out();
        return;
    case KEY_F12:
        undo_run(0);
        mn_trace();
        return;
    case 0xA0:
        if (sh)
            k = ' ';
        break;
    }
    if ((k >= 32 && k < 127) || k >= 160)
        type(k);
}

/*---------------------------------------------------------------
  the pointer
 ---------------------------------------------------------------*/
static void mouse_xy(unsigned int *x, unsigned int *y)
{
    do {
        *x = mouseXPos;
        *y = mouseYPosW;
    } while (*x != mouseXPos || *y != mouseYPosW);
}

void ide_press(void)
{
    unsigned int x, y;
    unsigned long p;
    unsigned char sh;
    if (help_open) {
        keyData = 0;                    /* (a press: the viewer takes keyData 0) */
        XCALL(B_HELP, help_key);
        return;
    }
    if (mouseData & 0x80) {
        dragging = 0;
        return;
    }
    mouse_xy(&x, &y);
    undo_run(0);
    /* (need_fix only for a press that moves the cursor: view_fix would
       take a view scrolled by the scroll bar back to the cursor, DECISIONS
       V214) */
    if (pane && x >= PANE_X * 8 && x < SB_X * 8 && y >= TY && y < TY + ROWS * 8) {
        need_fix = 1;
        press_y = y;                    /* (the debugger's pane) */
        XCALL(B_DBG, dbg_press);
        return;
    }
    if (view_hit(x, y, &p)) {
        need_fix = 1;
        sh = GetKeyMods() & 1;
        if (!sh && p == cur && !HAS_SEL() && dblClickCount) {
            dblClickCount = 0;
            select_word();
            return;
        }
        move_to(p, sh);
        goal = 0xFFFF;
        dragging = 1;
        dblClickCount = 30;
    } else if (x >= SB_X * 8 && y >= TY && y < TY + ROWS * 8) {
        sb_y = y;                       /* the scroll bar (Sunroom, V149) */
        XCALL(B_FMT, sb_hit);
        view_scroll(sb_steps[sb_part]);
    }
}

static void drag(void)
{
    unsigned int x, y;
    unsigned long p;
    if (mouseData & 0x80) {
        dragging = 0;
        return;
    }
    mouse_xy(&x, &y);
    if (y < TY) {
        move_line(-1, 1);
        need_fix = 1;
        return;
    }
    if (y >= TY + ROWS * 8) {
        move_line(1, 1);
        need_fix = 1;
        return;
    }
    if (x >= (X0 + COLS) * 8)
        x = (X0 + COLS) * 8 - 1;
    if (view_hit(x, y, &p) && p != cur) {
        move_to(p, 1);
        goal = 0xFFFF;
        need_fix = 1;
    }
}

/*---------------------------------------------------------------
  the main loop's pass (LOW's appMain)
 ---------------------------------------------------------------*/
/* (V215) the status bar, its syntax line and the title wait while keys
   come (textkit's tk_hold): drawn once none came for QUIET jiffies */
#define QUIET 8
static unsigned char quiet, syn_due;
static unsigned long last_ls = NOWHERE;
static unsigned int last_col = 0xFFFF;
static unsigned long last_n;

/* lines added or taken away (by the cursor's line): the breakpoints
   after them move with their lines (DECISIONS V97) */
static void bp_follow(void)
{
    long d = (long)nlines - (long)last_n;
    unsigned long c = cur_line + 1;
    unsigned char i, j;
    last_n = nlines;
    if (!bp_n)
        return;
    for (i = j = 0; i < bp_n; ++i) {
        if (d > 0 && bp_line[i] > c - d)
            bp_line[i] += (unsigned int)d;
        else if (d < 0 && bp_line[i] > c) {
            if (bp_line[i] <= c - d)
                continue;               /* (its line went) */
            bp_line[i] -= (unsigned int)-d;
        }
        bp_line[j++] = bp_line[i];
    }
    bp_n = j;
    memset(dirty, 1, ROWS);
}

static void state_log(void)
{
#ifdef IDE_TEST
    if (test_log & 0x80) {              /* (V215) the redraw check: the window */
        view_cursor(0);                 /* as drawn, then drawn whole */
        XCALL(B_FILE, test_redraw_a);
        view_all();
        view_cursor(0);
        XCALL(B_FILE, test_redraw_b);
        return;
    }
    ide_logn("IDE STATE ", test_log);
    ide_logn(" ", cur_line + 1);
    ide_logn(" ", view_col() + 1);
    ide_logn(" ", gb_len);
    ide_logn(" ", nlines);
    ide_logn(" ", modified);
    ide_logn(" ", err_line);
    ide_logn(" ", stop_line);
    ide_log(" ");
    ide_log(docname);
    ide_log("\n");
    test_log = 0;
#endif
}

void ide_tick(void)
{
    signed char w;
    unsigned int y;
    edit_idle = 0;
    if (help_open) {
        edit_idle = 1;
        return;
    }
    if (dragging)
        drag();
    asm("sei");
    w = (signed char)mouseWheel;
    mouseWheel = 0;
    asm("cli");
    if (w && menuNumber == 0)
        view_scroll(3 * w);
    y = mouseYPosW;
    SetPointer(y >= TY && y < TY + ROWS * 8 && mouseXPos >= X0 * 8 && mouseXPos < (X0 + COLS) * 8
               ? PTR_IBEAM : PTR_ARROW);
    if ((pressFlag & SET_KEYPRESS) || tk_keys())
        return;                         /* draw once the keys waiting are in (the ROM's too: V215) */
    if (nlines != last_n)
        bp_follow();
    if (pane_dirty) {
        pane_dirty = 0;
        if (pane)
            XCALL(B_DBG, dbg_draw);
    }
    if (need_fix) {
        need_fix = 0;
        if (cur_ls != last_ls || view_col() != last_col) {
            last_ls = cur_ls;           /* the syntax of the word at the cursor: */
            syn_due = 1;                /* with the status bar (V215) */
        }
        tk_hold = 1;                    /* (V215) the text first, the bars when the keys pause */
        if (goal == 0xFFFF) {
            view_fix();
            goal = view_col();
        } else
            view_fix();
        last_col = view_col();
        sb_check();
        quiet = tk_jiffy();             /* (from the drawing's end) */
        return;
    }
    sb_check();
    if (menuNumber == 0)
        view_blink();
    if (tk_hold && (syn_due || (bars_dirty & (B_STATUS | B_TITLE)))) {
        if ((unsigned char)(tk_jiffy() - quiet) >= QUIET) {
            tk_hold = 0;
            if (syn_due) {
                syn_due = 0;
                XCALL(B_SYN, help_syntax);
                bars_dirty |= B_STATUS;
            }
            view_paint();
            return;
        }
#ifdef IDE_TEST
        play_slow(cursor_on);
        XCALL(B_FILE, test_idle);       /* (a timed record: the text drawn) */
#endif
        return;                         /* (not idle: they wait) */
    }
    edit_idle = 1;
#ifdef IDE_TEST
    play_slow(cursor_on);               /* (the blink probe: tests/edit_play.s) */
    XCALL(B_FILE, test_idle);           /* (V215: a timed record drawn) */
#endif
    if (test_log)
        state_log();
}

