/* Veranda Claude: the conversation and its rows (main RAM; DECISIONS V114).

   RAM banks (store_start, 6 at once: with vrnet's 2 and the overlays'
   4 the switcher still finds room to put the program aside on the
   512 KB machine):
     5         the conversation, 40 KB as one space (address a: bank
               a / 8192, at $A000 + a % 8192): its messages one after
               another, [kind][length lo, hi][text], the text in CP437
               (the font's), lines ended by LF; the kinds: the user's
               and Claude's (sent to the API), the program's notes, a
               user turn left out (not answered, or declined) and a
               declined reply (shown, never sent)
     1         the rows it is shown in ($A000: 4 bytes each, ROWMAX:
               the text's address lo, hi, its length, its flags: the
               kind, the message's first row), a message's rows made
               when it comes (wrapped at TW, at the last space; an empty
               row between two messages); the font at $B000 (main.c)
   A reply coming is the last message: its text appended, only its last
   row wrapped again. When the conversation is full, the oldest turns go
   (whole: what is left starts with a user turn, as the API wants), the
   rest moved down at once and its rows made again. Bytes go in and out
   of the banks a block at a time (st_get, st_put: memcpy within a
   bank). Only main RAM's code can map the banks (the overlays run at
   $A000 too): every function here puts back the bank it found.

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <string.h>
#include "claude.h"

unsigned char sbank;
unsigned int st_used, st_rows, st_cur = NOMSG, st_prot, st_dirty;
unsigned char st_gen, st_cutn, st_k;
unsigned int st_n, row_msg;
unsigned int st_cutb;           /* bytes dropped from the start so far (code.c's blocks follow them) */
unsigned char row_fl;           /* row_at's */

static unsigned char rbank, keep, rfull;
static char wb[TW + 2];                 /* (wrap's window) */

#define ROW(i) ((unsigned char *)0xA000 + ((i) << 2))

unsigned char store_start(void)
{
    sbank = BankAlloc(STBANKS + 1);
    if (!sbank)
        return 0;
    rbank = sbank + STBANKS;
    return 1;
}

/* (the caller's bank put back) */
#define ENTER() (keep = RAMBANK)
#define LEAVE() (RAMBANK = keep)

unsigned char __fastcall__ st_rd(unsigned int a)
{
    RAMBANK = sbank + (a >> 13);
    return *(unsigned char *)(0xA000 + (a & 0x1FFF));
}

/* n bytes from a into buf (main RAM), or from buf to a */
static void __fastcall__ st_get(unsigned int a, char *buf, unsigned int n)
{
    unsigned int o, k;
    while (n) {
        o = a & 0x1FFF;
        k = 0x2000 - o;
        if (k > n)
            k = n;
        RAMBANK = sbank + (a >> 13);
        memcpy(buf, (char *)0xA000 + o, k);
        buf += k;
        a += k;
        n -= k;
    }
}

static void __fastcall__ st_put(unsigned int a, const char *buf, unsigned int n)
{
    unsigned int o, k;
    while (n) {
        o = a & 0x1FFF;
        k = 0x2000 - o;
        if (k > n)
            k = n;
        RAMBANK = sbank + (a >> 13);
        memcpy((char *)0xA000 + o, buf, k);
        buf += k;
        a += k;
        n -= k;
    }
}

static unsigned int __fastcall__ rd16(unsigned int a)
{
    unsigned int v;
    st_get(a, (char *)&v, 2);
    return v;
}

static void __fastcall__ wr16(unsigned int a, unsigned int v)
{
    st_put(a, (char *)&v, 2);
}

unsigned int __fastcall__ st_msg(unsigned int a)
{
    ENTER();
    st_k = st_rd(a);
    st_n = rd16(a + 1);
    LEAVE();
    return a + 3 + st_n;
}

/*---------------------------------------------------------------- rows */

static unsigned char __fastcall__ code(unsigned char kind)
{
    switch (kind) {
    case K_USER: return R_USER;
    case K_CLAUDE: return R_CLAUDE;
    case K_UNSENT: return R_UNSENT;
    case K_DECLINED: return R_DECL;
    case K_CUSER: return R_CUSER;
    case K_CASST: return R_CASST;
    }
    return R_NOTE;
}

static void __fastcall__ row_put(unsigned int a, unsigned char n, unsigned char fl)
{
    unsigned char *r;
    if (st_rows >= ROWMAX) {
        rfull = 1;
        return;
    }
    RAMBANK = rbank;
    r = ROW(st_rows);
    r[0] = a;
    r[1] = a >> 8;
    r[2] = n;
    r[3] = fl;
    if (st_rows < st_dirty)
        st_dirty = st_rows;
    ++st_rows;
}

/* the text p .. e - 1 as rows from st_rows on (fl: the first's flags):
   a row ends at a line feed, or at the last space within TW (one past
   a third of it at least), else after TW; the last row is open (a
   reply's text may come after it) */
static void __fastcall__ wrap(unsigned int p, unsigned int e, unsigned char fl)
{
    unsigned int rem;
    unsigned char n, i, b;
    for (;;) {
        rem = e - p;
        n = rem < TW + 1 ? rem : TW + 1;
        st_get(p, wb, n);
        if (n > TW)
            n = TW;
        for (i = 0; i < n && wb[i] != '\n'; ++i)
            ;
        if (i < n) {
            row_put(p, i, fl);
            p += i + 1;
        } else if (rem <= TW) {
            row_put(p, rem, fl);
            return;
        } else {
            for (b = TW; b > TW / 3 && wb[b] != ' '; --b)
                ;
            if (b > TW / 3) {
                row_put(p, b, fl);
                p += b + 1;
            } else {
                row_put(p, TW, fl);
                p += TW;
            }
        }
        fl &= ~R_FIRST;
        if (rfull)
            return;
    }
}

/* message a's rows (an empty row before it, unless it is the first) */
static void __fastcall__ rows_of(unsigned int a)
{
    unsigned char k = st_rd(a);
    unsigned int n = rd16(a + 1);
    if (k == K_CINST || k == K_HIDDEN)
        return;                         /* (not shown: V123's compaction request) */
    if (a)
        row_put(a, 0, R_GAP);
    wrap(a + 3, a + 3 + n, code(k) | R_FIRST);
}

static void rows_all(void)
{
    unsigned int a = 0;
    st_rows = 0;
    rfull = 0;
    st_dirty = 0;
    while (a < st_used && !rfull) {
        rows_of(a);
        a += 3 + rd16(a + 1);
    }
    ++st_gen;
}

unsigned char __fastcall__ row_get(unsigned int i)
{
    unsigned char *r, n, fl;
    unsigned int a;
    ENTER();
    RAMBANK = rbank;
    r = ROW(i);
    a = r[0] | (r[1] << 8);
    n = r[2];
    fl = r[3];
    st_get(a, cs_txt, n);
    memset(cs_txt + n, ' ', TW - n);
    row_msg = a;
    LEAVE();
    return fl;
}

/*---------------------------------------------------------------- the oldest turns dropped */

/* where the conversation can start so that need bytes are free and the
   rows have room: a message after 0 that is not a reply (a user turn, a
   note, a turn left out), not past st_prot; the first that will do, else
   the last there is; 0: none */
static unsigned int cut_at(unsigned int need)
{
    unsigned int a = 0, c = 0;
    unsigned char k;
    while (a < st_prot) {
        a += 3 + rd16(a + 1);
        if (a > st_prot || a >= st_used)
            break;
        k = st_rd(a);
        if (k != K_CLAUDE && k != K_DECLINED) {
            c = a;
            if (STSIZE - st_used + a >= need)
                break;
        }
    }
    return c;
}

unsigned char __fastcall__ st_room(unsigned int need)
{
    unsigned int c, i, k;
    unsigned char r = 1;
    ENTER();
    st_cutn = 0;
    while (STSIZE - st_used < need || st_rows + 40 > ROWMAX) {
        c = cut_at(STSIZE - st_used < need ? need : STSIZE - st_used + 1);
        if (!c) {
            r = 0;
            break;
        }
        for (i = c; i < st_used; i += k) {      /* (moved down, 256 bytes at a time) */
            k = st_used - i > sizeof rbuf ? sizeof rbuf : st_used - i;
            st_get(i, (char *)rbuf, k);
            st_put(i - c, (char *)rbuf, k);
        }
        st_used -= c;
        st_prot -= c;
        st_cutb += c;
        if (st_cur != NOMSG)
            st_cur -= c;
        ++st_cutn;
        rows_all();
    }
    LEAVE();
    return r;
}

/*---------------------------------------------------------------- messages */

void st_clear(void)
{
    st_used = st_rows = st_prot = 0;
    st_cur = NOMSG;
    st_dirty = 0;
    ++st_gen;
}

unsigned int __fastcall__ st_add(unsigned char kind, const char *t, unsigned int n)
{
    unsigned int a;
    if (!st_room(n + 3))
        return NOMSG;
    ENTER();
    a = st_used;
    st_put(a, (char *)&kind, 1);
    wr16(a + 1, n);
    st_put(a + 3, t, n);
    st_used += n + 3;
    rfull = 0;
    rows_of(a);
    LEAVE();
    return a;
}

unsigned char __fastcall__ st_open(unsigned char kind)
{
    unsigned int a = st_add(kind, "", 0);
    if (a == NOMSG)
        return 0;
    st_cur = a;
    return 1;
}

/* the open message's last row made again (from its start) */
static void rewrap(void)
{
    unsigned char *r, fl;
    unsigned int p;
    RAMBANK = rbank;
    r = ROW(st_rows - 1);
    p = r[0] | (r[1] << 8);
    fl = r[3];
    if (fl == R_GAP)                    /* (an empty message: only its gap made) */
        return;
    --st_rows;
    rfull = 0;
    wrap(p, st_used, fl);
}

unsigned char __fastcall__ st_append(const char *t, unsigned int n)
{
    if (st_cur == NOMSG)
        return 0;
    if (STSIZE - st_used < n || st_rows + 8 > ROWMAX)
        if (!st_room(n + 2048))
            return 0;
    ENTER();
    st_put(st_used, t, n);
    st_used += n;
    wr16(st_cur + 1, st_used - st_cur - 3);
    rewrap();
    LEAVE();
    return 1;
}

void st_close(void)
{
    unsigned char c, *r;
    if (st_cur == NOMSG)
        return;
    ENTER();
    while (st_used > st_cur + 3) {      /* (trailing spaces and line feeds dropped) */
        c = st_rd(st_used - 1);
        if (c != ' ' && c != '\n')
            break;
        --st_used;
    }
    wr16(st_cur + 1, st_used - st_cur - 3);
    while (st_rows) {                   /* (its rows from the last that starts in its text) */
        RAMBANK = rbank;
        r = ROW(st_rows - 1);
        if ((r[0] | (r[1] << 8)) <= st_used || r[3] == R_GAP)
            break;
        --st_rows;
    }
    rewrap();
    st_cur = NOMSG;
    LEAVE();
}

/* message a's kind changed (its rows' flags too) */
void __fastcall__ st_kind(unsigned int a, unsigned char kind)
{
    unsigned int i, e, p;
    unsigned char *r, c;
    ENTER();
    st_put(a, (char *)&kind, 1);
    e = a + 3 + rd16(a + 1);
    c = code(kind);
    RAMBANK = rbank;
    for (i = 0; i < st_rows; ++i) {
        r = ROW(i);
        p = r[0] | (r[1] << 8);
        if (r[3] != R_GAP && p >= a + 3 && p <= e) {
            r[3] = (r[3] & ~R_KIND) | c;
            if (i < st_dirty)
                st_dirty = i;
        }
    }
    LEAVE();
}

/* the open message (the last) removed, its rows and its gap */
void __fastcall__ st_drop_last(void)
{
    unsigned char *r;
    if (st_cur == NOMSG)
        return;
    ENTER();
    while (st_rows) {
        RAMBANK = rbank;
        r = ROW(st_rows - 1);
        if ((r[0] | (r[1] << 8)) < st_cur)
            break;
        --st_rows;
        if (r[3] == R_GAP)
            break;
    }
    if (st_rows < st_dirty)
        st_dirty = st_rows;
    st_used = st_cur;
    st_cur = NOMSG;
    LEAVE();
}

unsigned int __fastcall__ st_copy(unsigned int a, char *buf, unsigned int n)
{
    ENTER();
    st_get(a, buf, n);
    LEAVE();
    return n;
}

/*---------------------------------------------------------------- V123: code.c's */

/* row i's text address (row_fl its flags) */
unsigned int __fastcall__ row_at(unsigned int i)
{
    unsigned char *r;
    unsigned int a;
    ENTER();
    RAMBANK = rbank;
    r = ROW(i);
    a = r[0] | (r[1] << 8);
    row_fl = r[3];
    LEAVE();
    return a;
}

void __fastcall__ row_set(unsigned int i, unsigned char fl)
{
    ENTER();
    RAMBANK = rbank;
    ROW(i)[3] = fl;
    LEAVE();
    if (i < st_dirty)
        st_dirty = i;
}

/* message a's kind (no rows changed: st_relayout after) */
void __fastcall__ st_mark(unsigned int a, unsigned char kind)
{
    ENTER();
    st_put(a, (char *)&kind, 1);
    LEAVE();
}

void st_relayout(void)
{
    ENTER();
    rows_all();
    LEAVE();
}

/* n bytes of buf (main RAM) to the rows' bank at off (the CP437 table: code.c's cp_init) */
void __fastcall__ rb_put(unsigned int off, const void *buf, unsigned char n)
{
    ENTER();
    RAMBANK = rbank;
    memcpy((char *)0xA000 + off, buf, n);
    LEAVE();
}

/* u's byte in the font, 0 when it has none (a tab, a line feed and a
   carriage return are not glyphs here); Veranda's set ($A0-$FF) first,
   so that what it has (§ ¶) is kept as its own byte (V143) */
unsigned char __fastcall__ cp_of(unsigned int u)
{
    unsigned char i = 0xA0;
    if (u >= 32 && u < 127)
        return u;
    ENTER();
    RAMBANK = rbank;
    do {
        if (CP437U[i] == u && i != 9 && i != 10 && i != 13)
            break;
        if (!++i)
            i = 1;
    } while (i != 0xA0);
    if (i == 0xA0 && CP437U[0xA0] != u)
        i = 0;
    LEAVE();
    return i;
}

/* CP437 byte c's Unicode (the table in the rows' bank) */
unsigned int __fastcall__ cp_u(unsigned char c)
{
    unsigned int u;
    ENTER();
    RAMBANK = rbank;
    u = CP437U[c];
    LEAVE();
    return u;
}
