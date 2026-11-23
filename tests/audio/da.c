/* tests/audio/da.c -- gate audio's accessory: started (DaRun) while the
   application plays; it logs VERA's IEN AFLOW bit and goes back. */
#include <veranda.h>
#define IEN (*(volatile unsigned char *)0x9F26)
int main(void)
{
    LogText((IEN & 8) ? "AUDDA AFLOW ON" : "AUDDA AFLOW OFF");
    RstrAppl();
    return 0;
}
