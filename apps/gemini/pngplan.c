/* Veranda Gemini: a picture's place on the page (overlay 4; DECISIONS
   V125): the size it is shown at, its 16 colours (png.c's png_open chose
   the mode and a palette's own), its tiles white and the map's entries.
   The picture's numbers are in main RAM (png.h): the decoder (png.c and
   pngcore.s, overlay 5) and this read them.

   MIT licence (see LICENSE). */
#ifdef PNG_HOST
#include "png_host.h"
#define vset1(a) vset(0, 0x10000UL + (a))
#else
#include <veranda.h>
#include "gemini.h"
#include "png.h"
#pragma code-name ("OVERLAY4")
#pragma rodata-name ("OVL4RO")
#pragma bss-name ("BSS")                /* (the numbers below: main RAM) */
#define VCTRL  (*(volatile unsigned char *)0x9F25)
#define VAL    (*(volatile unsigned char *)0x9F20)
#define VAM    (*(volatile unsigned char *)0x9F21)
#define VAH    (*(volatile unsigned char *)0x9F22)
#define VD0    (*(volatile unsigned char *)0x9F23)
/* port 0 at $10000 + a */
static void __fastcall__ vset1(unsigned int a)
{
    VCTRL = 0;
    VAL = (unsigned char)a;
    VAM = a >> 8;
    VAH = 0x11;
}
#define VW(b) (VD0 = (b))
#endif

#define TILEV  0x13000UL
#define MAPV   0x1AC00UL

unsigned int pw, ph, pow_, poh;
unsigned char pdepth, pctype, pmode, ptw, pth, ptx, pty, perr;
unsigned int ppal[16];

/* the fixed colours: 2 reds x 4 greens x 2 blues (index r << 3 | g << 1 | b) */
static const unsigned int gcol[16] = { 0x000, 0x00F, 0x050, 0x05F, 0x0A0, 0x0AF, 0x0F0, 0x0FF,
    0xF00, 0xF0F, 0xF50, 0xF5F, 0xFA0, 0xFAF, 0xFF0, 0xFFF };

/* the size shown (78 x 51 cards from card 1, row 7: 624 x 408 pixels;
   912 tiles; twice at most), the colours, the tiles white, the map */
void png_plan(void)
{
    unsigned int s, t, i;
    unsigned char k, x, y;
    s = 512;                            /* (256ths; 32-bit sums only where needed: cc65's helpers are main RAM's) */
    if (pw > 312)
        s = (unsigned int)(624UL * 256 / pw);
    if (ph > 204 && (t = (unsigned int)(408UL * 256 / ph)) < s)
        s = t;
    for (;;) {
        pow_ = (unsigned int)((unsigned long)pw * s / 256);
        poh = (unsigned int)((unsigned long)ph * s / 256);
        if (!pow_) pow_ = 1;
        if (!poh) poh = 1;
        ptw = (pow_ + 7) >> 3;
        pth = (poh + 7) >> 3;
        if ((unsigned int)ptw * pth <= 912)
            break;
        s -= (s >> 3 >> 2) + 1;
    }
    ptx = 1 + ((unsigned char)(78 - ptw) >> 1);
    pty = 7 + ((unsigned char)(51 - pth) >> 1);
    if (pmode != PM_DIRECT)
        for (k = 0; k < 16; ++k)
            ppal[k] = pmode == PM_GRAY ? k * 0x111u : gcol[k];
    t = ptw * pth;
    for (i = 0; i < t; ++i) {
        vset1((i < 464 ? 16 + i : 80 + i) * 32 + 0x3000);       /* (tile i: $13000 + 32 i) */
        for (k = 0; k < 32; ++k)
            VW(0xFF);
    }
    for (y = 0; y < pth; ++y) {
        vset1(0xAC00 + ((unsigned int)(pty + y) << 8) + ((unsigned int)ptx << 1));      /* (the map at $1AC00) */
        for (x = 0; x < ptw; ++x) {
            i = y * ptw + x;
            i = i < 464 ? 16 + i : 80 + i;
            VW((unsigned char)i);
            VW(0x20 | (unsigned char)(i >> 8));
        }
    }
}
