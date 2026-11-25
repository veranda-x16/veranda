/* Veranda Gemini: jpghdr.c, jpegcore.s and pngplan.c on the X16's own runtime (cc65's
   cx16 target, no Veranda: tests/jpeg_bench.c, gate gemini's timings;
   DECISIONS V192). MIT licence (see LICENSE). */
#ifndef JPEG_BENCH_H
#define JPEG_BENCH_H
#include <stdio.h>
#include "png.h"
extern unsigned char ln[256];
extern FILE *jb_f;
#define FREAD(n) ((unsigned int)fread(ln, 1, (n), jb_f))
#define JNOW() 0
#endif
