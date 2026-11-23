/* Veranda's colour theme: what draws (theme.h; DECISIONS V65, V74, V79),
   apart from theme.c so that a program that only loads the theme and
   sets its menus' look links less. MIT licence. */
#include <veranda.h>
#include "theme.h"

extern const unsigned int theme_look_[2][16];
extern unsigned char theme_lk2;

#define VCTRL  (*(volatile unsigned char *)0x9F25)
#define VADDRL (*(volatile unsigned char *)0x9F20)
#define VADDRM (*(volatile unsigned char *)0x9F21)
#define VADDRH (*(volatile unsigned char *)0x9F22)
#define VDATA0 (*(volatile unsigned char *)0x9F23)
#define VVIDEO (*(volatile unsigned char *)0x9F29)

void theme_palette(void)
{
    const unsigned int *c = theme_look_[theme.dark ? 1 : 0];
    unsigned char i;
    unsigned int v;
    theme_lk2 = 1;             /* (theme_look2) */
    VCTRL = 0;
    VADDRL = 0;
    VADDRM = 0xFA;
    VADDRH = 0x11;              /* $1FA00, increment 1 */
    for (i = 0; i < 16; ++i) {
        v = i > 1 || theme.dark ? c[i] : i ? theme.ink : theme.paper;
        VDATA0 = v & 255;
        VDATA0 = v >> 8;
    }
}

unsigned char theme_map_on(void)
{
    VCTRL = 0;
    return (VVIDEO & 0x20) != 0;
}

void theme_rect(unsigned char x, unsigned char w, unsigned char y, unsigned char h, unsigned char c)
{
    if (c || theme_map_on())
        ColorRect(x, w, y, h, c);
}

