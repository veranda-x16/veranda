/* gate clip: the Photo Manager's and the Text Manager's test builds
   (apps/scrapman built with MAN_TEST and tests/sdk_play.s).
   man_test_start plays tests/photoman_script.h or textman_script.h from
   the accessory's own start; its end mark is never reached (the
   accessory ends with RstrAppl and the application's script goes on)
   unless MAN_STOP stops the session there with a dump (a screenshot). */
#include <veranda.h>

extern void __fastcall__ vr_play(const void *script);

#ifndef MAN_STOP
#define MAN_STOP 0xFFFE
#endif
#define AT(f, x, y) ((f) > MAN_STOP ? 0xFFFF : (f)), ((f) > MAN_STOP ? MAN_STOP : (x)), (y)
#define P(f, x, y, b) AT(f, x, ((y) & 255) | (((y) >> 8) << 14) | ((b) << 8))
#define K(f, c) AT(f, c, 0x8000)
#define END(f) 0xFFFF, ((f) > MAN_STOP ? MAN_STOP : (f)), 0

static const unsigned int script[] = {
#ifdef PHOTO
#include "photoman_script.h"
#else
#include "textman_script.h"
#endif
};

void man_test_start(void)
{
    vr_play(script);
}
