/* gate edit: the gap buffer (textkit's buf.s, text.c: sdk/lib/textkit)
   under random
   edits, against tests/check_edit_buf.py's copy of the same edits on a
   Python string. The text ends at about 60 KB (eight banks and more, the
   gap moved across them many times); then it is written out in its three
   line-end forms, read back from two of them, and the line, column and
   find calls are logged. MIT licence (see LICENSE). */
#include <veranda.h>
#include <string.h>
#include "tkapp.h"

static unsigned int x = 0x1D35;
static unsigned int rnd(void)
{
    x ^= x << 7;
    x ^= x >> 9;
    x ^= x << 8;
    return x;
}
static unsigned long rnd32(void)
{
    unsigned long h = rnd();
    return (h << 16) | rnd();
}

static unsigned char buf[3000];
static char line[96];
static const char hex[] = "0123456789ABCDEF";

static void logn(const char *what, unsigned long v)
{
    unsigned char n = 0, i;
    while (*what)
        line[n++] = *what++;
    line[n++] = ' ';
    for (i = 8; i-- > 0;)
        line[n++] = hex[(v >> (i * 4)) & 15];
    line[n] = 0;
    LogText(line);
}

static void save(const char *name, unsigned char mode)
{
    unsigned char h = FOpen((void *)name, 'w');
    unsigned int n;
    gb_mode = mode;
    gb_a = 0;
    for (;;) {
        gb_lp = buf;
        gb_n = 1024;
        n = gb_export();
        if (!n)
            break;
        FWrite(h, buf, n);
    }
    FClose(h);
}

static void load(const char *name, unsigned char mode)
{
    unsigned char h = FOpen((void *)name, 'r');
    unsigned int n;
    tx_new(70000UL, 1);
    gb_mode = mode;
    gb_crst = 0;
    gb_r = 0;
    while ((n = FRead(h, buf, 1024)) != 0) {
        if (tx_tail(n))
            LogText("BUF NO ROOM");
        gb_lp = buf;
        gb_n = n;
        gb_append();
    }
    tx_tail(1);
    gb_flush();
    FClose(h);
    logn("BUF LOADLF", gb_r);
}

int main(void)
{
    unsigned int i, k, j, op;
    unsigned long pos, len;
    if (tx_new(0, 0)) {
        LogText("BUF NO MEMORY");
        return 0;
    }
    for (i = 0; i < 700; ++i) {
        op = rnd() & 15;
        len = gb_len;
        if (op <= 6) {
            k = op == 6 ? rnd() % 3000 + 1 : rnd() % 200 + 1;
            pos = rnd32() % (len + 1);
            for (j = 0; j < k; ++j)
                buf[j] = (rnd() & 31) == 0 ? 10 : 'a' + (i + j) % 26;
            if (tx_insert(pos, buf, k))
                LogText("BUF FULL");
        } else if (op <= 9) {
            pos = rnd32() % (len + 1);
            k = rnd() % 300;
            if (pos + k > len)
                k = (unsigned int)(len - pos);
            tx_delete(pos, k);
        } else if (op <= 11) {
            gb_a = rnd32() % (len + 1);
            gb_moveto();
        } else {
            buf[0] = 'A' + (op & 7);
            tx_insert(gb_gs, buf, 1);
        }
    }
    logn("BUF LEN", gb_len);
    logn("BUF BANKS", gb_nb);
    logn("BUF GS", gb_gs);
    gb_a = 0;
    gb_b = gb_len;
    gb_count();
    logn("BUF LFS", gb_r);
    gb_a = 0;
    gb_n = 10;
    gb_fwd_lines();
    logn("BUF LINE10", gb_a);
    gb_a = gb_len / 2;
    gb_line_start();
    logn("BUF MIDSTART", gb_a);
    gb_b = gb_len / 2;
    logn("BUF MIDCOL", gb_col());
    gb_n = 5;
    gb_at_col();
    logn("BUF ATCOL5", gb_a);
    for (i = 0; i < 256; ++i)
        gb_ftab[i] = i;
    memcpy(gb_pat, "xyz", 3);
    gb_plen = 3;
    gb_a = 0;
    gb_find();
    logn("BUF FINDXYZ", gb_a);
    memcpy(gb_pat, "AB", 2);
    gb_plen = 2;
    gb_a = 100;
    gb_find();
    logn("BUF FINDAB", gb_a);
    gb_a = 0;
    gb_hs = 0;
    gb_mk[0] = 3;
    gb_mk[1] = 0;
    gb_mk[2] = NOWHERE;
    gb_render();
    for (i = 0; i < 79; ++i)
        if (gb_line[i] < 32)
            gb_line[i] = '.';
    memcpy(line, "BUF ROW0 ", 9);
    memcpy(line + 9, gb_line, 79);
    line[88] = 0;
    LogText(line);
    logn("BUF ROW0NEXT", gb_a);
    logn("BUF ROW0MK0", gb_mkc[0]);
    save("BUF.OUT", 0);
    save("BUF.CRLF", 1);
    save("BUF.CR", 2);
    load("BUF.CRLF", 1);
    save("BUF.RT1", 0);
    load("BUF.CR", 2);
    save("BUF.RT2", 0);
    LogText("BUF DONE");
    asm("jmp $FFFF");
    return 0;
}
