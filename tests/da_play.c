/* gate da: the native desk accessories' test builds (apps/dex,
   apps/calendar, apps/prefs built with their *_TEST define, DA_SCRIPT
   naming the script's header, and tests/sdk_play.s). da_test_start plays
   the script (tests/da_script.py writes them) from the accessory's own
   start; its end mark is never reached (the accessory ends with RstrAppl
   or starts Veranda Term, and the program's own script or test goes on)
   unless DA_STOP stops the session there with a dump (a screenshot). */
#include <veranda.h>

extern void __fastcall__ vr_play(const void *script);

#ifndef DA_STOP
#define DA_STOP 0xFFFE
#endif
#define AT(f, x, y) ((f) > DA_STOP ? 0xFFFF : (f)), ((f) > DA_STOP ? DA_STOP : (x)), (y)
#define P(f, x, y, b) AT(f, x, ((y) & 255) | (((y) >> 8) << 14) | ((b) << 8))
#define K(f, c) AT(f, c, 0x8000)
#define END(f) 0xFFFF, ((f) > DA_STOP ? DA_STOP : (f)), 0

static const unsigned int script[] = {
#include "da_script.h"           /* (-I: the session's folder) */
};

void da_test_start(void)
{
    vr_play(script);
}
