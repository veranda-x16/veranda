/* Veranda SDK: an application's tile (vr.h; Veranda Look 2, DECISIONS
   V77; an SDK call since V90, the shell's own drawing until then).

   A tile is a 32 x 32 glyph on a block of 4 x 4 cards of one paper
   colour, the ink a picture in a rounded frame (radius 4). vr_tile draws
   the frame and the glyph; the caller colours the cards (ColorRect: the
   tile's colour, the selection's ...). The picture is composed in buf as
   32 raw rows of 4 bytes for WBitmapUp (its height's bit 15, DECISIONS
   V81: a column of bytes at a time, VERA stepping by the stride, when the
   kernel's clip is off; with the clip on, a tile wholly inside it is
   drawn so with the clip off for it, one partly inside row by row,
   clipped). buf must be below $A000 (the kernel reads it); glyph may be
   anywhere, buf + 2 too (the shell composes in place).

   Its source is in the SDK's src/, so a program short of main RAM can
   compile it into an overlay (the shell's tiles overlay does).

   MIT licence (see LICENSE). */
#include <veranda.h>
#include "vr.h"

static const unsigned char frameRow[4][4] = {
    { 0x1F, 0xFF, 0xFF, 0xF8 },
    { 0x60, 0x00, 0x00, 0x06 },
    { 0x40, 0x00, 0x00, 0x02 },
    { 0x80, 0x00, 0x00, 0x01 },
};

void __fastcall__ vr_tile(unsigned char x, unsigned int y, const unsigned char *glyph, unsigned char *buf)
{
    unsigned char r, c;
    const unsigned char *d = glyph, *f;
    unsigned char *o = buf;
    for (r = 0; r < 32; ++r, d += 4, o += 4) {      /* (o may be d - 2) */
        f = frameRow[r < 4 ? r : r > 27 ? 31 - r : 3];
        o[0] = d[0] | f[0];
        o[1] = d[1] | f[1];
        o[2] = d[2] | f[2];
        o[3] = d[3] | f[3];
    }
    c = clipOn;
    if (c && x * 8 >= leftMargin && (x + 4) * 8 - 1 <= rightMargin && y >= windowTopW && y + 31 <= windowBottomW)
        clipOn = 0;
    WBitmapUp(buf, x, 4, y, 0x8000 | 32);
    clipOn = c;
}
