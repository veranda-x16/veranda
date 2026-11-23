/* textkit (Veranda Edit): UTF-8 files (DECISIONS V143), for a program that
   defines TK_UTF8 (main RAM). The text in the buffer is Veranda's set,
   ISO-8859-16 (V140; the SDK's vrcs.h converts). doc_load (file.c) tries a
   file as UTF-8 first: each piece read is decoded in place (it only
   shrinks); a byte that breaks UTF-8, a character the set lacks (or
   U+FFFD, or one past U+FFFF) makes u8_bad and doc_load reads the file
   again byte by byte (tk_enc 0), so nothing is lost; a file read whole as
   UTF-8 (plain ASCII too) is saved as UTF-8 again, which gives back the
   same bytes when nothing changed. doc_save asks gb_export for at most a
   third of iobuf (a byte of the set is at most 3 of UTF-8) and u8_out
   encodes it in place from the end.

   MIT licence (see LICENSE). */
#include <vrcs.h>
#include "tkapp.h"

unsigned char tk_enc = 1;
unsigned char u8_bad;
static unsigned char pend, raw;

void __fastcall__ u8_start(unsigned char r)
{
    raw = r;
    pend = u8_bad = 0;
    cs_dec_reset();
}

unsigned int __fastcall__ u8_in(unsigned int n)
{
    unsigned int i, j, u;
    unsigned char b, c;
    if (raw)
        return n;
    i = pend ? 0 : u8_scan(n);
    for (j = i; i < n; ++i) {
        b = iobuf[i];
        if (b < 0x80) {
            if (pend)
                goto bad;
            iobuf[j++] = b;
            continue;
        }
        if (b < 0xC0) {
            if (!pend)
                goto bad;
            --pend;
        } else {
            if (pend)
                goto bad;
            pend = b < 0xE0 ? 1 : b < 0xF0 ? 2 : 3;
        }
        u = cs_dec(b);
        if (u) {
            if (u == 0xFFFD || !(c = cs_byte(u)))
                goto bad;
            iobuf[j++] = c;
        }
    }
    return j;
bad:
    u8_bad = 1;
    return 0;
}

unsigned char u8_end(void)
{
    if (pend)
        u8_bad = 1;
    tk_enc = !raw && !u8_bad;
    return tk_enc;
}

unsigned int u8_gbn(void)
{
    return tk_enc ? TK_IOBUF / 3 : TK_IOBUF;
}

unsigned int __fastcall__ u8_out(unsigned int n)
{
    static char t[3];
    unsigned int i = u8_scan(n), m = n;
    unsigned char k, c;
    if (!tk_enc || i == n)
        return n;
    for (; i < n; ++i)
        if (iobuf[i] >= 0x80)
            m += cs_utf8(iobuf[i], t) - 1;
    i = n;
    n = m;
    while (i) {
        c = iobuf[--i];
        if (c < 0x80)
            iobuf[--m] = c;
        else {
            k = cs_utf8(c, t);
            m -= k;
            iobuf[m] = t[0];
            iobuf[m + 1] = t[1];
            if (k == 3)
                iobuf[m + 2] = t[2];
        }
    }
    return n;
}
