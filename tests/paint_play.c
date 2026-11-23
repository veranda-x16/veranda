/* gate paint: the test build's session (apps/paint built with PAINT_TEST
   and tests/sdk_play.s). paint_test_start plays the script;
   paint_test_snap writes the drawing area's rows to a host file. */
#include <veranda.h>
#include <string.h>
#include <scrap.h>

extern void __fastcall__ vr_play(const void *script);

/* tests/sdk_play.s's format: frame, x, y (low byte) | flags << 8 (bit 0
   the button, bit 6 y + 256, bit 7 a key: x is its code). PAINT_STOP: the
   session ends at that frame (the entries after it become the end mark). */
#ifndef PAINT_STOP
#define PAINT_STOP 0xFFFE
#endif
#define AT(f, x, y) ((f) > PAINT_STOP ? 0xFFFF : (f)), ((f) > PAINT_STOP ? PAINT_STOP : (x)), (y)
#define P(f, x, y, b) AT(f, x, ((y) & 255) | (((y) >> 8) << 14) | ((b) << 8))
#define K(f, c) AT(f, c, 0x8000)
#define END(f) 0xFFFF, ((f) > PAINT_STOP ? PAINT_STOP : (f)), 0

static const unsigned int script[] = {
#ifdef PAINT_DESK
#include "desk_script.h"
#elif defined(PAINT_DA)                 /* (gate da: the header's name, tests/da_script.py) */
#include "da_paint.h"            /* (-I: the session's folder) */
#elif defined(PAINT_INK)
#include "ink_script.h"
#elif defined(PAINT_PRINT)
#include "print_script.h"
#elif defined(PAINT_ARCHIVE)
#include "archive_paint_script.h"
#elif defined(PAINT_CLIP)
#include "clip_script.h"
#elif defined(PAINT_FONT)
#include "font_paint_script.h"
#else
#include "paint_script.h"
#endif
};

void paint_test_start(void)
{
    vr_play(script);
}

static unsigned char row[74];

void paint_test_snap(const char *name)
{
    unsigned char h, keep = dispBufferOn;
    unsigned int y;
    h = FOpen((void *)name, 'w');
    dispBufferOn = ST_WR_FORE;
    for (y = 16; y < 480; ++y) {
        ReadRow(row, 6, 74, y);
        FWrite(h, row, 74);
    }
    FClose(h);
    dispBufferOn = keep;
}

/* the drawing area's colour map (gate paint): 58 rows of 74 cards, a byte
   each (GetCardColor) */
void paint_test_snapmap(const char *name)
{
    unsigned char h, x, y;
    h = FOpen((void *)name, 'w');
    for (y = 2; y < 60; ++y) {
        for (x = 0; x < 74; ++x)
            row[x] = GetCardColor(6 + x, y);
        FWrite(h, row, 74);
    }
    FClose(h);
}

/* both screens, whole (gate desk): the foreground's 480 rows of 80 bytes,
   then the back screen's */
static unsigned char wrow[80];

void paint_test_snapall(const char *name)
{
    unsigned char h, s, keep = dispBufferOn;
    unsigned int y;
    h = FOpen((void *)name, 'w');
    for (s = 0; s < 2; ++s) {
        dispBufferOn = s ? ST_WR_BACK : ST_WR_FORE;
        for (y = 0; y < 480; ++y) {
            ReadRow(wrow, 0, 80, y);
            FWrite(h, wrow, 80);
        }
    }
    FClose(h);
    dispBufferOn = keep;
}

/* the emulator's cycle counter ($9FB8: a write resets it, a read of
   $9FB8 latches it, then $9FB9-$9FBB): "TIME <what> <cycles, hex>" */
void paint_test_clock_reset(void)
{
    *(volatile unsigned char *)0x9FB8 = 0;
}

void paint_test_clock_log(const char *what)
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

/* gate clip: "PAINT STAMP <kind> <16 hex digits>", the scrap's stamp */
void paint_test_stamp(unsigned char kind)
{
    static char line[32];
    static const char hex[] = "0123456789ABCDEF";
    unsigned char st[8], i;
    scrap_stamp(kind, st);
    memcpy(line, "PAINT STAMP 0 ", 14);
    line[12] = '0' + kind;
    for (i = 0; i < 8; ++i) {
        line[14 + 2 * i] = hex[st[i] >> 4];
        line[15 + 2 * i] = hex[st[i] & 15];
    }
    line[30] = 0;
    LogText(line);
}
