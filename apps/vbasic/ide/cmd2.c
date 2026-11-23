/* VeraBASIC, the editor (DECISIONS V93): B_CMD, the menus' actions (LOW's
   mn_* stubs call them here: low.s), the start and the way back from the
   runtime's side, the requests (the text to it), the answers it gives (the
   error jumps), Return's indentation, find and replace (textkit's find.c
   is in this bank too).

   MIT licence (LICENSE). */
#include <string.h>
#include <vrpath.h>
#include <theme.h>
#include <vrwin.h>
#include "ide.h"

unsigned char ide_lastreq;

/*---------------------------------------------------------------
  the requests: the text to a run of banks (B_FILE), then appMain's next
  pass goes to the runtime's side (LOW)
 ---------------------------------------------------------------*/
/* (another bank's request: B9's) */
unsigned char req_arg;
void ide_request_x(void)
{
    ide_request(req_arg);
}

static const char stopped_msg[] = "A program is stopped: F6 goes on, Run > Stop ends it";

void __fastcall__ ide_request(unsigned char r)
{
    if (help_open)
        return;
    if (dbg_paused && r < IR_CONT) {    /* (the debugger, DECISIONS V97) */
        view_status_msg(stopped_msg);
        return;
    }
    XCALL(B_VIEW, view_off);
    XCALL(B_HELP, help_free);           /* (the help's banks: the tokenizer's, the program's) */
    if (r < IR_OUTPUT) {
        if (vt_recb[0] && !dbg_paused) {    /* (the last run's names) */
            BankFree(vt_recb[0]);
            vt_recb[0] = 0;
        }
        XCALL(B_FILE, cmd_export);
        if (!export_ok)
            return;
    }
    ide_lastreq = r;
    if (r == IR_RUN)
        XCALL(B_DBG, dbg_prep);         /* the breakpoints, the trace emptied */
    vt_after = r == IR_CHECK ? (unsigned int)check_after : 0;
    check_after = 0;
    if (err_line || stop_line) {        /* (the old marks go: their rows drawn) */
        err_line = stop_line = 0;
        memset(dirty, 1, ROWS);
        XCALL(B_VIEW, view_paint);
    }
    XCALL(B_VIEW, view_off);
    status_msg[0] = 0;
    ide_logn("IDE REQ ", r);
    ide_log("\n");
    ide_req = r;
}

/*---------------------------------------------------------------
  the menus' actions (the kernel calls them with this bank mapped)
 ---------------------------------------------------------------*/
void do_about(void)
{
    menus_off();
    message("VeraBASIC 1.0: the editor and the runtime,", "for Veranda. MIT licence");
}
static unsigned char paused(void)
{
    if (dbg_paused)
        view_status_msg(stopped_msg);
    return dbg_paused;
}
void do_new(void) { menus_off(); if (!paused()) XCALL(B_FILE, cmd_new); }
void do_open(void) { menus_off(); if (!paused()) XCALL(B_FILE, cmd_open); }
void do_save(void) { menus_off(); XCALL(B_FILE, cmd_save); }
void do_saveas(void) { menus_off(); XCALL(B_FILE, cmd_saveas); }
void do_quit(void) { menus_off(); if (!paused()) XCALL(B_FILE, cmd_quit); }
/* File > Save program, Make application... (DECISIONS V99): the records
   made as for Format, then B_MK writes them (fmt_answer) */
static void make(unsigned char m)
{
    menus_off();
    if (paused())
        return;
    ide_make = m;
    ide_request(IR_FORMAT);
    if (ide_req != IR_FORMAT)
        ide_make = 0;
}
void do_saveprog(void) { make(MK_PROG); }
void do_makeapp(void) { make(MK_APP); }
void do_undo(void)
{
    menus_off();
    if (!undo())
        view_status_msg("Nothing to undo");
}
void do_cut(void) { menus_off(); XCALL(B_FILE, cmd_cut); }
void do_copy(void) { menus_off(); XCALL(B_FILE, cmd_copy); }
void do_paste(void) { menus_off(); XCALL(B_FILE, cmd_paste); }
void do_selall(void) { menus_off(); select_all(); }
void do_format(void) { menus_off(); ide_request(IR_FORMAT); }
void do_gutter(void)
{
    menus_off();
    gutter_on ^= 1;
    ide_relayout();
    XCALL(B_VIEW, view_all);
}
void do_find(void) { menus_off(); m_find(); }
void do_findnext(void) { menus_off(); m_findnext(); }
void do_replnext(void) { menus_off(); m_replnext(); }
void do_goto(void) { menus_off(); m_goto(); }
void do_nexterr(void)
{
    menus_off();
    if (!err_line) {
        view_status_msg("No error shown: Check first (Ctrl+K)");
        return;
    }
    check_after = err_line;
    ide_request(IR_CHECK);
}
void do_run(void)
{
    menus_off();
    if (dbg_paused)
        XCALL(B_DBG, dbg_cont);
    else {
        ide_step = 0;
        ide_request(IR_RUN);
    }
}
void do_check(void) { menus_off(); check_after = 0; ide_request(IR_CHECK); }
void do_stop(void)
{
    menus_off();
    if (dbg_paused)                     /* the stopped program ended */
        ide_request(IR_DEND);
    else
        view_status_msg("No program runs (Ctrl+C stops one while it runs)");
}
void do_output(void) { menus_off(); ide_request(IR_OUTPUT); }
static void help_page(const char *p, unsigned char f)
{
    strcpy(help_req, p);
    help_file = f;
    XCALL(B_VIEW, view_off);
    XCALL(B_HELP, help_show);
}
void do_help(void) { menus_off(); XCALL(B_VIEW, view_off); XCALL(B_SYN, help_word); }
void do_contents(void) { menus_off(); help_page("Contents", HF_KEYWORDS); }
void do_index(void) { menus_off(); help_page("Index", HF_KEYWORDS); }
void do_tutorial(void) { menus_off(); help_page("Tutorial", HF_TUTORIAL); }
void do_errors(void) { menus_off(); help_page("Errors", HF_ERRORS); }

/*---------------------------------------------------------------
  the start, and the way back from the runtime's side (LOW's enter)
 ---------------------------------------------------------------*/
static void the_start(void)
{
    dispBufferOn = ST_WR_FORE;
    vr_home(ide_opts);                  /* /DOCUMENTS first (DECISIONS V71) */
    if (curDirName[0] != '/')
        strcpy((char *)curDirName, "/");
    theme_load();
    colour_on = !theme_none();
#ifdef IDE_TEST
    ide_test = 1;
#endif
    ide_relayout();
    undo_init();
    XCALL(B_DBG, dbg_init);             /* (the debugger: no breakpoints, no trace) */
    XCALL(B_FILE, doc_new);
    XCALL(B_FILE, cmd_layout);
    XCALL(B_VIEW, view_frame);
    if ((ide_opts & ST_LD_DATA) && dataFileName[0])
        XCALL(B_FILE, m_startdoc);
    ide_redraw_menu();
    XCALL(B_VIEW, view_all);
    ide_log("IDE RUNNING\n");
    ide_banks_log();
}

/* (the test build: the RAM banks for programs and those free, to the log) */
void ide_banks_log(void)
{
#ifdef IDE_TEST
    TaskCtl(TASK_INFO, 0xFF, lexbuf);
    ide_logn("IDE BANKS ", lexbuf[TS_BANKS]);
    ide_logn(" ", lexbuf[TS_FREE]);
    ide_log("\n");
#endif
}

void ide_resume(void)
{
    if (!ide_first) {
        ide_first = 1;
        status_msg[0] = syn_line[0] = 0;
        the_start();
        return;
    }
    /* back: ide_req 1 if the screen was given back as it was */
    if (ide_req) {
        ide_redraw_menu();
        cursor_on = 0;                  /* (the screen was saved with it off) */
    } else {
        theme_palette();
        ide_redraw_menu();
        XCALL(B_VIEW, view_all);
    }
    ide_req = IR_NONE;
    status_msg[0] = syn_line[0] = 0;    /* (main RAM's scratch: a program's names were there) */
    fmt_answer();
    bars_dirty |= B_STATUS | B_TITLE;
    need_fix = 1;
}

/*---------------------------------------------------------------
  keys
 ---------------------------------------------------------------*/
/* the line's leading blanks (from its start ls): how many */
static unsigned char lead(unsigned long ls)
{
    unsigned char n = 0, k, c;
    gb_a = ls;
    gb_n = 64;
    gb_lp = lexbuf;
    k = (unsigned char)gb_read();
    while (n < k && ((c = lexbuf[n]) == ' ' || c == 9))
        ++n;
    return n;
}

/* the first word of the line at ls (after a line number or a label), upper
   case, into w (12 at most); the rest's first word too (THEN at the end?) */
static unsigned char first_word(char *w)
{
    unsigned char i = 0, n = 0, c;
    while (lexbuf[i] == ' ' || lexbuf[i] == 9)
        ++i;
    while (lexbuf[i] >= '0' && lexbuf[i] <= '9')
        ++i;
    while (lexbuf[i] == ' ' || lexbuf[i] == 9)
        ++i;
    for (;;) {
        c = lexbuf[i];
        if (c >= 'a' && c <= 'z')
            c -= 32;
        if (!((c >= 'A' && c <= 'Z') || (n && c >= '0' && c <= '9') || c == '_'))
            break;
        if (n < 12)
            w[n++] = c;
        ++i;
    }
    w[n] = 0;
    if (lexbuf[i] == ':' && n && strcmp(w, "ELSE")) {    /* a label: the next word */
        ++i;
        while (lexbuf[i] == ' ')
            ++i;
        n = 0;
        while (((c = lexbuf[i] & 0xDF) >= 'A' && c <= 'Z') && n < 12) {
            w[n++] = c;
            ++i;
        }
        w[n] = 0;
    }
    return i;
}

static unsigned char is(const char *w, const char *const *list)
{
    while (*list) {
        if (!strcmp(w, *list))
            return 1;
        ++list;
    }
    return 0;
}

static const char *const opens[] = { "FOR", "WHILE", "REPEAT", "DO", "SUB", "FUNCTION", "TRY",
    "DIALOG", "MENU", "SELECT", "ELSE", "ELSEIF", "CASE", "CATCH", 0 };
static const char *const closes[] = { "NEXT", "WEND", "UNTIL", "LOOP", "END", "ELSE", "ELSEIF",
    "CASE", "CATCH", 0 };

/* the line (lexbuf, n bytes) ends with THEN (a block IF), a comment after it allowed */
static unsigned char ends_then(unsigned char n)
{
    unsigned char i, q = 0, end = n;
    for (i = 0; i < n && lexbuf[i] != 10; ++i) {
        if (lexbuf[i] == '"')
            q ^= 1;
        else if (lexbuf[i] == '\'' && !q) {
            end = i;
            break;
        }
    }
    if (i < end)
        end = i;
    while (end && (lexbuf[end - 1] == ' ' || lexbuf[end - 1] == 9))
        --end;
    return end >= 4 && (lexbuf[end - 4] & 0xDF) == 'T' && (lexbuf[end - 3] & 0xDF) == 'H'
        && (lexbuf[end - 2] & 0xDF) == 'E' && (lexbuf[end - 1] & 0xDF) == 'N';
}

/* the indentation the line at ls has; its first word into w; lexbuf its
   bytes (end: up to its LF) */
static unsigned char line_info(unsigned long ls, char *w, unsigned char *end)
{
    unsigned char ind, i, n;
    ind = lead(ls);
    gb_a = ls;
    gb_n = 255;
    gb_lp = lexbuf;
    n = (unsigned char)gb_read();
    for (i = 0; i < n && lexbuf[i] != 10; ++i)
        ;
    *end = i;
    lexbuf[i] = 0;                      /* (the line's end: what is after it is not its) */
    first_word(w);
    return ind;
}

/* Return: a new line, indented as this one, by 2 more after a block's
   opening line (FOR, IF ... THEN, SUB, CASE ...); a closing word (NEXT,
   END IF, ELSE, CASE ...) typed at the indentation of the line before it
   goes back by 2 first (END SELECT by 4: its CASEs are 2 in) */
void do_newline(void)
{
    char w[13], pw[13];
    unsigned char ind, ps, end, pend, d, sel;
    unsigned long ls = cur_ls;
    static char sp[66];
    ind = line_info(ls, w, &end);
    if (HAS_SEL() || ind >= 64) {
        ed_insert("\n", 1);
        return;
    }
    sel = !strcmp(w, "END");
    if (ind >= 2 && is(w, closes) && cur > ls + ind && cur_line) {
        gb_a = ls - 1;
        gb_line_start();
        ps = line_info(gb_a, pw, &pend);
        d = 0;
        if (ps >= ind)
            d = 2;
        if (d && sel && ind >= 4) {     /* END SELECT: 4 */
            ind = line_info(ls, w, &end);
            for (pend = 0; pend + 6 < end; ++pend)
                if ((lexbuf[pend] & 0xDF) == 'S' && (lexbuf[pend + 1] & 0xDF) == 'E'
                    && (lexbuf[pend + 2] & 0xDF) == 'L' && (lexbuf[pend + 5] & 0xDF) == 'T') {
                    d = 4;
                    break;
                }
        }
        if (d) {
            undo_step();
            undo_push(U_DEL, ls, d);
            raw_delete(ls, d);
            cur -= d;
            anchor = cur;
        }
        ind = line_info(ls, w, &end);
    }
    if (is(w, opens) || (!strcmp(w, "IF") && ends_then(end)))
        ind += 2;
    if (ind > 64)
        ind = 64;
    sp[0] = 10;
    memset(sp + 1, ' ', ind);
    undo_run(0);
    ed_insert(sp, ind + 1);
    undo_step();
}


/* the gutter on or off: the text's first column, its width */
void ide_relayout(void)
{
    tk_x0 = gutter_on ? 5 : 0;
    tk_cols = (pane ? PANE_X : SB_X) - tk_x0;     /* (the debugger's pane at the right) */
    hs = 0;
}

/*---------------------------------------------------------------
  the line jumps
 ---------------------------------------------------------------*/

/* the cursor to line n (from 1), the view on it */
static void to_line(unsigned long n)
{
    unsigned long p = 0;
    unsigned int k;
    if (!n)
        return;
    --n;
    while (n) {
        k = n > 60000UL ? 60000U : (unsigned int)n;
        gb_a = p;
        gb_n = k;
        if (gb_fwd_lines() < k)
            n = k;
        p = gb_a;
        n -= k;
    }
    move_to(p, 0);
    goal = 0;
    memset(dirty, 1, ROWS);
}

/* (another bank's: B9's) */
unsigned long jump_line;
void ide_toline(void)
{
    to_line(jump_line);
}

/*---------------------------------------------------------------
  the answers (ideshare.h)
 ---------------------------------------------------------------*/
static char msg[80];

static char *put_n(char *p, unsigned long n)
{
    return tk_put_ul(p, n);
}

void fmt_answer(void)
{
    char *p = msg;
    unsigned char r = ide_res, mk = ide_make;
    ide_make = 0;                       /* (B_MK's turn: this answer only) */
    ide_logn("IDE ANSWER ", r);
    ide_logn(" ", ide_lastreq);
    if (r == IA_LOAD || r >= IA_BREAK)
        ide_log("\n");
    if (r == IA_BREAK) {                /* the debugger's (DECISIONS V97) */
        XCALL(B_DBG, dbg_break);
        return;
    }
    if (r == IA_EVAL) {
        XCALL(B_DBG, dbg_after);
        return;
    }
    if (r >= IA_LOAD && r != 0xFF)
        XCALL(B_DBG, dbg_ended);
    switch (r) {
    case IA_OK:
        if (ide_lastreq == IR_FORMAT) {
            ide_log("\n");
            if (mk) {
                ide_make = mk;
                XCALL(B_MK, mk_answer);
            } else
                XCALL(B_FMT, fmt_format);
            return;
        }
        if (vt_after) {
            p = tk_put_s(p, "No more errors after line ");
            p = put_n(p, vt_after);
        } else
            p = tk_put_s(p, "Checked: no errors");
        break;
    case IA_ERR:                        /* vt_msg "Line 12: NEXT without FOR" */
        err_line = vt_erl;
        to_line(err_line);
        PlaySound(SND_ERROR);
        p = tk_put_s(p, vt_msg);
        p = tk_put_s(p, "  (F8: the next)");
        ide_logn(" ", vt_erl);
        break;
    case IA_LOAD:
        message("The program could not start:", vt_msg);
        p = tk_put_s(p, vt_msg);
        break;
    case IA_END:
        p = tk_put_s(p, "The program has ended");
        break;
    case IA_STOP:
        stop_line = vb_esrc;
        to_line(stop_line);
        p = tk_put_s(p, "Stopped in line ");
        p = put_n(p, vb_esrc);
        ide_logn(" ", vb_esrc);
        break;
    case IA_RTERR:                      /* vt_msg: the error's text (ERR$) */
        err_line = vb_esrc;
        to_line(err_line);
        PlaySound(SND_ERROR);
        p = tk_put_s(p, "Error ");
        p = put_n(p, vb_errno);
        p = tk_put_s(p, ": ");
        p = tk_put_s(p, vt_msg);
        p = tk_put_s(p, " (line ");
        p = put_n(p, vb_esrc);
        *p++ = ')';
        ide_logn(" ", vb_errno);
        ide_logn(" ", vb_esrc);
        *p = 0;
        ide_log("\n");
        XCALL(B_DBG, dbg_error);        /* the message in the pane: the statement too */
        view_status_msg(msg);
        goto names;
    case IA_DEND:
        p = tk_put_s(p, "The program was ended");
        break;
    default:
        ide_log("\n");
        return;
    }
    *p = 0;
    ide_log("\n");
    view_status_msg(msg);
names:
    vt_after = 0;
    if (vt_recb[0] && r != IA_OK) {     /* (a run's names: the debugger's no more) */
        BankFree(vt_recb[0]);
        vt_recb[0] = 0;
    }
}

