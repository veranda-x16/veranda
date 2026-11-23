/* gate font: the Font Editor's test build (apps/fonted built with
   FONTED_TEST and tests/sdk_play.s): fonted_test_start plays
   tests/fonted_script.h (tests/font_script.py); FONTED_STOP ends it at
   that frame with a dump (a screenshot). */
#include <veranda.h>

extern void __fastcall__ vr_play(const void *script);

#ifndef FONTED_STOP
#define FONTED_STOP 0xFFFE
#endif
#define AT(f, x, y) ((f) > FONTED_STOP ? 0xFFFF : (f)), ((f) > FONTED_STOP ? FONTED_STOP : (x)), (y)
#define P(f, x, y, b) AT(f, x, ((y) & 255) | (((y) >> 8) << 14) | ((b) << 8))
#define K(f, c) AT(f, c, 0x8000)
#define END(f) 0xFFFF, ((f) > FONTED_STOP ? FONTED_STOP : (f)), 0

static const unsigned int script[] = {
#include "fonted_script.h"
};

void fonted_test_start(void)
{
    vr_play(script);
}
