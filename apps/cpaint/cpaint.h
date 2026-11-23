/* Colour Paint: what cpaint.c (the program: menus, files, the chrome),
   draw.c (the tools on the picture) and pic.s (the picture's bytes, fast)
   share. DECISIONS V167.

   The picture, 320 x 240 bytes (a palette entry a pixel), lives in RAM
   banks: band b (rows 24 b .. 24 b + 23) in bank pbank + b at $A000, row
   r of it at $A000 + 320 r. VRAM (the kernel's canvas, vrcanvas.h) is only
   its view: screen x VX-319, y VY-239 show the picture from (scrx, scry).

   MIT licence (see LICENSE). */
#ifndef CPAINT_H
#define CPAINT_H

#define PW      320             /* the picture */
#define PH      240
#define BANDH   24              /* rows a band: a bank */
#define BANDS   10
#define VX      40              /* the view on the screen */
#define VY      28              /* (V170: under the title band, y 14-27) */
#define VW      280
#define VH      212
#define MAXSX   (PW - VW)       /* the scroll's limits */
#define MAXSY   (PH - VH)

#define RAMBANK (*(volatile unsigned char *)0)

/* the tools, in the column's order (two a row) */
enum { T_SELECT, T_FILL, T_PENCIL, T_BRUSH, T_SPRAY, T_ERASER, T_LINE, T_TEXT, T_RECT, T_BOX, T_OVAL, T_DISC,
       T_PICK, TOOLS };

extern unsigned char pbank, ubank;      /* the picture's 10 banks, undo's 10 */
extern unsigned char rowbank[PH];       /* row y: its bank (pbank-relative) */
extern unsigned char rowlo[PH], rowhi[PH];  /* and address */
extern unsigned char scrx, scry;        /* the view's top left in the picture */
extern unsigned char cola, colb;        /* the two current colours */

/* pic.s: the arguments in pa_* (zero page is cc65's) */
extern unsigned char pa_y, pa_c;
extern unsigned int pa_x, pa_n;
extern unsigned long pa_v;
void pic_out(void);             /* row pa_y's bytes pa_x .. + pa_n - 1 to VRAM pa_v */
void pic_span(void);            /* row pa_y's bytes pa_x .. + pa_n - 1 = pa_c */
void vzero(void);               /* pa_n bytes of 0 to VRAM pa_v */
void vfill(void);               /* pa_n bytes of pa_c to VRAM pa_v */
void __fastcall__ vout(const unsigned char *p);   /* pa_n bytes from p to VRAM pa_v */

unsigned char __fastcall__ pget(unsigned int x, unsigned char y);
void __fastcall__ pset(unsigned int x, unsigned char y);   /* = pa_c */
unsigned char __fastcall__ uget(unsigned int x, unsigned char y);   /* undo's whole copy */
void urow_save(void);           /* row pa_y, pa_x .. + pa_n - 1: to undo's copy */
void urow_swap(void);           /* exchanged with undo's copy */
void row_get(void);             /* to rowbuf */
void row_put(void);             /* from rowbuf */
void old_row(void);             /* (V172) obuf's two rows of Paint's at half size to rowbuf */
extern unsigned char rowbuf[320];

/* cpaint.c */
extern unsigned int pal[256];
extern unsigned char dirty;
void screen_out(unsigned int l, unsigned char t, unsigned int r, unsigned char b);
void show(int l, int t, int r, int b);  /* picture box to the view */
void keep_box(int l, int t, int r, int b);      /* undo's copy */
void message(const char *a, const char *b);
void error(unsigned char e);
void title(void);
#define VADDR(sx, sy) (VR_CANVAS + 320UL * (sy) + (sx))

/* draw.c */
extern int dl, dt, dr, db;              /* the last change's box (picture) */
void __fastcall__ d_line(int x0, int y0, int x1, int y1);
void __fastcall__ d_rect(int l, int t, int r, int b, unsigned char filled);
void __fastcall__ d_oval(int l, int t, int r, int b, unsigned char filled);
void __fastcall__ d_erase(int x, int y);
unsigned char __fastcall__ d_fill(int x, int y);           /* 0: nothing to fill */
void __fastcall__ d_box(int l, int t, int r, int b);       /* the change's box grows */
extern unsigned char mbuf[176];
void __fastcall__ clip_move(unsigned char bank, unsigned long off, unsigned int n, unsigned char to);

/* tools4.c (overlay 4) */
void __fastcall__ t4_brush(int x0, int y0, int x1, int y1);
void __fastcall__ t4_spray(int x, int y);
void __fastcall__ t4_text(unsigned int l, unsigned char t, unsigned int r, unsigned char b);
unsigned char __fastcall__ t4_copy(int l, int t, int r, int b);
unsigned char t4_paste_ready(void);
unsigned int t4_cw(void);
unsigned int t4_ch(void);
void __fastcall__ t4_put(int x, int y, unsigned char into);
void __fastcall__ t4_pal_open(unsigned char e);
unsigned char __fastcall__ t4_pal_click(unsigned int x, unsigned char y);
void t4_pal_close(void);
void __fastcall__ t4_grid(unsigned int x, unsigned char y);   /* the 256 entries, 8 x 8 each */
void t4_whole(void);                    /* View > Whole picture */
void __fastcall__ t4_status(int x, int y);
void t4_title(void);
extern char docname[64], ttl[72];
#include "art.h"

/* export.c (overlay 7: V172) */
extern unsigned char sbank;
extern char expname[64];
void make_hdr(unsigned char kind);
unsigned char __fastcall__ rec_write(unsigned int n);
unsigned char x7_paint(void);
unsigned char x7_bmp(void);
unsigned char x7_print(void);

#endif
