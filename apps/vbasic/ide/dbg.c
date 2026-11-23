/* VeraBASIC, the debugger: the editor's side (DECISIONS V97), bank B9
   (B_DBG); the names are B_HELP's (names.c: fmt_names, fmt_vars,
   fmt_symname, fmt_procname), the statement an error stopped in B_FMT's
   (fmt.c fmt_quote), the expressions' tokens B_LEX's (tok.c). The runtime's side is vbdbg.s (overlay 12): what the two share
   is in its bank (dbgshare.h), read and written through LOW's dget, dput.

   A break (a breakpoint, a step, STOP, Run > Step at the start) gives the
   editor back with the program kept (IA_BREAK): the text narrows and the
   pane at the right shows the line stopped at, the call stack, the
   watches and the variables (the current procedure's locals first, then
   the globals; an array as its bounds, Return shows its elements). The
   values are the runtime's: the editor writes requests (the variables'
   and watches' tokens in the runtime's form) and asks for their answers
   (IR_EVAL), so a value is always what the program has; a scalar is
   changed by a request too (DR_SET: "name = value"). Tab gives the pane
   the keys (Up, Down, PgUp, PgDn, Return, Delete, Esc); F6 Continue, F7
   Step, F10 Step over, F11 Step out, F9 a breakpoint (the gutter's RED
   card), Ctrl+W a watch, F12 the trace (TRON's last 200 lines). An error
   that stopped the program is shown in the pane: its number and words,
   the kernel's code, the line, the procedure, the statement in canonical
   form.

   MIT licence (LICENSE). */
#include <string.h>
#include <theme.h>
#include "ide.h"
#include "dbgshare.h"

/* (code, tables and variables in B9: the Makefile's B9CODE, B9RO, B9BSS) */

#define PX      PANE_X
#define PW      PANE_W
#define NW      4                       /* watches */

static unsigned char vtop, sel;         /* the first variable shown; the row chosen (0-3 watches, 4 .. variables) */
static unsigned char vrows;             /* rows for variables (answers) */
static unsigned char vreq0;             /* the first variable's answer */
static unsigned char cproc_, reason, nstk, deep;
static unsigned int bsrc;
static char watch[NW][40];
static unsigned char wbad[NW];          /* the watch's error (TE_*), 0 none */
static unsigned char arr;               /* the array shown: its entry + 1 (0 none) */
static unsigned int afirst;             /* its first element shown (linear) */
static unsigned int adim[3];            /* its upper bounds */
static unsigned char andim;
#define ttop_ trace_top                 /* (the trace's first entry shown: trace.c's) */
static unsigned char help_errno, set_pending;
static char ebuf[200];                  /* an error's message (pane 3) */
static unsigned char prow;              /* the row being drawn */
static char *lp;
static char nb[12];
#define DBUF ((unsigned char *)lexbuf)  /* (main RAM's scratch) */
#define ABUF ((char *)iobuf + 448)      /* (a dialog box's text: below $A000) */
#define VE   (IDE_REC + 184)           /* (main RAM: a DI_VARS entry, 6; over Format's record) */
#define TBUF ((char *)IDE_REC + 192)    /* (an answer, a message: 64) */
#define ve VE
#define DPAPER ide_paper

static const char *const terrs[] = { "", "A string has no closing quote", "Only an expression",
    "No such variable", "A character it has not" };

/* variable e's entry (ve) and T_VAR operand */
static unsigned int var(unsigned char e)
{
    dget(DI_VARS + e * 6, ve, 6);
    return ve[3] & 1 ? ve[2] * 8 : cellbase + (ve[0] | ve[1] << 8) * 8;
}

static void name_of(unsigned char e)
{
    var(e);
    x_off = ve[4] | ve[5] << 8;
    XCALL(B_HELP, fmt_symname);
}

/*---------------------------------------------------------------
  the requests: built in RQBUF (main RAM), then DI_REQ
 ---------------------------------------------------------------*/
static void rq(unsigned char b)
{
    if (rqn < 500)
        RQBUF[rqn++] = b;
}

static void rq_w(unsigned char tag, unsigned int v)
{
    rq(tag);
    rq((unsigned char)v);
    rq(v >> 8);
}

static void rq_start(unsigned char kind)
{
    rq(kind);
    ++nreq;
}

/* the expression in XSRC onto the request: 0 and x_kind if it cannot be */
static unsigned char rq_expr(void)
{
    XCALL(B_LEX, tk_expr);
    return x_ok;
}

static void rq_flush(void)
{
    unsigned int o;
    unsigned char k;
    rq(0);
    for (o = 0; o < rqn; o += k) {
        k = rqn - o > 200 ? 200 : (unsigned char)(rqn - o);
        dput(DI_REQ + o, RQBUF + o, k);
    }
    dput(DI_REQN, &nreq, 1);
    ide_req = IR_EVAL;                  /* (LOW's appMain: to the runtime's side) */
}

/* the pane's requests: the watches, the variables shown (or the array's
   elements) */
static void ask_values(void)
{
    unsigned char i, k, e;
    unsigned int lin, idx[3], rem, op;
    rqn = 0;
    nreq = 0;
    for (i = 0; i < NW; ++i) {
        rq_start(DR_VALUE);
        lin = rqn;
        wbad[i] = 0;
        strcpy(XSRC, watch[i]);
        if (!watch[i][0] || !rq_expr()) {
            if (watch[i][0])
                wbad[i] = x_kind;
            rqn = lin;                  /* (a request of 0: the answers keep their numbers) */
            rq_w(1, 0);
        }
        rq(0);
    }
    vreq0 = nreq;
    if (arr) {
        op = var(arr - 1);
        for (k = 0; k < vrows; ++k) {
            lin = afirst + k;
            rem = lin;                  /* the subscripts, the last the fastest */
            for (i = andim; i--; ) {
                idx[i] = rem % (adim[i] + 1);
                rem /= adim[i] + 1;
            }
            if (rem)
                break;
            rq_start(DR_VALUE);
            rq_w(6, op);
            rq('(');
            for (i = 0; i < andim; ++i) {
                if (i)
                    rq(',');
                rq_w(1, idx[i]);
            }
            rq(')');
            rq(0);
        }
    } else
        for (k = 0; k < vrows && vtop + k < nv; ++k) {
            e = vtop + k;
            op = var(e);
            rq_start(ve[3] & 2 ? DR_DIMS : DR_VALUE);
            rq_w(6, op);
            rq(0);
        }
    rq_flush();
}

/*---------------------------------------------------------------
  the pane
 ---------------------------------------------------------------*/
static void row_start(void)
{
    memset(tk_line, ' ', PW);
    lp = tk_line;
}

static void put(const char *s)
{
    while (*s && lp < tk_line + PW)
        *lp++ = *s++;
}

static void put_n(unsigned int n)
{
    *tk_put_ul(nb, n) = 0;
    put(nb);
}

static void at(unsigned char c)
{
    lp = tk_line + c;
}

/* the row out: PutCards' flags (2 bold, 1 reversed), its paper */
static void row_out(unsigned char flags, unsigned char paper)
{
    if (prow >= ROWS)
        return;
    if (!colour_on && paper == SELECT)
        flags |= 1;
    PutCards(tk_line, vb_font, PX, PW, TY + prow * 8, flags);
    if (colour_on) {
        memset(DPAPER, paper, PW);
        r0 = (unsigned int)DPAPER;
        ColorRect(PX, PW, TROW + prow, 1, COLOR_BUF);
    }
    ++prow;
}

static void heading(const char *s)
{
    row_start();
    put(s);
    row_out(2, CHROME);
}

/* answer r onto the row */
static void put_res(unsigned char r)
{
    if (r >= nreq || r >= DI_RESN)
        return;
    dget(DI_RES + r * DI_RESW, TBUF, DI_RESW);
    TBUF[DI_RESW - 1] = 0;
    put(TBUF);
}

static void put_proc(unsigned char p)
{
    x_proc = p;
    XCALL(B_HELP, fmt_procname);
    put(XNAME);
}

static const char *const why[] = { "", "breakpoint", "step", "STOP", "paused", "the start" };
static const char *const tname[] = { "num", "int", "str" };

/* rows before the watches: the head (2), the stack's heading and rows */
static unsigned char stk_rows(void)
{
    return 3 + (nstk > 6 ? 6 : nstk) + (deep || nstk > 6);
}

static void draw_break(void)
{
    unsigned char i, k, e, t, b[6];
    row_start();
    put(" Stopped in line ");
    put_n(bsrc);
    row_out(2, SELECT);
    row_start();
    put(" (");
    put(why[reason < 6 ? reason : 0]);
    put(")  ");
    put_proc(cproc_);
    row_out(0, SIDEBAR);
    heading(" Call stack");
    for (i = 0; i < nstk && i < 6; ++i) {
        dget(DI_STACK + i * 6, b, 6);
        row_start();
        put(b[0] == 2 ? " GOSUB, " : " ");
        put_proc(b[1]);
        at(21);
        if (b[2] | b[3]) {
            put(" line ");
            put_n(b[2] | b[3] << 8);
        } else
            put(" (events)");
        row_out(0, SIDEBAR);
    }
    if (deep || nstk > 6) {
        row_start();
        put(" ...");
        row_out(0, SIDEBAR);
    }
    heading(" Watches (Ctrl+W)");
    for (i = 0; i < NW; ++i) {
        row_start();
        put(" ");
        if (watch[i][0]) {
            put(watch[i]);
            put(" = ");
            if (wbad[i]) {
                put("?");
                put(terrs[wbad[i]]);
            } else
                put_res(i);
        } else
            put("-");
        row_out(0, dfocus && sel == i ? SELECT : SIDEBAR);
    }
    row_start();
    if (arr) {
        name_of(arr - 1);
        put(" ");
        put(XNAME);
        put("(");
        for (i = 0; i < andim; ++i) {
            if (i)
                put(", ");
            put_n(adim[i]);
        }
        put(")  Esc: back");
    } else
        put(nloc ? " Variables (locals first)" : " Variables");
    row_out(2, CHROME);
    for (k = 0; k < vrows && prow < ROWS - 1; ++k) {
        row_start();
        put(" ");
        if (arr) {
            if (vreq0 + k < nreq) {
                put_n(afirst + k);
                put(": ");
                put_res(vreq0 + k);
            }
            row_out(0, SIDEBAR);
            continue;
        }
        e = vtop + k;
        if (e < nv) {
            name_of(e);
            XNAME[11] = 0;
            put(XNAME);
            at(13);
            t = ve[3] >> 4;
            put(tname[t < 3 ? t : 0]);
            put(ve[3] & 2 ? "()" : "");
            at(19);
            put_res(vreq0 + k);
        }
        row_out(0, dfocus && sel == NW + e ? SELECT : e < nloc ? 0 : SIDEBAR);
    }
    while (prow < ROWS - 1) {
        row_start();
        row_out(0, SIDEBAR);
    }
    row_start();
    put(" F6 go F7 step F10 over F11 out");
    row_out(0, CHROME);
}

static void draw_error(void)
{
    unsigned char i = 0, n, k;
    heading(" The program stopped");
    while (ebuf[i] && prow < ROWS - 2) {
        row_start();
        put(" ");
        n = strlen(ebuf + i);
        if (n > PW - 2) {               /* broken at a blank */
            for (k = PW - 2; k > 8 && ebuf[i + k] != ' '; --k)
                ;
            n = k > 8 ? k : PW - 2;
        }
        memcpy(lp, ebuf + i, n);
        row_out(0, SIDEBAR);
        i += n;
        while (ebuf[i] == ' ')
            ++i;
    }
    while (prow < ROWS - 1) {
        row_start();
        row_out(0, SIDEBAR);
    }
    row_start();
    put(" F1 its page; Esc: closed");
    row_out(0, CHROME);
}

void dbg_draw(void)
{
    prow = 0;
    dispBufferOn = ST_WR_FORE;
    if (pane == 1)
        draw_break();
    else if (pane == 2)
        XCALL(B_FILE, trace_draw);
    else if (pane == 3)
        draw_error();
}

/* the start (B_CMD's the_start): this bank's variables cleared (as crt0
   clears a BSS: a bank's is not), the breakpoints and the trace none */
extern unsigned char _B9BSS_RUN__[], _B9BSS_SIZE__[];
void dbg_init(void)
{
    memset(_B9BSS_RUN__, 0, (unsigned int)_B9BSS_SIZE__);
    dbg_prep();
}

/* the pane on or off: the text's width, the window drawn (its frame
   hook draws the pane: keys.c) */
static void relayout(void)             /* (as B_CMD's ide_relayout) */
{
    tk_x0 = gutter_on ? 5 : 0;
    tk_cols = (pane ? PANE_X : SB_X) - tk_x0;
    hs = 0;
}

static void layout(unsigned char p)
{
    pane = p;
    dfocus = 0;
    relayout();
    XCALL(B_VIEW, view_all);
}

static void request(unsigned char r)
{
    req_arg = r;
    XCALL(B_CMD, ide_request_x);
}

/* the pane closed: the break's again, or none */
static void close_pane(void)
{
    layout(dbg_paused);
    if (dbg_paused)
        ask_values();
}

/*---------------------------------------------------------------
  the answers
 ---------------------------------------------------------------*/
/* IA_BREAK: the break shown, its values asked for */
void dbg_break(void)
{
    unsigned char b[8];
    dget(DI_INFO, b, 8);
    reason = b[DB_REASON];
    bsrc = b[DB_SRC] | b[DB_SRC + 1] << 8;
    cproc_ = b[DB_PROC];
    nstk = b[DB_NSTK];
    deep = b[DB_DEEP];
    dbg_paused = 1;
    arr = 0;
    vtop = 0;
    sel = NW;
    XCALL(B_HELP, fmt_names);
    x_proc = cproc_;
    XCALL(B_HELP, fmt_vars);
    stop_line = bsrc;
    req_arg = 0;
    jump_line = bsrc;
    XCALL(B_CMD, ide_toline);
    layout(1);
    vrows = ROWS - 2 - stk_rows() - NW - 1;
    if (vrows > DI_RESN - NW)
        vrows = DI_RESN - NW;
    strcpy(TBUF, "Stopped in line ");
    *tk_put_ul(TBUF + 16, bsrc) = 0;
    view_status_msg(TBUF);
    ide_logn("IDE BREAK ", bsrc);
    ide_logn(" ", reason);
    ide_logn(" ", nstk);
    ide_logn(" ", nv);
    ide_log("\n");
#ifdef IDE_TEST
    XCALL(B_CMD, ide_banks_log);
#endif
    ask_values();
}

/* IA_EVAL: the answers drawn (the test build: each one to the log) */
static void answered(void)
{
#ifdef IDE_TEST
    unsigned char i, b[6];
    for (i = 0; i < nreq; ++i) {
        ide_logn("IDE VALUE ", i);
        ide_log(" ");
        if (i < NW)
            ide_log(watch[i]);
        else if (arr) {
            name_of(arr - 1);
            ide_log(XNAME);
            ide_logn(" ", afirst + i - vreq0);
        } else {
            name_of(vtop + i - vreq0);
            ide_log(XNAME);
        }
        dget(DI_RES + i * DI_RESW, TBUF, DI_RESW);
        TBUF[DI_RESW - 1] = 0;
        ide_log(" = ");
        ide_log(i < NW && wbad[i] ? terrs[wbad[i]] : TBUF);
        ide_log("\n");
    }
    for (i = 0; i < nstk && i < DI_STKN; ++i) {
        dget(DI_STACK + i * 6, b, 6);
        ide_logn("IDE STACK ", i);
        ide_logn(" ", b[0]);
        x_proc = b[1];
        XCALL(B_HELP, fmt_procname);
        ide_log(" ");
        ide_log(XNAME);
        ide_logn(" ", b[2] | b[3] << 8);
        ide_log("\n");
    }
#endif
    if (pane == 1)
        dbg_draw();
}

/* IA_EVAL: after an assignment, its answer, then the values again */
void dbg_after(void)
{
    if (set_pending) {
        set_pending = 0;
        dget(DI_RES, TBUF, DI_RESW);
        TBUF[DI_RESW - 1] = 0;
        view_status_msg(TBUF[0] == '?' ? TBUF + 1 : "Changed");
        ide_log("IDE SET ");
        ide_log(TBUF);
        ide_log("\n");
        ask_values();
        return;
    }
    answered();
}

/* the program ended (IA_END, IA_STOP, IA_RTERR, IA_LOAD, IA_DEND): the
   break's pane goes */
void dbg_ended(void)
{
    dbg_paused = 0;
    if (pane == 1)
        layout(0);
}

/* IA_RTERR: "Error 13, Type mismatch, in line 57 (SUB Tick): total% =
   name$"; a file's error with the kernel's code: "(kernel 5)" */
void dbg_error(void)
{
    unsigned char q[DQ_TOK], n;
    char *p = ebuf;
    dget(DI_QUOTE, q, DQ_TOK);
    XCALL(B_HELP, fmt_names);
    p = tk_put_s(p, "Error ");
    p = tk_put_ul(p, q[DQ_ERRNO]);
    p = tk_put_s(p, ", ");
    p = tk_put_s(p, vt_msg);
    if (q[DQ_KERR]) {
        p = tk_put_s(p, " (kernel ");
        p = tk_put_ul(p, q[DQ_KERR]);
        *p++ = ')';
    }
    p = tk_put_s(p, ", in line ");
    p = tk_put_ul(p, vb_esrc);
    if (x_ok && q[DQ_PROC] != 0xFF) {
        p = tk_put_s(p, " (");
        x_proc = q[DQ_PROC];
        XCALL(B_HELP, fmt_procname);
        p = tk_put_s(p, XNAME);
        *p++ = ')';
    }
    *p = 0;
    if (x_ok) {                         /* the statement: B_FMT detokenizes it */
        XCALL(B_FMT, fmt_quote);
        n = strlen(IDE_OUT);
        if (n && n < ebuf + sizeof ebuf - 3 - p) {
            p = tk_put_s(p, ": ");
            strcpy(p, IDE_OUT);
        }
    }
    ide_log("IDE ERROR ");
    ide_log(ebuf);
    ide_log("\n");
    help_errno = q[DQ_ERRNO];
    layout(3);
}

/*---------------------------------------------------------------
  the commands (the Run menu, the keys)
 ---------------------------------------------------------------*/
/* the breakpoints to DI before a program runs or goes on (a new run: the
   trace emptied) */
void dbg_prep(void)
{
    unsigned char z[2];
    dput(DI_BPN, &bp_n, 1);
    if (bp_n)
        dput(DI_BP, bp_line, bp_n * 2);
    if (!dbg_paused) {
        z[0] = z[1] = 0;
        dput(DI_RHEAD, z, 2);
    }
}

static void go(unsigned char step)
{
    menus_off();
    if (help_open)
        return;
    if (!dbg_paused) {
        if (step == 1) {                /* Step with no program: it runs, stopped at its first line */
            ide_step = 1;
            request(IR_RUN);
            return;
        }
        view_status_msg(step ? "No program is stopped (F7: one, a step at a time)"
                             : "No program is stopped: Run (Ctrl+R) runs it");
        return;
    }
    dbg_prep();
    dbg_paused = 0;
    dfocus = 0;
    ide_step = step;
    request(IR_CONT);
}

void dbg_cont(void) { go(0); }
void dbg_step(void) { go(1); }
void dbg_over(void) { go(2); }
void dbg_out(void) { go(3); }

/* F9: a breakpoint on the cursor's line, or none (the gutter shows it) */
void dbg_bp(void)
{
    unsigned int l = (unsigned int)cur_line + 1;
    unsigned char i;
    menus_off();
    for (i = 0; i < bp_n && bp_line[i] != l; ++i)
        ;
    if (i < bp_n) {
        bp_line[i] = bp_line[--bp_n];
        view_status_msg("Breakpoint off");
    } else if (bp_n >= 32) {
        view_status_msg("32 breakpoints at most");
        return;
    } else {
        bp_line[bp_n++] = l;
        view_status_msg("Breakpoint on (F9 again: off)");
    }
    ide_logn("IDE BP ", l);
    ide_logn(" ", bp_n);
    ide_log("\n");
    if (!gutter_on) {
        gutter_on = 1;
        relayout();
        XCALL(B_VIEW, view_all);
    } else
        memset(dirty, 1, ROWS);
}

/* a watch's expression asked for (the one chosen, or the first free) */
void dbg_watch(void)
{
    unsigned char i;
    menus_off();
    if (dfocus && sel < NW)
        i = sel;
    else {
        for (i = 0; i < NW && watch[i][0]; ++i)
            ;
        if (i == NW) {
            view_status_msg("4 watches at most (Tab, Delete: one off)");
            return;
        }
    }
    strcpy(ABUF, watch[i]);
    if (!ask("Watch the expression:", ABUF, 38))
        return;
    strcpy(watch[i], ABUF);
    ide_log("IDE WATCH ");
    ide_log(ABUF);
    ide_log("\n");
    if (dbg_paused)
        ask_values();
    else
        view_status_msg("Watched at each break");
}

void dbg_tron(void)
{
    menus_off();
    ide_dbgo ^= 1;
    view_status_msg(ide_dbgo & 1 ? "Trace on: each line a program runs, to the trace (F12)"
                                 : "Trace off (TRON in a program still traces)");
}

void dbg_trace(void)
{
    menus_off();
    if (pane == 2) {
        close_pane();
        return;
    }
    ttop_ = 0xFFFF;
    layout(2);
    XCALL(B_FILE, trace_log);
}

/* a new value for variable e (a scalar) */
static void set_var(unsigned char e)
{
    char p[44];
    unsigned int op;
    name_of(e);
    strcpy(p, XNAME);
    strcat(p, " =");
    ABUF[0] = 0;
    if (!ask(p, ABUF, 38))
        return;
    op = var(e);
    rqn = 0;
    nreq = 0;
    rq_start(DR_SET);
    rq_w(6, op);
    rq('=');
    strcpy(XSRC, ABUF);
    if (!rq_expr()) {
        view_status_msg(terrs[x_kind]);
        return;
    }
    ide_log("IDE SET ");
    ide_log(ABUF);
    ide_log("\n");
    rq(0);
    set_pending = 1;
    rq_flush();
}

/* an array's elements: its bounds from its answer ("10, 5") */
static void open_array(unsigned char e)
{
    char *p = TBUF;
    dget(DI_RES + (vreq0 + e - vtop) * DI_RESW, TBUF, DI_RESW);
    if (*p < '0' || *p > '9') {
        view_status_msg("The array has no DIM yet");
        return;
    }
    andim = 0;
    while (*p && andim < 3) {
        adim[andim] = 0;
        while (*p >= '0' && *p <= '9')
            adim[andim] = adim[andim] * 10 + *p++ - '0';
        ++andim;
        while (*p == ',' || *p == ' ')
            ++p;
    }
    arr = e + 1;
    afirst = 0;
    ask_values();
}

/* the pane's keys (pane 2 and 3 always; pane 1 when Tab gave it them):
   key_taken 1 if they were its */
void dbg_key(void)
{
    unsigned char k = keyData, n;
    key_taken = 1;
    if (pane >= 2) {
        if (k == KEY_ESC)
            close_pane();
        else if (k == KEY_F1 && pane == 3) {
            strcpy(help_req, "Error ");
            *tk_put_ul(help_req + 6, help_errno) = 0;
            help_file = HF_ERRORS;
            XCALL(B_VIEW, view_off);
            XCALL(B_HELP, help_show);
        } else if (pane == 2 && (k == KEY_PGUP || k == KEY_UP)) {
            n = k == KEY_UP ? 1 : ROWS - 3;
            ttop_ = ttop_ > n ? ttop_ - n : 0;
            XCALL(B_FILE, trace_draw);
        } else if (pane == 2 && (k == KEY_PGDN || k == KEY_DOWN)) {
            ttop_ += k == KEY_DOWN ? 1 : ROWS - 3;
            XCALL(B_FILE, trace_draw);
        } else
            key_taken = 0;
        return;
    }
    n = arr ? NW : NW + nv;
    switch (k) {
    case KEY_ESC:
        if (arr) {
            arr = 0;
            ask_values();
            return;
        }
    case KEY_TAB:
        dfocus = 0;
        break;
    case KEY_UP:
        if (arr) {
            if (afirst)
                --afirst;
            ask_values();
            return;
        }
        if (sel)
            --sel;
        if (sel >= NW && sel - NW < vtop) {
            vtop = sel - NW;
            ask_values();
            return;
        }
        break;
    case KEY_DOWN:
        if (arr) {
            ++afirst;
            ask_values();
            return;
        }
        if (sel + 1 < n)
            ++sel;
        if (sel >= NW && sel - NW >= vtop + vrows) {
            vtop = sel - NW - vrows + 1;
            ask_values();
            return;
        }
        break;
    case KEY_PGDN:
        if (arr)
            afirst += vrows;
        else if (vtop + vrows < nv) {
            vtop += vrows;
            sel = NW + vtop;
        }
        ask_values();
        return;
    case KEY_PGUP:
        if (arr)
            afirst = afirst > vrows ? afirst - vrows : 0;
        else {
            vtop = vtop > vrows ? vtop - vrows : 0;
            sel = NW + vtop;
        }
        ask_values();
        return;
    case KEY_DELETE:
    case 8:
        if (sel < NW) {
            watch[sel][0] = 0;
            ask_values();
        }
        return;
    case CR:
        if (arr)
            return;
        if (sel < NW) {
            dbg_watch();
            return;
        }
        var(sel - NW);
        if (ve[3] & 2)
            open_array(sel - NW);
        else
            set_var(sel - NW);
        return;
    default:
        key_taken = 0;
        return;
    }
    dbg_draw();
}

/* Tab while stopped: the keys to the pane */
void dbg_focus(void)
{
    if (pane != 1)
        return;
    dfocus = 1;
    if (sel >= NW + nv)
        sel = NW;
    dbg_draw();
}

/* a click in the pane: its row chosen (on the row chosen: as Return) */
void dbg_press(void)
{
    unsigned char r = (unsigned char)((press_y - TY) >> 3), i, base;
    if (pane != 1 || arr)
        return;
    base = stk_rows() + 1;              /* the watches' first row */
    if (r >= base && r < base + NW)
        i = r - base;
    else if (r > base + NW && r <= base + NW + vrows && vtop + r - (base + NW + 1) < nv)
        i = NW + vtop + r - (base + NW + 1);
    else
        return;
    if (dfocus && sel == i) {
        keyData = CR;
        dbg_key();
        return;
    }
    dfocus = 1;
    sel = i;
    dbg_draw();
}
