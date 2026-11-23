/* Veranda SDK: the canvas, a picture of one byte a pixel (lib/veranda.lib's
   vrcanvas.s; DECISIONS V166)

   The kernel's canvas mode (ColorRect COLOR_CANVAS, kernel/c/canvas.s), in
   the 320 x 240 mode only: VERA's layer 0 an 8 bpp bitmap of 320 x 240 at
   VR_CANVAS, any of the 256 palette entries a pixel, under the kernel's
   1 bpp screen (layer 1: its 0 pixels show the picture, its 1 pixels the
   ink). The program draws the picture's bytes into VRAM itself (a pixel
   at VR_CANVAS + 320 y + x); menus, dialog boxes and the pointer work as
   before over it.

   Under a menu or a dialog box the picture's cards are zeroed (the 1 bpp
   screen's 0 pixels are transparent: the box shows on the paper) and
   drawn again by the program when the last cover is gone: vr_canvas_on's
   repaint routine is called with the cards in vr_canvas_area (x, width,
   y, height; one row of cards a call). It runs inside the kernel's menu
   or box code: it writes VRAM (VERA_CTRL, port 0) and its own RAM banks
   only, no kernel calls; it must be in main RAM. vr_canvas_covered()
   tells a program drawing at another moment which cards to leave alone.

   VRAM while it is on: $00000-$0257F the 1 bpp screen; VR_CANVAS
   ($02800-$153FF) the picture; $15400-$155DF palette entries 16-255 as
   they were (the kernel puts them back when the mode ends); $155E0-
   $16BFF free; sprite slots 0-1 at $16C00; the save-under stack at
   $1AC00-$1EBFF (the colour map's room: no ColorRect colours meanwhile).
   The back screen is the picture's room: draw to the foreground only.

   Alt + Tab: vr_canvas_on puts a routine on asideVector that zeroes the
   picture's VRAM (the program put aside packs small) and notes it;
   vr_canvas_back() then returns 1 once: the program writes its palette
   and its picture again. A desk accessory hides the picture while it
   runs; the kernel puts the layers back after it (the picture's VRAM is
   kept).

   MIT licence (see LICENSE). */
#ifndef VRCANVAS_H
#define VRCANVAS_H

#define VR_CANVAS     0x02800UL    /* pixel (x, y) at VR_CANVAS + 320 y + x */
#define VR_CANVAS_W   320
#define VR_CANVAS_H   240

/* the cards the repaint routine draws again: x, width, y, height */
extern unsigned char vr_canvas_area[4];

/* the menus and dialog boxes over the picture now (0: none) */
extern unsigned char vr_canvas_covers;

/* the canvas on (SetVideoMode(MODE_320x240) first): the picture cleared
   (entry 0 everywhere), the covers counted from none, asideVector noted.
   0 if it is on; else the kernel's error (not the 320 mode, the colour
   map or tile mode on) */
unsigned char __fastcall__ vr_canvas_on(void (*repaint)(void));

/* the canvas off: palette entries 16-255 as they were, the 1 bpp screen
   alone; asideVector as it was. (A program that quits without it is fine
   too: the next program's SetVideoMode ends the mode the same way.) */
void vr_canvas_off(void);

/* 1 once after the switcher called asideVector (the program came back,
   or stayed after the question whether it may quit): the picture's VRAM
   is 0, palette entries 16-255 are whatever the other programs left */
unsigned char vr_canvas_back(void);

/* nonzero if card (x, y) (0-39, 0-29) is under a menu or a box */
unsigned char __fastcall__ vr_canvas_covered(unsigned char x, unsigned char y);

/* palette entries first .. first + n - 1 from pal ($0RGB words, VERA's
   order: pal[0] for entry `first`); entries 17-20 (the pointer's) are
   left as they are */
void __fastcall__ vr_canvas_palette(const unsigned int *pal, unsigned char first, unsigned char n);

#endif
