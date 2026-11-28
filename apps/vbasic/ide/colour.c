/* VeraBASIC, the editor (DECISIONS V93): B_LEX, a row of the text drawn
   in colour (textkit's TK_ROW_HOOK, after gb_render). One ink, so the
   colours are the cards' paper (ColorRect COLOR_BUF, a row at a time) and
   keywords are bold (tk_putrow's style 2, V215): strings on YELLOW, comments on
   SIDEBAR, numbers plain; the line of an error RED, the line a program
   stopped at SELECT; the gutter's line numbers on CHROME. A lexer pass
   over the row's own line alone (lex.s, in assembly since V215): strings
   and comments end at the line's end, so a row's colours never depend on
   the rows before it. Dark mode
   is the palette's (V74); the Classic theme has no colour map, so only
   the bold words (colour_on 0).

   MIT licence (LICENSE). */
#include <string.h>
#include <theme.h>
#include "ide.h"
#define IDEKW_WORDS
#define IDEKW_DETOK                     /* (Format's, B_FMT reads them here: ide_bget) */
#define IDEKW_EXTERN
#include "idekw.h"

#define K_PLAIN 0
#define K_WORD  1               /* a keyword: bold */
#define K_STR   2
#define K_REM   3
#define K_NUM   4

#define paper ide_paper

/* lex.s (V215: the lexer in assembly, as it was in C here): lexbuf's line
   (n bytes) into lexcls (the columns shown); the text's cards (from X0)
   of the row for tk_putrow, their paper (mark, or ide_ptab's) */
void __fastcall__ ide_lex(unsigned char n);
void __fastcall__ ide_cards(unsigned char mark);
extern unsigned char ide_ptab[5];

/* the row's cards and their styles for textkit's tk_putrow (V215): the
   gutter's and the text's in one call, in the line's bytes' place (read
   and lexed by then) */
#define rowc lexbuf
#define rowf (lexbuf + 128)

/* the gutter: the line's number (its last 4 digits) and a blank; a '*'
   where the number's digits above those are a breakpoint's line (as
   before: none below line 10,000) */
static void gutter(unsigned long line)
{
    unsigned int v;
    unsigned char i;
    memset(rowc, ' ', 5);
    if (line <= nlines) {
        if (line < 10000) {
            v = (unsigned int)line;
            for (i = 4; i--; ) {
                rowc[i] = '0' + (unsigned char)(v % 10);
                v /= 10;
                if (!v)
                    break;
            }
            line = 0;
        } else
            for (i = 4; i--; ) {
                rowc[i] = '0' + (unsigned char)(line % 10);
                line /= 10;
                if (!line)
                    break;
            }
    }
    if (line <= 0xFFFF && bp_has((unsigned int)line))
        rowc[4] = '*';                  /* a breakpoint (DECISIONS V97: its card RED) */
}

/* row r (textkit draws it after this): the gutter, the text's cards'
   styles (bold keywords; the selection, view.c's tk_pa, tk_pb, reversed),
   its colours */
void ide_row(void)
{
    unsigned char r = lex_row;
    unsigned long line = top_line + r + 1;
    unsigned long n;
    unsigned char i, k, mark = 0;
    if (line == err_line)
        mark = RED;
    else if (line == stop_line)
        mark = SELECT;
    if (gb_lcols == 0xFFFF) {           /* past the text's end: drawn blank */
        memset(lexcls, K_PLAIN, COLS);
    } else if (!hs && !gb_tab && gb_lcols <= COLS) {
        k = (unsigned char)gb_lcols;    /* (V215) the whole line rendered, */
        memcpy(lexbuf, gb_line, k);     /* column for byte: lexed from there */
        ide_lex(k);
    } else {
        n = rs[r + 1] - rs[r];          /* (the line and its LF: no more) */
        gb_a = rs[r];
        gb_n = n > 255 ? 255 : n;
        gb_lp = lexbuf;
        k = (unsigned char)gb_read();
        for (i = 0; i < k && lexbuf[i] != 10; ++i)
            ;
        ide_lex(i);
    }
    if (mark) {
        tk_iw[r] = X0 + COLS;           /* (the paper the whole row: vmove.s moves it all) */
        tk_pn = COLS;
    }
    memset(rowf, 0, X0);
    if (colour_on) {
        memset(paper, mark ? mark : CHROME, X0);
        if (X0 && line <= 0xFFFF && bp_has((unsigned int)line))
            paper[4] = RED;
    }
    ide_ptab[K_STR] = YELLOW;
    ide_ptab[K_REM] = SIDEBAR;
    ide_cards(mark);                    /* (tk_pn of them: past them blank) */
    tk_pf = rowf;
    if (X0) {
        gutter(line);
        tk_pc = rowc;
        tk_px = 0;
        tk_pn += X0;
        if (tk_pb) {
            tk_pa += X0;
            tk_pb += X0;
        }
    }
    if (!colour_on || !tk_pn)
        return;
    r0 = (unsigned int)paper;
    ColorRect(0, tk_pn, TROW + r, 1, COLOR_BUF);   /* (the cards drawn: past them 0) */
}
