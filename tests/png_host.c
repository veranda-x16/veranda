/* gate gemini (DECISIONS V124): apps/gemini/png.c compiled for the host
   (gcc), on a PNG file: what it leaves in VRAM's tiles and map, and the
   rows it decoded, for tests/check_png.py to compare with png_ref.py.

   usage: png_host <file.png> <out>   writes <out>: a line "ok w h pw ph
          mode tw th tx ty" (or "err N"), the 16 colours, then the shown
          picture as tw*8 x th*8 palette indices (one hex digit each, a
          line a row), then "rows" and each decoded row's sum
          (r + 2g + 3b over its pixels, modulo 65536) as PNG_TEST_IROW
          gives it on the X16

   MIT licence (see LICENSE). */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

unsigned char ln[256];
FILE *png_f;
unsigned char vram[0x20000];
unsigned long vaddr[2];
unsigned int png_clock;
static unsigned int rsum[70000];
static unsigned int rsum_n;
static unsigned int rsum_cur;
static unsigned char png_sums = 1;

#define PNG_TEST_PIXEL() (rsum_cur += cr + 2 * cg + 3 * cbl)
#define PNG_TEST_IROW() (rsum[rsum_n++] = rsum_cur, rsum_cur = 0)
#include "../apps/gemini/png.c"
#include "../apps/gemini/pngplan.c"

int main(int argc, char **argv)
{
    unsigned char r;
    unsigned int x, y, t, i;
    FILE *o;
    png_f = fopen(argv[1], "rb");
    o = fopen(argv[2], "w");
    if (!png_f || !o)
        return 2;
    r = png_open();
    if (r) {
        fprintf(o, "err %d\n", r);
        return 0;
    }
    png_plan();
    png_start();
    do
        r = png_step(50);
    while (!r);
    if (r != 1) {
        fprintf(o, "err %d\n", r);
        return 0;
    }
    fprintf(o, "ok %u %u %u %u %u %u %u %u %u\n", pw, ph, pow_, poh, pmode, ptw, pth, ptx, pty);
    for (i = 0; i < 16; ++i)
        fprintf(o, "%03x%c", ppal[i], i == 15 ? '\n' : ' ');
    for (y = 0; y < pth * 8u; ++y) {
        for (x = 0; x < ptw * 8u; ++x) {
            /* the map's tile for card (ptx + x/8, pty + y/8) */
            unsigned long m = MAPV + ((unsigned long)(pty + y / 8) << 8) + ((ptx + x / 8) << 1);
            t = vram[m] | ((vram[m + 1] & 3) << 8);
            i = vram[TILEV + t * 32UL + (y & 7) * 4 + (x & 7) / 2];
            fputc("0123456789abcdef"[x & 1 ? i & 15 : i >> 4], o);
        }
        fputc('\n', o);
    }
    fprintf(o, "rows\n");
    for (i = 0; i < rsum_n; ++i)
        fprintf(o, "%u\n", rsum[i] & 0xFFFF);
    return 0;
}
