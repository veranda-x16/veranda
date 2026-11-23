/* Veranda Chat: the windows and what they keep (main RAM; DECISIONS V111).

   RAM banks (store_start, 7 at once: the switcher still finds room to
   put the program aside on the 512 KB machine):
     4         the windows' scrollbacks, 4 KB each, two a bank (window w
               in bank w / 2, half w % 2), the input's history in the last
               half: lines one after another,
               [length lo, hi][attribute][hour][minute][text][length lo, hi]
               (the length at both ends: the screen reads them from the
               newest back); when a line does not fit, the oldest lines
               go (at least 1 KB at once, so the move is rare)
     3         the channels' topics and nicks, 4 KB each, two a bank
               (window w >= 1 in bank (w - 1) / 2): the topic
               (TOPICMAX), an index of
               NMAX words, kept sorted (ops, half-ops, voices, the rest;
               by name in IRC's case), pointing at entries of NICKLEN
               bytes (the mode character, ' ' none, 0 a free entry; the
               nick 0-padded)
     (the history: HISTN lines of 512 bytes, a ring)
   Only main RAM's code can map them (the overlays run at $A000 too), so
   everything that reads or writes them is here, through main RAM's
   buffers (ln, nk).

   (V178) Nothing here trusts what it reads back from a bank: a window
   number outside 1-6 maps no nick bank, a scrollback whose lengths do not
   add up is emptied instead of moved, a line longer than ln is not
   copied, the search for a free nick entry stops at the last one, an
   index past the nicks kept is not followed. A channel keeps NMAX nicks;
   W[].people counts them all (proto.c; "and N more" in the list). A nick
   is found by a binary search in each mode's run of the index (6 of 8
   steps instead of all 190 compared in turn: Libera's #linux, 2,418
   names in 45 lines, took 76 s, the main loop stopped 1.7 s a line).

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <string.h>
#include "chat.h"

struct win W[WMAX];
unsigned char cw;
char ln[LNMAX];
unsigned char ln_attr, ln_hh, ln_mm;
unsigned int ln_len;
char nk[NICKLEN + 1];
unsigned char hist_n;

static unsigned char sbb, nkb, hb, htop;
static unsigned char *sb;               /* the scrollback mapped (smap) */
static char *nb;                        /* the nick list mapped (nmap) */

static void __fastcall__ smap(unsigned char w)
{
    RAMBANK = sbb + (w >> 1);
    sb = (unsigned char *)(w & 1 ? 0xB000 : 0xA000);
}

static struct win *P;                   /* (nmap's) the window */

/* (callers check w with okw) */
static void __fastcall__ nmap(unsigned char w)
{
    P = &W[w];
    --w;
    RAMBANK = nkb + (w >> 1);
    nb = (char *)(w & 1 ? 0xB000 : 0xA000);
}

/* a window that has a nick bank: 1 .. WMAX - 1 */
#define okw(w)  ((unsigned char)((w) - 1) < WMAX - 1)
static char kn[NICKLEN];                /* a nick copied below $A000 (the caller's may be in an overlay) */

static void __fastcall__ knick(const char *s)
{
    if (s != kn) {
        strncpy(kn, s, NICKLEN - 1);
        kn[NICKLEN - 1] = 0;
    }
}

#define TOPIC   (nb)
#define IDX     ((unsigned int *)(nb + TOPICMAX))
#define ENT     (nb + TOPICMAX + 2 * NMAX)
#define ENDENT  (nb + TOPICMAX + 2 * NMAX + NMAX * NICKLEN)
#if TOPICMAX + 2 * NMAX + NMAX * NICKLEN > 4096
#error "a channel's topic and nicks are more than half a bank"
#endif

unsigned char store_start(void)
{
    sbb = BankAlloc(7);
    if (!sbb)
        return 0;
    nkb = sbb + 4;
    hb = sbb + 3;                       /* (its second half: $B000) */
    W[0].kind = W_SERV;
    return 1;
}

/*---------------------------------------------------------------- IRC's case */

unsigned char __fastcall__ ilower(unsigned char c)
{
    return c >= 'A' && c <= '^' ? c + 32 : c;
}

unsigned char __fastcall__ ieqn(const char *a, const char *b, unsigned char n)
{
    unsigned char c;
    while (n--) {
        c = ilower(*a++);
        if (c != ilower(*b++))
            return 0;
        if (!c)
            return 1;
    }
    return 1;
}

unsigned char __fastcall__ ieq(const char *a, const char *b)
{
    return ieqn(a, b, 255);
}

/*---------------------------------------------------------------- windows */

signed char __fastcall__ win_find(const char *name)
{
    unsigned char i;
    if (!name[0])
        return 0;
    for (i = 1; i < WMAX; ++i)
        if (W[i].kind != W_FREE && ieq(W[i].name, name))
            return i;
    return -1;
}

signed char __fastcall__ win_new(unsigned char kind, const char *name)
{
    unsigned char i;
    for (i = 1; i < WMAX; ++i)
        if (W[i].kind == W_FREE)
            break;
    if (i == WMAX)
        return -1;
    memset(&W[i], 0, sizeof W[i]);
    strncpy(W[i].name, name, NAMEMAX - 1);
    W[i].kind = kind;
    nk_clear(i);
    topic_set(i, "");
    dirty |= D_TABS;
    return i;
}

void __fastcall__ win_close(unsigned char w)
{
    if (!w)
        return;
    W[w].kind = W_FREE;
    if (cw == w) {
        cw = 0;
        cw_req = 0;
    }
    dirty |= D_ALL;
}

/*---------------------------------------------------------------- the scrollback */

void __fastcall__ sb_clear(unsigned char w)
{
    W[w].used = W[w].lines = 0;
    W[w].scroll = 0;
    ++W[w].seq;
}

void __fastcall__ sb_add(unsigned char w, unsigned char attr, const char *text)
{
    unsigned char keep = RAMBANK;
    struct win *p = &W[w];
    unsigned int n = strlen(text), size, cut, l;
    unsigned char *a;
    if (n > LNMAX - 1)
        n = LNMAX - 1;
    if (text != tbuf) {                 /* (it may be in an overlay's bank) */
        memcpy(tbuf, text, n);
        tbuf[n] = 0;
        text = tbuf;
    }
    size = n + 7;
#ifdef CHAT_TEST
    gt_line(w, attr, text);
#endif
    smap(w);
    if (p->used + size > SBSIZE) {      /* the oldest lines dropped */
        cut = 0;
        while (cut < p->used && (cut < p->used + size - SBSIZE || cut < 1024)) {
            a = sb + cut;
            l = a[0] | (a[1] << 8);
            cut += l + 7;
            --p->lines;
        }
        if (cut > p->used) {            /* (V178: lengths that do not add up: all of it) */
            cut = p->used;
            p->lines = 0;
        }
        memmove(sb, sb + cut, p->used - cut);
        p->used -= cut;
    }
    a = sb + p->used;
    a[0] = (unsigned char)n;
    a[1] = n >> 8;
    a[2] = attr;
    a[3] = now_hh();
    a[4] = now_mm();
    memcpy(a + 5, text, n);
    a[n + 5] = (unsigned char)n;
    a[n + 6] = n >> 8;
    p->used += size;
    ++p->lines;
    ++p->seq;
    RAMBANK = keep;
    if (w != cw && attr != A_INFO) {
        l = attr == A_MENTION || (p->kind == W_QUERY && attr != A_OWN) ? U_MENTION : U_NEW;
        if (p->unread < l) {
            p->unread = l;
            dirty |= D_TABS;
        }
    }
}

unsigned int __fastcall__ sb_prev(unsigned char w, unsigned int end)
{
    unsigned char keep = RAMBANK;
    unsigned char *a;
    unsigned int n, s;
    smap(w);
    a = sb + end;
    n = a[-2] | (a[-1] << 8);
    if (n >= LNMAX)                     /* (V178: never past ln) */
        n = 0;
    s = end - n - 7;
    a = sb + s;
    ln_attr = a[2];
    ln_hh = a[3];
    ln_mm = a[4];
    memcpy(ln, a + 5, n);
    ln[n] = 0;
    ln_len = n;
    RAMBANK = keep;
    return s;
}

/*---------------------------------------------------------------- nicks */

static unsigned char __fastcall__ rank(unsigned char m)
{
    switch (m) {
    case '~': return 0;
    case '&': return 1;
    case '@': return 2;
    case '%': return 3;
    case '+': return 4;
    }
    return 5;
}

/* (the bank mapped) entry e against mode m, nick s: < 0, 0, > 0 */
static signed char __fastcall__ cmp(const char *e, unsigned char m, const char *s)
{
    unsigned char i, a, b;
    a = rank(e[0]);
    b = rank(m);
    if (a != b)
        return a < b ? -1 : 1;
    for (i = 1; i <= 16; ++i) {
        a = ilower(e[i]);
        b = ilower(*s++);
        if (a != b)
            return a < b ? -1 : 1;
        if (!a)
            break;
    }
    return 0;
}

static unsigned char __fastcall__ same(const char *e, const char *s)
{
    unsigned char i, a;
    for (i = 1; i <= 16; ++i) {
        a = ilower(e[i]);
        if (a != ilower(*s++))
            return 0;
        if (!a)
            return 1;
    }
    return !*s;
}

void __fastcall__ nk_clear(unsigned char w)
{
    unsigned char keep = RAMBANK;
    if (!okw(w))
        return;
    nmap(w);
    P->nicks = P->people = 0;
    memset(ENT, 0, NMAX * NICKLEN);
    RAMBANK = keep;
}

/* (the bank mapped) the first place in the index whose entry is not
   before mode m, nick s */
static unsigned int __fastcall__ lower(unsigned char m, const char *s)
{
    unsigned int lo = 0, hi = P->nicks, mid;
    while (lo < hi) {
        mid = (lo + hi) >> 1;
        if (cmp((char *)IDX[mid], m, s) < 0)
            lo = mid + 1;
        else
            hi = mid;
    }
    return lo;
}

static const char modes[] = "~&@%+ ";  /* (rank's order) */

int __fastcall__ nk_find(unsigned char w, const char *nick)
{
    unsigned char keep = RAMBANK, r;
    unsigned int i;
    char *e;
    if (!okw(w))
        return -1;
    knick(nick);
    nmap(w);
    for (r = 0; r < 6; ++r) {           /* (each mode's run: a binary search) */
        i = lower(modes[r], kn);
        e = (char *)IDX[i];
        if (i < P->nicks && rank(e[0]) == r && same(e, kn)) {
            memcpy(nk, e, NICKLEN);
            nk[NICKLEN] = 0;
            RAMBANK = keep;
            return i;
        }
    }
    RAMBANK = keep;
    return -1;
}

void __fastcall__ nk_get(unsigned char w, unsigned int i)
{
    unsigned char keep = RAMBANK;
    nk[0] = 0;
    if (!okw(w))
        return;
    nmap(w);
    if (i < P->nicks)
        memcpy(nk, (char *)IDX[i], NICKLEN);
    nk[NICKLEN] = 0;
    RAMBANK = keep;
}

/* (the bank mapped) */
static void __fastcall__ unindex(unsigned int i)
{
    unsigned int n = P->nicks;
    if (i >= n)
        return;
    P->nicks = --n;
    ((char *)IDX[i])[0] = 0;
    memmove(&IDX[i], &IDX[i + 1], (n - i) * 2);
}

unsigned char __fastcall__ nk_del(unsigned char w, const char *nick)
{
    unsigned char keep = RAMBANK;
    int i = nk_find(w, nick);
    if (i < 0)
        return 0;
    nmap(w);
    unindex(i);
    RAMBANK = keep;
    dirty |= D_NICKS;
    return 1;
}

unsigned char __fastcall__ nk_add(unsigned char w, const char *nick, unsigned char mode)
{
    unsigned char keep = RAMBANK, r = 1;
    unsigned int lo, n;
    char *e;
    int i;
    if (!okw(w) || !nick[0])
        return 1;
    if (!mode)
        mode = ' ';
    knick(nick);
    nick = kn;
    i = nk_find(w, nick);
    nmap(w);
    if (i >= 0) {
        if (nk[0] == mode)
            goto out;
        unindex(i);
    } else
        r = 2;
    n = P->nicks;
    if (n >= NMAX) {
        r = 0;
        goto out;
    }
    for (e = ENT; e < ENDENT && e[0]; e += NICKLEN)
        ;
    if (e >= ENDENT) {                  /* (V178: every entry taken with fewer than NMAX kept: not trusted) */
        P->nicks = 0;
        memset(ENT, 0, NMAX * NICKLEN);
        r = 0;
        goto out;
    }
    e[0] = mode;
    strncpy(e + 1, nick, 16);
    lo = lower(mode, nick);
    memmove(&IDX[lo + 1], &IDX[lo], (n - lo) * 2);
    IDX[lo] = (unsigned int)e;
    P->nicks = n + 1;
    dirty |= D_NICKS;
out:
    RAMBANK = keep;
    return r;
}

/* (V178) a channel's people: one more (d 1) or one less (-1) */
static void __fastcall__ people(unsigned int *p, signed char d)
{
    if (d > 0 || *p)
        *p += d;
    dirty |= D_STAT | D_NICKS;
}

/* nick joined (NAMES, JOIN): counted unless it was in the list already;
   kept while there is room */
void __fastcall__ nk_join(unsigned char w, const char *nick, unsigned char mode)
{
    if (nk_add(w, nick, mode) != 1)
        people(&W[w].people, 1);
}

/* nick left (PART, KICK: part 1) or quit (0): taken out of the list; one
   not in it counted out too when it left this channel and the list does
   not hold everyone; 1: it was counted out (w: 1 .. WMAX - 1) */
unsigned char __fastcall__ nk_gone(unsigned char w, const char *nick, unsigned char part)
{
    struct win *p = &W[w];
    if (!nk_del(w, nick) && !(part && p->people > p->nicks))
        return 0;
    people(&p->people, -1);
    return 1;
}

/* a mode given or taken (+o: '@', +v: '+' ...); 1: the nick is there */
unsigned char __fastcall__ nk_mode(unsigned char w, const char *nick, unsigned char mode, unsigned char on)
{
    unsigned char m;
    if (nk_find(w, nick) < 0)
        return 0;
    m = nk[0];
    if (on) {
        if (rank(mode) < rank(m))
            m = mode;
    } else if (m == mode)
        m = ' ';
    nk_add(w, nick, m);
    return 1;
}

void __fastcall__ topic_set(unsigned char w, const char *t)
{
    unsigned char keep = RAMBANK;
    if (!w)
        return;
    if (!t)
        t = "";
    nmap(w);
    strncpy(TOPIC, t, TOPICMAX - 1);
    TOPIC[TOPICMAX - 1] = 0;
    RAMBANK = keep;
    dirty |= D_TOPIC;
}

void __fastcall__ topic_get(unsigned char w, char *buf, unsigned int max)
{
    unsigned char keep = RAMBANK;
    buf[0] = 0;
    if (!w)
        return;
    nmap(w);
    strncpy(buf, TOPIC, max - 1);
    buf[max - 1] = 0;
    RAMBANK = keep;
}

/*---------------------------------------------------------------- the input's history */

#define HSLOT(i) ((char *)0xB000 + ((i) & (HISTN - 1)) * 512)

void __fastcall__ hist_add(const char *s)
{
    unsigned char keep = RAMBANK;
    if (!s[0])
        return;
    RAMBANK = hb;
    if (!hist_n || strcmp(HSLOT(htop), s)) {
        htop = (htop + 1) & (HISTN - 1);
        strncpy(HSLOT(htop), s, 511);
        HSLOT(htop)[511] = 0;
        if (hist_n < HISTN)
            ++hist_n;
    }
    RAMBANK = keep;
}

unsigned char __fastcall__ hist_get(unsigned char back, char *buf)
{
    unsigned char keep = RAMBANK;
    if (!back || back > hist_n)
        return 0;
    RAMBANK = hb;
    strncpy(buf, HSLOT(htop - back + 1), INMAX);
    buf[INMAX] = 0;
    RAMBANK = keep;
    return 1;
}
