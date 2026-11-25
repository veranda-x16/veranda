/* Veranda shell: Get Info's colour icon (overlay 16, beside look3b.c:
   overlay 4, files.c's, has no room; DECISIONS V181).

   On the tile desktop (ic3On) the Info box shows the file's colour icon,
   as its window does (look3.c's ic3_draw and ic3_colour: the library's
   by its class, else its own). The box's cards are covered (the kernel's
   TileCover: palette row 15, the card's own row in its shadow byte), so
   ic3_colour's entries go into the shadow bytes; the icon's cards (row
   IROW there) are made to show it, and after the box the 16 entries and
   shadow bytes are put back as they were (the kernel gives back the
   rows, not the tiles: gui.s's gui_unbox likewise).

   MIT licence (see LICENSE). */
#include <veranda.h>
#include <string.h>
#include "shell.h"
#include "tiles.h"
#pragma code-name ("OVERLAY16")
#pragma rodata-name ("OVL16RO")
#pragma bss-name ("OVL16BSS")

#define IROW    12              /* look3.c's: the colour icons' palette row */
#define SHADOW  160             /* inc/x16hw.inc's TILE_SHADOW: a map row's byte 160 + x */
#define VREG(a) (*(volatile unsigned char *)(a))

static unsigned char sv[16][3]; /* the cards' entries (lo, hi) and shadow bytes */
static unsigned char svX, svY, svOn;

/* port 0 on card k's (svX, svY + 4 x 4) map entry (o 0: increment 1),
   its attribute (o 1) or its shadow byte (o SHADOW: increment 0) */
static void at(unsigned char k, unsigned char o)
{
    unsigned int m = 0xAC00 + ((unsigned int)(svY + (k >> 2)) << 8);
    m += o == SHADOW ? SHADOW + svX + (k & 3) : ((svX + (k & 3)) << 1) + o;
    VREG(0x9F25) = 0;
    VREG(0x9F20) = m;
    VREG(0x9F21) = m >> 8;
    VREG(0x9F22) = o ? 0x01 : 0x11;
}

/* the selection's (E, front's) colour icon at cards cx, cy (4 x 4) of the
   box; 0: none drawn (not the tile desktop, or its cards not covered once:
   files.c draws the 1-bit icon) */
unsigned char info_icon(unsigned char cx, unsigned char cy)
{
    unsigned char k, a, n = ic3Now, t;
    svOn = 0;
    if (!ic3On || front >= NWIN)
        return 0;
    svX = cx;
    svY = cy;
    for (k = 0; k < 16; ++k) {
        at(k, 0);
        sv[k][0] = VREG(0x9F23);
        sv[k][1] = VREG(0x9F23);
        at(k, SHADOW);
        if (((sv[k][2] = VREG(0x9F23)) & 0x0F) != 1)
            return 0;
    }
    svOn = 1;
    t = E.tile ? E.tile : TL_BUILT + T_DOCUMENT;        /* (view.c's tileOf) */
    ic3Now = 0;
    XCALL(bLook3, ic3_draw, unsigned char (*)(unsigned char, unsigned int, unsigned char, unsigned char, unsigned char))
        (cx, cy << 3, front, t, E.icon - I_OWN);
    XCALL(bLook3, ic3_colour, FICON)(cx, cy, front, t, 0xFF);
    ic3Now = n;
    for (k = 0; k < 16; ++k) {          /* the icon's cards shown (its empty ones the box's paper) */
        at(k, SHADOW);
        a = VREG(0x9F23);
        if ((a & 0xF0) != IROW << 4)
            continue;
        at(k, 1);
        a = (VREG(0x9F23) & 0x0F) | IROW << 4;
        VREG(0x9F23) = a;
    }
    return 1;
}

/* after the box (the kernel has given the rows back): the cards as they
   were before info_icon */
void info_unicon(void)
{
    unsigned char k;
    if (!svOn)
        return;
    svOn = 0;
    for (k = 0; k < 16; ++k) {
        at(k, 0);
        VREG(0x9F23) = sv[k][0];
        VREG(0x9F23) = (sv[k][2] & 0xF0) | (sv[k][1] & 0x0F);
        at(k, SHADOW);
        VREG(0x9F23) = 0;
    }
}

/*---------------------------------------------------------------
  find's names (files.c's until V182: overlay 4 and main RAM had no room)
 ---------------------------------------------------------------*/
static unsigned char lower(unsigned char c)
{
    return c >= 'A' && c <= 'Z' ? c + 32 : c;
}

/* * any characters, ? one, case ignored */
static unsigned char match(const char *p, const char *s)
{
    for (; *p; ++p, ++s) {
        if (*p == '*') {
            for (;; ++s) {
                if (match(p + 1, s))
                    return 1;
                if (!*s)
                    return 0;
            }
        }
        if (!*s || (*p != '?' && lower(*p) != lower(*s)))
            return 0;
    }
    return !*s;
}

/* the pattern p (main RAM: files.c's pat) matches a or b */
unsigned char files_match(const char *p, const char *a, const char *b)
{
    return match(p, a) || match(p, b);
}

/* (V185; mouse.c's win_idle: overlay 6 has no room) the wheel: its
   notches (+ down) read and cleared; on (the pointer over the front
   window, no drag), no menu open and no find results: the front window
   scrolled, its list 3 rows a notch, its icons a row, by view_page's row
   step (the scroll bar's arrows: clamped there) */
void win_wheel(unsigned char on)
{
    signed char k;
    unsigned char n;
    asm("sei");                         /* (the interrupt adds to it) */
    k = (signed char)mouseWheel;
    mouseWheel = 0;
    asm("cli");
    if (!on || menuNumber || found_on || mouseYPosW < 16)
        return;
    n = k < 0 ? -k : k;
    if (n > 8)
        n = 8;
    if (wins[front].view == V_LIST)
        n *= 3;
    while (n--)
        XCALL(bView, view_page, FBB)(front, k < 0 ? -2 : 2);
}
