/* VeraBASIC, the editor (DECISIONS V93): B_SYN, the keyword at the cursor
   (a compound too: END IF, EXIT FOR ...), its syntax line for the status
   bar (from vbasic/keywords.tbl: tools/vbgen.py's idekw.h) and F1's page.

   MIT licence (LICENSE). */
#include <string.h>
#include "ide.h"
#define IDEKW_SYNTAX
#include "idekw.h"

/*---------------------------------------------------------------
  the word at the cursor: its keyword (compounds too), its syntax line
 ---------------------------------------------------------------*/
static char w1[14], w2[14], w0[14];

static unsigned char wordc(unsigned char c)
{
    return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_'
        || c == '$' || c == '%';
}

/* the word of lexbuf at i into w (upper case), 13 at most */
static unsigned char word_at(unsigned char i, unsigned char n, char *w)
{
    unsigned char k = 0, c;
    while (i && wordc(lexbuf[i - 1]))
        --i;
    while (i < n && wordc(c = lexbuf[i]) && k < 13) {
        w[k++] = c >= 'a' && c <= 'z' ? c - 32 : c;
        ++i;
    }
    w[k] = 0;
    return i;
}

/* kw_syn's entry named s (its name, 0, its syntax), or 0 (the table is
   sorted: the search stops past the place) */
static const char *syn_find(const char *s)
{
    const char *p = kw_syn;
    unsigned int i;
    int c;
    for (i = 0; i < KW_NSYN; ++i) {
        c = strcmp(s, p);
        if (!c)
            return p;
        if (c < 0)
            break;
        p += strlen(p) + 1;
        p += strlen(p) + 1;
    }
    return 0;
}

/* the keyword at the cursor: its entry (0: none) */
static const char *at_cursor(void)
{
    unsigned char n, i, j, p;
    unsigned long d = cur - cur_ls;
    const char *e;
    char both[28];
    gb_a = cur_ls;
    gb_n = 255;
    gb_lp = lexbuf;
    n = (unsigned char)gb_read();
    for (i = 0; i < n && lexbuf[i] != 10; ++i)
        ;
    n = i;
    if (d > n)
        return 0;
    i = (unsigned char)d;
    if ((i == n || !wordc(lexbuf[i])) && i && wordc(lexbuf[i - 1]))
        --i;                            /* (just after a word) */
    if (i >= n || !wordc(lexbuf[i]))
        return 0;
    j = word_at(i, n, w1);
    /* the word after it, the word before it: a compound? */
    for (p = j; p < n && lexbuf[p] == ' '; ++p)
        ;
    w2[0] = 0;
    if (p < n && wordc(lexbuf[p]))
        word_at(p, n, w2);
    while (i && wordc(lexbuf[i - 1]))
        --i;
    for (p = i; p && lexbuf[p - 1] == ' '; --p)
        ;
    w0[0] = 0;
    if (p && wordc(lexbuf[p - 1]))
        word_at(p - 1, n, w0);
    if (w2[0]) {
        strcpy(both, w1);
        strcat(both, " ");
        strcat(both, w2);
        if ((e = syn_find(both)) != 0)
            return e;
    }
    if (w0[0]) {
        strcpy(both, w0);
        strcat(both, " ");
        strcat(both, w1);
        if ((e = syn_find(both)) != 0)
            return e;
    }
    return syn_find(w1);
}

void help_syntax(void)
{
    const char *s = at_cursor();
    syn_line[0] = 0;
    if (!s)
        return;
    s += strlen(s) + 1;
    strncpy(syn_line, s, 63);
    syn_line[63] = 0;
}

/* F1: the page of the keyword at the cursor (else Contents) */
void help_word(void)
{
    const char *e = at_cursor();
    if (e)
        strcpy(help_req, e);
    else
        strcpy(help_req, "Contents");
    help_file = HF_KEYWORDS;
    XCALL(B_HELP, help_show);
}
