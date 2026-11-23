/* tests/audio/sndda.c -- gate sound's desk accessory (DECISIONS V69): it
   waits a quarter of a second (the emulator's cycle counter: SND_OPEN is
   heard), logs and goes back (SND_CLOSE). */
#include <veranda.h>
#define C0 (*(volatile unsigned char *)0x9FB8)
#define C2 (*(volatile unsigned char *)0x9FBA)
static unsigned char c;
int main(void)
{
    C0 = 0;                     /* (reset; reading C0 latches) */
    do {
        c = C0;
        c = C2;
    } while (c < 0x20);         /* 2 M cycles */
    LogText("SNDDA RAN");
    RstrAppl();
    return 0;
}
