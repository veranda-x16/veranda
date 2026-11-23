/* gate notepad: Note Pad's test build (apps/notepad built with NOTE_TEST
   and tests/sdk_play.s). note_test_start plays tests/note_script.h from
   the accessory's own start (NOTE_FIRST: the first session, else the
   second); its end mark is not reached (the accessory ends with
   RstrAppl, the application's script goes on) unless NOTE_STOP stops the
   session there with a dump (a screenshot). MIT licence (see LICENSE). */
#include <veranda.h>

extern void __fastcall__ vr_play(const void *script);

#ifndef NOTE_STOP
#define NOTE_STOP 0xFFFE
#endif
#define AT(f, x, y) ((f) > NOTE_STOP ? 0xFFFF : (f)), ((f) > NOTE_STOP ? NOTE_STOP : (x)), (y)
#define P(f, x, y, b) AT(f, x, ((y) & 255) | (((y) >> 8) << 14) | ((b) << 8))
#define K(f, c) AT(f, c, 0x8000)
#define END(f) 0xFFFF, ((f) > NOTE_STOP ? NOTE_STOP : (f)), 0

static const unsigned int script[] = {
#include "note_script.h"
};

void note_test_start(void)
{
    vr_play(script);
}
