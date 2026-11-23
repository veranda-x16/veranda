/* Veranda C helpers from lib/veranda.lib (besides veranda.h's calls) */
#ifndef VR_H
#define VR_H

/* f is called every frame from the interrupt (intTopVector), with
   cc65's zero page kept and its own small C stack; 0: none. Keep it
   short: no kernel calls that draw or use files. */
void __fastcall__ vr_set_irq(void (*f)(void));

/* FOpen with its error: the handle, or 0 (the error in vr_ferr) */
unsigned char __fastcall__ vr_fopen(const char *name, unsigned char mode);
extern unsigned char vr_ferr;

/* DoDlgBox for a box whose C routines (DB_USR_ROUT, the vectors it
   sets) may close it with RstrFrmDialogue: that returns from DoDlgBox
   without unwinding the C stack; this puts it back. Returns DoDlgBox's
   result. */
unsigned char __fastcall__ vr_dlgbox(const void *box);

/* a routine for the kernel to call (a vector, a dialog box's
   DB_USR_ROUT) that may be in a banked overlay: the address of a
   trampoline (slot 0-3) that maps the RAM bank mapped now, calls f and
   maps back the bank it found (DECISIONS V79) */
void *__fastcall__ vr_tramp(unsigned char slot, void (*f)(void));

/* an application's tile (Veranda Look 2, DECISIONS V77, V90): the 32 x 32
   glyph (128 bytes, 4 a row, bit 7 the left pixel, 1 ink) in its rounded
   frame at card x, pixel row y, as the shell shows a tile; the caller
   colours the 4 x 4 cards (ColorRect). buf: 128 bytes below $A000, where
   the picture is composed (the kernel reads it); glyph may be buf + 2.
   Its source is in the SDK's src/vrtile.c too. */
void __fastcall__ vr_tile(unsigned char x, unsigned int y, const unsigned char *glyph, unsigned char *buf);

/* (DECISIONS V145) the RAM banks the program may still take with
   BankAlloc and still be put aside by the switcher (TaskCtl TASK_ROOM):
   in Fast mode the free banks less the desktop's reserve and a small
   program's packed data, in Roomy mode (programs aside onto the card)
   the free banks and those of the programs aside in RAM, less two; $FF
   on a kernel that does not know it */
unsigned char vr_room(void);

/* the address of a C function, for GEOS tables and vectors */
#define VR_FN(f) ((unsigned int)(f))

#endif
