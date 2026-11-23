/* VeraBASIC, the debugger (DECISIONS V97): B_LEX, a watch's or an
   assignment's expression into tokens in the runtime's form (the
   debugger's requests, dbgshare.h), with the keyword tables this bank
   has (idekw.h, colour.c's): numbers (a float as its spelling: vbdbg.s
   makes its value), strings, the program's variables (B_FMT's names:
   its procedure's locals first, as names.c listed them in DI_VARS), the
   operators and the functions. Statements, SUBs, FUNCTIONs and labels
   are not in an expression a debugger evaluates.

   tk_expr: XSRC onto RQBUF at rqn; x_ok 1, or 0 and x_kind the error
   (TE_*, dbg.c says it).

   MIT licence (LICENSE). */
#include <string.h>
#include "ide.h"
#include "dbgshare.h"

extern const char dt_name[];
extern const unsigned int dt_off[];
extern const unsigned char dt_cls[];

#define T_INT    1               /* (the token tags: vb.inc) */
#define T_VARTAG 6
#define TE_QUOTE 1
#define TE_STMT  2
#define TE_NAME  3
#define TE_CHAR  4

static void out(unsigned char b)
{
    if (rqn < 500)
        RQBUF[rqn++] = b;
}

static unsigned char up(unsigned char c)
{
    return c >= 'a' && c <= 'z' ? c - 32 : c;
}

/* a keyword (upper case) -> its token + 1 (0 none) and class */
static unsigned int kw(const char *w, unsigned char *cls)
{
    unsigned int t;
    for (t = 0; t < 383; ++t)
        if (dt_off[t] != 0xFFFF && !strcmp(dt_name + dt_off[t], w)) {
            *cls = dt_cls[t] & 15;
            return t + 1;
        }
    return 0;
}

static void out_kw(unsigned int t)
{
    if (t < 127)
        out(0x80 + t);
    else {
        out(0xFF);
        out(t - 127);
    }
}

static void out_word(unsigned char tag, unsigned int v)
{
    out(tag);
    out((unsigned char)v);
    out(v >> 8);
}

static unsigned char fail(unsigned char e)
{
    x_kind = e;
    x_ok = 0;
    return 0;
}

static unsigned char expr(const char *s)
{
    unsigned char i = 0, j, n, c, cls, dot, e[6];
    unsigned int t, v;
    char w[16];
    for (;;) {
        c = s[i];
        if (!c)
            return 1;
        if (c == ' ') {
            ++i;
            continue;
        }
        if ((c >= '0' && c <= '9') || (c == '.' && s[i + 1] >= '0' && s[i + 1] <= '9')) {
            for (j = i, dot = 0, v = 0; ; ++j) {
                c = s[j];
                if (c >= '0' && c <= '9') {
                    if (v > 3276 || (v == 3276 && c > '7'))
                        dot = 1;
                    v = v * 10 + c - '0';
                } else if (c == '.')
                    dot = 1;
                else if ((c & 0xDF) == 'E' && j > i) {
                    dot = 1;
                    if (s[j + 1] == '-' || s[j + 1] == '+')
                        ++j;
                } else
                    break;
            }
            if (!dot)
                out_word(T_INT, v);
            else {                      /* a float: its spelling (vbdbg.s: its value) */
                out(4);
                for (n = 0; n < 5; ++n)
                    out(0);
                out(j - i);
                for (n = i; n < j; ++n)
                    out(s[n]);
            }
            i = j;
            continue;
        }
        if ((c == '$' || c == '%') && s[i + 1] > ' ') {
            for (j = i + 1, v = 0; ; ++j) {
                n = up(s[j]);
                if (n >= '0' && n <= '9')
                    n -= '0';
                else if (c == '$' && n >= 'A' && n <= 'F')
                    n -= 'A' - 10;
                else
                    break;
                v = c == '$' ? v << 4 | n : v << 1 | (n & 1);
            }
            out_word(c == '$' ? 2 : 3, v);
            i = j;
            continue;
        }
        if (c == '"') {
            for (j = i + 1, n = 0; s[j] && s[j] != '"'; ++j)
                ++n;
            if (!s[j])
                return fail(TE_QUOTE);
            out(5);
            out(n);
            for (j = i + 1; s[j] != '"'; ++j)
                out(s[j]);
            i = j + 1;
            continue;
        }
        if (up(c) >= 'A' && up(c) <= 'Z') {
            for (j = i, n = 0; ; ++j) {
                c = up(s[j]);
                if (!((c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_'))
                    break;
                if (n < 14)
                    w[n++] = c;
            }
            if (s[j] == '$' || s[j] == '%') {
                if (n < 14)
                    w[n++] = s[j];
                ++j;
            }
            w[n] = 0;
            i = j;
            if ((t = kw(w, &cls)) != 0) {
                if (cls == 2 && strcmp(w, "NOT"))
                    return fail(TE_STMT);
                out_kw(t - 1);
                continue;
            }
            strcpy(XNAME, w);
            XCALL(B_HELP, fmt_findsym);
            if (x_sym == 0xFFFF || (x_kind & (8 | 16 | 32)))
                return fail(TE_NAME);
            for (n = 0; n < nloc; ++n) {    /* the procedure's own first */
                dget(DI_VARS + n * 6, e, 3);
                if ((e[0] | e[1] << 8) == x_sym) {
                    out_word(T_VARTAG, e[2] * 8);
                    break;
                }
            }
            if (n == nloc)
                out_word(T_VARTAG, cellbase + x_sym * 8);
            continue;
        }
        if ((c == '<' || c == '>') && (s[i + 1] == '=' || (c == '<' && s[i + 1] == '>'))) {
            w[0] = c;
            w[1] = s[i + 1];
            w[2] = 0;
            if ((t = kw(w, &cls)) != 0) {
                out_kw(t - 1);
                i += 2;
                continue;
            }
        }
        if (strchr("+-*/^()=<>,;", c)) {
            out(c);
            ++i;
            continue;
        }
        return fail(TE_CHAR);
    }
}

void tk_expr(void)
{
    x_ok = 1;
    expr(XSRC);
}
