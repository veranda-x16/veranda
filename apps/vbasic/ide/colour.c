/* VeraBASIC, the editor (DECISIONS V93): B_VIEW, a row of the text drawn
   in colour (textkit's TK_ROW_HOOK, after gb_render). One ink, so the
   colours are the cards' paper (ColorRect COLOR_BUF, a row at a time) and
   keywords are bold (PutCards flag 2): strings on YELLOW, comments on
   SIDEBAR, numbers plain; the line of an error RED, the line a program
   stopped at SELECT; the gutter's line numbers on CHROME. A lexer pass
   over the row's own line alone: strings and comments end at the line's
   end, so a row's colours never depend on the rows before it. Dark mode
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
static char wbuf[14];

/* the word in wbuf a keyword? (a binary search of the generated table) */
static unsigned char keyword(void)
{
    int lo = 0, hi = KW_NWORDS - 1, mid, c;
    while (lo <= hi) {
        mid = (lo + hi) >> 1;
        c = strcmp(wbuf, kw_wtxt + kw_woff[mid]);
        if (!c)
            return 1;
        if (c < 0)
            hi = mid - 1;
        else
            lo = mid + 1;
    }
    return 0;
}

static unsigned int col;                /* the column the lexer is at */

/* columns col .. of the next character (a tab: to the next eighth) get k */
static void put(unsigned char c, unsigned char k)
{
    unsigned int to = c == 9 ? (col | 7) + 1 : col + 1;
    unsigned int v;
    for (; col < to; ++col) {
        v = col - hs;
        if (col >= hs && v < COLS)
            lexcls[v] = k;
    }
}

static unsigned char is_letter(unsigned char c)
{
    return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z');
}

/* lexbuf's line (n bytes) into lexcls (the columns shown) */
static void lex(unsigned char n)
{
    unsigned char i = 0, j, c, k, w, rest = 0;
    memset(lexcls, K_PLAIN, COLS);
    col = 0;
    while (i < n) {
        c = lexbuf[i];
        if (rest) {                     /* a comment's rest */
            put(c, K_REM);
            ++i;
            continue;
        }
        if (c == '"') {
            put(c, K_STR);
            for (++i; i < n; ++i) {
                c = lexbuf[i];
                put(c, K_STR);
                if (c == '"') {
                    if (i + 1 < n && lexbuf[i + 1] == '"') {
                        put('"', K_STR);
                        ++i;
                        continue;
                    }
                    ++i;
                    break;
                }
            }
            continue;
        }
        if (c == '\'') {
            rest = 1;
            continue;
        }
        if (is_letter(c)) {
            for (j = i, w = 0; j < n; ++j) {
                c = lexbuf[j];
                if (!(is_letter(c) || (c >= '0' && c <= '9') || c == '_'))
                    break;
                if (w < 12)
                    wbuf[w++] = is_letter(c) ? c & 0xDF : c;
            }
            if (j < n && (lexbuf[j] == '$' || lexbuf[j] == '%')) {
                if (w < 12)
                    wbuf[w++] = lexbuf[j];
                ++j;
            }
            wbuf[w] = 0;
            k = w <= 11 && keyword() ? K_WORD : K_PLAIN;
            for (; i < j; ++i)
                put(lexbuf[i], k);
            if (k == K_WORD && !strcmp(wbuf, "REM"))
                rest = 1;
            continue;
        }
        if ((c >= '0' && c <= '9') || c == '.' || ((c == '$' || c == '%') && i + 1 < n
            && ((lexbuf[i + 1] >= '0' && lexbuf[i + 1] <= '9') || (lexbuf[i + 1] & 0xDF) >= 'A'))) {
            put(c, K_NUM);
            for (++i; i < n; ++i) {
                c = lexbuf[i];
                if (!((c >= '0' && c <= '9') || c == '.' || ((c & 0xDF) >= 'A' && (c & 0xDF) <= 'F')))
                    break;
                put(c, K_NUM);
            }
            continue;
        }
        put(c, K_PLAIN);
        ++i;
    }
}

/* the gutter: the line's number (4 digits) and a blank */
static void gutter(unsigned char r, unsigned int y, unsigned long line)
{
    char g[6];
    unsigned char i;
    memset(g, ' ', 5);
    g[5] = 0;
    if (line <= nlines)
        for (i = 4; i--; ) {
            g[i] = '0' + (unsigned char)(line % 10);
            line /= 10;
            if (!line)
                break;
        }
    if (line <= 0xFFFF && bp_has((unsigned int)line))
        g[4] = '*';                     /* a breakpoint (DECISIONS V97: its card RED) */
    PutCards(g, vb_font, 0, 5, y, 0);
    (void)r;
}

void ide_row(void)
{
    unsigned char r = lex_row;
    unsigned int y = TY + (r << 3);
    unsigned long line = top_line + r + 1;
    unsigned char i, j, f, k, n, mark = 0;
    if (tk_x0)
        gutter(r, y, line);
    if (line == err_line)
        mark = RED;
    else if (line == stop_line)
        mark = SELECT;
    if (gb_lcols == 0xFFFF) {           /* past the text's end: drawn blank */
        memset(lexcls, K_PLAIN, COLS);
    } else {
        gb_a = rs[r];
        gb_n = 255;
        gb_lp = lexbuf;
        n = (unsigned char)gb_read();
        for (i = 0; i < n && lexbuf[i] != 10; ++i)
            ;
        lex(i);
        /* the cards in runs of one style: bold keywords, the selection reversed */
        for (i = 0; i < COLS; i = j) {
            f = (lexcls[i] == K_WORD ? 2 : 0) | (i >= tk_sela && i < tk_selb);
            for (j = i + 1; j < COLS; ++j)
                if (((lexcls[j] == K_WORD ? 2 : 0) | (j >= tk_sela && j < tk_selb)) != f)
                    break;
            PutCards(gb_line + i, vb_font, X0 + i, j - i, y, f);
        }
    }
    if (!colour_on)
        return;
    for (i = 0; i < X0; ++i)
        paper[i] = mark ? mark : CHROME;
    if (X0 && line <= 0xFFFF && bp_has((unsigned int)line))
        paper[4] = RED;
    for (i = 0; i < COLS; ++i) {
        k = lexcls[i];
        paper[X0 + i] = mark ? mark : k == K_STR ? YELLOW : k == K_REM ? SIDEBAR : 0;
    }
    r0 = (unsigned int)paper;
    ColorRect(0, X0 + COLS, TROW + r, 1, COLOR_BUF);
}
