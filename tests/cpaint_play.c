/* gate cpaint (DECISIONS V167): Colour Paint's test build (apps/cpaint
   built with CP_TEST and tests/sdk_play.s). cp_test_start plays the
   script (tests/cpaint_script.h); cp_test_snap writes the picture (240
   rows of 320 bytes, from its banks) to a host file; cp_test_sample logs
   a pencil's or eraser's sample, "CPS x y" (the reference draws the same
   segments); the clock: "TIME <what> <cycles, hex>". */
#include <veranda.h>
#include <string.h>
#include "../apps/cpaint/cpaint.h"

extern void __fastcall__ cp_play(const void *script, unsigned char bank);

#ifndef CP_STOP
#define CP_STOP 0xFFFE
#endif
#define AT(f, x, y) ((f) > CP_STOP ? 0xFFFF : (f)), ((f) > CP_STOP ? CP_STOP : (x)), (y)
#define P(f, x, y, b) AT(f, x, ((y) & 255) | (((y) >> 8) << 14) | ((b) << 8))
#define K(f, c) AT(f, c, 0x8000)
#define END(f) 0xFFFF, ((f) > CP_STOP ? CP_STOP : (f)), 0

/* the script in overlay 6 (main RAM is full: V171); the player maps its
   bank while it reads (tests/cpaint_player.s) */
#pragma rodata-name ("OVL6RO")
static const unsigned int script[] = {
#include "cpaint_script.h"
};
#pragma rodata-name ("RODATA")

void cp_test_start(void)
{
    LoadOverlay(6, 0);
    cp_play(script, r1L);
}

void cp_test_snap(const char *name)
{
    unsigned char h, y;
    h = FOpen((void *)name, 'w');
    pa_x = 0;
    pa_n = PW;
    for (y = 0; y < PH; ++y) {
        pa_y = y;
        row_get();
        FWrite(h, rowbuf, PW);
    }
    FClose(h);
    LogText("CPAINT SNAP");
    LogText(name);
}

static const char hex[] = "0123456789ABCDEF";
static char line[24];

void cp_test_sample(int x, int y)
{
    line[0] = 'C', line[1] = 'P', line[2] = 'S', line[3] = ' ';
    line[4] = hex[(x >> 8) & 15], line[5] = hex[(x >> 4) & 15], line[6] = hex[x & 15];
    line[7] = ' ';
    line[8] = hex[(y >> 4) & 15], line[9] = hex[y & 15];
    line[10] = 0;
    LogText(line);
}

/* the emulator's cycle counter ($9FB8: a write resets it, a read of
   $9FB8 latches it, then $9FB9-$9FBB) */
void cp_test_clock_reset(void)
{
    *(volatile unsigned char *)0x9FB8 = 0;
}

void cp_test_clock_log(const char *what)
{
    unsigned char c[4], i, n = 5;
    c[0] = *(volatile unsigned char *)0x9FB8;
    c[1] = *(volatile unsigned char *)0x9FB9;
    c[2] = *(volatile unsigned char *)0x9FBA;
    c[3] = *(volatile unsigned char *)0x9FBB;
    memcpy(line, "TIME ", 5);
    while (*what)
        line[n++] = *what++;
    line[n++] = ' ';
    for (i = 4; i-- > 0;) {
        line[n++] = hex[c[i] >> 4];
        line[n++] = hex[c[i] & 15];
    }
    line[n] = 0;
    LogText(line);
}

/* (V171) the text tool's 1 bpp rows before they are stamped: "CPT <y>
   <first card> <hex bytes>" */
void cp_test_textrow(unsigned char y, unsigned char cx0, unsigned char n, const unsigned char *row)
{
    static char t[100];
    unsigned char i, k = 0;
    t[k++] = 'C', t[k++] = 'P', t[k++] = 'T', t[k++] = ' ';
    t[k++] = hex[y >> 4], t[k++] = hex[y & 15], t[k++] = ' ';
    t[k++] = hex[cx0 >> 4], t[k++] = hex[cx0 & 15], t[k++] = ' ';
    for (i = 0; i < n && k < 96; ++i) {
        t[k++] = hex[row[i] >> 4];
        t[k++] = hex[row[i] & 15];
    }
    t[k] = 0;
    LogText(t);
}

/* the text's box (screen): "CPB <l> <t> <r> <b>" */
void cp_test_textbox(unsigned int l, unsigned char t, unsigned int r, unsigned char b)
{
    static char u[24];
    u[0] = 'C', u[1] = 'P', u[2] = 'B', u[3] = ' ';
    u[4] = hex[(l >> 8) & 15], u[5] = hex[(l >> 4) & 15], u[6] = hex[l & 15], u[7] = ' ';
    u[8] = hex[t >> 4], u[9] = hex[t & 15], u[10] = ' ';
    u[11] = hex[(r >> 8) & 15], u[12] = hex[(r >> 4) & 15], u[13] = hex[r & 15], u[14] = ' ';
    u[15] = hex[b >> 4], u[16] = hex[b & 15], u[17] = 0;
    LogText(u);
}
