/* Veranda's colour theme: colours under a dialog box (theme.h,
   theme_cover_rect; DECISIONS V79), apart so that only the programs that
   use it link it. MIT licence. */
#include <veranda.h>
#include "theme.h"

#define VCTRL  (*(volatile unsigned char *)0x9F25)
#define VADDRL (*(volatile unsigned char *)0x9F20)
#define VADDRM (*(volatile unsigned char *)0x9F21)
#define VADDRH (*(volatile unsigned char *)0x9F22)
#define VDATA0 (*(volatile unsigned char *)0x9F23)

void theme_cover_rect(unsigned char x, unsigned char w, unsigned char y, unsigned char h, unsigned char c)
{
    unsigned char i;
    if (!theme_map_on())
        return;
    if (*(volatile unsigned char *)0x9F2F == 0x98)
        return;                 /* (the shell's tile desktop, V101: not a 1 bpp map) */
    c <<= 4;
    for (; h; --h, ++y) {
        VCTRL = 0;
        VADDRL = (x << 1) + 1;
        VADDRM = 0xAC + y;      /* the map at $1AC00, 256 bytes a row */
        VADDRH = 0x21;          /* increment 2: the attribute bytes */
        for (i = 0; i < w; ++i)
            VDATA0 = c;
    }
}

