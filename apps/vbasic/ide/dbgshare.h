/* VeraBASIC, the debugger (DECISIONS V97): what the runtime's side
   (vbdbg.s, overlay 12: record 23) and the editor's (ide/dbg.c, bank B9;
   fmt.c in B5, tok.c in B8) share: overlay 12's own bank (vx_dbg), from
   $B000 (its code ends below), at fixed addresses, the same in vbdbg.inc
   (keep the two in step).

   MIT licence (LICENSE). */
#ifndef DBGSHARE_H
#define DBGSHARE_H

#define DI_RING   0xB000        /* the trace: 200 entries of 4 bytes (number or source line, source line) */
#define DI_RN     200
#define DI_RHEAD  0xB320        /* the next entry (0-199) */
#define DI_RCNT   0xB321        /* entries (to 200) */
#define DI_BPN    0xB322        /* breakpoints */
#define DI_BP     0xB324        /* 32 of 2 bytes: their source lines */
#define DI_BPMAX  32
#define DI_INFO   0xB364        /* the break (below) */
#define DI_STACK  0xB384        /* the call stack: 12 entries of 6 bytes */
#define DI_STKN   12
#define DI_REQN   0xB3D0        /* the requests: how many */
#define DI_REQ    0xB3D1        /* each: kind (DR_*), its tokens (the runtime's form), 0 */
#define DI_REQEND 0xB700
#define DI_RES    0xB700        /* each request's answer: 32 bytes, 0-ended */
#define DI_RESN   40
#define DI_RESW   24
#define DI_QUOTE  0xBAC0        /* an error that stopped the program (below) */
#define DI_SCR    0xBBC0        /* the runtime's scratch (64) */
#define DI_VARS   0xBC00        /* the editor's: the variables listed, 6 bytes each (symbol, slot, flags, the symbol's offset) */
#define DI_VMAX   128
#define DI_LOCAL  0xBF00        /* the editor's: a bit a symbol, a procedure's frame entry (64) */
#define DI_BASE   0xB000

/* DI_INFO: the break */
#define DB_REASON 0             /* DW_* */
#define DB_SRC    1             /* the source line (2) */
#define DB_LABEL  3             /* its number, or the source line (2) */
#define DB_PROC   5             /* the procedure ($FF the main lines) */
#define DB_NSTK   6             /* call stack entries */
#define DB_DEEP   7             /* 1: more frames than DI_STKN */
#define DW_BP     1
#define DW_STEP   2
#define DW_STOP   3
#define DW_PAUSE  4
#define DW_START  5

/* DI_STACK entries */
#define DS_KIND   0             /* 1 a procedure's call, 2 GOSUB, 0 the break's own line */
#define DS_PROC   1             /* the procedure running there ($FF the main lines) */
#define DS_SRC    2             /* the line it is at (2) */
#define DS_LABEL  4             /* (2) */

/* the requests */
#define DR_VALUE  0             /* an expression: its value */
#define DR_DIMS   1             /* an array (T_VAR alone): its upper bounds, "10, 5" */
#define DR_SET    2             /* an assignment (T_VAR ... = expression) */

/* DI_QUOTE */
#define DQ_ERRNO  0
#define DQ_KERR   1             /* the kernel's error (ERRFILE), 0 none */
#define DQ_PROC   2             /* the procedure ($FF) */
#define DQ_SRC    3             /* (2) */
#define DQ_LABEL  5             /* (2) */
#define DQ_OFF    7             /* the statement's offset in record 1 (2) */
#define DQ_PBASE  9             /* the program's first bank */
#define DQ_CELL   10            /* cellbase (2) */
#define DQ_N      12            /* the tokens' bytes (to the line's end) */
#define DQ_TOK    13
#endif
