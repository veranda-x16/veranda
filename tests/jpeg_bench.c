/* gate gemini (DECISIONS V192): Veranda Gemini's JPEG decoder
   (apps/gemini/jpghdr.c, jpegcore.s, pngplan.c) on the X16's own runtime
   (cc65's cx16 target, x16emu with ROM R49, no Veranda), for its timings
   and its tiles: JB.CFG (a line: 1 or 0, VERA FX's multiplier used or
   not, then the file's name) decoded; the console ($9FBB) gets
   "JB ok w h pw ph ow oh tw th tx ty fx open decode huffman idct planes
   rows" (the emulator's cycles, $9FB8) or "JB err n"; then jmp $FFFF
   (-dump V: the tiles and the map for tests/check_jpeg.py).

   MIT licence (see LICENSE). */
#include <stdio.h>
#include <string.h>
#include "../apps/gemini/jpeg_bench.h"
#include "../apps/gemini/jpeg.h"

unsigned char ln[256];
FILE *jb_f;
#ifdef JPEG_PROF
extern unsigned long prof[4];
#endif

static void out(const char *s)
{
    while (*s)
        *(volatile unsigned char *)0x9FBB = *s++;
}

static void num(unsigned long v)
{
    char t[12];
    unsigned char n = 0;
    do {
        t[n++] = '0' + (unsigned char)(v % 10);
        v /= 10;
    } while (v);
    *(volatile unsigned char *)0x9FBB = ' ';
    while (n)
        *(volatile unsigned char *)0x9FBB = t[--n];
}

static unsigned long clk(void)
{
    unsigned long v;
    ((unsigned char *)&v)[0] = *(volatile unsigned char *)0x9FB8;
    ((unsigned char *)&v)[1] = *(volatile unsigned char *)0x9FB9;
    ((unsigned char *)&v)[2] = *(volatile unsigned char *)0x9FBA;
    ((unsigned char *)&v)[3] = *(volatile unsigned char *)0x9FBB;
    return v;
}

static char name[40];

int main(void)
{
    unsigned char r, fx, i;
    unsigned long t0, t1, t2;
    FILE *c = fopen("jb.cfg", "r");
    if (!c || !fgets(name, sizeof name, c)) {
        out("jb err 90\n");
        goto end;
    }
    fclose(c);
    fx = name[0] == '1';
    for (i = 0; name[i] >= ' '; ++i)
        ;
    name[i] = 0;
    jb_f = fopen(name + 2, "rb");
    if (!jb_f) {
        out("jb err 91\n");
        goto end;
    }
    t0 = clk();
    r = jpg_open();
    jnofx = !fx;
    if (!r) {
        png_plan();
        jpg_start();
        jinit();
        t1 = clk();
        r = jstep(1);
    } else
        t1 = clk();
    t2 = clk();
    if (r != 1) {
        out("jb err");
        num(r);
        out("\n");
        goto end;
    }
    out("jb ok");
    num(pw);
    num(ph);
    num(pow_);
    num(poh);
    num(ptw);
    num(pth);
    num(ptx);
    num(pty);
    num(jfx >> 7);
    num(t1 - t0);
    num(t2 - t1);
#ifdef JPEG_PROF
    for (i = 0; i < 4; ++i)
        num(prof[i]);
#endif
    out("\n");
end:
    __asm__("jmp $FFFF");
    return 0;
}
