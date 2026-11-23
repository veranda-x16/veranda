/* VeraBASIC, the editor (DECISIONS V93): B_FMT, Format.

   Format is guarantee G2 (docs/vbasic/FORMAT.md 4.4): the text becomes
   detok(tok(text)), tools/vbtokens.py's canonical form. The X16's own
   tokenizer and prepare make the records (ide_go, IR_FORMAT: records 0
   and 1 kept in their runs, vt_recb); this detokenizes them as
   vbtokens.py's detok_line does: keywords in upper case, names as the
   symbol table spells them, one blank between words, none inside
   parentheses or before , ; : and ), the indentation from each line's
   flags, literals as they were spelt, comments and DATA byte for byte.
   One undo step (when the undo log holds the text).

   MIT licence (LICENSE). */
#include <string.h>
#include "ide.h"
/* the tokens' names and classes: B_LEX's (colour.c), read through ide_bget */
extern const char dt_name[];
extern const unsigned int dt_off[];
extern const unsigned char dt_cls[];

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

/*---------------------------------------------------------------
  Format: records 0 and 1 (in their runs) to the canonical text
 ---------------------------------------------------------------*/
#define CL_O 1                  /* the pieces' classes (detok_line's) */
#define CL_K 2
#define CL_V 3
#define CL_F 4
#define CL_N 5                  /* a name before ( */
#define CL_CALL 6
#define CL_RAW 7
#define CL_RAWSEP 8
#define CL_KRAW 9
#define CL_U 10                 /* a unary + or - */
#define CL_TIGHT 11
#define CL_OPEN 12              /* ( */
#define CL_CLOSE 13             /* ) */
#define CL_SEP 14               /* , ; : */
#define CL_HASH 15              /* # */
#define CL_APOS 16              /* ' */

static unsigned char r0b, r1b;          /* the records' runs */
static unsigned int nsym, nproc;
#pragma bss-name (push, "B5BSS")
static unsigned int symo[512];          /* each symbol's offset in record 0 (this bank's) */
#pragma bss-name (pop)
static unsigned int proco;              /* the procedures' offset */
#define rec IDE_REC                     /* a line record (main RAM: ide_bget) */
#define out IDE_OUT                     /* its text */
static unsigned int on;
static unsigned char prev;              /* the last piece's class (0: none) */
static unsigned char lerr;

static void rget(unsigned char run, unsigned int o, void *to, unsigned char n)
{
    unsigned int k = 8192 - (o & 0x1FFF);
    if (!n)
        return;
    bg_bank = run + (unsigned char)(o >> 13);
    bg_at = (void *)(0xA000 + (o & 0x1FFF));
    bg_to = to;
    if (k < n) {
        bg_n = (unsigned char)k;
        ide_bget();
        rget(run, o + k, (unsigned char *)to + k, n - (unsigned char)k);
        return;
    }
    bg_n = n;
    ide_bget();
}

static unsigned int rw0(unsigned int o)
{
    unsigned char b[2];
    rget(r0b, o, b, 2);
    return b[0] | b[1] << 8;
}

/* spaces between two pieces (vbtokens.py space_between) */
static unsigned char space(unsigned char p, unsigned char c)
{
    if (c == CL_RAW || c == CL_RAWSEP || p == CL_RAWSEP || p == CL_KRAW || p == CL_APOS)
        return 0;
    if (c == CL_SEP || c == CL_CLOSE)
        return 0;
    if (p == CL_OPEN || p == CL_HASH || p == CL_U)
        return 0;
    if (c == CL_TIGHT || p == CL_TIGHT)
        return 0;
    if (c == CL_OPEN && (p == CL_N || p == CL_F))
        return 0;
    return 1;
}

static void piece(const char *s, unsigned char n, unsigned char c)
{
    if (prev && space(prev, c) && on < IDE_OUTN - 1)
        out[on++] = ' ';
    if (on + n > IDE_OUTN - 1)
        n = IDE_OUTN - 1 - on;
    memcpy(out + on, s, n);
    on += n;
    prev = c;
}

/* symbol s's name */
static void sym_name(unsigned int s, unsigned char c)
{
    unsigned char n;
    char b[40];
    if (s >= nsym) {
        lerr = 1;
        return;
    }
    rget(r0b, symo[s] + 7, &n, 1);
    if (n > 39)
        n = 39;
    rget(r0b, symo[s] + 8, b, n);
    piece(b, n, c);
}

/* a local's symbol: the frame entry `slot` of the procedure whose range
   holds the record 1 offset pos */
static unsigned int local_sym(unsigned int pos, unsigned int slot)
{
    unsigned int o = proco, i, a, e;
    unsigned char nf;
    for (i = 0; i < nproc; ++i) {
        a = rw0(o + 2);
        e = rw0(o + 4);
        rget(r0b, o + 7, &nf, 1);
        if (a <= pos && pos <= e && slot < nf)
            return rw0(o + 9 + 3 * slot);
        o += 9 + 3 * nf;
    }
    lerr = 1;
    return 0;
}

static char *hex(char *p, unsigned int v, unsigned char d)
{
    static const char hx[] = "0123456789ABCDEF";
    while (d--)
        *p++ = hx[(v >> (d * 4)) & 15];
    return p;
}

/* one line record (at offset off in record 1) to out[on] */
static void detok_line(unsigned int off)
{
    unsigned char i = 6, t, n, c, k, cls, stmt_first = 1, in_defint = 0, first = 1, ln;
    unsigned int v, tk;
    char nb[20], *q;
    ln = rec[0];
    on = 0;
    prev = 0;
    /* the head: the number, the indentation */
    v = rec[1] | rec[2] << 8;
    if (v) {
        q = tk_put_ul(nb, v);
        piece(nb, q - nb, 0);
        prev = 0;
    }
    n = (rec[5] >> 4) * 2;
    if (v && rec[6])
        out[on++] = ' ';
    memset(out + on, ' ', n);
    if (rec[6] || !v)
        on += n;
    else
        n = 0;
    prev = 0;
    while (i < ln && (t = rec[i]) != 0) {
        if (t == 0x0B) {                /* a block partner offset */
            i += 3;
            continue;
        }
        cls = 0;
        if (t >= 1 && t <= 3) {
            v = rec[i + 1] | rec[i + 2] << 8;
            q = nb;
            if (t == 1)
                q = tk_put_ul(nb, v);
            else if (t == 2) {
                *q++ = '$';
                q = hex(q, v, v < 0x100 ? 2 : 4);
            } else {
                *q++ = '%';
                for (k = v < 0x100 ? 8 : 16; k--; )
                    *q++ = (v >> k) & 1 ? '1' : '0';
            }
            piece(nb, q - nb, CL_V);
            i += 3;
        } else if (t == 4) {
            piece((char *)rec + i + 7, rec[i + 6], CL_V);
            i += 7 + rec[i + 6];
        } else if (t == 5) {
            n = rec[i + 1];
            if (prev && space(prev, CL_V))
                out[on++] = ' ';
            out[on++] = '"';
            for (k = 0; k < n && on < IDE_OUTN - 3; ++k) {
                c = rec[i + 2 + k];
                out[on++] = c;
                if (c == '"')
                    out[on++] = '"';
            }
            out[on++] = '"';
            prev = CL_V;
            i += 2 + n;
        } else if (t == 6) {
            v = rec[i + 1] | rec[i + 2] << 8;
            if (v & 0x8000)
                v = local_sym(off + i, v & 0x7FFF);
            sym_name(v, i + 3 < ln && rec[i + 3] == '(' ? CL_N : CL_V);
            i += 3;
        } else if (t == 7) {
            v = rec[i + 1] | rec[i + 2] << 8;
            q = tk_put_ul(nb, v);
            piece(nb, q - nb, CL_V);
            i += 6;
        } else if (t == 8) {
            v = rec[i + 1] | rec[i + 2] << 8;
            cls = i + 6 < ln && rec[i + 6] == '(' ? CL_N : stmt_first ? CL_CALL : CL_V;
            if (first && (rec[5] & 2))
                cls = CL_V;
            sym_name(v, cls);
            i += 6;
        } else if (t == 9) {
            piece((char *)rec + i + 2, rec[i + 1], CL_RAW);
            i += 2 + rec[i + 1];
        } else if (t == 10) {
            piece((char *)rec + i + 2, rec[i + 1], CL_RAW);
            i += 2 + rec[i + 1];
            if (i < ln && rec[i] == ',') {
                piece(",", 1, CL_RAWSEP);
                ++i;
            }
        } else if (t >= 0x20 && t < 0x80) {
            c = t;
            if ((c == '-' || c == '+') && prev != CL_V && prev != CL_CLOSE)
                cls = CL_U;
            else if (c == '-' && in_defint)
                cls = CL_U;
            else if (c == '(')
                cls = CL_OPEN;
            else if (c == ')')
                cls = CL_CLOSE;
            else if (c == ',' || c == ';' || c == ':')
                cls = CL_SEP;
            else if (c == '#')
                cls = CL_HASH;
            else if (c == '\'')
                cls = CL_APOS;
            else
                cls = CL_O;
            if (in_defint && c == '-')
                cls = CL_TIGHT;
            nb[0] = c;
            piece(nb, 1, cls);
            ++i;
        } else {                        /* a keyword */
            if (t == 0xFF) {
                tk = 127 + rec[i + 1];
                i += 2;
            } else {
                tk = t - 0x80;
                ++i;
            }
            bg_bank = ide_banks[B_LEX];
            bg_at = (void *)(dt_off + tk);
            bg_to = &v;
            bg_n = 2;
            ide_bget();
            if (v == 0xFFFF) {
                lerr = 1;
                break;
            }
            bg_at = (void *)(dt_cls + tk);
            bg_to = &k;
            bg_n = 1;
            ide_bget();
            cls = k & 15;
            if (cls == 1)
                cls = CL_O;
            else if (cls == 2)
                cls = CL_K;
            else if (cls == 3)
                cls = CL_V;
            else
                cls = CL_F;
            if ((k & 0x10) || ((k & 0x20) && stmt_first))
                cls = CL_KRAW;
            bg_at = (void *)(dt_name + v);
            bg_to = nb;
            bg_n = 20;
            ide_bget();
            nb[19] = 0;
            piece(nb, strlen(nb), cls);
            if (k & 0x80)
                in_defint = 1;
            stmt_first = 0;
            first = 0;
            if (k & 0x40) {
                stmt_first = 1;
                in_defint = 0;
            }
            continue;
        }
        stmt_first = 0;
        first = 0;
        if (t == ':') {
            stmt_first = 1;
            in_defint = 0;
        }
    }
    (void)n;
}

/*---------------------------------------------------------------
  the statement an error stopped the program in (DECISIONS V97): the debugger's
  DI_QUOTE holds its tokens in the runtime's form (vbdbg.s d_quote), made
  the file's form again here (a global's cell, a local's frame offset, a
  procedure's or a label's target back to their symbols), then detokenized
  as Format does: IDE_OUT, 0-ended ("" if it cannot be)
 ---------------------------------------------------------------*/
#include "dbgshare.h"
void fmt_quote(void)
{
    unsigned char q[DQ_TOK], n, i = 6, t, k, pb, b;
    unsigned int v, cell, off, s, o;
    out[0] = 0;
    bg_bank = vx_dbg;
    bg_at = (void *)DI_QUOTE;
    bg_to = q;
    bg_n = DQ_TOK;
    ide_bget();
    r0b = vt_recb[0];
    n = q[DQ_N];
    if (!r0b || n > 240)
        return;
    pb = q[DQ_PBASE];
    cell = q[DQ_CELL] | q[DQ_CELL + 1] << 8;
    bg_at = (void *)(DI_QUOTE + DQ_TOK);
    bg_to = rec + 6;
    bg_n = n ? n : 1;
    ide_bget();
    rec[6 + n] = 0;
    nsym = rw0(4);
    nproc = rw0(6);
    if (nsym > 512)
        return;
    off = 24;
    for (s = 0; s < nsym; ++s) {
        symo[s] = off;
        rget(r0b, off + 7, &b, 1);
        off += 8 + b;
    }
    proco = off;
    lerr = 0;
    while ((t = rec[i]) != 0) {
        if ((t == ':' || t == 0x92) && i > 6)  /* (the statement's end: :, ELSE) */
            break;
        if (t >= 1 && t <= 3 || t == 0x0B)
            i += 3;
        else if (t == 4)
            i += 7 + rec[i + 6];
        else if (t == 5 || t == 9 || t == 10)
            i += 2 + rec[i + 1];
        else if (t == 6) {
            v = rec[i + 1] | rec[i + 2] << 8;
            v = v >= 0x0800 ? (v - cell) >> 3 : 0x8000 | v >> 3;
            rec[i + 1] = (unsigned char)v;
            rec[i + 2] = v >> 8;
            i += 3;
        } else if (t == 7)
            i += 6;
        else if (t == 8) {
            v = 0xFFFF;
            if (rec[i + 2] & 0x80) {    /* a procedure: its symbol */
                o = proco;
                for (k = 0; k < rec[i + 1] && k < nproc; ++k) {
                    rget(r0b, o + 7, &b, 1);
                    o += 9 + 3 * b;
                }
                v = rw0(o);
            } else {                    /* a label: the symbol whose target is the record */
                o = (rec[i + 5] - pb) * 7936 + (rec[i + 3] | rec[i + 4] << 8) - 0xA000;
                for (s = 0; s < nsym; ++s) {
                    rget(r0b, symo[s], &b, 1);
                    if ((b & 32) && rw0(symo[s] + 2) == o) {
                        v = s;
                        break;
                    }
                }
            }
            rec[i + 1] = (unsigned char)v;
            rec[i + 2] = v >> 8;
            i += 6;
        } else if (t == 0xFF)
            i += 2;
        else
            ++i;
        if (i >= 6 + n)
            break;
    }
    rec[i] = 0;
    rec[0] = i + 1;
    rec[1] = rec[2] = rec[3] = rec[4] = rec[5] = 0;
    detok_line(q[DQ_OFF] | q[DQ_OFF + 1] << 8);
    out[on] = 0;
    if (lerr)
        out[0] = 0;
}

void fmt_format(void)
{
    unsigned int off = 0, last = 0, src, i, size1;
    unsigned long newlen = 0, oldlen = gb_len, keep = cur_line;
    unsigned char ok = 1, b;
    r0b = vt_recb[0];
    r1b = vt_recb[1];
    size1 = vt_size[1];
    lerr = 0;
    nsym = rw0(4);
    nproc = rw0(6);
    if (nsym > 512 || !r0b || !r1b) {
        view_status_msg("Format: the program is too big");
        goto free;
    }
    off = 24;
    for (i = 0; i < nsym; ++i) {
        symo[i] = off;
        rget(r0b, off + 7, &b, 1);
        off += 8 + b;
    }
    proco = off;
    /* the old text goes (one undo step with the new one) */
    undo_step();
    undo_push(U_DEL, 0, oldlen);
    tx_delete(0, oldlen);
    off = 0;
    while (off < size1) {
        rget(r1b, off, rec, 1);
        if (!rec[0])
            break;
        rget(r1b, off, rec, rec[0]);
        src = rec[3] | rec[4] << 8;
        for (; last + 1 < src; ++last) {
            if (tx_insert(gb_len, "\n", 1)) {
                ok = 0;
                break;
            }
        }
        detok_line(off);
        out[on++] = 10;
        if (tx_insert(gb_len, out, on)) {
            ok = 0;
            break;
        }
        last = src;
        off += rec[0];
    }
    newlen = gb_len;
    undo_push(U_INS, 0, newlen);
    nlines = 1;
    gb_a = 0;
    gb_b = gb_len;
    gb_count();
    nlines = gb_r + 1;
    cur = 0;
    ed_recount();
    to_line(keep + 1);
    if (!ok)
        message("Not enough memory", "to format the whole program.");
    else if (lerr)
        view_status_msg("Format: a name could not be found (the text kept as far as it went)");
    else
        view_status_msg("Formatted");
    ide_logn("IDE FORMAT ", newlen);
    ide_log("\n");
free:
    for (b = 0; b < 4; ++b)
        if (vt_recb[b]) {
            BankFree(vt_recb[b]);
            vt_recb[b] = 0;
        }
}
