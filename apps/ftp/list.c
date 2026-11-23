/* Veranda FTP: the panes' listings (main RAM; DECISIONS V100).

   A pane's entries (struct ent, 80 bytes) are kept in its RAM banks in
   the order they came; ord[] is the order shown, kept by a binary
   insertion as each one is added: ".." first, then the folders, then the
   files, by name (case ignored), size or date (View).

   The card's folder: CMDR-DOS's long listing ("$=L", DirOpen "=L": the
   shell's way, shell/dir.c): long names, sizes in bytes, dates.

   The server's listing, parsed as it arrives (Packet16's vfs.c: Marcin
   Spoczynski's, MIT with his permission): a line's fields counted as they
   come, the name being everything from its field to the end of the line
   (spaces kept):
     Unix  "drwxr-xr-x 2 user group 4096 Nov 16 10:42 name": the type from
           the first character (d, -, l), the size the field before the
           month, the name three fields after it (so a listing without
           the group column works too); "name -> target" for a link;
     DOS   (IIS) "11-16-26  10:42AM  <DIR>  name", "... 40960 name": a line
           that starts with a digit;
     MLSD  "type=file;size=40960;modify=20261116104200; name": the facts
           parsed one by one as each ";" comes (a server's facts may be
           longer than any buffer here: Packet16's Synology).
   ".", ".." and "total 8" are dropped; ".." is always added first.

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <string.h>
#include "ftp.h"

struct pane panes[2];
struct ent E, E2;
unsigned char sortby;
unsigned int rl_unparsed;

static unsigned char *addr(unsigned char i)
{
    return (unsigned char *)(0xA000 + (i % EPB) * ENTSZ);
}

static void __fastcall__ load(unsigned char p, unsigned char i, struct ent *e)
{
    BankCopy(addr(i), e, ENTSZ, panes[p].bank + i / EPB, 0);
}

void __fastcall__ ent_get(unsigned char p, unsigned char i)
{
    load(p, panes[p].ord[i], &E);
}

void pane_clear(unsigned char p)
{
    panes[p].n = panes[p].top = panes[p].sel = 0;
}

unsigned char __fastcall__ lower(unsigned char c)
{
    return c >= 'A' && c <= 'Z' ? c + 32 : c;
}

static unsigned char kind(const struct ent *e)
{
    return e->flags & E_UP ? 0 : e->flags & E_DIR ? 1 : 2;
}

/* <0: a before b */
static signed char cmp(const struct ent *a, const struct ent *b)
{
    unsigned char ka = kind(a), kb = kind(b), i;
    const unsigned char *x, *y;
    if (ka != kb)
        return ka < kb ? -1 : 1;
    if (sortby == SORT_SIZE && a->size != b->size)
        return a->size > b->size ? -1 : 1;
    if (sortby == SORT_DATE) {
        x = &a->y;
        y = &b->y;
        for (i = 0; i < 5; ++i)
            if (x[i] != y[i])
                return x[i] > y[i] ? -1 : 1;    /* (the newest first) */
    }
    x = (const unsigned char *)a->name;
    y = (const unsigned char *)b->name;
    for (; *x && lower(*x) == lower(*y); ++x, ++y)
        ;
    return lower(*x) < lower(*y) ? -1 : lower(*x) > lower(*y) ? 1 : 0;
}

/* entry k (in e) into the order of the first n */
static void __fastcall__ insert(unsigned char p, unsigned char k, const struct ent *e)
{
    struct pane *q = &panes[p];
    unsigned char lo = 0, hi = q->n, mid;
    while (lo < hi) {
        mid = (lo + hi) >> 1;
        load(p, q->ord[mid], &E2);
        if (cmp(e, &E2) < 0)
            hi = mid;
        else
            lo = mid + 1;
    }
    memmove(q->ord + lo + 1, q->ord + lo, q->n - lo);
    q->ord[lo] = k;
    ++q->n;
}

void __fastcall__ add(unsigned char p, struct ent *e)
{
    unsigned char k = panes[p].n;
    if (k >= MAXE)
        return;
    BankCopy(e, addr(k), ENTSZ, 0, panes[p].bank + k / EPB);
    insert(p, k, e);
}

void pane_add(unsigned char p)
{
    add(p, &E);
}

void pane_sort(unsigned char p)
{
    unsigned char n = panes[p].n, k;
    panes[p].n = 0;
    for (k = 0; k < n; ++k) {
        load(p, k, &E);
        insert(p, k, &E);
    }
}

void __fastcall__ up_entry(struct ent *e)
{
    memset(e, 0, sizeof *e);
    e->name[0] = e->name[1] = '.';
    e->flags = E_DIR | E_UP;
    e->h = 0xFF;
}

unsigned char __fastcall__ dec2(const char *p)
{
    return (p[0] - '0') * 10 + p[1] - '0';
}

unsigned char __fastcall__ is_digit(char c)
{
    return c >= '0' && c <= '9';
}

/*---------------------------------------------------------------- the server */

static struct ent R;                    /* the line being parsed */
static char rl[NAMEMAX + 8];
static unsigned char rln;
static char fbuf[24];
static unsigned char fbn;
static unsigned char lfield, in_word, in_name, semi, mlsd, name_at, mfield;
static char ltype;
static unsigned long prev_num, this_num;

static const char months[] = "janfebmaraprmayjunjulaugsepoctnovdec";

static void start_line(void)
{
    memset(&R, 0, sizeof R);
    R.h = 0xFF;
    rln = fbn = lfield = in_word = in_name = semi = mfield = 0;
    ltype = 0;
    name_at = 9;
    prev_num = this_num = 0;
}

void rlist_begin(unsigned char m)
{
    mlsd = m;
    rl_unparsed = 0;
    pane_clear(REMOTE);
    up_entry(&R);
    add(REMOTE, &R);
    start_line();
}

static unsigned long to_num(const char *s)
{
    unsigned long v = 0;
    while (is_digit(*s))
        v = v * 10 + (*s++ - '0');
    return v;
}

static unsigned char this_year(void)
{
    return year + 100;                  /* (the kernel's 0-99: 2000-2099) */
}

/* "HH:MM" with "AM"/"PM" or not */
static void time_of(const char *s)
{
    if (!is_digit(s[0]) || !is_digit(s[1]) || s[2] != ':')
        return;
    R.h = dec2(s);
    R.mi = dec2(s + 3);
    if ((s[5] == 'P' || s[5] == 'p') && R.h < 12)
        R.h += 12;
    else if ((s[5] == 'A' || s[5] == 'a') && R.h == 12)
        R.h = 0;
}

/* a field (fbuf, number lfield) of a LIST line has ended */
static void field_end(void)
{
    unsigned char i;
    fbuf[fbn] = 0;
    if (is_digit(ltype)) {              /* DOS: date, time, size or <DIR>, name */
        if (lfield == 1 && fbn >= 8) {
            R.mo = dec2(fbuf);
            R.d = dec2(fbuf + 3);
            R.y = fbn >= 10 ? (unsigned char)(to_num(fbuf + 6) - 1900) : dec2(fbuf + 6) + 100;
        } else if (lfield == 2)
            time_of(fbuf);
        else if (lfield == 3) {
            if (fbuf[0] == '<')
                R.flags = E_DIR;
            else
                R.size = to_num(fbuf);
        }
        return;
    }
    /* Unix: the month's field says where the others are */
    if (!mfield && lfield >= 4 && fbn == 3) {
        for (i = 0; i < 36; i += 3)
            if (lower(fbuf[0]) == months[i] && lower(fbuf[1]) == months[i + 1] && lower(fbuf[2]) == months[i + 2])
                break;
        if (i < 36) {
            mfield = lfield;
            name_at = lfield + 3;
            R.mo = i / 3 + 1;
            R.size = prev_num;
            return;
        }
    }
    if (mfield && lfield == mfield + 1)
        R.d = (unsigned char)to_num(fbuf);
    else if (mfield && lfield == mfield + 2) {
        if (fbuf[2] == ':') {
            time_of(fbuf);
            R.y = this_year();
            if (R.mo > month)
                --R.y;                  /* (ls: a time for the last 6 months) */
        } else
            R.y = (unsigned char)(to_num(fbuf) - 1900);
    }
    prev_num = is_digit(fbuf[0]) ? to_num(fbuf) : 0;
}

/* an MLSD fact (fbuf) */
static unsigned char prefix(const char *lit)
{
    const char *s = fbuf;
    for (; *lit; ++lit, ++s)
        if (lower(*s) != *lit)
            return 0;
    return 1;
}

static void fact(void)
{
    const char *s = fbuf + 7;
    fbuf[fbn] = 0;
    if (prefix("size="))
        R.size = to_num(fbuf + 5);
    else if (prefix("type=dir"))
        R.flags |= E_DIR;
    else if (prefix("type=cdir") || prefix("type=pdir"))
        R.flags |= E_UP;                /* (dropped) */
    else if (prefix("type=os.unix="))
        R.flags |= E_LINK;
    else if (prefix("modify=") && fbn >= 19) {
        R.y = (unsigned char)((s[0] - '0') * 1000u + dec2(s + 1) * 10u + (s[3] - '0') - 1900u);
        R.mo = dec2(s + 4);
        R.d = dec2(s + 6);
        R.h = dec2(s + 8);
        R.mi = dec2(s + 10);
    }
    fbn = 0;
}

static void flush_line(void)
{
    unsigned char i;
    rl[rln] = 0;
    if (!mlsd && in_name) {
        if (ltype == 'd')
            R.flags |= E_DIR;
        else if (ltype == 'l') {
            R.flags |= E_LINK;
            for (i = 0; i + 3 < rln; ++i)       /* "name -> target" */
                if (rl[i] == ' ' && rl[i + 1] == '-' && rl[i + 2] == '>' && rl[i + 3] == ' ') {
                    rl[i] = 0;
                    break;
                }
        } else if (ltype != '-' && !is_digit(ltype))
            in_name = 0;                /* (not an entry after all) */
        if (R.flags & (E_DIR | E_LINK))
            R.size = 0;
    }
    if (in_name && rl[0]) {
        if (!(R.flags & E_UP) && !(rl[0] == '.' && (!rl[1] || (rl[1] == '.' && !rl[2])))) {
            i = strlen(rl);
            if (i >= NAMEMAX) {
                rl[NAMEMAX - 2] = '~';
                rl[NAMEMAX - 1] = 0;
            }
            strcpy(R.name, rl);
            add(REMOTE, &R);
        }
    } else if (lfield) {
        if (!(ltype == 't' && lfield == 2))     /* ("total 8") */
            ++rl_unparsed;
    }
    start_line();
}

void __fastcall__ rlist_feed(const unsigned char *b, unsigned int n)
{
    unsigned char c;
    for (; n; --n) {
        c = *b++;
        if (c == '\n') {
            if (in_word && !in_name && !mlsd)
                field_end();
            flush_line();
            continue;
        }
        if (c == '\r')
            continue;
        if (in_name) {
            if (rln < sizeof rl - 1)
                rl[rln++] = c;
            continue;
        }
        if (mlsd) {
            if (semi && c == ' ') {     /* ";" then " ": the name */
                in_name = 1;
                continue;
            }
            semi = 0;
            if (c == ';') {
                fact();
                semi = 1;
                lfield = 1;             /* (something on the line) */
                continue;
            }
            if (fbn < sizeof fbuf - 1)
                fbuf[fbn++] = c;
            continue;
        }
        if (c == ' ' || c == '\t') {
            if (in_word)
                field_end();
            in_word = 0;
            continue;
        }
        if (!in_word) {
            in_word = 1;
            ++lfield;
            fbn = 0;
            if (lfield == 1)
                ltype = c;
            if (lfield == (is_digit(ltype) ? 4 : name_at)) {
                in_name = 1;
                rl[rln++] = c;
                continue;
            }
        }
        if (fbn < sizeof fbuf - 1)
            fbuf[fbn++] = c;
    }
}

void rlist_end(void)
{
    if (rln || lfield)
        flush_line();
}
