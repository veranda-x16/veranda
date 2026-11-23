/* textkit (Veranda Edit, VeraBASIC): undo. A log in six RAM banks of its own (48 KB, through
   buf.s's ul_read and ul_write): each change a record, the deleted bytes
   (for a deletion; for a replacement, U_REP, the text replaced) then a
   trailer: the position, the length (a replacement: the old length, the
   new one << 16), the kind, the step. A command is one step (typing runs on, Return ends a run);
   undo takes back the last step's records, newest first. When the log is
   full it starts again empty (the older steps are lost); a deletion
   larger than the log cannot be undone.

   MIT licence (see LICENSE). */
#include <string.h>
#include "tkapp.h"


struct trail {
    unsigned long pos, len;
    unsigned char type;
    unsigned int step;
};
#define TRAIL sizeof(struct trail)

static unsigned int ul_top, ul_cap, step, save_mark;
static struct trail t;
static unsigned char kind;              /* the run: 0 none, else its kind */

void undo_init(void)
{
    unsigned char b, n = TK_UNDO_BANKS, i;
    while (n && !(b = BankAlloc(n)))
        n >>= 1;
    for (i = 0; i < n; ++i)
        ul_bk[i] = b + i;
    ul_cap = n ? n * 8192U : 0;
    undo_clear();
}

void undo_clear(void)
{
    ul_top = 0;
    save_mark = 0;
    kind = 0;
}

void undo_step(void)
{
    ++step;
    kind = 0;
}

/* a change of this kind goes on the current run (typing): 1, or starts
   a new step: 0 */
unsigned char undo_run(unsigned char k)
{
    if (k && k == kind)
        return 1;
    undo_step();
    kind = k;
    return 0;
}

void undo_join(unsigned char k)
{
    kind = k;
}

static void io(unsigned int at, void *p, unsigned int n, unsigned char w)
{
    gb_a = at;
    gb_n = n;
    gb_lp = p;
    if (w)
        ul_write();
    else
        ul_read();
}

void undo_push(unsigned char type, unsigned long pos, unsigned long len)
{
    unsigned long dlen = type == U_DEL ? len : type == U_REP ? len & 0xFFFF : 0;
    unsigned long need = TRAIL + dlen, off;
    unsigned int c;
    if (!ul_cap)
        return;
    if (ul_top && type == U_INS) {      /* on from the last insertion */
        io(ul_top - TRAIL, &t, TRAIL, 0);
        if (t.type == U_INS && t.step == step && t.pos + t.len == pos) {
            t.len += len;
            io(ul_top - TRAIL, &t, TRAIL, 1);
            return;
        }
    }
    if (ul_top + need > ul_cap) {
        ul_top = 0;
        save_mark = 0xFFFF;
        if (need > ul_cap)
            return;                     /* lost: too large */
    }
    if (dlen)
        for (off = 0; off < dlen; off += c) {
            c = dlen - off > TK_IOBUF ? TK_IOBUF : (unsigned int)(dlen - off);
            gb_a = pos + off;
            gb_n = c;
            gb_lp = iobuf;
            gb_read();
            io(ul_top, iobuf, c, 1);
            ul_top += c;
        }
    t.pos = pos;
    t.len = len;
    t.type = type;
    t.step = step;
    io(ul_top, &t, TRAIL, 1);
    ul_top += TRAIL;
}

unsigned char undo_can(void)
{
    return ul_top != 0;
}

void undo_saved(void)
{
    undo_step();
    save_mark = ul_top;
}

/* the LFs in [p, p + n) */
static unsigned long lfs(unsigned long p, unsigned long n)
{
    gb_a = p;
    gb_b = p + n;
    gb_count();
    return gb_r;
}

/* the log's bytes at ul_top (len of them) back into the text at pos */
static void put_back(unsigned long pos, unsigned long len)
{
    unsigned long off;
    unsigned int c, i;
    for (off = 0; off < len; off += c) {
        c = len - off > TK_IOBUF ? TK_IOBUF : (unsigned int)(len - off);
        io(ul_top + (unsigned int)off, iobuf, c, 0);
        for (i = 0; i < c; ++i)
            if (iobuf[i] == 10)
                ++nlines;
        if (tx_insert(pos + off, iobuf, c))
            break;
    }
}

/* the last step's changes taken back, newest first: on the text itself
   (a replace all is hundreds of them), the cursor, the lines and the view
   counted again once at the end */
unsigned char undo(void)
{
    unsigned int s;
    unsigned long n;
    if (!ul_top)
        return 0;
    io(ul_top - TRAIL, &t, TRAIL, 0);
    s = t.step;
    while (ul_top) {
        io(ul_top - TRAIL, &t, TRAIL, 0);
        if (t.step != s)
            break;
        ul_top -= TRAIL;
        if (t.type == U_INS) {
            nlines -= lfs(t.pos, t.len);
            tx_delete(t.pos, t.len);
            cur = t.pos;
        } else if (t.type == U_DEL) {
            ul_top -= (unsigned int)t.len;
            put_back(t.pos, t.len);
            cur = t.pos + t.len;
        } else {                        /* U_REP: the old text for the new */
            n = t.len >> 16;
            t.len &= 0xFFFF;
            nlines -= lfs(t.pos, n);
            tx_delete(t.pos, n);
            ul_top -= (unsigned int)t.len;
            put_back(t.pos, t.len);
            cur = t.pos;
        }
    }
    ed_recount();
    modified = ul_top != save_mark;
    kind = 0;
    ++step;
    return 1;
}
