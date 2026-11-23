/* gate desk: the Calculator's test build (apps/calc built with CALC_TEST
   and tests/sdk_play.s). calc_test_start plays tests/calc_script.h from
   the accessory's own start; its end mark is never reached (the
   accessory ends with RstrAppl, and the application's script goes on)
   unless CALC_STOP stops the session there with a dump (a screenshot). */
#include <veranda.h>
#include <string.h>

extern void __fastcall__ vr_play(const void *script);

#ifndef CALC_STOP
#define CALC_STOP 0xFFFE
#endif
#define AT(f, x, y) ((f) > CALC_STOP ? 0xFFFF : (f)), ((f) > CALC_STOP ? CALC_STOP : (x)), (y)
#define P(f, x, y, b) AT(f, x, ((y) & 255) | (((y) >> 8) << 14) | ((b) << 8))
#define K(f, c) AT(f, c, 0x8000)
#define END(f) 0xFFFF, ((f) > CALC_STOP ? CALC_STOP : (f)), 0

static const unsigned int script[] = {
#include "calc_script.h"
};

void calc_test_start(void)
{
    vr_play(script);
}

/* the emulator's cycle counter ($9FB8: a write resets it, a read of
   $9FB8 latches it, then $9FB9-$9FBB): "TIME <what> <cycles, hex>" */
void calc_test_clock_reset(void)
{
    *(volatile unsigned char *)0x9FB8 = 0;
}

void calc_test_clock_log(const char *what)
{
    static char line[32];
    static const char hex[] = "0123456789ABCDEF";
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
