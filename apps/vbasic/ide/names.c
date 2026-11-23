/* VeraBASIC, the debugger (DECISIONS V97): B_HELP, the program's names
   for the debugger's pane (dbg.c calls these through xcall, their
   arguments and answers in LOW: x_sym, x_off, x_proc, x_kind, x_ok and
   XNAME), from record 0 (vt_recb[0], which a run keeps: its symbols, then
   its procedures; docs/vbasic/FORMAT.md). Walked, not cached: a bank has
   no room for the symbols' offsets, and the pane needs few names at a
   time (the variables' own offsets are in their DI_VARS entries).

   MIT licence (LICENSE). */
#include <string.h>
#include "ide.h"
#include "dbgshare.h"

static unsigned char r0b;
static unsigned int nsym, nproc, proco;

/* n (1-255) bytes of record 0 at o into main RAM */
static void rget(unsigned int o, void *to, unsigned char n)
{
    unsigned char k, *p = to;
    while (n) {
        k = 8192 - (o & 0x1FFF) > n ? n : (unsigned char)(8192 - (o & 0x1FFF));
        bg_bank = r0b + (unsigned char)(o >> 13);
        bg_at = (void *)(0xA000 + (o & 0x1FFF));
        bg_to = p;
        bg_n = k;
        ide_bget();
        p += k;
        o += k;
        n -= k;
    }
}

static unsigned int rw(unsigned int o)
{
    unsigned int v;
    rget(o, &v, 2);
    return v;
}

static unsigned char rb(unsigned int o)
{
    unsigned char v;
    rget(o, &v, 1);
    return v;
}

/* symbol s's offset */
static unsigned int sym_at(unsigned int s)
{
    unsigned int o = 24;
    while (s--)
        o += 8 + rb(o + 7);
    return o;
}

/* procedure p's entry */
static unsigned int proc_at(unsigned char p)
{
    unsigned int o = proco;
    while (p--)
        o += 9 + 3 * rb(o + 7);
    return o;
}

/* record 0 found (x_ok), the procedures' place; each symbol a frame
   entry of a procedure marked (DI_LOCAL, a bit each) */
void fmt_names(void)
{
    unsigned int i, s, o;
    unsigned char nf, k, bits[64];
    x_ok = 0;
    r0b = vt_recb[0];
    if (!r0b)
        return;
    nsym = rw(4);
    nproc = rw(6);
    if (nsym > 512)
        return;
    proco = sym_at(nsym);
    memset(bits, 0, 64);
    for (i = 0, o = proco; i < nproc; ++i) {
        nf = rb(o + 7);
        for (k = 0; k < nf; ++k) {
            s = rw(o + 9 + 3 * k);
            if (s < 512)
                bits[s >> 3] |= 1 << (s & 7);
        }
        o += 9 + 3 * nf;
    }
    dput(DI_LOCAL, bits, 64);
    x_ok = 1;
}

static void entry(unsigned int s, unsigned char slot, unsigned char fl, unsigned int o)
{
    unsigned char e[6];
    e[0] = (unsigned char)s;
    e[1] = s >> 8;
    e[2] = slot;
    e[3] = fl | rb(o + 1) << 4;
    e[4] = (unsigned char)o;
    e[5] = o >> 8;
    dput(DI_VARS + nv * 6, e, 6);
    ++nv;
}

/* the variables of procedure x_proc's break into DI_VARS (symbol, frame
   slot, flags: 1 a local, 2 an array, the type << 4; the symbol's offset):
   its frame first (nloc of them), then the globals (no procedure's) */
void fmt_vars(void)
{
    unsigned int o, i, s;
    unsigned char k, nf, kind, bits[64];
    nv = nloc = 0;
    if (!x_ok)
        return;
    if (x_proc != 0xFF && x_proc < nproc) {
        o = proc_at(x_proc);
        nf = rb(o + 7);
        for (k = 0; k < nf && nv < DI_VMAX; ++k) {
            s = rw(o + 9 + 3 * k);
            entry(s, k, 1 | (rb(o + 11 + 3 * k) & 2), sym_at(s));
        }
        nloc = nv;
    }
    dget(DI_LOCAL, bits, 64);
    for (i = 0, o = 24; i < nsym && nv < DI_VMAX; ++i, o += 8 + rb(o + 7)) {
        kind = rb(o);
        if (!(kind & 3) || (kind & (8 | 16 | 32 | 64)) || (bits[i >> 3] & (1 << (i & 7))))
            continue;
        entry(i, 0, kind & 2, o);
    }
}

/* the name of the symbol at offset x_off (0: of symbol x_sym) -> XNAME */
void fmt_symname(void)
{
    unsigned char n;
    if (!x_ok || (!x_off && x_sym >= nsym)) {
        strcpy(XNAME, "?");
        return;
    }
    if (!x_off)
        x_off = sym_at(x_sym);
    n = rb(x_off + 7);
    if (n > 40)
        n = 40;
    rget(x_off + 8, XNAME, n);
    XNAME[n] = 0;
    x_off = 0;
}

/* procedure x_proc -> XNAME: "SUB Tick", "FUNCTION Twice", "main" */
void fmt_procname(void)
{
    unsigned int o;
    unsigned char f, n, m;
    if (!x_ok || x_proc >= nproc) {
        strcpy(XNAME, "main");
        return;
    }
    o = proc_at(x_proc);
    f = rb(o + 8) & 1;
    n = f ? 9 : 4;
    x_off = 0;
    x_sym = rw(o);
    fmt_symname();
    m = strlen(XNAME);
    if (m > 38 - n)
        m = 38 - n;
    memmove(XNAME + n, XNAME, m);
    memcpy(XNAME, f ? "FUNCTION " : "SUB ", n);
    XNAME[n + m] = 0;
}

/* the name in XNAME (upper case) -> x_sym (0xFFFF: none), x_kind */
void fmt_findsym(void)
{
    unsigned int i, o;
    unsigned char n = strlen(XNAME), k, c, b[40];
    x_sym = 0xFFFF;
    if (!x_ok)
        return;
    for (i = 0, o = 24; i < nsym; ++i, o += 8 + k) {
        k = rb(o + 7);
        if (k != n)
            continue;
        rget(o + 8, b, n);
        for (c = 0; c < n && (b[c] >= 'a' && b[c] <= 'z' ? b[c] - 32 : b[c]) == XNAME[c]; ++c)
            ;
        if (c < n)
            continue;
        x_kind = rb(o);
        x_sym = i;
        return;
    }
}
