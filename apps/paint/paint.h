/* Paint: what paint.c (main RAM) and its overlays share: chrome.c
   (overlay 2: the Sunroom column, the status, the colour map's moments in
   the classic map) and tools.c (overlay 4: the brush, the spray, the
   ovals, the fill); overlay 1 is the SDK's Open and Save dialog, overlay
   3 the column's art (art.s, apps/paint/mkart.py). DECISIONS V20, V32,
   V147.

   An overlay runs at $A000 in its own RAM bank: main RAM calls it through
   OV2() and OV4() (its bank mapped, then the one before). Whatever the
   kernel reads through a pointer (text, rows) is in main RAM.

   MIT licence (see LICENSE). */
#ifndef PAINT_H
#define PAINT_H

/* the drawing area */
#define CX      48              /* left (a card boundary) */
#define CCARD   6
#define CBYTES  74              /* bytes a row */
#define CY      16
#define CR_     639
#define CB      479
#define BANDH   16
#define BANDS   29              /* 464 rows */
#define BANDSZ  (CBYTES * BANDH)
#define MCARD   6               /* the drawing area in cards: x 6-79 */
#define MROW    2               /* y 2-59 */
#define MW      74
#define MH      58

#define BOTH    (ST_WR_FORE | ST_WR_BACK)
#define RAMBANK (*(volatile unsigned char *)0)

/* the tools, in the column's order (2 a row: apps/paint/mkart.py) */
enum {
    T_SELECT, T_FILL, T_PENCIL, T_BRUSH, T_SPRAY, T_ERASER,
    T_LINE, T_TEXT, T_RECT, T_BOX, T_OVAL, T_DISC, TOOLS
};
#define PATS    24
#define COLS    16

/* the column (screen pixels; mkart.py's layout) */
#define TOOLY   16              /* tools: 24 x 24 cells, 2 a row */
#define PATY    168             /* patterns: 16 x 16, 3 a row */
#define CURY    304             /* the current pattern on the current colour */
#define COLY    344             /* colours: 16 x 16, 3 a row */
#define STATY   448             /* the status */

extern unsigned char tool, pat, col, ink, dragging, texting;
extern unsigned int x0, y0, lx, ly;
extern unsigned int rl, rt, rr, rb;
extern unsigned char ov2bank, ov3bank, ov4bank;
extern unsigned char band[BANDSZ], packed[BANDSZ + 16];
extern char stbuf[12];

void __fastcall__ colour(unsigned int x0, unsigned int y0, unsigned int x1, unsigned int y1);
unsigned int __fastcall__ clampx(unsigned int x);
unsigned int __fastcall__ clampy(unsigned int y);

/* chrome.c (overlay 2) */
void chrome_init(void);                 /* the art into VRAM, the column drawn */
void chrome_again(void);                /* the art again (after the switcher, an accessory) */
void __fastcall__ chrome_tool(unsigned char old);
void __fastcall__ chrome_pat(unsigned char old);
void __fastcall__ chrome_col(unsigned char old);
void chrome_ink(void);                  /* colour 1's swatch: the ink */
unsigned char __fastcall__ chrome_hit(unsigned int x, unsigned int y);   /* a click in the column */
void __fastcall__ chrome_status(unsigned int x, unsigned int y);         /* the pointer, a shape's size */
void __fastcall__ chrome_classic(unsigned char on);   /* the colour map as the classic one (print, export) */
unsigned int pack(void);                /* PackBits: band -> packed; the length */
unsigned char __fastcall__ unpack(unsigned int n);    /* packed -> band; 0 if it does not fill it */

/* tools.c (overlay 4) */
void __fastcall__ brush_to(unsigned int x, unsigned int y);
void __fastcall__ spray_at(unsigned int x, unsigned int y);
void __fastcall__ oval_band(unsigned char show);      /* the rubber band of rl, rt, rr, rb */
void oval_draw(void);                   /* the oval (T_OVAL) or the filled one (T_DISC) */
void __fastcall__ fill_at(unsigned int x, unsigned int y);

#define OV2(call) do { unsigned char _b = RAMBANK; RAMBANK = ov2bank; call; RAMBANK = _b; } while (0)
#define OV4(call) do { unsigned char _b = RAMBANK; RAMBANK = ov4bank; call; RAMBANK = _b; } while (0)

#endif
