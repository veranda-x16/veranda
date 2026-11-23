/* Veranda shell: the tiles (overlay 9; Veranda Look 2, DECISIONS V77).

   A tile is a 32 x 32 picture on a block of 4 x 4 cards of one paper
   colour, the ink a glyph in a rounded frame (radius 4). Where a tile
   comes from (an entry's TL_* byte):
   - TL_BUILT + n: the shell's own (tiles.h, from tiles.txt: the ports of
     GEOS programs, known by their class, which cannot carry one; a
     folder, "..", a plain document, the card, the printer, the trash);
   - TL_OWN + n: a Veranda application's own, read from its file's tile
     block (docs/APPFORMAT.md) into the tiles' bank by dir.c;
   - TL_ICON: any other GEOS file's icon (24 x 21), centred on a chrome
     tile.
   The tile is composed in tileBuf (resident: the kernel reads below
   $A000 only) by the SDK's vr_tile (DECISIONS V90) as raw rows for WBitmapUp (its height's bit 15, DECISIONS
   V81: a column of bytes at a time, VERA stepping by the stride, when
   the kernel's clip is off; in the scene, with the clip on, a tile
   wholly in it is drawn so with the clip off for it, one partly in it
   row by row, clipped).

   The small glyphs (11 x 11: the sidebar's places, the list's kind
   badges) are drawn at any x (shifted into 3 cards). */
#include <veranda.h>
#include <string.h>
#include <theme.h>
#include <vr.h>
#include "shell.h"
#pragma code-name ("OVERLAY10")
#pragma rodata-name ("OVL10RO")
#pragma bss-name ("OVL10BSS")
#define TILE_DATA
#include "tiles.h"

/* the tile's 128 bytes into tileBuf + 2 (a scratch place: composed after);
   its colour */
static unsigned char fetch(unsigned char w, unsigned char t, unsigned char icon)
{
    unsigned char *d = tileBuf + 2, r, a, b, c;
    const unsigned char *s;
    if (t & TL_BUILT) {
        t &= 0x1F;
        if (t >= NTILES)
            t = T_DOCUMENT;
        memcpy(d, tileData[t] + 1, 128);
        return tileData[t][0];
    }
    if (t & TL_OWN) {
        t &= 0x1F;
        if (w == 2)
            bget(bDesk, DT_AT + t * TILELEN, tileBuf, TILELEN);
        else
            bget(bTiles, (w ? 4096 : 0) + t * TILELEN, tileBuf, TILELEN);
        a = tileBuf[0];
        memmove(d, tileBuf + 1, 128);
        return a & 15;
    }
    /* a GEOS icon, 24 x 21, at 4, 6 */
    s = icon_get(w, icon, 0) + 1;
    memset(d, 0, 128);
    d += 6 * 4;
    for (r = 0; r < 21; ++r, s += 3, d += 4) {
        a = s[0];
        b = s[1];
        c = s[2];
        d[0] = a >> 4;
        d[1] = a << 4 | b >> 4;
        d[2] = b << 4 | c >> 4;
        d[3] = c << 4;
    }
    return CHROME;
}

/* raw rows (w bytes by h) at tileBuf to card x, row y; with the clip on
   and the rectangle wholly in it, the clip off for it (the fast way) */
static void raw(unsigned char x, unsigned char w, unsigned int y, unsigned char h)
{
    unsigned char c = clipOn;
    if (c && x * 8 >= leftMargin && (x + w) * 8 - 1 <= rightMargin && y >= windowTopW && y + h - 1 <= windowBottomW)
        clipOn = 0;
    WBitmapUp(tileBuf, x, w, y, 0x8000 | h);
    clipOn = c;
}

/* window w's tile t (or a pin's: w 2) at card cx, row y: drawn (the SDK's
   vr_tile, compiled into this overlay: the Makefile), its colour returned
   (the caller colours the cards); w + $80 (Look 3, V156: look3.c when
   there is no colour icon) its glyph alone, without the rounded frame */
unsigned char tile_draw(unsigned char cx, unsigned int y, unsigned char w, unsigned char t, unsigned char icon)
{
    unsigned char col = fetch(w & 3, t, icon);
    if (w & 0x80) {
        memmove(tileBuf, tileBuf + 2, 128);
        raw(cx, 4, y, 32);
    } else
        vr_tile(cx, y, tileBuf + 2, tileBuf);   /* (composed in place, 2 bytes down) */
    return col;
}

unsigned char tile_colour(unsigned char w, unsigned char t)
{
    if (t & TL_BUILT) {
        t &= 0x1F;
        return tileData[t < NTILES ? t : T_DOCUMENT][0];
    }
    if (t & TL_OWN) {
        bget(w == 2 ? bDesk : bTiles, (w == 2 ? DT_AT : w ? 4096 : 0) + (t & 0x1F) * TILELEN, tileBuf, 1);
        return tileBuf[0] & 15;
    }
    return CHROME;
}

/* an info block's class (12 characters) -> the shell's tile for it */
unsigned char tile_class(const unsigned char *cls)
{
    unsigned char i;
    for (i = 0; i < NCLASS; ++i)
        if (!memcmp(cls, tileClass[i], 12))
            return TL_BUILT + i;
    return 0;
}

/* glyph m (11 x 11) with its top left at x, y */
void mini_draw(unsigned int x, unsigned int y, unsigned char m)
{
    unsigned char r, s = x & 7, *d = tileBuf;
    unsigned int v;
    const unsigned int *g = miniData[m];
    for (r = 0; r < 11; ++r, d += 3) {      /* (the 24 bits of v << 8 - s: V81) */
        v = *g++;
        d[0] = v >> (8 + s);
        d[1] = v >> s;
        d[2] = v << (8 - s);
    }
    raw(x >> 3, 3, y, 11);
}
