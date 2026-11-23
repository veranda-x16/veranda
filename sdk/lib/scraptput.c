/* Veranda's clipboard: the Text Scrap: writing it (scrap.h). MIT licence (see LICENSE). */
#include <veranda.h>
#include <string.h>
#include "scrap.h"

/* NEWCARDSET: BSW 9 (font id 0, 9 points: $0009), plain */
static const unsigned char cardset[4] = { SCRAP_NEWCARDSET, 9, 0, 0 };

unsigned char __fastcall__ scrap_put_text_raw(const void *p, unsigned int n)
{
    unsigned char e = scrap_text_begin(n);
    if (!e)
        e = scrap_write(p, n);
    if (!e)
        return scrap_close();
    scrap_close();
    return e;
}

static unsigned char keep(unsigned char c)
{
    return c >= 32 && c < 127 || c == 9 || c == 10 || c == 13;
}

unsigned char __fastcall__ scrap_put_text(const char *s, unsigned int n)
{
    static unsigned char buf[64];
    unsigned int i, len = 4;
    unsigned char k = 0, e, c;
    for (i = 0; i < n; ++i)
        len += keep(s[i]);
    if ((e = scrap_text_begin(len)) != 0)
        return e;
    e = scrap_write(cardset, 4);
    for (i = 0; !e && i < n; ++i) {
        c = s[i];
        if (!keep(c))
            continue;
        buf[k++] = c == 10 ? 13 : c;
        if (k == sizeof buf || i + 1 == n) {
            e = scrap_write(buf, k);
            k = 0;
        }
    }
    if (!e && k)
        e = scrap_write(buf, k);
    if (!e)
        return scrap_close();
    scrap_close();
    return e;
}
