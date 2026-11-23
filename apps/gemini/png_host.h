/* Veranda Gemini: png.c on the host (tests/png_host.c; DECISIONS V124):
   the file through stdio, VERA's VRAM and two data ports as an array.
   MIT licence (see LICENSE). */
#ifndef PNG_HOST_H
#define PNG_HOST_H
#include <stdio.h>
#define __fastcall__
#include "png.h"
extern unsigned char ln[256];
extern FILE *png_f;
extern unsigned char vram[0x20000];
extern unsigned long vaddr[2];
extern unsigned int png_clock;
#define FREAD(n) ((unsigned int)fread(ln, 1, (n), png_f))
#define PNG_NOW() (png_clock++)
static void vset(unsigned char port, unsigned long a) { vaddr[port] = a; }
#define VW(b) (vram[vaddr[0]++ & 0x1FFFF] = (b))
#define VR() (vram[vaddr[1]++ & 0x1FFFF])
static void keep_ports(void) {}
static void back_ports(void) {}
#endif
