/* VeraBASIC, the editor (DECISIONS V93): what the runtime's side (main.c,
   built with VB_IDE: overlay 1) and the editor's (apps/vbasic/ide: its main
   RAM part, LOW, and its banks) share. Both live in one application; the
   editor's main RAM part and the interpreter's code take turns at
   _ide_s0 .. _ide_s1 (vb.s): while the editor shows, the interpreter's code
   is in three RAM banks; while a program runs (or the text is checked),
   the editor's part is. These variables are main RAM's, outside that
   place: the editor's link reads them as equates (tools/vbceq.py).

   MIT licence (LICENSE). */
#ifndef IDESHARE_H
#define IDESHARE_H

/* ide_req: what the editor asks the runtime's side for (LOW's appMain
   jumps to ide_go, overlay 1, with that bank mapped) */
#define IR_NONE   0
#define IR_CHECK  1             /* tokenize and prepare the text (vt_src) */
#define IR_RUN    2             /* check it, then run it */
#define IR_FORMAT 3             /* check it, records 0 and 1 kept (vt_recb) */
#define IR_OUTPUT 4             /* the last program's console again, until a key */
/* (the debugger, DECISIONS V97: a program stopped at a break) */
#define IR_CONT   5             /* it goes on (ide_step: 0 run, 1 step, 2 step over, 3 step out) */
#define IR_EVAL   6             /* the requests answered (dbgshare.h) (dbgshare.h) */
#define IR_DEND   7             /* it is ended */

/* ide_res: the answer, when the editor is back */
#define IA_OK     0             /* no error (IR_FORMAT: the records in vt_recb) */
#define IA_ERR    1             /* an error in the text: vt_erl its line, vt_msg */
#define IA_LOAD   2             /* it could not start: vt_msg */
#define IA_END    3             /* it ran to its end */
#define IA_STOP   4             /* stopped (Ctrl+C, Run > Stop): vb_esrc its line */
#define IA_RTERR  5             /* stopped by an error: vb_errno, vb_esrc, vt_msg (the debugger's DI_QUOTE) */
#define IA_BREAK  6             /* the debugger stopped it (the debugger's DI_INFO, DI_STACK) */
#define IA_EVAL   7             /* the requests answered (DI_RES) */
#define IA_DEND   8             /* the stopped program ended */

/* the application's records: the editor's main RAM part (3), its banks
   B1-B8 (15-22), the debugger's overlay (23: the runtime's; what the two
   sides share is in its bank: dbgshare.h), the debugger's bank B9 (24),
   B10 (Save program, Make application, V99) in record 5: the loader
   gives every record a bank, and the editor's build has vbfloat.s (Run's
   overlay 5) in overlay 8's bank, so its record 5 is B10's and the file
   has no record 25 (one RAM bank fewer, V149) */
#define IDE_REC_LOW  12
#define IDE_REC_BANK 15
#define IDE_REC_DBG  23
#define IDE_REC_MK   5
#define IDE_NBANKS   10

extern unsigned char ide_req, ide_res, ide_opts;
extern unsigned char ide_banks[IDE_NBANKS];     /* the editor's banks (records 15 ...) */
extern unsigned char ide_ovl1;                  /* overlay 1's bank (the runtime's appBank) */
extern unsigned int ide_govec;                  /* ide_go (overlay 1) */
extern unsigned char edit_idle;                 /* the program waits (textkit; the test's player) */
extern unsigned char test_log;                  /* (the test build: the player's 'L') */
void __fastcall__ play_slow(unsigned char cur); /* (the test build: the blink probe) */
extern unsigned char ide_step;                  /* IR_RUN, IR_CONT: 1 step, 2 step over, 3 step out */
extern unsigned char ide_dbgo;                  /* bit 0: TRON from the start (Run > Trace) */

#endif
