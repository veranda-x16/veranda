/* Veranda Edit: a text editor for plain text files in Veranda's set
   (ISO-8859-16, DECISIONS V140) or UTF-8 (decoded into the set when
   every character is in it, saved as UTF-8 again; File > Encoding or
   Ctrl+E: V143; any other file byte by byte, as it is), with LF,
   CR LF or CR line ends, of up to 400 KB in RAM banks (buf.s: a gap
   buffer across them).

   The screen: Veranda's menu bar; a title bar (the file, its folder);
   79 x 55 cells of 8 x 8 (PutCards, the ROM's ISO and ISO-8859-16 fonts); a
   scroll bar; the status line (line, column, size, line ends, modified).
   Keys go to key(), the pointer to press() and, while a button is held,
   tick(), which also draws: edits mark rows dirty and the main loop draws
   them when no key is waiting (view.c).

   This file and view.c are overlay 1 (misc.c): code only, at $A000.

   MIT licence (see LICENSE). */
#include <string.h>
#include <vrchoose.h>
#include <vrpath.h>
#include <theme.h>
#include <vrwin.h>
#include <vralert.h>
#include "edit.h"
#pragma code-name ("OVERLAY1")

unsigned char dragging;

/*---------------------------------------------------------------
  the commands
 ---------------------------------------------------------------*/
void quit(void)
{
    menus_off();
    call2(m_quit);
}

/* the commands in overlay 2 */
/* (V148) after a new or opened text the menu's encoding is the text's */
void c_new(void) { menus_off(); call2(m_new); call2(layout); view_all(); }
void c_open(void) { menus_off(); call2(m_open); call2(layout); view_all(); }
void c_save(void) { menus_off(); call2(m_save); }
void c_saveas(void) { menus_off(); call2(m_saveas); }
void c_find(void) { menus_off(); call2(m_find); }
void c_findnext(void) { menus_off(); call2(m_findnext); }
void c_replnext(void) { menus_off(); call2(m_replnext); }
void c_goto(void) { menus_off(); call2(m_goto); }
void mc_cut(void) { menus_off(); call2(m_cut); }
void mc_copy(void) { menus_off(); call2(m_copy); }
void mc_paste(void) { menus_off(); call2(m_paste); }

/* (V143) UTF-8 or the set when saving: the text changes on the card */
void c_enc(void)
{
    menus_off();
    tk_enc ^= 1;
    modified = 1;
    bars_dirty |= B_STATUS | B_TITLE;
    call2(layout);
    view_status_msg(tk_enc ? "Saved as UTF-8" : "Saved as ISO-8859-16");
}

void m_about(void)
{
    menus_off();
    alert(VA_OK, "Veranda Edit 1.1", "Text in UTF-8 or ISO-8859-16, with LF, CR LF or CR line ends. MIT licence.");
    need_fix = 1;
}

void m_undo(void)
{
    menus_off();
    if (!undo())
        view_status_msg("Nothing to undo");
}

void m_selall(void)
{
    menus_off();
    select_all();
}


/* a desk accessory from the applications' folder (DBGETFILES, DESK_ACC) */
struct filedlg {
    unsigned char pos;
    unsigned char f, fx, fy;
    unsigned char op, opx, opy;
    unsigned char cn, cnx, cny;
    unsigned char end;
};
static const struct filedlg dabox = {
    DEF_DB_POS | 1,
    DBGETFILES, 4, 4,
    OPEN, DBI_X_2, DBI_Y_0,
    CANCEL, DBI_X_2, DBI_Y_2,
    0
};

void m_desk(void)
{
    static char da[17];
    unsigned char r;
    menus_off();
    view_cursor(0);
    sys_dir();
    da[0] = 0;
    r5 = (unsigned int)da;
    r7L = DESK_ACC;
    r10 = 0;
    r = DoDlgBox((void *)&dabox);
    if (r == OPEN && da[0]) {
        r = GetFile(da, 0, 0, 0, 0);
        if (r)
            message("Cannot open", da);
    } else if (r == DBGETFILES)
        message("There are no desk accessories", "in /VERANDA/APPS.");
    doc_dir();
}

/*---------------------------------------------------------------
  the bars (textkit's view.c calls them)
 ---------------------------------------------------------------*/
void tk_status(void)
{
    /* (V148, Sunroom) the status bar's texts in the UI font (vrwin.h):
       at the left the place, the size and the selection; at the right a
       message, else the line ends, the encoding, modified */
    static char rt[48];
    static const char *const eols[3] = { "LF", "CR LF", "CR" };
    char *p = tk_line;
    p = tk_put_s(p, "Line ");
    p = tk_put_ul(p, cur_line + 1);
    p = tk_put_s(p, " of ");
    p = tk_put_ul(p, nlines);
    p = tk_put_s(p, "     Col ");
    p = tk_put_ul(p, (unsigned long)view_col() + 1);
    p = tk_put_s(p, "     ");
    p = tk_put_ul(p, gb_len);
    p = tk_put_s(p, " bytes");
    if (HAS_SEL()) {
        p = tk_put_s(p, "     ");
        p = tk_put_ul(p, sel_hi() - sel_lo());
        p = tk_put_s(p, " selected");
    }
    *p = 0;
    if (status_msg[0])
        vr_win_status(&tk_win, tk_line, status_msg);
    else {
        p = tk_put_s(rt, eols[eol]);
        p = tk_put_s(p, tk_enc ? "     UTF-8" : "     ISO-8859-16");
        if (modified)
            p = tk_put_s(p, "     Modified");
        *p = 0;
        vr_win_status(&tk_win, tk_line, rt);
    }
}

/* the title band: the file, modified, its folder */
void tk_title(void)
{
    unsigned char l;
    char *q = tk_line;
    q = tk_put_s(q, docname[0] ? docname : "Untitled");
    if (modified)
        q = tk_put_s(q, " *");
    q = tk_put_s(q, "  -  ");
    l = strlen((char *)curDirName);
    if (l > 40) {
        q = tk_put_s(q, "...");
        q = tk_put_s(q, (char *)curDirName + l - 37);
    } else
        q = tk_put_s(q, (char *)curDirName);
    *q = 0;
    vr_win_title(&tk_win, tk_line);
}

/*---------------------------------------------------------------
  keys
 ---------------------------------------------------------------*/
static void type(unsigned char c)
{
    if (HAS_SEL()) {
        undo_run(0);
        ed_delete_sel();
        undo_join(U_INS);
    } else
        undo_run(c == 10 ? 0 : U_INS);
    ed_insert(&c, 1);
    if (c == 10)
        undo_step();
}

static void letter(unsigned char c)
{
    switch (c | 0x20) {
    case 'a': m_selall(); break;
    case 'c': mc_copy(); break;
    case 'x': mc_cut(); break;
    case 'v': mc_paste(); break;
    case 'z': m_undo(); break;
    case 'f': c_find(); break;
    case 'r': c_replnext(); break;
    case 'l': case 'g': c_goto(); break;
    case 'n': c_new(); break;
    case 'o': c_open(); break;
    case 's': if (keyDataMods & 1) c_saveas(); else c_save(); break;
    case 'q': quit(); break;
    case 'e': c_enc(); break;
    case 'b': move_to(gb_len, keyDataMods & 1); break;     /* Ctrl+PgDn */
    }
}

static void key(void)
{
    unsigned char k = keyData, m = keyDataMods, sh = m & 1, ctrl = m & 2;
    need_fix = 1;
    if (status_msg[0]) {                /* a message lasts until the next key */
        status_msg[0] = 0;
        bars_dirty |= B_STATUS;
    }
#ifdef EDIT_TEST
    test_key(k);
#endif
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
        case KEY_UP:                    /* (Ctrl + Down is Ctrl + Q's code: */
            move_line(-1, sh);          /* the ROM's Ctrl map, DECISIONS V34) */
            break;
        case KEY_DOWN:
            move_line(1, sh);
            break;
        }
        return;
    }
    if (ctrl && k >= 1 && k <= 26) {
        undo_run(0);
        letter(k + 0x60);
        return;
    }
    if (k >= 0x80 && (m & 4)) {                 /* Alt + a letter (shortcuts) */
        undo_run(0);
        letter(k & 0x7F);
        return;
    }
    switch (k) {
    case KEY_HOME:
        undo_run(0);
        move_home(sh);
        goal = 0;
        return;
    case KEY_CLEAR:                     /* Shift + Home */
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
            move_to(0, sh);             /* Ctrl + PgUp, Ctrl + Home (the kernel) */
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
        type(10);
        return;
    case KEY_TAB:
        type(9);
        return;
    case KEY_ESC:
        undo_run(0);
        sel_clear();
        return;
    case KEY_F3:
        undo_run(0);
        c_findnext();
        return;
    case 0xA0:
        if (sh)
            k = ' ';                    /* Shift + Space */
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

static void press(void)
{
    unsigned int x, y;
    unsigned long p;
    unsigned char sh;
    if (mouseData & 0x80) {
        dragging = 0;
        return;
    }
    mouse_xy(&x, &y);
    need_fix = 1;
    undo_run(0);
    if (view_hit(x, y, &p)) {
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
    } else if (x >= SBX * 8 && y >= TY && y < TY + ROWS * 8) {
        /* the scroll bar: a page towards the pointer */
        view_scroll(y < TY + 8 * (ROWS / 2) ? -(ROWS - 1) : ROWS - 1);
    }
}

static void drag(void)
{
    unsigned int x, y;
    unsigned long p;
    if (mouseData & 0x80) {             /* (the button is up) */
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
    if (x >= COLS * 8)
        x = COLS * 8 - 1;
    if (view_hit(x, y, &p) && p != cur) {
        move_to(p, 1);
        goal = 0xFFFF;
        need_fix = 1;
    }
}

/*---------------------------------------------------------------
  the main loop
 ---------------------------------------------------------------*/
static void tick(void)
{
    signed char w;
    unsigned int y;
    edit_idle = 0;
    if (dragging)
        drag();
    asm("sei");
    w = (signed char)mouseWheel;
    mouseWheel = 0;
    asm("cli");
    if (w && menuNumber == 0)
        view_scroll(3 * w);
    y = mouseYPosW;
    SetPointer(y >= TY && y < TY + ROWS * 8 && mouseXPos < COLS * 8 ? PTR_IBEAM : PTR_ARROW);
    if (pressFlag & SET_KEYPRESS)
        return;                         /* draw once the keys waiting are in */
    if (need_fix) {
        need_fix = 0;
        if (goal == 0xFFFF) {
            view_fix();
            goal = view_col();
        } else
            view_fix();
#ifdef EDIT_TEST
        test_drawn();
#endif
        return;
    }
    if (menuNumber == 0)
        view_blink();
    edit_idle = 1;                      /* (a drag waits for the pointer) */
#ifdef EDIT_TEST
    play_slow(cursor_on);               /* (the blink probe: tests/edit_play.s) */
    if (test_log)
        test_log_state();
#endif
}

void __fastcall__ a_main(unsigned char opts)
{
    dispBufferOn = ST_WR_FORE;
    vr_home(opts);                      /* /DOCUMENTS first (DECISIONS V71) */
    if (curDirName[0] != '/')
        strcpy((char *)curDirName, "/");
    font_load();
    vr_alert_icon = vr_icon;            /* (V148: its alerts) */
    undo_init();
    call2(doc_new);
    call2(layout);
    view_frame();
#ifdef EDIT_TEST
    test_start();
#endif
    if ((opts & ST_LD_DATA) && dataFileName[0]) {
        call2(m_startdoc);
        call2(layout);
    }
    theme_menus();                      /* the menu bar (DECISIONS V74, V79) */
    DoMenu(menubar, 0);
    keyVector = VR_FN(key);
    otherPressVec = VR_FN(press);
    appMain = VR_FN(tick);
    view_all();
    LogText("EDIT RUNNING");
}
