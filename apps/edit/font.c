/* Veranda Edit: the 8 x 8 font, from the X16 ROM's charsets (ROM bank 6):
   glyphs 0-$9F the ISO set's (its $80-$9F unused by text), $A0-$FF the
   ISO-8859-16 set's upper half (the CHARLAE set, R47 and later), so the
   text's bytes show in Veranda's set (DECISIONS V140, V143). Glyphs 0-31
   are the ROM's inverted @ A-Z [ \ ] ^ _, so control characters show as
   such; glyph $80 shows a NUL byte (PutCards stops at a 0), as glyph 0.
   A ROM without the ISO-8859-16 set keeps its ISO-8859-15 glyphs there.

   MIT licence (see LICENSE). */
#include <string.h>
#include "edit.h"

unsigned char font[2048];

/* glyph 0 (an inverted @) and 'A' of the ROM's ISO set, and the
   ISO-8859-16 set's $A1 (A ogonek): how they are found */
static const unsigned char sig0[8] = { 0xC3, 0x99, 0x91, 0x91, 0x91, 0x9F, 0xC1, 0xFF };
static const unsigned char sigA[8] = { 0x18, 0x3C, 0x24, 0x66, 0x7E, 0x66, 0x66, 0x00 };
const unsigned char sigL10[8] = { 0x18, 0x3C, 0x24, 0x66, 0x7E, 0x66, 0x0C, 0x06 };

/* (with ROM bank 6 mapped) the ISO-8859-16 upper half's 96 glyphs to dst */
void __fastcall__ font_l10(unsigned char *dst)
{
    unsigned int a;
    for (a = 0xC008; a; a += 8)
        if (*(unsigned char *)a == 0x18 && !memcmp((void *)a, sigL10, 8)) {
            memcpy(dst, (void *)(a - 8), 96 * 8);
            return;
        }
}

void font_load(void)
{
    unsigned char keep, ok = 0;
    unsigned int a;
    asm("sei");                 /* ROM bank 6 has no interrupt vectors */
    keep = *(unsigned char *)1;
    *(unsigned char *)1 = 6;
    for (a = 0xC000; a; a += 0x800)
        if (!memcmp((void *)a, sig0, 8) && !memcmp((void *)(a + 0x41 * 8), sigA, 8)) {
            memcpy(font, (void *)a, 2048);
            ok = 1;
            break;
        }
    if (!ok)
        memcpy(font, (void *)0xC800, 2048);
    font_l10(font + 0xA0 * 8);
    *(unsigned char *)1 = keep;
    asm("cli");
    memcpy(font + 0x80 * 8, font, 8);
}
