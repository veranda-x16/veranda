/* Veranda Gemini: the document (main RAM; DECISIONS V118).

   The page's text as it comes, decoded (UTF-8, or ISO-8859-1) and folded
   to the X16's CP437 font as it is stored (Veranda Claude's folding:
   typographic quotes, dashes, spaces to plain forms, what CP437 has to its
   byte, accented letters it lacks to the letter, else '?'; carriage
   returns dropped), in DOCBANKS RAM banks (32 KB: more is cut, and the
   page says so); and the rows shown, in the bank after them: each row's
   start (2 bytes) and its kind (1 byte), LINEMAX rows.

   gemtext's lines are read as they come, a character at a time: a line's
   first characters say its kind ("=>" a link, "#", "##", "###" headings,
   "* " a list item, ">" a quote, "```" the preformatted toggle; anything
   else a paragraph), its first row starts where its text does (after
   the prefix and spaces; a link's at its label, or at its URL when it has
   none), and a paragraph, a heading, a list item, a quote or a link's
   label is wrapped to GEMW columns at its last space (a longer word cut)
   into rows marked K_CONT. A preformatted line is one row (cut where the
   window ends); the toggle's lines are not shown. A link's kind carries
   what its URL is (gemini, the web, gopher, mail, a picture, another
   scheme) for its badge. A plain text's lines are wrapped to PLAINW
   columns as Veranda Gopher's texts. So a row is drawn from its start to
   the next row's (or its line's end) wherever the page is scrolled, and
   nothing else is kept.

   The history's entries are in the bank after the rows (the font's: its
   tables at $B000, the CP437 table at $BA00), the page cache's CACHES
   banks after it: a page each (its URL, its length and kind, its stored
   text, at most CACHEMAX bytes), for Back and Forward.

   Whatever bank is mapped when these are called is mapped again after.

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <string.h>
#include "gemini.h"
#pragma static-locals (on)       /* (a character's way through here: locals not on the C stack) */

unsigned char doc_bank;
unsigned int doc_len, doc_lines, ulo;
unsigned char doc_mode, doc_full, doc_done;
char ln[LNMAX];
struct hent H;

#define RB   (doc_bank + DOCBANKS)              /* the rows' bank */
#define FB   (doc_bank + DOCBANKS + 1)          /* the history's and the font's */
unsigned char cbank[CACHES];            /* the cache's banks (main.c: one allocated, the overlays' two spare ones; V125) */
#define OFFS ((unsigned int *)0xA000)
#define KINDS ((unsigned char *)(0xA000 + 2 * LINEMAX))
#define CPT  ((unsigned int *)0xBA00)           /* the CP437 table (url.c's u_load) */

/* the parser's state */
#define P_START 0               /* a line's first characters */
#define P_WS    1               /* the spaces after its prefix */
#define P_URL   2               /* a link's URL */
#define P_WS2   3               /* the spaces after it */
#define P_BODY  4               /* the text, wrapped */
#define P_NONE  5               /* nothing more to count (a preformatted line, a toggle) */

static unsigned char *wp, wb;           /* where the next byte goes */
static unsigned char dec, u8n, st, np, pf[3], pre, fence, rk, col, spcol, ww;
static unsigned long u8;
static unsigned int lstart, rs, sp, uo;
static unsigned int po;                 /* the character's offset (wrapc's and body's: no argument
                                           on the C stack for each character) */
static unsigned char un, ucolon, uslash;        /* the URL: its length so far, its scheme's */
static char uh[8], ut[4];                       /* its first characters, its last four */

static unsigned char *__fastcall__ at(unsigned int o)
{
    RAMBANK = doc_bank + ((unsigned char)(o >> 8) >> 5);
    return (unsigned char *)(0xA000 + (o & 0x1FFF));
}

/*---------------------------------------------------------------- rows */

static void __fastcall__ newrow(unsigned int o, unsigned char k)
{
    unsigned char keep = RAMBANK;
    if (doc_lines >= LINEMAX) {
        doc_full = 1;
        return;
    }
    RAMBANK = RB;
    OFFS[doc_lines] = o;
    KINDS[doc_lines] = k;
    RAMBANK = keep;
    ++doc_lines;
    rs = o;
    sp = 0;
}

/* character c at po in a row being wrapped (ww columns) */
static void __fastcall__ wrapc(unsigned char c)
{
    unsigned char tab = c == '\t' && doc_mode == M_PLAIN, nc;
    nc = tab ? (col | 7) + 1 : col + 1;
    if (nc > ww) {
        if (sp > rs) {
            col -= spcol;
            newrow(sp, rk | K_CONT);
        } else {
            col = 0;
            newrow(po, rk | K_CONT);
        }
        nc = tab ? (col | 7) + 1 : col + 1;
        if (nc > ww)
            nc = ww;
    }
    col = nc;
    if (c == ' ' || c == '\t') {
        sp = po + 1;
        spcol = col;
    }
}

static void __fastcall__ first(unsigned int o, unsigned char k)
{
    newrow(o, k);
    col = 0;
    st = P_BODY;
}

/*---------------------------------------------------------------- a link's URL */

static void __fastcall__ url_c(unsigned char c)
{
    if (c >= 'A' && c <= 'Z')
        c += 32;
    if (un < sizeof uh - 1)
        uh[un] = c;
    ++un;
    if (c == ':' && !uslash && !ucolon)
        ucolon = un;                    /* (its scheme's length + 1) */
    else if (c == '?' || c == '#')
        uslash = 2;                     /* (V138: past the path: its last four are kept, as
                                           Gemipedia's /media/media.png?<Wikimedia's address>) */
    else if (c == '/' && !uslash)
        uslash = 1;
    if (uslash != 2) {
        ut[0] = ut[1];
        ut[1] = ut[2];
        ut[2] = ut[3];
        ut[3] = c;
    }
}

static const char *const schemes[] = { "gemini:", "http:", "https:", "gopher:", "mailto:" };
static const unsigned char skind[] = { LK_GEM, LK_WEB, LK_WEB, LK_GOPHER, LK_MAIL };
static const char *const pics[] = { ".png", ".jpg", "jpeg", ".gif", ".bmp" };

/* the link's kind, its URL read: K_LINK and what it leads to */
static unsigned char url_kind(void)
{
    unsigned char i, k = LK_GEM;
    if (ucolon) {
        k = LK_OTHER;
        uh[sizeof uh - 1] = 0;
        for (i = 0; i < sizeof skind; ++i)
            if (strlen(schemes[i]) == ucolon && !memcmp(uh, schemes[i], ucolon))
                k = skind[i];
    }
    if (k == LK_GEM && un >= 4)
        for (i = 0; i < 5; ++i)
            if (!memcmp(ut, pics[i], 4))
                k = LK_PIC;
    return K_LINK | (k << 4);
}

/*---------------------------------------------------------------- gemtext */

static void __fastcall__ body(unsigned char c)
{
    unsigned char s;
    if (st == P_BODY) {
        wrapc(c);
        return;
    }
    s = c == ' ' || c == '\t';
    switch (st) {
    case P_WS:
        if (s)
            return;
        if (rk == K_LINK) {
            st = P_URL;
            uo = po;
            un = ucolon = uslash = 0;
            memset(ut, 0, sizeof ut);
            url_c(c);
            return;
        }
        first(po, rk);
        break;
    case P_URL:
        if (!s) {
            url_c(c);
            return;
        }
        rk = url_kind();
        st = P_WS2;
        return;
    case P_WS2:
        if (s)
            return;
        first(po, rk);
        break;
    default:
        return;
    }
    wrapc(c);
}

/* the line's first characters (pf, np of them) seen: its kind (fin: the
   line ended); nothing yet if they could still be a prefix */
static void __fastcall__ decide(unsigned char fin)
{
    unsigned char k = K_TEXT, b = 0, n = 0, c0 = pf[0], i;
    while (n < np && pf[n] == '`')
        ++n;
    if (!np) {
        newrow(lstart, pre ? K_PRE : K_TEXT);
        st = P_NONE;
        return;
    }
    if (c0 == '`' && n == np && np < 3 && !fin)
        return;
    if (n >= 3) {                       /* the toggle */
        fence = 1;
        st = P_NONE;
        return;
    }
    if (pre) {
        newrow(lstart, K_PRE);
        st = P_NONE;
        return;
    }
    if (c0 == '=' || c0 == '*') {
        if (np < 2 && !fin)
            return;
        if (np >= 2 && pf[1] == (c0 == '=' ? '>' : ' ')) {
            k = c0 == '=' ? K_LINK : K_LIST;
            b = 2;
        }
    } else if (c0 == '#') {
        while (b < np && pf[b] == '#')
            ++b;
        if (b == np && np < 3 && !fin)
            return;
        k = K_H1 - 1 + b;
    } else if (c0 == '>') {
        k = K_QUOTE;
        b = 1;
    }
    rk = k;
    ww = GEMW;
    if (k == K_TEXT)
        first(lstart, K_TEXT);
    else
        st = P_WS;
    for (i = b; i < np; ++i) {
        po = lstart + i;
        body(pf[i]);
    }
}

static void __fastcall__ eol(unsigned int o)
{
    if (st == P_START)
        decide(1);
    if (st == P_WS) {
        if (rk == K_LINK)
            newrow(lstart, K_TEXT);     /* ("=>" alone: shown as it is) */
        else
            newrow(o, rk);              /* (a heading, an item, a quote with no text) */
    } else if (st == P_URL || st == P_WS2) {
        if (st == P_URL)
            rk = url_kind();
        newrow(uo, rk);                 /* (a link with no label: its URL shown) */
    }
    if (fence) {
        pre = !pre;
        fence = 0;
    }
    st = P_START;
    np = 0;
    lstart = o + 1;
}

/* a CP437 character for the page */
static void __fastcall__ putc_(unsigned char c)
{
    if (doc_full)
        return;
    if (doc_len >= DOCMAX) {
        doc_full = 1;
        return;
    }
    po = doc_len++;
    RAMBANK = wb;
    *wp = c;
    if (++wp == (unsigned char *)0xC000) {
        wp = (unsigned char *)0xA000;
        ++wb;
    }
    if (c == '\n') {
        if (doc_mode == M_PLAIN) {
            col = 0;
            newrow(po + 1, K_PLAIN);
        } else
            eol(po);
    } else if (doc_mode == M_PLAIN)
        wrapc(c);
    else if (st == P_START) {
        pf[np++] = c;
        decide(0);
    } else
        body(c);
}

static void __fastcall__ puts_(const char *s)
{
    while (*s)
        putc_(*s++);
}

/*---------------------------------------------------------------- Unicode to CP437 (Veranda Claude's) */

/* Latin-1 and Latin Extended-A letters without their accents (U+00C0-017F) */
static const char fold[] =
    "AAAAAAACEEEEIIIIDNOOOOOxOUUUUYPsaaaaaaaceeeeiiiidnooooo/ouuuuypy"
    "AaAaAaCcCcCcCcDdDdEeEeEeEeEeGgGgGgGgHhHhIiIiIiIiIiIiJjKkkLlLlLlLlLlNnNnNnnNnOoOoOoOoRrRrRrSsSsSsSsTtTtTtUuUuUuUuUuUuWwYyYZzZzZzs";

/* the code points written as short ASCII (quotes, dashes, spaces,
   bullets, checks, arrows, a few emoji: V124), in the font's bank at
   $BC00 (web.c's w_load copies them there): 5 bytes each, the code point
   (an emoji U+1Fxxx as U+Exxx) and up to 3 characters; a code point 0
   ends them. *p: puts_'s copy (doc.c's locals are static) */
#define SPT ((unsigned char *)0xBC00)

static unsigned char __fastcall__ special(unsigned int v)
{
    static char s[4];
    unsigned char *p = SPT, keep = RAMBANK;
    RAMBANK = FB;
    for (; p[0] | p[1]; p += 5)
        if (*(unsigned int *)p == v) {
            memcpy(s, p + 2, 3);
            RAMBANK = keep;
            puts_(s);
            return 1;
        }
    RAMBANK = keep;
    return 0;
}

/* code point u's CP437 byte from the table, 0 none */
static unsigned char __fastcall__ cp_of(unsigned int u)
{
    unsigned char i = 128, keep = RAMBANK;
    RAMBANK = FB;
    do {
        if (CPT[i] == u)
            break;
    } while (++i);
    RAMBANK = keep;
    return i;
}

static void __fastcall__ cp(unsigned long u)
{
    unsigned int v;
    unsigned char c;
    if (u > 0xFFFF) {
        if ((u >> 12) == 0x1F && special(0xE000 | ((unsigned int)u & 0xFFF)))
            return;                     /* (an emoji the table knows) */
        putc_('?');
        return;
    }
    v = u;
    if (v < 128) {
        if (v == '\n' || v == '\t' || (v >= 32 && v < 127))
            putc_(v);
        return;                         /* (other control characters dropped, CR among them) */
    }
    if (special(v))
        return;
    if (v >= 0x2000 && v <= 0x200A) {
        putc_(' ');
        return;
    }
    c = cp_of(v);
    if (c) {
        putc_(c);
        return;
    }
    if (v >= 0xC0 && v < 0x180) {
        putc_(fold[v - 0xC0]);
        return;
    }
    putc_('?');
}

static void __fastcall__ byte(unsigned char c)
{
    if (dec == D_RAW) {
        putc_(c);
        return;
    }
    if (c < 0x80 && !u8n) {             /* (ASCII: most of it, quickly) */
        if (c >= 32 ? c < 127 : c == '\n' || c == '\t')
            putc_(c);
        return;
    }
    if (dec == D_LATIN1) {
        cp(c);
        return;
    }
    if (u8n) {
        if ((c & 0xC0) == 0x80) {
            u8 = (u8 << 6) | (c & 0x3F);
            if (!--u8n)
                cp(u8);
            return;
        }
        u8n = 0;
        putc_('?');
    }
    if (c < 0x80)
        cp(c);
    else if ((c & 0xE0) == 0xC0) {
        u8 = c & 0x1F;
        u8n = 1;
    } else if ((c & 0xF0) == 0xE0) {
        u8 = c & 0x0F;
        u8n = 2;
    } else if ((c & 0xF8) == 0xF0) {
        u8 = c & 0x07;
        u8n = 3;
    } else
        putc_('?');
}

/*---------------------------------------------------------------- the document */

void __fastcall__ doc_clear(unsigned char mode, unsigned char d)
{
    doc_mode = mode;
    dec = d;
    doc_len = doc_lines = 0;
    doc_full = doc_done = 0;
    u8n = col = np = pre = fence = 0;
    st = P_START;
    lstart = 0;
    rk = K_PLAIN;
    ww = PLAINW;
    wb = doc_bank;
    wp = (unsigned char *)0xA000;
    if (mode == M_PLAIN)
        newrow(0, K_PLAIN);
}

unsigned char __fastcall__ doc_feed(const unsigned char *b, unsigned int n)
{
    unsigned char keep = RAMBANK;
    while (n-- && !doc_full)
        byte(*b++);
    RAMBANK = keep;
    return !doc_full;
}

static unsigned int __fastcall__ start(unsigned int i);

/* the end: an unfinished last line ended, the empty row after a plain
   text's last line dropped */
void doc_end(void)
{
    unsigned char keep = RAMBANK;
    if (doc_mode == M_GEM) {
        if (!doc_full && (st != P_START || np))
            eol(doc_len);
    } else if (doc_lines && start(doc_lines - 1) >= doc_len)
        --doc_lines;
    RAMBANK = keep;
    doc_done = 1;
}

unsigned char __fastcall__ doc_copy(unsigned char count);   /* (copy.s) */
extern unsigned char *doc_src;

static unsigned int __fastcall__ start(unsigned int i)
{
    unsigned int s;
    unsigned char keep = RAMBANK;
    RAMBANK = RB;
    s = OFFS[i];
    RAMBANK = keep;
    return s;
}

unsigned char __fastcall__ doc_kind(unsigned int i)
{
    unsigned char k, keep = RAMBANK;
    if (i >= doc_lines)
        return 0xFF;
    RAMBANK = RB;
    k = KINDS[i];
    RAMBANK = keep;
    return k;
}

unsigned char __fastcall__ doc_line(unsigned int i)
{
    unsigned char keep = RAMBANK, n;
    unsigned int o, e;
    ln[0] = 0;
    if (i >= doc_lines)
        return 0;
    o = start(i);
    e = i + 1 < doc_lines ? start(i + 1) : doc_len;
    if (e <= o)
        e = doc_len;
    if (e > doc_len)
        e = doc_len;
    if (e - o > LNMAX - 1)
        e = o + LNMAX - 1;
    if (e <= o)
        return 0;
    doc_src = at(o);
    n = doc_copy(e - o);
    RAMBANK = keep;
    return n;
}

unsigned int __fastcall__ link_head(unsigned int i)
{
    while (i && (doc_kind(i) & K_CONT))
        --i;
    return i;
}

/* link row i's URL into rel (its line read from its start: "=>", spaces,
   the URL); 0: not a link. (V138) A URL of URLMAX - 1 characters or more
   (Gemipedia's pictures: a Wikimedia address percent-encoded in the
   query) is cut to its first ULCUT in rel, and the request gets the rest
   from the page (copy.s's doc_tail, g_start's; ulo: the rest's place on
   the page, 0 none) */

unsigned char __fastcall__ doc_url(unsigned int i)
{
    unsigned char keep = RAMBANK, n = 0, c;
    unsigned int o;
    rel[0] = 0;
    ulo = 0;
    if ((doc_kind(i) & K_TYPE) != K_LINK)
        return 0;
    o = start(link_head(i));
    while (o && *at(o - 1) != '\n')
        --o;
    o += 2;                             /* ("=>") */
    while (o < doc_len && ((c = *at(o)) == ' ' || c == '\t'))
        ++o;
    while (o < doc_len && (c = *at(o)) != ' ' && c != '\t' && c != '\n') {
        if (n == URLMAX - 1) {
            ulo = o - (URLMAX - 1 - ULCUT);
            n = ULCUT;
            break;
        }
        rel[n++] = c;
        ++o;
    }
    rel[n] = 0;
    RAMBANK = keep;
    return n != 0;
}

/*---------------------------------------------------------------- the history */

void __fastcall__ hist_get(unsigned char i, struct hent *e)
{
    BankCopy((void *)(0xA000 + sizeof(struct hent) * i), e, sizeof *e, FB, 0);
}

void __fastcall__ hist_put(unsigned char i, const struct hent *e)
{
    BankCopy((void *)e, (void *)(0xA000 + sizeof(struct hent) * i), sizeof *e, 0, FB);
}

void hist_shift(void)
{
    BankCopy((void *)(0xA000 + sizeof(struct hent)), (void *)0xA000, sizeof(struct hent) * (HISTMAX - 1), FB, FB);
}

/*---------------------------------------------------------------- the page cache */

#define C_LEN  (*(unsigned int *)0xA100)
#define C_MODE (*(unsigned char *)0xA102)
#define C_BODY ((unsigned char *)0xA110)
static unsigned char cnext;

/* go's slot, or 0xFF */
static unsigned char find(void)
{
    unsigned char i, keep = RAMBANK, f = 0xFF;
    for (i = 0; i < CACHES; ++i) {
        RAMBANK = cbank[i];
        if (C_LEN && !strcmp((char *)0xA000, go)) {
            f = i;
            break;
        }
    }
    RAMBANK = keep;
    return f;
}

void cache_put(void)
{
    unsigned char s, keep = RAMBANK;
    strcpy(go, cur);
    if (!cur[0] || doc_full || doc_len > CACHEMAX)
        return;
    s = find();
    if (s == 0xFF) {
        s = cnext;
        cnext = (cnext + 1) % CACHES;
    }
    RAMBANK = cbank[s];
    strcpy((char *)0xA000, cur);
    C_LEN = doc_len;
    C_MODE = doc_mode;
    RAMBANK = keep;
    BankCopy((void *)0xA000, C_BODY, doc_len, doc_bank, cbank[s]);
}

void cache_drop(void)
{
    unsigned char s = find(), keep = RAMBANK;
    if (s == 0xFF)
        return;
    RAMBANK = cbank[s];
    C_LEN = 0;
    RAMBANK = keep;
}

static unsigned char cslot;

/* go's page kept? (gtext its kind) */
unsigned char cache_has(void)
{
    unsigned char keep = RAMBANK;
    cslot = find();
    if (cslot == 0xFF)
        return 0;
    RAMBANK = cbank[cslot];
    gtext = C_MODE;
    RAMBANK = keep;
    return 1;
}

/* (after cache_has) its text into the document */
void cache_fill(void)
{
    unsigned char keep = RAMBANK;
    unsigned int n, o, k;
    static unsigned char b[128];
    RAMBANK = cbank[cslot];
    n = C_LEN;
    RAMBANK = keep;
    doc_clear(gtext, D_RAW);
    for (o = 0; o < n; o += k) {
        k = n - o > sizeof b ? sizeof b : n - o;
        BankCopy(C_BODY + o, b, k, cbank[cslot], 0);
        doc_feed(b, k);
    }
}

/*---------------------------------------------------------------- a row as shown */

static const char cut[] = "--- Cut here: longer than 32 KB (File > Download saves all of it) ---";

/* row i into row (cards 1-76; 0-terminated; no control characters): a
   gemtext row's text at card 4 (a list item's bullet, a quote's bar at
   card 2), a preformatted or plain row's at card 1, its tabs to columns
   of 8; its kind, 0xFF past the end */
unsigned char __fastcall__ render(unsigned int i)
{
    unsigned char n, k, t, c, col, j, raw;
    memset(row, ' ', ROWW);
    row[ROWW] = 0;
    if (i >= doc_lines) {
        if (i == doc_lines + 1 && doc_full && doc_done)
            memcpy(row, cut, sizeof cut - 1);
        return 0xFF;
    }
    k = doc_kind(i);
    t = k & K_TYPE;
    n = doc_line(i);
    raw = t == K_PRE || t == K_PLAIN;
    col = raw ? 0 : 3;
    if (t == K_LIST && !(k & K_CONT))
        row[1] = 7;
    else if (t == K_QUOTE)
        row[1] = 0xB3;
    for (j = 0; j < n && col < ROWW; ++j) {
        c = ln[j];
        if (c == '\t' && raw) {
            col = (col | 7) + 1;
            continue;
        }
        row[col++] = c < 32 ? (c == '\t' ? ' ' : '?') : c;
    }
    if (k == (K_LINK | (LK_PIC << 4)) && col < ROWW - 12 && (i + 1 >= doc_lines || !(doc_kind(i + 1) & K_CONT)))
        memcpy(row + col + 1, "[Show image]", 12);     /* (a picture link's one row: V125) */
    return k;
}
