/* Veranda SDK: a program's full-colour picture (lib/veranda.lib's
   vrpic.s; DECISIONS V105)

   The kernel's tile mode (V101, the shell's desktop picture) for a
   program: VERA's layer 0 shows 4 bpp tiles of 8 x 8 pixels under the 1
   bpp bitmap (layer 1: its 0 bits show the tiles, its 1 bits the ink,
   palette entry 1). The program writes its tiles, its map and its palette
   rows into VRAM itself (vr_vram_load: records made by the SDK's
   tools/mkwall.py --tiles). Menus and dialog boxes work as before over
   it: their cards are covered (palette row 15, the paper), and what they
   cover comes back from the back screen (vr_pic_on clears it: the
   save-under stack's room holds the tiles), or, for a dialog box of a
   program that draws to the foreground only, as V84 copies it there.

   VRAM while it is on (640 x 480):
     tiles 0-15     solid colours (tile c every pixel c: ColorRect's colour c
                    in palette row 0); the program's from 16 on
     tiles 16-479   $13200-$16BFF; tiles 544-991 ($17400-$1ABFF, sprite
                    slots 1-7) too when the program keeps no sprite
                    pictures there (480-543 are sprite slot 0, the pointer)
     the map        card (x, y)'s entry at VR_PIC_MAP + 256 y + 2 x: the
                    tile's low byte; palette row << 4 | vflip << 3 | hflip
                    << 2 | the tile's bits 8-9 (rows 0-1, under the menu
                    bar, tile 0: the paper)
     palette        rows 2-13 the program's (its sprites' rows among them),
                    14 a covered card's highlight, 15 a covered card's
                    paper (vr_pic_on sets it: palette entry 0's colour as
                    it is then: set the paper first), 0 the UI, 1 the
                    pointer's
   A program that draws ink it wants back under a menu draws it to both
   screens (dispBufferOn ST_WR_FORE | ST_WR_BACK); one that draws to the
   foreground only keeps the bitmap empty where menus open.

   MIT licence (see LICENSE). */
#ifndef VRPIC_H
#define VRPIC_H

#define VR_PIC_TILES   0x13000UL   /* tile t's 32 bytes at VR_PIC_TILES + 32 t */
#define VR_PIC_TILES2  0x17400UL   /* tile 544 (sprite slots 1-7) */
#define VR_PIC_MAP     0x1AC00UL
#define VR_PIC_PALETTE 0x1FA00UL   /* row r at + 32 r */

/* tile mode on: palette rows 2-15 kept for its end, the map cleared
   (every card tile 0: the paper), tiles 0-15 solid, row 15 the paper,
   the back screen cleared, asideVector noted (the one found is still
   called). Nothing if it is on already. */
void vr_pic_on(void);

/* tile mode off: the bitmap alone again, palette rows 2-15 as they were
   before vr_pic_on; asideVector as it was. (A program that quits without
   it is fine too: the next program's start ends tile mode the same way.) */
void vr_pic_off(void);

/* 1 once after the switcher called asideVector (Alt + Tab: the program
   was put aside and is back, or stayed after the question whether it may
   quit): palette rows 2-15 are then as they were before vr_pic_on (the
   tiles and the map are kept); row 15 is written again here, the
   program writes its own rows again (vr_vram_load of mkwall's record 1,
   its sprites' rows). Call it from appMain. */
unsigned char vr_pic_back(void);

/* the VRAM chunks of a record in RAM bank `bank` at $A000 (LoadOverlay's
   r1L; mkwall.py --tiles's OUT.vram.N): 3 bytes the address, 2 the
   length, the bytes; a length 0 ends */
void __fastcall__ vr_vram_load(unsigned char bank);

#endif
