/* Veranda Gemini: PNG pictures (png.c and pngcore.s, overlay 5; pngplan.c, overlay 4; DECISIONS V125).
   MIT licence (see LICENSE). */
#ifndef PNG_H
#define PNG_H

#define PE_NOTPNG    2          /* not a PNG file */
#define PE_DATA      3          /* damaged */
#define PE_INTERLACE 4          /* interlaced (Adam7): refused */
#define PE_BIG       5          /* a row of more than 4,864 bytes (1,216 pixels of RGBA), or 65,536 pixels */

#define PM_GRAY   0             /* 16 greys, dithered */
#define PM_COLOUR 1             /* 2 reds x 4 greens x 2 blues, dithered */
#define PM_DIRECT 2             /* a palette of up to 16 colours as it is */

extern unsigned int pw, ph, pow_, poh;  /* the picture's size, the size shown */
extern unsigned char pdepth, pctype, pmode;
extern unsigned char ptw, pth, ptx, pty;        /* its tiles: columns, rows, the first card */
extern unsigned int ppal[16];           /* its colours (VERA's 12 bits: $0RGB) */
extern unsigned char perr;
extern unsigned char png_h;             /* the file's handle */

unsigned char png_open(void);           /* (overlay 5) the header, the colours' mode: 0, PE_* */
void png_plan(void);                    /* (overlay 4, pngplan.c) the size shown, the colours, the tiles white, the map */
void png_start(void);                   /* (overlay 5) the decoder's start */

unsigned char __fastcall__ png_step(unsigned char frames);     /* (overlay 5) 0 more, 1 done, PE_* */

#endif
