/* VeraBASIC, the debugger (DECISIONS V97): B_FILE, the trace pane: TRON's
   last 200 lines (overlay 12 keeps them in its ring, dbgshare.h DI_RING:
   each line's number or source line, and its source line), the newest at
   the bottom, each with its text from the editor's. dbg.c opens it (F12,
   Run > The trace) and scrolls it (trace_top: its first entry shown).

   MIT licence (LICENSE). */
#include <string.h>
#include <theme.h>
#include "ide.h"
#include "dbgshare.h"

#define DBUF ((unsigned char *)lexbuf)

/* a row of the pane: tk_line's first PANE_W characters */
static void row(unsigned char y, unsigned char paper, unsigned char flags)
{
    PutCards(tk_line, vb_font, PANE_X, PANE_W, TY + y * 8, flags);
    if (colour_on) {
        memset(ide_paper, paper, PANE_W);
        r0 = (unsigned int)ide_paper;
        ColorRect(PANE_X, PANE_W, TROW + y, 1, COLOR_BUF);
    }
}

static void text(const char *s)
{
    memset(tk_line, ' ', PANE_W);
    memcpy(tk_line, s, strlen(s));
}

/* entry i (0 the oldest) of the n -> DBUF[0..3] */
static void entry(unsigned char i, unsigned char n, unsigned char head)
{
    unsigned int o = head + DI_RN - n + i;
    if (o >= DI_RN)
        o -= DI_RN;
    dget(DI_RING + o * 4, DBUF, 4);
}

void trace_draw(void)
{
    unsigned char n, head, i, k, rows = ROWS - 2;
    unsigned int src, o;
    char *p;
    dispBufferOn = ST_WR_FORE;
    dget(DI_RHEAD, DBUF, 2);
    head = DBUF[0];
    n = DBUF[1];
    text(" The trace (TRON): the last 200");
    row(0, CHROME, 2);
    if (trace_top > n || trace_top + rows > n)  /* (0xFFFF: the newest) */
        trace_top = n > rows ? n - rows : 0;
    for (k = 0; k < rows; ++k) {
        text("");
        i = trace_top + k;
        if (!n && k < 2)
            text(k ? " or Run > Trace (TRON)" : " No line traced: TRON in a program,");
        if (i < n) {
            entry(i, n, head);
            src = DBUF[2] | DBUF[3] << 8;
            p = tk_put_ul(tk_line + 1, DBUF[0] | DBUF[1] << 8);
            *p = ' ';
            if (src && src <= nlines) { /* the line's text */
                gb_a = 0;
                gb_n = src - 1;
                if (src > 1)
                    gb_fwd_lines();
                gb_n = PANE_W - 8;
                gb_lp = DBUF;
                o = gb_read();
                for (i = 0; i < o && DBUF[i] != 10; ++i)
                    tk_line[7 + i] = DBUF[i] == 9 ? ' ' : DBUF[i];
            }
        }
        row(1 + k, SIDEBAR, 0);
    }
    text(" PgUp PgDn; F12, Esc: closed");
    row(ROWS - 1, CHROME, 0);
}

/* (the test build: the trace's entries to the log, for the gate) */
void trace_log(void)
{
#ifdef IDE_TEST
    unsigned char n, head, i;
    dget(DI_RHEAD, DBUF, 2);
    head = DBUF[0];
    n = DBUF[1];
    ide_logn("IDE TRACE N ", n);
    ide_log("\n");
    for (i = 0; i < n; ++i) {
        entry(i, n, head);
        ide_logn("IDE TRACE ", DBUF[0] | DBUF[1] << 8);
        ide_log("\n");
    }
#endif
}
