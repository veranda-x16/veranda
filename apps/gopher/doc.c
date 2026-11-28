/* Veranda Gopher: the document (main RAM; DECISIONS V109).

   The page's bytes as they came, in DOCBANKS RAM banks (64 KB; 48 KB
   before V230: more is cut, and the page says so), and the start of each
   line shown, a word a line, in the bank after them (LINEMAX lines). A
   menu's line is an item (its text, selector, host and port are read
   from it when it is shown or followed; V230: kept shortened); a text's
   lines are wrapped to WRAPW columns as they come (at the last space or
   tab, else where the line is full; a tab to the next multiple of 8). So a line is drawn from its start to the next
   one's, wherever the page is scrolled, and nothing else is kept. The
   history's entries (256 bytes each) are in the bank after that.

   Whatever bank is mapped when these are called is mapped again after
   (overlay 2 calls doc_feed).

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <string.h>
#include <vrcs.h>
#include "gopher.h"

unsigned char doc_bank;
unsigned int doc_len, doc_lines;
unsigned char doc_menu, doc_full, doc_done;
char ln[LNMAX];
struct hent H;

#define IDX(i) ((unsigned int *)0xA000)[i]

static unsigned int ls, sp;             /* the line's start, after its last space (0: none) */
static unsigned char col, spcol;
static unsigned char *wp, wb;           /* where the next byte goes */
static unsigned char u8n, u8l;          /* (V143, doc_text) UTF-8: continuation bytes to come, the bytes so far */
static unsigned char mnet;              /* (V230) the page is from the network (doc_text): its menu kept short */

/* offset o's bank (into RAMBANK) and address */
static unsigned char *__fastcall__ at(unsigned int o)
{
    RAMBANK = doc_bank + ((unsigned char)(o >> 8) >> 5);
    return (unsigned char *)(0xA000 + (o & 0x1FFF));
}

static unsigned int __fastcall__ start(unsigned int i)
{
    unsigned int s;
    unsigned char keep = RAMBANK;
    RAMBANK = doc_bank + DOCBANKS;
    s = IDX(i);
    RAMBANK = keep;
    return s;
}

/* (RAMBANK is the starts' bank) */
static unsigned char __fastcall__ newline(unsigned int s)
{
    if (doc_lines >= LINEMAX) {
        doc_full = 1;
        return 0;
    }
    IDX(doc_lines) = s;
    ++doc_lines;
    ls = s;
    sp = 0;
    return 1;
}

void __fastcall__ doc_clear(unsigned char menu)
{
    unsigned char keep = RAMBANK;
    doc_menu = menu;
    doc_len = 0;
    doc_lines = 0;
    doc_full = doc_done = 0;
    col = u8n = mnet = 0;
    wb = doc_bank;
    wp = (unsigned char *)0xA000;
    RAMBANK = doc_bank + DOCBANKS;
    newline(0);
    RAMBANK = keep;
}

/* one byte into the document; 0: it is full */
static unsigned char __fastcall__ put1(unsigned char c)
{
    unsigned char nc;
    unsigned int o;
    if (doc_len >= DOCMAX) {
        doc_full = 1;
        return 0;
    }
    o = doc_len++;
    RAMBANK = wb;
    *wp = c;
    if (++wp == (unsigned char *)0xC000) {
        wp = (unsigned char *)0xA000;
        ++wb;
    }
    RAMBANK = doc_bank + DOCBANKS;
    if (c == '\n') {
        col = 0;
        return newline(o + 1);
    }
    if (c == '\r' || doc_menu)
        return 1;
    nc = c == '\t' ? (col | 7) + 1 : col + 1;
    if (nc > WRAPW) {
        if (sp > ls) {
            col -= spcol;
            if (!newline(sp))
                return 0;
        } else {
            col = 0;
            if (!newline(o))
                return 0;
        }
        nc = c == '\t' ? (col | 7) + 1 : col + 1;
        if (nc > WRAPW)
            nc = WRAPW;
    }
    col = nc;
    if (c == ' ' || c == '\t') {
        sp = o + 1;
        spcol = col;
    }
    return 1;
}

/* bytes kept as they are (the bookmarks' page: Veranda's set already) */
unsigned char __fastcall__ doc_feed(const unsigned char *b, unsigned int n)
{
    unsigned char keep = RAMBANK;
    if (!doc_full)
        while (n-- && put1(*b++))
            ;
    RAMBANK = keep;
    return !doc_full;
}

/*---------------------------------------------------------------- (V230) a menu's lines kept short */

/* A menu from the network is kept shortened, a line at a time: its
   line goes in as it comes; at its end (its LF, or the page's end: a
   server that sends no "." line) it is read back into ln, shortened
   there by ui.c's mshort (overlay 1: main RAM's room) and written again
   over itself. gopher.quux.org's Usenet groups are lists of hundreds of
   articles at some 118 bytes a line, 60 of them its host, its port, its
   Gopher+ field and the group's own selector: NET.general's 995 (117
   KB) were cut at the 426th; kept short they take some 61 bytes a line.
   A line longer than ln is kept as it came. */
unsigned char __fastcall__ mshort(unsigned char n);     /* (ui.c) */
unsigned char __fastcall__ doc_copy(unsigned char count);   /* (copy.s) */
extern unsigned char *doc_src;

static unsigned char mend(void)
{
    unsigned int o = ls;
    unsigned char n;
    if (!mnet || doc_full || doc_len - o > LNMAX - 1 || doc_len == o)
        return 1;
    doc_src = at(o);
    n = doc_copy(doc_len - o);          /* (the line into ln) */
    RAMBANK = appBank;
    n = mshort(n);
    doc_len = o;                        /* (written again over itself) */
    wp = at(o);
    wb = RAMBANK;
    for (o = 0; o < n; ++o)
        if (!put1(ln[o]))
            return 0;
    return 1;
}

/* a byte of a page's text */
static unsigned char __fastcall__ mput(unsigned char c)
{
    if (doc_menu && c == '\n' && !mend())
        return 0;
    return put1(c);
}

/*---------------------------------------------------------------- (V143) a page's text */

/* A server's text into Veranda's set (ISO-8859-16): UTF-8 decoded; a
   byte that is not UTF-8 (and a sequence cut short) taken as Latin-1;
   typographic quotes, dashes and the ellipsis made plain; box lines,
   blocks and shades to the font's private glyphs; what the set lacks '?'
   (a page in CP437 is no longer shown as CP437) */
static unsigned char u8b[4];
static unsigned int u8;

/* the private glyphs' code points ($80-$9F: CP437's pi, square, root,
   shades, blocks and box lines; copy.s's cs_font) */
static const unsigned int pv[32] = {
    0x03C0, 0x25A0, 0x221A, 0x2591, 0x2592, 0x2593, 0x2502, 0x2524,
    0x2510, 0x2514, 0x2534, 0x252C, 0x251C, 0x2500, 0x253C, 0x2518,
    0x250C, 0x2588, 0x2584, 0x258C, 0x2590, 0x2580, 0x2551, 0x2550,
    0x2554, 0x2557, 0x255A, 0x255D, 0x2560, 0x2563, 0x2566, 0x2569
};

static unsigned char __fastcall__ cpt(unsigned int u)
{
    unsigned char c;
    for (c = 0; c < 32; ++c)
        if (pv[c] == u)
            return 0x80 + c;
    if (u == 0x2018 || u == 0x2019)
        return 39;
    if (u == 0x201C || u == 0x201D || u == 0x201E)
        return '"';
    if (u == 0x2013 || u == 0x2014)
        return '-';
    if (u == 0x2026)
        return '.';
    return (c = cs_byte(u)) != 0 ? c : '?';
}

static unsigned char __fastcall__ latin(unsigned char c)
{
    return c < 0xA0 ? '?' : cpt(c);
}

unsigned char __fastcall__ doc_text(const unsigned char *b, unsigned int n)
{
    unsigned char keep = RAMBANK, c, i, ok = 1;
    mnet = 1;
    if (doc_full)
        return 0;
    while (n-- && ok) {
        c = *b++;
        if (u8n) {
            if ((c & 0xC0) == 0x80) {
                u8b[u8l++] = c;
                u8 = u8 << 6 | (c & 0x3F);
                if (!--u8n)
                    ok = mput(u8l == 4 || u8 < 0x80 ? '?' : cpt(u8));
                continue;
            }
            for (i = 0; i < u8l && ok; ++i)     /* (not UTF-8: Latin-1) */
                ok = mput(latin(u8b[i]));
            u8n = 0;
        }
        if (!ok)
            break;
        if (c < 0x80)
            ok = mput(c);
        else if (c >= 0xC2 && c < 0xF5) {
            u8b[0] = c;
            u8l = 1;
            u8n = c < 0xE0 ? 1 : c < 0xF0 ? 2 : 3;
            u8 = c & (c < 0xE0 ? 0x1F : 0x0F);
        } else
            ok = mput(latin(c));
    }
    RAMBANK = keep;
    return !doc_full;
}

/* line i's bytes into ln */
unsigned char __fastcall__ doc_line(unsigned int i)
{
    unsigned char keep = RAMBANK, n;
    unsigned int o, e;
    ln[0] = 0;
    if (i >= doc_lines)
        return 0;
    o = start(i);
    e = i + 1 < doc_lines ? start(i + 1) : doc_len;
    if (e - o > LNMAX - 1)
        e = o + LNMAX - 1;
    doc_src = at(o);
    n = doc_copy(e - o);
    RAMBANK = keep;
    return n;
}

unsigned char __fastcall__ doc_type(unsigned int i)
{
    unsigned char keep = RAMBANK, c;
    unsigned int o;
    if (i >= doc_lines)
        return 0;
    o = start(i);
    if (o >= doc_len)
        return 0;
    c = *at(o);
    RAMBANK = keep;
    return c;
}

/* the end: the last line's empty rest and Gopher's "." line dropped */
void doc_end(void)
{
    unsigned char keep = RAMBANK;
    if (doc_menu && !doc_done)         /* (V230) a menu's last line without its LF (no "." line) */
        mend();
    RAMBANK = keep;
    if (doc_lines && start(doc_lines - 1) >= doc_len)
        --doc_lines;
    if (doc_lines && doc_line(doc_lines - 1) == 1 && ln[0] == '.')
        --doc_lines;
    doc_done = 1;
}

/*---------------------------------------------------------------- the history */

void __fastcall__ hist_get(unsigned char i, struct hent *e)
{
    BankCopy((void *)(0xA000 + 256 * i), e, sizeof *e, doc_bank + DOCBANKS + 1, 0);
}

void __fastcall__ hist_put(unsigned char i, const struct hent *e)
{
    BankCopy((void *)e, (void *)(0xA000 + 256 * i), sizeof *e, 0, doc_bank + DOCBANKS + 1);
}

void hist_shift(void)
{
    unsigned char b = doc_bank + DOCBANKS + 1;
    BankCopy((void *)0xA100, (void *)0xA000, 256 * (HISTMAX - 1), b, b);
}
