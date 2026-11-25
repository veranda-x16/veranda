/* Veranda Gemini: JPEG pictures (jpghdr.c, overlay 6; jpegcore.s, overlay
   7; DECISIONS V192): the picture's set-up, jpegcore.s's _jsx (written by
   jpghdr.c through BankCopy: the same layout in both).
   MIT licence (see LICENSE). */
#ifndef JPEG_H
#define JPEG_H

#define NBLK 6                  /* an MCU's blocks at most */

struct jcfg {
    unsigned char nblk;
    unsigned char bt[NBLK];     /* a block's component */
    unsigned char bq[NBLK];     /* its quantisation table */
    unsigned int bdc[NBLK];     /* its Huffman tables (their addresses in jsx.htab) */
    unsigned int bac[NBLK];
    unsigned int bd0[NBLK];     /* its place in an MCU row's first MCU (from $09600) */
    unsigned char bstep[NBLK];  /* the step to the next MCU's */
    unsigned char binc[NBLK];   /* VERA's increment: $10 (Y), $20 (Cb, Cr interleaved) */
    unsigned int bstr[NBLK];    /* its plane's stride */
    unsigned char bs;           /* samples a block across: 8, or 1 (its DC alone) */
    unsigned char hmax;         /* Y's samples a chroma sample across */
    unsigned char gray;         /* one component */
    unsigned char vmask;        /* Y's rows a chroma row, less 1 */
    unsigned int mcux;          /* MCUs a row */
    unsigned char yrows;        /* an MCU row's rows */
    unsigned int ystride, cstride, cbase;       /* the planes (cbase from $09600) */
    unsigned int dri;           /* the restart interval */
};

#define HT_DC1 67               /* the Huffman tables in htab: DC 0, 1, AC 0, 1 */
#define HT_AC0 134
#define HT_AC1 441
#define HT_SIZE 748

struct jstate {
    struct jcfg c;
    unsigned char htab[HT_SIZE];        /* each: lim[17], limh[17], off[17], vals */
    unsigned char qlo[256], qhi[256];   /* 4 tables, zigzag order, AAN-scaled */
};

extern struct jstate jsx;       /* (overlay 7) */
extern unsigned char jidx, jmark, jfx, jnofx;   /* (main RAM) */
extern unsigned int joy;
void jfill(void);               /* (main RAM) ln refilled */
void jinit(void);               /* (overlay 7) the tables, the state */
unsigned char __fastcall__ jstep(unsigned char frames);        /* (overlay 7) 0 more, 1 done, PE_* */

#endif
