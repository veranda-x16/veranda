/* textkit (Veranda Edit, VeraBASIC): the text's RAM banks (buf.s is the gap buffer itself).

   Banks come in runs from BankAlloc (the kernel keeps 24 runs for every
   program and itself, so not one bank at a time): a run of up to 16 for
   a new text, then runs of 4 as the gap needs more (a pool of spare
   banks); the table gb_bk makes them one array, in any order.

   MIT licence (see LICENSE). */
#include <veranda.h>
#include "tkapp.h"

#define MAXRUNS 16
static unsigned char runs[MAXRUNS];
unsigned char tx_runs;
static unsigned char pool, pooln;       /* the next spare bank, how many */

static unsigned char alloc_run(unsigned char want)
{
    unsigned char b;
    if (tx_runs == MAXRUNS)
        return 0;
    while (want) {
        b = BankAlloc(want);
        if (b) {
            runs[tx_runs++] = b;
            pool = b;
            pooln = want;
            return want;
        }
        want >>= 1;
    }
    return 0;
}

/* a spare bank, 0 if there is none */
unsigned char tx_bank(void)
{
    if (gb_nb >= 60 || (!pooln && !alloc_run(4)))
        return 0;
    --pooln;
    return pool++;
}

void tx_free(void)
{
    while (tx_runs)
        BankFree(runs[--tx_runs]);
    pooln = 0;
    gb_nb = 0;
    gb_gs = gb_ge = gb_cap = gb_len = 0;
}

/* a new, empty text with room for `room` bytes; load: the gap one bank
   at the front and the text appended after it (gb_append); 1: not
   enough memory */
unsigned char tx_new(unsigned long room, unsigned char load)
{
    unsigned char n, w;
    if (room > 59UL * BANK_SIZE)
        return 1;
    n = (unsigned char)((room + BANK_SIZE - 1) / BANK_SIZE) + 1;
    if (n < 2)
        n = 2;
    tx_free();
    while (gb_nb < n) {
        if (!pooln) {
            w = n - gb_nb;
            if (!alloc_run(w > 16 ? 16 : w)) {
                tx_free();
                return 1;
            }
        }
        gb_bk[gb_nb++] = pool++;
        --pooln;
    }
    gb_ge = gb_cap = load ? BANK_SIZE : (unsigned long)n * BANK_SIZE;
    return 0;
}

/* the gap at least n bytes long; 1: no memory */
unsigned char tx_room(unsigned int n)
{
    unsigned char b;
    while (gb_ge - gb_gs < n) {
        b = tx_bank();
        if (!b)
            return 1;
        gb_grow(b);
    }
    return 0;
}

/* loading: room for n + 1 bytes after cap */
unsigned char tx_tail(unsigned int n)
{
    unsigned char b;
    while ((unsigned long)gb_nb * BANK_SIZE - gb_cap < (unsigned long)n + 1) {
        b = tx_bank();
        if (!b)
            return 1;
        gb_bk[gb_nb++] = b;
    }
    return 0;
}

unsigned char tx_insert(unsigned long pos, const void *p, unsigned int n)
{
    gb_a = pos;
    gb_moveto();
    if (tx_room(n))
        return 1;
    gb_lp = (void *)p;
    gb_n = n;
    gb_ins();
    return 0;
}

void tx_delete(unsigned long pos, unsigned long n)
{
    gb_a = pos;
    gb_moveto();
    gb_n = n;
    gb_del();
}

unsigned char tx_get(unsigned long pos)
{
    gb_a = pos;
    return gb_get();
}
