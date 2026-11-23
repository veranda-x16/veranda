/* Veranda's clipboard: the Text Scrap: reading it (scrap.h). MIT licence (see LICENSE). */
#include <veranda.h>
#include <string.h>
#include "scrap.h"

unsigned int __fastcall__ scrap_get_text_raw(void *buf, unsigned int max)
{
    unsigned int n, len = 0;
    if (!scrap_open(SCRAP_TEXT) || scrap_read(&len, 2) != 2)
        len = 0;
    n = len > max ? max : len;
    if (n)
        n = scrap_read(buf, n);
    scrap_close();
    return n;
}

unsigned int __fastcall__ scrap_get_text(char *out, unsigned int max)
{
    static unsigned char buf[64];
    unsigned int len = 0, o = 0;
    unsigned char k = 0, i = 0, skip = 0, c;
    if (!max)
        return 0;
    if (scrap_open(SCRAP_TEXT) && scrap_read(&len, 2) == 2) {
        while (len && o + 1 < max) {
            if (i == k) {
                k = scrap_read(buf, len > sizeof buf ? sizeof buf : len);
                i = 0;
                if (!k)
                    break;
            }
            c = buf[i++];
            --len;
            if (skip) {
                --skip;
                continue;
            }
            if (c == SCRAP_NEWCARDSET)
                skip = 3;
            else if (c == SCRAP_ESC_RULER)
                skip = 26;
            else if (c == SCRAP_ESC_GRAPHICS)
                skip = 4;
            else if (c == SCRAP_PAGE_BREAK || c == 13)
                out[o++] = 13;
            else if (c == 9 || c >= 32 && c < 127)
                out[o++] = c;
        }
    }
    scrap_close();
    out[o] = 0;
    return o;
}
