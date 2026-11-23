/* textkit (Veranda Edit, VeraBASIC): editing and moving. raw_insert and raw_delete change the
   text and keep the line count and the rows (the view) right; the ed_
   functions are the commands: the cursor, the selection, undo.

   MIT licence (see LICENSE). */
#include <string.h>
#include "tkapp.h"

unsigned long cur, anchor, cur_line, cur_ls, nlines;
static unsigned long anchor_line;
unsigned int goal;
unsigned char modified;

unsigned long sel_lo(void)
{
    return anchor < cur ? anchor : cur;
}

unsigned long sel_hi(void)
{
    return anchor > cur ? anchor : cur;
}

/* rows showing lines a .. b dirty */
static void mark_lines(unsigned long a, unsigned long b)
{
    unsigned long t;
    unsigned char r;
    if (a > b) {
        t = a;
        a = b;
        b = t;
    }
    if (b < top_line || a >= top_line + ROWS || top == NOWHERE)
        return;
    r = a < top_line ? 0 : (unsigned char)(a - top_line);
    for (; r < ROWS && top_line + r <= b; ++r)
        dirty[r] = 1;
}

/* the text changed at pos: d bytes (negative: deleted), lfs LFs in them */
static void changed(unsigned long pos, long d, unsigned long lfs)
{
    unsigned char r, last;
    unsigned long n;
    modified = 1;
    bars_dirty |= B_STATUS | B_TITLE | B_SCROLL;
    if (top == NOWHERE)
        return;
    if (pos < top) {
        if (d < 0 && pos + (unsigned long)-d > top) {
            top = NOWHERE;              /* the view's first line went: view_fix */
            return;
        }
        top += d;
        if (d < 0)
            top_line -= lfs;
        else
            top_line += lfs;
        for (r = 0; r <= ROWS; ++r)
            rs[r] += d;
        return;
    }
    /* the row it is in: the last whose line starts at or before pos */
    n = d < 0 ? nlines + lfs : nlines - lfs;      /* the lines as drawn */
    last = top_line + ROWS <= n ? ROWS : (unsigned char)(n - top_line);
    if (pos >= rs[last] && last == ROWS)
        return;                         /* below the window */
    for (r = 0; r + 1 < last && rs[r + 1] <= pos; ++r)
        ;
    if (lfs == 0) {
        dirty[r] = 1;
        for (++r; r <= ROWS; ++r)
            rs[r] += d;
    } else
        for (; r < ROWS; ++r)
            dirty[r] = 1;
}

unsigned char raw_insert(unsigned long pos, const void *p, unsigned int n)
{
    unsigned long k = 0;
    unsigned int i;
    const unsigned char *s = p;
    for (i = 0; i < n; ++i)
        if (s[i] == 10)
            ++k;
    if (tx_insert(pos, p, n)) {
        message("There is not enough memory", "for more text.");
        return 1;
    }
    nlines += k;
    changed(pos, n, k);
    return 0;
}

void raw_delete(unsigned long pos, unsigned long n)
{
    unsigned long k;
    if (!n)
        return;
    gb_a = pos;
    gb_b = pos + n;
    gb_count();
    k = gb_r;
    tx_delete(pos, n);
    nlines -= k;
    changed(pos, -(long)n, k);
}

/* the cursor to p in the unchanged text: its line by counting */
void set_cur(unsigned long p)
{
    if (p == 0)
        cur_line = 0;
    else if (p >= gb_len) {
        p = gb_len;
        cur_line = nlines - 1;
    } else if (p > cur) {
        gb_a = cur;
        gb_b = p;
        gb_count();
        cur_line += gb_r;
    } else if (p < cur) {
        gb_a = p;
        gb_b = cur;
        gb_count();
        cur_line -= gb_r;
    }
    cur = p;
    gb_a = p;
    gb_line_start();
    cur_ls = gb_a;
}

/* the cursor to p; extend: the selection's anchor stays */
void move_to(unsigned long p, unsigned char extend)
{
    unsigned long old = cur_line;
    if (!extend && HAS_SEL())
        mark_lines(anchor_line, cur_line);
    set_cur(p);
    if (extend)
        mark_lines(old, cur_line);
    else {
        anchor = cur;
        anchor_line = cur_line;
    }
    bars_dirty |= B_STATUS;
}

static unsigned int col_of(unsigned long p)
{
    gb_a = cur_ls;
    gb_b = p;
    return gb_col();
}

/* n lines down (up if negative), at the column `goal` */
void move_line(long n, unsigned char extend)
{
    unsigned long ls = cur_ls, line = cur_line, oldl = cur_line;
    if (n > 0) {
        if (line + n >= nlines)
            n = nlines - 1 - line;
        if (!n) {
            move_to(gb_len, extend);
            return;
        }
        gb_a = ls;
        gb_n = n;
        gb_fwd_lines();
        ls = gb_a;
        line += n;
    } else {
        while (n++ < 0 && line) {
            gb_a = ls - 1;
            gb_line_start();
            ls = gb_a;
            --line;
        }
        if (line == cur_line) {
            move_to(0, extend);
            return;
        }
    }
    if (!extend && HAS_SEL())
        mark_lines(anchor_line, cur_line);
    gb_a = ls;
    gb_n = goal;
    gb_at_col();
    cur = gb_a;
    cur_ls = ls;
    cur_line = line;
    if (extend)
        mark_lines(oldl, cur_line);
    else {
        anchor = cur;
        anchor_line = cur_line;
    }
    bars_dirty |= B_STATUS;
}

static unsigned char is_word(unsigned char c)
{
    return (c >= '0' && c <= '9') || (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || c == '_' || c >= 0xC0;
}

void move_word(signed char dir, unsigned char extend)
{
    unsigned long p = cur;
    if (dir > 0) {
        while (p < gb_len && !is_word(tx_get(p)))
            ++p;
        while (p < gb_len && is_word(tx_get(p)))
            ++p;
    } else {
        while (p && !is_word(tx_get(p - 1)))
            --p;
        while (p && is_word(tx_get(p - 1)))
            --p;
    }
    move_to(p, extend);
    goal = col_of(cur);
}

void move_home(unsigned char extend)
{
    move_to(cur_ls, extend);
    goal = 0;
}

void move_end(unsigned char extend)
{
    gb_a = cur_ls;
    gb_n = 0xFFFF;
    gb_at_col();
    move_to(gb_a, extend);
    goal = col_of(cur);
}

void move_page(signed char dir, unsigned char extend)
{
    long n = dir > 0 ? ROWS - 1 : -(ROWS - 1);
    unsigned long t = top_line;
    move_line(n, extend);
    /* the view by a page too, as far as it goes */
    if (dir > 0) {
        if (t + ROWS - 1 + ROWS <= nlines) {
            gb_a = top;
            gb_n = ROWS - 1;
            gb_fwd_lines();
            top = gb_a;
            top_line = t + ROWS - 1;
        }
    } else if (t >= ROWS - 1) {
        while (top_line > t - (ROWS - 1)) {
            gb_a = top - 1;
            gb_line_start();
            top = gb_a;
            --top_line;
        }
    } else {
        top = 0;
        top_line = 0;
    }
    if (top_line != t) {
        rs[0] = top;
        memset(dirty, 1, ROWS);
        bars_dirty |= B_SCROLL;
    }
}

/* n bytes at the cursor, over the selection (undo recorded) */
unsigned char ed_insert(const void *p, unsigned int n)
{
    unsigned long k = nlines;
    if (HAS_SEL())
        ed_delete_sel();
    if (raw_insert(cur, p, n))
        return 1;
    undo_push(U_INS, cur, n);
    k = nlines - k;
    cur += n;
    cur_line += k;
    if (k) {
        gb_a = cur;
        gb_line_start();
        cur_ls = gb_a;
    }
    anchor = cur;
    anchor_line = cur_line;
    goal = col_of(cur);
    return 0;
}

void ed_delete_sel(void)
{
    unsigned long lo = sel_lo(), hi = sel_hi();
    if (lo == hi)
        return;
    mark_lines(anchor_line, cur_line);
    set_cur(lo);                        /* (counted in the text as it is) */
    undo_push(U_DEL, lo, hi - lo);
    raw_delete(lo, hi - lo);
    anchor = cur;
    anchor_line = cur_line;
    goal = col_of(cur);
}

void ed_backspace(void)
{
    if (HAS_SEL()) {
        ed_delete_sel();
        return;
    }
    if (!cur)
        return;
    anchor = cur - 1;
    ed_delete_sel();
}

void ed_delete(void)
{
    if (HAS_SEL()) {
        ed_delete_sel();
        return;
    }
    if (cur >= gb_len)
        return;
    anchor = cur + 1;
    anchor_line = cur_line;
    ed_delete_sel();
}

/* after a change everywhere (replace all, undo of much) */
void ed_changed_all(void)
{
    top = NOWHERE;
    bars_dirty = 7;
}

/* n bytes from pos into out (n <= 64): 1 if all there */
unsigned char ed_text(unsigned long pos, unsigned int n, char *out)
{
    gb_a = pos;
    gb_n = n;
    gb_lp = out;
    return gb_read() == n;
}

void select_all(void)
{
    move_to(0, 0);
    move_to(gb_len, 1);
    anchor_line = 0;
    memset(dirty, 1, ROWS);
}

void select_word(void)
{
    unsigned long a = cur, b = cur;
    while (a && is_word(tx_get(a - 1)))
        --a;
    while (b < gb_len && is_word(tx_get(b)))
        ++b;
    if (a == b)
        return;
    move_to(a, 0);
    move_to(b, 1);
    goal = col_of(cur);
}

/* after changes made on the text itself (undo, replace all): the
   cursor's line counted from the start, no selection, the view anchored
   at the cursor again, everything drawn */
void ed_recount(void)
{
    gb_a = 0;
    gb_b = cur;
    gb_count();
    cur_line = gb_r;
    gb_a = cur;
    gb_line_start();
    cur_ls = gb_a;
    anchor = cur;
    anchor_line = cur_line;
    top = NOWHERE;
    bars_dirty = 7;
    modified = 1;
}

/* no selection (the rows that showed one redrawn) */
void sel_clear(void)
{
    if (HAS_SEL()) {
        mark_lines(anchor_line, cur_line);
        bars_dirty |= B_STATUS;
    }
    anchor = cur;
    anchor_line = cur_line;
}

/* the view at the top, everything to be drawn (here, not in view.c:
   Veranda Edit's overlay 2 calls it) */
void view_init(void)
{
    top = 0;
    top_line = 0;
    hs = 0;
    rs[0] = 0;
    cursor_on = 0;
    memset(dirty, 1, ROWS);
    bars_dirty = 7;
    thumb_n = 0;
}

/* an empty document's state (the text made already) */
void doc_reset(void)
{
    cur = anchor = cur_line = cur_ls = anchor_line = 0;
    nlines = 1;
    goal = 0;
    modified = 0;
    view_init();
}
